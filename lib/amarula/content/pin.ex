defmodule Amarula.Content.Pin do
  @moduledoc """
  A received pin / unpin (`content` of a `%Amarula.Msg{type: :pin}`).

    * `:key` — the pinned message as a `{jid, msg_id}` ref.
    * `:pinned?` — `true` for a pin, `false` for an unpin.
  """

  @type t :: %__MODULE__{key: {String.t() | nil, String.t() | nil} | nil, pinned?: boolean()}

  @enforce_keys [:key]
  defstruct [:key, pinned?: false]
end
