# Upstream References

Amarula ports its protocol logic from [Baileys](https://github.com/WhiskeySockets/Baileys). While Baileys serves as our reference for what WhatsApp Web expects on the wire, Amarula doesn't mirror its TypeScript/Node.js code structure. We adapt the protocol to fit idiomatic BEAM concurrency. For example, `SessionCustodian` handles per-record serialization using OTP patterns, rather than trying to mimic a single-process Node environment.

We rely on two upstream references for different reasons:

* **[Baileys](https://github.com/WhiskeySockets/Baileys) (TypeScript):** Our primary source for the port. We track a **review watermark**—the specific commit marking the last time we reviewed Baileys for upstream changes. This isn't a guarantee of 100% bug-for-bug parity; any undetected protocol flaws in Baileys up to that commit might also exist here.
* **[whatsmeow](https://github.com/tulir/whatsmeow) (Go):** An independent implementation used for cross-checking. Since it's a separate codebase, it's a great tool for catching bugs that Baileys and Amarula might share, and for understanding undocumented parts of the protocol.

This document tracks our current Baileys review watermark and serves as a runbook for reviewing further.

## Pinned Baileys Revision

| Field | Value |
| --- | --- |
| Baileys version | `7.0.0-rc14` (master, unreleased) |
| Commit | `0af2386292907f7d9742d8d41f830d8c48208fa1` |
| Date | 2026-08-05 |

*(To re-verify: dereference `refs/tags/v7.0.0-rc14` on the real Baileys repo to get the commit the tag resolves to, rather than the tag object's own SHA.)*

## Two Versions to Track

Make sure to keep these two versions distinct, as either can change without the other:

* **Review watermark** (tracked in this doc): The boundary between what we've reviewed and what we haven't. You should bump this whenever you review upstream, even if you don't immediately port everything you find.
* **WA protocol version** (`Amarula.Config` `:version`, e.g., `[2, 3000, …]`): The on-the-wire version WhatsApp expects, pinned from `src/Defaults/index.ts`. Bump this when Baileys updates it or if WhatsApp starts rejecting the handshake.

## Checking Upstream for Changes

Run these checks from the Baileys checkout (one level up from `amarula/`).

**Setup tip:** Make sure your local checkout tracks branches, not just tags. If `git for-each-ref refs/remotes/` is empty, you'll need to update your fetch refspec to `+refs/heads/*:refs/remotes/origin/*` (or re-clone normally) before continuing. Also, double-check that the `$PINNED` hash actually resolves (`git cat-file -t $PINNED`) so the diff commands don't silently fail.

```bash
# Fetch the latest upstream and see what landed since our pinned commit.
git fetch origin
# Read the watermark straight out of the table above, so there is only ONE copy of
# it in this file. A hardcoded SHA here drifted out of step with the table and sent
# anyone following this runbook diffing against the wrong base — which shows up as
# phantom "unreviewed" commits.
# (these commands run from the Baileys checkout, so amarula/ is one level up)
PINNED=$(sed -n 's/^| Commit | `\(.*\)` |$/\1/p' ../amarula/docs/PARITY.md)

# Commits we haven't reviewed yet:
git log --oneline $PINNED..origin/master

# Focus on the layers we actually port (skipping docs/build/test updates):
git diff $PINNED..origin/master -- src/Socket src/Signal src/Utils src/WABinary src/Defaults
```

Read that diff against Amarula's corresponding modules. Look out for changes to protocol behavior: stanza shapes, crypto, encode/decode, version constants, and retry/ack logic. You can safely ignore TypeScript-specific updates like types, linting, or build configs.

## Bumping the Watermark

After reviewing a newer Baileys commit, update the watermark—even if you decide to defer porting some of the findings. Just log what you deferred and why in the review section below.

1. Update the **Pinned Baileys Revision** table above (version, commit, date).
2. If `src/Defaults/index.ts` changed the WA version, also update `@wa_version` in `lib/amarula/config.ex` to match.
3. Note anything you ported in `CHANGELOG.md`.

## Cross-checking against whatsmeow

Since `tulir/whatsmeow` is a completely independent Go implementation, it's worth periodically diffing *behavior* (not code) against Amarula to catch shared blind spots:

```bash
git clone --depth 1 https://github.com/tulir/whatsmeow /tmp/whatsmeow
```

This is purely a cross-check. We don't copy whatsmeow's code (it's MPL-2.0), but we learn from how it handles the protocol. This practice has already helped us fix media plaintext-hash verification on download, app-state snapshot/patch MAC validation, duplicate-redelivery handling, and receipt-vs-nack semantics for consumed-key duplicates.

## Where Baileys Lives in Amarula

See the mapping table in the repo-root `CLAUDE.md` ("Reference implementation structure") for the full breakdown. In short:

* `src/Socket/*` → `lib/amarula/connection.ex` + `lib/amarula/protocol/socket/`
* `src/Signal/*` → `lib/amarula/protocol/signal/`
* `src/WABinary/*` → `lib/amarula/protocol/binary/`
* `src/Utils/noise-handler.ts` → `lib/amarula/protocol/crypto/noise_handler.ex`
* `src/Defaults/index.ts` → `lib/amarula/config.ex`

## Upstream review — 2026-07-02 (rc12→rc13 + open items)

Audited the rc12→rc13 diff and the notable open Baileys issues/PRs against Amarula.

**Ported:**

- **#2643** pre-key pool refill — was refilling only at exactly 0; now refills
  toward the initial count below a low-water mark. `pre_key_ops.ex` + `connection.ex`.
- **#2435 / #2678** view-once media `mediatype` on send — `message_content.ex`
  (`media_type/1`) + `send_ops.ex` + group relay.

**Deferred (not yet ported):**

- **#2547** decrypt `secretEncryptedMessage` (secretEncType `:MESSAGE_EDIT`) — edits
  from newer clients arrive as an extra encryption layer keyed by the original
  message's `messageContextInfo.messageSecret`. Amarula handles only the legacy
  inline `editedMessage`; the new envelope falls through to `{:other, _}` still
  encrypted. Needs a small TTL cache of inbound message secrets (~15-min edit
  window, modelled on `DeviceListCache`'s lazy-expiry-on-read) + `PollCrypto`-style
  HMAC+GCM decrypt. NB: the retry cache is *not* usable for the secret (outbound,
  LRU-bounded). See the KNOWN GAP note at the `:MESSAGE_EDIT` clause in
  `message_content.ex`.

**Reviewed, NOT affected (no action needed):**

- **rc13** `fromMe` for peer-routed self stanzas — Amarula computes `from_me?` by
  matching the sender against our own account unconditionally (`connection.ex`), so
  it never had the gap rc13 patches.
- **#2665** `bufferToUInt` OOB read — Amarula's decoder is bounds-guarded (safe
  binary matches / pre-checked slices / `decode_frame` rescue); no `bufferToUInt`
  analog.
- **#2640** LIDMappingStore unbounded cache — Amarula's LID/device stores are
  file-backed with lazy TTL, no in-memory map or per-entry timers.

## Upstream review — 2026-07-24: app-state MAC-mismatch resilience

Prompted by a reliability bug report (`Sync.decode_collection/5` aborting a
whole collection's sync — chats/contacts/mute/pin/archive — on one patch's
aggregate MAC mismatch, permanently freezing that collection at the same
version on every resync retry) and a since-reverted first attempt (PR #37) that
fixed the freeze but went further than Baileys' own fix, applying
unauthenticated mutations and continuing past mismatches mid-batch.

**Ported, matching Baileys exactly (`chat-utils.ts`
`decodeSyncdPatch`/`decodePatches`, upstream Baileys PR #2456 "App state sync
resilience — skip undecryptable records instead of aborting", built on #2350):**

- **Patch MAC mismatch** → that patch's mutations are unauthenticated against
  this collection/version and are dropped entirely (mirrors
  `decodeSyncdPatch` throwing *before* `decodeSyncdMutations` is called); the
  collection version still advances to this patch's version so the freeze
  can't recur, and decoding continues to the next patch in the batch (mirrors
  `decodePatches`' catch + `continue`).
- **Snapshot MAC mismatch** → this patch's own mutations already passed
  per-record value/index MAC checks, so they still apply (mirrors
  `decodePatches` applying `decodeResult` before the snapshot check runs), but
  decoding stops for the rest of the batch since later patches' MACs chain
  onto a now-diverged local hash (mirrors `decodePatches`' `break`); the
  remaining patches are picked up on the next resync.
- Both kinds are surfaced via a `mismatches` return element (logged by
  `Connection.apply_app_state_reply/2`), never silently swallowed.

## Upstream review — 2026-08-01 (rc13→rc14)

The rc13→rc14 diff itself is four commits, but reviewing #2607 exposed that our
tctoken port covered only the **message** path. Baileys attaches the same token
in four places; the other three (profile picture, `presence subscribe`, and the
history-sync ingestion that populates the store in the first place) all predate
the rc13 watermark — they arrived in #2339 and were simply never carried over.
They are ported here alongside the rc14 delta.

**Ported:**

- **#2607** profile-picture tctoken, adopted **directly in its fixed form**: the
  `<tctoken t="...">` nests *inside* the `<picture>` node rather than sitting
  beside it (a sibling makes the server ignore it, so the picture returns empty
  and is indistinguishable from "no picture"). `Profile.Ops.picture_url_query/3`
  + `Amarula.Profile.picture_url/3`. Since we never shipped the sibling shape,
  there is no migration — only the gap closes.
- **tctoken on `<presence type=subscribe>`** (#2339) — top-level, *not* nested;
  `Protocol.Presence.subscribe/3` + the `:presence_subscribe` handler.
- **tctoken ingestion from history sync** (#2339, `storeTcTokensFromHistorySync`)
  — `HistorySync` now decodes `tcToken` / `tcTokenTimestamp` /
  `tcTokenSenderTimestamp` into a `:tc_tokens` result key, and `Connection`
  persists them via `TcTokenStore.store_history_sync/2`. This is the one with
  real behavioural weight: without it a freshly linked device starts with an
  empty store and has to earn a token per contact off rejected (`463`) sends,
  even though the phone just handed us every token it holds.
- **WA protocol version** — bumped to the *live* revision rather than Baileys'
  bundled `2.3000.1043857760`, since the bundled default is itself allowed to
  lag and stale pairing fails silently.
- **Android "experimental" warning** (the `Socket/socket.ts` hunk of #2201).

**Reviewed, NOT affected (no action needed):**

- **#2201** Android browser — already ported in `ccabc9b`, ahead of it landing
  upstream: platform `:ANDROID`, `webInfo` omitted, `DeviceProps.platformType`
  `:ANDROID_PHONE`. Only the warning above was missing.
- **The message `<tctoken>` keeps empty attrs.** rc14's `t` attr lands in
  `buildTcTokenFromJid`, which serves only the picture and presence paths;
  `messages-send.ts` still builds its own with `attrs: {}`. Adding `t` there
  would be a divergence, not a fix — `send_flow_test.exs` now asserts it stays
  empty. This is why `TcTokenStore` exposes both `valid_token/2` (bare) and
  `valid_entry/2`/`token_children/2` (timestamped).
- **rc14's "timestamp-less token is unusable" hardening** — already implied:
  `store_token/3` has always required a parseable `t` to write at all, so such
  an entry never reaches the store.
- **#2586** `import type Long` — TypeScript-only.

**Deferred (not ported):**

- **The `__index` sentinel + 24 h expired-token prune**
  (`messages-recv.ts:2050-2161`). Baileys needs the index because its prune walks
  an in-memory set; our store is one file-backed key per contact, so there is no
  memory pressure — only dead entries accumulating on disk. Worth doing if a
  long-lived profile's `tctoken` directory ever grows enough to matter.
- **Clear-on-expired-read.** `buildTcTokenFromJid` deletes the stored record when
  it finds it expired (preserving `senderTimestamp`); our `valid_entry/2` is a
  pure read and leaves it. Same observable send behaviour, one less write on the
  hot path.
- **tctoken re-issuance after a peer's identity change**
  (`messages-recv.ts:727`). `maybe_refresh_identity/3` wipes the stale sessions
  and refetches the bundle, but does not re-issue the privacy token, so the first
  send after a peer relinks can still cost one `463` round-trip.

## Upstream review — 2026-08-05 (rc14→master, 2 commits)

Routine watermark bump. Only two commits landed on Baileys `master` since the
rc14 pin, one of them protocol-relevant; also swept open issues/PRs on both
Baileys and whatsmeow for anything unmerged but worth tracking.

**Ported:**

- **#2741** `WIN32` → `WIN_HYBRID` web sub-platform — see CHANGELOG. Confirmed
  via `git diff` against `src/Utils/validate-connection.ts` that this is the
  full extent of the merged fix (a superset, PR #2693 covering Mac OS +
  `syncFullHistory` platform selection too, is still open/unmerged — watching,
  not porting speculative upstream work).
- **WA protocol version** bumped `1044303277` → `1044539926` (routine drift
  check, `mix run scripts/update_wa_version.exs`).
- **Pairing-code path no longer resolves before the server confirms**
  (Amarula-original fix — not ported, neither reference has one yet; see
  below for how the bug was found). `start_link_code_pairing/3` now sends the
  `companion_hello` IQ as a *tracked* IQ (`:pairing_code_hello`, the existing
  bootstrap-continuation mechanism `send_tracked_iq` already uses for
  login/prekey/digest) instead of fire-and-forget. The `{:ok, code}` reply and
  `:pairing_code` event still fire immediately — the code needs to reach the
  user right away and the common case is acceptance — but a server rejection
  now surfaces asynchronously as the existing `:pairing_failure` event instead
  of being silently dropped. No `IQ`/`pending_iqs` module change needed:
  pairing is low-frequency (once per pairing attempt), so it doesn't need the
  blocking-waiter machinery hot sends use — reusing the tracked-IQ path
  already built for one-off bootstrap steps was simpler than extending `IQ`
  to carry both a reply-to-caller and a state side-effect through one
  resolution. See `handle_tracked_iq(:pairing_code_hello, ...)` and the new
  regression test in `link_code_pairing_test.exs`.

**Reviewed, NOT affected (no action needed):**

- The other master commit (`74af8eee`) only touches `Example/example.ts` —
  no source impact.

**Watching (open upstream, not yet fixed anywhere — do not port speculatively):**

- **[Baileys #2737](https://github.com/WhiskeySockets/Baileys/issues/2737) —
  potentially critical.** As of ~2026-07-28, WhatsApp began sending a
  `<notification type="companion_reg_refresh">` to the companion client
  immediately after a successful QR scan. Neither Baileys nor whatsmeow
  (independently reproduced, `go.mau.fi/whatsmeow@e9a033b`) implement it; both
  ack-and-discard it, `pair-success` never arrives, and the phone reports
  "Couldn't link device — try connection again." Amarula has no handler for
  `companion_reg_refresh` either (`Router`/`dispatch_notification` in
  `connection.ex`), so it is presumptively exposed to the same failure — **new
  QR-based device pairing may currently be broken industry-wide**, not just
  for us. No open PR resolves the root cause yet (only server-side; no client
  workaround identified). Re-check this issue before assuming a live pairing
  failure is Amarula-specific. The #2737 thread also flagged a secondary,
  independent bug in Baileys' `requestPairingCode()` (resolves before the
  server responds) — Amarula had the same shape; see the Ported entry above
  for our fix.
- **PR #2693** (open, unmerged) — broader desktop-platform fix superseding
  #2741: also maps `Mac OS` + `Desktop` + `syncFullHistory` to
  `UserAgent.Platform.MACOS` (currently always `WEB` unless Android).
  Speculative/unreviewed by Baileys maintainers; Amarula's
  `create_user_agent/1` has the same always-`WEB`-unless-Android gap. Revisit
  once merged.
