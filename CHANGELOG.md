# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.5] - 2026-06-22

Documentation, validation, and retry-cache flexibility, a couple of process-level
performance fixes, and an explicit boundary around the crypto layer. Two things to
note when upgrading: option keys are now validated (unknown ones raise), and
`fetch_history/4` no longer accepts a raw protobuf key.

### Breaking

- **`fetch_history/4` takes a `message_ref`, not a raw `%Proto.MessageKey{}`.**
  Front-facing functions should never make you construct an internal protobuf. It
  now takes the `%Amarula.Msg{}` you received or a `{jid, msg_id}` tuple (consistent
  with `send_reaction`/`send_edit`/`pin_message`/…). If you were passing a
  `%Proto.MessageKey{}`, switch to `{jid, msg_id}` or the received `%Amarula.Msg{}`.
  (The public `message_key` type, which aliased `Proto.MessageKey`, is removed — no
  protobuf type remains in any public spec.)

### Changed

- **`send_*` options are now validated** (`NimbleOptions`). The option keywords on
  the facade send functions (`send_text`, `send_media`, `send_location`,
  `send_poll`, `send_poll_vote`, `send_event`, `send_group_invite`,
  `request_pairing_code`) are now validated against a schema, and each function's
  `## Options` docs are generated from that same schema (so they can't drift).
  **Behaviour change:** an unknown or mistyped option key now raises
  `NimbleOptions.ValidationError` instead of being silently ignored. This catches
  typos at the call site; if you were passing an undocumented key that happened to
  be tolerated, remove it. (`nimble_options` is a new direct dependency, but it was
  already in the tree via `Req`, so it adds no weight.)
- **Retry-cache built-ins are bounded the way the protocol is.** The ETS and DETS
  adapters now evict on a **5-minute TTL** (a retry receipt that hasn't arrived by
  then won't) in addition to a hard `:max_entries` cap, and that cap's default is
  raised **200 → 512** (matching the Baileys reference). Size `:max_entries` to your
  peak sends-per-5-minutes.

### Added

- **`Amarula.RetryCache.ReadOnly`** — back the retry cache with **your own message
  store** instead of a second copy. If your app already persists sent messages,
  supply `retry_cache: {Amarula.RetryCache.ReadOnly, get: fn profile, msg_id -> …}`;
  Amarula then only **reads** on a retry and never writes, evicts, or deletes
  anything in your store (the `put` callback is optional and this adapter doesn't
  implement it — there is no write path). Removes the `:max_entries`/TTL sizing
  question entirely.
- **`:max_entries` is documented** in the `Amarula.Config` option table and the
  `Amarula.RetryCache` docs (it already existed; it was just undiscoverable).
- **`:quoted` accepts a `{msg_id, participant}` tuple** (in addition to an
  `%Amarula.Msg{}`) — a lightweight quote that threads by id when you have the id
  but not the original message. It renders when the recipient still has the quoted
  message; otherwise the reply may show without a quote preview.

### Fixed

- **`Amarula.Connection.start_link/2` and `child_spec/1` are marked internal.** They
  start only the bare Connection process, not its supervision tree, so a consumer
  who put `{Amarula.Connection, …}` under their own supervisor got a non-functional
  connection. The supported entry point is `Amarula.connect/2`. (The connection is a
  protocol state machine — it self-restarts for the post-pairing 515 handshake — so
  the library owns its lifecycle; consumers control naming/distribution via the
  `:registry` config.)
- **Replies no longer grow with the quote chain.** A reply inlined the full quoted
  message verbatim, including *its* nested `contextInfo` — so quoting a reply
  re-embedded the whole quote ancestry each hop (the proto grew quadratically in
  chain depth). The quoted message is now stripped of its nested `contextInfo`
  before inlining, keeping a quote to one level (matching the Baileys reference).
- **Stopped copying the one-time-prekey map into every send.** The credentials
  handed to each per-recipient sender carried `:pre_keys` (up to ~812 entries,
  ~100 KB+ on a fresh account) — which the send/encrypt path never reads (it's only
  used on the receive/decrypt path, in `Connection`). It was being deep-copied into
  every sender, multiplied per recipient in a group fan-out. It's now dropped before
  the copy.

### Documentation

- **`docs/CRYPTO_BOUNDARY.md`** — the Noise/Signal crypto is a pure,
  self-contained layer; this draws the explicit line between the Core (no
  app/storage/WhatsApp coupling) and the thin Glue that bridges it to
  `Amarula.Storage`. Verified: no Core module depends on the app. The Core is
  extraction-ready in principle (a standalone Signal/Noise library), though
  extraction is not planned.
- Corrected the `ConversationSender` rationale across the docs: it is a per-recipient
  **serialization point**, not a holder of crypto state — the Signal session lives in
  Storage. (A test, `session_race_test`, documents a known concurrency gap between the
  send and inline-decrypt paths on that shared session; a fix is planned —
  `docs/plans/SESSION_WORKER.plan.md`.)
- README: fixed a stale module reference and the QR-render example (now `qr_code`,
  the actual dependency).

## [0.2.4] - 2026-06-21

An internals and robustness pass over the per-connection process tree, prompted
by an external review. No public API or behaviour changes — the `Amarula` facade
is untouched; everything here is below it. A new optional `:sender_idle_ms` knob
is the only consumer-visible addition.

### Changed

- **Per-connection process naming moved to an app-level `Amarula.InstanceRegistry`.**
  The connection tree no longer owns a per-instance `Registry`, and the tree
  supervisor, sibling roles, and each `ConversationSender` are now named by the
  connection's `instance_id` ref in one shared registry. Previously these were
  named by atoms derived from `:erlang.phash2(ref)` — which both leaked an atom
  per connection and could collide (two connections hashing to the same atom
  would fail to start). No atom is minted per connection now, and collisions are
  impossible.
- **Per-connection supervisor strategy is now `:rest_for_one` (was `:one_for_one`).**
  The children share fate — senders block on Connection's replies — so a
  Connection restart now restarts the senders waiting on it instead of leaving a
  half-dead tree.
- **The retry cache's ETS table is owned by the `Connection` process directly.**
  The dedicated `TableOwner` process is gone; `Connection` creates the table in
  `init` via the new `RetryCache.ensure_local/2` (adapter-aware — a no-op for
  non-ETS adapters). Because the table now dies with Connection, a crash/restart
  recreates it empty, so a poisoned cached entry can no longer outlive — and loop
  — the restart it triggers.
- **`ConversationSender` idle linger is now 1s and configurable** via
  `config[:sender_idle_ms]` (was a hardcoded 5 minutes). A fan-out to many
  one-shot recipients no longer leaves a long-lived process tail; a disk-backed
  session store can raise it to keep senders warm under bursty traffic.

### Fixed

- **Removed the dead `\\ __MODULE__` default argument** from `Connection.start_link/2`
  and ~28 `Connection` client functions. These delegate to a process started under
  the registry (never under the module name), so the default was never reachable
  and would have errored if hit. The public `Amarula` facade always passes the pid,
  so consumers are unaffected.
- **Dropped the inert `{:send_relayed, …}` message.** On a successful relay the
  sender now reports nothing back to `Connection`: the consumer's reply is already
  driven by the server `<ack>` armed at dispatch, so the message was a signal
  `Connection` only ever ignored. Failures still report `{:send_failed, …}`.

## [0.2.3] - 2026-06-20

A big batch of new message and group capabilities — replies, mentions, poll
votes, pins, view-once, albums, events, group invites, member tags, and LID↔PN
resolution — plus an optional Android client mode and three protocol fixes. No
breaking changes.

### Fixed

- **Audio: thread `:waveform` and warn when `:seconds` is missing** (Baileys
  #2646). `send_media(:audio, …)` now passes a `:waveform` opt through to the
  proto, and logs a warning when `:seconds` is absent — without a duration, clips
  longer than ~10s may fail to play on iPhone recipients. Amarula does no media
  processing, so the caller must supply `:seconds`; this is now documented on
  `send_media/5` and surfaced at send time.
- **Pinned chat state is always a definite boolean** (Baileys #2328). A pin
  app-state action whose `pinned` flag the server omits (proto3-optional) left
  `%Amarula.Chat{}.pinned` as `nil` ("undefined for some conversations"). It now
  coerces to `false` — only an explicit `pinned: true` is pinned — so consumers
  never see an ambiguous nil from a pin action.
- **`mark_online_on_connect: false` is now honored** (Baileys #2553). The
  per-connection setting was defined and documented but never read — the login
  path always sent presence-available, so the account appeared online and the
  primary phone stopped getting push notifications regardless of the flag. Connect
  (and the post-pairing push-name refresh) now gate presence-available on it.

### Added

- **LID↔PN mapping lookups + a `:lid_mapping_update` event** (Baileys #2263).
  `Amarula.Contacts.pn_for_lid/2` and `lid_for_pn/2` read the local mapping store
  (no server query) — resolve a group member's LID to a PN after a
  `:messages_upsert`. And a new `:lid_mapping_update` consumer event fires with
  `[%{lid: Address, pn: Address}]` whenever the send pipeline learns new mappings,
  so consumers can persist them as they arrive instead of polling.
- **Group member tags** (Baileys #2502). `Amarula.update_member_tag/3` sets (or
  clears, with `""`) your per-group self-label — capped at 30 chars, rejected with
  `{:error, :member_tag_too_long}` rather than silently truncated. Incoming tag
  changes classify as `{:member_tag, %{label, timestamp}}` on `%Amarula.Msg{}`,
  **including removals** (empty label) — the case Baileys #2502 dropped.
- **Android browser mode** (Baileys #2201). Setting a `:browser` whose client
  element contains `"Android"` (e.g. `["MyApp", "Android", ""]`) registers as an
  Android client instead of WhatsApp Web: `userAgent.platform = :ANDROID`, no
  `webInfo`, `DeviceProps.platformType = :ANDROID_PHONE`. Lets a session receive
  view-once media. Experimental, and shows as a phone in Linked Devices — see the
  impact note in `Amarula.Config`. Non-Android browsers are unaffected.

## [0.2.2] - 2026-06-20

A bug-fix plus new outgoing/incoming message types. One small breaking change to
how you reference an existing message (see **Changed (breaking)**).

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
