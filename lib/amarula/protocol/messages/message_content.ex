defmodule Amarula.Protocol.Messages.MessageContent do
  @moduledoc """
  Classify a decrypted `%Proto.Message{}` into a tagged tuple so consumers don't
  have to pattern-match the (large) proto. The inverse of the builders in
  `MessageEncoder`.

  `classify/1` returns one of:

    * `{:text, body}`
    * `{:reaction, target_key, emoji}`            — emoji "" means the reaction was removed
    * `{:edit, target_key, new_text}`
    * `{:revoke, target_key}`
    * `{:media, type, message_struct}`            — type in :image/:video/:audio/:document/:sticker
    * `{:protocol, type, protocol_message}`       — other protocolMessages (history sync, keys, …)
    * `{:pin, %{key, pinned?}}` / `{:keep, %{key, kept?}}`
    * `{:member_tag, %{label, timestamp}}` — a member's per-group self-label
      changed (`label: ""` means it was removed)
    * `{:group_invite, msg}` / `{:event, msg}`
    * `{:product, msg}` / `{:order, msg}` / `{:button_response, msg}` /
      `{:list_response, msg}` / `{:template_reply, msg}` /
      `{:interactive_response, msg}` — WhatsApp Business / interactive (receive-only)
    * `{:list, msg}` / `{:buttons, msg}` / `{:template, msg}` /
      `{:interactive, msg}` — interactive messages that *present* a set of choices
      (receive-only); see `Amarula.Content.Options`
    * `{:sender_key, skdm}`                        — Signal group-session-key plumbing (filtered before emit)
    * `{:other, message}`                          — anything not yet classified

  WhatsApp may wrap the real content in `deviceSentMessage` (our own other
  devices) or `ephemeralMessage`; those are unwrapped first.
  """

  alias Amarula.Protocol.Proto

  @doc """
  Classify a decrypted message into a tagged tuple.

  ## Examples

      iex> alias Amarula.Protocol.Proto
      iex> Amarula.Protocol.Messages.MessageContent.classify(%Proto.Message{conversation: "hi"})
      {:text, "hi"}

      iex> alias Amarula.Protocol.Proto
      iex> key = %Proto.MessageKey{remoteJid: "x@s.whatsapp.net", id: "ABC"}
      iex> msg = %Proto.Message{reactionMessage: %Proto.Message.ReactionMessage{key: key, text: "👍"}}
      iex> Amarula.Protocol.Messages.MessageContent.classify(msg)
      {:reaction, key, "👍"}
  """
  @spec classify(Proto.Message.t()) :: tuple()
  def classify(%Proto.Message{} = message) do
    message |> unwrap() |> do_classify()
  end

  @doc """
  The `mediatype` stanza attribute for an *outgoing* message (Baileys
  `getMediaType`), unwrapping view-once/ephemeral envelopes first. Returns `nil` for
  a message that carries no media type (plain text, etc.).

  WhatsApp expects this attribute on the `<message>` stanza for media and **silently
  drops view-once video/audio sent without it** (the media is nested inside a
  `viewOnceMessage`, so a naive top-level check misses it) — see #2435 / issue #2678.
  """
  @spec media_type(Proto.Message.t()) :: String.t() | nil
  def media_type(%Proto.Message{} = message) do
    message |> unwrap() |> do_media_type()
  end

  defp do_media_type(%Proto.Message{imageMessage: m}) when not is_nil(m), do: "image"
  defp do_media_type(%Proto.Message{videoMessage: %{gifPlayback: true}}), do: "gif"
  defp do_media_type(%Proto.Message{videoMessage: m}) when not is_nil(m), do: "video"
  defp do_media_type(%Proto.Message{audioMessage: %{ptt: true}}), do: "ptt"
  defp do_media_type(%Proto.Message{audioMessage: m}) when not is_nil(m), do: "audio"
  defp do_media_type(%Proto.Message{contactMessage: m}) when not is_nil(m), do: "vcard"
  defp do_media_type(%Proto.Message{documentMessage: m}) when not is_nil(m), do: "document"

  defp do_media_type(%Proto.Message{contactsArrayMessage: m}) when not is_nil(m),
    do: "contact_array"

  defp do_media_type(%Proto.Message{liveLocationMessage: m}) when not is_nil(m),
    do: "livelocation"

  defp do_media_type(%Proto.Message{stickerMessage: m}) when not is_nil(m), do: "sticker"
  defp do_media_type(%Proto.Message{listMessage: m}) when not is_nil(m), do: "list"

  defp do_media_type(%Proto.Message{listResponseMessage: m}) when not is_nil(m),
    do: "list_response"

  defp do_media_type(%Proto.Message{buttonsResponseMessage: m}) when not is_nil(m),
    do: "buttons_response"

  defp do_media_type(%Proto.Message{orderMessage: m}) when not is_nil(m), do: "order"
  defp do_media_type(%Proto.Message{productMessage: m}) when not is_nil(m), do: "product"

  defp do_media_type(%Proto.Message{interactiveResponseMessage: m}) when not is_nil(m),
    do: "native_flow_response"

  defp do_media_type(%Proto.Message{groupInviteMessage: m}) when not is_nil(m), do: "url"
  defp do_media_type(_message), do: nil

  # Unwrap device-sent / ephemeral envelopes to the inner content message.
  defp unwrap(%Proto.Message{deviceSentMessage: %{message: inner}}) when not is_nil(inner),
    do: unwrap(inner)

  defp unwrap(%Proto.Message{ephemeralMessage: %{message: inner}}) when not is_nil(inner),
    do: unwrap(inner)

  # View-once wrappers (V1/V2/extension) carry the real media inside; unwrap so it
  # classifies as ordinary media. (The "open once" semantics are the recipient
  # app's concern; the content is the same.)
  defp unwrap(%Proto.Message{viewOnceMessage: %{message: inner}}) when not is_nil(inner),
    do: unwrap(inner)

  defp unwrap(%Proto.Message{viewOnceMessageV2: %{message: inner}}) when not is_nil(inner),
    do: unwrap(inner)

  defp unwrap(%Proto.Message{viewOnceMessageV2Extension: %{message: inner}})
       when not is_nil(inner),
       do: unwrap(inner)

  defp unwrap(message), do: message

  defp do_classify(%Proto.Message{conversation: body}) when is_binary(body), do: {:text, body}

  defp do_classify(%Proto.Message{extendedTextMessage: %{text: body}}) when is_binary(body),
    do: {:text, body}

  defp do_classify(%Proto.Message{reactionMessage: %{key: key, text: emoji}})
       when not is_nil(key),
       do: {:reaction, key, emoji || ""}

  # Edits: the new content rides inline as `editedMessage`. Newer clients send an
  # encrypted `secretEncryptedMessage` envelope instead — Connection.handle_message
  # decrypts it (EditEnvelope, #30) back into this legacy shape before classify
  # runs, so both paths land here. An envelope that couldn't be decrypted (no
  # cached secret / expired window) still falls through to `{:other, _}` below.
  defp do_classify(%Proto.Message{
         protocolMessage: %{type: :MESSAGE_EDIT, key: key, editedMessage: edited}
       })
       when not is_nil(key) do
    new_text =
      case edited do
        %Proto.Message{} = m -> text_of(m)
        _ -> nil
      end

    {:edit, key, new_text}
  end

  defp do_classify(%Proto.Message{protocolMessage: %{type: :REVOKE, key: key}})
       when not is_nil(key),
       do: {:revoke, key}

  # A member changed their per-group self-label. Emit even when the label is empty
  # — that IS the removal, which Baileys #2502 dropped by guarding on a truthy
  # label. `label` is "" for a removal; consumers treat "" as "tag cleared".
  defp do_classify(%Proto.Message{
         protocolMessage: %{type: :GROUP_MEMBER_LABEL_CHANGE, memberLabel: %{} = ml}
       }) do
    {:member_tag, %{label: ml.label || "", timestamp: ml.labelTimestamp}}
  end

  defp do_classify(%Proto.Message{protocolMessage: %{type: type} = pm}) when not is_nil(type),
    do: {:protocol, type, pm}

  defp do_classify(%Proto.Message{imageMessage: m}) when not is_nil(m), do: {:media, :image, m}
  defp do_classify(%Proto.Message{videoMessage: m}) when not is_nil(m), do: {:media, :video, m}
  defp do_classify(%Proto.Message{audioMessage: m}) when not is_nil(m), do: {:media, :audio, m}

  defp do_classify(%Proto.Message{documentMessage: m}) when not is_nil(m),
    do: {:media, :document, m}

  defp do_classify(%Proto.Message{stickerMessage: m}) when not is_nil(m),
    do: {:media, :sticker, m}

  defp do_classify(%Proto.Message{contactMessage: m}) when not is_nil(m), do: {:contact, m}

  defp do_classify(%Proto.Message{contactsArrayMessage: m}) when not is_nil(m),
    do: {:contacts, m}

  defp do_classify(%Proto.Message{locationMessage: m}) when not is_nil(m), do: {:location, m}

  defp do_classify(%Proto.Message{pollCreationMessage: m}) when not is_nil(m), do: {:poll, m}
  defp do_classify(%Proto.Message{pollCreationMessageV2: m}) when not is_nil(m), do: {:poll, m}
  defp do_classify(%Proto.Message{pollCreationMessageV3: m}) when not is_nil(m), do: {:poll, m}

  # Votes arrive encrypted; decrypt with PollCrypto.decrypt_vote/2 + the poll secret.
  defp do_classify(%Proto.Message{pollUpdateMessage: m}) when not is_nil(m), do: {:poll_vote, m}

  # A bare senderKeyDistributionMessage is Signal group-session-key plumbing, not a
  # user message: the recipient installs the key so it can decrypt subsequent group
  # messages. The side effect runs in MessageDecryptor; this classification lets the
  # emit path drop it (Connection.signal_control?/1) so consumers never see it. When
  # SKDM rides ALONG WITH real content (group messages attach it to the first
  # message), the content clauses above win and this is never reached.
  defp do_classify(%Proto.Message{senderKeyDistributionMessage: skdm}) when not is_nil(skdm),
    do: {:sender_key, skdm}

  # PTV (round video note) reuses VideoMessage — surface it as media :video.
  defp do_classify(%Proto.Message{ptvMessage: m}) when not is_nil(m), do: {:media, :video, m}

  # Pin / keep updates mirror what we send (Tier-1). Carry the target key + flag.
  defp do_classify(%Proto.Message{pinInChatMessage: %{key: key, type: type}})
       when not is_nil(key),
       do: {:pin, %{key: key, pinned?: type == :PIN_FOR_ALL}}

  defp do_classify(%Proto.Message{keepInChatMessage: %{key: key, keepType: type}})
       when not is_nil(key),
       do: {:keep, %{key: key, kept?: type == :KEEP_FOR_ALL}}

  defp do_classify(%Proto.Message{groupInviteMessage: m}) when not is_nil(m),
    do: {:group_invite, m}

  defp do_classify(%Proto.Message{eventMessage: m}) when not is_nil(m), do: {:event, m}

  # WhatsApp Business / interactive content — a normal linked-device client can't
  # send these, but it can receive them. Surface them typed instead of {:other}.
  defp do_classify(%Proto.Message{productMessage: m}) when not is_nil(m), do: {:product, m}
  defp do_classify(%Proto.Message{orderMessage: m}) when not is_nil(m), do: {:order, m}

  defp do_classify(%Proto.Message{buttonsResponseMessage: m}) when not is_nil(m),
    do: {:button_response, m}

  defp do_classify(%Proto.Message{listResponseMessage: m}) when not is_nil(m),
    do: {:list_response, m}

  defp do_classify(%Proto.Message{templateButtonReplyMessage: m}) when not is_nil(m),
    do: {:template_reply, m}

  defp do_classify(%Proto.Message{interactiveResponseMessage: m}) when not is_nil(m),
    do: {:interactive_response, m}

  # Interactive messages that PRESENT a set of choices (a list menu, buttons, a
  # template, or a native-flow interactive message) — what business / call-center
  # / automated flows send to ask "pick one". Receive-only; the reply comes back
  # as one of the *_response messages above.
  defp do_classify(%Proto.Message{listMessage: m}) when not is_nil(m), do: {:list, m}
  defp do_classify(%Proto.Message{buttonsMessage: m}) when not is_nil(m), do: {:buttons, m}
  defp do_classify(%Proto.Message{templateMessage: m}) when not is_nil(m), do: {:template, m}

  defp do_classify(%Proto.Message{interactiveMessage: m}) when not is_nil(m),
    do: {:interactive, m}

  defp do_classify(message), do: {:other, message}

  @doc """
  Extract the `%Proto.ContextInfo{}` from a message, or `nil`. It lives on whichever
  content sub-message is present (extendedText/image/video/…); we unwrap envelopes
  first and return the first sub-message's `contextInfo`. Carries the reply
  reference (`stanzaId`/`participant`/`quotedMessage`) and `mentionedJid`.
  """
  @spec context_info(Proto.Message.t()) :: Proto.ContextInfo.t() | nil
  def context_info(%Proto.Message{} = message) do
    message |> unwrap() |> sub_message() |> ctx_of()
  end

  @doc """
  The `%Proto.Message.ExtendedTextMessage{}` of an inbound text message (after
  unwrapping device-sent/ephemeral envelopes), or `nil` when the message isn't an
  extended-text message. Callers read its link-preview fields
  (`matchedText`/`title`/`description`/`jpegThumbnail`/`previewType`); see
  `Amarula.Content.LinkPreview`.
  """
  @spec extended_text(Proto.Message.t()) :: Proto.Message.ExtendedTextMessage.t() | nil
  def extended_text(%Proto.Message{} = message) do
    case unwrap(message) do
      %Proto.Message{extendedTextMessage: %Proto.Message.ExtendedTextMessage{} = ext} -> ext
      _ -> nil
    end
  end

  @doc """
  The message's `messageContextInfo.messageSecret`, or `nil`. The
  `messageContextInfo` may sit on the outer message or inside an ephemeral /
  view-once wrapper (`MessageDecryptor` unwraps only `deviceSentMessage`), so
  both are checked. This is the key material a later `secretEncryptedMessage`
  edit envelope targeting this message is encrypted under — `Connection` stashes
  it per message id (`Amarula.MessageSecretStore`).
  """
  @spec message_secret(Proto.Message.t()) :: binary() | nil
  def message_secret(%Proto.Message{} = message) do
    secret_of(message) || message |> unwrap() |> secret_of()
  end

  defp secret_of(%Proto.Message{messageContextInfo: %{messageSecret: secret}})
       when is_binary(secret) and secret != "",
       do: secret

  defp secret_of(_), do: nil

  @doc """
  The message's `%Proto.Message.SecretEncryptedMessage{}` envelope (after
  unwrapping device-sent/ephemeral wrappers), or `nil`. Newer clients send
  message edits this way; see `Amarula.Protocol.Messages.EditEnvelope`.
  """
  @spec secret_envelope(Proto.Message.t()) :: Proto.Message.SecretEncryptedMessage.t() | nil
  def secret_envelope(%Proto.Message{} = message) do
    case unwrap(message) do
      %Proto.Message{secretEncryptedMessage: %Proto.Message.SecretEncryptedMessage{} = env} ->
        env

      _ ->
        nil
    end
  end

  # The content-bearing sub-struct (the one classify keys on), or nil.
  defp sub_message(%Proto.Message{} = m) do
    [
      m.extendedTextMessage,
      m.imageMessage,
      m.videoMessage,
      m.audioMessage,
      m.documentMessage,
      m.stickerMessage,
      m.contactMessage,
      m.contactsArrayMessage,
      m.locationMessage
    ]
    |> Enum.find(&(&1 != nil))
  end

  defp ctx_of(%{contextInfo: %Proto.ContextInfo{} = ctx}), do: ctx
  defp ctx_of(_), do: nil

  defp text_of(%Proto.Message{conversation: b}) when is_binary(b), do: b
  defp text_of(%Proto.Message{extendedTextMessage: %{text: b}}) when is_binary(b), do: b
  defp text_of(_), do: nil
end
