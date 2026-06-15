defmodule Amarula.MsgTest do
  use ExUnit.Case, async: true

  alias Amarula.{Address, Msg}
  alias Amarula.Protocol.Proto

  @chat Address.parse("5511999999999@s.whatsapp.net")

  defp build(proto, meta \\ %{}), do: Msg.from_proto(proto, Map.merge(%{chat: @chat}, meta))

  test "text message" do
    msg = build(%Proto.Message{conversation: "hello"})
    assert msg.type == :text
    assert msg.content == "hello"
    assert msg.chat == @chat
    assert msg.raw.conversation == "hello"
  end

  test "media message exposes kind + struct for download" do
    img = %Proto.Message.ImageMessage{directPath: "/x", mediaKey: <<1>>}
    msg = build(%Proto.Message{imageMessage: img})
    assert msg.type == :media
    assert msg.content == %{kind: :image, media: img}
  end

  test "reaction carries key + emoji" do
    key = %Proto.MessageKey{id: "ABC", remoteJid: "x@s.whatsapp.net"}

    msg =
      build(%Proto.Message{reactionMessage: %Proto.Message.ReactionMessage{key: key, text: "👍"}})

    assert msg.type == :reaction
    assert msg.content == %{key: key, emoji: "👍"}
  end

  test "envelope fields are carried" do
    msg =
      build(%Proto.Message{conversation: "hi"}, %{
        id: "MSGID",
        sender: Address.parse("5511888888888@s.whatsapp.net"),
        from_me: true,
        timestamp: 1_700_000_000
      })

    assert msg.id == "MSGID"
    assert %Address{user: "5511888888888"} = msg.sender
    assert msg.from_me == true
    assert msg.timestamp == 1_700_000_000
  end

  test "from_me defaults to false; raw is always the proto" do
    proto = %Proto.Message{conversation: "x"}
    msg = build(proto)
    assert msg.from_me == false
    assert msg.raw == proto
  end

  test "unknown content type is :other with nil content" do
    msg = build(%Proto.Message{})
    assert msg.type == :other
  end
end
