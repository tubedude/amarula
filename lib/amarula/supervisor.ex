defmodule Amarula.Supervisor do
  @moduledoc """
  Amarula's shared process tree — you add this to your supervision tree.

  It is not started automatically; placing it yourself lets you control its
  placement and restart strategy, start it conditionally, or nest it under a
  sub-tree:

      children = [
        Amarula.Supervisor,                              # ← the library's shared tree
        MyApp.Bot,                                       # your event sink
        {Amarula, profile: :my_bot, parent: MyApp.Bot}   # your connection(s)
      ]

      Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)

  Put it **before** any `{Amarula, …}` connection children and before `connect/2`
  is called — those need this tree to be running.

  It starts three shared, stateless processes:

    * `Amarula.ProfileRegistry` — the `profile -> Connection pid` registry that
      enforces one connection per profile (per node) and gives a restart-safe
      handle (refer to a connection by its `:profile`, not a raw pid).
    * `Amarula.InstanceRegistry` — names every per-connection tree's infrastructure
      by the connection's `instance_id` ref (tree supervisor, sibling roles, and
      each recipient's `ConversationSender`), keyed by the ref directly so no atom
      is minted per connection and two connections can never collide.
    * `Amarula.ConnectionsSupervisor` — a `DynamicSupervisor` that owns every
      per-connection tree. Connection trees start *here* (not linked to the caller
      of `connect/2`), so a connection crash is observable via events but never
      propagates an exit that kills the caller.

  A clustered consumer that wants one-connection-per-profile *cluster-wide* supplies
  its own registry via the `:registry` connection config (e.g. `Horde.Registry`);
  see `Amarula.Config`. The default local `Registry` enforces uniqueness per node.
  """

  use Supervisor

  @doc "Name of the `DynamicSupervisor` that owns all per-connection trees."
  def connections_supervisor, do: Amarula.ConnectionsSupervisor

  @doc "Start the shared tree. Pass no options; add `Amarula.Supervisor` to your children."
  def start_link(init_arg \\ []) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: Amarula.ProfileRegistry},
      {Registry, keys: :unique, name: Amarula.InstanceRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: connections_supervisor()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
