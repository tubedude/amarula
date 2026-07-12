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
    assert {:ok, [r]} = Receipt.parse(receipt(%{"id" => "ABC", "from" => @from, "t" => "1700"}))
    assert r.status == :delivered
    assert r.message_ids == ["ABC"]
    assert %Address{user: "5511999999999"} = r.from
    assert r.timestamp == 1700
  end

  test "a malformed t attribute degrades to a nil timestamp" do
    assert {:ok, [r]} = Receipt.parse(receipt(%{"id" => "ABC", "from" => @from, "t" => "soon"}))
    assert r.timestamp == nil

    assert {:ok, [r]} = Receipt.parse(receipt(%{"id" => "ABC", "from" => @from}))
    assert r.timestamp == nil
  end

  test "read / read-self map to :read" do
    assert {:ok, [%{status: :read}]} = Receipt.parse(receipt(%{"id" => "X", "type" => "read"}))

    assert {:ok, [%{status: :read}]} =
             Receipt.parse(receipt(%{"id" => "X", "type" => "read-self"}))
  end

  test "sender -> :server_ack, played -> :played" do
    assert {:ok, [%{status: :server_ack}]} =
             Receipt.parse(receipt(%{"id" => "X", "type" => "sender"}))

    assert {:ok, [%{status: :played}]} =
             Receipt.parse(receipt(%{"id" => "X", "type" => "played"}))
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

    assert {:ok, [%{message_ids: ids}]} = Receipt.parse(receipt(%{"id" => "ID1"}, [list]))
    assert ids == ["ID1", "ID2", "ID3"]
  end

  test "participant is parsed when present" do
    r = receipt(%{"id" => "X", "type" => "read", "participant" => @from})
    assert {:ok, [%{participant: %Address{user: "5511999999999"}}]} = Receipt.parse(r)
  end

  test "unmapped type (e.g. retry) is an error, not a bad status" do
    assert {:error, :unknown_type} = Receipt.parse(receipt(%{"id" => "X", "type" => "retry"}))
  end

  describe "grouped group receipt (<participants>)" do
    @u1 "111@s.whatsapp.net"
    @u2 "222@s.whatsapp.net"
    @group "123-456@g.us"

    defp participants(key, users) do
      %Node{
        tag: "participants",
        attrs: %{"key" => key},
        content: Enum.map(users, fn {jid, t} -> user_node(jid, t) end)
      }
    end

    defp user_node(jid, t), do: %Node{tag: "user", attrs: %{"jid" => jid, "t" => t}, content: nil}

    test "fans out to one receipt per (message, participant)", _ctx do
      # A read receipt with no top-level id/participant, two members, one message.
      node =
        receipt(%{"from" => @group, "type" => "read"}, [
          participants("MSG1", [{@u1, "1700"}, {@u2, "1701"}])
        ])

      assert {:ok, receipts} = Receipt.parse(node)
      assert length(receipts) == 2

      assert [
               %{message_ids: ["MSG1"], participant: %Address{user: "111"}, timestamp: 1700},
               %{message_ids: ["MSG1"], participant: %Address{user: "222"}, timestamp: 1701}
             ] =
               receipts

      assert Enum.all?(receipts, &(&1.status == :read))
      assert Enum.all?(receipts, &match?(%Address{user: "123-456"}, &1.from))
    end

    test "handles multiple <participants> (one per message)", _ctx do
      node =
        receipt(%{"from" => @group}, [
          participants("MSGA", [{@u1, "10"}]),
          participants("MSGB", [{@u2, "20"}])
        ])

      assert {:ok, receipts} = Receipt.parse(node)
      assert Enum.map(receipts, & &1.message_ids) == [["MSGA"], ["MSGB"]]
    end
  end
end
