defmodule FloodBench do
  @moduledoc """
  Load benchmark: flood ONE real `Connection` with real, Signal-encrypted
  inbound messages from many distinct synthetic counterparts, and measure
  memory/mailbox/throughput under that load.

  Run: mix run scripts/bench_flood_receive.exs

  ## What's real, what's faked

  Real: the `Connection` GenServer (via `Amarula.Testing.start_offline/1` — no
  websocket, no Noise, but everything after that is the genuine receive
  pipeline), every `SessionCustodian` it spins up (one per fake counterpart),
  every Signal session (`SessionBuilder.init_outgoing`), every ciphertext
  (`SessionCipher.encrypt`, real ratchet-stepping), and the real
  `MessageDecryptor`/`Router` node handling.

  Faked: there is no real WhatsApp server and no real second Amarula instance —
  each "counterpart" is a throwaway identity keypair used purely to originate a
  real Signal session TOWARD "Us"'s real published identity/prekeys (the same
  X3DH math a real client would run), with no network round-trip. This is
  deliberately narrower than a full two-instance/two-socket setup — see the
  conversation this script came from for why that's not achievable (Amarula
  only implements the Noise CLIENT role; two client instances can't complete a
  mutual handshake with each other).

  ## Scope

  This measures real crypto load on ONE Connection's inbound routing + the
  SessionCustodian fan-out behind it. It does NOT measure outbound send load,
  real network conditions, or sustained multi-hour growth — see the moduledoc
  in `bench_registry_memory.exs` for the same caveat pattern.
  """

  alias Amarula.Protocol.Auth.AuthUtils
  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Messages.MessageEncoder
  alias Amarula.Protocol.Signal.{SessionBuilder, SessionCipher, SessionRecord}

  def kb(bytes), do: Float.round(bytes / 1024, 1)

  def mem do
    :erlang.garbage_collect()
    %{total_kb: kb(:erlang.memory(:total)), processes_kb: kb(:erlang.memory(:processes))}
  end

  # 33-byte 0x05-prefixed wire form, exactly Amarula.Protocol.Signal.SessionInjector.wire_key/1.
  def wire_key(<<5, _::binary-size(32)>> = k), do: k
  def wire_key(<<k::binary-size(32)>>), do: <<5>> <> k

  # "Us"'s real published device bundle, built directly from real creds — no IQ,
  # no server, exactly the shape SessionInjector.parse_bundle/1 produces on the
  # wire, just skipping the wire encode/decode round-trip.
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

  # A throwaway counterpart identity: just enough of the SessionStore.build/1
  # shape for SessionBuilder.init_outgoing (uses our_identity for X3DH) and
  # SessionCipher.encrypt (never looks up our own prekeys — it only steps the
  # already-established ratchet) to work as a pure session-originator.
  def counterpart_store do
    identity = Crypto.generate_key_pair()

    %{
      our_identity: identity,
      # Required — the pkmsg wire message's registration_id field is a mandatory
      # varint; nil breaks encoding (SessionCipher.encrypt only needs this for
      # the FIRST message of a session, when it's still a pkmsg).
      our_registration_id: Crypto.generate_registration_id(),
      load_signed_pre_key: fn _id -> nil end,
      load_pre_key: fn _id -> nil end
    }
  end

  # Build a real session toward `device`, real-encrypt `text`, return {ciphertext, type, record}.
  def encrypt_first(device, store, text) do
    plaintext = MessageEncoder.encode(%Proto.Message{conversation: text})
    record = SessionRecord.new() |> SessionBuilder.init_outgoing(device, store)
    {:ok, type, ciphertext, record} = SessionCipher.encrypt(record, plaintext, store)
    {ciphertext, type, record}
  end

  def encrypt_next(record, store, text) do
    plaintext = MessageEncoder.encode(%Proto.Message{conversation: text})
    {:ok, type, ciphertext, record} = SessionCipher.encrypt(record, plaintext, store)
    {ciphertext, type, record}
  end

  def message_node(from, id, type, ciphertext) do
    enc = Node.create("enc", %{"type" => Atom.to_string(type), "v" => "2"}, ciphertext)
    Node.create("message", %{"from" => from, "id" => id, "t" => "1700000000"}, [enc])
  end

  def drain_sink do
    receive do
      {:frame_out, _node} -> drain_sink()
    end
  end

  # Count {:amarula, :messages_upsert, _} events until traffic goes quiet for
  # `timeout_ms`, tracking the timestamp of the LAST one seen — that timestamp,
  # not "how long we waited," is the real signal for when processing finished.
  def count_events(count \\ 0, last_at \\ nil, timeout_ms \\ 3_000) do
    receive do
      {:amarula, :messages_upsert, _} ->
        count_events(count + 1, System.monotonic_time(:millisecond), timeout_ms)

      {:amarula, _other, _} ->
        count_events(count, last_at, timeout_ms)
    after
      timeout_ms -> {count, last_at}
    end
  end
end

alias Amarula.Protocol.Auth.AuthUtils

{:ok, _sup} = Amarula.Supervisor.start_link()

n_counterparts = 100
n_followups = 10

