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
mix test test/protocol/auth/session_manager_test.exs

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

# Send one message, then exit (needs an already-paired ./amarula_auth)
mix run examples/send_message.exs "<number>" "hello"
```

### Protocol Buffer Compilation
```bash
# Compile proto files (when updated)
protoc --elixir_out=lib/amarula/protocol/proto proto/*.proto
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
- `Amarula` (`lib/amarula.ex`): the facade consumers call. `new/1` builds a
  `%Amarula.Conn{}`, `connect/2` starts it; `send_*`, `group_*`, `download_media`,
  presence/read helpers delegate to `Socket`. Events reach the consumer's
  `parent_pid` as `{:whatsapp, type, data}` (see `t:event/0`).
- Consumer structs: `Amarula.Msg` (a received message — `type` + `content`, never
  the raw proto), `Amarula.Address` (PN/LID/group boundary type), `Amarula.Chat`,
  `Amarula.Contact`, `Amarula.Group`, `Amarula.Conn`.

**Socket Layer** (`lib/amarula/protocol/socket/`):
- `Socket`: per-connection facade GenServer; forwards ConnectionManager events to
  `parent_pid` and delegates sends.
- `ConnectionManager`: the sole websocket owner — Noise handshake, IQ correlation,
  credential resolve/persist (via the Storage seam), 515 restart, offline batch,
  notification dispatch. The big coordinator (intentionally; not a god object —
  decision/domain logic live in their own modules).
- `Router`: pure node→handler-tag routing table (`route/1`).
- `IQ`: pure IQ-correlation state (`track/wait/resolve/timeout`).
- `Login`: pure handshake/login step builders.
- `WebSocketClient`: low-level frame I/O. `ConnectionValidator`: state checks.

**Crypto Layer** (`lib/amarula/protocol/crypto/`):
- `NoiseHandler`: Noise_XX handshake. `Crypto`: primitives. `Constants`.

**Authentication** (`lib/amarula/protocol/auth/`):
- `QRCodeGenerator`: QR string build/parse. `AuthUtils`: initial credential
  generation. `DeviceIdentity`: pure pairing crypto (verify + counter-sign the ADV
  device identity). Credentials are persisted by `ConnectionManager` through the
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
- `Repository` (sessions/keys), `SessionStore`, `SessionInjector`, `SessionCipher`,
  `PreKeys`, `DeviceListCache`, `LidMappingFileStore` (LID↔PN), `group/`
  (sender-key cipher).

**Storage** (`lib/amarula/storage*`): pluggable `Amarula.Storage` behaviour scoped
by `{profile, namespace, key}`; `File` + `DETS` adapters. Holds creds, sessions,
sender keys, LID mappings, device lists, app-state. `Amarula.RetryCache` is a
separate pluggable seam.

### Process Model

Each connection is an independent supervision tree (so many accounts run side by
side), started by `ConnectionSupervisor`:

```
ConnectionSupervisor (per instance)
├── ConnectionManager (GenServer) — owns the WebSocketClient + Noise/IQ state
├── Socket (GenServer) — facade, forwards events to parent_pid
├── Repository (Signal sessions)
└── ConversationSender DynamicSupervisor — one sender GenServer per recipient
```

Storage is a config concern (a scope on the `Conn`), not a process.

### Data Flow

**Connection**: `Amarula.connect/2` → `Socket` → `ConnectionManager` opens the
WebSocket → Noise XX handshake → first run emits `:connection_update` with a `qr`
string (consumer renders it) → phone scans → `:pairing_success` → creds persisted
internally → 515 restart (auto) → `:connection_update` `connection: :open`.

**Sending**: `Amarula.send_text/3` → `Socket` → per-recipient `ConversationSender`
→ `resolve_devices` (device cache / USync) → `ensure_sessions` (prekey bundle
fetch) → `encrypt` (per device) → `relay` (frame via ConnectionManager). Returns
`{:ok, msg_id}` or `{:error, reason}` (e.g. `:not_on_whatsapp`).

**Receiving**: frame → `ConnectionManager` decodes + `Router.route/1` → `handle_message`
→ `MessageDecryptor` → wrapped as `[%Amarula.Msg{}]` → `:messages_upsert` event to
`parent_pid`. Receipts/notifications dispatch to their own handlers + events
(`:receipt_update`, `:group_update`, ...).

### Important Architectural Patterns

**Noise Protocol Integration**: The handshake happens immediately after WebSocket connection. The `NoiseHandler` maintains state through three message exchanges:
- `→ e` (send ephemeral key)
- `← e, ee, s, es` (receive server keys, DH operations)
- `→ s, se` (send identity, complete handshake)

After handshake completion, all messages are encrypted/decrypted using derived keys. This is handled transparently by the `ConnectionManager`.

**Binary Node Protocol**: WhatsApp uses a custom binary format (not JSON). Every message is a "node" with:
- Tag (string identifier like "message", "iq", "presence")
- Attributes (map of string key-value pairs)
- Content (binary data or nested child nodes)

The `Encoder`/`Decoder` handle this serialization, using dictionary-based token compression for common strings.

**Event-Driven Architecture**: Instead of polling, the system emits events that applications subscribe to:
- `:qr` - New QR code generated
- `:connection_update` - Connection state changed
- `:messages_upsert` - New messages received
- `:message_reaction` - Reaction added/removed
- `:error` - Error occurred

**Credential Management**: Credentials include:
- `noise_key`: Curve25519 keypair for Noise Protocol
- `signed_identity_key`: Curve25519 keypair for identity
- `signed_pre_key`: Pre-key for Signal Protocol
- `registration_id`: Unique device registration ID
- `adv_secret_key`: Advanced encryption secret

These are managed by `SessionManager` and persisted via `KeyStoreBehaviour` implementations.

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
mix test test/protocol/auth/session_manager_test.exs:42
```

## Elixir-Specific Guidelines

**List Access**: Elixir lists do NOT support index-based access via `list[i]`. Use `Enum.at(list, i)` or pattern matching.

**Variable Rebinding in Blocks**: Variables are immutable but can be rebound. For `if`/`case`/`cond`, bind the result:
```elixir
# WRONG
if condition do
  socket = update_socket(socket)
end

# CORRECT
socket = if condition do
  update_socket(socket)
else
  socket
end
```

**Avoid Nested `if`**: Use `cond` or `case` with pattern matching for multiple conditions.

**Struct Access**: Never use bracket syntax `struct[:field]` on structs. Use dot notation `struct.field` or module functions.

**Pattern Matching Order**: Order patterns from most specific to least specific to avoid unreachable code warnings.

**Error Handling**: Prefer `{:ok, result}` / `{:error, reason}` tuples with pattern matching over exceptions. Use `!` versions (`File.read!/1`) only when failure should crash.

## Key Files to Reference

- `examples/connection.ex` - GenServer that embeds a connection (pairing + listen + send)
- `lib/amarula.ex` - The public API facade (the entry point library consumers use)
- `lib/amarula/protocol/messages/ARCHITECTURE.md` - Detailed message handling architecture
- `lib/amarula/protocol/socket/socket.ex` - Internal transport GenServer (the facade delegates here)
- `lib/amarula/protocol/crypto/noise_handler.ex` - Noise Protocol implementation
- `AGENTS.md` - Comprehensive Elixir coding guidelines for this project

## Protocol Buffer Usage

Protocol Buffers are compiled from `.proto` files in the `proto/` directory:
- `wa_proto.proto` - Full WhatsApp protocol definitions
- `wa_minimal.proto` - Minimal subset for basic operations

Generated modules are in `lib/amarula/protocol/proto/proto/`. These provide `encode/1` and `decode/1` functions for message serialization.

## WhatsApp Version

The current WhatsApp Web version must match the Baileys implementation. Check `../src/Defaults/index.ts` for the current version:
```typescript
const version = [2, 3000, 1027934701]  // Baileys version
```

This is configured in Amarula at `examples/connection.ex` (the `config/1` helper) and `lib/amarula/protocol/auth/auth_utils.ex:81` (used for MD5 buildHash calculation). If Baileys updates their version, Amarula must match it exactly or WhatsApp will reject the connection.
