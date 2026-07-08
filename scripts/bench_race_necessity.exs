defmodule RaceBench do
  @moduledoc """
  Does `SessionCustodian`'s per-record lock actually matter? A controlled
  comparison: run the exact send/receive race the custodian exists to
  prevent — an outbound `encrypt` and an inbound `decrypt` on the SAME 1:1
  session record, running concurrently — three ways:

    A. Unguarded (raw load -> cipher -> store, no lock), natural BEAM timing.
    B. Unguarded, with an artificial delay between load and store to
       deterministically force the two operations' windows to overlap. This
       does not manufacture a new bug class — the race window is always
       there — it just removes luck from observing it on a single run.
    C. Guarded — the same two operations, routed through the real
       `SessionCustodian.encrypt/5` and `.decrypt/6` (both calling into the
       SAME custodian pid), which serialize via its GenServer mailbox.

  Corruption is detected by an INDEPENDENT counterpart-side check, not by
  inspecting Amarula's internal record fields: a synthetic "Counterpart"
  tracks its OWN Signal session state entirely outside the race (never
  touched by either racing operation) and, after each round, tries to
  decrypt Us's actual emitted ciphertext with ITS real, untouched chain
  state. A lost update makes that fail with a real MAC verification error —
  the Double Ratchet math is the referee, not a guess about which internal
  field should have changed.

  Run: mix run scripts/bench_race_necessity.exs

  ## Scope

  This isolates the custodian's OWN locking specifically — it talks to
  `SessionCustodian` directly, not through a real `Connection` (which, being
  a single process, would incidentally serialize its own inbound decrypts
  anyway and confound the result — see the conversation this script came
  from). It does not exercise group sender-keys, migration, or multi-address
  contention — only the exact one-record two-writer race the custodian was
  built for.
  """

  alias Amarula.Protocol.Auth.AuthUtils
  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.Protocol.Messages.MessageEncoder
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.{SessionBuilder, SessionCipher, SessionCustodian, SessionRecord, SessionStore}
  alias Amarula.Protocol.Socket.ConnectionSupervisor

  def wire_key(<<5, _::binary-size(32)>> = k), do: k
  def wire_key(<<k::binary-size(32)>>), do: <<5>> <> k

  def device_bundle(creds) do
    %{
      registration_id: creds.registration_id,
      identity_key: wire_key(creds.signed_identity_key.public),
      signed_pre_key: %{
        key_id: creds.signed_pre_key.key_id,
        public: wire_key(creds.signed_pre_key.key_pair.public),
        signature: creds.signed_pre_key.signature
      }
    }
  end

  def counterpart_store do
    %{
      our_identity: Crypto.generate_key_pair(),
      our_registration_id: Crypto.generate_registration_id(),
      load_signed_pre_key: fn _id -> nil end,
      load_pre_key: fn _id -> nil end
    }
  end

  def encode(text), do: MessageEncoder.encode(%Proto.Message{conversation: text})

  def decode(plaintext) do
    <<pad>> = binary_part(plaintext, byte_size(plaintext) - 1, 1)
    unpadded = binary_part(plaintext, 0, byte_size(plaintext) - pad)
    Proto.Message.decode(unpadded).conversation
  end

  # --- the counterpart: real crypto, entirely outside the race -------------

  def counterpart_new(us_device) do
    store = counterpart_store()
    record = SessionRecord.new() |> SessionBuilder.init_outgoing(us_device, store)
    %{record: record, store: store}
  end

  def counterpart_encrypt(cp, text) do
    {:ok, type, ciphertext, record} = SessionCipher.encrypt(cp.record, encode(text), cp.store)
    {ciphertext, type, %{cp | record: record}}
  end

  # Independent check: does the counterpart's OWN untouched state agree that
  # `ciphertext` is a valid message from Us? Raises (MAC failure / no chain /
  # bad counter) on ANY lost update — that raise IS the corruption signal.
  def counterpart_verify(cp, ciphertext) do
    {:ok, plaintext, record} = SessionCipher.decrypt_whisper_message(cp.record, ciphertext, cp.store)
    {:ok, decode(plaintext), %{cp | record: record}}
  rescue
    e -> {:error, e}
  end

  # --- "Us" side: guarded vs unguarded --------------------------------------

  # Naive load -> cipher -> store, NO lock. `delay_ms` widens the window
  # between load and store to force two concurrent callers to overlap.
  # No lock, so a losing writer here can ALSO hit a storage-level failure (two
  # concurrent writers sharing Storage.File's one derived tmp-filename can
  # `rename` each other's file out from under them) — that's real fallout of
  # the same missing serialization, not a separate bug, so it's treated as a
  # corrupted round rather than crashing the run.
  def unguarded_encrypt(conn, addr, us_store, text, delay_ms, jitter_ms \\ 0) do
    if jitter_ms > 0, do: Process.sleep(:rand.uniform(jitter_ms))
    record = SessionStore.load_session(conn, addr)
    if delay_ms > 0, do: Process.sleep(delay_ms)
    {:ok, type, ciphertext, record} = SessionCipher.encrypt(record, encode(text), us_store)

    case SessionStore.store_session(conn, addr, record) do
      :ok -> {:ok, {ciphertext, type}}
      {:error, reason} -> {:error, reason}
    end
  end

  def unguarded_decrypt(conn, addr, us_store, ciphertext, delay_ms, jitter_ms \\ 0) do
    if jitter_ms > 0, do: Process.sleep(:rand.uniform(jitter_ms))
    record = SessionStore.load_session(conn, addr)
    if delay_ms > 0, do: Process.sleep(delay_ms)
    {:ok, plaintext, record} = SessionCipher.decrypt_whisper_message(record, ciphertext, us_store)

    case SessionStore.store_session(conn, addr, record) do
      :ok -> {:ok, decode(plaintext)}
      {:error, reason} -> {:error, reason}
    end
  end

  def guarded_encrypt(iid, conn, addr, us_store, text) do
    case SessionCustodian.encrypt(iid, conn, addr, encode(text), us_store) do
      {:ok, type, ciphertext} -> {:ok, {ciphertext, type}}
      {:error, reason} -> {:error, reason}
    end
  end

  def guarded_decrypt(iid, conn, addr, us_store, ciphertext) do
    case SessionCustodian.decrypt(iid, conn, addr, :msg, ciphertext, us_store) do
      {:ok, plaintext, _pre_key_id} -> {:ok, decode(plaintext)}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- one racing round: outbound encrypt vs inbound decrypt, concurrently -

  # `:sequential` runs the SAME unguarded (no-lock) functions with NO
  # concurrency at all — a control proving the harness/crypto setup isn't
  # just broken independent of racing. `{:unguarded_jitter, ms}` randomizes
  # each side's dispatch offset (0..ms) instead of launching both
  # perfectly back-to-back, so collision is probabilistic, not forced.
  def race_round(mode, ctx, round) do
    cp = ctx.counterpart
    {in_ciphertext, _type, cp} = counterpart_encrypt(cp, "inbound #{round}")

    {encrypt_result, decrypt_result} =
      case mode do
        :sequential ->
          e = unguarded_encrypt(ctx.conn, ctx.addr, ctx.us_store, "outbound #{round}", 0)
          d = unguarded_decrypt(ctx.conn, ctx.addr, ctx.us_store, in_ciphertext, 0)
          {e, d}

        _ ->
          encrypt_task =
            Task.async(fn ->
              case mode do
                :guarded ->
                  guarded_encrypt(ctx.iid, ctx.conn, ctx.addr, ctx.us_store, "outbound #{round}")

                {:unguarded, delay} ->
                  unguarded_encrypt(ctx.conn, ctx.addr, ctx.us_store, "outbound #{round}", delay)

                {:unguarded_jitter, jitter} ->
                  unguarded_encrypt(ctx.conn, ctx.addr, ctx.us_store, "outbound #{round}", 0, jitter)
              end
            end)

          decrypt_task =
            Task.async(fn ->
              case mode do
                :guarded ->
                  guarded_decrypt(ctx.iid, ctx.conn, ctx.addr, ctx.us_store, in_ciphertext)

                {:unguarded, delay} ->
                  unguarded_decrypt(ctx.conn, ctx.addr, ctx.us_store, in_ciphertext, delay)

                {:unguarded_jitter, jitter} ->
                  unguarded_decrypt(ctx.conn, ctx.addr, ctx.us_store, in_ciphertext, 0, jitter)
              end
            end)

          {Task.await(encrypt_task, 5_000), Task.await(decrypt_task, 5_000)}
      end

    recv_ok = match?({:ok, "inbound " <> _}, decrypt_result) and elem(decrypt_result, 1) == "inbound #{round}"
    # A LOUD failure: either side got an explicit {:error, _} back (e.g. the
    # storage write itself failed) — the caller at least knows something broke.
    loud = match?({:error, _}, encrypt_result) or match?({:error, _}, decrypt_result)

    case encrypt_result do
      {:ok, {out_ciphertext, _out_type}} ->
        case counterpart_verify(cp, out_ciphertext) do
          {:ok, text, cp} ->
            ok = recv_ok and text == "outbound #{round}"
            # SILENT: both writers reported :ok, no error anywhere, yet the
            # state was actually clobbered — only the counterpart's
            # independent, out-of-band check caught it.
            {classify(ok, loud), %{ctx | counterpart: cp}}

          {:error, _} ->
            {classify(false, loud), %{ctx | counterpart: cp}}
        end

      {:error, _} ->
        {classify(false, loud), %{ctx | counterpart: cp}}
    end
  end

  defp classify(true, _loud), do: :ok
  defp classify(false, true), do: :loud_failure
  defp classify(false, false), do: :silent_corruption

  def run(mode, ctx, rounds) do
    Enum.reduce(1..rounds, {%{ok: 0, loud_failure: 0, silent_corruption: 0}, ctx}, fn round, {tally, ctx} ->
      {outcome, ctx} = race_round(mode, ctx, round)
      {Map.update!(tally, outcome, &(&1 + 1)), ctx}
    end)
  end

  # Fresh "Us" session + custodian address, established via a real round-trip
  # handshake (so both racing operations start from a real, open session).
  def new_context(iid, conn, us_device, us_store, addr) do
    cp = counterpart_new(us_device)
    {pk_ciphertext, :pkmsg, cp} = counterpart_encrypt(cp, "hello")
    {:ok, plaintext, _} = SessionCustodian.decrypt(iid, conn, addr, :pkmsg, pk_ciphertext, us_store)
    "hello" = decode(plaintext)
    {:ok, :msg, reply_ciphertext} = SessionCustodian.encrypt(iid, conn, addr, encode("hi"), us_store)
    {:ok, "hi", cp} = counterpart_verify(cp, reply_ciphertext)
    %{iid: iid, conn: conn, addr: addr, us_store: us_store, counterpart: cp}
  end
