# Upstream References

Amarula ports its protocol logic from [Baileys](https://github.com/WhiskeySockets/Baileys). While Baileys serves as our reference for what WhatsApp Web expects on the wire, Amarula doesn't mirror its TypeScript/Node.js code structure. We adapt the protocol to fit idiomatic BEAM concurrency. For example, `SessionCustodian` handles per-record serialization using OTP patterns, rather than trying to mimic a single-process Node environment.

We rely on two upstream references for different reasons:

* **[Baileys](https://github.com/WhiskeySockets/Baileys) (TypeScript):** Our primary source for the port. We track a **review watermark**—the specific commit marking the last time we reviewed Baileys for upstream changes. This isn't a guarantee of 100% bug-for-bug parity; any undetected protocol flaws in Baileys up to that commit might also exist here.
* **[whatsmeow](https://github.com/tulir/whatsmeow) (Go):** An independent implementation used for cross-checking. Since it's a separate codebase, it's a great tool for catching bugs that Baileys and Amarula might share, and for understanding undocumented parts of the protocol.

This document tracks our current Baileys review watermark and serves as a runbook for reviewing further.

## Pinned Baileys Revision

| Field | Value |
| --- | --- |
| Baileys version | `7.0.0-rc13` (+3 commits) |
| Commit | `731cd6b5d1` |
| Date | 2026-07-20 |

*(To re-verify: dereference `refs/tags/v7.0.0-rc13` on the real Baileys repo to get the commit the tag resolves to, rather than the tag object's own SHA.)*

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
PINNED=8053b086ecc97ec3f78299561de11959bab05d39   # the commit pinned above

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

## Upstream review — 2026-07-20: app-state collection resilience

From a reliability-focused pass over Baileys' `src/Utils/chat-utils.ts`
(`decodeSyncdPatch`), targeting silent-failure-class gaps — protocol mechanisms
whose *absence* looks like normal operation, not a crash.

**Ported:**

- **App-state collection resilience** — `Sync.decode_collection/5` used to abort
  a whole collection's sync on one patch's aggregate MAC mismatch, discarding
  every patch decoded in the same batch and keeping the old version — so the next
  resync re-requested the exact same version and hit the exact same mismatch,
  freezing `chats`/`contacts`/mute/pin/archive updates for that collection
  permanently if the cause didn't self-resolve. A patch's *individual* record
  MACs already authenticate it (same app-state-sync key), so an aggregate
  mismatch is now reported (`mismatches` in the return tuple, logged by
  `Connection.apply_app_state_reply/2`) rather than fatal — mutations and the
  version still apply.
