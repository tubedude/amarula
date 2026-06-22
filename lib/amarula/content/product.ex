defmodule Amarula.Content.Product do
  @moduledoc """
  A received product message (WhatsApp Business). A linked-device client can
  receive these but not send them; this surfaces the few useful fields. For full
  catalog detail, read `msg.raw`.

    * `:product_id` — the catalog product id.
    * `:title` — the product title.
    * `:description` — the product description.
    * `:business_owner_jid` — the seller's jid.
  """

  @type t :: %__MODULE__{
          product_id: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          business_owner_jid: String.t() | nil
        }

  defstruct [:product_id, :title, :description, :business_owner_jid]

  @doc "Normalize a `%Proto.Message.ProductMessage{}` into a minimal `%Amarula.Content.Product{}`."
  @spec from_proto(struct()) :: t()
  def from_proto(%{} = m) do
    snapshot = Map.get(m, :product) || %{}

    %__MODULE__{
      product_id: Map.get(snapshot, :productId),
      title: Map.get(snapshot, :title),
      description: Map.get(snapshot, :description),
      business_owner_jid: Map.get(m, :businessOwnerJid)
    }
  end
end