end

alias Amarula.Protocol.Auth.AuthUtils
alias Amarula.Protocol.Signal.{SessionCustodian, SessionStore}
alias Amarula.Protocol.Socket.ConnectionSupervisor

IO.puts("\n== Amarula race-necessity benchmark (mix run scripts/bench_race_necessity.exs) ==\n")

{:ok, _sup} = Amarula.Supervisor.start_link()

dir = Path.join(System.tmp_dir!(), "amarula_race_bench_#{System.unique_integer([:positive])}")

conn =
  %{profile: :race_bench, storage: {Amarula.Storage.File, root: dir}}
  |> Amarula.Config.merge()
  |> Amarula.Conn.new()

iid = make_ref()

{:ok, _custodian_sup} =
  DynamicSupervisor.start_link(
    strategy: :one_for_one,
    name: ConnectionSupervisor.name(iid, :custodian_supervisor)
  )

us_creds = AuthUtils.init_auth_creds()
us_device = RaceBench.device_bundle(us_creds)
us_store = SessionStore.build(us_creds)

report = fn tally, total ->
  IO.puts(
    "   #{tally.ok}/#{total} correct — #{tally.loud_failure} loud failure(s) " <>
      "(explicit storage/write error), #{tally.silent_corruption} SILENT corruption(s) " <>
      "(no error anywhere, state just wrong)\n"
  )
