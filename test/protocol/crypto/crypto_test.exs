defmodule Amarula.Protocol.Crypto.CryptoTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Crypto.Crypto

  describe "generate_signal_pub_key/1" do
    test "returns key as-is if already 33 bytes" do
      # 33-byte key (with prefix)
      key_33 = <<5>> <> :crypto.strong_rand_bytes(32)
      assert Crypto.generate_signal_pub_key(key_33) == key_33
    end

    test "prefixes 32-byte key with key bundle type" do
      # 32-byte raw key
      key_32 = :crypto.strong_rand_bytes(32)
      result = Crypto.generate_signal_pub_key(key_32)

      assert byte_size(result) == 33
      assert <<5, _rest::binary>> = result
      assert binary_part(result, 1, 32) == key_32
    end

    test "handles unexpected key sizes with warning" do
      # Test with 31-byte key (unexpected size)
      key_31 = :crypto.strong_rand_bytes(31)
      result = Crypto.generate_signal_pub_key(key_31)

      # Should still prefix it
      assert byte_size(result) == 32
      assert <<5, _rest::binary>> = result
    end
  end
end
