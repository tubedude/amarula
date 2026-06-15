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

**Socket Layer** (`lib/amarula/protocol/socket/`):
- `Socket`: Main GenServer coordinating the entire connection lifecycle. Acts as the primary API entry point.
- `ConnectionManager`: Handles WebSocket connections, retry logic, handshake orchestration, and event emission.
- `WebSocketClient`: Low-level WebSocketEx wrapper for sending/receiving frames.
- `ConnectionValidator`: Validates connection state and handles connection-related errors.

**Crypto Layer** (`lib/amarula/protocol/crypto/`):
- `NoiseHandler`: Implements Noise Protocol XX pattern for initial handshake. This is critical for establishing the secure channel before authentication.
- `Crypto`: Core cryptographic primitives (encryption, hashing, key generation).
- `Constants`: Cryptographic constants and WhatsApp-specific protocol values.

**Authentication** (`lib/amarula/protocol/auth/`):
- `SessionManager`: GenServer managing authentication state, credentials, and session lifecycle.
- `QRCodeGenerator`: Generates and refreshes QR codes for mobile device pairing.
- `ETSKeyStore`: ETS-based key-value store implementing `KeyStoreBehaviour` for credential persistence.
- `EventPublisher`: GenServer for publishing authentication events (QR codes, pairing success/failure).
- `BaileysCredentialLoader`: Utility for loading credentials from Baileys (TypeScript implementation) for comparison/testing.

**Binary Protocol** (`lib/amarula/protocol/binary/`):
- `Encoder`/`Decoder`: Serialize/deserialize WhatsApp's custom binary node format.
- `Node`: Binary node structure representing WhatsApp protocol messages.
- `NodeUtils`: Helper functions for node manipulation and validation.
- `JID`: JID (Jabber ID) parsing and manipulation for WhatsApp identifiers.
- `Constants`: Protocol constants and tags.

**Message Handling** (`lib/amarula/protocol/messages/`):
- `Messages`: Main public API for sending/receiving messages.
- `Sender`: Message generation and sending logic.
- `Receiver`: Incoming message processing and parsing.
- `Media`: Media message encryption, decryption, and processing.
- `Reactions`: Reactions and replies to messages.
- `Edit`: Message editing and deletion.
- `Events`: GenServer-based event subscription system for real-time updates.

**Signal Protocol** (`lib/amarula/protocol/signal/`):
- `Repository`: Signal Protocol session/key management.
- `LidMappingStore`: LID (Local ID) to JID mapping for multi-device.
- `group/`: Group messaging specific Signal Protocol components.

### Process Model

Amarula uses OTP principles with a supervision tree:

```
Socket (GenServer)
├── ConnectionManager (GenServer)
│   └── WebSocketClient (WebSocketEx process)
├── SessionManager (GenServer)
│   └── ETSKeyStore (ETS table)
├── QRCodeGenerator (started on-demand)
└── EventPublisher (GenServer)
```

Each socket connection is an independent GenServer that coordinates child processes. The architecture supports multiple concurrent connections (though typically one per application instance).

### Data Flow

**Connection Flow**:
1. `Socket.make_socket/1` creates socket GenServer
2. `Socket.connect/1` initiates connection
3. `ConnectionManager` establishes WebSocket
4. Noise Protocol handshake (3 messages)
5. `QRCodeGenerator` starts and emits QR codes
6. Mobile device scans QR code
7. Pairing completed, session established

**Message Sending**:
1. Application calls `Messages.send_text/3` (or other send function)
2. `Sender` generates message structure with ID, timestamp
3. `Sender.build_message_node/1` creates binary node
4. `Socket.send_message/2` → `ConnectionManager` → `WebSocketClient`
5. WebSocket frame sent to WhatsApp servers

**Message Receiving**:
1. WebSocket frame arrives at `WebSocketClient`
2. `ConnectionManager` decodes binary node via `Decoder`
3. Routed to `Receiver.process_message_node/1`
4. Message parsed and normalized
5. `Events` emits `:messages_upsert` event
6. Subscribed processes receive message

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
