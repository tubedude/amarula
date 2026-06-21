defmodule Amarula.RetryCache do
  @moduledoc """
  Pluggable cache of recently-sent messages, so the library can re-encrypt and
  resend when a recipient asks for a retry (`<receipt type="retry">`).

  This is a **separate concern from `Amarula.Storage`**: it holds ephemeral,
  bounded, latency-sensitive state (a small LRU of recent sends), not durable
  account state. It therefore has its own behaviour, its own adapters, and its
  own config key — independent of where durable storage lives.

  ## Adapters

    * `Amarula.RetryCache.ETS` — in-memory, per-connection (the default). Lost on
      restart, which is fine: a retry receipt arrives within seconds.
    * `Amarula.RetryCache.DETS` — on-disk, survives restart.

  Select one via the connection config `:retry_cache` (a `{adapter, opts}` spec,
  a bare opts list → the default adapter, or a prebuilt `Scope`), or set the
  default for all connections:

      config :amarula, retry_cache_adapter: Amarula.RetryCache.DETS

  ## Scoping

  Like `Amarula.Storage`, every call carries the connection `profile`, so one
  adapter instance serves many connections. The dispatch handle is a
  `RetryCache.Scope` (adapter + state).

  ## Eviction

  The cache is bounded; **eviction is the adapter's job** (each backend does it
  differently — an ETS size check, a DETS fold, a Redis TTL). `put/4` is expected
  to keep the cache within its bound.
  """

  alias Amarula.RetryCache.Scope

  @typedoc "Adapter-specific state, returned by the adapter's `new/1`."
  @type adapter_state :: term()

  @typedoc "The connection identity (its `:profile`)."
  @type profile :: atom() | String.t()

  @typedoc "A cached entry: the recipient + the sent message + a ms timestamp."
  @type entry :: %{recipient_jid: String.t(), message: struct(), ts: integer()}

  @doc "Initialise adapter state from `opts`. Called once per connection."
  @callback new(opts :: keyword()) :: adapter_state()

  @doc "Store `entry` under `msg_id` for `profile`, evicting to stay within bound."
  @callback put(adapter_state(), profile(), msg_id :: String.t(), entry()) :: :ok

  @doc "Fetch a cached entry by `msg_id`, or `:error` on a miss."
  @callback get(adapter_state(), profile(), msg_id :: String.t()) :: {:ok, entry()} | :error

  @doc "Number of cached entries for `profile` (for tests/introspection)."
  @callback count(adapter_state(), profile()) :: non_neg_integer()

  @doc """
  Optional. Create any **process-owned local resource** the adapter needs, owned
  by the *calling* process — for the ETS adapter, the named table. Called from
  `Connection.init`, so the table is owned by Connection and dies (and is
  recreated empty) with it: a poisoned entry can never survive the Connection
  restart it triggers. Adapters with no process-owned resource (DETS, Redis)
  don't implement this and it is a no-op.
  """
  @callback ensure_local(adapter_state(), profile()) :: :ok

  @optional_callbacks ensure_local: 2

  @doc "The adapter used when config gives bare opts / no `:retry_cache`."
  @spec default_adapter() :: module()
  def default_adapter do
    Application.get_env(:amarula, :retry_cache_adapter, Amarula.RetryCache.ETS)
  end

  @doc """
  Build a `RetryCache.Scope` from a connection `config`. Reads `:retry_cache`
  (a `{adapter, opts}` spec, a bare adapter module, a bare opts list, or a
  prebuilt `Scope`); when absent, uses `default_adapter/0` with no opts.
  """
  @spec scope(map()) :: Scope.t()
  def scope(config) when is_map(config), do: from_spec(Map.get(config, :retry_cache))

  defp from_spec(%Scope{} = scope), do: scope

  defp from_spec({adapter, opts}) when is_atom(adapter) and is_list(opts),
    do: build(adapter, opts)

  defp from_spec(adapter) when is_atom(adapter) and not is_nil(adapter), do: build(adapter, [])
  defp from_spec(opts) when is_list(opts), do: build(default_adapter(), opts)
  defp from_spec(nil), do: build(default_adapter(), [])

  defp build(adapter, opts), do: %Scope{adapter: adapter, state: adapter.new(opts)}

  @doc "Store a sent message for possible retry-resend."
  @spec put(Scope.t(), profile(), String.t(), entry()) :: :ok
  def put(%Scope{adapter: a, state: s}, profile, msg_id, entry),
    do: a.put(s, profile, msg_id, entry)

  @doc "Fetch a cached entry by id, or `:error`."
  @spec get(Scope.t(), profile(), String.t()) :: {:ok, entry()} | :error
  def get(%Scope{adapter: a, state: s}, profile, msg_id), do: a.get(s, profile, msg_id)

  @doc "Number of cached entries for `profile`."
  @spec count(Scope.t(), profile()) :: non_neg_integer()
  def count(%Scope{adapter: a, state: s}, profile), do: a.count(s, profile)

  @doc """
  Create the adapter's process-owned local resource (the ETS table, for the
  default adapter), owned by the caller — call this from `Connection.init`.
  A no-op for adapters that don't own such a resource.
  """
  @spec ensure_local(Scope.t(), profile()) :: :ok
  def ensure_local(%Scope{adapter: a, state: s}, profile) do
    if function_exported?(a, :ensure_local, 2), do: a.ensure_local(s, profile), else: :ok
  end
end
