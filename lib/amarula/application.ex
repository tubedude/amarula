defmodule Amarula.Application do
  @moduledoc """
  Starts the library's process tree. Currently just the default
  `Amarula.ProfileRegistry` — the app-level `profile -> Connection pid` registry
  that enforces one connection per profile (per node) and gives consumers a
  restart-safe handle (refer to a connection by its `:profile`, not a raw pid).

  A clustered consumer that wants one-connection-per-profile *cluster-wide* can
  supply its own registry module via the `:registry` connection config (e.g.
  `Horde.Registry`); see `Amarula.Config`. The default local `Registry` enforces
  uniqueness per node only.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Amarula.ProfileRegistry}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Amarula.Supervisor)
  end
end
