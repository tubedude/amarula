# Plan: fix #7 — sender crash leaves parked sends hanging to :ack_timeout

## The bug

A send's pipe runs inside the per-recipient `ConversationSender`. The consumer's
`from` is parked in **Connection** under `msg_id` in `pending_acks`
(`%{msg_id => {from, on_ack, timer}}`).

The sender reports its result back to Connection explicitly:
- relay ok  → `{:send_relayed, msg_id}` (keep parked, await server `<ack>`)
- pipe error → `{:send_failed, msg_id, reason}` (reply caller now)

But a **crash** (raised exception in the pipe — Signal error, USync blowup, bad
bundle, etc.) kills the sender *before* it can `send(state.cm, ...)`. Connection
never learns. The parked `from` then resolves only via the 30 s `:ack_timeout`,
so the consumer:
- waits the full 30 s, and
- gets `{:error, :ack_timeout}` — **wrong**: nothing was ever relayed; it crashed.

Ack-on-send sharpened this: pre-ack the `from` rode inside the dying `msg`, so the
caller got a fast `:DOWN`/exit. Now the failure is silent, slow, and mislabeled.

`ConversationSender` is `restart: :temporary` — the supervisor will NOT restart it;
the next `deliver` respawns a fresh one. So Connection is the only place that can
notice the death and unblock callers.

## The wrinkle

One sender serves one **recipient**, but may hold **multiple in-flight/queued
`msg_id`s** (several sends to the same number, serialized on that one process).
`pending_acks` is keyed by `msg_id` only — it has no link to the sender pid or
recipient. On `:DOWN` we get `{pid, reason}` and must answer *every* parked
`msg_id` that belonged to that sender. We need pid↔msg_id tracking we don't have.

## Design

Connection monitors each sender and, on `:DOWN`, fails all that sender's parked
sends with `{:error, {:sender_crashed, reason}}`.

### State

Add to `pending_acks` entries the owning recipient (cheapest correlation key,
since `deliver_async` already computes `jid`), and track a monitor per live
sender:

```
pending_acks:    %{msg_id => {from, on_ack, timer, recipient_jid}}   # +recipient
sender_monitors: %{recipient_jid => monitor_ref}                     # NEW
```

Keyed by `recipient_jid` (not pid) because that is the sender's stable identity —
the Registry key — and `deliver_async` already has it. One monitor per recipient,
established the first time we park a send for a recipient with no live monitor.

### Where the monitor is set

`deliver` does find-or-start of the sender and returns nothing useful today
(`:ok`). Two options:

- **A. Monitor from `deliver_async` in Connection.** `ConversationSender.deliver`
  returns the pid; Connection `Process.monitor(pid)` if it has no monitor for that
  recipient yet. Clean: monitoring lives with the parker.
- B. Sender links/reports its own pid. More indirection; rejected.

Pick **A**. Change `ConversationSender.deliver/2` to return `{:ok, pid}` (it
already resolves the pid internally — just return it).

### deliver_async changes

```elixir
{:ok, sender} = ConversationSender.deliver(opts, msg)
state = ensure_sender_monitor(state, jid, sender)
{:noreply, park_ack(state, msg_id, from, shape, jid)}
```

