# SessionCustodian concurrency benchmarks

`Amarula.Protocol.Signal.SessionCustodian` (see `docs/INFRASTRUCTURE.md`) adds a
process, a registry, and a locking discipline in front of every Signal session
record. That's real complexity, and complexity is a claim that should be
checked, not assumed. This document reports a benchmark exercise measuring
session correctness with the per-record lock removed — methodology, results,
and, just as importantly, the limits of what was actually measured.

Headline result: a lock-free version of the same code loses roughly 3 in 4
concurrent send/receive rounds under realistic timing, most of them silently.
Full breakdown below.

## The problem

A 1:1 session's ratchet is one blob, `load → mutate → store`, mutated by two
different processes — `ConversationSender` on send (encrypt) and `Connection`
on receive (decrypt) — with nothing serializing them. A concurrent send +
receive to the same contact can interleave that read-modify-write and silently
lose one side's advance (a forked ratchet).

## Methodology

`scripts/bench_race_necessity.exs` drives that exact race with real Signal
Protocol crypto — an actual X3DH session, real `SessionCipher.encrypt`/
`decrypt`, real ciphertext, not a synthetic counter — through both a guarded
(`SessionCustodian`) and an unguarded path, so the same run checks both the
problem and the fix. Corruption detection is independent of Amarula's own
bookkeeping: a synthetic counterpart tracks its own session state entirely
outside the race and, each round, tries to decrypt what "Us" actually emitted
with its real, untouched chain state. A lost update shows up as a genuine MAC
verification failure — the Double Ratchet math is the referee, not an
assertion about which internal field should have changed.

`test/protocol/signal/session_race_test.exs` covers the same underlying
non-atomicity as a lighter unit test — a synthetic counter instead of real
crypto, no guarded condition. Still in the suite, still passing.

## Methodology and results

Five conditions, all against the real `SessionCustodian.encrypt/decrypt` (for
the guarded case) or the same underlying `SessionStore`/`SessionCipher` calls
directly (for the unguarded cases, mirroring what code looked like before the
custodian existed). 100 rounds unless noted; each round races one outbound
encrypt against one real inbound decrypt on the same session record.

| Condition | What it isolates | Result |
|---|---|---|
| **Z. Sequential, no lock** | Control: does the unguarded code path work at all, absent a race? | **100/100 correct** |
| **A. Unguarded, synchronized dispatch** | Worst case: both operations launched in lockstep | **0/100 correct** (100% failure) |
| **A2. Unguarded, random 0–10ms dispatch jitter** | Realistic case: dispatch timing not artificially forced | **23/100 correct** (~77% failure, mostly silent) |
| **B. Unguarded, forced overlap (5ms delay)** | Deterministic worst case, window forced wide open | **0/20 correct** (100% failure) |
| **C. Guarded, through `SessionCustodian`** | Does the actual fix hold, under any of the above timing? | **100/100 correct**, in every run, at every timing |

Condition Z rules out the concern that the harness itself was just broken —
the unguarded code path is fine in isolation; failure requires the race
specifically. Condition A2 is the most important correction made mid-exercise:
an earlier version of this benchmark launched both sides in near-perfect
lockstep, which overstated inevitability. With realistic, non-synchronized
timing the failure rate drops from a manufactured 100% to a measured ~75–80%
— still severe, but a real, honest number rather than a forced one. Condition
C is unaffected by any of this: the lock makes the timing question moot
rather than just less likely to bite.

**One further finding, found by accident and worth keeping**: the *visible
symptom* of the same race depends on the storage adapter. `Storage.File`
happened to fail most of these rounds loudly (`{:error, :enoent}`, from two
writers racing on the same temp filename) — but `Storage.DETS.put` is a bare
`:dets.insert/2` with no such collision, so the identical race would very
plausibly manifest there as **100% silent** corruption: no error anywhere,
just quietly wrong session state. (`session_race_test.exs` uses DETS for
exactly this reason — the File-adapter collision is a separate bug, not the
lost-update this benchmark isolates.) Condition A2's own breakdown shows both
failure modes occurring naturally even under `Storage.File` (9 loud, 68
silent) — so this isn't purely an
adapter-specific curiosity, it shows up without forcing it.

## What this does NOT prove — read before citing this doc

This is a narrow, targeted check, not a general concurrency audit:

- **Only the exact 1:1 send-vs-receive race is tested.** Group sender-keys,
  PN↔LID migration, identity wipe, and multi-address contention were not
  exercised by this benchmark at all.
- **Only two concurrent writers.** Real bursty traffic could have more; this
  doesn't say anything about 3+-way contention (though the mechanism —
  unserialized read-modify-write — doesn't get safer with more writers).
- **The jitter window (0–10ms) is a guess, not a measurement of real
  production timing.** A different jitter distribution would show a different
  failure rate; the qualitative finding (severe, not negligible, mostly
  silent) is the load-bearing part, not the specific 77%.
- **Isolated from `Connection`.** The benchmark talks to `SessionCustodian`
  directly rather than through a real `Connection`, deliberately — a real
  `Connection` would incidentally serialize its own inbound decrypts anyway
  (it processes its mailbox inline, one frame at a time), which would confound
  whether the *custodian's* lock is doing the protecting or `Connection`'s own
  single-process nature is. See the flood-receive benchmark
  (`scripts/bench_flood_receive.exs`) and its own scope notes for that
  separate finding.

## Findings

The lock-free version's failure rate under realistic (not artificially
forced) concurrent timing measures at roughly 3-in-4, and most of those
failures are silent, undetectable corruption rather than a loud error a
caller could react to. Concurrent send + receive to the same contact is
routine, not rare, in normal usage, so this isn't a theoretical edge case —
it's the difference between 23% and 100% correctness on a race that happens
constantly.

The methodology itself needed a correction mid-exercise, and that correction
is part of the result, not a footnote: an early version of this benchmark
launched both sides in lockstep and overstated certainty (a manufactured
100% failure rate rather than the measured ~77%). That was caught by
directly testing whether the harness could produce a false result — a
sequential control run (no race at all) and a randomized-jitter run (no
forced synchrony) — rather than accepting the first clean-looking number.

## Reproducing this

```
mix run scripts/bench_race_necessity.exs   # this document's evidence
mix run scripts/bench_flood_receive.exs    # real-crypto throughput/backlog under load
mix run scripts/bench_registry_memory.exs  # at-rest process/memory topology cost
```

All three are real code against the compiled `amarula` app — no mocks, and
each script's own moduledoc states its scope limits directly, mirroring the
pattern in this document.
