# Amarula Messages Module

This module implements Phase 6 of the Baileys Elixir rewrite: **Message Handling**.

## Overview

The Messages module provides comprehensive functionality for handling WhatsApp messages, including:

- **Message Sending**: Text, media, and other message types
- **Message Receiving**: Processing incoming messages from WebSocket frames
- **Media Handling**: Images, videos, audio, documents with encryption
- **Reactions & Replies**: Message reactions and reply functionality
- **Editing & Deletion**: Support for editing and deleting messages
- **Event System**: Real-time message events and notifications

## Architecture

```
Amarula.Protocol.Messages/
├── types.ex          # Type definitions and specs
├── sender.ex         # Message sending functionality
├── receiver.ex       # Message receiving and processing
├── media.ex          # Media message handling
├── reactions.ex      # Reactions and replies
├── edit.ex           # Message editing and deletion
├── events.ex         # Real-time event system
└── messages.ex       # Main public API
```

## Usage

### Sending Messages

```elixir
# Send a text message
{:ok, message} = Messages.send_text(socket_pid, "1234567890@s.whatsapp.net", "Hello!")

# Send an image
{:ok, image_data} = File.read("photo.jpg")
{:ok, message} = Messages.send_image(socket_pid, jid, image_data, %{caption: "Check this out!"})

# Send a video
{:ok, video_data} = File.read("video.mp4")
{:ok, message} = Messages.send_video(socket_pid, jid, video_data)

# Send an audio message
{:ok, audio_data} = File.read("voice.ogg")
{:ok, message} = Messages.send_audio(socket_pid, jid, audio_data, %{ptt: true})

# Send a document
{:ok, doc_data} = File.read("document.pdf")
{:ok, message} = Messages.send_document(socket_pid, jid, doc_data, %{
  file_name: "document.pdf",
  mime_type: "application/pdf"
})
```

### Receiving Messages

```elixir
# Process incoming message node
{:ok, message} = Messages.process_incoming_message(node)

# Process batch of messages
{:ok, messages} = Messages.process_messages_batch(nodes)
```

### Message Reactions

```elixir
# Send a reaction
{:ok, reaction} = Messages.send_reaction(socket_pid, message_key, "👍")

# Remove a reaction
{:ok, _} = Messages.remove_reaction(socket_pid, message_key)
```

### Message Replies

```elixir
# Reply to a message
{:ok, reply} = Messages.send_reply(socket_pid, quoted_message, "Thanks for your message!")
```

### Message Editing

```elixir
# Edit a message (within 15 minutes)
if Messages.can_edit?(message) do
  {:ok, edited} = Messages.edit_message(socket_pid, message.key, "Updated text")
end
```

### Message Deletion

```elixir
# Delete for yourself
{:ok, _} = Messages.delete_message(socket_pid, message.key, false)

# Delete for everyone (if you sent it)
if Messages.can_delete?(message, true) do
  {:ok, _} = Messages.delete_message(socket_pid, message.key, true)
end
```

### Event System

```elixir
# Start the events manager
{:ok, events_pid} = Messages.start_events_manager()

# Subscribe to message events
Messages.subscribe_to_events(:messages_upsert)

# Receive events in your process
receive do
  {:message_event, event} ->
    case event.type do
      :messages_upsert ->
        IO.inspect(event.data.messages, label: "New messages")
      
      :message_reaction ->
        IO.inspect(event.data.reaction, label: "New reaction")
      
      :messages_update ->
        IO.inspect(event.data, label: "Message updates")
    end
end
```

## Event Types

The event system supports the following event types:

- `:messages_upsert` - New messages received or sent
- `:messages_update` - Existing messages updated
- `:messages_delete` - Messages deleted
- `:message_reaction` - Reaction added or removed
- `:message_receipt` - Message receipt/read status updated

## Media Handling

Media messages are automatically encrypted before upload and decrypted after download:

```elixir
# Download media from a message
case Messages.download_media(message.message.image) do
  {:ok, image_data} ->
    File.write("downloaded_image.jpg", image_data)
  
  {:error, reason} ->
    Logger.error("Failed to download media: #{inspect(reason)}")
end
```

## Message Structure

All messages follow the `wa_message` structure:

```elixir
%{
  key: %{
    remote_jid: "1234567890@s.whatsapp.net",
    from_me: true,
    id: "3EB0ABC123...",
    participant: nil  # Set for group messages
  },
  message: %{
    text: "Message content",
    # Or other message types (image, video, etc.)
  },
  message_timestamp: 1234567890,
  status: :sent  # or :received, :pending, etc.
}
```

## Implementation Status

### ✅ Completed

- [x] Message type definitions
- [x] Text message sending
- [x] Message receiving and processing
- [x] Media message preparation (encryption)
- [x] Media download and decryption
- [x] Message reactions (send/remove)
- [x] Message replies
- [x] Message editing
- [x] Message deletion
- [x] Real-time event system
- [x] Event subscriptions
- [x] Comprehensive tests

### 🚧 TODO (Future Enhancements)

- [ ] Protocol buffer encoding/decoding (currently placeholder)
- [ ] Full Signal protocol integration for encryption
- [ ] Media upload to WhatsApp servers
- [ ] Thumbnail generation for images/videos
- [ ] Link preview generation
- [ ] Poll messages
- [ ] Contact messages
- [ ] Location messages
- [ ] Button messages
- [ ] List messages
- [ ] Message retry mechanism
- [ ] Message caching

## Design Decisions

### Following Elixir Guidelines

1. **No index-based list access**: We use `Enum.at/2` and pattern matching instead of `list[index]`

2. **Proper variable rebinding**: All block expressions (`if`, `case`, `cond`) bind their results to variables

3. **Pattern matching over nested ifs**: Using `case` and `cond` for clearer control flow

4. **Error handling with tuples**: Using `{:ok, result}` / `{:error, reason}` pattern matching

5. **GenServer for state management**: The Events module uses GenServer for managing subscriptions

### Modular Design

Each module has a single responsibility:
- `Sender` - Only handles sending
- `Receiver` - Only handles receiving
- `Media` - Only handles media processing
- `Reactions` - Only handles reactions and replies
- `Edit` - Only handles editing and deletion
- `Events` - Only handles event management
- `Messages` - Public API that delegates to specialized modules

### Type Safety

All public functions have `@spec` annotations for type safety and documentation.

## Integration with Other Modules

The Messages module integrates with:

- **Binary Protocol** (`Amarula.Protocol.Binary`): For encoding/decoding WhatsApp binary nodes
- **Socket Layer** (`Amarula.Protocol.Socket`): For sending/receiving WebSocket frames
- **Signal Protocol** (`Amarula.Protocol.Signal`): For end-to-end encryption (TODO)
- **Authentication** (`Amarula.Protocol.Auth`): For user credentials and session management

## Testing

Run tests with:

```bash
cd amarula
mix test test/protocol/messages/
```

## Next Steps

After completing Phase 6, the next phases are:

- **Phase 7**: Group Management (group creation, participants, settings)
- **Phase 8**: Media Processing (advanced image/video processing)
- **Phase 9**: Event System enhancements
- **Phase 10**: Testing & Compatibility

## Contributing

When adding new message types or features:

1. Add type definitions to `types.ex`
2. Implement the logic in the appropriate specialized module
3. Add a public API function in `messages.ex`
4. Write comprehensive tests
5. Update this README

## License

Part of the Amarula project - Baileys Elixir rewrite.

