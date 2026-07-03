> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Send refactor: per-send GenServer + blocking `query_iq`

## Goal

Replace the continuation-passing send pipeline (a state machine smeared across
ConnectionManager via `pending_sends` + `kind`-tagged resume handlers) with a
**per-send process** that runs the send as a **branchless pipe of `ctx -> ctx`
steps**, blocking on IQ round-trips through ConnectionManager.

```elixir
def run(ctx) do
  ctx
  |> resolve_devices()   # cache, else blocking query_iq(usync)
  |> ensure_sessions()   # disk, else blocking query_iq(bundle fetch)
  |> encrypt()           # pure file I/O (ratchet advance)
  |> relay()             # blocking call: ConnectionManager frames + sends stanza
end
```

## Principles (agreed)

- **ConnectionManager is the sole websocket owner.** Anything touching the
  socket / noise state / message epoch goes through it. Calls that need a socket
  reply **block** until the socket replies — that's the contract. The websocket
  is the impure boundary; blocking on it is correct.
- **No `kind`.** ConnectionManager has no continuation logic, so nothing to tag.
  It just answers "send this IQ, give me the reply" and "send this stanza."
- **Login stays put this pass.** It's a non-concurrent bootstrap (no send GSs
  exist yet), so its existing inline/async IQ handling is untouched and isolated.
  `query_iq` + `id => from` is introduced only for the post-login send path.
- **Let it crash.** A send is a disposable process; on a step failure it crashes
  and the supervisor reaps it. Keeps the pipe branchless (no error arms).

## New `query_iq` mechanic in ConnectionManager

A blocking call, replied to only once the websocket answers:

```elixir
# public
def query_iq(conn, %Node{} = node, timeout \\ 20_000),
  do: GenServer.call(conn, {:query_iq, node}, timeout)

# handle_call — defer the reply, hold `from` under the IQ id
def handle_call({:query_iq, node}, from, state) do
  {state, id} = send_tracked_iq_with_id(state, node)   # frames, sends, epoch++
  {:noreply, %{state | pending_iqs: Map.put(state.pending_iqs, id, from)}}
end

# inbound iq result/error frame (handle_iq_response):
case Map.pop(state.pending_iqs, id) do
  {nil, _}     -> state                       # unknown id, ignore
  {from, rest} ->
    GenServer.reply(from, classify(node))     # {:ok, node} | {:error, node}
    %{state | pending_iqs: rest}
end
```

- `pending_iqs` shrinks from `id => {kind, timer}` to `id => from`.
- Timeout handled by the **caller's** `GenServer.call` timeout (the blocked send
  GS), so the `{:iq_timeout, id}` self-message + `handle_iq_timeout` go away for
  the send path. (Login path keeps its own if it still uses the old helper.)
- A `relay` stanza is fire-and-forget (no reply expected): a separate
  `relay_stanza` call that frames+sends and replies `:ok` immediately.

## New module: `Amarula.Protocol.Messages.ConversationSender` (per-recipient GenServer)

**Keyed per recipient (phone), not per message.** All sends to one recipient
funnel through one process and run **one at a time** — this serializes ratchet
advance for that recipient's session, so the session-write race is solved
structurally (no per-address lock needed). Different recipients run in parallel.

- Registered in a **Registry keyed by recipient jid**; spawned under a
  **DynamicSupervisor** owned by `Socket`. `send_text` does
  `lookup-or-start(jid)` then `cast({:send, msg})`.
- Process state: `%{conn, session_dir, creds, recipient_jid, idle_timer}`.
  Per-message work uses a transient `ctx` built per `{:send, msg}`.
- A `{:send, %{msg_id, text}}` cast runs the blocking pipe **to completion**
  before the next queued message is handled (mailbox = the queue). A blocking
  `query_iq` inside the pipe blocks this process only, so message N+1 to the same
  recipient waits for message N to finish (including its network round-trips).
  After the first send the device/session caches are warm, so follow-ups are fast.
- **Idle lifecycle:** after handling a message, (re)arm an idle timer; on idle
  timeout with an empty mailbox, stop `:normal`. Next message to that recipient
  respawns it.

### `ctx` and the pipe

`ctx` is built per message: `%{conn, session_dir, creds, msg_id, target_jid,
text, devices, participants}`. Most state is file-backed (sessions, device cache,
LID maps) so the sender reads/writes disk directly; only socket interactions go
through `conn`. The pipe runs inside `handle_cast({:send, msg}, state)`.

### Steps (each `ctx -> ctx`, blocking inside)

