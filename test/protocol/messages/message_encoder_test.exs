defmodule Amarula.Protocol.Messages.MessageEncoderTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Messages.MessageEncoder
  alias Amarula.Protocol.Proto

  # A received message to reply to, built through the real constructor.
  defp inbound_msg do
    proto = %Proto.Message{conversation: "original"}

    Amarula.Msg.from_proto(proto, %{
      id: "ORIG1",
      channel: Amarula.Address.parse("g@g.us"),
      from: Amarula.Address.parse("1@s.whatsapp.net")
    })
  end

  defp media_info do
    %{
      url: "u",
      direct_path: "d",
      media_key: "k",
      file_sha256: "s",
      file_enc_sha256: "e",
      file_length: 1,
      mimetype: "image/jpeg"
    }
  end

  describe "text/1" do
    test "builds a conversation message" do
      assert %Proto.Message{conversation: "hi"} = MessageEncoder.text("hi")
    end
  end

  describe "event/2" do
    test "builds an eventMessage with name + optional fields" do
      msg =
        MessageEncoder.event("Launch",
          description: "v1.0",
          join_link: "https://call",
          start_time: 1_700_000_000,
          end_time: 1_700_003_600,
          extra_guests_allowed: true
        )

      ev = msg.eventMessage
      assert ev.name == "Launch"
      assert ev.description == "v1.0"
      assert ev.joinLink == "https://call"
      assert ev.startTime == 1_700_000_000
      assert ev.endTime == 1_700_003_600
      assert ev.extraGuestsAllowed == true
    end

    test "location as a {lat, lng} tuple builds a LocationMessage" do
      msg = MessageEncoder.event("Picnic", location: {1.5, 2.5})
      assert msg.eventMessage.location.degreesLatitude == 1.5
      assert msg.eventMessage.location.degreesLongitude == 2.5
    end

    test "location as a keyword carries name/address" do
      msg = MessageEncoder.event("Picnic", location: [lat: 1.0, lng: 2.0, name: "Park"])
      assert msg.eventMessage.location.name == "Park"
    end

    test "no location → nil" do
      assert MessageEncoder.event("Bare").eventMessage.location == nil
    end

    test "round-trips through classify as {:event, _}" do
      assert {:event, %Proto.Message.EventMessage{name: "X"}} =
               Amarula.Protocol.Messages.MessageContent.classify(MessageEncoder.event("X"))
    end
  end

  describe "group_invite/3" do
    test "builds a groupInviteMessage with code + optional fields" do
      msg =
        MessageEncoder.group_invite("123@g.us", "ABCD1234",
          group_name: "Team",
          caption: "join us",
          expiration: 1_700_000_000
        )

      gi = msg.groupInviteMessage
      assert gi.groupJid == "123@g.us"
      assert gi.inviteCode == "ABCD1234"
      assert gi.groupName == "Team"
      assert gi.caption == "join us"
      assert gi.inviteExpiration == 1_700_000_000
    end

    test "round-trips through classify as {:group_invite, _}" do
      msg = MessageEncoder.group_invite("123@g.us", "ABCD1234")

      assert {:group_invite, %Proto.Message.GroupInviteMessage{inviteCode: "ABCD1234"}} =
               Amarula.Protocol.Messages.MessageContent.classify(msg)
    end
  end

  describe "media view-once + ptv" do
    test "view_once wraps the whole message in viewOnceMessage" do
      msg = MessageEncoder.media(:image, media_info(), view_once: true)

      assert msg.imageMessage == nil
      assert %Proto.Message.FutureProofMessage{message: inner} = msg.viewOnceMessage
      assert inner.imageMessage.url == "u"
    end

    test "ptv relocates the videoMessage to ptvMessage" do
      msg = MessageEncoder.media(:video, media_info(), ptv: true)

      assert msg.videoMessage == nil
      assert msg.ptvMessage.url == "u"
    end

    test "ptv is ignored for non-video types" do
      msg = MessageEncoder.media(:image, media_info(), ptv: true)
      assert msg.imageMessage.url == "u"
      assert msg.ptvMessage == nil
    end

    test "view_once + ptv compose (round note, openable once)" do
      msg = MessageEncoder.media(:video, media_info(), ptv: true, view_once: true)
      assert msg.viewOnceMessage.message.ptvMessage.url == "u"
    end
  end

  describe "pin/2 and keep/2" do
    setup do
      {:ok, key: %Proto.MessageKey{remoteJid: "g@g.us", id: "ABC"}}
    end

    test "pin → PIN_FOR_ALL with key + timestamp", %{key: key} do
      msg = MessageEncoder.pin(key, true)
      assert msg.pinInChatMessage.type == :PIN_FOR_ALL
      assert msg.pinInChatMessage.key == key
      assert is_integer(msg.pinInChatMessage.senderTimestampMs)
    end

    test "unpin → UNPIN_FOR_ALL", %{key: key} do
      assert MessageEncoder.pin(key, false).pinInChatMessage.type == :UNPIN_FOR_ALL
    end

    test "keep → KEEP_FOR_ALL, undo → UNDO_KEEP_FOR_ALL", %{key: key} do
      assert MessageEncoder.keep(key, true).keepInChatMessage.keepType == :KEEP_FOR_ALL
      assert MessageEncoder.keep(key, false).keepInChatMessage.keepType == :UNDO_KEEP_FOR_ALL
    end
  end

  describe "context_info/1 (reply + mentions)" do
    test "no quoted/mentions → nil (message stays a plain conversation)" do
      assert MessageEncoder.context_info([]) == nil
      assert %Proto.Message{conversation: "hi"} = MessageEncoder.text("hi", [])
    end

    test "quoted builds stanzaId + participant + inlined quotedMessage" do
      msg = inbound_msg()
      ctx = MessageEncoder.context_info(quoted: msg)

      assert ctx.stanzaId == "ORIG1"
      assert ctx.participant == "1@s.whatsapp.net"
      assert ctx.quotedMessage == msg.raw
    end

    test "mentions map to mentionedJid (jids or Address)" do
      ctx =
        MessageEncoder.context_info(
          mentions: ["2@s.whatsapp.net", Amarula.Address.parse("3@s.whatsapp.net")]
        )

      assert ctx.mentionedJid == ["2@s.whatsapp.net", "3@s.whatsapp.net"]
      assert ctx.stanzaId == nil
    end

    test "a reply switches text to extendedTextMessage carrying the contextInfo" do
      msg = MessageEncoder.text("yes!", quoted: inbound_msg())

      assert msg.conversation == nil
      assert msg.extendedTextMessage.text == "yes!"
      assert msg.extendedTextMessage.contextInfo.stanzaId == "ORIG1"
    end

    test "mentions alone also switch to extendedTextMessage" do
      msg = MessageEncoder.text("hi @x", mentions: ["2@s.whatsapp.net"])
      assert msg.extendedTextMessage.contextInfo.mentionedJid == ["2@s.whatsapp.net"]
    end

    test "context attaches to the media submessage, not the top level" do
      msg = MessageEncoder.media(:image, media_info(), quoted: inbound_msg())

      assert msg.imageMessage.contextInfo.stanzaId == "ORIG1"
      # round-trips through the proto encoder without raising
      assert is_binary(MessageEncoder.encode(msg))
    end
  end

  describe "reaction/2" do
    setup do
      {:ok, key: %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", fromMe: false, id: "ABC"}}
    end

    test "builds a reaction carrying the target key, emoji and timestamp", %{key: key} do
      msg = MessageEncoder.reaction(key, "👍")

      assert msg.reactionMessage.text == "👍"
      assert msg.reactionMessage.key == key
      assert is_integer(msg.reactionMessage.senderTimestampMs)
    end

    test "empty emoji removes a reaction", %{key: key} do
      assert MessageEncoder.reaction(key, "").reactionMessage.text == ""
    end
  end

  describe "revoke/1" do
    test "builds a REVOKE protocolMessage carrying the target key" do
      key = %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", fromMe: true, id: "ABC"}
      msg = MessageEncoder.revoke(key)

      assert msg.protocolMessage.type == :REVOKE
      assert msg.protocolMessage.key == key
    end

    test "round-trips through encode" do
      key = %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", id: "ABC"}
      encoded = key |> MessageEncoder.revoke() |> MessageEncoder.encode()
      pad = :binary.last(encoded)
      decoded = Proto.Message.decode(:binary.part(encoded, 0, byte_size(encoded) - pad))

      assert decoded.protocolMessage.type == :REVOKE
      assert decoded.protocolMessage.key.id == "ABC"
    end
  end

  describe "history_sync_on_demand_request/3" do
    setup do
      {:ok, key: %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", fromMe: false, id: "ABC"}}
    end

    test "builds a PEER_DATA_OPERATION on-demand history request", %{key: key} do
      msg = MessageEncoder.history_sync_on_demand_request(key, 1_700_000_000_000, 50)

      assert msg.protocolMessage.type == :PEER_DATA_OPERATION_REQUEST_MESSAGE

      pdo = msg.protocolMessage.peerDataOperationRequestMessage
      assert pdo.peerDataOperationRequestType == :HISTORY_SYNC_ON_DEMAND

      req = pdo.historySyncOnDemandRequest
      assert req.chatJid == "x@s.whatsapp.net"
      assert req.oldestMsgFromMe == false
      assert req.oldestMsgId == "ABC"
      assert req.oldestMsgTimestampMs == 1_700_000_000_000
      assert req.onDemandMsgCount == 50
    end

    test "round-trips through encode", %{key: key} do
      encoded =
        key
        |> MessageEncoder.history_sync_on_demand_request(1_700_000_000_000, 50)
        |> MessageEncoder.encode()

      pad = :binary.last(encoded)
      decoded = Proto.Message.decode(:binary.part(encoded, 0, byte_size(encoded) - pad))

      assert decoded.protocolMessage.type == :PEER_DATA_OPERATION_REQUEST_MESSAGE
      req = decoded.protocolMessage.peerDataOperationRequestMessage.historySyncOnDemandRequest
      assert req.chatJid == "x@s.whatsapp.net"
      assert req.oldestMsgId == "ABC"
      assert req.oldestMsgTimestampMs == 1_700_000_000_000
      assert req.onDemandMsgCount == 50
    end
  end

  describe "edit/2" do
    test "builds a MESSAGE_EDIT protocolMessage with the new text" do
      key = %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", fromMe: true, id: "ABC"}
      msg = MessageEncoder.edit(key, "fixed typo")

      assert msg.protocolMessage.type == :MESSAGE_EDIT
      assert msg.protocolMessage.key == key
      assert msg.protocolMessage.editedMessage.conversation == "fixed typo"
      assert is_integer(msg.protocolMessage.timestampMs)
    end

    test "round-trips through encode" do
      key = %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", id: "ABC"}
      encoded = key |> MessageEncoder.edit("v2") |> MessageEncoder.encode()
      pad = :binary.last(encoded)
      decoded = Proto.Message.decode(:binary.part(encoded, 0, byte_size(encoded) - pad))

      assert decoded.protocolMessage.type == :MESSAGE_EDIT
      assert decoded.protocolMessage.editedMessage.conversation == "v2"
    end
  end

  describe "media/3" do
    @info %{
      url: "https://x/y",
      direct_path: "/v/abc",
      media_key: <<1, 2, 3>>,
      file_sha256: <<4>>,
      file_enc_sha256: <<5>>,
      file_length: 1234,
      mimetype: "image/jpeg"
    }

    test "image carries common fields + caption/width/height" do
      m = MessageEncoder.media(:image, @info, caption: "hi", width: 10, height: 20)
      img = m.imageMessage

      assert img.url == "https://x/y"
      assert img.directPath == "/v/abc"
      assert img.mediaKey == <<1, 2, 3>>
      assert img.fileEncSha256 == <<5>>
      assert img.fileLength == 1234
      assert img.caption == "hi"
      assert {img.width, img.height} == {10, 20}
    end

    test "each type maps to its own proto field" do
      assert MessageEncoder.media(:video, @info, seconds: 3).videoMessage.seconds == 3
      assert MessageEncoder.media(:audio, @info, ptt: true).audioMessage.ptt == true
      assert MessageEncoder.media(:document, @info, title: "t").documentMessage.title == "t"
      assert MessageEncoder.media(:sticker, @info).stickerMessage.url == "https://x/y"
    end

    test "image/2 is media(:image, ...)" do
      assert MessageEncoder.image(@info).imageMessage.url == "https://x/y"
    end
  end

  describe "encode/1" do
    test "round-trips a reaction through proto encode + random pad" do
      key = %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", id: "ABC"}
      encoded = key |> then(&MessageEncoder.reaction(&1, "❤️")) |> MessageEncoder.encode()

      # last byte is the pad length (1..16); strip it and decode the proto
      pad = :binary.last(encoded)
      assert pad in 1..16
      payload = :binary.part(encoded, 0, byte_size(encoded) - pad)

      decoded = Proto.Message.decode(payload)
      assert decoded.reactionMessage.text == "❤️"
      assert decoded.reactionMessage.key.id == "ABC"
    end
  end

  describe "contact/2 and contacts/2" do
    test "single contact" do
      assert %Proto.Message{contactMessage: %{displayName: "Bob", vcard: "BEGIN:VCARD"}} =
               MessageEncoder.contact("Bob", "BEGIN:VCARD")
    end

    test "contacts array" do
      msg = MessageEncoder.contacts("Team", [{"A", "vcA"}, {"B", "vcB"}])
      assert msg.contactsArrayMessage.displayName == "Team"
      assert Enum.map(msg.contactsArrayMessage.contacts, & &1.displayName) == ["A", "B"]
    end
  end

  describe "location/3" do
    test "lat/lng + opts" do
      msg = MessageEncoder.location(-23.5, -46.6, name: "SP", is_live: true)
      assert msg.locationMessage.degreesLatitude == -23.5
      assert msg.locationMessage.degreesLongitude == -46.6
      assert msg.locationMessage.name == "SP"
      assert msg.locationMessage.isLive == true
    end

    test "rejects non-float coordinates" do
      assert_raise FunctionClauseError, fn -> MessageEncoder.location(1, 2) end
    end
  end
end
