defmodule Amarula.ProfileRegistry do
  @moduledoc """
  The app-level `profile -> Connection pid` registry: the seam that enforces one
  connection per profile and lets a consumer refer to a connection by its
  `:profile` (restart-safe) rather than a raw pid.

  ## Reach = the registry module's reach

  By default this is a local Elixir `Registry` (this module name doubles as the
  default registry's process name, started by `Amarula.Supervisor`), so uniqueness
  is enforced **per node**. A clustered consumer can supply a different,
  `:via`-compatible registry via the `:registry` connection config — e.g.
  `Horde.Registry` for **cluster-wide** uniqueness:

      Amarula.new(%{profile: :primary, registry: {Horde.Registry, MyApp.HordeReg}})

  The `:registry` config is `{module, name}` (or just `name`, defaulting the module
  to `Registry`). The library only relies on the standard `Registry`/`:via`
  contract (`register/3`, `lookup/2`, `{:via, mod, {name, key}}`), so any module
  implementing it works without a code change here.

  Uniqueness is keyed by `profile` and is the **consumer's responsibility**: the
  library trusts `profile <-> credentials` 1:1 and does not validate it.
  """

  @default_module Registry
  @default_name __MODULE__

  @typedoc "A registry spec: `{module, name}` or a bare `name` (module defaults to `Registry`)."
  @type spec :: {module(), atom()} | atom()

  @doc "Resolve the `{module, name}` for a `Conn` (or config map), with defaults."
  @spec resolve(Amarula.Conn.t() | map()) :: {module(), atom()}
  def resolve(%Amarula.Conn{config: config}), do: resolve(config)
  def resolve(%{registry: {module, name}}), do: {module, name}

  def resolve(%{registry: name}) when is_atom(name) and not is_nil(name),
    do: {@default_module, name}

  def resolve(_), do: {@default_module, @default_name}

  @doc "The `:via` tuple for a connection's profile, used as the GenServer name."
  @spec via(Amarula.Conn.t() | map(), term()) :: {:via, module(), {atom(), term()}}
  def via(conn_or_config, profile) do
    {module, name} = resolve(conn_or_config)
    {:via, module, {name, profile}}
  end

  @doc "The live Connection pid for `profile`, or `nil`."
  @spec whereis(Amarula.Conn.t() | map(), term()) :: pid() | nil
  def whereis(conn_or_config, profile) do
    {module, name} = resolve(conn_or_config)

    case module.lookup(name, profile) do
      [{pid, _}] -> pid
      [] -> nil
    end
  rescue
    # The default registry (`Amarula.ProfileRegistry`) is started by
    # `Amarula.Supervisor`, which the consumer adds to their own tree — it isn't
    # auto-started. Looking it up before it exists raises `ArgumentError` from
    # `Registry.lookup/2`; surface a message naming the fix instead of that opaque
    # "unknown registry" error.
    ArgumentError ->
      raise """
      Amarula.Supervisor is not running. Add `Amarula.Supervisor` to your supervision \
      tree, before any `{Amarula, …}` connection children:

          children = [Amarula.Supervisor, MyApp.Bot, {Amarula, profile: :me, parent: MyApp.Bot}]
      """
  end
end
