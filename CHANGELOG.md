# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`%Amarula.Msg{}.forwarded`** — a boolean, `true` when the message was forwarded
  from another chat (decoded from `ContextInfo.isForwarded`). Defaults to `false`;
  inlined quoted messages carry their own flag. The forward *score*
  (`forwardingScore`, the "forwarded many times" signal) stays on `msg.raw`.
- **Incoming calls surfaced as `:call_update`.** A `<call>` stanza was previously
  acked and dropped; it now also emits a `:call_update` consumer event carrying
  `%{chat, from, id, status, timestamp, offline, video?, group?, group_jid}`.
  `status` is `:offer` (ringing), `:terminate`, `:timeout` (unanswered), `:reject`,
  `:accept`, or `:ringing`; correlate an `:offer` with its later `:terminate` via
  `id`. Parsing lives in the new pure `Amarula.Protocol.Call`.
- **Interactive "pick one" messages classified.** `listMessage`, `buttonsMessage`,
  `templateMessage`, and `interactiveMessage` (native-flow) — the prompts business
  / call-center / automated flows send to present a set of choices — used to fall
  through to `{:other}`. They now classify to `msg.type` `:list` / `:buttons` /
  `:template` / `:interactive` with content as the new `Amarula.Content.Options`
  struct (`title`, `body`, `footer`, `button_text`, and `options: [%{id, text,
  description}]`). The option `id` matches the `id` on the user's later
  `%Amarula.Content.Response{}`.
- **Link previews surfaced on received messages.** A text message carrying a URL
  preview now exposes it on the new `%Amarula.Msg{}.preview` field — an
  `%Amarula.Content.LinkPreview{}` with `url`/`title`/`description`/`thumbnail`
  (raw JPEG bytes)/`type`, or `nil` when there's no preview. The message `type`
  stays `:text` and `content` stays the body string, so it's non-breaking.
  Receiving only — sending previews isn't supported yet.

### Fixed

- **`:pairing_failure` added to the `t:event/0` typespec.** The event was already
  emitted on a failed pair-success but was missing from the documented event list.

## [0.3.1] - 2026-06-26

A small follow-up to 0.3.0 — connection robustness fixes plus post-release review
catches. No breaking changes; purely additive/fixes.

### Fixed

- **Auto-reconnect when the websocket dies.** `WebSocketClient` was linked to
  `Connection` (which doesn't trap exits), so a server close signal-killed
  `Connection` before it could drive the reconnect, leaving the account stuck
  `:disconnected`. The link is now a monitor, so the client's death arrives as a
  `{:DOWN}` that triggers a reconnect.
- **Never crash on a send while disconnected.** A send before the handshake
  completed (nil `noise_state`) or after the socket dropped (nil
  `websocket_client`) crashed the whole `Connection` instead of returning to the
  caller. A backstop in `send_binary_node/2` drops the frame and a
  `ready_to_send?/1` guard on the consumer sends replies `{:error, :not_connected}`.
- **Emit a `:connection_update` down-transition on error paths.** Errors (ws
  errors, timeouts, non-515 stream errors, server close) previously emitted only
  an `:error` event, so a consumer tracking connection state never saw the drop.
- **Treat "Invalid PreKey ID" on a pkmsg as a duplicate (ack 487).** A redelivered
  pkmsg whose one-time prekey was consumed on first decrypt raised this error and
  fell through to retry+nack-500, making the server re-fan the stanza forever. It
  is now recognised as a duplicate and acked, terminating the redelivery loop.

### Changed

- `Content.Poll.options` drops malformed entries instead of emitting `nil`, so it
  always matches its `[String.t()]` type.
- Removed the unused `Connection.cache_sent_message/4` (superseded by the
  `RetryCache.Step` send-pipe step) and corrected the `Media.download/2` doc to
  the snake_case-only descriptor shape.

## [0.3.0] - 2026-06-22

The headline is the **receive side**: a `%Amarula.Msg{}`'s `content` is now always a
clean, proto-free `Amarula.Content.*` struct — you never pattern-match a raw
protobuf again. Plus validated `send_*` options, a normalized media struct (with
mimetype), retry-cache flexibility, and an explicit crypto boundary. This is a
breaking release; the migration is mechanical (struct fields instead of maps/protos).

### Breaking

- **`%Amarula.Msg{}.content` is now an `Amarula.Content.*` struct for every type**
  (except `:text` → `String.t()` and `:other` → `nil`). Previously `content` handed
  back raw protobufs and bare maps. Now: `:reaction` → `%Content.Reaction{}`,
  `:location` → `%Content.Location{}`, `:poll` → `%Content.Poll{}`, etc. — see the
  table in `Amarula.Msg`. Any `key`/`poll_key` is a `{jid, msg_id}` ref (the form the
  send API takes, so a received reaction feeds straight back into `send_reaction/3`).
  The full proto is still on `msg.raw`. **Migration:** replace map/proto field access
  on `content` with the documented struct fields.
- **Media is `%Amarula.Content.Media{}`** (moved from `Amarula.Media`), and `:media`
  content **is that struct directly** — no more `%{kind:, media:}` wrapper. It
  surfaces `:mimetype` (use it for the file extension, not `:kind`). Inbound jids on
  the new structs (`GroupInvite.group`, `Product.business_owner`, `Order.seller`) are
  `%Amarula.Address{}`, not strings.
- **Control frames moved off `:messages_upsert` to a new `:protocol_update` event.**
  Bare `protocolMessage`s (ephemeral/setting changes and other unhandled types) no
  longer arrive as junk messages; subscribe to `:protocol_update` if you want them.
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

- **Re-attachable consumer event sink — `Amarula.set_parent/2`.** The event sink
  (where `{:amarula, …}` events go) is no longer frozen at `connect/2`. If the
  process that called `connect/2` restarts while the connection survives in the
  registry, re-point the sink on the live connection instead of forcing a
  stop+reconnect: `Amarula.set_parent(Amarula.via(:primary), self())`. There is
  still exactly one sink — no subscriber registry, no relay hop.
- **The sink may be a name, not just a pid** (`connect(:parent)` /
  `set_parent/2` accept a `t:Amarula.Connection.sink/0`: pid, registered name,
  `{:via, …}`, or `{name, node}`). A **name re-resolves per event**, so it
  re-attaches to the consumer's current pid automatically — surviving both the
  consumer's restart *and* the connection's own restart, the same way a `:profile`
  handle survives where a raw pid goes stale. A raw pid is not restart-safe; recover
  it with `set_parent/2`. `:parent` is the preferred connect option; `:parent_pid`
  remains a legacy alias.
- **`[:amarula, :sink, :down]` telemetry.** The connection monitors its sink, so a
  dead consumer is observable instead of events vanishing silently. A name sink's
  monitor self-heals off the keep-alive once a holder reappears.
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
- **`download_media/1` honours its `{:ok | :error}` contract.** A malformed/empty
  media descriptor now returns `{:error, :invalid_media}` instead of letting the
  HTTP layer raise (which forced consumers to wrap the call in rescue). It also
  works with no live connection — documented now — so you can download from a `Task`.

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
