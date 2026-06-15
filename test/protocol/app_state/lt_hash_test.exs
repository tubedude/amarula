defmodule Amarula.Protocol.AppState.LTHashTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.AppState.LTHash
  alias Amarula.Protocol.Crypto.Crypto

  defp mac(s), do: :crypto.hash(:sha256, s)

  test "zero/0 is 128 zero bytes" do
    assert LTHash.zero() == <<0::1024>>
    assert byte_size(LTHash.zero()) == 128
  end

  test "add then subtract the same mac is identity" do
    m = mac("a")
    h = LTHash.add(LTHash.zero(), [m])
    assert LTHash.subtract(h, [m]) == LTHash.zero()
    refute h == LTHash.zero()
  end

  test "add is commutative (order-independent)" do
    a = mac("a")
    b = mac("b")
    assert LTHash.add(LTHash.zero(), [a, b]) == LTHash.add(LTHash.zero(), [b, a])
  end

  test "subtract_then_add applies subtracts then adds" do
    a = mac("a")
    b = mac("b")
    base = LTHash.add(LTHash.zero(), [a])
    # remove a, add b → same as just adding b to zero
    assert LTHash.subtract_then_add(base, [a], [b]) == LTHash.add(LTHash.zero(), [b])
  end

  test "wraparound: adding the same mac 2^16 times returns to base (mod 2^16)" do
    # Each word is uint16; adding the derived words 65536 times wraps to original.
    m = mac("x")
    derived_once = LTHash.add(LTHash.zero(), [m])
    looped = Enum.reduce(1..65_536, LTHash.zero(), fn _, h -> LTHash.add(h, [m]) end)
    assert looped == LTHash.zero()
    refute derived_once == LTHash.zero()
  end

  test "first word matches the HKDF-derived word added to zero" do
    m = mac("known")
    <<w0::little-16, _::binary>> = Crypto.hkdf(m, 128, <<>>, "WhatsApp Patch Integrity")
    <<got::little-16, _::binary>> = LTHash.add(LTHash.zero(), [m])
    assert got == w0
  end
end
