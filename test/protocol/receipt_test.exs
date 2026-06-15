defmodule Amarula.Protocol.ReceiptTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Receipt

  test "single id: read receipt, no list content" do
    node = Receipt.read(["ID1"], "999@s.whatsapp.net", nil, 1_700_000_000)

    assert %Node{
             tag: "receipt",
             attrs: %{
               "id" => "ID1",
               "type" => "read",
               "t" => "1700000000",
               "to" => "999@s.whatsapp.net"
             },
             content: nil
           } = node

    refute Map.has_key?(node.attrs, "participant")
  end

  test "multiple ids: first in id attr, rest in <list><item>" do
    node = Receipt.read(["ID1", "ID2", "ID3"], "999@s.whatsapp.net", nil, 1)

    assert node.attrs["id"] == "ID1"
    assert [%Node{tag: "list", content: items}] = node.content
    assert Enum.map(items, & &1.attrs["id"]) == ["ID2", "ID3"]
  end

  test "participant included when given (group sender)" do
    node = Receipt.read(["ID1"], "g@g.us", "555@s.whatsapp.net", 1)
    assert node.attrs["participant"] == "555@s.whatsapp.net"
  end
end
