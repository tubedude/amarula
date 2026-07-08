# Upstream references

Amarula's protocol logic was ported from [Baileys](https://github.com/WhiskeySockets/Baileys).
Two different upstream references keep that port honest, for two different reasons
— don't conflate them:

- **[Baileys](https://github.com/WhiskeySockets/Baileys)** (TypeScript) — the port
  lineage, not an independent check. We track a *specific* Baileys revision so we
  can `git diff` it against newer Baileys and find upstream changes worth porting.
  A bug in Baileys itself would happily reproduce here too — this only catches
  drift from our own source, not a shared mistake.
- **[whatsmeow](https://github.com/tulir/whatsmeow)** (Go, by tulir) — the actual
  independent implementation, and the only one of the two that can catch a bug
  Baileys and Amarula share. It's often the more rigorously reverse-engineered of
  the two.

This doc is the single source of truth for the pinned Baileys revision (there is no
`Amarula.Baileys` module — Amarula has graduated from being a single-upstream port,
so the tracking lives here) and the runbook for re-syncing.

## Pinned Baileys revision

| field | value |
|-------|-------|
| Baileys version | `7.0.0-rc13` |
| commit | `8053b086ecc97ec3f78299561de11959bab05d39` |
| date | 2026-05-21 |

(Verified directly against `refs/tags/v7.0.0-rc13` on the real Baileys repo —
the commit the tag actually resolves to, not the tag object's own SHA. A
previous version of this table listed a hash that doesn't exist in Baileys'
history at all.)

## Two versions — don't conflate them

- **Source parity** (this doc): which Baileys *commit* our port is faithful to. Bump
  when you port new upstream changes.
- **WA protocol version** (`Amarula.Config` `:version`, e.g. `[2, 3000, …]`): the
  on-the-wire version WhatsApp must accept, pinned from `src/Defaults/index.ts`.
  Bump when WhatsApp/Baileys bumps it, or the handshake is rejected.

Either can change without the other.

## Checking upstream for changes to port

From the Baileys checkout (the repo root, one level up from `amarula/`).

**Prerequisite — the checkout must track branches, not just a tag.** A
tag-only clone (`fetch = +refs/tags/vX:refs/tags/vX` in `.git/config`, no
`refs/heads/*` refspec) will never populate `origin/master`, no matter how
many times you fetch — the commands below fail outright against one. Confirm
with `git for-each-ref refs/remotes/`; if it's empty, re-point the fetch
refspec to `+refs/heads/*:refs/remotes/origin/*` (or re-clone normally)
before continuing.

**Also confirm the pin itself resolves** (`git cat-file -t $PINNED`) before
trusting the diff — a stale or hand-typed hash here silently breaks this
whole workflow without an obvious error until the `git log`/`git diff` below.

```bash
# Fetch the latest upstream and see what landed since our pinned commit.
git fetch origin
PINNED=8053b086ecc97ec3f78299561de11959bab05d39   # the commit pinned above

# Commits we haven't reviewed yet:
git log --oneline $PINNED..origin/master

# Focus on the layers we actually port (skip docs/build/test churn):
git diff $PINNED..origin/master -- src/Socket src/Signal src/Utils src/WABinary src/Defaults
```

Read that diff against Amarula's corresponding modules (the `CLAUDE.md` mapping
table pairs each `src/` file with its Elixir home). Port anything that changes
protocol behaviour: stanza shapes, crypto, encode/decode, version constants,
retry/ack logic. Ignore TypeScript-only churn (types, lint, build).

## Re-syncing (bumping the pin)

When you've ported up to a newer Baileys commit:

1. Update the **Pinned Baileys revision** table above (version, commit, date).
2. If `src/Defaults/index.ts` changed the WA version, also update `@wa_version` in
   `lib/amarula/config.ex` to match.
3. Note what you ported in `CHANGELOG.md`.

## Cross-checking against whatsmeow

whatsmeow (`tulir/whatsmeow`) is an independent Go implementation of the same
protocol. Periodically clone it and diff *behaviour* (not code) against Amarula to
catch bugs the single-upstream port could share with Baileys:

```bash
git clone --depth 1 https://github.com/tulir/whatsmeow /tmp/whatsmeow
```

This cross-check has already surfaced real fixes — media plaintext-hash
verification on download, app-state snapshot/patch MAC validation, the
duplicate-redelivery handling, and the receipt-vs-nack semantics for consumed-key
duplicates. It is a **cross-check, not a port**: we don't copy whatsmeow's code
(it's MPL-2.0), we learn from its handling of the undocumented protocol.

## Where each Baileys layer lives in Amarula

See the mapping table in the repo-root `CLAUDE.md` ("Reference implementation
structure"). In short: `src/Socket/*` → `lib/amarula/connection.ex` +
`lib/amarula/protocol/socket/`; `src/Signal/*` → `lib/amarula/protocol/signal/`;
`src/WABinary/*` → `lib/amarula/protocol/binary/`; `src/Utils/noise-handler.ts` →
`lib/amarula/protocol/crypto/noise_handler.ex`; `src/Defaults/index.ts` →
`lib/amarula/config.ex`.

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
