defmodule Amarula.Protocol.Binary.ConstantsTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Binary.Constants

  describe "TAGS constants" do
    test "LIST_EMPTY is 0" do
      assert Constants.tag(:list_empty) == 0
    end

    test "DICTIONARY_0 is 236" do
      assert Constants.tag(:dictionary_0) == 236
    end

    test "DICTIONARY_1 is 237" do
      assert Constants.tag(:dictionary_1) == 237
    end

    test "DICTIONARY_2 is 238" do
      assert Constants.tag(:dictionary_2) == 238
    end

    test "DICTIONARY_3 is 239" do
      assert Constants.tag(:dictionary_3) == 239
    end

    test "INTEROP_JID is 245" do
      assert Constants.tag(:interop_jid) == 245
    end

    test "FB_JID is 246" do
      assert Constants.tag(:fb_jid) == 246
    end

    test "AD_JID is 247" do
      assert Constants.tag(:ad_jid) == 247
    end

    test "LIST_8 is 248" do
      assert Constants.tag(:list_8) == 248
    end

    test "LIST_16 is 249" do
      assert Constants.tag(:list_16) == 249
    end

    test "JID_PAIR is 250" do
      assert Constants.tag(:jid_pair) == 250
    end

    test "HEX_8 is 251" do
      assert Constants.tag(:hex_8) == 251
    end

    test "BINARY_8 is 252" do
      assert Constants.tag(:binary_8) == 252
    end

    test "BINARY_20 is 253" do
      assert Constants.tag(:binary_20) == 253
    end

    test "BINARY_32 is 254" do
      assert Constants.tag(:binary_32) == 254
    end

    test "NIBBLE_8 is 255" do
      assert Constants.tag(:nibble_8) == 255
    end

    test "PACKED_MAX is 127" do
      assert Constants.tag(:packed_max) == 127
    end
  end

  describe "string_to_tag/1" do
    test "converts single byte tokens" do
      assert Constants.string_to_tag("") == 0
      assert Constants.string_to_tag("xmlstreamstart") == 1
      assert Constants.string_to_tag("xmlstreamend") == 2
      assert Constants.string_to_tag("s.whatsapp.net") == 3
      assert Constants.string_to_tag("type") == 4
      assert Constants.string_to_tag("participant") == 5
      assert Constants.string_to_tag("from") == 6
      assert Constants.string_to_tag("receipt") == 7
      assert Constants.string_to_tag("id") == 8
      assert Constants.string_to_tag("notification") == 9
      assert Constants.string_to_tag("iq") == 25
      assert Constants.string_to_tag("g.us") == 28
    end

    test "converts double byte tokens" do
      assert Constants.string_to_tag("read-self") == {0, 0}
      assert Constants.string_to_tag("active") == {0, 1}
      assert Constants.string_to_tag("fbns") == {0, 2}
      assert Constants.string_to_tag("protocol") == {0, 3}
      assert Constants.string_to_tag("reaction") == {0, 4}
    end

    test "returns nil for unknown tokens" do
      assert Constants.string_to_tag("unknown_token") == nil
    end
  end

  describe "tag_to_string/1" do
    test "converts single byte tags to strings" do
      assert Constants.tag_to_string(0) == ""
      assert Constants.tag_to_string(1) == "xmlstreamstart"
      assert Constants.tag_to_string(2) == "xmlstreamend"
      assert Constants.tag_to_string(3) == "s.whatsapp.net"
      assert Constants.tag_to_string(25) == "iq"
      assert Constants.tag_to_string(28) == "g.us"
    end

    test "converts double byte tags to strings" do
      assert Constants.tag_to_string({0, 0}) == "read-self"
      assert Constants.tag_to_string({0, 1}) == "active"
      assert Constants.tag_to_string({0, 2}) == "fbns"
      assert Constants.tag_to_string({0, 3}) == "protocol"
      assert Constants.tag_to_string({0, 4}) == "reaction"
    end

    test "returns nil for unknown tags" do
      assert Constants.tag_to_string(999) == nil
      assert Constants.tag_to_string({999, 999}) == nil
    end
  end

  describe "token_to_string/1" do
    test "converts single byte token indices" do
      assert Constants.token_to_string(0) == ""
      assert Constants.token_to_string(1) == "xmlstreamstart"
      assert Constants.token_to_string(2) == "xmlstreamend"
      assert Constants.token_to_string(3) == "s.whatsapp.net"
    end

    test "returns nil for invalid indices" do
      assert Constants.token_to_string(-1) == nil
      assert Constants.token_to_string(999) == nil
    end
  end

  describe "string_to_token/1" do
    test "converts strings to token indices" do
      assert Constants.string_to_token("") == 0
      assert Constants.string_to_token("xmlstreamstart") == 1
      assert Constants.string_to_token("xmlstreamend") == 2
      assert Constants.string_to_token("s.whatsapp.net") == 3
    end

    test "returns nil for unknown strings" do
      # "unknown" is now a valid token in the list, so test with a truly unknown string
      assert Constants.string_to_token("this_is_not_a_token_12345") == nil
    end
  end

  describe "single_byte_token?/1" do
    test "identifies single byte tokens" do
      assert Constants.single_byte_token?("") == true
      assert Constants.single_byte_token?("xmlstreamstart") == true
      assert Constants.single_byte_token?("iq") == true
    end

    test "identifies double byte tokens as false" do
      assert Constants.single_byte_token?("read-self") == false
      assert Constants.single_byte_token?("active") == false
    end

    test "returns false for unknown tokens" do
      # "unknown" is now a valid token in the list, so test with a truly unknown string
      assert Constants.single_byte_token?("this_is_not_a_token_12345") == false
    end
  end

  describe "double_byte_token?/1" do
    test "identifies double byte tokens" do
      assert Constants.double_byte_token?("read-self") == true
      assert Constants.double_byte_token?("active") == true
      assert Constants.double_byte_token?("fbns") == true
    end

    test "identifies single byte tokens as false" do
      assert Constants.double_byte_token?("") == false
      assert Constants.double_byte_token?("xmlstreamstart") == false
      assert Constants.double_byte_token?("iq") == false
    end

    test "returns false for unknown tokens" do
      assert Constants.double_byte_token?("unknown") == false
    end
  end
end
