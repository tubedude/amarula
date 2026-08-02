defmodule Amarula.Msg do
  @moduledoc """
  A received message in consumer terms — the friendly view of a decrypted
  `%Proto.Message{}`. Delivered in `{:amarula, :messages_upsert, %{messages:
  [%Msg{}]}}`, so consumers never pattern-match the large WA protobuf.

  `type` + `content` are derived from the message body.

  **The rule:** `content` is an `Amarula.Content.*` struct (never a raw protobuf),
  except `:text` (a `String.t()`) and `:other` (`nil`). The raw `%Proto.Message{}`
  is always on `raw`. Any `key`/`poll_key` is a `t:ref/0` — a `{chat, id, from_me}`
  tuple (plus `participant` for a group target), already **remapped to your
  perspective** (`from_me` = whether the target is a message *you* sent), so you can
  pass a received reaction's `key` straight to `Amarula.send_reaction/3`.

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
  | `:list` / `:buttons` / `:template` | `Amarula.send_options_reply/4` (pick one of the prompt's options — this replies to the prompt, it does not originate a new one) |

  **Receive-only** (no originating send): `:product`, `:order`, and originating a
  new `:list`/`:buttons`/`:template`/`:interactive` *prompt* — only Meta-approved
  Business integrations may do that; a normal account can reply to one (see the
  table above) but not send one from scratch. `:interactive_response`
  (a native-flow reply) also has no send helper yet — `send_options_reply/4`
  covers button/list/template replies only. Event RSVP responses are not yet
  supported either.

  ## Addressing — `channel`, `from`, `to`

  Every message carries three address roles, each an `Amarula.Address`:

  | role      | meaning                                                  | 1:1 DM       | group         | self-chat       |
  |-----------|----------------------------------------------------------|--------------|---------------|-----------------|
  | `channel` | the room it was published to — **the reply handle**      | the peer     | the **group** | me              |
  | `from`    | who **wrote** it (carries the sending **device**)        | the peer / me| the participant | me (+device)  |
  | `to`      | who it was **addressed to** — the real recipient         | the peer / me| the group     | me              |

  To **reply**, put `msg.channel` straight into a send's target — it routes back to the
  same conversation. In a **1:1, `from == channel`** apart from the device (see below);
  in a **group, `from` (the participant) ≠ `channel` (the group)**.

  > #### `channel` is account-level; `from` is device-level {: .info}
  >
  > `channel` never carries a device — it is normalized to the account address, so it
  > is always safe as a send target. `from` **does** carry the sending device when the
  > peer wrote from a linked device (WhatsApp Web, desktop), because the writer
  > identity is per-device.
  >
  > So reply with `msg.channel`, not `msg.from`. Sending to a device-bound jid
  > (`5511999999999:29@s.whatsapp.net`) is rejected by the server with
  > `{:error, {:send_rejected, "400"}}` — nothing on the send path strips it for you.
  > If you must build a target from `msg.from`, run it through
  > `Amarula.Address.normalize/1` first.

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

  > #### Non-nil is not the same as addressable {: .warning}
  >
  > An address can be present and still have nowhere to send: `Amarula.Address`
  > parses a jid whose chat kind we don't model yet (`@hosted`, `status@broadcast`,
  > `@newsletter`) to `kind: :unsupported`, carrying its raw `server`. You'll meet
  > these mainly as `from` — a `@hosted` business account writing in an ordinary
  > group — and on history-synced status posts.
  >
  > They compare and inspect like any address, but every send refuses them with
  > `{:error, {:unsupported, server}}` rather than guessing a destination. Check
  > `Amarula.Address.unsupported?/1` before replying to an address that came off
  > the wire. Live messages *from* such a chat are not delivered at all (the router
  > declines them) until the kind is implemented.

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
  A reference to a target message, as carried on a received reaction/edit/revoke/
  pin/keep/poll-vote `key`. A `{chat, id, from_me}` tuple (plus `participant` for a
  group target), already remapped to **your** perspective — so you can feed it
  straight to `Amarula.send_reaction/3`, `send_edit/3`, `Amarula.send_poll_vote/5`,
  etc. `from_me` is whether the target message is one **you** sent.
  """
  @type ref ::
          {chat :: String.t(), id :: String.t(), from_me :: boolean()}
          | {chat :: String.t(), id :: String.t(), from_me :: boolean(),
             participant :: String.t()}

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

  `:channel` is normalized to its account-level address here (device stripped) — it
  is the reply handle, and a device-bound one is rejected on send. `:from` keeps its
  device. See the "Addressing" section above.
  """
  @spec from_proto(Proto.Message.t(), map()) :: t()
  def from_proto(%Proto.Message{} = proto, meta) do
    {type, content} = classify(proto)
    ctx = MessageContent.context_info(proto)
    channel = normalize_channel(meta[:channel])

    %__MODULE__{
      id: meta[:id],
      channel: channel,
      from: meta[:from],
      to: meta[:to],
      from_me: meta[:from_me] || false,
      pushname: meta[:pushname],
      timestamp: meta[:timestamp],
      type: type,
      content: content,
      quoted: quoted(ctx, channel),
      mentions: mentions(ctx),
      forwarded: forwarded?(ctx),
      preview: link_preview(proto),
      raw: proto
    }
  end

  @doc """
  The message's `messageContextInfo.messageSecret`, or `nil`.

  Newer WhatsApp clients encrypt a message *edit* under the original message's
  secret. To decrypt those edits after a restart, persist this secret (keyed by
  `msg.id`) alongside the message when you handle `:messages_upsert`, and serve it
  back via an `Amarula.MessageSecretStore.ReadOnly` adapter. Also persist the
  message's `from` (its server-attested sender) — the store's author check
  compares against it.

      def handle_info({:amarula, :messages_upsert, %{messages: msgs}}, state) do
        for m <- msgs do
          MyApp.Messages.save(m.id, secret: Amarula.Msg.message_secret(m), sender: m.from)
        end
        {:noreply, state}
      end

  The default in-memory store handles this automatically; you only need it when
  you want edits to survive a connection restart. See `Amarula.MessageSecretStore`.
  """
  @spec message_secret(t()) :: binary() | nil
  def message_secret(%__MODULE__{raw: %Proto.Message{} = proto}),
    do: MessageContent.message_secret(proto)

  def message_secret(%__MODULE__{}), do: nil

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
    channel = normalize_channel(address(ctx.remoteJid)) || channel

    inner =
      case ctx.quotedMessage do
        %Proto.Message{} = qm -> nested_msg(qm, id, channel, from || channel)
        _ -> nil
      end

    %{id: id, from: from, channel: channel, message: inner}
  end

  defp quoted(_ctx, _channel), do: nil

  # `channel` is the reply handle, so it must name the ACCOUNT, not one device.
  # A DM stanza's `from` carries the sending device (Signal sessions are per-device
  # — see `LidMappingFileStore.signal_address/2`), and a DM has no `participant` to
  # distinguish writer from room, so the room would otherwise inherit that device.
  # Replying to `5511999999999:29@s.whatsapp.net` is rejected by the server with
  # `<ack class="message" error="400">` → `{:error, {:send_rejected, "400"}}`, because
  # nothing on the send path normalizes the target (issue #41).
  # `nil` passes through: `from_proto/2` never fabricates an address (decrypt-failure
  # path), and `quoted/2` relies on nil to fall back to the outer channel.
  defp normalize_channel(nil), do: nil
  defp normalize_channel(%Address{} = channel), do: Address.normalize(channel)

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

  # `context_info/1` yields nil or a %ContextInfo{}, whose mentionedJid is always
  # a list (proto3 repeated field), so these two clauses are total.
  defp mentions(nil), do: []

  # Unparseable mentions are dropped rather than carried as nil (#50). A mention of
  # a `@hosted` user arrives inside an ordinary group message, so the router gate
  # never sees it — and a nil in this list is a live grenade: the documented
  # round-trip `send_text(conn, chan, text, mentions: msg.mentions)` feeds it to
  # `to_jid!/1` inside the Connection GenServer. Dropping also makes the list match
  # its declared `[Address.t()]` type.
  defp mentions(%Proto.ContextInfo{mentionedJid: jids}) when is_list(jids),
    do: jids |> Enum.map(&Address.parse/1) |> Enum.reject(&is_nil/1)

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

  # A %Proto.MessageKey{} → a widened message_ref (the form the send API takes),
  # or nil. Carries `from_me` (and `participant` for a group target) so the ref
  # round-trips back through `Amarula.send_reaction/3` etc. correctly — the key was
  # already remapped to our perspective upstream (`Connection.normalize_reply_keys`,
  # #47), so this is a pure widening, no identity logic here.
  defp ref(%Proto.MessageKey{remoteJid: jid, id: id, fromMe: from_me, participant: p})
       when is_binary(jid) and is_binary(id) and is_binary(p) and p != "",
       do: {jid, id, from_me == true, p}

  defp ref(%Proto.MessageKey{remoteJid: jid, id: id, fromMe: from_me})
       when is_binary(jid) and is_binary(id),
       do: {jid, id, from_me == true}

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
