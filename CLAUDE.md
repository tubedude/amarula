# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Amarula is an Elixir implementation of the WhatsApp Web protocol. It provides a complete client library for connecting to WhatsApp Web, handling authentication via QR codes, and sending/receiving messages. The project is structured around the WebSocket-based protocol used by WhatsApp Web, implementing the Noise Protocol for encryption, Signal Protocol for end-to-end encryption, and Protocol Buffers for message serialization.

## Common Commands

### Development
```bash
# Install dependencies
mix deps.get

# Compile project
mix compile

# Format code
mix format

# Run all tests
mix test

# Run specific test file
mix test test/protocol/auth/qr_code_generator_test.exs

# Run tests with coverage
mix test --cover

# Type checking (Dialyzer)
mix dialyzer

# Linting (Credo)
mix credo
```

### Running Examples
```bash
# Pair a device + listen (GenServer connection)
iex -S mix
iex> {:ok, _} = Amarula.Examples.Connection.start_link(name: :wa)   # scan the QR
iex> Amarula.Examples.Connection.send_text(:wa, "<number>@s.whatsapp.net", "hi")

# Send one message, then exit (needs an already-paired ./amarula_data)
mix run examples/send_message.exs "<number>" "hello"
```

### Protocol Buffer Compilation
```bash
# Regenerate lib/amarula/protocol/proto/wa_proto.pb.ex when proto/wa_proto.proto changes
protoc -I proto --elixir_out=package_prefix=amarula.protocol:lib/amarula/protocol/proto wa_proto.proto
```

## Architecture

### High-Level Structure

The codebase follows a layered architecture mirroring the WhatsApp Web protocol stack:

```
lib/amarula/protocol/
├── socket/          # WebSocket layer & connection management
├── crypto/          # Noise Protocol & cryptographic operations
├── auth/            # Authentication, QR codes, session management
├── binary/          # Binary node encoding/decoding
├── messages/        # Message handling (send/receive/media)
├── signal/          # Signal Protocol (E2E encryption)
└── proto/           # Protocol Buffer definitions
```

### Key Components

**Public API**:
- `Amarula` (`lib/amarula.ex`): the core facade consumers call. `new/1` builds a
  `%Amarula.Conn{}`, `connect/2` starts it; `send_*`, `download_media`,
  presence/read helpers delegate to `Amarula.Connection`. Events reach the
  consumer's `parent_pid` as `{:amarula, type, data}` (see `t:event/0`).
- Family operations live on their own modules, not the flat facade:
  `Amarula.Group` (create/leave/metadata/invites/requests/…),
  `Amarula.Profile` (picture/status), `Amarula.Contacts` (on_whatsapp/status/lid).
- Consumer structs: `Amarula.Msg` (a received message — `type` + `content`, never
  the raw proto), `Amarula.Address` (PN/LID/group boundary type), `Amarula.Chat`,
  `Amarula.Contact`, `Amarula.Group`, `Amarula.Conn`.

**Socket Layer** (`lib/amarula/protocol/socket/`):
- `Amarula.Connection` (`lib/amarula/connection.ex`): the single per-connection
  process and the consumer's endpoint (the pid `connect/2` returns). The sole
  websocket owner — Noise handshake, IQ correlation, credential resolve/persist
  (via the Storage seam), 515 restart, offline batch, notification dispatch,
  send dispatch — and it delivers consumer events straight to `parent_pid`
  (no relay process, no subscriber registry). The big coordinator (intentionally;
  not a god object — decision/domain logic live in their own modules).
- `Router`: pure node→handler-tag routing table (`route/1`).
- `IQ`: pure IQ-correlation state (`track/wait/resolve/timeout`).
- `Login`: pure handshake/login step builders.
- `WebSocketClient`: low-level frame I/O. `ConnectionValidator`: state checks.

**Crypto Layer** (`lib/amarula/protocol/crypto/`):
- `NoiseHandler`: Noise_XX handshake. `Crypto`: primitives. `Constants`.

**Authentication** (`lib/amarula/protocol/auth/`):
- `QRCodeGenerator`: QR string build/parse. `AuthUtils`: initial credential
  generation. `DeviceIdentity`: pure pairing crypto (verify + counter-sign the ADV
  device identity). Credentials are persisted by `Amarula.Connection` through the
  `Amarula.Storage` seam (`:creds`/`:self`), scoped to the connection's `:profile`
  — there is no SessionManager/ETSKeyStore/EventPublisher (removed).

**Binary Protocol** (`lib/amarula/protocol/binary/`):
- `Encoder`/`Decoder` (custom binary node format), `Node`, `NodeUtils`, `JID`,
  `Constants`.

**Message Handling** (`lib/amarula/protocol/messages/`):
- `ConversationSender`: per-recipient send GenServer; runs the blocking pipe
  `resolve_devices → ensure_sessions → encrypt → relay` and returns
  `:ok | {:error, {stage, reason}}`. Sends are synchronous.
