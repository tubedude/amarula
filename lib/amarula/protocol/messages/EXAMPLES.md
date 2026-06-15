# Message Handling Examples

This document provides practical examples of using the Amarula Messages module.

## Table of Contents

1. [Basic Setup](#basic-setup)
2. [Sending Messages](#sending-messages)
3. [Receiving Messages](#receiving-messages)
4. [Media Messages](#media-messages)
5. [Reactions](#reactions)
6. [Replies](#replies)
7. [Editing & Deleting](#editing--deleting)
8. [Event System](#event-system)
9. [Advanced Patterns](#advanced-patterns)

## Basic Setup

```elixir
# Create socket with parent_pid for receiving events
# Events will be sent directly to the calling process
{:ok, socket_pid} = Amarula.Protocol.Socket.make_socket(config, parent_pid: self())

# Connect to WhatsApp
:ok = Amarula.Protocol.Socket.connect(socket_pid)

# Events will now be received as messages in your process:
# {:whatsapp, :qr, qr_data}
# {:whatsapp, :connection_update, update}
# {:whatsapp, :messages_upsert, data}
# etc.
```

### Alternative: Using Events GenServer for Pub/Sub

If you need multiple processes to receive events, you can use the optional Events GenServer:

```elixir
# Start the events manager
{:ok, events_pid} = Amarula.Protocol.Messages.Events.start_link()

# Subscribe to message events
Amarula.Protocol.Messages.Events.subscribe(events_pid, :messages_upsert)

# Receive events
receive do
  {:message_event, %{type: :messages_upsert, data: data}} ->
    # Process messages
    IO.inspect(data.messages)
end
```

## Sending Messages

### Simple Text Message

```elixir
alias Amarula.Protocol.Messages

# Send a simple text message
{:ok, message} = Messages.send_text(
  socket_pid,
  "1234567890@s.whatsapp.net",
  "Hello from Amarula!"
)

IO.inspect(message, label: "Sent message")
```

### Text with Mentions

```elixir
text = "Hello @John, welcome to the group!"

opts = %{
  context_info: %{
    mentioned_jid: ["9876543210@s.whatsapp.net"]
  }
}

{:ok, message} = Messages.send_text(
  socket,
  "group123@g.us",
  text,
  opts
)
```

### Message with Custom Options

```elixir
opts = %{
  message_id: "CUSTOM_ID_12345",
  timestamp: DateTime.utc_now(),
  ephemeral_expiration: 86400  # 24 hours
}

{:ok, message} = Messages.send_text(
  socket,
  "1234567890@s.whatsapp.net",
  "This message will disappear in 24 hours",
  opts
)
```

## Receiving Messages

### Process Single Message

```elixir
# Receive a binary node from WebSocket
receive do
  {:websocket_frame, node} ->
    case Messages.process_incoming_message(node) do
      {:ok, message} ->
        IO.puts("Received: #{message.message.text}")
        IO.puts("From: #{message.key.remote_jid}")
        IO.puts("ID: #{message.key.id}")
      
      {:error, reason} ->
        IO.puts("Failed to process message: #{inspect(reason)}")
    end
end
```

### Process Batch of Messages

```elixir
# Process multiple messages at once
nodes = [node1, node2, node3]

case Messages.process_messages_batch(nodes) do
  {:ok, messages} ->
    Enum.each(messages, fn msg ->
      IO.puts("Message: #{inspect(msg.message)}")
    end)
  
  {:error, reason} ->
    IO.puts("Batch processing failed: #{inspect(reason)}")
end
```

### Auto-respond to Messages

```elixir
# Messages are received automatically via parent_pid
# Listen for messages
receive do
  {:whatsapp, :messages_upsert, data} ->
    Enum.each(data.messages, fn message ->
      # Only respond to messages not from us
      unless message.key.from_me do
        text = message.message.text || ""
        from = message.key.remote_jid

        # Send auto-reply
        Messages.send_text(
          socket_pid,
          from,
          "Thanks for your message: '#{text}'"
        )
      end
    end)
end
```

## Media Messages

### Send an Image

```elixir
# Read image file
{:ok, image_data} = File.read("photos/vacation.jpg")

# Send with caption
opts = %{
  caption: "My summer vacation! 🌴",
  mime_type: "image/jpeg"
}

{:ok, message} = Messages.send_image(
  socket,
  "1234567890@s.whatsapp.net",
  image_data,
  opts
)
```

### Send a Video

```elixir
{:ok, video_data} = File.read("videos/funny_cat.mp4")

opts = %{
  caption: "Check out this funny cat video!",
  gif_playback: true  # Play as GIF
}

{:ok, message} = Messages.send_video(
  socket,
  "1234567890@s.whatsapp.net",
  video_data,
  opts
)
```

### Send Voice Note

```elixir
{:ok, audio_data} = File.read("voice/recording.ogg")

opts = %{
  ptt: true,  # Mark as Push-to-Talk (voice note)
  seconds: 15  # Duration in seconds
}

{:ok, message} = Messages.send_audio(
  socket,
  "1234567890@s.whatsapp.net",
  audio_data,
  opts
)
```

### Send Document

```elixir
{:ok, doc_data} = File.read("documents/report.pdf")

opts = %{
  file_name: "Monthly_Report_October.pdf",
  mime_type: "application/pdf",
  caption: "Here's the monthly report"
}

{:ok, message} = Messages.send_document(
  socket,
  "1234567890@s.whatsapp.net",
  doc_data,
  opts
)
```

### Download Media from Message

```elixir
# Receive a message with image
receive do
  {:whatsapp, :messages_upsert, data} ->
    Enum.each(data.messages, fn message ->
      case message.message do
        %{image: image_info} ->
          # Download the image
          case Messages.download_media(image_info) do
            {:ok, image_data} ->
              File.write("downloads/image_#{message.key.id}.jpg", image_data)
              IO.puts("Image downloaded successfully")

            {:error, reason} ->
              IO.puts("Download failed: #{inspect(reason)}")
          end

        _ ->
          :ok
      end
    end)
end
```

## Reactions

### Send a Reaction

```elixir
# React with a thumbs up
message_key = %{
  remote_jid: "1234567890@s.whatsapp.net",
  from_me: false,
  id: "MESSAGE_ID_123",
  participant: nil
}

{:ok, reaction} = Messages.send_reaction(
  socket,
  message_key,
  "👍"
)
```

### React to Received Message

```elixir
receive do
  {:whatsapp, :messages_upsert, data} ->
    Enum.each(data.messages, fn message ->
      # Auto-react to all messages with ❤️
      Messages.send_reaction(socket_pid, message.key, "❤️")
    end)
end
```

### Remove a Reaction

```elixir
# Remove your reaction (send empty emoji)
{:ok, _} = Messages.remove_reaction(socket, message_key)
```

### Listen for Reactions

```elixir
receive do
  {:whatsapp, :message_reaction, data} ->
    IO.puts("Reaction: #{data.reaction.text}")
    IO.puts("On message: #{data.key.id}")
end
```

## Replies

### Reply to a Message

```elixir
# Get the original message
receive do
  {:whatsapp, :messages_upsert, data} ->
    original_message = Enum.at(data.messages, 0)

    # Send a reply
    {:ok, reply} = Messages.send_reply(
      socket_pid,
      original_message,
      "Thanks for your message!"
    )

    IO.puts("Reply sent: #{reply.key.id}")
end
```

### Reply with Additional Options

```elixir
opts = %{
  context_info: %{
    mentioned_jid: ["9876543210@s.whatsapp.net"]
  }
}

{:ok, reply} = Messages.send_reply(
  socket,
  original_message,
  "Thanks @John!",
  opts
)
```

## Editing & Deleting

### Edit a Message

```elixir
# Send a message
{:ok, message} = Messages.send_text(
  socket,
  "1234567890@s.whatsapp.net",
  "Hello World"
)

# Wait a bit, then edit it
Process.sleep(2000)

# Check if we can edit
if Messages.can_edit?(message) do
  {:ok, edited} = Messages.edit_message(
    socket,
    message.key,
    "Hello World! (edited)"
  )
  
  IO.puts("Message edited successfully")
else
  IO.puts("Message is too old to edit (>15 minutes)")
end
```

### Delete Message for Self

```elixir
# Delete just for yourself
{:ok, _} = Messages.delete_message(
  socket,
  message.key,
  false  # for_everyone = false
)
```

### Delete Message for Everyone

```elixir
# Check if we can delete for everyone
if Messages.can_delete?(message, true) do
  {:ok, _} = Messages.delete_message(
    socket,
    message.key,
    true  # for_everyone = true
  )
  
  IO.puts("Message deleted for everyone")
else
  IO.puts("Cannot delete this message for everyone")
end
```

### Listen for Message Updates

```elixir
receive do
  {:whatsapp, :messages_update, updates} ->
    Enum.each(updates, fn update ->
      IO.puts("Message #{update.key.id} was updated")
      IO.inspect(update.update, label: "Changes")
    end)
end
```

## Event System

### Direct Event Reception (Recommended)

Events are automatically sent to the parent_pid specified when creating the socket:

```elixir
# Socket was created with parent_pid: self()
# All events come as {:whatsapp, event_type, data}

receive do
  {:whatsapp, :messages_upsert, data} ->
    IO.puts("New messages: #{length(data.messages)}")

  {:whatsapp, :messages_update, updates} ->
    IO.puts("Message updates: #{length(updates)}")

  {:whatsapp, :messages_delete, data} ->
    IO.puts("Messages deleted: #{length(data.keys)}")

  {:whatsapp, :message_reaction, data} ->
    IO.puts("Reaction: #{data.reaction.text}")

  {:whatsapp, :connection_update, update} ->
    IO.puts("Connection: #{update.connection}")

  {:whatsapp, :qr, qr_data} ->
    IO.puts("QR Code: #{qr_data.qr}")
end
```

### Using Events GenServer for Pub/Sub (Optional)

If you need multiple processes to receive the same events:

```elixir
# Start events manager
{:ok, events_pid} = Amarula.Protocol.Messages.Events.start_link()

# Subscribe to all message-related events
Amarula.Protocol.Messages.Events.subscribe(events_pid, :messages_upsert)
Amarula.Protocol.Messages.Events.subscribe(events_pid, :messages_update)
Amarula.Protocol.Messages.Events.subscribe(events_pid, :messages_delete)
Amarula.Protocol.Messages.Events.subscribe(events_pid, :message_reaction)
Amarula.Protocol.Messages.Events.subscribe(events_pid, :message_receipt)
```

### Event Handler Process (Using Direct Events)

```elixir
defmodule MyApp.MessageHandler do
  use GenServer

  alias Amarula.Protocol.Messages
  alias Amarula.Protocol.Socket

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl GenServer
  def init(config) do
    # Create socket with this process as parent
    {:ok, socket_pid} = Socket.make_socket(config, parent_pid: self())
    Socket.connect(socket_pid)

    {:ok, %{socket_pid: socket_pid}}
  end

  @impl GenServer
  def handle_info({:whatsapp, :messages_upsert, data}, state) do
    handle_new_messages(data, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:whatsapp, :message_reaction, data}, state) do
    handle_reaction(data, state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:whatsapp, :connection_update, update}, state) do
    IO.puts("Connection: #{update.connection}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:whatsapp, :qr, qr_data}, state) do
    IO.puts("QR Code: #{qr_data.qr}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp handle_new_messages(%{messages: messages}, state) do
    Enum.each(messages, fn message ->
      unless message.key.from_me do
        process_message(message, state.socket_pid)
      end
    end)
  end

  defp handle_reaction(%{key: key, reaction: reaction}, _state) do
    IO.puts("Got reaction #{reaction.text} on message #{key.id}")
  end

  defp process_message(message, socket_pid) do
    text = message.message.text || ""

    cond do
      String.starts_with?(text, "/help") ->
        Messages.send_text(socket_pid, message.key.remote_jid, "Available commands: /help, /about")

      String.starts_with?(text, "/about") ->
        Messages.send_text(socket_pid, message.key.remote_jid, "Amarula WhatsApp Bot v1.0")

      true ->
        # Echo the message
        Messages.send_text(socket_pid, message.key.remote_jid, "You said: #{text}")
    end
  end
end
```

### Unsubscribe from Events (When Using Events GenServer)

```elixir
# Only needed if using the optional Events GenServer
Amarula.Protocol.Messages.Events.unsubscribe(events_pid, :messages_upsert)
Amarula.Protocol.Messages.Events.unsubscribe(events_pid, :message_reaction)
```

## Advanced Patterns

### Message Queue with Rate Limiting

```elixir
defmodule MyApp.MessageQueue do
  use GenServer
  
  alias Amarula.Protocol.Messages
  
  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket, name: __MODULE__)
  end
  
  def enqueue(message) do
    GenServer.cast(__MODULE__, {:enqueue, message})
  end
  
  @impl GenServer
  def init(socket) do
    schedule_process_queue()
    {:ok, %{socket: socket, queue: :queue.new()}}
  end
  
  @impl GenServer
  def handle_cast({:enqueue, message}, state) do
    new_queue = :queue.in(message, state.queue)
    {:noreply, %{state | queue: new_queue}}
  end
  
  @impl GenServer
  def handle_info(:process_queue, state) do
    case :queue.out(state.queue) do
      {{:value, {jid, text}}, new_queue} ->
        Messages.send_text(state.socket, jid, text)
        schedule_process_queue()
        {:noreply, %{state | queue: new_queue}}
      
      {:empty, _queue} ->
        schedule_process_queue()
        {:noreply, state}
    end
  end
  
  defp schedule_process_queue do
    # Process one message per second
    Process.send_after(self(), :process_queue, 1000)
  end
end
```

### Broadcast to Multiple Chats

```elixir
defmodule MyApp.Broadcast do
  alias Amarula.Protocol.Messages
  
  def broadcast(socket, jids, text) do
    Task.async_stream(
      jids,
      fn jid ->
        Messages.send_text(socket, jid, text)
      end,
      timeout: :infinity,
      max_concurrency: 5
    )
    |> Enum.to_list()
  end
end

# Usage
jids = [
  "1111111111@s.whatsapp.net",
  "2222222222@s.whatsapp.net",
  "3333333333@s.whatsapp.net"
]

MyApp.Broadcast.broadcast(socket, jids, "Broadcast message to all!")
```

### Message Logger

```elixir
defmodule MyApp.MessageLogger do
  use GenServer
  
  alias Amarula.Protocol.Messages
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end
  
  @impl GenServer
  def init(_) do
    # Note: You need to pass this PID as parent_pid when creating the socket
    # Or use the Events GenServer for pub/sub
    {:ok, %{messages: []}}
  end

  @impl GenServer
  def handle_info({:whatsapp, :messages_upsert, data}, state) do
    # Log all messages to file
    Enum.each(data.messages, fn message ->
      log_entry = %{
        id: message.key.id,
        from: message.key.remote_jid,
        text: message.message.text,
        timestamp: message.message_timestamp
      }
      
      File.write!(
        "message_log.json",
        Jason.encode!(log_entry) <> "\n",
        [:append]
      )
    end)
    
    {:noreply, state}
  end
end
```

### Auto-responder with Cooldown

```elixir
defmodule MyApp.AutoResponder do
  use GenServer
  
  alias Amarula.Protocol.Messages
  
  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket, name: __MODULE__)
  end
  
  @impl GenServer
  def init(socket_pid) do
    {:ok, %{socket_pid: socket_pid, cooldowns: %{}}}
  end

  @impl GenServer
  def handle_info({:whatsapp, :messages_upsert, data}, state) do
    new_state = Enum.reduce(data.messages, state, fn message, acc_state ->
      unless message.key.from_me do
        handle_auto_response(message, acc_state)
      else
        acc_state
      end
    end)
    
    {:noreply, new_state}
  end
  
  defp handle_auto_response(message, state) do
    jid = message.key.remote_jid
    now = System.system_time(:second)
    
    case Map.get(state.cooldowns, jid) do
      nil ->
        # First message, send response
        send_response(message, state.socket)
        put_in(state.cooldowns[jid], now)
      
      last_response when now - last_response > 300 ->
        # More than 5 minutes passed, send response
        send_response(message, state.socket)
        put_in(state.cooldowns[jid], now)
      
      _ ->
        # Still in cooldown
        state
    end
  end
  
  defp send_response(message, socket_pid) do
    Messages.send_text(
      socket_pid,
      message.key.remote_jid,
      "Thanks for your message! I'll get back to you soon."
    )
  end
end

# Usage
{:ok, socket_pid} = Socket.make_socket(config, parent_pid: auto_responder_pid)
{:ok, auto_responder_pid} = MyApp.AutoResponder.start_link(socket_pid)
```

## Testing Examples

```elixir
defmodule MyApp.MessagesTest do
  use ExUnit.Case, async: true
  
  alias Amarula.Protocol.Messages
  
  describe "send_text/4" do
    test "sends a text message" do
      socket = start_test_socket()
      jid = "1234567890@s.whatsapp.net"
      text = "Test message"
      
      assert {:ok, message} = Messages.send_text(socket, jid, text)
      assert message.message.text == text
      assert message.key.remote_jid == jid
      assert message.key.from_me == true
    end
  end
  
  describe "event system" do
    test "receives events via parent_pid" do
      config = build_test_config()
      {:ok, socket_pid} = Socket.make_socket(config, parent_pid: self())

      # Simulate receiving a message
      simulate_incoming_message(socket_pid)

      assert_receive {:whatsapp, :messages_upsert, data}, 1000
      assert is_list(data.messages)
    end
  end
end
```

---

These examples demonstrate the full capabilities of the Amarula Messages module. For more information, see the [README](README.md) and [ARCHITECTURE](ARCHITECTURE.md) documents.

