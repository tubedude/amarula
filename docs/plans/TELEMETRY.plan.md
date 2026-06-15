# TELEMETRY plan — `:telemetry` instrumentation for Amarula

Status: **plan only**. No instrumentation has been written. This document defines
*what* to emit, *where*, and *in what order of value*. Implementation is a
follow-up.

## Goal

Let an operator observe the health of a live WhatsApp connection without reading
logs: connection up/down, send success/failure and latency, message throughput,
decrypt failures, IQ round-trip latency, reconnect/backoff, prekey ops, app-state
sync. We do this with the standard Elixir [`:telemetry`](https://hexdocs.pm/telemetry)
library so consumers can attach their own handlers and wire `telemetry_metrics` →
Prometheus/StatsD/etc. without us prescribing a metrics backend.

## How this relates to the existing event system (it is orthogonal)

Amarula already has a **consumer event** path, and telemetry is **not** that:

- `ConnectionManager.emit_event/3` → `emit_to_subscribers/3` push
  `{:connection_event, {type, data}}` to subscribed pids; `Socket` forwards them to
  the consumer's `parent_pid` as `{:whatsapp, type, data}` (`:messages_upsert`,
  `:connection_update`, `:receipt_update`, `:group_update`, `:chats_update`, …).
  These are **application semantics** — the payload carries real message content,
  JIDs, chats. A bot consumes them to *act* on messages.

- **Telemetry is operational metrics** — counts, durations, booleans, kinds. It is
  for *observing* the client, not for delivering data to it. It must carry **no
  PII / content / key material** (see Privacy rule). A consumer attaches a
  telemetry handler to feed a dashboard; it never replaces the `{:whatsapp, …}`
  callbacks.

The two live side by side: an emission point may emit *both* a consumer event
(with content) and a telemetry event (with only counts/booleans). They never share
a payload.

## Privacy rule (hard requirement for this project)

NEVER place any of the following in telemetry `measurements` or `metadata`:

- phone numbers, JIDs, LIDs, group ids, push names, any user identifier
- message text / media / any plaintext or ciphertext
- key material (prekeys, session bytes, noise keys, adv secrets)

Allowed in metadata: `:profile` (the connection profile atom/string — it is our
own label, not the peer), booleans (`recipient_present?`, `fromMe?`, `offline?`),
counts/integers, `kind`/type atoms (`:dm` | `:group`, enc type `:pkmsg` | `:msg` |
`:skmsg`), normalized `error_reason` atoms, and **hashes** if a stable opaque key
is ever genuinely needed (prefer a count). When in doubt, emit a boolean or a
count, never the value. Reviewers should reject any telemetry PR that puts a raw
`jid`/`from`/`to`/`message` into a payload.

## Conventions

- **Event name**: a list of atoms, prefixed `[:amarula, …]`.
- **Spans** (anything with a duration): use the `:telemetry.span/3` convention —
  `[:amarula, X, :start]`, `[:amarula, X, :stop]`, `[:amarula, X, :exception]`.
  `:start` carries `%{system_time}`, `:stop`/`:exception` carry
  `%{duration, monotonic_time}` plus our metadata. Use `:telemetry.span/3` where
  the work is a self-contained function call; emit start/stop manually where the
  span straddles a request/reply across GenServer messages (the IQ round-trip).
- **Single events** (discrete occurrences): one event with a `%{count: 1}` (or a
  meaningful measurement) and metadata.

---

## Event taxonomy

### Connection lifecycle

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:amarula, :connection, :update]` | every connection-state transition (`:connecting`, `:connected`, `:open`, `:disconnected`, `:closed`) | `%{count: 1}` | `%{profile, state, received_pending_notifications?}` |
| `[:amarula, :handshake, :start]` / `:stop` / `:exception` | Noise XX handshake — start at WS `:open` (ClientHello sent), stop at `complete_handshake` | start `%{system_time}`; stop `%{duration}` | `%{profile, result: :ok \| :error, error_reason}` |
| `[:amarula, :connection, :error]` | `handle_connection_error/2` | `%{count: 1}` | `%{profile, error_reason}` (normalized: `:timeout`, `:handshake_timeout`, `:server_response_timeout`, `{:stream_error, code}`, …) |
| `[:amarula, :reconnect, :scheduled]` | `schedule_reconnect/1` | `%{delay_ms, retry_count}` | `%{profile}` |
| `[:amarula, :stream_error, :restart]` | 515 restart (`handle_stream_error`, code 515) | `%{count: 1}` | `%{profile}` |
| `[:amarula, :stream_error, :received]` | non-515 stream error | `%{count: 1}` | `%{profile, code}` (code is a protocol int, not PII) |

`:open` (login fully complete) is the single most important operational signal —
it is the `:connection, :update` with `state: :open` emitted from `finish_login/1`.

### Login bootstrap

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:amarula, :login, :complete]` | `finish_login/1` (after passive `active` + digest + init queries; `:open` emitted) | `%{count: 1}` | `%{profile}` |
| `[:amarula, :pairing, :success]` | `handle_pair_success/1` after `verify_and_sign` succeeds | `%{count: 1}` | `%{profile, business?}` (no jid/lid/platform string) |

