# SessionCustodian Concurrency Benchmarks

`Amarula.Protocol.Signal.SessionCustodian` puts a process, a registry, and a locking discipline in front of every Signal session record. That is a non-trivial amount of complexity. This document benchmarks session correctness with that per-record lock removed, detailing the methodology, results, and the limits of the test.

**Headline result:** A lock-free version of this code loses roughly 3 in 4 concurrent send/receive rounds under realistic timing, with most failures occurring silently.

## The Problem

A 1:1 session's Double Ratchet state is updated via a `load → mutate → store` cycle. Two different processes mutate this state: `ConversationSender` (encrypting outbound) and `Connection` (decrypting inbound). Without serialization, a concurrent send and receive to the same contact can interleave, silently dropping one side's state advancement (forking the ratchet).

## Methodology & Results

The script `scripts/bench_race_necessity.exs` forces this exact race using real Signal Protocol crypto, testing both a guarded (`SessionCustodian`) and an unguarded path.

Corruption detection happens independently of Amarula's normal bookkeeping. A synthetic counterpart tracks its own session state entirely outside the race and attempts to decrypt what was actually emitted on the wire. A lost update surfaces as a genuine MAC verification failure, letting the math act as the referee.

*(`test/protocol/signal/session_race_test.exs` covers this same non-atomicity issue as a lighter unit test using a synthetic counter instead of real crypto.)*

We tested five conditions (100 rounds each unless noted), racing one outbound encrypt against one inbound decrypt on the same session record:

| Condition | What it isolates | Result |
|---|---|---|
| **Z. Sequential, no lock** | Control: verifies the unguarded code works absent a race. | **100/100 correct** |
| **A. Unguarded, synchronized dispatch** | Worst case: operations launched in perfect lockstep. | **0/100 correct** |
| **A2. Unguarded, random 0–10ms jitter** | Realistic case: non-synchronized timing. | **23/100 correct** (~77% failure, mostly silent) |
| **B. Unguarded, forced overlap (5ms delay)** | Deterministic worst case: window forced wide open. | **0/20 correct** |
| **C. Guarded, via `SessionCustodian`** | Validates the fix under any timing condition. | **100/100 correct** |

**Storage adapter impact:** the visible symptom of this race depends heavily on the storage adapter. `Storage.File` often fails loudly (`{:error, :enoent}`) because two writers collide on a temp filename. `Storage.DETS.put`, however, is a bare `:dets.insert/2` with no collision mechanism — under DETS, this race results in 100% silent corruption. Even with the File adapter in condition A2, both modes occurred (9 loud, 68 silent).

## Scope & Limitations

This is a targeted check, not a generalized concurrency audit. Keep the following in mind:

- **Scope.** Only the 1:1 send-vs-receive race is tested. Group sender-keys, identity wipes, and PN↔LID migrations were excluded.
- **Contention.** The test simulates exactly two concurrent writers. It does not measure 3+-way contention.
- **Timing.** The 0–10ms jitter is an estimate, not a production measurement. A different jitter profile would yield a different failure rate, but the qualitative finding (failures are severe and mostly silent) remains valid.
- **Isolation.** The benchmark deliberately bypasses `Connection` to hit `SessionCustodian` directly. A real `Connection` serializes its own inbound decrypts, which would make it hard to tell if the custodian's lock or the single-process mailbox was actually doing the work.

## Conclusion

The lock-free code fails roughly 75% of the time under realistic concurrent timing, usually causing undetectable corruption. Since concurrent sending and receiving is routine, this isn't an edge case. The per-record lock fixes a very real vulnerability.

The methodology itself needed a correction mid-exercise, and that correction is part of the result, not a footnote: an early version of this benchmark launched both sides in lockstep and overstated certainty (a manufactured 100% failure rate rather than the measured ~77%). That was caught by directly testing whether the harness could produce a false result — a sequential control run (no race at all) and a randomized-jitter run (no forced synchrony) — rather than accepting the first clean-looking number.

## Reproducing the Benchmarks

```
mix run scripts/bench_race_necessity.exs   # This document's evidence
mix run scripts/bench_flood_receive.exs    # Real-crypto throughput/backlog under load
mix run scripts/bench_registry_memory.exs  # At-rest process/memory topology cost
```

All three scripts execute real code against the compiled `amarula` app without using mocks.
