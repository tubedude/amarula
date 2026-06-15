defmodule Amarula.Storage do
  @moduledoc """
  Pluggable, connection-scoped persistence for a connection's protocol state.

  Everything Amarula must remember across a send/receive — credentials, 1:1
  Signal sessions, group sender keys, LID↔PN mappings, the device-list cache —
  is a key/value entry in one of a handful of *namespaces*. This behaviour is the
  seam between the protocol code (which only ever says "save this session", "load
  that mapping") and *where* those bytes actually live.

  ## Scoping by profile

  Storage is a plugin: implement the callbacks below and pass `{YourAdapter,
  opts}` as a connection's `:storage` config. Every call also receives the
  connection's **profile** (its identity, e.g. `:primary`), so one adapter
  instance can serve many connections, each isolated. The adapter decides *how*
  to isolate by that profile — `Amarula.Storage.File` uses a per-profile
  subfolder; a database adapter would use it as a tenant key. There is exactly
  one profile (the connection's); the storage layer never invents its own.

  The scope threaded through the protocol layer is `t:Amarula.Storage.Scope.t/0`
  (adapter + its state), built once at connect; the profile is carried alongside
  on the `Amarula.Conn` and passed to each call.

  ## Namespaces

    * `:creds`       — the auth-creds map. Singleton; key is `:self`.
    * `:session`     — 1:1 Signal `SessionRecord`, keyed by signal address.
    * `:sender_key`  — group `SenderKeyRecord`, keyed by sender-key-name string.
    * `:lid_mapping` — LID↔PN user mapping, keyed by the user string.
    * `:device_list` — cached device list, keyed by user string.

  The retry cache is deliberately *not* here — it is ephemeral, bounded state
  with different needs (eviction, low latency), handled by the separate
  pluggable `Amarula.RetryCache` (its own behaviour + adapters).

  ## Contract

  Values are arbitrary Elixir terms. `get/4` returns `{:ok, value}` on a hit and
  `:error` on a miss (a corrupt/unreadable entry is treated as a miss). `put/5`
  and `delete/4` return `:ok` or `{:error, reason}`. Adapters must be safe to
  call concurrently from multiple processes for the same scope/name.
  """

  alias Amarula.Storage.Scope

  @typedoc "Adapter-specific state, returned by the adapter's `new/1`."
  @type adapter_state :: term()

  @typedoc "The connection identity (its `:profile`) used to scope storage."
  @type profile :: atom() | String.t()

  @typedoc "A storage namespace. See the moduledoc."
  @type namespace ::
          :creds
          | :session
          | :sender_key
          | :lid_mapping
          | :device_list
          | :app_state_sync_key
          | :app_state_version

  @typedoc "A key within a namespace. `:creds` uses `:self`; the rest use strings."
  @type key :: :self | String.t()

  @doc """
  Initialise adapter state from `opts`. Returns the value carried in the scope and
  passed back to every other callback. Called once per connection.
  """
  @callback new(opts :: keyword()) :: adapter_state()

  @doc "Fetch the value at `{profile, namespace, key}`. `:error` on miss/corruption."
  @callback get(adapter_state(), profile(), namespace(), key()) :: {:ok, term()} | :error

  @doc "Store `value` at `{profile, namespace, key}`, overwriting any prior value."
  @callback put(adapter_state(), profile(), namespace(), key(), value :: term()) ::
              :ok | {:error, term()}

  @doc "Delete `{profile, namespace, key}`. Deleting a missing key is `:ok`."
  @callback delete(adapter_state(), profile(), namespace(), key()) :: :ok | {:error, term()}

  @doc """
  Wipe ALL stored data for `profile` (every namespace) — used by logout/forget.
  A filesystem adapter removes the profile directory; a DB adapter drops the
  tenant's rows. Optional: adapters that don't implement it report `{:error,
  :not_supported}`.
  """
  @callback clear(adapter_state(), profile()) :: :ok | {:error, term()}
  @optional_callbacks clear: 2

  # The adapter used when config gives bare opts / no :storage. Configurable so
  # the core privileges no concrete backend:
  #   config :amarula, default_storage_adapter: Amarula.Storage.DETS
  @spec default_adapter() :: module()
  def default_adapter do
    Application.get_env(:amarula, :default_storage_adapter, Amarula.Storage.File)
  end

  @doc """
  Build a `t:Amarula.Storage.Scope.t/0` from a `:storage` config value. Accepts a
  `{adapter, opts}` spec, a bare opts list (→ `default_adapter/0`), or a prebuilt
  `Scope`. The adapter's `new/1` runs now.

      Storage.scope({Amarula.Storage.File, root: "./data"})
      Storage.scope(root: "./data")        # default adapter
  """
  @spec scope(Scope.t() | {module(), keyword()} | keyword()) :: Scope.t()
  def scope(%Scope{} = scope), do: scope
  def scope({adapter, opts}) when is_atom(adapter) and is_list(opts), do: build(adapter, opts)
  def scope(opts) when is_list(opts), do: build(default_adapter(), opts)

  defp build(adapter, opts), do: %Scope{adapter: adapter, state: adapter.new(opts)}

  @doc "Fetch the value at `{profile, namespace, key}`. `:error` on miss/corruption."
  @spec get(Scope.t(), profile(), namespace(), key()) :: {:ok, term()} | :error
  def get(%Scope{adapter: a, state: s}, profile, namespace, key),
    do: a.get(s, profile, namespace, key)

  @doc "Like `get/4`, returning `default` (nil) instead of `:error` on a miss."
  @spec fetch(Scope.t(), profile(), namespace(), key(), term()) :: term()
  def fetch(scope, profile, namespace, key, default \\ nil) do
    case get(scope, profile, namespace, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc "Store `value` at `{profile, namespace, key}`."
  @spec put(Scope.t(), profile(), namespace(), key(), term()) :: :ok | {:error, term()}
  def put(%Scope{adapter: a, state: s}, profile, namespace, key, value),
    do: a.put(s, profile, namespace, key, value)

  @doc "Delete `{profile, namespace, key}`."
  @spec delete(Scope.t(), profile(), namespace(), key()) :: :ok | {:error, term()}
  def delete(%Scope{adapter: a, state: s}, profile, namespace, key),
    do: a.delete(s, profile, namespace, key)

  @doc "Wipe all data for `profile` (logout/forget). `{:error, :not_supported}` if the adapter can't."
  @spec clear(Scope.t(), profile()) :: :ok | {:error, term()}
  def clear(%Scope{adapter: a, state: s}, profile) do
    if function_exported?(a, :clear, 2), do: a.clear(s, profile), else: {:error, :not_supported}
  end
end
