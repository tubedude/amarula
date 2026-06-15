defmodule Amarula.ConnectionTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Amarula.Protocol.Binary.{Decoder, Encoder, Node, NodeUtils}
  alias Amarula.Connection

  setup do
    # Create a test configuration
    config = %{
      wa_websocket_url: "wss://test.example.com/ws",
      connect_timeout_ms: 5000,
      keep_alive_interval_ms: 30000,
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
    test "emits {:whatsapp, type, data} straight to the parent_pid", %{config: config} do
      # No internal subscriber registry anymore — Connection sends consumer events
      # directly to the parent_pid it was started with. Injecting a stream-end
      # close drives an emit through the same path the consumer sees.
      {:ok, pid} = Connection.start_link(config, parent_pid: self())

      send(pid, {:ws_event, nil, {:close, :test}})

      assert_receive {:whatsapp, :connection_update, %{connection: :disconnected}}
      GenServer.stop(pid)
    end
  end
end
