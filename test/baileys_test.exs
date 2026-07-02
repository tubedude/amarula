defmodule Amarula.BaileysTest do
  use ExUnit.Case, async: true
  doctest Amarula.Baileys

  test "parity has all fields" do
    p = Amarula.Baileys.parity()
    # commit is a full git SHA; version is set. (The fields are statically typed
    # binary, so is_binary/1 guards would be provably-true dead checks.)
    assert byte_size(p.commit) == 40
    assert p.version != ""
  end
end
