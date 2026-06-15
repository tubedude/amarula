defmodule Amarula.Protocol.AppState.SyncTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.AppState.{Keys, Mutation, Patch, Sync}
  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Proto

  @key_id "k1"

  test "request_iq builds <iq w:sync:app:state><sync><collection…>" do
    iq = Sync.request_iq([{"regular", 5, false}, {"critical_block", 0, true}])
    assert Map.new(iq.attrs)["xmlns"] == "w:sync:app:state"
    sync = NodeUtils.get_binary_node_child(iq, "sync")
    cols = NodeUtils.get_binary_node_children(sync, "collection")
    assert length(cols) == 2
    c = hd(cols)
    assert NodeUtils.get_attr(c, "name") == "regular"
    assert NodeUtils.get_attr(c, "version") == "5"
    assert NodeUtils.get_attr(c, "return_snapshot") == "false"
  end

  test "collections/0 lists the five app-state collections" do
    assert "regular" in Sync.collections()
    assert "critical_block" in Sync.collections()
    assert length(Sync.collections()) == 5
  end

  describe "extract + decode a real patch round-trip" do
    setup do
      key_data = :crypto.strong_rand_bytes(32)
      keys = Keys.expand(key_data)
      {:ok, keys: keys, get_key: fn _ -> keys end}
    end

    test "extract_collections + decode_collection yields the chat change", %{
      keys: keys,
      get_key: gk
    } do
      # Build a SyncdPatch with one SET mutation (a pin action on a chat).
      index = ["pin_v1", "5511999999999@s.whatsapp.net"]
      av = %Proto.SyncActionValue{pinAction: %Proto.SyncActionValue.PinAction{pinned: true}}
      patch = build_patch(index, av, keys, 1)

      # Wrap it in a sync IQ reply node: <iq><sync><collection name=regular><patch>…
      reply = sync_reply("regular", [Proto.SyncdPatch.encode(patch)])

      [%{name: "regular", patches: [decoded_patch]}] = Sync.extract_collections(reply)
      {:ok, changes, new_state} = Sync.decode_collection([decoded_patch], Patch.new_state(), gk)

      assert [{:chat, %Amarula.Chat{pinned: true}}] = changes
      assert new_state.version == 1
    end
  end

  defp build_patch(index, action_value, keys, version) do
    index_bytes = Jason.encode!(index)
    action = %Proto.SyncActionData{index: index_bytes, value: action_value, version: 1}
    plaintext = Proto.SyncActionData.encode(action)
    iv = :crypto.strong_rand_bytes(16)

    padded =
      plaintext <>
        :binary.copy(<<16 - rem(byte_size(plaintext), 16)>>, 16 - rem(byte_size(plaintext), 16))

    ct = :crypto.crypto_one_time(:aes_256_cbc, keys.value_encryption_key, iv, padded, true)
    enc = iv <> ct
    value_mac = Mutation.generate_mac(:set, enc, @key_id, keys.value_mac_key)
    index_mac = :crypto.mac(:hmac, :sha256, keys.index_key, index_bytes)

    record = %Proto.SyncdRecord{
      index: %Proto.SyncdIndex{blob: index_mac},
      value: %Proto.SyncdValue{blob: enc <> value_mac},
      keyId: %Proto.KeyId{id: @key_id}
    }

    %Proto.SyncdPatch{
      version: %Proto.SyncdVersion{version: version},
      mutations: [%Proto.SyncdMutation{operation: :SET, record: record}]
    }
  end

  defp sync_reply(name, patch_blobs) do
    patches = Enum.map(patch_blobs, &%Node{tag: "patch", attrs: %{}, content: &1})
    collection = %Node{tag: "collection", attrs: %{"name" => name}, content: patches}
    sync = %Node{tag: "sync", attrs: %{}, content: [collection]}
    %Node{tag: "iq", attrs: %{}, content: [sync]}
  end
end
