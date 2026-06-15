defmodule Amarula.Group do
  @moduledoc """
  A group chat — the consumer-facing view of group metadata, with addresses as
  `Amarula.Address`. Built from the protocol metadata (`Groups.Metadata`) at the
  boundary; you get these from `Amarula.group_metadata/2` and `Amarula.list_groups/1`.

  A group is a *container* of participants, not a person: `:address` names the
  group (`:group` kind), `:participants` are the member `Amarula.Address`es.
  """

  alias Amarula.Address

  @type participant :: %{
          address: Address.t(),
          admin: :admin | :superadmin | nil
        }

  @type t :: %__MODULE__{
          address: Address.t(),
          subject: String.t() | nil,
          owner: Address.t() | nil,
          size: non_neg_integer(),
          participants: [participant()]
        }

  @enforce_keys [:address]
  defstruct [:address, :subject, :owner, :participants, size: 0]

  @doc "Build a `Group` from a `Amarula.Protocol.Groups.Metadata` map."
  @spec from_metadata(map()) :: t()
  def from_metadata(meta) do
    %__MODULE__{
      address: Address.parse(meta.id),
      subject: Map.get(meta, :subject),
      owner: meta |> Map.get(:owner) |> maybe_address(),
      size: Map.get(meta, :size, 0),
      participants: Enum.map(meta.participants, &participant/1)
    }
  end

  # A participant's id may be a PN or LID; parse to its Address. `admin` is the
  # raw `type` attr ("admin"/"superadmin"/nil).
  defp participant(%{id: id, admin: admin}) do
    %{address: Address.parse(id), admin: admin_kind(admin)}
  end

  defp admin_kind("superadmin"), do: :superadmin
  defp admin_kind("admin"), do: :admin
  defp admin_kind(_), do: nil

  defp maybe_address(nil), do: nil
  defp maybe_address(jid), do: Address.parse(jid)
end
