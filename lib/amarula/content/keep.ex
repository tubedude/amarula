defmodule Amarula.Content.Keep do
  @moduledoc """
  A received keep-in-chat / undo (`content` of a `%Amarula.Msg{type: :keep}`).

    * `:key` — the kept message as a `{jid, msg_id}` ref.
    * `:kept?` — `true` to keep, `false` to undo a keep.
  """

  @type t :: %__MODULE__{key: {String.t() | nil, String.t() | nil} | nil, kept?: boolean()}

  @enforce_keys [:key]
  defstruct [:key, kept?: false]
end
