defmodule Amarula.Protocol.Messages.MessageEncoder do
  @moduledoc """
  Encode an outgoing `Proto.Message` to the padded plaintext bytes that the
  Signal cipher encrypts, ported from Baileys `encodeWAMessage`
  (`src/Utils/generics.ts`):

      encodeWAMessage(m) = writeRandomPadMax16(proto.Message.encode(m))

  `writeRandomPadMax16` appends `padLength` bytes each equal to `padLength`,
  where `padLength = (rand_byte & 0x0f) + 1` (1..16). `unpadRandomMax16` (the
  receive side) reads the last byte as the pad length and strips it.
  """

  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Messages.{Poll, PollCrypto}

  @doc "Encode a `%Proto.Message{}` (or message map) and append random PKCS-style pad."
  @spec encode(struct() | map()) :: binary()
  def encode(message) do
    message
    |> to_proto()
    |> Proto.Message.encode()
    |> pad_random_max16()
  end

  @doc """
  Build a text message. With no `:quoted`/`:mentions` context it's a plain
  `conversation`; when a reply or mentions are present WhatsApp requires an
  `extendedTextMessage` (which carries the `contextInfo`), so we switch to that.
  """
  @spec text(String.t(), keyword()) :: Proto.Message.t()
  def text(body, opts \\ []) when is_binary(body) do
    case context_info(opts) do
      nil ->
        %Proto.Message{conversation: body}

      %Proto.ContextInfo{} = ctx ->
        %Proto.Message{
          extendedTextMessage: %Proto.Message.ExtendedTextMessage{text: body, contextInfo: ctx}
        }
    end
  end

  @doc """
  Build a `%Proto.ContextInfo{}` from reply/mention opts, or `nil` when neither
  is present (so a message stays a plain `conversation`/bare media):

    * `:quoted` — an `%Amarula.Msg{}` being replied to. Fills `stanzaId` (its id),
      `participant` (its sender jid), and inlines its raw proto as `quotedMessage`.
    * `:mentions` — a list of jids or `%Amarula.Address{}` to tag (`mentionedJid`).
  """
  @spec context_info(keyword()) :: Proto.ContextInfo.t() | nil
  def context_info(opts) do
    quoted = Keyword.get(opts, :quoted)
    mentions = Keyword.get(opts, :mentions, [])

    if is_nil(quoted) and mentions == [] do
      nil
    else
      base =
        case quoted do
          %Amarula.Msg{} = msg ->
            %Proto.ContextInfo{
              stanzaId: msg.id,
              participant: msg.from && Amarula.Address.to_jid!(msg.from),
              quotedMessage: msg.raw
            }

          nil ->
            %Proto.ContextInfo{}
        end

      %{base | mentionedJid: Enum.map(mentions, &Amarula.Address.to_jid!/1)}
    end
  end

  @doc """
  Build a contact message from a `display_name` + `vcard` string. Pass a list of
  `{display_name, vcard}` to build a `contactsArrayMessage` (multiple contacts).
  """
  @spec contact(String.t(), String.t()) :: Proto.Message.t()
  def contact(display_name, vcard) when is_binary(display_name) and is_binary(vcard) do
    %Proto.Message{
      contactMessage: %Proto.Message.ContactMessage{displayName: display_name, vcard: vcard}
    }
  end

  @spec contacts(String.t(), [{String.t(), String.t()}, ...]) :: Proto.Message.t()
  def contacts(display_name, [_ | _] = pairs) do
    %Proto.Message{
      contactsArrayMessage: %Proto.Message.ContactsArrayMessage{
        displayName: display_name,
        contacts:
          Enum.map(pairs, fn {name, vcard} ->
            %Proto.Message.ContactMessage{displayName: name, vcard: vcard}
          end)
      }
    }
  end

  @doc """
  Build a poll-creation message. `name` is the question, `options` the choice
  strings. `opts`:

    * `:selectable` — max selectable options (0 = unlimited; default 1 = single).
    * `:announcement` — community-announcement-group poll (v2).
    * `:message_secret` — 32-byte vote-encryption key (default: random). Keep it;
      tallying incoming votes needs it (`Poll.tally/3`).

  Picks the proto variant like Baileys: v2 for announcement, v3 for single-select,
  v1 for multi. Returns `{message, message_secret}`.
  """
  @spec poll(String.t(), [String.t(), ...], keyword()) :: {Proto.Message.t(), binary()}
  def poll(name, [_ | _] = options, opts \\ []) when is_binary(name) do
    selectable = Keyword.get(opts, :selectable, 1)

    unless selectable >= 0 and selectable <= length(options) do
      raise ArgumentError, "selectable must be 0..#{length(options)}, got #{selectable}"
    end

    secret = Keyword.get(opts, :message_secret) || :crypto.strong_rand_bytes(32)

    creation = %Proto.Message.PollCreationMessage{
      name: name,
      selectableOptionsCount: selectable,
      options: Enum.map(options, &%Proto.Message.PollCreationMessage.Option{optionName: &1})
    }

    ctx = %Proto.MessageContextInfo{messageSecret: secret}
    message = %{poll_variant(opts, selectable) => creation, messageContextInfo: ctx}
    {struct(Proto.Message, message), secret}
  end

  @doc """
  Build a `pollUpdateMessage` casting a vote on an existing poll. Args:

    * `poll_key` — the `%Proto.MessageKey{}` of the poll-creation message.
    * `creator_jid` — the poll creator's jid (the poll message author).
    * `voter_jid` — our jid (the vote is encrypted per voter).
    * `message_secret` — the poll's 32-byte secret (returned by `poll/3` at
      creation, or decoded from the poll's `messageContextInfo`).
    * `option_names` — the chosen option strings (must match the poll's options).

  The vote is AES-256-GCM encrypted under the poll secret (`PollCrypto`), so it
  round-trips through the same decrypt path tallies use.
  """
  @spec poll_vote(Proto.MessageKey.t(), String.t(), String.t(), binary(), [String.t()]) ::
          Proto.Message.t()
  def poll_vote(
        %Proto.MessageKey{} = poll_key,
        creator_jid,
        voter_jid,
        message_secret,
        option_names
      ) do
    ctx = %{
      message_secret: message_secret,
      poll_msg_id: poll_key.id,
      poll_creator_jid: creator_jid,
      voter_jid: voter_jid
    }

    hashes = Enum.map(option_names, &Poll.option_hash/1)
    vote = PollCrypto.encrypt_vote(hashes, ctx)

    %Proto.Message{
      pollUpdateMessage: %Proto.Message.PollUpdateMessage{
        pollCreationMessageKey: poll_key,
        vote: vote,
        senderTimestampMs: System.system_time(:millisecond)
      }
    }
  end

  defp poll_variant(opts, selectable) do
    cond do
      Keyword.get(opts, :announcement, false) -> :pollCreationMessageV2
      selectable == 1 -> :pollCreationMessageV3
      true -> :pollCreationMessage
    end
  end

  @doc """
  Build a location message. `lat`/`lng` are floats (proto `double`). `opts`:
  `:name`, `:address`, `:url`, `:is_live`.
  """
  @spec location(float(), float(), keyword()) :: Proto.Message.t()
  def location(lat, lng, opts \\ []) when is_float(lat) and is_float(lng) do
    %Proto.Message{
      locationMessage: %Proto.Message.LocationMessage{
        degreesLatitude: lat,
        degreesLongitude: lng,
        name: opts[:name],
        address: opts[:address],
        url: opts[:url],
        isLive: opts[:is_live]
      }
    }
  end

  @doc """
  Build a reaction to the message identified by `target_key`. `emoji` is the
  reaction (e.g. "👍"); pass "" to REMOVE a previous reaction (Baileys semantics).
  """
  @spec reaction(Proto.MessageKey.t(), String.t()) :: Proto.Message.t()
  def reaction(%Proto.MessageKey{} = target_key, emoji) when is_binary(emoji) do
    %Proto.Message{
      reactionMessage: %Proto.Message.ReactionMessage{
        key: target_key,
        text: emoji,
        senderTimestampMs: System.system_time(:millisecond)
      }
    }
  end

  @doc """
  Build a media message of `type` (`:image`/`:video`/`:audio`/`:document`/
  `:sticker`) from an `encrypt`+`upload` result. `info` carries the uploaded
  `:url`/`:direct_path`, the encrypt result (`:media_key`, `:file_sha256`,
  `:file_enc_sha256`, `:file_length`) and `:mimetype`. `opts` adds per-type extras
  (`:caption`, `:width`, `:height`, `:seconds`, `:ptt`, `:file_name`, `:title`).
  """
  @spec media(:image | :video | :audio | :document | :sticker, map(), keyword()) ::
          Proto.Message.t()
  def media(type, info, opts \\ []) do
    common = %{
      url: info.url,
      directPath: info.direct_path,
      mediaKey: info.media_key,
      fileSha256: info.file_sha256,
      fileEncSha256: info.file_enc_sha256,
      fileLength: info.file_length,
      mimetype: info.mimetype
    }

    type
    |> media_message(common, opts)
    |> put_media_context(media_field(type), context_info(opts))
    |> maybe_ptv(type, opts)
    |> maybe_view_once(opts)
    |> maybe_album_child(opts[:album_parent])
  end

  # An album child references its parent album message via a top-level
  # messageContextInfo.messageAssociation (MEDIA_ALBUM). The send path forwards
  # messageContextInfo, so this rides along to the recipient.
  defp maybe_album_child(message, nil), do: message

  defp maybe_album_child(%Proto.Message{} = message, %Proto.MessageKey{} = parent_key) do
    %{
      message
      | messageContextInfo: %Proto.MessageContextInfo{
          messageAssociation: %Proto.MessageAssociation{
            associationType: :MEDIA_ALBUM,
            parentMessageKey: parent_key
          }
        }
    }
  end

  # PTV (round video note): relocate the built videoMessage to the ptvMessage
  # field (Baileys `obj.ptvMessage = obj.videoMessage`). Only valid for video.
  defp maybe_ptv(%Proto.Message{videoMessage: vid} = message, :video, opts) do
    if Keyword.get(opts, :ptv, false) do
      %Proto.Message{ptvMessage: vid}
    else
      message
    end
  end

  defp maybe_ptv(message, _type, _opts), do: message

  # View-once: wrap the whole message in a viewOnceMessage (FutureProofMessage),
  # mirroring Baileys `m = { viewOnceMessage: { message: m } }`.
  defp maybe_view_once(message, opts) do
    if Keyword.get(opts, :view_once, false) do
      %Proto.Message{
        viewOnceMessage: %Proto.Message.FutureProofMessage{message: message}
      }
    else
      message
    end
  end

  defp media_field(:image), do: :imageMessage
  defp media_field(:video), do: :videoMessage
  defp media_field(:audio), do: :audioMessage
  defp media_field(:document), do: :documentMessage
  defp media_field(:sticker), do: :stickerMessage

  # Attach reply/mention contextInfo to the media submessage. No context →
  # unchanged.
  defp put_media_context(message, _field, nil), do: message

  defp put_media_context(%Proto.Message{} = message, field, %Proto.ContextInfo{} = ctx) do
    sub = Map.fetch!(message, field)
    %{message | field => %{sub | contextInfo: ctx}}
  end

  @doc "Convenience: `media(:image, info, opts)`."
  @spec image(map(), keyword()) :: Proto.Message.t()
  def image(info, opts \\ []), do: media(:image, info, opts)

  defp media_message(:image, common, opts) do
    %Proto.Message{
      imageMessage:
        struct(
          Proto.Message.ImageMessage,
          Map.merge(common, take(opts, [:caption, :width, :height]))
        )
    }
  end

  defp media_message(:video, common, opts) do
    %Proto.Message{
      videoMessage:
        struct(
          Proto.Message.VideoMessage,
          Map.merge(common, take(opts, [:caption, :width, :height, :seconds, :gifPlayback]))
        )
    }
  end

  defp media_message(:audio, common, opts) do
    # No :seconds → WhatsApp can't show a duration, and iPhone recipients may
    # refuse to play clips longer than ~10s (Baileys #2646). We don't compute it
    # (no media processing); warn so the caller knows to pass it.
    if is_nil(Keyword.get(opts, :seconds)) do
      require Logger

      Logger.warning(
        "audio sent without :seconds — clips >10s may not play on iPhone (pass :seconds)"
      )
    end

    %Proto.Message{
      audioMessage:
        struct(
          Proto.Message.AudioMessage,
          Map.merge(common, take(opts, [:seconds, :ptt, :waveform]))
        )
    }
  end

  defp media_message(:document, common, opts) do
    %Proto.Message{
      documentMessage:
        struct(
          Proto.Message.DocumentMessage,
          Map.merge(common, take(opts, [:title, :fileName, :pageCount]))
        )
    }
  end

  defp media_message(:sticker, common, opts) do
    %Proto.Message{
      stickerMessage:
        struct(
          Proto.Message.StickerMessage,
          Map.merge(common, take(opts, [:width, :height, :isAnimated]))
        )
    }
  end

  # Pull the given keys from opts into a map, dropping absent ones.
  defp take(opts, keys) do
    for k <- keys, (v = Keyword.get(opts, k)) != nil, into: %{}, do: {k, v}
  end

  @doc """
  Edit the message identified by `target_key`, replacing its body with `new_text`.
  Sent to `target_key.remoteJid` with the `edit="1"` stanza attr (added by the
  send path); the recipient replaces the original message's content.
  """
  @spec edit(Proto.MessageKey.t(), String.t()) :: Proto.Message.t()
  def edit(%Proto.MessageKey{} = target_key, new_text) when is_binary(new_text) do
    %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{
        key: target_key,
        type: :MESSAGE_EDIT,
        editedMessage: text(new_text),
        timestampMs: System.system_time(:millisecond)
      }
    }
  end

  @doc """
  Build an album **parent** message announcing how many images/videos follow.
  The children are sent afterwards, each referencing this message's key as their
  album parent (see `media/3`'s `:album_parent` opt).
  """
  @spec album(non_neg_integer(), non_neg_integer()) :: Proto.Message.t()
  def album(image_count, video_count) do
    %Proto.Message{
      albumMessage: %Proto.Message.AlbumMessage{
        expectedImageCount: image_count,
        expectedVideoCount: video_count
      }
    }
  end

  @doc """
  Build an event message. `name` is the event title. `opts`:

    * `:description` — free text.
    * `:location` — `{lat, lng}` floats, or a keyword with `:name`/`:address`.
    * `:join_link` — a call/meeting URL.
    * `:start_time` / `:end_time` — unix seconds.
    * `:extra_guests_allowed` — boolean.
  """
  @spec event(String.t(), keyword()) :: Proto.Message.t()
  def event(name, opts \\ []) when is_binary(name) do
    %Proto.Message{
      eventMessage: %Proto.Message.EventMessage{
        name: name,
        description: opts[:description],
        location: event_location(opts[:location]),
        joinLink: opts[:join_link],
        startTime: opts[:start_time],
        endTime: opts[:end_time],
        extraGuestsAllowed: opts[:extra_guests_allowed]
      }
    }
  end

  defp event_location(nil), do: nil

  defp event_location({lat, lng}) when is_float(lat) and is_float(lng),
    do: %Proto.Message.LocationMessage{degreesLatitude: lat, degreesLongitude: lng}

  defp event_location(opts) when is_list(opts) do
    %Proto.Message.LocationMessage{
      degreesLatitude: opts[:lat],
      degreesLongitude: opts[:lng],
      name: opts[:name],
      address: opts[:address]
    }
  end

  @doc """
  Build a group-invite message — a sendable chat card that lets the recipient
  join `group_jid` via `code` (from `Amarula.Group.invite_code/2`). `opts`:
  `:group_name`, `:caption`, `:expiration` (unix ms when the code expires).
  """
  @spec group_invite(String.t(), String.t(), keyword()) :: Proto.Message.t()
  def group_invite(group_jid, code, opts \\ []) do
    %Proto.Message{
      groupInviteMessage: %Proto.Message.GroupInviteMessage{
        groupJid: group_jid,
        inviteCode: code,
        inviteExpiration: opts[:expiration],
        groupName: opts[:group_name],
        caption: opts[:caption]
      }
    }
  end

  @doc """
  Pin (`pin?: true`) or unpin (`false`) the message identified by `target_key`
  for everyone in the chat (`PIN_FOR_ALL` / `UNPIN_FOR_ALL`).
  """
  @spec pin(Proto.MessageKey.t(), boolean()) :: Proto.Message.t()
  def pin(%Proto.MessageKey{} = target_key, pin?) when is_boolean(pin?) do
    type = if pin?, do: :PIN_FOR_ALL, else: :UNPIN_FOR_ALL

    %Proto.Message{
      pinInChatMessage: %Proto.Message.PinInChatMessage{
        key: target_key,
        type: type,
        senderTimestampMs: System.system_time(:millisecond)
      }
    }
  end

  @doc """
  Keep (`keep?: true`, `KEEP_FOR_ALL`) or undo-keep (`false`, `UNDO_KEEP_FOR_ALL`)
  the message identified by `target_key` — for messages in a disappearing chat.
  """
  @spec keep(Proto.MessageKey.t(), boolean()) :: Proto.Message.t()
  def keep(%Proto.MessageKey{} = target_key, keep?) when is_boolean(keep?) do
    type = if keep?, do: :KEEP_FOR_ALL, else: :UNDO_KEEP_FOR_ALL

    %Proto.Message{
      keepInChatMessage: %Proto.Message.KeepInChatMessage{
        key: target_key,
        keepType: type,
        timestampMs: System.system_time(:millisecond)
      }
    }
  end

  @doc """
  Build a delete-for-everyone (revoke) of the message identified by `target_key`.
  Sent to `target_key.remoteJid`; the recipient replaces the message with a
  "this message was deleted" tombstone.
  """
  @spec revoke(Proto.MessageKey.t()) :: Proto.Message.t()
  def revoke(%Proto.MessageKey{} = target_key) do
    %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{
        key: target_key,
        type: :REVOKE
      }
    }
  end

  @doc """
  Set (or, with `""`, clear) your own **member tag** in a group — the per-group
  self-label shown next to your name. Capped at 30 characters (WhatsApp's limit).
  Sent to the group as a `GROUP_MEMBER_LABEL_CHANGE` protocol message.
  """
  @spec member_label(String.t()) :: Proto.Message.t()
  def member_label(label) when is_binary(label) do
    %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{
        type: :GROUP_MEMBER_LABEL_CHANGE,
        memberLabel: %Proto.MemberLabel{
          label: String.slice(label, 0, 30),
          labelTimestamp: System.system_time(:second)
        }
      }
    }
  end

  @doc """
  A PEER_DATA_OPERATION placeholder-resend request for `message_key` — sent to our
  own devices to ask the phone to re-deliver that message (Baileys
  requestPlaceholderResend).
  """
  @spec placeholder_resend_request(Proto.MessageKey.t()) :: Proto.Message.t()
  def placeholder_resend_request(%Proto.MessageKey{} = message_key) do
    %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{
        type: :PEER_DATA_OPERATION_REQUEST_MESSAGE,
        peerDataOperationRequestMessage: %Proto.Message.PeerDataOperationRequestMessage{
          peerDataOperationRequestType: :PLACEHOLDER_MESSAGE_RESEND,
          placeholderMessageResendRequest: [
            %Proto.Message.PeerDataOperationRequestMessage.PlaceholderMessageResendRequest{
              messageKey: message_key
            }
          ]
        }
      }
    }
  end

  @doc """
  A PEER_DATA_OPERATION on-demand history request — sent to our own devices to ask
  the phone for older messages of a chat (Baileys fetchMessageHistory). `oldest_key`
  is the oldest message we already have; the phone replies with an `ON_DEMAND`
  HistorySync notification carrying up to `count` older messages.
  """
  @spec history_sync_on_demand_request(Proto.MessageKey.t(), integer(), non_neg_integer()) ::
          Proto.Message.t()
  def history_sync_on_demand_request(%Proto.MessageKey{} = oldest_key, oldest_ts, count) do
    %Proto.Message{
      protocolMessage: %Proto.Message.ProtocolMessage{
        type: :PEER_DATA_OPERATION_REQUEST_MESSAGE,
        peerDataOperationRequestMessage: %Proto.Message.PeerDataOperationRequestMessage{
          peerDataOperationRequestType: :HISTORY_SYNC_ON_DEMAND,
          historySyncOnDemandRequest:
            %Proto.Message.PeerDataOperationRequestMessage.HistorySyncOnDemandRequest{
              chatJid: oldest_key.remoteJid,
              oldestMsgFromMe: oldest_key.fromMe,
              oldestMsgId: oldest_key.id,
              oldestMsgTimestampMs: oldest_ts,
              onDemandMsgCount: count
            }
        }
      }
    }
  end

  # writeRandomPadMax16: padLength in 1..16, that many bytes each == padLength.
  @spec pad_random_max16(binary()) :: binary()
  defp pad_random_max16(bytes) do
    <<rand>> = :crypto.strong_rand_bytes(1)
    pad_length = Bitwise.band(rand, 0x0F) + 1
    bytes <> :binary.copy(<<pad_length>>, pad_length)
  end

  defp to_proto(%Proto.Message{} = m), do: m
  defp to_proto(map) when is_map(map), do: struct(Proto.Message, map)
end
