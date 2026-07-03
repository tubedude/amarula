defmodule Amarula.Protocol.Signal.Group.SenderChainKeyTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Signal.Group.{SenderChainKey, SenderMessageKey}

  describe "new/2" do
    test "creates a new SenderChainKey" do
      iteration = 5
      seed = :crypto.strong_rand_bytes(32)

      chain_key = SenderChainKey.new(iteration, seed)

      assert chain_key.iteration == iteration
      assert chain_key.seed == seed
    end
  end

  describe "get_iteration/1" do
    test "returns the iteration number" do
      chain_key = SenderChainKey.new(42, :crypto.strong_rand_bytes(32))
      assert SenderChainKey.get_iteration(chain_key) == 42
    end
  end

  describe "seed" do
    test "keeps the seed on the struct" do
      seed = :crypto.strong_rand_bytes(32)
      chain_key = SenderChainKey.new(1, seed)

      assert chain_key.seed == seed
    end
  end

  describe "get_next/1" do
    test "generates the next chain key" do
      seed = :crypto.strong_rand_bytes(32)
      chain_key = SenderChainKey.new(5, seed)

      next_key = SenderChainKey.get_next(chain_key)

      assert next_key.iteration == 6
      assert next_key.seed != seed
      assert byte_size(next_key.seed) == 32
    end

    test "generates different seeds for consecutive calls" do
      seed = :crypto.strong_rand_bytes(32)
      chain_key = SenderChainKey.new(1, seed)

      next1 = SenderChainKey.get_next(chain_key)
      next2 = SenderChainKey.get_next(next1)

      assert next1.seed != next2.seed
      assert next1.iteration == 2
      assert next2.iteration == 3
    end
  end

  describe "get_sender_message_key/1" do
    test "generates a message key for current iteration" do
      seed = :crypto.strong_rand_bytes(32)
      chain_key = SenderChainKey.new(10, seed)

      message_key = SenderChainKey.get_sender_message_key(chain_key)

      assert %SenderMessageKey{} = message_key
      assert SenderMessageKey.get_iteration(message_key) == 10
      assert byte_size(SenderMessageKey.get_iv(message_key)) == 16
      assert byte_size(SenderMessageKey.get_cipher_key(message_key)) == 32
    end

    # Key material derives from the seed alone (libsignal HMAC(seed, 0x01));
    # iteration is metadata. Advancing the chain (get_next) changes the seed.
    test "advancing the chain yields different message keys" do
      chain_key1 = SenderChainKey.new(1, :crypto.strong_rand_bytes(32))
      chain_key2 = SenderChainKey.get_next(chain_key1)

      message_key1 = SenderChainKey.get_sender_message_key(chain_key1)
      message_key2 = SenderChainKey.get_sender_message_key(chain_key2)

      assert SenderMessageKey.get_iteration(message_key1) == 1
      assert SenderMessageKey.get_iteration(message_key2) == 2
      assert SenderMessageKey.get_iv(message_key1) != SenderMessageKey.get_iv(message_key2)

      assert SenderMessageKey.get_cipher_key(message_key1) !=
               SenderMessageKey.get_cipher_key(message_key2)
    end
  end

  describe "valid?/1" do
    test "returns true for valid chain key" do
      chain_key = SenderChainKey.new(5, :crypto.strong_rand_bytes(32))
      assert SenderChainKey.valid?(chain_key)
    end

    test "returns false for negative iteration" do
      chain_key = SenderChainKey.new(-1, :crypto.strong_rand_bytes(32))
      refute SenderChainKey.valid?(chain_key)
    end

    test "returns false for wrong seed size" do
      # Wrong size
      chain_key = SenderChainKey.new(1, <<1, 2, 3>>)
      refute SenderChainKey.valid?(chain_key)
    end
  end
end
