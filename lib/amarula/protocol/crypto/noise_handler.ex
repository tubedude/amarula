defmodule Amarula.Protocol.Crypto.NoiseHandler do
  @moduledoc """
  Noise protocol handler for WhatsApp WebSocket communication.

  This module implements the Noise_XX_25519_AESGCM_SHA256 protocol used by WhatsApp
  for secure WebSocket communication. It provides stateless functions that operate
  on noise state, which is stored in the Connection's GenServer state.

  The noise state is recreated on every new WebSocket connection with fresh ephemeral keys.
  """

  import Bitwise
  require Logger
  alias Amarula.Protocol.Crypto.{Crypto, Constants}

  # Pinned WhatsApp root certificate (Baileys WA_CERT_DETAILS). The Noise_XX
  # handshake's server authentication is only anchored to WhatsApp by verifying the
  # cert chain's intermediate signature against THIS key — without it any cert with
  # issuerSerial=0 would pass.
  @wa_cert_public_key Base.decode16!(
                        "142375574D0A587166AAE71EBE516437C4A28B73E3695C6CE1F7F9545DA8EE6B"
                      )
  @wa_cert_serial 0

  @type noise_state :: %{
          ephemeral_key_pair: Crypto.key_pair(),
          hash: binary(),
          salt: binary(),
          enc_key: binary(),
          dec_key: binary(),
          read_counter: non_neg_integer(),
          write_counter: non_neg_integer(),
          handshake_state:
            :init | :awaiting_server_hello | :handshake | :handshake_complete | :transport,
          sent_intro: boolean(),
          in_bytes: binary(),
          routing_info: binary() | nil,
          noise_header: binary()
        }

  @type handshake_result :: {:ok, binary(), noise_state()} | {:error, term()}
  @type frame_result :: {:ok, list(binary()), noise_state()}
  @type encrypt_result :: {binary(), noise_state()}
  @type decrypt_result :: {:ok, binary(), noise_state()} | {:error, term()}

  @doc """
  Create initial noise state with ephemeral key pair and configuration.

  Returns a new noise state struct ready for handshake.
  """
  @spec new(Crypto.key_pair(), keyword()) :: noise_state()
  def new(ephemeral_key_pair, opts \\ []) do
    routing_info = Keyword.get(opts, :routing_info)
    noise_header = Constants.noise_wa_header()

    # Initialize hash with noise mode
    # Match Baileys: if noise_mode is exactly 32 bytes, use it directly as hash
    # otherwise compute SHA256
    noise_mode = Constants.noise_mode()
    hash = if byte_size(noise_mode) == 32, do: noise_mode, else: Crypto.sha256(noise_mode)

    %{
      ephemeral_key_pair: ephemeral_key_pair,
      hash: hash,
      salt: hash,
      enc_key: hash,
      dec_key: hash,
      read_counter: 0,
      write_counter: 0,
      handshake_state: :init,
      sent_intro: false,
      in_bytes: <<>>,
      routing_info: routing_info,
      noise_header: noise_header
    }
    |> authenticate(noise_header)
    |> authenticate(ephemeral_key_pair.public)
  end

  @doc """
  Update running hash with data for authentication.

  Returns updated noise state.
  """
  @spec authenticate(noise_state(), binary()) :: noise_state()
  def authenticate(%{handshake_state: :transport} = state, _data) do
    # Handshake complete, authentication no longer needed
    state
  end

  def authenticate(state, data) do
    hash = Crypto.sha256(state.hash <> data)
    %{state | hash: hash}
  end

  @doc """
  Encrypt plaintext using current encryption key and counter.

  Returns {encrypted_data, updated_state}.
  """
  @spec encrypt(noise_state(), binary()) :: encrypt_result()
  def encrypt(%{handshake_state: :init} = _state, _plaintext) do
    raise "Cannot encrypt before keys are established via mix_into_key"
  end

  def encrypt(state, plaintext) do
    iv = Crypto.generate_iv(state.write_counter)
    aad = if state.handshake_state == :transport, do: <<>>, else: state.hash

    {:ok, encrypted} = Crypto.aes_encrypt_gcm(plaintext, state.enc_key, iv, aad)
    new_state = %{state | write_counter: state.write_counter + 1}
    new_state = authenticate(new_state, encrypted)
    {encrypted, new_state}
  end

  @doc """
  Decrypt ciphertext using current decryption key and counter.

  Returns {:ok, decrypted_data, updated_state} or {:error, reason}.
  """
  @spec decrypt(noise_state(), binary()) :: decrypt_result()
  def decrypt(state, ciphertext) do
    # Compute default AAD based on phase and forward to 3-arity
    aad = if state.handshake_state == :transport, do: <<>>, else: state.hash
    decrypt(state, ciphertext, aad)
  end

  @doc """
  Decrypt with explicit AAD (used by tests to ensure exact handshake semantics).

  Returns {:ok, decrypted_data, updated_state} or {:error, reason}.
  """
  @spec decrypt(noise_state(), binary(), binary()) :: decrypt_result()
  def decrypt(state, ciphertext, aad) do
    counter =
      case state.handshake_state do
        :transport -> state.read_counter
        _ -> state.write_counter
      end

    iv = Crypto.generate_iv(counter)

    case Crypto.aes_decrypt_gcm(ciphertext, state.dec_key, iv, aad) do
      {:ok, decrypted} ->
        new_state =
          case state.handshake_state do
            :transport -> %{state | read_counter: state.read_counter + 1}
            _ -> %{state | write_counter: state.write_counter + 1}
          end

        new_state = authenticate(new_state, ciphertext)
        {:ok, decrypted, new_state}

      {:error, reason} ->
        Logger.error("Decryption failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Mix data into key using HKDF.

  Returns updated noise state with new keys.
  """
  @spec mix_into_key(noise_state(), binary()) :: noise_state()
  def mix_into_key(state, data) do
    # HKDF according to Noise MixKey: HKDF(ck, DH_output, 2)
    # Returns (ck, k) where ck becomes the new salt and k is the cipher key
    derived_key = Crypto.hkdf(data, Constants.hkdf_output_length(), state.salt, <<>>)
    {new_salt, cipher_key} = :erlang.split_binary(derived_key, 32)

    # During handshake: both enc_key and dec_key use the same key (cipher_key)
    # Messages alternate, so both parties use the same cipher state
    # Key splitting into read/write keys only happens during finish_init (Split operation)
    # IMPORTANT: Reset counters to 0 on MixKey (per Noise spec and Baileys implementation)
    %{
      state
      | salt: new_salt,
        enc_key: cipher_key,
        dec_key: cipher_key,
        read_counter: 0,
        write_counter: 0,
        handshake_state: :handshake
    }
  end

  @doc """
  Complete handshake initialization by splitting keys.

  Returns updated noise state with finished handshake.
  """
  @spec finish_init(noise_state()) :: noise_state()
  def finish_init(state) do
    # Final HKDF with empty input
    derived_key = Crypto.hkdf(<<>>, Constants.hkdf_output_length(), state.salt, <<>>)
    {write_key, read_key} = :erlang.split_binary(derived_key, 32)

    Logger.debug("Noise finish_init: split keys, reset counters, entering transport phase")

    %{
      state
      | enc_key: write_key,
        dec_key: read_key,
        hash: <<>>,
        read_counter: 0,
        write_counter: 0,
        handshake_state: :transport
    }
  end

  @doc """
  Process server hello message during handshake.

  Returns {:ok, encrypted_key, updated_state} or {:error, reason}.
  """
  @spec process_handshake(noise_state(), map(), Crypto.key_pair()) :: handshake_result()
  def process_handshake(state, %{serverHello: server_hello}, noise_key) do
    # Authenticate the server's ephemeral public key into the hash
    state = authenticate(state, server_hello.ephemeral)

    # Compute the shared secret from ECDH and mix into keys
    shared_key = Crypto.shared_key(state.ephemeral_key_pair.private, server_hello.ephemeral)
    state = mix_into_key(state, shared_key)
    state = %{state | handshake_state: :awaiting_server_hello}

    # Decrypt server static, mix, then decrypt + verify the certificate. A GCM
    # auth failure here (corrupt/MITM hello) returns {:error, _} per the spec.
    with {:ok, decrypted_static, state_after_first_decrypt} <-
           decrypt(state, server_hello.static),
         shared_static = Crypto.shared_key(state.ephemeral_key_pair.private, decrypted_static),
         state_after_mix = mix_into_key(state_after_first_decrypt, shared_static),
         {:ok, cert_decoded, state_after_second_decrypt} <-
           decrypt(state_after_mix, server_hello.payload),
         :ok <- verify_certificate(cert_decoded) do
      # Encrypt noise key
      {key_encrypted, state_after_encrypt} = encrypt(state_after_second_decrypt, noise_key.public)

      # Mix noise key with server ephemeral
      noise_shared = Crypto.shared_key(noise_key.private, server_hello.ephemeral)
      final_state = mix_into_key(state_after_encrypt, noise_shared)

      {:ok, key_encrypted, final_state}
    end
  end

  @doc """
  Encode data into protocol frame format.

  Returns {frame_binary, updated_state}.
  """
  @spec encode_frame(noise_state(), binary()) :: encrypt_result()
  def encode_frame(state, data) do
    # Encrypt data if handshake is complete (transport phase)
    {processed_data, state} =
      if state.handshake_state == :transport do
        encrypt(state, data)
      else
        {data, state}
      end

    # Build frame header
    header =
      if state.routing_info do
        routing_size = byte_size(state.routing_info)
        <<"ED", 0, 1, routing_size::16, state.routing_info::binary, state.noise_header::binary>>
      else
        state.noise_header
      end

    # Build frame by concatenating parts
    # Match TypeScript: write length as 3 separate bytes (big-endian)
    data_length = byte_size(processed_data)

    length_bytes = <<
      data_length >>> 16::8,
      data_length >>> 8 &&& 0xFF::8,
      data_length &&& 0xFF::8
    >>

    frame =
      if not state.sent_intro do
        header <> length_bytes <> processed_data
      else
        length_bytes <> processed_data
      end

    new_state = %{state | sent_intro: true}

    {frame, new_state}
  end

  @doc """
  Decode incoming frames and extract messages.

  Returns {:ok, frames, updated_state} where frames is a list of decoded messages.
  """
  @spec decode_frame(noise_state(), binary()) :: {:ok, list(binary()), noise_state()}
  def decode_frame(state, new_data) do
    # Append new data to buffer
    in_bytes = state.in_bytes <> new_data
    frames = []

    # Process complete frames, thread state through recursion
    {remaining_bytes, decoded_frames, final_state} = process_frames(in_bytes, frames, state)

    new_state = %{final_state | in_bytes: remaining_bytes}
    # process_frames accumulates by prepending; reverse to restore arrival order.
    {:ok, Enum.reverse(decoded_frames), new_state}
  end

  # Private helper functions

  # Base case: not enough data for length header
  defp process_frames(in_bytes, frames, state) when byte_size(in_bytes) < 3 do
    {in_bytes, frames, state}
  end

  defp process_frames(in_bytes, frames, state) do
    # Extract frame length using TypeScript format: (byte1 << 16) | (byte2 << 8) | byte3
    <<byte1, byte2, byte3, rest::binary>> = in_bytes
    length = byte1 <<< 16 ||| byte2 <<< 8 ||| byte3

    Logger.debug(
      "Processing Noise frame: length=#{length}, remaining_bytes=#{byte_size(rest)}, frames_so_far=#{length(frames)}"
    )

    cond do
      byte_size(rest) < length ->
        # Not enough data for complete frame
        Logger.debug("Not enough data for complete frame, waiting for more")
        {in_bytes, frames, state}

      true ->
        # Extract frame data
        <<frame_data::binary-size(^length), remaining::binary>> = rest

        Logger.debug(
          "Extracted frame data, remaining=#{byte_size(remaining)} bytes after this frame"
        )

        # Decrypt frame if in transport phase, thread state through
        {processed_frame, updated_state} = decrypt_if_transport(state, frame_data)

        # Continue processing remaining frames with updated state
        process_frames(remaining, [processed_frame | frames], updated_state)
    end
  end

  defp decrypt_if_transport(%{handshake_state: :transport} = state, frame_data) do
    case decrypt(state, frame_data) do
      {:ok, decrypted, new_state} ->
        {decrypted, new_state}

      {:error, reason} ->
        # Propagate instead of silently returning the (still-encrypted) frame
        raise "Transport phase decryption failed: #{inspect(reason)}"
    end
  end

  defp decrypt_if_transport(state, frame_data) do
    {frame_data, state}
  end

  # Verify the server's Noise certificate chain (Baileys noise-handler.ts). Three
  # checks, ALL required:
  #   1. the leaf is signed by the intermediate's key,
  #   2. the intermediate is signed by the pinned WhatsApp root key (@wa_cert_public_key),
  #   3. the intermediate's issuerSerial is the pinned serial (0).
  # Check #2 is what actually authenticates the server as WhatsApp; #1 chains the
  # leaf to it. Signatures are XEd25519 (Crypto.verify = XEdDSA), keyed by a 32-byte
  # Montgomery key — strip a leading 0x05 type byte if present.
  @doc false
  @spec verify_certificate(binary()) :: :ok | {:error, term()}
  def verify_certificate(cert_decoded) do
    with %{intermediate: intermediate, leaf: leaf}
         when not is_nil(intermediate) and not is_nil(leaf) <-
           Amarula.Protocol.Proto.CertChain.decode(cert_decoded),
         %{details: int_details, signature: int_sig}
         when is_binary(int_details) and is_binary(int_sig) <-
           intermediate,
         %{details: leaf_details, signature: leaf_sig}
         when is_binary(leaf_details) and is_binary(leaf_sig) <-
           leaf,
         details = Amarula.Protocol.Proto.CertChain.NoiseCertificate.Details.decode(int_details),
         :ok <- verify_sig(leaf_details, leaf_sig, details.key, :leaf_signature_invalid),
         :ok <-
           verify_sig(int_details, int_sig, @wa_cert_public_key, :intermediate_signature_invalid),
         :ok <-
           check(details.issuerSerial == @wa_cert_serial, {:issuer_serial, details.issuerSerial}) do
      :ok
    else
      {:error, _reason} = err -> err
      other -> {:error, {:invalid_certificate, other}}
    end
  end

  defp verify_sig(data, signature, public_key, reason) do
    check(Crypto.verify(data, signature, strip5(public_key)), reason)
  end

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  # WhatsApp pubkeys are sometimes prefixed with a 0x05 type byte; XEdDSA wants the
  # raw 32-byte Montgomery key.
  defp strip5(<<5, key::binary-size(32)>>), do: key
  defp strip5(<<key::binary-size(32)>>), do: key
  defp strip5(other), do: other
end
