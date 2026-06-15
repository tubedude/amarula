defmodule Amarula.Protocol.Signal.SessionCipherCrossLangTest do
  @moduledoc """
  Cross-language wire-compat for the 1:1 Signal cipher. The fixture is built by
  the reference node libsignal (../../../gen_session_fixture.mjs): Alice builds
  an initiator session to Bob and encrypts a pkmsg. Bob = Elixir.

  Proves: (1) we decrypt a real libsignal pkmsg; (2) SessionCipher.encrypt
  produces a WhisperMessage that the companion verify script
  (verify_session_reply.mjs) decrypts as Alice. Step 2's reply is written to a
  fixture file the verify script reads.
  """

  use ExUnit.Case, async: false

  alias Amarula.Protocol.Signal.{SessionCipher, SessionStore}

  @fixture_path Path.expand("../../fixtures/session_fixture.json", __DIR__)
  @reply_out Path.expand("../../fixtures/session_reply.json", __DIR__)

  defp d64(s), do: Base.decode64!(s)
  # node curve pubkeys are 33-byte 0x05-prefixed; our store keeps raw 32-byte.
  defp raw(<<5, k::binary-size(32)>>), do: k
  defp raw(<<k::binary-size(32)>>), do: k

  test "decrypt a libsignal pkmsg, then encrypt a reply libsignal can read" do
    fix = @fixture_path |> File.read!() |> JSON.decode!()
    bob = fix["bob"]

    creds = %{
      registration_id: bob["registrationId"],
      signed_identity_key: %{
        public: raw(d64(bob["identityPub"])),
        private: d64(bob["identityPriv"])
      },
      signed_pre_key: %{
        key_id: bob["signedPreKeyId"],
        key_pair: %{
          public: raw(d64(bob["signedPreKeyPub"])),
          private: d64(bob["signedPreKeyPriv"])
        }
      },
      pre_keys: %{
        bob["preKeyId"] => %{
          public: raw(d64(bob["preKeyPub"])),
          private: d64(bob["preKeyPriv"])
        }
      }
    }

    store = SessionStore.build(creds)

    # 1) decrypt Alice's pkmsg
    %{"type" => 3, "body" => body_b64} = fix["aliceToBob"]

    {:ok, plaintext, record, _pre_key_id} =
      SessionCipher.decrypt_pre_key_whisper_message(nil, d64(body_b64), store)

    assert plaintext == "hello bob from alice"

    # 2) encrypt a reply on the now-established session
    {:ok, type, reply_body, _record} =
      SessionCipher.encrypt(record, "hi alice from bob", store)

    # responder's first send is a normal msg (no pending prekey on Bob's side)
    assert type == :msg

    File.write!(@reply_out, JSON.encode!(%{"body" => Base.encode64(reply_body)}))
  end
end
