defmodule Amarula.Content.Protocol do
  @moduledoc """
  A received control frame (`content` of a `%Amarula.Msg{type: :protocol}`) — a
  bare `protocolMessage` Amarula doesn't surface as a user message (ephemeral /
  setting changes and other unhandled types). Delivered on the `:protocol_update`
  event, not `:messages_upsert`.

    * `:type` — the protocol-message type atom (e.g. `:EPHEMERAL_SETTING`). The full
      detail is on `msg.raw` if you need it.
  """

  @type t :: %__MODULE__{type: atom() | nil}

  @enforce_keys [:type]
  defstruct [:type]
end
