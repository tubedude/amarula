# Proto Message Coverage

A map of `proto/wa_proto.proto`'s `Message` type against what Amarula actually
sends and receives, checked directly against `MessageEncoder`, `MessageContent`,
and the `Amarula` facade — not against this document's own bookkeeping. `Message`
has about 90 content fields; most of the interesting ones are covered.

> **Scope note:** most of the remaining unhandled fields are WhatsApp Business /
> template UX that the server no longer lets a normal linked-device client
> **send** (sends are rejected). Those are only worth handling on **receive**.

## Currently Implemented

**Send** — `Amarula.Protocol.Messages.MessageEncoder` + the `Amarula` facade:

- `conversation` (text), switching to `extendedTextMessage` automatically when a
  reply or mentions are present (`contextInfo`: quoted message + `mentionedJid`)
- `contactMessage` / `contactsArrayMessage`
- `pollCreationMessage` v1 / v2 / v3, and `pollUpdateMessage` (casting a vote)
- `locationMessage` (incl. the `isLive` flag on a static location)
- `reactionMessage`
- media: `imageMessage` / `videoMessage` / `audioMessage` / `documentMessage` /
  `stickerMessage`, plus the view-once wrapper, the PTV (round video note)
  variant, and album parent/child linking (`albumMessage`)
- `eventMessage` (event creation — RSVP responses are not supported; see Gaps)
- `groupInviteMessage`, `pinInChatMessage`, `keepInChatMessage`
- `protocolMessage`: edit (`MESSAGE_EDIT`), revoke (`REVOKE`),
  `PEER_DATA_OPERATION` (placeholder resend, on-demand history),
  `GROUP_MEMBER_LABEL_CHANGE` (per-group member label)

Plus non-`Message` surfaces: presence, chat state, read receipts, groups
(`Amarula.Group`), profile (`Amarula.Profile`), contacts / USync
(`Amarula.Contacts`).

**Receive** — `Amarula.Protocol.Messages.MessageContent.classify/1`:

- text, reaction, edit, revoke, member_tag, media (image/video/audio/document/
  sticker, incl. PTV mapped to `:video`), protocol, sender_key, contact,
  contacts, location, poll, poll_vote
- pin, keep, group_invite, event
- WhatsApp Business / interactive content, receive-only: product, order,
  button_response, list_response, template_reply, interactive_response, list,
  buttons, template, interactive

Everything else falls through to `{:other, message}`. Inbound `contextInfo`
(quoted reply + mentions) is decoded in `Amarula.Msg` regardless of message type.

## Gaps Worth Implementing

### Live location

`liveLocationMessage` is a distinct message from the `isLive` flag Amarula
already sets on a static `locationMessage`. It supports streaming updates
(`sequenceNumber`, speed/heading) and isn't sent, or classified on receive —
both directions fall through today. Worth adding if a consumer needs live
tracking rather than a one-shot pin.

### Event RSVP

Amarula can create and send an event (`send_event`), but can't send or decode
an RSVP response — that's `encEventResponseMessage`, an encrypted envelope with
its own crypto seam, similar to poll votes (`PollCrypto`). Not yet built.

### Reply/quoted for `secretEncryptedMessage`-based edits

Not in scope for this document's "reply" gap, but a related known limitation:
edits from newer WhatsApp clients arrive as `secretEncryptedMessage`
(`secretEncType: :MESSAGE_EDIT`), an extra encryption layer keyed by the
original message's `messageContextInfo.messageSecret`. Amarula only decodes the
legacy inline `editedMessage`; the new envelope falls through to `{:other, _}`
still encrypted. See the `KNOWN GAP` comment on the `:MESSAGE_EDIT` clause in
`message_content.ex` for what's needed (a TTL cache of inbound message secrets +
HMAC+GCM decrypt).

### Receive-side classification for the remaining Business/payment fields

`invoiceMessage`, the payment family (`sendPaymentMessage` /
`requestPaymentMessage` / `declinePaymentRequestMessage` /
`cancelPaymentRequestMessage`), `newsletterAdminInviteMessage`, and the
scheduled-call messages (`scheduledCallCreationMessage` /
`scheduledCallEditMessage`) still fall through to `{:other, message}` on
receive. Sending them from a linked-device client generally fails server-side,
so send support isn't worth building, but decode-only `classify/1` clauses
would let a consumer at least react to them. Low priority — these are
Business-account-specific flows most consumers won't hit.

### Receive-side classification for `albumMessage`

Amarula can send an album (parent + child media), but an inbound album falls
through to `{:other, message}` — there's no `classify/1` clause pairing an
album's children back to their parent on receive.

## Recommended Order

Start with **live location** if a consumer needs it — it's a contained addition
to the existing location path (see `MessageEncoder.location/3` and
`MessageContent.do_media_type/1`, which already recognizes
`liveLocationMessage` for the `mediatype` stanza attribute but has no send
builder or `classify/1` clause). Event RSVP and the remaining Business/payment
receive clauses are lower priority — they gate on demand from consumers who
actually need them.
