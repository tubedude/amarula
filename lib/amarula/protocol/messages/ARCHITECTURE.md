# Message Handling Architecture

## Overview Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Amarula.Protocol.Messages                    │
│                        (Main Public API)                         │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ Delegates to specialized modules
                 │
    ┌────────────┴────────────┬─────────────┬──────────────┐
    │                         │             │              │
    ▼                         ▼             ▼              ▼
┌─────────┐             ┌──────────┐  ┌─────────┐  ┌──────────┐
│ Sender  │             │ Receiver │  │  Media  │  │ Reactions│
│         │             │          │  │         │  │          │
│ - send  │             │ - process│  │ - prep  │  │ - react  │
│ - gen   │             │ - decrypt│  │ - enc   │  │ - reply  │
│ - relay │             │ - extract│  │ - down  │  │ - quote  │
└────┬────┘             └────┬─────┘  └────┬────┘  └────┬─────┘
     │                       │             │            │
     └───────────────────────┴─────────────┴────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │      Edit       │
                    │                 │
                    │ - edit_message  │
                    │ - delete        │
                    │ - validate      │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │     Events      │
                    │   (GenServer)   │
                    │                 │
                    │ - subscribe     │
                    │ - emit          │
                    │ - buffer        │
                    └─────────────────┘
```

## Data Flow

### Sending a Message

```
User/Application
       │
       │ send_text(socket, jid, "Hello")
       ▼
Messages (Main API)
       │
       │ delegate
       ▼
Sender.send_text_message
       │
       ├─► generate_message
       │   │
       │   ├─► Generate unique ID
       │   ├─► Add timestamp
       │   ├─► Add context info
       │   └─► Build message structure
       │
       └─► relay_message
           │
           ├─► build_message_node
           │   │
           │   ├─► Build attributes
           │   ├─► Build children
           │   └─► Encode content
           │
           └─► Socket.send_message
               │
               └─► WebSocket ──► WhatsApp Server
```

### Receiving a Message

```
WhatsApp Server
       │
       │ WebSocket Frame
       ▼
Socket Layer
       │
       │ Binary Node
       ▼
Messages (Main API)
       │
       │ process_incoming_message
       ▼
Receiver.process_message_node
       │
       ├─► extract_message_data
       │   │
       │   ├─► Extract ID, from, timestamp
       │   ├─► Extract participant (if group)
       │   └─► Extract content
       │
       ├─► build_wa_message
       │   │
       │   └─► Create standardized structure
       │
       └─► Events.emit_messages_upsert
           │
           └─► Notify subscribers
               │
               ▼
         User/Application
```

### Media Message Flow

```
User sends image
       │
       ▼
Messages.send_image(socket, jid, data)
       │
       ▼
Media.prepare_media_message(:image, data)
       │
       ├─► process_media(data)
       │   └─► Handle binary/stream/url
       │
       ├─► encrypt_media(data)
       │   │
       │   ├─► Generate media_key (32 bytes)
       │   ├─► Generate IV (16 bytes)
       │   ├─► Encrypt with AES-256-CBC
       │   └─► Calculate SHA256
       │
       ├─► generate_thumbnail(data)
       │   └─► TODO: Image processing
       │
       └─► Return encrypted media message
           │
           ▼
Sender.send_message (with media content)
       │
       └─► Relay to WhatsApp
