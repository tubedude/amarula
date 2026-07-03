> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Plan: proto-free `%Amarula.Msg{}.content`

Status: PROPOSED. Goal: **no `%Proto.*{}` value ever appears in a `%Amarula.Msg{}`'s
`content`.** Consumers get clean, snake_case Elixir structs/values; the raw proto
stays available only via the deliberate `msg.raw` escape hatch.

## Why

`Msg.classify/1` currently puts raw protobuf structs into `content` for most
message types — `%Proto.MessageKey{}` (reaction/edit/revoke/pin/keep),
`%Proto.Message.*Message{}` (poll/event/location/contact/group_invite, the Business
types), and the whole `%Proto.Message{}` for `:other`. That leaks an internal type
into the most-used part of the public API and forces consumers to learn camelCase
proto shapes. Media is already fixed (`Amarula.Media`); this does the rest.

## Principles

1. **One canonical, snake_case shape per content type.** No camelCase, no proto.
2. **Structs for the rich, well-understood types**; small maps only where a struct
   is overkill.
3. **`MessageKey` → `{jid, msg_id}`** (a `message_ref` tuple) everywhere it appears
   in content. This is the same form `send_reaction`/`send_edit`/… already accept,
   so a consumer can round-trip a received reaction straight back into an action.
4. **Business/interactive types get a *minimal* normalized struct**, surfacing only
   the few fields a linked-device consumer realistically uses; the full detail stays
   in `msg.raw`. We do NOT deep-model WhatsApp Business catalogs.
5. **`:other`** carries **no proto** — just a tag; the consumer reads `msg.raw` if
   they must. (We never hand back `%Proto.Message{}` as content.)

## Module layout

New consumer structs under `Amarula.Content.*` (keeps the `Amarula.*` namespace
clean; `Amarula.Media` already exists at the top level — leave it, it predates this
and is the most-used):

```
Amarula.Media                      (exists)          :media
Amarula.Content.Contact            displayName,vcard :contact / :contacts
Amarula.Content.Location           lat,lng,name,...  :location
Amarula.Content.Poll               name,options,...  :poll
Amarula.Content.Event              name,times,...     :event
Amarula.Content.GroupInvite        code,group,...     :group_invite
Amarula.Content.Product            (minimal)          :product
Amarula.Content.Order              (minimal)          :order
Amarula.Content.Response           (unifies button/list/template/interactive)
```

Reaction/edit/revoke/pin/keep/member_tag/poll_vote stay **plain maps** (they're
small; a struct adds no value) — but with `key` as `{jid, msg_id}`, not a proto.

## Per-type target shape

| `type` | new `content` (all proto-free) |
|--------|--------------------------------|
| `:text` | `body` (string) — already clean |
| `:media` | `%{kind, media: %Amarula.Media{}}` — already done |
| `:reaction` | `%{key: {jid, msg_id}, emoji}` |
| `:edit` | `%{key: {jid, msg_id}, text}` |
| `:revoke` | `%{key: {jid, msg_id}}` |
| `:pin` | `%{key: {jid, msg_id}, pinned?: bool}` |
| `:keep` | `%{key: {jid, msg_id}, kept?: bool}` |
| `:member_tag` | `%{label, timestamp}` — already clean |
| `:contact` | `%Amarula.Content.Contact{display_name, vcard}` |
| `:contacts` | `%{display_name, contacts: [%Content.Contact{}]}` |
| `:location` | `%Amarula.Content.Location{latitude, longitude, name, address, url, live?, ...}` |
| `:poll` | `%Amarula.Content.Poll{name, options: [String], selectable_count, enc_key}` |
| `:poll_vote` | `%{enc_payload: bytes, ...}` (the encrypted vote — keep it a small map; decrypt is a separate step) |
| `:event` | `%Amarula.Content.Event{name, description, location: %Content.Location{}|nil, join_link, start_time, end_time, ...}` |
| `:group_invite` | `%Amarula.Content.GroupInvite{group_jid, code, group_name, caption, expiration}` |
| `:product` | `%Amarula.Content.Product{title, body, business_owner_jid}` (minimal) |
| `:order` | `%Amarula.Content.Order{order_id, title, item_count, status, seller_jid}` (minimal) |
| `:button_response`/`:list_response`/`:template_reply`/`:interactive_response` | `%Amarula.Content.Response{kind: :button|:list|:template|:interactive, id, text}` (unified, minimal) |
| `:sender_key` | dropped from delivery (not consumer-visible) — no content concern |
| `:protocol` | `%{type, message: ???}` — **the `message` is a `%Proto.Message.ProtocolMessage{}` today; must change.** Emitted on `:protocol_update`. Carry `%{type: atom}` only (the type tag); the consumer reads `msg.raw` for detail. No proto in content. |
| `:other` | `%{}` or `:unsupported` tag — **no proto**; `msg.raw` is the escape hatch |

## Key conversion helper

`MessageKey → {jid, msg_id}`: `{remoteJid, id}`. (We drop `fromMe`/`participant`
from the surfaced form; a consumer rarely needs them, and the tuple is the
`message_ref` shape the send API takes. If a use case needs participant, it's in
`msg.raw`.)

## Open questions — RESOLVED

1. **`:poll_vote`** — `PollUpdateMessage` carries `pollCreationMessageKey` (→
   `{jid, msg_id}`), `vote` (an encrypted `PollEncValue` proto), `senderTimestampMs`.
   Target: `%{poll_key: {jid, msg_id}, enc_vote: %{payload: bytes, iv: bytes}, timestamp}`
   — surface the `PollEncValue`'s raw bytes, never the proto. Decrypt stays a
   separate step (`PollCrypto`).
2. **`:protocol` content** — today `%{type, message: %Proto.*ProtocolMessage{}}`.
   No internal/consumer code reads `message` as a proto (verified). New shape:
   `%{type: atom}` only; detail via `msg.raw`. (Emitted on `:protocol_update`.)
3. **`:contacts`** nested list — reuse `Content.Contact` per element. ✓
4. **`Amarula.Media` stays top-level** (not moved under `Content.*`) — most-used,
   already public; document the asymmetry. ✓
5. **`:other` is already `nil`** today (no proto) — keep it `nil`. ✓ Only the typed
   leaks need fixing.

## Verification

- A test per normalized type (right fields, right values).
- A **guard test**: build a `%Msg{}` for every classify branch and assert
  `content` (recursively) contains **no** `%Proto.*{}` struct. This is the
  enforceable "no leak" invariant.
- Update `Amarula.Msg` moduledoc's content table to the new shapes.
- Full suite + format + credo green.

## Breaking change note

This changes the **shape of `content`** for every non-text type — a breaking change
to the consumer API. It belongs in 0.2.5's Breaking section (alongside the
`fetch_history`/`message_ref` change). Worth it: the old shapes leaked protos and
camelCase; the new ones are the stable, documented contract.