IO.puts("\n== Amarula flood-receive benchmark (mix run scripts/bench_flood_receive.exs) ==")
IO.puts("#{n_counterparts} counterparts, #{n_followups} follow-ups each " <>
  "(#{n_counterparts + n_counterparts * n_followups} messages total)\n")

# --- boot "Us" -------------------------------------------------------------
creds =
  AuthUtils.init_auth_creds()
  |> Map.put(:me, %{id: "20000000000@s.whatsapp.net", lid: nil, name: "Bench Us"})

sink = spawn(&FloodBench.drain_sink/0)

{:ok, conn} =
  Amarula.Testing.start_offline(
    profile: :bench_flood_receive,
    auth: creds,
    frame_sink: sink,
    parent_pid: self()
  )

device = FloodBench.device_bundle(creds)
mem0 = FloodBench.mem()
IO.puts("boot: total=#{mem0.total_kb} KB processes=#{mem0.processes_kb} KB\n")

# --- wave 1: first contact from N distinct counterparts (real pkmsg each) --
IO.puts("wave 1 — #{n_counterparts} distinct counterparts, first contact (pkmsg)")

t0 = System.monotonic_time(:millisecond)

records =
  for i <- 1..n_counterparts, into: %{} do
    from = "19000000#{String.pad_leading(Integer.to_string(i), 4, "0")}@s.whatsapp.net"
    store = FloodBench.counterpart_store()
    {ciphertext, type, record} = FloodBench.encrypt_first(device, store, "flood #{i}")
    node = FloodBench.message_node(from, "bench-#{i}-0", type, ciphertext)
    send(conn, {:inject_node, node})
    {i, %{from: from, store: store, record: record}}
  end

t1 = System.monotonic_time(:millisecond)
# Sample the mailbox FIRST, before count_events/2 blocks until it's quiet —
# reading it after the drain would always show 0 by construction.
mailbox1 = Process.info(conn, :message_queue_len)
mem1 = FloodBench.mem()
{received1, last_at1} = FloodBench.count_events()
processing_ms1 = if last_at1, do: last_at1 - t1, else: 0

IO.puts(
  "  injected #{n_counterparts} in #{t1 - t0} ms, " <>
    "#{received1}/#{n_counterparts} decrypted+delivered, " <>
    "last one landed #{processing_ms1} ms after injection finished " <>
    "(#{Float.round(n_counterparts / max(processing_ms1, 1) * 1000, 1)} msg/s real processing rate)"
)

IO.puts("  memory: total=#{mem1.total_kb} KB (Δ#{Float.round(mem1.total_kb - mem0.total_kb, 1)}) " <>
  "processes=#{mem1.processes_kb} KB (Δ#{Float.round(mem1.processes_kb - mem0.processes_kb, 1)})")

IO.puts("  Connection mailbox length immediately after injection (before draining): #{inspect(mailbox1)}\n")

# --- wave 2: sustained follow-ups across all N established sessions --------
IO.puts("wave 2 — #{n_followups} follow-ups (real :msg) across all #{n_counterparts} sessions")

t2 = System.monotonic_time(:millisecond)

_final_records =
  Enum.reduce(1..n_followups, records, fn round, acc ->
    Enum.reduce(acc, %{}, fn {i, %{from: from, store: store, record: record}}, updated ->
      {ciphertext, type, record} = FloodBench.encrypt_next(record, store, "flood #{i}-#{round}")
      node = FloodBench.message_node(from, "bench-#{i}-#{round}", type, ciphertext)
      send(conn, {:inject_node, node})
      Map.put(updated, i, %{from: from, store: store, record: record})
    end)
  end)

t3 = System.monotonic_time(:millisecond)
mailbox2 = Process.info(conn, :message_queue_len)
mem2 = FloodBench.mem()
{received2, last_at2} = FloodBench.count_events()
processing_ms2 = if last_at2, do: last_at2 - t3, else: 0

total_followups = n_counterparts * n_followups

IO.puts(
  "  injected #{total_followups} in #{t3 - t2} ms, " <>
    "#{received2}/#{total_followups} decrypted+delivered, " <>
    "last one landed #{processing_ms2} ms after injection finished " <>
    "(#{Float.round(total_followups / max(processing_ms2, 1) * 1000, 1)} msg/s real processing rate)"
)

IO.puts("  memory: total=#{mem2.total_kb} KB (Δ#{Float.round(mem2.total_kb - mem1.total_kb, 1)} vs wave 1) " <>
  "processes=#{mem2.processes_kb} KB (Δ#{Float.round(mem2.processes_kb - mem1.processes_kb, 1)} vs wave 1)")

IO.puts("  Connection mailbox length immediately after injection (before draining): #{inspect(mailbox2)}\n")

per_message_kb =
  if total_followups > 0, do: Float.round((mem2.total_kb - mem1.total_kb) / total_followups, 3), else: 0.0

IO.puts(
  "  => #{n_counterparts} live sessions, #{n_counterparts + total_followups} real decrypt cycles total, " <>
    "~#{per_message_kb} KB/message steady-state growth\n"
)

Amarula.stop(conn)
IO.puts("== done ==\n")
