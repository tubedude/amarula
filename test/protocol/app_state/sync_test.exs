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

      {:ok, changes, new_state, mismatches} =
        Sync.decode_collection([decoded_patch], Patch.new_state(), gk, "regular")

      assert [{:chat, %Amarula.Chat{pinned: true}}] = changes
      assert new_state.version == 1
      assert mismatches == []
    end

    test "a tampered patch MAC drops that patch's mutations but still advances the version", %{
      keys: keys,
      get_key: gk
    } do
      patch =
        pin_patch(keys, 1, "regular")
        |> Map.put(:patchMac, :crypto.strong_rand_bytes(32))

      assert {:ok, [], new_state, [{:patch_mac_mismatch, "regular"}]} =
               Sync.decode_collection([patch], Patch.new_state(), gk, "regular")

      # Version still advances — a persistently-mismatching patch must not
      # fossilize the collection at the old version forever (the original bug:
      # keeping the old version meant the next resync re-requested the same
      # version and hit the same mismatch).
      assert new_state.version == 1
      # The dropped patch's mutations never touched the hash: a legitimate
      # follow-up patch chained onto LTHash.zero() (not onto this patch's
      # value mac) still authenticates.
      assert new_state.hash == LTHash.zero()
    end

    test "a tampered snapshot MAC still applies that patch's mutations but stops the batch", %{
      keys: keys,
      get_key: gk
    } do
      # The patch MAC is itself computed over the (server-supplied) snapshot MAC
      # bytes, so a real-world scenario where only the snapshot/LTHash bookkeeping
      # is wrong (not a tampered wire patch) requires patchMac to still verify
      # against the bad snapshotMac — i.e. the server legitimately signed a
      # snapshotMac that doesn't match what we compute locally.
      base = pin_patch(keys, 1, "regular")
      bad_snapshot_mac = :crypto.strong_rand_bytes(32)

      value_macs =
        Enum.map(base.mutations, fn %{record: %{value: %{blob: b}}} ->
          binary_part(b, byte_size(b) - 32, 32)
        end)

      patch_mac =
        Mutation.generate_patch_mac(
          bad_snapshot_mac,
          value_macs,
          1,
          "regular",
          keys.patch_mac_key
        )

      patch =
        base
        |> Map.put(:snapshotMac, bad_snapshot_mac)
        |> Map.put(:patchMac, patch_mac)

      assert {:ok, [{:chat, %Amarula.Chat{pinned: true}}], new_state,
              [{:snapshot_mac_mismatch, "regular"}]} =
               Sync.decode_collection([patch], Patch.new_state(), gk, "regular")

      # The collection's version still advances — same freeze-prevention as above.
      assert new_state.version == 1
    end

    test "a mismatched patch MAC does not derail a clean sibling patch in the same batch", %{
      keys: keys,
      get_key: gk
    } do
      # First patch (v1) has its patchMac corrupted in transit — its mutations
      # must be dropped entirely, so the hash the second patch chains onto is
      # LTHash.zero() (as if the first patch never existed), not a hash that
      # includes the first patch's (never-applied) mutation.
      tampered =
        pin_patch(keys, 1, "regular")
        |> Map.put(:patchMac, :crypto.strong_rand_bytes(32))

      av = %Proto.SyncActionValue{pinAction: %Proto.SyncActionValue.PinAction{pinned: true}}

      clean =
        build_patch(
          ["pin_v1", "5511888888888@s.whatsapp.net"],
          av,
          keys,
          2,
          "regular",
          LTHash.zero()
        )

      {:ok, changes, new_state, mismatches} =
        Sync.decode_collection([tampered, clean], Patch.new_state(), gk, "regular")

      assert [{:chat, %Amarula.Chat{pinned: true}}] = changes
      assert new_state.version == 2
      assert mismatches == [{:patch_mac_mismatch, "regular"}]
    end

    test "a mismatched snapshot MAC on a contiguous patch does not stop the batch", %{
      keys: keys,
      get_key: gk
    } do
      # First patch (v1) is legitimate. Second patch (v2)'s snapshotMac is
      # corrupted, but its patch MAC is valid and it directly follows local state,
      # so the third patch (v3) is still processed (whatsmeow #1319).
      patch_1 = pin_patch(keys, 1, "regular")
      blob_1 = hd(patch_1.mutations).record.value.blob
      value_mac_1 = binary_part(blob_1, byte_size(blob_1) - 32, 32)
      hash_after_1 = LTHash.subtract_then_add(LTHash.zero(), [], [value_mac_1])

      av2 = %Proto.SyncActionValue{pinAction: %Proto.SyncActionValue.PinAction{pinned: false}}

      patch_2_base =
        build_patch(
          ["pin_v1", "5511888888888@s.whatsapp.net"],
          av2,
          keys,
          2,
          "regular",
          hash_after_1
        )

      bad_snapshot_mac_2 = :crypto.strong_rand_bytes(32)

      value_macs_2 =
        Enum.map(patch_2_base.mutations, fn %{record: %{value: %{blob: b}}} ->
          binary_part(b, byte_size(b) - 32, 32)
        end)

      patch_mac_2 =
        Mutation.generate_patch_mac(
          bad_snapshot_mac_2,
          value_macs_2,
          2,
          "regular",
          keys.patch_mac_key
        )

      patch_2 =
        patch_2_base
        |> Map.put(:snapshotMac, bad_snapshot_mac_2)
        |> Map.put(:patchMac, patch_mac_2)

      av3 = %Proto.SyncActionValue{pinAction: %Proto.SyncActionValue.PinAction{pinned: true}}

      patch_3 =
        build_patch(
          ["pin_v1", "5511777777777@s.whatsapp.net"],
          av3,
          keys,
          3,
          "regular",
          hash_after_1
        )

      {:ok, changes, new_state, mismatches} =
        Sync.decode_collection([patch_1, patch_2, patch_3], Patch.new_state(), gk, "regular")

      assert [
               {:chat, %Amarula.Chat{pinned: true}},
               {:chat, %Amarula.Chat{pinned: false}},
               {:chat, %Amarula.Chat{pinned: true}}
             ] = changes

      assert new_state.version == 3
      assert Enum.uniq(mismatches) == [{:snapshot_mac_mismatch, "regular"}]
    end

    test "a mismatched snapshot MAC stops the batch when a version was skipped", %{
      keys: keys,
      get_key: gk
    } do
      prior = %{Patch.new_state() | version: 4, hash: :crypto.strong_rand_bytes(128)}
      skipped = pin_patch(keys, 6, "regular")
      next = pin_patch(keys, 7, "regular")

      assert {:ok, [_only_first], %{version: 6}, [{:snapshot_mac_mismatch, "regular"}]} =
               Sync.decode_collection([skipped, next], prior, gk, "regular")
    end

    test "a mismatched snapshot MAC stops the batch when local state is empty", %{
      keys: keys,
      get_key: gk
    } do
      prior = %{Patch.new_state() | version: 4}
      patch = keys |> pin_patch(5, "regular") |> with_bad_snapshot_mac(keys, 5)
      next = pin_patch(keys, 6, "regular")

      assert {:ok, [_only_first], %{version: 5}, [{:snapshot_mac_mismatch, "regular"}]} =
               Sync.decode_collection([patch, next], prior, gk, "regular")
    end

    test "validate_macs: false skips the collection MACs", %{keys: keys, get_key: gk} do
      patch =
        pin_patch(keys, 1, "regular")
        |> Map.put(:snapshotMac, :crypto.strong_rand_bytes(32))
        |> Map.put(:patchMac, :crypto.strong_rand_bytes(32))

      assert {:ok, [{:chat, %Amarula.Chat{pinned: true}}], _state, []} =
               Sync.decode_collection([patch], Patch.new_state(), gk, "regular",
                 validate_macs: false
               )
    end

    test "a patch whose key is unavailable decodes to nothing and is not reported", %{
      keys: keys
    } do
      # get_key returns nil → every record is skipped, so there are no changes and no
      # collection MAC to authenticate. Must NOT be treated as a MAC mismatch.
      patch = pin_patch(keys, 1, "regular")

      assert {:ok, [], _state, []} =
               Sync.decode_collection([patch], Patch.new_state(), fn _ -> nil end, "regular")
    end

    test "an empty patch list yields no changes and the unchanged state", %{get_key: gk} do
      state = Patch.new_state()
      assert {:ok, [], ^state, []} = Sync.decode_collection([], state, gk, "regular")
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

      {:ok, changes, new_state, mismatches} =
        Sync.decode_collection([set.(true, 1), set.(false, 2)], Patch.new_state(), gk, "regular")

      assert new_state.version == 2
      assert mismatches == []

      assert [{:chat, %Amarula.Chat{pinned: true}}, {:chat, %Amarula.Chat{pinned: false}}] =
               changes
    end
  end

  defp pin_patch(keys, version, name) do
    index = ["pin_v1", "5511999999999@s.whatsapp.net"]
    av = %Proto.SyncActionValue{pinAction: %Proto.SyncActionValue.PinAction{pinned: true}}
    build_patch(index, av, keys, version, name)
  end

  defp build_patch(index, action_value, keys, version, name, prior_hash \\ nil) do
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

    # The resulting LTHash after this SET (chained onto `prior_hash`, default
    # zero for a patch that's the first in its collection), and the collection
    # MACs the server signs it with — so the patch authenticates against `keys`.
    hash = LTHash.subtract_then_add(prior_hash || LTHash.zero(), [], [value_mac])
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

  # A patch whose patch MAC verifies, but whose snapshot MAC doesn't match local state.
  defp with_bad_snapshot_mac(patch, keys, version) do
    snapshot_mac = :crypto.strong_rand_bytes(32)

    value_macs =
      Enum.map(patch.mutations, fn %{record: %{value: %{blob: b}}} ->
        binary_part(b, byte_size(b) - 32, 32)
      end)

    patch_mac =
      Mutation.generate_patch_mac(
        snapshot_mac,
        value_macs,
        version,
        "regular",
        keys.patch_mac_key
      )

    %{patch | snapshotMac: snapshot_mac, patchMac: patch_mac}
  end

  defp sync_reply(name, patch_blobs) do
    patches = Enum.map(patch_blobs, &%Node{tag: "patch", attrs: %{}, content: &1})
    collection = %Node{tag: "collection", attrs: %{"name" => name}, content: patches}
    sync = %Node{tag: "sync", attrs: %{}, content: [collection]}
    %Node{tag: "iq", attrs: %{}, content: [sync]}
  end
end
