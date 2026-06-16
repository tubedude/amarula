defmodule Amarula.MsgTest do
  use ExUnit.Case, async: true

  alias Amarula.{Address, Msg}
  alias Amarula.Protocol.Proto

  @channel Address.parse("5511999999999@s.whatsapp.net")

  defp build(proto, meta \\ %{}), do: Msg.from_proto(proto, Map.merge(%{channel: @channel}, meta))

  test "text message" do
    msg = build(%Proto.Message{conversation: "hello"})
    assert msg.type == :text
    assert msg.content == "hello"
    assert msg.channel == @channel
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

  test "envelope fields are carried (channel/from/to)" do
    msg =
      build(%Proto.Message{conversation: "hi"}, %{
        id: "MSGID",
        from: Address.parse("5511888888888@s.whatsapp.net"),
        to: Address.parse("5511999999999@s.whatsapp.net"),
        from_me: true,
        timestamp: 1_700_000_000
      })

    assert msg.id == "MSGID"
    assert %Address{user: "5511888888888"} = msg.from
    assert %Address{user: "5511999999999"} = msg.to
    assert msg.from_me == true
    assert msg.timestamp == 1_700_000_000
  end

  test "from carries the sending device — the self-send loop signal" do
    # A self-chat send by a linked device (e.g. :29) comes back from_me with the
    # device on `from`; a consumer compares it to Amarula.own_address(conn).device.
    # Fake jid only (no real number).
    msg =
      build(%Proto.Message{conversation: "to myself"}, %{
        from: Address.parse("5511999999999:29@s.whatsapp.net"),
        from_me: true
      })

    assert msg.from.device == 29
    assert msg.from_me == true
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

  test "pass-through classes carry the struct as content" do
    contact = %Proto.Message.ContactMessage{displayName: "Bob"}
    assert %{type: :contact, content: ^contact} = build(%Proto.Message{contactMessage: contact})

    loc = %Proto.Message.LocationMessage{degreesLatitude: 1.0}
    assert %{type: :location, content: ^loc} = build(%Proto.Message{locationMessage: loc})

    poll = %Proto.Message.PollCreationMessage{name: "Q"}
    assert %{type: :poll, content: ^poll} = build(%Proto.Message{pollCreationMessage: poll})
  end

  test "protocol messages surface as {:protocol, %{type, message}}" do
    pm = %Proto.Message.ProtocolMessage{type: :APP_STATE_SYNC_KEY_SHARE}
    msg = build(%Proto.Message{protocolMessage: pm})
    assert msg.type == :protocol
    assert msg.content == %{type: :APP_STATE_SYNC_KEY_SHARE, message: pm}
  end

  describe "quoted replies + mentions" do
    alias Amarula.Protocol.Proto.ContextInfo

    test "a reply surfaces the quoted reference + the inlined original" do
      ctx = %ContextInfo{
        stanzaId: "ORIGID",
        participant: "5511888888888@s.whatsapp.net",
        quotedMessage: %Proto.Message{conversation: "the original"}
      }

      reply =
        build(%Proto.Message{
          extendedTextMessage: %Proto.Message.ExtendedTextMessage{
            text: "my reply",
            contextInfo: ctx
          }
        })

      assert reply.type == :text
      assert reply.content == "my reply"

      assert %{id: "ORIGID", from: %Address{user: "5511888888888"}, message: q} =
               reply.quoted

      # the inlined quoted message is itself a %Msg{}
      assert %Amarula.Msg{type: :text, content: "the original", id: "ORIGID"} = q
    end

    test "a non-reply has quoted: nil" do
      msg = build(%Proto.Message{conversation: "hi"})
      assert msg.quoted == nil
    end

    test "the inlined quoted message is capped at one level (its own quote ignored)" do
      # A quotedMessage that itself carries a contextInfo with a deeper quote.
      deep_ctx = %ContextInfo{
        stanzaId: "DEEP",
        quotedMessage: %Proto.Message{conversation: "deep"}
      }

      ctx = %ContextInfo{
        stanzaId: "ORIG",
        quotedMessage: %Proto.Message{
          extendedTextMessage: %Proto.Message.ExtendedTextMessage{
            text: "mid",
            contextInfo: deep_ctx
          }
        }
      }

      reply =
        build(%Proto.Message{
          extendedTextMessage: %Proto.Message.ExtendedTextMessage{text: "top", contextInfo: ctx}
        })

      assert %Amarula.Msg{content: "mid", quoted: nil} = reply.quoted.message
    end

    test "mentions are parsed to Addresses" do
      ctx = %ContextInfo{
        mentionedJid: ["5511888888888@s.whatsapp.net", "120363@g.us"]
      }

      msg =
        build(%Proto.Message{
          extendedTextMessage: %Proto.Message.ExtendedTextMessage{text: "@x", contextInfo: ctx}
        })

      assert [%Address{user: "5511888888888"}, %Address{kind: :group}] = msg.mentions
    end

    test "quoted on a media reply too (contextInfo lives on the media sub-message)" do
      ctx = %ContextInfo{stanzaId: "QID", quotedMessage: %Proto.Message{conversation: "q"}}

      msg =
        build(%Proto.Message{
          imageMessage: %Proto.Message.ImageMessage{directPath: "/x", contextInfo: ctx}
        })

      assert msg.type == :media
      assert %{id: "QID", message: %Amarula.Msg{content: "q"}} = msg.quoted
    end
  end
end
