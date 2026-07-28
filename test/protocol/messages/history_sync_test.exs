defmodule Amarula.Protocol.Messages.HistorySyncTest do
  use ExUnit.Case, async: true

  alias Amarula.{Address, Chat, Content, Msg}
  alias Amarula.Protocol.Proto

  # We can't unit-test the network download, but the decode/map logic (the part
  # that turns a HistorySync proto into %Chat{}/%Contact{}) is pure — exercise it
  # by encoding a HistorySync, deflating, and running the same inflate+decode+map
  # the module does. (fetch/1 itself needs a live blob.)

  test "a HistorySync blob decodes + maps to chats/contacts" do
    sync = %Proto.HistorySync{
      syncType: :RECENT,
      conversations: [
        %Proto.Conversation{
          id: "5511999999999@s.whatsapp.net",
          displayName: "Alice",
          archived: true,
          pinned: 3,
          unreadCount: 2
        },
        %Proto.Conversation{id: "120363000000000000@g.us", name: "Group X"}
      ]
    }

    raw = Proto.HistorySync.encode(sync)
    deflated = deflate(raw)

    # mirror HistorySync.fetch's post-download steps
    {:ok, inflated} = inflate(deflated)
    decoded = Proto.HistorySync.decode(inflated)
    assert decoded.syncType == :RECENT
    assert length(decoded.conversations) == 2

    # map (same shape HistorySync produces)
    [c1, c2] = decoded.conversations
    assert %Address{user: "5511999999999", kind: :pn} = Address.parse(c1.id)
    assert c1.displayName == "Alice"
    assert %Address{kind: :group} = Address.parse(c2.id)
  end

  test "fetch/1 handles an inline (initialHistBootstrapInlinePayload) notification" do
    # PUSH_NAME and small chunks arrive inline (no external blob, directPath nil).
    sync = %Proto.HistorySync{
      syncType: :PUSH_NAME,
      conversations: [%Proto.Conversation{id: "5511999999999@s.whatsapp.net", name: "Bob"}]
    }

    inline = sync |> Proto.HistorySync.encode() |> deflate()

    notification = %Proto.Message.HistorySyncNotification{
      syncType: :PUSH_NAME,
      initialHistBootstrapInlinePayload: inline,
      directPath: nil,
      mediaKey: nil
    }

    assert {:ok, result} = Amarula.Protocol.Messages.HistorySync.fetch(notification)
    assert result.sync_type == :PUSH_NAME
    assert [%Chat{address: %Address{user: "5511999999999"}}] = result.chats
  end

  test "fetch/1 errors cleanly when a notification has neither inline nor blob" do
    n = %Proto.Message.HistorySyncNotification{syncType: :PUSH_NAME}
    assert {:error, :no_history_payload} = Amarula.Protocol.Messages.HistorySync.fetch(n)
  end

  test "fetch/1 surfaces push_names (jid → name)" do
    sync = %Proto.HistorySync{
      syncType: :PUSH_NAME,
      pushnames: [
        %Proto.Pushname{id: "15550001234@s.whatsapp.net", pushname: "Tester"},
        %Proto.Pushname{id: "x@s.whatsapp.net", pushname: nil}
      ]
    }

    inline = sync |> Proto.HistorySync.encode() |> deflate()

    n = %Proto.Message.HistorySyncNotification{
      syncType: :PUSH_NAME,
      initialHistBootstrapInlinePayload: inline
    }

    assert {:ok, result} = Amarula.Protocol.Messages.HistorySync.fetch(n)
    assert result.push_names == [{"15550001234@s.whatsapp.net", "Tester"}]
  end

  describe "messages" do
    test "a conversation's messages map to %Msg{} (incl. from_me)" do
      convo = %Proto.Conversation{
        id: "5511999999999@s.whatsapp.net",
        messages: [
          hsm(text_wmi("A", "5511999999999@s.whatsapp.net", "hello")),
          hsm(text_wmi("B", "5511999999999@s.whatsapp.net", "hi back", fromMe: true))
        ]
      }

      assert {:ok, result} = fetch(%Proto.HistorySync{syncType: :RECENT, conversations: [convo]})
      assert [a, b] = result.messages

      assert %Msg{id: "A", type: :text, content: "hello", from_me: false} = a
      assert %Msg{id: "B", type: :text, content: "hi back", from_me: true} = b

      # channel is the room; `to` isn't derivable in this pure module.
      assert %Address{user: "5511999999999"} = a.channel
      assert a.from == a.channel
      assert a.to == nil
      assert a.timestamp == 1_700_000_000

      # ...but for OUR OWN message the key is chat-keyed: remoteJid is the PEER,
      # so attributing it as the writer would be backwards. nil, not wrong.
      # (Baileys getKeyAuthor short-circuits fromMe to `me` for the same reason.)
      assert b.from == nil
      assert %Address{user: "5511999999999"} = b.channel
    end

    test "a from_me group message doesn't attribute the group as the writer" do
      wmi = text_wmi("G2", "120363000000000000@g.us", "mine", fromMe: true)
      convo = %Proto.Conversation{id: "120363000000000000@g.us", messages: [hsm(wmi)]}

      assert {:ok, result} = fetch(%Proto.HistorySync{syncType: :FULL, conversations: [convo]})
      assert [%Msg{from_me: true, from: nil, pushname: nil} = msg] = result.messages
      assert %Address{kind: :group} = msg.channel
    end

    test "a group message's `from` is the participant, not the channel" do
      wmi =
        text_wmi("G1", "120363000000000000@g.us", "yo",
          participant: "5511888888888@s.whatsapp.net"
        )

      convo = %Proto.Conversation{id: "120363000000000000@g.us", messages: [hsm(wmi)]}

      assert {:ok, result} = fetch(%Proto.HistorySync{syncType: :FULL, conversations: [convo]})
      assert [msg] = result.messages

      assert %Address{kind: :group, user: "120363000000000000"} = msg.channel
      assert %Address{user: "5511888888888"} = msg.from
      refute msg.from == msg.channel
    end

    # Regression guard: history blobs are full of stub-only entries (group
    # joins/leaves, "security code changed") whose `message` is nil. They must be
    # skipped, not handed to Msg.from_proto/2, which requires a %Proto.Message{}.
    test "stub-only entries (message: nil) are skipped, not crashed on" do
      stub = %Proto.WebMessageInfo{
        key: %Proto.MessageKey{id: "STUB", remoteJid: "120363000000000000@g.us"},
        message: nil,
        messageStubType: :GROUP_PARTICIPANT_ADD
      }

      convo = %Proto.Conversation{
        id: "120363000000000000@g.us",
        messages: [hsm(stub), hsm(text_wmi("REAL", "120363000000000000@g.us", "still here"))]
      }

      assert {:ok, result} = fetch(%Proto.HistorySync{syncType: :FULL, conversations: [convo]})
      assert [%Msg{id: "REAL", content: "still here"}] = result.messages
    end

    test "a media message carries a download-ready descriptor" do
      image = %Proto.Message.ImageMessage{
        mimetype: "image/jpeg",
        directPath: "/v/t62.7118-24/abc",
        mediaKey: :binary.copy(<<7>>, 32),
        fileLength: 1234
      }

      wmi = %Proto.WebMessageInfo{
        key: %Proto.MessageKey{id: "IMG", remoteJid: "5511999999999@s.whatsapp.net"},
        message: %Proto.Message{imageMessage: image},
        messageTimestamp: 1_700_000_000
      }

      convo = %Proto.Conversation{id: "5511999999999@s.whatsapp.net", messages: [hsm(wmi)]}

      assert {:ok, result} = fetch(%Proto.HistorySync{syncType: :RECENT, conversations: [convo]})
      assert [%Msg{type: :media, content: %Content.Media{} = media}] = result.messages
      assert media.kind == :image
      assert media.direct_path == "/v/t62.7118-24/abc"
      assert is_binary(media.media_key)
    end

    test "statusV3Messages surface as status_messages" do
      sync = %Proto.HistorySync{
        syncType: :INITIAL_STATUS_V3,
        statusV3Messages: [text_wmi("S1", "status@broadcast", "my story")]
      }

      assert {:ok, result} = fetch(sync)
      assert [%Msg{id: "S1", type: :text, content: "my story"} = msg] = result.status_messages
      assert result.messages == []

      # `status@broadcast` isn't an addressable jid — there's nothing to reply to.
      assert msg.channel == nil
    end

    test "a HistorySyncMsg with no inner WebMessageInfo is skipped" do
      convo = %Proto.Conversation{
        id: "5511999999999@s.whatsapp.net",
        messages: [
          %Proto.HistorySyncMsg{message: nil},
          hsm(text_wmi("OK", "5511999999999@s.whatsapp.net", "survived"))
        ]
      }

      assert {:ok, result} = fetch(%Proto.HistorySync{syncType: :RECENT, conversations: [convo]})
      assert [%Msg{id: "OK"}] = result.messages
    end

    test "a wrapped (ephemeral) history message classifies as its inner content" do
      wmi = %Proto.WebMessageInfo{
        key: %Proto.MessageKey{id: "EPH", remoteJid: "5511999999999@s.whatsapp.net"},
        message: %Proto.Message{
          ephemeralMessage: %Proto.Message.FutureProofMessage{
            message: %Proto.Message{conversation: "vanishing"}
          }
        },
        messageTimestamp: 1_700_000_000
      }

      convo = %Proto.Conversation{id: "5511999999999@s.whatsapp.net", messages: [hsm(wmi)]}

      assert {:ok, result} = fetch(%Proto.HistorySync{syncType: :RECENT, conversations: [convo]})
      assert [%Msg{id: "EPH", type: :text, content: "vanishing"}] = result.messages
    end

    test "a conversation with no messages yields an empty list" do
      sync = %Proto.HistorySync{
        syncType: :RECENT,
        conversations: [%Proto.Conversation{id: "5511999999999@s.whatsapp.net"}]
      }

      assert {:ok, result} = fetch(sync)
      assert result.messages == []
      assert result.status_messages == []
    end
  end

  describe "lid_mappings" do
    test "extracts the explicit phoneNumberToLidMappings list" do
      sync = %Proto.HistorySync{
        syncType: :INITIAL_BOOTSTRAP,
        phoneNumberToLidMappings: [
          %Proto.PhoneNumberToLIDMapping{
            pnJid: "5511999999999@s.whatsapp.net",
            lidJid: "111@lid"
          },
          # incomplete pairs are dropped
          %Proto.PhoneNumberToLIDMapping{pnJid: "5511888888888@s.whatsapp.net", lidJid: nil}
        ]
      }

      assert {:ok, result} = fetch(sync)
      assert result.lid_mappings == [{"111@lid", "5511999999999@s.whatsapp.net"}]
    end

    test "extracts a conversation's counterpart jid in either direction" do
      sync = %Proto.HistorySync{
        syncType: :RECENT,
        conversations: [
          # PN-keyed chat naming its LID
          %Proto.Conversation{id: "5511999999999@s.whatsapp.net", lidJid: "111@lid"},
          # LID-keyed chat naming its PN
          %Proto.Conversation{id: "222@lid", pnJid: "5511888888888@s.whatsapp.net"},
          # a chat that names neither contributes nothing
          %Proto.Conversation{id: "120363000000000000@g.us"}
        ]
      }

      assert {:ok, result} = fetch(sync)

      assert result.lid_mappings == [
               {"111@lid", "5511999999999@s.whatsapp.net"},
               {"222@lid", "5511888888888@s.whatsapp.net"}
             ]
    end

    test "falls back to a userReceipt PN for a LID chat with no pnJid" do
      # userReceipt.userJid is the RECIPIENT, so it names the peer only on a
      # message we sent — hence fromMe: true.
      mine = text_wmi("M1", "333@lid", "hi", fromMe: true)
      mine = %{mine | userReceipt: [%Proto.UserReceipt{userJid: "5511777777777@s.whatsapp.net"}]}

      sync = %Proto.HistorySync{
        syncType: :RECENT,
        conversations: [%Proto.Conversation{id: "333@lid", messages: [hsm(mine)]}]
      }

      assert {:ok, result} = fetch(sync)
      assert result.lid_mappings == [{"333@lid", "5511777777777@s.whatsapp.net"}]
    end

    test "ignores receipts on messages we did not send" do
      # An inbound message's receipt userJid is OUR jid, not the peer's — using it
      # would map the peer's LID to our own number.
      theirs = text_wmi("T1", "444@lid", "yo")

      theirs = %{
        theirs
        | userReceipt: [%Proto.UserReceipt{userJid: "5511000000000@s.whatsapp.net"}]
      }

      sync = %Proto.HistorySync{
        syncType: :RECENT,
        conversations: [%Proto.Conversation{id: "444@lid", messages: [hsm(theirs)]}]
      }

      assert {:ok, result} = fetch(sync)
      assert result.lid_mappings == []
    end

    test "a LID chat echoing its own id in lidJid still yields its real pn pair" do
      # Keying on "which field is set" would emit a useless {lid, lid} pair here
      # AND mask the real pnJid behind it. Branch on the chat id's namespace.
      sync = %Proto.HistorySync{
        syncType: :RECENT,
        conversations: [
          %Proto.Conversation{
            id: "555@lid",
            lidJid: "555@lid",
            pnJid: "5511666666666@s.whatsapp.net"
          }
        ]
      }

      assert {:ok, result} = fetch(sync)
      assert result.lid_mappings == [{"555@lid", "5511666666666@s.whatsapp.net"}]
    end

    test "a LID chat with only a self-echoing lidJid still reaches the receipt fallback" do
      mine = text_wmi("M2", "666@lid", "hi", fromMe: true)
      mine = %{mine | userReceipt: [%Proto.UserReceipt{userJid: "5511555555555@s.whatsapp.net"}]}

      sync = %Proto.HistorySync{
        syncType: :RECENT,
        conversations: [
          %Proto.Conversation{id: "666@lid", lidJid: "666@lid", messages: [hsm(mine)]}
        ]
      }

      assert {:ok, result} = fetch(sync)
      assert result.lid_mappings == [{"666@lid", "5511555555555@s.whatsapp.net"}]
    end

    test "a hosted-LID receipt is not treated as a phone number" do
      # jid_user?/1 accepts @hosted.lid, so a subtractive "not lid_user?" test
      # would persist a LID-namespace user on the PN side of the mapping.
      mine = text_wmi("M3", "777@lid", "hi", fromMe: true)
      mine = %{mine | userReceipt: [%Proto.UserReceipt{userJid: "999@hosted.lid"}]}

      sync = %Proto.HistorySync{
        syncType: :RECENT,
        conversations: [%Proto.Conversation{id: "777@lid", messages: [hsm(mine)]}]
      }

      assert {:ok, result} = fetch(sync)
      assert result.lid_mappings == []
    end

    test "a group conversation contributes no user-level mapping" do
      sync = %Proto.HistorySync{
        syncType: :FULL,
        conversations: [
          %Proto.Conversation{
            id: "120363000000000000@g.us",
            pnJid: "5511444444444@s.whatsapp.net",
            lidJid: "888@lid"
          }
        ]
      }

      assert {:ok, result} = fetch(sync)
      assert result.lid_mappings == []
    end

    test "de-duplicates a pair carried by more than one source" do
      sync = %Proto.HistorySync{
        syncType: :RECENT,
        phoneNumberToLidMappings: [
          %Proto.PhoneNumberToLIDMapping{pnJid: "5511999999999@s.whatsapp.net", lidJid: "111@lid"}
        ],
        conversations: [
          %Proto.Conversation{id: "5511999999999@s.whatsapp.net", lidJid: "111@lid"}
        ]
      }

      assert {:ok, result} = fetch(sync)
      assert result.lid_mappings == [{"111@lid", "5511999999999@s.whatsapp.net"}]
    end

    test "is empty for a blob carrying no mappings" do
      assert {:ok, result} = fetch(%Proto.HistorySync{syncType: :PUSH_NAME})
      assert result.lid_mappings == []
    end
  end

  # Encode + deflate a HistorySync and run it through fetch/1 as an inline payload.
  defp fetch(%Proto.HistorySync{} = sync) do
    Amarula.Protocol.Messages.HistorySync.fetch(%Proto.Message.HistorySyncNotification{
      syncType: sync.syncType,
      initialHistBootstrapInlinePayload: sync |> Proto.HistorySync.encode() |> deflate()
    })
  end

  defp hsm(%Proto.WebMessageInfo{} = wmi), do: %Proto.HistorySyncMsg{message: wmi}

  defp text_wmi(id, remote_jid, body, opts \\ []) do
    %Proto.WebMessageInfo{
      key: %Proto.MessageKey{
        id: id,
        remoteJid: remote_jid,
        fromMe: Keyword.get(opts, :fromMe, false),
        participant: Keyword.get(opts, :participant)
      },
      message: %Proto.Message{conversation: body},
      messageTimestamp: 1_700_000_000
    }
  end

  defp deflate(bin) do
    z = :zlib.open()
    :zlib.deflateInit(z)
    out = :zlib.deflate(z, bin, :finish) |> IO.iodata_to_binary()
    :zlib.deflateEnd(z)
    :zlib.close(z)
    out
  end

  defp inflate(bin) do
    z = :zlib.open()
    :zlib.inflateInit(z)
    out = :zlib.inflate(z, bin) |> IO.iodata_to_binary()
    :zlib.inflateEnd(z)
    :zlib.close(z)
    {:ok, out}
  end
end
