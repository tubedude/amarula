defmodule Amarula.Protocol.Groups.MetadataTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Groups.Metadata

  @group "120363000000000001@g.us"

  describe "query_iq/1" do
    test "builds an interactive w:g2 get query" do
      iq = Metadata.query_iq(@group)

      assert iq.tag == "iq"
      assert {"type", "get"} in iq.attrs
      assert {"xmlns", "w:g2"} in iq.attrs
      assert {"to", @group} in iq.attrs

      query = NodeUtils.get_binary_node_child(iq, "query")
      assert NodeUtils.get_attr(query, "request") == "interactive"
    end
  end

  describe "parse/1" do
    defp group_result(group_attrs, participants) do
      part_nodes =
        Enum.map(participants, fn attrs -> Node.create("participant", attrs, nil) end)

      group = Node.create("group", group_attrs, part_nodes)
      Node.create("iq", %{"type" => "result"}, [group])
    end

    test "parses id, addressing mode, size and participants" do
      reply =
        group_result(
          %{"id" => "120363000000000001", "addressing_mode" => "lid", "size" => "2"},
          [
            %{
              "jid" => "10000000001@lid",
              "type" => "admin",
              "phone_number" => "5550001@s.whatsapp.net"
            },
            %{"jid" => "10000000002@s.whatsapp.net", "lid" => "20000000002@lid"}
          ]
        )

      assert {:ok, meta} = Metadata.parse(reply)
      assert meta.id == @group
      assert meta.addressing_mode == :lid
      assert meta.size == 2

      [p1, p2] = meta.participants
      assert p1.id == "10000000001@lid"
      assert p1.admin == "admin"
      # lid id with a pn phone_number → carried
      assert p1.phone_number == "5550001@s.whatsapp.net"
      assert p1.lid == nil

      assert p2.id == "10000000002@s.whatsapp.net"
      # pn id with a lid → carried
      assert p2.lid == "20000000002@lid"
      assert p2.phone_number == nil
      assert p2.admin == nil
    end

    test "defaults addressing_mode to :pn and size to participant count" do
      reply =
        group_result(%{"id" => "120363000000000001"}, [
          %{"jid" => "10000000001@s.whatsapp.net"},
          %{"jid" => "10000000002@s.whatsapp.net"}
        ])

      assert {:ok, meta} = Metadata.parse(reply)
      assert meta.addressing_mode == :pn
      assert meta.size == 2
    end

    test "normalizes a bare group id to a g.us jid" do
      reply = group_result(%{"id" => "120363000000000001"}, [])
      assert {:ok, %{id: @group}} = Metadata.parse(reply)
    end

    test "surfaces an <error> node" do
      error = Node.create("error", %{"code" => "403", "text" => "not authorized"}, nil)
      reply = Node.create("iq", %{"type" => "error"}, [error])

      assert {:error, {:group_query_failed, "403", "not authorized"}} = Metadata.parse(reply)
    end

    test "errors when the <group> node is missing" do
      reply = Node.create("iq", %{"type" => "result"}, [])
      assert {:error, :missing_group_node} = Metadata.parse(reply)
    end

    test "errors when the group id is missing" do
      reply = Node.create("iq", %{"type" => "result"}, [Node.create("group", %{}, [])])
      assert {:error, :missing_group_id} = Metadata.parse(reply)
    end
  end
end
