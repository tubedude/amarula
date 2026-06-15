defmodule Amarula.Protocol.Signal.SessionInjectorTest do
  @moduledoc """
  SessionInjector parses a server-shaped prekey-bundle IQ and builds a sending
  session. We assemble the IQ from Bob's node-libsignal bundle fixture, inject
  it, encrypt a message, and write it for verify_outbound_message.mjs (reused)
  to decode as Bob — proving parse → init_outgoing → encrypt end to end.
  """

  use ExUnit.Case, async: false

  alias Amarula.Protocol.Binary.Node
  alias Amarula.Protocol.Messages.MessageEncoder
  alias Amarula.Protocol.Signal.{SessionCipher, SessionInjector, SessionStore}

  @bundle_path Path.expand("../../fixtures/initiator_bundle.json", __DIR__)
  @out_path Path.expand("../../fixtures/outbound_message.json", __DIR__)

  defp d64(s), do: Base.decode64!(s)
  defp raw(<<5, k::binary-size(32)>>), do: k
  defp raw(<<k::binary-size(32)>>), do: k

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_inject_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir, conn: Amarula.TestConn.new(dir)}
  end

  test "parses a bundle IQ, builds a session, encrypts a decodable message", %{conn: conn} do
    bundle = @bundle_path |> File.read!() |> JSON.decode!()

    # Bob's bundle uses raw 32B value nodes (server form); identity raw too.
    user =
      Node.create("user", %{"jid" => "5511999999999@s.whatsapp.net"}, [
        Node.create("registration", %{}, <<bundle["registrationId"]::big-unsigned-32>>),
        Node.create("identity", %{}, raw(d64(bundle["identityPub"]))),
        Node.create("skey", %{}, [
          Node.create("id", %{}, <<bundle["signedPreKeyId"]::big-unsigned-24>>),
          Node.create("value", %{}, raw(d64(bundle["signedPreKeyPub"]))),
          Node.create("signature", %{}, d64(bundle["signedPreKeySig"]))
        ]),
        Node.create("key", %{}, [
          Node.create("id", %{}, <<bundle["preKeyId"]::big-unsigned-24>>),
          Node.create("value", %{}, raw(d64(bundle["preKeyPub"])))
        ])
      ])

    iq = Node.create("iq", %{"type" => "result"}, [Node.create("list", %{}, [user])])

    alice = Amarula.Protocol.Crypto.Crypto.generate_key_pair()

    creds = %{
      registration_id: 4242,
      signed_identity_key: %{public: alice.public, private: alice.private},
      signed_pre_key: %{key_id: 1, key_pair: alice},
      pre_keys: %{}
    }

    assert SessionInjector.inject(iq, creds, conn) == 1

    # Load the session the injector persisted and encrypt over it.
    addr = "5511999999999.0"
    record = SessionStore.load_session(conn, addr)
    assert record != nil

    store = SessionStore.build(creds)
    plaintext = MessageEncoder.encode(MessageEncoder.text("hello from amarula"))
    {:ok, :pkmsg, body, _r} = SessionCipher.encrypt(record, plaintext, store)

    File.write!(@out_path, JSON.encode!(%{"body" => Base.encode64(body)}))
  end
end
