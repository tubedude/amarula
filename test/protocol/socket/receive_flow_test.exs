defmodule Amarula.Protocol.Socket.ReceiveFlowTest do
  @moduledoc """
  End-to-end tests of the receive-side handlers on `Amarula.Connection`, in the
  send_flow_test style: a real Connection driven offline via the test seams —

    * `{:inject_node, %Node{}}` — feed a synthetic inbound server frame;
    * `frame_sink` — capture every outbound node as `{:frame_out, node}`;
    * `parent_pid: self()` — receive the consumer events the handlers emit.

  Covered here: the retry/resend machinery (inbound retry receipts → resend from
  the retry cache; our own decrypt failures → retry receipt + 500 nack, with the
  count>1 <keys> escalation), notification dispatch (server_sync, encrypt/prekey
  top-up, devices, w:gp2, picture, account_sync), the tracked-IQ login bootstrap
  (prekey count → upload → finish_login → :open; digest re-upload), the offline
  batch (<ib> preview/complete), inbound presence/chatstate and receipts, and
  learning our own push name from a history sync.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Amarula.Protocol.Auth.AuthUtils
  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Crypto
  alias Amarula.Protocol.Messages.Media
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.{LidMappingFileStore, SessionStore}
  alias Amarula.Protocol.Socket.ConnectionSupervisor
  alias Amarula.Connection

  # Obviously-fake placeholder JIDs — not real numbers.
  @jid "10000000001@s.whatsapp.net"
  @me_jid "10000000002@s.whatsapp.net"
  @server "@s.whatsapp.net"
  @bundle_path Path.expand("../../fixtures/initiator_bundle.json", __DIR__)

  defp d64(s), do: Base.decode64!(s)
  defp raw(<<5, k::binary-size(32)>>), do: k
  defp raw(<<k::binary-size(32)>>), do: k

  # Full generated creds (signed prekey WITH signature — the upload/keys-bundle
  # paths need it), plus a fake `me` and a stub ADV account for device-identity
  # encoding. `name` opt lets the push-name test start from the "~" placeholder.
  defp creds(opts) do
    AuthUtils.init_auth_creds()
    |> Map.put(:me, %{id: @me_jid, lid: nil, name: Keyword.get(opts, :name, "Tester")})
    |> Map.put(:account, %Proto.ADVSignedDeviceIdentity{details: <<1, 2, 3>>})
  end

  setup context do
    dir = Path.join(System.tmp_dir!(), "amarula_recvflow_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    config = %{
      wa_websocket_url: "wss://test.example.com/ws",
      max_retries: 1,
      retry_delay: 100,
      connection_state: :connected,
      frame_sink: self(),
      profile: :"recv_#{System.unique_integer([:positive])}",
      storage: {Amarula.Storage.File, root: dir},
      auth: creds(context[:creds_opts] || [])
    }

    # Real per-instance sender supervisor under the app-level InstanceRegistry, so
    # the retry-resend path (`deliver_async` → per-recipient ConversationSender)
    # runs exactly as in production.
    instance_id = make_ref()

    {:ok, sup} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: ConnectionSupervisor.name(instance_id, :sender_supervisor)
      )

    {:ok, pid} =
      Connection.start_link(config,
        name: :"recv_conn_#{:erlang.phash2(instance_id)}",
        instance_id: instance_id,
        parent_pid: self()
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    {:ok, pid: pid, conn: Amarula.Conn.new(config), supervisor: sup, config: config}
  end

  # --- shared wire helpers (send_flow_test style) ---

  defp inject(ctx, node), do: send(ctx.pid, {:inject_node, node})

  defp recv_frame do
    receive do
      {:frame_out, node} -> node
    after
      1000 -> flunk("timed out waiting for an outbound frame")
    end
  end

  # Outbound IQs use keyword-list attrs; injected replies use maps. Read either.
  defp attr(%Node{attrs: attrs}, key) when is_list(attrs) do
    case List.keyfind(attrs, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp attr(node, key), do: NodeUtils.get_attr(node, key)

  defp with_id(%Node{attrs: attrs} = node, id), do: %{node | attrs: Map.put(attrs, "id", id)}

  defp attach_telemetry(events) do
    ref = :telemetry_test.attach_event_handlers(self(), events)
    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  # --- send-pipe helpers, to prime the retry cache with a real send ---

  defp usync_user_node(jid, device_ids) do
    devices =
      Node.create("device-list", %{}, Enum.map(device_ids, &device_node/1))

    Node.create("user", %{"jid" => jid}, [Node.create("devices", %{}, [devices])])
  end

  defp device_node("0"), do: Node.create("device", %{"id" => "0"}, nil)
  defp device_node(id), do: Node.create("device", %{"id" => id, "key-index" => "1"}, nil)

  # Our own user gets a companion device (1) besides the sending device (0) —
  # without one the own-user cache entry stays empty and every send re-USyncs,
  # which would make the cache-invalidation assertions vacuous.
  defp usync_reply(id, jids) do
    users =
      Enum.map(jids, fn
        @me_jid -> usync_user_node(@me_jid, ["0", "1"])
        jid -> usync_user_node(jid, ["0"])
      end)

    usync = Node.create("usync", %{}, [Node.create("list", %{}, users)])
    with_id(Node.create("iq", %{"type" => "result"}, [usync]), id)
  end

  defp bundle_reply(id, jids) do
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

  # The user jids a USync frame is querying.
  defp usync_queried(iq) do
    iq
    |> NodeUtils.get_binary_node_child("usync")
    |> NodeUtils.get_binary_node_child("list")
    |> Map.get(:content)
    |> Enum.map(&NodeUtils.get_attr(&1, "jid"))
  end

  # Drain outbound frames answering every send-pipe IQ (USync devices, encrypt
  # bundle fetch) until the relayed <message> appears; skips non-iq frames (acks).
  defp drain_to_message(ctx) do
    case recv_frame() do
      %{tag: "message"} = message ->
        message

      %{tag: "iq"} = iq ->
        case attr(iq, "xmlns") do
          "usync" ->
            inject(ctx, usync_reply(attr(iq, "id"), usync_queried(iq)))

          "encrypt" ->
            requested =
              iq
              |> NodeUtils.get_binary_node_child("key")
              |> Map.get(:content)
              |> Enum.map(&NodeUtils.get_attr(&1, "jid"))

            inject(ctx, bundle_reply(attr(iq, "id"), requested))
        end

        drain_to_message(ctx)

      _other ->
        drain_to_message(ctx)
    end
  end

  # Run one full text send so the retry cache holds the message. Returns msg_id.
  defp complete_send(ctx, text) do
    task = Task.async(fn -> Connection.send_text(ctx.pid, @jid, text) end)
    message = drain_to_message(ctx)
    msg_id = message.attrs["id"]
    inject(ctx, Node.create("ack", %{"class" => "message", "id" => msg_id}, nil))
    assert {:ok, ^msg_id} = Task.await(task, 2000)
    msg_id
  end

  # --- retry/resend machinery (recipient couldn't decrypt OUR message) ---

  describe "inbound retry receipt (recipient asks us to resend)" do
    test "resends the cached message with the same id and acks the receipt", ctx do
      ref = attach_telemetry([[:amarula, :retry, :received]])
      msg_id = complete_send(ctx, "resend me")

      inject(ctx, retry_receipt(msg_id, @jid))

      # The receipt is acked first (class must echo the received node's tag).
      ack = recv_frame()
      assert ack.tag == "ack"
      assert attr(ack, "class") == "receipt"
      assert attr(ack, "id") == msg_id
      assert attr(ack, "to") == @jid

      # Then the original message is re-encrypted + resent with the SAME id, so
      # the recipient replaces rather than duplicates.
      resent = drain_to_message(ctx)
      assert resent.attrs["id"] == msg_id
      assert resent.attrs["to"] == @jid

      assert_receive {[:amarula, :retry, :received], ^ref, %{count: 1}, _meta}
    end

    test "a retry for an id not in the cache acks but resends nothing", ctx do
      inject(ctx, retry_receipt("3EB0DOESNOTEXIST", @jid))

      ack = recv_frame()
      assert ack.tag == "ack"
      assert attr(ack, "id") == "3EB0DOESNOTEXIST"

      # No cached copy and no get_message callback → nothing goes out.
      refute_receive {:frame_out, _}, 150
      assert Process.alive?(ctx.pid)
    end

    test "a retry receipt without an id is acked and otherwise ignored", ctx do
      node =
        Node.create("receipt", %{"from" => @jid, "type" => "retry"}, [
          Node.create("retry", %{"count" => "1", "v" => "1"}, nil)
        ])

      inject(ctx, node)

      ack = recv_frame()
      assert ack.tag == "ack"
      refute_receive {:frame_out, _}, 150
      assert Process.alive?(ctx.pid)
    end
  end

  defp retry_receipt(msg_id, from) do
    Node.create("receipt", %{"from" => from, "id" => msg_id, "type" => "retry", "t" => "1"}, [
      Node.create("retry", %{"count" => "1", "id" => msg_id, "v" => "1"}, nil)
    ])
  end

  # --- retry request (WE couldn't decrypt an inbound message) ---

  describe "undecryptable inbound message" do
    test "sends a retry receipt (count=1, registration, no keys) then a 500 nack", ctx do
      ref = attach_telemetry([[:amarula, :retry, :sent]])

      inject(ctx, undecryptable_message("MSGFAIL1", @jid))

      receipt = recv_frame()
      assert receipt.tag == "receipt"
      assert attr(receipt, "type") == "retry"
      assert attr(receipt, "id") == "MSGFAIL1"
      assert attr(receipt, "to") == @jid

      retry = NodeUtils.get_binary_node_child(receipt, "retry")
      assert attr(retry, "count") == "1"
      assert attr(retry, "id") == "MSGFAIL1"

      registration = NodeUtils.get_binary_node_child(receipt, "registration")
      assert registration.content == <<ctx.config.auth.registration_id::big-unsigned-32>>

      # First retry carries NO keys bundle — that's the count>1 escalation.
      assert NodeUtils.get_binary_node_child(receipt, "keys") == nil

      nack = recv_frame()
      assert nack.tag == "ack"
      assert attr(nack, "class") == "message"
      assert attr(nack, "id") == "MSGFAIL1"
      assert attr(nack, "error") == "500"

      assert_receive {[:amarula, :retry, :sent], ^ref, %{count: 1, attempt: 1}, _meta}
    end

    test "a second failure from the same peer escalates: count=2 with a <keys> bundle", ctx do
      ref = attach_telemetry([[:amarula, :retry, :sent]])

      inject(ctx, undecryptable_message("MSGFAIL1", @jid))
      _receipt1 = recv_frame()
      _nack1 = recv_frame()

      inject(ctx, undecryptable_message("MSGFAIL2", @jid))
      receipt2 = recv_frame()
      assert receipt2.tag == "receipt"
      retry = NodeUtils.get_binary_node_child(receipt2, "retry")
      # The counter is keyed on the peer, not the message id — a NEW id from the
      # same broken sender still escalates.
      assert attr(retry, "count") == "2"
      assert attr(retry, "id") == "MSGFAIL2"

      # count>1 ⇒ a fresh session bundle so the sender can rebuild from scratch.
      keys = NodeUtils.get_binary_node_child(receipt2, "keys")
      assert %Node{} = keys
      child_tags = Enum.map(keys.content, & &1.tag)
      assert child_tags == ["type", "identity", "key", "skey", "device-identity"]

      # The one-time prekey in the bundle was reserved (persisted) — its id is a
      # real 3-byte id and the value a 32-byte pubkey.
      key = NodeUtils.get_binary_node_child(keys, "key")
      assert %Node{content: <<_id::big-unsigned-24>>} = NodeUtils.get_binary_node_child(key, "id")

      assert %Node{content: <<_pub::binary-size(32)>>} =
               NodeUtils.get_binary_node_child(key, "value")

      _nack2 = recv_frame()

      assert_receive {[:amarula, :retry, :sent], ^ref, %{attempt: 1}, _}
      assert_receive {[:amarula, :retry, :sent], ^ref, %{attempt: 2}, _}
    end
  end

  # A <message> whose <enc type="msg"> can't decrypt (no session with the peer).
  defp undecryptable_message(id, from) do
    enc = Node.create("enc", %{"type" => "msg", "v" => "2"}, <<1, 2, 3, 4>>)

    Node.create(
      "message",
      %{"from" => from, "id" => id, "t" => "1700000000", "type" => "text"},
      [enc]
    )
  end

  # --- PN→LID session migration (#15) ---

  describe "PN→LID session migration" do
    test "moves a PN sender's session onto the LID address before decrypting", ctx do
      conn = ctx.conn

      # We know this contact's PN and LID are the same account and hold a live
      # PN-keyed Signal session for them.
      SessionStore.store_session(conn, "10000000001.0", %{sessions: %{live: true}})
      LidMappingFileStore.store_mappings(conn, [{"20000000009@lid", @jid}])

      # An inbound message from the PN address drives handle_message; the retry
      # receipt it emits (undecryptable) is our barrier that migration has run.
      inject(ctx, undecryptable_message("MIG1", @jid))
      assert recv_frame().tag == "receipt"

      # The ratchet moved to the LID signal-address; the PN entry is gone.
      assert SessionStore.load_session(conn, "20000000009_1.0") == %{sessions: %{live: true}}
      assert SessionStore.load_session(conn, "10000000001.0") == nil
    end

    test "leaves a PN sender with no known LID untouched", ctx do
      conn = ctx.conn
      SessionStore.store_session(conn, "10000000001.0", %{sessions: %{live: true}})

      inject(ctx, undecryptable_message("MIG2", @jid))
      assert recv_frame().tag == "receipt"

      # No mapping → no migration; the session stays under the PN address.
      assert SessionStore.load_session(conn, "10000000001.0") == %{sessions: %{live: true}}
    end
  end

  # --- notification dispatch ---

  describe "notification dispatch" do
    test "server_sync: acks, then resyncs exactly the named app-state collection", ctx do
      node =
        Node.create("notification", %{"type" => "server_sync", "from" => @server, "id" => "N1"}, [
          Node.create("collection", %{"name" => "regular_high"}, nil)
        ])

      inject(ctx, node)

      ack = recv_frame()
      assert ack.tag == "ack"
      assert attr(ack, "class") == "notification"
      assert attr(ack, "type") == "server_sync"

      sync_iq = recv_frame()
      assert sync_iq.tag == "iq"
      assert attr(sync_iq, "xmlns") == "w:sync:app:state"
      assert attr(sync_iq, "type") == "set"

      sync = NodeUtils.get_binary_node_child(sync_iq, "sync")
      assert [collection] = sync.content
      assert attr(collection, "name") == "regular_high"
      assert attr(collection, "version") == "0"
      assert attr(collection, "return_snapshot") == "true"

      # The tracked reply continues in handle_tracked_iq(:app_state_sync) — an
      # empty result is applied without crashing or emitting spurious events.
      inject(ctx, with_id(Node.create("iq", %{"type" => "result"}, []), attr(sync_iq, "id")))
      refute_receive {:amarula, :chats_update, _}, 100
      assert Process.alive?(ctx.pid)
    end

    test "encrypt from the server with a low count: uploads fresh prekeys", ctx do
      node =
        Node.create("notification", %{"type" => "encrypt", "from" => @server, "id" => "N2"}, [
          Node.create("count", %{"value" => "7"}, nil)
        ])

      inject(ctx, node)

      _ack = recv_frame()

      upload = recv_frame()
      assert upload.tag == "iq"
      assert attr(upload, "xmlns") == "encrypt"
      assert attr(upload, "type") == "set"

      # The batch refills toward the initial pool (812 - 7), not a token top-up.
      list = NodeUtils.get_binary_node_child(upload, "list")
      assert length(list.content) == 805
      assert Enum.all?(list.content, &(&1.tag == "key"))
    end

    test "encrypt from the server with a healthy count: no upload", ctx do
      node =
        Node.create("notification", %{"type" => "encrypt", "from" => @server, "id" => "N3"}, [
          Node.create("count", %{"value" => "500"}, nil)
        ])

      inject(ctx, node)

      ack = recv_frame()
      assert ack.tag == "ack"
      refute_receive {:frame_out, _}, 150
    end

    test "devices: drops the cached device list so the next send re-USyncs", ctx do
      # Prime the device cache (the first send USyncs both users).
      _msg_id = complete_send(ctx, "prime the cache")

      # Sanity: a second send is a pure cache hit — the first frame is <message>.
      task = Task.async(fn -> Connection.send_text(ctx.pid, @jid, "cache hit") end)
      cached = recv_frame()
      assert cached.tag == "message"
      inject(ctx, Node.create("ack", %{"class" => "message", "id" => cached.attrs["id"]}, nil))
      assert {:ok, _} = Task.await(task, 2000)

      # A devices notification for the recipient invalidates their cached list.
      node =
        Node.create("notification", %{"type" => "devices", "from" => @jid, "id" => "N4"}, [
          Node.create("add", %{}, [Node.create("device", %{"jid" => @jid}, nil)])
        ])

      inject(ctx, node)
      _ack = recv_frame()

      # The next send must re-fetch devices: the first frame is a USync IQ again.
      _task = Task.async(fn -> Connection.send_text(ctx.pid, @jid, "after invalidate") end)
      frame = recv_frame()
      assert frame.tag == "iq"
      assert attr(frame, "xmlns") == "usync"
      assert @jid in usync_queried(frame)
    end

    test "w:gp2: emits a :group_update event with the parsed change", ctx do
      group = "120363000000000042@g.us"

      node =
        Node.create(
          "notification",
          %{"type" => "w:gp2", "from" => group, "participant" => @jid, "id" => "N5"},
          [Node.create("add", %{}, [Node.create("participant", %{"jid" => @jid}, nil)])]
        )

      inject(ctx, node)

      _ack = recv_frame()

      assert_receive {:amarula, :group_update, update}
      assert %Amarula.Address{kind: :group} = update.group
      assert update.group.user == "120363000000000042"

      assert {:participants, :add, [%{address: %Amarula.Address{user: "10000000001"}}]} =
               update.action
    end

    test "picture: emits a :contacts_update with img_url changed/removed", ctx do
      changed =
        Node.create("notification", %{"type" => "picture", "from" => @jid, "id" => "N6"}, [
          Node.create("set", %{}, nil)
        ])

      inject(ctx, changed)
      _ack = recv_frame()
      assert_receive {:amarula, :contacts_update, [%{id: id, img_url: "changed"}]}
      assert id == @jid

      removed =
        Node.create("notification", %{"type" => "picture", "from" => @jid, "id" => "N7"}, [])

      inject(ctx, removed)
      _ack = recv_frame()
      assert_receive {:amarula, :contacts_update, [%{img_url: "removed"}]}
    end

    test "account_sync blocklist: emits :blocklist_update items", ctx do
      node =
        Node.create(
          "notification",
          %{"type" => "account_sync", "from" => @server, "id" => "N8"},
          [
            Node.create("blocklist", %{}, [
              Node.create("item", %{"jid" => @jid, "action" => "block"}, nil)
            ])
          ]
        )

      inject(ctx, node)
      _ack = recv_frame()

      assert_receive {:amarula, :blocklist_update, [%{jid: jid, action: "block"}]}
      assert jid == @jid
    end

    test "account_sync disappearing_mode: persists the duration into creds", ctx do
      node =
        Node.create(
          "notification",
          %{"type" => "account_sync", "from" => @server, "id" => "N9"},
          [
            Node.create("disappearing_mode", %{"duration" => "604800"}, nil)
          ]
        )

      inject(ctx, node)
      _ack = recv_frame()

      creds = Connection.get_auth_creds(ctx.pid)
      assert creds.account_settings.default_disappearing_mode == "604800"
    end

    test "an unknown notification type is acked and dropped without crashing", ctx do
      node =
        Node.create("notification", %{"type" => "mystery", "from" => @server, "id" => "N10"}, [])

      inject(ctx, node)

      ack = recv_frame()
      assert ack.tag == "ack"
      assert attr(ack, "type") == "mystery"
      refute_receive {:frame_out, _}, 100
      assert Process.alive?(ctx.pid)
    end
  end

  # --- tracked-IQ login bootstrap (auth success → prekey count → open) ---

  describe "login bootstrap (tracked IQs)" do
    test "auth success with an empty server pool: upload, then finish_login + :open", ctx do
      inject(ctx, Node.create("success", %{"lid" => "20000000002@lid"}, nil))

      # 1. The prekey-count query goes out.
      count_iq = recv_frame()
      assert count_iq.tag == "iq"
      assert attr(count_iq, "xmlns") == "encrypt"
      assert attr(count_iq, "type") == "get"
      assert %Node{} = NodeUtils.get_binary_node_child(count_iq, "count")

      # The success node's lid was adopted into creds.
      assert Connection.get_auth_creds(ctx.pid).me.lid == "20000000002@lid"

      # 2. Server holds 0 → a full upload IQ goes out.
      inject(ctx, count_reply(attr(count_iq, "id"), 0))
      upload = recv_frame()
      assert attr(upload, "xmlns") == "encrypt"
      assert attr(upload, "type") == "set"
      assert length(NodeUtils.get_binary_node_child(upload, "list").content) == 812

      # 3. Upload confirmed → finish_login: passive active, unified session,
      # digest, init queries, presence — and the :open connection update.
      inject(ctx, with_id(Node.create("iq", %{"type" => "result"}, []), attr(upload, "id")))

      passive = recv_frame()
      assert attr(passive, "xmlns") == "passive"
      assert %Node{} = NodeUtils.get_binary_node_child(passive, "active")

      assert_receive {:amarula, :connection_update, %{connection: :open}}
    end

    test "auth success with a healthy pool skips the upload and opens directly", ctx do
      inject(ctx, Node.create("success", %{}, nil))

      count_iq = recv_frame()
      inject(ctx, count_reply(attr(count_iq, "id"), 500))

      # No upload IQ: the very next frame is finish_login's passive active.
      passive = recv_frame()
      assert passive.tag == "iq"
      assert attr(passive, "xmlns") == "passive"

      assert_receive {:amarula, :connection_update, %{connection: :open}}
    end

    test "a failed prekey-count query still finishes login (:open is not blocked)", ctx do
      inject(ctx, Node.create("success", %{}, nil))

      count_iq = recv_frame()
      inject(ctx, with_id(Node.create("iq", %{"type" => "error"}, []), attr(count_iq, "id")))

      passive = recv_frame()
      assert attr(passive, "xmlns") == "passive"
      assert_receive {:amarula, :connection_update, %{connection: :open}}
    end

    test "a digest reply without <digest> triggers a one-shot prekey re-upload", ctx do
      inject(ctx, Node.create("success", %{}, nil))
      count_iq = recv_frame()
      inject(ctx, count_reply(attr(count_iq, "id"), 500))

      # finish_login frames: passive, unified session <ib>, then the digest IQ.
      _passive = recv_frame()
      ib = recv_frame()
      assert ib.tag == "ib"
      digest_iq = recv_frame()
      assert digest_iq.tag == "iq"
      assert %Node{} = NodeUtils.get_binary_node_child(digest_iq, "digest")

      # Drain the three init queries + presence that finish_login also sent.
      for _ <- 1..4, do: recv_frame()

      # Reply WITHOUT a <digest> child → the server didn't validate our bundle →
      # a min-count re-upload goes out (and must NOT loop back into finish_login).
      inject(ctx, with_id(Node.create("iq", %{"type" => "result"}, []), attr(digest_iq, "id")))

      reupload = recv_frame()
      assert attr(reupload, "xmlns") == "encrypt"
      assert attr(reupload, "type") == "set"
      assert length(NodeUtils.get_binary_node_child(reupload, "list").content) == 5

      # Confirming the re-upload ends the sequence — no second digest, no loop.
      inject(ctx, with_id(Node.create("iq", %{"type" => "result"}, []), attr(reupload, "id")))
      refute_receive {:frame_out, _}, 150
    end
  end

  defp count_reply(id, count) do
    with_id(
      Node.create("iq", %{"type" => "result"}, [
        Node.create("count", %{"value" => Integer.to_string(count)}, nil)
      ]),
      id
    )
  end

  # --- offline batch (<ib> preview/complete) ---

  describe "offline batch" do
    test "an offline_preview is answered with an offline_batch request", ctx do
      inject(
        ctx,
        Node.create("ib", %{}, [Node.create("offline_preview", %{"count" => "5"}, nil)])
      )

      reply = recv_frame()
      assert reply.tag == "ib"
      batch = NodeUtils.get_binary_node_child(reply, "offline_batch")
      assert attr(batch, "count") == "100"
    end

    test "offline complete emits received_pending_notifications", ctx do
      inject(ctx, Node.create("ib", %{}, [Node.create("offline", %{"count" => "5"}, nil)]))

      assert_receive {:amarula, :connection_update, %{received_pending_notifications: true}}
      # Purely informational — nothing goes out.
      refute_receive {:frame_out, _}, 100
    end
  end

  # --- dirty flag ---

  describe "ib dirty" do
    test "clears the dirty bits with a clean IQ echoing type + timestamp", ctx do
      inject(
        ctx,
        Node.create("ib", %{}, [
          Node.create("dirty", %{"type" => "groups", "timestamp" => "1700000001"}, nil)
        ])
      )

      clean_iq = recv_frame()
      assert clean_iq.tag == "iq"
      assert attr(clean_iq, "xmlns") == "urn:xmpp:whatsapp:dirty"
      clean = NodeUtils.get_binary_node_child(clean_iq, "clean")
      assert attr(clean, "type") == "groups"
      assert attr(clean, "timestamp") == "1700000001"

      # A non-account_sync dirty type does NOT trigger an app-state resync.
      refute_receive {:frame_out, %Node{tag: "iq"}}, 100
    end

    test "an account_sync dirty flag also resyncs app state", ctx do
      inject(
        ctx,
        Node.create("ib", %{}, [Node.create("dirty", %{"type" => "account_sync"}, nil)])
      )

      clean_iq = recv_frame()
      assert attr(clean_iq, "xmlns") == "urn:xmpp:whatsapp:dirty"

      sync_iq = recv_frame()
      assert attr(sync_iq, "xmlns") == "w:sync:app:state"
      sync = NodeUtils.get_binary_node_child(sync_iq, "sync")
      # The full resync asks for all five collections.
      assert length(sync.content) == 5
    end
  end

  # --- presence / chatstate ---

  describe "inbound presence" do
    test "a <presence unavailable> emits :presence_update with last_seen", ctx do
      inject(
        ctx,
        Node.create("presence", %{"from" => @jid, "type" => "unavailable", "last" => "1700"}, nil)
      )

      assert_receive {:amarula, :presence_update, update}
      assert update.presence == :unavailable
      assert update.last_seen == 1700
      assert %Amarula.Address{user: "10000000001"} = update.jid
      # Unsolicited: no ack goes out for presence.
      refute_receive {:frame_out, _}, 100
    end

    test "a <chatstate composing> emits :presence_update :composing", ctx do
      inject(
        ctx,
        Node.create("chatstate", %{"from" => @jid}, [Node.create("composing", %{}, nil)])
      )

      assert_receive {:amarula, :presence_update, %{presence: :composing}}
    end

    test "a malformed chatstate (no child) is dropped without crashing", ctx do
      inject(ctx, Node.create("chatstate", %{"from" => @jid}, nil))
      refute_receive {:amarula, :presence_update, _}, 100
      assert Process.alive?(ctx.pid)
    end
  end

  # --- delivery/read receipts (non-retry) ---

  describe "inbound receipt" do
    test "a read receipt is acked and surfaced as :receipt_update", ctx do
      node =
        Node.create(
          "receipt",
          %{"from" => @jid, "id" => "3EB0AAAA", "type" => "read", "t" => "1700000002"},
          nil
        )

      inject(ctx, node)

      ack = recv_frame()
      assert ack.tag == "ack"
      assert attr(ack, "class") == "receipt"
      assert attr(ack, "id") == "3EB0AAAA"

      assert_receive {:amarula, :receipt_update, receipt}
      assert receipt.status == :read
      assert receipt.message_ids == ["3EB0AAAA"]
      assert %Amarula.Address{user: "10000000001"} = receipt.from
    end
  end

  # --- learn_own_push_name (PUSH_NAME history sync) ---

  describe "learning our own push name" do
    @describetag creds_opts: [name: "~"]

    test "adopts our real name from the sync, persists it, and re-sends presence", ctx do
      result = history_result(push_names: [{@me_jid, "Real Name"}])
      send(ctx.pid, {:history_sync_result, result})

      # The consumer sees the history sync itself.
      assert_receive {:amarula, :history_sync, ^result}

      # The learned name is persisted into creds…
      assert Connection.get_auth_creds(ctx.pid).me.name == "Real Name"

      # …and presence is refreshed with it (mark_online defaults to true).
      presence = recv_frame()
      assert presence.tag == "presence"
      assert attr(presence, "name") == "Real Name"
      assert attr(presence, "type") == "available"
    end

    test "someone else's push name does not overwrite ours", ctx do
      send(ctx.pid, {:history_sync_result, history_result(push_names: [{@jid, "Not Me"}])})
      assert_receive {:amarula, :history_sync, _}

      assert Connection.get_auth_creds(ctx.pid).me.name == "~"
      refute_receive {:frame_out, _}, 100
    end

    @tag creds_opts: [name: "Already Real"]
    test "a real (non-placeholder) name is never replaced", ctx do
      send(
        ctx.pid,
        {:history_sync_result, history_result(push_names: [{@me_jid, "Different"}])}
      )

      assert_receive {:amarula, :history_sync, _}
      assert Connection.get_auth_creds(ctx.pid).me.name == "Already Real"
      refute_receive {:frame_out, _}, 100
    end
  end

  defp history_result(opts) do
    %{
      sync_type: :PUSH_NAME,
      chats: [],
      contacts: [],
      push_names: Keyword.fetch!(opts, :push_names)
    }
  end

  describe "media retry (server-error receipt ↔ mediaretry notification)" do
    test "sends a server-error receipt, then resolves the caller with the refreshed path", ctx do
      media_key = :crypto.strong_rand_bytes(32)
      msg = media_msg(media_key)

      # retry_media/2 parks on a GenServer.call — drive it from a Task so the test
      # stays free to observe the receipt and inject the phone's reply.
      task = Task.async(fn -> Amarula.retry_media(ctx.pid, msg) end)

      receipt = recv_frame()
      assert receipt.tag == "receipt"
      assert attr(receipt, "type") == "server-error"
      # Addressed to our own (non-AD) user jid.
      assert attr(receipt, "to") == @me_jid

      rmr = NodeUtils.get_binary_node_child(receipt, "rmr")
      assert attr(rmr, "jid") == @jid
      assert attr(rmr, "from_me") == "false"
      # 1:1 chat → no participant on the <rmr>.
      assert attr(rmr, "participant") == nil

      inject(ctx, mediaretry_notification(msg.id, media_key, :SUCCESS, "/v/new/path"))

      assert {:ok, %Amarula.Content.Media{direct_path: "/v/new/path", media_key: ^media_key}} =
               Task.await(task)
    end

    test "surfaces <error code=2> as {:error, :not_on_phone}", ctx do
      media_key = :crypto.strong_rand_bytes(32)
      msg = media_msg(media_key)

      task = Task.async(fn -> Amarula.retry_media(ctx.pid, msg) end)
      _receipt = recv_frame()

      error_notif = %Node{
        tag: "notification",
        attrs: %{"id" => msg.id, "type" => "mediaretry", "from" => @jid},
        content: [%Node{tag: "error", attrs: %{"code" => "2"}, content: nil}]
      }

      inject(ctx, error_notif)
      assert {:error, :not_on_phone} = Task.await(task)
    end

    test "a non-media message is rejected in-process, never touching the socket", ctx do
      text = %Amarula.Msg{
        channel: Amarula.Address.pn("10000000001"),
        type: :text,
        content: "hi",
        raw: %Proto.Message{}
      }

      assert {:error, :not_media} = Amarula.retry_media(ctx.pid, text)
      refute_receive {:frame_out, _}, 100
    end
  end

  # A minimal 1:1 media %Msg{} to retry, keyed by `media_key`.
  defp media_msg(media_key) do
    %Amarula.Msg{
      id: "MEDIARETRY1",
      channel: Amarula.Address.pn("10000000001"),
      from: Amarula.Address.pn("10000000001"),
      to: Amarula.Address.pn("10000000002"),
      from_me: false,
      type: :media,
      content: %Amarula.Content.Media{
        kind: :image,
        media_key: media_key,
        direct_path: "/old/path"
      },
      raw: %Proto.Message{}
    }
  end

  # A <notification type="mediaretry"> carrying a GCM-encrypted MediaRetryNotification,
  # exactly as the phone answers our server-error receipt.
  defp mediaretry_notification(msg_id, media_key, result, direct_path) do
    iv = :crypto.strong_rand_bytes(12)

    payload =
      Proto.MediaRetryNotification.encode(%Proto.MediaRetryNotification{
        stanzaId: msg_id,
        result: result,
        directPath: direct_path
      })

    {:ok, enc_p} = Crypto.aes_encrypt_gcm(payload, Media.retry_key(media_key), iv, msg_id)

    %Node{
      tag: "notification",
      attrs: %{"id" => msg_id, "type" => "mediaretry", "from" => @jid},
      content: [
        %Node{
          tag: "encrypt",
          attrs: %{},
          content: [
            %Node{tag: "enc_p", attrs: %{}, content: enc_p},
            %Node{tag: "enc_iv", attrs: %{}, content: iv}
          ]
        }
      ]
    }
  end
end
