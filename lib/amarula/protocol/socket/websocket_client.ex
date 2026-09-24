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
    * `:origin` - `Origin` header for the handshake (defaults to WhatsApp Web's origin)
    * `:connect_timeout_ms` - TCP connect deadline (defaults to `30_000`)
    * Other options for timeouts and configuration

  `:origin` is sent as a real `Origin` header unless `:headers` already sets
  one (case-insensitively), in which case the explicit `:headers` entry wins.
  No `User-Agent` is sent — the same as Baileys and whatsmeow, which send only
  `Origin`.

  `:connect_timeout_ms` is passed to WebSockex as `:socket_connect_timeout`
  (WebSockex's own option name) — leaving it unset would silently fall back
  to WebSockex's 6-second default instead of this module's 30-second one.
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

    # `origin` was being computed (and logged) but never actually added to the
    # request — the handshake went out with no Origin header at all unless the
    # caller duplicated it into `:headers` manually. An explicit `:headers`
    # entry still wins (matched case-insensitively, since HTTP header names are).
    headers_list = build_headers(headers, origin)

    # Build initial state struct
    state = %__MODULE__{
      url: url,
      connection_state: :disconnected,
      parent_pid: parent_pid
    }

    # WebSockex options. `:socket_connect_timeout` (not `:connect_timeout_ms`,
    # which is this module's own option name) is what WebSockex actually
    # reads for the TCP connect deadline — it defaults to 6s, so leaving it
    # unset silently ignored the configured `connect_timeout_ms` (default
    # 30s): every connection used WebSockex's 6s default regardless of config.
    websocket_opts = [
      extra_headers: headers_list,
      socket_connect_timeout: connect_timeout_ms,
      async: true
    ]

    Logger.debug("Attempting to connect to WhatsApp WebSocket at: #{url}")
    Logger.debug("Connection timeout: #{connect_timeout_ms}ms")
    Logger.debug("Origin: #{origin}")

    WebSockex.start_link(url, __MODULE__, state, websocket_opts)
  end

  @doc """
  Normalizes `headers` (a list or map — anything else becomes `[]`) and adds
  `Origin`, unless it already has that key (matched case-insensitively), in
  which case the explicit entry wins. Public so this can be unit-tested without
  a live connection.
  """
  @spec build_headers(term(), String.t()) :: [{String.t() | atom(), String.t()}]
  def build_headers(headers, origin) do
    headers
    |> case do
      h when is_map(h) -> Map.to_list(h)
      h when is_list(h) -> h
      _ -> []
    end
    |> put_new_header("Origin", origin)
  end

  # Append `{name, value}` unless the caller already supplied that header.
  # HTTP header names are case-insensitive, so the comparison has to be too —
  # otherwise a caller passing "origin" would get a duplicate header.
  defp put_new_header(headers, name, value) do
    downcased = String.downcase(name)

    already_set? =
      Enum.any?(headers, fn
        {k, _v} when is_binary(k) -> String.downcase(k) == downcased
        {k, _v} when is_atom(k) -> k |> Atom.to_string() |> String.downcase() == downcased
        _ -> false
      end)

    if already_set?, do: headers, else: headers ++ [{name, value}]
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
