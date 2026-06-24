defmodule Amarula.Content.Contacts do
  @moduledoc """
  A received multi-contact card (`content` of a `%Amarula.Msg{type: :contacts}`).

    * `:display_name` — the array's group label (WhatsApp's `displayName` on the
      contacts-array message), distinct from each card's own `display_name`.
    * `:contacts` — the individual cards as `%Amarula.Content.Contact{}`.
  """

  alias Amarula.Content.Contact

  @type t :: %__MODULE__{display_name: String.t() | nil, contacts: [Contact.t()]}

  defstruct [:display_name, contacts: []]

  @doc "Normalize a `%Proto.Message.ContactsArrayMessage{}` into a `%Amarula.Content.Contacts{}`."
  @spec from_proto(struct()) :: t()
  def from_proto(%{} = m) do
    %__MODULE__{
      display_name: Map.get(m, :displayName),
      contacts: m |> Map.get(:contacts, []) |> Enum.map(&Contact.from_proto/1)
    }
  end
end
