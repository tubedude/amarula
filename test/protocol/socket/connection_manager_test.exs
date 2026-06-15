defmodule Amarula.Protocol.Socket.ConnectionManagerTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Amarula.Protocol.Binary.{Decoder, Encoder, Node, NodeUtils}
  alias Amarula.Protocol.Socket.ConnectionManager

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

      decoded = framed |> ConnectionManager.decompress_frame() |> Decoder.decode()
      assert decoded.tag == "ack"
      assert NodeUtils.get_attr(decoded, "id") == "1"
    end

    test "inflates a zlib-compressed (0x02) frame" do
      {:ok, encoded} = Encoder.encode(%Node{tag: "receipt", attrs: %{"id" => "9"}, content: nil})
      framed = <<2>> <> :zlib.compress(encoded)

      decoded = framed |> ConnectionManager.decompress_frame() |> Decoder.decode()
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

      {:ok, pid} = ConnectionManager.start_link(conn)

      # Test initial state
      assert ConnectionManager.get_connection_state(pid) == :disconnected

      # Clean up
      GenServer.stop(pid)
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

      {:ok, pid} = ConnectionManager.start_link(conn)
      assert ConnectionManager.get_auth_creds(pid) == creds
      GenServer.stop(pid)
    end

    test "generates fresh creds when none are stored", %{conn: conn} do
      {:ok, pid} = ConnectionManager.start_link(conn)
      creds = ConnectionManager.get_auth_creds(pid)
      # init_auth_creds always sets a registration_id; nothing was stored.
      assert is_map(creds) and Map.has_key?(creds, :registration_id)
      GenServer.stop(pid)
    end

    test "persists creds to storage when they change", %{conn: conn} do
      {:ok, pid} = ConnectionManager.start_link(conn)
      new_creds = %{registration_id: 99, me: %{id: "y@s.whatsapp.net"}}
      :ok = ConnectionManager.update_auth_creds(pid, new_creds)

      # Written through to storage — a fresh read sees it (no consumer involved).
      assert {:ok, ^new_creds} = Storage.get(conn.storage, conn.profile, :creds, :self)
      GenServer.stop(pid)
    end

    test "explicit config[:auth] overrides stored creds", %{conn: conn} do
      stored = %{registration_id: 1}
      :ok = Storage.put(conn.storage, conn.profile, :creds, :self, stored)
      override = %{registration_id: 2, source: :config}

      {:ok, pid} =
        ConnectionManager.start_link(%{conn | config: Map.put(conn.config, :auth, override)})

      assert ConnectionManager.get_auth_creds(pid) == override
      GenServer.stop(pid)
    end
  end

  describe "lifecycle + subscription" do
    test "disconnect on a freshly-started (disconnected) manager is a :ok no-op",
         %{config: config} do
      {:ok, pid} = ConnectionManager.start_link(config)
      assert ConnectionManager.disconnect(pid) == :ok
      assert ConnectionManager.get_connection_state(pid) == :disconnected
      GenServer.stop(pid)
    end

    test "subscribe/unsubscribe accept any event topic (incl. unknown) and dedupe",
         %{config: config} do
      {:ok, pid} = ConnectionManager.start_link(config)

      # Known + unknown topics both accepted; double-subscribe is idempotent.
      assert ConnectionManager.subscribe(pid, :connection_update, self()) == :ok
      assert ConnectionManager.subscribe(pid, :connection_update, self()) == :ok
      assert ConnectionManager.subscribe(pid, :totally_made_up, self()) == :ok

      assert ConnectionManager.unsubscribe(pid, :connection_update, self()) == :ok
      assert ConnectionManager.unsubscribe(pid, :never_subscribed, self()) == :ok

      GenServer.stop(pid)
    end
  end
end
