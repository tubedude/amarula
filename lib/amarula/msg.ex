defmodule Amarula.Msg do
  @moduledoc """
  A received message in consumer terms — the friendly view of a decrypted
  `%Proto.Message{}`. Delivered in `{:amarula, :messages_upsert, %{messages:
  [%Msg{}]}}`, so consumers never pattern-match the large WA protobuf.

  `type` + `content` are derived from the message body.

  **The rule:** `content` is an `Amarula.Content.*` struct (never a raw protobuf),
  except `:text` (a `String.t()`) and `:other` (`nil`). The raw `%Proto.Message{}`
  is always on `raw`. Any `key`/`poll_key` is a `{jid, msg_id}` reference — the same
  form the send API takes, so you can pass a received reaction's `key` straight to
  `Amarula.send_reaction/3`.

  | `type`        | `content`                                              |
  |---------------|--------------------------------------------------------|
  | `:text`       | the text `String.t()`                                  |
  | `:media`      | `%Amarula.Content.Media{}`                             |
  | `:reaction`   | `%Amarula.Content.Reaction{}` (`emoji: ""` = removed)  |
  | `:edit`       | `%Amarula.Content.Edit{}`                              |
  | `:revoke`     | `%Amarula.Content.Revoke{}`                            |
  | `:pin`        | `%Amarula.Content.Pin{}`                               |
  | `:keep`       | `%Amarula.Content.Keep{}`                              |
  | `:member_tag` | `%Amarula.Content.MemberTag{}`                         |
  | `:contact`    | `%Amarula.Content.Contact{}`                           |
  | `:contacts`   | `%Amarula.Content.Contacts{}`                          |
  | `:location`   | `%Amarula.Content.Location{}`                          |
  | `:poll`       | `%Amarula.Content.Poll{}`                              |
  | `:poll_vote`  | `%Amarula.Content.PollVote{}`                          |
  | `:event`      | `%Amarula.Content.Event{}`                             |
  | `:group_invite` | `%Amarula.Content.GroupInvite{}`                     |
  | `:product`    | `%Amarula.Content.Product{}` (minimal — detail on `raw`) |
  | `:order`      | `%Amarula.Content.Order{}` (minimal — detail on `raw`) |
  | `:button_response` / `:list_response` / `:template_reply` / `:interactive_response` | `%Amarula.Content.Response{}` |
  | `:list` / `:buttons` / `:template` / `:interactive` | `%Amarula.Content.Options{}` (a presented set of choices) |
  | `:protocol`   | `%Amarula.Content.Protocol{}` (control frame) — arrives on `:protocol_update` |
  | `:other`      | `nil` (read `raw`)                                     |

  Pure Signal-protocol plumbing (a bare `senderKeyDistributionMessage`) is applied
  internally and never emitted as a `%Msg{}` — consumers do not see it.

  ## Replying in kind

  Most received types have a matching `send_*` to reproduce or respond:

  | received `type`        | send with                                            |
  |------------------------|------------------------------------------------------|
  | `:text`                | `Amarula.send_text/4`                                |
  | `:media`               | `Amarula.send_media/5`                               |
  | `:reaction`            | `Amarula.send_reaction/3` (pass `content.key`)       |
  | `:edit` / `:revoke`    | `Amarula.send_edit/3` / `send_revoke/2`              |
  | `:pin` / `:keep`       | `Amarula.pin_message/2` / `keep_message/2`           |
  | `:location`            | `Amarula.send_location/5`                            |
  | `:poll`                | `Amarula.send_poll/5`                                |
  | `:poll_vote`           | `Amarula.send_poll_vote/5`                           |
  | `:contact` / `:contacts` | `Amarula.send_contact/4` / `send_contacts/4`       |
  | `:event`               | `Amarula.send_event/4`                               |
  | `:group_invite`        | `Amarula.send_group_invite/5`                        |
  | `:member_tag`          | `Amarula.update_member_tag/3` (group is `msg.channel`) |

  **Receive-only** (no originating send): `:product`, `:order`, the interactive
  replies (`:button_response`/`:list_response`/`:template_reply`/`:interactive_response`
  — you receive a user's choice, but originating the buttons/list isn't supported),
  and the interactive *prompts* (`:list`/`:buttons`/`:template`/`:interactive` — you
  receive a presented set of choices but can't send one). Event RSVP responses are
  not yet supported either.

  ## Addressing — `channel`, `from`, `to`

  Every message carries three address roles, each an `Amarula.Address`:

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

  `channel`/`from`/`to` are typed `Address.t() | nil` because `from_proto/2` never
  fails on a missing field — it copies `meta` verbatim, which a directly-constructed
  `%Msg{}` may leave nil. In
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

  ## `forwarded`

  `forwarded` is `true` when the message was forwarded from another chat
  (`ContextInfo.isForwarded` on the wire), else `false`. The forward *score* (how
  many hops — WhatsApp shows "forwarded many times" at ≥ 5) isn't surfaced here;
  read `ContextInfo.forwardingScore` off `msg.raw` if you need it.

  ## `preview`

  `preview` is the link-preview card a `:text` message carries for a URL it
  contains — an `%Amarula.Content.LinkPreview{}` with `url`/`title`/`description`/
  `thumbnail`/`type`, or `nil` when the message has no preview. It rides
  alongside the text (the `type` stays `:text` and `content` stays the body
  string); a plain text message, or a reply/mention with no link, has `nil`.
  Amarula surfaces previews it *receives*; sending them isn't supported yet.
  """

  alias Amarula.Address
  alias Amarula.Content
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
          forwarded: boolean(),
          preview: Content.LinkPreview.t() | nil,
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
    :preview,
    :raw,
    forwarded: false,
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
      forwarded: forwarded?(ctx),
      preview: link_preview(proto),
      raw: proto
    }
  end

  # Link-preview card for a text message carrying a URL, or nil (see
  # Amarula.Content.LinkPreview). Reads the (unwrapped) extendedTextMessage.
  defp link_preview(proto) do
    proto |> MessageContent.extended_text() |> Content.LinkPreview.from_proto()
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
      forwarded: forwarded?(MessageContent.context_info(proto)),
      preview: link_preview(proto),
      raw: proto
    }
  end

  defp mentions(nil), do: []

  defp mentions(%Proto.ContextInfo{mentionedJid: jids}) when is_list(jids),
    do: Enum.map(jids, &Address.parse/1)

  defp mentions(_), do: []

  # Whether the message was forwarded (ContextInfo.isForwarded, field 22). The
  # proto3-optional field is nil when unset, so only an explicit `true` counts.
  defp forwarded?(%Proto.ContextInfo{isForwarded: true}), do: true
  defp forwarded?(_), do: false

  defp address(nil), do: nil
  defp address(""), do: nil
  defp address(jid) when is_binary(jid), do: Address.parse(jid)

  # Map the internal classify tuple to a {type, proto-free content} pair. Every
  # branch here MUST yield content with no `%Proto.*{}` value (the raw proto is on
  # `msg.raw`); see `Amarula.Content.*` and the guard test.
  defp classify(proto) do
    case MessageContent.classify(proto) do
      {:text, body} ->
        {:text, body}

      {:media, kind, m} ->
        {:media, Content.Media.from_proto(kind, m)}

      # key-bearing types: surface the target key as a {jid, msg_id} ref.
      {:reaction, key, emoji} ->
        {:reaction, %Content.Reaction{key: ref(key), emoji: emoji}}

      {:edit, key, text} ->
        {:edit, %Content.Edit{key: ref(key), text: text}}

      {:revoke, key} ->
        {:revoke, %Content.Revoke{key: ref(key)}}

      {:pin, %{key: key, pinned?: p}} ->
        {:pin, %Content.Pin{key: ref(key), pinned?: p}}

      {:keep, %{key: key, kept?: k}} ->
        {:keep, %Content.Keep{key: ref(key), kept?: k}}

      {:member_tag, %{label: label, timestamp: ts}} ->
        {:member_tag, %Content.MemberTag{label: label, timestamp: ts}}

      # structured types: normalized Content structs.
      {:contact, m} ->
        {:contact, Content.Contact.from_proto(m)}

      {:contacts, m} ->
        {:contacts, Content.Contacts.from_proto(m)}

      {:location, m} ->
        {:location, Content.Location.from_proto(m)}

      {:poll, m} ->
        {:poll, Content.Poll.from_proto(m)}

      {:poll_vote, m} ->
        {:poll_vote, poll_vote(m)}

      {:event, m} ->
        {:event, Content.Event.from_proto(m)}

      {:group_invite, m} ->
        {:group_invite, Content.GroupInvite.from_proto(m)}

      # business / interactive: minimal structs; full detail via msg.raw.
      {:product, m} ->
        {:product, Content.Product.from_proto(m)}

      {:order, m} ->
        {:order, Content.Order.from_proto(m)}

      {:button_response, m} ->
        {:button_response, Content.Response.from_proto(:button, m)}

      {:list_response, m} ->
        {:list_response, Content.Response.from_proto(:list, m)}

      {:template_reply, m} ->
        {:template_reply, Content.Response.from_proto(:template, m)}

      {:interactive_response, m} ->
        {:interactive_response, Content.Response.from_proto(:interactive, m)}

      # interactive messages presenting a set of choices → unified Options struct.
      {:list, m} ->
        {:list, Content.Options.from_proto(:list, m)}

      {:buttons, m} ->
        {:buttons, Content.Options.from_proto(:buttons, m)}

      {:template, m} ->
        {:template, Content.Options.from_proto(:template, m)}

      {:interactive, m} ->
        {:interactive, Content.Options.from_proto(:interactive, m)}

      # control: the type tag only; detail (and the proto) stays on msg.raw.
      {:protocol, t, _pm} ->
        {:protocol, %Content.Protocol{type: t}}

      # :other (and anything unmapped) carries no content — read msg.raw.
      {:other, _proto} ->
        {:other, nil}

      {tag, _payload} ->
        {tag, nil}
    end
  end

  # A %Proto.MessageKey{} → a {jid, msg_id} message_ref (the form the send API
  # takes), or nil. Drops fromMe/participant — available on msg.raw if needed.
  defp ref(%Proto.MessageKey{remoteJid: jid, id: id}), do: {jid, id}
  defp ref(_), do: nil

  # PollUpdateMessage → %Content.PollVote{}: the poll being voted on + the encrypted
  # vote payload. Decrypt with PollCrypto + the poll's enc_key (see Content.PollVote).
  defp poll_vote(%{} = m) do
    enc = Map.get(m, :vote) || %{}

    %Content.PollVote{
      poll_key: ref(Map.get(m, :pollCreationMessageKey)),
      enc_vote: %{payload: Map.get(enc, :encPayload), iv: Map.get(enc, :encIv)},
      timestamp: Map.get(m, :senderTimestampMs)
    }
  end
end
