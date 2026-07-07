defmodule Amarula.Protocol.AppState.SyncTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.AppState.{Keys, LTHash, Mutation, Patch, Sync}
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
      patch = build_patch(index, av, keys, 1, "regular")

      # Wrap it in a sync IQ reply node: <iq><sync><collection name=regular><patch>…
      reply = sync_reply("regular", [Proto.SyncdPatch.encode(patch)])

      [%{name: "regular", patches: [decoded_patch]}] = Sync.extract_collections(reply)

      {:ok, changes, new_state} =
        Sync.decode_collection([decoded_patch], Patch.new_state(), gk, "regular")

      assert [{:chat, %Amarula.Chat{pinned: true}}] = changes
      assert new_state.version == 1
    end

    test "a tampered snapshot MAC is rejected", %{keys: keys, get_key: gk} do
      patch =
        pin_patch(keys, 1, "regular")
        |> Map.put(:snapshotMac, :crypto.strong_rand_bytes(32))

      assert {:error, {:snapshot_mac_mismatch, "regular"}} =
               Sync.decode_collection([patch], Patch.new_state(), gk, "regular")
    end

    test "a tampered patch MAC is rejected", %{keys: keys, get_key: gk} do
      patch =
        pin_patch(keys, 1, "regular")
        |> Map.put(:patchMac, :crypto.strong_rand_bytes(32))

      assert {:error, {:patch_mac_mismatch, "regular"}} =
               Sync.decode_collection([patch], Patch.new_state(), gk, "regular")
    end

    test "validate_macs: false skips the collection MACs", %{keys: keys, get_key: gk} do
      patch =
        pin_patch(keys, 1, "regular")
        |> Map.put(:snapshotMac, :crypto.strong_rand_bytes(32))
        |> Map.put(:patchMac, :crypto.strong_rand_bytes(32))

      assert {:ok, [{:chat, %Amarula.Chat{pinned: true}}], _} =
               Sync.decode_collection([patch], Patch.new_state(), gk, "regular",
                 validate_macs: false
               )
    end

    test "a patch whose key is unavailable decodes to nothing and is not rejected", %{keys: keys} do
      # get_key returns nil → every record is skipped, so there are no changes and no
      # collection MAC to authenticate. Must NOT be treated as a MAC failure.
      patch = pin_patch(keys, 1, "regular")

      assert {:ok, [], _state} =
               Sync.decode_collection([patch], Patch.new_state(), fn _ -> nil end, "regular")
    end

    test "an empty patch list yields no changes and the unchanged state", %{get_key: gk} do
      state = Patch.new_state()
      assert {:ok, [], ^state} = Sync.decode_collection([], state, gk, "regular")
    end

    test "a multi-patch collection threads state and validates each patch", %{
      keys: keys,
      get_key: gk
    } do
      # Two SETs on the same chat (pin true → false) at versions 1 and 2; the second
      # patch's snapshot MAC covers the cumulative LTHash.
      set = fn pinned, v ->
        av = %Proto.SyncActionValue{pinAction: %Proto.SyncActionValue.PinAction{pinned: pinned}}
        build_patch(["pin_v1", "5511999999999@s.whatsapp.net"], av, keys, v, "regular")
      end

      {:ok, changes, new_state} =
        Sync.decode_collection([set.(true, 1), set.(false, 2)], Patch.new_state(), gk, "regular")

      assert new_state.version == 2

      assert [{:chat, %Amarula.Chat{pinned: true}}, {:chat, %Amarula.Chat{pinned: false}}] =
               changes
    end
  end

  defp pin_patch(keys, version, name) do
    index = ["pin_v1", "5511999999999@s.whatsapp.net"]
    av = %Proto.SyncActionValue{pinAction: %Proto.SyncActionValue.PinAction{pinned: true}}
    build_patch(index, av, keys, version, name)
  end

  defp build_patch(index, action_value, keys, version, name) do
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

    # The resulting LTHash after this single SET, and the collection MACs the server
    # signs it with — so the patch authenticates against `keys`.
    hash = LTHash.subtract_then_add(LTHash.zero(), [], [value_mac])
    snapshot_mac = Mutation.generate_snapshot_mac(hash, version, name, keys.snapshot_mac_key)

    patch_mac =
      Mutation.generate_patch_mac(snapshot_mac, [value_mac], version, name, keys.patch_mac_key)

    %Proto.SyncdPatch{
      version: %Proto.SyncdVersion{version: version},
      mutations: [%Proto.SyncdMutation{operation: :SET, record: record}],
      keyId: %Proto.KeyId{id: @key_id},
      snapshotMac: snapshot_mac,
      patchMac: patch_mac
    }
  end

  defp sync_reply(name, patch_blobs) do
    patches = Enum.map(patch_blobs, &%Node{tag: "patch", attrs: %{}, content: &1})
    collection = %Node{tag: "collection", attrs: %{"name" => name}, content: patches}
    sync = %Node{tag: "sync", attrs: %{}, content: [collection]}
    %Node{tag: "iq", attrs: %{}, content: [sync]}
  end
end
