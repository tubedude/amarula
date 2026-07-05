defmodule Amarula.Protocol.Socket.WebSocketClient do
  @moduledoc """
  WebSocket client implementation using websockex.

  This module provides a WebSocket client that handles connection management,
  message sending/receiving, and event emission for WhatsApp WebSocket communication.
  """

  use WebSockex
  require Logger

  alias Amarula.Protocol.Socket.Types

  @behaviour Types

  defstruct [
    :url,
    :connection_state,
    :parent_pid
  ]

  @type t :: %__MODULE__{
          url: String.t(),
          connection_state: Types.connection_state(),
          parent_pid: pid()
        }

  @doc """
  Starts a new WebSocket client.

  ## Options

    * `:parent_pid` - Required. PID of the Connection that will receive events.
    * `:url` - WebSocket URL (defaults to WhatsApp WebSocket URL)
    * `:headers` - List or map of HTTP headers
    * Other options for timeouts and configuration

  """
  def start_link(opts \\ []) do
    Logger.debug("Starting WebSocket client connection to WhatsApp server")

    # Parent PID is required
    parent_pid = Keyword.fetch!(opts, :parent_pid)

    # Set defaults from Application config
    url =
      opts[:url] ||
        Application.get_env(:amarula, :websocket_url, "wss://web.whatsapp.com/ws/chat")

    connect_timeout_ms =
      opts[:connect_timeout_ms] || Application.get_env(:amarula, :connect_timeout_ms, 30_000)

    headers = opts[:headers] || []
    origin = opts[:origin] || Application.get_env(:amarula, :origin, "https://web.whatsapp.com")
    agent = opts[:agent] || "Mozilla/5.0"

    # Convert headers to list format
    headers_list =
      case headers do
        h when is_map(h) -> Enum.map(h, fn {k, v} -> {k, v} end)
        h when is_list(h) -> h
        _ -> []
      end

    # Build initial state struct
    state = %__MODULE__{
      url: url,
      connection_state: :disconnected,
      parent_pid: parent_pid
    }

    # WebSockex options
    websocket_opts = [
      extra_headers: headers_list,
      async: true
    ]

    Logger.debug("Attempting to connect to WhatsApp WebSocket at: #{url}")
    Logger.debug("Connection timeout: #{connect_timeout_ms}ms")
    Logger.debug("Origin: #{origin}")
    Logger.debug("User agent: #{agent}")

    WebSockex.start_link(url, __MODULE__, state, websocket_opts)
  end

  @doc """
  Closes the WebSocket connection.
  """
  @impl Types
  def close(pid \\ __MODULE__) do
    GenServer.call(pid, :close)
  end

  @doc """
  Sends data through the WebSocket connection.
  """
  @impl Types
  def send_data(pid \\ __MODULE__, data) do
    WebSockex.send_frame(pid, {:binary, data})
  end

  # WebSockex callbacks

  def init(state) do
    Logger.debug("WebSocket client initialized, ready to connect to: #{state.url}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info("WebSocket connected to WhatsApp server")

    new_state = %{state | connection_state: :connected}

    # WebSocket-level ping is disabled - keep-alive is handled at application level
    # via WA XML ping messages in Connection
    # This matches Baileys behavior which only uses WA XML ping, not WebSocket ping

    # Send connection event directly to parent (Connection)
    send(state.parent_pid, {:ws_event, self(), {:open, %{url: state.url}}})

    {:ok, new_state}
  end

  @impl WebSockex
  def handle_disconnect(conn, state) do
    Logger.warning("WebSocket disconnected from WhatsApp server: #{inspect(conn.reason)}")
    Logger.debug("Connection state before disconnect: #{state.connection_state}")

    new_state = %{state | connection_state: :disconnected}

    # Send disconnection event directly to parent
    send(state.parent_pid, {:ws_event, self(), {:close, %{reason: conn.reason}}})

    {:ok, new_state}
  end

  # Raw frame receipt is wire-level detail — not logged here. Set AMARULA_FRAME_TAP
  # to trace every decoded node (Amarula.Connection.frame_tap/2); the domain-level
  # "we received something" signal is logged once the frame is decoded and
  # dispatched (e.g. a decrypted message, a receipt, a presence update).
  @impl WebSockex
  def handle_frame({:text, data}, state) do
    send(state.parent_pid, {:ws_event, self(), {:frame, data}})
    {:ok, state}
  end

  def handle_frame({:binary, data}, state) do
    send(state.parent_pid, {:ws_event, self(), {:frame, data}})
    {:ok, state}
  end

  def handle_frame({:ping, data}, state) do
    send(state.parent_pid, {:ws_event, self(), {:ping, data}})
    {:ok, state}
  end

  def handle_frame({:pong, data}, state) do
    send(state.parent_pid, {:ws_event, self(), {:pong, data}})
    {:ok, state}
  end

  @impl WebSockex
  def handle_info({:"$gen_call", from, :close}, state) do
    # Request graceful WebSocket closure using WebSockex's close mechanism
    # Close code 1000 = normal closure
    GenServer.reply(from, :ok)
    {:close, {1000, "Client requested close"}, state}
  end

  @impl WebSockex
  def handle_info(message, state) do
    Logger.debug("Received unexpected message: #{inspect(message)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast(message, state) do
    Logger.debug("Received cast message: #{inspect(message)}")
    {:ok, state}
  end

  @impl WebSockex
  def terminate(reason, state) do
    Logger.info("WebSocket client terminating: #{inspect(reason)}")

    # Send termination event directly to parent
    send(state.parent_pid, {:ws_event, self(), {:close, %{reason: reason}}})
  end
end
