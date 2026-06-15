defmodule Amarula.Protocol.AppState.KeysMutationTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.AppState.{Keys, Mutation}
  alias Amarula.Protocol.Crypto.Crypto

  describe "Keys.expand/1" do
    test "yields 5 distinct 32-byte sub-keys" do
      k = Keys.expand(:crypto.strong_rand_bytes(32))

      vals = [
        k.index_key,
        k.value_encryption_key,
        k.value_mac_key,
        k.snapshot_mac_key,
        k.patch_mac_key
      ]

      assert Enum.all?(vals, &(byte_size(&1) == 32))
      assert length(Enum.uniq(vals)) == 5
    end

    test "matches the HKDF slices directly" do
      key_data = :crypto.strong_rand_bytes(32)

      <<a::binary-32, b::binary-32, _::binary-32, _::binary-32, e::binary-32>> =
        Crypto.hkdf(key_data, 160, <<>>, "WhatsApp Mutation Keys")

      k = Keys.expand(key_data)
      assert k.index_key == a
      assert k.value_encryption_key == b
      assert k.patch_mac_key == e
    end
  end

  describe "Mutation MACs" do
    test "generate_mac is deterministic and op-sensitive" do
      key = :crypto.strong_rand_bytes(32)
      data = "payload"
      key_id = "kid"
      m_set = Mutation.generate_mac(:set, data, key_id, key)
      assert byte_size(m_set) == 32
      assert m_set == Mutation.generate_mac(:set, data, key_id, key)
      refute m_set == Mutation.generate_mac(:remove, data, key_id, key)
    end

    test "u64be packs version in the low 32 bits" do
      assert Mutation.u64be(7) == <<0, 0, 0, 0, 0, 0, 0, 7>>
      assert Mutation.u64be(0x0102_0304) == <<0, 0, 0, 0, 1, 2, 3, 4>>
    end

    test "snapshot/patch MACs are 32 bytes and stable" do
      sk = :crypto.strong_rand_bytes(32)
      pk = :crypto.strong_rand_bytes(32)
      lthash = :crypto.strong_rand_bytes(128)
      snap = Mutation.generate_snapshot_mac(lthash, 3, "regular", sk)
      assert byte_size(snap) == 32
      patch = Mutation.generate_patch_mac(snap, [<<1::256>>, <<2::256>>], 3, "regular", pk)
      assert byte_size(patch) == 32

      assert patch ==
               Mutation.generate_patch_mac(snap, [<<1::256>>, <<2::256>>], 3, "regular", pk)
    end
  end

  describe "Mutation.decrypt_value/2" do
    test "decrypts an AES-256-CBC value we encrypt (iv ++ ciphertext)" do
      key = :crypto.strong_rand_bytes(32)
      iv = :crypto.strong_rand_bytes(16)
      plaintext = "the SyncActionData bytes"
      padded = pkcs7_pad(plaintext)
      ct = :crypto.crypto_one_time(:aes_256_cbc, key, iv, padded, true)

      assert Mutation.decrypt_value(iv <> ct, key) == plaintext
    end
  end

  defp pkcs7_pad(data) do
    pad = 16 - rem(byte_size(data), 16)
    data <> :binary.copy(<<pad>>, pad)
  end
end
