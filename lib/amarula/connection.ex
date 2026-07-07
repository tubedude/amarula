defmodule Amarula.Connection do
  @moduledoc """
  The per-connection process that owns the entire server conversation: the
  `WebSocketClient`, the noise cipher (frame encode/decode + counters), IQ
  correlation, login/handshake, send dispatch, and server-notification handling.

  It is also the **consumer's endpoint** — the pid `Amarula.connect/2` returns.
  Consumer calls (`connect`, `send_text`, `group_*`, …) land here directly, and
  consumer events go straight to the connection's `parent_pid` as
  `{:amarula, type, data}` (no relay process, no subscriber registry).

  Per-send work stays tiny: Connection only frames + writes + correlates (acks,
  IQ replies). The heavy USync/bundle waits and Signal encrypt run on the
  per-recipient `ConversationSender`, which hands back a ready stanza to relay.
  """

  use GenServer
  require Logger

  alias Amarula.Protocol.Socket.{Types, WebSocketClient, ConnectionSupervisor}
  alias Amarula.Protocol.{Crypto.NoiseHandler, Auth.AuthUtils, Socket.ConnectionValidator}
  alias Amarula.Protocol.Auth.{DeviceIdentity, CompanionReg}
  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.ProfileRegistry
  alias Amarula.Protocol.Socket.{IQ, Login, Router}
  alias Amarula.Protocol.Binary.{Decoder, JID, NodeUtils, Encoder, Node}
  alias Amarula.Protocol.Messages.{ConversationSender, Media, MessageEncoder}
  alias Amarula.Protocol.Messages.{HistorySync, MessageDecryptor}
  alias Amarula.Protocol.Presence
  alias Amarula.Protocol.Call
  alias Amarula.Protocol.Signal.DecryptError

  # A send blocks the caller until the per-recipient sender finishes (up to three
  # IQ round-trips for a new recipient). The client-side call timeout must exceed
  # that worst case — see ConversationSender's own bound.
  @send_call_timeout 90_000

  @media_default_mimetype %{
    image: "image/jpeg",
    video: "video/mp4",
    audio: "audio/ogg; codecs=opus",
    document: "application/octet-stream",
    sticker: "image/webp"
  }

  # Baileys NACK_REASONS (decode-wa-message.ts). Only 500 (unhandled) is used — a
  # decrypt we can't recover from, retried once then nacked. Duplicates are receipted
  # as delivered (see the duplicate_decrypt_error? branch), not nacked; WhatsApp's
  # accurate code for that case would be 496 (SignalErrorOldCounter), noted there.
  @nack_unhandled_error 500
  # Baileys maxMsgRetryCount default — cap on retry-resends per message.
  @max_msg_retry_count 5

  # How long to wait for an IQ reply before failing the waiting caller.
  @iq_timeout_ms 20_000

  # The <ack> wait (default 30s, config :ack_timeout_ms) lives on
  # Connection.AckLifecycle now; @send_call_timeout must still exceed it.
  alias Amarula.Protocol.Crypto.Constants
  alias Amarula.Protocol.Proto

  alias Amarula.Protocol.Signal.{PreKeys, SessionInjector, SessionStore, DeviceListCache}
  alias Amarula.Protocol.Signal.LidMappingFileStore
  alias Amarula.Protocol.Messages.Receipt
  alias Amarula.Protocol.Groups.Notification, as: GroupNotification
  alias Amarula.Connection.{SendOps, GroupOps, PreKeyOps, Pairing, Notifications, Receive}
  alias Amarula.Connection.{AppStateOps, AckLifecycle}

  defstruct [
    :websocket_client,
    :websocket_monitor,
    :conn,
    :config,
    :connection_state,
    :retry_count,
    :max_retries,
    :retry_delay,
    :retry_timer,
    :parent_pid,
    :parent_monitor,
    :instance_id,
    :connection_timeout_timer,
    :last_error,
    :auth_creds,
    :handshake_state,
    :noise_state,
    :keep_alive_timer,
    :last_recv_time,
    :message_counter,
    :message_tag_prefix,
    :message_epoch,
    :waiting_for_server_response,
    :server_response_timeout_timer,
    :qr_refs,
    :qr_timer,
    pending_iqs: %{},
    msg_retry_counts: %{},
    pending_sends: %{},
    pending_acks: %{},
    sender_monitors: %{}
  ]

  @typedoc """
  The consumer event sink — where `{:amarula, type, data}` events are delivered.

  A raw `pid()` is the simplest form, but it is **not restart-safe**: if the
  consumer process restarts under a new pid, a pid sink points at a corpse (only
  `set_parent/2` recovers it). Any name `GenServer.whereis/1` resolves — a
  registered atom, a `{:via, mod, term}` tuple (e.g. `Amarula.via(profile)` of
  *another* registry), or a `{name, node}` for a remote consumer — re-resolves to
  the current holder on every event, so it survives the consumer's restart and
  even this `Connection`'s own restart automatically. `nil` drops events.
  """
  @type sink :: pid() | atom() | {:via, module(), term()} | {atom(), node()} | nil

  @type t :: %__MODULE__{
          websocket_client: pid() | nil,
          websocket_monitor: reference() | nil,
          config: Types.socket_config(),
          connection_state: Types.connection_state(),
          retry_count: non_neg_integer(),
          max_retries: non_neg_integer(),
          retry_delay: non_neg_integer(),
          retry_timer: reference() | nil,
          parent_pid: sink(),
          parent_monitor: reference() | nil,
          instance_id: reference() | nil,
          connection_timeout_timer: reference() | nil,
          last_error: term() | nil,
          auth_creds: AuthUtils.auth_creds() | nil,
          handshake_state: ConnectionValidator.handshake_state() | nil,
          noise_state: NoiseHandler.noise_state() | nil,
          keep_alive_timer: reference() | nil,
          last_recv_time: non_neg_integer() | nil,
          message_counter: non_neg_integer(),
          message_tag_prefix: String.t(),
          message_epoch: non_neg_integer(),
          waiting_for_server_response: boolean(),
          server_response_timeout_timer: reference() | nil,
          qr_refs: [String.t()],
          qr_timer: reference() | nil,
          pending_iqs: %{String.t() => {atom(), reference()}},
          msg_retry_counts: %{String.t() => non_neg_integer()},
          pending_sends: %{
            String.t() => %{
              msg_id: String.t(),
              text: String.t(),
              target_jid: String.t(),
              devices: [map()]
            }
          },
          # Sends awaiting the server's <ack class="message" id=msg_id>. Each entry
          # holds the consumer's `from` (parked until the ack), the reply-shaping
          # fun applied on a successful ack, the ack-timeout timer, and the
          # recipient jid (so a sender :DOWN can fail all of that recipient's
          # parked sends at once).
          pending_acks: %{
            String.t() => {GenServer.from(), (:ok -> term()), reference(), String.t()}
          },
          # One monitor per recipient with a live sender holding parked sends.
          # On the sender's :DOWN we fail every pending_acks entry for that jid.
          sender_monitors: %{String.t() => reference()}
        }

  # Client API

  @doc """
  **Internal.** Starts the bare Connection process only.

  This starts *just* this GenServer — **not** a working connection. A functional
  connection needs the surrounding per-connection tree (its sender supervisor and
  the `InstanceRegistry` wiring its siblings resolve through); without that, the
  first send fails. `ConnectionSupervisor` calls this as the tree's child.

  Consumers must **not** put `{Amarula.Connection, …}` in their own supervisor —
  that yields a half-wired connection. The supported entry point is
  `Amarula.connect/2`, which builds the whole tree (and owns the protocol-driven
  restarts — e.g. the 515 reconnect after QR pairing — that the consumer should
  not have to manage). To control *naming/distribution*, pass a `:registry` in the
  connection config (e.g. `Horde.Registry`); see `Amarula.ProfileRegistry`.

  `opts`:
    * `:name`       — registered name (a `:via` tuple into `InstanceRegistry`,
      passed by `ConnectionSupervisor`). Omit to start an unnamed process.
    * `:parent_pid` — process to receive `{:amarula, type, data}` events
  """
  def start_link(conn, opts \\ []) do
    init_arg = %{
      conn: conn,
      parent_pid: Keyword.get(opts, :parent_pid),
      instance_id: Keyword.get(opts, :instance_id)
    }

    GenServer.start_link(__MODULE__, init_arg, name: Keyword.get(opts, :name))
  end

  @doc false
  # Internal: used by ConnectionSupervisor to start Connection as a tree child.
  # NOT a consumer "supervise-it-yourself" hook — a bare Connection is non-functional
  # (see start_link/2). Use Amarula.connect/2.
  def child_spec({conn, opts}) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [conn, opts]}}
  end

  @doc """
  Start a connection instance and return its pid — the consumer's handle. Starts
  the per-connection supervision tree (Registry, caches, sender supervisor, this
  Connection) and hands back the Connection child pid, so the public API
  (`connect/send_text/...` on that pid) lands here directly.

  `opts` may carry `:parent_pid` (events sink, default the caller).
  """
  @spec make_socket(Amarula.Conn.t(), keyword()) ::
          {:ok, pid()} | {:error, {:already_running, pid()}} | {:error, term()}
  def make_socket(%Amarula.Conn{} = conn, opts \\ []) do
    # One connection per profile. The profile registration in `init` is the atomic
    # guard (closes the start race); this lookup is a fast-path for the common
    # case so we don't spin up a tree only to tear it down.
    case ProfileRegistry.whereis(conn, conn.profile) do
      pid when is_pid(pid) ->
        {:error, {:already_running, pid}}

      nil ->
        start_instance(conn, opts)
    end
  end

  defp start_instance(conn, opts) do
    case ConnectionSupervisor.start_instance(conn, opts) do
      {:ok, _sup, conn_pid} ->
        {:ok, conn_pid}

      {:error, reason} ->
        # `init` stops with {:already_registered, winner} when it loses the
        # profile-registration race; the Supervisor wraps that in
        # {:shutdown, {:failed_to_start_child, Connection, reason}}. Unwrap it to
        # the same {:already_running, winner} the fast-path returns.
        case already_running_reason(reason) do
          {:already_running, _pid} = mapped -> {:error, mapped}
          nil -> {:error, reason}
        end
    end
  end

  defp already_running_reason({:shutdown, {:failed_to_start_child, _child, inner}}),
    do: already_running_reason(inner)

  defp already_running_reason({:already_registered, pid}), do: {:already_running, pid}
  defp already_running_reason(_), do: nil

  # LID → PN canonicalization. Non-LID jids and unmapped LIDs pass through.
  defp do_canonical_jid(conn, jid) do
    with true <- JID.lid_user?(jid),
         pn_user when is_binary(pn_user) <- LidMappingFileStore.pn_for_lid(conn, jid),
         %{} = decoded <- JID.decode(jid) do
      device = Map.get(decoded, :device, 0) || 0
      JID.encode(%{user: pn_user, server: "s.whatsapp.net", device: device})
    else
      _ -> jid
    end
  end

  @doc """
  Connects to the WebSocket server.
  """
  def connect(pid) do
    GenServer.call(pid, :connect)
  end

  @doc """
  Disconnects from the WebSocket server.
  """
  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  @doc """
  Stop the whole connection tree (this Connection, its caches + sender supervisor),
  freeing the profile registration. Unlike `disconnect/1` (which only closes the
  websocket, leaving the supervised tree up to reconnect), this releases the profile
  so it can be started again elsewhere. Returns `:ok | {:error, :not_found}`.
  """
  @spec stop(pid()) :: :ok | {:error, :not_found}
  def stop(pid) do
    case GenServer.call(pid, :instance_id) do
      nil -> {:error, :not_found}
      instance_id -> ConnectionSupervisor.stop_instance(instance_id)
    end
  end

  @doc """
  Gets the current connection state.
  """
  def get_connection_state(pid) do
    GenServer.call(pid, :get_connection_state)
  end

  @doc """
  Re-point the consumer event sink to `sink` (a `t:sink/0` — pid, registered name,
  `{:via, …}`, `{name, node}`, or `nil`) on a live connection, without bouncing the
  websocket. The old sink is demonitored and the new one monitored.

  This is the recovery path when the process that called `connect/2` restarts while
  the connection survives: the new consumer re-attaches instead of forcing a
  stop+reconnect. For a sink that should survive *both* the consumer's and this
  connection's restarts, pass a name rather than a raw pid (see `t:sink/0`).
  """
  @spec set_parent(GenServer.server(), sink()) :: :ok
  def set_parent(pid, sink) do
    GenServer.call(pid, {:set_parent, sink})
  end

  @doc """
  Canonicalize `jid` to its phone-number identity. If `jid` is a LID
  (`<n>@lid`) with a stored PN mapping, returns the equivalent
  `<pn>@s.whatsapp.net` (preserving any device). Any other jid — already a PN,
  a group, or a LID with no known mapping — is returned unchanged.

  This is the public entry point to the LID↔PN mapping the library maintains
  internally; consumers no longer need to reach into `Protocol.Signal.*`.
  """
  @spec canonical_jid(GenServer.server(), String.t()) :: String.t()
  def canonical_jid(pid, jid) when is_binary(jid) do
    GenServer.call(pid, {:canonical_jid, jid})
  end

  @doc """
  Whether `msg` is a message in our **own** chat (the "Message Yourself" chat) — i.e.
  it's `from_me` and addressed `to` our own account.

  This is the check a self-chat command channel needs (drive an agent by messaging
  yourself), and it handles the LID/PN duality for you: WhatsApp may address the self
  chat by either our PN (`me.id`, always present) or our LID (`me.lid`, present once the
  server has sent it), so it matches `msg.to` against **both** of our own identities
  (device ignored) rather than forcing a single normalized form.

  On a **single connection** there is no feedback loop: a reply this connection sends to
  the self chat is delivered to our *other* devices but not back to us (the send path
  excludes our own sending device), so you don't need to filter your own sends. Only when
  running **two connections on the same account** do their self-chat sends reach each
  other — dedupe those cross-connection by the `msg_id` from the send.
  """
  @spec own_chat?(GenServer.server(), Amarula.Msg.t()) :: boolean()
  def own_chat?(pid, %Amarula.Msg{} = msg) do
    GenServer.call(pid, {:own_chat?, msg})
  end

  @doc """
  The connection's `%Amarula.Conn{}` — its storage scope + profile. Library code
  that needs to read/write the Storage seam (sessions, LID mappings) from the
  *caller's* process holds the pid; this hands it the `%Conn{}` those stores key
  by. Internal: consumers use the higher-level facade calls.
  """
  @spec get_conn(GenServer.server()) :: Amarula.Conn.t()
  def get_conn(pid), do: GenServer.call(pid, :conn)

  @doc """
  Send an IQ and block until the matching websocket reply arrives.

  Returns `{:ok, node}` on a `type="result"` reply, `{:error, node}` on an
  error reply, or `{:error, :timeout}` if no reply comes within the IQ timeout.
  The caller (a `ConversationSender`) blocks; Connection keeps owning the
  socket and just routes the reply back. This is the only correlation primitive
  the send path needs — no continuation logic lives here.
  """
  @spec query_iq(GenServer.server(), Amarula.Protocol.Binary.Node.t(), timeout()) ::
          {:ok, Amarula.Protocol.Binary.Node.t()}
          | {:error, Amarula.Protocol.Binary.Node.t() | :timeout | :not_connected}
  def query_iq(pid, node, timeout \\ 25_000) do
    GenServer.call(pid, {:query_iq, node}, timeout)
  end

  @doc """
  Frame and send a stanza over the websocket (fire-and-forget; no IQ reply
  awaited). Used by the send path to relay the final `<message>`.
  """
  @spec relay_stanza(GenServer.server(), Amarula.Protocol.Binary.Node.t()) ::
          :ok | {:error, :not_connected}
  def relay_stanza(pid, node) do
    GenServer.call(pid, {:relay_stanza, node})
  end

  @doc "Cast a request to force-refresh sessions for newly mapped LIDs."
  @spec assert_lid_sessions(GenServer.server(), [String.t()]) :: :ok
  def assert_lid_sessions(_pid, []), do: :ok
  def assert_lid_sessions(pid, lids), do: GenServer.cast(pid, {:assert_lid_sessions, lids})

  @doc """
  Cast newly-learned LID↔PN pairs so the consumer gets a `:lid_mapping_update`
  event. `pairs` is `[{lid_jid, pn_jid}, ...]`.
  """
  @spec notify_lid_mappings(GenServer.server(), [{String.t(), String.t()}]) :: :ok
  def notify_lid_mappings(_pid, []), do: :ok
  def notify_lid_mappings(pid, pairs), do: GenServer.cast(pid, {:notify_lid_mappings, pairs})

  @doc "Send global presence (`:available`/`:unavailable`). Needs `me.name`."
  @spec set_presence(GenServer.server(), :available | :unavailable) :: :ok | {:error, term()}
  def set_presence(pid, type), do: GenServer.call(pid, {:set_presence, type})

  @doc "Send a chat-state to `jid` (`:composing`/`:recording`/`:paused`)."
  @spec send_chatstate(GenServer.server(), Amarula.jid(), :composing | :recording | :paused) ::
          :ok | {:error, :not_connected}
  def send_chatstate(pid, jid, type),
    do: GenServer.call(pid, {:send_chatstate, jid, type})

  @doc """
  Request a link-code (phone-number) pairing code for `phone` (digits only,
  E.164 without `+`).

  Call this during the QR window while unregistered (on the first
  `:connection_update` carrying a `qr`). Returns `{:ok, code}` with an 8-char
  code the user types into WhatsApp → Linked Devices → "Link with phone number".
  The server later pushes a `link_code_companion_reg` notification, which we
  finish internally; the usual 515 restart then logs in.

  Pass `custom_code: "ABCD2345"` to use a fixed 8-char code instead of a random
  one.
  """
  @spec request_pairing_code(GenServer.server(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def request_pairing_code(pid, phone, opts \\ []) do
    digits = String.replace(phone, ~r/\D/, "")
    GenServer.call(pid, {:request_pairing_code, digits, Keyword.get(opts, :custom_code)})
  end

  @doc "Subscribe to a contact's presence."
  @spec presence_subscribe(GenServer.server(), Amarula.jid()) :: :ok | {:error, :not_connected}
  def presence_subscribe(pid, jid),
    do: GenServer.call(pid, {:presence_subscribe, jid})

  @doc "Send a read receipt for `message_ids` in chat `jid` (optional `participant`)."
  @spec mark_read(GenServer.server(), Amarula.jid(), [String.t(), ...], Amarula.jid() | nil) ::
          :ok | {:error, :not_connected}
  def mark_read(pid, jid, message_ids, participant \\ nil),
    do: GenServer.call(pid, {:mark_read, jid, message_ids, participant})

  @doc "Fetch one group's metadata. `group` is an `Address` or the `@g.us` jid string."
  @spec group_metadata(GenServer.server(), Amarula.jid()) ::
          {:ok, Amarula.Group.t()} | {:error, term()}
  def group_metadata(pid, group), do: GenServer.call(pid, {:group_metadata, group})

  @doc "Fetch all groups we participate in."
  @spec list_groups(GenServer.server()) :: {:ok, [Amarula.Group.t()]} | {:error, term()}
  def list_groups(pid), do: GenServer.call(pid, :list_groups, 30_000)

  @doc """
  Run a group management op: send the IQ `Groups.Ops.<builder>` produced and run
  `transform` on the reply. `transform` is `fn {:ok, node} | {:error, node} ->
  result end`. Used by the `Amarula` group_* API.
  """
  @spec group_op(GenServer.server(), Node.t(), (term() -> term())) :: term()
  def group_op(pid, %Node{} = iq, transform),
    do: GenServer.call(pid, {:group_op, iq, transform}, 30_000)

  @doc "Unlink this companion server-side, wipe ALL local storage, then disconnect. Destructive."
  @spec wipe_credentials(GenServer.server()) :: :ok | {:error, term()}
  def wipe_credentials(pid), do: GenServer.call(pid, :wipe_credentials)

  @doc """
  Send a 1:1/group text message to `jid`. Encrypts and relays (fetching the
  recipient's prekey bundle first if we have no session). Returns `{:ok, msg_id}`.
  """
  def send_text(pid, jid, text, opts \\ []) do
    GenServer.call(pid, {:send_text, jid, text, opts}, @send_call_timeout)
  end

  @doc """
  Send a pre-built `%Proto.Message{}` to `jid` (1:1 or group). Used for
  reactions, edits, deletes and media. Returns `{:ok, msg_id}`.
  """
  def send_message(pid, jid, %Proto.Message{} = message) do
    GenServer.call(pid, {:send_message, jid, message}, @send_call_timeout)
  end

  @doc "Ask the phone to re-deliver a message by key (PEER_DATA_OPERATION resend)."
  def request_resend(pid, %Proto.MessageKey{} = message_key) do
    GenServer.call(pid, {:request_resend, message_key}, @send_call_timeout)
  end

  @doc "Ask the phone for older history of a chat (PEER_DATA_OPERATION on-demand)."
  def fetch_history(pid, %Proto.MessageKey{} = oldest_key, oldest_ts, count) do
    GenServer.call(pid, {:fetch_history, oldest_key, oldest_ts, count}, @send_call_timeout)
  end

  @doc """
  Send a poll to `jid`. Returns `{:ok, msg_id, message_secret}` — keep the secret
  to tally incoming votes. `opts`: `:selectable`, `:announcement`, `:message_secret`.
  """
  def send_poll(pid, jid, name, options, opts \\ []) do
    GenServer.call(pid, {:send_poll, jid, name, options, opts}, @send_call_timeout)
  end

  @doc "Send a contact (`display_name` + vCard string) to `jid`."
  def send_contact(pid, jid, display_name, vcard) do
    send_message(pid, jid, MessageEncoder.contact(display_name, vcard))
  end

  @doc "Send multiple contacts: `pairs` is `[{display_name, vcard}, ...]`."
  def send_contacts(pid, jid, display_name, pairs) do
    send_message(pid, jid, MessageEncoder.contacts(display_name, pairs))
  end

  @doc "Send a location to `jid`. `opts`: `:name`, `:address`, `:url`, `:is_live`."
  def send_location(pid, jid, lat, lng, opts \\ []) do
    send_message(pid, jid, MessageEncoder.location(lat, lng, opts))
  end

  @doc """
  React to a message with `emoji` (pass "" to remove the reaction). `target_key`
  is the `%Proto.MessageKey{}` of the message being reacted to.
  """
  def send_reaction(pid, %Proto.MessageKey{remoteJid: jid} = target_key, emoji) do
    send_message(pid, jid, MessageEncoder.reaction(target_key, emoji))
  end

  @doc "Delete a message for everyone (revoke). `target_key` is its `%Proto.MessageKey{}`."
  def send_revoke(pid, %Proto.MessageKey{remoteJid: jid} = target_key) do
    send_message(pid, jid, MessageEncoder.revoke(target_key))
  end

  @doc "Edit a previously-sent message, replacing its text with `new_text`."
  def send_edit(pid, %Proto.MessageKey{remoteJid: jid} = target_key, new_text) do
    send_message(pid, jid, MessageEncoder.edit(target_key, new_text))
  end

  @doc """
  Send a media message to `jid`. `type` is `:image`/`:video`/`:audio`/
  `:document`/`:sticker`; `data` is the raw bytes. `opts` may carry `:mimetype`
  plus per-type extras. Encrypts + uploads + sends. `{:ok, msg_id}` or `{:error, _}`.
  """
  def send_media(pid, jid, type, data, opts \\ [])
      when type in [:image, :video, :audio, :document, :sticker] and is_binary(data) do
    GenServer.call(pid, {:send_media, jid, type, data, opts}, @send_call_timeout)
  end

  @doc "Convenience: `send_media(pid, jid, :image, ...)`."
  def send_image(pid, jid, data, opts \\ []) when is_binary(data) do
    send_media(pid, jid, :image, data, opts)
  end

  @doc """
  Updates authentication credentials.

  Called when credentials are updated (e.g., after successful pairing).
  """
  def update_auth_creds(pid, new_creds) do
    GenServer.call(pid, {:update_auth_creds, new_creds})
  end

  @doc "Current auth creds (carries me.id/me.lid/account once logged in)."
  def get_auth_creds(pid), do: GenServer.call(pid, :get_auth_creds)

  # GenServer callbacks

  @impl GenServer
  def init(%{conn: arg, parent_pid: parent_pid, instance_id: instance_id}) do
    # Accept a built %Conn{} (the normal path) or a bare config map (tests start
    # Connection directly). Either way, carry the conn (for steps/scopes)
    # and config (for protocol settings via state.config.*). `parent_pid` is the
    # consumer's event sink — `{:amarula, type, data}` go straight there;
    # `instance_id` addresses the per-connection Registry + sender supervisor.
    conn = normalize_conn(arg)
    config = conn.config

    # Resolve auth credentials, in precedence order:
    #   1. an explicit config[:auth] (tests / advanced callers that manage creds);
    #   2. the profile's stored creds (the normal path — Amarula owns persistence
    #      via the Storage seam, so the consumer only names a :profile);
    #   3. freshly generated creds (first run → triggers QR pairing).
    auth_creds = resolve_auth_creds(conn, config)

    state = %__MODULE__{
      websocket_client: nil,
      conn: conn,
      config: config,
      # Honour a connection_state override from config (used by tests to start in
      # :connected without a real handshake); defaults to :disconnected.
      connection_state: Map.get(config, :connection_state, :disconnected),
      retry_count: 0,
      max_retries: config.max_retries || 5,
      retry_delay: config.retry_delay || 1000,
      retry_timer: nil,
      parent_pid: parent_pid,
      # Watch the sink so a dead consumer is observable (telemetry) instead of a
      # silent send into the void; a raw-pid sink is also cleared on its :DOWN.
      parent_monitor: monitor_sink(parent_pid),
      instance_id: instance_id,
      connection_timeout_timer: nil,
      last_error: nil,
      auth_creds: auth_creds,
      handshake_state: nil,
      noise_state: nil,
      keep_alive_timer: nil,
      last_recv_time: nil,
      message_counter: 0,
      message_tag_prefix: generate_message_tag_prefix(),
      message_epoch: 1,
      waiting_for_server_response: false,
      server_response_timeout_timer: nil,
      qr_refs: [],
      qr_timer: nil
    }

    # Own the retry cache's local resource (the ETS table, for the default
    # adapter) here, so it is owned by *this* process: it dies with the Connection
    # and is recreated empty on restart — a poisoned cached value can never
    # outlive the crash it triggers. A no-op for adapters with no process-owned
    # resource (DETS, Redis).
    :ok = Amarula.RetryCache.ensure_local(conn.retry_cache, conn.profile)

    # Register under the profile in the app-level registry (the one-per-profile
    # guard + the consumer's restart-safe handle). On a restart this re-registers
    # the same key, so a profile ref keeps resolving to the (new) pid. A clashing
    # registration means another connection for this profile is already live: stop
    # so the tree unwinds and `make_socket` reports {:already_running, winner}.
    {module, name} = ProfileRegistry.resolve(conn)

    case module.register(name, conn.profile, nil) do
      {:ok, _} ->
        {:ok, state}

      {:error, {:already_registered, pid}} ->
        {:stop, {:already_registered, pid}}
    end
  end

  @impl GenServer
  def handle_call(:connect, _from, state) do
    case state.connection_state do
      :connected ->
        {:reply, :ok, state}

      _ ->
        new_state = attempt_connection(state)
        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call(:instance_id, _from, state) do
    {:reply, state.instance_id, state}
  end

  @impl GenServer
  def handle_call({:set_parent, sink}, _from, state) do
    {:reply, :ok, install_sink(state, sink)}
  end

  @impl GenServer
  def handle_call({:canonical_jid, jid}, _from, state) do
    {:reply, do_canonical_jid(state.conn, jid), state}
  end

  @impl GenServer
  def handle_call(
        {:own_chat?, %Amarula.Msg{from_me: true, to: %Amarula.Address{} = to}},
        _from,
        state
      ) do
    {:reply, own_account?(state, to), state}
  end

  def handle_call({:own_chat?, %Amarula.Msg{}}, _from, state) do
    {:reply, false, state}
  end

  @impl GenServer
  def handle_call(:conn, _from, state) do
    {:reply, state.conn, state}
  end

  @impl GenServer
  def handle_call(:disconnect, _from, state) do
    new_state = disconnect_websocket(state)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_connection_state, _from, state) do
    {:reply, state.connection_state, state}
  end

  @impl GenServer
  def handle_call(:get_auth_creds, _from, state) do
    {:reply, state.auth_creds, state}
  end

  # Blocking IQ: stamp + send, then defer the reply (hold `from` under the id)
  # until the matching websocket frame arrives in handle_iq_response.
  @impl GenServer
  def handle_call({:query_iq, node}, from, state) do
    if ready_to_send?(state) do
      {state, id, node} = stamp_iq(state, node)
      timer = Process.send_after(self(), {:iq_timeout, id}, @iq_timeout_ms)
      state = %{state | pending_iqs: IQ.wait(state.pending_iqs, id, from, timer, nil)}
      {:noreply, send_binary_node(state, node)}
    else
      # Don't park a caller behind a frame that can never go out — fail fast.
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:relay_stanza, node}, _from, state) do
    send_reply(state, node)
  end

  @impl GenServer
  def handle_call(:wipe_credentials, _from, state) do
    # Destructive: forget the profile entirely. Unlink this companion server-side
    # (the phone drops the device), wipe all local storage, then disconnect.
    state = send_remove_companion(state)
    result = Amarula.Storage.clear(scope(state), profile(state))

    Logger.info(
      "Wiped credentials for #{inspect(profile(state))}: companion removed, storage #{inspect(result)}"
    )

    {:reply, result, disconnect_websocket(state)}
  end

  @impl GenServer
  def handle_call({:group_metadata, group}, from, state) do
    {iq, transform} = GroupOps.metadata(Amarula.Address.to_jid!(group))
    {:noreply, send_waiter_iq(state, iq, from, transform)}
  end

  @impl GenServer
  def handle_call(:list_groups, from, state) do
    {iq, transform} = GroupOps.list()
    {:noreply, send_waiter_iq(state, iq, from, transform)}
  end

  @impl GenServer
  def handle_call({:group_op, iq, transform}, from, state) do
    {:noreply, send_waiter_iq(state, iq, from, transform)}
  end

  @impl GenServer
  def handle_call({:set_presence, type}, _from, state) do
    case Presence.presence(type, me(state)) do
      {:ok, node} -> send_reply(state, node)
      {:error, _} = err -> {:reply, err, state}
    end
  end

  @impl GenServer
  def handle_call({:send_chatstate, jid, type}, _from, state) do
    node = Presence.chatstate(type, Amarula.Address.to_jid!(jid), me(state))
    send_reply(state, node)
  end

  @impl GenServer
  def handle_call({:request_pairing_code, phone, custom_code}, _from, state) do
    case build_pairing_code(custom_code) do
      {:ok, code} ->
        state = start_link_code_pairing(state, phone, code)
        {:reply, {:ok, code}, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl GenServer
  def handle_call({:presence_subscribe, jid}, _from, state) do
    node =
      Presence.subscribe(
        Amarula.Address.to_jid!(jid),
        generate_message_tag(state)
      )

    send_reply(state, node)
  end

  @impl GenServer
  def handle_call({:mark_read, jid, message_ids, participant}, _from, state) do
    jid = Amarula.Address.to_jid!(jid)
    participant = participant && Amarula.Address.to_jid!(participant)
    node = Amarula.Protocol.Receipt.read(message_ids, jid, participant)
    send_reply(state, node)
  end

  # --- Send path (folded from the former Socket facade) ---

  @impl GenServer
  def handle_call({:send_text, jid, text, opts}, from, state) do
    dispatch_send(state, SendOps.text(jid, text, opts), from)
  end

  @impl GenServer
  def handle_call({:send_message, jid, message}, from, state) do
    dispatch_send(state, SendOps.message(jid, message), from)
  end

  @impl GenServer
  def handle_call({:request_resend, message_key}, from, state) do
    with_me_id(state, from, fn me_id ->
      SendOps.request_resend(me_id, message_key)
    end)
  end

  @impl GenServer
  def handle_call({:fetch_history, oldest_key, oldest_ts, count}, from, state) do
    with_me_id(state, from, fn me_id ->
      SendOps.fetch_history(me_id, oldest_key, oldest_ts, count)
    end)
  end

  @impl GenServer
  def handle_call({:send_poll, jid, name, options, opts}, from, state) do
    dispatch_send(state, SendOps.poll(jid, name, options, opts), from)
  end

  @impl GenServer
  def handle_call({:send_media, jid, type, data, opts}, from, state) do
    mimetype = Keyword.get(opts, :mimetype, @media_default_mimetype[type])
    conn_pid = self()

    # Media encrypt+upload are heavy and themselves round-trip through Connection
    # (the media_conn IQ) — running them inline would block (and deadlock on the
    # self-call). Do them in a Task so Connection stays responsive to that IQ; the
    # Task hands the ready media message back via {:send_media_ready, ...}, where
    # the normal async dispatch (forwarding the caller's `from`) takes over. On a
    # failure the Task replies the error to `from` directly.
    Task.start(fn ->
      # `from` must always get an answer — a raise here would otherwise leave the
      # caller hanging for the full send-call timeout.
      try do
        with {:ok, enc} <- Media.encrypt(data, type),
             {:ok, uploaded} <- Media.upload(conn_pid, enc.enc, enc.file_enc_sha256, type) do
          info = Map.merge(enc, Map.put(uploaded, :mimetype, mimetype))
          message = MessageEncoder.media(type, info, opts)
          send(conn_pid, {:send_media_ready, jid, message, from})
        else
          {:error, reason} -> GenServer.reply(from, {:error, reason})
        end
      rescue
        e -> GenServer.reply(from, {:error, {:media_prepare_failed, e}})
      end
    end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:update_auth_creds, new_creds}, _from, state) do
    Logger.info("Updating authentication credentials")
    {:reply, :ok, update_creds(state, new_creds)}
  end

  # Catch-all: an unexpected call must not crash the whole per-connection tree.
  @impl GenServer
  def handle_call(request, _from, state) do
    Logger.warning("Unexpected call: #{inspect(request)}")
    {:reply, {:error, :unknown_request}, state}
  end

  # Reaction to "a brand-new LID mapping was learned" (cast from
  # store_lid_mappings). Force-refresh Signal sessions for those LIDs — Baileys
  # assertSessions(lids, force=true) — by fetching fresh prekey bundles
  # (reason="identity") and injecting them. Decoupled from the send that learned
  # the mapping.
  @impl GenServer
  def handle_cast({:assert_lid_sessions, lids}, state) do
    Logger.debug("Force-refreshing sessions for #{length(lids)} newly mapped LID(s)")
    {:noreply, force_refresh_sessions(state, lids)}
  end

  @impl GenServer
  def handle_cast({:notify_lid_mappings, pairs}, state) do
    mappings =
      Enum.map(pairs, fn {lid, pn} ->
        %{lid: Amarula.Address.parse(lid), pn: Amarula.Address.parse(pn)}
      end)

    emit_to_subscribers(state, :lid_mapping_update, mappings)
    {:noreply, state}
  end

  # Ignore events from a websocket we've already replaced (e.g. after a 515
  # restart) — a dying socket emits close events from both handle_disconnect
  # and terminate, which must not trigger reconnects for the new socket.
  @impl GenServer
  def handle_info({:ws_event, ws_pid, event}, %{websocket_client: current} = state)
      when ws_pid != current do
    Logger.debug(
      "Ignoring #{inspect(elem(event, 0))} event from stale websocket #{inspect(ws_pid)}"
    )

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:history_sync_result, result}, state) do
    Logger.debug(
      "history sync (#{inspect(result.sync_type)}): #{length(result.chats)} chats, " <>
        "#{length(result.contacts)} contacts"
    )

    if result.chats != [], do: emit_to_subscribers(state, :chats_update, result.chats)
    if result.contacts != [], do: emit_to_subscribers(state, :contacts_update, result.contacts)
    emit_to_subscribers(state, :history_sync, result)
    {:noreply, learn_own_push_name(state, Map.get(result, :push_names, []))}
  end

  def handle_info({:ws_event, _ws_pid, {:open, _data}}, state) do
    Logger.debug("WebSocket connected - initiating handshake")

    # Build the ClientHello (pure) then send it + transition (CM owns the socket).
    case Login.client_hello(state.auth_creds, state.config) do
      {:ok, frame, handshake_state} ->
        case WebSocketClient.send_data(state.websocket_client, frame) do
          :ok ->
            Logger.debug("ClientHello sent (#{byte_size(frame)} bytes)")
            emit_connection_update(state, :connecting)
            {:noreply, %{state | handshake_state: handshake_state}}

          {:error, reason} ->
            Logger.error("Failed to send ClientHello: #{inspect(reason)}")
            {:noreply, handle_connection_error(state, reason)}
        end

      {:error, reason} ->
        Logger.error("Failed to generate ClientHello: #{inspect(reason)}")
        {:noreply, handle_connection_error(state, reason)}
    end
  end

  @impl GenServer
  def handle_info({:ws_event, _ws_pid, {:close, data}}, state) do
    Logger.debug("WebSocket connection closed: #{inspect(data)}")

    # Drop the pid so further events from this socket are ignored as stale.
    # Count the close toward backoff/give-up like the error path does.
    new_state = %{
      state
      | connection_state: :disconnected,
        websocket_client: nil,
        retry_count: state.retry_count + 1
    }

    # Emit connection update event
    emit_connection_update(new_state, :disconnected)

    # Attempt reconnection if not manually disconnected
    new_state =
      if new_state.retry_count < new_state.max_retries do
        schedule_reconnect(new_state)
      else
        Logger.error("Max retry attempts reached, giving up")
        updated = %{new_state | connection_state: :closed}
        emit_connection_update(updated, :closed)
        updated
      end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:ws_event, _ws_pid, {:error, error}}, state) do
    Logger.error("WebSocket error: #{inspect(error)}")

    new_state = handle_connection_error(state, error)
    {:noreply, new_state}
  end

  # WebSocket control frames must be handled first - they're protocol-level and shouldn't be decrypted
  # Most specific pattern: control frame close (0x88)
  @impl GenServer
  def handle_info({:ws_event, _ws_pid, {:frame, <<136, _::binary>>}}, state) do
    Logger.warning("Received WebSocket close frame (0x88) - server closing connection")
    # This is a protocol-level close, not an application message
    # Let WebSocket client handle the close event
    {:noreply, state}
  end

  # Most specific pattern: control frame pong (0x8A)
  @impl GenServer
  def handle_info({:ws_event, _ws_pid, {:frame, <<138, _::binary>>}}, state) do
    Logger.debug("Received WebSocket pong frame")
    {:noreply, %{state | last_recv_time: System.monotonic_time(:millisecond)}}
  end

  # Handshake frames - most specific state pattern: connecting with no handshake state
  @impl GenServer
  def handle_info(
        {:ws_event, _ws_pid, {:frame, _data}},
        %{connection_state: :connecting, handshake_state: nil} = state
      ) do
    Logger.warning("Received frame during handshake but no handshake state")
    {:noreply, state}
  end

  # Handshake frames - specific state pattern: connecting with handshake state
  @impl GenServer
  def handle_info(
        {:ws_event, _ws_pid, {:frame, data}},
        %{connection_state: :connecting, handshake_state: handshake_state} = state
      ) do
    with {:ok, finish_frame, final_noise} <- Login.server_hello(handshake_state, data),
         :ok <- WebSocketClient.send_data(state.websocket_client, finish_frame) do
      Logger.debug("ClientFinish sent (#{byte_size(finish_frame)} bytes)")
      complete_handshake(state, final_noise)
    else
      {:error, reason} ->
        Logger.error("Handshake frame processing failed: #{inspect(reason)}")
        {:noreply, handle_connection_error(state, reason)}
    end
  end

  # Connected frames - specific state pattern: connected but no noise state
  @impl GenServer
  def handle_info(
        {:ws_event, _ws_pid, {:frame, _data}},
        %{connection_state: :connected, noise_state: nil} = state
      ) do
    Logger.warning("Received frame but no noise state available")
    {:noreply, state}
  end

  # Connected frames - specific state pattern: connected with noise state (application frames)
  @impl GenServer
  def handle_info(
        {:ws_event, _ws_pid, {:frame, data}},
        %{connection_state: :connected, noise_state: noise_state} = state
      ) do
    # Application frame - decode with noise. decode_and_emit_frame always returns
    # {:ok, _} (NoiseHandler.decode_frame never errors; a real node-handling bug
    # crashes the socket so the supervisor restores clean crypto state).
    {:ok, updated_state} = decode_and_emit_frame(noise_state, data, state)
    {:noreply, %{updated_state | last_recv_time: System.monotonic_time(:millisecond)}}
  end

  # Catch-all: a frame arriving in an unexpected state (not connecting/connected).
  # Nothing consumes raw frames upstream, so just drop it with a warning.
  @impl GenServer
  def handle_info({:ws_event, _ws_pid, {:frame, _data}}, state) do
    Logger.warning(
      "Dropping frame received in unexpected state #{inspect(state.connection_state)}"
    )

    {:noreply, state}
  end

  # Test seam: inject an already-decoded server node straight into the routing
  # path, skipping noise decode. Mirrors what decode_and_emit_frame does per
  # frame. Used by Connection's own tests and by `Amarula.Testing` (the public
  # consumer test-support API) to feed synthetic inbound messages.
  @impl GenServer
  def handle_info({:inject_node, node}, state) do
    {:noreply, process_server_node(state, node)}
  end

  # The media encrypt+upload Task finished; dispatch the ready media message to
  # the recipient's ConversationSender, forwarding the original caller's `from`.
  @impl GenServer
  def handle_info({:send_media_ready, jid, message, from}, state) do
    dispatch_send(state, SendOps.media(jid, message), from)
  end

  @impl GenServer
  def handle_info(:next_qr, state) do
    {:noreply, emit_next_qr(state)}
  end

  @impl GenServer
  def handle_info(:reconnect, state) do
    new_state = attempt_connection(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:connection_timeout, state) do
    Logger.error("Connection timeout")

    new_state = handle_connection_error(state, :timeout)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:handshake_timeout, state) do
    Logger.error("Handshake timeout")

    new_state = handle_connection_error(state, :handshake_timeout)
    {:noreply, new_state}
  end

  # Handle server response timeout
  @impl GenServer
  def handle_info(:server_response_timeout, state) do
    if state.waiting_for_server_response do
      Logger.warning("Server response timeout - no response received after passive IQ")
      new_state = handle_connection_error(state, :server_response_timeout)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # A tracked IQ (prekey count/upload) never got a result — run its error path
  @impl GenServer
  def handle_info({:iq_timeout, id}, state) do
    {:noreply, handle_iq_timeout(state, id)}
  end

  # --- Ack-on-send: the per-recipient Sender reports its pipe result back here;
  # the consumer's `from` was parked under msg_id at dispatch.
  #
  # On SUCCESS the Sender reports nothing: the parked entry + ack-timeout armed at
  # dispatch already handle it — the consumer is replied when the server's <ack>
  # arrives (or on the ack-timeout). Only failure needs a message:

  # The pipe failed before any frame went out (not_on_whatsapp, IQ timeout,
  # encrypt error, plugin halt). No ack will ever come, so reply the parked caller
  # the failure directly (bypassing the ack-success shape) and drop the entry.
  @impl GenServer
  def handle_info({:send_failed, msg_id, reason}, state) do
    {:noreply, resolve_ack(state, msg_id, fn _shape -> {:error, reason} end)}
  end

  # The send was relayed but the server never confirmed it within the timeout.
  # Report it honestly as unconfirmed.
  @impl GenServer
  def handle_info({:ack_timeout, msg_id}, state) do
    emit_ack_outcome(state, msg_id, :timeout)
    {:noreply, resolve_ack(state, msg_id, fn _shape -> {:error, :ack_timeout} end)}
  end

  # The consumer event sink went down. Emit telemetry so the loss is observable
  # (the whole point of monitoring it) rather than events vanishing silently. A
  # name/via sink stays put — it re-resolves to the consumer's next pid on its own
  # via `emit_event`, and we re-arm the monitor against whoever holds it now (nil
  # if no one yet). A raw-pid sink can't come back, so it's cleared; a later
  # `set_parent/2` re-attaches it.
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{parent_monitor: ref} = state) do
    Amarula.Telemetry.emit([:amarula, :sink, :down], profile(state), %{count: 1}, %{
      reason: reason,
      sink: state.parent_pid
    })

    Logger.info("Consumer event sink #{inspect(state.parent_pid)} went down (#{inspect(reason)})")

    new_sink = if is_pid(state.parent_pid), do: nil, else: state.parent_pid
    {:noreply, install_sink(%{state | parent_monitor: nil}, new_sink)}
  end

  # The WebSockex client process died. We unlink + monitor it (see
  # attempt_connection/1) so a server-initiated close — WebSockex exits
  # {:remote, :closed}, a non-normal exit — can't signal-kill Connection before we
  # reconnect. On the normal close path handle_disconnect already sent
  # {:ws_event, {:close}} (which ran first and nil'd websocket_client + scheduled
  # the reconnect), so here websocket_client no longer matches `pid` and we just
  # let the monitor lapse. If it DOES still match, the client crashed hard without
  # a close — drive the reconnect ourselves.
  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, reason}, %{websocket_monitor: ref} = state) do
    state = %{state | websocket_monitor: nil}

    if state.websocket_client == pid do
      Logger.warning("WebSocket client died (#{inspect(reason)}) with no close — reconnecting")
      {:noreply, handle_connection_error(%{state | websocket_client: nil}, reason)}
    else
      Logger.debug("WebSocket client #{inspect(pid)} down (#{inspect(reason)}) — already handled")
      {:noreply, state}
    end
  end

  # A per-recipient Sender died. If it crashed mid-pipe it never reported
  # {:send_failed,...}, so its parked sends would otherwise hang to :ack_timeout
  # (and be mislabeled). Fail them now, fast and correctly. A :normal exit is the
  # idle-stop of a sender with no in-flight sends — just drop the (already empty)
  # monitor. An unknown ref isn't ours — ignore.
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case AckLifecycle.pop_monitor_by_ref(state, ref) do
      {nil, state} ->
        {:noreply, state}

      {_jid, state} when reason == :normal ->
        {:noreply, state}

      {jid, state} ->
        emit_sender_crashed(state, jid)
        {:noreply, AckLifecycle.fail_recipient_sends(state, jid, reason)}
    end
  end

  # Handle keep-alive messages
  # This matches Baileys startKeepAliveRequest() behavior exactly
  @impl GenServer
  def handle_info(:send_keep_alive, state) do
    # Self-heal the sink monitor off the existing heartbeat: a name sink that was
    # unheld when attached (or when its holder last died) delivers via per-event
    # re-resolution but carries no monitor, so a later death would emit no
    # `:sink, :down`. Re-arm here once the name resolves — no new timer, no polling
    # loop, just the keep-alive we already run. No-op unless a sink needs it.
    state = rearm_sink_if_needed(state)

    # Initialize last_recv_time if not set (shouldn't happen, but safety check)
    last_recv = state.last_recv_time || System.monotonic_time(:millisecond)

    # Check if it's been a suspicious amount of time since server responded
    # This could indicate the network is down
    time_diff = System.monotonic_time(:millisecond) - last_recv
    keep_alive_interval = state.config.keep_alive_interval_ms || 30_000

    if time_diff > keep_alive_interval + 5000 do
      # Connection lost - close connection
      Logger.error("Connection was lost - no response for #{time_diff}ms")
      new_state = handle_connection_error(state, :connection_lost)
      {:noreply, new_state}
    else
      # Connection is alive - send WA XML ping
      # Send pings even during pairing phase (matches Baileys behavior)
      case state.connection_state do
        :connected ->
          new_state = send_ping_message(state)
          # Schedule next ping
          timer = Process.send_after(self(), :send_keep_alive, keep_alive_interval)
          {:noreply, %{new_state | keep_alive_timer: timer}}

        _ ->
          Logger.warning(
            "Keep alive called when connection not open (state: #{state.connection_state})"
          )

          {:noreply, state}
      end
    end
  end

  # Catch-all: this process owns a socket and is long-lived — an unexpected
  # message must not crash the whole per-connection tree.
  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("Ignoring unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("Connection manager terminating: #{inspect(reason)}")

    # Clean up timers
    for timer <- [
          state.retry_timer,
          state.connection_timeout_timer,
          state.keep_alive_timer,
          state.qr_timer,
          state.server_response_timeout_timer
        ],
        timer,
        do: Process.cancel_timer(timer)

    # Disconnect WebSocket
    if state.websocket_client do
      WebSocketClient.close(state.websocket_client)
    end
  end

  # Private functions

  defp attempt_connection(state) do
    Logger.debug("Attempting WebSocket connection (attempt #{state.retry_count + 1})")

    # A re-entrant connect (e.g. :connect while still :connecting) must not
    # orphan the previous client — tear it down before starting a new one.
    state = if state.websocket_client, do: disconnect_websocket(state), else: state

    new_state = %{state | connection_state: :connecting}

    # Start connection timeout timer
    timeout_timer =
      Process.send_after(self(), :connection_timeout, state.config.connect_timeout_ms)

    new_state = %{new_state | connection_timeout_timer: timeout_timer}

    # Emit connecting event
    emit_connection_update(new_state, :connecting)

    # Start WebSocket client with parent_pid for direct message passing
    websocket_opts = [
      parent_pid: self(),
      url: state.config.wa_websocket_url,
      connect_timeout_ms: state.config.connect_timeout_ms,
      keep_alive_interval_ms: state.config.keep_alive_interval_ms,
      headers: state.config.headers || %{},
      origin: state.config.origin || "https://web.whatsapp.com",
      agent: state.config.agent
    ]

    case WebSocketClient.start_link(websocket_opts) do
      {:ok, websocket_pid} ->
        # WebSocketClient.start_link LINKS the client to us. Swap that for a
        # monitor: a server close makes WebSockex exit {:remote, :closed} (a
        # non-normal exit) — linked, that signal-killed Connection before the
        # {:ws_event, {:close}} it sends could drive the reconnect, and the
        # supervisor-restarted Connection never reconnects (init only registers),
        # so the account got stuck :disconnected. As a monitor, the death arrives
        # as a {:DOWN} we handle. terminate/2 still closes the client, so dropping
        # the link doesn't orphan it. (Unlinking only the websocket keeps
        # Connection's own parent/supervisor behaviour unchanged — unlike
        # trap_exit, which would also tie us to the parent's lifecycle.)
        new_state = demonitor_websocket(new_state)
        Process.unlink(websocket_pid)
        ref = Process.monitor(websocket_pid)

        # Store websocket_pid and wait for :open event to initiate handshake.
        # retry_count is NOT reset here — the socket process starting says nothing
        # about the connection succeeding; finish_login resets it, so an
        # accept-then-drop server still backs off and eventually gives up.
        %{
          new_state
          | websocket_client: websocket_pid,
            websocket_monitor: ref,
            connection_state: :connecting,
            last_error: nil
        }

      {:error, reason} ->
        Logger.error("Failed to start WebSocket client: #{inspect(reason)}")
        handle_connection_error(new_state, reason)
    end
  end

  # Drop the websocket monitor (flushing any pending {:DOWN}) before we replace or
  # deliberately close the client, so a self-initiated teardown doesn't look like a
  # crash to reconnect from.
  defp demonitor_websocket(%{websocket_monitor: nil} = state), do: state

  defp demonitor_websocket(%{websocket_monitor: ref} = state) do
    Process.demonitor(ref, [:flush])
    %{state | websocket_monitor: nil}
  end

  defp disconnect_websocket(state) do
    state = demonitor_websocket(state)

    if state.websocket_client do
      WebSocketClient.close(state.websocket_client)
    end

    # Cancel timers
    if state.retry_timer do
      Process.cancel_timer(state.retry_timer)
    end

    if state.connection_timeout_timer do
      Process.cancel_timer(state.connection_timeout_timer)
    end

    %{
      state
      | websocket_client: nil,
        connection_state: :disconnected,
        retry_timer: nil,
        connection_timeout_timer: nil
    }
  end

  defp handle_connection_error(state, error) do
    # :xml_stream_end is the server ending the stream — normal after the 515
    # restart (we reconnect right after), so don't log it as an error.
    case error do
      :xml_stream_end -> Logger.info("Stream ended by server — reconnecting")
      _ -> Logger.error("Connection error: #{inspect(error)}")
    end

    new_state = %{
      state
      | connection_state: :disconnected,
        last_error: error,
        retry_count: state.retry_count + 1
    }

    # Cancel connection timeout timer
    if state.connection_timeout_timer do
      Process.cancel_timer(state.connection_timeout_timer)
    end

    # Emit error event
    emit_event(new_state, :error, error)

    # Schedule reconnection if within retry limit
    new_state =
      if new_state.retry_count < new_state.max_retries do
        schedule_reconnect(new_state)
      else
        Logger.error("Max retry attempts reached, giving up")
        %{new_state | connection_state: :closed}
      end

    # Announce the down-transition. Previously the error paths emitted only
    # :error, never the :connection_update the clean-close path emits — so a
    # consumer tracking connection state never saw the drop and its UI went stale
    # on the last "open". Emit the resulting state (:disconnected, or :closed once
    # retries are exhausted).
    emit_connection_update(new_state, new_state.connection_state)
    new_state
  end

  defp schedule_reconnect(state) do
    delay = calculate_retry_delay(state.retry_count, state.retry_delay)
    Logger.debug("Scheduling reconnection in #{delay}ms")

    Amarula.Telemetry.emit([:amarula, :reconnect, :scheduled], profile(state), %{
      count: 1,
      delay_ms: delay,
      attempt: state.retry_count
    })

    retry_timer = Process.send_after(self(), :reconnect, delay)
    %{state | retry_timer: retry_timer}
  end

  defp calculate_retry_delay(retry_count, base_delay) do
    # Exponential backoff with jitter
    exponential_delay = base_delay * :math.pow(2, retry_count)
    jitter = :rand.uniform() * 0.1 * exponential_delay
    round(exponential_delay + jitter)
  end

  defp emit_connection_update(state, connection_state) do
    update = %{
      connection: connection_state,
      received_pending_notifications: false,
      qr: nil
    }

    Amarula.Telemetry.emit([:amarula, :connection, :update], profile(state), %{count: 1}, %{
      state: connection_state
    })

    emit_event(state, :connection_update, update)
  end

  # Deliver a consumer event straight to the connection's sink as
  # `{:amarula, type, data}`. No internal subscriber registry, no relay hop — the
  # sink is the only one. A pid sink is sent to directly; a name/via sink is
  # resolved per event (so it re-attaches to the consumer's current pid for free).
  # An unresolvable sink (nil, or a name no one holds right now) drops the event.
  defp emit_event(%{parent_pid: nil}, _event_type, _data), do: :ok

  defp emit_event(%{parent_pid: sink}, event_type, data) do
    case sink_dest(sink) do
      nil -> :ok
      dest -> send(dest, {:amarula, event_type, data})
    end

    :ok
  end

  # Resolve a sink to something `send/2` accepts (a pid, or a `{name, node}`), or
  # nil if it can't be resolved right now. A bare pid is the fast path; everything
  # else goes through `GenServer.whereis/1` so an unregistered name yields nil
  # instead of raising (which `send/2` to a stale atom name would).
  defp sink_dest(pid) when is_pid(pid), do: pid
  defp sink_dest(sink), do: GenServer.whereis(sink)

  # Re-point the sink: demonitor the old, monitor the new, store it. Used by both
  # `set_parent/2` and the sink-:DOWN re-arm.
  defp install_sink(state, sink) do
    state = demonitor_sink(state)
    %{state | parent_pid: sink, parent_monitor: monitor_sink(sink)}
  end

  defp demonitor_sink(%{parent_monitor: nil} = state), do: state

  defp demonitor_sink(%{parent_monitor: ref} = state) do
    Process.demonitor(ref, [:flush])
    %{state | parent_monitor: nil}
  end

  # Monitor a sink's current holder so its death is observable. Returns the monitor
  # ref, or nil when there's nothing to watch (no sink, or a name no one holds yet).
  # An unheld name stays unmonitored but is NOT a delivery hole — `emit_event`
  # re-resolves it per event, and `rearm_sink_if_needed/1` re-arms the monitor off
  # the keep-alive once it resolves, so observability self-heals too.
  defp monitor_sink(nil), do: nil

  defp monitor_sink(sink) do
    case sink_dest(sink) do
      nil -> nil
      dest -> Process.monitor(dest)
    end
  end

  # Re-arm an unmonitored name sink once it resolves (called off the keep-alive).
  # Only acts when there's a sink but no live monitor — a pid sink is cleared to
  # nil on its :DOWN, so this only ever re-arms a name/via that's now holdable.
  defp rearm_sink_if_needed(%{parent_monitor: nil, parent_pid: sink} = state)
       when not is_nil(sink) do
    case monitor_sink(sink) do
      nil -> state
      ref -> %{state | parent_monitor: ref}
    end
  end

  defp rearm_sink_if_needed(state), do: state

  # Dispatch a message to the per-recipient ConversationSender and DON'T block.
  # Connection mints the msg_id and PARKS the caller's `from` under it in
  # `pending_acks` (arming an ack-timeout), then returns `{:noreply, state}` and is
  # immediately free for other sends. The reply to the caller is deferred to ack
  # time: on success the Sender reports nothing — the consumer's `from` is answered
  # when the server's <ack class="message" id=msg_id> arrives (a plain ack →
  # `shape.(:ok)`), or on the ack-timeout (`:ack_timeout`). On a pipe failure the
  # Sender reports `{:send_failed, …}`, which replies the caller the error at once.
  #
  # `from` nil = fire-and-forget (a retry resend, no caller waiting) → nothing is
  # parked. `shape` maps a successful ack to the caller's reply (default:
  # `{:ok, msg_id}`; poll adds its secret).
  # Dispatch a `SendOps` build triple. Thin glue between the send-callback bodies
  # (which now live in `SendOps`) and `deliver_async` (the ack-aware dispatcher,
  # which stays here because it owns the ack lifecycle).
  defp dispatch_send(state, {target, payload, shape}, from) do
    deliver_async(state, target, payload, from, shape)
  end

  # Resend/history go to OUR own devices, so they need a logged-in `me.id`. Guard
  # it once; on success run `build_fun.(me_id)` (a `SendOps` builder) and dispatch.
  defp with_me_id(state, from, build_fun) do
    case get_in(state.auth_creds, [:me, :id]) do
      nil -> {:reply, {:error, :not_authenticated}, state}
      me_id -> dispatch_send(state, build_fun.(me_id), from)
    end
  end

  defp deliver_async(state, target, payload, from, shape \\ &SendOps.default_send_reply/2)

  # Sandbox (offline) mode: the connection has no socket and there is no peer to
  # reach, so a send must not run the real pipeline (USync/bundle fetch IQs would
  # block forever with nothing to answer them). Short-circuit at the boundary:
  # mint a msg_id and reply exactly as a confirmed send would (`shape.(:ok, …)` →
  # `{:ok, id}`, or `{:ok, id, secret}` for a poll). Nothing is encrypted, no
  # frame leaves the process — the consumer's bot logic runs unchanged. A
  # fire-and-forget send (from == nil) simply does nothing.
  defp deliver_async(%{config: %{offline: true}} = state, _target, payload, from, shape) do
    msg_id = Map.get(payload, :msg_id) || generate_message_id()

    case from do
      nil -> {:noreply, state}
      _ -> {:reply, shape.(:ok, msg_id), state}
    end
  end

  defp deliver_async(state, target, payload, from, shape) do
    jid = Amarula.Address.to_jid!(target)
    msg_id = Map.get(payload, :msg_id) || generate_message_id()
    instance_id = state.instance_id

    opts = [
      registry: ConnectionSupervisor.registry_name(instance_id),
      supervisor: ConnectionSupervisor.whereis(instance_id, :sender_supervisor),
      instance_id: instance_id,
      cm: self(),
      conn: state.conn,
      # Drop :pre_keys before handing creds to the sender — it's the one-time-prekey
      # map (up to ~812 entries on a fresh account, ~100 KB+) read *only* on the
      # responder/decrypt path (`SessionBuilder.init_incoming`), which runs in
      # Connection, never in the sender (the sender is always the encrypt/initiator
      # side). Passing it would deep-copy ~100 KB into every sender, per recipient
      # on a fan-out. `Map.delete` is cheap (structural sharing); creds still go
      # per-send so they stay fresh as they mutate after login.
      creds: Map.delete(state.auth_creds, :pre_keys),
      recipient_jid: jid
    ]

    # The Sender carries the msg_id and reports its pipe result back to `cm`
    # (Connection) — it no longer holds the consumer's `from`.
    msg = Map.put(payload, :msg_id, msg_id)

    case ConversationSender.deliver(opts, msg) do
      {:ok, sender} ->
        state = ensure_sender_monitor(state, jid, sender)
        {:noreply, park_ack(state, msg_id, from, shape, jid)}

      {:error, reason} ->
        # The sender could not be started (e.g. :max_children). No frame went
        # out and no process exists to monitor — park the caller, then resolve
        # it immediately as a recoverable send failure rather than crashing.
        state = park_ack(state, msg_id, from, shape, jid)
        {:noreply, resolve_ack(state, msg_id, fn _shape -> {:error, reason} end)}
    end
  end

  # Monitor a recipient's sender once, the first time we park a send for it. The
  # sender is per recipient and may hold several in-flight sends; one monitor
  # covers them all. On its :DOWN we fail every parked send for this jid. A
  # fire-and-forget send (no parked entry) needs no monitor — but harmless to set.
  # Monitor a recipient's sender once (the self()-bound Process.monitor stays
  # here; AckLifecycle owns the map). One monitor covers all the recipient's
  # in-flight sends; on its :DOWN we fail every parked send for this jid.
  defp ensure_sender_monitor(state, jid, sender) do
    if AckLifecycle.monitored?(state, jid) do
      state
    else
      AckLifecycle.put_monitor(state, jid, Process.monitor(sender))
    end
  end

  # Park the consumer's `from` until the server confirms msg_id. The timeout
  # timer needs self() so it's created here; AckLifecycle stores it. The shape
  # applies to a successful ack only, so it's pre-bound with msg_id as `on_ack`.
  defp park_ack(state, _msg_id, nil, _shape, _jid), do: state

  defp park_ack(state, msg_id, from, shape, jid) do
    timer = Process.send_after(self(), {:ack_timeout, msg_id}, AckLifecycle.timeout_ms(state))
    AckLifecycle.park(state, msg_id, from, timer, fn :ok -> shape.(:ok, msg_id) end, jid)
  end

  defp resolve_ack(state, msg_id, reply_fun), do: AckLifecycle.resolve(state, msg_id, reply_fun)

  defp generate_message_id do
    "3EB0" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :upper))
  end

  # Handshake/login crypto + builders live in Socket.Login (pure); CM performs
  # the socket sends + state transitions from the ws_event handlers above.

  defp complete_handshake(state, final_noise_state_from_frame) do
    Logger.debug("Handshake completed successfully!")

    # Cancel connection timeout timer since handshake is complete
    if state.connection_timeout_timer do
      Process.cancel_timer(state.connection_timeout_timer)
    end

    # Use the noise state after encoding ClientFinish frame and transition to transport phase
    noise_state = Login.complete(final_noise_state_from_frame)

    # Wait for server response (pair-device IQ or success message)
    # Do NOT send immediate ping - matches Baileys behavior
    new_state =
      %{
        state
        | connection_state: :connected,
          handshake_state: nil,
          noise_state: noise_state,
          last_recv_time: System.monotonic_time(:millisecond),
          waiting_for_server_response: true,
          connection_timeout_timer: nil
      }
      |> start_keep_alive_timer()
      |> start_server_response_timeout()
      |> emit_to_subscribers(:connection_update, %{
        connection: :connecting,
        received_pending_notifications: false,
        qr: nil
      })

    Logger.debug("Handshake completed, waiting for server response...")
    {:noreply, new_state}
  end

  defp decode_and_emit_frame(noise_state, data, state) do
    with {:ok, frames, updated_noise_state} <- NoiseHandler.decode_frame(noise_state, data) do
      # Seed processing with the read-advanced noise state so any nodes we send while
      # handling these frames (acks, pings, replies) build on the SAME noise state and
      # advance write_counter from here. Returning a separate updated_noise_state and
      # then overwriting state.noise_state with it would discard those send-side counter
      # increments and desync the cipher (server rejects later frames with bad-mac).
      state = %{state | noise_state: updated_noise_state}

      # Process each decoded frame and accumulate state changes.
      updated_state =
        frames
        |> Enum.with_index()
        |> Enum.reduce(state, &process_indexed_frame/2)

      # noise_state already lives inside updated_state and reflects both the read
      # decode and any sends performed while handling these frames.
      {:ok, updated_state}
    end
  end

  # Only decode is wrapped: WhatsApp interleaves non-binary WS control frames
  # (close/pong) into this stream that the Decoder can't parse, so a decode failure
  # means "route as a control frame", not "crash". Node handling
  # (process_server_node) is deliberately OUTSIDE the rescue — a crash there is a
  # real protocol/state bug and should let the socket crash so the supervisor
  # restores a clean noise/crypto state.
  defp process_indexed_frame({frame, idx}, acc_state) do
    case decode_frame(frame, idx) do
      {:ok, binary_node} -> process_server_node(acc_state, binary_node)
      :control -> handle_control_frame(acc_state, frame)
    end
  end

  # Decompress + decode a single frame to a binary node. A failure here means the
  # bytes aren't a parseable WA node (e.g. an interleaved WS control frame), so we
  # report :control and let the caller route it — we do NOT catch downstream node
  # handling.
  defp decode_frame(frame, idx) do
    decompressed_frame = decompress_frame(frame)
    maybe_capture_frame(decompressed_frame)
    binary_node = Decoder.decode(decompressed_frame)
    {:ok, binary_node}
  rescue
    error ->
      Logger.warning(
        "Frame #{idx}: decode failed: #{inspect(error)}, treating as control frame\n" <>
          "frame hex: #{Base.encode16(frame)}\n" <>
          Exception.format_stacktrace(__STACKTRACE__)
      )

      :control
  end

  defp handle_control_frame(state, frame) do
    # Handle non-binary control frames
    # IMPORTANT: Do NOT treat 0x88 (Close frame) as keep-alive response
    # 0x88 is WebSocket close frame and should be handled separately
    case frame do
      # WebSocket close frame (0x88 = FIN=1, opcode=8)
      <<136, _::binary>> ->
        Logger.warning("Received WebSocket close frame - connection closing")
        # This will be handled by WebSocket client disconnect handler
        state

      # WebSocket pong frame (0x8A = FIN=1, opcode=10)
      # We don't use WS ping, but handle pong if server sends it
      <<138, _::binary>> ->
        %{state | last_recv_time: System.monotonic_time(:millisecond)}

      _ ->
        state
    end
  end

  defp process_server_node(state, node) do
    frame_tap("IN", node)

    # No generic "received node" log here — downstream handlers log their own
    # domain event (a decrypted message, a receipt, a presence update, …). Set
    # AMARULA_FRAME_TAP to trace every node regardless of whether a handler logs.

    # The routing DECISION (node shape -> handler tag) is pure and lives in
    # Socket.Router; here we just run the chosen handler. Behaviour is unchanged
    # from the old inline {tag,type,child,xmlns} case.
    dispatch_node(state, Router.route(node), node)
  end

  # QR code generation for new device pairing.
  defp dispatch_node(state, :pair_device, node), do: handle_pair_device(state, node)
  # Device paired successfully (QR scanned).
  defp dispatch_node(state, :pair_success, node), do: handle_pair_success(state, node)
  # Authentication/login successful.
  defp dispatch_node(state, :auth_success, node), do: handle_auth_success(state, node)
  # Encrypted message stanza.
  defp dispatch_node(state, :message, node), do: handle_message(state, node)
  # Stream errors (may contain QR data).
  defp dispatch_node(state, :stream_error, node), do: handle_stream_error(state, node)
  # Connection failure.
  defp dispatch_node(state, :connection_failure, node), do: handle_connection_failure(state, node)
  # Ping request from server (respond) / our ping acked.
  defp dispatch_node(state, :server_ping, node), do: handle_server_ping(state, node)
  defp dispatch_node(state, :ping_response, node), do: handle_ping_response(state, node)
  # Result/error for a tracked IQ we sent (e.g. prekey count/upload).
  defp dispatch_node(state, :iq_response, node), do: handle_iq_response(state, node)
  defp dispatch_node(state, :xml_stream_end, node), do: handle_xml_stream_end(state, node)
  # Queued offline messages: announced (must request) / fully delivered.
  defp dispatch_node(state, :offline_preview, node), do: handle_offline_preview(state, node)
  defp dispatch_node(state, :offline_complete, node), do: handle_offline_complete(state, node)
  # Edge routing info to persist for future connections.
  defp dispatch_node(state, :edge_routing, node), do: handle_edge_routing(state, node)
  # Server "dirty" sync flag — reply cleanDirtyBits or the phone stays "paused".
  defp dispatch_node(state, :dirty, node), do: handle_dirty(state, node)
  # Server notifications (group changes, app-state collections, ...).
  defp dispatch_node(state, :notification, node), do: handle_notification(state, node)
  # Inbound presence (<presence>) / typing (<chatstate>) → :presence_update.
  defp dispatch_node(state, :presence, node), do: handle_presence(state, node)
  # type="retry" receipt = recipient asking us to re-encrypt+resend; others just ack.
  defp dispatch_node(state, :retry_receipt, node), do: handle_retry_receipt(state, node)
  defp dispatch_node(state, :receipt_ack, node), do: handle_receipt(state, node)
  # Incoming call (offer/terminate/accept/reject/...). Always ack first (stops
  # the server retransmitting), then surface it as :call_update.
  defp dispatch_node(state, :call_ack, node), do: handle_call(state, node)
  # Server confirmation of a send we relayed — reply the parked consumer.
  defp dispatch_node(state, :message_ack, node), do: handle_message_ack(state, node)

  # Informational nodes that need no reply (thread_metadata, incoming <ack>).
  defp dispatch_node(state, :ignore, _node), do: state

  # Unhandled nodes — log LOUDLY (with the full node) so a server frame we don't
  # yet handle is never silently dropped. Silent drops here hid the `ib,,dirty` /
  # app-state `server_sync` gaps for a long time.
  defp dispatch_node(state, :unhandled, node) do
    Logger.warning(
      "UNHANDLED server node: tag=#{node.tag} attrs=#{inspect(node.attrs)} " <>
        "first_child=#{inspect(first_child_tag(node))} — no handler; dropping. " <>
        "Full node: #{inspect(node, limit: :infinity, printable_limit: 256)}"
    )

    state
  end

  defp first_child_tag(%Node{content: [%Node{tag: t} | _]}), do: t
  defp first_child_tag(_), do: nil

  # The server confirmed (or rejected) a message we sent. `<ack class="message"
  # id=msg_id [error=code] [phash=...]>`. Reply the parked consumer and drop the
  # entry:
  #   - no `error` → success → the parked ack-success shape `on_ack.(:ok)`.
  #   - `error` attr → {:error, {:send_rejected, code}}.
  #
  # Multiple acks for one id (the group / multi-device case): a stanza to a group
  # is a single `<message>` with one id, but the server MAY emit a `phash` ack
  # ("not all devices have it yet") before/with the terminal ack. We resolve on the
  # FIRST no-error ack regardless of phash — the server has ACCEPTED the message;
  # phash concerns device propagation, not acceptance. The first ack drops the
  # entry, so any later ack for the same id (a second phash, the clean follow-up,
  # or a duplicate) is a harmless no-op via `resolve_ack`. We NEVER auto-resend on
  # phash (the commented-out Baileys handleBadAck path loops). An `error` ack
  # arrives instead of a plain one, not after it, so resolving on the first no-error
  # ack cannot mask a later error for the same id.
  defp handle_message_ack(state, node) do
    msg_id = NodeUtils.get_attr(node, "id")

    case Receive.ack_outcome(node) do
      :ok ->
        emit_ack_outcome(state, msg_id, :ok)
        resolve_ack(state, msg_id, fn on_ack -> on_ack.(:ok) end)

      {:error, {:send_rejected, code}} = err ->
        emit_ack_outcome(state, msg_id, :rejected, code)
        resolve_ack(state, msg_id, fn _on_ack -> err end)
    end
  end

  # Telemetry for the outcome of a tracked send AFTER relay — the send span
  # closes at relay time, so the server's verdict needs its own event. Gated on
  # the parked entry so duplicate acks (phash + clean follow-up), acks for
  # untracked ids, and fire-and-forget sends don't inflate the count. `code` is
  # the server's rejection code (a protocol int/string), JID-free.
  defp emit_ack_outcome(state, msg_id, outcome, code \\ nil) do
    if AckLifecycle.parked?(state, msg_id) do
      Amarula.Telemetry.emit([:amarula, :send, :ack], profile(state), %{count: 1}, %{
        outcome: outcome,
        code: code
      })
    end

    :ok
  end

  # One [:amarula, :send, :ack] covering every parked send a sender crash takes
  # out (count = how many). The crash `reason` never enters the payload — it is
  # an arbitrary term.
  defp emit_sender_crashed(state, jid) do
    case AckLifecycle.parked_count(state, jid) do
      0 ->
        :ok

      n ->
        Amarula.Telemetry.emit([:amarula, :send, :ack], profile(state), %{count: n}, %{
          outcome: :sender_crashed,
          code: nil
        })
    end
  end

  # The recipient couldn't decrypt a message we sent and is asking us to resend it
  # (their Signal session was out of sync). We:
  #   1. ack the receipt (always — stops redelivery),
  #   2. inject the fresh prekey bundle the retry carries (if any), so the new
  #      session matches what the requester now has,
  #   3. look up the original message in the recent-message cache and, if found,
  #      emit :retry_send so the Socket re-encrypts + resends it to the requester.
  # Capped per-id so a persistently-broken peer can't loop us forever.
  # A non-retry receipt tells us a message we sent was delivered/read/played (or a
  # device of ours read something). Always ack, then surface it as :receipt_update
  # so a consumer can track delivery/read state.
  defp handle_receipt(state, node) do
    state = send_message_ack(state, node)

    case Receipt.parse(node) do
      {:ok, receipt} ->
        Logger.debug("Receipt #{receipt.status} for #{inspect(receipt.message_ids)}")
        emit_to_subscribers(state, :receipt_update, receipt)
        state

      {:error, _} ->
        state
    end
  end

  # A contact/group sent us a presence (<presence available|unavailable>) or a
  # typing indicator (<chatstate><composing|recording|paused/>). These are
  # unsolicited (no ack), so just parse and surface as :presence_update. jid +
  # participant are converted to %Amarula.Address{} (consistent with receipts).
  defp handle_presence(state, node) do
    case Presence.parse_update(node) do
      {:ok, update} ->
        data = %{
          jid: Amarula.Address.parse(update.jid),
          participant: Amarula.Address.parse(update.participant),
          presence: update.presence,
          last_seen: update.last_seen
        }

        Logger.debug("Presence #{update.presence} for #{update.participant}")
        emit_to_subscribers(state, :presence_update, data)
        state

      {:error, _} ->
        Logger.warning("Invalid presence node: #{inspect(node)}")
        state
    end
  end

  # An incoming `<call>` stanza (a contact calling, the call timing out, being
  # accepted/rejected, ...). Ack first so the server stops retransmitting, then
  # parse and surface it as :call_update. A malformed call (no info child) is
  # still acked but not surfaced.
  defp handle_call(state, node) do
    state = send_message_ack(state, node)

    case Call.parse(node) do
      {:ok, call} ->
        Logger.debug("Call #{call.status} from #{inspect(call.from)}")
        emit_to_subscribers(state, :call_update, call)
        state

      {:error, _} ->
        Logger.warning("Invalid call node: #{inspect(node)}")
        state
    end
  end

  defp handle_retry_receipt(state, node) do
    state = send_message_ack(state, node)
    Amarula.Telemetry.emit([:amarula, :retry, :received], profile(state), %{count: 1})

    {msg_id, participant} = Receive.retry_targets(node)

    cond do
      is_nil(msg_id) ->
        state

      retry_exhausted?(state, msg_id) ->
        Logger.warning("Retry resend limit reached for #{msg_id} — not resending")
        state

      true ->
        state = maybe_inject_retry_keys(state, node)
        state = bump_retry(state, msg_id)
        resend_from_cache(state, msg_id, participant)
        state
    end
  end

  defp retry_exhausted?(state, msg_id),
    do: Map.get(state.msg_retry_counts, "send:" <> msg_id, 0) >= @max_msg_retry_count

  defp bump_retry(state, msg_id) do
    key = "send:" <> msg_id
    %{state | msg_retry_counts: Map.update(state.msg_retry_counts, key, 1, &(&1 + 1))}
  end

  # A retry receipt may carry a <keys> bundle (a fresh session for the requester).
  # Inject it like a prekey-bundle reply so our re-encrypt uses the right session.
  defp maybe_inject_retry_keys(state, node) do
    case NodeUtils.get_binary_node_child(node, "keys") do
      %Node{} ->
        SessionInjector.inject(node, state.auth_creds, conn(state))
        state

      _ ->
        state
    end
  end

  defp resend_from_cache(state, msg_id, participant) do
    # Built-in DETS cache first, then the consumer-supplied get_message callback
    # (a store plugin) for messages older than the cache.
    case lookup_for_resend(state, msg_id) do
      {recipient, message, stanza_attrs} ->
        Logger.debug("Resending #{msg_id} to #{participant} (retry)")

        # Re-encrypt + resend the original (same id, so the recipient replaces
        # rather than duplicates). A fresh ConversationSender pass picks up the
        # session the retry's <keys> bundle just injected. Replay the original
        # stanza_attrs so a peer/edit stanza keeps its category/edit on resend.
        # Fire-and-forget: no caller is waiting, so `from` is nil.
        payload = %{msg_id: msg_id, message: message, stanza_attrs: stanza_attrs}
        deliver_async(state, recipient, payload, nil)

      nil ->
        Logger.debug("Retry for #{msg_id} but no cached/stored copy — cannot resend")
    end
  end

  defp lookup_for_resend(state, msg_id) do
    case Amarula.RetryCache.get(retry_cache(state), profile(state), msg_id) do
      {:ok, %{recipient_jid: recipient, message: message} = entry} ->
        {recipient, message, Map.get(entry, :stanza_attrs, %{})}

      :error ->
        case get_message_via_callback(state, msg_id) do
          {recipient, message} -> {recipient, message, %{}}
          nil -> nil
        end
    end
  end

  # config[:get_message] is `fn msg_id -> {recipient_jid, %Proto.Message{}} | nil`,
  # supplied by a consumer store plugin. Absent/erroring callback → no resend.
  defp get_message_via_callback(state, msg_id) do
    case Map.get(state.config, :get_message) do
      fun when is_function(fun, 1) ->
        case fun.(msg_id) do
          {recipient, %{} = message} when is_binary(recipient) -> {recipient, message}
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    error ->
      Logger.warning("get_message callback failed for #{msg_id}: #{inspect(error)}")
      nil
  end

  # Every notification must be acked or the server stops delivering; then we
  # dispatch by type. Types we don't yet handle fall through to a debug log
  # (still acked) rather than being dropped silently.
  defp handle_notification(state, node) do
    type = NodeUtils.get_attr(node, "type")
    state = send_message_ack(state, node)
    dispatch_notification(state, type, node)
  end

  # w:gp2 — group membership/metadata change. Parse it and emit :group_update.
  defp dispatch_notification(state, "w:gp2", node) do
    case GroupNotification.parse(node) do
      {:ok, update} ->
        Logger.debug("Group update (#{inspect(elem(update.action, 0))}) in #{update.group.user}")
        emit_to_subscribers(state, :group_update, update)
        state

      {:error, reason} ->
        Logger.debug("w:gp2 notification not parsed: #{inspect(reason)}")
        state
    end
  end

  # server_sync — names ONE app-state collection with new patches. We have the
  # full decode stack (keys + LTHash + MAC) now, so resync just that collection
  # (Baileys: resyncAppState([name])). The reply is decoded + emitted in
  # handle_tracked_iq(:app_state_sync).
  defp dispatch_notification(state, "server_sync", node) do
    case NodeUtils.get_binary_node_child(node, "collection") do
      %Node{} = collection ->
        name = NodeUtils.get_attr(collection, "name")
        Logger.debug("server_sync: resyncing app-state collection #{name}")
        resync_app_state(state, [name])

      _ ->
        state
    end
  end

  # encrypt — dispatched by origin: from the server it carries our remaining
  # pre-key <count>; from a peer it signals an identity change.
  defp dispatch_notification(state, "encrypt", node) do
    handle_encrypt_notification(state, node, NodeUtils.get_attr(node, "from"))
  end

  # account_sync — account-level setting changes. disappearing_mode updates creds;
  # blocklist additions/removals surface as a :blocklist_update event.
  defp dispatch_notification(state, "account_sync", node) do
    case Notifications.account_sync(node) do
      {:disappearing, duration} ->
        Logger.debug("account_sync: disappearing mode duration=#{duration}")
        settings = Map.get(state.auth_creds, :account_settings, %{})

        creds =
          Map.put(
            state.auth_creds,
            :account_settings,
            Map.put(settings, :default_disappearing_mode, duration)
          )

        update_creds(state, creds)

      {:blocklist, items} ->
        Logger.debug("account_sync: blocklist update (#{length(items)} item(s))")
        emit_to_subscribers(state, :blocklist_update, items)
        state

      :ignore ->
        state
    end
  end

  # devices — a contact's device list changed (add/remove/update). Rather than
  # apply the delta (a partial list would look authoritative — Baileys defers when
  # uncached), we drop the cached device list for each affected user so the next
  # send re-fetches a fresh list via USync. A "remove" also drops their sessions.
  defp dispatch_notification(state, "devices", node) do
    case Notifications.devices(node) do
      {tag, users} ->
        Logger.debug("devices #{tag}: dropping cached device list for #{length(users)} user(s)")
        Enum.each(users, &DeviceListCache.delete(conn(state), &1))
        state

      :ignore ->
        state
    end
  end

  # picture — a contact/group avatar changed; surface it as a contact update so a
  # consumer can refresh the image (Baileys emits contacts.update imgUrl).
  defp dispatch_notification(state, "picture", node) do
    {from, img_url} = Notifications.picture(node)
    Logger.debug("picture #{img_url} for #{from}")
    emit_to_subscribers(state, :contacts_update, [%{id: from, img_url: img_url}])
    state
  end

  # link_code_companion_reg — the phone confirmed our pairing code. Finish the
  # handshake (companion_finish IQ + adv_secret re-key + registered=true); the
  # server's subsequent 515 then logs us in via the normal login path.
  #
  # The same tag also arrives as a fieldless notification (Baileys #2600). Guard
  # buffer extraction with `with` so a missing field logs-and-skips rather than
  # crashing the connection.
  defp dispatch_notification(state, "link_code_companion_reg", node) do
    inner = NodeUtils.get_binary_node_child(node, "link_code_companion_reg")

    with reg when not is_nil(reg) <- inner,
         ref when not is_nil(ref) <- child_buffer(reg, "link_code_pairing_ref"),
         primary_identity_pub when not is_nil(primary_identity_pub) <-
           child_buffer(reg, "primary_identity_pub"),
         wrapped when not is_nil(wrapped) <-
           child_buffer(reg, "link_code_pairing_wrapped_primary_ephemeral_pub") do
      finish_link_code_pairing(state, ref, primary_identity_pub, wrapped)
    else
      _ ->
        Logger.debug("link_code_companion_reg notification missing fields — skipping")
        state
    end
  end

  defp dispatch_notification(state, type, _node) do
    Logger.debug("Notification (type=#{type}) acked — no handler")
    state
  end

  # Mirror of Baileys' link_code_companion_reg handler: decipher the phone's
  # ephemeral key, build the encrypted key bundle, re-key adv_secret, send
  # companion_finish, mark registered, emit :pairing_success.
  defp finish_link_code_pairing(state, ref, primary_identity_pub, wrapped) do
    creds = state.auth_creds

    code_pairing_pub = decipher_link_public_key(creds, wrapped)

    companion_shared =
      Crypto.shared_key(creds.pairing_ephemeral_key_pair.private, code_pairing_pub)

    random = Crypto.random_bytes(32)
    link_code_salt = Crypto.random_bytes(32)

    expanded =
      Crypto.hkdf(
        companion_shared,
        32,
        link_code_salt,
        "link_code_pairing_key_bundle_encryption_key"
      )

    payload = creds.signed_identity_key.public <> primary_identity_pub <> random
    iv = Crypto.random_bytes(12)
    {:ok, encrypted} = Crypto.aes_encrypt_gcm(payload, expanded, iv, <<>>)
    encrypted_payload = link_code_salt <> iv <> encrypted

    identity_shared = Crypto.shared_key(creds.signed_identity_key.private, primary_identity_pub)

    adv_secret =
      Crypto.hkdf(companion_shared <> identity_shared <> random, 32, <<>>, "adv_secret")
      |> Base.encode64()

    creds = %{creds | adv_secret_key: adv_secret, registered: true}

    iq = %Node{
      tag: "iq",
      attrs: [
        {"to", Constants.s_whatsapp_net()},
        {"type", "set"},
        {"id", generate_message_tag(state)},
        {"xmlns", "md"}
      ],
      content: [
        %Node{
          tag: "link_code_companion_reg",
          attrs: [{"jid", me(state).id}, {"stage", "companion_finish"}],
          content: [
            child("link_code_pairing_wrapped_key_bundle", encrypted_payload),
            child("companion_identity_public", creds.signed_identity_key.public),
            child("link_code_pairing_ref", ref)
          ]
        }
      ]
    }

    Logger.info("Finishing link-code pairing — sending companion_finish")
    state = send_binary_node(state, iq)
    state = update_creds(state, creds)
    emit_to_subscribers(state, :pairing_success, %{via: :link_code})
  end

  # salt(0..32) <> iv(32..48) <> payload(48..80); AES-CTR-decrypt the wrapped pub.
  defp decipher_link_public_key(creds, buffer) do
    <<salt::binary-size(32), iv::binary-size(16), payload::binary-size(32), _rest::binary>> =
      buffer

    key = Crypto.derive_pairing_code_key(creds.pairing_code, salt)
    Crypto.aes_decrypt_ctr(payload, key, iv)
  end

  # Fetch a named child's content, but only if it's a binary buffer (the #2600
  # guard — a fieldless notification yields nil, not a crash).
  defp child_buffer(node, tag) do
    case NodeUtils.get_binary_node_child(node, tag) do
      %Node{content: content} when is_binary(content) -> content
      _ -> nil
    end
  end

  # No `from` (or the server jid) → pre-key top-up; any other origin is a peer
  # identity change. (Guards can't call Constants, so the server-jid compare is in
  # the body.)
  defp handle_encrypt_notification(state, node, nil), do: do_prekey_topup(state, node)

  defp handle_encrypt_notification(state, node, from) do
    if from == Constants.s_whatsapp_net() do
      do_prekey_topup(state, node)
    else
      maybe_refresh_identity(state, node, from)
    end
  end

  defp do_prekey_topup(state, node) do
    count =
      case NodeUtils.get_binary_node_child(node, "count") do
        %Node{} = c -> String.to_integer(NodeUtils.get_attr(c, "value") || "0")
        _ -> 0
      end

    low_water = PreKeys.low_water_pre_key_count()

    if count <= low_water do
      target = PreKeyOps.upload_target(count)
      Logger.debug("encrypt: #{count} pre-keys left (<= #{low_water}) — uploading #{target}")
      upload_pre_keys(state, target, :prekey_reupload)
    else
      Logger.debug("encrypt: #{count} pre-keys left — no upload needed")
      state
    end
  end

  # A peer's identity changed. Baileys (handleIdentityChange): only force-refresh
  # if we ALREADY have a session with them (a new contact needs none), and skip
  # during offline batch processing (it'd refresh stale state). Otherwise re-fetch
  # their key bundle so our session matches their new identity.
  defp maybe_refresh_identity(state, node, from) do
    offline? = NodeUtils.get_attr(node, "offline") not in [nil, ""]
    has_session? = SessionStore.load_session(conn(state), from) != nil

    cond do
      not has_session? ->
        Logger.debug("encrypt(identity) from #{from}: no existing session — skipping refresh")
        state

      offline? ->
        Logger.debug("encrypt(identity) from #{from}: offline batch — deferring refresh")
        state

      true ->
        Logger.debug("encrypt(identity) from #{from}: refreshing session")
        force_refresh_sessions(state, [from])
    end
  end

  # Build + send the <iq xmlns=encrypt> key fetch that force-refreshes the named
  # jids' Signal sessions (Baileys assertSessions force=true). Used both for
  # newly-mapped LIDs and for an identity-change notification.
  defp force_refresh_sessions(state, jids) do
    user_nodes =
      Enum.map(jids, fn jid ->
        %Node{tag: "user", attrs: %{"jid" => jid, "reason" => "identity"}, content: nil}
      end)

    node = %Node{
      tag: "iq",
      attrs: [{"xmlns", "encrypt"}, {"type", "get"}, {"to", Constants.s_whatsapp_net()}],
      content: [%Node{tag: "key", attrs: %{}, content: user_nodes}]
    }

    send_tracked_iq(state, node, :assert_lid_sessions)
  end

  # Baileys CB:ib,,dirty (chats.ts): clear the server's dirty sync flag with a
  # <iq type=set xmlns="urn:xmpp:whatsapp:dirty"><clean type=.. timestamp=../></iq>.
  # Until this is acked the server keeps the companion's sync "paused".
  defp handle_dirty(state, node) do
    case NodeUtils.get_binary_node_child(node, "dirty") do
      nil ->
        state

      dirty ->
        type = NodeUtils.get_attr(dirty, "type") || "account_sync"
        ts = NodeUtils.get_attr(dirty, "timestamp")

        clean_attrs =
          if ts, do: %{"type" => type, "timestamp" => ts}, else: %{"type" => type}

        iq = %Node{
          tag: "iq",
          attrs: [
            {"to", Constants.s_whatsapp_net()},
            {"type", "set"},
            {"xmlns", "urn:xmpp:whatsapp:dirty"}
          ],
          content: [%Node{tag: "clean", attrs: clean_attrs, content: nil}]
        }

        Logger.debug("Clearing dirty bits (type=#{type})")
        state = send_tracked_iq(state, iq, :clean_dirty)
        # An account_sync dirty flag means app state changed — resync it.
        if type == "account_sync", do: resync_app_state(state), else: state
    end
  end

  # Baileys CB:ib,,offline_preview — reply <ib><offline_batch count="100"/></ib>
  # or the server never delivers the queued offline messages.
  defp handle_offline_preview(state, node) do
    count =
      case NodeUtils.get_binary_node_child(node, "offline_preview") do
        nil -> "?"
        child -> NodeUtils.get_attr(child, "count") || "?"
      end

    Logger.debug("Offline preview received (count=#{count}) — requesting batch")

    batch = %Node{
      tag: "ib",
      attrs: %{},
      content: [%Node{tag: "offline_batch", attrs: %{"count" => "100"}, content: nil}]
    }

    send_binary_node(state, batch)
  end

  defp handle_offline_complete(state, node) do
    count =
      case NodeUtils.get_binary_node_child(node, "offline") do
        nil -> 0
        child -> String.to_integer(NodeUtils.get_attr(child, "count") || "0")
      end

    Logger.debug("Handled #{count} offline messages/notifications")

    emit_to_subscribers(state, :connection_update, %{received_pending_notifications: true})
    state
  end

  # Baileys CB:ib,,edge_routing — persist routing info in creds.
  defp handle_edge_routing(state, node) do
    with %Node{} = edge <- NodeUtils.get_binary_node_child(node, "edge_routing"),
         %Node{content: info} when is_binary(info) <-
           NodeUtils.get_binary_node_child(edge, "routing_info") do
      update_creds(state, Map.put(state.auth_creds, :routing_info, info))
    else
      _ -> state
    end
  end

  # WhatsApp closes the stream with code 515 after a successful pair-device-sign
  # reply; the client must reconnect and log in with the freshly paired creds
  # (Baileys DisconnectReason.restartRequired).
  @stream_error_restart_required 515

  defp handle_stream_error(state, node) do
    {code, reason} = stream_error_details(node)

    Amarula.Telemetry.emit([:amarula, :stream_error, :received], profile(state), %{count: 1}, %{
      code: code
    })

    if code == @stream_error_restart_required do
      Logger.debug(
        "Stream error 515 (restart required) — reconnecting to log in with paired credentials"
      )

      # Creds were already persisted at pairing; just reconnect.
      restart_connection(state)
    else
      Logger.error("Stream error: code=#{code}, reason=#{reason}")
      handle_connection_error(state, {:stream_error, code, reason})
    end
  end

  # Mirrors Baileys getErrorCodeFromStreamError: code attr, reason = first child tag
  defp stream_error_details(node) do
    reason = NodeUtils.get_first_child_tag(node) || "unknown"

    code =
      case Integer.parse(NodeUtils.get_attr(node, "code") || "") do
        {code, _} -> code
        :error -> 500
      end

    {code, reason}
  end

  # Tear down the current socket and reconnect immediately, keeping auth creds.
  # The handshake then sends a login (not registration) payload since creds.me is set.
  defp restart_connection(state) do
    if state.keep_alive_timer do
      Process.cancel_timer(state.keep_alive_timer)
    end

    state
    |> clear_server_response_waiting()
    |> fail_pending_iqs(:not_connected)
    |> disconnect_websocket()
    |> Map.merge(%{
      noise_state: nil,
      handshake_state: nil,
      keep_alive_timer: nil,
      retry_count: 0
    })
    |> attempt_connection()
  end

  # Drain pending IQs on a restart: blocked query_iq callers get an immediate
  # error instead of hanging to their call timeout; tracked-IQ timers are
  # cancelled (their continuations are abandoned with the old socket).
  defp fail_pending_iqs(state, reason) do
    Enum.each(state.pending_iqs, fn
      {_id, {:waiter, from, timer}} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, {:error, reason})

      {_id, {:waiter, from, timer, _transform}} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, {:error, reason})

      {_id, {:tracked, _kind, timer}} ->
        Process.cancel_timer(timer)
    end)

    %{state | pending_iqs: %{}}
  end

  defp handle_pair_device(state, node) do
    Logger.debug("Received pair-device IQ, generating QR codes...")

    # Cancel the server response timeout timer - we're now waiting for user action (QR scan),
    # not server action. The user can take as long as they need.
    state =
      if state.server_response_timeout_timer do
        Process.cancel_timer(state.server_response_timeout_timer)
        %{state | server_response_timeout_timer: nil}
      else
        state
      end

    # NOTE: Do NOT clear waiting_for_server_response here!
    # We're still waiting for the user to scan the QR code and pair-success to arrive.
    # The pair-device IQ is just sending us QR codes, not completing authentication.

    # Send IQ acknowledgment.
    msg_id = NodeUtils.get_attr(node, "id")
    Logger.debug("Sending pair-device IQ ack (id=#{msg_id})")
    state = send_binary_node(state, Pairing.pair_device_ack_node(msg_id))

    # Extract ref nodes and start cycling QR codes (matches Baileys genPairQR loop)
    case Pairing.qr_refs(node) do
      [] ->
        Logger.warning("pair-device IQ had no ref nodes")
        state

      refs ->
        emit_next_qr(%{state | qr_refs: refs})
    end
  end

  # Emit the next QR ref and schedule the following one. The first QR lives for
  # qr_timeout (default 60s), subsequent refs for a shorter window (20s), matching
  # Baileys. When refs run out the pairing window has expired.
  defp emit_next_qr(%{qr_refs: []} = state) do
    Logger.warning("QR refs exhausted — pairing window expired")
    handle_connection_error(state, {:pairing_error, :qr_timeout})
  end

  defp emit_next_qr(%{qr_refs: [ref | rest]} = state) do
    if state.qr_timer, do: Process.cancel_timer(state.qr_timer)

    qr = generate_qr_code(ref, state.auth_creds, state.config)

    emit_to_subscribers(state, :connection_update, %{
      connection: :connecting,
      qr: qr
    })

    # First QR: full timeout; later refs: shorter. Only schedule if more remain.
    state = %{state | qr_refs: rest}

    if rest == [] do
      %{state | qr_timer: nil}
    else
      delay = qr_refresh_delay(state)
      timer = Process.send_after(self(), :next_qr, delay)
      %{state | qr_timer: timer}
    end
  end

  defp qr_refresh_delay(state) do
    # First emission uses the configured qr_timeout; afterwards 20s like Baileys.
    base = Map.get(state.config, :qr_timeout) || 60_000
    if state.qr_timer == nil, do: base, else: 20_000
  end

  defp handle_pair_success(state, node) do
    Logger.debug("Received pair-success message, processing device pairing...")

    # Clear waiting state - pairing is complete
    state = clear_server_response_waiting(state)

    with msg_id when not is_nil(msg_id) <- NodeUtils.get_attr(node, "id"),
         pair_success_node when not is_nil(pair_success_node) <-
           NodeUtils.get_binary_node_child(node, "pair-success"),
         device_identity_node when not is_nil(device_identity_node) <-
           NodeUtils.get_binary_node_child(pair_success_node, "device-identity"),
         device_node when not is_nil(device_node) <-
           NodeUtils.get_binary_node_child(pair_success_node, "device"),
         jid when not is_nil(jid) <- NodeUtils.get_attr(device_node, "jid"),
         lid when not is_nil(lid) <- NodeUtils.get_attr(device_node, "lid"),
         identity_hmac <-
           Proto.ADVSignedDeviceIdentityHMAC.decode(device_identity_node.content),
         {:ok, verified_account} <-
           DeviceIdentity.verify_and_sign(identity_hmac, state.auth_creds),
         device_identity <- Proto.ADVDeviceIdentity.decode(verified_account.details) do
      # Extract optional fields
      platform_node = NodeUtils.get_binary_node_child(pair_success_node, "platform")
      business_node = NodeUtils.get_binary_node_child(pair_success_node, "biz")
      platform = if platform_node, do: NodeUtils.get_attr(platform_node, "name"), else: nil
      biz_name = if business_node, do: NodeUtils.get_attr(business_node, "name"), else: nil

      Logger.info("Pairing device (platform=#{platform})")
      Logger.debug("Pairing jid=#{jid} lid=#{lid}")

      signal_identity = DeviceIdentity.signal_identity(lid, verified_account.accountSignatureKey)

      # Encode without the account signature key
      account_enc = DeviceIdentity.encode(verified_account, false)

      reply_node = Pairing.pair_device_sign_reply(msg_id, device_identity.keyIndex, account_enc)

      Logger.debug(
        "Sending pair-device-sign reply: msg_id=#{msg_id}, key_index=#{device_identity.keyIndex}"
      )

      state = send_binary_node(state, reply_node)

      updated_creds =
        Pairing.update_credentials_after_pairing(
          state.auth_creds,
          verified_account,
          jid,
          lid,
          biz_name,
          platform,
          signal_identity
        )

      # Persist the paired credentials (internally) before the server's 515
      # restart, so the reconnect logs in with them.
      state = update_creds(state, updated_creds)

      Logger.info("Pairing successful")
      Logger.debug("Paired device: #{jid}")

      emit_to_subscribers(state, :pairing_success, %{jid: jid, lid: lid, platform: platform})

      emit_to_subscribers(state, :connection_update, %{
        connection: :connecting,
        is_new_login: true,
        qr: nil
      })

      state
    else
      nil ->
        Logger.error("Missing required field in pair-success message")
        emit_to_subscribers(state, :pairing_failure, %{reason: "missing_required_field"})
        handle_connection_error(state, {:pairing_error, :missing_field})

      {:error, reason} ->
        Logger.error("Failed to process pair-success: #{inspect(reason)}")
        emit_to_subscribers(state, :pairing_failure, %{reason: inspect(reason)})
        handle_connection_error(state, {:pairing_error, reason})
    end
  end

  # Device-identity pairing crypto extracted to Auth.DeviceIdentity (pure);
  # pairing node/creds builders extracted to Connection.Pairing (pure).

  # Full-frame tap for protocol diffing against Baileys. Off unless AMARULA_FRAME_TAP
  # is set. Dumps every in/out node as one-line XML so two clients' post-login frame
  # streams can be diffed directly. Skips noisy decode of message bodies (logs the
  # stanza shell only). Direction is "IN"/"OUT".
  defp frame_tap(dir, node) do
    if System.get_env("AMARULA_FRAME_TAP") do
      # inspect (binary-safe) rather than binary_node_to_string, which emits raw
      # bytes from <enc> content and crashes the Logger formatter.
      dump = inspect(node, limit: :infinity, printable_limit: 64, width: :infinity)
      Logger.info("TAP #{dir} #{dump}")
    end

    :ok
  end

  defp send_binary_node(%{config: %{frame_sink: sink}} = state, node) when is_pid(sink) do
    # Test seam: when a frame_sink pid is configured, deliver the decoded node
    # directly (bypassing noise framing + websocket) so tests can assert on what
    # would be sent without standing up a real connection. No-op in production
    # where frame_sink is never set.
    send(sink, {:frame_out, node})
    state
  end

  # Backstop: an outbound must never crash the connection. A send before the
  # handshake completes (noise_state nil ⇒ encode_frame derefs nil ⇒ BadMapError)
  # or after the socket dropped (websocket_client nil ⇒ send_data crash) drops the
  # frame and returns the state unchanged. The consumer-facing send clauses guard
  # with ready_to_send?/1 and reply {:error, :not_connected}; this catches every
  # other (internal) caller — receipts, acks, pings — that fires in the same window.
  defp send_binary_node(%{noise_state: nil} = state, _node) do
    Logger.warning("Dropping outbound frame: connection not established (no noise state)")
    state
  end

  defp send_binary_node(%{websocket_client: nil} = state, _node) do
    Logger.warning("Dropping outbound frame: connection down (no websocket)")
    state
  end

  defp send_binary_node(state, node) do
    frame_tap("OUT", node)
    {:ok, encoded} = Encoder.encode(node)

    # Prepend the 1-byte compression flag (0x00 = uncompressed). Baileys frames every
    # binary node with this leading byte; the receive path strips it before decoding.
    # Without it the server reads the node shifted by one byte → xml-not-well-formed.
    framed = <<0>> <> encoded
    {encrypted, updated_noise_state} = NoiseHandler.encode_frame(state.noise_state, framed)
    WebSocketClient.send_data(state.websocket_client, encrypted)
    %{state | noise_state: updated_noise_state}
  end

  # Whether the send path can run without hitting the nil-noise / nil-socket
  # backstop above. A configured frame_sink (test seam) is always ready; otherwise
  # we need a completed handshake (noise_state) AND a live socket (websocket_client).
  # Race-free server-side: only this process mutates state, so the check and the
  # send it gates can't straddle a disconnect.
  defp ready_to_send?(%{config: %{frame_sink: sink}}) when is_pid(sink), do: true

  defp ready_to_send?(%{noise_state: noise, websocket_client: ws}),
    do: not is_nil(noise) and not is_nil(ws)

  # Send `node` and reply :ok, unless the connection isn't ready — then reply
  # {:error, :not_connected} without entering the noise/socket path. For the
  # synchronous consumer sends (presence, read receipts, relayed stanzas).
  defp send_reply(state, node) do
    if ready_to_send?(state) do
      {:reply, :ok, send_binary_node(state, node)}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  defp handle_connection_failure(state, node) do
    Logger.error("Connection failure: #{NodeUtils.binary_node_to_string(node)}")

    reason = NodeUtils.get_attr(node, "reason") || "unknown"
    handle_connection_error(state, {:connection_failure, reason})
  end

  defp handle_ping_response(state, _node) do
    %{state | last_recv_time: System.monotonic_time(:millisecond)}
  end

  defp handle_server_ping(state, node) do
    # The server pings us to check liveness; reply with an empty iq result or it
    # concludes the client is dead and closes the stream. Matches Baileys, which
    # auto-acks CB:iq,,ping with { type: 'result', to, id }.
    msg_id = NodeUtils.get_attr(node, "id")

    pong = %Node{
      tag: "iq",
      attrs: [
        {"to", Constants.s_whatsapp_net()},
        {"type", "result"},
        {"id", msg_id}
      ],
      content: nil
    }

    send_binary_node(state, pong)
  end

  defp handle_xml_stream_end(state, _node) do
    Logger.info("XML stream ended by server")
    handle_connection_error(state, :xml_stream_end)
  end

  defp generate_qr_code(ref, auth_creds, config) do
    # Matches Baileys buildPairingQRData (rc13):
    # "https://wa.me/settings/linked_devices#" +
    #   [ref, noiseKey, identityKey, advSecretKey, companionPlatformId].join(",")
    noise_key_b64 = Base.encode64(auth_creds.noise_key.public)
    identity_key_b64 = Base.encode64(auth_creds.signed_identity_key.public)
    adv_b64 = auth_creds.adv_secret_key
    platform_id = companion_platform_id(config.browser)

    "https://wa.me/settings/linked_devices#" <>
      Enum.join([ref, noise_key_b64, identity_key_b64, adv_b64, platform_id], ",")
  end

  # Mirrors Baileys getCompanionWebClientType: browser name → CompanionWebClientType
  defp companion_platform_id([os, browser_name | _]) do
    cond do
      browser_name == "Desktop" and os == "Windows" ->
        "8"

      browser_name == "Desktop" ->
        "7"

      true ->
        case browser_name do
          "Chrome" -> "1"
          "Edge" -> "2"
          "Firefox" -> "3"
          "IE" -> "4"
          "Opera" -> "5"
          "Safari" -> "6"
          _ -> "9"
        end
    end
  end

  defp companion_platform_id(_), do: "9"

  # ── Link-code (phone-number) pairing ──────────────────────────────────────
  # Mirrors Baileys requestPairingCode / generatePairingKey (socket.ts) on the
  # request side and the link_code_companion_reg notification handler
  # (messages-recv.ts) on the finish side. Plugs into the existing post-handshake
  # IQ + notification machinery, parallel to QR pairing.

  # nil → random 8-char Crockford code; a custom code must be exactly 8 chars.
  defp build_pairing_code(nil), do: {:ok, CompanionReg.crockford_encode(Crypto.random_bytes(5))}
  defp build_pairing_code(code) when is_binary(code) and byte_size(code) == 8, do: {:ok, code}
  defp build_pairing_code(_), do: {:error, :custom_pairing_code_must_be_8_chars}

  # Set me + pairing_code, persist, then send the companion_hello IQ and emit
  # :pairing_code so the consumer can display the code.
  defp start_link_code_pairing(state, phone, code) do
    me = %{id: JID.encode(%{user: phone, server: "s.whatsapp.net"}), name: "~"}

    creds =
      state.auth_creds
      |> Map.put(:me, me)
      |> Map.put(:pairing_code, code)

    state = update_creds(state, creds)

    iq = %Node{
      tag: "iq",
      attrs: [
        {"to", Constants.s_whatsapp_net()},
        {"type", "set"},
        {"id", generate_message_tag(state)},
        {"xmlns", "md"}
      ],
      content: [
        %Node{
          tag: "link_code_companion_reg",
          attrs: [
            {"jid", me.id},
            {"stage", "companion_hello"},
            {"should_show_push_notification", "true"}
          ],
          content: [
            child(
              "link_code_pairing_wrapped_companion_ephemeral_pub",
              generate_pairing_key(creds)
            ),
            child("companion_server_auth_key_pub", creds.noise_key.public),
            child("companion_platform_id", companion_platform_id(state.config.browser)),
            child("companion_platform_display", platform_display(state.config.browser)),
            child("link_code_pairing_nonce", "0")
          ]
        }
      ]
    }

    Logger.info("Requested link-code pairing for #{phone} — code #{code}")
    state = send_binary_node(state, iq)
    emit_to_subscribers(state, :pairing_code, %{code: code})
  end

  # salt(32) <> iv(16) <> AES-CTR(pairing ephemeral pub, derivePairingCodeKey(code, salt), iv)
  defp generate_pairing_key(creds) do
    salt = Crypto.random_bytes(32)
    iv = Crypto.random_bytes(16)
    key = Crypto.derive_pairing_code_key(creds.pairing_code, salt)
    ciphered = Crypto.aes_encrypt_ctr(creds.pairing_ephemeral_key_pair.public, key, iv)
    salt <> iv <> ciphered
  end

  # Baileys `${browser[1]} (${browser[0]})` → "Chrome (Mac OS)".
  defp platform_display([os, browser_name | _]), do: "#{browser_name} (#{os})"
  defp platform_display(_), do: "Chrome"

  defp child(tag, content), do: %Node{tag: tag, attrs: [], content: content}

  defp start_server_response_timeout(state) do
    timer = Process.send_after(self(), :server_response_timeout, 15_000)
    %{state | server_response_timeout_timer: timer}
  end

  defp clear_server_response_waiting(state) do
    # Cancel timeout timer if it exists
    if state.server_response_timeout_timer do
      Process.cancel_timer(state.server_response_timeout_timer)
    end

    # Stop QR cycling — the server has responded (pair-success / success)
    if state.qr_timer do
      Process.cancel_timer(state.qr_timer)
    end

    %{
      state
      | waiting_for_server_response: false,
        server_response_timeout_timer: nil,
        qr_refs: [],
        qr_timer: nil
    }
  end

  defp send_passive_iq(state, tag) do
    # Send passive IQ with proper child node format
    # This matches the TypeScript Baileys implementation
    iq_id = generate_message_tag(state)
    state = increment_message_epoch(state)

    passive_node = %Amarula.Protocol.Binary.Node{
      tag: "iq",
      # List attrs preserve Baileys order: to, xmlns, type, id
      attrs: [
        {"to", Constants.s_whatsapp_net()},
        {"xmlns", "passive"},
        {"type", "set"},
        {"id", iq_id}
      ],
      content: [
        %Amarula.Protocol.Binary.Node{
          tag: tag,
          attrs: %{},
          content: nil
        }
      ]
    }

    send_binary_node(state, passive_node)
  end

  # Baileys executeInitQueries (chats.ts), fired on `open`: fetchProps + blocklist
  # + privacy. These appear to be a server-side precondition for E2E key-exchange:
  # without them the server SILENTLY ignores our prekey-bundle fetches (answers
  # every other IQ). Fire-and-forget, matching Baileys (it doesn't block sends on
  # the replies). The abt/props hash is omitted on first run (Baileys sends it only
  # when it has a cached lastPropHash).
  defp send_init_queries(state) do
    state
    |> send_init_iq(
      [{"to", Constants.s_whatsapp_net()}, {"xmlns", "abt"}, {"type", "get"}],
      %Node{
        tag: "props",
        attrs: %{"protocol" => "1"},
        content: nil
      }
    )
    |> send_init_iq(
      [{"xmlns", "blocklist"}, {"to", Constants.s_whatsapp_net()}, {"type", "get"}],
      nil
    )
    |> send_init_iq(
      [{"xmlns", "privacy"}, {"to", Constants.s_whatsapp_net()}, {"type", "get"}],
      %Node{
        tag: "privacy",
        attrs: %{},
        content: nil
      }
    )
  end

  defp send_init_iq(state, base_attrs, child) do
    id = generate_message_tag(state)
    state = increment_message_epoch(state)
    content = if child, do: [child], else: nil
    node = %Node{tag: "iq", attrs: base_attrs ++ [{"id", id}], content: content}
    send_binary_node(state, node)
  end

  # sendUnifiedSession: <ib><unified_session id="..."/></ib>
  # id = (now_ms + 3_days) % 7_days — mirrors Baileys getUnifiedSessionId().
  defp send_unified_session(state) do
    send_binary_node(state, Login.unified_session_node())
  end

  # Server-side device unlink: <iq set xmlns=md><remove-companion-device jid=<me.id>
  # reason="user_initiated"/></iq>. Fire-and-forget; we tear down right after.
  defp send_remove_companion(state) do
    case me(state) do
      %{id: jid} when is_binary(jid) ->
        iq = %Node{
          tag: "iq",
          attrs: [
            {"to", Constants.s_whatsapp_net()},
            {"type", "set"},
            {"id", generate_message_tag(state)},
            {"xmlns", "md"}
          ],
          content: [
            %Node{
              tag: "remove-companion-device",
              attrs: %{"jid" => jid, "reason" => "user_initiated"},
              content: nil
            }
          ]
        }

        send_binary_node(increment_message_epoch(state), iq)

      _ ->
        state
    end
  end

  # digestKeyBundle: server validates our key bundle; if no <digest> in reply we
  # re-upload prekeys (handled by the :digest tracked continuation).
  defp send_digest_iq(state) do
    send_tracked_iq(state, Login.digest_iq(), :digest)
  end

  defp start_keep_alive_timer(state) do
    # Start keep-alive timer to send periodic ping messages
    # NO immediate ping after handshake - first ping sent after keep_alive_interval_ms
    # Cancel any timer from a previous (re)connect so ping loops don't multiply.
    if state.keep_alive_timer, do: Process.cancel_timer(state.keep_alive_timer)
    keep_alive_interval = state.config.keep_alive_interval_ms || 30_000

    # Schedule first ping after interval
    timer = Process.send_after(self(), :send_keep_alive, keep_alive_interval)

    %{state | keep_alive_timer: timer}
  end

  defp send_ping_message(state) do
    # Send ping message to keep connection alive
    # Using list-based attrs to preserve Baileys order: id, to, type, xmlns
    ping_id = generate_message_tag(state)
    state = increment_message_epoch(state)

    ping_node = %Amarula.Protocol.Binary.Node{
      tag: "iq",
      attrs: [
        {"id", ping_id},
        {"to", "@s.whatsapp.net"},
        {"type", "get"},
        {"xmlns", "w:p"}
      ],
      content: [
        %Amarula.Protocol.Binary.Node{
          tag: "ping",
          attrs: %{},
          content: nil
        }
      ]
    }

    send_binary_node(state, ping_node)
  end

  defp generate_message_tag_prefix do
    # Match Baileys generateMdTagPrefix: `<uint16>.<uint16>-` (e.g. "31678.52841-").
    # The full message tag is prefix <> epoch. The server appears to validate this
    # id shape for some queries (a bare-hex id got no reply on prekey-bundle fetch).
    <<a::16, b::16>> = :crypto.strong_rand_bytes(4)
    "#{a}.#{b}-"
  end

  defp generate_message_tag(state) do
    "#{state.message_tag_prefix}#{state.message_epoch}"
  end

  @doc false
  def increment_message_epoch(state) do
    %{state | message_epoch: state.message_epoch + 1}
  end

  defp emit_to_subscribers(state, event_type, data) do
    emit_event(state, event_type, data)
    state
  end

  # Wrap a decrypted proto into the consumer %Amarula.Msg{}, pulling the envelope
  # (chat, sender, timestamp, from_me) off the stanza so the consumer never sees a
  # raw protobuf.
  # `to_addr` is our own identity — constant across a node's messages, so the caller
  # computes it once per batch (via `own_address/1`) and passes it in.
  @doc false
  def build_msg(state, proto, node, from, msg_id, to_addr) do
    # Three address roles (see Amarula.Msg): `channel` is the room (the reply handle —
    # group jid for groups, the peer for DMs). `from` is the writer (the participant in
    # a group, else the channel) and carries the sending device. `to` is whom it was
    # addressed to.
    stanza_from = Amarula.Address.parse(from)
    from_addr = node |> NodeUtils.get_attr("participant") |> maybe_address() || stanza_from
    from_me? = own_account?(state, from_addr)

    # WhatsApp fans every message we send out to our linked devices as a `from_me`
    # stanza whose `from` is our own account — so the stanza `from` is NOT the peer.
    # The real other party is the `recipient` attr (Baileys decode: own message →
    # chatId = recipient). Use it for both the room (`channel`/reply handle) and `to`,
    # so a consumer can tell "I messaged myself" (to == self) from "I messaged someone
    # else" (to == that contact). Falls back to the old behaviour when absent (e.g. a
    # peer-routed self stanza with no recipient).
    # Only for non-group stanzas: a group's room is the group jid (`from`), and
    # group messages carry `participant`, never `recipient` (Baileys applies the
    # recipient override only in the PN/LID-user branch, not the group branch).
    # `stanza_from` is nil when `from` doesn't parse (the decrypt-failure path — a
    # Signal-desynced contact: "Key used already" / old counter / bad PreKey id). Such
    # a message must NOT crash the connection (it'd loop-crash inbound + fetch_groups);
    # skip the recipient override and let the fallback branch carry the nils through.
    recipient =
      if stanza_from && stanza_from.kind != :group,
        do: node |> NodeUtils.get_attr("recipient") |> maybe_address()

    {channel, to} =
      if from_me? && recipient do
        {recipient, recipient}
      else
        {stanza_from, to_addr}
      end

    Amarula.Msg.from_proto(proto, %{
      id: msg_id,
      channel: channel,
      from: from_addr,
      to: to,
      from_me: from_me?,
      # The sender's display name, off the stanza envelope (absent on our own sends).
      pushname: NodeUtils.get_attr(node, "notify"),
      timestamp: parse_ts(NodeUtils.get_attr(node, "t"))
    })
  end

  # Our own identity as an Address (the addressed `to`), or empty before login.
  defp own_address(state) do
    case me(state)[:id] do
      id when is_binary(id) -> Amarula.Address.parse(id) || Amarula.Address.empty()
      _ -> Amarula.Address.empty()
    end
  end

  # One :message,:received per decrypted message — throughput + media volume.
  # media_bytes is the sender's declared fileLength (no eager download). Privacy:
  # counts/kinds/booleans only.
  defp emit_message_telemetry(state, msgs, node, from) do
    group? = JID.jid_group?(from)
    offline? = NodeUtils.get_attr(node, "offline") not in [nil, ""]

    Enum.each(msgs, fn msg ->
      {media?, media_kind, bytes} =
        case msg do
          %{type: :media, content: %Amarula.Content.Media{kind: kind, file_length: len}} ->
            {true, kind, len || 0}

          _ ->
            {false, nil, 0}
        end

      Amarula.Telemetry.emit(
        [:amarula, :message, :received],
        profile(state),
        %{count: 1, media_bytes: bytes},
        %{
          from_me?: msg.from_me,
          group?: group?,
          offline?: offline?,
          media?: media?,
          media_kind: media_kind
        }
      )
    end)
  end

  defp maybe_address(nil), do: nil
  defp maybe_address(jid), do: Amarula.Address.parse(jid)

  defp parse_ts(nil), do: nil
  defp parse_ts(t), do: String.to_integer(t)

  # True when `addr` is one of our own identities (id or lid).
  defp own_account?(state, %Amarula.Address{} = addr) do
    me = me(state)

    [me[:id], me[:lid]]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Amarula.Address.parse/1)
    |> Enum.any?(&Amarula.Address.same_account?(&1, addr))
  end

  defp own_account?(_state, _), do: false

  # Who actually sent this stanza, server-attested (participant for a group,
  # else the stanza `from`) — the same identity build_msg/6 uses for `from_me?`.
  # Exposed (not private) so it can be unit-tested directly, like build_msg/6.
  #
  # Callers gate the self-only protocolMessage types on this BEFORE any
  # per-message classification: APP_STATE_SYNC_KEY_SHARE and
  # HISTORY_SYNC_NOTIFICATION are only ever legitimate from our own linked
  # device. Baileys shipped this as a security fix (GHSA-qvv5-jq5g-4cgg /
  # CVE-2026-48063) — without it, anyone who can open a session with us can
  # spoof one of these to poison our app-state sync keys or feed us fake
  # history.
  @doc false
  def own_sender?(state, node, from) do
    participant = node |> NodeUtils.get_attr("participant") |> maybe_address()
    own_account?(state, participant || maybe_address(from))
  end

  defp handle_message(state, node) do
    msg_id = NodeUtils.get_attr(node, "from") && NodeUtils.get_attr(node, "id")
    from = NodeUtils.get_attr(node, "from")
    own_sender? = own_sender?(state, node, from)

    store = SessionStore.build(state.auth_creds)

    {:ok, messages, used_pre_key_ids, errors} =
      MessageDecryptor.decrypt_node(node,
        store: store,
        conn: conn(state)
      )

    state = remove_used_pre_keys(state, used_pre_key_ids)

    # The primary device shares app-state-sync keys via an APP_STATE_SYNC_KEY_SHARE
    # protocol message. Store them and (re)sync app state once we have keys — but
    # only when it genuinely came from us (own_sender? above); otherwise it's a
    # spoof attempt (CVE-2026-48063) and must be dropped.
    state =
      if own_sender? do
        maybe_handle_app_state_key_share(state, messages)
      else
        if AppStateOps.sync_keys_in(messages) != [] do
          Logger.warning(
            "dropping spoofed app-state-sync-key-share protocolMessage from non-self origin (#{from})"
          )
        end

        state
      end

    # Run the receive plugin pipeline over each decrypted message: steps may
    # transform a message or drop it (halt). Dropped messages never reach the
    # consumer; we still receipt the node so the server's offline queue drains.
    messages = run_recv_steps(state, from, msg_id, messages)

    # Baileys handleMessage: success → <receipt> (this is what removes the
    # message from the server's offline queue — a plain <ack> does NOT);
    # failure → retry receipt (asks the sender to re-encrypt, re-establishing
    # session/sender key) then <ack error="500"> nack.
    cond do
      messages != [] ->
        # Classify each decrypted message once, then split the stream so the
        # consumer's `:messages_upsert` carries only real user messages:
        #   * :sender_key — a bare senderKeyDistributionMessage (group-session-key
        #     plumbing whose side effect MessageDecryptor already applied). Dropped
        #     entirely; not user-visible in any form.
        #   * :protocol — a bare protocolMessage (the residue of control frames:
        #     ephemeral/setting changes and other types Amarula doesn't handle
        #     specially; the important ones — history-sync, app-state key-share — are
        #     already extracted to their own events/handlers upstream). Re-emitted on
        #     a separate `:protocol_update` event rather than dropped, so a consumer
        #     CAN react without it polluting `messages_upsert`.
        # User-meaningful protocolMessages (edit/revoke/member-tag) classify into
        # their own types upstream, so they stay in `messages_upsert`. We keep all of
        # them counting as a successful decrypt (we split `msgs`, not `messages`), so
        # the delivery receipt fires and we never nack a control-only node.
        to_addr = own_address(state)

        classified =
          messages
          |> Enum.map(&build_msg(state, &1, node, from, msg_id, to_addr))
          |> Enum.reject(&(&1.type == :sender_key))

        {protocol_msgs, msgs} = Enum.split_with(classified, &(&1.type == :protocol))

        if protocol_msgs != [] do
          emit_to_subscribers(state, :protocol_update, %{
            from: Amarula.Address.parse(from),
            id: msg_id,
            messages: protocol_msgs
          })
        end

        if msgs != [] do
          kinds = Enum.map(msgs, & &1.type)
          Logger.debug("Decrypted #{length(msgs)} message(s) from #{from} (#{inspect(kinds)})")

          emit_message_telemetry(state, msgs, node, from)

          emit_to_subscribers(state, :messages_upsert, %{
            from: Amarula.Address.parse(from),
            id: msg_id,
            messages: msgs
          })
        end

        state = send_delivery_receipt(state, node)

        # A message carrying a history-sync notification needs an extra
        # <receipt type="hist_sync"> — this is the signal the server waits for to
        # mark the companion's initial sync complete (Baileys messages-recv.ts).
        # Without it the phone shows the device as "Paused" / times out, and the
        # server treats the companion as not fully linked.
        #
        # Only our own linked device legitimately sends this — gated on
        # own_sender? for the same reason as the app-state-key-share branch
        # above (CVE-2026-48063): anyone else's historySyncNotification is a
        # spoof attempt, dropped without downloading or acking hist_sync.
        cond do
          not Enum.any?(messages, &history_sync_message?/1) ->
            state

          own_sender? ->
            download_history_sync(state, messages)
            send_hist_sync_receipt(state, node)

          true ->
            Logger.warning(
              "dropping spoofed history-sync-notification protocolMessage from non-self origin (#{from})"
            )

            state
        end

      # `%DecryptError{reason: :key_unavailable}` = the key material this stanza
      # references is gone: the ratchet counter was consumed, or the pkmsg's
      # one-time prekey isn't in our store. Almost always a duplicate redelivery
      # (the first decrypt consumed the key), though a genuinely unknown prekey id
      # lands here too. Either way we can't (and needn't) retry.
      #
      # We treat it as RECEIVED: send the same <receipt> the success path does
      # (which is what drains the server's offline queue), NOT an error nack. A
      # duplicate is a message we already have, so nacking 487 (ParsingError) would
      # mislabel it as a parse failure. WhatsApp does have an accurate code for this
      # exact condition — 496 (SignalErrorOldCounter) — but whatsmeow (the more
      # rigorous reference impl) defines 496 and deliberately doesn't use it either,
      # preferring the positive delivery receipt. We follow whatsmeow: it's the most
      # honest signal to the server (received, not an error) and sidesteps any
      # error-rate heuristics. (Baileys nacks 487 here; we diverge on purpose.)
      duplicate_decrypt_error?(errors) ->
        Logger.debug(
          "Message #{msg_id} from #{from}: already-decrypted duplicate — receipt as delivered"
        )

        send_delivery_receipt(state, node)

      true ->
        Logger.debug("Message #{msg_id} from #{from}: nothing decrypted — retry + nack")

        Amarula.Telemetry.emit([:amarula, :decrypt, :exception], profile(state), %{count: 1}, %{
          reason: :nothing_decrypted
        })

        state = send_retry_request(state, node)
        send_message_ack(state, node, @nack_unhandled_error)
    end
  end

  # A redelivery we can't (and needn't) retry: the key material the stanza
  # references is unavailable — the ratchet counter was consumed, or the pkmsg's
  # one-time prekey isn't in our store. The Signal layer flags this structurally as
  # `%DecryptError{reason: :key_unavailable}` (raised in `SessionCipher`/
  # `SessionBuilder`, propagated through the multi-session trial decrypt), so we
  # match the reason — not error prose, which the `msg` path wraps. It's ~always a
  # duplicate; recognising it each time is what terminates the redelivery loop,
  # which recurs on every 515 reconnect (the server re-fans the undrained stanza)
  # where an in-memory "seen msg_ids" set would be wiped by the restart. Exposed
  # for a direct test.
  @doc false
  def duplicate_decrypt_error?(errors) do
    Enum.any?(errors, &match?(%DecryptError{reason: :key_unavailable}, &1))
  end

  # One-time prekeys consumed by a PreKeySignalMessage must be deleted, like
  # libsignal's removePreKey after decryptPreKeyWhisperMessage.
  defp remove_used_pre_keys(state, []), do: state

  defp remove_used_pre_keys(state, ids) do
    Logger.debug("Removing used one-time prekey(s): #{inspect(ids)}")
    pre_keys = Map.drop(Map.get(state.auth_creds, :pre_keys, %{}), ids)
    updated_creds = Map.put(state.auth_creds, :pre_keys, pre_keys)

    update_creds(state, updated_creds)
  end

  # Ack an incoming stanza, ported from Baileys buildAckStanza (stanza-ack.ts):
  # <ack id to class={node.tag} [error] [participant] [recipient] [type] from={me}/>.
  # class must be the received node's tag — a wrong class makes the server
  # treat the ack as unrelated and redeliver. `error` (nack) marks the stanza
  # processed-with-error so it stops redelivering.
  defp send_message_ack(state, node, error_code \\ nil) do
    me_id = get_in(state.auth_creds, [:me, :id])

    attrs =
      [
        {"id", NodeUtils.get_attr(node, "id")},
        {"to", NodeUtils.get_attr(node, "from")},
        {"class", node.tag}
      ] ++
        optional_attr("error", error_code && Integer.to_string(error_code)) ++
        optional_attr("participant", NodeUtils.get_attr(node, "participant")) ++
        optional_attr("recipient", NodeUtils.get_attr(node, "recipient")) ++
        optional_attr("type", NodeUtils.get_attr(node, "type")) ++
        if(node.tag == "message" and me_id, do: [{"from", me_id}], else: [])

    ack = %Node{tag: "ack", attrs: attrs, content: nil}
    send_binary_node(state, ack)
  end

  # Delivery receipt for a successfully decrypted message, ported from Baileys
  # sendReceipt (messages-send.ts) as called by handleMessage:
  #   <receipt id to [participant] [type]/>
  # type: "peer_msg" for category="peer" stanzas, "sender" for messages sent
  # from our own phone (fromMe), absent = plain delivered.
  # True when a decrypted Proto.Message carries a history-sync notification
  # (directly or wrapped in deviceSentMessage).
  defp history_sync_message?(%{protocolMessage: %{historySyncNotification: hsn}})
       when not is_nil(hsn),
       do: true

  defp history_sync_message?(%{deviceSentMessage: %{message: inner}}) when not is_nil(inner),
    do: history_sync_message?(inner)

  defp history_sync_message?(_), do: false

  # Download + decode the history-sync blob(s) these messages reference and emit
  # the chats/contacts to the consumer. The download is a network call; run it in
  # a Task so the receive path isn't blocked, and emit from there.
  defp download_history_sync(state, messages) do
    parent = self()
    notifications = Enum.flat_map(messages, &history_notification/1)

    for hsn <- notifications do
      Task.start(fn ->
        case HistorySync.fetch(hsn) do
          {:ok, result} ->
            send(parent, {:history_sync_result, result})

          {:error, reason} ->
            Logger.warning("history-sync download failed: #{inspect(reason)}")
        end
      end)
    end

    state
  end

  defp history_notification(%{protocolMessage: %{historySyncNotification: hsn}})
       when not is_nil(hsn),
       do: [hsn]

  defp history_notification(%{deviceSentMessage: %{message: inner}}) when not is_nil(inner),
    do: history_notification(inner)

  defp history_notification(_), do: []

  # Baileys sendReceipt(jid, _, [id], 'hist_sync'): <receipt type="hist_sync"
  # to=<bare-user jid> id=..>. Tells the server we received the history sync so it
  # marks initial sync complete (device leaves "Paused").
  defp send_hist_sync_receipt(state, node) do
    from = NodeUtils.get_attr(node, "from")
    jid = JID.jid_normalized_user(from)

    receipt = %Node{
      tag: "receipt",
      attrs: [
        {"id", NodeUtils.get_attr(node, "id")},
        {"to", jid},
        {"type", "hist_sync"}
      ],
      content: nil
    }

    Logger.debug("Sending hist_sync receipt (initial-sync ack)")
    send_binary_node(state, receipt)
  end

  defp send_delivery_receipt(state, node) do
    from = NodeUtils.get_attr(node, "from")
    participant = NodeUtils.get_attr(node, "participant")
    category = NodeUtils.get_attr(node, "category")
    author = participant || from

    type =
      cond do
        category == "peer" -> "peer_msg"
        author_is_me?(state, author) -> "sender"
        true -> nil
      end

    # Baileys: for type="sender" on a 1:1 (pn/lid) jid, recipient=jid and
    # to=participant; without a participant fall back to the plain form.
    to_attrs =
      if type == "sender" and participant do
        [{"recipient", from}, {"to", participant}]
      else
        [{"to", from}] ++ optional_attr("participant", participant)
      end

    attrs =
      [{"id", NodeUtils.get_attr(node, "id")}] ++ to_attrs ++ optional_attr("type", type)

    receipt = %Node{tag: "receipt", attrs: attrs, content: nil}
    send_binary_node(state, receipt)
  end

  # Retry receipt for a message we failed to decrypt, ported from Baileys
  # sendRetryRequest (messages-recv.ts, minus the retry-manager/placeholder
  # machinery): <receipt id type="retry" to [participant] [recipient]> with
  # <retry count id t v error/> + <registration/>; from the second retry on,
  # a <keys> bundle (one-time prekey + signed prekey + device identity) so the
  # sender can rebuild the session from scratch.
  defp send_retry_request(state, node) do
    msg_id = NodeUtils.get_attr(node, "id")
    participant = NodeUtils.get_attr(node, "participant")

    # Counter is keyed on the participant (not the message id) so repeated
    # failures from the SAME broken sender escalate: count>1 attaches the
    # <keys> bundle, which a sender with no session to us needs to redistribute
    # its sender key. Baileys keys on msgId:participant, but a member whose SKDM
    # we lost sends a NEW bare skmsg each time, so a per-message counter would
    # never escalate and the keys bundle would never go out.
    cache_key = participant || NodeUtils.get_attr(node, "from")
    retry_count = Map.get(state.msg_retry_counts, cache_key, 0) + 1

    if retry_count > @max_msg_retry_count do
      Logger.warning("Retry limit reached for #{cache_key} — giving up")
      %{state | msg_retry_counts: Map.delete(state.msg_retry_counts, cache_key)}
    else
      state = %{state | msg_retry_counts: Map.put(state.msg_retry_counts, cache_key, retry_count)}

      retry_child = %Node{
        tag: "retry",
        attrs: [
          {"count", Integer.to_string(retry_count)},
          {"id", msg_id},
          {"t", NodeUtils.get_attr(node, "t") || ""},
          {"v", "1"},
          {"error", "0"}
        ],
        content: nil
      }

      registration_child = %Node{
        tag: "registration",
        attrs: %{},
        content: <<state.auth_creds.registration_id::big-unsigned-32>>
      }

      {state, extra_children} =
        if retry_count > 1 do
          {state, keys_node} = build_retry_keys_node(state)
          {state, [keys_node]}
        else
          {state, []}
        end

      attrs =
        [
          {"id", msg_id},
          {"type", "retry"},
          {"to", NodeUtils.get_attr(node, "from")}
        ] ++
          optional_attr("participant", participant) ++
          optional_attr("recipient", NodeUtils.get_attr(node, "recipient"))

      receipt = %Node{
        tag: "receipt",
        attrs: attrs,
        content: [retry_child, registration_child] ++ extra_children
      }

      Logger.debug("Sending retry receipt for message #{msg_id} (count=#{retry_count})")

      # `attempt` is the escalating per-peer retry count: a one-off is normal, a
      # climbing attempt means a peer we can't re-establish a session with (poison
      # message / lost sender key). That's the signal worth alerting on.
      Amarula.Telemetry.emit([:amarula, :retry, :sent], profile(state), %{
        count: 1,
        attempt: retry_count
      })

      send_binary_node(state, receipt)
    end
  end

  # <keys> bundle for a retry receipt: reserves a fresh one-time prekey
  # (persisted internally) and includes identity + signed prekey + device
  # identity, mirroring Baileys' getNextPreKeys(authState, 1) block.
  defp build_retry_keys_node(state) do
    creds = state.auth_creds
    {updated_creds, [{key_id, pair} | _]} = PreKeys.get_next_pre_keys(creds, 1)

    state = update_creds(state, updated_creds)

    keys_node = %Node{
      tag: "keys",
      attrs: %{},
      content: [
        %Node{tag: "type", attrs: %{}, content: PreKeys.key_bundle_type()},
        %Node{tag: "identity", attrs: %{}, content: creds.signed_identity_key.public},
        PreKeys.xmpp_pre_key(pair, key_id),
        PreKeys.xmpp_signed_pre_key(creds.signed_pre_key),
        %Node{
          tag: "device-identity",
          attrs: %{},
          content: DeviceIdentity.encode(creds.account, true)
        }
      ]
    }

    {state, keys_node}
  end

  # fromMe: the author is one of our own identities (pn or lid user part).
  defp author_is_me?(state, author) do
    me = Map.get(state.auth_creds, :me) || %{}

    author_user =
      case JID.decode(author) do
        %{user: user} -> user
        _ -> nil
      end

    my_users =
      [Map.get(me, :id), Map.get(me, :lid)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn jid ->
        case JID.decode(jid) do
          %{user: user} -> user
          _ -> nil
        end
      end)

    author_user != nil and author_user in my_users
  end

  defp optional_attr(_key, nil), do: []
  defp optional_attr(key, value), do: [{key, value}]

  # --- app-state sync (C2) ---

  alias Amarula.Protocol.AppState.{Keys, Patch, Sync}

  # Store any app-state-sync keys shared in these messages; resync if we got some.
  defp maybe_handle_app_state_key_share(state, messages) do
    case AppStateOps.sync_keys_in(messages) do
      [] ->
        state

      keys ->
        Enum.each(keys, fn {key_id_b64, key_data} ->
          Amarula.Storage.put(
            scope(state),
            profile(state),
            :app_state_sync_key,
            key_id_b64,
            key_data
          )
        end)

        Logger.debug("Stored #{length(keys)} app-state-sync key(s); syncing app state")
        resync_app_state(state)
    end
  end

  # Request + decode patches for the named collections (all by default), persist
  # new state, emit changes. A server_sync notification names ONE collection, so
  # we resync just that one (Baileys: resyncAppState([name])) rather than hammer
  # the server with all five.
  defp resync_app_state(state, names \\ Sync.collections()) do
    collections =
      Enum.map(names, fn name ->
        st = load_collection_state(state, name)
        {name, st.version, st.version == 0}
      end)

    iq = Sync.request_iq(collections)
    # Tracked (not blocking): the reply continues in handle_tracked_iq(:app_state_sync).
    send_tracked_iq(state, iq, :app_state_sync)
  end

  defp apply_app_state_reply(state, reply) do
    get_key = fn id_b64 ->
      case Amarula.Storage.get(scope(state), profile(state), :app_state_sync_key, id_b64) do
        {:ok, key_data} -> Keys.expand(key_data)
        :error -> nil
      end
    end

    reply
    |> Sync.extract_collections()
    |> Enum.each(fn %{name: name, patches: patches} ->
      prior = load_collection_state(state, name)

      case Sync.decode_collection(patches, prior, get_key, name) do
        {:ok, changes, new_state} ->
          save_collection_state(state, name, new_state)
          emit_app_state_changes(state, changes)

        {:error, reason} ->
          # A patch whose snapshot/patch MAC doesn't match is unauthenticated — drop
          # it (don't persist the state or emit changes). Prior state is kept, so the
          # next resync re-requests from the same version.
          Logger.warning("app-state sync for #{name} rejected (#{inspect(reason)}); not applied")
      end
    end)
  end

  defp emit_app_state_changes(state, changes) do
    {chats, contacts} = AppStateOps.partition_changes(changes)
    if chats != [], do: emit_to_subscribers(state, :chats_update, chats)
    if contacts != [], do: emit_to_subscribers(state, :contacts_update, contacts)
  end

  defp load_collection_state(state, name) do
    case Amarula.Storage.get(scope(state), profile(state), :app_state_version, name) do
      {:ok, st} -> st
      :error -> Patch.new_state()
    end
  end

  defp save_collection_state(state, name, st) do
    Amarula.Storage.put(scope(state), profile(state), :app_state_version, name, st)
  end

  defp scope(state), do: state.conn.storage

  # The connection handle (Amarula.Conn) — the one built at connect, carrying the
  # storage/retry-cache scopes, profile, and plugin pipelines.
  defp conn(state), do: state.conn

  defp profile(state), do: state.conn.profile

  # Resolve startup creds: explicit config[:auth] > profile's stored creds >
  # freshly generated. Amarula owns persistence (Storage :creds/:self), so a
  # consumer normally just names a :profile and never touches credentials.
  defp resolve_auth_creds(conn, config) do
    case Map.get(config, :auth) do
      creds when is_map(creds) and map_size(creds) > 0 ->
        Logger.info("Using auth credentials from config")
        creds

      _ ->
        case Amarula.Storage.get(conn.storage, conn.profile, :creds, :self) do
          {:ok, creds} ->
            Logger.info("Loaded stored credentials for profile #{inspect(conn.profile)}")
            creds

          :error ->
            Logger.info("No stored credentials for #{inspect(conn.profile)} — generating new")
            AuthUtils.init_auth_creds()
        end
    end
  end

  # The single path for a credentials change: store the new creds in state and
  # write them to the profile's storage. Amarula OWNS credential persistence (the
  # Storage :creds/:self entry the next connect reloads), so there is no public
  # :creds_update event — the consumer never handles credentials.
  defp update_creds(state, new_creds) do
    state = %{state | auth_creds: new_creds}
    Amarula.Storage.put(scope(state), profile(state), :creds, :self, new_creds)
    state
  end

  # The logged-in identity (me.id/me.lid/me.name) from auth creds.
  defp me(state), do: Map.get(state.auth_creds, :me, %{})

  # A PUSH_NAME history-sync carries push names by jid. If ours is in there and we
  # only have the "~" placeholder, adopt the real name, persist it, and re-send
  # presence (the phone shows the real device name + flips active).
  defp learn_own_push_name(state, []), do: state

  defp learn_own_push_name(state, push_names) do
    me = me(state)
    my_users = [me[:id], me[:lid]] |> Enum.reject(&is_nil/1) |> Enum.map(&Amarula.Address.parse/1)

    real_name =
      Enum.find_value(push_names, fn {jid, name} ->
        addr = Amarula.Address.parse(jid)
        if addr && Enum.any?(my_users, &Amarula.Address.same_account?(&1, addr)), do: name
      end)

    if real_name && me[:name] in [nil, "~"] do
      new_state = update_creds(state, put_in(state.auth_creds, [:me, :name], real_name))
      Logger.info("Learned push name: #{inspect(real_name)} — refreshing presence")
      # Honor mark_online_on_connect here too: learning the name must not force a
      # connection that opted out of presence back online.
      maybe_mark_online(new_state)
    else
      state
    end
  end

  defp retry_cache(state), do: state.conn.retry_cache

  # Run the receive pipeline over each message; keep transformed ones, drop halts.
  defp run_recv_steps(%{conn: %{recv_steps: []}}, _from, _id, messages), do: messages

  defp run_recv_steps(state, from, id, messages) do
    steps = state.conn.recv_steps
    profile = state.conn.profile

    Enum.flat_map(messages, fn message ->
      ctx = %{message: message, from: from, id: id, profile: profile}

      case Amarula.Plugin.run(steps, ctx) do
        {:cont, %{message: m}} -> [m]
        {:halt, _reason} -> []
      end
    end)
  end

  # init/1 accepts a built %Conn{} (normal path) or a bare config map (tests that
  # start Connection directly). For the bare map, default :profile so a
  # storage-agnostic test needn't supply one; real connects go through
  # Amarula.new/1, which still requires :profile.
  defp normalize_conn(%Amarula.Conn{} = conn), do: conn

  defp normalize_conn(config) when is_map(config) do
    config |> Map.put_new(:profile, :default) |> Amarula.Conn.new()
  end

  @doc """
  Strip a decoded frame's 1-byte prefix, inflating when compressed. Bit 1 (0x02)
  of the prefix means the remainder is zlib-compressed (Baileys
  decompressingIfRequired); the server compresses larger frames. Public for
  testability.
  """
  @spec decompress_frame(binary()) :: binary()
  def decompress_frame(<<prefix, rest::binary>>) when Bitwise.band(prefix, 2) == 2 do
    :zlib.uncompress(rest)
  end

  def decompress_frame(<<_prefix, rest::binary>>), do: rest
  def decompress_frame(frame), do: frame

  # When AMARULA_CAPTURE_DIR is set, dump each decrypted (post-noise) binary-node
  # frame to a timestamped .bin file so it can be replayed offline through
  # Decoder/MessageDecryptor without re-pairing or re-sending. No-op otherwise.
  defp maybe_capture_frame(frame) do
    case System.get_env("AMARULA_CAPTURE_DIR") do
      nil ->
        :ok

      dir ->
        File.mkdir_p(dir)
        name = "frame-#{System.system_time(:microsecond)}.bin"
        File.write(Path.join(dir, name), frame)
        :ok
    end
  end

  defp handle_auth_success(state, node) do
    Logger.info("Authentication successful!")

    # Clear waiting state since we got a response
    state = clear_server_response_waiting(state)

    # Extract LID from success node
    lid = NodeUtils.get_attr(node, "lid")

    # Update auth credentials with LID
    updated_creds =
      if lid do
        %{state.auth_creds | me: %{state.auth_creds.me | lid: lid}}
      else
        state.auth_creds
      end

    # Persist the logged-in creds (now carrying me.lid) and signal open
    new_state = if lid, do: update_creds(state, updated_creds), else: state

    # Baileys CB:success order: uploadPreKeysToServerIfRequired, then
    # sendPassiveIq('active'). The count query is async here, so the passive IQ
    # is sent from the prekey-count/upload continuations (or their error paths),
    # which converge in finish_login — where we emit :open. Emitting :open here
    # (before passive 'active') let senders fire prekey-bundle fetches the server
    # silently ignores until the connection is active.
    request_pre_key_count(new_state)
  end

  # --- IQ request/response correlation by message id ---
  #
  # `pending_iqs` maps an outbound IQ id to who is waiting for the reply. Two
  # shapes coexist:
  #
  #   {:waiter, from, timer}  — a process blocked in query_iq/2 (sends); the
  #                             reply is delivered with GenServer.reply/2.
  #   {:tracked, kind, timer} — the login bootstrap sequence, continued inline
  #                             via handle_tracked_iq/3.
  #
  # Connection holds no send logic: a query_iq caller blocks until the
  # websocket answers, then gets the raw reply. The meaning of the reply lives
  # in the caller (the per-recipient ConversationSender).

  # Blocking IQ request used by the send path: returns {:ok, node} | {:error,
  # node | :timeout} only once the matching websocket reply arrives. The caller
  # (a ConversationSender) blocks; Connection keeps owning the socket.
  defp send_tracked_iq(state, %Node{} = node, kind) do
    {state, _id} = send_tracked_iq_with_id(state, node, kind)
    state
  end

  defp send_tracked_iq_with_id(state, %Node{} = node, kind) do
    {state, id, node} = stamp_iq(state, node)
    timer = Process.send_after(self(), {:iq_timeout, id}, @iq_timeout_ms)
    state = %{state | pending_iqs: IQ.track(state.pending_iqs, id, kind, timer)}
    {send_binary_node(state, node), id}
  end

  # Like query_iq, but applies `transform` to the {:ok,node}|{:error,node} result
  # before replying to `from` — used for queries that return a parsed value
  # (e.g. group metadata → %Amarula.Group{}).
  defp send_waiter_iq(state, %Node{} = node, from, transform) do
    if ready_to_send?(state) do
      {state, id, node} = stamp_iq(state, node)
      timer = Process.send_after(self(), {:iq_timeout, id}, @iq_timeout_ms)
      state = %{state | pending_iqs: IQ.wait(state.pending_iqs, id, from, timer, transform)}
      send_binary_node(state, node)
    else
      # Called from {:noreply, send_waiter_iq(...)} clauses — reply the waiter
      # directly rather than park it behind a frame that can never go out.
      GenServer.reply(from, {:error, :not_connected})
      state
    end
  end

  # Stamp an outbound IQ with the next id and advance the message epoch.
  defp stamp_iq(state, node) do
    id = generate_message_tag(state)
    state = increment_message_epoch(state)
    {state, id, %{node | attrs: put_attr(node.attrs, "id", id)}}
  end

  defp put_attr(attrs, key, value) when is_list(attrs), do: attrs ++ [{key, value}]
  defp put_attr(attrs, key, value) when is_map(attrs), do: Map.put(attrs, key, value)

  # IQ correlation lives in Socket.IQ (pure over the pending map); CM performs the
  # effect it returns (reply a blocked caller / run a tracked continuation).
  defp handle_iq_response(state, node) do
    id = NodeUtils.get_attr(node, "id")
    {pending, effect} = IQ.resolve(state.pending_iqs, node)

    if effect == :none do
      Logger.debug(
        "IQ reply #{id} had no pending waiter; pending=#{inspect(Map.keys(state.pending_iqs))}"
      )
    end

    perform_iq_effect(effect, %{state | pending_iqs: pending})
  end

  defp handle_iq_timeout(state, id) do
    {pending, effect} = IQ.timeout(state.pending_iqs, id)

    # An IQ timeout is the primary sick-connection signal — count it. Tracked
    # IQs carry their bootstrap kind (:prekey_count/:digest/:app_state_sync/…);
    # a blocking waiter has none, so `kind` is omitted rather than invented.
    # :none = the reply raced the timer — nothing actually timed out.
    case effect do
      {:tracked, kind, _result, _timer} ->
        Logger.warning("IQ #{id} (#{kind}) timed out after #{@iq_timeout_ms}ms")

        Amarula.Telemetry.emit([:amarula, :iq, :timeout], profile(state), %{count: 1}, %{
          kind: kind
        })

      {:reply, _from, _result, _timer} ->
        Amarula.Telemetry.emit([:amarula, :iq, :timeout], profile(state), %{count: 1})

      :none ->
        :ok
    end

    perform_iq_effect(effect, %{state | pending_iqs: pending})
  end

  defp perform_iq_effect(:none, state), do: state

  defp perform_iq_effect({:reply, from, result, timer}, state) do
    Process.cancel_timer(timer)
    GenServer.reply(from, result)
    state
  end

  defp perform_iq_effect({:tracked, kind, result, timer}, state) do
    Process.cancel_timer(timer)
    handle_tracked_iq(kind, result, state)
  end

  # --- Pre-key upload (Baileys uploadPreKeysToServerIfRequired) ---

  # Ask the server how many of our one-time prekeys it still holds.
  defp request_pre_key_count(state) do
    send_tracked_iq(state, PreKeyOps.count_query_node(), :prekey_count)
  end

  defp handle_tracked_iq(:app_state_sync, {:ok, node}, state) do
    apply_app_state_reply(state, node)
    state
  end

  defp handle_tracked_iq(:app_state_sync, {:error, reason}, state) do
    Logger.warning("app-state sync IQ failed: #{inspect(reason)}")
    state
  end

  defp handle_tracked_iq(:prekey_count, {:ok, node}, state) do
    server_count = PreKeyOps.server_count(node)
    target = PreKeyOps.upload_target(server_count)

    Logger.debug("#{server_count} pre-keys found on server")

    if PreKeyOps.upload_needed?(server_count, target, state.auth_creds) do
      upload_pre_keys(state, target)
    else
      finish_login(state)
    end
  end

  defp handle_tracked_iq(:prekey_count, {:error, reason}, state) do
    Logger.warning("Pre-key count query failed (#{inspect(reason)}) — continuing without upload")
    finish_login(state)
  end

  defp handle_tracked_iq(:prekey_upload, {:ok, _node}, state) do
    Logger.debug("Uploaded pre-keys successfully")
    finish_login(state)
  end

  defp handle_tracked_iq(:prekey_upload, {:error, reason}, state) do
    Logger.error("Pre-key upload failed: #{inspect(reason)}")
    finish_login(state)
  end

  # Digest failure → one-shot top-up via :prekey_reupload, which must NOT
  # re-enter finish_login (that would loop: digest fail → upload → finish_login
  # → digest → ...). Baileys likewise just uploads MIN_PREKEY_COUNT and logs.
  defp handle_tracked_iq(:digest, {:ok, node}, state) do
    case NodeUtils.get_binary_node_child(node, "digest") do
      nil ->
        Logger.warning("digest IQ returned no <digest> node — re-uploading prekeys")
        upload_pre_keys(state, PreKeys.min_pre_key_count(), :prekey_reupload)

      _ ->
        Logger.debug("Key bundle digest verified")
        state
    end
  end

  defp handle_tracked_iq(:digest, {:error, reason}, state) do
    Logger.warning("digest IQ failed (#{inspect(reason)}) — re-uploading prekeys")
    upload_pre_keys(state, PreKeys.min_pre_key_count(), :prekey_reupload)
  end

  defp handle_tracked_iq(:prekey_reupload, {:ok, _node}, state) do
    Logger.debug("Re-uploaded pre-keys after digest failure")
    state
  end

  defp handle_tracked_iq(:prekey_reupload, {:error, reason}, state) do
    Logger.error("Pre-key re-upload failed: #{inspect(reason)}")
    state
  end

  # Force-refresh of LID sessions (assertSessions force). Inject the fetched
  # bundles; the injector LID-resolves the addresses so they overwrite/seed the
  # LID-keyed sessions the send path uses. Best-effort: failures are logged only.
  defp handle_tracked_iq(:assert_lid_sessions, {:ok, node}, state) do
    injected = SessionInjector.inject(node, state.auth_creds, conn(state))
    Logger.debug("Force-refreshed #{injected} LID session(s)")
    state
  end

  defp handle_tracked_iq(:assert_lid_sessions, {:error, reason}, state) do
    Logger.warning("LID session force-refresh failed: #{inspect(reason)}")
    state
  end

  defp handle_tracked_iq(:clean_dirty, {:ok, _node}, state) do
    Logger.debug("Dirty bits cleared")
    state
  end

  defp handle_tracked_iq(:clean_dirty, {:error, reason}, state) do
    Logger.warning("Clean dirty bits failed: #{inspect(reason)}")
    state
  end

  # Mirrors Baileys CB:success body (passive IQ, unified_session, digest key
  # bundle) plus the connection-open presence (markOnlineOnConnect default).
  defp finish_login(state) do
    # Login succeeded — this is where the reconnect backoff counter resets.
    state =
      %{state | retry_count: 0}
      |> send_passive_iq("active")
      |> send_unified_session()
      |> send_digest_iq()
      |> send_init_queries()
      |> maybe_mark_online()

    # Emit :open here, on CB:success (after passive 'active' + digest + init
    # queries), mirroring Baileys socket.ts which emits `connection: 'open'` in its
    # CB:success handler — NOT gated on offline drain. `receivedPendingNotifications`
    # is a separate, later signal in Baileys and does not gate sends.
    emit_to_subscribers(state, :connection_update, %{connection: :open, qr: nil})
    state
  end

  # Presence-available on connect is gated by the per-connection
  # `:mark_online_on_connect` setting (default true; passed to `Amarula.new/1`).
  #
  # When false, the companion stays "unavailable" to the server: it appears
  # OFFLINE to other users and the PRIMARY PHONE keeps receiving push
  # notifications — the documented trade-off (Baileys #2553). Live messages are
  # then queued offline rather than pushed straight to this session, so a
  # consumer that wants real-time delivery should leave this at the default true
  # (or call `set_presence(:available)` explicitly).
  defp maybe_mark_online(state) do
    if mark_online?(state.config) do
      send_presence_available(state)
    else
      Logger.debug("mark_online_on_connect: false — staying unavailable on connect")
      state
    end
  end

  @doc false
  # Whether to send presence-available on connect. Per-connection setting (passed
  # to `Amarula.new/1`), default true. Public-ish (`@doc false`) so the gate is
  # unit-testable without a live login.
  def mark_online?(config), do: Map.get(config, :mark_online_on_connect, true)

  # Baileys sendPresenceUpdate('available'): <presence name={me.name} type="available"/>.
  defp send_presence_available(state) do
    # Personal accounts (and profiles paired before push-name learning existed)
    # carry no me.name; "~" is the bootstrap placeholder WhatsApp accepts. The
    # real push name self-heals later from the PUSH_NAME history sync.
    name = get_in(state.auth_creds, [:me, :name]) || "~"

    node = %Node{
      tag: "presence",
      attrs: [{"name", String.replace(name, "@", "")}, {"type", "available"}],
      content: nil
    }

    Logger.debug("Sending presence available (name: #{name})")
    send_binary_node(state, node)
  end

  defp upload_pre_keys(state, count, kind \\ :prekey_upload) do
    Logger.debug("Uploading #{count} pre-keys")
    {updated_creds, node} = PreKeys.get_next_pre_keys_node(state.auth_creds, count)

    # Persist the generated prekeys before the upload round-trip so a crash
    # can't leave the server holding keys we no longer have (Baileys saves
    # inside the keys.transaction for the same reason).
    state = update_creds(state, updated_creds)

    send_tracked_iq(state, node, kind)
  end
end
