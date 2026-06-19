# Infrastructure

How a connection is built, supervised, and torn down; how messages flow out and
in; and how failures stay contained. This tracks current reality. Point-in-time
design plans live in `docs/plans/` and go stale by design — when they disagree
with this file, this file wins.

## Overview

A connection is one independent supervision tree. Many accounts can run side by
side, fully isolated: one account crashing never touches another.

```
Amarula.ConnectionsSupervisor          (library-owned DynamicSupervisor)
└── ConnectionSupervisor               (:one_for_one — one per connection)
    ├── Registry                       (per-instance; keys {instance_id, role}
    │                                    for siblings, recipient_jid for senders)
    ├── TableOwner                     (owns the per-connection retry-cache ETS)
    ├── Connection                     (GenServer — the one process per connection)
    └── Sender Supervisor              (DynamicSupervisor)
        └── ConversationSender …       (one per recipient JID, lazily started)
```

`Connection` is the heart: one process per connection that owns the WebSocket, the
Noise cipher, IQ correlation, login/handshake, credential persistence, the
consumer-facing API, and event delivery back to the consumer. Everything else in
the tree exists to support it.

`ConnectionSupervisor.start_instance/2` builds the tree under the library-owned
`Amarula.ConnectionsSupervisor` and returns `{:ok, sup_pid, connection_pid}`. The
connection pid is the consumer's handle — public API calls (`send_text`, etc.)
land on `Connection` directly, with no relay hop. Because the tree is supervised by
the library and not linked to the caller, a connection crash reaches the consumer
only as an event through `parent_pid`; it never delivers an exit signal that could
take the consumer down.

## The processes

### Connection

The single per-connection process and the consumer's endpoint. It owns:

- the WebSocket client and the Noise handshake state (read/write ciphers);
- IQ correlation (matching responses to in-flight requests);
- login, pairing, and the 515 restart;
- credential resolve/persist through the Storage seam;
- the consumer API (`send_*`, `group_*`, presence, reads, downloads);
- dispatch of inbound frames and delivery of events to `parent_pid`.

It is a large coordinator on purpose. The decision and domain logic live in their
own pure modules (`Router`, `IQ`, `Login`, the message and signal layers);
`Connection` wires them together and owns the side effects.

### TableOwner

Creates the per-connection retry-cache ETS table in `init`, before any reader
exists, so there is no lazy-create race and no `try/rescue` guard around table
access. It owns ETS only because the default `RetryCache` adapter happens to use
ETS — a different adapter would own its own resources.

### ConversationSender

