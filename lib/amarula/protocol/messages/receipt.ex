defmodule Amarula.Protocol.Messages.Receipt do
  @moduledoc """
  Parse an inbound `<receipt>` into a delivery/read status update, ported from the
  status side of Baileys `handleReceipt` (`Socket/messages-recv.ts`) +
  `getStatusFromReceiptType` (`Utils/generics.ts`).

  A receipt tells us a message *we* sent reached or was read by the recipient (or
  that another of our devices read something). We surface that as a
  `:receipt_update` event so a consumer can track delivery/read state — the half
  of receipts that was previously just acked and dropped.
  """

  alias Amarula.Address
  alias Amarula.Protocol.Binary.{Node, NodeUtils}

  @typedoc "Message status implied by a receipt's `type` attribute."
  @type status :: :delivered | :server_ack | :read | :played

  @type t :: %{
          message_ids: [String.t()],
          from: Address.t() | nil,
          participant: Address.t() | nil,
          status: status(),
          timestamp: integer() | nil
        }

  # Receipt type -> message status (Baileys STATUS_MAP; missing type = delivered).
  @status_map %{
    "sender" => :server_ack,
    "played" => :played,
    "read" => :read,
    "read-self" => :read
  }

  @doc """
  Parse a `<receipt>` node into `%{message_ids, from, participant, status,
  timestamp}`. Returns `{:ok, t}`, or `{:error, :unknown_type}` for a receipt type
  we don't map (e.g. `retry`, handled elsewhere).
  """
  @spec parse(Node.t()) :: {:ok, t()} | {:error, :unknown_type}
  def parse(%Node{} = node) do
    type = NodeUtils.get_attr(node, "type")

    case status(type) do
      nil ->
        {:error, :unknown_type}

      status ->
        {:ok,
         %{
           message_ids: message_ids(node),
           from: address(NodeUtils.get_attr(node, "from")),
           participant: address(NodeUtils.get_attr(node, "participant")),
           status: status,
           timestamp: timestamp(node)
         }}
    end
  end

  # A missing type means a plain delivery receipt.
  defp status(nil), do: :delivered
  defp status(type), do: Map.get(@status_map, type)

  # The primary id is on the receipt; a <list> child can batch more.
  defp message_ids(node) do
    primary = NodeUtils.get_attr(node, "id")

    batched =
      case NodeUtils.get_binary_node_child(node, "list") do
        %Node{} = list ->
          list
          |> NodeUtils.get_binary_node_children("item")
          |> Enum.map(&NodeUtils.get_attr(&1, "id"))

        _ ->
          []
      end

    Enum.reject([primary | batched], &is_nil/1)
  end

  defp timestamp(node) do
    case Integer.parse(NodeUtils.get_attr(node, "t") || "") do
      {t, _} -> t
      :error -> nil
    end
  end

  defp address(nil), do: nil
  defp address(jid), do: Address.parse(jid)
end
