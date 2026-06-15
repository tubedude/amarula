defmodule Amarula.Protocol.Socket.ConnectionValidator do
  @moduledoc """
  Static validation functions for WhatsApp WebSocket handshake.

  This module provides pure functions for validating handshake messages
  and generating appropriate responses. The Connection orchestrates
  the actual sending and state management.
  """

  require Logger
  alias Amarula.Protocol.Crypto.{Crypto, NoiseHandler}
  alias Amarula.Protocol.Auth.AuthUtils
  alias Amarula.Protocol.Proto

  @type handshake_state :: %{
          noise_state: NoiseHandler.noise_state(),
          auth_creds: AuthUtils.auth_creds(),
          socket_config: AuthUtils.socket_config(),
          handshake_step: atom()
        }

  @type validation_result :: {:ok, handshake_state()} | {:error, term()}
  @type message_result :: {:ok, binary(), handshake_state()} | {:error, term()}

  @doc """
  Generate initial ClientHello message for handshake start.

  Returns the encoded ClientHello message and initial handshake state.
  """
  @spec generate_client_hello(AuthUtils.auth_creds(), AuthUtils.socket_config()) ::
          message_result()
  def generate_client_hello(auth_creds, socket_config) do
    try do
      Logger.debug("Generating ClientHello message...")

      # Generate ephemeral key pair for this connection
      ephemeral_key_pair = Crypto.generate_key_pair()

      # Initialize noise handler (this hashes protocol name and client ephemeral)
      noise_state = NoiseHandler.new(ephemeral_key_pair)

      # Create ClientHello message
      client_hello = %Proto.HandshakeMessage.ClientHello{
        ephemeral: noise_state.ephemeral_key_pair.public,
        static: nil,
        payload: nil
      }

      # Create HandshakeMessage
      handshake_message = %Proto.HandshakeMessage{
        clientHello: client_hello,
        serverHello: nil,
        clientFinish: nil
      }

      # Encode message
      encoded_message = Proto.HandshakeMessage.encode(handshake_message)

      # Create handshake state
      handshake_state = %{
        noise_state: noise_state,
        auth_creds: auth_creds,
        socket_config: socket_config,
        handshake_step: :waiting_server_hello
      }

      Logger.debug("ClientHello generated successfully")
      {:ok, encoded_message, handshake_state}
    rescue
      error ->
        Logger.error("Error generating ClientHello: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Process ServerHello message and generate ClientFinish response.

  Takes the incoming ServerHello message and returns the ClientFinish
  message to send back to the server.
  """
  @spec process_server_hello(handshake_state(), binary()) :: message_result()
  def process_server_hello(state, message_data) do
    try do
      Logger.debug("Processing ServerHello message...")

      # Decode HandshakeMessage
      handshake_message = Proto.HandshakeMessage.decode(message_data)

      case handshake_message.serverHello do
        nil ->
          Logger.error("Received HandshakeMessage without ServerHello")
          {:error, :missing_server_hello}

        _server_hello ->
          Logger.debug("Received ServerHello, processing handshake...")

          # Process handshake through noise handler
          # CRITICAL: Preserve sent_intro from incoming state (should be true from ClientHello encoding)
          Logger.debug(
            "Processing handshake with noise_state.sent_intro=#{state.noise_state.sent_intro}"
          )

          case NoiseHandler.process_handshake(
                 state.noise_state,
                 handshake_message,
                 state.auth_creds.noise_key
               ) do
            {:ok, encrypted_key, updated_noise_state} ->
              # CRITICAL: Preserve sent_intro flag through handshake processing
              # This ensures ClientFinish (second frame) won't include NOISE_HEADER
              preserved_noise_state = %{
                updated_noise_state
                | sent_intro: state.noise_state.sent_intro
              }

              Logger.debug(
                "After process_handshake: preserved sent_intro=#{preserved_noise_state.sent_intro}"
              )

              # Generate ClientPayload
              client_payload =
                if state.auth_creds.me do
                  AuthUtils.generate_login_node(state.auth_creds.me.id, state.socket_config)
                else
                  AuthUtils.generate_registration_node(state.auth_creds, state.socket_config)
                end

              # Encode payload
              encoded_payload = Proto.ClientPayload.encode(client_payload)

              # Encrypt payload (payload is encrypted in handshake phase, NOT transport phase)
              # finish_init will be called AFTER sending ClientFinish
              {encrypted_payload, final_noise_state} =
                NoiseHandler.encrypt(preserved_noise_state, encoded_payload)

              # Create ClientFinish message
              client_finish = %Proto.HandshakeMessage.ClientFinish{
                static: encrypted_key,
                payload: encrypted_payload
              }

              # Create final HandshakeMessage
              final_message = %Proto.HandshakeMessage{
                clientHello: nil,
                serverHello: nil,
                clientFinish: client_finish
              }

              # Note: finish_init is NOT called here - it will be called AFTER sending ClientFinish
              # This matches Baileys: noise.finishInit() is called after sendRawMessage(clientFinish)

              new_state = %{state | noise_state: final_noise_state, handshake_step: :completed}

              encoded_final = Proto.HandshakeMessage.encode(final_message)
              {:ok, encoded_final, new_state}

            {:error, reason} ->
              Logger.error("Handshake processing failed: #{inspect(reason)}")
              {:error, reason}
          end
      end
    rescue
      error ->
        Logger.error("Error processing ServerHello: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Process handshake completion message.

  Handles the final handshake message from the server.
  """
  @spec process_handshake_complete(handshake_state(), binary()) ::
          {:ok, handshake_state()} | {:error, term()}
  def process_handshake_complete(state, _message_data) do
    Logger.debug("Handshake completion message received")
    {:ok, state}
  end

  @doc """
  Check if handshake is completed.
  """
  @spec handshake_completed?(handshake_state()) :: boolean()
  def handshake_completed?(state) do
    state.handshake_step == :completed
  end

  @doc """
  Get the completed noise state for ongoing communication.
  """
  @spec get_noise_state(handshake_state()) :: NoiseHandler.noise_state() | nil
  def get_noise_state(state) do
    if handshake_completed?(state) do
      state.noise_state
    else
      nil
    end
  end
end
