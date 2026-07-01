defmodule Amarula.Protocol.Binary.DecoderTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Binary.Decoder

  describe "decode/1 basic nodes" do
    test "decodes empty list node" do
      # LIST_EMPTY (0) + LIST_EMPTY (0) + empty string (0)
      binary = <<0, 0, 0>>
      node = Decoder.decode(binary)

      assert node.tag == ""
      assert node.attrs == %{}
      assert node.content == nil
    end

    test "decodes simple node with single byte tag" do
      # LIST_8 (248) + size (1) + tag "iq" (25) + LIST_EMPTY (0)
      binary = <<248, 1, 25, 0>>
      node = Decoder.decode(binary)

      assert node.tag == "iq"
      assert node.attrs == %{}
      assert node.content == nil
    end

    test "decodes node with attributes" do
      # LIST_8 (248) + size (3) + tag "iq" (25) + attr_key "id" (8) + attr_value "1" (0) + LIST_EMPTY (0)
      binary = <<248, 3, 25, 8, 0, 0>>
      node = Decoder.decode(binary)

      assert node.tag == "iq"
      assert node.attrs == %{"id" => ""}
      assert node.content == nil
    end

    test "decodes node with string content" do
      # LIST_8 (248) + size (2) + tag "message" (19) + BINARY_8 (252) + length (5) + "hello"
      binary = <<248, 2, 19, 252, 5, "hello">>
      node = Decoder.decode(binary)

      assert node.tag == "message"
      assert node.attrs == %{}
      assert node.content == "hello"
    end
  end

  describe "decode/1 content types" do
    test "decodes binary content (BINARY_8)" do
      binary = <<248, 2, 19, 252, 4, 1, 2, 3, 4>>
      node = Decoder.decode(binary)

      assert node.content == <<1, 2, 3, 4>>
      assert is_binary(node.content)
    end

    test "decodes binary content (BINARY_20)" do
      # BINARY_20 (253) + 20-bit length 256 encoded as ((len>>16)&0x0F, (len>>8)&0xFF, len&0xFF)
      # = <<0, 1, 0>>. Baileys readInt20 masks the first byte with 0x0F.
      binary = <<248, 2, 19, 253, 0, 1, 0>>
      data = :binary.copy(<<65>>, 256)
      full_binary = binary <> data

      node = Decoder.decode(full_binary)

      assert is_binary(node.content)
      assert byte_size(node.content) == 256
    end

    test "round-trips BINARY_20 content through encoder and decoder" do
      content = :binary.copy(<<7>>, 4096)

      {:ok, encoded} =
        Amarula.Protocol.Binary.Encoder.encode(%Amarula.Protocol.Binary.Node{
          tag: "message",
          attrs: %{},
          content: content
        })

      node = Decoder.decode(encoded)

      assert node.content == content
    end

    # Regression: LIST_16 size was returned as the {value, index} tuple from
    # read_int, raising ArithmeticError. First seen live on the digest IQ
    # result, whose prekey list has >255 children.
    test "round-trips a node with more than 255 children (LIST_16)" do
      children =
        for i <- 1..300 do
          %Amarula.Protocol.Binary.Node{
            tag: "key",
            attrs: %{},
            content: <<i::24>>
          }
        end

      {:ok, encoded} =
        Amarula.Protocol.Binary.Encoder.encode(%Amarula.Protocol.Binary.Node{
          tag: "list",
          attrs: %{},
          content: children
        })

      node = Decoder.decode(encoded)

      assert length(node.content) == 300
      assert Enum.at(node.content, 0).content == <<1::24>>
      assert Enum.at(node.content, 299).content == <<300::24>>
    end

    test "decodes binary content (BINARY_32)" do
      # BINARY_32 (254) + length (0x00000100 = 256)
      binary = <<248, 2, 19, 254, 0, 0, 1, 0>>
      # Add 256 bytes of data
      data = :binary.copy(<<65>>, 256)
      full_binary = binary <> data

      node = Decoder.decode(full_binary)

      assert is_binary(node.content)
      assert byte_size(node.content) == 256
    end

    test "decodes list of nodes (LIST_8)" do
      # Parent: LIST_8 (248) + size (2) + tag "message" (19) + content
      # Content: LIST_8 (248) + size (1) + child_node
      # Child: LIST_8 (248) + size (2) + tag "iq" (25) + LIST_EMPTY (0)
      binary = <<248, 2, 19, 248, 1, 248, 2, 25, 0>>
      node = Decoder.decode(binary)

      assert node.tag == "message"
      assert is_list(node.content)
      assert length(node.content) == 1

      child = Enum.at(node.content, 0)
      assert child.tag == "iq"
      assert child.content == nil
    end

    test "decodes string tokens" do
      # Single byte token "iq" (25)
      binary = <<248, 2, 19, 25>>
      node = Decoder.decode(binary)

      assert node.content == "iq"
    end

    test "decodes JID pairs" do
      # JID_PAIR (250) + user token (14) + server token (3)
      # Token 14 = "user", Token 3 = "s.whatsapp.net" (from SINGLE_BYTE_TOKENS)
      # Structure: LIST_8 (248) + size (2) + tag "message" (19) + JID_PAIR content

      # list_size = 2: 0 attributes + 1 content item = 2 total (even)
      # Structure: LIST_8 + size(2) + tag(19) + JID_PAIR + user_token + server_token
      binary = <<248, 2, 19, 250, 14, 3>>
      node = Decoder.decode(binary)

      assert node.content == "user@s.whatsapp.net"
    end

    test "decodes AD_JID" do
      # AD_JID (247) + domain_type (0) + device (0) + user as BINARY_8 string (252, len 4, "user")
      # device 0 omits the ":0" suffix, matching Baileys jidEncode.
      binary = <<248, 2, 19, 247, 0, 0, 252, 4, "user">>
      node = Decoder.decode(binary)

      assert node.content == "user@s.whatsapp.net"
    end

    test "decodes AD_JID with non-zero device" do
      # AD_JID (247) + domain_type (0) + device (5) + user as BINARY_8 string
      binary = <<248, 2, 19, 247, 0, 5, 252, 4, "user">>
      node = Decoder.decode(binary)

      assert node.content == "user:5@s.whatsapp.net"
    end
  end

  describe "decode/1 error handling" do
    test "handles malformed binary gracefully" do
      # Invalid binary that should cause an error
      assert_raise RuntimeError, fn ->
        Decoder.decode(<<255, 255, 255>>)
      end
    end

    test "handles truncated binary" do
      # Binary that ends mid-frame
      assert_raise RuntimeError, fn ->
        # Missing 10 bytes
        Decoder.decode(<<248, 2, 19, 252, 10>>)
      end
    end

    test "handles empty binary" do
      assert_raise RuntimeError, fn ->
        Decoder.decode(<<>>)
      end
    end
  end

  describe "decode/1 complex scenarios" do
    test "decodes nested nodes with attributes" do
      # Parent: LIST_8 (248) + size (2) + tag "message" (19) + content
      # Content: LIST_8 (248) + size (1) + child_node
      # Child: LIST_8 (248) + size (3) + tag "iq" (25) + attr_key "id" (8) + attr_value "" (0) + LIST_EMPTY (0)
      binary = <<248, 2, 19, 248, 1, 248, 3, 25, 8, 0, 0>>
      node = Decoder.decode(binary)

      assert node.tag == "message"
      assert is_list(node.content)

      child = Enum.at(node.content, 0)
      assert child.tag == "iq"
      assert child.attrs == %{"id" => ""}
    end

    test "decodes multiple attributes" do
      # LIST_8 (248) + size (5) + tag "iq" + attr1_key + attr1_value + attr2_key + attr2_value + LIST_EMPTY (0)
      binary = <<248, 5, 25, 8, 0, 4, 0, 0>>
      node = Decoder.decode(binary)

      assert node.tag == "iq"
      assert node.attrs == %{"id" => "", "type" => ""}
    end

    test "decodes double byte tokens" do
      # DICTIONARY_0 (236) + index (0) for "read-self"
      binary = <<248, 2, 19, 236, 0>>
      node = Decoder.decode(binary)

      assert node.content == "read-self"
    end
  end

  describe "decode/1 edge cases" do
    test "handles zero-length strings" do
      binary = <<248, 2, 19, 252, 0>>
      node = Decoder.decode(binary)

      assert node.content == ""
    end

    test "handles maximum single byte length" do
      # BINARY_8 with length 255
      binary = <<248, 2, 19, 252, 255>>
      data = :binary.copy(<<65>>, 255)
      full_binary = binary <> data

      node = Decoder.decode(full_binary)

      assert byte_size(node.content) == 255
    end

    test "handles invalid list size tag" do
      assert_raise RuntimeError, "invalid tag for list size: 255", fn ->
        Decoder.decode(<<255, 1, 19, 0>>)
      end
    end

    test "handles invalid string tag" do
      # Error message changed from specific "invalid string with tag: X" to generic "invalid node"
      assert_raise RuntimeError, "invalid node", fn ->
        Decoder.decode(<<248, 1, 255, 0>>)
      end
    end

    test "handles truncated LIST_8" do
      assert_raise RuntimeError, fn ->
        # Missing size byte
        Decoder.decode(<<248>>)
      end
    end

    test "handles truncated LIST_16" do
      assert_raise RuntimeError, fn ->
        # Missing second size byte
        Decoder.decode(<<249, 1>>)
      end
    end

    test "handles truncated BINARY_8" do
      assert_raise RuntimeError, fn ->
        # Missing length byte
        Decoder.decode(<<248, 2, 19, 252>>)
      end
    end

    test "handles truncated BINARY_20" do
      assert_raise RuntimeError, fn ->
        # Missing second length byte
        Decoder.decode(<<248, 2, 19, 253, 1>>)
      end
    end

    test "handles truncated BINARY_32" do
      assert_raise RuntimeError, fn ->
        # Missing fourth length byte
        Decoder.decode(<<248, 2, 19, 254, 0, 0, 1>>)
      end
    end

    test "handles truncated JID_PAIR" do
      assert_raise RuntimeError, fn ->
        # Missing server token
        Decoder.decode(<<248, 2, 19, 250, 14>>)
      end
    end

    test "handles truncated DICTIONARY" do
      assert_raise RuntimeError, fn ->
        # Missing index byte
        Decoder.decode(<<248, 2, 19, 236>>)
      end
    end

    test "handles binary with null bytes" do
      binary = <<248, 2, 19, 252, 5, 0, 1, 0, 2, 0>>
      node = Decoder.decode(binary)

      assert node.content == <<0, 1, 0, 2, 0>>
    end

    test "handles attribute names and values" do
      binary = <<248, 3, 19, 252, 4, "name", 252, 5, "value", 0>>
      node = Decoder.decode(binary)

      assert node.tag == "message"
      assert node.attrs == %{"name" => "value"}
    end
  end
end
