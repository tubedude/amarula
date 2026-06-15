defmodule Amarula.AddressTest do
  use ExUnit.Case, async: true

  alias Amarula.Address

  describe "constructors accept bare id or full jid" do
    test "pn" do
      assert %Address{user: "5511", kind: :pn, device: nil} = Address.pn("5511")
      assert %Address{user: "5511", kind: :pn} = Address.pn("5511@s.whatsapp.net")
      assert %Address{user: "5511", kind: :pn} = Address.pn("5511:3@s.whatsapp.net")
    end

    test "lid / group" do
      assert %Address{user: "147", kind: :lid} = Address.lid("147@lid")
      assert %Address{user: "120363", kind: :group} = Address.group("120363@g.us")
    end
  end

  describe "parse/1" do
    test "pn / lid / group / device" do
      assert %Address{user: "5511", kind: :pn, device: nil} =
               Address.parse("5511@s.whatsapp.net")

      assert %Address{user: "147", kind: :lid, device: 94} = Address.parse("147:94@lid")
      assert %Address{user: "120363", kind: :group} = Address.parse("120363@g.us")
    end

    test "c.us maps to :pn" do
      assert %Address{kind: :pn} = Address.parse("5511@c.us")
    end

    test "unknown server → nil; passthrough an Address" do
      assert Address.parse("x@newsletter") == nil
      a = Address.pn("5511")
      assert Address.parse(a) == a
    end
  end

  describe "to_jid/1 round-trips with parse" do
    for jid <- ["5511@s.whatsapp.net", "147@lid", "120363@g.us"] do
      test "round-trip #{jid}" do
        assert unquote(jid) |> Address.parse() |> Address.to_jid() == unquote(jid)
      end
    end

    test "device is preserved" do
      assert "147:94@lid" |> Address.parse() |> Address.to_jid() == "147:94@lid"
    end
  end

  describe "predicates + helpers" do
    test "is_pn?/is_lid?/is_group?" do
      assert Address.is_pn?(Address.pn("5511"))
      assert Address.is_lid?(Address.lid("147@lid"))
      assert Address.is_group?(Address.group("g@g.us"))
      refute Address.is_pn?(Address.lid("147@lid"))
    end

    test "normalize strips device" do
      assert %Address{device: nil} = Address.normalize(Address.parse("147:94@lid"))
    end

    test "same_account? ignores device, respects kind" do
      a = Address.parse("147:94@lid")
      b = Address.parse("147:1@lid")
      assert Address.same_account?(a, b)
      refute Address.same_account?(a, Address.pn("147"))
    end

    test "coerce/to_wire accept string or Address" do
      assert %Address{kind: :pn} = Address.coerce("5511@s.whatsapp.net")
      assert Address.coerce(Address.pn("5511")) == Address.pn("5511")
      assert Address.to_wire("5511@s.whatsapp.net") == "5511@s.whatsapp.net"
      assert Address.to_wire(Address.pn("5511")) == "5511@s.whatsapp.net"
    end
  end
end
