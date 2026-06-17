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
  internally and never emitted as a `%Msg{}` — consumers do not see it.

  ## Addressing — `channel`, `from`, `to`

  Every message carries three address roles, each an `Amarula.Address` (terms chosen
  to read across chat / PubSub / generic messaging, not just WhatsApp):

  | role      | meaning                                                  | 1:1 DM       | group         | self-chat       |
  |-----------|----------------------------------------------------------|--------------|---------------|-----------------|
  | `channel` | the room it was published to — **the reply handle**      | the peer     | the **group** | me              |
  | `from`    | who **wrote** it (carries the sending **device**)        | the peer / me| the participant | me (+device)  |
  | `to`      | who it was **addressed to** — the real recipient         | the peer / me| the group     | me              |

  To **reply**, put `msg.channel` straight into a send's target — it routes back to the
  same conversation. In a **1:1, `from == channel`**; in a **group, `from` (the
  participant) ≠ `channel` (the group)**.

  ## `from_me` and the real recipient

  WhatsApp's multi-device model **fans every message you send out to your linked
  devices** as a `from_me` message. The stanza's `from` is then your *own* account, not
  the peer — so for a `from_me` message the receive path derives `channel` and `to` from
  the stanza's `recipient` (the actual other party), not from `from`. This means `to` is
  the **real recipient**: it tells "I messaged myself" apart from "I messaged someone
  else", which `from`/`channel` alone cannot (both collapse to your account on a linked
  device).

  So a **self-chat command channel** — talking to an agent by messaging yourself — is
  `Amarula.own_chat?/2` (no device comparison: the sending device isn't recoverable for
  own messages — WhatsApp strips it from the writer jid):

      if Amarula.own_chat?(conn, msg) do
        handle_self_command(msg)   # the user messaged themselves → drive the agent
      end

  `own_chat?/2` handles the LID/PN duality (the self chat may be addressed by either our
  PN or our LID) by matching `to` against both of our own identities.

  **No echo on a single connection.** WhatsApp delivers a message only to the devices it
  was encrypted for, and the send path excludes our *own* sending device from that set.
  So a reply this connection sends to the self chat is delivered to our *other* devices
  (phone, other companions) but is **not** delivered back to us — there is no feedback
  loop, and you do **not** need to dedupe your own sends. (The only exception is running
  **two connections on the same account**: each then receives the other's sends, since
  they're different devices — there, dedupe cross-connection by the `msg_id` you got from
  the send.)

  `channel`/`from`/`to` are typed `Address.t() | nil` because `from_proto/2` is total
  (it copies `meta` verbatim, which a directly-constructed `%Msg{}` may leave nil). In
  practice every top-level `%Msg{}` emitted on `:messages_upsert` has a non-nil
  `channel`, `from`, and `to` — the receive path derives them from the stanza and our
  creds. The one exception is a **nested quoted message** (`quoted.message`): it carries
  `channel`/`from` but `to: nil` (a quote isn't independently addressed to you).

  ## `pushname`

  `pushname` is the sender's display name as it rides on the inbound stanza (the
  `notify` attr WhatsApp ships alongside `participant`/`from`). It lets a consumer name
  a contact the moment they message — no re-pairing, no separate contact fetch — even
  for someone WhatsApp only addresses by LID/number. It's `nil` for our own
  (`from_me`) messages and any stanza without the attr.
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
          from: Address.t() | nil,
          channel: Address.t() | nil,
          message: t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t() | nil,
          channel: Address.t() | nil,
          from: Address.t() | nil,
          to: Address.t() | nil,
          from_me: boolean(),
          pushname: String.t() | nil,
          timestamp: integer() | nil,
          type: atom(),
          content: term(),
          quoted: quoted() | nil,
          mentions: [Address.t()],
          raw: Proto.Message.t()
        }

  @enforce_keys [:channel, :type, :raw]
  defstruct [
    :id,
    :channel,
    :from,
    :to,
    :from_me,
    :pushname,
    :timestamp,
    :type,
    :content,
    :quoted,
    :raw,
    mentions: []
  ]

  @doc """
  Build a `%Msg{}` from a decrypted proto and its envelope.

  `meta` carries the stanza fields: `:id`, `:channel` (the room `Address`), `:from`
  (the writer `Address` — participant in a group, else the channel), `:to` (the
  addressed identity `Address`), `:from_me`, `:pushname` (the sender's display name
  off the stanza, `nil` when absent), `:timestamp`.
  """
  @spec from_proto(Proto.Message.t(), map()) :: t()
  def from_proto(%Proto.Message{} = proto, meta) do
    {type, content} = classify(proto)
    ctx = MessageContent.context_info(proto)

    %__MODULE__{
      id: meta[:id],
      channel: meta[:channel],
      from: meta[:from],
      to: meta[:to],
      from_me: meta[:from_me] || false,
      pushname: meta[:pushname],
      timestamp: meta[:timestamp],
      type: type,
      content: content,
      quoted: quoted(ctx, meta[:channel]),
      mentions: mentions(ctx),
      raw: proto
    }
  end

  # Build the `quoted` view from a message's contextInfo (nil if not a reply).
  # The inlined quotedMessage is wrapped as a nested %Msg{} so consumers read it
  # the same way as any message. Capped at ONE level: WhatsApp only inlines the
  # immediate quoted message, and a nested quote inside it is ignored (no
  # unbounded recursion on crafted input).
  defp quoted(nil, _channel), do: nil

  defp quoted(%Proto.ContextInfo{stanzaId: id} = ctx, channel) when is_binary(id) and id != "" do
    from = address(ctx.participant)
    channel = address(ctx.remoteJid) || channel

    inner =
      case ctx.quotedMessage do
        %Proto.Message{} = qm -> nested_msg(qm, id, channel, from || channel)
        _ -> nil
      end

    %{id: id, from: from, channel: channel, message: inner}
  end

  defp quoted(_ctx, _channel), do: nil

  # The inlined quoted message as a %Msg{} WITHOUT its own `quoted` (one level only).
  defp nested_msg(%Proto.Message{} = proto, id, channel, from) do
    {type, content} = classify(proto)

    %__MODULE__{
      id: id,
      channel: channel,
      from: from,
      to: nil,
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
