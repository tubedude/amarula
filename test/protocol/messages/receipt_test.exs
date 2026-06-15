defmodule Amarula.Protocol.Messages.ReceiptTest do
  use ExUnit.Case, async: true

  alias Amarula.Address
  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Messages.Receipt

  defp receipt(attrs, children \\ []) do
    %Node{tag: "receipt", attrs: attrs, content: children}
  end

  @from "5511999999999@s.whatsapp.net"

  test "no type means delivered" do
    assert {:ok, r} = Receipt.parse(receipt(%{"id" => "ABC", "from" => @from, "t" => "1700"}))
    assert r.status == :delivered
    assert r.message_ids == ["ABC"]
    assert %Address{user: "5511999999999"} = r.from
    assert r.timestamp == 1700
  end

  test "read / read-self map to :read" do
    assert {:ok, %{status: :read}} = Receipt.parse(receipt(%{"id" => "X", "type" => "read"}))
    assert {:ok, %{status: :read}} = Receipt.parse(receipt(%{"id" => "X", "type" => "read-self"}))
  end

  test "sender -> :server_ack, played -> :played" do
    assert {:ok, %{status: :server_ack}} =
             Receipt.parse(receipt(%{"id" => "X", "type" => "sender"}))

    assert {:ok, %{status: :played}} = Receipt.parse(receipt(%{"id" => "X", "type" => "played"}))
  end

  test "a <list> child batches multiple ids" do
    list = %Node{
      tag: "list",
      attrs: %{},
      content: [
        %Node{tag: "item", attrs: %{"id" => "ID2"}, content: nil},
        %Node{tag: "item", attrs: %{"id" => "ID3"}, content: nil}
      ]
    }

    assert {:ok, %{message_ids: ids}} = Receipt.parse(receipt(%{"id" => "ID1"}, [list]))
    assert ids == ["ID1", "ID2", "ID3"]
  end

  test "participant is parsed when present" do
    r = receipt(%{"id" => "X", "type" => "read", "participant" => @from})
    assert {:ok, %{participant: %Address{user: "5511999999999"}}} = Receipt.parse(r)
  end

  test "unmapped type (e.g. retry) is an error, not a bad status" do
    assert {:error, :unknown_type} = Receipt.parse(receipt(%{"id" => "X", "type" => "retry"}))
  end
end