### Send pipeline (spans + outcomes)

The whole `deliver → run_send → do_send` pipe is a span; the inner IQ round-trips
(group metadata, USync, bundle fetch) are their own IQ spans (below).

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:amarula, :send, :start]` | top of `do_send/5` (after plugins, send decided) | `%{system_time}` | `%{profile, kind}` (`:dm` \| `:group`) |
| `[:amarula, :send, :stop]` | send pipe returned `:ok` (relay enqueued) | `%{duration, device_count, participant_count}` | `%{profile, kind, edit?}` |
| `[:amarula, :send, :exception]` | `{:error, {stage, reason}}` (a recoverable drop) | `%{duration}` | `%{profile, kind, stage, error_reason}` where `stage ∈ {:resolve_devices, :usync, :group_metadata, :fetch_bundles, :relay}` and `error_reason` normalized (`:timeout`, `:not_on_whatsapp`, `:no_encrypted_devices`, …) |
| `[:amarula, :send, :halted]` | a send plugin halted (`{:halt, reason}` in `run_send`) | `%{count: 1}` | `%{profile, reason}` (plugin-supplied atom, not content) |
| `[:amarula, :send, :not_on_whatsapp]` | `resolve_devices` DM yields no recipient device | `%{count: 1}` | `%{profile}` |

Note: `:not_on_whatsapp` is *also* surfaced as a `:send, :exception` with
`error_reason: :not_on_whatsapp`. Keep the dedicated single event too — operators
want to alert on "tried to message a number not on WA" independently of generic
send failure.

### Receive / decrypt

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:amarula, :message, :received]` | `handle_message/2`, per inbound `<message>` node successfully decrypted | `%{count, decrypted_count}` (count of `<enc>`/messages) | `%{profile, fromMe?, offline?, group?}` |
| `[:amarula, :decrypt, :stop]` | per `<enc>` decrypted OK (wrap `decrypt_enc`) | `%{duration}` | `%{profile, enc_type}` (`:pkmsg`\|`:msg`\|`:skmsg`\|`:plaintext`) |
| `[:amarula, :decrypt, :exception]` | per `<enc>` decrypt failure (`{:error, reason}` in `decrypt_enc`) | `%{duration}` | `%{profile, enc_type, error_reason}` (`:no_session`, `:no_content`, `{:unsupported_enc_type, …}`, `:missing_keys` for the dup case) |
| `[:amarula, :message, :duplicate]` | `missing_keys_error?` branch (already-decrypted dup → ack 487) | `%{count: 1}` | `%{profile, group?}` |
| `[:amarula, :message, :nack]` | nothing decrypted → retry + nack 500 | `%{count: 1}` | `%{profile}` |

Decrypt spans can be done with `:telemetry.span/3` around `decrypt_enc/8` (each is
a self-contained call), which gives free `:exception` on a raised libsignal error.

