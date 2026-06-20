# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **`mark_online_on_connect: false` is now honored** (Baileys #2553). The
  per-connection setting was defined and documented but never read — the login
  path always sent presence-available, so the account appeared online and the
  primary phone stopped getting push notifications regardless of the flag. Connect
  (and the post-pairing push-name refresh) now gate presence-available on it.

### Added

- **Android browser mode** (Baileys #2201). Setting a `:browser` whose client
  element contains `"Android"` (e.g. `["MyApp", "Android", ""]`) registers as an
  Android client instead of WhatsApp Web: `userAgent.platform = :ANDROID`, no
  `webInfo`, `DeviceProps.platformType = :ANDROID_PHONE`. Lets a session receive
  view-once media. Experimental, and shows as a phone in Linked Devices — see the
  impact note in `Amarula.Config`. Non-Android browsers are unaffected.

## [0.2.2] - 2026-06-20

A bug-fix plus new outgoing/incoming message types (Tier 1 + Tier 2 of the proto
coverage review). One small breaking change to how you reference an existing
message (see **Changed (breaking)**).

### Fixed

- **`Storage.File` no longer discards a valid `creds.term` as "corrupt" on a cold
  start** (#1). Decoding used `:erlang.binary_to_term/2` with `[:safe]`, which
  refuses to mint atoms that aren't loaded yet. A persisted creds term legitimately
  carries generated proto-struct atoms (e.g.
  `Amarula.Protocol.Proto.ADVSignedDeviceIdentity`); if creds were read before that
  module loaded, `[:safe]` raised and the entry was swallowed as a miss — silently
  logging the session out and forcing a re-pair, intermittently and load-order
  dependent. Decode now falls back to an unsafe `binary_to_term/1` on the
  `[:safe]`-specific rejection (these files are self-written and trusted), so a valid
  creds file is always recovered; only a genuinely undecodable file is treated as a
  miss.

### Added

- **More inbound message types are now classified** instead of collapsing to
  `{:other}`: view-once media (unwrapped to its inner media), PTV round notes
  (as media `:video`), pin/keep updates, group invites, events, and the
  receive-only WhatsApp Business / interactive types (product, order, button /
  list / template / interactive responses). Surfaced on `%Amarula.Msg{}` via its
  `type` + `content`.
- **Send albums (grouped media).** `Amarula.send_album/3` takes a list of
  `{type, data, opts}` image/video items; it sends the album parent, then each
  item referencing it (via `messageContextInfo.messageAssociation`, MEDIA_ALBUM).
- **Create events.** `Amarula.send_event/4` sends an event (name + optional
  description, location, join link, start/end time, extra-guests flag).
  Responding (RSVP) is not yet supported — it's an encrypted response, a separate
  seam like poll votes.
- **Send a group invite as a chat message.** `Amarula.send_group_invite/5` wraps
  a group's invite `code` (from `Amarula.Group.invite_code/2`) into a tap-to-join
  card sent to a chat. `opts`: `:group_name`, `:caption`, `:expiration`.
- **Cast a poll vote.** `Amarula.send_poll_vote/5` encrypts and sends a vote on an
  existing poll (the inverse of the tally/decrypt path). Pass the poll's
  `message_ref`, its `message_secret`, and the chosen option names.
- **Pin / unpin and keep / unkeep messages.** `Amarula.pin_message/2`,
  `unpin_message/2` (pin for everyone), `keep_message/2`, `unkeep_message/2`
  (exempt a message from a disappearing chat). Each takes a `message_ref`.
- **View-once media and PTV (round video notes).** `send_media/5` gains
  `:view_once` (wrap as view-once) and `:ptv` (for `:video`, send as a round
  video note).

### Changed (breaking)

- **Unified how you reference an existing message.** `send_reaction/3`,
  `send_edit/3`, `send_revoke/2` (and the new `send_poll_vote`) now take a
  `message_ref` — a `%Amarula.Msg{}` (the message you received) **or** a
  `{jid, msg_id}` tuple — instead of a raw `%Proto.MessageKey{}`. This removes the
  last proto type from the public API and gives one consistent currency: pass back
  the struct you got, or the chat jid + id. Migration: replace
  `%Proto.MessageKey{remoteJid: jid, id: id}` with `{jid, id}`, or pass the
  `%Amarula.Msg{}` directly.

### Added

- **Reply (quoted) and mentions on outgoing messages.** `Amarula.send_text/4`
  and `Amarula.send_media/5` now take `:quoted` (an `%Amarula.Msg{}` to reply to)
  and `:mentions` (a list of jids/`%Amarula.Address{}`) opts. A text with either
  is sent as an `extendedTextMessage` carrying the `contextInfo`; media attaches
  the `contextInfo` to the media submessage. Backward compatible — existing
  3-arg `send_text` calls are unchanged.

## [0.2.1] - 2026-06-20

Internal refactor only — **no API changes.** Every public `Amarula` function
keeps its exact signature, arity, defaults, and return shape (verified by diff);
consumer event shapes are unchanged. No action needed to upgrade.

### Changed (internal)

- Decomposed the ~3.9k-line `Amarula.Connection` god-module: the pure bodies of
  its callbacks moved into eight focused submodules under
  `Amarula.Connection.*` — `SendOps`, `GroupOps`, `PreKeyOps`, `Pairing`,
  `Notifications`, `Receive`, `AppStateOps`, and the shared `AckLifecycle` seam.
  `Connection` remains the single per-connection process and dispatcher; anything
  bound to the live socket, cipher, IQ correlation, or Storage stayed put. Each
  new module has direct unit tests (100% line coverage).
- The `Amarula` facade now calls the connection process directly
  (`GenServer.call`) instead of `defdelegate`-ing through `Connection`'s client
  wrappers, removing one indirection hop. Public signatures are untouched.

## [0.2.0] - 2026-06-19

A consumer-API cleanup pass: leaner, more consistent `Amarula` facade with no
protocol types leaked. **All breaking changes are mechanical** — rename the call
or swap two arguments; behaviour is unchanged.

### Changed (breaking)

**Namespaced the group / profile / contact families** — these moved off the flat
`Amarula` facade onto dedicated modules, shrinking the top-level surface and
dropping the prefix-stutter. Every operation is unchanged; only the module differs:

| Before | After |
|--------|-------|
| `Amarula.group_create/3`, `group_leave/2`, … (all `group_*`) | `Amarula.Group.create/3`, `Amarula.Group.leave/2`, … (drop the `group_` prefix) |
| `Amarula.group_metadata/2`, `Amarula.list_groups/1` | `Amarula.Group.metadata/2`, `Amarula.Group.list/1` |
| `Amarula.on_whatsapp/2`, `fetch_profile_status/2` | `Amarula.Contacts.on_whatsapp/2`, `Amarula.Contacts.fetch_status/2` |
| `Amarula.profile_picture_url/3`, `update_profile_*`, `remove_profile_picture/2` | `Amarula.Profile.picture_url/3`, `update_picture/3`, `update_status/2`, `remove_picture/2` |

**Event tag** — consumer events are now tagged `:amarula`, not `:whatsapp`, so the
origin is clear and the tag won't collide with other libraries:

```elixir
# before
{:whatsapp, :messages_upsert, data}
# after
{:amarula, :messages_upsert, data}
```

Update every `receive`/`handle_info` clause that matches the event tuple.

**Renamed functions** (same behaviour, clearer name):

| Before | After |
|--------|-------|
| `Amarula.Address.to_wire/1`, `to_wire!/1` | `Amarula.Address.to_jid/1`, `to_jid!/1` (now accept a string *or* an `Address`) |
| `Amarula.fetch_status/2` | `Amarula.fetch_profile_status/2` |
| `Amarula.presence_subscribe/2` | `Amarula.subscribe_presence/2` |
| `Amarula.group_setting/3` | `Amarula.group_update_setting/3` |
| `Amarula.group_ephemeral/3` | `Amarula.group_toggle_ephemeral/3` |

**Argument order** — `jid` now always comes right after `conn`, matching every
other send:

- `Amarula.mark_read(conn, message_ids, jid, participant)` →
  `Amarula.mark_read(conn, jid, message_ids, participant)`
- `Amarula.send_media(conn, type, jid, data, opts)` →
  `Amarula.send_media(conn, jid, type, data, opts)`

**Return shape** — `Amarula.group_requests/2` now returns clean
`[%{jid: Amarula.Address.t(), requested_at: integer | nil}]` instead of raw
string-keyed wire attributes.

### Removed (breaking)

Removed from the `Amarula` facade. These were either a protocol leak or internal
plumbing the library handles for you; the underlying function still exists for
power users:

| Removed | Use instead |
|---------|-------------|
| `Amarula.send_message/3` (took a raw `%Proto.Message{}`) | `Amarula.send_text/3` & friends, or `Amarula.Connection.send_message/3` |
| `Amarula.request_resend/2` | `Amarula.Connection.request_resend/2` |
| `Amarula.resolve_lid/2` | `Amarula.Contacts.resolve_lid/2` (addressing resolves automatically on send) |
| `Amarula.normalize_jid/2` (was `canonical_jid`) | `Amarula.Connection.canonical_jid/2` |

### Documentation

- Dropped internal jargon ("wire jid", "boundary", "total function", "canonical")
  from the consumer-facing docs in favour of plain language.

## [0.1.0] - 2026-06-19

First public release.

### Added

- **Offline sandbox + `Amarula.Testing`** — test your bot's receive→reply logic
  with no WhatsApp connection. `Amarula.new(%{profile: x, offline: true})` runs a
  connection with no socket whose `send_*` calls short-circuit to `{:ok, msg_id}`
  (no encrypt, no frame, no real-world effect). `Amarula.Testing.start_offline/1`
  starts one; `deliver_text/2` and `deliver/2` feed synthetic inbound messages
  through the real decode/classify pipeline, so your bot receives a true
  `%Amarula.Msg{}`. `send_media/5` is unsupported offline (needs a live socket).
- `Amarula.list_profiles/1` — list the profiles that have stored credentials in a
  given storage source (a `Conn`, a `Storage.Scope`, or a `{adapter, opts}` /
  bare-opts storage spec). Returns the names you'd pass as `:profile` to reconnect.
- `Amarula.list_profiles_with_metadata/1` — like `list_profiles/1`, but each entry
  carries the logged-in identity read from that profile's creds
  (`%{profile, jid, lid, name}`), for building account pickers.
- `Amarula.Storage` gains an optional `list_profiles/1` behaviour callback,
  implemented by the `File` and `DETS` adapters. Adapters that don't implement it
  report `{:error, :not_supported}`.

### Changed

- **Teardown API reworked.** `wipe_credentials/1` is now the single destructive
  path: it unlinks the companion server-side (`remove-companion-device`, the phone
  drops the device), wipes **all** local storage for the profile, then disconnects.
  After it, the profile must be re-paired.

### Removed

- **`Amarula.logout/1`** (removed). For a non-destructive teardown that keeps
  credentials, use `disconnect/1` (closes the websocket only) or `stop/1` (takes
  the supervision tree down and frees the profile slot). The server-side
  device-unlink now lives only in `wipe_credentials/1`.

[Unreleased]: https://github.com/tubedude/amarula/compare/v0.1.1...HEAD
