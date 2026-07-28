defmodule Amarula.Protocol.Messages.HistorySync do
  @moduledoc """
  Download + decode the history-sync blob a `HISTORY_SYNC_NOTIFICATION` points to,
  ported from Baileys `downloadHistory`/`processHistoryMessage` (`Utils/history.ts`).

  On first link (and incrementally), the primary device pushes the chat history as
  an external, encrypted, zlib-deflated blob referenced by the notification. We
  download it (media crypto, `:history` keys), inflate, and decode a
  `Proto.HistorySync` — yielding the conversations (chats), contacts, and their
  messages. This is what populates the chat list, and acking/consuming it is what
  moves the phone from "Paused" to "active".

  ## Messages

  `messages` carries the synced history itself as `%Amarula.Msg{}` structs — the
  same consumer view the live receive path emits, so `msg.type`/`msg.content`,
  `Amarula.download_media/1` and `Amarula.send_reaction/3` all work on them.
  `status_messages` is the same for status/story posts (`statusV3Messages`).

  This is the *only* way to recover a message the live path never delivers — most
  notably a message you sent from your phone while this device was disconnected,
  which WhatsApp does not redeliver on reconnect (#40).

  Four things to know:

    * **`to` is always `nil`, and `from` is `nil` on your own messages.** This
      module is pure and has no access to our own credentials, so neither the
      addressed identity nor "me" can be named. A history key doesn't carry the
      author of a `from_me` message either (WhatsApp keys those by the *chat*, so
      `remoteJid` is the peer — attributing it as the writer would be backwards).
      **Branch on `from_me` before reading `from`.** `from_me`, `id` and
      `timestamp` are always populated. `Amarula.own_chat?/2` does not work on a
      history message.
    * **`channel` is `nil` on a status post.** `status_messages` are keyed
      `status@broadcast`, which isn't an addressable jid — there's nothing to
      reply to. Chat messages always have a `channel`.
    * **Overlap with `:messages_upsert` is possible** — a `RECENT` sync re-sends
      messages that also arrived live. Amarula keeps no inbound-message store, so
      it can't dedup for you: dedup by `msg.id` against your own store.
    * **Media expires.** A synced media message carries a complete descriptor, but
      WhatsApp drops old media from its CDN — `download_media/1` on an old one
      fails with `{:error, {:http, 404}}`.

  Entries carrying only a `messageStubType` (group joins/leaves, "security code
  changed") have no message body and are skipped. A `FULL` sync can hold a lot of
  history; every `%Msg{}` retains its `raw` proto, so peak memory is roughly double
  the decoded message set.

  ## LID↔PN mappings

  `lid_mappings` is `[{lid_jid, pn_jid}]` learned from the blob — the same pairs
  Baileys' `processHistoryMessage` collects, from all three of its sources:

    1. `phoneNumberToLidMappings` — the explicit top-level list.
    2. A conversation's `lidJid`/`pnJid` — each chat names its counterpart in the
       other namespace.
    3. For a LID-keyed chat with no `pnJid`, the PN in the first `userReceipt` of
       one of *our own* messages. A receipt's `userJid` is the *recipient*, so it
       identifies the peer only on a message we sent (Baileys
       `extractPnFromMessages`).

  These are *candidates*: orientation and validity are
  `Amarula.Protocol.Signal.LidMappingFileStore.store_mappings/2`'s job, which
  accepts either order and skips anything that isn't a real PN/LID pair. This
  module stays pure — `Amarula.Connection` persists them and emits
  `:lid_mapping_update`.

  A history sync is the richest mapping source there is: the blob names the LID
  and PN of every chat at once, so a first link populates the store in one pass
  instead of learning pairs one send at a time. Note that learning a mapping here
  does *not* establish a Signal session for that contact (unlike the USync path,
  where a send is imminent) — the blob covers every contact you've ever chatted
  with, so sessions stay lazy and a send builds them when it needs them.
  """

  alias Amarula.{Address, Chat, Contact, Msg}
  alias Amarula.Protocol.Binary.JID
  alias Amarula.Protocol.Messages.Media
  alias Amarula.Protocol.Proto

  @type result :: %{
          sync_type: atom(),
          chats: [Chat.t()],
          contacts: [Contact.t()],
          push_names: [{String.t(), String.t()}],
          messages: [Msg.t()],
          status_messages: [Msg.t()],
          lid_mappings: [{String.t(), String.t()}]
        }

  @doc """
  Download + decode the blob for a `%HistorySyncNotification{}`. Returns
  `{:ok, %{sync_type, chats, contacts}}` or `{:error, reason}`.
  """
  @spec fetch(struct()) :: {:ok, result()} | {:error, term()}
  def fetch(notification) do
    with {:ok, deflated} <- raw_blob(notification),
         {:ok, raw} <- inflate(deflated) do
      sync = Proto.HistorySync.decode(raw)
      {:ok, to_result(sync)}
    end
  end

  # A HISTORY_SYNC_NOTIFICATION is delivered one of two ways:
  #   * inline — `initialHistBootstrapInlinePayload` carries the (still-deflated)
  #     bytes directly (e.g. PUSH_NAME / small chunks); no download.
  #   * external — `directPath`+`mediaKey` reference an encrypted blob to download.
  defp raw_blob(%{initialHistBootstrapInlinePayload: inline}) when is_binary(inline),
    do: {:ok, inline}

  defp raw_blob(%{directPath: dp, mediaKey: mk} = n) when is_binary(dp) and is_binary(mk) do
    # `n` is a raw proto node (camelCase); build the canonical snake_case descriptor.
    Media.download(%{direct_path: dp, url: Map.get(n, :url), media_key: mk}, :history)
  end

  defp raw_blob(_notification), do: {:error, :no_history_payload}

  # The blob is raw zlib (deflate); inflate to the HistorySync protobuf bytes.
  defp inflate(deflated) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z)
      raw = :zlib.inflate(z, deflated) |> IO.iodata_to_binary()
      :zlib.inflateEnd(z)
      {:ok, raw}
    rescue
      e -> {:error, {:inflate_failed, e}}
    after
      :zlib.close(z)
    end
  end

  defp to_result(sync) do
    convos = sync.conversations || []

    %{
      sync_type: sync.syncType,
      chats: Enum.map(convos, &chat/1),
      contacts: Enum.flat_map(convos, &contact/1),
      # push names keyed by jid (incl. our own — used to learn me.name)
      push_names: for(p <- sync.pushnames || [], p.pushname, do: {p.id, p.pushname}),
      messages: Enum.flat_map(convos, &messages/1),
      status_messages: Enum.flat_map(sync.statusV3Messages || [], &msg/1),
      lid_mappings: lid_mappings(sync, convos)
    }
  end

  # LID↔PN pairs carried by the blob, from the three places Baileys reads them
  # (`processHistoryMessage`). Emitted as `{lid, pn}` candidates — orientation and
  # validity are `LidMappingFileStore.store_mappings/2`'s job, so we stay permissive
  # here and let the store skip what isn't a real PN/LID pair.
  defp lid_mappings(sync, convos) do
    explicit =
      for %{pnJid: pn, lidJid: lid} <- sync.phoneNumberToLidMappings || [],
          is_binary(pn) and is_binary(lid),
          do: {lid, pn}

    (explicit ++ Enum.flat_map(convos, &convo_mapping/1)) |> Enum.uniq()
  end

  # A conversation names its counterpart in the *other* namespace. Branch on the
  # chat id's own namespace, not on which field happens to be set (Baileys
  # `processHistoryMessage`): a LID chat may carry `lidJid` echoing its own id, and
  # keying on presence would emit a useless LID↔LID pair *and* mask the real
  # `pnJid`/receipt mapping behind it.
  defp convo_mapping(convo) do
    cond do
      JID.lid_user?(convo.id) -> lid_chat_mapping(convo)
      pn?(convo.id) -> present(convo.lidJid, &{&1, convo.id})
      # groups and anything else carry no user-level mapping
      true -> []
    end
  end

  # A LID-keyed chat names its PN directly, or — failing that — via the PN in the
  # first user receipt on one of OUR OWN messages. `userReceipt.userJid` is the
  # *recipient*, so it identifies the peer only when we were the sender (Baileys
  # `extractPnFromMessages`).
  defp lid_chat_mapping(convo) do
    case present(convo.pnJid, &{convo.id, &1}) do
      [] -> lid_from_receipts(convo)
      pair -> pair
    end
  end

  defp present(jid, build) when is_binary(jid) and jid != "", do: [build.(jid)]
  defp present(_jid, _build), do: []

  defp lid_from_receipts(convo) do
    (convo.messages || [])
    |> Enum.find_value(&receipt_pn/1)
    |> case do
      pn when is_binary(pn) -> [{convo.id, pn}]
      nil -> []
    end
  end

  # The recipient PN named by the first receipt on one of our own messages, or nil.
  defp receipt_pn(%Proto.HistorySyncMsg{
         message: %Proto.WebMessageInfo{key: %{fromMe: true}, userReceipt: [%{userJid: pn} | _]}
       })
       when is_binary(pn) do
    if pn?(pn), do: pn
  end

  defp receipt_pn(_entry), do: nil

  # A phone-number user. `JID.jid_user?/1` also accepts `@hosted.lid`, which
  # `lid_user?/1` (an `@lid` suffix check) does NOT exclude — so test the PN
  # servers positively rather than by subtraction, or a hosted LID would be
  # persisted on the PN side of a mapping. Mirrors Baileys' `isPnUser ||
  # isHostedPnUser`.
  defp pn?(jid) when is_binary(jid),
    do: String.ends_with?(jid, "@s.whatsapp.net") or String.ends_with?(jid, "@hosted")

  defp pn?(_jid), do: false

  defp chat(convo) do
    %Chat{
      address: Address.parse(convo.id),
      archived: convo.archived,
      pinned: pinned?(convo),
      mute_end: convo.muteEndTime,
      unread: convo.unreadCount
    }
  end

  defp contact(convo) do
    name = convo.displayName || convo.name

    if is_binary(name) and name != "" do
      [%Contact{address: Address.parse(convo.id), full_name: name}]
    else
      []
    end
  end

  defp pinned?(%{pinned: p}) when is_integer(p), do: p > 0
  defp pinned?(_), do: nil

  # A conversation's synced history. Each entry is a HistorySyncMsg wrapping the
  # WebMessageInfo (one level more than statusV3Messages, which are bare).
  defp messages(convo) do
    Enum.flat_map(convo.messages || [], fn
      %Proto.HistorySyncMsg{message: %Proto.WebMessageInfo{} = wmi} -> msg(wmi)
      _ -> []
    end)
  end

  # A WebMessageInfo → a one-element [%Msg{}], or [] when it carries no body.
  # Stub-only entries (messageStubType: group joins/leaves, "security code
  # changed") have `message: nil` and are skipped — Msg.from_proto/2 requires a
  # %Proto.Message{}.
  defp msg(
         %Proto.WebMessageInfo{key: %Proto.MessageKey{} = key, message: %Proto.Message{} = m} =
           wmi
       ) do
    channel = Address.parse(key.remoteJid)
    from_me? = key.fromMe == true

    [
      Msg.from_proto(m, %{
        id: key.id,
        # The room (reply handle): the group jid for a group, the peer for a DM.
        # nil for a status post — `status@broadcast` is not an addressable jid.
        channel: channel,
        from: from(key, channel, from_me?),
        # Not derivable here — this module has no access to our own creds.
        to: nil,
        from_me: from_me?,
        # Our own sends carry no foreign pushname; match the live path's nil.
        pushname: unless(from_me?, do: wmi.pushName),
        # Seconds, same unit as the live path's stanza `t` attr.
        timestamp: wmi.messageTimestamp
      })
    ]
  end

  defp msg(_wmi), do: []

  # The writer. Mirrors Baileys' `getKeyAuthor` (Utils/generics.ts): `fromMe`
  # short-circuits to *us* — it never falls through to participant/remoteJid,
  # which in a DM is the PEER. We can't name ourselves here (no creds), so we
  # return nil rather than a confidently wrong address: for our own messages a
  # history blob's key simply doesn't carry the author.
  defp from(_key, _channel, true), do: nil
  defp from(key, channel, _from_me?), do: Address.parse(key.participant) || channel
end
