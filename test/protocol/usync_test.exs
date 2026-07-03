defmodule Amarula.Protocol.USyncTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.{Decoder, Encoder, Node, NodeUtils}
  alias Amarula.Protocol.USync
  alias Amarula.Protocol.USync.Protocols

  describe "build_iq/2" do
    test "errors with no protocols" do
      assert {:error, :no_protocols} = USync.new() |> USync.build_iq()
    end

    test "builds a devices+lid query for a jid user" do
      query =
        USync.new()
        |> USync.with_context("message")
        |> USync.with_protocol(:devices)
        |> USync.with_protocol(:lid)
        |> USync.with_user(%{id: "1234@s.whatsapp.net"})

      assert {:ok, iq} = USync.build_iq(query, "sid-123")

      assert iq.tag == "iq"
      assert iq.attrs["xmlns"] == "usync"
      assert iq.attrs["type"] == "get"

      usync = NodeUtils.get_binary_node_child(iq, "usync")
      assert usync.attrs["context"] == "message"
      assert usync.attrs["mode"] == "query"
      assert usync.attrs["sid"] == "sid-123"
      assert usync.attrs["last"] == "true"
      assert usync.attrs["index"] == "0"

      query_node = NodeUtils.get_binary_node_child(usync, "query")
      tags = Enum.map(query_node.content, & &1.tag)
      assert tags == ["devices", "lid"]

      devices_q = NodeUtils.get_binary_node_child(query_node, "devices")
      assert devices_q.attrs["version"] == "2"

      list_node = NodeUtils.get_binary_node_child(usync, "list")
      [user_node] = list_node.content
      assert user_node.attrs["jid"] == "1234@s.whatsapp.net"
    end

    test "devices/status emit no per-user element; lid emits only when lid present" do
      query =
        USync.new()
        |> USync.with_protocol(:devices)
        |> USync.with_protocol(:lid)
        |> USync.with_user(%{id: "1234@s.whatsapp.net"})

      {:ok, iq} = USync.build_iq(query)
      usync = NodeUtils.get_binary_node_child(iq, "usync")
      list_node = NodeUtils.get_binary_node_child(usync, "list")
      [user_node] = list_node.content

      # no lid on the user → devices nil + lid nil → empty user content
      assert user_node.content == []
    end

    test "lid user element is emitted when lid is set" do
      query =
        USync.new()
        |> USync.with_protocol(:lid)
        |> USync.with_user(%{id: "1234@s.whatsapp.net", lid: "99@lid"})

      {:ok, iq} = USync.build_iq(query)
      usync = NodeUtils.get_binary_node_child(iq, "usync")
      list_node = NodeUtils.get_binary_node_child(usync, "list")
      [user_node] = list_node.content
      [lid_node] = user_node.content
      assert lid_node.tag == "lid"
      assert lid_node.attrs["jid"] == "99@lid"
    end

    test "phone-based contact user omits jid attr and carries phone content" do
      query =
        USync.new()
        |> USync.with_protocol(:contact)
        |> USync.with_user(%{phone: "+15551234567"})

      {:ok, iq} = USync.build_iq(query)
      usync = NodeUtils.get_binary_node_child(iq, "usync")
      list_node = NodeUtils.get_binary_node_child(usync, "list")
      [user_node] = list_node.content

      refute Map.has_key?(user_node.attrs, "jid")
      [contact_node] = user_node.content
      assert contact_node.tag == "contact"
      assert contact_node.content == "+15551234567"
    end

    test "built IQ survives an encode/decode round-trip" do
      query =
        USync.new()
        |> USync.with_context("message")
        |> USync.with_protocol(:devices)
        |> USync.with_protocol(:lid)
        |> USync.with_user(%{id: "1234@s.whatsapp.net"})

      {:ok, iq} = USync.build_iq(query, "sid-abc")
      {:ok, bytes} = Encoder.encode(iq)
      decoded = Decoder.decode(bytes)

      assert decoded.tag == "iq"
      assert NodeUtils.get_attr(decoded, "xmlns") == "usync"

      usync = NodeUtils.get_binary_node_child(decoded, "usync")
      assert NodeUtils.get_attr(usync, "sid") == "sid-abc"
      assert NodeUtils.get_attr(usync, "context") == "message"

      query_node = NodeUtils.get_binary_node_child(usync, "query")
      assert Enum.map(query_node.content, & &1.tag) == ["devices", "lid"]
    end
  end

  describe "parse_result/2" do
    test "returns nil for non-result IQ" do
      query = USync.new() |> USync.with_protocol(:devices)
      reply = %Node{tag: "iq", attrs: %{"type" => "error"}, content: []}
      assert USync.parse_result(query, reply) == nil
    end

    test "parses lid and devices for a user" do
      query =
        USync.new()
        |> USync.with_protocol(:devices)
        |> USync.with_protocol(:lid)

      device_list = %Node{
        tag: "device-list",
        attrs: %{},
        content: [
          %Node{tag: "device", attrs: %{"id" => "0", "key-index" => "1"}, content: nil},
          %Node{
            tag: "device",
            attrs: %{"id" => "2", "key-index" => "3", "is_hosted" => "true"},
            content: nil
          }
        ]
      }

      reply = %Node{
        tag: "iq",
        attrs: %{"type" => "result"},
        content: [
          %Node{
            tag: "usync",
            attrs: %{},
            content: [
              %Node{
                tag: "list",
                attrs: %{},
                content: [
                  %Node{
                    tag: "user",
                    attrs: %{"jid" => "1234@s.whatsapp.net"},
                    content: [
                      %Node{tag: "lid", attrs: %{"val" => "99@lid"}, content: nil},
                      %Node{tag: "devices", attrs: %{}, content: [device_list]}
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }

      assert %{list: [entry], side_list: []} = USync.parse_result(query, reply)
      assert entry.id == "1234@s.whatsapp.net"
      assert entry["lid"] == "99@lid"

      assert %{device_list: devices} = entry["devices"]

      assert devices == [
               %{id: 0, key_index: 1, is_hosted: false},
               %{id: 2, key_index: 3, is_hosted: true}
             ]
    end

    test "skips users without a jid and drops unknown protocols" do
      query = USync.new() |> USync.with_protocol(:lid)

      reply = %Node{
        tag: "iq",
        attrs: %{"type" => "result"},
        content: [
          %Node{
            tag: "usync",
            attrs: %{},
            content: [
              %Node{
                tag: "list",
                attrs: %{},
                content: [
                  %Node{tag: "user", attrs: %{}, content: []},
                  %Node{
                    tag: "user",
                    attrs: %{"jid" => "5@s.whatsapp.net"},
                    content: [%Node{tag: "mystery", attrs: %{}, content: nil}]
                  }
                ]
              }
            ]
          }
        ]
      }

      assert %{list: [entry]} = USync.parse_result(query, reply)
      assert entry == %{id: "5@s.whatsapp.net"}
    end
  end

  describe "status protocol parsing" do
    test "a status node with t parses set_at as a DateTime" do
      node = %Node{tag: "status", attrs: %{"t" => "1700000000"}, content: "busy"}
      assert %{status: "busy", set_at: set_at} = Protocols.parse("status", node)
      assert set_at == DateTime.from_unix!(1_700_000_000)
    end

    test "a status node without t has set_at nil, not the epoch" do
      node = %Node{tag: "status", attrs: %{}, content: "busy"}
      assert %{status: "busy", set_at: nil} = Protocols.parse("status", node)
    end
  end
end
