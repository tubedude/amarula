> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Connection decomposition plan

> Status: **landed.** All eight extraction slices plus the facade collapse
> shipped. Point-in-time design doc (the `docs/plans/` convention); the living
> reference is `docs/INFRASTRUCTURE.md`. The design rationale below is kept as
> written; see **As landed** for where the result differs from the original plan.

## As landed

Eight focused modules now live under `lib/amarula/connection/`, each backed by a
direct unit test (all at 100% line coverage). The bodies of `Connection`'s
callbacks moved into them; `Connection` stays the process and the dispatcher.

| Module | Holds |
|---|---|
| `SendOps` | send builders (`text`/`message`/`poll`/`media`/`request_resend`/`fetch_history`) + `default_send_reply` → `{target, payload, shape}` |
| `GroupOps` | `metadata`/`list` IQ + reply-transform builders |
| `PreKeyOps` | count-query node, server-count parse, upload-target/needed decisions |
| `Pairing` | pair-device ack node, QR-ref extraction, sign-reply node, post-pairing creds merge |
| `Notifications` | `account_sync`/`devices`/`picture` parsers |
| `Receive` | `<ack>` outcome + retry-receipt target parsing |
| `AppStateOps` | sync-key extraction + chat/contact change partitioning |
| `AckLifecycle` | the shared park/resolve/monitor seam (a state module) |

**Facade collapse done, signatures frozen.** `lib/amarula.ex` now issues
`GenServer.call(conn, {…})` directly instead of `defdelegate`-ing. Every public
function's signature, arity, defaults, and `@spec` are byte-identical (verified by
diff) — only bodies changed, so the whole suite passed unchanged. The
message-building helpers (contact/contacts/location/reaction/edit/revoke) inline
their `MessageEncoder` construction via a private `send_built/3`;
`request_pairing_code` inlines its digit-strip.

### Where this differs from the original plan

- **The `Connection` client wrappers were kept, not deleted.** The plan called
  them dead boilerplate (its "role 1"). They are not: they are a real per-process
  client API (a leaf API — consumers/tests/examples call them, nothing internal
  calls them onward, which is the normal state of a public capability, not
  evidence of dead code). The facade simply no longer *routes through* them.
- **`AckLifecycle` is the shared ack seam** (plan slice 8), separated from
  `SendOps` exactly as the seam discussion concluded — used by the send path, the
  receive `<ack>` handler, and the `:DOWN`/`:ack_timeout` handlers.
- **Each slice extracted the *pure* body only**; anything bound to the live
  socket, cipher, IQ correlation, or the Storage seam stayed on `Connection`
  (`deliver_async`, `send_waiter_iq`, `send_tracked_iq`, the login flow). Several
  slices are thinner than the table below implied because their parsing already
  lived in dedicated modules (`Receipt.parse`, `Presence.parse_update`,
  `GroupNotification.parse`, `MessageDecryptor`).

The dialyzer warnings present after the work (`login.ex`, `retry_cache/step.ex`)
predate it and are untouched by these modules.

## Motivation

`Amarula` (the public facade) is mostly `defdelegate … to: Connection`. The facade
stays — a thin, stable seam is correct — but the `defdelegate` goes. Today a call
takes three hops: facade `defdelegate` → a client wrapper on `Connection`
(`def send_text(pid, …), do: GenServer.call(...)`) → the `handle_call` body. The
middle wrapper is pure boilerplate. The facade will instead `GenServer.call` the
process directly (signatures unchanged), and the client wrappers — the plan's
"role 1" below — are deleted.

The deeper complexity is one layer down. `lib/amarula/connection.ex` is a single
module playing five roles at once:

- **~3884 lines**, **54** GenServer callbacks, **104** public funcs, **207**
  private funcs.

Roles currently fused into that one module:

1. **Client API** — `def send_text(pid, …)` → `GenServer.call` (the wrappers the
   facade delegates *to*). The facade now calls the process directly and no longer
   routes through these; the `handle_call` clauses stay on `Connection`, their
   bodies move out. (As landed, the wrappers were **kept**, not deleted — they're a
   real per-process API; see **As landed › Where this differs**.)
