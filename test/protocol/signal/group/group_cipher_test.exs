defmodule Amarula.Protocol.Signal.Group.GroupCipherTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.Group.{
    GroupCipher,
    GroupSessionBuilder,
    KeyHelper,
    SenderKeyDistributionMessage,
    SenderKeyName,
    SenderKeyRecord,
    SenderKeyState,
    SenderKeyStore
  }

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_sk_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    name = SenderKeyName.new("group1", "55119", 0)
    {:ok, dir: dir, name: name}
  end

  defp make_state(key_id \\ 1) do
    {pub, priv} = KeyHelper.generate_sender_signing_key()
    seed = KeyHelper.generate_sender_key()
    SenderKeyState.new(key_id, 0, seed, %{public: pub, private: priv})
  end

  # Sender creates its own sender key, returns {sender_store, receiver_store}
  # where the receiver has processed the sender's SKDM — mirrors the real flow.
  defp paired_stores(dir, name) do
    sender_store = SenderKeyStore.build(Amarula.TestConn.new(dir, :send))
    receiver_store = SenderKeyStore.build(Amarula.TestConn.new(dir, :recv))
    author = "#{name.sender.id}@s.whatsapp.net"

    builder = GroupSessionBuilder.new(sender_store)

    {:ok, skdm} =
      GroupSessionBuilder.create_sender_key_distribution_message(
        builder,
        sender_store,
        name.group_id,
        author
      )

    # The wire carries skdm.serialized ([version][protobuf]) as
    # axolotlSenderKeyDistributionMessage.
    item = %{
      groupId: name.group_id,
      axolotlSenderKeyDistributionMessage: skdm.serialized
    }

    recv_builder = GroupSessionBuilder.new(receiver_store)

    :ok =
      GroupSessionBuilder.process_sender_key_distribution_message(
        recv_builder,
        receiver_store,
        item,
        author
      )

    {sender_store, receiver_store}
  end

  describe "SenderKeyStore.build/1" do
    test "load returns :not_found for unknown key", %{dir: dir, name: name} do
      store = SenderKeyStore.build(Amarula.TestConn.new(dir))
      assert {:error, :not_found} = store.load_sender_key.(name)
    end

    test "store then load round-trips", %{dir: dir, name: name} do
      store = SenderKeyStore.build(Amarula.TestConn.new(dir))
      record = SenderKeyRecord.new() |> SenderKeyRecord.add_sender_key_state(make_state())
      :ok = store.store_sender_key.(name, record)
      {:ok, loaded} = store.load_sender_key.(name)
      assert loaded == record
    end

    test "different names use separate files", %{dir: dir} do
      store = SenderKeyStore.build(Amarula.TestConn.new(dir))
      n1 = SenderKeyName.new("g1", "alice", 0)
      n2 = SenderKeyName.new("g1", "bob", 0)
      r1 = SenderKeyRecord.new() |> SenderKeyRecord.add_sender_key_state(make_state(1))
      r2 = SenderKeyRecord.new() |> SenderKeyRecord.add_sender_key_state(make_state(2))

      :ok = store.store_sender_key.(n1, r1)
      :ok = store.store_sender_key.(n2, r2)

      {:ok, loaded1} = store.load_sender_key.(n1)
      {:ok, loaded2} = store.load_sender_key.(n2)
      assert loaded1 == r1
      assert loaded2 == r2
    end
  end

  describe "GroupCipher.decrypt/3 — no sender key" do
    test "returns error when no record stored", %{dir: dir, name: name} do
      store = SenderKeyStore.build(Amarula.TestConn.new(dir))
      assert {:error, _} = GroupCipher.decrypt(store, name, <<1, 2, 3>>)
    end
  end

  describe "encrypt/decrypt across SKDM-paired stores" do
    test "single message", %{dir: dir, name: name} do
      {sender_store, receiver_store} = paired_stores(dir, name)

      {:ok, ciphertext} = GroupCipher.encrypt(sender_store, name, "hello group")
      {:ok, plaintext} = GroupCipher.decrypt(receiver_store, name, ciphertext)
      assert plaintext == "hello group"
    end

    test "multiple messages advance chain key", %{dir: dir, name: name} do
      {sender_store, receiver_store} = paired_stores(dir, name)
      messages = ["first", "second", "third"]

      ciphertexts =
        Enum.map(messages, fn msg ->
          {:ok, ct} = GroupCipher.encrypt(sender_store, name, msg)
          ct
        end)

      decrypted =
        Enum.map(ciphertexts, fn ct ->
          {:ok, pt} = GroupCipher.decrypt(receiver_store, name, ct)
          pt
        end)

      assert decrypted == messages
    end

    test "out-of-order delivery uses skipped message keys", %{dir: dir, name: name} do
      {sender_store, receiver_store} = paired_stores(dir, name)

      {:ok, ct1} = GroupCipher.encrypt(sender_store, name, "first")
      {:ok, ct2} = GroupCipher.encrypt(sender_store, name, "second")

      {:ok, pt2} = GroupCipher.decrypt(receiver_store, name, ct2)
      {:ok, pt1} = GroupCipher.decrypt(receiver_store, name, ct1)

      assert pt2 == "second"
      assert pt1 == "first"
    end

    test "replaying a consumed message fails", %{dir: dir, name: name} do
      {sender_store, receiver_store} = paired_stores(dir, name)

      {:ok, ct} = GroupCipher.encrypt(sender_store, name, "once")
      {:ok, _} = GroupCipher.decrypt(receiver_store, name, ct)

      assert {:error, _} = GroupCipher.decrypt(receiver_store, name, ct)
    end

    test "tampered signature fails verification", %{dir: dir, name: name} do
      {sender_store, receiver_store} = paired_stores(dir, name)

      {:ok, ct} = GroupCipher.encrypt(sender_store, name, "intact")
      # Flip a bit in the signature (last 64 bytes) — protobuf stays valid,
      # XEd25519 verification must fail.
      head_len = byte_size(ct) - 1
      <<head::binary-size(^head_len), last>> = ct
      tampered = <<head::binary, bxor(last, 1)>>

      # The failure is a signature failure — it must NOT be relabeled as a
      # parse error (only from_serialized failures get that label).
      assert {:error, reason} = GroupCipher.decrypt(receiver_store, name, tampered)
      assert reason == "Invalid signature"
    end

    test "an unparseable blob reports a parse error", %{dir: dir, name: name} do
      {_sender_store, receiver_store} = paired_stores(dir, name)

      # Too short to be [version][protobuf][64-byte signature]
      assert {:error, reason} = GroupCipher.decrypt(receiver_store, name, <<1, 2, 3>>)
      assert reason =~ "Failed to parse sender key message"
    end
  end

  describe "wire format" do
    test "skmsg is [0x33][protobuf][64-byte signature]", %{dir: dir, name: name} do
      {sender_store, _} = paired_stores(dir, name)
      {:ok, ct} = GroupCipher.encrypt(sender_store, name, "wire")

      assert <<0x33, _rest::binary>> = ct
      body_len = byte_size(ct) - 1 - 64
      <<_v, body::binary-size(^body_len), _sig::binary-size(64)>> = ct

      msg = Amarula.Protocol.Proto.SenderKeyMessage.decode(body)
      assert is_integer(msg.id)
      assert is_integer(msg.iteration)
      assert is_binary(msg.ciphertext)
    end

    test "SKDM serialized is [0x33][protobuf]", %{dir: dir, name: name} do
      sender_store = SenderKeyStore.build(Amarula.TestConn.new(dir))
      builder = GroupSessionBuilder.new(sender_store)

      {:ok, skdm} =
        GroupSessionBuilder.create_sender_key_distribution_message(
          builder,
          sender_store,
          name.group_id,
          "#{name.sender.id}@s.whatsapp.net"
        )

      serialized = skdm.serialized
      assert <<0x33, body::binary>> = serialized

      decoded = Amarula.Protocol.Proto.SenderKeyDistributionMessage.decode(body)
      assert decoded.id == skdm.id
      assert decoded.iteration == skdm.iteration
      assert decoded.chainKey == skdm.chain_key
      assert decoded.signingKey == skdm.signature_key
      # signing key travels in wire form (0x05-prefixed, 33 bytes)
      assert <<5, _::binary-size(32)>> = decoded.signingKey
    end
  end

  defp bxor(a, b), do: Bitwise.bxor(a, b)
end
