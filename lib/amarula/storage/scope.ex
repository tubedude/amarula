defmodule Amarula.Storage.Scope do
  @moduledoc """
  A storage scope: the resolved adapter plus its per-connection state.

  This is what gets handed to a storage plugin (along with the connection
  `name`) — never the full `Amarula.Conn`, so a backend can't reach into the
  socket pid or creds. It carries no name of its own; the one name is the
  connection's, passed to each `Amarula.Storage` call.
  """

  @enforce_keys [:adapter, :state]
  defstruct [:adapter, :state]

  @type t :: %__MODULE__{adapter: module(), state: Amarula.Storage.adapter_state()}
end
