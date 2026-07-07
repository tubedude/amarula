defmodule Amarula.Application do
  @moduledoc """
  Optional auto-start of Amarula's shared tree (`Amarula.Supervisor`).

  By default this starts **nothing** — you add `Amarula.Supervisor` to your own
  supervision tree and control its placement. If you'd rather Amarula start it for
  you (so the library works once it's in your deps), opt in:

      config :amarula, start_supervisor: true

  Either way the tree is the same; this only decides who starts it.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:amarula, :start_supervisor, false) do
        [Amarula.Supervisor]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Amarula.RootSupervisor)
  end
end
