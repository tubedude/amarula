defmodule Amarula.Protocol.Signal.CryptoHelpersTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.CryptoHelpers

  # Vectors generated with node_modules/libsignal/src/crypto.js — see
  # test/fixtures/sig_crypto_vecs.json. Cross-checks derive_secrets/calculate_mac/
  # aes_cbc_decrypt against the exact implementation Baileys runs.
  @vectors "test/fixtures/sig_crypto_vecs.json"
           |> File.read!()
           |> JSON.decode!()

  defp h(hex), do: Base.decode16!(hex, case: :lower)

  describe "derive_secrets/4 (HKDF-SHA256)" do
    test "matches libsignal deriveSecrets for 1..3 chunks" do
      for v <- @vectors["derive"] do
        out = CryptoHelpers.derive_secrets(h(v["input"]), h(v["salt"]), h(v["info"]), v["chunks"])
        expected = Enum.map(v["out"], &h/1)

        assert out == expected
        assert length(out) == v["chunks"]
        assert Enum.all?(out, &(byte_size(&1) == 32))
      end
    end

    test "rejects salt that is not 32 bytes" do
      assert_raise FunctionClauseError, fn ->
        CryptoHelpers.derive_secrets(<<1, 2, 3>>, <<0::8*16>>, <<>>, 1)
      end
    end
  end

  describe "calculate_mac/2" do
    test "matches libsignal calculateMAC" do
      m = @vectors["mac"]
      assert CryptoHelpers.calculate_mac(h(m["key"]), h(m["data"])) == h(m["mac"])
    end
  end

  describe "verify_mac/4" do
    test "accepts the correct truncated MAC" do
      m = @vectors["mac"]

      assert CryptoHelpers.verify_mac(
               h(m["data"]),
               h(m["key"]),
               binary_part(h(m["mac"]), 0, 8),
               8
             ) == :ok
    end

    test "raises on a wrong MAC" do
      m = @vectors["mac"]
      bad = :binary.copy(<<0>>, 8)

      assert_raise RuntimeError, "Bad MAC", fn ->
        CryptoHelpers.verify_mac(h(m["data"]), h(m["key"]), bad, 8)
      end
    end

    test "raises on wrong MAC length" do
      m = @vectors["mac"]

      assert_raise RuntimeError, "Bad MAC length", fn ->
        CryptoHelpers.verify_mac(h(m["data"]), h(m["key"]), <<0, 1, 2>>, 8)
      end
    end
  end

  describe "aes_cbc_decrypt/3" do
    test "decrypts a libsignal AES-256-CBC ciphertext back to plaintext" do
      c = @vectors["cbc"]
      assert CryptoHelpers.aes_cbc_decrypt(h(c["key"]), h(c["ct"]), h(c["iv"])) == h(c["pt"])
    end
  end
end
