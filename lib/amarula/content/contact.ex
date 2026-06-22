defmodule Amarula.Content.Contact do
  @moduledoc """
  A received contact card (the `content` of a `%Amarula.Msg{type: :contact}`, and
  each element of a `:contacts` array).

    * `:display_name` — the contact's shown name.
    * `:vcard` — the raw vCard string (parse it with any vCard library if you need
      structured fields).
  """

  @type t :: %__MODULE__{display_name: String.t() | nil, vcard: String.t() | nil}

  @enforce_keys []
  defstruct [:display_name, :vcard]

  @doc "Normalize a `%Proto.Message.ContactMessage{}` into a `%Amarula.Content.Contact{}`."
  @spec from_proto(struct()) :: t()
  def from_proto(%{} = m) do
    %__MODULE__{display_name: Map.get(m, :displayName), vcard: Map.get(m, :vcard)}
  end
end
