# Baileys parity

Amarula is a port of [Baileys](https://github.com/WhiskeySockets/Baileys). Its
protocol logic tracks a **specific upstream revision**, recorded in one place:
`Amarula.Baileys.parity/0` (`lib/amarula/baileys.ex`). This doc is the runbook for
checking upstream for changes and re-syncing.

## Currently pinned

Run `Amarula.Baileys.parity()` for the live value. As of this writing:

| field | value |
|-------|-------|
| Baileys version | `7.0.0-rc13` |
| commit | `eb595a5a8f0fd6b753ee97e3b2d77612fafa501d` |
| date | 2026-06-10 |

## Two versions — don't conflate them

- **Source parity** (this doc / `Amarula.Baileys`): which Baileys *commit* our port
  is faithful to. Bump when you port new upstream changes.
- **WA protocol version** (`Amarula.Config` `:version`, e.g. `[2, 3000, …]`): the
  on-the-wire version WhatsApp must accept, pinned from `src/Defaults/index.ts`.
  Bump when WhatsApp/Baileys bumps it, or the handshake is rejected.

Either can change without the other.

## Checking upstream for changes to port

From the Baileys checkout (the repo root, one level up from `amarula/`):

```bash
# Fetch the latest upstream and see what landed since our pinned commit.
git fetch origin
PINNED=eb595a5a8f0fd6b753ee97e3b2d77612fafa501d   # = Amarula.Baileys.parity().commit

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

1. Update **all four** fields of `@parity` in `lib/amarula/baileys.ex` (version,
   commit, date, repo) to the new upstream revision.
2. If `src/Defaults/index.ts` changed the WA version, also update `@wa_version` in
   `lib/amarula/config.ex` to match.
3. Note what you ported in `CHANGELOG.md`.
4. The doctest in `Amarula.Baileys` asserts the version string — update it too.

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