### Retry / receipts

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:amarula, :retry, :received]` | `handle_retry_receipt/2` (a peer asked us to re-encrypt) | `%{count: 1, retry_count}` | `%{profile, exhausted?, resent?, has_keys?}` |
| `[:amarula, :retry, :sent]` | `send_retry_request/2` (we ask sender to re-encrypt) | `%{count: 1}` | `%{profile}` |
| `[:amarula, :receipt, :update]` | `handle_receipt/2` parsed a delivery/read receipt | `%{count: 1}` | `%{profile, status}` (delivered/read/etc. — a status atom, not ids) |

### IQ round-trips (span across GenServer messages)

The IQ is registered in `handle_call({:query_iq, …})` / `send_tracked_iq` and
resolved in `handle_iq_response` or `handle_info({:iq_timeout, id})`. The span
straddles those, so store a `start_mono`/`start_metadata` alongside the pending-IQ
entry and emit `:stop` on resolve, `:exception` on timeout — emit manually, not via
`:telemetry.span/3`.

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:amarula, :iq, :start]` | IQ registered (`IQ.wait` / `IQ.track`) | `%{system_time}` | `%{profile, intent: :waiter \| :tracked, kind}` (`kind` for tracked = `:prekey_count`/`:digest`/`:app_state_sync`/…; for waiters a coarse label like `:query` — never the stanza) |
| `[:amarula, :iq, :stop]` | matching reply resolved (`IQ.resolve` effect fires) | `%{duration}` | `%{profile, intent, kind, result: :ok \| :error}` |
| `[:amarula, :iq, :exception]` | `iq_timeout` for that id (`IQ.timeout`) | `%{duration}` | `%{profile, intent, kind, error_reason: :timeout}` |

This single span gives latency + timeout rate for *every* round-trip: USync, bundle
fetch, group metadata, prekey count/upload, digest, app-state sync, dirty clean.

### Prekey ops

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:amarula, :prekey, :upload]` | `upload_pre_keys/3` | `%{count}` (number uploaded) | `%{profile, kind}` (`:prekey_upload` \| `:prekey_reupload`) |
| `[:amarula, :prekey, :count]` | `:prekey_count` reply parsed | `%{server_count, target}` | `%{profile, will_upload?}` |
| `[:amarula, :prekey, :consumed]` | `remove_used_pre_keys/2` (one-time prekey(s) deleted after pkmsg) | `%{count}` | `%{profile}` |

### App-state sync (span)

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:amarula, :app_state, :sync, :start]` | `resync_app_state/2` issues the request IQ | `%{collection_count}` | `%{profile}` |
| `[:amarula, :app_state, :sync, :stop]` | `:app_state_sync` tracked-IQ reply applied (`apply_app_state_reply`) | `%{duration, chats_changed, contacts_changed}` | `%{profile, result: :ok}` |
| `[:amarula, :app_state, :sync, :exception]` | `:app_state_sync` IQ error/timeout | `%{duration}` | `%{profile, error_reason}` |