2. **GenServer process** — `handle_call` / `handle_info` / `handle_cast`.
3. **Send orchestration** — `deliver_async`, poll/media/resend/history builders.
4. **Receive / dispatch** — decode → `dispatch_node` → `handle_*`, notification
   handling, app-state sync.
5. **Protocol plumbing** — IQ correlation, pre-key upload, creds persistence.

## The one real constraint, and the one it is *not*

`Connection` is the sole owner of the websocket + Noise cipher + IQ state. Code
that touches live socket/cipher state **must execute inside that process** —
moving it to another process would reintroduce the double-hop the architecture
deliberately removed (the old relay `Socket` GenServer was merged in on purpose;
see `docs/INFRASTRUCTURE.md`).

But: **"runs in one process" ≠ "lives in one module."** The GenServer mailbox
(`handle_*`) must stay, but the *bodies* are almost all pure decision/building
logic over the `state` struct. They can move into focused modules that
`Connection` *calls*, while still executing in the connection process.

This is already the codebase's own pattern — `Router` (pure routing table), `IQ`
(pure correlation state), `Login` (pure step builders) were extracted exactly
this way. This plan finishes what they started.

## The seam: `state` in, `{result, state}` out

Two things move, in opposite directions:

- **Up, into the facade:** the `GenServer.call`. The `defdelegate` and the client
  wrapper on `Connection` are replaced by a direct call from `Amarula`. The
  message tuple (`{:send_poll, …}`) becomes the facade's business; signatures and
  return shapes are unchanged.
- **Out, into a focused module:** the *body* of each callback. Each extracted
  function takes the connection `state` struct (defined at `connection.ex:69`) and
  returns the exact `{:reply, …, state}` / `{:noreply, state}` tuple the callback
  returns today.

The `handle_*` callbacks **stay on `Connection`** — that is the GenServer's
mailbox, and `Connection` remains the process that owns the socket/cipher. The
callbacks shrink to thin one-line dispatchers into the new modules. No new
process, no new message hop, no change to what crosses the process boundary; the
extracted modules are plain (non-process) modules called in-process.

Example — send_poll today (`connection.ex:792`):

```elixir
# lib/amarula.ex — facade, before:
defdelegate send_poll(conn, jid, name, options, opts), to: Connection

# connection.ex — client wrapper (deleted) + callback body (moves):
def send_poll(pid, jid, name, options, opts),
  do: GenServer.call(pid, {:send_poll, jid, name, options, opts})

def handle_call({:send_poll, jid, name, options, opts}, from, state) do
  {message, secret} = MessageEncoder.poll(name, options, opts)
  shape = fn :ok, id -> {:ok, id, secret}; r, id -> default_send_reply(r, id) end
  deliver_async(state, jid, %{message: message}, from, shape)
end
```

after:

```elixir
# lib/amarula.ex — facade calls the process directly, signature frozen:
def send_poll(conn, jid, name, options, opts),
  do: GenServer.call(conn, {:send_poll, jid, name, options, opts}, @send_call_timeout)

# connection.ex — the wrapper is gone; the callback stays here as a dispatcher:
def handle_call({:send_poll, jid, name, options, opts}, from, state),
  do: SendOps.poll(state, jid, name, options, opts, from)
```

`deliver_async`, `default_send_reply`, and the poll/media/resend/history builders
move into `SendOps` (a new internal module, `Amarula.Connection.SendOps`, that
organizes the send-callback bodies — a plain module, no socket). Behaviour
identical; the body is now testable without a live socket.

## Module decomposition (mirror the facade's own grouping)

> This is the **as-planned** carve (intended line ranges). For the modules that
> actually shipped and what each ended up holding, see **As landed** above — some
> are thinner because their parsing already lived in dedicated modules.

