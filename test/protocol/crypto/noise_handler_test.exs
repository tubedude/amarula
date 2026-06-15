defmodule Amarula.Protocol.Crypto.NoiseHandlerTest do
  @moduledoc """
  Unit tests for NoiseHandler state management, focusing on:
  - State transitions through handshake phases
  - Hash chaining correctness
  - Key mixing and derivation
  - Counter management
  - Edge cases and error conditions
  """

  use ExUnit.Case, async: true
  alias Amarula.Protocol.Crypto.{Crypto, NoiseHandler, Constants}

  describe "new/2 - initial state creation" do
    test "creates initial state with correct defaults" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)

      assert state.ephemeral_key_pair == key_pair
      assert state.handshake_state == :init
      assert state.read_counter == 0
      assert state.write_counter == 0
      assert state.sent_intro == false
      assert state.in_bytes == <<>>
      assert state.routing_info == nil
      assert byte_size(state.hash) == 32
      assert byte_size(state.salt) == 32
      assert byte_size(state.enc_key) == 32
      assert byte_size(state.dec_key) == 32
    end

    test "initializes hash correctly from noise mode" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)

      # Hash should be SHA256 of noise mode if noise_mode is not 32 bytes
      noise_mode = Constants.noise_mode()

      expected_initial_hash =
        if byte_size(noise_mode) == 32 do
          noise_mode
        else
          Crypto.sha256(noise_mode)
        end

      # The new/2 function authenticates the header and ephemeral key
      # So we need to recreate that process to verify
      noise_header = Constants.noise_wa_header()
      expected_hash_after_header = Crypto.sha256(expected_initial_hash <> noise_header)
      expected_final_hash = Crypto.sha256(expected_hash_after_header <> key_pair.public)

      assert state.hash == expected_final_hash
    end

    test "accepts routing_info option" do
      key_pair = Crypto.generate_key_pair()
      routing_info = "test_routing"
      state = NoiseHandler.new(key_pair, routing_info: routing_info)

      assert state.routing_info == routing_info
    end

    test "salt is initialized to same value as initial hash" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)

      # Initial salt should equal the pre-authentication hash
      noise_mode = Constants.noise_mode()

      expected_salt =
        if byte_size(noise_mode) == 32, do: noise_mode, else: Crypto.sha256(noise_mode)

      assert state.salt == expected_salt
    end
  end

  describe "authenticate/2 - hash chaining" do
    test "updates hash by concatenating and hashing" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)
      initial_hash = state.hash

      test_data = "test_data"
      updated_state = NoiseHandler.authenticate(state, test_data)

      expected_hash = Crypto.sha256(initial_hash <> test_data)
      assert updated_state.hash == expected_hash
      assert updated_state.hash != initial_hash
    end

    test "chains multiple authentications correctly" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)

      data1 = "first"
      data2 = "second"
      data3 = "third"

      state1 = NoiseHandler.authenticate(state, data1)
      state2 = NoiseHandler.authenticate(state1, data2)
      state3 = NoiseHandler.authenticate(state2, data3)

      # Verify hash chain
      expected_hash1 = Crypto.sha256(state.hash <> data1)
      expected_hash2 = Crypto.sha256(expected_hash1 <> data2)
      expected_hash3 = Crypto.sha256(expected_hash2 <> data3)

      assert state1.hash == expected_hash1
      assert state2.hash == expected_hash2
      assert state3.hash == expected_hash3
    end

    test "does not update hash in transport phase" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)
        |> NoiseHandler.finish_init()

      assert state.handshake_state == :transport
      assert state.hash == <<>>

      # Authenticate should not update hash in transport phase
      updated_state = NoiseHandler.authenticate(state, "test_data")
      assert updated_state.hash == <<>>
    end

    test "preserves other state fields" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)

      updated_state = NoiseHandler.authenticate(state, "test")

      assert updated_state.ephemeral_key_pair == state.ephemeral_key_pair
      assert updated_state.salt == state.salt
      assert updated_state.enc_key == state.enc_key
      assert updated_state.dec_key == state.dec_key
      assert updated_state.read_counter == state.read_counter
      assert updated_state.write_counter == state.write_counter
    end
  end

  describe "mix_into_key/2 - key derivation" do
    test "derives new salt and cipher key using HKDF" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)
      initial_salt = state.salt

      shared_secret = :crypto.strong_rand_bytes(32)
      updated_state = NoiseHandler.mix_into_key(state, shared_secret)

      # Verify HKDF derivation
      expected_derived =
        Crypto.hkdf(shared_secret, Constants.hkdf_output_length(), initial_salt, <<>>)

      {expected_salt, expected_cipher_key} = :erlang.split_binary(expected_derived, 32)

      assert updated_state.salt == expected_salt
      assert updated_state.enc_key == expected_cipher_key
      assert updated_state.dec_key == expected_cipher_key
    end

    test "sets both enc_key and dec_key to same cipher key during handshake" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)
      shared_secret = :crypto.strong_rand_bytes(32)

      updated_state = NoiseHandler.mix_into_key(state, shared_secret)

      assert updated_state.enc_key == updated_state.dec_key
      assert byte_size(updated_state.enc_key) == 32
    end

    test "resets counters to 0" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)

      # Set counters to non-zero values
      state_with_counters = %{state | read_counter: 5, write_counter: 10}

      shared_secret = :crypto.strong_rand_bytes(32)
      updated_state = NoiseHandler.mix_into_key(state_with_counters, shared_secret)

      assert updated_state.read_counter == 0
      assert updated_state.write_counter == 0
    end

    test "transitions handshake_state to :handshake" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)
      assert state.handshake_state == :init

      shared_secret = :crypto.strong_rand_bytes(32)
      updated_state = NoiseHandler.mix_into_key(state, shared_secret)

      assert updated_state.handshake_state == :handshake
    end

    test "can be called multiple times (key ratcheting)" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)

      secret1 = :crypto.strong_rand_bytes(32)
      state1 = NoiseHandler.mix_into_key(state, secret1)

      secret2 = :crypto.strong_rand_bytes(32)
      state2 = NoiseHandler.mix_into_key(state1, secret2)

      secret3 = :crypto.strong_rand_bytes(32)
      state3 = NoiseHandler.mix_into_key(state2, secret3)

      # Each mix should produce different keys
      assert state1.enc_key != state2.enc_key
      assert state2.enc_key != state3.enc_key
      assert state1.salt != state2.salt
      assert state2.salt != state3.salt
    end
  end

  describe "finish_init/1 - handshake completion" do
    test "splits keys for transport phase" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      # Before finish_init, keys are the same
      assert state.enc_key == state.dec_key

      finished_state = NoiseHandler.finish_init(state)

      # After finish_init, keys should be different
      assert finished_state.enc_key != finished_state.dec_key
      assert byte_size(finished_state.enc_key) == 32
      assert byte_size(finished_state.dec_key) == 32
    end

    test "derives keys from final HKDF with empty input" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      finished_state = NoiseHandler.finish_init(state)

      # Verify key derivation
      expected_derived = Crypto.hkdf(<<>>, Constants.hkdf_output_length(), state.salt, <<>>)
      {expected_write_key, expected_read_key} = :erlang.split_binary(expected_derived, 32)

      assert finished_state.enc_key == expected_write_key
      assert finished_state.dec_key == expected_read_key
    end

    test "transitions to transport phase" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      assert state.handshake_state == :handshake

      finished_state = NoiseHandler.finish_init(state)

      assert finished_state.handshake_state == :transport
    end

    test "clears hash" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      assert byte_size(state.hash) == 32

      finished_state = NoiseHandler.finish_init(state)

      assert finished_state.hash == <<>>
    end

    test "resets counters to 0" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      # Set counters to non-zero
      state_with_counters = %{state | read_counter: 7, write_counter: 3}

      finished_state = NoiseHandler.finish_init(state_with_counters)

      assert finished_state.read_counter == 0
      assert finished_state.write_counter == 0
    end
  end

  describe "encrypt/2 - state transitions" do
    test "raises error when called before mix_into_key" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)

      assert state.handshake_state == :init

      assert_raise RuntimeError, ~r/Cannot encrypt before keys are established/, fn ->
        NoiseHandler.encrypt(state, "test data")
      end
    end

    test "increments write_counter after encryption" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      assert state.write_counter == 0

      {_encrypted1, state1} = NoiseHandler.encrypt(state, "message 1")
      assert state1.write_counter == 1

      {_encrypted2, state2} = NoiseHandler.encrypt(state1, "message 2")
      assert state2.write_counter == 2

      {_encrypted3, state3} = NoiseHandler.encrypt(state2, "message 3")
      assert state3.write_counter == 3
    end

    test "updates hash with ciphertext during handshake phase" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      assert state.handshake_state == :handshake
      initial_hash = state.hash

      {encrypted, updated_state} = NoiseHandler.encrypt(state, "test")

      expected_hash = Crypto.sha256(initial_hash <> encrypted)
      assert updated_state.hash == expected_hash
    end

    test "does not update hash in transport phase" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)
        |> NoiseHandler.finish_init()

      assert state.handshake_state == :transport
      assert state.hash == <<>>

      {_encrypted, updated_state} = NoiseHandler.encrypt(state, "test")

      # Hash should remain empty in transport phase
      assert updated_state.hash == <<>>
    end

    test "produces different ciphertext with incrementing counter" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      plaintext = "same message"

      {encrypted1, state1} = NoiseHandler.encrypt(state, plaintext)
      {encrypted2, _state2} = NoiseHandler.encrypt(state1, plaintext)

      # Same plaintext should produce different ciphertext due to different counters/IVs
      assert encrypted1 != encrypted2
    end
  end

  describe "decrypt/2 - state transitions" do
    test "increments write_counter during handshake phase" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      assert state.handshake_state == :handshake
      assert state.write_counter == 0

      # Encrypt to get valid ciphertext
      {ciphertext, state_after_encrypt} = NoiseHandler.encrypt(state, "test")

      # Decrypt uses write_counter during handshake
      assert state_after_encrypt.write_counter == 1

      # Create a fresh state with the same key to simulate receiving party
      fresh_state = %{state | write_counter: 0}
      {:ok, _decrypted, state_after_decrypt} = NoiseHandler.decrypt(fresh_state, ciphertext)

      assert state_after_decrypt.write_counter == 1
    end

    test "increments read_counter during transport phase" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)
        |> NoiseHandler.finish_init()

      assert state.handshake_state == :transport
      assert state.read_counter == 0

      # Encrypt to get valid ciphertext
      {ciphertext, _} = NoiseHandler.encrypt(state, "test")

      # Simulate receiving: create fresh state with swapped keys
      receiver_state = %{
        state
        | enc_key: state.dec_key,
          dec_key: state.enc_key,
          read_counter: 0,
          write_counter: 0
      }

      {:ok, _decrypted, state_after_decrypt} = NoiseHandler.decrypt(receiver_state, ciphertext)

      assert state_after_decrypt.read_counter == 1
    end

    test "updates hash with ciphertext during handshake" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      {ciphertext, _state_after_encrypt} = NoiseHandler.encrypt(state, "test")

      # Create fresh state for decryption
      fresh_state = %{state | write_counter: 0}
      initial_hash = fresh_state.hash

      {:ok, _decrypted, state_after_decrypt} = NoiseHandler.decrypt(fresh_state, ciphertext)

      expected_hash = Crypto.sha256(initial_hash <> ciphertext)
      assert state_after_decrypt.hash == expected_hash
    end

    test "returns error on decryption failure" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      # Invalid ciphertext
      invalid_ciphertext = :crypto.strong_rand_bytes(32)

      result = NoiseHandler.decrypt(state, invalid_ciphertext)

      assert {:error, _reason} = result
    end
  end

  describe "state transition correctness" do
    test "full handshake state progression: init -> handshake -> transport" do
      key_pair = Crypto.generate_key_pair()

      # Step 1: Initial state
      state1 = NoiseHandler.new(key_pair)
      assert state1.handshake_state == :init

      # Step 2: After first mix_into_key (e.g., after DH with server ephemeral)
      shared_secret1 = :crypto.strong_rand_bytes(32)
      state2 = NoiseHandler.mix_into_key(state1, shared_secret1)
      assert state2.handshake_state == :handshake

      # Step 3: After second mix_into_key (e.g., after DH with server static)
      shared_secret2 = :crypto.strong_rand_bytes(32)
      state3 = NoiseHandler.mix_into_key(state2, shared_secret2)
      assert state3.handshake_state == :handshake

      # Step 4: After finish_init (Split operation)
      state4 = NoiseHandler.finish_init(state3)
      assert state4.handshake_state == :transport
    end

    test "counters reset properly at key transitions" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)

      # Simulate some counter increments (shouldn't happen in init, but testing reset)
      state = %{state | write_counter: 5, read_counter: 3}

      # mix_into_key should reset counters
      shared_secret = :crypto.strong_rand_bytes(32)
      state = NoiseHandler.mix_into_key(state, shared_secret)
      assert state.write_counter == 0
      assert state.read_counter == 0

      # Increment counters during handshake
      {_, state} = NoiseHandler.encrypt(state, "msg1")
      {_, state} = NoiseHandler.encrypt(state, "msg2")
      assert state.write_counter == 2

      # finish_init should reset counters
      state = NoiseHandler.finish_init(state)
      assert state.write_counter == 0
      assert state.read_counter == 0
    end

    test "hash evolution through state transitions" do
      key_pair = Crypto.generate_key_pair()

      state = NoiseHandler.new(key_pair)
      hash1 = state.hash
      assert byte_size(hash1) == 32

      # Authenticate adds to hash
      state = NoiseHandler.authenticate(state, "data1")
      hash2 = state.hash
      assert hash2 != hash1
      assert byte_size(hash2) == 32

      # mix_into_key preserves hash
      shared_secret = :crypto.strong_rand_bytes(32)
      state = NoiseHandler.mix_into_key(state, shared_secret)
      assert state.hash == hash2

      # Encryption updates hash during handshake
      {_, state} = NoiseHandler.encrypt(state, "msg")
      hash3 = state.hash
      assert hash3 != hash2
      assert byte_size(hash3) == 32

      # finish_init clears hash
      state = NoiseHandler.finish_init(state)
      assert state.hash == <<>>
    end
  end

  describe "edge cases" do
    test "handles empty data in authenticate" do
      key_pair = Crypto.generate_key_pair()
      state = NoiseHandler.new(key_pair)
      initial_hash = state.hash

      updated_state = NoiseHandler.authenticate(state, <<>>)

      expected_hash = Crypto.sha256(initial_hash <> <<>>)
      assert updated_state.hash == expected_hash
    end

    test "handles empty plaintext in encrypt" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      {encrypted, updated_state} = NoiseHandler.encrypt(state, <<>>)

      # Should produce ciphertext with GCM tag even for empty plaintext
      assert is_binary(encrypted)
      assert byte_size(encrypted) > 0
      assert updated_state.write_counter == 1
    end

    test "handles large plaintext in encrypt" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)

      # 1 MB of data
      large_plaintext = :crypto.strong_rand_bytes(1024 * 1024)

      {encrypted, updated_state} = NoiseHandler.encrypt(state, large_plaintext)

      assert is_binary(encrypted)
      assert byte_size(encrypted) > byte_size(large_plaintext)
      assert updated_state.write_counter == 1
    end

    test "counter overflow behavior (high counter values)" do
      key_pair = Crypto.generate_key_pair()
      shared_secret = :crypto.strong_rand_bytes(32)

      state =
        NoiseHandler.new(key_pair)
        |> NoiseHandler.mix_into_key(shared_secret)
        |> NoiseHandler.finish_init()

      # Set counter to near max value
      # 24-bit max value
      high_counter = 0xFFFFFF
      state_with_high_counter = %{state | write_counter: high_counter}

      # Should still work (Erlang integers don't overflow)
      {_encrypted, updated_state} = NoiseHandler.encrypt(state_with_high_counter, "test")

      assert updated_state.write_counter == high_counter + 1
    end
  end

  describe "verify_certificate/1" do
    alias Amarula.Protocol.Proto.CertChain
    alias Amarula.Protocol.Proto.CertChain.NoiseCertificate

    # Build a cert chain. `int_key` signs the leaf; the intermediate is signed by
    # `root_priv` (defaults to a NON-WhatsApp key, so the pinned-root check fails).
    defp build_chain(opts \\ []) do
      int = Crypto.generate_key_pair()
      root = Crypto.generate_key_pair()
      root_priv = Keyword.get(opts, :root_priv, root.private)
      serial = Keyword.get(opts, :serial, 0)

      int_details =
        CertChain.NoiseCertificate.Details.encode(%CertChain.NoiseCertificate.Details{
          serial: 1,
          issuerSerial: serial,
          key: int.public
        })

      leaf_details = "leaf-details-bytes"

      leaf = %NoiseCertificate{
        details: leaf_details,
        signature: Keyword.get(opts, :leaf_sig, Crypto.sign(leaf_details, int.private))
      }

      intermediate = %NoiseCertificate{
        details: int_details,
        signature: Keyword.get(opts, :int_sig, Crypto.sign(int_details, root_priv))
      }

      CertChain.encode(%CertChain{leaf: leaf, intermediate: intermediate})
    end

    test "rejects a chain whose intermediate is not signed by the pinned WA root" do
      # Leaf signature is valid, but the intermediate is signed by a random key.
      assert {:error, :intermediate_signature_invalid} =
               NoiseHandler.verify_certificate(build_chain())
    end

    test "rejects a tampered leaf signature" do
      assert {:error, :leaf_signature_invalid} =
               NoiseHandler.verify_certificate(
                 build_chain(leaf_sig: :crypto.strong_rand_bytes(64))
               )
    end

    # NOTE: a positive (accept) case can't be unit-tested — it requires a chain whose
    # intermediate is signed by WhatsApp's private root key, which we don't have. The
    # real WA cert is verified by the live handshake; these tests prove the chain is
    # REJECTED when the pinned-root or leaf signatures don't hold.
  end
end