`ensure_sender_monitor`: if `sender_monitors` has no ref for `jid`, `Process.monitor(sender)`
and store `{jid => ref}`. (Reuse across that recipient's many sends.)

`park_ack` now also stores `recipient_jid` in the entry.

### The :DOWN handler

```elixir
def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
  case pop_monitor(state, ref) do
    {nil, state} -> {:noreply, state}            # not a sender we track
    {jid, state} -> {:noreply, fail_recipient_sends(state, jid, reason)}
  end
end
```

`fail_recipient_sends(state, jid, reason)`:
- find every `pending_acks` entry whose `recipient_jid == jid`
- for each: cancel its timer, `GenServer.reply(from, {:error, {:sender_crashed, reason}})`,
  drop it
- drop the `sender_monitors[jid]` entry

`reason == :normal` (idle-timeout stop) must NOT fail anything — by then the
sender has no in-flight sends (it only stops on idle with an empty mailbox), but
guard anyway: on `:normal`, just drop the monitor entry, reply nothing.

### resolve_ack / normal completion cleanup

When a send completes normally (ack, pipe-failure, or ack-timeout), `resolve_ack`
drops the `pending_acks` entry. The `sender_monitors` entry should be cleaned up
when a recipient has **no more** parked sends, else we leak monitor refs (and hold
a monitor on a since-respawned sender). Two sub-options:

- **A. Demonitor when the last entry for a recipient is resolved.** After
  `resolve_ack` drops an entry, if no remaining `pending_acks` entry has that
  `recipient_jid`, `Process.demonitor(ref, [:flush])` and drop `sender_monitors[jid]`.
- B. Leave the monitor; reconcile lazily. Leaks; rejected.

Pick **A**. Small helper `maybe_drop_monitor(state, jid)`.

Note the idle-timeout interplay: a sender with no parked sends may keep running
(it idles 5 min before stopping). That's fine — we demonitor as soon as its last
send resolves; the eventual `:DOWN :normal` then finds no monitor and is a no-op.
If a *new* send arrives for that recipient before idle-stop, `deliver` reuses the
live sender and `ensure_sender_monitor` re-establishes a monitor. Correct.

## Edge cases / correctness

1. **Crash with several parked msg_ids** → all failed together. ✓ (recipient key)
2. **Crash race vs a just-arrived `<ack>`** → whichever message Connection
   processes first wins; the other finds the entry already gone (resolve_ack /
   fail_recipient_sends both no-op on missing). ✓
3. **`{:send_failed}` already replied, then `:DOWN`** → entry gone; DOWN finds no
   matching pending_acks for jid, drops monitor. ✓ (sender can crash right after
   reporting a failure for one msg while another is queued — the queued one is
   correctly failed by DOWN.)
4. **Fire-and-forget (from == nil)** → never parked, never monitored. A crash on a
   pure retry resend is silent, as intended. ✓
5. **Idle-stop `:normal`** → no in-flight sends; guarded to reply nothing. ✓
6. **ack_timeout fires after crash already failed it** → `Map.pop` miss → no-op. ✓

## Files

- `lib/amarula/protocol/messages/conversation_sender.ex`
  - `deliver/2`: return `{:ok, pid}` (it already has the pid).
- `lib/amarula/connection.ex`
  - state: add `sender_monitors: %{}`; widen `pending_acks` value to include
    `recipient_jid`.
  - `deliver_async`: capture pid, `ensure_sender_monitor`, pass jid to `park_ack`.
  - `park_ack`: store recipient_jid.
  - `resolve_ack`: after dropping, `maybe_drop_monitor`.
  - new `handle_info({:DOWN, ...})`, `ensure_sender_monitor`, `pop_monitor`,
    `fail_recipient_sends`, `maybe_drop_monitor`.

## Tests (send_flow_test)

- **sender crash fails the parked caller fast + correctly**: stub a pipe step to
  raise; assert the caller gets `{:error, {:sender_crashed, _}}` quickly (NOT after
  ack_timeout, NOT `:ack_timeout`).
- **crash fails ALL of that recipient's in-flight sends** (two sends to one jid,
  crash → both get `:sender_crashed`).
- **crash of recipient A does NOT touch recipient B's parked send**.
- **normal completion demonitors** (no leak): after an ack resolves the last send,
  killing the (now-unmonitored) idle sender does not reply anything / crash
  Connection. Hard to observe directly — assert via no stray message to the test
  caller + Connection still alive.
- **idle `:normal` DOWN is a no-op** (no parked sends).

## Out of scope

- Auto-resend on crash. We report the failure; the consumer decides. (Matches the
  ack-on-send decision to never auto-resend.)
- Monitoring senders for *liveness*/metrics — only failure-correlation here.
