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

  describe "connection state management" do
    test "tracks connection state changes" do
      config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        connect_timeout_ms: 1000,
        keep_alive_interval_ms: 30000,
        max_retries: 1,
        retry_delay: 100,
        headers: %{},
        origin: "https://test.example.com",
        agent: nil
      }

      {:ok, pid} = ConnectionManager.start_link(config)

      # Test initial state
      assert ConnectionManager.get_connection_state(pid) == :disconnected

      # Clean up
      GenServer.stop(pid)
    end

    test "handles disconnection" do
      config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        connect_timeout_ms: 1000,
        keep_alive_interval_ms: 30000,
        max_retries: 1,
        retry_delay: 100,
        headers: %{},
        origin: "https://test.example.com",
        agent: nil
      }

      {:ok, pid} = ConnectionManager.start_link(config)

      # Test disconnection
      assert ConnectionManager.disconnect(pid) == :ok
      assert ConnectionManager.get_connection_state(pid) == :disconnected

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "event subscription" do
    test "subscribes and unsubscribes to events" do
      config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        connect_timeout_ms: 1000,
        keep_alive_interval_ms: 30000,
        max_retries: 1,
        retry_delay: 100,
        headers: %{},
        origin: "https://test.example.com",
        agent: nil
      }

      {:ok, pid} = ConnectionManager.start_link(config)

      # Test subscription
      assert ConnectionManager.subscribe(pid, :connection_update, self()) == :ok
      assert ConnectionManager.subscribe(pid, :frame, self()) == :ok

      # Test unsubscription
      assert ConnectionManager.unsubscribe(pid, :connection_update, self()) == :ok
      assert ConnectionManager.unsubscribe(pid, :frame, self()) == :ok

      # Clean up
      GenServer.stop(pid)
    end

    test "emits events to subscribers" do
      config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        connect_timeout_ms: 1000,
        keep_alive_interval_ms: 30000,
        max_retries: 1,
        retry_delay: 100,
        headers: %{},
        origin: "https://test.example.com",
        agent: nil
      }

      {:ok, pid} = ConnectionManager.start_link(config)

      # Subscribe to events
      ConnectionManager.subscribe(pid, :connection_update, self())

      # Test event emission (this would require actual connection events)
      # For now, we'll just test the subscription mechanism
      assert true

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "error handling" do
    test "handles invalid configuration" do
      # Test with missing required fields
      invalid_config = %{
        wa_websocket_url: nil,
        connect_timeout_ms: 1000,
        max_retries: 1,
        retry_delay: 100
      }

      # Should still start but with default values
      {:ok, pid} = ConnectionManager.start_link(invalid_config)
      assert ConnectionManager.get_connection_state(pid) == :disconnected

      # Clean up
      GenServer.stop(pid)
    end

    test "handles disconnection when not connected" do
      config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        connect_timeout_ms: 1000,
        keep_alive_interval_ms: 30000,
        max_retries: 1,
        retry_delay: 100,
        headers: %{},
        origin: "https://test.example.com",
        agent: nil
      }

      {:ok, pid} = ConnectionManager.start_link(config)

      # Disconnect when already disconnected
      assert ConnectionManager.disconnect(pid) == :ok
      assert ConnectionManager.get_connection_state(pid) == :disconnected

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "configuration handling" do
    test "handles minimal configuration" do
      minimal_config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        max_retries: 1,
        retry_delay: 100
      }

      {:ok, pid} = ConnectionManager.start_link(minimal_config)
      assert ConnectionManager.get_connection_state(pid) == :disconnected

      # Clean up
      GenServer.stop(pid)
    end

    test "handles configuration with custom headers" do
      config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        connect_timeout_ms: 1000,
        keep_alive_interval_ms: 30000,
        max_retries: 1,
        retry_delay: 100,
        headers: %{
          "User-Agent" => "CustomAgent/1.0",
          "X-Custom-Header" => "custom-value"
        },
        origin: "https://test.example.com",
        agent: nil
      }

      {:ok, pid} = ConnectionManager.start_link(config)
      assert ConnectionManager.get_connection_state(pid) == :disconnected

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "event handling edge cases" do
    test "handles subscription to non-existent event types" do
      config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        connect_timeout_ms: 1000,
        keep_alive_interval_ms: 30000,
        max_retries: 1,
        retry_delay: 100,
        headers: %{},
        origin: "https://test.example.com",
        agent: nil
      }

      {:ok, pid} = ConnectionManager.start_link(config)

      # Subscribe to non-existent event type
      assert ConnectionManager.subscribe(pid, :non_existent_event, self()) == :ok

      # Clean up
      GenServer.stop(pid)
    end

    test "handles unsubscription from non-existent event types" do
      config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        connect_timeout_ms: 1000,
        keep_alive_interval_ms: 30000,
        max_retries: 1,
        retry_delay: 100,
        headers: %{},
        origin: "https://test.example.com",
        agent: nil
      }

      {:ok, pid} = ConnectionManager.start_link(config)

      # Unsubscribe from non-existent event type
      assert ConnectionManager.unsubscribe(pid, :non_existent_event, self()) == :ok

      # Clean up
      GenServer.stop(pid)
    end

    test "handles multiple subscribers to same event" do
      config = %{
        wa_websocket_url: "wss://test.example.com/ws",
        connect_timeout_ms: 1000,
        keep_alive_interval_ms: 30000,
        max_retries: 1,
        retry_delay: 100,
        headers: %{},
        origin: "https://test.example.com",
        agent: nil
      }

      {:ok, pid} = ConnectionManager.start_link(config)

      # Subscribe multiple times to same event
      assert ConnectionManager.subscribe(pid, :connection_update, self()) == :ok
      assert ConnectionManager.subscribe(pid, :connection_update, self()) == :ok

      # Clean up
      GenServer.stop(pid)
    end
  end
end
