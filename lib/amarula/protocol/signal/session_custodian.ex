defmodule Amarula.Protocol.Signal.SessionCustodian do
  @moduledoc """
  The single serialization point for **one** Signal session record.

  A peer's session record holds both directions of the Double Ratchet and is
  persisted as one opaque blob (a whole-record overwrite, no field-level merge). It
  is mutated from two different processes — the per-recipient `ConversationSender`
  (encrypt, on send) and the `Connection` (decrypt/migrate/wipe, on receive). Two
  non-atomic `load → modify → store` cycles on the same blob can lose an update. A
  custodian is a per-record lock: every read-modify-write of that record funnels
  through this one process, so send and receive can no longer clobber each other.

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

  This slice is **write-through** — each op hits storage. An in-memory record cache
  is a deliberate later step, gated on every mutator provably routing through here.
  """

  use GenServer

  alias Amarula.Conn
  alias Amarula.Protocol.Signal.{SessionBuilder, SessionCipher, SessionRecord, SessionStore}
  alias Amarula.Storage

  @call_timeout 15_000

  @type t :: GenServer.server()
  @type store :: map()

  # --- client API ---

  @doc "Start a custodian for one record `key` on `conn`. (Phase 1 adds find-or-start.)"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    conn = Keyword.fetch!(opts, :conn)
    key = Keyword.fetch!(opts, :key)
    GenServer.start_link(__MODULE__, %{conn: conn, key: key}, Keyword.take(opts, [:name]))
  end

  @doc """
  Encrypt `plaintext` against this record, advancing the sending chain.
  `{:ok, :pkmsg | :msg, ciphertext}` or `{:error, :no_session | Exception.t()}`.
  """
  @spec encrypt(t(), binary(), store()) ::
          {:ok, :pkmsg | :msg, binary()} | {:error, :no_session | Exception.t()}
  def encrypt(custodian, plaintext, store) do
    GenServer.call(custodian, {:encrypt, plaintext, store}, @call_timeout)
  end

  @doc """
  Decrypt a `:pkmsg` (establishes a session if needed) or `:msg` against this
  record, advancing a receiving chain. `{:ok, plaintext, used_pre_key_id | nil}` or
  `{:error, reason}` (the reason preserves the cipher exception — the receive path
  inspects it for the consumed-key duplicate signal).
  """
  @spec decrypt(t(), :pkmsg | :msg, binary(), store()) ::
          {:ok, binary(), non_neg_integer() | nil} | {:error, term()}
  def decrypt(custodian, type, content, store) when type in [:pkmsg, :msg] do
    GenServer.call(custodian, {:decrypt, type, content, store}, @call_timeout)
  end

  @doc """
  Build an outgoing session from a parsed prekey-bundle `device`. `mode`:

    * `:if_absent` — skip when the record already has an open session (the
      first-contact re-check: a concurrent inbound pkmsg may have created one).
    * `:always` — (re-)initialise unconditionally (retry `<keys>` / identity refresh).

  Returns `:ok`, `{:skipped, :session_exists}`, or `{:error, Exception.t()}`.
  """
  @spec inject(t(), map(), store(), :always | :if_absent) ::
          :ok | {:skipped, :session_exists} | {:error, Exception.t()}
  def inject(custodian, device, store, mode) when mode in [:always, :if_absent] do
    GenServer.call(custodian, {:inject, device, store, mode}, @call_timeout)
  end

  @doc "`inject/4` then `encrypt/3` in one critical section (the atomic first-contact step)."
  @spec inject_then_encrypt(t(), map(), binary(), store(), :always | :if_absent) ::
          {:ok, :pkmsg | :msg, binary()} | {:error, term()}
  def inject_then_encrypt(custodian, device, plaintext, store, mode)
      when mode in [:always, :if_absent] do
    GenServer.call(
      custodian,
      {:inject_then_encrypt, device, plaintext, store, mode},
      @call_timeout
    )
  end

  @doc "Read the record without removing it (`{:ok, record | nil}`)."
  @spec get_record(t()) :: {:ok, map() | nil}
  def get_record(custodian), do: GenServer.call(custodian, :get_record, @call_timeout)

  @doc "Read and delete the record in one step (`{:ok, record | nil}`) — migration source side."
  @spec take_record(t()) :: {:ok, map() | nil}
  def take_record(custodian), do: GenServer.call(custodian, :take_record, @call_timeout)

  @doc "Blind-write a record — migration target side."
  @spec put_record(t(), map()) :: :ok
  def put_record(custodian, record),
    do: GenServer.call(custodian, {:put_record, record}, @call_timeout)

  @doc "Delete the record — identity-change wipe."
  @spec delete(t()) :: :ok
  def delete(custodian), do: GenServer.call(custodian, :delete, @call_timeout)

  # --- server ---

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:encrypt, plaintext, store}, _from, state) do
    {:reply, do_encrypt(state, plaintext, store), state}
  end

  @impl GenServer
  def handle_call({:decrypt, type, content, store}, _from, %{conn: conn, key: key} = state) do
    reply =
      case {type, SessionStore.load_session(conn, key)} do
        # A pkmsg can establish a session, so a nil record is valid input.
        {:pkmsg, record} ->
          with_cipher(fn ->
            {:ok, plaintext, record, pre_key_id} =
              SessionCipher.decrypt_pre_key_whisper_message(record, content, store)

            SessionStore.store_session(conn, key, record)
            {:ok, plaintext, pre_key_id}
          end)

        {:msg, nil} ->
          {:error, :no_session}

        {:msg, record} ->
          with_cipher(fn ->
            {:ok, plaintext, record} =
              SessionCipher.decrypt_whisper_message(record, content, store)

            SessionStore.store_session(conn, key, record)
            {:ok, plaintext, nil}
          end)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:inject, device, store, mode}, _from, %{conn: conn, key: key} = state) do
    reply =
      with_cipher(fn ->
        record = SessionStore.load_session(conn, key) || SessionRecord.new()

        if mode == :if_absent and SessionRecord.get_open_session(record) != nil do
          {:skipped, :session_exists}
        else
          SessionStore.store_session(
            conn,
            key,
            SessionBuilder.init_outgoing(record, device, store)
          )

          :ok
        end
      end)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:inject_then_encrypt, device, plaintext, store, mode}, _from, state) do
    %{conn: conn, key: key} = state

    reply =
      with_cipher(fn ->
        record = SessionStore.load_session(conn, key) || SessionRecord.new()

        record =
          if mode == :if_absent and SessionRecord.get_open_session(record) != nil,
            do: record,
            else: SessionBuilder.init_outgoing(record, device, store)

        {:ok, type, ciphertext, record} = SessionCipher.encrypt(record, plaintext, store)
        SessionStore.store_session(conn, key, record)
        {:ok, type, ciphertext}
      end)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(:get_record, _from, %{conn: conn, key: key} = state) do
    {:reply, {:ok, SessionStore.load_session(conn, key)}, state}
  end

  @impl GenServer
  def handle_call(:take_record, _from, %{conn: conn, key: key} = state) do
    record = SessionStore.load_session(conn, key)
    if record, do: delete_record(conn, key)
    {:reply, {:ok, record}, state}
  end

  @impl GenServer
  def handle_call({:put_record, record}, _from, %{conn: conn, key: key} = state) do
    SessionStore.store_session(conn, key, record)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:delete, _from, %{conn: conn, key: key} = state) do
    delete_record(conn, key)
    {:reply, :ok, state}
  end

  # --- internals ---

  defp do_encrypt(%{conn: conn, key: key}, plaintext, store) do
    case SessionStore.load_session(conn, key) do
      nil ->
        {:error, :no_session}

      record ->
        with_cipher(fn ->
          {:ok, type, ciphertext, record} = SessionCipher.encrypt(record, plaintext, store)
          SessionStore.store_session(conn, key, record)
          {:ok, type, ciphertext}
        end)
    end
  end

  # The cipher/builder raise on failure (and the trial-decrypt re-raises a
  # structured DecryptError the receive path inspects). Convert to an error tuple
  # HERE so a cipher failure fails only this one op, never crashes the custodian —
  # a crash would `:exit` every queued caller.
  defp with_cipher(fun) do
    fun.()
  rescue
    e -> {:error, e}
  end

  defp delete_record(%Conn{storage: scope, profile: profile}, key) do
    Storage.delete(scope, profile, :session, key)
  end
end
