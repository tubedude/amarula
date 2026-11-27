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

  test "unwraps lottie-sticker, group-mention, spoiler and audio-sticker envelopes" do
    text = %Proto.Message{conversation: "hidden"}

    for field <- [:lottieStickerMessage, :groupMentionedMessage, :spoilerMessage] do
      wrapped = struct(Proto.Message, [{field, %Proto.Message.FutureProofMessage{message: text}}])
      assert MessageContent.classify(wrapped) == {:text, "hidden"}
    end

    audio = MessageEncoder.media(:audio, @info, [])

    wrapped = %Proto.Message{
      audioStickerMessage: %Proto.Message.FutureProofMessage{message: audio}
    }

    assert {:media, :audio, _} = MessageContent.classify(wrapped)
    assert MessageContent.media_type(wrapped) == "audio"
  end

  test "unwraps documentWithCaptionMessage to the inner document" do
    inner = MessageEncoder.media(:document, @info, caption: "report")

    wrapped = %Proto.Message{
      documentWithCaptionMessage: %Proto.Message.FutureProofMessage{message: inner}
    }

    assert {:media, :document, _} = MessageContent.classify(wrapped)
    assert MessageContent.stanza_type(wrapped) == "media"
    assert MessageContent.media_type(wrapped) == "document"
  end

  describe "view_once?/1" do
    test "true for all three view-once wrappers, false otherwise" do
      wrapper = %Proto.Message.FutureProofMessage{message: %Proto.Message{}}

      assert MessageContent.view_once?(%Proto.Message{viewOnceMessage: wrapper})
      assert MessageContent.view_once?(%Proto.Message{viewOnceMessageV2: wrapper})
      assert MessageContent.view_once?(%Proto.Message{viewOnceMessageV2Extension: wrapper})
      refute MessageContent.view_once?(%Proto.Message{conversation: "hi"})
    end
  end

  describe "stanza_type/1 and stanza_meta/1" do
    test "polls and events get their type and meta attrs" do
      {poll, _secret} = MessageEncoder.poll("Lunch?", ["Yes", "No"], [])
      {multi, _secret} = MessageEncoder.poll("Pick", ["A", "B"], selectable: 0)
      {announce, _secret} = MessageEncoder.poll("News", ["A", "B"], announcement: true)

      ephemeral = %Proto.Message{
        ephemeralMessage: %Proto.Message.FutureProofMessage{message: poll}
      }

      vote = %Proto.Message{pollUpdateMessage: %Proto.Message.PollUpdateMessage{}}
      event = MessageEncoder.event("Party")

      for m <- [poll, multi, announce, ephemeral] do
        assert MessageContent.stanza_type(m) == "poll"
        assert MessageContent.stanza_meta(m) == %{"polltype" => "creation"}
      end

      assert MessageContent.stanza_type(vote) == "poll"
      assert MessageContent.stanza_meta(vote) == %{"polltype" => "vote"}
      assert MessageContent.stanza_type(event) == "event"
      assert MessageContent.stanza_meta(event) == %{"event_type" => "creation"}
    end

    test "reactions, media and text" do
      key = %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", id: "ABC"}
      video = %Proto.Message{videoMessage: %Proto.Message.VideoMessage{}}

      view_once = %Proto.Message{
        viewOnceMessage: %Proto.Message.FutureProofMessage{message: video}
      }

      enc_reaction = %Proto.Message{encReactionMessage: %Proto.Message.EncReactionMessage{}}

      assert MessageContent.stanza_type(MessageEncoder.reaction(key, "👍")) == "reaction"
      assert MessageContent.stanza_type(enc_reaction) == "reaction"
      assert MessageContent.stanza_type(view_once) == "media"
      assert MessageContent.media_type(view_once) == "video"
      assert MessageContent.stanza_type(MessageEncoder.contact("A", "BEGIN:VCARD")) == "media"
      assert MessageContent.stanza_type(%Proto.Message{conversation: "hi"}) == "text"
      assert MessageContent.stanza_meta(%Proto.Message{conversation: "hi"}) == nil
    end
  end

  test "pollResultSnapshotMessageV3 is field 115 (tag bytes 0x9A 0x07)" do
    snapshot = %Proto.Message.PollResultSnapshotMessage{name: "p"}

    assert <<0x9A, 0x07, _::binary>> =
             Proto.Message.encode(%Proto.Message{pollResultSnapshotMessageV3: snapshot})
  end

  describe "media_type/1 (outgoing stanza mediatype, #2435)" do
    test "maps each media message to its wire type" do
      assert MessageContent.media_type(MessageEncoder.media(:image, @info, [])) == "image"
      assert MessageContent.media_type(MessageEncoder.media(:video, @info, [])) == "video"
      assert MessageContent.media_type(MessageEncoder.media(:audio, @info, [])) == "audio"
      assert MessageContent.media_type(MessageEncoder.media(:document, @info, [])) == "document"

      sticker = %Proto.Message{stickerMessage: %Proto.Message.StickerMessage{}}
      assert MessageContent.media_type(sticker) == "sticker"
    end

    test "distinguishes gif and ptt variants" do
      gif = %Proto.Message{videoMessage: %Proto.Message.VideoMessage{gifPlayback: true}}
      assert MessageContent.media_type(gif) == "gif"

      ptt = %Proto.Message{audioMessage: %Proto.Message.AudioMessage{ptt: true}}
      assert MessageContent.media_type(ptt) == "ptt"
    end

    test "sees through a view-once wrapper (the #2678 case)" do
      inner = MessageEncoder.media(:video, @info, [])
      wrapped = %Proto.Message{viewOnceMessage: %Proto.Message.FutureProofMessage{message: inner}}
      assert MessageContent.media_type(wrapped) == "video"
    end

    test "nil for a message that carries no media type" do
      assert MessageContent.media_type(MessageEncoder.text("hi")) == nil
    end
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

  test "message_secret/1 reads the secret off the outer or wrapped message" do
    secret = :crypto.strong_rand_bytes(32)
    info = %Proto.MessageContextInfo{messageSecret: secret}

    assert MessageContent.message_secret(%Proto.Message{messageContextInfo: info}) == secret

    wrapped = %Proto.Message{
      ephemeralMessage: %Proto.Message.FutureProofMessage{
        message: %Proto.Message{conversation: "hi", messageContextInfo: info}
      }
    }

    assert MessageContent.message_secret(wrapped) == secret

    assert MessageContent.message_secret(%Proto.Message{conversation: "hi"}) == nil
    empty = %Proto.Message{messageContextInfo: %Proto.MessageContextInfo{messageSecret: ""}}
    assert MessageContent.message_secret(empty) == nil
  end

  test "secret_envelope/1 finds the envelope plain and wrapped; raw envelopes stay {:other}" do
    env = %Proto.Message.SecretEncryptedMessage{
      targetMessageKey: @key,
      encPayload: <<1, 2, 3>>,
      encIv: <<0::96>>,
      secretEncType: :MESSAGE_EDIT
    }

    plain = %Proto.Message{secretEncryptedMessage: env}
    assert MessageContent.secret_envelope(plain) == env

    wrapped = %Proto.Message{
      ephemeralMessage: %Proto.Message.FutureProofMessage{message: plain}
    }

    assert MessageContent.secret_envelope(wrapped) == env

    assert MessageContent.secret_envelope(%Proto.Message{conversation: "x"}) == nil

    # An envelope that reaches classify undecrypted still falls through.
    assert {:other, _} = MessageContent.classify(plain)
  end

  test "classifies a member-tag change, including removal (empty label, #2502)" do
    set = MessageEncoder.member_label("VIP")
    assert {:member_tag, %{label: "VIP", timestamp: ts}} = MessageContent.classify(set)
    assert is_integer(ts)

    # The #2502 case: removing the tag sends an empty label — still classified,
    # not dropped.
    removed = MessageEncoder.member_label("")
    assert {:member_tag, %{label: ""}} = MessageContent.classify(removed)
  end
end
