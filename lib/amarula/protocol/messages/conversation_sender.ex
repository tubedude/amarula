defmodule Amarula.Protocol.Messages.ConversationSender do
  @moduledoc """
  Per-recipient send process. One `ConversationSender` exists per recipient JID;
  all sends to that recipient funnel through it and run **one at a time**.
  Different recipients run in parallel under the DynamicSupervisor.

  ## Why a process per recipient — it is a *lock*, not a cache

  The Sender holds **no state of its own** — not even the ratchet. Encrypting a
  message is a `load → advance → store` against the **shared** Signal session in
  Storage (see `encrypt_for_device/2`): load the session record, advance the
  ratchet (pure), write the advanced record back. That read-modify-write is **not
  atomic**. If two sends to the *same* recipient ran concurrently, both could load
  the same record, advance from the same point, and store — a lost update that
  **forks the ratchet** and corrupts the session.

  So the Sender exists to **serialize** that read-modify-write, not to hold it. Its
  mailbox is the lock: cast #2's `load` can't begin until cast #1's `store` has
  finished. One process per recipient gives exactly the right granularity — serial
  *within* a recipient (ratchet-safe), parallel *across* recipients (throughput).
  This is why a bare `Task` per send would be wrong (no per-recipient mutual
  exclusion → forked ratchets) and why a single shared process would be wrong (no
  cross-recipient parallelism). Because it holds nothing, a Sender is cheap to lose
  and respawn, and current credentials are handed to it per send (creds mutate
  after login, so a cached snapshot would encrypt stale).

  A send is a branchless pipe of `ctx -> ctx` steps that block on IQ round-trips
  through `Connection` (the sole websocket owner):

      ctx
      |> resolve_devices()   # device-list cache, else a USync query
      |> ensure_sessions()   # session files, else a prekey-bundle fetch
      |> encrypt()           # per device; plain vs DSM; advance ratchet
      |> relay()             # frame + send the <participants> stanza

  Each step that needs server data calls `Connection.query_iq/2`, which
  blocks until the matching websocket reply arrives. A step failure crashes the
  process (the DynamicSupervisor reaps it); the pipe carries no error branches.

  ## Lifecycle & registry presence

  **Identity.** A sender's identity *is* its `{instance_id, recipient_jid}` pair.
  It is registered in the app-level `Amarula.InstanceRegistry` under that key
  (namespaced by `instance_id` so two connections don't collide on a shared
  recipient) — so at most one sender per recipient per connection exists at a
  time, and `deliver/2` is a find-or-start on that key.

  **Birth (lazy).** Started on the first `deliver/2` to a recipient with no live
  sender: find-or-start via `Registry.lookup` → else `DynamicSupervisor.start_child`.
  The `{:error, {:already_started, pid}}` branch makes the start race-safe even
  though, in practice, only `Connection` calls `deliver` (single process, so no
  concurrent start for the same recipient).

  **Registration.** Automatic, via the `:via` name in `start_link` — the Registry
  registers the pid on start and **auto-unregisters it on death** (it monitors the
  pid). So a dead sender's key vanishes; there are never stale registry entries to
  reap.

  **Life.** Serializes all sends to its recipient — one pipe at a time, so the
  ratchet's load-modify-store can't interleave (see the lock note above).
  Different recipients run in parallel. Holds no durable state: sessions/keys live
  in Storage, the consumer's `from` is parked in `Connection`. So a sender is cheap
  to lose and cheap to respawn.

  **Death (three ways).**
    1. *Idle.* Each `:send` re-arms an idle timer (`idle_ms`, default 1s,
       overridable via `config[:sender_idle_ms]`); after that long with no further
       send it `{:stop, :normal}`s. It carries no durable state, so lingering buys
       only warm reuse — a quick follow-up to the same recipient skips a respawn +
       a session re-read from Storage. The short default keeps a fan-out to N
       one-shot recipients from leaving a long-lived process tail; a disk-backed
       store may want a larger value to cut re-reads under bursty traffic.
    2. *Crash.* A raise in the pipe (Signal error, USync blowup, bad bundle) kills
       it. `restart: :temporary` ⇒ the supervisor does NOT restart it; the next
       `deliver` respawns a fresh one. In-flight + queued sends are lost.
    3. *Shutdown.* The connection's supervision tree going down takes it too.
    All three auto-unregister the Registry key (the Registry's pid monitor).

  **Rebirth.** The next `deliver/2` to that recipient starts a fresh sender — no
  carried state; it re-reads sessions from Storage.

  **Crash ⇒ parked-send recovery.** Because the consumer's `from` lives in
  `Connection` (not in the dying sender), `Connection` monitors each sender and,
  on its `:DOWN`, fails every parked send for that recipient with
  `{:error, {:sender_crashed, reason}}` — promptly, instead of letting the caller
  hang to the ack-timeout. A `:normal` idle-stop fails nothing (no in-flight
  sends). See `Amarula.Connection` (`ensure_sender_monitor` / the `:DOWN` handler)
  and `docs/plans/SENDER_CRASH_FIX.plan.md`.
  """

  use GenServer, restart: :temporary
  require Logger

  alias Amarula.Protocol.Binary.{JID, Node}
  alias Amarula.Protocol.Crypto.Constants
  alias Amarula.Protocol.Groups.Metadata, as: GroupMetadata
  alias Amarula.Protocol.Messages.{MessageContent, MessageEncoder, Relay}
  alias Amarula.Protocol.Proto

  alias Amarula.Protocol.Signal.{
    DeviceListCache,
    LidMappingFileStore,
    SessionCipher,
    SessionInjector,
    SessionStore
  }

  alias Amarula.Protocol.Signal.Group.{
    GroupCipher,
    GroupSessionBuilder,
    SenderKeyName,
    SenderKeyStore
  }

  alias Amarula.Connection
  alias Amarula.Protocol.USync

  # Idle linger before a drained sender stops. Short (1s) so a fan-out to N
  # one-shot recipients sheds its processes within a second, while still letting a
  # quick follow-up to the same recipient reuse the warm sender (skipping a
  # respawn + a re-read of the session from Storage). The sender holds no durable
  # state, so stopping and respawning is cheap.
  @idle_timeout_ms 1_000

  # --- API ---

  @doc """
  Hand a message to the recipient's sender (start-or-lookup), asynchronously. The
  send runs on the per-recipient process — serialized per recipient, parallel
  across recipients — so the CALLING process (Connection) is not blocked.

  `msg` carries `:msg_id`. The sender does NOT reply the consumer: it runs the
  pipe and, **only on failure**, reports back to `Connection` (`state.cm`), which
  owns the parked consumer `from`:

    * relay succeeded (frame written) → the sender reports **nothing**. Connection
      already parked the `from` and armed an ack-timeout at dispatch, so it simply
      awaits the server's `<ack>` (which resolves the caller) — a "frame went out"
      signal would be inert, so we don't send one.
    * pipe failed (not_on_whatsapp / IQ timeout / encrypt error / plugin halt)
      → `{:send_failed, msg_id, reason}`. No frame went out, so no `<ack>` will
      ever come; Connection replies the parked caller the failure immediately
      (instead of letting it hang to the ack-timeout).

  Returns `{:ok, pid}` — the (started or reused) sender pid, so Connection can
  monitor it and fail the recipient's parked sends if it crashes mid-pipe — or
  `{:error, reason}` if the sender could not be started (e.g. `:max_children`).
  A start failure is a recoverable send failure: Connection maps it to a
  `{:send_failed, msg_id, reason}` for the parked caller rather than crashing.
  """
  @spec deliver(keyword(), map()) :: {:ok, pid()} | {:error, term()}
  def deliver(opts, msg) do
    registry = Keyword.fetch!(opts, :registry)

    with {:ok, pid} <- find_or_start(registry, opts) do
      GenServer.cast(pid, {:send, msg})
      {:ok, pid}
    end
  end

  defp find_or_start(registry, opts) do
    case Registry.lookup(registry, sender_key(opts)) do
      [{pid, _}] -> {:ok, pid}
      [] -> start_child(opts)
    end
  end

  # Sender identity in the (shared, app-level) registry: namespaced by the
  # connection's `instance_id` so two connections sending to the same recipient
  # don't collide on one key.
  defp sender_key(opts) do
    {Keyword.fetch!(opts, :instance_id), Keyword.fetch!(opts, :recipient_jid)}
  end

  # Normalize every DynamicSupervisor.start_child/2 outcome to a tagged tuple.
  # A lost race (:already_started) is success — reuse the live sender. Anything
  # else ({:error, reason} | :ignore | {:error, :max_children}) is a recoverable
  # start failure, surfaced as {:error, reason} so the send fails cleanly instead
  # of raising a CaseClauseError inside Connection.
  defp start_child(opts) do
    spec = {__MODULE__, opts}

    case DynamicSupervisor.start_child(Keyword.fetch!(opts, :supervisor), spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      :ignore -> {:error, :sender_start_ignored}
      {:error, reason} -> {:error, reason}
    end
  end

  def start_link(opts) do
    registry = Keyword.fetch!(opts, :registry)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {registry, sender_key(opts)}})
  end

  # --- GenServer ---

  @impl true
  def init(opts) do
    conn = Keyword.fetch!(opts, :conn)

    state = %{
      recipient_jid: Keyword.fetch!(opts, :recipient_jid),
      cm: Keyword.fetch!(opts, :cm),
      conn: conn,
      creds: Keyword.fetch!(opts, :creds),
      idle_ms: idle_ms(conn)
    }

    {:ok, state, state.idle_ms}
  end

  # Idle linger, overridable per connection via `config[:sender_idle_ms]`
  # (defaults to @idle_timeout_ms). A larger value keeps senders warm longer —
  # useful with a disk-backed session store to avoid re-reading the ratchet on
  # bursty traffic; a smaller one sheds processes faster after a fan-out.
  defp idle_ms(%{config: %{sender_idle_ms: ms}}) when is_integer(ms) and ms >= 0, do: ms
  defp idle_ms(_conn), do: @idle_timeout_ms

  @impl true
  def handle_cast({:send, %{msg_id: msg_id} = msg}, state) do
    # Report ONLY a failure back to Connection — NOT the consumer, and NOT on
    # success. Connection holds the parked `from` (under msg_id) and an armed
    # ack-timeout: a relayed frame just awaits the server <ack>, so "frame went
    # out" needs no message. A failure means no frame went out (no ack will come),
    # so Connection must reply the parked caller the failure immediately.
    case report(run_send(msg, state), msg_id) do
      :ok -> :noop
      failure -> send(state.cm, failure)
    end

    # Re-arm the idle timer: stay warm `state.idle_ms` for a quick follow-up to
    # this recipient, then stop (`handle_info(:timeout, …)`). While sends keep
    # arriving, each cast resets the timer, so a busy recipient never idles out.
    {:noreply, state, state.idle_ms}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.debug("ConversationSender for #{state.recipient_jid} idle — stopping")
    {:stop, :normal, state}
  end

  # Map the pipe result to what Connection needs: nothing on success (`:ok`),
  # a {:send_failed, …} message on failure.
  defp report(:ok, _msg_id), do: :ok
  defp report({:error, reason}, msg_id), do: {:send_failed, msg_id, reason}
  defp report({:halted, reason}, msg_id), do: {:send_failed, msg_id, {:halted, reason}}

  # --- the send pipe ---

  defp run_send(%{msg_id: msg_id} = msg, state) do
    jid = state.recipient_jid
    kind = if JID.jid_group?(jid), do: :group, else: :dm
    Logger.debug("Sending #{msg_id} to #{jid} (#{kind})")

    # Run the send plugin pipeline (before encrypt): steps may transform the
    # message or halt the send. The built-in retry-cache step records it here.
    stanza_attrs = Map.get(msg, :stanza_attrs, %{})

    case run_send_steps(state.conn, msg_id, jid, message_content(msg), stanza_attrs) do
      {:halt, reason} ->
        Logger.debug("Send #{msg_id} to #{jid} halted by a plugin: #{inspect(reason)}")
        {:halted, reason}

      {:cont, %{message: message}} ->
        store_own_lid_mapping(state)
        do_send(state, msg_id, jid, kind, message, stanza_attrs)
    end
  end

  # The plugin send pipeline. ctx carries the message + addressing + the scopes a
  # step needs (e.g. the retry cache). `stanza_attrs` rides along so the retry
  # cache can replay a peer/edit stanza verbatim on a retry-receipt resend.
  # Returns {:cont, ctx} (possibly transformed) or {:halt, reason}.
  defp run_send_steps(conn, msg_id, jid, message, stanza_attrs) do
    ctx = %{
      message: message,
      to: jid,
      profile: conn.profile,
      msg_id: msg_id,
      stanza_attrs: stanza_attrs,
      retry_cache: conn.retry_cache
    }

    Amarula.Plugin.run(conn.send_steps, ctx)
  end

  defp do_send(state, msg_id, jid, kind, message, stanza_attrs) do
    ctx = %{
      cm: state.cm,
      conn: state.conn,
      creds: state.creds,
      kind: kind,
      msg_id: msg_id,
      target_jid: jid,
      message: message,
      # Extra <message> stanza attrs (e.g. category/push_priority for a peer
      # message). Empty for a normal send.
      stanza_attrs: stanza_attrs,
      # The `edit` attr on the <message> stanza, required for delete/edit/pin
      # (Baileys messages-send.ts): "7" delete-for-everyone, "1" edit. nil = none.
      edit_attr: edit_attr(message),
      devices: [],
      participants: [],
      addressing_mode: nil,
      skmsg: nil
    }

    profile = state.conn.profile
    {media?, media_kind, bytes} = media_stats(message)

    # Telemetry span around the whole send. :stop carries duration + byte size +
    # media kind + the outcome (result/error_stage/error_reason), so an operator
    # can compute a send error rate off the one event. (Privacy: counts/kinds/
    # stage atoms only — no jid/content.)
    Amarula.Telemetry.span(
      [:amarula, :send],
      profile,
      %{kind: kind, media?: media?, media_kind: media_kind},
      fn ->
        {result, outcome} = run_pipe(ctx, msg_id, jid, profile)
        {result, %{bytes: bytes}, outcome}
      end
    )
  end

  # Each stage returns {:ok, ctx} or {:error, {stage, reason}}; `with` threads the
  # happy path and stops at the first failure. A recoverable failure (e.g. a
  # timed-out IQ, an unreachable recipient) is logged and returned; unexpected
  # errors still crash the (disposable) process. Returns `{result, outcome}` —
  # the pipe result plus the JID-free outcome metadata for the send :stop event.
  defp run_pipe(ctx, msg_id, jid, profile) do
    with {:ok, ctx} <- resolve_devices(ctx),
         {:ok, ctx} <- ensure_sessions(ctx),
         {:ok, ctx} <- encrypt(ctx),
         :ok <- relay(ctx) do
      {:ok, %{result: :ok, error_stage: nil, error_reason: nil}}
    else
      {:error, {:resolve_devices, :not_on_whatsapp} = stage_reason} ->
        Amarula.Telemetry.emit([:amarula, :send, :not_on_whatsapp], profile)
        log_drop(msg_id, jid, stage_reason)

      {:error, {_stage, _reason} = stage_reason} ->
        log_drop(msg_id, jid, stage_reason)
    end
  end

  defp log_drop(msg_id, jid, {stage, reason}) do
    Logger.error("Send #{msg_id} to #{jid} dropped at #{stage}: #{inspect(reason)}")
    {{:error, reason}, %{result: :error, error_stage: stage, error_reason: reason_tag(reason)}}
  end

  # The telemetry-safe reason: only a bounded atom (e.g. :not_on_whatsapp,
  # :timeout) may enter the payload — a non-atom reason (an error node, a tuple)
  # could embed a jid, so it is dropped and the stage atom carries the signal.
  defp reason_tag(reason) when is_atom(reason), do: reason
  defp reason_tag(_reason), do: nil

  # Byte size + media kind of an outgoing message, for telemetry. Media protos
  # carry fileLength; text/other report 0 bytes and media? = false.
  defp media_stats(%Proto.Message{} = message) do
    case MessageContent.classify(message) do
      {:media, kind, m} -> {true, kind, Map.get(m, :fileLength) || 0}
      _ -> {false, nil, 0}
    end
  end

  # A send carries either a ready %Proto.Message{} (:message) or :text shorthand.
  defp message_content(%{message: %Proto.Message{} = m}), do: m
  defp message_content(%{text: text}) when is_binary(text), do: MessageEncoder.text(text)

  # The `edit` stanza attr the server needs to apply delete/edit (Baileys). A
  # plain message has none. Delete-for-everyone (our own) = "7"; MESSAGE_EDIT = "1".
  defp edit_attr(%Proto.Message{protocolMessage: %{type: :REVOKE}}), do: "7"
  defp edit_attr(%Proto.Message{protocolMessage: %{type: :MESSAGE_EDIT}}), do: "1"
  defp edit_attr(_message), do: nil

  # Persist our own PN↔LID mapping so own-device bundle fetches resolve to the
  # LID wire jid (the server won't serve our own PN bundle).
  defp store_own_lid_mapping(%{creds: %{me: %{id: id, lid: lid}}} = state)
       when is_binary(id) and is_binary(lid) do
    LidMappingFileStore.store_mappings(state.conn, [{lid, id}])
  end

  defp store_own_lid_mapping(_state), do: :ok

  # Step 1: resolve the device set to encrypt for. DM = the recipient's (and our
  # own) devices. Group = every participant's (and our own) devices, after a
  # group-metadata fetch. Either way the result is a flat list of device maps.
  defp resolve_devices(%{kind: :group} = ctx) do
    with {:ok, devices, addressing_mode} <- group_devices(ctx) do
      {:ok, %{ctx | devices: devices, addressing_mode: addressing_mode}}
    end
  end

  defp resolve_devices(%{kind: :dm} = ctx) do
    with {:ok, devices} <- user_devices(ctx, [ctx.target_jid | own_id_list(ctx)]) do
      # A peer-category send (PEER_DATA_OPERATION: placeholder resend, on-demand
      # history) is addressed to OURSELVES — every resolved device is our own, so
      # the recipient-devices guard below doesn't apply. Baileys sends these to
      # jidNormalizedUser(me.id) with no such check (sendPeerDataOperationMessage).
      #
      # A self-chat ("Message Yourself") targets our own account — every resolved
      # device is ours, so the recipient-devices guard below would reject it. It's
      # a real conversation though (Baileys allows sendMessage to me.id), so skip
      # the guard, exactly like the peer_send? carve-out.
      #
      # Otherwise: if the recipient resolved to no real devices, the number isn't
      # reachable on WhatsApp (unregistered / wrong number). Fail instead of
      # fabricating a device and producing a "sent" message the server silently
      # drops — Baileys#2635. The recipient must contribute at least one device
      # (our own devices don't count).
      if peer_send?(ctx) or self_send?(ctx) or recipient_devices?(ctx, devices) do
        {:ok, %{ctx | devices: devices}}
      else
        {:error, {:resolve_devices, :not_on_whatsapp}}
      end
    end
  end

  # A peer-category stanza targets our own devices (PEER_DATA_OPERATION).
  defp peer_send?(%{stanza_attrs: %{"category" => "peer"}}), do: true
  defp peer_send?(_), do: false

  # A self-chat: the target normalizes to our own account (id or lid), ignoring
  # device. Our own devices are the legitimate recipients here.
  defp self_send?(%{target_jid: target, creds: %{me: me}}) do
    target_user = JID.jid_normalized_user(target)
    mine = [me[:id], me[:lid]] |> Enum.reject(&is_nil/1) |> Enum.map(&JID.jid_normalized_user/1)
    target_user in mine
  end

  # The device set for a list of user jids: cache-hit users skip USync; misses
  # are fetched in one query. {:ok, flat device list} | {:error, {stage, reason}}.
  defp user_devices(ctx, users) do
    case DeviceListCache.get_many(ctx.conn, users) do
      {hits, []} -> {:ok, hits |> Map.values() |> List.flatten()}
      {_hits, _misses} -> usync_devices(ctx, users)
    end
  end

  # Group: fetch metadata → participant jids (+ our own) → their devices.
  # {:ok, devices, addressing_mode} | {:error, {stage, reason}}; the mode picks
  # our sender-key identity.
  defp group_devices(ctx) do
    iq = GroupMetadata.query_iq(ctx.target_jid)

    with {:ok, reply} <- Connection.query_iq(ctx.cm, iq),
         {:ok, meta} <- GroupMetadata.parse(reply) do
      store_participant_lid_mappings(ctx, meta)
      users = Enum.uniq(participant_user_jids(meta) ++ own_id_list(ctx))

      # user_devices already returns {:error, {stage, reason}} on failure.
      with {:ok, devices} <- user_devices(ctx, users) do
        {:ok, devices, meta.addressing_mode}
      end
    else
      {:error, {_stage, _reason}} = err -> err
      error -> {:error, {:group_metadata, error}}
    end
  end

  # Persist PN↔LID pairs the metadata carried, so sessions for PN-USynced devices
  # resolve to the recipient's LID identity (matching how we receive from them).
  # A lid-group participant is {id: lid, phone_number: pn}; a pn-group one is
  # {id: pn, lid: lid} — either way pull the {lid, pn} when both are present.
  defp store_participant_lid_mappings(ctx, %{participants: parts}) do
    pairs =
      for p <- parts,
          {lid, pn} = participant_lid_pn(p),
          is_binary(lid) and is_binary(pn),
          do: {lid, pn}

    unless pairs == [], do: LidMappingFileStore.store_mappings(ctx.conn, pairs)
  end

  defp participant_lid_pn(%{id: id, lid: lid, phone_number: pn}) do
    cond do
      JID.lid_user?(id) -> {id, pn}
      is_binary(lid) -> {lid, id}
      true -> {nil, nil}
    end
  end

  # Participant jids to USync for devices. USync's device directory is keyed by
  # phone number, so for a lid-addressed group we look up each member's PN
  # (participant_pn), not their lid — querying by lid gets no reply (the live
  # symptom was a USync timeout). The PN→LID session addressing is handled later
  # by LidMappingFileStore.signal_address. A pn group already exposes pn ids.
  defp participant_user_jids(%{participants: parts}) do
    Enum.map(parts, fn p -> p.phone_number || p.id end)
  end

  # Our own jid, unless we are the recipient (DM to self).
  defp own_id_list(%{creds: %{me: %{id: id}}, target_jid: id}), do: []
  defp own_id_list(%{creds: %{me: %{id: id}}}), do: [id]

  defp usync_devices(ctx, users) do
    # USync is a user→devices lookup: the <user jid> must be the bare user jid,
    # never device-suffixed (our own me.id carries our companion device, e.g.
    # :29). A device-suffixed jid makes the server drop the whole query with no
    # reply → timeout. Normalize + dedup.
    normalized = users |> Enum.map(&JID.jid_normalized_user/1) |> Enum.uniq()

    query =
      Enum.reduce(normalized, USync.with_context(USync.new(), "message"), fn user, q ->
        USync.with_user(q, %{id: user})
      end)
      |> USync.with_protocol(:devices)
      |> USync.with_protocol(:lid)

    {:ok, iq} = USync.build_iq(query)

    case Connection.query_iq(ctx.cm, iq) do
      {:ok, reply} -> {:ok, parse_devices(ctx, reply)}
      {:error, reason} -> {:error, {:usync, reason}}
    end
  end

  defp parse_devices(ctx, reply) do
    query = USync.new() |> USync.with_protocol(:devices) |> USync.with_protocol(:lid)

    case USync.parse_result(query, reply) do
      %{list: list} ->
        store_lid_mappings(ctx, list)
        me = ctx.creds.me
        # 1:1 send keeps device 0 (the recipient's primary).
        devices = USync.Devices.extract(list, me.id, Map.get(me, :lid), _exclude_zero? = false)
        cache_device_lists(ctx, devices)
        devices

      nil ->
        # No <list> in the reply — nothing resolved. Don't fabricate a device;
        # resolve_devices turns an empty set into a :not_on_whatsapp error.
        []
    end
  end

  # Does the resolved device set include at least one device that is NOT us? A
  # number that isn't on WhatsApp resolves to only our own devices (or none).
  defp recipient_devices?(ctx, devices) do
    me = ctx.creds.me
    mine = [me[:id], me[:lid]] |> Enum.reject(&is_nil/1) |> Enum.map(&JID.jid_normalized_user/1)

    Enum.any?(devices, fn %{jid: jid} ->
      JID.jid_normalized_user(jid) not in mine
    end)
  end

  # Step 2: ensure a Signal session per device, fetching bundles for any missing.
  defp ensure_sessions(%{devices: devices} = ctx) do
    missing = Enum.filter(devices, fn %{jid: jid} -> is_nil(load_session(ctx, jid)) end)

    if missing == [] do
      {:ok, ctx}
    else
      Logger.debug("Fetching bundles for #{length(missing)} device(s)")

      with {:ok, reply} <- fetch_bundles(ctx, Enum.map(missing, & &1.jid)) do
        SessionInjector.inject(reply, ctx.creds, ctx.conn)
        {:ok, ctx}
      end
    end
  end

  defp fetch_bundles(ctx, jids) do
    # Fetch keyed by LID when the user is lid-mapped (Baileys wireJids): the
    # server doesn't answer a PN bundle request for a lid-mapped user.
    wire = jids |> Enum.map(&LidMappingFileStore.wire_jid(ctx.conn, &1)) |> Enum.uniq()
    users = Enum.map(wire, fn jid -> %Node{tag: "user", attrs: %{"jid" => jid}, content: nil} end)

    iq = %Node{
      tag: "iq",
      attrs: [{"xmlns", "encrypt"}, {"type", "get"}, {"to", Constants.s_whatsapp_net()}],
      content: [%Node{tag: "key", attrs: %{}, content: users}]
    }

    case Connection.query_iq(ctx.cm, iq) do
      {:ok, reply} -> {:ok, reply}
      {:error, reason} -> {:error, {:fetch_bundles, reason}}
    end
  end

  # Step 3 (DM): encrypt per device — own companion devices get a DSM-wrapped
  # copy, the recipient's devices the plain message — advancing each ratchet.
  defp encrypt(%{kind: :dm, devices: devices, message: message, target_jid: jid} = ctx) do
    plaintext = MessageEncoder.encode(message)
    dsm_plaintext = MessageEncoder.encode(device_sent_message(message, jid))
    own_user = JID.decode(ctx.creds.me.id).user

    participants =
      Enum.map(devices, fn device ->
        bytes = if own_device?(device, own_user), do: dsm_plaintext, else: plaintext
        encrypt_for_device(ctx, device, bytes)
      end)

    {:ok, %{ctx | participants: participants}}
  end

  # Step 3 (group): encrypt the message ONCE with our sender key (skmsg), and
  # distribute our sender-key-distribution-message (SKDM) to every participant
  # device as a per-device pkmsg so they can decrypt the skmsg. First send to a
  # group distributes keys to everyone; we redistribute on every send for now.
  defp encrypt(%{kind: :group, message: message} = ctx) do
    sk_store = SenderKeyStore.build(ctx.conn)
    me_id = sender_identity(ctx)
    sender_name = SenderKeyName.from_jids(ctx.target_jid, me_id)

    {:ok, skdm} =
      GroupSessionBuilder.create_sender_key_distribution_message(
        GroupSessionBuilder.new(sk_store),
        sk_store,
        ctx.target_jid,
        me_id
      )

    {:ok, skmsg} =
      GroupCipher.encrypt(sk_store, sender_name, MessageEncoder.encode(message))

    # The SKDM-only message, encrypted per device (the dm path). It carries no
    # text — members read the body from the group skmsg; this pkmsg only delivers
    # our sender key (Baileys senderKeyMsg).
    skdm_plaintext = MessageEncoder.encode(skdm_message(ctx.target_jid, skdm))

    participants = Enum.map(ctx.devices, &encrypt_for_device(ctx, &1, skdm_plaintext))

    {:ok, %{ctx | participants: participants, skmsg: skmsg}}
  end

  # Step 4: build + relay the stanza. DM = a <participants> of per-device <enc>.
  # Group = the skmsg <enc> plus the SKDM <participants>.
  defp relay(%{participants: []} = ctx) do
    {:error, {:relay, {:no_encrypted_devices, ctx.target_jid}}}
  end

  defp relay(%{kind: :group} = ctx) do
    {:ok, stanza} =
      Relay.build_group_stanza(
        ctx.msg_id,
        ctx.target_jid,
        ctx.skmsg,
        ctx.participants,
        ctx.creds.account,
        edit: ctx.edit_attr,
        extra_attrs: ctx.stanza_attrs
      )

    Logger.debug("Relaying group #{ctx.msg_id} (#{length(ctx.participants)} devices)")

    # relay_stanza enqueues the frame on the socket and replies :ok (it can't know
    # delivery — that's what later receipts report). Its :ok is this stage's result.
    Connection.relay_stanza(ctx.cm, stanza)
  end

  defp relay(ctx) do
    {:ok, stanza} =
      Relay.build_multi_device_stanza(
        ctx.msg_id,
        ctx.target_jid,
        ctx.participants,
        ctx.creds.account,
        edit: ctx.edit_attr,
        extra_attrs: ctx.stanza_attrs
      )

    Logger.debug("Relaying #{ctx.msg_id} (#{length(ctx.participants)} device(s))")

    Connection.relay_stanza(ctx.cm, stanza)
  end

  # --- helpers (ported from the former Connection send path) ---

  defp store_lid_mappings(ctx, list) do
    pairs = for %{id: pn} = e <- list, lid = Map.get(e, "lid"), is_binary(lid), do: {lid, pn}

    unless pairs == [] do
      {count, newly} = LidMappingFileStore.store_mappings(ctx.conn, pairs)
      if count > 0, do: Logger.debug("Stored #{count} LID↔PN mapping(s) from USync")

      new_lids = for {lid, _pn} <- newly, do: lid
      Connection.assert_lid_sessions(ctx.cm, new_lids)
      # Surface the newly-learned pairs to the consumer (:lid_mapping_update).
      Connection.notify_lid_mappings(ctx.cm, newly)
    end

    :ok
  end

  defp cache_device_lists(ctx, devices) do
    DeviceListCache.put_many(ctx.conn, Enum.group_by(devices, & &1.user))
  end

  # {device_jid, enc_type, ciphertext}. Session keyed by the LID address when a
  # mapping exists; wire <to jid> stays the PN device jid.
  defp encrypt_for_device(ctx, %{jid: device_jid}, plaintext) do
    addr = LidMappingFileStore.signal_address(ctx.conn, device_jid)
    store = SessionStore.build(ctx.creds)
    record = SessionStore.load_session(ctx.conn, addr)

    # SessionCipher.encrypt returns {:ok, ...} or raises (let-it-crash); there is
    # no error tuple to handle.
    {:ok, enc_type, ciphertext, record} = SessionCipher.encrypt(record, plaintext, store)
    SessionStore.store_session(ctx.conn, addr, record)
    {device_jid, enc_type, ciphertext}
  end

  defp load_session(ctx, jid),
    do: SessionStore.load_session(ctx.conn, LidMappingFileStore.signal_address(ctx.conn, jid))

  defp own_device?(%{user: user}, own_user), do: user == own_user

  defp device_sent_message(message, destination_jid) do
    %Proto.Message{
      deviceSentMessage: %Proto.Message.DeviceSentMessage{
        destinationJid: destination_jid,
        message: message
      },
      messageContextInfo: Map.get(message, :messageContextInfo)
    }
  end

  # Our sender identity for the group's sender key: LID for a lid-addressed
  # group, otherwise our PN. Must match how the group addresses us so peers find
  # our sender key under the right name.
  defp sender_identity(%{addressing_mode: :lid, creds: %{me: %{lid: lid}}}) when is_binary(lid),
    do: lid

  defp sender_identity(%{creds: %{me: %{id: id}}}), do: id

  # The per-device message that distributes our sender key — SKDM only, no body
  # (Baileys senderKeyMsg). Members read the actual text from the group skmsg.
  defp skdm_message(group_jid, skdm) do
    %Proto.Message{
      senderKeyDistributionMessage: %Proto.Message.SenderKeyDistributionMessage{
        groupId: group_jid,
        axolotlSenderKeyDistributionMessage: skdm.serialized
      }
    }
  end
end