- `MessageEncoder` (build outgoing protos), `MessageContent` (classify incoming →
  used by `Amarula.Msg`), `MessageDecryptor`, `Receipt`, `Media`, `HistorySync`.

**Signal Protocol** (`lib/amarula/protocol/signal/`):
- `SessionStore`, `SessionInjector`, `SessionCipher`,
  `PreKeys`, `DeviceListCache`, `LidMappingFileStore` (LID↔PN), `group/`
  (sender-key cipher).
- **The crypto is a pure, self-contained layer with an explicit boundary** — the
  Core (Noise + Signal cipher/ratchet) depends on no app/storage/WhatsApp code; a
  small set of Glue modules (`SessionStore`, `SessionInjector`, `DeviceListCache`,
  `LidMapping*Store`, `group/SenderKeyStore`) is the only bridge to
  `Amarula.Conn`/`Amarula.Storage`. The rule: **Core must never depend on the app.**
  See [`docs/CRYPTO_BOUNDARY.md`](docs/CRYPTO_BOUNDARY.md).

**Storage** (`lib/amarula/storage*`): pluggable `Amarula.Storage` behaviour scoped
by `{profile, namespace, key}`; `File` + `DETS` adapters. Holds creds, sessions,
sender keys, LID mappings, device lists, app-state. `Amarula.RetryCache` is a
separate pluggable seam.

### Process Model

Each connection is an independent supervision tree (so many accounts run side by
side), started by `ConnectionSupervisor`:

```
ConnectionSupervisor (per instance, :rest_for_one)
├── Connection (GenServer) — owns the WebSocketClient + Noise/IQ state, the
│     consumer API, consumer-event delivery to parent_pid, AND the
│     per-connection retry-cache ETS table
└── ConversationSender DynamicSupervisor — one sender GenServer per recipient
```

`Connection` is both the websocket owner and the consumer's endpoint — the relay
`Socket` GenServer was merged into it (one process per connection, no double hop).
Storage is a config concern (a scope on the `Conn`), not a process. The retry-cache
ETS table is owned by `Connection` (created in `init`), so it's recreated clean on a
restart — no separate owner process.

The tree owns no Registry. The app-level `Amarula.InstanceRegistry` names every
tree's processes by its `instance_id` ref, and maps `{instance_id, recipient_jid} →
sender pid` (a registry, not atom names, because the recipient key space is
unbounded/user-controlled). Senders are one-per-recipient, `:temporary`, lazily
started, and hold no durable state — not even the ratchet (sessions live in
Storage). A sender is a *lock*, not a cache: `encrypt` is a non-atomic
load-modify-store of the shared Signal session, so one process per recipient
serializes it (serial within a recipient, parallel across). See
`Amarula.Protocol.Messages.ConversationSender`.

**For the full, current infrastructure reference — supervision tree, registry
rationale, the ConversationSender lifecycle, and the send/ack/crash-recovery
semantics — see [`docs/INFRASTRUCTURE.md`](docs/INFRASTRUCTURE.md)** (the living
architecture doc; `docs/plans/` are point-in-time and may be stale).

### Data Flow

**Connection**: `Amarula.connect/2` → `Connection` opens the
WebSocket → Noise XX handshake → first run emits `:connection_update` with a `qr`
string (consumer renders it) → phone scans → `:pairing_success` → creds persisted
internally → 515 restart (auto) → `:connection_update` `connection: :open`.

**Sending**: `Amarula.send_text/3` → `Connection` → per-recipient `ConversationSender`
→ `resolve_devices` (device cache / USync) → `ensure_sessions` (prekey bundle
fetch) → `encrypt` (per device) → `relay` (frame via `Connection`). Returns
`{:ok, msg_id}` or `{:error, reason}` (e.g. `:not_on_whatsapp`). `Connection`
forwards the caller's `from` to the sender, which replies when the send finishes —
so sends to different recipients complete out-of-order without blocking each other.

**Receiving**: frame → `Connection` decodes + `Router.route/1` → `handle_message`
→ `MessageDecryptor` → wrapped as `[%Amarula.Msg{}]` → `:messages_upsert` event to
`parent_pid`. Receipts/notifications dispatch to their own handlers + events
(`:receipt_update`, `:group_update`, ...).

### Important Architectural Patterns

**Noise Protocol Integration**: The handshake happens immediately after WebSocket connection. The `NoiseHandler` maintains state through three message exchanges:
- `→ e` (send ephemeral key)
- `← e, ee, s, es` (receive server keys, DH operations)
- `→ s, se` (send identity, complete handshake)

After handshake completion, all messages are encrypted/decrypted using derived keys. This is handled transparently by `Amarula.Connection`.

**Binary Node Protocol**: WhatsApp uses a custom binary format (not JSON). Every message is a "node" with:
- Tag (string identifier like "message", "iq", "presence")
- Attributes (map of string key-value pairs)
- Content (binary data or nested child nodes)

The `Encoder`/`Decoder` handle this serialization, using dictionary-based token compression for common strings.

**Event-Driven Architecture**: Instead of polling, the system delivers events to the
consumer's `parent_pid` as `{:amarula, type, data}` messages — e.g. `:connection_update`
(carries the `qr` string during pairing), `:messages_upsert`, `:receipt_update`,
`:group_update`. The authoritative list is `t:Amarula.event/0` in `lib/amarula.ex` —
don't maintain a copy here.

**Credential Management**: Credentials include:
- `noise_key`: Curve25519 keypair for Noise Protocol
- `signed_identity_key`: Curve25519 keypair for identity
- `signed_pre_key`: Pre-key for Signal Protocol
- `registration_id`: Unique device registration ID
- `adv_secret_key`: Advanced encryption secret

They are persisted by `Amarula.Connection` through the `Amarula.Storage` seam
(`:creds`/`:self` namespaces), scoped to the connection's `:profile`.

## Testing

Tests are organized by protocol layer:
```
test/
├── protocol/
│   ├── auth/           # Authentication tests
│   ├── binary/         # Binary encoding/decoding tests
│   ├── crypto/         # Crypto and handshake tests
│   ├── messages/       # Message handling tests
│   └── signal/         # Signal Protocol tests
└── integration/        # End-to-end integration tests
```

Run specific test suites:
```bash
# Auth layer
mix test test/protocol/auth/

