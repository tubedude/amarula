defmodule Amarula.AddressTest do
  use ExUnit.Case, async: true

  # The `@doc` examples are the first thing a consumer copies, and `parse/1`'s now
  # carry the nil-vs-:unsupported distinction (#50) — worth having the suite prove
  # they stay true.
  doctest Amarula.Address

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

  describe "constructors agree with parse/1 on every jid form (#51)" do
    # `parse/1` goes through `JID.decode/1`, which splits `user_agent:device`. The
    # bare constructors go through `user_of/1`. If the two disagree on any form, the
    # SAME jid string yields two Addresses that `same_account?/2` calls different
    # accounts — and that predicate backs `own_account?/2`, `own_chat?/2` and
    # `own_sender?/3` (the spoof gate for self-only protocolMessages).
    test "an agent-suffixed jid strips the agent in both paths" do
      jid = "1234_1@s.whatsapp.net"

      assert %Address{user: "1234", kind: :pn, device: nil} = Address.pn(jid)
      assert Address.pn(jid) == Address.parse(jid)
      assert Address.same_account?(Address.pn(jid), Address.parse(jid))
    end

    test "agent and device together" do
      jid = "1234_1:29@s.whatsapp.net"

      # The constructor is account-level by definition, so it drops the device too;
      # parse/1 keeps it. They must still name the same ACCOUNT.
      assert %Address{user: "1234", device: nil} = Address.pn(jid)
      assert %Address{user: "1234", device: 29} = Address.parse(jid)
      assert Address.same_account?(Address.pn(jid), Address.parse(jid))
    end

    test "an agent-suffixed LID agrees too" do
      jid = "147451226890315_1@lid"

      assert %Address{user: "147451226890315", kind: :lid} = Address.lid(jid)
      assert Address.lid(jid) == Address.parse(jid)
    end

    # Full jids only: the constructors also accept a BARE id ("5511999999999"), but
    # `parse/1` needs a server to determine `kind` and returns nil for one. That's a
    # documented difference in accepted input, not a disagreement about a jid.
    test "every pn/lid/group jid form: constructor == parse (modulo device)" do
      forms = [
        {&Address.pn/1, "5511999999999@s.whatsapp.net"},
        {&Address.pn/1, "5511999999999:29@s.whatsapp.net"},
        {&Address.pn/1, "5511999999999_1@s.whatsapp.net"},
        {&Address.pn/1, "5511999999999_1:29@s.whatsapp.net"},
        {&Address.lid/1, "147451226890315@lid"},
        {&Address.lid/1, "147451226890315:12@lid"},
        {&Address.lid/1, "147451226890315_1@lid"},
        {&Address.group/1, "120363000000000000@g.us"}
      ]

      for {ctor, jid} <- forms do
        built = ctor.(jid)
        parsed = Address.parse(jid)

        assert built.user == parsed.user,
               "user mismatch for #{jid}: constructor #{inspect(built.user)} vs parse #{inspect(parsed.user)}"

        assert built.kind == parsed.kind, "kind mismatch for #{jid}"

        assert Address.same_account?(built, parsed),
               "same_account?/2 false for #{jid}: #{inspect(built)} vs #{inspect(parsed)}"
      end
    end

    test "an underscore-free jid is unaffected" do
      jid = "5511999999999@s.whatsapp.net"
      assert %Address{user: "5511999999999"} = Address.pn(jid)
      assert Address.pn(jid) == Address.parse(jid)
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

    test "unmodelled server → :unsupported; non-jid → nil; passthrough an Address" do
      assert %Address{kind: :unsupported, server: "newsletter", user: "x"} =
               Address.parse("x@newsletter")

      assert Address.parse("not-a-jid") == nil
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

  describe "empty / jid rendering" do
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

    test "to_jid/1: {:ok, jid} for real, {:error, :no_jid} for empty" do
      assert {:ok, "5511@s.whatsapp.net"} = Address.to_jid(Address.pn("5511"))
      assert {:error, :no_jid} = Address.to_jid(Address.empty())
    end

    test "to_jid!/1 raises on empty, returns the string otherwise" do
      assert Address.to_jid!(Address.pn("5511")) == "5511@s.whatsapp.net"
      assert_raise ArgumentError, fn -> Address.to_jid!(empty()) end
    end

    test "to_jid/1: string passes through as {:ok, _}" do
      assert {:ok, "5511@s.whatsapp.net"} = Address.to_jid("5511@s.whatsapp.net")
      assert {:ok, "5511@s.whatsapp.net"} = Address.to_jid(Address.pn("5511"))
      assert {:error, :no_jid} = Address.to_jid(Address.empty())
    end

    test "to_jid!/1 bare string; raises on empty" do
      assert Address.to_jid!("5511@s.whatsapp.net") == "5511@s.whatsapp.net"
      assert Address.to_jid!(Address.pn("5511")) == "5511@s.whatsapp.net"
      assert_raise ArgumentError, fn -> Address.to_jid!(empty()) end
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

    test "parse!/parse / to_jid accept string or Address" do
      assert %Address{kind: :pn} = Address.parse!("5511@s.whatsapp.net")
      assert Address.parse!(Address.pn("5511")) == Address.pn("5511")
      assert Address.parse(Address.pn("5511")) == Address.pn("5511")
      # `parse!/1` raises only on a non-jid now — an unmodelled server IS parseable,
      # it just isn't addressable, and `to_jid!/1` is what refuses it.
      assert_raise ArgumentError, fn -> Address.parse!("not-a-jid") end
      assert_raise ArgumentError, fn -> Address.to_jid!(Address.parse("x@newsletter")) end
      assert Address.to_jid!("5511@s.whatsapp.net") == "5511@s.whatsapp.net"
      assert Address.to_jid!(Address.pn("5511")) == "5511@s.whatsapp.net"
    end
  end
end
