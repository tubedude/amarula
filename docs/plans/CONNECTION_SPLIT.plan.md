# Connection decomposition plan

> Status: **planned, not started.** Point-in-time design doc (the
> `docs/plans/` convention — may drift from the code). The living reference is
> `docs/INFRASTRUCTURE.md`.

## Motivation

`Amarula` (the public facade) is mostly `defdelegate … to: Connection`. That is
correct and stays: a facade should be a thin, stable seam. The delegation is not
the complexity.

The complexity is one layer down. `lib/amarula/connection.ex` is a single module
playing five roles at once:

- **~3884 lines**, **54** GenServer callbacks, **104** public funcs, **207**
  private funcs.

Roles currently fused into that one module:

1. **Client API** — `def send_text(pid, …)` → `GenServer.call` (what the facade
   delegates *to*).
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

Every extracted function takes the connection `state` struct (defined at
`connection.ex:69`) and returns either updated `state` or the exact
`{:reply, …, state}` / `{:noreply, state}` tuple the callback returns today.
`Connection`'s callbacks shrink to thin dispatchers. No new process, no new
message hop, no change to what crosses the process boundary.

Example — send_poll today (`connection.ex:792`):

```elixir
def handle_call({:send_poll, jid, name, options, opts}, from, state) do
  {message, secret} = MessageEncoder.poll(name, options, opts)
  shape = fn :ok, id -> {:ok, id, secret}; r, id -> default_send_reply(r, id) end
  deliver_async(state, jid, %{message: message}, from, shape)
end
```

after:

```elixir
def handle_call({:send_poll, jid, name, options, opts}, from, state),
  do: SendOps.poll(state, jid, name, options, opts, from)
```

`deliver_async`, `default_send_reply`, and the poll/media/resend/history builders
move into `SendOps`. Behaviour identical; the body is now testable without a live
socket.

## Module decomposition (mirror the facade's own grouping)

| New module | Absorbs (approx. line ranges) | Backs facade |
|---|---|---|
| `Connection.SendOps` | `deliver_async` (1333–1351), send_text/message/poll/media/resend/history bodies (744–828), `default_send_reply`, ack-on-send block (1081+) | `send_*`, `fetch_history` |
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

1. **`SendOps`** — first. Most self-contained (already folded as one section at
   `connection.ex:741`), maps 1:1 to the facade `send_*`, proves the pattern.
2. **`GroupOps`** — small, isolated, three callbacks.
3. **`PreKeyOps`** — internal-only, no event-shape risk.
4. **`Pairing`** — self-contained handshake/QR slice.
5. **`Notifications`** — larger; depends on the event-emit helpers staying put.
6. **`Receive`** — last and most careful; touches the decrypt/cipher path.
7. **`AppStateOps`** — can land any time after 1; orthogonal.

## Guardrails

- **Facade is frozen.** Not one byte of `lib/amarula.ex` changes. If a slice
  tempts a facade change, the slice is wrong — stop.
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
