defmodule Amarula.Content.Edit do
  @moduledoc """
  A received message edit (`content` of a `%Amarula.Msg{type: :edit}`).

    * `:key` — the edited message as a `{jid, msg_id}` ref.
    * `:text` — the new text.
  """

  @type t :: %__MODULE__{key: {String.t() | nil, String.t() | nil} | nil, text: String.t() | nil}

  @enforce_keys [:key]
  defstruct [:key, :text]
end
