defmodule Amarula.Protocol.Messages.ConversationSender do
  @moduledoc """
  Per-recipient send process. One `ConversationSender` exists per recipient JID;
  all sends to that recipient funnel through it and run **one at a time**, which
  serializes Signal ratchet advance for that recipient's session (no per-address
  lock needed). Different recipients run in parallel under the DynamicSupervisor.

  A send is a branchless pipe of `ctx -> ctx` steps that block on IQ round-trips
  through `ConnectionManager` (the sole websocket owner):

      ctx
      |> resolve_devices()   # device-list cache, else a USync query
      |> ensure_sessions()   # session files, else a prekey-bundle fetch
      |> encrypt()           # per device; plain vs DSM; advance ratchet
      |> relay()             # frame + send the <participants> stanza

  Each step that needs server data calls `ConnectionManager.query_iq/2`, which
  blocks until the matching websocket reply arrives. A step failure crashes the
  process (the DynamicSupervisor reaps it); the pipe carries no error branches.

  Lifecycle: started on demand via the Registry/DynamicSupervisor, stays alive
  after draining its queue, stops after `@idle_timeout_ms` of inactivity, and is
  respawned on the next message to that recipient.
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

  alias Amarula.Protocol.Socket.ConnectionManager
  alias Amarula.Protocol.USync

  @idle_timeout_ms 5 * 60 * 1000

  # --- API ---

  # The outer (caller-facing) send timeout. A send blocks on up to THREE sequential
  # IQ round-trips — group metadata, USync devices, prekey-bundle fetch — each
  # bounded by the CM's ~20s IQ timeout. This must exceed the worst case (3 × ~20s)
  # so a stalled round-trip surfaces as a tagged {:error, {stage, :timeout}} from
  # an inner IQ, never as an :exit from this call blowing first.
  @send_timeout_ms 90_000

  @doc """
  Start-or-lookup the sender for `recipient_jid` under `supervisor` (registered in
  `registry`), then send `msg` through it, synchronously. Idempotent: an
  already-running sender for that recipient is reused, and sends to one recipient
  are serialized (each blocks behind the prior).

  `opts` must carry `:registry`, `:supervisor`, `:cm`, `:conn`, `:creds`,
  `:recipient_jid`.

  Returns `:ok` on a successful relay, `{:error, reason}` if the send couldn't be
  delivered (e.g. `:not_on_whatsapp`, a timed-out IQ), or `{:halted, reason}` if a
  send-plugin dropped it. A consumer that wants fire-and-forget can wrap the call
  in its own `Task`.
  """
  @spec deliver(keyword(), map()) :: :ok | {:error, term()} | {:halted, term()}
  def deliver(opts, msg) do
    registry = Keyword.fetch!(opts, :registry)
    recipient = Keyword.fetch!(opts, :recipient_jid)

    pid =
      case Registry.lookup(registry, recipient) do
        [{pid, _}] -> pid
        [] -> start_child(opts)
      end

    GenServer.call(pid, {:send, msg}, @send_timeout_ms)
  end

  defp start_child(opts) do
    spec = {__MODULE__, opts}

    case DynamicSupervisor.start_child(Keyword.fetch!(opts, :supervisor), spec) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  def start_link(opts) do
    registry = Keyword.fetch!(opts, :registry)
    recipient = Keyword.fetch!(opts, :recipient_jid)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {registry, recipient}})
  end

  # --- GenServer ---

  @impl true
  def init(opts) do
    state = %{
      recipient_jid: Keyword.fetch!(opts, :recipient_jid),
      cm: Keyword.fetch!(opts, :cm),
      conn: Keyword.fetch!(opts, :conn),
      creds: Keyword.fetch!(opts, :creds)
    }

    {:ok, state, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:send, msg}, _from, state) do
    {:reply, run_send(msg, state), state, @idle_timeout_ms}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.debug("ConversationSender for #{state.recipient_jid} idle — stopping")
    {:stop, :normal, state}
  end

  # --- the send pipe ---

  defp run_send(%{msg_id: msg_id} = msg, state) do
    jid = state.recipient_jid
    kind = if JID.is_jid_group?(jid), do: :group, else: :dm
    Logger.info("Sending #{msg_id} to #{jid} (#{kind})")

    # Run the send plugin pipeline (before encrypt): steps may transform the
    # message or halt the send. The built-in retry-cache step records it here.
    case run_send_steps(state.conn, msg_id, jid, message_content(msg)) do
      {:halt, reason} ->
        Logger.info("Send #{msg_id} to #{jid} halted by a plugin: #{inspect(reason)}")
        {:halted, reason}

      {:cont, %{message: message}} ->
        store_own_lid_mapping(state)
        do_send(state, msg_id, jid, kind, message)
    end
  end

  # The plugin send pipeline. ctx carries the message + addressing + the scopes a
  # step needs (e.g. the retry cache). Returns {:cont, ctx} (possibly transformed)
  # or {:halt, reason}.
  defp run_send_steps(conn, msg_id, jid, message) do
    ctx = %{
      message: message,
      to: jid,
      profile: conn.profile,
      msg_id: msg_id,
      retry_cache: conn.retry_cache
    }

    Amarula.Plugin.run(conn.send_steps, ctx)
  end

  defp do_send(state, msg_id, jid, kind, message) do
    ctx = %{
      cm: state.cm,
      conn: state.conn,
      creds: state.creds,
      kind: kind,
      msg_id: msg_id,
      target_jid: jid,
      message: message,
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
    # media kind; :exception carries the failing stage. (Privacy: counts/kinds
    # only — no jid/content.)
    Amarula.Telemetry.span(
      [:amarula, :send],
      profile,
      %{kind: kind, media?: media?, media_kind: media_kind},
      fn -> {run_pipe(ctx, msg_id, jid, profile), %{bytes: bytes}} end
    )
  end

  # Each stage returns {:ok, ctx} or {:error, {stage, reason}}; `with` threads the
  # happy path and stops at the first failure. A recoverable failure (e.g. a
  # timed-out IQ, an unreachable recipient) is logged and returned; unexpected
  # errors still crash the (disposable) process.
  defp run_pipe(ctx, msg_id, jid, profile) do
    with {:ok, ctx} <- resolve_devices(ctx),
         {:ok, ctx} <- ensure_sessions(ctx),
         {:ok, ctx} <- encrypt(ctx),
         :ok <- relay(ctx) do
      :ok
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
    {:error, reason}
  end

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
      # If the recipient resolved to no real devices, the number isn't reachable on
      # WhatsApp (unregistered / wrong number). Fail instead of fabricating a device
      # and producing a "sent" message the server silently drops — Baileys#2635. The
      # recipient must contribute at least one device (our own devices don't count).
      if recipient_devices?(ctx, devices) do
        {:ok, %{ctx | devices: devices}}
      else
        {:error, {:resolve_devices, :not_on_whatsapp}}
      end
    end
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

    with {:ok, reply} <- ConnectionManager.query_iq(ctx.cm, iq),
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
      JID.is_lid_user?(id) -> {id, pn}
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

    case ConnectionManager.query_iq(ctx.cm, iq) do
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
      Logger.info("Fetching bundles for #{length(missing)} device(s)")

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

    case ConnectionManager.query_iq(ctx.cm, iq) do
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
      devices
      |> Enum.map(fn device ->
        bytes = if own_device?(device, own_user), do: dsm_plaintext, else: plaintext
        encrypt_for_device(ctx, device, bytes)
      end)
      |> Enum.reject(&is_nil/1)

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

    participants =
      ctx.devices
      |> Enum.map(&encrypt_for_device(ctx, &1, skdm_plaintext))
      |> Enum.reject(&is_nil/1)

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
        edit: ctx.edit_attr
      )

    Logger.info(
      "📤 Sending group #{ctx.msg_id} to #{ctx.target_jid} (#{length(ctx.participants)} devices)"
    )

    # relay_stanza enqueues the frame on the socket and replies :ok (it can't know
    # delivery — that's what later receipts report). Its :ok is this stage's result.
    ConnectionManager.relay_stanza(ctx.cm, stanza)
  end

  defp relay(ctx) do
    {:ok, stanza} =
      Relay.build_multi_device_stanza(
        ctx.msg_id,
        ctx.target_jid,
        ctx.participants,
        ctx.creds.account,
        edit: ctx.edit_attr
      )

    Logger.info(
      "📤 Sending #{ctx.msg_id} to #{length(ctx.participants)} device(s) of #{ctx.target_jid}"
    )

    ConnectionManager.relay_stanza(ctx.cm, stanza)
  end

  # --- helpers (ported from the former ConnectionManager send path) ---

  defp store_lid_mappings(ctx, list) do
    pairs = for %{id: pn} = e <- list, lid = Map.get(e, "lid"), is_binary(lid), do: {lid, pn}

    unless pairs == [] do
      {count, newly} = LidMappingFileStore.store_mappings(ctx.conn, pairs)
      if count > 0, do: Logger.debug("Stored #{count} LID↔PN mapping(s) from USync")

      new_lids = for {lid, _pn} <- newly, do: lid
      ConnectionManager.assert_lid_sessions(ctx.cm, new_lids)
    end

    :ok
  end

  defp cache_device_lists(ctx, devices) do
    DeviceListCache.put_many(ctx.conn, Enum.group_by(devices, & &1.user))
  end

  # {device_jid, enc_type, ciphertext} or nil on failure. Session keyed by the
  # LID address when a mapping exists; wire <to jid> stays the PN device jid.
  defp encrypt_for_device(ctx, %{jid: device_jid}, plaintext) do
    addr = LidMappingFileStore.signal_address(ctx.conn, device_jid)
    store = SessionStore.build(ctx.creds)
    record = SessionStore.load_session(ctx.conn, addr)

    case SessionCipher.encrypt(record, plaintext, store) do
      {:ok, enc_type, ciphertext, record} ->
        SessionStore.store_session(ctx.conn, addr, record)
        {device_jid, enc_type, ciphertext}

      other ->
        Logger.error("Encryption for #{device_jid} failed: #{inspect(other)} — skipping device")
        nil
    end
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
