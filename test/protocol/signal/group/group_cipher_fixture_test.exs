defmodule Amarula.Protocol.Signal.Group.GroupCipherFixtureTest do
  @moduledoc """
  Cross-language wire-compat proof: the fixture was produced by the reference
  libsignal primitives + WAProto protobufs (see ../../../gen_group_fixture.mjs
  in the repo root). If Amarula can process that SKDM and decrypt those skmsg
  blobs, the group cipher is wire-compatible with Baileys.
  """

  use ExUnit.Case, async: true

  alias Amarula.Protocol.Signal.Group.{
    GroupCipher,
    GroupSessionBuilder,
    SenderKeyName,
    SenderKeyStore
  }

  @fixture_path Path.expand("../../../fixtures/group_cipher_fixture.json", __DIR__)

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_skfix_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    fixture = @fixture_path |> File.read!() |> JSON.decode!()
    {:ok, dir: dir, fixture: fixture}
  end

  test "decrypts skmsg produced by reference libsignal", %{dir: dir, fixture: fixture} do
    store = SenderKeyStore.build(Amarula.TestConn.new(dir))
    author = "#{fixture["senderId"]}@s.whatsapp.net"

    item = %{
      groupId: fixture["groupId"],
      axolotlSenderKeyDistributionMessage: Base.decode64!(fixture["skdm"])
    }

    builder = GroupSessionBuilder.new(store)

    :ok =
      GroupSessionBuilder.process_sender_key_distribution_message(builder, store, item, author)

    name = SenderKeyName.new(fixture["groupId"], fixture["senderId"], fixture["deviceId"])

    for %{"plaintext" => expected, "ciphertext" => ct_b64} <- fixture["messages"] do
      {:ok, plaintext} = GroupCipher.decrypt(store, name, Base.decode64!(ct_b64))
      assert plaintext == expected
    end
  end
end
