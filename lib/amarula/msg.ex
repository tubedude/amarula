defmodule Amarula.Msg do
  @moduledoc """
  A received message, in consumer terms — the friendly view of a decrypted
  `%Proto.Message{}`. This is what `{:whatsapp, :messages_upsert, %{messages:
  [%Msg{}]}}` carries, so a consumer never has to pattern-match the (large) WA
  protobuf.

  `type` + `content` are derived from the message body:

  | `type`        | `content`                                              |
  |---------------|--------------------------------------------------------|
  | `:text`       | the text `String.t()`                                  |
  | `:media`      | `%{kind: :image\|:video\|:audio\|:document\|:sticker, media: struct}` — pass to `Amarula.download_media/2` |
  | `:reaction`   | `%{key: MessageKey, emoji: String.t()}` (`""` = removed) |
  | `:edit`       | `%{key: MessageKey, text: String.t()}`                 |
  | `:revoke`     | `%{key: MessageKey}`                                    |
  | `:contact`    | the contact message struct                             |
  | `:location`   | the location message struct                            |
  | `:poll`       | the poll-creation struct                               |
  | `:poll_vote`  | the poll-update struct                                 |
  | `:protocol`   | `%{type: atom, message: struct}` (app-state keys, …)   |
  | `:other`      | `nil`                                                  |

  `raw` is always the underlying `%Proto.Message{}` — the escape hatch for
  anything not surfaced here.
  """

  alias Amarula.Address
  alias Amarula.Protocol.Messages.MessageContent
  alias Amarula.Protocol.Proto

  @type media_kind :: :image | :video | :audio | :document | :sticker

  @type t :: %__MODULE__{
          id: String.t() | nil,
          chat: Address.t(),
          sender: Address.t() | nil,
          from_me: boolean(),
          timestamp: integer() | nil,
          type: atom(),
          content: term(),
          raw: Proto.Message.t()
        }

  @enforce_keys [:chat, :type, :raw]
  defstruct [:id, :chat, :sender, :from_me, :timestamp, :type, :content, :raw]

  @doc """
  Build a `%Msg{}` from a decrypted proto and its envelope.

  `meta` carries the stanza fields: `:id`, `:chat` (an `Address`), `:sender`
  (`Address` of the actual author in a group, else nil), `:from_me`, `:timestamp`.
  """
  @spec from_proto(Proto.Message.t(), map()) :: t()
  def from_proto(%Proto.Message{} = proto, meta) do
    {type, content} = classify(proto)

    %__MODULE__{
      id: meta[:id],
      chat: meta[:chat],
      sender: meta[:sender],
      from_me: meta[:from_me] || false,
      timestamp: meta[:timestamp],
      type: type,
      content: content,
      raw: proto
    }
  end

  # Map the internal classify tuple to a {type, friendly-content} pair.
  defp classify(proto) do
    case MessageContent.classify(proto) do
      {:text, body} -> {:text, body}
      {:media, kind, m} -> {:media, %{kind: kind, media: m}}
      {:reaction, key, emoji} -> {:reaction, %{key: key, emoji: emoji}}
      {:edit, key, text} -> {:edit, %{key: key, text: text}}
      {:revoke, key} -> {:revoke, %{key: key}}
      {:protocol, t, m} -> {:protocol, %{type: t, message: m}}
      {tag, payload} -> {tag, payload}
    end
  end
end
