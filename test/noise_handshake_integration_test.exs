defmodule Amarula.NoiseHandshakeIntegrationTest do
  use ExUnit.Case
  require Logger
  alias Amarula.Protocol.Crypto.{Crypto, NoiseHandler, Constants}
  alias Amarula.Protocol.Proto

  test "full Noise XX handshake simulation" do
    client_ephemeral_keypair = Crypto.generate_key_pair()
    client_state = NoiseHandler.new(client_ephemeral_keypair)

    noise_mode = Constants.noise_mode()
    noise_header = Constants.noise_wa_header()
    h1 = noise_mode
    h2 = Crypto.sha256(h1 <> noise_header)
    h3 = Crypto.sha256(h2 <> client_ephemeral_keypair.public)

    assert client_state.hash == h3

    server_ephemeral_keypair = Crypto.generate_key_pair()
    server_static_keypair = Crypto.generate_key_pair()
    server_state = %{hash: h3, salt: noise_mode, enc_key: h3, dec_key: h3, counter: 0}

    server_state = simulate_authenticate(server_state, server_ephemeral_keypair.public)
    server_hash_after_authenticate = server_state.hash

    shared_ee =
      Crypto.shared_key(server_ephemeral_keypair.private, client_ephemeral_keypair.public)

    server_state = simulate_mix_into_key(server_state, shared_ee)

    {encrypted_static, server_state} =
      simulate_encrypt(server_state, server_static_keypair.public)

    shared_es = Crypto.shared_key(server_static_keypair.private, client_ephemeral_keypair.public)
    server_state = simulate_mix_into_key(server_state, shared_es)

    cert_payload = generate_test_certificate()
    {encrypted_cert, _server_state_final} = simulate_encrypt(server_state, cert_payload)

    client_state = NoiseHandler.authenticate(client_state, server_ephemeral_keypair.public)
    assert client_state.hash == server_hash_after_authenticate

    client_shared_ee =
      Crypto.shared_key(client_ephemeral_keypair.private, server_ephemeral_keypair.public)

    assert client_shared_ee == shared_ee
    client_state = NoiseHandler.mix_into_key(client_state, client_shared_ee)

    {:ok, decrypted_static, client_state_after_decrypt} =
      NoiseHandler.decrypt(client_state, encrypted_static)

    assert decrypted_static == server_static_keypair.public

    shared_es_client = Crypto.shared_key(client_ephemeral_keypair.private, decrypted_static)
    assert shared_es_client == shared_es

    client_state_after_es =
      NoiseHandler.mix_into_key(client_state_after_decrypt, shared_es_client)

    {:ok, decrypted_cert, client_state_after_cert} =
      NoiseHandler.decrypt(client_state_after_es, encrypted_cert)

    assert validate_certificate(decrypted_cert)

    client_noise_keypair = Crypto.generate_key_pair()

    {_encrypted_noise_key, client_state_after_noise_encrypt} =
      NoiseHandler.encrypt(client_state_after_cert, client_noise_keypair.public)

    shared_se = Crypto.shared_key(client_noise_keypair.private, server_ephemeral_keypair.public)
    client_state_final = NoiseHandler.mix_into_key(client_state_after_noise_encrypt, shared_se)

    client_payload = <<1, 2, 3, 4, 5>>

    {_encrypted_payload, client_state_transport} =
      NoiseHandler.encrypt(client_state_final, client_payload)

    client_state_transport = NoiseHandler.finish_init(client_state_transport)

    assert client_state_transport.handshake_state == :transport
    assert client_state_transport.hash == <<>>
    assert client_state_transport.write_counter == 0
    assert client_state_transport.read_counter == 0

    Logger.info("✓ Full handshake completed successfully!")
  end

  defp simulate_authenticate(state, data) do
    %{state | hash: Crypto.sha256(state.hash <> data)}
  end

  defp simulate_mix_into_key(state, shared_secret) do
    derived_key = Crypto.hkdf(shared_secret, Constants.hkdf_output_length(), state.salt, <<>>)
    {new_salt, cipher_key} = :erlang.split_binary(derived_key, 32)

    Map.merge(state, %{
      salt: new_salt,
      enc_key: cipher_key,
      dec_key: cipher_key,
      counter: 0
    })
  end

  defp simulate_encrypt(state, plaintext) do
    iv = Crypto.generate_iv(state.counter)
    {:ok, ciphertext} = Crypto.aes_encrypt_gcm(plaintext, state.enc_key, iv, state.hash)
    new_hash = Crypto.sha256(state.hash <> ciphertext)

    {ciphertext, Map.merge(state, %{hash: new_hash, counter: state.counter + 1})}
  end

  defp generate_test_certificate do
    details = %Proto.CertChain.NoiseCertificate.Details{
      serial: 0,
      issuerSerial: 0,
      key: <<>>,
      notBefore: 0,
      notAfter: 0
    }

    details_bin = Proto.CertChain.NoiseCertificate.Details.encode(details)

    intermediate = %Proto.CertChain.NoiseCertificate{
      details: details_bin,
      signature: <<>>
    }

    chain = %Proto.CertChain{leaf: nil, intermediate: intermediate}
    Proto.CertChain.encode(chain)
  end

  defp validate_certificate(cert_data) do
    case Proto.CertChain.decode(cert_data) do
      %Proto.CertChain{intermediate: %Proto.CertChain.NoiseCertificate{details: details_bin}}
      when is_binary(details_bin) ->
        %Proto.CertChain.NoiseCertificate.Details{issuerSerial: issuer} =
          Proto.CertChain.NoiseCertificate.Details.decode(details_bin)

        issuer == 0

      _ ->
        false
    end
  end
end
