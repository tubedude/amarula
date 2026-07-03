> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Large-group send: parallelize per-device encryption

> Status: **planned, not started.** A latency optimization, **not a bug fix** —
> Amarula does not have the Baileys "event loop stall" form of this (see below).
> Point-in-time design doc (`docs/plans/` convention; may drift from the code).

## Motivation

Upstream Baileys reports (#2654, #2631) that sending to a 200+ member group spikes
the Node event loop for up to ~2s, because `createParticipantNodes` runs a
**synchronous, serial** libsignal encrypt per participant device — hundreds of
sequential CPU-bound operations on a single thread.

Amarula does **not** have the severe form of this bug. The per-device encrypt
runs inside the per-recipient `ConversationSender` process, not the `Connection`
(websocket) process — so a slow group encrypt blocks only that one sender, and the
BEAM scheduler preempts it. It cannot freeze the connection, receiving, or other
recipients' sends. There is no event loop to stall.

What remains is a **latency** opportunity: within one group send, the encrypt loop
is still serial on one core. On a multi-core box, a 200-device group leaves cores
idle while one core does all the work. Parallelizing cuts the wall-clock latency of
a large-group send roughly by the core count.

## Where it is

`lib/amarula/protocol/messages/conversation_sender.ex`, the group encrypt step:

```elixir
defp encrypt(%{kind: :group, ...} = ctx) do
  ...
  participants =
    ctx.devices
    |> Enum.map(&encrypt_for_device(ctx, &1, skdm_plaintext))   # <-- serial
    |> Enum.reject(&is_nil/1)
  ...
end
```

The DM path (`encrypt(%{kind: :dm} ...)`) has the same `Enum.map` shape but a small
device count — not worth parallelizing.

## The constraint that makes this non-trivial

`encrypt_for_device/3` is **not pure**: each call runs a Signal session cipher that
**advances that device's ratchet** and **persists the updated session**
(`SessionStore.store_session`). So:

- Two encrypts for the **same device** must not run concurrently (they'd race the
  ratchet). Within one send each device appears once, so this is naturally safe —
  but the persistence layer must tolerate concurrent writes to *different* keys.
- The session store is the shared seam. Confirm `Amarula.Storage` (File/DETS) and
  the Signal `SessionStore` are safe under concurrent writes to distinct keys
  before fanning out. DETS in particular needs checking (single-writer semantics).

So this is **not** a drop-in `Enum.map → Task.async_stream`. The store concurrency
has to be verified or serialized first.

## Approach (sketch — confirm at implementation time)

1. **Verify the store seam** under concurrent distinct-key writes (File adapter:
   per-key files, likely fine; DETS: verify, may need a writer process or
   `:dets` access mode).
2. Replace the group `Enum.map` with `Task.async_stream/3`:
   - `max_concurrency: System.schedulers_online()` (CPU-bound — don't oversubscribe),
   - `ordered: false` (participant order in the stanza doesn't matter),
   - a timeout bound so one wedged device can't hang the whole send.
   Runs on the `ConversationSender` process's behalf (it can block on the stream;
   it's already the per-recipient serialization point).
3. Keep `encrypt_for_device` returning `nil` on a skippable device; reject after.
4. **Bench** with a synthetic large device set (100/200/500) — confirm wall-clock
   drops and no ratchet/session corruption (a round-trip decrypt test across the
   fanned-out sessions).

## Out of scope

- The DM path (small N).
- Any change to the `Connection` process or the send/ack lifecycle.
- libsignal itself (a Rust-NIF cipher would help raw throughput but is a separate,
  much larger effort; this plan is about using the cores we have).

## Acceptance

- A large-group send's encrypt wall-clock scales down with core count.
- No session/ratchet corruption (decrypt round-trip test green).
- `mix test` + `mix dialyzer` + `mix credo` green; no change to existing send
  semantics or event shapes.
