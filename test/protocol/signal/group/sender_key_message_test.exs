defmodule Amarula.Protocol.Signal.Group.SenderKeyMessageTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Signal.Group.{KeyHelper, SenderKeyMessage}

  describe "new/4" do
    test "creates a new SenderKeyMessage" do
      key_id = 123
      iteration = 5
      ciphertext = :crypto.strong_rand_bytes(64)
      {_public_key, private_key} = KeyHelper.generate_sender_signing_key()

      message = SenderKeyMessage.new(key_id, iteration, ciphertext, private_key)

      assert message.key_id == key_id
      assert message.iteration == iteration
      assert message.ciphertext == ciphertext
      assert byte_size(message.signature) == 64
      assert byte_size(message.serialized) > 0
    end

    test "creates different signatures for different data" do
      key_id = 123
      iteration = 5
      ciphertext1 = :crypto.strong_rand_bytes(64)
      ciphertext2 = :crypto.strong_rand_bytes(64)
      {_public_key, private_key} = KeyHelper.generate_sender_signing_key()

      message1 = SenderKeyMessage.new(key_id, iteration, ciphertext1, private_key)
      message2 = SenderKeyMessage.new(key_id, iteration, ciphertext2, private_key)

      assert message1.signature != message2.signature
      assert message1.serialized != message2.serialized
    end
  end

  describe "from_serialized/1" do
    test "creates message from serialized data" do
      key_id = 123
      iteration = 5
      ciphertext = :crypto.strong_rand_bytes(64)
      {_public_key, private_key} = KeyHelper.generate_sender_signing_key()

      original_message = SenderKeyMessage.new(key_id, iteration, ciphertext, private_key)
      serialized = SenderKeyMessage.serialize(original_message)

      case SenderKeyMessage.from_serialized(serialized) do
        {:ok, reconstructed_message} ->
          assert reconstructed_message.key_id == key_id
          assert reconstructed_message.iteration == iteration
          assert reconstructed_message.ciphertext == ciphertext
          assert reconstructed_message.signature == original_message.signature

        {:error, reason} ->
          flunk("Failed to deserialize message: #{reason}")
      end
    end

    test "returns error for invalid serialized data" do
      invalid_data = <<1, 2, 3>>

      assert {:error, "Serialized message too short"} =
               SenderKeyMessage.from_serialized(invalid_data)
    end

    test "raises for malformed protobuf body (let it crash)" do
      # Long enough to pass the size guard, but the body is not valid protobuf
      malformed_data = :binary.copy(<<0xFF>>, 100)

      assert_raise Protobuf.DecodeError, fn ->
        SenderKeyMessage.from_serialized(malformed_data)
      end
    end
  end

  describe "get_key_id/1" do
    test "returns the key ID" do
      {_public_key, private_key} = KeyHelper.generate_sender_signing_key()
      message = SenderKeyMessage.new(456, 10, :crypto.strong_rand_bytes(32), private_key)
      assert SenderKeyMessage.get_key_id(message) == 456
    end
  end

  describe "get_iteration/1" do
    test "returns the iteration" do
      {_public_key, private_key} = KeyHelper.generate_sender_signing_key()
      message = SenderKeyMessage.new(123, 789, :crypto.strong_rand_bytes(32), private_key)
      assert SenderKeyMessage.get_iteration(message) == 789
    end
  end

  describe "get_ciphertext/1" do
    test "returns the ciphertext" do
      ciphertext = :crypto.strong_rand_bytes(64)
      {_public_key, private_key} = KeyHelper.generate_sender_signing_key()
      message = SenderKeyMessage.new(123, 5, ciphertext, private_key)
      assert SenderKeyMessage.get_ciphertext(message) == ciphertext
    end
  end

  describe "verify_signature/2" do
    test "verifies correct signature" do
      # Generate Ed25519 key pair
      {public_key, private_key} = KeyHelper.generate_sender_signing_key()
      message = SenderKeyMessage.new(123, 5, :crypto.strong_rand_bytes(32), private_key)

      assert :ok = SenderKeyMessage.verify_signature(message, public_key)
    end

    test "rejects incorrect signature" do
      # Generate Ed25519 key pair
      {_public_key, private_key} = KeyHelper.generate_sender_signing_key()
      {wrong_public_key, _wrong_private_key} = KeyHelper.generate_sender_signing_key()
      message = SenderKeyMessage.new(123, 5, :crypto.strong_rand_bytes(32), private_key)

      assert {:error, "Invalid signature"} =
               SenderKeyMessage.verify_signature(message, wrong_public_key)
    end
  end

  describe "serialize/1" do
    test "serializes message to binary" do
      {_public_key, private_key} = KeyHelper.generate_sender_signing_key()
      message = SenderKeyMessage.new(123, 5, :crypto.strong_rand_bytes(32), private_key)
      serialized = SenderKeyMessage.serialize(message)

      assert is_binary(serialized)
      assert byte_size(serialized) > 0
    end
  end

  describe "round-trip serialization" do
    test "serialize and from_serialized are inverse operations" do
      key_id = 999
      iteration = 42
      ciphertext = :crypto.strong_rand_bytes(128)
      {_public_key, private_key} = KeyHelper.generate_sender_signing_key()

      original_message = SenderKeyMessage.new(key_id, iteration, ciphertext, private_key)
      serialized = SenderKeyMessage.serialize(original_message)

      case SenderKeyMessage.from_serialized(serialized) do
        {:ok, reconstructed_message} ->
          assert reconstructed_message.key_id == original_message.key_id
          assert reconstructed_message.iteration == original_message.iteration
          assert reconstructed_message.ciphertext == original_message.ciphertext
          assert reconstructed_message.signature == original_message.signature
          assert reconstructed_message.serialized == original_message.serialized

        {:error, reason} ->
          flunk("Round-trip serialization failed: #{reason}")
      end
    end
  end
end
