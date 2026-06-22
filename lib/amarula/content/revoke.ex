defmodule Amarula.Content.Revoke do
  @moduledoc """
  A received delete-for-everyone (`content` of a `%Amarula.Msg{type: :revoke}`).

    * `:key` — the revoked message as a `{jid, msg_id}` ref.
  """

  @type t :: %__MODULE__{key: {String.t() | nil, String.t() | nil} | nil}

  @enforce_keys [:key]
  defstruct [:key]
end