| New module | Absorbs (approx. line ranges) | Backs facade |
|---|---|---|
| `Connection.SendOps` | send_text/message/poll/media/resend/history bodies (744–828), `default_send_reply`, payload builders, the `deliver_async` *entry* | `send_*`, `fetch_history` |
| `Connection.AckLifecycle` | `park_ack`/`resolve_ack` (1401–1478), `ensure_sender_monitor`/`maybe_drop_monitor`, `pending_acks` state, `<ack>` resolution + `:DOWN`/timeout handlers | (internal, **shared**) |
| `Connection.Receive` | `decode_and_emit_frame` (1528), `process_server_node`/`dispatch_node` (1607–1664), `handle_message`, `handle_receipt`/`handle_presence`/`handle_message_ack` (1693–1751) | `:messages_upsert`, `:receipt_update`, `:presence_update` |
| `Connection.Notifications` | `handle_notification` + `dispatch_notification/*` (1851–1987), `handle_encrypt_notification` (2075) | `:group_update`, `:contacts_update`, `:blocklist_update` |
| `Connection.AppStateOps` | app-state sync block (3369+) | chats/contacts updates |
| `Connection.PreKeyOps` | pre-key upload block (3710+), `do_prekey_topup` | (internal) |
| `Connection.GroupOps` | `group_metadata` / `list_groups` / `group_op` bodies (659–697) | `Amarula.Group` |
| `Connection.Pairing` | `handle_pair_device` (2283) / `handle_pair_success` (2367), `emit_next_qr` (2334) | `:pairing_*` events |

Boundaries to confirm against the code at implementation time — the table is the
intended carve, not a guarantee of exact line numbers (the file will shift as
slices land).

## Ordering — incremental, tests green between each

One slice per commit. Run the full suite (`mix test`) **and** `mix dialyzer` /
`mix credo` after each; do not batch slices.

Each slice does three things together: (a) move the callback bodies into the new
module, (b) delete the now-dead client wrappers on `Connection`, (c) swap the
corresponding `lib/amarula.ex` `defdelegate`s for direct `GenServer.call`s. A
slice is only "green" when all three land and the contract is unchanged. Slices
backing events only (`Receive`, `Notifications`, `AppStateOps`, `PreKeyOps`) have
no facade funcs and skip (c).

1. **`SendOps`** — first. Most self-contained (already folded as one section at
   `connection.ex:741`), maps 1:1 to the facade `send_*`, proves the pattern.
2. **`GroupOps`** — small, isolated, three callbacks.
3. **`PreKeyOps`** — internal-only, no event-shape risk.
4. **`Pairing`** — self-contained handshake/QR slice.
5. **`Notifications`** — larger; depends on the event-emit helpers staying put.
6. **`Receive`** — last and most careful; touches the decrypt/cipher path.
7. **`AppStateOps`** — can land any time after 1; orthogonal.
8. **`AckLifecycle`** — the `park_ack`/`resolve_ack`/monitor seam. **Shared** by the
   send path (`SendOps`), the receive `<ack>` handler, and notification resends, so
   it is its own module, not part of `SendOps`. Land after `SendOps` and `Receive`
   so all its callers exist; until then it stays on `Connection` and `SendOps`
   calls it in-module.

## Guardrails

- **Facade *contract* is frozen — its bodies are not.** Every public function in
  `lib/amarula.ex` keeps its exact signature, arity, defaults, and return shape.
  The only permitted change is mechanical: `defdelegate … to: Connection` becomes
  a direct `GenServer.call(conn, {…})` (`conn` is already the call target — a pid
  or via-tuple; `via/1` takes a *profile*, not a conn, so it is not wrapped here).
  No new public function, no changed argument, no changed return. If a slice tempts
  anything beyond that swap, the slice is wrong — stop. *(As landed: held — the
  public function set and every `@spec` are byte-identical, verified by diff.)*
- **Event shapes are frozen.** `{:amarula, type, data}` payloads are the
  consumer contract (`Amarula` `t:event/0`). Extraction must not alter them.
- **No new process / no new message hop.** Pure-ish modules called in-process
  only. Anything needing live socket/cipher state stays reachable via `state`.
- **`emit_event` / `emit_connection_update`** (1314/1296) stay on `Connection`
  (they read `state.parent_pid`); extracted modules return data for `Connection`
  to emit, or are passed an emit closure — pick one convention and keep it.
- **State struct is the only coupling.** If a slice needs a private field, expose
  it through a named accessor rather than reaching in, to keep the seam legible.
- **Per-slice test add.** Each new module gets a direct unit test exercising its
  pure logic without a socket — the payoff that justifies the move.

## Out of scope

- No behavioural change, no new features (Tier-1 message types from
  `docs/PROTO_COVERAGE.md` are a separate effort).
- No change to the supervision tree, registry, or `ConversationSender`.
- No rename of `Connection` itself — it remains the process and the dispatcher.