# Crypto layer
mix test test/protocol/crypto/

# Messages
mix test test/protocol/messages/

# Single test with line number
mix test test/protocol/auth/qr_code_generator_test.exs:42
```

## Elixir Guidelines

See `AGENTS.md` — the comprehensive Elixir coding guidelines for this project
(list access, rebinding, pattern-matching order, error-tuple conventions, etc.).

## Key Files to Reference

- `examples/connection.ex` - GenServer that embeds a connection (pairing + listen + send)
- `lib/amarula.ex` - The public API facade (the entry point library consumers use)
- `docs/INFRASTRUCTURE.md` - The living architecture reference (process model, send/ack/crash semantics)
- `lib/amarula/connection.ex` - The per-connection process: websocket + cipher + IQ + sends + consumer API (the facade delegates here)
- `lib/amarula/protocol/crypto/noise_handler.ex` - Noise Protocol implementation
- `AGENTS.md` - Comprehensive Elixir coding guidelines for this project

## Protocol Buffer Usage

Protocol Buffers are compiled from `proto/wa_proto.proto` (the full WhatsApp protocol
definitions). The generated module is `lib/amarula/protocol/proto/wa_proto.pb.ex`
(`Amarula.Protocol.Proto.*`), providing `encode/1` and `decode/1` for message
serialization. Regeneration command: see "Protocol Buffer Compilation" above.

## WhatsApp Version

The current WhatsApp Web version must match a version WhatsApp still accepts. Check `../baileys/src/Defaults/index.ts` for Baileys' bundled default:
```typescript
const version = [2, 3000, 1042537629]  // Baileys version
```

Note: Baileys' bundled default can lag the *live* WA Web version and a stale
version silently breaks new-device pairing (QR/pairing code generates, but the
phone reports "Couldn't link device"). When pairing fails, check the current live
version (e.g. Baileys' `fetchLatestWaWebVersion()` or the WA Web client) — it may
be ahead of the bundled default.

The single source of truth in Amarula is `Amarula.Config` (`lib/amarula/config.ex`,
the `@wa_version` module attribute → the connection's `:version`); the mirror in
`lib/amarula/protocol/crypto/constants.ex` is kept in sync. The version also feeds
the MD5 buildHash in `lib/amarula/protocol/auth/auth_utils.ex`. If the version
drifts, Amarula must match it or WhatsApp will reject the connection.

### When to update the version

WhatsApp bumps this version periodically. **When you should suspect it's stale:**

- New-device pairing fails: the QR / pairing code generates, but the phone reports
  **"Couldn't link device — An error occurred"** and `:pairing_success` never fires
  (the socket eventually 408s and retries with the same result).
- The handshake is rejected outright on connect.

**How to check and update (maintainer):**

```bash
# Compare the pinned version against the live WhatsApp Web version — changes nothing
mix run scripts/update_wa_version.exs --check

# If out of date: rewrite the pinned literal in config.ex + constants.ex
mix run scripts/update_wa_version.exs
#   → review `git diff`, then commit (bump the CLAUDE.md example above too)
```

The script fetches the live version from WhatsApp Web's own service worker
(`https://web.whatsapp.com/sw.js`, the `client_revision` field) — the same source
Baileys uses. **The running library never fetches the version itself**; it always
uses the pinned value, so a version bump is a deliberate, reviewed commit.

**Consumer override (no recompile):** set the `AMARULA_WA_VERSION` env var to a
dotted triple (e.g. `AMARULA_WA_VERSION=2.3000.1042537629`) to override the pinned
default at runtime — useful to track a new WhatsApp version before the pinned one
is bumped. A malformed value is ignored (warned) and the pinned default is used.
