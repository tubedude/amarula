defmodule Amarula.Application do
  @moduledoc """
  Starts the library's process tree:

    * `Amarula.ProfileRegistry` — the app-level `profile -> Connection pid`
      registry that enforces one connection per profile (per node) and gives
      consumers a restart-safe handle (refer to a connection by its `:profile`,
      not a raw pid).
    * `Amarula.InstanceRegistry` — the app-level registry that names every
      per-connection tree's *infrastructure* by the connection's `instance_id`
      ref: the tree supervisor, the sibling roles (Connection, sender
      supervisor), and each recipient's `ConversationSender`. Keying by the ref
      directly (not a hashed atom) means no atom is minted per connection and two
      connections can never collide.
    * `Amarula.ConnectionsSupervisor` — a `DynamicSupervisor` that owns every
      per-connection tree. Connection trees are started *here* (not linked to the
      caller of `connect/2`), so a connection crash is observable by the consumer
      via events but never propagates an exit signal that kills it.

  A clustered consumer that wants one-connection-per-profile *cluster-wide* can
  supply its own registry module via the `:registry` connection config (e.g.
  `Horde.Registry`); see `Amarula.Config`. The default local `Registry` enforces
  uniqueness per node only.
  """

  use Application

  @doc "Name of the `DynamicSupervisor` that owns all per-connection trees."
  def connections_supervisor, do: Amarula.ConnectionsSupervisor

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Amarula.ProfileRegistry},
      {Registry, keys: :unique, name: Amarula.InstanceRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: connections_supervisor()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Amarula.Supervisor)
  end
end
