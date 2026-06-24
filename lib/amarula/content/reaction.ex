defmodule Amarula.Content.Reaction do
  @moduledoc """
  A received reaction (`content` of a `%Amarula.Msg{type: :reaction}`).

    * `:key` — the reacted-to message as a `{jid, msg_id}` ref (feed it straight to
      `Amarula.send_reaction/3`).
    * `:emoji` — the reaction emoji; `""` means the reaction was **removed**.
  """

  @type t :: %__MODULE__{key: {String.t() | nil, String.t() | nil} | nil, emoji: String.t()}

  @enforce_keys [:key]
  defstruct [:key, emoji: ""]
end
