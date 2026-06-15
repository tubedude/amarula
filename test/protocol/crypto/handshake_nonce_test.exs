defmodule Amarula.Protocol.Crypto.HandshakeNonceTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Crypto.{NoiseHandler, Crypto, Constants}

  test "handshake decryption uses correct nonce format" do
    # Simulate what the server is doing when it encrypts server_hello.static
    server_static = Crypto.generate_key_pair()
    server_ephemeral = Crypto.generate_key_pair()

    _client_static = Crypto.generate_key_pair()
    client_ephemeral = Crypto.generate_key_pair()

    # Both compute shared secret (DH between ephemerals)
    shared_ee = Crypto.shared_key(client_ephemeral.private, server_ephemeral.public)

    # Initialize both states identically
    noise_mode = Constants.noise_mode()
    initial_hash = :crypto.hash(:sha256, noise_mode)

    client_state =
      %{
        hash: initial_hash,
        salt: initial_hash,
        enc_key: initial_hash,
        dec_key: initial_hash,
        ephemeral_key_pair: client_ephemeral,
        read_counter: 0,
        write_counter: 0,
        handshake_state: :init,
        sent_intro: false,
        in_bytes: <<>>,
        routing_info: nil,
        noise_header: Constants.noise_wa_header()
      }
      |> NoiseHandler.authenticate(Constants.noise_wa_header())
      |> NoiseHandler.authenticate(client_ephemeral.public)
      |> NoiseHandler.authenticate(server_ephemeral.public)
      |> NoiseHandler.mix_into_key(shared_ee)

    server_state =
      %{
        hash: initial_hash,
        salt: initial_hash,
        enc_key: initial_hash,
        dec_key: initial_hash,
        ephemeral_key_pair: server_ephemeral,
        read_counter: 0,
        write_counter: 0,
        handshake_state: :init,
        sent_intro: false,
        in_bytes: <<>>,
        routing_info: nil,
        noise_header: Constants.noise_wa_header()
      }
      |> NoiseHandler.authenticate(Constants.noise_wa_header())
      |> NoiseHandler.authenticate(client_ephemeral.public)
      |> NoiseHandler.authenticate(server_ephemeral.public)
      |> NoiseHandler.mix_into_key(shared_ee)

    assert client_state.enc_key == server_state.enc_key
    assert client_state.hash == server_state.hash

    # Server encrypts its static key with HANDSHAKE nonce format: <<0::64, counter::32-big>>
    handshake_counter = 0
    nonce = <<0::64, handshake_counter::32-big>>
    aad = server_state.hash

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        server_state.enc_key,
        nonce,
        server_static.public,
        aad,
        true
      )

    encrypted_static = ciphertext <> tag

    # Client tries to decrypt using NoiseHandler.decrypt/3
    result = NoiseHandler.decrypt(client_state, encrypted_static, aad)

    case result do
      {:ok, decrypted, _state} ->
        assert decrypted == server_static.public

      {:error, reason} ->
        flunk(
          "Decryption failed: #{inspect(reason)}. NoiseHandler.decrypt is using wrong nonce format during handshake."
        )
    end
  end

  test "nonce construction during handshake vs transport" do
    key_pair = Crypto.generate_key_pair()
    shared = :crypto.strong_rand_bytes(32)

    # Handshake phase: mix into key to derive cipher keys
    handshake_state =
      %{
        NoiseHandler.new(key_pair)
        | # ensure we're in :init and then derive keys
          handshake_state: :init
      }
      |> NoiseHandler.mix_into_key(shared)

    # During handshake, nonce should be 12 bytes: 8 zero bytes + 4-byte big-endian counter
    handshake_nonce = <<0::64, 0::32-big>>
    assert byte_size(handshake_nonce) == 12
    assert handshake_nonce == Crypto.generate_iv(0)

    # After finish_init, transport phase uses independent read/write counters
    transport_state = NoiseHandler.finish_init(handshake_state)
    assert transport_state.handshake_state == :transport
    # Initial counters are zeroed after split
    assert transport_state.read_counter == 0
    assert transport_state.write_counter == 0
    # Ensure IV construction remains 12 bytes
    assert Crypto.generate_iv(transport_state.read_counter) |> byte_size() == 12
  end
end
