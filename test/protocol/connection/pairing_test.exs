defmodule Amarula.Connection.PairingTest do
  @moduledoc "Pure unit tests for the pairing node/creds builders — no socket, no state."
  use ExUnit.Case, async: true

  alias Amarula.Connection.Pairing
  alias Amarula.Protocol.Binary.Node

  describe "pair_device_ack_node/1" do
    test "is a result IQ echoing the id, no content" do
      node = Pairing.pair_device_ack_node("ID-1")

      assert %Node{tag: "iq", content: nil} = node
      assert {"type", "result"} in node.attrs
      assert {"id", "ID-1"} in node.attrs
    end
  end

  describe "qr_refs/1" do
    test "extracts ref payloads in order" do
      node = %Node{
        tag: "iq",
        content: [
          %Node{
            tag: "pair-device",
            content: [
              %Node{tag: "ref", content: "REF1"},
              %Node{tag: "ref", content: "REF2"}
            ]
          }
        ]
      }

      assert Pairing.qr_refs(node) == ["REF1", "REF2"]
    end

    test "returns [] when there is no pair-device wrapper" do
      assert Pairing.qr_refs(%Node{tag: "iq", content: []}) == []
    end

    test "returns [] when pair-device has no refs" do
      node = %Node{tag: "iq", content: [%Node{tag: "pair-device", content: []}]}
      assert Pairing.qr_refs(node) == []
    end
  end

  describe "pair_device_sign_reply/3" do
    test "wraps the account-enc under pair-device-sign with the key-index" do
      node = Pairing.pair_device_sign_reply("ID-2", 7, "ACCT")

      assert %Node{tag: "iq"} = node
      assert [%Node{tag: "pair-device-sign", content: [device_identity]}] = node.content
      assert %Node{tag: "device-identity", content: "ACCT"} = device_identity
      assert device_identity.attrs == %{"key-index" => "7"}
    end
  end

  describe "update_credentials_after_pairing/7" do
    test "sets me/account/platform and prepends the signal identity" do
      creds = Pairing.update_credentials_after_pairing(
        %{signal_identities: [:existing]},
        :account,
        "jid@s.whatsapp.net",
        "lid@lid",
        "Biz",
        "android",
        :new_identity
      )

      assert creds.account == :account
      assert creds.platform == "android"
      assert creds.me == %{id: "jid@s.whatsapp.net", name: "Biz", lid: "lid@lid"}
      assert creds.signal_identities == [:new_identity, :existing]
    end

    test "defaults me.name to ~ when there's no business name, seeds identities" do
      creds = Pairing.update_credentials_after_pairing(
        %{},
        :account,
        "jid@s.whatsapp.net",
        "lid@lid",
        nil,
        "ios",
        :id
      )

      assert creds.me.name == "~"
      assert creds.signal_identities == [:id]
    end
  end
end
