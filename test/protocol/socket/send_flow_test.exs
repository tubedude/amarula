defmodule Amarula.Protocol.Socket.SendFlowTest do
  @moduledoc """
  End-to-end test of the multi-device send pipeline. A per-recipient
  `ConversationSender` runs the blocking `ctx -> ctx` pipe, calling the (dumb)
  `ConnectionManager` for IQ round-trips:

      deliver({:send, msg})
        └─ resolve_devices  → query_iq(usync)   ──▶ (inject usync result)
             └─ ensure_sessions → query_iq(bundle) ──▶ (inject bundle result)
                  └─ encrypt + relay_stanza <participants>

  Test seams on ConnectionManager (config-driven, inert in production):
    * `frame_sink` — captures decoded outbound nodes (IQs + the relayed stanza)
    * `connection_state: :connected` — start connected without a real handshake
    * `{:inject_node, node}` — feed a synthetic server reply; for a query_iq the
      reply unblocks the waiting sender via GenServer.reply.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.Protocol.Messages.ConversationSender
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.{LidMappingFileStore, SessionStore}
  alias Amarula.Protocol.Socket.ConnectionManager

  # Obviously-fake placeholder JIDs — not real numbers.
  @jid "10000000001@s.whatsapp.net"
  # Device 0 emits NO `:0` suffix (Baileys jidEncode `!!device`), so the wire jid
  # for the recipient's primary is the bare user jid.
  @device0_jid "10000000001@s.whatsapp.net"
  @me_jid "10000000002@s.whatsapp.net"
  @bundle_path Path.expand("../../fixtures/initiator_bundle.json", __DIR__)

  defp d64(s), do: Base.decode64!(s)
  defp raw(<<5, k::binary-size(32)>>), do: k
  defp raw(<<k::binary-size(32)>>), do: k

  defp creds do
    alice = Crypto.generate_key_pair()

    %{
      registration_id: 4242,
      signed_identity_key: %{public: alice.public, private: alice.private},
      signed_pre_key: %{key_id: 1, key_pair: alice},
      pre_keys: %{},
      me: %{id: @me_jid, lid: nil, name: "Tester"},
      account: %Proto.ADVSignedDeviceIdentity{details: <<1, 2, 3>>}
    }
  end

  # Stamp a reply IQ with the id of the request it answers — the GenServer
  # correlates tracked IQs by id, so a reply without it is dropped.
  defp with_id(%Node{attrs: attrs} = node, id), do: %{node | attrs: Map.put(attrs, "id", id)}

  # USync devices result: recipient has a single device 0. When `lid` is given,
  # the user node also carries a <lid val=...> so the pipeline stores a mapping.
  defp usync_devices_reply(id, lid \\ nil) do
    device_list =
      Node.create("device-list", %{}, [
        Node.create("device", %{"id" => "0"}, nil)
      ])

    user_children =
      [Node.create("devices", %{}, [device_list])] ++
        if lid, do: [Node.create("lid", %{"val" => lid}, nil)], else: []

    user = Node.create("user", %{"jid" => @jid}, user_children)
    list = Node.create("list", %{}, [user])
    usync = Node.create("usync", %{}, [list])
    with_id(Node.create("iq", %{"type" => "result"}, [usync]), id)
  end

  # USync result with two user entries: the recipient (device 0) and ourselves
  # (devices 0 + `own_device`), so the pipeline fans a DSM copy to our companion.
  defp usync_reply_with_own(id, own_device) do
    recipient = usync_user_node(@jid, ["0"])
    own = usync_user_node(@me_jid, ["0", Integer.to_string(own_device)])
    usync = Node.create("usync", %{}, [Node.create("list", %{}, [recipient, own])])
    with_id(Node.create("iq", %{"type" => "result"}, [usync]), id)
  end

  # USync result with a device-0 entry for each member jid.
  defp usync_members_reply(id, member_jids) do
    users = Enum.map(member_jids, &usync_user_node(&1, ["0"]))
    usync = Node.create("usync", %{}, [Node.create("list", %{}, users)])
    with_id(Node.create("iq", %{"type" => "result"}, [usync]), id)
  end

  defp usync_user_node(jid, device_ids) do
    devices =
      Node.create("device-list", %{}, Enum.map(device_ids, &device_node/1))

    Node.create("user", %{"jid" => jid}, [Node.create("devices", %{}, [devices])])
  end

  # Non-zero devices need a key-index or extract/4 drops them.
  defp device_node("0"), do: Node.create("device", %{"id" => "0"}, nil)
  defp device_node(id), do: Node.create("device", %{"id" => id, "key-index" => "1"}, nil)

  # Lid-addressed group metadata: each participant's jid is a lid carrying its
  # phone_number (mirrors a real lid group). `members` = [{lid, pn}, ...].
  defp lid_group_metadata_reply(id, group_jid, members) do
    parts =
      Enum.map(members, fn {lid, pn} ->
        Node.create("participant", %{"jid" => lid, "phone_number" => pn}, nil)
      end)

    group = Node.create("group", %{"id" => group_jid, "addressing_mode" => "lid"}, parts)
    with_id(Node.create("iq", %{"type" => "result"}, [group]), id)
  end

  # Group metadata IQ result with the given participant jids (all members, PN).
  defp group_metadata_reply(id, group_jid, participant_jids) do
    parts = Enum.map(participant_jids, &Node.create("participant", %{"jid" => &1}, nil))
    group = Node.create("group", %{"id" => group_jid, "subject" => "Test"}, parts)
    with_id(Node.create("iq", %{"type" => "result"}, [group]), id)
  end

  # Prekey-bundle result assembled from Bob's fixture (same shape the
  # SessionInjector test uses). Accepts one jid or a list — one <user> per jid.
  defp bundle_reply(id, jids \\ @jid)

  defp bundle_reply(id, jid) when is_binary(jid), do: bundle_reply(id, [jid])

  defp bundle_reply(id, jids) when is_list(jids) do
    users = Enum.map(jids, &bundle_user_node/1)
    with_id(Node.create("iq", %{"type" => "result"}, [Node.create("list", %{}, users)]), id)
  end

  defp bundle_user_node(jid) do
    bundle = @bundle_path |> File.read!() |> JSON.decode!()

    Node.create("user", %{"jid" => jid}, [
      Node.create("registration", %{}, <<bundle["registrationId"]::big-unsigned-32>>),
      Node.create("identity", %{}, raw(d64(bundle["identityPub"]))),
      Node.create("skey", %{}, [
        Node.create("id", %{}, <<bundle["signedPreKeyId"]::big-unsigned-24>>),
        Node.create("value", %{}, raw(d64(bundle["signedPreKeyPub"]))),
        Node.create("signature", %{}, d64(bundle["signedPreKeySig"]))
      ]),
      Node.create("key", %{}, [
        Node.create("id", %{}, <<bundle["preKeyId"]::big-unsigned-24>>),
        Node.create("value", %{}, raw(d64(bundle["preKeyPub"])))
      ])
    ])
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_sendflow_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    config = %{
      wa_websocket_url: "wss://test.example.com/ws",
      max_retries: 1,
      retry_delay: 100,
      connection_state: :connected,
      frame_sink: self(),
      profile: :test,
      storage: {Amarula.Storage.File, root: dir},
      auth: creds()
    }

    {:ok, pid} = ConnectionManager.start_link(config)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    # Per-recipient sender infra (normally owned by ConnectionSupervisor).
    registry = :"send_flow_registry_#{System.unique_integer([:positive])}"
    {:ok, _} = Registry.start_link(keys: :unique, name: registry)
    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    # Stable creds for the whole test (a fresh keypair per send would break
    # multi-send cases that reuse a session).
    {:ok,
     pid: pid, conn: Amarula.Conn.new(config), registry: registry, supervisor: sup, creds: creds()}
  end

  # Trigger a send the way Socket.send_text does: deliver to the recipient's
  # ConversationSender. Returns the msg_id. The sender runs the blocking pipe in
  # its own process; the test answers its query_iq calls via inject_node.
  defp send_text(ctx, jid, text) do
    msg_id = "3EB0" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :upper))

    opts = [
      registry: ctx.registry,
      supervisor: ctx.supervisor,
      cm: ctx.pid,
      conn: ctx.conn,
      creds: ctx.creds,
      recipient_jid: jid
    ]

    :ok = ConversationSender.deliver(opts, %{msg_id: msg_id, text: text})
    msg_id
  end

  defp recv_frame do
    receive do
      {:frame_out, node} -> node
    after
      1000 -> flunk("timed out waiting for an outbound frame")
    end
  end

  # Outbound IQs use keyword-list attrs (the encoder's ordered form); replies we
  # build use maps. Read an attr from either shape.
  defp attr(%Node{attrs: attrs}, key) when is_list(attrs) do
    case List.keyfind(attrs, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp attr(node, key), do: NodeUtils.get_attr(node, key)

  # Inject a synthetic server reply into the (test) ConnectionManager.
  defp inject(ctx, node), do: send(ctx.pid, {:inject_node, node})

  # The sender emits encrypt/get IQs (bundle fetch + any LID force-refresh) then
  # the message. Drain frames, answer each encrypt IQ with a bundle for the jids
  # it asked for, and return the message frame.
  defp drain_until_message(ctx) do
    case recv_frame() do
      %{tag: "message"} = message ->
        message

      %{tag: "iq"} = iq ->
        requested =
          iq
          |> NodeUtils.get_binary_node_child("key")
          |> Map.get(:content)
          |> Enum.map(&NodeUtils.get_attr(&1, "jid"))

        inject(ctx, bundle_reply(attr(iq, "id"), requested))
        drain_until_message(ctx)
    end
  end

  # Recv frames until an encrypt/get IQ whose first <user> carries
  # reason="identity" (the force-refresh). Returns that user node.
  defp recv_identity_refresh do
    iq = recv_frame()
    assert iq.tag == "iq"

    user = iq |> NodeUtils.get_binary_node_child("key") |> Map.get(:content) |> hd()

    if NodeUtils.get_attr(user, "reason") == "identity",
      do: user,
      else: recv_identity_refresh()
  end

  test "resolves devices, fetches a bundle, then relays a participants stanza", ctx do
    msg_id = send_text(ctx, @jid, "hello from amarula")

    # Stage 1: USync devices query went out.
    usync_iq = recv_frame()
    assert usync_iq.tag == "iq"
    assert NodeUtils.get_attr(usync_iq, "xmlns") == "usync"
    usync = NodeUtils.get_binary_node_child(usync_iq, "usync")
    query = NodeUtils.get_binary_node_child(usync, "query")
    assert "devices" in Enum.map(query.content, & &1.tag)

    # Feed the devices result → pipeline finds no session → fetches a bundle.
    inject(ctx, usync_devices_reply(attr(usync_iq, "id")))

    bundle_iq = recv_frame()
    assert bundle_iq.tag == "iq"
    assert attr(bundle_iq, "xmlns") == "encrypt"
    key = NodeUtils.get_binary_node_child(bundle_iq, "key")
    [bundle_user] = key.content
    assert NodeUtils.get_attr(bundle_user, "jid") == @device0_jid

    # Feed the bundle → session injected → message encrypted + relayed.
    inject(ctx, bundle_reply(attr(bundle_iq, "id")))

    message = recv_frame()
    assert message.tag == "message"
    assert message.attrs["id"] == msg_id
    assert message.attrs["to"] == @jid
    assert message.attrs["type"] == "text"

    participants = NodeUtils.get_binary_node_child(message, "participants")
    [to_node] = participants.content
    assert NodeUtils.get_attr(to_node, "jid") == @device0_jid

    enc = NodeUtils.get_binary_node_child(to_node, "enc")
    # First message on a freshly injected session is a PreKeyWhisperMessage.
    assert enc.attrs["type"] == "pkmsg"
    assert is_binary(enc.content) and byte_size(enc.content) > 0

    # pkmsg ⇒ device-identity must be attached so the peer can verify us.
    assert %Node{content: identity} = NodeUtils.get_binary_node_child(message, "device-identity")
    assert is_binary(identity) and byte_size(identity) > 0
  end

  test "skips the bundle fetch when a session already exists", ctx do
    # Prime a session by running the full flow once.
    send_text(ctx, @jid, "first")
    usync1 = recv_frame()
    inject(ctx, usync_devices_reply(attr(usync1, "id")))
    bundle1 = recv_frame()
    inject(ctx, bundle_reply(attr(bundle1, "id")))
    _first_msg = recv_frame()

    # Second send: USync still runs, but the session now exists so no bundle IQ.
    msg_id = send_text(ctx, @jid, "second")
    usync_iq = recv_frame()
    assert NodeUtils.get_attr(usync_iq, "xmlns") == "usync"

    inject(ctx, usync_devices_reply(attr(usync_iq, "id")))

    # Next frame should be the message directly (not an encrypt/get bundle IQ).
    next = recv_frame()
    assert next.tag == "message"
    assert next.attrs["id"] == msg_id

    # The key assertion is that NO bundle fetch happened between the USync reply
    # and this message — the existing session was reused. (The enc stays a pkmsg
    # until the recipient replies and advances the ratchet, so we don't assert on
    # the enc type here.)
    enc =
      next
      |> NodeUtils.get_binary_node_child("participants")
      |> then(fn p -> hd(p.content) end)
      |> NodeUtils.get_binary_node_child("enc")

    assert is_binary(enc.content) and byte_size(enc.content) > 0
  end

  test "persists the LID↔PN mapping when the USync result carries a lid", ctx do
    lid = "20000000001@lid"

    send_text(ctx, @jid, "with lid")
    usync_iq = recv_frame()

    # USync reply includes a <lid val=...> for the recipient.
    inject(ctx, usync_devices_reply(attr(usync_iq, "id"), lid))

    # Drains the force-refresh IQ + bundle fetch, then the message.
    _msg = drain_until_message(ctx)

    assert LidMappingFileStore.lid_for_pn(ctx.conn, @jid) == "20000000001"
    assert LidMappingFileStore.pn_for_lid(ctx.conn, lid) == "10000000001"

    # LID-priority: the session was injected + stored under the recipient's LID
    # address (20000000001_1.0), not the PN address — even though the wire <to>
    # used the PN device jid.
    lid_addr = LidMappingFileStore.signal_address(ctx.conn, @device0_jid)
    assert lid_addr == "20000000001_1.0"
    refute is_nil(SessionStore.load_session(ctx.conn, lid_addr))
    assert is_nil(SessionStore.load_session(ctx.conn, "10000000001.0"))
  end

  test "wire <to jid> stays PN even when the session uses the LID address", ctx do
    lid = "20000000001@lid"

    send_text(ctx, @jid, "lid wire check")
    usync_iq = recv_frame()
    inject(ctx, usync_devices_reply(attr(usync_iq, "id"), lid))
    message = drain_until_message(ctx)

    [to_node] =
      message
      |> NodeUtils.get_binary_node_child("participants")
      |> Map.get(:content)

    # PN-initiated send ⇒ wire jid is the PN device jid, not the LID.
    assert NodeUtils.get_attr(to_node, "jid") == @device0_jid
  end

  test "force-refreshes sessions for a newly mapped LID (reason=identity)", ctx do
    lid = "20000000001@lid"

    send_text(ctx, @jid, "force refresh")
    usync_iq = recv_frame()
    inject(ctx, usync_devices_reply(attr(usync_iq, "id"), lid))

    # The send's bundle fetch and the (cast-driven) force-refresh both go out;
    # the refresh is the encrypt IQ requesting the LID jid with reason=identity.
    user = recv_identity_refresh()
    assert NodeUtils.get_attr(user, "jid") == lid
    assert NodeUtils.get_attr(user, "reason") == "identity"
  end

  test "does not force-refresh when the mapping already exists", ctx do
    lid = "20000000001@lid"
    # Pre-seed the mapping so the USync result reports nothing new.
    LidMappingFileStore.store_mappings(ctx.conn, [{lid, @jid}])

    msg_id = send_text(ctx, @jid, "no refresh")
    usync_iq = recv_frame()
    inject(ctx, usync_devices_reply(attr(usync_iq, "id"), lid))

    # No force-refresh IQ — the next frame is the bundle fetch for the send.
    bundle_iq = recv_frame()
    [user] = bundle_iq |> NodeUtils.get_binary_node_child("key") |> Map.get(:content)
    # lid-mapped user ⇒ bundle fetch is keyed by the LID wire jid, not PN
    # (Baileys wireJids). The MAIN per-device fetch carries NO reason —
    # reason="identity" is only for the separate newly-mapped-LID force-refresh
    # (Baileys assertSessions force path). A reason on the main fetch makes the
    # server silently drop it.
    assert NodeUtils.get_attr(user, "jid") == "20000000001@lid"
    refute NodeUtils.get_attr(user, "reason")

    inject(ctx, bundle_reply(attr(bundle_iq, "id")))
    message = recv_frame()
    assert message.attrs["id"] == msg_id
  end

  test "fans out a DSM copy to our own companion device", ctx do
    own_device_jid = "10000000002:1@s.whatsapp.net"

    send_text(ctx, @jid, "dsm fanout")
    usync_iq = recv_frame()
    # USync also enumerates our own devices (device 1 is a companion).
    inject(ctx, usync_reply_with_own(attr(usync_iq, "id"), 1))

    message = drain_until_message(ctx)

    to_nodes =
      message |> NodeUtils.get_binary_node_child("participants") |> Map.get(:content)

    jids = Enum.map(to_nodes, &NodeUtils.get_attr(&1, "jid"))

    # Both the recipient's device and our companion device received a copy.
    assert @device0_jid in jids
    assert own_device_jid in jids

    # The two copies differ (recipient gets the plain message, our companion a
    # DSM-wrapped one), so their ciphertexts are not identical.
    enc_for = fn jid ->
      to_nodes
      |> Enum.find(&(NodeUtils.get_attr(&1, "jid") == jid))
      |> NodeUtils.get_binary_node_child("enc")
      |> Map.get(:content)
    end

    assert enc_for.(@device0_jid) != enc_for.(own_device_jid)
  end

  test "asks USync for both the recipient and our own devices", ctx do
    send_text(ctx, @jid, "two users")
    usync_iq = recv_frame()

    list =
      usync_iq
      |> NodeUtils.get_binary_node_child("usync")
      |> NodeUtils.get_binary_node_child("list")

    jids = list.content |> Enum.map(&NodeUtils.get_attr(&1, "jid")) |> Enum.sort()

    assert jids == Enum.sort([@jid, @me_jid])
  end

  test "second send to the same recipient skips USync (device cache hit)", ctx do
    # First send: full flow populates the device cache for both the recipient and
    # our own user (USync enumerates both), plus the sessions.
    send_text(ctx, @jid, "first")
    usync_iq = recv_frame()
    assert NodeUtils.get_attr(usync_iq, "xmlns") == "usync"
    inject(ctx, usync_reply_with_own(attr(usync_iq, "id"), 1))
    _first = drain_until_message(ctx)

    # Second send: devices are cached → no USync; sessions exist → no bundle
    # fetch. First (and only) frame is the message itself.
    msg_id = send_text(ctx, @jid, "second")
    frame = recv_frame()

    assert frame.tag == "message"
    assert frame.attrs["id"] == msg_id
  end

  test "group send: metadata → participant USync → skmsg + SKDM fan-out", ctx do
    group = "120363000000000001@g.us"
    # Group has us + one other member (both PN-addressed).
    members = [@me_jid, @jid]

    msg_id = send_text(ctx, group, "hello group")

    # Stage 1a: group metadata query (w:g2) goes out.
    meta_iq = recv_frame()
    assert meta_iq.tag == "iq"
    assert attr(meta_iq, "xmlns") == "w:g2"
    assert attr(meta_iq, "to") == group
    inject(ctx, group_metadata_reply(attr(meta_iq, "id"), group, members))

    # Stage 1b: USync the members' devices.
    usync_iq = recv_frame()
    assert NodeUtils.get_attr(usync_iq, "xmlns") == "usync"
    inject(ctx, usync_members_reply(attr(usync_iq, "id"), members))

    # Stage 2 + 4: bundle fetches for missing sessions, then the group stanza.
    message = drain_until_message(ctx)
    assert message.tag == "message"
    assert message.attrs["id"] == msg_id
    assert message.attrs["to"] == group

    # The group ciphertext: one top-level <enc type=skmsg>.
    skmsg = NodeUtils.get_binary_node_child(message, "enc")
    assert skmsg.attrs["type"] == "skmsg"
    assert is_binary(skmsg.content) and byte_size(skmsg.content) > 0

    # The SKDM fan-out: a <participants> of per-device pkmsg <enc>.
    participants = NodeUtils.get_binary_node_child(message, "participants")
    to_nodes = participants.content
    assert to_nodes != []

    Enum.each(to_nodes, fn to ->
      enc = NodeUtils.get_binary_node_child(to, "enc")
      assert enc.attrs["type"] == "pkmsg"
    end)

    # pkmsg SKDMs ⇒ device-identity attached.
    assert %Node{content: identity} = NodeUtils.get_binary_node_child(message, "device-identity")
    assert is_binary(identity) and byte_size(identity) > 0
  end

  test "lid group: USyncs participants by PN (not lid) and stores LID mappings", ctx do
    group = "120363000000000002@g.us"
    member_lid = "44444444444444@lid"
    member_pn = "10000000009@s.whatsapp.net"
    me_pn = @me_jid

    send_text(ctx, group, "oi lid group")

    meta_iq = recv_frame()
    assert attr(meta_iq, "xmlns") == "w:g2"
    inject(ctx, lid_group_metadata_reply(attr(meta_iq, "id"), group, [{member_lid, member_pn}]))

    # The device USync must ask for the participant's PN, not the lid. (Querying
    # by lid is what hung live.)
    usync_iq = recv_frame()
    assert NodeUtils.get_attr(usync_iq, "xmlns") == "usync"

    queried =
      usync_iq
      |> NodeUtils.get_binary_node_child("usync")
      |> NodeUtils.get_binary_node_child("list")
      |> Map.get(:content)
      |> Enum.map(&NodeUtils.get_attr(&1, "jid"))

    assert member_pn in queried
    assert me_pn in queried
    refute member_lid in queried

    # The PN↔LID mapping from metadata is persisted.
    assert LidMappingFileStore.lid_for_pn(ctx.conn, member_pn) == "44444444444444"
  end
end
