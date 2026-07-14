defmodule Amarula.Protocol.Messages.EditCryptoTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Messages.{EditCrypto, MessageContent, MessageEncoder}
  alias Amarula.Protocol.Proto

  @target_key %Proto.MessageKey{remoteJid: "10000000001@s.whatsapp.net", id: "ORIG1"}

  defp ctx(overrides \\ %{}) do
    Map.merge(
      %{
        message_secret: :crypto.strong_rand_bytes(32),
        target_msg_id: "ORIG1",
        original_sender_jid: "10000000001@s.whatsapp.net",
        editor_jid: "10000000001@s.whatsapp.net"
      },
      overrides
    )
  end

  describe "round-trip" do
    test "decrypts an envelope encrypted with the same context; inner classifies as the legacy edit" do
      ctx = ctx()
      inner = MessageEncoder.edit(@target_key, "corrected text")

      env = EditCrypto.encrypt_edit(inner, ctx)
      assert env.secretEncType == :MESSAGE_EDIT
      assert byte_size(env.encIv) == 12

      assert {:ok, %Proto.Message{} = decrypted} = EditCrypto.decrypt_edit(env, ctx)
      assert MessageContent.classify(decrypted) == {:edit, @target_key, "corrected text"}
    end

    test "LID jid forms round-trip too" do
      ctx =
        ctx(%{
          original_sender_jid: "200000000000009@lid",
          editor_jid: "200000000000009@lid"
        })

      env = EditCrypto.encrypt_edit(MessageEncoder.edit(@target_key, "hi"), ctx)
      assert {:ok, _} = EditCrypto.decrypt_edit(env, ctx)
    end
  end

  describe "failure modes" do
    test "wrong message secret fails GCM" do
      env = EditCrypto.encrypt_edit(MessageEncoder.edit(@target_key, "x"), ctx())

      assert EditCrypto.decrypt_edit(env, ctx(%{message_secret: :crypto.strong_rand_bytes(32)})) ==
               {:error, :decrypt_failed}
    end

    test "jid form mismatch fails GCM (encrypted with LID, decrypted with PN)" do
      secret = :crypto.strong_rand_bytes(32)
      lid_ctx = ctx(%{message_secret: secret, editor_jid: "200000000000009@lid"})
      pn_ctx = ctx(%{message_secret: secret, editor_jid: "10000000009@s.whatsapp.net"})

      env = EditCrypto.encrypt_edit(MessageEncoder.edit(@target_key, "x"), lid_ctx)
      assert EditCrypto.decrypt_edit(env, pn_ctx) == {:error, :decrypt_failed}
    end

    test "tampered payload fails GCM" do
      ctx = ctx()
      env = EditCrypto.encrypt_edit(MessageEncoder.edit(@target_key, "x"), ctx)
      <<first, rest::binary>> = env.encPayload
      tampered = %{env | encPayload: <<Bitwise.bxor(first, 1), rest::binary>>}

      assert EditCrypto.decrypt_edit(tampered, ctx) == {:error, :decrypt_failed}
    end

    test "non-12-byte IV is rejected before decrypting" do
      ctx = ctx()
      env = EditCrypto.encrypt_edit(MessageEncoder.edit(@target_key, "x"), ctx)

      assert EditCrypto.decrypt_edit(%{env | encIv: :crypto.strong_rand_bytes(16)}, ctx) ==
               {:error, :bad_iv}
    end

    test "EVENT_EDIT envelopes are out of scope" do
      env = %Proto.Message.SecretEncryptedMessage{
        encPayload: :crypto.strong_rand_bytes(32),
        encIv: :crypto.strong_rand_bytes(12),
        secretEncType: :EVENT_EDIT
      }

      assert EditCrypto.decrypt_edit(env, ctx()) == {:error, {:unsupported_enc_type, :EVENT_EDIT}}
    end

    test "missing payload/iv" do
      assert EditCrypto.decrypt_edit(
               %{secretEncType: :MESSAGE_EDIT, encPayload: nil, encIv: nil},
               ctx()
             ) ==
               {:error, :no_payload}
    end
  end
end
