defmodule Amarula.Protocol.Auth.CompanionRegTest do
  use ExUnit.Case, async: true

  doctest Amarula.Protocol.Auth.CompanionReg

  alias Amarula.Protocol.Auth.CompanionReg

  describe "crockford_encode/1" do
    # Vectors generated from the Baileys bytesToCrockford reference.
    test "matches Baileys vectors for 5-byte inputs" do
      assert CompanionReg.crockford_encode(<<0, 1, 2, 3, 4>>) == "111H51R5"
      assert CompanionReg.crockford_encode(<<255, 255, 255, 255, 255>>) == "ZZZZZZZZ"
      assert CompanionReg.crockford_encode(<<0xDE, 0xAD, 0xBE, 0xEF, 0x42>>) == "VTPVXVT3"
    end

    test "left-pads a trailing partial group (3-byte input)" do
      assert CompanionReg.crockford_encode(<<0xDE, 0xAD, 0xBE>>) == "VTPVW"
    end

    test "5 random bytes always yield an 8-char code" do
      for _ <- 1..50 do
        code = CompanionReg.crockford_encode(:crypto.strong_rand_bytes(5))
        assert byte_size(code) == 8
        assert code =~ ~r/^[123456789ABCDEFGHJKLMNPQRSTVWXYZ]{8}$/
      end
    end
  end
end
