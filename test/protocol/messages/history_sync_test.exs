defmodule Amarula.Protocol.Messages.HistorySyncTest do
  use ExUnit.Case, async: true

  alias Amarula.{Address, Chat, Contact}
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

    # %Chat{} mapping fields
    chat = %Chat{
      address: Address.parse(c1.id),
      archived: c1.archived,
      pinned: c1.pinned > 0,
      mute_end: c1.muteEndTime,
      unread: c1.unreadCount
    }

    assert chat.archived == true
    assert chat.pinned == true
    assert chat.unread == 2

    contact = %Contact{address: Address.parse(c1.id), full_name: c1.displayName}
    assert contact.full_name == "Alice"
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
