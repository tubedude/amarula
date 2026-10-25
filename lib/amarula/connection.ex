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
  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.ProfileRegistry
  alias Amarula.Protocol.Socket.{IQ, Login, Router}
  alias Amarula.Protocol.Binary.{Decoder, JID, NodeUtils, Encoder, Node}
  alias Amarula.Protocol.Messages.{ConversationSender, Media, MessageEncoder}
  alias Amarula.Protocol.Messages.{HistorySync, MessageDecryptor}
  alias Amarula.MessageSecretStore
  alias Amarula.Protocol.Presence
  alias Amarula.Protocol.Call
  alias Amarula.Protocol.Proto

  # A send blocks the caller until the per-recipient sender finishes (up to three
  # IQ round-trips for a new recipient). The client-side call timeout must exceed
  # that worst case — see ConversationSender's own bound.
  @send_call_timeout_default 90_000

  @doc false
  # The GenServer.call deadline shared by every consumer send/fetch — here and on
  # the `Amarula` facade, so both honour `config :amarula, send_call_timeout_ms:`.
  # Read at call time (not a module attribute) so runtime config applies.
  @spec send_call_timeout() :: timeout()
  def send_call_timeout,
    do: Application.get_env(:amarula, :send_call_timeout_ms, @send_call_timeout_default)

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

  # How long to wait for the phone's <notification type="mediaretry"> reply to a
  # server-error receipt before failing the waiting caller (the phone re-uploads
  # off its own copy, so this can take longer than an IQ round-trip).
  @media_retry_timeout_ms 30_000

  # The <ack> wait (default 30s, config :ack_timeout_ms) lives on
  # Connection.AckLifecycle now; send_call_timeout/0 must still exceed it.
  alias Amarula.Protocol.Crypto.Constants

  alias Amarula.Protocol.Signal.{PreKeys, SessionInjector, SessionStore}
  alias Amarula.Protocol.Signal.{DeviceListCache, TcTokenStore}
  alias Amarula.Protocol.Messages.Receipt
  alias Amarula.Protocol.Groups.Notification, as: GroupNotification

  alias Amarula.Connection.{
    AckLifecycle,
    AppStateOps,
    GroupOps,
    Notifications,
    Pairing,
    PreKeyOps,
    Receive,
    SendOps,
    SessionOps
  }

  # This is the per-connection coordinator: one process owning the websocket,
  # Noise state, IQ correlation, ack parking, and several in-flight task maps (see
  # the moduledoc). The fields are cohesive, and grouping them into sub-maps would
  # churn every `state.x` access across this module for no behavioural gain. The
  # check guards Erlang's 32-key flatmap→hashmap switch, which this struct passed
  # long before the current count — so the representation is unchanged either way.
  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
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
    :qr_ref,
    :qr_timer,
    :task_supervisor,
    pending_iqs: %{},
    msg_retry_counts: %{},
    pending_sends: %{},
    pending_acks: %{},
    pending_media_retries: %{},
    sender_monitors: %{},
    media_tasks: %{},
    tctoken_recoveries: %{},
    migrated_pn_sessions: MapSet.new()
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
          qr_ref: String.t() | nil,
          qr_timer: reference() | nil,
          # Connection-owned Task.Supervisor (started linked in init) running the
          # off-process work — media prep and history-sync downloads. Linked, so it
          # dies with Connection and takes its in-flight tasks with it; nil only for
          # a not-yet-initialised state.
          task_supervisor: pid() | nil,
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
          sender_monitors: %{String.t() => reference()},
          # In-flight media-prep tasks (async_nolink), keyed by the task's monitor
          # ref → the parked caller `from` + target jid. The task result replies via
          # the {ref, result} message; a task crash replies via its {:DOWN, ref, …}.
          media_tasks: %{reference() => {GenServer.from(), String.t()}},
          # In-flight 463 tctoken recoveries (async_nolink), monitor ref → jid.
          # Guards against concurrent 463s for one contact each spawning an
          # issuance IQ (Baileys' `inFlight463Recoveries`).
          tctoken_recoveries: %{reference() => {:send | :recover, String.t()}},
          # Media re-upload requests awaiting the phone's mediaretry notification,
          # keyed by msg id. Each holds the consumer's `from`, the media_key needed
          # to decrypt the reply, and the timeout timer.
          pending_media_retries: %{
            String.t() => {GenServer.from(), binary(), reference()}
          },
          # PN users whose Signal sessions have been migrated onto their LID this
          # connection — an idempotency guard so we migrate once, not per message.
          migrated_pn_sessions: MapSet.t(String.t())
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

  # Internal plumbing; not part of the consumer API.
  @doc false
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

  # Internal: the documented entry point is `Amarula.connect/2`.
  @doc false
  def connect(pid) do
    GenServer.call(pid, :connect)
  end

  # Internal: the documented entry point is `Amarula.disconnect/1`.
  @doc false
  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  # Internal: the documented entry point is `Amarula.stop/1`.
  @doc false
  @spec stop(pid()) :: :ok | {:error, :not_found}
  def stop(pid) do
    case GenServer.call(pid, :instance_id) do
      nil -> {:error, :not_found}
      instance_id -> ConnectionSupervisor.stop_instance(instance_id)
    end
  end

  # Internal: the documented entry point is `Amarula.connection_state/1`.
  @doc false
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

  # Internal plumbing; not part of the consumer API.
  @doc false
  @spec canonical_jid(GenServer.server(), String.t()) :: String.t()
  def canonical_jid(pid, jid) when is_binary(jid) do
    GenServer.call(pid, {:canonical_jid, jid})
  end

  # Internal: the documented entry point is `Amarula.own_chat?/2`.
  @doc false
  @spec own_chat?(GenServer.server(), Amarula.Msg.t()) :: boolean()
  def own_chat?(pid, %Amarula.Msg{} = msg) do
    GenServer.call(pid, {:own_chat?, msg})
  end

  # The connection's `%Amarula.Conn{}` — its storage scope + profile. Library code
  # that needs to read/write the Storage seam (sessions, LID mappings) from the
  # *caller's* process holds the pid; this hands it the `%Conn{}` those stores key
  # by. Internal: consumers use the higher-level facade calls.
  @doc false
  @spec get_conn(GenServer.server()) :: Amarula.Conn.t()
  def get_conn(pid), do: GenServer.call(pid, :conn)

  # Send an IQ and block until the matching websocket reply arrives.
  # Returns `{:ok, node}` on a `type="result"` reply, `{:error, node}` on an
  # error reply, or `{:error, :timeout}` if no reply comes within the IQ timeout.
  # The caller (a `ConversationSender`) blocks; Connection keeps owning the
  # socket and just routes the reply back. This is the only correlation primitive
  # the send path needs — no continuation logic lives here.
  @doc false
  @spec query_iq(GenServer.server(), Amarula.Protocol.Binary.Node.t(), timeout()) ::
          {:ok, Amarula.Protocol.Binary.Node.t()}
          | {:error, Amarula.Protocol.Binary.Node.t() | :timeout | :not_connected}
  def query_iq(pid, node, timeout \\ 25_000) do
    GenServer.call(pid, {:query_iq, node}, timeout)
  end

  # Frame and send a stanza over the websocket (fire-and-forget; no IQ reply
  # awaited). Used by the send path to relay the final `<message>`.
  @doc false
  @spec relay_stanza(GenServer.server(), Amarula.Protocol.Binary.Node.t()) ::
          :ok | {:error, :not_connected}
  def relay_stanza(pid, node) do
    GenServer.call(pid, {:relay_stanza, node})
  end

  # Run `fun` (arity 0) as a supervised, fire-and-forget task under this
  # connection's `Task.Supervisor` — for best-effort background work a caller
  # (e.g. `ConversationSender`) doesn't hold a `task_supervisor` pid for itself.
  # No result is returned to the caller; a raise is contained by the supervisor.
  # Internal: not part of the consumer API.
  @doc false
  @spec run_background(GenServer.server(), (-> any())) :: :ok
  def run_background(pid, fun) when is_function(fun, 0) do
    GenServer.cast(pid, {:run_background, fun})
  end

  # Ask Connection to issue a trusted-contact token for `jid`, deduped against
  # any issuance already in flight for that contact. Internal: the send path
  # calls this after a 1:1 send.
  @doc false
  @spec issue_tctoken_async(GenServer.server(), String.t()) :: :ok
  def issue_tctoken_async(pid, jid), do: GenServer.cast(pid, {:issue_tctoken, jid})

  # Fire an `issuePrivacyTokens` IQ for `jid` and store whatever trusted-contact
  # token(s) come back (`TcTokenStore`), so a *future* 1:1 send to `jid` has one
  # to attach. Best-effort and fire-and-forget by design: an IQ failure is logged
  # and swallowed here — this never blocks or retries the message that triggered
  # it (see `TcTokenStore` moduledoc and the 463 handling in `handle_message_ack/2`).
  # Internal: not part of the consumer API.
  @doc false
  @spec issue_tctoken(GenServer.server(), Amarula.Conn.t(), String.t()) :: :ok
  def issue_tctoken(pid, conn, jid) do
    ts = System.system_time(:second)
    iq = TcTokenStore.build_issue_iq(conn, jid, ts)

    # Only record on success. `store_result/4` stamps `sender_timestamp`, which
    # `should_issue_new?/2` reads to skip re-issuing for the rest of the ~7-day
    # bucket — so stamping after a failed IQ (timeout, disconnect mid-send) would
    # suppress issuance for that contact for a week over a transient error.
    # Baileys likewise records only in the success branch.
    case query_iq(pid, iq) do
      {:ok, node} ->
        TcTokenStore.store_result(conn, node, jid, ts)

      {:error, reason} ->
        Logger.debug("tctoken issuance for #{jid} failed: #{inspect(reason)}")
        :ok
    end
  end

  # Internal: LID session refresh, driven by the receive path.
  @doc false
  @spec assert_lid_sessions(GenServer.server(), [String.t()]) :: :ok
  def assert_lid_sessions(_pid, []), do: :ok
  def assert_lid_sessions(pid, lids), do: GenServer.cast(pid, {:assert_lid_sessions, lids})

  # Internal plumbing; not part of the consumer API.
  @doc false
  @spec migrate_pn_sessions(GenServer.server(), [{String.t(), String.t()}]) :: :ok
  def migrate_pn_sessions(_pid, []), do: :ok
  def migrate_pn_sessions(pid, pairs), do: GenServer.call(pid, {:migrate_pn_sessions, pairs})

  # Internal plumbing; not part of the consumer API.
  @doc false
  @spec notify_lid_mappings(GenServer.server(), [{String.t(), String.t()}]) :: :ok
  def notify_lid_mappings(_pid, []), do: :ok
  def notify_lid_mappings(pid, pairs), do: GenServer.cast(pid, {:notify_lid_mappings, pairs})

  # Internal: the documented entry point is `Amarula.AppState.force_resync/2`.
  @doc false
  @spec force_resync_app_state(GenServer.server(), [String.t()] | :all) :: :ok
  def force_resync_app_state(pid, names \\ :all),
    do: GenServer.cast(pid, {:force_resync_app_state, names})

  # Internal: the documented entry point is `Amarula.set_presence/2`.
  @doc false
  @spec set_presence(GenServer.server(), :available | :unavailable) :: :ok | {:error, term()}
  def set_presence(pid, type), do: GenServer.call(pid, {:set_presence, type})

  # Internal: the documented entry point is `Amarula.send_chatstate/3`.
  @doc false
  @spec send_chatstate(GenServer.server(), Amarula.jid(), :composing | :recording | :paused) ::
          :ok | {:error, :not_connected}
  def send_chatstate(pid, jid, type),
    do: GenServer.call(pid, {:send_chatstate, jid, type})

  # Internal: the documented entry point is `Amarula.request_pairing_code/3`.
  @doc false
  @spec request_pairing_code(GenServer.server(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def request_pairing_code(pid, phone, opts \\ []) do
    digits = String.replace(phone, ~r/\D/, "")
    GenServer.call(pid, {:request_pairing_code, digits, Keyword.get(opts, :custom_code)})
  end

  # Internal: the documented entry point is `Amarula.subscribe_presence/2`.
  @doc false
  @spec presence_subscribe(GenServer.server(), Amarula.jid()) :: :ok | {:error, :not_connected}
  def presence_subscribe(pid, jid),
    do: GenServer.call(pid, {:presence_subscribe, jid})

  # Internal: the documented entry point is `Amarula.mark_read/3`.
  @doc false
  @spec mark_read(GenServer.server(), Amarula.jid(), [String.t(), ...], Amarula.jid() | nil) ::
          :ok | {:error, :not_connected}
  def mark_read(pid, jid, message_ids, participant \\ nil),
    do: GenServer.call(pid, {:mark_read, jid, message_ids, participant})

  # Internal: the documented entry point is `Amarula.Group.metadata/2`.
  @doc false
  @spec group_metadata(GenServer.server(), Amarula.jid()) ::
          {:ok, Amarula.Group.t()} | {:error, term()}
  def group_metadata(pid, group), do: GenServer.call(pid, {:group_metadata, group})

  # Internal: the documented entry point is `Amarula.Group.list/1`.
  @doc false
  @spec list_groups(GenServer.server()) :: {:ok, [Amarula.Group.t()]} | {:error, term()}
  def list_groups(pid), do: GenServer.call(pid, :list_groups, 30_000)

  # Run a group management op: send the IQ `Groups.Ops.<builder>` produced and run
  # `transform` on the reply. `transform` is `fn {:ok, node} | {:error, node} ->
  # result end`. Used by the `Amarula` group_* API.
  @doc false
  @spec group_op(GenServer.server(), Node.t(), (term() -> term())) :: term()
  def group_op(pid, %Node{} = iq, transform),
    do: GenServer.call(pid, {:group_op, iq, transform}, 30_000)

  # Internal: the documented entry point is `Amarula.wipe_credentials/1`.
  @doc false
  @spec wipe_credentials(GenServer.server()) :: :ok | {:error, term()}
  def wipe_credentials(pid), do: GenServer.call(pid, :wipe_credentials)

  # Internal: the documented entry point is `Amarula.send_text/4`.
  @doc false
  def send_text(pid, jid, text, opts \\ []) do
    GenServer.call(pid, {:send_text, jid, text, opts}, send_call_timeout())
  end

  @doc """
  Send a pre-built `%Proto.Message{}` to `jid` (1:1 or group). Used for
  reactions, edits, deletes and media. Returns `{:ok, msg_id}`.
  """
  def send_message(pid, jid, %Proto.Message{} = message) do
    GenServer.call(pid, {:send_message, jid, message}, send_call_timeout())
  end

  # Internal: the documented entry point is `Amarula.resolve_quoted/2`.
  @doc false
  def request_resend(pid, %Proto.MessageKey{} = message_key) do
    GenServer.call(pid, {:request_resend, message_key}, send_call_timeout())
  end

  # Internal: the documented entry point is `Amarula.fetch_history/4`.
  @doc false
  def fetch_history(pid, %Proto.MessageKey{} = oldest_key, oldest_ts, count) do
    GenServer.call(pid, {:fetch_history, oldest_key, oldest_ts, count}, send_call_timeout())
  end

  # Internal: the documented entry point is `Amarula.send_poll/5`.
  @doc false
  def send_poll(pid, jid, name, options, opts \\ []) do
    GenServer.call(pid, {:send_poll, jid, name, options, opts}, send_call_timeout())
  end

  # Internal: the documented entry point is `Amarula.send_contact/4`.
  @doc false
  def send_contact(pid, jid, display_name, vcard) do
    send_message(pid, jid, MessageEncoder.contact(display_name, vcard))
  end

  # Internal: the documented entry point is `Amarula.send_contacts/4`.
  @doc false
  def send_contacts(pid, jid, display_name, pairs) do
    send_message(pid, jid, MessageEncoder.contacts(display_name, pairs))
  end

  # Internal: the documented entry point is `Amarula.send_location/5`.
  @doc false
  def send_location(pid, jid, lat, lng, opts \\ []) do
    send_message(pid, jid, MessageEncoder.location(lat, lng, opts))
  end

  # Internal: the documented entry point is `Amarula.send_reaction/3`.
  @doc false
  def send_reaction(pid, %Proto.MessageKey{remoteJid: jid} = target_key, emoji) do
    send_message(pid, jid, MessageEncoder.reaction(target_key, emoji))
  end

  # Internal: the documented entry point is `Amarula.send_revoke/2`.
  @doc false
  def send_revoke(pid, %Proto.MessageKey{remoteJid: jid} = target_key) do
    send_message(pid, jid, MessageEncoder.revoke(target_key))
  end

  # Internal: the documented entry point is `Amarula.send_edit/3`.
  @doc false
  def send_edit(pid, %Proto.MessageKey{remoteJid: jid} = target_key, new_text) do
    send_message(pid, jid, MessageEncoder.edit(target_key, new_text))
  end

  # Internal: the documented entry point is `Amarula.send_media/5`.
  @doc false
  def send_media(pid, jid, type, data, opts \\ [])
      when type in [:image, :video, :audio, :document, :sticker] and is_binary(data) do
    GenServer.call(pid, {:send_media, jid, type, data, opts}, send_call_timeout())
  end

  # Internal: the documented entry point is `Amarula.send_media/5`.
  @doc false
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
    warn_if_android(config)

    # A Connection-owned Task.Supervisor for off-process work (media prep,
    # history-sync downloads). Started LINKED here so it dies with this Connection
    # — killing any in-flight task rather than leaving it to run against a stale
    # pid — and a fresh one is created on restart. Every Connection has one, tree
    # or bare, so there is no unsupervised fallback path.
    {:ok, task_supervisor} = Task.Supervisor.start_link([])

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
      qr_ref: nil,
      qr_timer: nil,
      task_supervisor: task_supervisor
    }

    # Own the retry cache's local resource (the ETS table, for the default
    # adapter) here, so it is owned by *this* process: it dies with the Connection
    # and is recreated empty on restart — a poisoned cached value can never
    # outlive the crash it triggers. A no-op for adapters with no process-owned
    # resource (DETS, Redis).
    :ok = Amarula.RetryCache.ensure_local(conn.retry_cache, conn.profile)

    # Same ownership story for the message-secret store's local resource (the
    # ETS adapter's table — inbound messageSecrets held for the 15-min edit
    # window, so newer-client edit envelopes can be decrypted; #30). A no-op for
    # a consumer-backed ReadOnly adapter, which owns its own storage.
    :ok = MessageSecretStore.ensure_local(conn.message_secret_store, conn.profile)

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
    {:reply, SessionOps.canonical_jid(state.conn, jid), state}
  end

  @impl GenServer
  def handle_call(
        {:own_chat?, %Amarula.Msg{from_me: true, to: %Amarula.Address{} = to}},
        _from,
        state
      ) do
    {:reply, Receive.own_account?(state, to), state}
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

  # Blocking media re-upload: send a server-error receipt for a message whose CDN
  # blob expired, then park the caller under the msg id until the phone's
  # <notification type="mediaretry"> arrives (handle_media_retry_notification) or
  # the media-retry timeout fires.
  @impl GenServer
  def handle_call(
        {:request_media_retry, msg_id, chat_jid, from_me, participant, media_key},
        from,
        state
      ) do
    if ready_to_send?(state) do
      own_jid = JID.jid_normalized_user(me(state).id)

      receipt =
        Media.build_retry_receipt(msg_id, own_jid, chat_jid, from_me, participant, media_key)

      timer = Process.send_after(self(), {:media_retry_timeout, msg_id}, @media_retry_timeout_ms)
      pending = Map.put(state.pending_media_retries, msg_id, {from, media_key, timer})
      {:noreply, send_binary_node(%{state | pending_media_retries: pending}, receipt)}
    else
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
    case Pairing.build_pairing_code(custom_code) do
      {:ok, code} ->
        state = start_link_code_pairing(state, phone, code)
        {:reply, {:ok, code}, state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl GenServer
  def handle_call({:presence_subscribe, jid}, _from, state) do
    to_jid = Amarula.Address.to_jid!(jid)

    node =
      Presence.subscribe(
        to_jid,
        generate_message_tag(state),
        TcTokenStore.token_children(conn(state), to_jid)
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

  # The one sanctioned way to send to `status@broadcast`: `resolve_target/1` refuses
  # it for every other send, so a bot replying to a status channel cannot post.
  @impl GenServer
  def handle_call({:post_status, text, audience}, from, state) do
    case SendOps.status_audience(audience) do
      {:ok, jids} ->
        payload = %{text: text, status_audience: jids}
        deliver_resolved(state, "status@broadcast", payload, from, &SendOps.default_send_reply/2)

      {:error, _} = error ->
        {:reply, error, state}
    end
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
    # self-call). Run them in an async_nolink task under our Task.Supervisor and
    # monitor it: the task returns {:ok, message} | {:error, reason} (no rescue —
    # the pipeline's errors are already tuples), delivered as {ref, result}; an
    # unexpected raise surfaces as {:DOWN, ref, …}. Either way `from` is answered
    # (see the handle_info clauses below), so the caller never hangs.
    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        with {:ok, enc} <- Media.encrypt(data, type),
             {:ok, uploaded} <- Media.upload(conn_pid, enc.enc, enc.file_enc_sha256, type) do
          info = Map.merge(enc, Map.put(uploaded, :mimetype, mimetype))
          {:ok, MessageEncoder.media(type, info, opts)}
        end
      end)

    {:noreply, put_in(state.media_tasks[task.ref], {from, jid})}
  end

  @impl GenServer
  def handle_call({:update_auth_creds, new_creds}, _from, state) do
    Logger.info("Updating authentication credentials")
    {:reply, :ok, update_creds(state, new_creds)}
  end

  # Re-key existing PN sessions onto their LID; only contacts with no PN session to
  # move need a fresh bundle (fetching for a migrated one would clobber the ratchet).
  @impl GenServer
  def handle_call({:migrate_pn_sessions, pairs}, _from, state) do
    case SessionOps.migrate_pairs(pairs, state) do
      {:ok, needs_fetch, state} ->
        {:reply, :ok, force_refresh_sessions(state, needs_fetch)}

      {:error, reason} ->
        Logger.warning(
          "migrate_pn_sessions: cannot enumerate sessions (#{inspect(reason)}); " <>
            "senders fall back to fresh-bundle fetches"
        )

        {:reply, :ok, state}
    end
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

  # A caller with no `task_supervisor` of its own (e.g. ConversationSender)
  # asking us to run best-effort background work under ours.
  @impl GenServer
  def handle_cast({:run_background, fun}, state) do
    Task.Supervisor.start_child(state.task_supervisor, fun)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:issue_tctoken, jid}, state) do
    {:noreply, spawn_tctoken_issuance(state, :send, jid)}
  end

  @impl GenServer
  def handle_cast({:notify_lid_mappings, pairs}, state) do
    emit_to_subscribers(state, :lid_mapping_update, SessionOps.format_lid_mappings(pairs))
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:force_resync_app_state, names}, state) do
    names = AppStateOps.reset_collections(scope(state), profile(state), names)
    Logger.debug("Force-resyncing app-state collection(s): #{inspect(names)}")
    {:noreply, do_resync_app_state(state, names)}
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
    # Read the optional keys defensively: this handler must not crash the whole
    # connection over an unexpected result shape (a partial map from a plugin or
    # an older HistorySync). The chats/contacts/sync_type keys predate that
    # concern and stay direct.
    messages = Map.get(result, :messages, [])
    lid_mappings = Map.get(result, :lid_mappings, [])
    tc_tokens = Map.get(result, :tc_tokens, [])

    Logger.debug(
      "history sync (#{inspect(result.sync_type)}): #{length(result.chats)} chats, " <>
        "#{length(result.contacts)} contacts, " <>
        "#{length(messages)} messages, " <>
        "#{length(lid_mappings)} lid mappings, " <>
        "#{length(tc_tokens)} tctokens"
    )

    if result.chats != [], do: emit_to_subscribers(state, :chats_update, result.chats)
    if result.contacts != [], do: emit_to_subscribers(state, :contacts_update, result.contacts)
    emit_to_subscribers(state, :history_sync, result)

    state = learn_lid_mappings(state, lid_mappings)
    # After learn_lid_mappings/2 on purpose: the tokens are keyed by LID, and the
    # pairs this same blob carries are what let storage_jid/2 resolve a PN chat to
    # the LID key a later send will look under.
    TcTokenStore.store_history_sync(conn(state), tc_tokens)
    {:noreply, learn_own_push_name(state, Map.get(result, :push_names, []))}
  end

  def handle_info({:ws_event, _ws_pid, {:open, _data}}, state) do
    Logger.debug("WebSocket connected - initiating handshake")

    # Build the ClientHello (pure) then send it + transition (CM owns the socket).
    # `client_hello/2` is pure key generation and always succeeds, so only the
    # send can fail here.
    {:ok, frame, handshake_state} = Login.client_hello(state.auth_creds, state.config)

    case WebSocketClient.send_data(state.websocket_client, frame) do
      :ok ->
        Logger.debug("ClientHello sent (#{byte_size(frame)} bytes)")
        emit_connection_update(state, :connecting)
        {:noreply, %{state | handshake_state: handshake_state}}

      {:error, reason} ->
        Logger.error("Failed to send ClientHello: #{inspect(reason)}")
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

  # These two clauses do NOT catch WebSocket control frames — despite the 0x88/0x8A
  # bytes, that framing is a red herring. WebSockex demuxes the frame layer before
  # we see it: a genuine close arrives as a {:ws_event, _, {:close, _}} event
  # (handled above) and a ping/pong as {:ws_event, _, {:ping | :pong, _}} — never as
  # {:frame, data}. Here `data` is always an already-decoded text/binary *payload*,
  # not raw frame bytes with an opcode. So these fire only when the payload is
  # exactly the lone byte 0x88 / 0x8A; we match it EXACTLY (not as a prefix) so a
  # real Noise/binary-node payload that merely begins with that byte isn't swallowed.
  @impl GenServer
  def handle_info({:ws_event, _ws_pid, {:frame, <<136>>}}, state) do
    Logger.warning(
      "Dropping a lone 0x88 payload byte (not a socket close — see {:close, _} above)"
    )

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:ws_event, _ws_pid, {:frame, <<138>>}}, state) do
    # A lone 0x8A payload byte. It's still inbound traffic, so treat it as a
    # liveness signal and bump last_recv_time, but decode nothing.
    Logger.debug("Dropping a lone 0x8A payload byte (not a pong)")
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

  # A media-prep task finished. Demonitor+flush so its trailing {:DOWN, :normal}
  # doesn't also fire, then either dispatch the send (forwarding `from`, as any
  # other send) or reply the pipeline's {:error, reason} to the caller.
  @impl GenServer
  def handle_info({ref, result}, state) when is_map_key(state.media_tasks, ref) do
    Process.demonitor(ref, [:flush])
    {{from, jid}, media_tasks} = Map.pop(state.media_tasks, ref)
    state = %{state | media_tasks: media_tasks}

    case result do
      {:ok, message} ->
        dispatch_send(state, SendOps.media(jid, message), from)

      {:error, reason} ->
        GenServer.reply(from, {:error, reason})
        {:noreply, state}
    end
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

  # The phone never answered our media-retry receipt within the window — fail the
  # parked caller so retry_media/2 returns instead of hanging to its call timeout.
  @impl GenServer
  def handle_info({:media_retry_timeout, msg_id}, state) do
    case Map.pop(state.pending_media_retries, msg_id) do
      {nil, _} ->
        {:noreply, state}

      {{from, _media_key, _timer}, pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_media_retries: pending}}
    end
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

  # A media-prep task crashed before returning a result (async_nolink, so the exit
  # doesn't reach us as a link — only this monitor DOWN). Answer the parked caller
  # with a clean error instead of letting it hang to the send-call timeout.
  # A 463 tctoken recovery finished (or died). Either way it is fire-and-forget —
  # just drop the in-flight entry so a later 463 for the same contact can retry.
  @impl GenServer
  def handle_info({ref, _result}, state) when is_map_key(state.tctoken_recoveries, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | tctoken_recoveries: Map.delete(state.tctoken_recoveries, ref)}}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state)
      when is_map_key(state.tctoken_recoveries, ref) do
    {:noreply, %{state | tctoken_recoveries: Map.delete(state.tctoken_recoveries, ref)}}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.media_tasks, ref) do
    {{from, _jid}, media_tasks} = Map.pop(state.media_tasks, ref)
    GenServer.reply(from, {:error, {:media_prepare_failed, reason}})
    {:noreply, %{state | media_tasks: media_tasks}}
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

  # The caller gets the reason — `{:unsupported, "broadcast"}` says "this is a
  # status post, you cannot reply to it", which is actionable in a way that a
  # crashed-and-restarted connection is not.
  defp refuse_send(state, from, shape, payload, reason) do
    msg_id = Map.get(payload, :msg_id) || generate_message_id()

    case from do
      nil -> {:noreply, state}
      _ -> {:reply, shape.({:error, reason}, msg_id), state}
    end
  end

  defp deliver_async(state, target, payload, from, shape \\ &SendOps.default_send_reply/2)

  # A target we cannot turn into a jid must never reach `to_jid!/1` further down:
  # that runs INSIDE the Connection GenServer, so it would not fail the caller's
  # send — it would take the whole connection down and restart it (#50). Refuse
  # and let the caller see why. Reached when a consumer sends to an address we
  # cannot address: a `%Msg{}` channel of kind `:unsupported` (a status post), or
  # the empty address.
  #
  # Ahead of the sandbox clause ON PURPOSE. Sandbox mode exists so a consumer can
  # exercise bot logic without a socket; if it answered `{:ok, id}` here while the
  # live path refuses, the sandbox would certify a bot that breaks in production.
  # Both modes must agree on what is addressable.
  defp deliver_async(state, target, payload, from, shape) do
    case SendOps.resolve_target(target) do
      {:ok, jid} -> deliver_resolved(state, jid, payload, from, shape)
      {:error, reason} -> refuse_send(state, from, shape, payload, reason)
    end
  end

  # Sandbox (offline) mode: the connection has no socket and there is no peer to
  # reach, so a send must not run the real pipeline (USync/bundle fetch IQs would
  # block forever with nothing to answer them). Short-circuit at the boundary:
  # mint a msg_id and reply exactly as a confirmed send would (`shape.(:ok, …)` →
  # `{:ok, id}`, or `{:ok, id, secret}` for a poll). Nothing is encrypted, no
  # frame leaves the process — the consumer's bot logic runs unchanged. A
  # fire-and-forget send (from == nil) simply does nothing.
  defp deliver_resolved(%{config: %{offline: true}} = state, _jid, payload, from, shape) do
    msg_id = Map.get(payload, :msg_id) || generate_message_id()

    case from do
      nil -> {:noreply, state}
      _ -> {:reply, shape.(:ok, msg_id), state}
    end
  end

  defp deliver_resolved(state, jid, payload, from, shape) do
    jid = lid_target(state, jid)
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
  # Top-level <status> stanza (server-side rollout for contacts' status updates,
  # Baileys #2858 / #2866, whatsmeow a238105488). Plain-ack with class="status"
  # so the server doesn't close the stream after 50 minutes with `<stream:error><ack class="status"/>`.
  defp dispatch_node(state, :status_ack, node), do: send_message_ack(state, node)
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
        state = maybe_recover_tctoken(state, node, code)
        resolve_ack(state, msg_id, fn _on_ack -> err end)
    end
  end

  # 463 = MessageAccountRestriction: the recipient hasn't trusted us yet (no
  # tctoken on file for them) — the message above was NOT delivered. Fire off a
  # best-effort issuance so a FUTURE send to them may succeed; never retry the
  # message itself (Baileys' handleBadAck: retrying counts as another "reach
  # out" and worsens the restriction). See `TcTokenStore` moduledoc.
  defp maybe_recover_tctoken(state, node, "463"),
    do: spawn_tctoken_issuance(state, :recover, NodeUtils.get_attr(node, "from"))

  defp maybe_recover_tctoken(state, _node, _code), do: state

  # Start one issuance for `jid`, unless one is already in flight for that
  # contact FROM THE SAME TRIGGER. Both funnel through here, but keyed by source:
  # Baileys tracks the two windows separately (`inFlightTcTokenIssuance` for the
  # post-send path, `inFlight463Recoveries` for the rejection path), because a 463
  # says the recipient rejected us and still warrants recovery even if a routine
  # post-send issuance happens to be in flight. Within one source, a burst
  # collapses to a single `issuePrivacyTokens` IQ. Cleared when the task ends or dies.
  defp spawn_tctoken_issuance(state, source, jid) when is_binary(jid) do
    if {source, jid} in Map.values(state.tctoken_recoveries) do
      state
    else
      pid = self()
      conn = state.conn

      task =
        Task.Supervisor.async_nolink(state.task_supervisor, fn ->
          issue_tctoken(pid, conn, jid)
        end)

      put_in(state.tctoken_recoveries[task.ref], {source, jid})
    end
  end

  defp spawn_tctoken_issuance(state, _source, _jid), do: state

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
      {:ok, receipts} ->
        Enum.each(receipts, fn receipt ->
          Logger.debug("Receipt #{receipt.status} for #{inspect(receipt.message_ids)}")
          emit_to_subscribers(state, :receipt_update, receipt)
        end)

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
  # Inject it so our re-encrypt uses the session the requester just advertised.
  defp maybe_inject_retry_keys(state, node) do
    case NodeUtils.get_binary_node_child(node, "keys") do
      %Node{} ->
        SessionInjector.inject_retry(node, state.auth_creds, conn(state), state.instance_id)
        state

      _ ->
        state
    end
  end

  defp resend_from_cache(state, msg_id, participant) do
    case Receive.lookup_for_resend(retry_cache(state), profile(state), state.config, msg_id) do
      {recipient, message, stanza_attrs} ->
        Logger.debug("Resending #{msg_id} to #{participant} (retry)")
        payload = SendOps.resend_payload(msg_id, message, stanza_attrs)
        deliver_async(state, recipient, payload, nil)

      nil ->
        Logger.debug("Retry for #{msg_id} but no cached/stored copy — cannot resend")
    end
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

      :own_devices ->
        Logger.debug("account_sync: own device set changed — dropping own device cache")

        state
        |> me()
        |> Notifications.own_device_users()
        |> Enum.each(&DeviceListCache.delete(conn(state), &1))

        state

      :ignore ->
        state
    end
  end

  # devices — a contact's device list changed (add/remove/update).
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

  # picture — a contact/group avatar changed; surface it as a contact update.
  defp dispatch_notification(state, "picture", node) do
    update = Notifications.picture(node)
    Logger.debug("picture #{update.img_url} for #{update.id}")
    emit_to_subscribers(state, :contacts_update, [update])
    state
  end

  # link_code_companion_reg — the phone confirmed our pairing code.
  defp dispatch_notification(state, "link_code_companion_reg", node) do
    case Pairing.parse_link_code_notification(node) do
      {:ok, ref, primary_identity_pub, wrapped} ->
        finish_link_code_pairing(state, ref, primary_identity_pub, wrapped)

      :ignore ->
        Logger.debug("link_code_companion_reg notification missing fields — skipping")
        state
    end
  end

  # companion_reg_refresh — rotate QR advertisement secret while QR pairing is pending.
  defp dispatch_notification(state, "companion_reg_refresh", node) do
    case {Pairing.rotate_qr_adv_secret?(node), Map.get(state.auth_creds, :me), state.qr_ref} do
      {true, nil, ref} when is_binary(ref) ->
        adv_secret_key = Crypto.random_bytes(32) |> Base.encode64()
        state = update_creds(state, %{state.auth_creds | adv_secret_key: adv_secret_key})
        qr = Pairing.generate_qr_code(ref, state.auth_creds, state.config)

        emit_to_subscribers(state, :connection_update, %{
          connection: :connecting,
          qr: qr
        })

        state

      _ ->
        Logger.debug("companion_reg_refresh ignored outside active QR pairing")
        state
    end
  end

  defp dispatch_notification(state, "mediaretry", node) do
    handle_media_retry_notification(state, node)
  end

  defp dispatch_notification(state, "privacy_token", node) do
    case Notifications.privacy_token_sender(node) do
      fallback_jid when is_binary(fallback_jid) ->
        Logger.debug("privacy_token notification from #{fallback_jid}")
        TcTokenStore.store_notification(conn(state), node, fallback_jid)
        state

      _ ->
        state
    end
  end

  defp dispatch_notification(state, type, _node) do
    Logger.debug("Notification (type=#{type}) acked — no handler")
    state
  end

  defp handle_media_retry_notification(state, node) do
    msg_id = NodeUtils.get_attr(node, "id")

    case Map.pop(state.pending_media_retries, msg_id) do
      {nil, _} ->
        Logger.debug("mediaretry notification for #{msg_id} with no pending waiter — ignoring")
        state

      {{from, media_key, timer}, pending} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, Media.decode_retry_notification(node, media_key))
        %{state | pending_media_retries: pending}
    end
  end

  defp finish_link_code_pairing(state, ref, primary_identity_pub, wrapped) do
    {creds, iq} =
      Pairing.finish_link_code(
        state.auth_creds,
        me(state).id,
        generate_message_tag(state),
        ref,
        primary_identity_pub,
        wrapped
      )

    Logger.info("Finishing link-code pairing — sending companion_finish")
    state = send_binary_node(state, iq)
    state = update_creds(state, creds)
    emit_to_subscribers(state, :pairing_success, %{via: :link_code})
  end

  defp handle_encrypt_notification(state, node, nil), do: do_prekey_topup(state, node)

  defp handle_encrypt_notification(state, node, from) do
    if from == Constants.s_whatsapp_net() do
      do_prekey_topup(state, node)
    else
      maybe_refresh_identity(state, node, from)
    end
  end

  defp do_prekey_topup(state, node) do
    count = PreKeyOps.server_count(node)
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

  defp maybe_refresh_identity(state, node, from) do
    if Receive.offline_node?(node) do
      Logger.debug("encrypt(identity) from #{from}: offline batch — deferring refresh")
      state
    else
      case SessionOps.wipe_identity_sessions(conn(state), state.instance_id, from) do
        n when n > 0 ->
          Logger.debug("encrypt(identity) from #{from}: wiped #{n} stale session(s), refreshing")
          force_refresh_sessions(state, [from])

        _ ->
          Logger.debug("encrypt(identity) from #{from}: no existing session — skipping refresh")
          state
      end
    end
  end

  defp learn_lid_mappings(state, pairs) do
    case SessionOps.store_and_format_lid_mappings(conn(state), pairs) do
      [] -> state
      mappings -> emit_to_subscribers(state, :lid_mapping_update, mappings)
    end
  end

  defp force_refresh_sessions(state, []), do: state

  defp force_refresh_sessions(state, jids) do
    send_tracked_iq(state, SessionOps.force_refresh_iq(jids), :assert_lid_sessions)
  end

  defp handle_dirty(state, node) do
    case Login.dirty_clean_iq(node) do
      :ignore ->
        state

      {:ok, type, iq} ->
        Logger.debug("Clearing dirty bits (type=#{type})")
        state = send_tracked_iq(state, iq, :clean_dirty)
        if type == "account_sync", do: resync_app_state(state), else: state
    end
  end

  defp handle_offline_preview(state, node) do
    Logger.debug(
      "Offline preview received (count=#{Login.offline_preview_count(node)}) — requesting batch"
    )

    send_binary_node(state, Login.offline_batch_node())
  end

  defp handle_offline_complete(state, node) do
    Logger.debug("Handled #{Login.offline_complete_count(node)} offline messages/notifications")
    emit_to_subscribers(state, :connection_update, %{received_pending_notifications: true})
    state
  end

  defp handle_edge_routing(state, node) do
    case Login.routing_info(node) do
      {:ok, info} -> update_creds(state, Map.put(state.auth_creds, :routing_info, info))
      :ignore -> state
    end
  end

  @stream_error_restart_required 515

  defp handle_stream_error(state, node) do
    {code, reason} = Login.stream_error_details(node)

    Amarula.Telemetry.emit([:amarula, :stream_error, :received], profile(state), %{count: 1}, %{
      code: code
    })

    if code == @stream_error_restart_required do
      Logger.debug(
        "Stream error 515 (restart required) — reconnecting to log in with paired credentials"
      )

      restart_connection(state)
    else
      Logger.error("Stream error: code=#{code}, reason=#{reason}")
      handle_connection_error(state, {:stream_error, code, reason})
    end
  end

  defp restart_connection(state) do
    if state.keep_alive_timer do
      Process.cancel_timer(state.keep_alive_timer)
    end

    state
    |> clear_server_response_waiting()
    |> fail_pending_iqs(:not_connected)
    |> fail_pending_media_retries(:not_connected)
    |> disconnect_websocket()
    |> Map.merge(%{
      noise_state: nil,
      handshake_state: nil,
      keep_alive_timer: nil,
      retry_count: 0
    })
    |> attempt_connection()
  end

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

  defp fail_pending_media_retries(state, reason) do
    Enum.each(state.pending_media_retries, fn {_id, {from, _media_key, timer}} ->
      Process.cancel_timer(timer)
      GenServer.reply(from, {:error, reason})
    end)

    %{state | pending_media_retries: %{}}
  end

  defp handle_pair_device(state, node) do
    Logger.debug("Received pair-device IQ, generating QR codes...")

    state =
      if state.server_response_timeout_timer do
        Process.cancel_timer(state.server_response_timeout_timer)
        %{state | server_response_timeout_timer: nil}
      else
        state
      end

    msg_id = NodeUtils.get_attr(node, "id")
    Logger.debug("Sending pair-device IQ ack (id=#{msg_id})")
    state = send_binary_node(state, Pairing.pair_device_ack_node(msg_id))

    case Pairing.qr_refs(node) do
      [] ->
        Logger.warning("pair-device IQ had no ref nodes")
        state

      refs ->
        emit_next_qr(%{state | qr_refs: refs})
    end
  end

  defp emit_next_qr(%{qr_refs: []} = state) do
    Logger.warning("QR refs exhausted — pairing window expired")
    handle_connection_error(state, {:pairing_error, :qr_timeout})
  end

  defp emit_next_qr(%{qr_refs: [ref | rest]} = state) do
    if state.qr_timer, do: Process.cancel_timer(state.qr_timer)

    qr = Pairing.generate_qr_code(ref, state.auth_creds, state.config)

    emit_to_subscribers(state, :connection_update, %{
      connection: :connecting,
      qr: qr
    })

    state = %{state | qr_refs: rest, qr_ref: ref}

    if rest == [] do
      %{state | qr_timer: nil}
    else
      delay = Pairing.qr_refresh_delay(state.config, state.qr_timer)
      timer = Process.send_after(self(), :next_qr, delay)
      %{state | qr_timer: timer}
    end
  end

  defp handle_pair_success(state, node) do
    Logger.debug("Received pair-success message, processing device pairing...")
    state = clear_server_response_waiting(state)

    case Pairing.verify_pair_success(node, state.auth_creds) do
      {:ok,
       %{
         msg_id: msg_id,
         key_index: key_index,
         jid: jid,
         lid: lid,
         platform: platform,
         reply_node: reply_node,
         updated_creds: updated_creds
       }} ->
        Logger.info("Pairing device (platform=#{platform})")
        Logger.debug("Pairing jid=#{jid} lid=#{lid}")
        Logger.debug("Sending pair-device-sign reply: msg_id=#{msg_id}, key_index=#{key_index}")

        state =
          state
          |> send_binary_node(reply_node)
          |> update_creds(updated_creds)

        Logger.info("Pairing successful")
        Logger.debug("Paired device: #{jid}")

        emit_to_subscribers(state, :pairing_success, %{jid: jid, lid: lid, platform: platform})

        emit_to_subscribers(state, :connection_update, %{
          connection: :connecting,
          is_new_login: true,
          qr: nil
        })

        state

      {:error, :missing_field} ->
        Logger.error("Missing required field in pair-success message")
        emit_to_subscribers(state, :pairing_failure, %{reason: "missing_required_field"})
        handle_connection_error(state, {:pairing_error, :missing_field})

      {:error, reason} ->
        Logger.error("Failed to process pair-success: #{inspect(reason)}")
        emit_to_subscribers(state, :pairing_failure, %{reason: inspect(reason)})
        handle_connection_error(state, {:pairing_error, reason})
    end
  end

  defp frame_tap(dir, node) do
    if System.get_env("AMARULA_FRAME_TAP") do
      dump = inspect(node, limit: :infinity, printable_limit: 64, width: :infinity)
      Logger.info("TAP #{dir} #{dump}")
    end

    :ok
  end

  defp send_binary_node(%{config: %{frame_sink: sink}} = state, node) when is_pid(sink) do
    send(sink, {:frame_out, node})
    state
  end

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
    framed = <<0>> <> encoded
    {encrypted, updated_noise_state} = NoiseHandler.encode_frame(state.noise_state, framed)
    WebSocketClient.send_data(state.websocket_client, encrypted)
    %{state | noise_state: updated_noise_state}
  end

  defp ready_to_send?(%{config: %{frame_sink: sink}}) when is_pid(sink), do: true

  defp ready_to_send?(%{noise_state: noise, websocket_client: ws}),
    do: not is_nil(noise) and not is_nil(ws)

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
    msg_id = NodeUtils.get_attr(node, "id")
    send_binary_node(state, Pairing.pair_device_ack_node(msg_id))
  end

  defp handle_xml_stream_end(state, _node) do
    Logger.info("XML stream ended by server")
    handle_connection_error(state, :xml_stream_end)
  end

  defp start_link_code_pairing(state, phone, code) do
    me = %{id: JID.encode(%{user: phone, server: "s.whatsapp.net"}), name: "~"}

    creds =
      state.auth_creds
      |> Map.put(:me, me)
      |> Map.put(:pairing_code, code)

    state = update_creds(state, creds)
    iq = Pairing.companion_hello_iq(me.id, creds, state.config.browser)

    Logger.info("Requested link-code pairing for #{phone} — code #{code}")
    state = send_tracked_iq(state, iq, :pairing_code_hello)
    emit_to_subscribers(state, :pairing_code, %{code: code})
  end

  defp start_server_response_timeout(state) do
    timer = Process.send_after(self(), :server_response_timeout, 15_000)
    %{state | server_response_timeout_timer: timer}
  end

  defp clear_server_response_waiting(state) do
    if state.server_response_timeout_timer do
      Process.cancel_timer(state.server_response_timeout_timer)
    end

    if state.qr_timer do
      Process.cancel_timer(state.qr_timer)
    end

    %{
      state
      | waiting_for_server_response: false,
        server_response_timeout_timer: nil,
        qr_refs: [],
        qr_ref: nil,
        qr_timer: nil
    }
  end

  defp send_passive_iq(state, tag) do
    iq_id = generate_message_tag(state)
    state = increment_message_epoch(state)
    send_binary_node(state, Login.passive_iq(iq_id, tag))
  end

  defp maybe_send_init_queries(state) do
    if fire_init_queries?(state.config), do: send_init_queries(state), else: state
  end

  defp send_init_queries(state) do
    Enum.reduce(Login.init_query_specs(), state, fn {base_attrs, child}, acc ->
      send_init_iq(acc, base_attrs, child)
    end)
  end

  defp send_init_iq(state, base_attrs, child) do
    id = generate_message_tag(state)
    state = increment_message_epoch(state)
    content = if child, do: [child], else: nil
    node = %Node{tag: "iq", attrs: base_attrs ++ [{"id", id}], content: content}
    send_binary_node(state, node)
  end

  defp send_unified_session(state) do
    send_binary_node(state, Login.unified_session_node())
  end

  defp send_remove_companion(state) do
    case me(state) do
      %{id: jid} when is_binary(jid) ->
        iq = Login.remove_companion_iq(generate_message_tag(state), jid)
        send_binary_node(increment_message_epoch(state), iq)

      _ ->
        state
    end
  end

  defp send_digest_iq(state) do
    send_tracked_iq(state, Login.digest_iq(), :digest)
  end

  defp start_keep_alive_timer(state) do
    if state.keep_alive_timer, do: Process.cancel_timer(state.keep_alive_timer)
    keep_alive_interval = state.config.keep_alive_interval_ms || 30_000
    timer = Process.send_after(self(), :send_keep_alive, keep_alive_interval)
    %{state | keep_alive_timer: timer}
  end

  defp send_ping_message(state) do
    ping_id = generate_message_tag(state)
    state = increment_message_epoch(state)
    send_binary_node(state, Login.ping_iq(ping_id))
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

  @doc false
  defdelegate build_msg(state, proto, node, from, msg_id, to_addr), to: Receive

  @doc false
  defdelegate normalize_reply_keys(state, proto, channel, from_me?, from), to: Receive

  @doc false
  defdelegate own_sender?(state, node, from), to: Receive

  @doc false
  defdelegate duplicate_decrypt_error?(errors), to: Receive

  # The inbound message pipeline: token capture, session migration, decrypt, classify,
  # emit, receipt-or-nack. Connection is the per-connection coordinator by design (see
  # CLAUDE.md) and this is its hot path — the ORDER of these steps is load-bearing, so
  # they stay in one readable sequence rather than being split for a metric.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp handle_message(state, node) do
    msg_id = NodeUtils.get_attr(node, "from") && NodeUtils.get_attr(node, "id")
    from = NodeUtils.get_attr(node, "from")
    own_sender? = Receive.own_sender?(state, node, from)

    TcTokenStore.store_message_node(state.conn, node)
    state = SessionOps.maybe_migrate_sender_session(state, node)
    store = SessionStore.build(state.auth_creds)

    {:ok, messages, used_pre_key_ids, errors} =
      MessageDecryptor.decrypt_node(node,
        store: store,
        conn: conn(state),
        instance_id: state.instance_id
      )

    state = remove_used_pre_keys(state, used_pre_key_ids)

    Receive.stash_message_secrets(conn(state), profile(state), node, from, messages)

    messages =
      Enum.map(
        messages,
        &Receive.decrypt_edit_envelope(conn(state), profile(state), node, from, &1)
      )

    state = maybe_apply_key_share(state, own_sender?, from, messages)
    messages = Receive.run_recv_steps(conn(state), from, msg_id, messages)

    cond do
      messages != [] ->
        to_addr = Receive.own_address(me(state))

        classified =
          messages
          |> Enum.map(&Receive.build_msg(state, &1, node, from, msg_id, to_addr))
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

          Receive.emit_message_telemetry(profile(state), msgs, node, from)

          emit_to_subscribers(state, :messages_upsert, %{
            from: Amarula.Address.parse(from),
            id: msg_id,
            messages: msgs
          })
        end

        state = send_delivery_receipt(state, node)

        cond do
          not Enum.any?(messages, &Receive.history_sync_message?/1) ->
            state

          own_sender? ->
            maybe_download_history_sync(state, messages)
            send_hist_sync_receipt(state, node)

          true ->
            Logger.warning(
              "dropping spoofed history-sync-notification protocolMessage from non-self origin (#{from})"
            )

            state
        end

      Receive.duplicate_decrypt_error?(errors) ->
        Logger.debug(
          "Message #{msg_id} from #{from}: already-decrypted duplicate — receipt as delivered"
        )

        send_delivery_receipt(state, node)

      JID.jid_newsletter?(from) ->
        Logger.debug("Channel post #{msg_id}: undecodable — plain ack")
        emit_nothing_decrypted_telemetry(state)
        send_message_ack(state, node)

      own_sender? ->
        Logger.debug(
          "Own message #{msg_id} from #{from}: undecryptable — plain ack without retry"
        )

        emit_nothing_decrypted_telemetry(state)
        send_message_ack(state, node)

      JID.jid_status_broadcast?(from) ->
        Logger.debug("Status #{msg_id}: nothing decrypted — retry + plain ack")
        emit_nothing_decrypted_telemetry(state)
        state = send_retry_request(state, node)
        send_message_ack(state, node)

      true ->
        Logger.debug("Message #{msg_id} from #{from}: nothing decrypted — retry + nack")
        emit_nothing_decrypted_telemetry(state)
        state = send_retry_request(state, node)
        send_message_ack(state, node, @nack_unhandled_error)
    end
  end

  defp maybe_apply_key_share(state, true, _from, messages),
    do: maybe_handle_app_state_key_share(state, messages)

  defp maybe_apply_key_share(state, false, from, messages) do
    if AppStateOps.sync_keys_in(messages) != [] do
      Logger.warning(
        "dropping spoofed app-state-sync-key-share protocolMessage from non-self origin (#{from})"
      )
    end

    state
  end

  defp emit_nothing_decrypted_telemetry(state) do
    Amarula.Telemetry.emit([:amarula, :decrypt, :exception], profile(state), %{count: 1}, %{
      reason: :nothing_decrypted
    })
  end

  defp remove_used_pre_keys(state, []), do: state

  defp remove_used_pre_keys(state, ids) do
    Logger.debug("Removing used one-time prekey(s): #{inspect(ids)}")
    pre_keys = Map.drop(Map.get(state.auth_creds, :pre_keys, %{}), ids)
    update_creds(state, Map.put(state.auth_creds, :pre_keys, pre_keys))
  end

  defp send_message_ack(state, node, error_code \\ nil) do
    me_id = get_in(state.auth_creds, [:me, :id])
    send_binary_node(state, Receive.ack_stanza(node, me_id, error_code))
  end

  defp maybe_download_history_sync(state, messages) do
    if sync_history?(state.config), do: download_history_sync(state, messages), else: state
  end

  defp download_history_sync(state, messages) do
    parent = self()

    for hsn <- Receive.history_notifications(messages) do
      Task.Supervisor.start_child(state.task_supervisor, fn ->
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

  defp send_hist_sync_receipt(state, node) do
    Logger.debug("Sending hist_sync receipt (initial-sync ack)")
    send_binary_node(state, Receive.hist_sync_receipt(node))
  end

  defp send_delivery_receipt(state, node) do
    send_binary_node(state, Receive.delivery_receipt(state, node))
  end

  defp send_retry_request(state, node) do
    msg_id = NodeUtils.get_attr(node, "id")
    participant = NodeUtils.get_attr(node, "participant")
    cache_key = participant || NodeUtils.get_attr(node, "from")
    retry_count = Map.get(state.msg_retry_counts, cache_key, 0) + 1

    if retry_count > @max_msg_retry_count do
      Logger.warning("Retry limit reached for #{cache_key} — giving up")
      %{state | msg_retry_counts: Map.delete(state.msg_retry_counts, cache_key)}
    else
      state = %{state | msg_retry_counts: Map.put(state.msg_retry_counts, cache_key, retry_count)}

      {state, extra_children} =
        if retry_count > 1 do
          {updated_creds, keys_node} = Receive.retry_keys_node(state.auth_creds)
          {update_creds(state, updated_creds), [keys_node]}
        else
          {state, []}
        end

      receipt =
        Receive.retry_receipt(
          node,
          retry_count,
          state.auth_creds.registration_id,
          extra_children
        )

      Logger.debug("Sending retry receipt for message #{msg_id} (count=#{retry_count})")

      Amarula.Telemetry.emit([:amarula, :retry, :sent], profile(state), %{
        count: 1,
        attempt: retry_count
      })

      send_binary_node(state, receipt)
    end
  end

  # --- app-state sync (C2) ---

  alias Amarula.Protocol.AppState.Sync

  defp maybe_handle_app_state_key_share(state, messages) do
    case AppStateOps.store_shared_keys(scope(state), profile(state), messages) do
      0 ->
        state

      count ->
        Logger.debug("Stored #{count} app-state-sync key(s); syncing app state")
        resync_app_state(state)
    end
  end

  defp resync_app_state(state, names \\ Sync.collections()) do
    if sync_app_state?(state.config), do: do_resync_app_state(state, names), else: state
  end

  defp do_resync_app_state(state, names) do
    iq = AppStateOps.resync_iq(scope(state), profile(state), names)
    send_tracked_iq(state, iq, :app_state_sync)
  end

  defp apply_app_state_reply(state, reply) do
    AppStateOps.apply_reply(scope(state), profile(state), reply, fn chats, contacts ->
      if chats != [], do: emit_to_subscribers(state, :chats_update, chats)
      if contacts != [], do: emit_to_subscribers(state, :contacts_update, contacts)
    end)
  end

  defp scope(state), do: state.conn.storage
  defp conn(state), do: state.conn
  defp profile(state), do: state.conn.profile

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

  defp update_creds(state, new_creds) do
    state = %{state | auth_creds: new_creds}
    Amarula.Storage.put(scope(state), profile(state), :creds, :self, new_creds)
    state
  end

  defp me(state), do: Map.get(state.auth_creds, :me, %{})

  defp learn_own_push_name(state, []), do: state

  defp learn_own_push_name(state, push_names) do
    case Login.own_push_name(me(state), push_names) do
      nil ->
        state

      real_name ->
        new_state = update_creds(state, put_in(state.auth_creds, [:me, :name], real_name))
        Logger.info("Learned push name: #{inspect(real_name)} — refreshing presence")
        maybe_mark_online(new_state)
    end
  end

  defp retry_cache(state), do: state.conn.retry_cache

  # init/1 accepts a built %Conn{} (normal path) or a bare config map (tests that
  # start Connection directly). For the bare map, default :profile so a
  # storage-agnostic test needn't supply one; real connects go through
  # Amarula.new/1, which still requires :profile.
  defp normalize_conn(%Amarula.Conn{} = conn), do: conn

  defp normalize_conn(config) when is_map(config) do
    config |> Map.put_new(:profile, :default) |> Amarula.Conn.new()
  end

  # Android registration is a newer, less-exercised WhatsApp path; upstream
  # labels it experimental and warns on every socket (Baileys `Socket/socket.ts`).
  # Opting in is deliberate — see the `:browser` notes in `Amarula.Config` — but
  # it changes how the device is registered, so it should never be silent.
  defp warn_if_android(config) do
    if AuthUtils.android?(Map.get(config, :browser)) do
      Logger.warning(
        "Android browser mode is experimental: this device registers as an Android " <>
          "client, not WhatsApp Web. Use at your own risk."
      )
    end

    :ok
  end

  # Internal plumbing; not part of the consumer API.
  @doc false
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
    injected =
      SessionInjector.inject(node, state.auth_creds, conn(state), state.instance_id, :always)

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

  defp handle_tracked_iq(:pairing_code_hello, {:ok, _node}, state) do
    Logger.debug("Link-code companion_hello accepted")
    state
  end

  defp handle_tracked_iq(:pairing_code_hello, {:error, reason}, state) do
    Logger.error("Link-code companion_hello rejected: #{inspect(reason)}")
    emit_to_subscribers(state, :pairing_failure, %{reason: "link_code_rejected"})
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
      |> maybe_send_init_queries()
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

  # Connect-time opt-outs, all default true (see `Amarula.Config`). `@doc false` +
  # public so each gate is unit-testable without a live login, like `mark_online?/1`.
  @doc false
  def sync_history?(config), do: Map.get(config, :sync_history, true)
  @doc false
  def sync_app_state?(config), do: Map.get(config, :sync_app_state, true)
  @doc false
  def fire_init_queries?(config), do: Map.get(config, :fire_init_queries, true)

  @doc """
  Whether to re-address a 1:1 send to the contact's LID when the mapping is known.

  **Experimental, `false` by default.** With it off, the wire envelope carries
  whatever you addressed — a PN stays a PN — which is the behaviour `docs/LID_PN.md`
  documents and the rest of the send path assumes.

  Turn it on if sends to a phone number are being rejected with
  `{:error, {:send_rejected, "463"}}` for a contact you know is reachable. WhatsApp
  appears to evaluate the trust gate against the LID identity, so a PN-addressed
  stanza to a LID-mapped contact can read as an untrusted reachout no matter what
  token is attached — see Baileys#2683.

  Why this is a flag rather than the default: upstream has attempted the same change
  twice (Baileys PRs #2711 and #2748) and merged neither, while two LID-migration
  bugs sit open there. The direction of travel is clear — WhatsApp has begun omitting
  `*_pn` attributes altogether — but the landing is not, so this stays opt-in until
  upstream settles or field evidence accumulates.

  One caveat while it is on: device resolution then queries USync by LID. If that
  comes back empty for a contact, the send fails as
  `{:error, {:resolve_devices, :not_on_whatsapp}}` — accurate about the outcome,
  misleading about the cause.
  """
  @spec resolve_pn_to_lid?(map()) :: boolean()
  def resolve_pn_to_lid?(config), do: Map.get(config, :resolve_pn_to_lid, false)

  defp lid_target(state, jid) do
    SessionOps.lid_target(state.conn, resolve_pn_to_lid?(state.config), jid)
  end

  defp send_presence_available(state) do
    name = get_in(state.auth_creds, [:me, :name]) || "~"
    Logger.debug("Sending presence available (name: #{name})")
    send_binary_node(state, Login.presence_available_node(name))
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
