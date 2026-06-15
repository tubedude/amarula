defmodule Amarula.Protocol.Signal.SessionBuilderCrossLangTest do
  @moduledoc """
  Cross-language wire-compat for initiator X3DH. The bundle is built by node
  libsignal (../../../gen_initiator_bundle.mjs) as Bob; Elixir is Alice. Elixir
  runs init_outgoing against Bob's bundle, encrypts a pkmsg, and writes it for
  the companion verify script (verify_initiator_pkmsg.mjs) to decrypt as Bob —
  proving SessionBuilder.init_outgoing produces a session whose first message
  is a valid Signal pkmsg.
  """

  use ExUnit.Case, async: false

  alias Amarula.Protocol.Signal.{SessionBuilder, SessionCipher, SessionRecord}
  alias Amarula.Protocol.Messages.MessageEncoder

  @bundle_path Path.expand("../../fixtures/initiator_bundle.json", __DIR__)
  @pkmsg_out Path.expand("../../fixtures/initiator_pkmsg.json", __DIR__)

  defp d64(s), do: Base.decode64!(s)
  # init_outgoing keeps keys wire-form internally; identity store is raw 32B.
  defp raw(<<5, k::binary-size(32)>>), do: k
  defp raw(<<k::binary-size(32)>>), do: k

  test "init_outgoing builds a session; first encrypt is a pkmsg node decrypts" do
    bundle = @bundle_path |> File.read!() |> JSON.decode!()

    # Alice's own identity + registration (we generate fresh; node only needs the
    # identity pub inside the pkmsg, which our encrypt embeds).
    alice_identity = Amarula.Protocol.Crypto.Crypto.generate_key_pair()

    creds = %{
      registration_id: 4242,
      signed_identity_key: %{public: alice_identity.public, private: alice_identity.private},
      # Alice's own signed prekey is unused on the initiator send path, but the
      # store builder requires the shape.
      signed_pre_key: %{key_id: 1, key_pair: alice_identity},
      pre_keys: %{}
    }

    store = Amarula.Protocol.Signal.SessionStore.build(creds)

    device = %{
      registration_id: bundle["registrationId"],
      identity_key: d64(bundle["identityPub"]),
      signed_pre_key: %{
        key_id: bundle["signedPreKeyId"],
        public: d64(bundle["signedPreKeyPub"]),
        signature: d64(bundle["signedPreKeySig"])
      },
      pre_key: %{
        key_id: bundle["preKeyId"],
        public: d64(bundle["preKeyPub"])
      }
    }

    record = SessionBuilder.init_outgoing(SessionRecord.new(), device, store)

    {:ok, type, body, _record} =
      SessionCipher.encrypt(record, "hello from elixir initiator", store)

    assert type == :pkmsg

    File.write!(
      @pkmsg_out,
      JSON.encode!(%{
        "body" => Base.encode64(body),
        "aliceIdentityPub" => Base.encode64(raw(alice_identity.public))
      })
    )

    # Full outbound: encode a real Proto.Message, pad, encrypt over a fresh
    # session, and write it for verify_outbound_message.mjs to decode.
    record2 = SessionBuilder.init_outgoing(SessionRecord.new(), device, store)

    plaintext =
      Amarula.Protocol.Messages.MessageEncoder.encode(MessageEncoder.text("hello from amarula"))

    {:ok, :pkmsg, msg_body, _r} = SessionCipher.encrypt(record2, plaintext, store)

    File.write!(
      Path.expand("../../fixtures/outbound_message.json", __DIR__),
      JSON.encode!(%{"body" => Base.encode64(msg_body)})
    )
  end
end