### History sync

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:amarula, :history_sync, :downloaded]` | `:history_sync_result` applied (`handle_info({:history_sync_result, …})`) | `%{chats, contacts}` | `%{profile}` |
| `[:amarula, :history_sync, :failed]` | the Task in `download_history_sync/2` errors | `%{count: 1}` | `%{profile, error_reason}` |

---

## Emission-point map (module + function → event, span vs single)

`connection_manager.ex` = `lib/amarula/protocol/socket/connection_manager.ex`.
`conversation_sender.ex` = `lib/amarula/protocol/messages/conversation_sender.ex`.
Line numbers are as of this plan; re-confirm at implementation time.

| Event | File:fn | ~Line | Span? |
|---|---|---|---|
| `connection.update` | `connection_manager.ex` `emit_connection_update/2` & the `finish_login/1` `:open` emit | 842, 2875 | single |
| `handshake.start` | `connection_manager.ex` ws `:open` handler (ClientHello sent) | 481–491 | span start |
| `handshake.stop`/`.exception` | `connection_manager.ex` `complete_handshake/2` (stop) / handshake-frame error branch (exception) | 871, 575 | span stop |
| `connection.error` | `connection_manager.ex` `handle_connection_error/2` | 795 | single |
| `reconnect.scheduled` | `connection_manager.ex` `schedule_reconnect/1` | 827 | single |
| `stream_error.restart` / `.received` | `connection_manager.ex` `handle_stream_error/2` | 1441 | single |
| `login.complete` | `connection_manager.ex` `finish_login/1` | 2864 | single |
| `pairing.success` | `connection_manager.ex` `handle_pair_success/1` (after verify) | 1591 | single |
| `send.start` | `conversation_sender.ex` `do_send/5` top | 167 | span start |
| `send.stop` / `.exception` | `conversation_sender.ex` `do_send/5` `with`/`else` | 189–198 | span stop |
| `send.halted` | `conversation_sender.ex` `run_send/2` `{:halt, …}` | 142 | single |
| `send.not_on_whatsapp` | `conversation_sender.ex` `resolve_devices/1` (DM) | 238 | single |
| `message.received` | `connection_manager.ex` `handle_message/2` (success branch) | 2087 | single |
| `decrypt.stop`/`.exception` | `message_decryptor.ex` `decrypt_enc/8` (wrap the call site in `decrypt_node`'s reduce, ~line 64–69, or `:telemetry.span` inside `decrypt_enc`) | 64, 102–150 | span |
| `message.duplicate` | `connection_manager.ex` `handle_message/2` `missing_keys_error?` branch | 2118 | single |
| `message.nack` | `connection_manager.ex` `handle_message/2` final branch | 2125 | single |
| `retry.received` | `connection_manager.ex` `handle_retry_receipt/2` | 1076 | single |
| `retry.sent` | `connection_manager.ex` `send_retry_request/2` | 2282 | single |
| `receipt.update` | `connection_manager.ex` `handle_receipt/2` | 1062 | single |
| `iq.start` | `connection_manager.ex` `handle_call({:query_iq…})` + `send_tracked_iq/3` (where `IQ.wait`/`IQ.track` register) | 318, 2668 | span start (manual) |
| `iq.stop` | `connection_manager.ex` `handle_iq_response/2` → `IQ.resolve` effect | (resolve path) | span stop (manual) |
| `iq.exception` | `connection_manager.ex` `handle_info({:iq_timeout, id})` → `IQ.timeout` | 668 | span stop (manual) |
| `prekey.upload` | `connection_manager.ex` `upload_pre_keys/3` | 2904 | single |
| `prekey.count` | `connection_manager.ex` `handle_tracked_iq(:prekey_count, {:ok,…})` | 2769 | single |
| `prekey.consumed` | `connection_manager.ex` `remove_used_pre_keys/2` | 2147 | single |
| `app_state.sync.start` | `connection_manager.ex` `resync_app_state/2` | 2448 | span start |
| `app_state.sync.stop`/`.exception` | `connection_manager.ex` `handle_tracked_iq(:app_state_sync, …)` | 2759, 2764 | span stop |
| `history_sync.downloaded` | `connection_manager.ex` `handle_info({:history_sync_result,…})` | 469 | single |
| `history_sync.failed` | `connection_manager.ex` `download_history_sync/2` Task error | 2208 | single |

### IQ span — implementation note

The IQ correlation is already factored into the pure `Socket.IQ` module
(`track/wait/resolve/timeout` over a pending map). To time round-trips without
polluting that pure module, store the start monotonic time + the span metadata in
the **CM-side** entry (CM owns timers and the tracked-kind continuations), keyed by
the same IQ id, and emit `:start` when CM registers and `:stop`/`:exception` when CM
acts on the `IQ.resolve`/`IQ.timeout` effect. `Socket.IQ` stays pure.

---

## Recommended structure

### Dependency

Add to `amarula/mix.exs` deps (planning note only — do **not** add yet):

```elixir
{:telemetry, "~> 1.0"}
```

`:telemetry` is a tiny, dependency-free hex package (an ETS-backed handler
registry); it is already a transitive dep of many libs. For tests, optionally add
`{:telemetry_test, "~> 0.1", only: :test}` (or just attach a handler that forwards
to `self()` — see Testability).

### `Amarula.Telemetry` module

Create `lib/amarula/telemetry.ex` as the single documented home for the taxonomy
(telemetry's docs convention — one module that lists every event, its
measurements, and its metadata in `@moduledoc`). Suggested contents:

- `@moduledoc` table of all events (copy of the taxonomy above) — this is the
  contract consumers read.
- Thin helper(s) so call sites stay terse and the privacy rule is enforced in one
  place, e.g. `Amarula.Telemetry.span(name, meta, fun)` wrapping
  `:telemetry.span/3`, and `Amarula.Telemetry.emit(name, measurements, meta)`
  wrapping `:telemetry.execute/3` and always injecting `profile`. Keeping all
  emits behind this module makes "does any payload leak PII?" a one-file audit.
- A list constant `events/0` returning all event names — handy for
  `:telemetry.attach_many/4` and for `Telemetry.Metrics` wiring.

We do **not** add `:telemetry_metrics`/`:telemetry_poller` as deps — those are a
*consumer's* choice of backend. The plan: document in `Amarula.Telemetry` how a
consumer wires them, but keep Amarula backend-agnostic.

### How a consumer attaches handlers

```elixir
:telemetry.attach_many(
  "my-app-amarula",
  Amarula.Telemetry.events(),
  &MyApp.Telemetry.handle/4,
  nil
)
```

…or, with `telemetry_metrics` + a reporter:

```elixir
[
  Telemetry.Metrics.counter("amarula.message.received.count", tags: [:profile, :group?]),
  Telemetry.Metrics.summary("amarula.send.stop.duration", unit: {:native, :millisecond}, tags: [:profile, :kind]),
  Telemetry.Metrics.summary("amarula.iq.stop.duration", tags: [:profile, :kind]),
  Telemetry.Metrics.counter("amarula.send.exception.count", tags: [:profile, :stage, :error_reason]),
  Telemetry.Metrics.last_value("amarula.connection.update.count", tags: [:profile, :state])
]
```

### Testability

`:telemetry` is trivially testable — no `telemetry_test` dep strictly required:

```elixir
test "emits send.stop on a successful relay" do
  ref = make_ref()
  :telemetry.attach(
    {ref, :send_stop},
    [:amarula, :send, :stop],
    fn name, meas, meta, _ -> send(self(), {:telemetry, name, meas, meta}) end,
    nil
  )
  # ... drive a send through ConversationSender (existing send tests already do) ...
  assert_receive {:telemetry, [:amarula, :send, :stop], %{duration: _}, %{kind: :dm}}
  :telemetry.detach({ref, :send_stop})
