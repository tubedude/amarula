defmodule Amarula.Protocol.Binary.EncoderTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Binary.{Encoder, Decoder, Node}

  describe "encode/1 basic nodes" do
    test "encodes empty list node" do
      node = %Node{tag: "", attrs: %{}, content: nil}
      {:ok, binary} = Encoder.encode(node)

      # Should decode back to the same node
      decoded = Decoder.decode(binary)
      assert decoded.tag == ""
      assert decoded.attrs == %{}
      assert decoded.content == nil
    end

    test "encodes node with string tag" do
      node = %Node{tag: "message", attrs: %{}, content: nil}
      {:ok, binary} = Encoder.encode(node)

      decoded = Decoder.decode(binary)
      assert decoded.tag == "message"
      assert decoded.attrs == %{}
      assert decoded.content == nil
    end

    test "encodes node with attributes" do
      node = %Node{tag: "iq", attrs: %{"id" => "1", "type" => "get"}, content: nil}
      {:ok, binary} = Encoder.encode(node)

      decoded = Decoder.decode(binary)
      assert decoded.tag == "iq"
      assert decoded.attrs == %{"id" => "1", "type" => "get"}
      assert decoded.content == nil
    end
  end

  describe "encode/1 content types" do
    test "encodes string content" do
      node = %Node{tag: "message", attrs: %{}, content: "hello"}
      {:ok, binary} = Encoder.encode(node)

      decoded = Decoder.decode(binary)
      assert decoded.content == "hello"
    end

    test "encodes binary content" do
      binary_content = <<1, 2, 3, 4, 5>>
      node = %Node{tag: "message", attrs: %{}, content: binary_content}
      {:ok, binary} = Encoder.encode(node)

      decoded = Decoder.decode(binary)
      assert decoded.content == binary_content
    end

    test "encodes non-UTF-8 protobuf blob content (device-identity)" do
      # Real ADVSignedDeviceIdentity bytes start 0a 12 08 e6 ... which are not valid UTF-8.
      blob = <<10, 18, 8, 230, 206, 149, 253, 11, 16, 186, 224, 166, 209, 6, 24, 1, 32, 0, 40, 0>>

      node = %Node{
        tag: "device-identity",
        attrs: %{"key-index" => "1"},
        content: blob
      }

      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)
      assert decoded.content == blob
    end

    test "encodes JID content" do
      node = %Node{tag: "message", attrs: %{}, content: "user@s.whatsapp.net"}
      {:ok, binary} = Encoder.encode(node)

      decoded = Decoder.decode(binary)
      assert decoded.content == "user@s.whatsapp.net"
    end

    test "encodes double-byte dictionary tokens (e.g. passive IQ)" do
      # "passive" and "active" are double-byte dictionary tokens. Encoding them
      # must emit a DICTIONARY_n marker + index, not crash trying to push a tuple.
      node = %Node{
        tag: "iq",
        attrs: [{"to", "@s.whatsapp.net"}, {"xmlns", "passive"}, {"type", "set"}, {"id", "ab121"}],
        content: [%Node{tag: "active", attrs: %{}, content: nil}]
      }

      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)

      assert decoded.tag == "iq"
      assert decoded.attrs["xmlns"] == "passive"
      assert hd(decoded.content).tag == "active"
    end

    test "encodes list content" do
      child = %Node{tag: "iq", attrs: %{}, content: nil}
      node = %Node{tag: "message", attrs: %{}, content: [child]}
      {:ok, binary} = Encoder.encode(node)

      decoded = Decoder.decode(binary)
      assert is_list(decoded.content)
      assert length(decoded.content) == 1
      assert hd(decoded.content).tag == "iq"
    end
  end

  describe "encode/1 complex scenarios" do
    test "encodes nested nodes with attributes" do
      child = %Node{tag: "iq", attrs: %{"id" => "1"}, content: nil}
      node = %Node{tag: "message", attrs: %{"from" => "user"}, content: [child]}
      {:ok, binary} = Encoder.encode(node)

      decoded = Decoder.decode(binary)
      assert decoded.tag == "message"
      assert decoded.attrs == %{"from" => "user"}
      assert is_list(decoded.content)

      child_decoded = hd(decoded.content)
      assert child_decoded.tag == "iq"
      assert child_decoded.attrs == %{"id" => "1"}
    end
  end

  describe "round-trip encoding/decoding" do
    test "handles empty attributes correctly" do
      node = %Node{tag: "iq", attrs: %{}, content: nil}
      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)

      assert decoded.attrs == %{}
    end

    test "handles nil content correctly" do
      node = %Node{tag: "iq", attrs: %{"id" => "1"}, content: nil}
      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)

      assert decoded.content == nil
    end
  end

  describe "edge cases and error handling" do
    test "handles nil attributes" do
      node = %Node{tag: "message", attrs: nil, content: nil}
      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)

      assert decoded.tag == "message"
      assert decoded.attrs == %{}
      assert decoded.content == nil
    end

    test "handles empty string tag" do
      node = %Node{tag: "", attrs: %{}, content: nil}
      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)

      assert decoded.tag == ""
      assert decoded.attrs == %{}
      assert decoded.content == nil
    end

    test "handles special characters in strings" do
      special_string = "Hello\nWorld\tTest\"Quote'"
      node = %Node{tag: "message", attrs: %{"text" => special_string}, content: nil}
      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)

      assert decoded.attrs["text"] == special_string
    end

    test "handles binary content with null bytes" do
      binary_content = <<1, 0, 2, 0, 3>>
      node = %Node{tag: "message", attrs: %{}, content: binary_content}
      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)

      assert decoded.content == binary_content
    end

    test "handles attributes with numeric values" do
      node = %Node{tag: "message", attrs: %{"id" => "123", "count" => "456"}, content: nil}
      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)

      assert decoded.attrs["id"] == "123"
      assert decoded.attrs["count"] == "456"
    end
  end

  describe "list size handling" do
    test "handles small list sizes" do
      node = %Node{tag: "small", attrs: %{}, content: nil}
      {:ok, binary} = Encoder.encode(node)
      decoded = Decoder.decode(binary)

      assert decoded.tag == "small"
    end

    test "raises on a node list beyond the LIST_16 wire maximum" do
      node = %Node{tag: "x", attrs: %{}, content: List.duplicate(%Node{tag: "k"}, 65_536)}

      assert_raise ArgumentError, ~r/LIST_16 maximum/, fn -> Encoder.encode(node) end
    end
  end

  describe "AD_JID domain types" do
    # Encoder writes and decoder reads the Baileys WAJIDDomains values
    # (WHATSAPP=0, LID=1, HOSTED=128, HOSTED_LID=129) — device jids for every
    # domain must survive the wire round-trip.
    test "device jids round-trip for every domain" do
      for jid <- [
            "1234:5@s.whatsapp.net",
            "1234:5@lid",
            "1234:5@hosted",
            "1234:5@hosted.lid"
          ] do
        node = %Node{tag: "message", attrs: %{"from" => jid}, content: nil}
        {:ok, binary} = Encoder.encode(node)

        assert %{attrs: %{"from" => ^jid}} = Decoder.decode(binary)
      end
    end

    test "a malformed device segment falls back to a raw string, not a crash" do
      node = %Node{tag: "message", attrs: %{"from" => "1234:xx@s.whatsapp.net"}, content: nil}
      {:ok, binary} = Encoder.encode(node)

      assert %{attrs: %{"from" => "1234:xx@s.whatsapp.net"}} = Decoder.decode(binary)
    end
  end
end
