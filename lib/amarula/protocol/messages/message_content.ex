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
    * `{:group_invite, msg}` / `{:event, msg}`
    * `{:product, msg}` / `{:order, msg}` / `{:button_response, msg}` /
      `{:list_response, msg}` / `{:template_reply, msg}` /
      `{:interactive_response, msg}` — WhatsApp Business / interactive (receive-only)
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
