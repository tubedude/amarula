defmodule Amarula.Content.GroupInvite do
  @moduledoc """
  A received group-invite card (`content` of a
  `%Amarula.Msg{type: :group_invite}`) — a tap-to-join invite for a group.

    * `:group` — the invited group as an `%Amarula.Address{}`.
    * `:code` — the invite code (the value `Amarula.Group.accept_invite/2` takes).
    * `:group_name` — the group's name as shown on the card.
    * `:caption` — accompanying text.
    * `:expiration` — invite expiry as a unix-ms timestamp (`nil` if none).
  """

  alias Amarula.Address

  @type t :: %__MODULE__{
          group: Address.t() | nil,
          code: String.t() | nil,
          group_name: String.t() | nil,
          caption: String.t() | nil,
          expiration: integer() | nil
        }

  defstruct [:group, :code, :group_name, :caption, :expiration]

  @doc "Normalize a `%Proto.Message.GroupInviteMessage{}` into a `%Amarula.Content.GroupInvite{}`."
  @spec from_proto(struct()) :: t()
  def from_proto(%{} = m) do
    %__MODULE__{
      group: Address.parse(Map.get(m, :groupJid)),
      code: Map.get(m, :inviteCode),
      group_name: Map.get(m, :groupName),
      caption: Map.get(m, :caption),
      expiration: Map.get(m, :inviteExpiration)
    }
  end
end