```

## Module Responsibilities

### 1. Types (`types.ex`)
**Purpose**: Define all type specifications

**Responsibilities**:
- Message key structure
- Message content types
- Send options types
- Type safety across modules

**No Dependencies**

### 2. Sender (`sender.ex`)
**Purpose**: Handle all message sending operations

**Responsibilities**:
- Generate message IDs
- Build message structures
- Add timestamps
- Add context info/quoted messages
- Build binary nodes for transmission
- Relay to socket layer

**Dependencies**:
- `Types` - Type definitions
- `Binary.{Encoder, Node, JID}` - Binary protocol
- `Socket` - WebSocket communication

### 3. Receiver (`receiver.ex`)
**Purpose**: Process incoming messages

**Responsibilities**:
- Parse binary nodes
- Extract message data
- Decrypt message content (TODO: Full Signal)
- Build standardized message structures
- Batch processing

**Dependencies**:
- `Types` - Type definitions
- `Binary.{Decoder, Node}` - Binary protocol

### 4. Media (`media.ex`)
**Purpose**: Handle media message processing

**Responsibilities**:
- Prepare media for upload
- Encrypt media (AES-256-CBC)
- Decrypt media
- Generate thumbnails (TODO)
- Handle multiple media types
- Download media from URLs

**Dependencies**:
- Erlang `:crypto` - Encryption
- TODO: HTTP client for downloads
- TODO: Image processing library

### 5. Reactions (`reactions.ex`)
**Purpose**: Handle reactions and replies

**Responsibilities**:
- Send reactions (emoji)
- Remove reactions
- Reply to messages
- Create quoted context
- Process incoming reactions

**Dependencies**:
- `Types` - Type definitions
- `Sender` - For sending reactions
- `Binary.Node` - Node processing

### 6. Edit (`edit.ex`)
**Purpose**: Handle message editing and deletion

**Responsibilities**:
- Edit messages (within 15 minutes)
- Delete messages (self/everyone)
- Validate edit/delete permissions
- Process edit notifications
- Process deletion notifications

**Dependencies**:
- `Types` - Type definitions
- `Sender` - For sending edits/deletes
- `Binary.Node` - Node processing

### 7. Events (`events.ex`)
**Purpose**: Real-time event system

**Responsibilities**:
- Manage subscriptions (GenServer)
- Emit events to subscribers
- Buffer recent events
- Handle multiple event types
- Clean up dead subscriber processes

**Architecture**:
- Standalone GenServer (not embedded in Socket)
- Direct parent-child communication pattern
- Map of event_type => [subscriber_pids]
- Event buffer (last 100 events)
- Process monitoring for automatic cleanup

**Event Types**:
- `:messages_upsert` - New messages
- `:messages_update` - Updates
- `:messages_delete` - Deletions
- `:message_reaction` - Reactions
- `:message_receipt` - Read receipts

**Event Flow**:
- Events are sent directly to parent_pid (specified in Socket.make_socket)
- No intermediate Events GenServer for message routing
- Simple `send(parent_pid, {:whatsapp, event_type, data})` pattern

### 8. Messages (`messages.ex`)
**Purpose**: Main public API

**Responsibilities**:
- Unified interface
- Delegate to specialized modules
- Comprehensive documentation
- Type safety
- Easy-to-use functions

**Delegates to**:
- All other message modules

## Process Model

```
┌──────────────────────────────────────────────────────────┐
│                    Socket Process                         │
│                     (GenServer)                           │
│                                                           │
│  ┌─────────────────┐  ┌──────────────────┐              │
│  │ ConnectionMgr   │  │ SessionManager   │              │
│  │  (GenServer)    │  │   (GenServer)    │              │
│  └─────────────────┘  └──────────────────┘              │
│                                                           │
│  parent_pid: <Application Process>                       │
└────────────────────┬──────────────────────────────────────┘
                     │
                     │ Direct send()
                     │ {:whatsapp, event_type, data}
                     │
                     ▼
              ┌──────────────────┐
              │  Application     │
              │  Process         │
              │  (parent_pid)    │
              └──────────────────┘
                     │
                     │ Can spawn child handlers
                     │
      ┌──────────────┼──────────────┐
      │              │              │
      ▼              ▼              ▼
 ┌────────┐    ┌────────┐    ┌────────┐
 │Handler │    │Handler │    │Handler │
 │   #1   │    │   #2   │    │   #3   │
 └────────┘    └────────┘    └────────┘
