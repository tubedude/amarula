defmodule Amarula.Protocol.Signal.Group.SenderMessageKeyTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Signal.Group.SenderMessageKey

  describe "new/2" do
    test "creates a new SenderMessageKey" do
      iteration = 42
      seed = :crypto.strong_rand_bytes(32)

      message_key = SenderMessageKey.new(iteration, seed)

      assert message_key.iteration == iteration
      assert message_key.seed == seed
      assert byte_size(message_key.iv) == 16
      assert byte_size(message_key.cipher_key) == 32
    end

    # Key material derives from the seed alone (libsignal HKDF "WhisperGroup");
    # iteration is metadata and does not affect iv/cipher_key.
    test "same seed yields same key material regardless of iteration" do
      seed = :crypto.strong_rand_bytes(32)

      key1 = SenderMessageKey.new(1, seed)
      key2 = SenderMessageKey.new(2, seed)

      assert key1.iteration != key2.iteration
      assert key1.iv == key2.iv
      assert key1.cipher_key == key2.cipher_key
    end

    test "creates different keys for different seeds" do
      seed1 = :crypto.strong_rand_bytes(32)
      seed2 = :crypto.strong_rand_bytes(32)

      key1 = SenderMessageKey.new(1, seed1)
      key2 = SenderMessageKey.new(1, seed2)

      assert key1.iv != key2.iv
      assert key1.cipher_key != key2.cipher_key
    end
  end

  describe "get_iteration/1" do
    test "returns the iteration number" do
      message_key = SenderMessageKey.new(123, :crypto.strong_rand_bytes(32))
      assert SenderMessageKey.get_iteration(message_key) == 123
    end
  end

  describe "get_iv/1" do
    test "returns the IV" do
      message_key = SenderMessageKey.new(1, :crypto.strong_rand_bytes(32))
      iv = SenderMessageKey.get_iv(message_key)

      assert byte_size(iv) == 16
      assert iv == message_key.iv
    end
  end

  describe "get_cipher_key/1" do
    test "returns the cipher key" do
      message_key = SenderMessageKey.new(1, :crypto.strong_rand_bytes(32))
      cipher_key = SenderMessageKey.get_cipher_key(message_key)

      assert byte_size(cipher_key) == 32
      assert cipher_key == message_key.cipher_key
    end
  end

  describe "get_seed/1" do
    test "returns the original seed" do
      seed = :crypto.strong_rand_bytes(32)
      message_key = SenderMessageKey.new(1, seed)

      assert SenderMessageKey.get_seed(message_key) == seed
    end
  end
end
