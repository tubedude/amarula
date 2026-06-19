defmodule Amarula.Protocol.Binary.JIDTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Binary.JID

  describe "jid_encode/1" do
    test "encodes user and server" do
      assert JID.encode(%{user: "1234", server: "s.whatsapp.net"}) ==
               "1234@s.whatsapp.net"
    end

    test "encodes with default server" do
      assert JID.encode(%{user: "1234"}) == "1234@s.whatsapp.net"
    end

    test "encodes with device" do
      # device 0 emits no suffix (Baileys jidEncode `!!device`)
      assert JID.encode(%{user: "1234", device: 0, server: "s.whatsapp.net"}) ==
               "1234@s.whatsapp.net"

      assert JID.encode(%{user: "1234", device: 3, server: "s.whatsapp.net"}) ==
               "1234:3@s.whatsapp.net"
    end

    test "encodes with agent" do
      assert JID.encode(%{user: "1234", agent: 1, server: "s.whatsapp.net"}) ==
               "1234_1@s.whatsapp.net"
    end

    test "encodes with device and agent" do
      assert JID.encode(%{user: "1234", agent: 1, device: 0, server: "s.whatsapp.net"}) ==
               "1234_1@s.whatsapp.net"

      assert JID.encode(%{user: "1234", agent: 1, device: 2, server: "s.whatsapp.net"}) ==
               "1234_1:2@s.whatsapp.net"
    end

    test "encodes with nil user" do
      assert JID.encode(%{user: nil, server: "s.whatsapp.net"}) == "@s.whatsapp.net"
    end

    test "encodes with numeric user" do
      assert JID.encode(%{user: 1234, server: "s.whatsapp.net"}) == "1234@s.whatsapp.net"
    end
  end

  describe "jid_decode/1" do
    test "decodes basic JID" do
      assert JID.decode("1234@s.whatsapp.net") ==
               %{user: "1234", server: "s.whatsapp.net", domain_type: 0}
    end

    test "decodes JID with device" do
      assert JID.decode("1234:0@s.whatsapp.net") ==
               %{user: "1234", device: 0, server: "s.whatsapp.net", domain_type: 0}
    end

    test "decodes JID with agent" do
      assert JID.decode("1234_1@s.whatsapp.net") ==
               %{user: "1234", server: "s.whatsapp.net", domain_type: 1}
    end

    test "decodes JID with device and agent" do
      assert JID.decode("1234_1:0@s.whatsapp.net") ==
               %{user: "1234", device: 0, server: "s.whatsapp.net", domain_type: 1}
    end

    test "handles invalid JID" do
      assert JID.decode("invalid") == nil
    end

    test "handles nil JID" do
      assert JID.decode(nil) == nil
    end

    test "decodes LID JID" do
      assert JID.decode("1234@lid") ==
               %{user: "1234", server: "lid", domain_type: 1}
    end

    test "decodes hosted JID" do
      assert JID.decode("1234@hosted") ==
               %{user: "1234", server: "hosted", domain_type: 128}
    end

    test "decodes hosted LID JID" do
      assert JID.decode("1234@hosted.lid") ==
               %{user: "1234", server: "hosted.lid", domain_type: 129}
    end
  end

  describe "predicates" do
    test "jid_user?/1 identifies user JIDs" do
      assert JID.jid_user?("1234@s.whatsapp.net") == true
      assert JID.jid_user?("1234@g.us") == false
      assert JID.jid_user?("1234@lid") == true
      assert JID.jid_user?("1234@hosted") == true
    end

    test "jid_group?/1 identifies group JIDs" do
      assert JID.jid_group?("1234@g.us") == true
      assert JID.jid_group?("1234@s.whatsapp.net") == false
    end

    test "lid_user?/1 identifies LID users" do
      assert JID.lid_user?("1234@lid") == true
      assert JID.lid_user?("1234@s.whatsapp.net") == false
    end

    test "jid_broadcast?/1 identifies broadcast JIDs" do
      assert JID.jid_broadcast?("1234@broadcast") == true
      assert JID.jid_broadcast?("1234@s.whatsapp.net") == false
    end

    test "jid_bot?/1 identifies bots" do
      # From TypeScript: /^1313555\d{4}$|^131655500\d{2}$/
      assert JID.jid_bot?("13135551234@c.us") == true
      assert JID.jid_bot?("13165550012@c.us") == true
      assert JID.jid_bot?("1234@c.us") == false
      assert JID.jid_bot?("13135551234@s.whatsapp.net") == false
    end

    test "jid_newsletter?/1 identifies newsletter JIDs" do
      assert JID.jid_newsletter?("1234@newsletter") == true
      assert JID.jid_newsletter?("1234@s.whatsapp.net") == false
    end

    test "hosted_pn_user?/1 identifies hosted PN users" do
      assert JID.hosted_pn_user?("1234@hosted") == true
      assert JID.hosted_pn_user?("1234@s.whatsapp.net") == false
    end

    test "hosted_lid_user?/1 identifies hosted LID users" do
      assert JID.hosted_lid_user?("1234@hosted.lid") == true
      assert JID.hosted_lid_user?("1234@lid") == false
    end

    test "jid_status_broadcast?/1 identifies status broadcast" do
      assert JID.jid_status_broadcast?("status@broadcast") == true
      assert JID.jid_status_broadcast?("1234@broadcast") == false
    end

    test "jid_meta_ai?/1 identifies Meta AI" do
      assert JID.jid_meta_ai?("1234@bot") == true
      assert JID.jid_meta_ai?("1234@s.whatsapp.net") == false
    end
  end

  describe "jid_normalized_user/1" do
    test "normalizes JID to user format" do
      assert JID.jid_normalized_user("1234:0@s.whatsapp.net") ==
               "1234@s.whatsapp.net"
    end

    test "converts c.us to s.whatsapp.net" do
      assert JID.jid_normalized_user("1234@c.us") == "1234@s.whatsapp.net"
    end

    test "handles nil JID" do
      assert JID.jid_normalized_user(nil) == ""
    end

    test "handles invalid JID" do
      assert JID.jid_normalized_user("invalid") == ""
    end
  end

  describe "are_jids_same_user?/2" do
    test "compares two JIDs for same user" do
      assert JID.are_jids_same_user?(
               "1234:0@s.whatsapp.net",
               "1234:1@s.whatsapp.net"
             ) == true
    end

    test "returns false for different users" do
      assert JID.are_jids_same_user?(
               "1234@s.whatsapp.net",
               "5678@s.whatsapp.net"
             ) == false
    end

    test "handles nil JIDs" do
      assert JID.are_jids_same_user?(nil, "1234@s.whatsapp.net") == false
      assert JID.are_jids_same_user?("1234@s.whatsapp.net", nil) == false
      assert JID.are_jids_same_user?(nil, nil) == false
    end
  end

  describe "transfer_device/2" do
    test "transfers device from one JID to another" do
      # device 0 → no suffix; non-zero keeps it
      assert JID.transfer_device("1234:0@s.whatsapp.net", "5678@s.whatsapp.net") ==
               "5678@s.whatsapp.net"

      assert JID.transfer_device("1234:2@s.whatsapp.net", "5678@s.whatsapp.net") ==
               "5678:2@s.whatsapp.net"
    end

    test "uses device 0 (no suffix) when source has no device" do
      assert JID.transfer_device("1234@s.whatsapp.net", "5678@s.whatsapp.net") ==
               "5678@s.whatsapp.net"
    end
  end

  describe "group?/1 alias" do
    test "group?/1 is alias for jid_group?/1" do
      assert JID.group?("1234@g.us") == JID.jid_group?("1234@g.us")
      assert JID.group?("1234@s.whatsapp.net") == JID.jid_group?("1234@s.whatsapp.net")
      assert JID.group?(nil) == JID.jid_group?(nil)
    end
  end

  describe "predicate edge cases" do
    test "predicates handle nil gracefully" do
      assert JID.jid_user?(nil) == false
      assert JID.jid_group?(nil) == false
      assert JID.lid_user?(nil) == false
      assert JID.jid_broadcast?(nil) == false
      assert JID.jid_bot?(nil) == false
      assert JID.jid_newsletter?(nil) == false
      assert JID.hosted_pn_user?(nil) == false
      assert JID.hosted_lid_user?(nil) == false
      assert JID.jid_meta_ai?(nil) == false
    end

    test "predicates handle non-binary input" do
      assert JID.jid_user?(123) == false
      assert JID.jid_group?(%{}) == false
      assert JID.lid_user?([]) == false
    end
  end

  describe "additional device/agent scenarios" do
    test "encodes with device 0" do
      # device 0 emits no `:0` suffix (Baileys jidEncode `!!device`)
      assert JID.encode(%{user: "1234", device: 0, server: "s.whatsapp.net"}) ==
               "1234@s.whatsapp.net"
    end

    test "encodes with agent 0" do
      assert JID.encode(%{user: "1234", agent: 0, server: "s.whatsapp.net"}) ==
               "1234_0@s.whatsapp.net"
    end

    test "encodes with both device and agent 0" do
      # device 0 drops its suffix; agent 0 is kept by the agent+device clause
      assert JID.encode(%{user: "1234", agent: 0, device: 0, server: "s.whatsapp.net"}) ==
               "1234_0@s.whatsapp.net"
    end

    test "decodes JID with agent 0" do
      assert JID.decode("1234_0@s.whatsapp.net") ==
               %{user: "1234", server: "s.whatsapp.net", domain_type: 0}
    end

    test "decodes JID with device and agent 0" do
      assert JID.decode("1234_0:0@s.whatsapp.net") ==
               %{user: "1234", device: 0, server: "s.whatsapp.net", domain_type: 0}
    end
  end

  describe "constants" do
    test "S_WHATSAPP_NET constant" do
      assert JID.s_whatsapp_net() == "@s.whatsapp.net"
    end

    test "OFFICIAL_BIZ_JID constant" do
      assert JID.official_biz_jid() == "16505361212@c.us"
    end

    test "SERVER_JID constant" do
      assert JID.server_jid() == "server@c.us"
    end

    test "PSA_WID constant" do
      assert JID.psa_wid() == "0@c.us"
    end

    test "STORIES_JID constant" do
      assert JID.stories_jid() == "status@broadcast"
    end

    test "META_AI_JID constant" do
      assert JID.meta_ai_jid() == "13135550002@c.us"
    end
  end
end