end
```

A `test/support` helper that attaches/forwards/detaches around a block keeps this
boilerplate-free. The existing CM/sender tests (which already drive real send and
receive paths) are the natural place to assert the Phase-1 events.

---

## Phasing (by operational value)

### Phase 1 — must-have (do first)

The minimum to answer "is it up, is it sending, is it receiving, is it failing?":

1. `[:amarula, :connection, :update]` (esp. `state: :open` / `:disconnected` / `:closed`)
2. `[:amarula, :send, :start|:stop|:exception]` (success/failure + duration + stage)
3. `[:amarula, :send, :not_on_whatsapp]`
4. `[:amarula, :message, :received]`
5. `[:amarula, :decrypt, :exception]` (decrypt-failure rate is the early-warning of session breakage)
6. `[:amarula, :connection, :error]`

### Phase 2 — strong value

7. `[:amarula, :iq, :start|:stop|:exception]` (latency + timeout rate across every round-trip)
8. `[:amarula, :reconnect, :scheduled]` + `[:amarula, :stream_error, :restart|:received]`
9. `[:amarula, :app_state, :sync, :start|:stop|:exception]`
10. `[:amarula, :prekey, :upload|:count|:consumed]`
11. `[:amarula, :retry, :received|:sent]`
12. `[:amarula, :handshake, :start|:stop|:exception]`

### Phase 3 — nice-to-have

13. `[:amarula, :receipt, :update]`
14. `[:amarula, :message, :duplicate|:nack]`
15. `[:amarula, :decrypt, :stop]` (per-enc success durations — high volume, mostly redundant with `message.received`)
16. `[:amarula, :history_sync, :downloaded|:failed]`
17. `[:amarula, :login, :complete]`, `[:amarula, :pairing, :success]`

---

## Open considerations

- **`profile` in every payload**: a single connection has one profile; multi-account
  setups run a tree per profile. Putting `:profile` on every event is the one tag
  that lets a dashboard split by account — and it is *our* label, never the peer's,
  so it is privacy-safe.
- **IQ `kind` cardinality**: tracked kinds are a small fixed set (good as a tag).
  For blocking waiters, use a coarse `kind` (e.g. `:query`) — do not derive a tag
  from the stanza xmlns if it could be high-cardinality; a fixed small set keeps
  `telemetry_metrics` tag explosion in check.
- **Decrypt span volume**: `decrypt.stop` fires per `<enc>` and is high-volume;
  it is Phase 3 precisely so operators opt in. `decrypt.exception` is Phase 1
  because failures are rare and load-bearing.
- **Span across processes**: the send span lives entirely inside one
  `ConversationSender` call, so `:telemetry.span/3` works directly. The IQ span
  straddles GenServer messages and must be emitted manually (start on register,
  stop on resolve/timeout) — see the IQ note above.
