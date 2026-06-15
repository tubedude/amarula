# Infrastructure

The living reference for Amarula's process model — how a connection is supervised,
how sends flow, and how failures are contained. (Point-in-time *plans* live in
`docs/plans/`; they go stale by design. This document tracks current reality.)

## Process model

Each connection is an **independent supervision tree**, so many accounts run side
by side with full crash isolation. One tree per connection, started by
`ConnectionSupervisor`.

```
ConnectionSupervisor              (Supervisor, :one_for_one — per instance)
├── Registry                      (per-instance; keys = {instance_id, role}
│                                   and recipient_jid for senders)
├── TableOwner                    (owns the per-connection retry-cache ETS table)
├── Connection                    (GenServer — the one process per connection)
└── ConversationSender Supervisor (DynamicSupervisor) ── ConversationSender …
                                                          (one per recipient JID)
```

- **`Connection`** is the single per-connection process: it owns the WebSocket
  client, the Noise cipher, IQ correlation, login/handshake, credential
  resolve/persist (via the Storage seam), the consumer-facing send API, and
  consumer-event delivery to `parent_pid`. The old relay `Socket` GenServer was
  merged into it — one process per connection, no double hop.
- **`TableOwner`** creates the retry-cache ETS table at `init`, before any reader,
  so there is no lazy-create race (and no `try/rescue` guard). It owns ETS only
  *because the default `RetryCache` adapter is ETS*; a different adapter owns its
  own resources.
- **`ConversationSender`** — one GenServer per recipient JID; see below.
- **Storage** is a config concern (a scope on the `Conn`), not a process.

## The per-instance Registry — why it exists

The Registry maps **`recipient_jid → sender pid`**. It earns its keep for one
specific reason: the sender key space is **unbounded and user-controlled** — any
phone number you message becomes a key. That rules out static atom names (atoms are
never garbage-collected; an unbounded atom table eventually crashes the VM). A
Registry keyed by the JID *term* find-or-starts a sender per recipient and
auto-unregisters it on death, with no atom growth.

A registry is the right tool when the key space is unbounded/user-controlled. It is
*not* needed for bounded, operator-controlled identities — e.g. a future
*consumer → Connection* handle keyed by profile can be a plain named process, no
per-instance registry required.

`instance_id` is a `make_ref()` minted by `ConnectionSupervisor.start_instance/2`.
It namespaces the per-instance Registry + the sender DynamicSupervisor so siblings
address each other across child restarts. It is **not** a stable consumer handle
(it is ephemeral, re-minted per `start_instance`).

## ConversationSender lifecycle

One sender per recipient JID, `restart: :temporary`.

- **Identity.** The sender *is* its recipient: registered under
  `{registry, recipient_jid}`. At most one per recipient at a time.
- **Birth (lazy).** Started on the first `deliver/2` to a recipient with no live
  sender — find-or-start: `Registry.lookup` → else
  `DynamicSupervisor.start_child`. The `{:error, {:already_started, pid}}` branch
  makes it race-safe (in practice only `Connection` calls `deliver`, so starts for
  a given recipient are already serialized).
- **Registration.** Automatic via the `:via` name; the Registry monitors the pid
  and **auto-unregisters on death** — no stale keys to reap.
- **Life.** Serializes that recipient's sends (one pipe at a time → ordered Signal
  ratchet advance, no per-address lock); different recipients run in parallel.
  Holds **no durable state**: sessions/keys live in Storage, the consumer's `from`
  is parked in `Connection`. Cheap to lose, cheap to respawn.
- **Death (three ways).**
  1. *Idle* — after `@idle_timeout_ms` with an empty mailbox: `{:stop, :normal}`.
  2. *Crash* — a raise in the pipe (Signal error, USync blowup, bad bundle).
     `:temporary` ⇒ not restarted; the next `deliver` respawns a fresh one;
     in-flight + queued sends are lost.
  3. *Shutdown* — the connection's tree going down takes it too.
  All three auto-unregister the Registry key.
- **Rebirth.** The next `deliver/2` to that recipient starts a fresh sender; no
  carried state — it re-reads sessions from Storage.

## Profile registry — one connection per profile + restart-safe handle

Distinct from the per-instance Registry (intra-tree wiring) there is one
**app-level registry** mapping `profile -> Connection pid`, started by
`Amarula.Application` as `Amarula.ProfileRegistry` (a local `Registry`). It serves
two purposes:

1. **One connection per profile.** `make_socket` refuses to start a profile that is
   already live, returning `{:error, {:already_running, pid}}`. The registration in
   `Connection.init` is the atomic guard (the pre-check is a fast path) — two
   websockets on one set of credentials would corrupt the shared Signal ratchet, so
   this is a correctness invariant, not just dedup.
2. **Restart-safe handle.** `Amarula.whereis(profile)` resolves to the current pid;
   `Amarula.via(profile)` is a `:via` handle usable anywhere a `conn()` is accepted.
   On a Connection restart, `init` re-registers the same profile key, so the handle
   keeps resolving to the new pid (the raw pid from `connect/2` would go stale).

