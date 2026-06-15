defmodule Amarula.Protocol.Socket.SendFlowTest do
  @moduledoc """
  End-to-end test of the multi-device send pipeline. A per-recipient
  `ConversationSender` runs the blocking `ctx -> ctx` pipe, calling the (dumb)
  `Connection` for IQ round-trips:

      deliver({:send, msg})
        └─ resolve_devices  → query_iq(usync)   ──▶ (inject usync result)
             └─ ensure_sessions → query_iq(bundle) ──▶ (inject bundle result)
                  └─ encrypt + relay_stanza <participants>

  Test seams on Connection (config-driven, inert in production):
    * `frame_sink` — captures decoded outbound nodes (IQs + the relayed stanza)
    * `connection_state: :connected` — start connected without a real handshake
    * `{:inject_node, node}` — feed a synthetic server reply; for a query_iq the
      reply unblocks the waiting sender via GenServer.reply.
    * `ack_timeout_ms` — shrink the ack-timeout for the timeout test.

  Ack-on-send (Design 2): a consumer send now completes only when the server's
  `<ack class="message" id=msg_id>` arrives. Sends are driven through the real
  `Connection.send_*` client API (in a Task so the test stays free to inject) so
  `Connection` parks the caller's `from` under msg_id; the test injects the
  USync/bundle replies, observes the relayed `<message>` (whose `id` is the
  msg_id), then injects the `<ack>` to unblock the caller.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.Protocol.Messages.ConversationSender
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.{LidMappingFileStore, SessionStore}
  alias Amarula.Protocol.Socket.ConnectionSupervisor
  alias Amarula.Connection

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

  setup context do
    dir = Path.join(System.tmp_dir!(), "amarula_sendflow_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    config =
      %{
        wa_websocket_url: "wss://test.example.com/ws",
        max_retries: 1,
        retry_delay: 100,
        connection_state: :connected,
        frame_sink: self(),
        profile: :test,
        storage: {Amarula.Storage.File, root: dir},
        auth: creds()
      }
      |> maybe_put(:ack_timeout_ms, context[:ack_timeout_ms])

    # A real per-instance Registry + sender DynamicSupervisor, registered under the
    # names ConnectionSupervisor derives from instance_id — so Connection's
    # `deliver_async` dispatches to the per-recipient ConversationSender exactly as
    # in production (it looks them up by instance_id). Driving sends through
    # Connection.send_* (below) thus exercises the real ack-parking path.
    instance_id = make_ref()
    registry = ConnectionSupervisor.registry_name(instance_id)
    {:ok, _} = Registry.start_link(keys: :unique, name: registry)

    {:ok, sup} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: ConnectionSupervisor.name(instance_id, :sender_supervisor)
      )

    {:ok, pid} =
      Connection.start_link(config,
        name: :"conn_#{:erlang.phash2(instance_id)}",
        instance_id: instance_id
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    # Stable creds for the whole test (a fresh keypair per send would break
    # multi-send cases that reuse a session).
    {:ok,
     pid: pid, conn: Amarula.Conn.new(config), registry: registry, supervisor: sup, creds: creds()}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Drive a send through the real consumer API. `Connection.send_text` is a
  # blocking GenServer.call that completes only on the server's <ack> (ack-on-send,
  # Design 2), so run it in a Task to keep THIS process free to inject the
  # USync/bundle/ack replies the send is waiting on. Returns the Task — await its
  # reply with await_send_result/1. The msg_id isn't known up front; read it from
  # the relayed <message> frame (recv_frame) and feed it back via ack/2.
  defp send_text_async(ctx, jid, text) do
    Task.async(fn -> Connection.send_text(ctx.pid, jid, text) end)
  end

  # The fire-and-forget convenience for tests that only assert on frames, not the
  # reply: start the send and return the Task (the caller may ignore it).
  defp send_text(ctx, jid, text) do
    send_text_async(ctx, jid, text)
  end

  defp await_send_result(task) do
    case Task.yield(task, 2000) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> flunk("timed out waiting for the send result")
    end
  end

  # An inbound server <ack class="message" id=msg_id [error=code] [phash=...]> —
  # the confirmation (or rejection) that completes a parked send. `:phash` models
  # the group/multi-device "not all devices yet" ack the server may emit.
  defp ack(ctx, msg_id, opts \\ []) do
    attrs = %{"class" => "message", "id" => msg_id}
    attrs = if code = opts[:error], do: Map.put(attrs, "error", code), else: attrs
    attrs = if ph = opts[:phash], do: Map.put(attrs, "phash", ph), else: attrs
    inject(ctx, Node.create("ack", attrs, nil))
  end

  # Run the USync + bundle round-trips for a single-recipient text send, returning
  # the relayed <message> frame (whose `id` attr is the msg_id to ack).
  defp relay_text(ctx) do
    usync = recv_frame()
    inject(ctx, usync_devices_reply(attr(usync, "id")))
    drain_until_message(ctx)
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

  # Inject a synthetic server reply into the (test) Connection.
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
    task = send_text_async(ctx, @jid, "hello from amarula")

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
    msg_id = message.attrs["id"]
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

    # Ack-on-send: the caller stays blocked until the server confirms the msg_id.
    ack(ctx, msg_id)
    assert {:ok, ^msg_id} = await_send_result(task)
  end

  test "emits an [:amarula, :send, :stop] telemetry span on a successful send", ctx do
    ref = make_ref()
    test_pid = self()

    :telemetry.attach(
      {ref, :send_stop},
      [:amarula, :send, :stop],
      fn name, meas, meta, _ -> send(test_pid, {:telemetry, name, meas, meta}) end,
      nil
    )

    task = send_text_async(ctx, @jid, "hi")
    usync = recv_frame()
    inject(ctx, usync_devices_reply(attr(usync, "id")))
    bundle = recv_frame()
    inject(ctx, bundle_reply(attr(bundle, "id")))
    message = recv_frame()
    msg_id = message.attrs["id"]
    # The send completes on the server ack; the default reply is {:ok, msg_id}.
    ack(ctx, msg_id)
    assert {:ok, ^msg_id} = await_send_result(task)

    assert_receive {:telemetry, [:amarula, :send, :stop], measurements, metadata}
    assert is_integer(measurements.duration)
    # text send → 0 declared media bytes, not a media message.
    assert measurements.bytes == 0
    assert metadata.kind == :dm
    assert metadata.media? == false
    assert metadata.profile == ctx.conn.profile

    :telemetry.detach({ref, :send_stop})
  end

  test "drops the send (no relay) when the recipient resolves to no devices", ctx do
    # A number that isn't on WhatsApp returns a USync list with no devices. The
    # send must NOT fabricate a device and relay a phantom message (Baileys#2635);
    # it drops at resolve_devices, so no bundle fetch and no <message> go out.
    import ExUnit.CaptureLog

    log =
      capture_log(fn ->
        task = send_text_async(ctx, @jid, "to an unknown number")
        usync_iq = recv_frame()
        assert NodeUtils.get_attr(usync_iq, "xmlns") == "usync"
        inject(ctx, usync_empty_reply(attr(usync_iq, "id"), @jid))

        # The send resolves to no recipient devices → the pipe fails before any
        # frame goes out, so Connection replies the error immediately (no ack).
        assert {:error, :not_on_whatsapp} = await_send_result(task)
        refute_receive {:frame_out, _}, 100
      end)

    assert log =~ "not_on_whatsapp"
  end

  @tag :capture_log
  test "concurrent sends complete in the server's ACK order, not the send order", ctx do
    # Three sends to three different recipients → three ConversationSenders running
    # in parallel + three parked acks in Connection. A send completes only on its
    # own <ack class=message id=msg_id>, so completion follows the ack-injection
    # order, regardless of which send was issued first.
    a = "20000000001@s.whatsapp.net"
    b = "20000000002@s.whatsapp.net"
    c = "20000000003@s.whatsapp.net"

    # Issue A, then B, then C (send order).
    task_a = send_text_async(ctx, a, "A")
    task_b = send_text_async(ctx, b, "B")
    task_c = send_text_async(ctx, c, "C")

    # Drive all three through USync + bundle to their relayed <message> frames,
    # then map each recipient to its minted msg_id (read off the wire).
    by_recipient =
      for _ <- 1..3, into: %{} do
        message = relay_one_message(ctx)
        {message.attrs["to"], message.attrs["id"]}
      end

    tasks = %{a => task_a, b => task_b, c => task_c}

    # Ack in a DIFFERENT order: C, then A, then B. Each ack completes exactly its
    # own send; the not-yet-acked sends stay blocked.
    ack(ctx, by_recipient[c])
    assert {:ok, id_c} = await_send_result(task_c)
    assert id_c == by_recipient[c]
    refute Task.yield(tasks[a], 0)
    refute Task.yield(tasks[b], 0)

    ack(ctx, by_recipient[a])
    assert {:ok, id_a} = await_send_result(task_a)
    assert id_a == by_recipient[a]
    refute Task.yield(tasks[b], 0)

    ack(ctx, by_recipient[b])
    assert {:ok, id_b} = await_send_result(task_b)
    assert id_b == by_recipient[b]
  end

  # Drive one send (USync devices reply + bundle replies) to its <message> frame,
  # interleaving across the concurrent senders (each frame is handled in arrival
  # order). Returns the next relayed <message>.
  defp relay_one_message(ctx) do
    case recv_frame() do
      %{tag: "message"} = message ->
        message

      %{tag: "iq"} = iq ->
        answer_send_iq(ctx, iq)
        relay_one_message(ctx)
    end
  end

  # Answer whichever send IQ this is: a USync devices query → a single-device
  # reply for the queried user; an encrypt bundle fetch → bundles for the jids.
  defp answer_send_iq(ctx, iq) do
    case attr(iq, "xmlns") do
      "usync" ->
        user = usync_target(iq)
        inject(ctx, usync_one_device_reply(attr(iq, "id"), user))

      "encrypt" ->
        requested =
          iq
          |> NodeUtils.get_binary_node_child("key")
          |> Map.get(:content)
          |> Enum.map(&NodeUtils.get_attr(&1, "jid"))

        inject(ctx, bundle_reply(attr(iq, "id"), requested))
    end
  end

  # A USync devices result for an arbitrary user jid (single device 0).
  defp usync_one_device_reply(id, jid) do
    user = usync_user_node(jid, ["0"])
    usync = Node.create("usync", %{}, [Node.create("list", %{}, [user])])
    with_id(Node.create("iq", %{"type" => "result"}, [usync]), id)
  end

  test "a send-plugin halt reports {:send_failed, msg_id, {:halted, reason}} and no frame", ctx do
    # The sender no longer replies the consumer — it reports its pipe result back
    # to Connection (`cm`). Point `cm` at the test process to observe the report
    # contract directly: a plugin halt → {:send_failed, msg_id, {:halted, reason}}
    # and nothing on the wire (Connection then replies the parked caller {:error,
    # {:halted, reason}} — covered by the deliver_async path's unit behaviour).
    conn = Amarula.Plugin.on_send(ctx.conn, fn _ctx -> {:halt, :blocked} end)

    opts = [
      registry: ctx.registry,
      supervisor: ctx.supervisor,
      cm: self(),
      conn: conn,
      creds: ctx.creds,
      recipient_jid: @jid
    ]

    {:ok, _pid} = ConversationSender.deliver(opts, %{msg_id: "3EB0HALT", text: "nope"})

    assert_receive {:send_failed, "3EB0HALT", {:halted, :blocked}}, 2000
    refute_receive {:frame_out, _}, 100
  end

  # A USync result for a number with no WhatsApp devices: the user node carries an
  # empty device-list.
  defp usync_empty_reply(id, jid) do
    user =
      Node.create("user", %{"jid" => jid}, [
        Node.create("devices", %{}, [Node.create("device-list", %{}, [])])
      ])

    list = Node.create("list", %{}, [user])
    usync = Node.create("usync", %{}, [list])
    with_id(Node.create("iq", %{"type" => "result"}, [usync]), id)
  end

  # The <user jid> a USync IQ frame is asking about (which recipient it's for).
  defp usync_target(iq) do
    iq
    |> NodeUtils.get_binary_node_child("usync")
    |> NodeUtils.get_binary_node_child("list")
    |> NodeUtils.get_binary_node_child("user")
    |> NodeUtils.get_attr("jid")
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
    send_text(ctx, @jid, "second")
    usync_iq = recv_frame()
    assert NodeUtils.get_attr(usync_iq, "xmlns") == "usync"

    inject(ctx, usync_devices_reply(attr(usync_iq, "id")))

    # Next frame should be the message directly (not an encrypt/get bundle IQ).
    next = recv_frame()
    assert next.tag == "message"
    assert is_binary(next.attrs["id"])

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

    send_text(ctx, @jid, "no refresh")
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
    assert is_binary(message.attrs["id"])
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
    send_text(ctx, @jid, "second")
    frame = recv_frame()

    assert frame.tag == "message"
    assert is_binary(frame.attrs["id"])
  end

  test "group send: metadata → participant USync → skmsg + SKDM fan-out", ctx do
    group = "120363000000000001@g.us"
    # Group has us + one other member (both PN-addressed).
    members = [@me_jid, @jid]

    task = send_text_async(ctx, group, "hello group")

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
    msg_id = message.attrs["id"]
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

    # One group message stanza ⇒ one server ack completes the send.
    ack(ctx, msg_id)
    assert {:ok, ^msg_id} = await_send_result(task)
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

  # --- Ack-on-send (Design 2) ---

  test "a plain server ack completes the send with {:ok, msg_id}", ctx do
    task = send_text_async(ctx, @jid, "ack me")
    message = relay_text(ctx)
    msg_id = message.attrs["id"]

    # Caller is still blocked until the server confirms the relayed frame.
    refute Task.yield(task, 0)

    ack(ctx, msg_id)
    assert {:ok, ^msg_id} = await_send_result(task)
  end

  test "an ack carrying an error attr fails the send with {:send_rejected, code}", ctx do
    task = send_text_async(ctx, @jid, "will be rejected")
    message = relay_text(ctx)
    msg_id = message.attrs["id"]

    # A class=message ack with an `error` attr is a server rejection — NOT a
    # success, and never a resend (Baileys handleBadAck loops on resend).
    ack(ctx, msg_id, error: "479")
    assert {:error, {:send_rejected, "479"}} = await_send_result(task)
  end

  test "a phash ack (no error attr) is success, never a resend", ctx do
    # Baileys handleBadAck warns a phash-driven resend loops. A plain ack — even
    # one carrying a phash — is success; only an `error` attr is a failure.
    task = send_text_async(ctx, @jid, "phash ack")
    message = relay_text(ctx)
    msg_id = message.attrs["id"]

    inject(
      ctx,
      Node.create("ack", %{"class" => "message", "id" => msg_id, "phash" => "1:abc"}, nil)
    )

    assert {:ok, ^msg_id} = await_send_result(task)
    # No resend frame went out after the ack.
    refute_receive {:frame_out, _}, 100
  end

  @tag ack_timeout_ms: 80
  test "a relayed send with no ack times out with {:error, :ack_timeout}", ctx do
    # The ack-timeout is shrunk to 80ms via config (see setup). The frame is
    # written but no <ack> is injected, so Connection reports it unconfirmed.
    task = send_text_async(ctx, @jid, "never acked")
    _message = relay_text(ctx)

    assert {:error, :ack_timeout} = await_send_result(task)
  end

  test "an ack for an unknown msg_id is ignored (no crash, no stray reply)", ctx do
    task = send_text_async(ctx, @jid, "real send")
    message = relay_text(ctx)
    msg_id = message.attrs["id"]

    # An ack for a different id must not resolve our parked send.
    ack(ctx, "3EB0DEADBEEF")
    refute Task.yield(task, 50)

    # The correct ack still completes it — the connection survived the stray ack.
    ack(ctx, msg_id)
    assert {:ok, ^msg_id} = await_send_result(task)
  end

  # --- Multi-ack (group / multi-device): the server may send a phash ack ("not all
  # devices yet") and/or more than one ack for a single message id. We resolve on
  # the first no-error ack; later acks for the same id are no-ops.

  test "a phash ack resolves the send {:ok} (server accepted it)", ctx do
    task = send_text_async(ctx, @jid, "to a group-ish recipient")
    message = relay_text(ctx)
    msg_id = message.attrs["id"]

    # phash = propagation not complete to all devices — but the server ACCEPTED the
    # message, so the caller completes {:ok}.
    ack(ctx, msg_id, phash: "1:abc")
    assert {:ok, ^msg_id} = await_send_result(task)
  end

  test "a second ack for the same id (phash then clean) is a harmless no-op", ctx do
    task = send_text_async(ctx, @jid, "double-acked")
    message = relay_text(ctx)
    msg_id = message.attrs["id"]

    ack(ctx, msg_id, phash: "1:abc")
    assert {:ok, ^msg_id} = await_send_result(task)

    # The clean follow-up ack for the same (already-resolved) id must not crash the
    # connection or produce a stray reply.
    ack(ctx, msg_id)
    refute_receive _, 50
    assert Process.alive?(ctx.pid)
  end

  test "group send: a single ack completes it; a duplicate ack is a no-op", ctx do
    group = "120363000000000099@g.us"
    members = [@me_jid, @jid]

    task = send_text_async(ctx, group, "hello group multi-ack")

    meta_iq = recv_frame()
    assert attr(meta_iq, "xmlns") == "w:g2"
    inject(ctx, group_metadata_reply(attr(meta_iq, "id"), group, members))

    usync_iq = recv_frame()
    assert NodeUtils.get_attr(usync_iq, "xmlns") == "usync"
    inject(ctx, usync_members_reply(attr(usync_iq, "id"), members))

    message = drain_until_message(ctx)
    msg_id = message.attrs["id"]
    assert message.attrs["to"] == group

    # One stanza → one id; the first ack completes it.
    ack(ctx, msg_id)
    assert {:ok, ^msg_id} = await_send_result(task)

    # A duplicate ack for the same group msg_id is a no-op.
    ack(ctx, msg_id)
    refute_receive _, 50
    assert Process.alive?(ctx.pid)
  end

  # --- Sender crash (#7): Connection monitors each sender; its :DOWN fails the
  # recipient's parked sends fast + correctly, instead of hanging to :ack_timeout.

  # The per-recipient sender pid, looked up in the same Registry Connection uses.
  defp sender_pid(ctx, jid) do
    case Registry.lookup(ctx.registry, jid) do
      [{pid, _}] -> pid
      [] -> flunk("no sender registered for #{jid}")
    end
  end

  test "a sender crash fails the parked caller fast with :sender_crashed", ctx do
    task = send_text_async(ctx, @jid, "in flight")
    # Drive the pipe to the point the sender is alive + the send is parked, then
    # kill it as if it had crashed mid-pipe (before reporting any result).
    _message = relay_text(ctx)

    Process.exit(sender_pid(ctx, @jid), :kill)

    # The caller is unblocked promptly — NOT after the 30s ack-timeout — and with
    # the right reason.
    assert {:error, {:sender_crashed, :killed}} = await_send_result(task)
  end

  test "a sender crash fails ALL of that recipient's in-flight sends", ctx do
    # Two sends to the same recipient share one sender. Park the first (full
    # flow), then queue a second to the same jid (device cache hit → message only).
    task1 = send_text_async(ctx, @jid, "first")
    _m1 = relay_text(ctx)

    task2 = send_text_async(ctx, @jid, "second")
    _m2 = relay_text(ctx)

    # One crash takes out both parked sends.
    Process.exit(sender_pid(ctx, @jid), :kill)

    assert {:error, {:sender_crashed, :killed}} = await_send_result(task1)
    assert {:error, {:sender_crashed, :killed}} = await_send_result(task2)
  end

  test "a sender crash does not affect another recipient's parked send", ctx do
    other = "10000000003@s.whatsapp.net"

    task_a = send_text_async(ctx, @jid, "to A")
    msg_a = relay_text(ctx)

    task_b = send_text_async(ctx, other, "to B")
    msg_b = relay_text(ctx)

    # Crash only A's sender.
    Process.exit(sender_pid(ctx, @jid), :kill)
    assert {:error, {:sender_crashed, :killed}} = await_send_result(task_a)

    # B is untouched — its ack still completes it normally.
    ack(ctx, msg_b.attrs["id"])
    assert {:ok, _} = await_send_result(task_b)
    refute msg_a.attrs["id"] == msg_b.attrs["id"]
  end

  test "a sender idle-stop (:normal) does not reply or crash the connection", ctx do
    # Complete a send fully so nothing is parked; Connection demonitors the sender.
    task = send_text_async(ctx, @jid, "done")
    message = relay_text(ctx)
    ack(ctx, message.attrs["id"])
    assert {:ok, _} = await_send_result(task)

    # Now stop the (unmonitored, idle) sender normally. Connection must shrug it
    # off: no stray reply, still alive.
    pid = sender_pid(ctx, @jid)
    ref = Process.monitor(pid)
    GenServer.stop(pid, :normal)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

    assert Process.alive?(ctx.pid)
    refute_receive {:frame_out, _}, 50
  end
end
