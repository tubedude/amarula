defmodule Amarula.Content.MemberTag do
  @moduledoc """
  A received group member-label change (`content` of a
  `%Amarula.Msg{type: :member_tag}`).

    * `:label` — the new label; `""` means the tag was **cleared** (removal).
    * `:timestamp` — when it changed (ms).

  The group is `msg.channel`; pair it with `Amarula.update_member_tag/3`.
  """

  @type t :: %__MODULE__{label: String.t(), timestamp: integer() | nil}

  @enforce_keys [:label]
  defstruct [:label, :timestamp]
end
