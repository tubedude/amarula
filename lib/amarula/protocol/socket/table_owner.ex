defmodule Amarula.Protocol.Socket.TableOwner do
  @moduledoc """
  Owns the per-connection retry-cache ETS table, created once at `init` — BEFORE
  the Connection that reads it starts, since it's an early child of the
  `ConnectionSupervisor`.

  This is why `RetryCache.ETS` never creates its table lazily: the owner
  guarantees it exists before any reader runs, so there's no create race (and no
  `try/rescue` race guard). The table is `:public` so reads/writes happen directly
  from any process; it dies (and is recreated on restart) with this owner.

  NOTE: this owns ETS *because the default RetryCache adapter is ETS*. A different
  retry-cache adapter (DETS, Redis) owns its own resources — see the adapter; the
  framework only provides this supervision slot for the local case.
  """

  use GenServer

  alias Amarula.RetryCache

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    profile = Keyword.fetch!(opts, :profile)
    GenServer.start_link(__MODULE__, profile, opts)
  end

  @impl true
  def init(profile) do
    RetryCache.ETS.ensure_table(profile)
    {:ok, profile}
  end
end
