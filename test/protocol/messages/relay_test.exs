defmodule Amarula.Protocol.Messages.RelayTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Messages.Relay
  alias Amarula.Protocol.Proto

  defp account, do: %Proto.ADVSignedDeviceIdentity{details: <<1, 2, 3>>}

  defp to_nodes(stanza) do
    stanza
    |> NodeUtils.get_binary_node_child("participants")
    |> NodeUtils.get_all_binary_node_children()
  end

  describe "build_multi_device_stanza/5" do
    test "errors on empty participant list" do
      assert {:error, :no_participants} =
               Relay.build_multi_device_stanza("M1", "1234@s.whatsapp.net", [], account())
    end

    test "builds one <to>/<enc> per device" do
      participants = [
        {"1234:0@s.whatsapp.net", :msg, <<0xAA>>},
        {"1234:2@s.whatsapp.net", :msg, <<0xBB>>}
      ]

      {:ok, stanza} =
        Relay.build_multi_device_stanza("M1", "1234@s.whatsapp.net", participants, account(), [])

      assert stanza.tag == "message"
      assert stanza.attrs["id"] == "M1"
      assert stanza.attrs["to"] == "1234@s.whatsapp.net"
      # No `t` attr — matches a live Baileys 1:1 send.
      refute Map.has_key?(stanza.attrs, "t")

      [to1, to2] = to_nodes(stanza)
      assert to1.attrs["jid"] == "1234:0@s.whatsapp.net"
      assert to2.attrs["jid"] == "1234:2@s.whatsapp.net"

      enc1 = NodeUtils.get_binary_node_child(to1, "enc")
      assert enc1.attrs == %{"v" => "2", "type" => "msg"}
      assert enc1.content == <<0xAA>>
    end

    test "omits device-identity when all enc are :msg" do
      participants = [{"1234:0@s.whatsapp.net", :msg, <<0xAA>>}]

      {:ok, stanza} =
        Relay.build_multi_device_stanza("M1", "1234@s.whatsapp.net", participants, account())

      assert NodeUtils.get_binary_node_child(stanza, "device-identity") == nil
    end

    test "includes device-identity when any enc is :pkmsg" do
      participants = [
        {"1234:0@s.whatsapp.net", :msg, <<0xAA>>},
        {"1234:2@s.whatsapp.net", :pkmsg, <<0xBB>>}
      ]

      {:ok, stanza} =
        Relay.build_multi_device_stanza("M1", "1234@s.whatsapp.net", participants, account())

      assert %Node{content: bytes} = NodeUtils.get_binary_node_child(stanza, "device-identity")
      assert bytes == Proto.ADVSignedDeviceIdentity.encode(account())
    end
  end
end