One GenServer per recipient JID, started lazily, holding no durable state. Covered
in detail under [Sending](#sending).

### Storage

Not a process. Storage is a config concern — a scope carried on the `Conn` struct —
backed by a pluggable adapter (File or DETS). It holds creds, sessions, sender
keys, LID mappings, device lists, and app-state.

## The two registries

There are two distinct registries; keep them straight.

### Per-instance Registry — intra-tree wiring

Lives inside one connection's tree. It does two jobs:

1. **Names the siblings.** `Connection` and the sender supervisor register under
   `{instance_id, role}`, so siblings can find each other by role across restarts
   without global atom names.
2. **Maps `recipient_jid → sender pid`.** This is the load-bearing reason it
   exists. The recipient key space is unbounded and user-controlled — every phone
   number you message becomes a key. Static atom names can't work here: atoms are
   never garbage-collected, so an unbounded atom table would eventually crash the
   VM. A Registry keyed by the JID term find-or-starts a sender per recipient and
   auto-unregisters it on the sender's death, with no atom growth.

`instance_id` is a `make_ref()` minted per `start_instance/2`. It namespaces the
Registry and the sender supervisor so siblings address each other correctly. It is
ephemeral — re-minted on every start — so it is *not* a stable consumer handle.

### Profile registry — one connection per profile

An app-level `Registry` (`Amarula.ProfileRegistry`, started by
`Amarula.Application`) mapping `profile → Connection pid`. Two jobs:

1. **One connection per profile.** Starting a profile that is already live returns
   `{:error, {:already_running, pid}}`. The registration happens atomically in
   `Connection.init` (the pre-check is just a fast path). This is a correctness
   invariant, not mere deduplication: two WebSockets on one set of credentials
   would corrupt the shared Signal ratchet.
2. **Restart-safe handle.** `Amarula.whereis(profile)` resolves to the current pid
   and `Amarula.via(profile)` is a `:via` handle usable anywhere a `conn()` is
   accepted. On a Connection restart, `init` re-registers the same profile key, so
   the handle keeps resolving — where a raw pid from `connect/2` would go stale.

The key is the `profile`. Uniqueness is the consumer's responsibility: the library
trusts `profile ↔ credentials` to be 1:1 and does not fingerprint or validate it.

**Releasing a profile.** `disconnect/1` only closes the WebSocket; the tree stays
up and may reconnect, so the profile stays registered. To fully release it — stop
the whole tree and free the registration — use `Amarula.stop/1` (by pid or
profile). The tree is found by a name derived from its `instance_id`, so the
consumer doesn't need to hold the supervisor pid.

#### Cluster reach

The profile registry is a config seam: `:registry` is `{module, name}` or a bare
`name`. The library only uses the standard `Registry`/`:via` contract, so
**uniqueness reach equals the registry's reach**:

- the default local `Registry` → one connection per profile *per node*;
- a `:via`-compatible cluster registry (`Horde.Registry`, a `:global`/`:pg` shim) →
  one connection per profile *cluster-wide*, where "already registered" means
  "running anywhere in the cluster."

The consumer distributes credentials and picks the registry; Amarula enforces
one-per-profile against whatever reach that registry has. The library never decides
clustering. Note that `:global` is best-effort — a netsplit can briefly allow two
registrations, reconciled on heal — so a production setup usually pairs this with
an external lease (a DB row or Redis key) the orchestrator holds per profile. The
seam composes with that rather than replacing it.

## Sending

`Amarula.send_text/3` → `Connection` → the recipient's `ConversationSender`. The
sender runs a linear `ctx → ctx` pipe:

```
resolve_devices    (device cache, else USync)
  → ensure_sessions  (stored sessions, else prekey-bundle fetch)
    → encrypt        (per device; plain vs DSM; advances the ratchet)
      → relay        (build the frame, send the <participants> stanza)
```

### ConversationSender lifecycle

One sender per recipient JID, `restart: :temporary`.

- **Identity.** The sender *is* its recipient: registered under
  `{registry, recipient_jid}`, at most one per recipient at a time.
- **Birth.** Lazy. The first `deliver/2` to a recipient with no live sender does
  find-or-start: `Registry.lookup`, else `DynamicSupervisor.start_child`. The
  `{:error, {:already_started, pid}}` branch keeps it race-safe (in practice only
  `Connection` calls `deliver`, so starts for one recipient are already
  serialized).
- **Life.** It serializes that recipient's sends — one pipe at a time, so the
  Signal ratchet advances in order with no per-address lock. Different recipients
  run in parallel. It holds no durable state: sessions and keys live in Storage,
  and the consumer's `from` is parked in `Connection`. Cheap to lose, cheap to
  respawn.
- **Death.** Three ways, all of which auto-unregister the Registry key:
  1. *Idle* — empty mailbox past `@idle_timeout_ms` → `{:stop, :normal}`.
  2. *Crash* — a raise in the pipe (Signal error, USync failure, bad bundle).
     `:temporary` means no restart; in-flight and queued sends are lost.
  3. *Shutdown* — the tree going down takes it with it.
- **Rebirth.** The next `deliver/2` starts a fresh sender that re-reads sessions
  from Storage.

### Completion: ack-on-send

A `send_*` call returns `{:ok, msg_id}` only when the **server** confirms with
`<ack class="message" id=msg_id>` — not when the frame is merely written.

- `Connection` mints the `msg_id`, parks the caller's `from` in `pending_acks`
  (keyed by `msg_id`, with the recipient JID and an ack-timeout timer), and
  dispatches to the sender. It does not block — it is free for other sends
  immediately.
- The sender reports its pipe result back to `Connection`:
  `{:send_relayed, msg_id}` (frame written, keep the entry parked and await the
  server ack) or `{:send_failed, msg_id, reason}` (pipe failed before any frame,
  reply now).
- On the inbound `<ack>`: a plain ack resolves the parked success shape (default
  `{:ok, msg_id}`); an ack with an `error` attr resolves
  `{:error, {:send_rejected, code}}`. Either way the entry is dropped, so a
  duplicate ack is a harmless no-op.
- No confirmation within `@ack_timeout_ms` (default 30s, overridable via
  `config.ack_timeout_ms`) → `{:error, :ack_timeout}`.

Two subtleties worth stating, both about *not* over-reacting to acks:

- **Never auto-resend on a phash ack.** A plain ack is success even when it carries
  a phash; only an `error` attr is failure. Auto-resending on phash is the Baileys
  `handleBadAck` loop trap, and we avoid it.
- **Multiple acks for one id** (group / multi-device). A group stanza is a single
  `<message>` with one id, but the server may emit a phash ack ("not all devices
  yet") before the terminal one. We resolve on the *first* no-error ack and treat
  any later ack for that id as a no-op — the server has accepted the message; phash
  is about device propagation, not acceptance. An `error` ack arrives *instead of*
  a plain one, never after, so this can't mask a real failure.

Because `Connection` parks the `from` and routes replies by id, sends to different
recipients complete out of order without blocking each other — a later send can be
acked before an earlier one.

### Offline (sandbox) mode

With `offline: true` on the config, the connection has no socket and no peer. A
send must not run the real pipe — USync and bundle-fetch IQs would block forever
with nothing to answer them. So `deliver_async` short-circuits at the boundary: it
mints a `msg_id` and replies exactly as a confirmed send would (`{:ok, id}`, or
`{:ok, id, secret}` for a poll). Nothing is encrypted and no frame leaves the
process, so a consumer's bot logic runs unchanged against
`Amarula.Testing`. A fire-and-forget send (`from == nil`) simply does nothing.

## Receiving

An inbound frame is decrypted by the Noise layer, decoded into a binary `Node`, and
handed to `Connection.process_server_node/2`. Dispatch is split in two:

1. **`Router.route/1`** is a pure function: it maps a node to a handler tag (an
   atom like `:message`, `:notification`, `:receipt_ack`, `:iq_response`,
   `:message_ack`) based only on the node's tag, `type`/`xmlns` attrs, and
   first-child tag — never on connection state. The explicit catch-all is
   `:unhandled`, which `Connection` logs loudly. Keeping the table pure makes "which
   frames do we handle?" one readable list and testable without a live socket.
2. **`Connection` dispatches** on that tag to the matching handler, which performs
   the side effects.

For a `:message`, the handler decrypts via `MessageDecryptor`, builds each
decrypted payload into an `%Amarula.Msg{}` (a consumer struct — `type` + `content`,
never the raw proto), drops Signal sender-key plumbing (`type == :sender_key`,
which is group-session-key bookkeeping, not a user message), and emits the rest as
a `:messages_upsert` event to `parent_pid`. It then sends the delivery receipt the
server expects — and, for a message carrying a history-sync notification, an extra
`<receipt type="hist_sync">`, the signal the server waits for to mark the
companion's initial sync complete (without it the phone shows the device as
"Paused").

Receipts, notifications, presence, and acks dispatch to their own handlers and emit
their own events (`:receipt_update`, `:group_update`, …). Consumer events all reach
`parent_pid` as `{:whatsapp, type, data}`.

## Failure containment

- **IQ timeout** (a USync or bundle request never answered) → the pipe step fails →
  `{:send_failed, …}` → the caller gets `{:error, reason}`.
- **Sender crash mid-pipe.** The caller's `from` lives in `Connection`, not in the
  dying sender, so a crash would otherwise leave the caller hanging until the
  ack-timeout and then get a *mislabeled* `:ack_timeout` (nothing was relayed).
  Instead, `Connection` monitors each sender (one monitor per recipient, reused
  across that recipient's in-flight sends) and on a `:DOWN` fails **all** of that
  recipient's parked sends with `{:error, {:sender_crashed, reason}}` — promptly and
  correctly. A `:normal` idle-stop fails nothing. The monitor is dropped when the
  recipient's last parked send resolves, so it doesn't leak. See
  `docs/plans/SENDER_CRASH_FIX.plan.md`.
- **Connection crash** → the whole instance tree restarts and reconnects as a unit.
  Because the tree isn't linked to the consumer, this never propagates an exit
  signal to the caller.

## See also

- `Amarula.Connection` — moduledoc plus the send / ack / `:DOWN` handlers.
- `Amarula.Protocol.Socket.ConnectionSupervisor` — the tree and the role-name
  helpers.
- `Amarula.Protocol.Socket.Router` — the full inbound routing table.
- `Amarula.Protocol.Messages.ConversationSender` — moduledoc (lifecycle).
- `docs/plans/` — point-in-time design plans; may be stale. This doc is current.
