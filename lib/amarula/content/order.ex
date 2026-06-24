defmodule Amarula.Content.Order do
  @moduledoc """
  A received order message (WhatsApp Business). Surfaces the few useful fields; for
  full detail read `msg.raw`.

    * `:order_id` — the order id.
    * `:title` — the order title.
    * `:item_count` — number of items.
    * `:message` — an accompanying message.
    * `:seller` — the seller as an `%Amarula.Address{}`.
  """

  alias Amarula.Address

  @type t :: %__MODULE__{
          order_id: String.t() | nil,
          title: String.t() | nil,
          item_count: integer() | nil,
          message: String.t() | nil,
          seller: Address.t() | nil
        }

  defstruct [:order_id, :title, :item_count, :message, :seller]

  @doc "Normalize a `%Proto.Message.OrderMessage{}` into a minimal `%Amarula.Content.Order{}`."
  @spec from_proto(struct()) :: t()
  def from_proto(%{} = m) do
    %__MODULE__{
      order_id: Map.get(m, :orderId),
      title: Map.get(m, :orderTitle),
      item_count: Map.get(m, :itemCount),
      message: Map.get(m, :message),
      seller: Address.parse(Map.get(m, :sellerJid))
    }
  end
end
