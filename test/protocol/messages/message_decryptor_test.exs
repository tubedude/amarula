defmodule Amarula.Protocol.Messages.MessageDecryptorTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Messages.MessageDecryptor
  alias Amarula.Protocol.Signal.SessionStore
  alias Amarula.Protocol.Binary.Node

  # Fixtures: amarula creds + a real libsignal-encrypted proto.Message wrapped as
  # a pkmsg enc, generated against amarula's bundle. See /tmp generators in the
  # session work. The message is the same WhatsApp self-message shape we see live.
  @creds "test/fixtures/amarula_creds.term" |> File.read!() |> :erlang.binary_to_term()
  @vector "test/fixtures/msg_node_vec.json" |> File.read!() |> JSON.decode!()

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_md_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir, conn: Amarula.TestConn.new(dir)}
  end

  defp h(hex), do: Base.decode16!(hex, case: :lower)

  test "decrypts a message node's pkmsg enc into a proto.Message", %{conn: conn} do
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
      MessageDecryptor.decrypt_node(node, store: store, conn: conn)

    assert msg.conversation == @vector["expectedText"]

    # The session was persisted for the sender's address.
    assert SessionStore.load_session(conn, "15550001234.0") != nil
  end

  test "ignores enc children that fail to decrypt", %{conn: conn} do
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
             MessageDecryptor.decrypt_node(node,
               store: store,
               conn: conn
             )
  end
end
