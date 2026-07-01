defmodule Amarula.Protocol.Socket.Types do
  @moduledoc """
  Types and behaviors for WebSocket layer implementation.
  """

  @type connection_state :: :connecting | :connected | :disconnected | :reconnecting | :closed

  @type websocket_config :: %{
          url: String.t(),
          connect_timeout_ms: non_neg_integer(),
          keep_alive_interval_ms: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          origin: String.t(),
          agent: term()
        }

  @type websocket_event ::
          {:open, term()}
          | {:close, term()}
          | {:error, term()}
          | {:message, binary()}
          | {:ping, term()}
          | {:pong, term()}
          | {:frame, binary()}

  @type connection_update :: %{
          connection: connection_state(),
          received_pending_notifications: boolean(),
          qr: String.t() | nil
        }

  @type socket_config :: %{
          wa_websocket_url: String.t(),
          connect_timeout_ms: non_neg_integer(),
          keep_alive_interval_ms: non_neg_integer(),
          logger: module(),
          browser: map(),
          auth: map(),
          print_qr_in_terminal: boolean(),
          default_query_timeout_ms: non_neg_integer(),
          transaction_opts: map(),
          qr_timeout: non_neg_integer(),
          make_signal_repository: function()
        }

  @doc """
  Behavior for WebSocket client implementations. Connection lifecycle is
  process lifecycle: `start_link` connects, `close/1` (or killing the process)
  disconnects — there are no separate connect/state-predicate callbacks.
  """
  @callback close() :: :ok | {:error, term()}
  @callback send_data(data :: binary() | iodata()) :: :ok | {:error, term()}
end
