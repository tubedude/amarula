defmodule Amarula.Protocol.Signal.SessionCustodian do
  @moduledoc """
  The single serialization point for **one** Signal crypto record — a 1:1 session
  (`for_address/3`) or a group sender-key (`for_sender_key/3`).

  A record is persisted as one opaque blob (a whole-record overwrite, no field-level
  merge). A 1:1 session is mutated from two different processes — the per-recipient
  `ConversationSender` (encrypt, on send) and the `Connection` (decrypt/migrate/wipe,
  on receive) — so two non-atomic `load → modify → store` cycles on the same blob can
  lose an update. A custodian is a per-record lock: every read-modify-write of that
  record funnels through this one process, so send and receive can no longer clobber
  each other. (Group sender-key records have a single writer today; routing them
  through a custodian too keeps one uniform rule — no process touches a record except
  its custodian — and pre-empts a future second writer.)

  ## The leaf invariant (what makes this deadlock-free)

  A custodian **touches only `Amarula.Storage` and the pure cipher/builder — it
  calls nobody**: no IQ, no socket, no callback into `Connection` or a sender, no
  `GenServer.call` other than into the storage adapter. That leaf property is the
  whole point: the `ConversationSender` already blocks on `Connection` (USync /
  prekey-bundle / relay calls), so a `Connection → sender` blocking call would
  deadlock. `Connection → custodian` and `sender → custodian` are safe *because the
  custodian waits on no one* — it always makes progress and replies.

  Two rules keep that true:

    * **The custodian does the mutation itself** — the ops are `encrypt/decrypt/…`
      that run `load → cipher → store` internally. It never hands the record out
      for a caller to mutate and return.
    * **The bundle fetch stays outside** — a prekey-bundle fetch needs the socket,
      so it can't live in the critical section. First-contact session *creation*
      therefore straddles the lock: the caller fetches outside, then hands the
      parsed bundle back for `inject/4` (`:if_absent` re-checks whether an inbound
      pkmsg established a session while it was fetching).

  ## Creds are passed per call, not held

  The cipher `store` map (`SessionStore.build/1`) is built from the auth creds,
  which mutate after login (consumed one-time prekeys, etc.). The custodian holds
  only the static `%Amarula.Conn{}` (profile + storage scope); every op takes the
  freshly-built `store` from the caller.

  The 1:1 session record is held in memory as a **write-through cache** — loaded
  once, kept coherent because the custodian is its sole writer, and persisted on
  every mutation. Never write-back: an idle-stop or crash must not lose a ratchet
  advance, so storage is always current. (Group sender-key ops aren't cached — the
  group cipher does its own storage I/O.)
  """

  use GenServer, restart: :temporary

  alias Amarula.Conn
  alias Amarula.Protocol.Signal.{SessionBuilder, SessionCipher, SessionRecord, SessionStore}

  alias Amarula.Protocol.Signal.Group.{
    GroupCipher,
    GroupSessionBuilder,
    SenderKeyName,
    SenderKeyStore
  }

  alias Amarula.Protocol.Socket.ConnectionSupervisor
  alias Amarula.Storage

  @call_timeout 15_000
  @idle_timeout_ms 30_000

  @type t :: GenServer.server()
  @type store :: map()

  # --- client API ---

  @doc """
  Find — or lazily start — the custodian for record `addr` on `conn`, registered in
  the app-level registry under `{instance_id, {:session, addr}}` so every caller
  (Connection and any sender) converges on the ONE custodian for that record. An
  unregistered custodian would serialize nothing.
  """
  @spec for_address(reference(), Conn.t(), String.t()) :: {:ok, pid()} | {:error, term()}
  def for_address(instance_id, conn, addr) do
    registry = ConnectionSupervisor.registry_name(instance_id)
    key = {instance_id, {:session, addr}}

    case Registry.lookup(registry, key) do
      [{pid, _}] -> {:ok, pid}
      [] -> start_custodian(instance_id, conn, addr, {:via, Registry, {registry, key}})
    end
  end

  @doc """
  Find — or lazily start — the custodian for a group **sender-key** record, keyed
  under `{instance_id, {:sender_key, <name>}}`. Same per-record lock as `for_address/3`,
  for the group cipher instead of the 1:1 session.
  """
  @spec for_sender_key(reference(), Conn.t(), SenderKeyName.t()) ::
          {:ok, pid()} | {:error, term()}
  def for_sender_key(instance_id, conn, sender_key_name) do
    registry = ConnectionSupervisor.registry_name(instance_id)
    key = {instance_id, {:sender_key, SenderKeyName.to_string_repr(sender_key_name)}}

    case Registry.lookup(registry, key) do
      [{pid, _}] -> {:ok, pid}
      # state.key is the SenderKeyName itself (the group ops need it), not the
      # registry tuple — a 1:1 op invoked here would then misfile under a struct key.
      [] -> start_custodian(instance_id, conn, sender_key_name, {:via, Registry, {registry, key}})
    end
  end

  # A lost start race (:already_started) is success — reuse the live custodian.
  defp start_custodian(instance_id, conn, key, via) do
    spec = {__MODULE__, conn: conn, key: key, name: via, idle_ms: idle_ms(conn)}
    supervisor = ConnectionSupervisor.name(instance_id, :custodian_supervisor)

    case DynamicSupervisor.start_child(supervisor, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      :ignore -> {:error, :custodian_start_ignored}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    state = %{
      conn: Keyword.fetch!(opts, :conn),
      key: Keyword.fetch!(opts, :key),
      idle_ms: Keyword.get(opts, :idle_ms, @idle_timeout_ms)
    }

    GenServer.start_link(__MODULE__, state, Keyword.take(opts, [:name]))
  end

  # Idle linger before the process is shed; overridable per connection via
  # `config[:custodian_idle_ms]`. An idle-stop or crash loses nothing (write-through).
  defp idle_ms(%{config: %{custodian_idle_ms: ms}}) when is_integer(ms) and ms >= 0, do: ms
  defp idle_ms(_conn), do: @idle_timeout_ms

  # --- ops ---
  #
  # Each op resolves the record's custodian and calls it, so the caller never holds
  # a pid across the idle-shed window. `resolve_call/3` retries through find-or-start
  # if the custodian died between resolve and call — a bare call to a mid-:stop pid
  # would exit the CALLER, and on the receive path that caller is `Connection`, the
  # socket owner. The leaf property makes the retry safe: a fresh custodian re-reads
  # storage, which is current (write-through). We retry a few times with a 1ms yield
  # because `Registry` evicts a dead pid asynchronously — until it processes the
  # `:DOWN`, `for_address` keeps handing back the SAME dead pid, so an instant retry
  # would just re-hit it; the yield lets the eviction land, then a fresh start wins.

  @doc """
  Encrypt `plaintext` against 1:1 session `addr`, advancing the sending chain.
  `{:ok, :pkmsg | :msg, ciphertext}` or `{:error, reason}`.
  """
  @spec encrypt(reference(), Conn.t(), String.t(), binary(), store()) ::
          {:ok, :pkmsg | :msg, binary()} | {:error, term()}
  def encrypt(instance_id, conn, addr, plaintext, store),
    do: call_session(instance_id, conn, addr, {:encrypt, plaintext, store})

  @doc """
  Decrypt a `:pkmsg`/`:msg` against 1:1 session `addr`. `{:ok, plaintext,
  used_pre_key_id | nil}` or `{:error, reason}` (the reason preserves the cipher
  exception — the receive path inspects it for the consumed-key duplicate signal).
  """
  @spec decrypt(reference(), Conn.t(), String.t(), :pkmsg | :msg, binary(), store()) ::
          {:ok, binary(), non_neg_integer() | nil} | {:error, term()}
  def decrypt(instance_id, conn, addr, type, content, store) when type in [:pkmsg, :msg],
    do: call_session(instance_id, conn, addr, {:decrypt, type, content, store})

  @doc """
  Build an outgoing session for `addr` from a parsed prekey-bundle `device`.
  `:if_absent` skips when a session already exists (first-contact recheck);
  `:always` re-initialises. `:ok`, `{:skipped, :session_exists}`, or `{:error, _}`.
  """
  @spec inject(reference(), Conn.t(), String.t(), map(), store(), :always | :if_absent) ::
          :ok | {:skipped, :session_exists} | {:error, term()}
  def inject(instance_id, conn, addr, device, store, mode) when mode in [:always, :if_absent],
    do: call_session(instance_id, conn, addr, {:inject, device, store, mode})

  @doc "Read 1:1 record `addr` (`{:ok, record | nil}` | `{:error, _}`) — migration source read."
  @spec record(reference(), Conn.t(), String.t()) :: {:ok, map() | nil} | {:error, term()}
  def record(instance_id, conn, addr),
    do: call_session(instance_id, conn, addr, :record)

  @doc """
  Replace 1:1 record `addr`: write `record`, or **delete** when `record` is `nil`.
  `:ok` or `{:error, reason}`. Used by the PN→LID migration and the identity wipe.
  """
  @spec replace(reference(), Conn.t(), String.t(), map() | nil) :: :ok | {:error, term()}
  def replace(instance_id, conn, addr, record),
    do: call_session(instance_id, conn, addr, {:replace, record})

  @doc "Group: encrypt `plaintext` with our sender key for `name` (skmsg)."
  @spec group_encrypt(reference(), Conn.t(), SenderKeyName.t(), binary()) ::
          {:ok, binary()} | {:error, term()}
  def group_encrypt(instance_id, conn, name, plaintext),
    do: call_sender_key(instance_id, conn, name, {:group_encrypt, plaintext})

  @doc "Group: decrypt a peer's skmsg with their sender key `name`."
  @spec group_decrypt(reference(), Conn.t(), SenderKeyName.t(), binary()) ::
          {:ok, binary()} | {:error, term()}
  def group_decrypt(instance_id, conn, name, content),
    do: call_sender_key(instance_id, conn, name, {:group_decrypt, content})

  @doc "Group: build our sender-key-distribution message for `group_id` (custodian `name`)."
  @spec create_skdm(reference(), Conn.t(), SenderKeyName.t(), String.t(), String.t()) ::
          {:ok, struct()} | {:error, term()}
  def create_skdm(instance_id, conn, name, group_id, me_id),
    do: call_sender_key(instance_id, conn, name, {:create_skdm, group_id, me_id})

  @doc "Group: process a peer's inbound SKDM (custodian `name`), storing their sender key."
  @spec process_skdm(reference(), Conn.t(), SenderKeyName.t(), struct(), String.t()) ::
          :ok | {:error, term()}
  def process_skdm(instance_id, conn, name, skdm, author),
    do: call_sender_key(instance_id, conn, name, {:process_skdm, skdm, author})

  defp call_session(instance_id, conn, addr, request),
    do: resolve_call(fn -> for_address(instance_id, conn, addr) end, request)

  defp call_sender_key(instance_id, conn, name, request),
    do: resolve_call(fn -> for_sender_key(instance_id, conn, name) end, request)

  @resolve_tries 5

  defp resolve_call(resolve, request, tries \\ @resolve_tries) do
    case resolve.() do
      {:ok, pid} ->
        try do
          GenServer.call(pid, request, @call_timeout)
        catch
          :exit, {reason, _} when reason in [:noproc, :normal, :shutdown] and tries > 1 ->
            # Let Registry evict the dead pid before re-resolving, else we re-hit it.
            Process.sleep(1)
            resolve_call(resolve, request, tries - 1)

          :exit, {reason, _} when reason in [:noproc, :normal, :shutdown] ->
            {:error, :custodian_down}
        end

      {:error, _} = err ->
        err
    end
  end

  # --- server ---

  @impl GenServer
  # `cached` holds the 1:1 session record in memory (write-through): loaded once on
  # first access, kept coherent because the custodian is the record's sole writer.
  # `:unloaded` distinguishes "not read yet" from a loaded-nil (no record).
  def init(state), do: {:ok, Map.put(state, :cached, :unloaded), state.idle_ms}

  @impl GenServer
  def handle_call({:encrypt, plaintext, store}, _from, state) do
    {record, state} = cached_record(state)

    {reply, state} =
      case record do
        nil ->
          {{:error, :no_session}, state}

        record ->
          mutate(state, fn ->
            {:ok, type, ciphertext, record} = SessionCipher.encrypt(record, plaintext, store)
            {record, {:ok, type, ciphertext}}
          end)
      end

    {:reply, reply, state, state.idle_ms}
  end

  @impl GenServer
  def handle_call({:decrypt, type, content, store}, _from, state) do
    {record, state} = cached_record(state)

    {reply, state} =
      case {type, record} do
        # A pkmsg can establish a session, so a nil record is valid input.
        {:pkmsg, record} ->
          mutate(state, fn ->
            {:ok, plaintext, record, pre_key_id} =
              SessionCipher.decrypt_pre_key_whisper_message(record, content, store)

            {record, {:ok, plaintext, pre_key_id}}
          end)

        {:msg, nil} ->
          {{:error, :no_session}, state}

        {:msg, record} ->
          mutate(state, fn ->
            {:ok, plaintext, record} =
              SessionCipher.decrypt_whisper_message(record, content, store)

            {record, {:ok, plaintext, nil}}
          end)
      end

    {:reply, reply, state, state.idle_ms}
  end

  @impl GenServer
  def handle_call({:inject, device, store, mode}, _from, state) do
    {record, state} = cached_record(state)
    record = record || SessionRecord.new()

    {reply, state} =
      if mode == :if_absent and SessionRecord.get_open_session(record) != nil do
        {{:skipped, :session_exists}, state}
      else
        mutate(state, fn -> {SessionBuilder.init_outgoing(record, device, store), :ok} end)
      end

    {:reply, reply, state, state.idle_ms}
  end

  @impl GenServer
  def handle_call(:record, _from, state) do
    {record, state} = cached_record(state)
    {:reply, {:ok, record}, state, state.idle_ms}
  end

  @impl GenServer
  def handle_call({:replace, nil}, _from, %{conn: conn, key: key} = state) do
    delete_record(conn, key)
    {:reply, :ok, %{state | cached: nil}, state.idle_ms}
  end

  @impl GenServer
  def handle_call({:replace, record}, _from, state) do
    case store_and_cache(state, record) do
      {:ok, state} -> {:reply, :ok, state, state.idle_ms}
      {:error, reason} -> {:reply, {:error, reason}, state, state.idle_ms}
    end
  end

  @impl GenServer
  def handle_call({:group_encrypt, plaintext}, _from, %{conn: conn, key: name} = state) do
    {:reply, GroupCipher.encrypt(SenderKeyStore.build(conn), name, plaintext), state, state.idle_ms}
  end

  @impl GenServer
  def handle_call({:group_decrypt, content}, _from, %{conn: conn, key: name} = state) do
    {:reply, GroupCipher.decrypt(SenderKeyStore.build(conn), name, content), state, state.idle_ms}
  end

  @impl GenServer
  def handle_call({:create_skdm, group_id, me_id}, _from, %{conn: conn} = state) do
    sk_store = SenderKeyStore.build(conn)
    builder = GroupSessionBuilder.new(sk_store)

    reply =
      GroupSessionBuilder.create_sender_key_distribution_message(
        builder,
        sk_store,
        group_id,
        me_id
      )

    {:reply, reply, state, state.idle_ms}
  end

  @impl GenServer
  def handle_call({:process_skdm, skdm, author}, _from, %{conn: conn} = state) do
    sk_store = SenderKeyStore.build(conn)
    builder = GroupSessionBuilder.new(sk_store)

    reply =
      GroupSessionBuilder.process_sender_key_distribution_message(builder, sk_store, skdm, author)

    {:reply, reply, state, state.idle_ms}
  end

  # Idle long enough → shed the process. Write-through means there's nothing to
  # flush; the next op for this record re-starts a fresh custodian via for_address/3.
  @impl GenServer
  def handle_info(:timeout, state), do: {:stop, :normal, state}

  # --- internals ---

  # The record from the in-memory cache, loading it once on first access.
  defp cached_record(%{cached: :unloaded, conn: conn, key: key} = state) do
    record = SessionStore.load_session(conn, key)
    {record, %{state | cached: record}}
  end

  defp cached_record(%{cached: record} = state), do: {record, state}

  # Run a cipher `fun` that returns `{new_record, reply}` (or raises). On success,
  # persist the new record write-through and refresh the cache. A cipher raise
  # (incl. the trial-decrypt's re-raised DecryptError the receive path inspects) is
  # caught into `{:error, exception}` so it fails only this op — a crash would
  # `:exit` every queued caller — and leaves the cache/storage untouched.
  defp mutate(state, fun) do
    result =
      try do
        {:ok, fun.()}
      rescue
        e -> {:error, e}
      end

    case result do
      # The cipher advanced the record; only surface success (and cache it) if the
      # write LANDED. A failed write returns the error with the cache/storage
      # UNCHANGED — the advance is discarded (no message consumed it: an outbound
      # send fails, an inbound decrypt returns an error → redelivery retries).
      {:ok, {new_record, reply}} ->
        case store_and_cache(state, new_record) do
          {:ok, state} -> {reply, state}
          {:error, _} = err -> {err, state}
        end

      {:error, e} ->
        {{:error, e}, state}
    end
  end

  # Write-through: persist, then cache exactly what was stored so cache == storage.
  # `store_session` prunes closed sessions past the cap; cache the pruned form.
  defp store_and_cache(%{conn: conn, key: key} = state, record) do
    pruned = SessionRecord.remove_old_sessions(record)

    case SessionStore.store_session(conn, key, pruned) do
      :ok -> {:ok, %{state | cached: pruned}}
      {:error, reason} -> {:error, {:storage_write_failed, reason}}
    end
  end

  defp delete_record(%Conn{storage: scope, profile: profile}, key) do
    Storage.delete(scope, profile, :session, key)
  end
end
