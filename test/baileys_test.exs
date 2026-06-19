defmodule Amarula.BaileysTest do
  use ExUnit.Case, async: true
  doctest Amarula.Baileys

  test "parity has all fields" do
    p = Amarula.Baileys.parity()
    assert is_binary(p.commit) and byte_size(p.commit) == 40
    assert is_binary(p.version)
  end
end
