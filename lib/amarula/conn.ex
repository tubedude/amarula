defmodule Amarula.Conn do
  @moduledoc """
  A connection handle: everything Amarula knows about one connection, built once
  from its config at connect time and threaded through the protocol layer.

  Fields:

    * `:profile` — the connection's identity, e.g. `:primary`. Required; it scopes
      storage and distinguishes connections.
    * `:storage` — the resolved `Amarula.Storage.Scope` (adapter + state). Passed,
      with `:profile`, to every storage operation.
    * `:retry_cache` — the resolved `Amarula.RetryCache.Scope`.
    * `:message_secret_store` — the resolved `Amarula.MessageSecretStore.Scope`
      (inbound message secrets for decrypting newer-client edit envelopes, #30).
    * `:send_steps` / `:recv_steps` — the plugin pipelines (lists of step funs).
      A step is `fn ctx -> {:cont, ctx} | {:halt, reason}`; `attach/2` on a
      plugin appends to these (Req-style). The send pipeline runs before encrypt;
      the receive pipeline after decrypt, before the consumer sees the message.
    * `:config`  — the original config map (protocol settings: version, browser,
      websocket url, …).

  Storage plugins receive only `profile` + the scope's adapter state — never this
  struct — so a backend can't reach the socket pid or creds.
  """

  alias Amarula.MessageSecretStore
  alias Amarula.RetryCache
  alias Amarula.Storage

  @typedoc "A pipeline step: transforms the ctx or halts the pipeline."
  @type step :: (map() -> {:cont, map()} | {:halt, term()})

  @enforce_keys [:profile, :storage, :config]
  defstruct [
    :profile,
    :storage,
    :retry_cache,
    :message_secret_store,
    :config,
    send_steps: [],
    recv_steps: []
  ]

  @type t :: %__MODULE__{
          profile: Storage.profile(),
          storage: Storage.Scope.t(),
          retry_cache: RetryCache.Scope.t() | nil,
          message_secret_store: MessageSecretStore.Scope.t() | nil,
          config: map(),
          send_steps: [step()],
          recv_steps: [step()]
        }

  @default_root "./amarula_data"

  @doc """
  Build a `Conn` from a connection `config` map.

  Requires `:profile` (the connection name). Storage comes from `:storage`
  (a `{adapter, opts}` spec or a prebuilt `Scope`); if omitted it defaults to
  `Amarula.Storage.default_adapter/0` (the `File` adapter unless configured
  otherwise) rooted at `AMARULA_DATA_DIR` (or `#{@default_root}`). The adapter
  scopes by `:profile`.

  The returned `Conn` carries the default plugin pipelines (e.g. the retry-cache
  send step). Attach more with a plugin's `attach/2`, Req-style:

      Amarula.new(config) |> MyPlugin.attach() |> Amarula.connect()
  """
  @spec new(map()) :: t()
  def new(%{profile: profile} = config) when not is_nil(profile) do
    %__MODULE__{
      profile: profile,
      storage: Storage.scope(storage_spec(config)),
      retry_cache: RetryCache.scope(config),
      message_secret_store: MessageSecretStore.scope(config),
      config: config,
      send_steps: default_send_steps(),
      recv_steps: []
    }
  end

  def new(config) when is_map(config) do
    raise ArgumentError,
          "connection config must set :profile (e.g. profile: :primary); got: " <>
            inspect(Map.take(config, [:profile, :storage]))
  end

  @doc "Append a step to the send pipeline (runs before encrypt)."
  @spec append_send_step(t(), step()) :: t()
  def append_send_step(%__MODULE__{send_steps: steps} = conn, step) when is_function(step, 1) do
    %{conn | send_steps: steps ++ [step]}
  end

  @doc "Append a step to the receive pipeline (runs after decrypt)."
  @spec append_recv_step(t(), step()) :: t()
  def append_recv_step(%__MODULE__{recv_steps: steps} = conn, step) when is_function(step, 1) do
    %{conn | recv_steps: steps ++ [step]}
  end

  defp storage_spec(%{storage: storage}) when not is_nil(storage), do: storage

  defp storage_spec(_config) do
    {Storage.default_adapter(), root: System.get_env("AMARULA_DATA_DIR", @default_root)}
  end

  # Built-in send steps Amarula attaches by default. The retry cache records each
  # outgoing message here (a side-effect step) — dogfooding the plugin pipeline.
  defp default_send_steps, do: [&RetryCache.Step.record/1]
end
