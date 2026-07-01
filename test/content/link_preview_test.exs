defmodule Amarula.Content.LinkPreviewTest do
  use ExUnit.Case, async: true

  alias Amarula.Content.LinkPreview
  alias Amarula.Protocol.Proto

  @meta %{
    id: "M",
    channel: Amarula.Address.parse("1@s.whatsapp.net"),
    from: Amarula.Address.parse("1@s.whatsapp.net")
  }

  defp msg(proto), do: Amarula.Msg.from_proto(proto, @meta)

  defp ext_text(fields) do
    %Proto.Message{
      extendedTextMessage: struct(Proto.Message.ExtendedTextMessage, fields)
    }
  end

  describe "on a received %Msg{}" do
    test "a link message stays :text and carries the preview" do
      m =
        msg(
          ext_text(
            text: "check https://example.com",
            matchedText: "https://example.com",
            title: "Example Domain",
            description: "For use in illustrative examples",
            jpegThumbnail: <<255, 216, 255, 0>>,
            previewType: :IMAGE
          )
        )

      assert m.type == :text
      assert m.content == "check https://example.com"

      assert %LinkPreview{
               url: "https://example.com",
               title: "Example Domain",
               description: "For use in illustrative examples",
               thumbnail: <<255, 216, 255, 0>>,
               type: :image
             } = m.preview
    end

    test "a plain conversation text has no preview" do
      m = msg(%Proto.Message{conversation: "hello"})
      assert m.type == :text
      assert m.preview == nil
    end

    test "a plain extendedTextMessage (reply/mention, no link) has no preview" do
      m =
        msg(
          ext_text(
            text: "yes",
            contextInfo: %Proto.ContextInfo{stanzaId: "ABC"}
          )
        )

      assert m.type == :text
      assert m.preview == nil
    end

    test "a non-text message has no preview" do
      m = msg(%Proto.Message{imageMessage: %Proto.Message.ImageMessage{directPath: "/x"}})
      assert m.preview == nil
    end

    test "a preview through a deviceSent wrapper is still surfaced" do
      inner = ext_text(text: "x", matchedText: "https://x.test", title: "X")

      wrapped = %Proto.Message{
        deviceSentMessage: %Proto.Message.DeviceSentMessage{message: inner}
      }

      m = msg(wrapped)
      assert m.type == :text
      assert %LinkPreview{url: "https://x.test", title: "X"} = m.preview
    end
  end

  describe "from_proto/1" do
    test "nil in, nil out" do
      assert LinkPreview.from_proto(nil) == nil
    end

    test "empty strings are treated as absent" do
      ext = %Proto.Message.ExtendedTextMessage{matchedText: "", title: "", description: ""}
      assert LinkPreview.from_proto(ext) == nil
    end

    test "title-only (no url) still counts as a preview" do
      ext = %Proto.Message.ExtendedTextMessage{title: "Just a title"}
      assert %LinkPreview{title: "Just a title", url: nil} = LinkPreview.from_proto(ext)
    end

    test "unknown/absent previewType maps to nil type" do
      ext = %Proto.Message.ExtendedTextMessage{matchedText: "https://a.test"}
      assert %LinkPreview{type: nil} = LinkPreview.from_proto(ext)
    end
  end
end
