# Proto message coverage

A review of `proto/wa_proto.proto` against what Amarula currently sends and
receives, and which still-unimplemented message types are realistically worth
adding. The proto's `Message` has ~90 content fields; this is the map of which
ones we handle.

> Scope note: most unimplemented fields are WhatsApp Business / template UX that
> the server no longer lets a normal linked-device client **send** (sends are
> rejected). Those are only worth handling on **receive**. The tiers below
> reflect that.

## Currently implemented

**Send** — `Amarula.Protocol.Messages.MessageEncoder` + the `Amarula` facade:

- `conversation` (text)
- `contactMessage` / `contactsArrayMessage`
- `pollCreationMessage` v1 / v2 / v3
- `locationMessage` (incl. the `isLive` flag on a static location)
- `reactionMessage`
- media: `imageMessage` / `videoMessage` / `audioMessage` / `documentMessage` /
  `stickerMessage`
- `protocolMessage`: edit (`MESSAGE_EDIT`), revoke (`REVOKE`),
  `PEER_DATA_OPERATION` (placeholder resend, on-demand history)

Plus non-`Message` surfaces: presence, chat state, read receipts, groups
(`Amarula.Group`), profile (`Amarula.Profile`), contacts / USync
(`Amarula.Contacts`).

**Receive** — `Amarula.Protocol.Messages.MessageContent.classify/1`:

- text, reaction, edit, revoke, media (5 kinds), protocol, sender_key, contact,
  contacts, location, poll, poll_vote

Everything else falls through to `{:other, message}`. Inbound `contextInfo`
(quoted reply + mentions) is already decoded in `Amarula.Msg`.

## Gaps worth implementing

### Tier 1 — high value, normal-user features, low effort

| Feature | Proto field | Notes |
|---|---|---|
| **Reply / quoted send** | `contextInfo` on any sub-message | Biggest gap. We *decode* quotes on receive but there's **no way to send one** — `send_text`/`send_media` take no `quoted:` opt and the encoder never sets `contextInfo`. Needs a `stanzaId`/`participant`/`quotedMessage` builder + threading an opt through `send_*`. |
| **Mentions** | `contextInfo.mentionedJid` (with `extendedTextMessage`) | Same plumbing as replies; requires switching text → `extendedTextMessage` when mentions are present. |
| **Cast a poll vote** | `pollUpdateMessage` (encrypted vote w/ poll secret) | We can *tally* incoming votes but can't *send* one. The crypto seam (`PollCrypto`) already exists for the receive side. |
| **Pin / unpin a message** | `pinInChatMessage` (`PIN_FOR_ALL` / `UNPIN_FOR_ALL` + key) | Trivial encoder, key-based like reaction. |
| **Keep in chat** | `keepInChatMessage` (key + `keepType`) | Trivial; for disappearing chats. |
| **View-once media** | `viewOnce` bool on image/audio + `viewOnceMessageV2` wrapper | Small addition to the media path (set the flag / wrap). |
| **PTV (video note)** | `ptvMessage` (field 66, reuses `VideoMessage`) | Round video notes; the media path already builds `VideoMessage`. |

### Tier 2 — useful, moderate effort

| Feature | Proto field | Notes |
|---|---|---|
| **Group invite as a message** | `groupInviteMessage` | `Amarula.Group.invite_code/2` already fetches the code — this wraps it into a sendable chat message (`groupJid` / `inviteCode` / `groupName` / `caption`). |
| **Live location** | `liveLocationMessage` | Distinct from the `isLive` flag we set on a static `locationMessage`; supports streaming updates (`sequenceNumber`, speed/heading). |
| **Album** | `albumMessage` + child media | Grouped media; needs the child-association plumbing. |
| **Event** | `eventMessage` (+ `encEventResponseMessage`) | Create / respond to events (name, description, location, start/end). |
| **Receive-side classification** | buttons/list/template *responses*, `productMessage`, `orderMessage`, `groupInviteMessage`, `pinInChatMessage`, `keepInChatMessage`, `eventMessage` | Today these all collapse to `{:other, message}`. Adding `classify/1` clauses (pure decode, no protocol risk) lets consumers react to them. |

### Tier 3 — low priority / likely server-rejected on send

`templateMessage`, `buttonsMessage`, `listMessage`, `interactiveMessage`,
`productMessage`, `orderMessage`, `invoiceMessage`, the payment family
(`sendPaymentMessage` / `requestPaymentMessage` / …),
`newsletterAdminInviteMessage`, scheduled calls
(`scheduledCallCreationMessage` / `scheduledCallEditMessage`).

These are WhatsApp Business / deprecated paths — worth **receive**
classification only; sending them from a linked-device client generally fails.

## Recommended order

Start with **Tier 1**, and within it the **reply + mentions `contextInfo`
plumbing first**: it's the most-requested capability, unblocks proper threaded
bots, and the receive-side structs already exist to mirror. The encoder changes
are small; the real work is threading a `quoted:` / `mentions:` option from
`send_text` / `send_media` through `Connection` → `ConversationSender` — which
at `conversation_sender.ex:651` already forwards `messageContextInfo`, so the
send pipe is close.
