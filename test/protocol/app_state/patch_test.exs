defmodule Amarula.Protocol.AppState.PatchTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.AppState.{Keys, LTHash, Mutation, Patch}
  alias Amarula.Protocol.Proto

  @key_id "test-key-id"

  setup do
    key_data = :crypto.strong_rand_bytes(32)
    keys = Keys.expand(key_data)
    get_key = fn b64 -> if b64 == Base.encode64(@key_id), do: keys, else: nil end
    {:ok, keys: keys, get_key: get_key}
  end

  # Build a SyncdRecord the way WhatsApp would: encrypt the SyncActionData value,
  # append the value MAC, HMAC the index. `index` is a JSON-encodable list.
  defp record(operation, index, action_value, keys) do
    index_bytes = Jason.encode!(index)
    action = %Proto.SyncActionData{index: index_bytes, value: action_value, version: 1}
    plaintext = Proto.SyncActionData.encode(action)

    iv = :crypto.strong_rand_bytes(16)
    padded = pkcs7_pad(plaintext)
    ct = :crypto.crypto_one_time(:aes_256_cbc, keys.value_encryption_key, iv, padded, true)
    enc = iv <> ct
    value_mac = Mutation.generate_mac(operation, enc, @key_id, keys.value_mac_key)
    index_mac = :crypto.mac(:hmac, :sha256, keys.index_key, index_bytes)

    %Proto.SyncdRecord{
      index: %Proto.SyncdIndex{blob: index_mac},
      value: %Proto.SyncdValue{blob: enc <> value_mac},
      keyId: %Proto.KeyId{id: @key_id}
    }
  end

  defp set_mutation(index, action_value, keys) do
    %Proto.SyncdMutation{operation: :SET, record: record(:set, index, action_value, keys)}
  end

  test "decodes a SET mutation, recovering index + action", %{keys: keys, get_key: gk} do
    av = %Proto.SyncActionValue{starAction: %Proto.SyncActionValue.StarAction{starred: true}}
    mut = set_mutation(["star", "123@s.whatsapp.net"], av, keys)

    {:ok, [m], state} = Patch.decode_mutations([mut], Patch.new_state(), gk)
    assert m.operation == :set
    assert m.index == ["star", "123@s.whatsapp.net"]
    assert m.action.value.starAction.starred == true
    refute state.hash == LTHash.zero()
    assert map_size(state.index_value_map) == 1
  end

  test "SET then REMOVE of the same index returns the hash to base", %{keys: keys, get_key: gk} do
    av = %Proto.SyncActionValue{}
    idx = ["mute", "g@g.us"]
    set = set_mutation(idx, av, keys)
    {:ok, _, after_set} = Patch.decode_mutations([set], Patch.new_state(), gk)

    rem = %Proto.SyncdMutation{operation: :REMOVE, record: record(:remove, idx, av, keys)}
    {:ok, _, after_remove} = Patch.decode_mutations([rem], after_set, gk)

    assert after_remove.hash == LTHash.zero()
    assert after_remove.index_value_map == %{}
  end

  test "skips records whose key is unavailable (missing key → parked)", %{keys: keys} do
    mut = set_mutation(["x"], %Proto.SyncActionValue{}, keys)
    {:ok, mutations, state} = Patch.decode_mutations([mut], Patch.new_state(), fn _ -> nil end)
    assert mutations == []
    assert state.hash == LTHash.zero()
  end

  test "skips a record with a bad value MAC", %{keys: keys, get_key: gk} do
    mut = set_mutation(["x"], %Proto.SyncActionValue{}, keys)
    # Corrupt the trailing value MAC.
    blob = mut.record.value.blob
    bad = binary_part(blob, 0, byte_size(blob) - 1) <> <<0>>
    mut = put_in(mut.record.value.blob, bad)

    {:ok, mutations, _state} = Patch.decode_mutations([mut], Patch.new_state(), gk)
    assert mutations == []
  end

  defp pkcs7_pad(data) do
    pad = 16 - rem(byte_size(data), 16)
    data <> :binary.copy(<<pad>>, pad)
  end
end
