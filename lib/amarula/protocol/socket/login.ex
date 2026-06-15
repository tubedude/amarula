defmodule Amarula.Protocol.Socket.Login do
  @moduledoc """
  The Noise XX handshake + login-bootstrap stanza builders, extracted from
  `ConnectionManager`. Pure: these compute frames/nodes from inputs and return
  values — they do NOT touch the websocket, timers, or emit events. CM stays the
  process: it sends the frames/nodes, transitions state, and emits updates.

  Handshake flow (CM drives it across `:ws_event` frames):

      client_hello(creds, config)  → {:ok, hello_frame, handshake_state}   # CM sends hello_frame
      server_hello(handshake, frame) → {:ok, finish_frame, final_noise}    # CM sends finish_frame
      complete(final_noise)        → transport_noise_state                 # CM enters transport
  """

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Crypto.{Constants, NoiseHandler}
  alias Amarula.Protocol.Socket.ConnectionValidator

  @doc """
  Build the ClientHello frame + initial handshake state from creds/config.
  Returns `{:ok, encoded_frame, handshake_state}` (with `sent_intro` set) or
  `{:error, reason}`.
  """
  @spec client_hello(map(), map()) :: {:ok, binary(), map()} | {:error, term()}
  def client_hello(auth_creds, config) do
    with {:ok, client_hello_message, handshake_state} <-
           ConnectionValidator.generate_client_hello(auth_creds, config),
         {encoded_frame, updated_noise} <-
           NoiseHandler.encode_frame(handshake_state.noise_state, client_hello_message) do
      {:ok, encoded_frame, %{handshake_state | noise_state: updated_noise}}
    end
  end

  @doc """
  Process a ServerHello `frame` against `handshake_state`: decode, validate, and
  produce the ClientFinish frame. Returns `{:ok, finish_frame, final_noise_state}`
  or `{:error, reason}`. (CM sends `finish_frame`, then calls `complete/1`.)
  """
  @spec server_hello(map(), binary()) :: {:ok, binary(), map()} | {:error, term()}
  def server_hello(handshake_state, frame_data) do
    with {:ok, decoded_frame} <- decode_first_frame(handshake_state, frame_data),
         {:ok, client_finish, updated_handshake} <-
           ConnectionValidator.process_server_hello(handshake_state, decoded_frame) do
      {encoded_finish, final_noise} =
        NoiseHandler.encode_frame(updated_handshake.noise_state, client_finish)

      {:ok, encoded_finish, final_noise}
    end
  end

  @doc "Transition the post-ClientFinish noise state into the transport phase."
  @spec complete(map()) :: map()
  def complete(final_noise_state), do: NoiseHandler.finish_init(final_noise_state)

  # --- login-bootstrap stanza builders (pure Node constructors) ---

  @doc "The digest-key-bundle IQ (`<iq get xmlns=encrypt><digest/>`)."
  @spec digest_iq() :: Node.t()
  def digest_iq do
    %Node{
      tag: "iq",
      attrs: [{"to", Constants.s_whatsapp_net()}, {"type", "get"}, {"xmlns", "encrypt"}],
      content: [%Node{tag: "digest", attrs: %{}, content: nil}]
    }
  end

  @doc "The unified-session `<ib><unified_session id=>` node (id per Baileys)."
  @spec unified_session_node() :: Node.t()
  def unified_session_node do
    three_days = 3 * 24 * 60 * 60 * 1000
    seven_days = 7 * 24 * 60 * 60 * 1000
    id = rem(System.system_time(:millisecond) + three_days, seven_days)

    %Node{
      tag: "ib",
      attrs: %{},
      content: [
        %Node{tag: "unified_session", attrs: %{"id" => Integer.to_string(id)}, content: nil}
      ]
    }
  end

  # --- internals ---

  defp decode_first_frame(handshake_state, data) do
    case NoiseHandler.decode_frame(handshake_state.noise_state, data) do
      {:ok, [frame | _], _noise} -> {:ok, frame}
      {:ok, [], _noise} -> {:error, :no_handshake_frame}
      other -> other
    end
  end
end
