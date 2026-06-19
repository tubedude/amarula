defmodule Amarula.AddressTest do
  use ExUnit.Case, async: true

  alias Amarula.Address

  # The empty address, widened back to the full `Address.t()`. The compiler narrows a
  # literal `Address.empty()` to `kind: :none` and warns that the bang variants don't
  # accept it — the contract we want for real callers, but noise where we deliberately
  # test the raising path. The `@spec`'d identity passthrough launders the type without
  # the misdirection of a random pick over a one-element list.
  @spec empty() :: Address.t()
  defp empty, do: widen(Address.empty())

  @spec widen(Address.t()) :: Address.t()
  defp widen(addr), do: addr

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

  describe "to_jid!/1 round-trips with parse" do
    for jid <- ["5511@s.whatsapp.net", "147@lid", "120363@g.us"] do
      test "round-trip #{jid}" do
        assert unquote(jid) |> Address.parse() |> Address.to_jid!() == unquote(jid)
      end
    end

    test "device is preserved" do
      assert "147:94@lid" |> Address.parse() |> Address.to_jid!() == "147:94@lid"
    end
  end

  describe "empty / total wire rendering" do
    test "empty/0 is the :none address; empty? only for it" do
      assert %Address{user: "", kind: :none, device: nil} = Address.empty()
      assert Address.empty?(Address.empty())
      refute Address.empty?(Address.pn("5511"))
      refute Address.pn?(Address.empty())
      refute Address.lid?(Address.empty())
      refute Address.group?(Address.empty())
    end

    test "empty is never same_account? with anything (incl. another empty)" do
      refute Address.same_account?(Address.empty(), Address.empty())
      refute Address.same_account?(Address.empty(), Address.pn("5511"))
      refute Address.same_account?(Address.pn("5511"), Address.empty())
    end

    test "to_jid/1 is total: {:ok, jid} for real, {:error, :no_jid} for empty" do
      assert {:ok, "5511@s.whatsapp.net"} = Address.to_jid(Address.pn("5511"))
      assert {:error, :no_jid} = Address.to_jid(Address.empty())
    end

    test "to_jid!/1 raises on empty, returns the string otherwise" do
      assert Address.to_jid!(Address.pn("5511")) == "5511@s.whatsapp.net"
      assert_raise ArgumentError, fn -> Address.to_jid!(empty()) end
    end

    test "to_wire/1 total; string arm passes through as {:ok, _}" do
      assert {:ok, "5511@s.whatsapp.net"} = Address.to_wire("5511@s.whatsapp.net")
      assert {:ok, "5511@s.whatsapp.net"} = Address.to_wire(Address.pn("5511"))
      assert {:error, :no_jid} = Address.to_wire(Address.empty())
    end

    test "to_wire!/1 bare string; raises on empty" do
      assert Address.to_wire!("5511@s.whatsapp.net") == "5511@s.whatsapp.net"
      assert Address.to_wire!(Address.pn("5511")) == "5511@s.whatsapp.net"
      assert_raise ArgumentError, fn -> Address.to_wire!(empty()) end
    end
  end

  describe "predicates + helpers" do
    test "pn?/lid?/group?" do
      assert Address.pn?(Address.pn("5511"))
      assert Address.lid?(Address.lid("147@lid"))
      assert Address.group?(Address.group("g@g.us"))
      refute Address.pn?(Address.lid("147@lid"))
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

    test "parse!/parse / to_wire accept string or Address" do
      assert %Address{kind: :pn} = Address.parse!("5511@s.whatsapp.net")
      assert Address.parse!(Address.pn("5511")) == Address.pn("5511")
      assert Address.parse(Address.pn("5511")) == Address.pn("5511")
      assert_raise ArgumentError, fn -> Address.parse!("x@newsletter") end
      assert Address.to_wire!("5511@s.whatsapp.net") == "5511@s.whatsapp.net"
      assert Address.to_wire!(Address.pn("5511")) == "5511@s.whatsapp.net"
    end
  end
end