**Releasing a profile.** `disconnect/1` only closes the websocket — the supervised
tree stays up (and may reconnect), so the profile stays registered. To fully release
a profile (stop the whole tree, free the registration so it can run again — here or,
with a cluster registry, on another node) use `Amarula.stop/1` (by pid or profile).
The tree is found by a name derived from its `instance_id`, so `stop/1` works without
the consumer holding the supervisor pid.

**Key = `profile`.** Uniqueness is the consumer's responsibility — the library
trusts `profile <-> credentials` 1:1 and does not derive a fingerprint or validate
it. A duplicate start is an explicit error (never silently idempotent).

### Cluster readiness (the seam, not an opinion)

The registry is a config seam (`:registry` = `{module, name}` or bare `name`). The
library only uses the standard `Registry`/`:via` contract (`register/3`,
`lookup/2`, `{:via, mod, {name, key}}`), so **uniqueness reach = the registry's
reach**:

- default local `Registry` → one connection per profile **per node**;
- a `:via`-compatible cluster registry (`Horde.Registry`, a `:global`/`:pg` shim) →
  one **cluster-wide**, for free — "already registered" then means "running
  anywhere in the cluster."

So the consumer distributes credentials across the cluster and picks the registry;
Amarula enforces one-conn-per-profile against whatever reach that registry has. The
library never decides clustering. Caveats: `:global` is best-effort (a netsplit can
briefly allow two registrations, reconciled on heal); the robust production answer
is usually an external lease (DB row / Redis) the consumer's orchestrator holds per
profile — the seam composes with that rather than replacing it.

## Send flow & completion semantics

`Amarula.send_text/3` → `Connection` → the recipient's `ConversationSender`, which
runs a branchless `ctx -> ctx` pipe:

```
resolve_devices  (device cache, else USync)
  → ensure_sessions (session files, else prekey-bundle fetch)
    → encrypt       (per device; plain vs DSM; advance ratchet)
      → relay       (frame + send the <participants> stanza)
```

**Ack-on-send (Design 2).** A consumer `send_*` returns `{:ok, msg_id}` only when
the **server confirms** with `<ack class="message" id=msg_id>` — not when the frame
is merely written. Mechanics:

- `Connection` mints `msg_id`, parks the caller's `from` in `pending_acks`
  (keyed by `msg_id`, plus the recipient jid + an ack-timeout timer), and dispatches
  to the sender. It does **not** block — it is free for other sends immediately.
- The sender reports its pipe result back to `Connection`:
  `{:send_relayed, msg_id}` (frame written — keep parked, await the server ack) or
  `{:send_failed, msg_id, reason}` (pipe failed before any frame — reply now).
- On the inbound `<ack>`: a plain ack → the parked success shape (default
  `{:ok, msg_id}`); an ack carrying an `error` attr → `{:error, {:send_rejected,
  code}}`. The entry is dropped (a duplicate ack is then a harmless no-op).
- Never confirmed within the timeout (`@ack_timeout_ms`, default 30s, overridable
  via `config.ack_timeout_ms`) → `{:error, :ack_timeout}`.
- **Never auto-resends** on a phash ack — a plain ack (even with phash) is success;
  only an `error` attr is failure (auto-resend is the Baileys `handleBadAck` loop
  trap).

Because `Connection` parks the `from` and routes replies by id, sends to different
recipients **complete out-of-order** without blocking each other: a later send can
be acked (and its caller unblocked) before an earlier one.

## Failure containment

- **IQ timeout** (USync/bundle never answered) → the pipe step fails →
  `{:send_failed, …}` → the caller gets `{:error, reason}`.
- **Sender crash mid-pipe** (#7). The caller's `from` lives in `Connection`, not in
  the dying sender — so a crash would otherwise leave the caller hanging to the
  ack-timeout and then get a *mislabeled* `:ack_timeout` (nothing relayed). Instead,
  `Connection` **monitors each sender** (one monitor per recipient in
  `sender_monitors`, reused across its many in-flight sends) and on the sender's
  `:DOWN` fails **all** of that recipient's parked sends with
  `{:error, {:sender_crashed, reason}}` — promptly and correctly. A `:normal`
  idle-stop fails nothing. The monitor is dropped when a recipient's last parked
  send resolves (no leak). See `docs/plans/SENDER_CRASH_FIX.plan.md`.
- **Connection crash** → the whole instance tree restarts/reconnects as a unit.

## See also

- `Amarula.Connection` — moduledoc + the send/ack/`:DOWN` handlers.
- `Amarula.Protocol.Messages.ConversationSender` — moduledoc (lifecycle).
- `lib/amarula/protocol/messages/ARCHITECTURE.md` — message-handling internals.
- `docs/plans/` — point-in-time design plans (may be stale; this doc is current).