```

**Note**: The Events module (`events.ex`) is a standalone GenServer that can be used
for pub/sub patterns if needed, but the primary event flow is direct parent-child
communication via `send(parent_pid, message)`.

## State Management

### Socket State (in Socket)
```elixir
%Amarula.Protocol.Socket{
  connection_manager: pid(),
  session_manager: pid(),
  qr_state: %{...},
  event_publisher: pid(),
  config: %{...},
  connection_state: %{connection: :connected, ...},
  parent_pid: pid(),  # Where events are sent
  message_tag_generator: function(),
  epoch: 0
}
```

### Events Manager State (Optional Standalone)
If using the optional standalone Events GenServer for pub/sub patterns:

```elixir
%Amarula.Protocol.Messages.Events{
  subscribers: %{
    messages_upsert: [pid1, pid2, pid3],
    message_reaction: [pid4],
    messages_delete: [pid5]
  },
  event_buffer: [
    %{type: :messages_upsert, data: %{...}, timestamp: 1234567890},
    %{type: :message_reaction, data: %{...}, timestamp: 1234567891},
    # ... last 100 events
  ]
}
```

**Note**: Most applications receive events directly via parent_pid without using
the Events GenServer.

## Message Lifecycle

### Outgoing Message
```
1. User calls Messages.send_text(socket, jid, "Hello")
2. Sender.generate_message creates message structure
3. Sender.build_message_node builds binary node
4. Socket.send_message sends to WebSocket
5. WhatsApp server receives and processes
6. Server sends acknowledgment
7. Events.emit_messages_update notifies subscribers
8. Message status updated to :sent/:delivered
```

### Incoming Message
```
1. WhatsApp server sends message via WebSocket
2. Connection receives and decodes binary node
3. Connection routes to appropriate handler
4. Receiver.process_message_node parses the node
5. Receiver.extract_message_data extracts data
6. Receiver.build_wa_message creates structure
7. Socket sends directly to parent_pid: send(parent_pid, {:whatsapp, :messages_upsert, data})
8. Application receives {:whatsapp, :messages_upsert, data}
9. Application processes new message
```

## Error Handling

All modules use consistent error handling:

```elixir
# Success
{:ok, result}

# Failure
{:error, reason}
```

Common error reasons:
- `:not_connected` - Socket not connected
- `:invalid_jid` - Invalid JID format
- `:no_media_url` - Media URL missing
- `:encryption_failed` - Encryption error
- `:no_content` - Missing message content

## Type Safety

Every public function has a `@spec`:

```elixir
@spec send_text(pid(), String.t(), String.t(), map()) ::
        {:ok, Types.wa_message()} | {:error, term()}
```

This provides:
- Compile-time type checking (with Dialyzer)
- Editor autocomplete
- Clear documentation
- Contract enforcement

## Concurrency Model

- **GenServer (Events)**: Single process managing all subscriptions
- **Functional Modules**: Stateless, pure functions
- **Process Isolation**: Each socket is independent
- **Message Passing**: All communication via messages
- **Fault Tolerance**: Supervisor tree handles crashes

## Performance Characteristics

### Time Complexity
- Send message: O(1)
- Receive message: O(1)
- Event emission: O(n) where n = subscribers
- Event subscription: O(1)

### Space Complexity
- Event buffer: O(1) - limited to 100 events
- Subscribers: O(n) where n = active subscribers
- Message processing: O(1) - no caching

## Testing Strategy

```
Unit Tests
├── Sender
│   ├── Message generation
│   ├── ID uniqueness
│   └── Options handling
├── Events
│   ├── Subscription
│   ├── Emission
│   └── Unsubscription
└── Reactions
    ├── Send reaction
    └── Reply to message

Integration Tests (TODO)
├── Full message flow
├── WebSocket integration
└── Signal encryption

E2E Tests (TODO)
├── Real WhatsApp connection
└── Multi-device scenarios
```

## Future Enhancements

### Protocol Integration
- [ ] Full Protocol Buffer encoding
- [ ] Signal Protocol encryption
- [ ] Proper binary node handling

### Media Processing
- [ ] Thumbnail generation with image library
- [ ] Video thumbnail extraction
- [ ] Audio waveform generation
- [ ] Document preview

### Advanced Features
- [ ] Message scheduling
- [ ] Draft messages
- [ ] Message templates
- [ ] Bulk operations
- [ ] Message search/query

### Performance
- [ ] Message caching
- [ ] Event batching
- [ ] Compression
- [ ] Streaming for large media

---

This architecture provides a solid foundation for WhatsApp message handling while maintaining flexibility for future enhancements and optimizations.

