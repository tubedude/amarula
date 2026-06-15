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

  @doc "Encode a `%Proto.Message{}` (or message map) and append random PKCS-style pad."
  @spec encode(struct() | map()) :: binary()
  def encode(message) do
    message
    |> to_proto()
    |> Proto.Message.encode()
    |> pad_random_max16()
  end

  @doc "Build a plain-text conversation message."
  @spec text(String.t()) :: Proto.Message.t()
  def text(body) when is_binary(body) do
    %Proto.Message{conversation: body}
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

    media_message(type, common, opts)
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
    %Proto.Message{
      audioMessage:
        struct(Proto.Message.AudioMessage, Map.merge(common, take(opts, [:seconds, :ptt])))
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
