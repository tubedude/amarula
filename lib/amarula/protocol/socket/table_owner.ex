defmodule Amarula.Protocol.Socket.TableOwner do
  @moduledoc """
  Owns the per-connection ETS tables (message cache + retry cache), created once
  at `init` — BEFORE the ConnectionManager/Socket that read them start, since it's
  the first child of the `ConnectionSupervisor`.

  This is why the cache modules never create tables lazily: the owner guarantees
  the table exists before any reader runs, so there's no create race (and no
  `try/rescue` race guard — not an idiomatic pattern). The table is `:public` so
  cache reads/writes happen directly from any process; it dies (and is recreated
  on restart) with this owner, matching the connection's lifetime.
  """

  use GenServer

  alias Amarula.{MessageCache, RetryCache}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    profile = Keyword.fetch!(opts, :profile)
    GenServer.start_link(__MODULE__, profile, opts)
  end

  @impl true
  def init(profile) do
    # Create the tables we own. The cache modules look them up by name; we never
    # rely on lazy first-use creation.
    MessageCache.ensure_table(profile)
    RetryCache.ETS.ensure_table(profile)
    {:ok, profile}
  end
end
