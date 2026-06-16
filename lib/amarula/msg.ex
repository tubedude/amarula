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

  Pure Signal-protocol plumbing (a bare `senderKeyDistributionMessage`) is applied
  internally and never emitted as a `%Msg{}` — consumers do not see it. Every `%Msg{}`
  delivered via `:messages_upsert` therefore has a non-nil `chat`. The struct itself
  still permits `chat: nil` (`from_proto/2` is total), so the type is `Address.t() | nil`.
  """

  alias Amarula.Address
  alias Amarula.Protocol.Messages.MessageContent
  alias Amarula.Protocol.Proto

  @type media_kind :: :image | :video | :audio | :document | :sticker

  @typedoc """
  A quoted message a reply points at. `id`/`participant` identify the original;
  `message` is the partial copy WhatsApp inlines (a nested `%Amarula.Msg{}`),
  enough to show the quote without a lookup. Use `Amarula.resolve_quoted/2` to
  fetch the FULL original (cache → server) when the inline copy isn't enough.
  """
  @type quoted :: %{
          id: String.t(),
          participant: Address.t() | nil,
          chat: Address.t() | nil,
          message: t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t() | nil,
          chat: Address.t() | nil,
          sender: Address.t() | nil,
          from_me: boolean(),
          timestamp: integer() | nil,
          type: atom(),
          content: term(),
          quoted: quoted() | nil,
          mentions: [Address.t()],
          raw: Proto.Message.t()
        }

  @enforce_keys [:chat, :type, :raw]
  defstruct [
    :id,
    :chat,
    :sender,
    :from_me,
    :timestamp,
    :type,
    :content,
    :quoted,
    :raw,
    mentions: []
  ]

  @doc """
  Build a `%Msg{}` from a decrypted proto and its envelope.

  `meta` carries the stanza fields: `:id`, `:chat` (an `Address`), `:sender`
  (`Address` of the actual author in a group, else nil), `:from_me`, `:timestamp`.
  """
  @spec from_proto(Proto.Message.t(), map()) :: t()
  def from_proto(%Proto.Message{} = proto, meta) do
    {type, content} = classify(proto)
    ctx = MessageContent.context_info(proto)

    %__MODULE__{
      id: meta[:id],
      chat: meta[:chat],
      sender: meta[:sender],
      from_me: meta[:from_me] || false,
      timestamp: meta[:timestamp],
      type: type,
      content: content,
      quoted: quoted(ctx, meta[:chat]),
      mentions: mentions(ctx),
      raw: proto
    }
  end

  # Build the `quoted` view from a message's contextInfo (nil if not a reply).
  # The inlined quotedMessage is wrapped as a nested %Msg{} so consumers read it
  # the same way as any message. Capped at ONE level: WhatsApp only inlines the
  # immediate quoted message, and a nested quote inside it is ignored (no
  # unbounded recursion on crafted input).
  defp quoted(nil, _chat), do: nil

  defp quoted(%Proto.ContextInfo{stanzaId: id} = ctx, chat) when is_binary(id) and id != "" do
    participant = address(ctx.participant)

    inner =
      case ctx.quotedMessage do
        %Proto.Message{} = qm -> nested_msg(qm, id, chat, participant)
        _ -> nil
      end

    %{id: id, participant: participant, chat: address(ctx.remoteJid) || chat, message: inner}
  end

  defp quoted(_ctx, _chat), do: nil

  # The inlined quoted message as a %Msg{} WITHOUT its own `quoted` (one level only).
  defp nested_msg(%Proto.Message{} = proto, id, chat, sender) do
    {type, content} = classify(proto)

    %__MODULE__{
      id: id,
      chat: chat,
      sender: sender,
      from_me: false,
      type: type,
      content: content,
      quoted: nil,
      mentions: [],
      raw: proto
    }
  end

  defp mentions(nil), do: []

  defp mentions(%Proto.ContextInfo{mentionedJid: jids}) when is_list(jids),
    do: Enum.map(jids, &Address.parse/1)

  defp mentions(_), do: []

  defp address(nil), do: nil
  defp address(""), do: nil
  defp address(jid) when is_binary(jid), do: Address.parse(jid)

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
