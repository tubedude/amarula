defmodule Amarula.NoiseProtocolTest do
  @moduledoc """
  Integration test for Noise Protocol implementation.
  """

  use ExUnit.Case, async: false
  alias Amarula.Protocol.Crypto.{Crypto, NoiseHandler, Constants}
  alias Amarula.Protocol.Auth.AuthUtils

  test "complete crypto flow works" do
    # Test key generation and shared secret
    key_pair1 = Crypto.generate_key_pair()
    key_pair2 = Crypto.generate_key_pair()
    shared = Crypto.shared_key(key_pair1.private, key_pair2.public)

    assert byte_size(shared) == 32

    # Test noise handler
    noise_state = NoiseHandler.new(key_pair1)

    # Establish valid encryption keys using mix_into_key
    state_with_keys = NoiseHandler.mix_into_key(noise_state, shared)

    # Transition to transport phase for proper encryption/decryption
    # Create two separate states to simulate client and server
    client_state = NoiseHandler.finish_init(state_with_keys)

    test_data = "Hello, Noise!"

    # Encrypt with client state
    {encrypted, _updated_client_state} = NoiseHandler.encrypt(client_state, test_data)

    # Verify encryption works at least
    assert is_binary(encrypted)
    # Should have GCM tag
    assert byte_size(encrypted) > byte_size(test_data)

    # Note: Decryption test is skipped here because we'd need matching server state
    # The actual handshake test would verify this with proper state synchronization
    # In a real scenario, both client and server derive shared keys from the handshake
    # and then can decrypt each other's messages

    # Test auth credentials
    auth_creds = AuthUtils.init_auth_creds()
    assert is_integer(auth_creds.registration_id)

    # Test constants
    assert Constants.noise_mode() == "Noise_XX_25519_AESGCM_SHA256\0\0\0\0"
    assert Constants.dict_version() == 3
  end

  test "noise state hash concatenation works with various data types" do
    # This test verifies that authenticate works with different hash initializations

    key_pair = Crypto.generate_key_pair()

    # Create noise state normally
    noise_state = NoiseHandler.new(key_pair)

    # Verify that hash is a bitstring
    assert is_bitstring(noise_state.hash)

    # Test authentication with binary data
    test_data = :crypto.strong_rand_bytes(32)
    updated_state = NoiseHandler.authenticate(noise_state, test_data)

    # Verify the state was updated correctly
    assert is_bitstring(updated_state.hash)
    assert updated_state.hash != noise_state.hash

    # Test multiple concatenations
    test_data2 = :crypto.strong_rand_bytes(16)
    updated_state2 = NoiseHandler.authenticate(updated_state, test_data2)
    assert is_bitstring(updated_state2.hash)
  end

  test "mix_into_key uses same key during handshake" do
    # Create a noise state
    key_pair = Crypto.generate_key_pair()
    noise_state = NoiseHandler.new(key_pair)

    # Mix in a random shared secret (simulating server ephemeral)
    shared_secret = :crypto.strong_rand_bytes(32)
    updated_state = NoiseHandler.mix_into_key(noise_state, shared_secret)

    # During handshake, enc_key and dec_key should be THE SAME
    assert updated_state.enc_key == updated_state.dec_key,
           "enc_key and dec_key should be the same during handshake (before finish_init)"

    # Both keys are 32 bytes
    assert byte_size(updated_state.enc_key) == 32
    assert byte_size(updated_state.dec_key) == 32

    # Verify HKDF derivation
    derived_key =
      Crypto.hkdf(shared_secret, Constants.hkdf_output_length(), noise_state.salt, <<>>)

    {_new_salt, expected_cipher_key} = :erlang.split_binary(derived_key, 32)

    # Both should equal the cipher key (second 32 bytes)
    assert updated_state.enc_key == expected_cipher_key
    assert updated_state.dec_key == expected_cipher_key

    # The salt should be updated
    assert updated_state.salt != noise_state.salt
    assert byte_size(updated_state.salt) == 32

    # After finish_init, keys should split
    finished_state = NoiseHandler.finish_init(updated_state)

    assert finished_state.enc_key != finished_state.dec_key,
           "enc_key and dec_key should be different after finish_init (Split operation)"
  end

  test "transport encryption after key establishment" do
    # This test verifies that transport encryption works with properly established keys
    # without needing a full handshake fixture

    key_pair = Crypto.generate_key_pair()
    shared_secret = :crypto.strong_rand_bytes(32)

    # Simulate handshake completion by establishing valid keys and finishing init
    state =
      NoiseHandler.new(key_pair)
      |> NoiseHandler.mix_into_key(shared_secret)
      |> NoiseHandler.finish_init()

    # Verify handshake state is :transport
    assert state.handshake_state == :transport

    # Now test transport encryption with proper state chaining
    test_payload = "Hello, WhatsApp!"
    {encrypted_payload, state2} = NoiseHandler.encrypt(state, test_payload)

    # At least verify encryption works
    assert is_binary(encrypted_payload)
    assert byte_size(encrypted_payload) > byte_size(test_payload)

    # Test multiple messages - counters should increment properly
    test_payload2 = "Second message"
    {encrypted_payload2, state3} = NoiseHandler.encrypt(state2, test_payload2)

    assert is_binary(encrypted_payload2)
    # Verify write counter incremented
    # Should have incremented twice
    assert state3.write_counter == 2
  end

  test "process_handshake returns {:error, _} on a corrupt serverHello (no raise)" do
    # A garbage/MITM'd static or payload fails GCM auth inside process_handshake;
    # that must surface as the spec'd error tuple, not a MatchError crash.
    key_pair = Crypto.generate_key_pair()
    noise_key = Crypto.generate_key_pair()
    state = NoiseHandler.new(key_pair)

    server_hello = %{
      ephemeral: Crypto.generate_key_pair().public,
      static: :crypto.strong_rand_bytes(48),
      payload: :crypto.strong_rand_bytes(64)
    }

    assert {:error, _} =
             NoiseHandler.process_handshake(state, %{serverHello: server_hello}, noise_key)
  end

  test "state threading works correctly in decode_frame" do
    # decode_frame must thread the noise state through multiple encrypted frames
    # in one buffer, advancing read_counter once per frame. In transport phase
    # frames are always encrypted, so we build them with a peer "sender" whose
    # write key/counter mirror the receiver's read key/counter.
    key_pair = Crypto.generate_key_pair()
    shared_secret = :crypto.strong_rand_bytes(32)

    receiver =
      NoiseHandler.new(key_pair)
      |> NoiseHandler.mix_into_key(shared_secret)
      |> NoiseHandler.finish_init()

    # Sender encrypts with the same key the receiver decrypts with (dec_key),
    # starting from read_counter 0 — mirroring the WhatsApp server side.
    # sent_intro: true so transport frames carry no NOISE_HEADER, just length+ciphertext.
    sender = %{
      receiver
      | enc_key: receiver.dec_key,
        write_counter: receiver.read_counter,
        sent_intro: true
    }

    test_data1 = "Test frame 1"
    test_data2 = "Test frame 2"

    {cipher1, sender} = NoiseHandler.encode_frame(sender, test_data1)
    {cipher2, _sender} = NoiseHandler.encode_frame(sender, test_data2)
    combined_frames = cipher1 <> cipher2

    {:ok, decoded_frames, final_state} = NoiseHandler.decode_frame(receiver, combined_frames)

    # Both frames decrypt back to the originals, in order
    assert length(decoded_frames) == 2
    assert Enum.at(decoded_frames, 0) == test_data1
    assert Enum.at(decoded_frames, 1) == test_data2

    # read_counter advanced once per decrypted frame
    assert final_state.read_counter == receiver.read_counter + 2
  end
end
