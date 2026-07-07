defmodule Amarula.ConnectionTest do
  # async: false — starts real connections on the shared, app-global
  # ConnectionsSupervisor + ProfileRegistry. Running these concurrently with
  # other real-connection tests (notably the crash-isolation suite) perturbs that
  # shared OTP state and causes a rare cross-test flake. Serialize them.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Amarula.Protocol.Binary.{Decoder, Encoder, Node, NodeUtils}
  alias Amarula.Protocol.Socket.Router
  alias Amarula.Connection

  setup do
    # Create a test configuration
    config = %{
      wa_websocket_url: "wss://test.example.com/ws",
      connect_timeout_ms: 5000,
      keep_alive_interval_ms: 30_000,
      max_retries: 3,
      retry_delay: 1000,
      headers: %{"User-Agent" => "TestClient"},
      origin: "https://test.example.com",
      agent: nil
    }

    {:ok, config: config}
  end

  describe "decompress_frame/1" do
    test "strips the prefix of an uncompressed (0x00) frame" do
      {:ok, encoded} = Encoder.encode(%Node{tag: "ack", attrs: %{"id" => "1"}, content: nil})
      framed = <<0>> <> encoded

      decoded = framed |> Connection.decompress_frame() |> Decoder.decode()
      assert decoded.tag == "ack"
      assert NodeUtils.get_attr(decoded, "id") == "1"
    end

    test "inflates a zlib-compressed (0x02) frame" do
      {:ok, encoded} = Encoder.encode(%Node{tag: "receipt", attrs: %{"id" => "9"}, content: nil})
      framed = <<2>> <> :zlib.compress(encoded)

      decoded = framed |> Connection.decompress_frame() |> Decoder.decode()
      assert decoded.tag == "receipt"
      assert NodeUtils.get_attr(decoded, "id") == "9"
    end
  end

  describe "mark_online?/1 (markOnlineOnConnect — Baileys #2553)" do
    test "defaults to true when unset (connect sends presence-available)" do
      assert Connection.mark_online?(%{})
    end

    test "honors an explicit per-connection false" do
      refute Connection.mark_online?(%{mark_online_on_connect: false})
    end

    test "honors an explicit true" do
      assert Connection.mark_online?(%{mark_online_on_connect: true})
    end
  end

  describe "connection manager lifecycle" do
    test "starts and initializes correctly" do
      # Use a tmp-rooted profile so the connection never touches the repo's data
      # dir (Amarula owns credential persistence; init reads from this scope).
      root =
        Path.join(System.tmp_dir!(), "amarula_cm_init_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf(root) end)
      conn = Amarula.new(%{profile: :init_test, storage: {Amarula.Storage.File, root: root}})

      {:ok, pid} = Connection.start_link(conn)

      # Test initial state
      assert Connection.get_connection_state(pid) == :disconnected

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "one connection per profile (profile registry)" do
    setup do
      root =
        Path.join(System.tmp_dir!(), "amarula_reg_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf(root) end)
      profile = :"reg_#{System.unique_integer([:positive])}"
      conn = Amarula.new(%{profile: profile, storage: {Amarula.Storage.File, root: root}})
      {:ok, conn: conn, profile: profile}
    end

    # Start a full connection tree and stop it (the supervisor) on exit — stopping
    # the Connection child alone would just be restarted by its :one_for_one parent.
    # `start_instance` uses Supervisor.start_link, so the tree is LINKED to the
    # test process and dies automatically when the test ends — no on_exit cleanup
    # needed (and stopping a linked, already-terminating supervisor from on_exit
    # races teardown). Tests that need an explicit shutdown call Supervisor.stop/1.
    defp start_tree(conn) do
      {:ok, sup, pid} = Amarula.Protocol.Socket.ConnectionSupervisor.start_instance(conn)
      {sup, pid}
    end

    test "make_socket registers the profile; whereis resolves it", %{conn: conn, profile: profile} do
      assert Amarula.whereis(profile) == nil
      {_sup, pid} = start_tree(conn)
      assert Amarula.whereis(profile) == pid
    end

    test "a second start for a live profile is {:error, {:already_running, pid}}",
         %{conn: conn} do
      {_sup, pid} = start_tree(conn)
      assert {:error, {:already_running, ^pid}} = Connection.make_socket(conn)
    end

    test "tree shutdown unregisters the profile (whereis -> nil)",
         %{conn: conn, profile: profile} do
      {sup, _pid} = start_tree(conn)
      assert is_pid(Amarula.whereis(profile))

      Supervisor.stop(sup)
      # Registry unregisters on the registered pid's death; give it a beat.
      Process.sleep(20)
      assert Amarula.whereis(profile) == nil
    end

    test "a restart re-registers the profile (handle stays resolvable)",
         %{conn: conn, profile: profile} do
      {_sup, pid} = start_tree(conn)
      assert Amarula.whereis(profile) == pid

      # Kill the Connection child; its :one_for_one supervisor restarts it, and
      # init re-registers the same profile → whereis resolves to the NEW pid.
      Process.exit(pid, :kill)

      new_pid =
        Enum.find_value(1..50, fn _ ->
          case Amarula.whereis(profile) do
            ^pid -> nil
            other when is_pid(other) -> other
            nil -> nil
          end || (Process.sleep(10) && nil)
        end)

      assert is_pid(new_pid) and new_pid != pid
    end

    test "stop/1 by pid takes the tree down and frees the profile",
         %{conn: conn, profile: profile} do
      {sup, pid} = start_tree(conn)
      ref = Process.monitor(sup)

      assert :ok = Amarula.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^sup, _}, 1000
      Process.sleep(20)
      assert Amarula.whereis(profile) == nil
    end

    test "stop/1 by profile resolves then stops", %{conn: conn, profile: profile} do
      {sup, _pid} = start_tree(conn)
      ref = Process.monitor(sup)

      assert :ok = Amarula.stop(profile)
      assert_receive {:DOWN, ^ref, :process, ^sup, _}, 1000
      Process.sleep(20)
      assert Amarula.whereis(profile) == nil
    end

    test "stop/1 on an unknown profile is {:error, :not_found}" do
      assert {:error, :not_found} = Amarula.stop(:"never_started_#{System.unique_integer()}")
    end

    test "a custom :registry module from config is honored", %{conn: base_conn} do
      # A distinct local Registry instance proves the seam routes through config,
      # not the default ProfileRegistry.
      name = :"custom_reg_#{System.unique_integer([:positive])}"
      start_supervised!({Registry, keys: :unique, name: name})

      conn = %{base_conn | config: Map.put(base_conn.config, :registry, name)}
      {_sup, pid} = start_tree(conn)

      # Registered in the custom registry, not the default one.
      assert [{^pid, _}] = Registry.lookup(name, conn.profile)
      assert Amarula.whereis(conn.profile) == nil
    end
  end

  describe "credential persistence (Amarula owns it)" do
    alias Amarula.Storage

    setup do
      root =
        Path.join(System.tmp_dir!(), "amarula_cm_creds_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf(root) end)
      # Amarula.new merges protocol defaults (max_retries, etc.) into the Conn.
      conn = Amarula.new(%{profile: :creds_test, storage: {Storage.File, root: root}})
      {:ok, conn: conn, root: root}
    end

    test "loads stored creds for the profile on init", %{conn: conn} do
      creds = %{registration_id: 4242, me: %{id: "x@s.whatsapp.net"}}
      :ok = Storage.put(conn.storage, conn.profile, :creds, :self, creds)

      {:ok, pid} = Connection.start_link(conn)
      assert Connection.get_auth_creds(pid) == creds
      GenServer.stop(pid)
    end

    test "generates fresh creds when none are stored", %{conn: conn} do
      {:ok, pid} = Connection.start_link(conn)
      creds = Connection.get_auth_creds(pid)
      # init_auth_creds always sets a registration_id; nothing was stored.
      assert is_map(creds) and Map.has_key?(creds, :registration_id)
      GenServer.stop(pid)
    end

    test "persists creds to storage when they change", %{conn: conn} do
      {:ok, pid} = Connection.start_link(conn)
      new_creds = %{registration_id: 99, me: %{id: "y@s.whatsapp.net"}}
      :ok = Connection.update_auth_creds(pid, new_creds)

      # Written through to storage — a fresh read sees it (no consumer involved).
      assert {:ok, ^new_creds} = Storage.get(conn.storage, conn.profile, :creds, :self)
      GenServer.stop(pid)
    end

    test "explicit config[:auth] overrides stored creds", %{conn: conn} do
      stored = %{registration_id: 1}
      :ok = Storage.put(conn.storage, conn.profile, :creds, :self, stored)
      override = %{registration_id: 2, source: :config}

      {:ok, pid} =
        Connection.start_link(%{conn | config: Map.put(conn.config, :auth, override)})

      assert Connection.get_auth_creds(pid) == override
      GenServer.stop(pid)
    end
  end

  describe "lifecycle" do
    test "disconnect on a freshly-started (disconnected) manager is a :ok no-op",
         %{config: config} do
      {:ok, pid} = Connection.start_link(config)
      assert Connection.disconnect(pid) == :ok
      assert Connection.get_connection_state(pid) == :disconnected
      GenServer.stop(pid)
    end
  end

  describe "consumer event delivery (direct to parent_pid)" do
    test "emits {:amarula, type, data} straight to the parent_pid", %{config: config} do
      # No internal subscriber registry anymore — Connection sends consumer events
      # directly to the parent_pid it was started with. Injecting a stream-end
      # close drives an emit through the same path the consumer sees.
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      send(pid, {:ws_event, nil, {:close, :test}})

      assert_receive {:amarula, :connection_update, %{connection: :disconnected}}
      GenServer.stop(pid)
    end

    test "emits :lid_mapping_update with Address pairs (#2263)", %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      Connection.notify_lid_mappings(pid, [{"111@lid", "15550001234@s.whatsapp.net"}])

      assert_receive {:amarula, :lid_mapping_update, [%{lid: lid, pn: pn}]}
      assert %Amarula.Address{kind: :lid, user: "111"} = lid
      assert %Amarula.Address{kind: :pn, user: "15550001234"} = pn
      GenServer.stop(pid)
    end

    test "notify_lid_mappings with [] emits nothing", %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      Connection.notify_lid_mappings(pid, [])

      refute_receive {:amarula, :lid_mapping_update, _}
      GenServer.stop(pid)
    end
  end

  describe "sending while disconnected (no crash, tagged error)" do
    # A fresh Connection has noise_state: nil and websocket_client: nil (handshake
    # not done) — exactly the window where a send used to crash the GenServer:
    # encode_frame(nil, _) → BadMapError, or send_data(nil, _) → :noproc. Every
    # send path must instead return {:error, :not_connected} and stay alive.

    test "mark_read returns {:error, :not_connected} and does not crash", %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      assert {:error, :not_connected} =
               Connection.mark_read(pid, "5511999998888@s.whatsapp.net", ["M1"])

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "relay_stanza returns {:error, :not_connected} and does not crash", %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())
      node = %Node{tag: "ping", attrs: %{"id" => "x"}, content: nil}

      assert {:error, :not_connected} = Connection.relay_stanza(pid, node)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "a query_iq fails fast instead of parking the caller", %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())
      node = %Node{tag: "iq", attrs: %{"type" => "get"}, content: nil}

      assert {:error, :not_connected} = Connection.query_iq(pid, node)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "a waiter IQ (list_groups) fails fast instead of parking", %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      assert {:error, :not_connected} = Connection.list_groups(pid)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "auto-reconnect when the websocket dies" do
    test "killing the websocket does not kill Connection and drives a reconnect",
         %{config: config} do
      # The WebSockex client used to be LINKED to Connection (start_link): a server
      # close (WebSockex exits {:remote, :closed}, non-normal) signal-killed
      # Connection before it could reconnect, and the restarted process never
      # reconnected — stuck :disconnected. We now unlink + monitor it. A brutal
      # :kill propagates through a link regardless of trap_exit, so Connection
      # surviving this proves the link is gone; the :DOWN then drives the reconnect.
      {:ok, pid} = Connection.start_link(config, parent_pid: self())
      :ok = GenServer.call(pid, :connect)

      ws = :sys.get_state(pid).websocket_client
      assert is_pid(ws) and Process.alive?(ws)

      Process.exit(ws, :kill)

      assert_receive {:amarula, :connection_update, %{connection: :disconnected}}, 1000
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "reconnect is in-process (the invariant Amarula.SupervisedConnection relies on)" do
    # `Amarula.SupervisedConnection` monitors the Connection pid and treats a `:DOWN`
    # as true death, re-adopting the rest_for_one-restarted pid. That is only correct
    # because a *routine* reconnect — the server-mandated 515 stream-restart after
    # pairing, or any socket drop — is handled IN-PROCESS (`restart_connection/1` →
    # `attempt_connection/1`), keeping the SAME Connection pid and profile
    # registration. These two tests guard that invariant. (Driving a real 515
    # end-to-end needs a completed Noise handshake, since post-handshake frames are
    # encrypted — so we assert the 515 *routing* here, and the pid stability via the
    # shared reconnect path a socket drop takes.)

    test "a 515 stream:error routes to the stream-error handler (in-process restart), not a crash path" do
      node = %Node{
        tag: "stream:error",
        attrs: %{"code" => "515"},
        content: [%Node{tag: "xml-not-well-formed", attrs: %{}, content: nil}]
      }

      assert Router.route(node) == :stream_error
    end

    test "a reconnect keeps the same Connection pid and swaps the websocket", %{config: config} do
      # A local listener that accepts TCP but never answers the WS upgrade: the
      # replacement WebSockex stays alive mid-handshake, so the swap is observable.
      # (The default wss://test.example.com resolves differently across CI runners —
      # an instant :nxdomain kills each new socket before the poll can see it.)
      {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
      {:ok, port} = :inet.port(listen)
      on_exit(fn -> :gen_tcp.close(listen) end)

      config = %{config | wa_websocket_url: "ws://127.0.0.1:#{port}/ws", retry_delay: 50}
      {:ok, pid} = Connection.start_link(config, parent_pid: self())
      :ok = GenServer.call(pid, :connect)

      ws1 = :sys.get_state(pid).websocket_client
      assert is_pid(ws1)

      # Kill the socket → drives the same in-process reconnect a 515 restart takes.
      Process.exit(ws1, :kill)
      assert_receive {:amarula, :connection_update, %{connection: :disconnected}}, 1000

      # The Connection GenServer is the SAME process; only its websocket is replaced.
      ws2 = wait_for_new_ws(pid, ws1, 60)
      assert is_pid(ws2) and ws2 != ws1
      assert Process.alive?(pid)

      # Brutal-kill teardown: ws2 is a live WebSockex mid-connect to the fake URL,
      # and a graceful stop would run terminate → :close on it and error out. Unlink
      # first so the kill doesn't reach the test process.
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end

    defp wait_for_new_ws(_pid, _old, 0), do: nil

    defp wait_for_new_ws(pid, old, tries) do
      case :sys.get_state(pid).websocket_client do
        ws when is_pid(ws) and ws != old ->
          ws

        _ ->
          Process.sleep(25)
          wait_for_new_ws(pid, old, tries - 1)
      end
    end
  end

  describe "down-transition on a connection error" do
    test "a ws error emits :connection_update :disconnected, not just :error", %{config: config} do
      # The error paths used to emit only :error, never the :connection_update the
      # clean-close path emits — so a consumer tracking connection state never saw
      # the drop and its UI went stale on the last "open". Every handled error must
      # announce the down-transition.
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      send(pid, {:ws_event, nil, {:error, :econnreset}})

      assert_receive {:amarula, :error, :econnreset}
      assert_receive {:amarula, :connection_update, %{connection: :disconnected}}
      GenServer.stop(pid)
    end
  end

  describe "re-attaching the event sink (set_parent/2 + sink monitor)" do
    # A process that forwards everything it receives to `dest`, tagged — lets a
    # test prove WHICH sink an event reached.
    defp forwarder(dest) do
      spawn(fn -> forward_loop(dest) end)
    end

    defp forward_loop(dest) do
      receive do
        msg ->
          send(dest, {:forwarded, msg})
          forward_loop(dest)
      end
    end

    # Drive one consumer emit through the same path the consumer sees.
    defp drive_emit(pid), do: send(pid, {:ws_event, nil, {:close, :test}})

    test "set_parent re-points the sink without bouncing the connection", %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())
      relay = forwarder(self())

      assert :ok = Connection.set_parent(pid, relay)
      drive_emit(pid)

      assert_receive {:forwarded, {:amarula, :connection_update, %{connection: :disconnected}}}
      # The original sink (self) no longer receives.
      refute_receive {:amarula, :connection_update, _}, 50
      GenServer.stop(pid)
    end

    test "a name-based sink re-resolves to the consumer's new pid (no set_parent needed)",
         %{config: config} do
      name = :"sink_name_#{System.unique_integer([:positive])}"
      Process.register(self(), name)

      {:ok, pid} = Connection.start_link(config, parent_pid: name)
      drive_emit(pid)
      assert_receive {:amarula, :connection_update, %{connection: :disconnected}}

      # Simulate the consumer restarting: a NEW process takes over the name. The
      # connection wasn't touched, yet the next event lands on the new holder.
      Process.unregister(name)
      relay = forwarder(self())
      Process.register(relay, name)

      drive_emit(pid)
      assert_receive {:forwarded, {:amarula, :connection_update, %{connection: :disconnected}}}

      GenServer.stop(pid)
    end

    test "a dead pid sink emits [:amarula, :sink, :down] telemetry and is cleared",
         %{config: config} do
      test = self()
      handler = "sink-down-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:amarula, :sink, :down],
        fn _e, meas, meta, _ -> send(test, {:sink_down, meas, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      sink = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, pid} = Connection.start_link(config, parent_pid: sink)

      Process.exit(sink, :kill)

      assert_receive {:sink_down, %{count: 1}, %{sink: ^sink, reason: :killed}}
      # The raw-pid sink is cleared, so the connection now has no sink (not a corpse).
      assert :sys.get_state(pid).parent_pid == nil
      GenServer.stop(pid)
    end

    test "an unheld name sink is delivered-to AND its monitor self-heals on keep-alive",
         %{config: config} do
      name = :"sink_unheld_#{System.unique_integer([:positive])}"
      # Attach a name nobody holds yet: no monitor is armed at attach time.
      {:ok, pid} = Connection.start_link(config, parent_pid: name)
      assert :sys.get_state(pid).parent_monitor == nil

      # Consumer appears and claims the name. Per-event resolution already delivers
      # to it (no set_parent needed)...
      relay = forwarder(self())
      Process.register(relay, name)
      drive_emit(pid)
      assert_receive {:forwarded, {:amarula, :connection_update, %{connection: :disconnected}}}

      # ...and the monitor self-heals off the heartbeat, so a later death is observable.
      send(pid, :send_keep_alive)
      assert :sys.get_state(pid).parent_monitor != nil

      GenServer.stop(pid)
    end
  end

  describe "build_msg/6 — real recipient on own (fan-out) messages" do
    alias Amarula.{Address, Msg}
    alias Amarula.Protocol.Proto

    # Minimal state: build_msg only reads me(state) (creds.me.id) for own_account?.
    @me_pn "5511999999999@s.whatsapp.net"
    @other "5511888888888@s.whatsapp.net"
    @state %{auth_creds: %{me: %{id: @me_pn}}}
    @own Address.parse(@me_pn)

    defp msg_node(attrs), do: %Node{tag: "message", attrs: attrs, content: nil}

    test "a from_me message to another contact carries that contact as channel + to" do
      # WhatsApp fans our send out as a from_me stanza whose `from` is our own
      # account; the real peer is the `recipient` attr.
      node = msg_node(%{"from" => @me_pn, "recipient" => @other, "id" => "M1"})

      msg =
        Connection.build_msg(@state, %Proto.Message{conversation: "hi"}, node, @me_pn, "M1", @own)

      assert msg.from_me
      assert %Address{user: "5511888888888"} = msg.to
      assert %Address{user: "5511888888888"} = msg.channel
    end

    test "a from_me message to self keeps self as to (to == own account)" do
      node = msg_node(%{"from" => @me_pn, "recipient" => @me_pn, "id" => "M2"})

      msg =
        Connection.build_msg(
          @state,
          %Proto.Message{conversation: "note"},
          node,
          @me_pn,
          "M2",
          @own
        )

      assert msg.from_me
      assert Address.same_account?(msg.to, @own)
    end

    test "an inbound (not from_me) message keeps the passed-in to_addr and stanza from" do
      node = msg_node(%{"from" => @other, "id" => "M3"})

      msg =
        Connection.build_msg(@state, %Proto.Message{conversation: "yo"}, node, @other, "M3", @own)

      refute msg.from_me
      assert Address.same_account?(msg.to, @own)
      assert %Address{user: "5511888888888"} = msg.channel
    end

    test "a from_me message with no recipient attr falls back to to_addr (peer-routed self stanza)" do
      node = msg_node(%{"from" => @me_pn, "id" => "M4"})

      msg =
        Connection.build_msg(@state, %Proto.Message{conversation: "x"}, node, @me_pn, "M4", @own)

      assert msg.from_me
      assert Address.same_account?(msg.to, @own)
    end

    test "a group from_me message keeps the group as channel (recipient override is DM-only)" do
      group = "123456789@g.us"
      # group stanza: from = group, participant = us; even a stray recipient must not win.
      node =
        msg_node(%{"from" => group, "participant" => @me_pn, "recipient" => @other, "id" => "M5"})

      msg =
        Connection.build_msg(@state, %Proto.Message{conversation: "g"}, node, group, "M5", @own)

      assert msg.from_me
      assert %Address{kind: :group} = msg.channel
      assert match?(%Msg{}, msg)
    end

    test "an unparseable sender (decrypt-failure path) does not crash; carries nils" do
      # On the Signal-desync path (e.g. \"Key used already\") `from` may not parse to an
      # Address. build_msg must NOT raise (a crash here loop-crashes the connection) —
      # it builds a %Msg{} with nil channel/from and falls back to to_addr.
      bad = "x@unknown-server"
      node = msg_node(%{"from" => bad, "id" => "M6"})

      msg = Connection.build_msg(@state, %Proto.Message{conversation: "?"}, node, bad, "M6", @own)

      assert match?(%Msg{}, msg)
      refute msg.from_me
      assert is_nil(msg.channel)
      assert Address.same_account?(msg.to, @own)
    end
  end

  describe "own_sender?/3 — gate for self-only protocolMessage types (CVE-2026-48063)" do
    alias Amarula.Address

    # app-state-sync-key-share and history-sync-notification are only ever
    # legitimate from our own linked device; own_sender? is what
    # handle_message/2 gates them on before acting on the payload.
    @me_pn "5511999999999@s.whatsapp.net"
    @me_lid "147451226890315@lid"
    @other "5511888888888@s.whatsapp.net"
    @state %{auth_creds: %{me: %{id: @me_pn, lid: @me_lid}}}

    defp own_sender_node(attrs), do: %Node{tag: "message", attrs: attrs, content: nil}

    test "a stanza from our own account is our own sender" do
      node = own_sender_node(%{"from" => @me_pn})
      assert Connection.own_sender?(@state, node, @me_pn)
    end

    test "a stanza from another contact is not our own sender (the spoof case)" do
      node = own_sender_node(%{"from" => @other})
      refute Connection.own_sender?(@state, node, @other)
    end

    test "our LID counts as our own account too" do
      node = own_sender_node(%{"from" => @me_lid})
      assert Connection.own_sender?(@state, node, @me_lid)
    end

    test "a group stanza uses participant, not the group jid, as the sender" do
      group = "123456789@g.us"
      node = own_sender_node(%{"from" => group, "participant" => @me_pn})
      assert Connection.own_sender?(@state, node, group)

      node = own_sender_node(%{"from" => group, "participant" => @other})
      refute Connection.own_sender?(@state, node, group)
    end

    test "an unparseable sender is not our own sender, and does not crash" do
      bad = "x@unknown-server"
      node = own_sender_node(%{"from" => bad})
      refute Connection.own_sender?(@state, node, bad)
    end
  end

  describe "duplicate_decrypt_error?/1 — consumed-key duplicate detection (ack 487, not 500+retry)" do
    test "matches the unwrapped pkmsg/whisper texts" do
      assert Connection.duplicate_decrypt_error?([%RuntimeError{message: "Invalid PreKey ID"}])
      assert Connection.duplicate_decrypt_error?(["Key used already or never filled"])
    end

    test "matches the WRAPPED msg-path error (consumed-key DecryptError inside 'No matching sessions')" do
      # The 1:1 `msg` path runs a multi-session trial decrypt that wraps the
      # per-session DecryptError; the consumed-key text is a substring, not the
      # whole message. This is the redelivery-after-lost-ack case that used to
      # nack 500 + retry instead of ack 487.
      wrapped = %RuntimeError{
        message:
          ~s(No matching sessions found for message: [%DecryptError{message: "Key used already or never filled"}])
      }

      assert Connection.duplicate_decrypt_error?([wrapped])
    end

    test "does NOT match a genuine decrypt failure (still retries)" do
      refute Connection.duplicate_decrypt_error?([%RuntimeError{message: "Bad MAC"}])

      refute Connection.duplicate_decrypt_error?([
               %RuntimeError{
                 message:
                   ~s(No matching sessions found for message: [%DecryptError{message: "Bad MAC"}])
               }
             ])

      refute Connection.duplicate_decrypt_error?([:no_session, :no_content])
    end
  end

  describe "own_chat?/2 — the self-chat command channel (LID/PN agnostic)" do
    alias Amarula.{Address, Msg, Storage}
    alias Amarula.Protocol.Proto

    @me_pn "5511999999999@s.whatsapp.net"
    @me_lid "147451226890315@lid"
    @other "5511888888888@s.whatsapp.net"

    # A %Msg{} addressed `to` `jid`, optionally from_me.
    defp msg_to(jid, from_me?) do
      %Msg{
        channel: Address.parse(jid),
        to: Address.parse(jid),
        from_me: from_me?,
        type: :text,
        content: "x",
        raw: %Proto.Message{conversation: "x"}
      }
    end

    setup do
      root = Path.join(System.tmp_dir!(), "amarula_ownchat_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf(root) end)
      conn = Amarula.new(%{profile: :own_chat_test, storage: {Storage.File, root: root}})
      # Logged-in creds carry BOTH our PN (always) and our LID (best-effort).
      creds = %{registration_id: 7, me: %{id: @me_pn, lid: @me_lid, name: "~"}}
      :ok = Storage.put(conn.storage, conn.profile, :creds, :self, creds)
      {:ok, pid} = Connection.start_link(conn)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, pid: pid}
    end

    test "true for a from_me message addressed to our PN", %{pid: pid} do
      assert Connection.own_chat?(pid, msg_to(@me_pn, true))
    end

    test "true for a from_me message addressed to our LID (the duality case)", %{pid: pid} do
      assert Connection.own_chat?(pid, msg_to(@me_lid, true))
    end

    test "false for a from_me message to someone else", %{pid: pid} do
      refute Connection.own_chat?(pid, msg_to(@other, true))
    end

    test "false for an inbound (not from_me) message to ourselves", %{pid: pid} do
      refute Connection.own_chat?(pid, msg_to(@me_pn, false))
    end
  end

  describe "retry give-up (max_retries exhausted → :closed, no more reconnects)" do
    test "repeated closes drive the count to the limit, then :closed, then stop reconnecting",
         %{config: config} do
      # retry_count now increments on the websocket {:close, _} path (not just the
      # error path) and is reset only in finish_login. With a tiny max_retries and a
      # long retry_delay — so the scheduled :reconnect never fires during the test —
      # repeated closes reach the limit and flip the connection to :closed.
      config = %{config | max_retries: 2, retry_delay: 60_000}
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      # websocket_client is nil on a fresh start, so {:ws_event, nil, {:close, _}}
      # is NOT treated as stale (nil == current) and counts toward give-up.
      # Close 1: retry_count 0 -> 1 (< 2) → :disconnected + a (far-future) reconnect.
      send(pid, {:ws_event, nil, {:close, :test}})
      assert_receive {:amarula, :connection_update, %{connection: :disconnected}}

      # Close 2: retry_count 1 -> 2 (not < 2) → give up → :closed.
      send(pid, {:ws_event, nil, {:close, :test}})
      assert_receive {:amarula, :connection_update, %{connection: :closed}}

      # It stays closed and attempts no further reconnect — a reconnect would run
      # attempt_connection and emit :connecting. The only scheduled retry timer is
      # 60s+ out, so nothing fires in the test window.
      assert :sys.get_state(pid).connection_state == :closed
      refute_receive {:amarula, :connection_update, %{connection: :connecting}}, 100

      GenServer.stop(pid)
    end
  end

  describe "restart drains pending IQ waiters (fail_pending_iqs → {:error, :not_connected})" do
    test "a parked query_iq caller is failed fast on a 515 restart", %{config: config} do
      # A configured frame_sink makes the send path 'ready', so query_iq parks the
      # caller in pending_iqs (holding its `from`) exactly as in production. The
      # outbound IQ is captured as {:frame_out, _}: receiving it proves the waiter is
      # parked (same-mailbox ordering) BEFORE we trigger the restart.
      config = Map.merge(config, %{frame_sink: self(), connection_state: :connected})
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      node = %Node{tag: "iq", attrs: %{"type" => "get"}, content: nil}
      task = Task.async(fn -> Connection.query_iq(pid, node) end)

      # The parked query stamped + emitted its IQ frame → the waiter is registered.
      assert_receive {:frame_out, %Node{tag: "iq"}}, 1000

      # A 515 stream:error drives restart_connection/1, which now calls
      # fail_pending_iqs and replies every parked waiter {:error, :not_connected}
      # before tearing down + reconnecting — so the caller unblocks promptly instead
      # of hanging to its call timeout.
      send(
        pid,
        {:inject_node, %Node{tag: "stream:error", attrs: %{"code" => "515"}, content: nil}}
      )

      assert {:error, :not_connected} = Task.await(task, 1000)

      # The 515 restart also kicks off a reconnect to the (unreachable) test URL,
      # leaving a half-open WebSockex client. Trap exits so tearing the (linked)
      # Connection down — its terminate/2 does a synchronous close on that doomed
      # client — can't take the test process with it; then kill the orphaned client
      # (Connection is already gone, so its monitor won't respawn one).
      ws = :sys.get_state(pid).websocket_client
      Process.flag(:trap_exit, true)

      try do
        GenServer.stop(pid, :shutdown, 1000)
      catch
        :exit, _ -> :ok
      end

      if is_pid(ws) and Process.alive?(ws), do: Process.exit(ws, :kill)
    end
  end

  describe "catch-all handlers (an unexpected message must not crash the tree)" do
    test "an unknown info message is ignored and the process stays alive", %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      send(pid, :garbage_message)

      # A round-trip call proves the process processed past the garbage and lives.
      assert Connection.get_connection_state(pid) == :disconnected
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "an unknown call returns {:error, :unknown_request} without crashing",
         %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      assert {:error, :unknown_request} = GenServer.call(pid, :nonsense)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "send_media prep failure (the Task rescue path replies the caller)" do
    test "a raise during media prep replies {:error, {:media_prepare_failed, _}}",
         %{config: config} do
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      # Drive the raw {:send_media, ...} call directly — bypassing the public
      # send_media/5 guard, which only admits binary data — with non-binary data, so
      # Media.encrypt/2 (guarded is_binary) raises with no matching clause inside the
      # prep Task. The Task's try/rescue must convert that raise into a reply to the
      # caller; otherwise the caller would hang for the full 90s send-call timeout.
      assert {:error, {:media_prepare_failed, _}} =
               GenServer.call(
                 pid,
                 {:send_media, "5511999998888@s.whatsapp.net", :image, :not_binary, []},
                 5000
               )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
end
