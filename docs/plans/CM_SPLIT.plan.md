> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Deep ConnectionManager split — plan

CM ≈2700 lines / ~190 funs. Safe pass done (Auth.DeviceIdentity extracted, pure).
The remaining bulk is three state-coupled clusters. This plans extracting them
without creating a god-module or breaking the live pairing/send path.

## CM state fields (the coupling)
websocket_client, conn, config, connection_state, retry_count/max_retries/
retry_delay/retry_timer, event_handlers, connection_timeout_timer, last_error,
auth_creds, handshake_state, noise_state, keep_alive_timer, last_recv_time,
message_counter/message_tag_prefix/message_epoch, waiting_for_server_response,
server_response_timeout_timer, qr_refs, qr_timer, pending_iqs.

## The three clusters

### 1. Node router (~11 dispatch arms + handlers) — `process_server_node/2`
Dispatches {tag,type,first_child,xmlns} → handle_message / handle_notification /
handle_receipt(retry) / handle_stream_error / handle_dirty / handle_offline_* /
handle_edge_routing / handle_pair_* / handle_ack / handle_call / iq result/error.
COUPLING: heavy — most arms read+write state, send frames inline.

### 2. Login / handshake bootstrap
initiate_handshake, decode_handshake_frame, process_server_hello_frame,
send_client_finish, complete_handshake, handle_auth_success, finish_login,
send_init_iq/queries, send_passive_iq, send_unified_session, send_digest_iq,
request_pre_key_count, upload_pre_keys, update_credentials_after_pairing.
COUPLING: noise_state/handshake_state/auth_creds + the IQ sender.

### 3. IQ correlation
stamp_iq, put_pending, send_tracked_iq(_with_id), send_waiter_iq,
handle_iq_response, handle_iq_timeout, handle_tracked_iq (14 clauses),
generate_message_tag, message_epoch. COUPLING: pending_iqs + message_epoch +
send_binary_node.

## The technique: {state, effects}
A state-coupled cluster can't be a pure module if it sends inline. Extract by
making cluster functions PURE: `(state, input) -> {new_state, [effect]}` where an
effect is e.g. `{:send, node}` / `{:emit, topic, data}` / `{:schedule, msg, ms}`.
CM stays the only process: it calls the cluster, then performs the effects
(send_binary_node / emit_to_subscribers / Process.send_after). This removes the
send/state entanglement WITHOUT a god-module and keeps one socket owner.

## Order (lowest risk → highest)
1. **IQ correlation** first — most self-contained (pending_iqs is its own field;
   handle_tracked_iq dispatches to named continuations). Extract to
   `Socket.IQ` returning effects + keeping the tracked-kind continuations as a
   behaviour/callback CM provides. MEDIUM risk.
2. **Login bootstrap** → `Socket.Login` as a {state, effects} sequence
   (handshake → success → prekey → passive active → finish/open). It's mostly a
   linear pipeline already. MEDIUM-HIGH (touches noise state; the thing that took
   days to get right — guard with the live pairing test each step).
3. **Node router** → `Socket.Router.route(node, state) -> {state, [effect]}`.
   HIGHEST risk/value: it's the heart. Do last, arm by arm, re-running the live
   send + e2e after each.

## Safety net
- `mix check` (602 tests) after every extraction — but the router/login paths are
  thin on unit coverage (they're integration). The REAL net is the live runs:
  send_message.exs (send), e2e.exs (two-client round trip), pair.exs (login).
  Run all three after clusters 2 and 3.
- Extract one cluster per commit; keep CM compiling + tests green between.
- Don't change behaviour — pure mechanical move into {state, effects}. Any logic
  change is a separate commit.

## Decision needed before building
- Effect representation: a tagged-tuple list CM interprets (simple) vs a small
  Effects struct. Lean: tagged tuples.
- Whether to do all three now or just cluster 1 (IQ) as a proof of the pattern,
  then reassess. Lean: cluster 1 first (prove {state,effects} works), commit,
  then 2 and 3.
