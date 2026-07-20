defmodule Amarula.Protocol.Messages.MessageDecryptorTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Messages.MessageDecryptor
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.{DecryptError, SessionStore}

  alias Amarula.Protocol.Signal.Group.{
    GroupCipher,
    GroupSessionBuilder,
    SenderKeyName,
    SenderKeyStore
  }

  alias Amarula.Protocol.Socket.ConnectionSupervisor
  alias Amarula.Protocol.Binary.Node

  # Fixtures: amarula creds + a real libsignal-encrypted proto.Message wrapped as
  # a pkmsg enc, generated against amarula's bundle. See /tmp generators in the
  # session work. The message is the same WhatsApp self-message shape we see live.
  @creds "test/fixtures/amarula_creds.term" |> File.read!() |> :erlang.binary_to_term()
  @vector "test/fixtures/msg_node_vec.json" |> File.read!() |> JSON.decode!()

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_md_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    instance_id = make_ref()

    # 1:1 decrypt routes through the record's custodian, which lives under this tree.
    {:ok, _custodian_sup} =
      DynamicSupervisor.start_link(
        strategy: :one_for_one,
        name: ConnectionSupervisor.name(instance_id, :custodian_supervisor)
      )

    {:ok, dir: dir, conn: Amarula.TestConn.new(dir), instance_id: instance_id}
  end

  defp h(hex), do: Base.decode16!(hex, case: :lower)

  test "decrypts a message node's pkmsg enc into a proto.Message", %{conn: conn, instance_id: iid} do
    store = SessionStore.build(@creds)

    enc = %Node{
      tag: "enc",
      attrs: %{"type" => @vector["encType"]},
      content: h(@vector["encBody"])
    }

    node = %Node{
      tag: "message",
      attrs: %{"from" => "15550001234:0@s.whatsapp.net", "id" => "ABC", "t" => "1"},
      content: [enc]
    }

    {:ok, [msg], _used_pre_key_ids, []} =
      MessageDecryptor.decrypt_node(node, store: store, conn: conn, instance_id: iid)

    assert msg.conversation == @vector["expectedText"]

    # The session was persisted for the sender's address.
    assert SessionStore.load_session(conn, "15550001234.0") != nil
  end

  test "ignores enc children that fail to decrypt", %{conn: conn, instance_id: iid} do
    store = SessionStore.build(@creds)

    enc = %Node{tag: "enc", attrs: %{"type" => "msg"}, content: <<0x33, 0, 0>>}

    node = %Node{
      tag: "message",
      attrs: %{"from" => "15550001234:0@s.whatsapp.net", "id" => "ABC", "t" => "1"},
      content: [enc]
    }

    # No session exists for a bare msg → nothing decrypted, no crash. The error
    # is surfaced (4th element) so the caller can choose how to ack.
    assert {:ok, [], [], [_error]} =
             MessageDecryptor.decrypt_node(node, store: store, conn: conn, instance_id: iid)
  end

  test "a plaintext enc with undecodable bytes becomes an error entry, no raise", %{
    conn: conn,
    instance_id: iid
  } do
    store = SessionStore.build(@creds)

    # Not a valid protobuf wire encoding → Proto.Message.decode/1 raises, which
    # decrypt_node converts to an error entry rather than crashing.
    enc = %Node{tag: "enc", attrs: %{"type" => "plaintext"}, content: <<0xFF, 0xFF, 0xFF, 0xFF>>}

    node = %Node{
      tag: "message",
      attrs: %{"from" => "15550001234:0@s.whatsapp.net", "id" => "ABC", "t" => "1"},
      content: [enc]
    }

    assert {:ok, [], [], [_error]} =
             MessageDecryptor.decrypt_node(node, store: store, conn: conn, instance_id: iid)
  end

  test "partial failure: the good plaintext enc decodes, the bad one is an error", %{
    conn: conn,
    instance_id: iid
  } do
    store = SessionStore.build(@creds)

    good_bytes = IO.iodata_to_binary(Proto.Message.encode(%Proto.Message{conversation: "hi"}))

    good = %Node{tag: "enc", attrs: %{"type" => "plaintext"}, content: good_bytes}
    bad = %Node{tag: "enc", attrs: %{"type" => "plaintext"}, content: <<0xFF, 0xFF, 0xFF, 0xFF>>}

    node = %Node{
      tag: "message",
      attrs: %{"from" => "15550001234:0@s.whatsapp.net", "id" => "ABC", "t" => "1"},
      content: [good, bad]
    }

    assert {:ok, [msg], [], [_error]} =
             MessageDecryptor.decrypt_node(node, store: store, conn: conn, instance_id: iid)

    assert msg.conversation == "hi"
  end

  # #35: an skmsg redelivery whose skipped sender-message-key was already
  # consumed must reach connection.ex's duplicate_decrypt_error?/1 as a
  # %DecryptError{reason: :key_unavailable} (tagged at the source, in
  # GroupCipher.decrypt/3 — see group_cipher_test.exs), the same shape the 1:1
  # path already produces, so it gets ack'd as delivered instead of falling
  # through to retry + nack on every occurrence. This end-to-end test proves
  # the struct survives the full decrypt_node/2 pipeline unmangled.
  test "an skmsg redelivery past a consumed skipped key classifies as :key_unavailable (#35)",
       %{conn: conn, instance_id: iid} do
    group = "12345-6789@g.us"
    author = "15550005678:0@s.whatsapp.net"
    name = SenderKeyName.new(group, "15550005678", 0)

    sender_dir =
      Path.join(System.tmp_dir!(), "amarula_md_sender_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(sender_dir) end)
    sender_store = SenderKeyStore.build(Amarula.TestConn.new(sender_dir))
    receiver_store = SenderKeyStore.build(conn)

    sender_builder = GroupSessionBuilder.new(sender_store)

    {:ok, skdm} =
      GroupSessionBuilder.create_sender_key_distribution_message(
        sender_builder,
        sender_store,
        group,
        author
      )

    item = %{groupId: group, axolotlSenderKeyDistributionMessage: skdm.serialized}
    receiver_builder = GroupSessionBuilder.new(receiver_store)

    :ok =
      GroupSessionBuilder.process_sender_key_distribution_message(
        receiver_builder,
        receiver_store,
        item,
        author
      )

    # skmsg plaintext is a padded proto.Message (random-max-16 pad, last byte =
    # pad length), matching what decode_padded/unpad expects on the way back.
    pad = fn msg -> IO.iodata_to_binary(Proto.Message.encode(msg)) <> <<1>> end

    {:ok, ct1} =
      GroupCipher.encrypt(sender_store, name, pad.(%Proto.Message{conversation: "one"}))

    {:ok, ct2} =
      GroupCipher.encrypt(sender_store, name, pad.(%Proto.Message{conversation: "two"}))

    enc = fn ct -> %Node{tag: "enc", attrs: %{"type" => "skmsg"}, content: ct} end

    node = fn ct ->
      %Node{
        tag: "message",
        attrs: %{"from" => group, "participant" => author, "id" => "ABC", "t" => "1"},
        content: [enc.(ct)]
      }
    end

    store = SessionStore.build(@creds)
    opts = [store: store, conn: conn, instance_id: iid]

    # ct2 first caches ct1's skipped key; decrypting ct1 consumes and removes it.
    {:ok, [_msg2], [], []} = MessageDecryptor.decrypt_node(node.(ct2), opts)
    {:ok, [_msg1], [], []} = MessageDecryptor.decrypt_node(node.(ct1), opts)

    assert {:ok, [], [], [%DecryptError{reason: :key_unavailable}]} =
             MessageDecryptor.decrypt_node(node.(ct1), opts)
  end
end
