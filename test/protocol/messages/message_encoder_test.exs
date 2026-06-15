defmodule Amarula.Protocol.Messages.MessageEncoderTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Messages.MessageEncoder
  alias Amarula.Protocol.Proto

  describe "text/1" do
    test "builds a conversation message" do
      assert %Proto.Message{conversation: "hi"} = MessageEncoder.text("hi")
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
