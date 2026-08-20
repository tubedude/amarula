# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Found by reviewing upstream Baileys for portable changes (see `docs/PARITY.md`).
Three of the four are bugs Amarula had independently; none needed a consumer-visible
API change.

### Added

- **`resolve_pn_to_lid` — opt-in PN→LID re-addressing for 1:1 sends**
  ([Baileys#2683]). WhatsApp appears to evaluate the trusted-contact gate against the
  **LID** identity, so a send addressed to a phone number can be accepted by the
  socket and then discarded with ack `463` for a contact you know is reachable —
  regardless of the token attached. With this on, a 1:1 send is re-addressed to the
  contact's LID when the mapping is already known.

  **Off by default**, and staying that way for now. The direction of travel is not in
  doubt: WhatsApp has begun omitting `*_pn` attributes altogether, so clients now
  reconstruct phone numbers locally. But upstream has attempted this exact change
  twice ([Baileys#2711], [Baileys#2748]) and merged neither, while two LID-migration
  bugs remain open there. Turning it on by default on that basis would be following a
  change its own authors can't land.

  Set `resolve_pn_to_lid: true` if you are seeing repeatable `463`s. One caveat:
  device resolution then queries USync by LID, and an empty result surfaces as
  `{:error, {:resolve_devices, :not_on_whatsapp}}` — accurate about the outcome,
  misleading about the cause. See `Amarula.Connection.resolve_pn_to_lid?/1`.

### Fixed

- **A message containing a Facebook-interop jid no longer vanishes.** The binary
  decoder had no clause for string tags `245` (INTEROP_JID) or `246` (FB_JID), so
  either raised; the frame decoder rescues a decode failure and treats the frame as a
  control frame, which **discarded the whole message**. One WA frame carries the
  entire `<message>` node, so a single such jid anywhere inside it — including a
  nested `<device>` — lost the message with no `:messages_upsert`, no receipt, and
  **no ack or nack**, so the server never retransmitted. The only trace was one log
  warning. Latent rather than reproducible: FB_JID is interop addressing WhatsApp
  enables progressively.

- **A trusted-contact token attached to an incoming message is no longer thrown
  away.** Token ingestion had three sources, all reactive (our own issuance result, a
  `privacy_token` notification, the history-sync blob). A contact could hand us their
  token in the very message we were about to reply to, and the reply still went out
  tokenless — accepted by the socket, dropped by the server with ack `463`. One
  wasted send plus an issuance round-trip per warm contact, for a token already
  present in the decoded node. Ported from [Baileys#2752].

  Note this does not on its own eliminate `463`s; upstream shipped it alongside the
  PN→LID change above, and their reports show LID-keyed tokens were not sufficient
  by themselves.

- **Editing your own message from your phone now surfaces as an edit.** A message you
  send is fanned out to your linked devices wrapped in `deviceSentMessage`, and the
  `messageContextInfo` — carrying the `messageSecret` — can sit on the **outer**
  wrapper. Unwrapping dropped it, so a later `secretEncryptedMessage` edit had no key
  and arrived as `{:other, _}` instead of `{:edit, key, text}`. Ported from
  [Baileys#2743]. Still narrower than upstream there: Amarula tries two JID-form
  combinations where upstream tries the full sender × editor product, so an edit whose
  original was stored under a PN while the editor is LID-addressed can still fail.

- **`Amarula.Content.Media.mimetype` no longer surfaces an explicit blank
  string.** WhatsApp sometimes sends `mimetype` explicitly set to `""` (or
  whitespace) rather than omitting the field, and `from_proto/2` passed that
  through verbatim. `nil` is now the sole "no mimetype" value, matching the
  moduledoc's contract. Found while reviewing a downstream consumer's own
  workaround for the same gap.

## [0.5.7] - 2026-08-05

### Changed

- **Pinned WhatsApp Web version bumped to `2.3000.1044539926`.** Routine drift
  check against the live revision (see `docs/PARITY.md`); the previous pin
  (`1044303277`, from 0.5.6) had fallen behind.

### Deprecated

- **The bare `{jid, msg_id}` message ref is now reported by Dialyzer** ([#46],
  [#47]). It has warned at runtime since 0.5.4, but `t:Amarula.message_ref/0`
  still listed it — so every public `@spec` declared it valid and a consumer got
  no build-time signal at all. The type now omits it, matching
  `t:Amarula.Msg.ref/0`, which never listed it.

  Nothing breaks: it still works at runtime with the same `IO.warn`. But the only
  previous signal was that warning, which fires solely on a path you execute and
  is easy to lose in a running app — while the failure it guards is silent, since
  a wrong `from_me` makes an edit or revoke match nothing and the payload is
  E2E-encrypted, so the server cannot reject it.

  **It is removed in 0.6.0.** Pass `{jid, msg_id, from_me}`, or the received
  `%Amarula.Msg{}` / `content.key`, which carry `from_me` for you. Also fixed a
  leftover in `usage-rules.md` still teaching the 2-tuple for `fetch_history/4`
  ([#81] cleaned up the others).

### Fixed

- **Windows desktop pairing advertised the retired `WIN32` web sub-platform;
  now advertises `WIN_HYBRID`.** Ported from upstream Baileys
  [#2741](https://github.com/WhiskeySockets/Baileys/pull/2741) (merged
  2026-08-04): as of ~2026-06-30 the WhatsApp server rejects the handshake
  with a 428 before any QR is emitted when `webInfo.webSubPlatform = WIN32`
  and `browser[0] = "Windows"` with `sync_full_history: true`. `WIN32` was the
  legacy Electron WhatsApp Desktop identity; the modern native Desktop
  advertises `WIN_HYBRID`, already present in the proto but never selected.
  `platform_to_web_sub_platform/1` in `auth_utils.ex` now matches.

- **A rejected phone-number pairing code is no longer silently treated as
  valid.** `request_pairing_code/3` fired the `companion_hello` IQ and
  returned/emitted the code without waiting on the server's reply, so a
  rejection (e.g. `400 bad-request`) still handed the caller a code that was
  never registered. The IQ is now tracked; a rejection surfaces as the
  existing `:pairing_failure` event. The code itself still returns/emits
  immediately on the (common) accepted path. Found while reviewing
  [Baileys#2737](https://github.com/WhiskeySockets/Baileys/issues/2737), which
  flagged the identical bug upstream — not yet fixed there either, so this is
  an Amarula-original fix, not a port.

- **Rapid first sends to the same contact no longer fire a duplicate
  `issuePrivacyTokens` for each one** ([#81]). The post-send issuance path was
  guarded only by `should_issue_new?/2`, which reads a `sender_timestamp` written
  *after* the IQ round-trips — so anything sent inside that window saw a stale
  "no token yet" and issued again. Issuance now goes through `Connection`, on the
  same in-flight plumbing as the 463 path. The two are keyed separately by source,
  matching Baileys: a 463 means the recipient rejected us and still warrants
  recovery even while a routine post-send issuance is in flight, so a single
  shared key would dedupe a 463 against the very send that caused it.

- **`usage-rules.md` no longer teaches the deprecated 2-tuple message ref**
  ([#81]). It still documented `{jid, msg_id}` instead of
  `{jid, msg_id, from_me}`. That file ships inside the hex package as agent
  guidance, so consumers syncing it via `mix usage_rules.sync` were being taught
  a form the API rejects. It now also covers the per-type `send_media` options
  (including that the proto-cased spellings are refused), `send_call_timeout_ms`,
  `req_options`, and the three connect-time sync flags.

## [0.5.6] - 2026-08-01

> **Media sends were broken in every release up to 0.5.5** — if you send media,
> upgrade. Text sending was unaffected. This release also closes a HIGH-severity
> advisory in a dependency that parses untrusted network input (see **Security**).

### Security

- **`protobuf` raised to `~> 0.17`, closing GHSA-rv48-qqj5-crxg / CVE-2026-54451
  (HIGH)** ([#68]). Every `~> 0.15.0` version placed no recursion limit on
  embedded-message decoding, so a small deeply-nested payload could exhaust
  memory. That is directly reachable here: Amarula decodes protobuf from bytes
  decrypted from **any peer able to open a Signal session with you**, so this was
  a remote denial-of-service vector, not a theoretical one. 0.16.1 caps nesting at
  100 levels. No Amarula code changed — only the generated `decode/1` API is used,
  and the existing generated module compiles unchanged under 0.17.
- **Dependency lock refreshed alongside it** ([#68]) — `mint` (two HIGH, including
  the HTTP/2 CONTINUATION flood), `hpax` (HIGH) and `plug`, taking `mix hex.audit`
  in this repo from 14 advisories to none.

  To be precise about what that buys you: **only the `protobuf` floor above is
  enforced downstream.** `mix.lock` ships with the repo, not the package, so your
  build resolves this project's constraints against your own tree. `mint` and
  `hpax` arrive transitively via `req` and are not constrained here, and `plug` is
  test-only. If you carry an older `req`, re-resolve and run `mix hex.audit`
  yourself.

### Changed

- **Pinned WhatsApp Web version bumped to `2.3000.1044303277`** ([#70]). The pin
  must track a version WhatsApp still accepts; when it goes stale the failure is
  quiet and misleading — the QR / pairing code generates, the phone reports
  *"Couldn't link device"*, `:pairing_success` never fires, and the socket 408s and
  retries identically. The previous pin had drifted well behind the live revision,
  so **new-device pairing was affected**; already-paired sessions were not. (The pin
  can still be overridden without recompiling via `AMARULA_WA_VERSION`.)

### Fixed

- **Replying to a LID-addressed 1:1 chat no longer fails with `{:error,
  {:send_rejected, "400"}}`** ([#64]). `msg.channel` is LID-kind for a
  LID-originated chat, but our own devices were always enumerated by PN — and
  WhatsApp rejects a stanza that mixes addressing kinds. We now match our identity
  to the target's mode, as the group path already did.

- **1:1 sends to a contact that hasn't trusted this device are no longer silently
  dropped** ([#67]). WhatsApp gates them behind a trusted-contact token; without
  one the socket accepts the frame and the server discards it with ack error 463.
  Amarula now attaches a held token, issues one after each 1:1 send (and on a 463,
  never retrying the message — a retry worsens the restriction), ingests tokens
  pushed as `privacy_token` notifications, and reads the ones the history-sync blob
  already carried. Also fixes `Profile.picture_url/3` returning `{:ok, nil}` for a
  privacy-gated contact, which was indistinguishable from "no picture".

- **A stream error with no child tag now reports `"unknown"` instead of an empty
  reason** ([#72]). `get_first_child_tag/1` returns `""`, never `nil`, so the
  `|| "unknown"` fallback could not fire and the blank string reached the log and
  `last_error`. Ships alongside the removal of eight clauses Dialyzer proves
  unreachable — the one above was hiding this bug.

- **Media sends no longer fail with `{:error, {:send_rejected, "479"}}`** ([#61]).
  Every `send_media/5` — image, video, audio, document, sticker — was rejected by
  the server with ack error 479 (`smax-invalid`), while text sends on the same
  session delivered fine. The upload succeeded and the message encrypted and
  relayed; the rejection arrived milliseconds later, so nothing surfaced until the
  ack. The stanza shape was wrong in two ways: the `<message>` node carried
  `type="text"` (media needs `type="media"`), and the `mediatype` hint was an
  attribute of `<message>` when it belongs on **every per-device `<enc>`** — on the
  single `skmsg` `<enc>` for groups. Both are now emitted correctly, including on
  the retry-resend path (the attrs aren't cached, so they're re-derived from the
  message). Verified against Baileys `messages-send.ts` (`createParticipantNodes`
  and `getMessageType`) and a live whatsmeow capture.
- **`send_media/5` documents now carry their file name** ([#61]). The documented
  option is snake_case `:file_name`, but the document builder only read `:fileName`
  — so `documentMessage.fileName` was always `nil` and every document arrived
  untitled. Use the documented `:file_name`; the proto-cased `:fileName` is not an
  accepted option.
- **Three `send_media/5` options were unreachable and now work** ([#62]). The
  builders read `:gifPlayback`, `:isAnimated` and `:pageCount`, but `send_media/5`
  validates against a strict schema that **rejects unknown keys** — so the only
  spelling the builder accepted was the one the validator refused. Sending an
  animated-GIF video, an animated sticker, or a document page count was impossible
  through the public API. Same root cause as the `:file_name` bug above: the public
  API is snake_case while the generated protos are camelCase.

### Added

- **`:jpeg_thumbnail` option on `send_media/5` for `:document`** ([#65]) — JPEG
  preview bytes for the message bubble; without one the recipient sees a generic
  file icon. Pairs with `:page_count`.
- **`config :amarula, send_call_timeout_ms: ms`** ([#65]) — the shared
  `GenServer.call` deadline for send/fetch (default 90s, unchanged). Large media
  needs the whole encrypt+upload+relay inside it; raise `:req_options`
  `[receive_timeout:]` alongside. Verified live to 1.75GB.
- **`:gif_playback`, `:is_animated` and `:page_count` options on `send_media/5`**
  ([#62]) — play a video as a looping GIF, mark a sticker animated, and set a
  document's page count. Builders now name only public snake_case options and a
  single mapping translates to the proto field, so a documented option can't
  silently miss its field again; a test asserts every documented option lands.

- **Connect-time flags to skip history / app-state sync, for lighter ephemeral
  connects** ([#59]). Three per-connection settings (each default `true`, so
  existing behaviour is unchanged):
  - `:sync_history` — when `false`, still **acks** a pushed history-sync
    notification (the phone won't show this device as "Paused") but skips the
    download / decrypt / `:history_sync` emit. Distinct from `:sync_full_history`,
    which is the pairing-time *depth* knob.
  - `:sync_app_state` — when `false`, skips app-state resync on
    `server_sync`/`account_sync`/key-share (no `:chats_update`/`:contacts_update`
    from app-state). Shared keys are still stored, so re-enabling later works.
  - `:fire_init_queries` — previously declared but never read (a dead flag); now
    actually gates the post-login props/blocklist/privacy IQ queries.

- **A warning when Android browser mode is enabled** ([#71]). An Android
  `:browser` registers the device as an Android client rather than WhatsApp Web —
  deliberate, but previously silent.

- **`Amarula.AppState.force_resync/2` — consumer-initiated app-state resync.**
  Every app-state resync used to be server-triggered only (`server_sync`/
  `account_sync` notifications, or a freshly shared app-state-sync key),
  always resuming from whatever version is stored locally. There was no way
  for a consumer app to ask for a fresh resync itself. This adds that lever:
  it resets the named collections (default: all) to a clean, version-0 state
  and re-requests them as a full snapshot — the same request shape as a
  first-ever sync — rather than resuming from a version that may have drifted
  (e.g. after `Sync.decode_collection/5` reported repeated MAC mismatches and
  truncated batches). Fire-and-forget; results land as the usual
  `:chats_update`/`:contacts_update` events.

[#59]: https://github.com/tubedude/amarula/issues/59
[#61]: https://github.com/tubedude/amarula/pull/61
[#62]: https://github.com/tubedude/amarula/issues/62
[#64]: https://github.com/tubedude/amarula/issues/64
[#65]: https://github.com/tubedude/amarula/pull/65
[#67]: https://github.com/tubedude/amarula/issues/67
[#68]: https://github.com/tubedude/amarula/pull/68
[#70]: https://github.com/tubedude/amarula/pull/70
[#71]: https://github.com/tubedude/amarula/pull/71
[#72]: https://github.com/tubedude/amarula/pull/72
[Baileys#2683]: https://github.com/WhiskeySockets/Baileys/issues/2683
[Baileys#2711]: https://github.com/WhiskeySockets/Baileys/pull/2711
[Baileys#2743]: https://github.com/WhiskeySockets/Baileys/pull/2743
[Baileys#2748]: https://github.com/WhiskeySockets/Baileys/pull/2748
[Baileys#2752]: https://github.com/WhiskeySockets/Baileys/pull/2752
[#81]: https://github.com/tubedude/amarula/pull/81

## [0.5.5] - 2026-07-30

### Fixed

- **Reactions / edits / deletes / votes now address the right message when the
  peer wrote from a linked device** ([#46], [#47]). Two related defects in how a
  message key crosses the API — same shape as [#41].

  *Received keys were in the sender's perspective* ([#47]). A reaction / poll /
  edit / pin / keep you receive embeds a key naming its target **as the sender
  sees the chat** — in a 1:1 DM that means `remoteJid` is *your* jid and `fromMe`
  is false-from-their-side. `Amarula.Msg` documents such a key as safe to feed
  straight to `send_reaction/3`, but doing so pointed the reaction at *yourself*
  (it landed in your self-chat instead of going back to the peer). Groups masked
  it — a group jid is identical from every perspective. `Connection` now remaps
  every embedded key to your perspective before you see it (as Baileys'
  `normaliseKey` does): `remoteJid` becomes the chat as you see it, `fromMe` is
  recomputed against your own account (both PN *and* LID), and the target's author
  is preserved as `participant`.

  *The reference could not carry `from_me`* ([#46]). `send_edit` / `send_revoke` /
  `pin_message` / `keep_message` act on **your own** messages, but the
  `{jid, msg_id}` reference hardcoded `fromMe: false`, so the edit / revoke
  silently matched nothing (the payload is end-to-end encrypted, so the server
  cannot reject it — no error surfaces). References now carry `from_me`; see
  **Changed**.

- **Poll votes now derive their key from account-level identities** ([#48]). The
  vote key is derived from the creator and voter jids; a device (`:29`) or agent
  (`_1`) segment on either made each side derive a different key, so the vote
  decrypted to nothing and silently never counted — in 1:1 and group polls alike.
  `PollCrypto` now normalizes the device / agent segment at the crypto boundary
  (the PN/LID choice is deliberately preserved — a LID group votes on the LID).

- **`Contacts.fetch_status/2` no longer drops the query for a device-suffixed
  jid** ([#49]). A `<usync>` user jid must be account-level; a device suffix made
  the server drop the whole query. `USync.with_user/2` now normalizes it at the
  boundary, so no caller can reintroduce it.

- **`Address.same_account?/2` is no longer false for one identity written two
  ways** ([#51]). `Address.pn/1` stripped an agent segment (`user_1@…`) but
  `Address.parse/1` did not, so the two disagreed and `same_account?/2` returned
  false for what is a single identity. `parse/1` now strips the agent segment too.

### Changed

- **A message reference (`t:Amarula.message_ref/0`) now carries `from_me`.** A
  received `key` / `poll_key` — and a reference you build by hand — is now
  `{jid, msg_id, from_me}` (with an optional 4th `participant` for a group target),
  not the old `{jid, msg_id}` 2-tuple. Carrying `from_me` in the value is what lets
  a reaction / edit / vote address the right message ([#46], [#47]).

  The bare `{jid, msg_id}` 2-tuple **still works** but is **deprecated**: it emits
  a warning and assumes a per-operation default `from_me` (`true` for the
  self-directed `send_edit` / `send_revoke` / `pin_message` / `keep_message`,
  `false` elsewhere). If you only pass a received `key` straight back to a `send_*`
  helper — the documented pattern — nothing changes. Two cases do need an update:
  a reference you build by hand (pass the explicit 3-tuple), and code that
  *pattern-matches* the tuple (`{jid, id} = reaction.key` → `{jid, id, from_me}`).

[#46]: https://github.com/tubedude/amarula/issues/46
[#47]: https://github.com/tubedude/amarula/issues/47
[#48]: https://github.com/tubedude/amarula/issues/48
[#49]: https://github.com/tubedude/amarula/issues/49
[#51]: https://github.com/tubedude/amarula/issues/51

## [0.5.4] - 2026-07-29

### Fixed

- **History sync now surfaces messages and LID↔PN mappings** ([#40]). The
  `:history_sync` event carries `%{sync_type, chats, contacts, push_names,
  messages, status_messages, lid_mappings}` — previously `to_result/1` decoded
  the whole blob but mapped only chat metadata, contact names and push names,
  dropping every `conversation.messages` list on the floor. The practical
  impact: a message sent from your phone while a linked device was disconnected
  is never redelivered live on reconnect, and history sync discarded it too, so
  it was permanently unrecoverable by any consumer. `messages` and
  `status_messages` are `%Amarula.Msg{}` lists — the same consumer view the live
  path emits, so `download_media/1` and the `send_*` helpers work on them. Two
  caveats a consumer must handle: a history `%Msg{}` has less envelope than a
  live one (`to` is always `nil`, and `from` is `nil` when `from_me` is true, so
  branch on `from_me` before reading `from`), and a message may arrive both here
  and on `:messages_upsert` — dedup by `msg.id`. The LID↔PN mappings are read
  from all three sources Baileys collects, and are persisted and re-emitted as
  `:lid_mapping_update`, so a first link learns every synced chat's pair at
  once. They are stored and emitted only, never asserted: a history blob names
  every contact you have ever chatted with, so asserting sessions would fetch a
  prekey bundle for each one — burning a one-time prekey and risking throttling
  — for sessions nothing needs yet. The new result keys are purely additive, so
  existing `:history_sync` consumers keep working unchanged.
- **Replying with `msg.channel` no longer fails with `{:error, {:send_rejected,
  "400"}}` when the peer wrote from a linked device** ([#41]). `channel` is
  documented as the reply handle, but for a 1:1 DM it was the stanza's `from`
  attr verbatim — and that carries the **sending device** (`5511888888888:29@
  s.whatsapp.net`) whenever the peer types on WhatsApp Web/desktop rather than
  their phone. A DM has no `participant` attr to separate writer from room, so
  the room inherited the writer's device; the device is genuinely on the wire
  because Signal sessions are per-device (the decrypt path reads it off the same
  jid via `LidMappingFileStore.signal_address/2`). Nothing downstream stripped
  it — `deliver_async/5` flattens an `Address` target with `Address.to_jid!/1`,
  which re-encodes `device` verbatim, so a device-bound jid reached the relay
  stanza's `to` attr and WhatsApp rejected it with `<ack class="message"
  error="400">`. `Msg.from_proto/2` now normalizes `channel` (and a quoted
  message's `channel`, which becomes a `MessageKey.remoteJid`) to its
  account-level address. **`from` is unchanged** — the writer identity
  legitimately carries the device, and consumers rely on it to recognize their
  own device. Replying to a peer on their phone was always fine, which made this
  look intermittent.

[#40]: https://github.com/tubedude/amarula/issues/40
[#41]: https://github.com/tubedude/amarula/issues/41

## [0.5.3] - 2026-07-25

### Fixed

- **A single corrupt or stale app-state patch no longer permanently freezes
  that collection's sync**, without weakening MAC authentication.
  `Sync.decode_collection/5` used to abort an entire collection
  (chats/contacts/mute/pin/archive) the moment any patch's aggregate
  snapshot/patch MAC failed to verify — discarding every patch decoded in that
  batch and keeping the collection's old local version, so the next resync
  re-requested the same version and hit the same mismatch again, freezing
  updates for good if the cause didn't self-resolve. Decoding now matches
  WhatsApp Web's own resilience fix exactly (`chat-utils.ts`
  `decodeSyncdPatch`/`decodePatches`, upstream Baileys PR #2456): a **patch
  MAC** mismatch means that patch's mutations are unauthenticated and are
  dropped entirely (never decoded), but the collection version still advances
  so the freeze can't recur; a **snapshot MAC** mismatch means the patch's own
  (individually-authenticated) mutations still apply, but decoding stops for
  the rest of that batch since later patches' MACs are chained onto a
  now-diverged local hash — they're picked up on the next resync instead. Both
  cases are reported via a `mismatches` list (logged by
  `Connection.apply_app_state_reply/2`), never silently swallowed.

## [0.5.2] - 2026-07-21

### Fixed

- **Redelivery of an already-consumed group sender-key message no longer
  triggers an uncapped retry/nack loop** (#35). `GroupCipher`'s "old counter"
  condition was plain error prose, so `duplicate_decrypt_error?/1` (which only
  matched `%DecryptError{reason: :key_unavailable}`) never recognized it as a
  duplicate. Every occurrence fell through to retry + nack, which correlated
  with WhatsApp tearing down the whole stream (`code=500 reason=ack`) after
  repeated hits on the same `(group, sender)` pair. That one condition is now
  tagged `%DecryptError{reason: :key_unavailable}` at its source, matching the
  1:1 session path's vocabulary, so it's ack'd as delivered instead of retried
  forever.

## [0.5.1] - 2026-07-18

### Added

- **Message edits from newer WhatsApp clients are now decoded** (#30). Current
  clients send an edit as an encrypted `secretEncryptedMessage` envelope (keyed
  by the original message's `messageSecret`) instead of the legacy inline
  `protocolMessage.editedMessage`; those edits previously surfaced as `:other`
  with their text still encrypted. The connection now stashes each inbound
  message's secret for the 15-minute edit window (a per-connection in-memory
  cache) and decrypts the envelope back into the same `:edit` message the
  legacy path emits — no consumer changes needed. Envelopes that can't be
  decrypted (original older than the edit window, or received before the
  connection process last restarted) still fall through as `:other`, and an
  edit whose sender isn't the original message's author is rejected.
- **`Amarula.MessageSecretStore` — a pluggable store for the above secrets.** The
  default (`Amarula.MessageSecretStore.ETS`) is the per-connection in-memory
  cache described above, so nothing changes out of the box. If your app already
  persists received messages, point the store at them with
  `Amarula.MessageSecretStore.ReadOnly` (a `get: fn profile, msg_id -> {:ok,
  %{secret, sender}} | :error end` closure) via the `:message_secret_store`
  connection config: Amarula then keeps no in-memory copy, and edits survive a
  connection restart because retention becomes your durable store's. Mirrors the
  `Amarula.RetryCache` seam.
- **`Amarula.Msg.message_secret/1`** returns a received message's
  `messageContextInfo.messageSecret`, so a `ReadOnly` store can persist it (with
  `msg.from`, the sender the forgery check compares against) from the
  `:messages_upsert` event.

### Security

- **Fixed an atom-exhaustion denial-of-service on the receive path.** Inbound
  `<chatstate>` and group (`w:gp2`) notification tags were passed to
  `String.to_atom/1` — the chatstate path with no guard at all — so a peer streaming
  novel tag names could exhaust the BEAM atom table (atoms are never garbage
  collected) and bring the node down. Both paths now map only the tags the wire
  protocol defines to fixed atoms; anything else is ignored and never interned.

### Fixed

- **Media sends are now fully supervised and never orphan or hang.** Media
  encrypt+upload and history-sync downloads previously ran under bare, unsupervised
  `Task.start/1`, with a `try/rescue` that only caught raises — not external kills.
  They now run under a Connection-owned, linked `Task.Supervisor`; `send_media`
  always answers the caller (even if the job crashes) and a crashed media job can
  never take the connection's socket down with it.
- **Inbound messages whose payload begins with `0x88` or `0x8A` are no longer
  dropped.** Two receive-path clauses matched those bytes as WebSocket close/pong
  control frames, but the WebSocket layer already demultiplexes control frames — so
  the match ran against decoded message payloads and would silently swallow a
  legitimate one. Narrowed to exact single-byte matches.
- **A send to a contact whose prekey bundle can't be fetched now fails cleanly
  instead of crashing the sender** (#32). `ensure_sessions/1` reported success
  even when the bundle IQ round-trip returned no usable bundle for a device (the
  number isn't on WhatsApp, or a LID/PN mismatch queried the wrong wire JID),
  leaving the Signal session missing; the pipeline then crashed the per-recipient
  `ConversationSender` with a `MatchError` on `{:error, :no_session}`. It now
  re-checks for still-missing sessions after bundle injection and returns a clean
  `{:error, {:no_bundle, jids}}` through the normal send-failure path — no process
  crash, and the send `:stop` telemetry span is tagged `error_stage:
  :ensure_sessions`.

## [0.5.0] - 2026-07-11

### Added

- **`Amarula.retry_media/2` — re-upload retry for expired media.** WhatsApp's media
  URLs are short-lived; once the CDN drops a blob, `download_media/1` fails with
  `{:error, {:http, 404}}`. `retry_media/2` asks the sender's phone to re-upload it
  and returns a refreshed `%Amarula.Content.Media{}` (new `direct_path`) you can hand
  straight back to `download_media/1`. Returns `{:error, :not_on_phone}` if the phone
  no longer has it, `{:error, :timeout}` if it never answers.
- **`Amarula.send_options_reply/4` — reply to a button/list/template prompt.** Covers
  the normal "user taps a button" action (originating a new prompt remains
  unsupported). Pass the received `%Amarula.Msg{}` plus the tapped option's id and
  everything else — which proto to build, the display text, a template's 0-indexed
  button position — is auto-derived from the message's `content.options`:

      Amarula.send_options_reply(conn, msg, "yes")

  A lightweight `{jid, msg_id}` ref also works, with `:kind`/`:text`/`:index` supplied
  explicitly since the original prompt's options aren't available to look up.
  `:interactive` (native-flow) prompts are explicitly rejected with a clear error, not
  silently mis-encoded.
- **`SessionCustodian` — per-record serialization for Signal sessions (internal).** A
  per-record GenServer now funnels every load-modify-store of one Signal session
  through a single process, so the send path (`ConversationSender.encrypt`) and the
  receive path (`Connection` decrypt/migrate/wipe) can no longer clobber each other's
  whole-record write. Closes a real race: concurrent encrypt/decrypt against the same
  session could corrupt the ratchet state. No public API change; three new
  benchmarks (`scripts/bench_*.exs`) demonstrate both the race and the fix against
  real Signal traffic, no mocks.

### Changed

- **BREAKING — Amarula no longer starts its process tree; you add it to yours.** The
  library no longer defines an `Application` — the two registries and the connections
  `DynamicSupervisor` now live in a new **`Amarula.Supervisor`** that you add to your
  own supervision tree, so you control its placement, restart strategy, and nesting,
  and there is no global auto-start.

  **Migration:** add `Amarula.Supervisor` as a child, **before** any `{Amarula, …}`
  connection children and before `connect/2`:

      children = [
        Amarula.Supervisor,
        MyApp.Bot,
        {Amarula, profile: :me, parent: MyApp.Bot}
      ]

  If it isn't running when you connect, Amarula raises with a message telling you
  to add `Amarula.Supervisor`, instead of a `:noproc` exit or an opaque
  `unknown registry` error.
- **The `:contacts_update` avatar event carries more.** A `picture` notification now
  surfaces `picture_id` (to fetch the new avatar) and `author` (who changed it, on
  group avatars) alongside the existing `id`/`img_url`.

### Removed

- **The internal `Amarula.Baileys` parity module is gone.** Amarula is now an
  independent OTP-native implementation rather than a single-upstream port; the
  reference-revision tracking it held moved into `docs/PARITY.md`.

### Fixed

- **PN→LID Signal-session migration.** When a contact who was known by phone number
  adopts a LID identity, their live Signal session is now re-keyed from the
  phone-number address onto the LID address (both on receiving their next message and
  before the next send), instead of leaving the ratchet stranded — which previously
  caused a window of undecryptable messages. No renegotiation when a session already
  exists to move.
- **Duplicate 1:1 message redeliveries are acknowledged as received, not retried.** A
  ratchet message redelivered after a lost ack or a 515 restart is a consumed-key
  duplicate. Amarula now recognises it structurally (a typed decrypt error, covering
  both the `pkmsg` and the wrapped `msg` forms) and sends the same delivery receipt
  the success path does — draining the server's offline queue — instead of nacking
  `500` and firing a spurious retry receipt (the redelivery/poison loop).
- **A peer's identity change now actually refreshes the session.** On an
  `encrypt`/`identity` notification for a peer we hold a session with, Amarula wipes
  the stale session up front and re-fetches their key bundle — so nothing encrypts to
  the old identity in the gap. (The prior guard compared a jid against a
  signal-address key, so the refresh never fired.)
- **Group delivery/read receipts are no longer dropped.** An aggregated group
  receipt (no top-level `id`, one `<participants key=<msg_id>>` child per message)
  parsed as an empty-id `:receipt_update`; it now fans out to one `:receipt_update`
  per (message, participant), so per-member delivery/read state actually surfaces.
- **Own linked-device changes refresh the device cache.** An `account_sync`
  notification with a `<devices>` child (a device linked/unlinked from another
  session) was ignored, leaving our own device list stale until the next full USync —
  so a newly-linked device could be omitted from a send's encrypt recipients. We now
  drop our own cached device list on that notification.

## [0.4.5] - 2026-07-07

Two integrity fixes surfaced by reviewing the whatsmeow implementation.

### Fixed

- **App-state sync now verifies the snapshot and patch MACs.** Incoming app-state
  patches were checked at the per-record level (value/index MAC) but not at the
  collection level: the snapshot MAC (authenticating the resulting LTHash) and the
  patch MAC (authenticating the patch's mutations) were computed but never enforced.
  A patch whose MAC doesn't match is now rejected and not applied.
- **Media downloads now verify the declared plaintext hash.** After decrypting,
  `download/2` checks the decrypted bytes against the sender's `file_sha256` (carried
  on `%Amarula.Content.Media{}`) — end-to-end content integrity on top of the MAC,
  catching a decrypt/unpad bug. A mismatch returns `{:error, :bad_file_hash}`; a
  descriptor without the hash is skipped. (The MAC already covers ciphertext
  integrity, so the redundant `file_enc_sha256` check isn't performed.)

## [0.4.4] - 2026-07-04

### Changed

- **Debug logging separates signal from wire noise.** The always-on `:debug`
  stream now carries only routine bot activity (send/receive/receipts/presence);
  low-level frame/byte/hex tracing was removed from it and remains available
  opt-in via the `AMARULA_FRAME_TAP` env var. Sends emit a single
  `Sent <id> to <peer> (N device(s))` line once the relay actually succeeds, so a
  successful send and a failed send are each one visible line.

### Documentation

- Corrected the consumer event tuple to `{:amarula, type, data}` across the guides
  (was mistakenly shown as `{:whatsapp, …}`), and pointed module references at the
  hexdocs pages instead of repo-relative source links that 404'd.
- Rewrote the LID/PN addressing guide — the envelope (PN on the wire) vs. lock (LID
  crypto identity) split, and the PN↔LID mapping a consumer must keep to DM someone
  known only by LID (the by-LID device-lookup failure).
- `GOING_PROD`: fixed accuracy bugs — history sync arrives as its own
  `:history_sync` event (not `:messages_upsert`), a storage adapter needs only four
  required callbacks, media `content` is an `%Amarula.Content.Media{}` struct, and
  the `./amarula_data` storage dir must be gitignored by the consumer (the library's
  own ignore rule doesn't travel with the dependency).
- Hexdocs surface: hid the internal `Amarula.Protocol.*` / `Amarula.Connection.*`
  layers, grouped `Content` / `Storage` / `RetryCache` into sidebar folders, and
  fixed two moduledoc tables (`Amarula.Config`, `Amarula.Telemetry`) that a stray
  `|` had broken.

## [0.4.3] - 2026-07-03

### Added

- **`Amarula.render_qr/1`** — render the `qr` string from a `:connection_update`
  as terminal-printable ASCII art (the renderer `mix amarula.pair` already used,
  now public). No more hand-rolling QR display for the common case.
- **Telemetry: failure outcomes are now observable.** `[:amarula, :send, :stop]`
  carries `result`/`error_stage`/`error_reason` (compute a send error rate off one
  event); new `[:amarula, :send, :ack]` reports the post-relay server verdict
  (`:ok | :rejected | :timeout | :sender_crashed` + rejection code); new
  `[:amarula, :iq, :timeout]` counts the primary sick-connection signal.
- **README feature guide** — runnable examples for receive & reply (GenServer
  event sink), media send/download, reactions/quoted replies, groups, and offline
  bot testing with `Amarula.Testing`.
- **`Amarula.child_spec/1`** — start a fixed, known-at-boot set of profiles
  declaratively in your own supervision tree: `{Amarula, profile: :sales, parent:
  MyRouter}`. Each child gets a distinct `id` of `{Amarula, profile}`, so several
  coexist under one supervisor; an already-running profile is *adopted* (not an
  error), so a restart is safe. For **already-paired** accounts (pair first with
  `mix amarula.pair`) — an unbounded/dynamic set should use a `DynamicSupervisor` +
  `connect/2` instead. Backed by the new `Amarula.SupervisedConnection`, a thin
  owner that survives the socket's internal restarts so your supervisor never sees
  spurious child deaths, and tears the connection down on a deliberate shutdown.

### Fixed

- **Group decrypt failures report their real reason** — a bad signature, old
  counter, or padding error was previously relabeled "Failed to parse sender key
  message"; the parse label now applies only to genuinely unparseable payloads.
- **Malformed group IQ replies are errors, not empty successes** — a server
  `<error>` or missing attr in invite-code / join-request replies returned
  `{:ok, nil}` / `{:ok, []}`; they now return `{:error, reason}` like every other
  group op.
- **A USync status with no timestamp yields `set_at: nil`** instead of
  1970-01-01.
- **Closed Signal sessions no longer accumulate unboundedly** — the persisted
  session record is capped (40 closed sessions, oldest dropped), pruned at the
  same point libsignal does.
- **Media uploads honor `req_options`** like downloads (uploads are now
  `Req.Test`-stubbable).

### Removed

- **`BaileysCredentialLoader`** (a build-phase comparison tool) and a body of
  dead internal code (~5,800 lines: unused modules, behaviours with no
  implementers, test-only accessors).
- **Three redundant telemetry events**: `[:amarula, :send, :not_on_whatsapp]`
  (tag `send :stop` by `error_reason` instead), `[:amarula, :stream_error,
  :restart]` (`stream_error :received`'s `code` identifies the 515), and
  `[:amarula, :prekey, :upload]`. Handlers attached via
  `Amarula.Telemetry.events/0` need no change.

## [0.4.2] - 2026-07-02

### Fixed

- **Pre-key pool now refills before it drains (Baileys #2643).** The server-side
  one-time pre-key pool was only deep-refilled when it hit *exactly* 0; otherwise it
  topped up by just 5, so it idled near-empty and dropped first-contact messages
  under any burst. It now refills back toward the initial count (812) once it drops
  to/below a low-water mark (100), on both the login count-check and the server's
  `<notification type=encrypt>` top-up path.
- **View-once media now sends reliably (Baileys #2435 / #2678).** Outgoing media
  stanzas carry a `mediatype` attribute (`image`/`video`/`gif`/`audio`/`ptt`/
  `document`/`sticker`/…), derived through the view-once wrapper. WhatsApp silently
  dropped view-once video/audio sent without it. Applies to both 1:1 and group
  sends (the group relay now threads stanza attrs too).

### Changed

- **Bumped the WhatsApp Web protocol version** to `[2, 3000, 1_042_537_629]` (was
  `1_035_194_821`). The stale value silently broke new-device pairing — the QR /
  pairing code generated, but the phone reported "Couldn't link device" and
  `:pairing_success` never fired. Also aligned the (previously divergent, unused)
  mirror in `Amarula.Protocol.Crypto.Constants`.

### Added

- **`AMARULA_WA_VERSION` env override.** Set it to a dotted triple (e.g.
  `2.3000.1042537629`) to override the pinned WhatsApp Web version at runtime
  without recompiling — useful to track a new WhatsApp version before the pinned
  default is bumped. Malformed values are ignored (warned) and fall back to the
  pinned default. See `Amarula.Config.wa_version/0`.
- **`scripts/update_wa_version.exs`** — maintainer tool that fetches the live
  version from WhatsApp's own service worker (`client_revision` in `sw.js`, mirroring
  Baileys' `fetchLatestWaWebVersion()`) and rewrites the pinned literal for review +
  commit (`--check` to compare without writing). **The running library never fetches
  the version itself** — it always uses the pinned/overridden default.
- **`mix amarula.pair` task** — link an account by QR or phone code from any project
  that depends on Amarula (`mix amarula.pair <profile> [--phone <e164>]`). Unlike the
  `examples/` scripts, this ships in the Hex package (it lives under `lib/`), so a
  downstream integration can pair a user without vendoring a script. Addresses the
  "no easy way to pair an account" gap for consumers like agentjido/jido_chat#25.
- **Phone-code pairing docs + example.** `examples/pair.exs` now links by QR *or*
  by 8-char phone code (`mix run examples/pair.exs <profile> [phone-e164]`), and the
  README documents `Amarula.request_pairing_code/3` / the `:pairing_code` event for
  headless/programmatic pairing (the API already existed; this makes it discoverable).

## [0.4.1] - 2026-07-02

A security fix, ported from upstream Baileys.

### Security

- **Dropped spoofed self-only `protocolMessage`s.** `APP_STATE_SYNC_KEY_SHARE`
  and `HISTORY_SYNC_NOTIFICATION` are only ever legitimate from our own linked
  device, but `Connection` acted on them from any sender that could open a
  session with us — letting an attacker poison our app-state sync keys or feed
  us fake chat history. Both are now gated on `own_sender?/3` (participant, or
  `from` when absent, matched against our own id/lid), mirroring Baileys'
  fix for [GHSA-qvv5-jq5g-4cgg / CVE-2026-48063](https://github.com/WhiskeySockets/Baileys/security/advisories/GHSA-qvv5-jq5g-4cgg)
  (`v7.0.0-rc12`). A spoofed message is dropped with a warning log instead of
  processed; the node is still acked/receipted as normal so the offline queue
  drains.

## [0.4.0] - 2026-07-01

First hex release since 0.3.0 — the 0.3.1 section below landed in git but was
never published; its changes ship in this release too.

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
- **Keep-alive pings no longer multiply across reconnects.** The generic reconnect
  path armed a new ping timer without cancelling the old one, so every reconnect
  added a permanent extra ping loop (which can itself provoke server disconnects).
- **Reconnect backoff and give-up actually work.** `retry_count` was reset the
  moment the socket process started, so backoff never grew and `max_retries`
  never triggered — a server that accepts-then-drops caused a tight reconnect
  storm. The counter now resets only on a successful login, and a server close
  counts toward the limit; exhausting it transitions to `:closed`.
- **A malformed `<enc>` payload can't take down the connection.** `skmsg` and
  `plaintext` decrypt paths were unguarded, so garbage bytes crashed the whole
  `Connection` (dropping the batch and forcing a reconnect). Every enc type now
  degrades to a per-enc error entry.
- **Constant-time pairing HMAC verification.** The ADV device-identity HMAC was
  compared with `==`; it now uses `:crypto.hash_equals/2` with a length pre-check,
  like every other MAC comparison in the codebase.
- **Retry-cache reads no longer mint atoms from `profile`.** Unknown profiles
  resolved through `:"amarula_retry_cache_#{profile}"` on every read — an atom
  exhaustion vector for multi-tenant bots with user-derived profiles. Reads now
  use `String.to_existing_atom`; the atom is created once, at connection init.
- **`send_media` can't hang its caller.** A raise inside the media encrypt/upload
  task left the caller blocked for the full 90s call timeout; it now replies
  `{:error, {:media_prepare_failed, _}}`.
- **A 515 restart fails parked IQ callers fast.** Pending `query_iq` waiters were
  silently dropped on restart and hung to their 25s call timeout; they now get
  `{:error, :not_connected}` immediately.
- **Unexpected messages no longer crash `Connection`.** Catch-all `handle_call`/
  `handle_info` clauses log and ignore instead of `FunctionClauseError`-ing the
  whole per-connection tree.
- **Hosted JIDs decode correctly off the wire.** The binary decoder read AD_JID
  domain types 2/3 for `hosted`/`hosted.lid` while the encoder (and Baileys'
  `WAJIDDomains`) use 128/129 — hosted device jids silently mangled to
  `s.whatsapp.net` on receive.
- **Server-supplied integers degrade instead of crashing.** Malformed receipt
  `t`, group `size`, and JID device/agent segments (decode and encode paths) now
  parse via `Integer.parse` with a fallback rather than raising mid-frame.
- **Trial decryption can't mask real bugs.** The Signal session trial-decrypt
  loop rescued *every* exception as "wrong session, try next"; it now rescues
  only the new `DecryptError` (bad MAC / version / chain), so programming errors
  propagate instead of surfacing as "No matching sessions found".

### Changed

- **Binary node encoding is O(n).** The encoder accumulated a byte list with tail
  appends and exploded binaries via `bin_to_list` — quadratic time and ~10x
  memory on large payloads. It now builds iodata.
- Removed dead internal modules: `Signal.Repository` and `Signal.LIDMappingStore`
  (unused, superseded by `LidMappingFileStore`), the unused `SenderKeyName`
  hash/parse helpers, and the vestigial `WebSocketClient` connect/state-predicate
  API.

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
- **The connection auto-reconnects when the websocket dies.** When the underlying
  websocket goes down unexpectedly, `Connection` now unlinks and monitors it, then
  reconnects — instead of the dead socket lingering. Paired with the down-transition
  emit below, a consumer sees the connection go down and come back.
- **A send while disconnected no longer crashes the connection.** Relaying a frame
  with no live socket now returns an error to the caller instead of taking the
  `Connection` process down with it.
- **Errors emit a `:connection_update` down-transition.** On a connection error the
  consumer now gets a `connection: :close` (down) `:connection_update`, so the
  connection state a consumer observes always reflects reality.

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
- **`docs/LID_PN.md`** — a LID vs PN identity guide: the two identities a person
  has, raw JID vs the parsed `Amarula.Address`, the LID>PN rule (sessions and
  bundles key on LID; the wire `<to>` stays PN), where mappings are learned, and how
  a consumer should key its own contacts.

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

[Unreleased]: https://github.com/tubedude/amarula/compare/v0.5.7...HEAD
[0.5.7]: https://github.com/tubedude/amarula/compare/v0.5.6...v0.5.7
[0.5.6]: https://github.com/tubedude/amarula/compare/v0.5.5...v0.5.6
[0.5.5]: https://github.com/tubedude/amarula/compare/v0.5.4...v0.5.5
[0.5.4]: https://github.com/tubedude/amarula/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/tubedude/amarula/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/tubedude/amarula/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/tubedude/amarula/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/tubedude/amarula/compare/v0.4.5...v0.5.0
[0.4.5]: https://github.com/tubedude/amarula/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/tubedude/amarula/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/tubedude/amarula/compare/v0.3.0...v0.4.3
[0.3.0]: https://github.com/tubedude/amarula/compare/v0.2.4...v0.3.0
[0.2.4]: https://github.com/tubedude/amarula/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/tubedude/amarula/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/tubedude/amarula/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/tubedude/amarula/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/tubedude/amarula/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tubedude/amarula/releases/tag/v0.1.0