1. `resolve_devices(ctx)` — `DeviceListCache.get_many`; all-fresh → fill
   `ctx.devices`; any miss → `query_iq(usync)`, parse, store LID maps, cache,
   fill devices. (LID force-refresh stays a cast to `conn`.)
2. `ensure_sessions(ctx)` — find devices with no session file; if any →
   `query_iq(bundle fetch)` + `SessionInjector.inject` (file I/O).
3. `encrypt(ctx)` — per device, plain vs DSM plaintext, advance ratchet, collect
   `{jid, type, ciphertext}` into `ctx.participants` (pure file I/O).
4. `relay(ctx)` — `Relay.build_multi_device_stanza`; `conn` frames + sends it.

Failure in any step → the GS crashes (logged by supervisor). No `{:error}` arms
in the pipe.

## Lifecycle / supervision

- No DynamicSupervisor or Registry exists today (Socket starts children via bare
  `start_link`). Add both, **owned by Socket**, alongside ConnectionManager:
  - `Registry` (keys = recipient jids) for `lookup-or-start` + `:via` addressing.
  - `DynamicSupervisor` for the `ConversationSender` children (`:temporary` —
    a crashed send is not restarted; resending blindly risks double-send).
- `Socket.send_text(jid, text)`:
  1. `start_or_lookup(jid)` → ConversationSender pid (via Registry/DynamicSupervisor).
  2. `GenServer.cast(pid, {:send, %{msg_id, text}})`.
  3. return `{:ok, msg_id}` immediately (same external contract; send is async).
- Crash isolation: a failed send crashes only its recipient's process; the
  DynamicSupervisor reaps it; other recipients unaffected.

## What gets DELETED from ConnectionManager

- `pending_sends` field + type.
- `request_device_sync`/`resolve_devices`/`park_usync_devices`/
  `handle_usync_devices`/`devices_from_reply`/`cache_device_lists`.
- `ensure_sessions_then_relay`/`request_prekey_bundles`/`handle_fetch_bundle`.
- `encrypt_and_relay`/`encrypt_for_device`/`own_device?`/`device_sent_message`/
  `device_signal_address`/`load_device_session` → move to MessageSend.
- send-side branches in `handle_iq_response`/`handle_iq_timeout` (the
  `:usync_devices`/`:fetch_bundle` cases).
- `handle_call({:send_text, ...})` body shrinks to a `start_child`.

These move into `MessageSend` (the encrypt/relay/device helpers) or vanish (the
parking/resume machinery).

## What STAYS

- Login IQ path: `request_pre_key_count`, `handle_tracked_iq(:prekey_*/:digest)`,
  the `:assert_lid_sessions` cast handler. Untouched this pass.
- `send_tracked_iq_with_id` (reused by `query_iq` and login).
- `send_binary_node`, noise/socket ownership, `frame_sink` test seam.
- All file-backed stores (SessionStore, DeviceListCache, LidMappingFileStore,
  SessionInjector) — MessageSend calls them directly.

## Test impact

- `send_flow_test.exs`: today it drives ConnectionManager's `handle_call`
  `:send_text` + `{:inject_node, ...}`/`{:frame_out, ...}` seams. After: a send
  spawns a MessageSend GS that blocks on `query_iq` (a `GenServer.call` into
  ConnectionManager). The test must answer that call. Two options:
  - keep frame_sink/inject_node, but now the IQ reply must `GenServer.reply` the
    blocked send GS — so the test injects the reply frame into ConnectionManager
    as today, and ConnectionManager replies to the send GS. Should work with
    minimal change since `inject_node` → `handle_iq_response` → `GenServer.reply`.
  - Most existing assertions (USync IQ out, bundle IQ out, participants stanza,
    DSM, LID-priority, device-cache-skip) remain valid; the driving harness adapts.
- DeviceListCache / LidMappingFileStore unit tests: unchanged.

## Decisions (locked)

1. **DynamicSupervisor + Registry owner**: **Socket**, siblings of
   ConnectionManager. ConnectionManager stays a pure GenServer.
2. **Process keying**: **per recipient (phone)**, Registry-addressed. Messages to
   the same recipient serialize; different recipients run in parallel.
3. **Session-write race**: **solved structurally** by per-recipient
   serialization — no per-address lock needed.
4. **Idle lifecycle**: stay alive after draining, **stop on idle timeout**;
   respawn on next message.

## Still open (minor, confirm during build)

- **`relay`**: fire-and-forget call returning `:ok` (lean), vs awaiting an ack.
  Lean `:ok` now; receipt/ack handling is a separate concern.
- **Idle timeout value** (e.g. 30s).
