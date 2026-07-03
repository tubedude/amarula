> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Plan: per-peer SessionWorker — close the ratchet fork (all-async)

Status: PROPOSED (planning only, no code yet). Target: 0.2.5.

## Problem (proven)

The 1:1 Signal session ratchet advance is a `load_session → cipher → store_session`
against shared Storage, with **no serialization** (`SessionStore` has no lock/CAS/
version). The **send** path runs this in a per-recipient `ConversationSender`; the
**receive** path runs it *inline in the Connection process* (`MessageDecryptor`'s
`pkmsg`/`msg` clauses). Two different processes touch the same bidirectional session
with nothing serializing them → a concurrent send + receive to the same peer
interleaves the load-modify-store and **forks the ratchet** (key reuse / undecryptable
session).

Reproduced: `test/protocol/signal/session_race_test.exs` — 50 concurrent RMWs land 1
(49 lost updates).

## Goal

One process per peer owns that peer's 1:1 session and serializes **both** encrypt and
decrypt for it. Single owner ⇒ no interleaving ⇒ no fork.

## Surgical boundary — what moves, what does NOT

**Moves into the worker (the only ratchet-touching code, both directions):**
- Send: `load → SessionCipher.encrypt → store` (already in `ConversationSender`).
- Receive: `load → SessionCipher.decrypt → store` — **only** the `pkmsg` and `msg`
  clauses of `MessageDecryptor.decrypt_enc` (the 1:1 session RMW).

**Stays exactly where it is (NOT in the worker):**
- `skmsg` (group sender-key) — a *different* store (`SenderKeyStore`/`GroupCipher`),
  not the 1:1 ratchet. Stays inline in Connection/MessageDecryptor.
- `plaintext` enc, SKDM side-effects, prekey-id collection, error handling.
- ALL post-decrypt handling stays in Connection: `remove_used_pre_keys`,
  `maybe_handle_app_state_key_share`, `run_recv_steps`, `build_msg`, telemetry,
  `:messages_upsert`, delivery/hist_sync/retry receipts.

So the worker owns *only* `load→cipher→store` for the 1:1 session. Everything else is
unchanged.

## Why all-async (the deadlock that forces it)

A **synchronous** "Connection calls worker to decrypt" DEADLOCKS: the worker, during a
send, calls `Connection.query_iq` (USync/prekey) and blocks on Connection; if
Connection is simultaneously blocked in `call(worker, :decrypt)`, they wait on each
other forever.

Therefore everything into the worker is a **cast**, the worker reports results back by
message, and Connection never blocks on the worker. This is pure OTP message-passing
(the worker's mailbox is the serialization point — not a mutex, not shared memory).

Cost accepted: Connection must **reassemble** a node's per-`<enc>` results from the
worker's reply before it can receipt/emit (the "assembly").

## Design

### SessionWorker (evolve ConversationSender)
- One per peer (key `{instance_id, peer_addr}` in `InstanceRegistry`, as today).
- Still holds **no ratchet state** — load→cipher→store against Storage every op
  (crash-safe; a cached ratchet would desync on a `:temporary` crash — see the
  write-through decision in INFRASTRUCTURE.md).
- Messages it handles:
  - `{:send, msg}` (cast) — existing send pipe, reports `{:send_failed,…}` on failure.
  - `{:decrypt, ref, enc_list, ctx}` (cast) — for each `pkmsg`/`msg` enc, do
    `load→decrypt→store`; reply to Connection with
    `{:decrypted, ref, results}` (cast back), where `results` preserves enc order and
    carries `{:ok, plaintext, pre_key_id} | {:error, reason}` per enc.

### Connection.handle_message (receive path)
Today: decrypt inline → post-process → receipt, all in one synchronous pass.

New:
1. Parse the node, split `<enc>` children into **1:1** (`pkmsg`/`msg`) and **non-1:1**
   (`skmsg`/`plaintext`).
2. Decrypt non-1:1 inline as today (group path unchanged).
3. For the 1:1 encs: `cast {:decrypt, ref, encs, ctx}` to the peer's worker, **park
   the node + the already-decrypted non-1:1 results under `ref`** in Connection state
   (a `pending_decrypts` map, mirroring `pending_acks`). Return `{:noreply}` — do NOT
   block.
4. On `{:decrypted, ref, results}` (handle_info): look up the parked node/context,
   **merge** the worker's 1:1 results with the inline non-1:1 results in original enc
   order, then run the EXISTING post-decrypt flow verbatim (prekey cleanup, app-state,
   recv steps, build_msg, events, receipts).

### Ordering
Today receive is fully ordered (Connection's mailbox, one node at a time). Async
decrypt makes node completion **per-peer ordered but cross-peer interleaved**. This is
acceptable (messages from different peers have no ordering relationship), and within a
peer the worker's mailbox preserves order. Must verify: receipts still fire once per
node; a node with mixed 1:1 + group encs assembles correctly.

## Risks / must-verify
1. **Deadlock** — eliminated by all-cast (no Connection→worker call, no worker→
   Connection call that the other is blocked on). Re-audit every worker→Connection
   call to confirm none is a `call` Connection could be blocked behind.
2. **Receipt correctness** — exactly one delivery receipt per node, after ALL its encs
   (1:1 + group) are assembled. The parked-node mechanism must not double-receipt or
   drop on a decrypt error.
3. **Retry/nack path** — a 1:1 decrypt failure currently triggers a retry receipt +
   nack. That decision now happens at assembly time, from the worker's `{:error,…}`.
4. **Worker crash mid-decrypt** — `:temporary`, so the parked node would never get its
   `{:decrypted}` reply. Need a monitor/timeout on `pending_decrypts` (mirror the
   `pending_acks` sender-monitor) so a crashed decrypt nacks the node instead of
   hanging it.
5. **Ordering tests** — `noise_protocol_test`, `pairing_test` touch receive; run full
   suite. Add a test: concurrent send + inbound to one peer no longer forks (the race
   test should pass against the real path, not just the primitive).
6. **History sync / offline batch** — these replay many nodes; confirm the parked-
   decrypt path handles a burst without unbounded `pending_decrypts` growth.

## Rollout
- Step 1 (done): prove the fork — `session_race_test.exs`.
- Step 2: SessionWorker `{:decrypt}` handler + reply (no Connection wiring yet; unit-test
  the worker decrypts correctly and serializes with encrypt).
- Step 3: Connection split/park/assemble; monitor+timeout for crashed decrypts.
- Step 4: integration test — concurrent send+receive to one peer, assert no fork via
  the real paths.
- Step 5: full suite, docs (INFRASTRUCTURE.md receive section + the worker moduledoc).

## Open decision
- Keep the name `ConversationSender` or rename to `SessionWorker`? It now owns both
  directions, so the name is stale — but renaming touches more files. Lean: rename,
  it's clarifying and 0.2.5 is already a refactor release.
