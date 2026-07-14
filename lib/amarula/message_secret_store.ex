defmodule Amarula.MessageSecretStore do
  @moduledoc """
  Pluggable store of inbound messages' `messageContextInfo.messageSecret`, keyed
  by message id — the key material needed to decrypt a later
  `secretEncryptedMessage` MESSAGE_EDIT envelope targeting that message (issue
  #30; see `Amarula.Protocol.Messages.EditEnvelope`).

  Each entry is `%{secret: binary(), sender: String.t()}`: the message's secret
  and its original, server-attested sender (used to reject an edit forged by a
  different group member who also knows the secret).

  This is a **separate concern from `Amarula.Storage`**: it holds ephemeral,
  bounded state (secrets for the ~15-minute edit window), not durable account
  state, so it has its own behaviour, adapters, and config key.

  ## Adapters

    * `Amarula.MessageSecretStore.ETS` — in-memory, per-connection (the default).
      Lost on restart, which is usually fine: an edit lands within minutes of the
      original. TTL-bounded so it can't grow without limit.
    * `Amarula.MessageSecretStore.ReadOnly` — backed by **your own** message
      store; Amarula keeps no copy and only reads. See "Using your own store".

  Select one via the connection config `:message_secret_store` (a `{adapter,
  opts}` spec, a bare adapter module, a bare opts list → the default adapter, or
  a prebuilt `Scope`), or set the default for all connections:

      config :amarula, message_secret_store_adapter: Amarula.MessageSecretStore.ETS

  The behaviour is open: any module implementing it can be passed as the adapter.

  ## Using your own store

  If your application already persists received messages (you must, to render an
  edit at all), the built-in cache is a redundant second copy — and it does not
  survive a connection restart. Point the store at what you already have with
  `Amarula.MessageSecretStore.ReadOnly` (or your own behaviour module): **you own
  writes** — Amarula never stores anything — and on an edit it reads the target
  message's secret back from you by `msg_id`. Retention (and surviving restarts)
  is then whatever your store already does.

  On receive, persist the secret (`Amarula.Msg.message_secret/1`) and the
  server-attested sender (`msg.from`) alongside the message, then serve them back:

      # in your :messages_upsert handler
      for m <- messages do
        MyApp.Messages.save(m.id, secret: Amarula.Msg.message_secret(m), sender: m.from)
      end

      # at connect
      Amarula.new(%{
        profile: :primary,
        message_secret_store:
          {Amarula.MessageSecretStore.ReadOnly,
           get: fn _profile, msg_id ->
             case MyApp.Messages.fetch(msg_id) do
               {:ok, %{secret: s, sender: j}} when is_binary(s) -> {:ok, %{secret: s, sender: j}}
               _ -> :error
             end
           end}
      })

  ## Scoping

  Like `Amarula.Storage`, every call carries the connection `profile`, so one
  adapter instance serves many connections. The dispatch handle is a
  `MessageSecretStore.Scope` (adapter + state).
  """

  alias Amarula.MessageSecretStore.Scope

  @typedoc "Adapter-specific state, returned by the adapter's `new/1`."
  @type adapter_state :: term()

  @typedoc "The connection identity (its `:profile`)."
  @type profile :: atom() | String.t()

  @typedoc "A stored entry: the message's secret and its server-attested sender."
  @type entry :: %{secret: binary(), sender: String.t()}

  @doc "Initialise adapter state from `opts`. Called once per connection."
  @callback new(opts :: keyword()) :: adapter_state()

  @doc """
  Optional. Stash `entry` under `msg_id` for `profile`, staying within bound. A
  **read-only** adapter backed by the consumer's own store (e.g.
  `Amarula.MessageSecretStore.ReadOnly`) does not implement this — the consumer
  owns writes, so Amarula never writes here.
  """
  @callback put(adapter_state(), profile(), msg_id :: String.t(), entry()) :: :ok

  @doc "Fetch a stored entry by `msg_id`, or `:error` on a miss (or past retention)."
  @callback get(adapter_state(), profile(), msg_id :: String.t()) :: {:ok, entry()} | :error

  @doc "Number of stored entries for `profile` (for tests/introspection)."
  @callback count(adapter_state(), profile()) :: non_neg_integer()

  @doc """
  Optional. Create any **process-owned local resource** the adapter needs, owned
  by the *calling* process — for the ETS adapter, the named table. Called from
  `Connection.init`, so the table is owned by Connection and dies (recreated
  empty) with it. Adapters with no such resource don't implement this.
  """
  @callback ensure_local(adapter_state(), profile()) :: :ok

  @optional_callbacks put: 4, ensure_local: 2

  @doc "The adapter used when config gives bare opts / no `:message_secret_store`."
  @spec default_adapter() :: module()
  def default_adapter do
    Application.get_env(:amarula, :message_secret_store_adapter, Amarula.MessageSecretStore.ETS)
  end

  @doc """
  Build a `MessageSecretStore.Scope` from a connection `config`. Reads
  `:message_secret_store` (a `{adapter, opts}` spec, a bare adapter module, a
  bare opts list, or a prebuilt `Scope`); when absent, uses `default_adapter/0`.
  """
  @spec scope(map()) :: Scope.t()
  def scope(config) when is_map(config), do: from_spec(Map.get(config, :message_secret_store))

  defp from_spec(%Scope{} = scope), do: scope

  defp from_spec({adapter, opts}) when is_atom(adapter) and is_list(opts),
    do: build(adapter, opts)

  defp from_spec(adapter) when is_atom(adapter) and not is_nil(adapter), do: build(adapter, [])
  defp from_spec(opts) when is_list(opts), do: build(default_adapter(), opts)
  defp from_spec(nil), do: build(default_adapter(), [])

  defp build(adapter, opts), do: %Scope{adapter: adapter, state: adapter.new(opts)}

  @doc """
  Stash a received message's secret + sender. A no-op for read-only adapters
  (those that don't implement `put/4`) — the consumer's store already has it.
  """
  @spec put(Scope.t(), profile(), String.t(), entry()) :: :ok
  def put(%Scope{adapter: a, state: s}, profile, msg_id, entry) do
    if function_exported?(a, :put, 4), do: a.put(s, profile, msg_id, entry), else: :ok
  end

  @doc "Fetch a stored entry by id, or `:error`."
  @spec get(Scope.t(), profile(), String.t()) :: {:ok, entry()} | :error
  def get(%Scope{adapter: a, state: s}, profile, msg_id), do: a.get(s, profile, msg_id)

  @doc "Number of stored entries for `profile`."
  @spec count(Scope.t(), profile()) :: non_neg_integer()
  def count(%Scope{adapter: a, state: s}, profile), do: a.count(s, profile)

  @doc """
  Create the adapter's process-owned local resource (the ETS table, for the
  default adapter), owned by the caller — call this from `Connection.init`. A
  no-op for adapters that don't own such a resource.
  """
  @spec ensure_local(Scope.t(), profile()) :: :ok
  def ensure_local(%Scope{adapter: a, state: s}, profile) do
    if function_exported?(a, :ensure_local, 2), do: a.ensure_local(s, profile), else: :ok
  end
end