end

# --- Condition Z: unguarded, SEQUENTIAL (no concurrency at all) — control --
# Proves the harness itself isn't just broken: same no-lock code path, same
# session, same everything — but encrypt and decrypt never overlap in time.
IO.puts("Z. unguarded, SEQUENTIAL — no race at all (control, 100 rounds)")
ctx_z = RaceBench.new_context(iid, conn, us_device, us_store, "cp_z.0")
{tally_z, _} = RaceBench.run(:sequential, ctx_z, 100)
report.(tally_z, 100)

# --- Condition A: unguarded, natural timing --------------------------------
IO.puts("A. unguarded, natural BEAM scheduling (100 rounds)")
ctx_a = RaceBench.new_context(iid, conn, us_device, us_store, "cp_a.0")
{tally_a, _} = RaceBench.run({:unguarded, 0}, ctx_a, 100)
report.(tally_a, 100)

# --- Condition A2: unguarded, RANDOM jitter (not perfectly synchronized) --
# Does forced back-to-back Task.async dispatch overstate how often this
# actually collides? Each side starts at a random offset within 0..10ms
# instead of launching in the same instant.
IO.puts("A2. unguarded, random 0-10ms dispatch jitter — not forced synchrony (100 rounds)")
ctx_a2 = RaceBench.new_context(iid, conn, us_device, us_store, "cp_a2.0")
{tally_a2, _} = RaceBench.run({:unguarded_jitter, 10}, ctx_a2, 100)
report.(tally_a2, 100)

# --- Condition B: unguarded, forced overlap --------------------------------
IO.puts("B. unguarded, forced overlap (5ms delay between load and store, 20 rounds)")
ctx_b = RaceBench.new_context(iid, conn, us_device, us_store, "cp_b.0")
{tally_b, _} = RaceBench.run({:unguarded, 5}, ctx_b, 20)
report.(tally_b, 20)

# --- Condition C: guarded, through SessionCustodian ------------------------
IO.puts("C. guarded — through SessionCustodian.encrypt/decrypt (100 rounds)")
ctx_c = RaceBench.new_context(iid, conn, us_device, us_store, "cp_c.0")
{tally_c, _} = RaceBench.run(:guarded, ctx_c, 100)
report.(tally_c, 100)

IO.puts("== done ==\n")
