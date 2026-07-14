defmodule Amarula.Protocol.Messages.EditCrypto do
  @moduledoc """
  Decrypt `secretEncryptedMessage` MESSAGE_EDIT envelopes — the extra encryption
  layer newer WhatsApp clients wrap message edits in (issue #30; the reference
  implementation is Baileys `decryptMessageEdit`, PR #2547, and whatsmeow's
  `msgsecret.go` "Message Edit" use case).

  The envelope's `encPayload`/`encIv` are AES-256-GCM encrypted under a key
  derived from the **original (target) message's** `messageContextInfo.messageSecret`
  and the ids of the target message, its author, and the editor:

      sign    = target_msg_id ++ original_sender_jid ++ editor_jid ++ "Message Edit" ++ <<1>>
      key0    = HMAC-SHA256(key=<<0::256>>, data=message_secret)   # key is 32 zero bytes
      dec_key = HMAC-SHA256(key=key0, data=sign)
      plain   = AES-256-GCM-decrypt(encPayload, key=dec_key, iv=encIv, aad=<<>>)
              → Proto.Message (carries the legacy protocolMessage.editedMessage shape)

  Same HMAC chain as `Amarula.Protocol.Messages.PollCrypto`, with two deliberate
  differences: the **AAD is empty** (WA Web binds `"id\\0jid"` into the AAD only
  for PollVote/EventResponse — every other addon uses an empty AAD), and the IV
  must be **exactly 12 bytes** (WA Web rejects anything else before decrypting;
  doing the same turns a malformed envelope into a clear error instead of an
  opaque GCM failure). GCM tag is the trailing 16 bytes of `encPayload`.

  The decrypted plaintext is a full `Proto.Message` whose
  `protocolMessage: %{type: :MESSAGE_EDIT, key, editedMessage}` is the legacy
  inline-edit shape — so it re-enters `MessageContent.classify/1` unchanged.
  """

  alias Amarula.Protocol.Proto

  @gcm_tag_len 16
  @iv_len 12

  @typedoc """
  Everything the key derivation needs. The jids must be the **bare normalized
  user form** (`user@server`, no device) **in the addressing form the editor
  used** (LID in a LID group, PN otherwise) — a wrong form derives a wrong key
  and decryption fails, exactly like poll votes (see `PollCrypto`'s warning).
  """
  @type context :: %{
          message_secret: binary(),
          target_msg_id: String.t(),
          original_sender_jid: String.t(),
          editor_jid: String.t()
        }

  @doc """
  Decrypt a MESSAGE_EDIT envelope (`env` = `%Proto.Message.SecretEncryptedMessage{}`
  or a map with `:encPayload`/`:encIv`/`:secretEncType`). Returns
  `{:ok, %Proto.Message{}}` — the recovered inner message in the legacy
  `protocolMessage.editedMessage` shape — or `{:error, reason}`:

    * `{:error, {:unsupported_enc_type, t}}` — not a MESSAGE_EDIT envelope
      (`:EVENT_EDIT` is deliberately out of scope here)
    * `{:error, :bad_iv}` — IV is not exactly #{@iv_len} bytes
    * `{:error, :decrypt_failed}` — GCM verification failed (wrong secret or a
      jid form mismatch — the caller may retry with the LID↔PN alternate forms)
  """
  @spec decrypt_edit(map(), context()) :: {:ok, Proto.Message.t()} | {:error, term()}
  def decrypt_edit(%{secretEncType: :MESSAGE_EDIT, encPayload: payload, encIv: iv}, ctx)
      when is_binary(payload) and is_binary(iv) do
    cond do
      byte_size(iv) != @iv_len ->
        {:error, :bad_iv}

      byte_size(payload) <= @gcm_tag_len ->
        {:error, :no_payload}

      true ->
        do_decrypt(payload, iv, ctx)
    end
  end

  def decrypt_edit(%{secretEncType: t}, _ctx) when t != :MESSAGE_EDIT,
    do: {:error, {:unsupported_enc_type, t}}

  def decrypt_edit(_env, _ctx), do: {:error, :no_payload}

  @doc """
  Encrypt an inner message into a MESSAGE_EDIT envelope — the inverse of
  `decrypt_edit/2`, for round-trip tests. `inner` should carry the legacy
  `protocolMessage.editedMessage` shape. `targetMessageKey` is left to the
  caller (the key derivation only uses the ids in `ctx`).
  """
  @spec encrypt_edit(Proto.Message.t(), context()) :: Proto.Message.SecretEncryptedMessage.t()
  def encrypt_edit(%Proto.Message{} = inner, ctx) do
    dec_key = edit_key(ctx)
    iv = :crypto.strong_rand_bytes(@iv_len)
    plaintext = Proto.Message.encode(inner)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, dec_key, iv, plaintext, <<>>, @gcm_tag_len, true)

    %Proto.Message.SecretEncryptedMessage{
      encPayload: ciphertext <> tag,
      encIv: iv,
      secretEncType: :MESSAGE_EDIT
    }
  end

  defp do_decrypt(payload, iv, ctx) do
    dec_key = edit_key(ctx)
    ct_len = byte_size(payload) - @gcm_tag_len
    <<ciphertext::binary-size(^ct_len), tag::binary-size(@gcm_tag_len)>> = payload

    case :crypto.crypto_one_time_aead(:aes_256_gcm, dec_key, iv, ciphertext, <<>>, tag, false) do
      plaintext when is_binary(plaintext) ->
        {:ok, Proto.Message.decode(plaintext)}

      :error ->
        {:error, :decrypt_failed}
    end
  rescue
    e -> {:error, e}
  end

  # Same two-stage HMAC chain as PollCrypto.vote_key/1 (HKDF-SHA256 with a zero
  # salt and a one-block expand), with the "Message Edit" use-case label.
  defp edit_key(ctx) do
    sign =
      ctx.target_msg_id <> ctx.original_sender_jid <> ctx.editor_jid <> "Message Edit" <> <<1>>

    key0 = :crypto.mac(:hmac, :sha256, <<0::256>>, ctx.message_secret)
    :crypto.mac(:hmac, :sha256, key0, sign)
  end
end
