defmodule Amarula.Protocol.Messages.EditEnvelopeTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Amarula.MessageSecretStore
  alias Amarula.Protocol.Messages.{EditCrypto, EditEnvelope, MessageEncoder}
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.LidMappingFileStore

  @pn "10000000001@s.whatsapp.net"
  @lid "200000000000009@lid"
  @other_pn "10000000002@s.whatsapp.net"
  @group "123456789-123456@g.us"

  setup do
    dir = Path.join(System.tmp_dir!(), "amarula_editenv_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    profile = :"edit_env_test_#{System.unique_integer([:positive])}"

    conn = Amarula.Conn.new(%{profile: profile, storage: {Amarula.Storage.File, root: dir}})
    :ok = MessageSecretStore.ensure_local(conn.message_secret_store, profile)
    {:ok, conn: conn, profile: profile}
  end

  defp ctx(test_ctx, overrides \\ %{}) do
    Map.merge(
      %{conn: test_ctx.conn, profile: test_ctx.profile, stanza_from: @pn, participant: nil},
      overrides
    )
  end

  defp stash(test_ctx, msg_id, secret, sender) do
    MessageSecretStore.put(test_ctx.conn.message_secret_store, test_ctx.profile, msg_id, %{
      secret: secret,
      sender: sender
    })
  end

  # An envelope editing ORIG1, encrypted the way a real client would (bare
  # normalized jids for both derivation roles).
  defp envelope(secret, target_key, text, original_sender, editor) do
    inner = MessageEncoder.edit(target_key, text)

    env =
      EditCrypto.encrypt_edit(inner, %{
        message_secret: secret,
        target_msg_id: target_key.id,
        original_sender_jid: original_sender,
        editor_jid: editor
      })

    wrap(%{env | targetMessageKey: target_key})
  end

  defp wrap(env), do: %Proto.Message{secretEncryptedMessage: env}

  test "decrypts a 1:1 edit into the legacy inline shape", test_ctx do
    secret = :crypto.strong_rand_bytes(32)
    stash(test_ctx, "ORIG1", secret, @pn)

    target = %Proto.MessageKey{remoteJid: @pn, id: "ORIG1"}
    msg = envelope(secret, target, "fixed", @pn, @pn)

    assert {:ok, %Proto.Message{protocolMessage: pm}} = EditEnvelope.decrypt(msg, ctx(test_ctx))
    assert pm.type == :MESSAGE_EDIT
    assert pm.editedMessage.conversation == "fixed"
  end

  test "group edit: editor comes from the participant attr, original sender from targetKey.participant",
       test_ctx do
    secret = :crypto.strong_rand_bytes(32)
    stash(test_ctx, "ORIG1", secret, @pn)

    target = %Proto.MessageKey{remoteJid: @group, id: "ORIG1", participant: @pn}
    msg = envelope(secret, target, "fixed", @pn, @pn)

    ctx = ctx(test_ctx, %{stanza_from: @group, participant: "#{@pn}"})
    assert {:ok, _} = EditEnvelope.decrypt(msg, ctx)
  end

  test "targetKey.fromMe with no participant derives the original sender from the editor",
       test_ctx do
    secret = :crypto.strong_rand_bytes(32)
    stash(test_ctx, "ORIG1", secret, @pn)

    # The editor edits their own message: original sender == editor.
    target = %Proto.MessageKey{remoteJid: @other_pn, id: "ORIG1", fromMe: true}
    msg = envelope(secret, target, "fixed", @pn, @pn)

    assert {:ok, _} = EditEnvelope.decrypt(msg, ctx(test_ctx))
  end

  test "editor jids with a device suffix are normalized for derivation", test_ctx do
    secret = :crypto.strong_rand_bytes(32)
    stash(test_ctx, "ORIG1", secret, @pn)

    target = %Proto.MessageKey{remoteJid: @pn, id: "ORIG1"}
    # Encrypted with bare jids (what a client does)…
    msg = envelope(secret, target, "fixed", @pn, @pn)
    # …arrives on a stanza whose from carries a device.
    ctx = ctx(test_ctx, %{stanza_from: "10000000001:17@s.whatsapp.net"})

    assert {:ok, _} = EditEnvelope.decrypt(msg, ctx)
  end

  test "no stashed secret", test_ctx do
    target = %Proto.MessageKey{remoteJid: @pn, id: "UNKNOWN"}
    msg = envelope(:crypto.strong_rand_bytes(32), target, "x", @pn, @pn)

    assert EditEnvelope.decrypt(msg, ctx(test_ctx)) == {:error, :no_message_secret}
  end

  test "author mismatch: a different account than the stashed sender is rejected", test_ctx do
    secret = :crypto.strong_rand_bytes(32)
    stash(test_ctx, "ORIG1", secret, @pn)

    target = %Proto.MessageKey{remoteJid: @group, id: "ORIG1", participant: @pn}
    # A different group member (who legitimately knows the secret) forges an edit.
    msg = envelope(secret, target, "forged", @pn, @other_pn)

    ctx = ctx(test_ctx, %{stanza_from: @group, participant: @other_pn})
    assert EditEnvelope.decrypt(msg, ctx) == {:error, :author_mismatch}
  end

  test "author check is permissive cross-kind when no mapping is known", test_ctx do
    secret = :crypto.strong_rand_bytes(32)
    stash(test_ctx, "ORIG1", secret, @pn)

    target = %Proto.MessageKey{remoteJid: @group, id: "ORIG1", participant: @lid}
    # Editor arrives LID-addressed; the stash recorded the PN. No mapping stored
    # → the check can't judge, and the decrypt itself decides (keys match here).
    msg = envelope(secret, target, "fixed", @lid, @lid)

    ctx = ctx(test_ctx, %{stanza_from: @group, participant: @lid})
    assert {:ok, _} = EditEnvelope.decrypt(msg, ctx)
  end

  test "author check rejects cross-kind when the mapping proves a different user", test_ctx do
    secret = :crypto.strong_rand_bytes(32)
    stash(test_ctx, "ORIG1", secret, @other_pn)
    LidMappingFileStore.store_mappings(test_ctx.conn, [{@lid, @pn}])

    target = %Proto.MessageKey{remoteJid: @group, id: "ORIG1", participant: @lid}
    msg = envelope(secret, target, "forged", @lid, @lid)

    ctx = ctx(test_ctx, %{stanza_from: @group, participant: @lid})
    assert EditEnvelope.decrypt(msg, ctx) == {:error, :author_mismatch}
  end

  test "GCM failure retries once with the LID↔PN alternate forms", test_ctx do
    secret = :crypto.strong_rand_bytes(32)
    # Original stanza arrived PN-addressed; the editor encrypted with LID forms.
    stash(test_ctx, "ORIG1", secret, @pn)
    LidMappingFileStore.store_mappings(test_ctx.conn, [{@lid, @pn}])

    target = %Proto.MessageKey{remoteJid: @pn, id: "ORIG1"}
    msg = envelope(secret, target, "fixed", @lid, @lid)

    # The stanza reaches us PN-addressed → primary attempt (PN forms) fails GCM,
    # the alternate (LID forms via the mapping) succeeds.
    assert {:ok, _} = EditEnvelope.decrypt(msg, ctx(test_ctx))
  end

  test "decrypt failure with no alternate forms available", test_ctx do
    secret = :crypto.strong_rand_bytes(32)
    stash(test_ctx, "ORIG1", secret, @pn)

    target = %Proto.MessageKey{remoteJid: @pn, id: "ORIG1"}
    msg = envelope(secret, target, "fixed", @lid, @lid)

    # Encrypted with LID forms but no mapping stored → no alternate to try.
    assert EditEnvelope.decrypt(msg, ctx(test_ctx)) == {:error, :decrypt_failed}
  end

  test "non-edit messages and EVENT_EDIT envelopes pass through", test_ctx do
    assert EditEnvelope.decrypt(%Proto.Message{conversation: "hi"}, ctx(test_ctx)) ==
             :not_an_edit_envelope

    event_env = %Proto.Message.SecretEncryptedMessage{
      targetMessageKey: %Proto.MessageKey{remoteJid: @pn, id: "E1"},
      encPayload: :crypto.strong_rand_bytes(32),
      encIv: :crypto.strong_rand_bytes(12),
      secretEncType: :EVENT_EDIT
    }

    assert EditEnvelope.decrypt(wrap(event_env), ctx(test_ctx)) == :not_an_edit_envelope
  end

  describe "with a consumer-backed ReadOnly store (no internal ETS)" do
    setup do
      dir = Path.join(System.tmp_dir!(), "amarula_editro_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf(dir) end)

      profile = :"edit_ro_test_#{System.unique_integer([:positive])}"
      secret = :crypto.strong_rand_bytes(32)

      # The consumer serves the secret from "their DB" — a closure. Amarula keeps
      # no ETS copy; nothing is stashed on receive.
      store =
        {Amarula.MessageSecretStore.ReadOnly,
         get: fn _profile, msg_id ->
           case msg_id do
             "ORIG1" -> {:ok, %{secret: secret, sender: @pn}}
             _ -> :error
           end
         end}

      conn =
        Amarula.Conn.new(%{
          profile: profile,
          storage: {Amarula.Storage.File, root: dir},
          message_secret_store: store
        })

      {:ok, conn: conn, profile: profile, secret: secret}
    end

    test "an edit decrypts using the secret read from the consumer store", test_ctx do
      target = %Proto.MessageKey{remoteJid: @pn, id: "ORIG1"}
      msg = envelope(test_ctx.secret, target, "fixed", @pn, @pn)

      assert {:ok, %Proto.Message{protocolMessage: pm}} = EditEnvelope.decrypt(msg, ctx(test_ctx))
      assert pm.editedMessage.conversation == "fixed"
    end

    test "an edit the consumer store doesn't know about misses", test_ctx do
      target = %Proto.MessageKey{remoteJid: @pn, id: "GONE"}
      msg = envelope(test_ctx.secret, target, "fixed", @pn, @pn)

      assert EditEnvelope.decrypt(msg, ctx(test_ctx)) == {:error, :no_message_secret}
    end
  end
end
