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

  defp do_classify(message), do: {:other, message}

  defp text_of(%Proto.Message{conversation: b}) when is_binary(b), do: b
  defp text_of(%Proto.Message{extendedTextMessage: %{text: b}}) when is_binary(b), do: b
  defp text_of(_), do: nil
end
