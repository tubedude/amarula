defmodule Amarula.AppState do
  @moduledoc """
  Consumer-facing app-state sync controls.

  App state (chats, contacts, mute/pin/archive, …) normally resyncs on its own —
  triggered by server `server_sync`/`account_sync` notifications, or a freshly
  shared app-state-sync key — always resuming from whatever version is stored
  locally. That's an internal, automatic path with no consumer entry point.

  `force_resync/2` is the one consumer-initiated lever: it resets the named
  collections back to a clean, version-0 state and re-requests them from the
  server as a fresh snapshot, rather than resuming from the (possibly diverged)
  locally stored version. Reach for it if a collection's local state looks
  stuck or wrong — most commonly after repeated MAC mismatches and truncated batches left it
  out of sync with the server for longer than a normal resync would fix.
  """

  alias Amarula.Connection

  @type conn :: GenServer.server()

  @doc """
  Force a fresh resync of `names` (default: every collection), from a clean
  snapshot rather than the locally stored version.

  Fire-and-forget — this returns as soon as the request is queued, not once the
  server replies. Results land the same way any other app-state resync's do:
  `:chats_update` / `:contacts_update` events to `parent_pid`. While the server's
  rate-limit wait (code 429) is running, no request goes out.

  `names` is `:all` (the default) or a list drawn from the five collections:
  `"critical_block"`, `"critical_unblock_low"`, `"regular_high"`, `"regular"`,
  `"regular_low"`. An unrecognised name resyncs nothing.

      Amarula.AppState.force_resync(conn)
      Amarula.AppState.force_resync(conn, ["regular", "regular_low"])
  """
  @spec force_resync(conn(), [String.t()] | :all) :: :ok
  def force_resync(conn, names \\ :all), do: Connection.force_resync_app_state(conn, names)
end
