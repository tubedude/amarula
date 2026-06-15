defmodule Amarula.Protocol.Signal.Group.SenderKeyStateTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Signal.Group.{SenderKeyState, SenderChainKey, SenderMessageKey}

  describe "new/4" do
    test "creates a new SenderKeyState" do
      sender_key_id = 123
      iteration = 5
      chain_key_seed = :crypto.strong_rand_bytes(32)

      signing_key = %{
        public: :crypto.strong_rand_bytes(32),
        private: :crypto.strong_rand_bytes(32)
      }

      state = SenderKeyState.new(sender_key_id, iteration, chain_key_seed, signing_key)

      assert state.sender_key_id == sender_key_id
      assert SenderChainKey.get_iteration(state.sender_chain_key) == iteration
      assert state.sender_signing_key == signing_key
      assert state.sender_message_keys == []
    end
  end

  describe "get_key_id/1" do
    test "returns the sender key ID" do
      state = create_test_state()
      assert SenderKeyState.get_key_id(state) == 123
    end
  end

  describe "get_sender_chain_key/1" do
    test "returns the sender chain key" do
      state = create_test_state()
      chain_key = SenderKeyState.get_sender_chain_key(state)

      assert %SenderChainKey{} = chain_key
      assert SenderChainKey.get_iteration(chain_key) == 5
    end
  end

  describe "set_sender_chain_key/2" do
    test "sets a new sender chain key" do
      state = create_test_state()
      new_chain_key = SenderChainKey.new(10, :crypto.strong_rand_bytes(32))

      updated_state = SenderKeyState.set_sender_chain_key(state, new_chain_key)

      assert SenderKeyState.get_sender_chain_key(updated_state) == new_chain_key
    end
  end

  describe "get_signing_key_public/1" do
    test "returns the public signing key" do
      public_key = :crypto.strong_rand_bytes(32)
      signing_key = %{public: public_key, private: :crypto.strong_rand_bytes(32)}
      state = SenderKeyState.new(123, 5, :crypto.strong_rand_bytes(32), signing_key)

      assert SenderKeyState.get_signing_key_public(state) == public_key
    end
  end

  describe "get_signing_key_private/1" do
    test "returns the private signing key" do
      private_key = :crypto.strong_rand_bytes(32)
      signing_key = %{public: :crypto.strong_rand_bytes(32), private: private_key}
      state = SenderKeyState.new(123, 5, :crypto.strong_rand_bytes(32), signing_key)

      assert SenderKeyState.get_signing_key_private(state) == private_key
    end

    test "returns nil when private key is nil" do
      signing_key = %{public: :crypto.strong_rand_bytes(32), private: nil}
      state = SenderKeyState.new(123, 5, :crypto.strong_rand_bytes(32), signing_key)

      assert SenderKeyState.get_signing_key_private(state) == nil
    end
  end

  describe "add_sender_message_key/2" do
    test "adds a message key to the state" do
      state = create_test_state()
      message_key = SenderMessageKey.new(1, :crypto.strong_rand_bytes(32))

      updated_state = SenderKeyState.add_sender_message_key(state, message_key)

      assert length(updated_state.sender_message_keys) == 1
      assert hd(updated_state.sender_message_keys) == message_key
    end

    test "limits message keys to max count" do
      state = create_test_state()

      # Add more than max message keys
      updated_state =
        Enum.reduce(1..2001, state, fn i, acc ->
          message_key = SenderMessageKey.new(i, :crypto.strong_rand_bytes(32))
          SenderKeyState.add_sender_message_key(acc, message_key)
        end)

      assert length(updated_state.sender_message_keys) == 2000
    end
  end

  describe "has_sender_message_key/2" do
    test "returns true when message key exists" do
      state = create_test_state()
      message_key = SenderMessageKey.new(5, :crypto.strong_rand_bytes(32))
      updated_state = SenderKeyState.add_sender_message_key(state, message_key)

      assert SenderKeyState.has_sender_message_key(updated_state, 5)
    end

    test "returns false when message key does not exist" do
      state = create_test_state()
      refute SenderKeyState.has_sender_message_key(state, 5)
    end
  end

  describe "remove_sender_message_key/2" do
    test "removes and returns existing message key" do
      state = create_test_state()
      message_key = SenderMessageKey.new(5, :crypto.strong_rand_bytes(32))
      updated_state = SenderKeyState.add_sender_message_key(state, message_key)

      {removed_key, final_state} = SenderKeyState.remove_sender_message_key(updated_state, 5)

      assert removed_key == message_key
      assert length(final_state.sender_message_keys) == 0
    end

    test "returns nil when message key does not exist" do
      state = create_test_state()

      {removed_key, final_state} = SenderKeyState.remove_sender_message_key(state, 5)

      assert removed_key == nil
      assert final_state == state
    end
  end

  describe "valid?/1" do
    test "returns true for valid state" do
      state = create_test_state()
      assert SenderKeyState.valid?(state)
    end

    test "returns false for negative key ID" do
      state =
        SenderKeyState.new(-1, 5, :crypto.strong_rand_bytes(32), %{
          public: :crypto.strong_rand_bytes(32),
          private: nil
        })

      refute SenderKeyState.valid?(state)
    end

    test "returns false for empty public key" do
      state =
        SenderKeyState.new(123, 5, :crypto.strong_rand_bytes(32), %{public: <<>>, private: nil})

      refute SenderKeyState.valid?(state)
    end
  end

  # Helper function to create a test state
  defp create_test_state do
    signing_key = %{public: :crypto.strong_rand_bytes(32), private: :crypto.strong_rand_bytes(32)}
    SenderKeyState.new(123, 5, :crypto.strong_rand_bytes(32), signing_key)
  end
end
