defmodule Amarula.Protocol.Signal.LIDMappingTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Amarula.Protocol.Signal.LIDMapping

  describe "new/2" do
    test "creates a new LID mapping" do
      mapping = LIDMapping.new("1234567890@s.whatsapp.net", "lid123@lid")

      assert mapping.pn == "1234567890@s.whatsapp.net"
      assert mapping.lid == "lid123@lid"
    end
  end

  describe "pn_user?/1" do
    test "returns true for phone number users" do
      assert LIDMapping.pn_user?("1234567890@s.whatsapp.net")
      assert LIDMapping.pn_user?("1234567890:1@s.whatsapp.net")
      assert LIDMapping.pn_user?("1234567890@hosted")
    end

    test "returns false for non-phone number users" do
      refute LIDMapping.pn_user?("lid123@lid")
      refute LIDMapping.pn_user?("group123@g.us")
      refute LIDMapping.pn_user?("invalid")
    end
  end

  describe "hosted_pn_user?/1" do
    test "returns true for hosted phone number users" do
      assert LIDMapping.hosted_pn_user?("1234567890@hosted")
      assert LIDMapping.hosted_pn_user?("1234567890:1@hosted")
    end

    test "returns false for non-hosted users" do
      refute LIDMapping.hosted_pn_user?("1234567890@s.whatsapp.net")
      refute LIDMapping.hosted_pn_user?("lid123@lid")
    end
  end

  describe "lid_user?/1" do
    test "returns true for LID users" do
      assert LIDMapping.lid_user?("lid123@lid")
      assert LIDMapping.lid_user?("lid123:1@lid")
      assert LIDMapping.lid_user?("lid123@hosted.lid")
    end

    test "returns false for non-LID users" do
      refute LIDMapping.lid_user?("1234567890@s.whatsapp.net")
      refute LIDMapping.lid_user?("group123@g.us")
    end
  end

  describe "normalize_user/1" do
    test "extracts user part from JID" do
      assert LIDMapping.normalize_user("1234567890@s.whatsapp.net") == "1234567890"
      assert LIDMapping.normalize_user("lid123@lid") == "lid123"
      assert LIDMapping.normalize_user("user:1@domain") == "user:1"
    end

    test "returns original string if no @ found" do
      assert LIDMapping.normalize_user("invalid") == "invalid"
    end
  end

  describe "decode_jid/1" do
    test "decodes simple JID" do
      assert {:ok, decoded} = LIDMapping.decode_jid("1234567890@s.whatsapp.net")
      assert decoded.user == "1234567890"
      assert decoded.device == 0
      assert decoded.domain == "s.whatsapp.net"
    end

    test "decodes JID with device" do
      assert {:ok, decoded} = LIDMapping.decode_jid("1234567890:1@s.whatsapp.net")
      assert decoded.user == "1234567890"
      assert decoded.device == 1
      assert decoded.domain == "s.whatsapp.net"
    end

    test "decodes LID JID" do
      assert {:ok, decoded} = LIDMapping.decode_jid("lid123@lid")
      assert decoded.user == "lid123"
      assert decoded.device == 0
      assert decoded.domain == "lid"
    end

    test "returns error for invalid JID format" do
      assert {:error, _} = LIDMapping.decode_jid("invalid")
      assert {:error, _} = LIDMapping.decode_jid("user:invalid@s.whatsapp.net")
    end
  end

  describe "construct_device_jid/3" do
    test "constructs JID without device" do
      assert LIDMapping.construct_device_jid("1234567890", 0, "s.whatsapp.net") ==
               "1234567890@s.whatsapp.net"
    end

    test "constructs JID with device" do
      assert LIDMapping.construct_device_jid("1234567890", 1, "s.whatsapp.net") ==
               "1234567890:1@s.whatsapp.net"
    end

    test "constructs LID JID" do
      assert LIDMapping.construct_device_jid("lid123", 0, "lid") == "lid123@lid"
      assert LIDMapping.construct_device_jid("lid123", 1, "lid") == "lid123:1@lid"
    end
  end
end
