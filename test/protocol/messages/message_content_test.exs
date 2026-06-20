defmodule Amarula.Protocol.Messages.MessageContentTest do
  use ExUnit.Case, async: true
  doctest Amarula.Protocol.Messages.MessageContent

  alias Amarula.Protocol.Messages.{MessageContent, MessageEncoder}
  alias Amarula.Protocol.Proto

  @key %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", fromMe: true, id: "ABC"}
  @info %{
    url: "u",
    direct_path: "/d",
    media_key: <<1>>,
    file_sha256: <<2>>,
    file_enc_sha256: <<3>>,
    file_length: 9,
    mimetype: "x"
  }

  test "classifies text (conversation and extendedTextMessage)" do
    assert MessageContent.classify(MessageEncoder.text("hi")) == {:text, "hi"}

    ext = %Proto.Message{extendedTextMessage: %Proto.Message.ExtendedTextMessage{text: "yo"}}
    assert MessageContent.classify(ext) == {:text, "yo"}
  end

  test "classifies a reaction (and a removed reaction)" do
    assert MessageContent.classify(MessageEncoder.reaction(@key, "👍")) == {:reaction, @key, "👍"}
    assert MessageContent.classify(MessageEncoder.reaction(@key, "")) == {:reaction, @key, ""}
  end

  test "classifies edit and revoke" do
    assert MessageContent.classify(MessageEncoder.edit(@key, "new")) == {:edit, @key, "new"}
    assert MessageContent.classify(MessageEncoder.revoke(@key)) == {:revoke, @key}
  end

  test "classifies each media type" do
    for type <- [:image, :video, :audio, :document, :sticker] do
      assert {:media, ^type, _struct} = MessageContent.classify(MessageEncoder.media(type, @info))
    end
  end

  test "unwraps deviceSentMessage and ephemeralMessage" do
    dsm = %Proto.Message{
      deviceSentMessage: %Proto.Message.DeviceSentMessage{
        destinationJid: "x",
        message: MessageEncoder.text("wrapped")
      }
    }

    assert MessageContent.classify(dsm) == {:text, "wrapped"}
  end

  test "other protocol messages and unknown content fall through" do
    pm = %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{type: :APP_STATE_SYNC_KEY_SHARE}
    }

    assert {:protocol, :APP_STATE_SYNC_KEY_SHARE, _} = MessageContent.classify(pm)
    assert {:other, %Proto.Message{}} = MessageContent.classify(%Proto.Message{})
  end

  test "a bare senderKeyDistributionMessage classifies as :sender_key (plumbing)" do
    skdm = %Proto.Message{
      senderKeyDistributionMessage: %Proto.Message.SenderKeyDistributionMessage{
        groupId: "status@broadcast",
        axolotlSenderKeyDistributionMessage: <<1, 2, 3>>
      }
    }

    assert {:sender_key, %{groupId: "status@broadcast"}} = MessageContent.classify(skdm)
  end

  test "SKDM riding along with real content classifies as the content, not :sender_key" do
    msg = %Proto.Message{
      conversation: "hi",
      senderKeyDistributionMessage: %Proto.Message.SenderKeyDistributionMessage{
        groupId: "g@g.us",
        axolotlSenderKeyDistributionMessage: <<1>>
      }
    }

    assert {:text, "hi"} = MessageContent.classify(msg)
  end

  test "classifies contact / contacts / location" do
    contact = %Proto.Message{contactMessage: %Proto.Message.ContactMessage{displayName: "Bob"}}
    assert {:contact, %{displayName: "Bob"}} = MessageContent.classify(contact)

    arr = %Proto.Message{
      contactsArrayMessage: %Proto.Message.ContactsArrayMessage{displayName: "Team"}
    }

    assert {:contacts, %{displayName: "Team"}} = MessageContent.classify(arr)

    loc = %Proto.Message{locationMessage: %Proto.Message.LocationMessage{degreesLatitude: -23.5}}
    assert {:location, %{degreesLatitude: -23.5}} = MessageContent.classify(loc)
  end

  test "classifies poll creation and poll vote" do
    {poll, _} = MessageEncoder.poll("Q", ["A", "B"])
    assert {:poll, %{name: "Q"}} = MessageContent.classify(poll)

    vote = %Proto.Message{pollUpdateMessage: %Proto.Message.PollUpdateMessage{}}
    assert {:poll_vote, %Proto.Message.PollUpdateMessage{}} = MessageContent.classify(vote)
  end

  test "unwraps view-once and classifies the inner media" do
    inner = MessageEncoder.media(:image, @info, [])
    wrapped = %Proto.Message{viewOnceMessage: %Proto.Message.FutureProofMessage{message: inner}}
    assert {:media, :image, _} = MessageContent.classify(wrapped)
  end

  test "classifies a round video note (ptvMessage) as media :video" do
    ptv = MessageEncoder.media(:video, @info, ptv: true)
    assert {:media, :video, _} = MessageContent.classify(ptv)
  end

  test "classifies pin and keep updates with the target key + flag" do
    assert {:pin, %{key: @key, pinned?: true}} =
             MessageContent.classify(MessageEncoder.pin(@key, true))

    assert {:pin, %{pinned?: false}} = MessageContent.classify(MessageEncoder.pin(@key, false))

    assert {:keep, %{key: @key, kept?: true}} =
             MessageContent.classify(MessageEncoder.keep(@key, true))

    assert {:keep, %{kept?: false}} = MessageContent.classify(MessageEncoder.keep(@key, false))
  end

  test "classifies receive-only business/interactive types instead of {:other}" do
    invite = %Proto.Message{groupInviteMessage: %Proto.Message.GroupInviteMessage{}}
    assert {:group_invite, _} = MessageContent.classify(invite)

    event = %Proto.Message{eventMessage: %Proto.Message.EventMessage{}}
    assert {:event, _} = MessageContent.classify(event)

    order = %Proto.Message{orderMessage: %Proto.Message.OrderMessage{}}
    assert {:order, _} = MessageContent.classify(order)

    list = %Proto.Message{listResponseMessage: %Proto.Message.ListResponseMessage{}}
    assert {:list_response, _} = MessageContent.classify(list)
  end

  test "still falls through to {:other} for genuinely unknown content" do
    assert {:other, _} = MessageContent.classify(%Proto.Message{})
  end
end
