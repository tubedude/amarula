defmodule Amarula.Protocol.Socket do
  @moduledoc """
  Internal per-connection GenServer: drives one account's pairing/login, sends
  through the ConversationSender pipe, and forwards Connection events to
  the instance's `parent_pid`.

  Not the public entry point — use the `Amarula` facade, which delegates here.
  """

  use GenServer
  require Logger

  alias Amarula.Connection
  alias Amarula.Protocol.Socket.{Types, ConnectionSupervisor}
  alias Amarula.Protocol.Messages.{ConversationSender, Media, MessageEncoder}
  alias Amarula.Protocol.Proto

  defstruct [
    :instance_id,
    :connection_manager,
    :conn,
    :config,
    :connection_state,
    :parent_pid
  ]

  @type t :: %__MODULE__{
          instance_id: reference() | nil,
          connection_manager: pid() | nil,
          conn: Amarula.Conn.t() | nil,
          config: Types.socket_config(),
          connection_state: Types.connection_state(),
          parent_pid: pid() | nil
        }

  # A send blocks the caller until the per-recipient sender finishes (up to three
  # IQ round-trips for a new recipient). The client-side call timeout must exceed
  # that worst case — see ConversationSender's own bound.
  @send_call_timeout 90_000

  # Client API

  @doc """
  Creates a new WhatsApp socket.

  Options:
  - `:name` - Optional name for the GenServer (default: `__MODULE__`)
  - `:parent_pid` - Optional parent PID to send events to (default: calling process)
  """
  def make_socket(%Amarula.Conn{} = conn, opts \\ []) do
    # Start the per-connection supervision tree and hand back the Socket child
    # pid, so the public API (connect/send_text/... on this pid) is unchanged.
    case ConnectionSupervisor.start_instance(conn, opts) do
      {:ok, _sup, socket_pid} -> {:ok, socket_pid}
      {:error, _} = err -> err
    end
  end

  @doc false
  # Started by ConnectionSupervisor with the resolved instance context.
  def start_link(%{name: name} = init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: name)
  end

  @doc """
  Connects to WhatsApp WebSocket server.
  """
  def connect(pid \\ __MODULE__) do
    GenServer.call(pid, :connect)
  end

  @doc """
  Disconnects from WhatsApp WebSocket server.
  """
  def disconnect(pid \\ __MODULE__) do
    GenServer.call(pid, :disconnect)
  end

  @doc """
  Gets the current connection state.
  """
  def get_connection_state(pid \\ __MODULE__) do
    GenServer.call(pid, :get_connection_state)
  end

  @doc """
  Send a 1:1 text message to `jid`. Encrypts and relays (fetching the
  recipient's prekey bundle first if we have no session). Returns `{:ok, msg_id}`.
  """
  def send_text(pid \\ __MODULE__, jid, text) do
    GenServer.call(pid, {:send_text, jid, text}, @send_call_timeout)
  end

  @doc "Set global presence (`:available`/`:unavailable`)."
  def set_presence(pid \\ __MODULE__, type) do
    GenServer.call(pid, {:set_presence, type})
  end

  @doc "Send a chat-state to `jid` (`:composing`/`:recording`/`:paused`)."
  def send_chatstate(pid \\ __MODULE__, jid, type) do
    GenServer.call(pid, {:send_chatstate, jid, type})
  end

  @doc "Subscribe to a contact's presence."
  def presence_subscribe(pid \\ __MODULE__, jid) do
    GenServer.call(pid, {:presence_subscribe, jid})
  end

  @doc "Send a read receipt for `message_ids` in chat `jid` (optional `participant`)."
  def mark_read(pid \\ __MODULE__, message_ids, jid, participant \\ nil) do
    GenServer.call(pid, {:mark_read, message_ids, jid, participant})
  end

  @doc "Fetch a group's metadata (`%Amarula.Group{}`). `group` is an Address or jid."
  def group_metadata(pid \\ __MODULE__, group) do
    GenServer.call(pid, {:group_metadata, group})
  end

  @doc "Fetch all groups we participate in (`[%Amarula.Group{}]`)."
  def list_groups(pid \\ __MODULE__) do
    GenServer.call(pid, :list_groups, 30_000)
  end

  @doc """
  Run a group management op. `iq` is a `%Node{}` from `Amarula.Protocol.Groups.Ops`,
  `transform` runs on the reply. The `Amarula` group_* functions build both.
  """
  def group_op(pid \\ __MODULE__, iq, transform) do
    GenServer.call(pid, {:group_op, iq, transform}, 30_000)
  end

  @doc "Log out: unlink this companion server-side + wipe local storage + disconnect."
  def logout(pid \\ __MODULE__) do
    GenServer.call(pid, :logout)
  end

  @doc """
  Send a pre-built `%Proto.Message{}` to `jid` (1:1 or group). Used for
  reactions, edits, deletes and media. Returns `{:ok, msg_id}`.
  """
  def send_message(pid \\ __MODULE__, jid, %Proto.Message{} = message) do
    GenServer.call(pid, {:send_message, jid, message}, @send_call_timeout)
  end

  @doc "Ask the phone to re-deliver a message by key (PEER_DATA_OPERATION resend)."
  def request_resend(pid \\ __MODULE__, %Proto.MessageKey{} = message_key) do
    GenServer.call(pid, {:request_resend, message_key}, @send_call_timeout)
  end

  @doc """
  Send a poll to `jid`. Returns `{:ok, msg_id, message_secret}` — keep the secret
  to tally incoming votes. `opts`: `:selectable`, `:announcement`, `:message_secret`.
  """
  def send_poll(pid \\ __MODULE__, jid, name, options, opts \\ []) do
    GenServer.call(pid, {:send_poll, jid, name, options, opts}, @send_call_timeout)
  end

  @doc "Send a contact (`display_name` + vCard string) to `jid`."
  def send_contact(pid \\ __MODULE__, jid, display_name, vcard) do
    send_message(pid, jid, MessageEncoder.contact(display_name, vcard))
  end

  @doc "Send multiple contacts: `pairs` is `[{display_name, vcard}, ...]`."
  def send_contacts(pid \\ __MODULE__, jid, display_name, pairs) do
    send_message(pid, jid, MessageEncoder.contacts(display_name, pairs))
  end

  @doc "Send a location to `jid`. `opts`: `:name`, `:address`, `:url`, `:is_live`."
  def send_location(pid \\ __MODULE__, jid, lat, lng, opts \\ []) do
    send_message(pid, jid, MessageEncoder.location(lat, lng, opts))
  end

  @doc """
  React to a message with `emoji` (pass "" to remove the reaction). `target_key`
  is the `%Proto.MessageKey{}` of the message being reacted to (from a received
  message's key). The reaction is sent to `target_key.remoteJid`.
  """
  def send_reaction(pid \\ __MODULE__, %Proto.MessageKey{remoteJid: jid} = target_key, emoji) do
    send_message(pid, jid, MessageEncoder.reaction(target_key, emoji))
  end

  @doc """
  Delete a message for everyone (revoke). `target_key` is the `%Proto.MessageKey{}`
  of the message to delete; it's removed for all participants in `remoteJid`.
  """
  def send_revoke(pid \\ __MODULE__, %Proto.MessageKey{remoteJid: jid} = target_key) do
    send_message(pid, jid, MessageEncoder.revoke(target_key))
  end

  @doc """
  Edit a previously-sent message, replacing its text with `new_text`. `target_key`
  is the `%Proto.MessageKey{}` of the message to edit (must be one we sent).
  """
  def send_edit(pid \\ __MODULE__, %Proto.MessageKey{remoteJid: jid} = target_key, new_text) do
    send_message(pid, jid, MessageEncoder.edit(target_key, new_text))
  end

  @media_default_mimetype %{
    image: "image/jpeg",
    video: "video/mp4",
    audio: "audio/ogg; codecs=opus",
    document: "application/octet-stream",
    sticker: "image/webp"
  }

  @doc """
  Send a media message to `jid`. `type` is `:image`/`:video`/`:audio`/
  `:document`/`:sticker`; `data` is the raw bytes. `opts` may carry `:mimetype`
  plus per-type extras (`:caption`, `:width`, `:height`, `:seconds`, `:ptt`,
  `:file_name`, `:title`). Encrypts + uploads + sends. `{:ok, msg_id}` or `{:error, _}`.
  """
  def send_media(pid \\ __MODULE__, type, jid, data, opts \\ [])
      when type in [:image, :video, :audio, :document, :sticker] and is_binary(data) do
    GenServer.call(pid, {:send_media, type, jid, data, opts}, @send_call_timeout)
  end

  @doc "Convenience: `send_media(:image, ...)`."
  def send_image(pid \\ __MODULE__, jid, data, opts \\ []) when is_binary(data) do
    send_media(pid, :image, jid, data, opts)
  end

  # GenServer callbacks

  @impl GenServer
  def init(%{instance_id: instance_id, conn: conn, parent_pid: parent_pid}) do
    config = conn.config

    # Siblings are already started (Socket is the last child of the
    # ConnectionSupervisor); resolve the Connection by role from the
    # per-instance Registry.
    connection_manager = ConnectionSupervisor.whereis(instance_id, :connection_manager)

    # Forward the high-level connection events Connection emits.
    for topic <- [
          :connection_update,
          :error,
          :pairing_success,
          :messages_upsert,
          :retry_send,
          :chats_update,
          :contacts_update,
          :group_update,
          :receipt_update,
          :blocklist_update,
          :history_sync
        ] do
      Connection.subscribe(connection_manager, topic, self())
    end

    state = %__MODULE__{
      instance_id: instance_id,
      connection_manager: connection_manager,
      conn: conn,
      config: config,
      connection_state: :disconnected,
      parent_pid: parent_pid
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:connect, _from, state) do
    case state.connection_state do
      :connected ->
        {:reply, :ok, state}

      _ ->
        # Start connection process
        case Connection.connect(state.connection_manager) do
          :ok ->
            {:reply, :ok, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl GenServer
  def handle_call(:disconnect, _from, state) do
    case Connection.disconnect(state.connection_manager) do
      :ok ->
        new_state = %{state | connection_state: :disconnected}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_connection_state, _from, state) do
    {:reply, state.connection_state, state}
  end

  @impl GenServer
  def handle_call({:send_text, jid, text}, from, state) do
    deliver_async(state, jid, %{text: text}, from)
  end

  @impl GenServer
  def handle_call({:set_presence, type}, _from, state) do
    {:reply, Connection.set_presence(state.connection_manager, type), state}
  end

  @impl GenServer
  def handle_call({:send_chatstate, jid, type}, _from, state) do
    jid = Amarula.Address.to_wire(jid)
    {:reply, Connection.send_chatstate(state.connection_manager, jid, type), state}
  end

  @impl GenServer
  def handle_call({:presence_subscribe, jid}, _from, state) do
    jid = Amarula.Address.to_wire(jid)
    {:reply, Connection.presence_subscribe(state.connection_manager, jid), state}
  end

  @impl GenServer
  def handle_call({:mark_read, message_ids, jid, participant}, _from, state) do
    jid = Amarula.Address.to_wire(jid)
    participant = participant && Amarula.Address.to_wire(participant)

    {:reply, Connection.mark_read(state.connection_manager, message_ids, jid, participant), state}
  end

  @impl GenServer
  def handle_call({:group_metadata, group}, _from, state) do
    jid = Amarula.Address.to_wire(group)
    {:reply, Connection.group_metadata(state.connection_manager, jid), state}
  end

  @impl GenServer
  def handle_call({:group_op, iq, transform}, _from, state) do
    {:reply, Connection.group_op(state.connection_manager, iq, transform), state}
  end

  def handle_call(:list_groups, _from, state) do
    {:reply, Connection.list_groups(state.connection_manager), state}
  end

  @impl GenServer
  def handle_call(:logout, _from, state) do
    reply = Connection.logout(state.connection_manager)
    {:reply, reply, %{state | connection_state: :disconnected}}
  end

  @impl GenServer
  def handle_call({:send_message, jid, message}, from, state) do
    deliver_async(state, jid, %{message: message}, from)
  end

  def handle_call({:request_resend, message_key}, from, state) do
    creds = Connection.get_auth_creds(state.connection_manager)
    me_id = get_in(creds, [:me, :id])

    if me_id do
      pdo = MessageEncoder.placeholder_resend_request(message_key)
      # A PEER_DATA_OPERATION request is sent to OURSELVES (own devices) with the
      # peer category + high push priority, so the phone re-delivers the original.
      payload = %{
        message: pdo,
        stanza_attrs: %{"category" => "peer", "push_priority" => "high_force"}
      }

      deliver_async(state, me_id, payload, from)
    else
      {:reply, {:error, :not_authenticated}, state}
    end
  end

  @impl GenServer
  def handle_call({:send_poll, jid, name, options, opts}, from, state) do
    {message, secret} = MessageEncoder.poll(name, options, opts)

    # Poll's reply carries the secret: {:ok, id} → {:ok, id, secret}.
    shape = fn
      :ok, msg_id -> {:ok, msg_id, secret}
      result, msg_id -> default_send_reply(result, msg_id)
    end

    deliver_async(state, jid, %{message: message}, from, shape)
  end

  @impl GenServer
  def handle_call({:send_media, type, jid, data, opts}, from, state) do
    mimetype = Keyword.get(opts, :mimetype, @media_default_mimetype[type])

    # Media encrypt+upload happen on Socket (blocking) — they're independent of the
    # recipient session; the per-recipient send is then dispatched async.
    with {:ok, enc} <- Media.encrypt(data, type),
         {:ok, uploaded} <-
           Media.upload(state.connection_manager, enc.enc, enc.file_enc_sha256, type) do
      info = Map.merge(enc, Map.put(uploaded, :mimetype, mimetype))
      deliver_async(state, jid, %{message: MessageEncoder.media(type, info, opts)}, from)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info({:connection_event, {:connection_update, update}}, state) do
    Logger.info("Connection update: #{inspect(update)}")

    # Updates are partial (Baileys semantics): :connection may be absent,
    # e.g. %{received_pending_notifications: true}.
    connection = Map.get(update, :connection)

    new_state =
      if connection, do: %{state | connection_state: connection}, else: state

    # Emit connection update to subscribers
    emit_event(new_state, :connection_update, update)

    # Handle specific connection states
    case connection do
      :connected ->
        handle_connected_state(new_state)

      :disconnected ->
        handle_disconnected_state(new_state)

      _ ->
        :ok
    end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:connection_event, {:error, error}}, state) do
    # Error already logged by Connection, just emit event
    emit_event(state, :error, error)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:connection_event, {:messages_upsert, data}}, state) do
    emit_event(state, :messages_upsert, data)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:connection_event, {topic, data}}, state)
      when topic in [
             :chats_update,
             :contacts_update,
             :group_update,
             :receipt_update,
             :blocklist_update,
             :history_sync
           ] do
    emit_event(state, topic, data)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:connection_event,
         {:retry_send, %{recipient_jid: jid, msg_id: msg_id, message: message}}},
        state
      ) do
    # Re-encrypt + resend the original message (same id, so the recipient replaces
    # rather than duplicates). Fresh ConversationSender pass picks up the session
    # the retry's <keys> bundle just injected.
    # Fire-and-forget resend (no caller waiting → from = nil).
    deliver_async(state, jid, %{msg_id: msg_id, message: message}, nil)
  end

  @impl GenServer
  def handle_info({:connection_event, {:pairing_success, data}}, state) do
    emit_event(state, :pairing_success, data)

    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("Socket terminating: #{inspect(reason)}")

    # Clean up services
    if state.connection_manager do
      Connection.disconnect(state.connection_manager)
    end
  end

  # Private functions

  defp handle_connected_state(state) do
    Logger.info("Socket connected to WhatsApp")

    # Start initial queries if configured
    if state.config.fire_init_queries do
      # TODO: Implement initial queries
      :ok
    end

    # Send presence update if configured
    if state.config.mark_online_on_connect do
      # TODO: Implement presence update
      :ok
    end
  end

  defp handle_disconnected_state(_state) do
    Logger.info("Socket disconnected from WhatsApp")

    # Clear any pending operations
    :ok
  end

  defp generate_message_id do
    "3EB0" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :upper))
  end

  # Dispatch a message to the per-recipient ConversationSender and DON'T block:
  # the caller's `from` is forwarded so the sender replies directly when the send
  # finishes. Socket returns `{:noreply, state}` and is immediately free for other
  # sends (to other recipients, in parallel). The caller still blocks on its own
  # GenServer.call until the sender answers.
  #
  # `from` nil = fire-and-forget (a retry resend, no caller waiting). `shape` maps
  # the raw send result to the caller's reply (default: {:ok, msg_id}/{:error,..}).
  defp deliver_async(state, target, payload, from, shape \\ &default_send_reply/2) do
    jid = Amarula.Address.to_wire(target)
    msg_id = Map.get(payload, :msg_id) || generate_message_id()
    # The sender applies `shape.(result, msg_id)` to build the caller's reply.
    reply_shape = &shape.(&1, msg_id)

    opts = [
      registry: ConnectionSupervisor.registry_name(state.instance_id),
      supervisor: ConnectionSupervisor.whereis(state.instance_id, :sender_supervisor),
      cm: state.connection_manager,
      conn: state.conn,
      creds: Connection.get_auth_creds(state.connection_manager),
      recipient_jid: jid
    ]

    msg =
      payload
      |> Map.put(:msg_id, msg_id)
      |> Map.put(:reply_to, from)
      |> Map.put(:reply_shape, reply_shape)

    :ok = ConversationSender.deliver(opts, msg)
    {:noreply, state}
  end

  defp default_send_reply(:ok, msg_id), do: {:ok, msg_id}
  defp default_send_reply({:error, reason}, _msg_id), do: {:error, reason}
  defp default_send_reply({:halted, reason}, _msg_id), do: {:error, {:halted, reason}}

  defp emit_event(state, event_type, data) do
    send(state.parent_pid, {:whatsapp, event_type, data})
  end
end
