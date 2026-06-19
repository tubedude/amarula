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
    :parent_pid,
    :keep_alive_interval_ms,
    :keep_alive_timer,
    :connect_timeout_timer
  ]

  @type t :: %__MODULE__{
          url: String.t(),
          connection_state: Types.connection_state(),
          parent_pid: pid(),
          keep_alive_interval_ms: non_neg_integer(),
          keep_alive_timer: reference() | nil,
          connect_timeout_timer: reference() | nil
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

    keep_alive_interval_ms =
      opts[:keep_alive_interval_ms] ||
        Application.get_env(:amarula, :keep_alive_interval_ms, 30_000)

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
      parent_pid: parent_pid,
      keep_alive_interval_ms: keep_alive_interval_ms,
      keep_alive_timer: nil,
      connect_timeout_timer: nil
    }

    # WebSockex options
    websocket_opts = [
      extra_headers: headers_list,
      async: true
    ]

    Logger.debug("Attempting to connect to WhatsApp WebSocket at: #{url}")
    Logger.debug("Connection timeout: #{connect_timeout_ms}ms")
    Logger.debug("Keep alive interval: #{keep_alive_interval_ms}ms")
    Logger.debug("Origin: #{origin}")
    Logger.debug("User agent: #{agent}")

    WebSockex.start_link(url, __MODULE__, state, websocket_opts)
  end

  @doc """
  Connects to the WebSocket server.
  """
  @impl Types
  def connect(pid \\ __MODULE__) do
    GenServer.call(pid, :connect)
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

  @doc """
  Checks if the WebSocket is open.
  """
  @impl Types
  def open?(pid \\ __MODULE__) do
    GenServer.call(pid, :open?)
  end

  @doc """
  Checks if the WebSocket is closed.
  """
  @impl Types
  def closed?(pid \\ __MODULE__) do
    GenServer.call(pid, :closed?)
  end

  @doc """
  Checks if the WebSocket is connecting.
  """
  @impl Types
  def connecting?(pid \\ __MODULE__) do
    GenServer.call(pid, :connecting?)
  end

  @doc """
  Checks if the WebSocket is closing.
  """
  @impl Types
  def closing?(pid \\ __MODULE__) do
    GenServer.call(pid, :closing?)
  end

  # WebSockex callbacks

  def init(state) do
    Logger.debug("WebSocket client initialized, ready to connect to: #{state.url}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_connect(conn, state) do
    Logger.info("WebSocket connected to WhatsApp server")
    Logger.debug("Connection URL: #{state.url}")
    Logger.debug("Connection details: #{inspect(conn)}")

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

    # Cancel keep-alive timer
    if state.keep_alive_timer do
      Process.cancel_timer(state.keep_alive_timer)
      Logger.debug("Keep-alive timer cancelled")
    end

    # Send disconnection event directly to parent
    send(state.parent_pid, {:ws_event, self(), {:close, %{reason: conn.reason}}})

    {:ok, new_state}
  end

  @impl WebSockex
  def handle_frame({:text, data}, state) do
    Logger.debug("Received text frame from WhatsApp server")
    Logger.debug("Text frame data length: #{byte_size(data)} bytes")
    Logger.debug("Text frame preview: #{String.slice(data, 0, 100)}...")

    # Send frame event directly to parent
    send(state.parent_pid, {:ws_event, self(), {:frame, data}})
    {:ok, state}
  end

  def handle_frame({:binary, data}, state) do
    Logger.debug("Received binary frame from WhatsApp server")
    Logger.debug("Binary frame data length: #{byte_size(data)} bytes")

    Logger.debug(
      "Binary frame hex preview: #{data |> :binary.part(0, min(20, byte_size(data))) |> Base.encode16()}"
    )

    # Send frame event directly to parent
    send(state.parent_pid, {:ws_event, self(), {:frame, data}})
    {:ok, state}
  end

  def handle_frame({:ping, data}, state) do
    Logger.debug("Received ping from WhatsApp server: #{inspect(data)}")
    send(state.parent_pid, {:ws_event, self(), {:ping, data}})
    {:ok, state}
  end

  def handle_frame({:pong, data}, state) do
    Logger.debug("Received pong from WhatsApp server: #{inspect(data)}")
    send(state.parent_pid, {:ws_event, self(), {:pong, data}})
    {:ok, state}
  end

  @impl WebSockex
  def handle_info(:keep_alive, state) do
    # WebSocket-level ping disabled - keep-alive handled by Connection via WA XML ping
    {:ok, state}
  end

  @impl WebSockex
  def handle_info({:"$gen_call", from, :connect}, state) do
    # WebSockex handles connection automatically on start_link
    # This is a no-op for compatibility with the Types behavior
    GenServer.reply(from, :ok)
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
  def handle_info({:"$gen_call", from, :open?}, state) do
    is_open = state.connection_state == :connected
    GenServer.reply(from, is_open)
    {:ok, state}
  end

  @impl WebSockex
  def handle_info({:"$gen_call", from, :closed?}, state) do
    is_closed = state.connection_state == :disconnected or state.connection_state == :closed
    GenServer.reply(from, is_closed)
    {:ok, state}
  end

  @impl WebSockex
  def handle_info({:"$gen_call", from, :connecting?}, state) do
    is_connecting = state.connection_state == :connecting
    GenServer.reply(from, is_connecting)
    {:ok, state}
  end

  @impl WebSockex
  def handle_info({:"$gen_call", from, :closing?}, state) do
    is_closing = state.connection_state == :reconnecting
    GenServer.reply(from, is_closing)
    {:ok, state}
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

    # Cancel timers
    if state.keep_alive_timer do
      Process.cancel_timer(state.keep_alive_timer)
    end

    if state.connect_timeout_timer do
      Process.cancel_timer(state.connect_timeout_timer)
    end

    # Send termination event directly to parent
    send(state.parent_pid, {:ws_event, self(), {:close, %{reason: reason}}})
  end

  # Private functions

  @doc false
  def start_keep_alive_timer(interval_ms) when interval_ms > 0 do
    Process.send_after(self(), :keep_alive, interval_ms)
  end

  @doc false
  def start_keep_alive_timer(_), do: nil
end
