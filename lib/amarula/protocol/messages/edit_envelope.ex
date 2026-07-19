defmodule Amarula.Protocol.Messages.EditEnvelope do
  @moduledoc """
  Turn a `secretEncryptedMessage` MESSAGE_EDIT envelope back into the legacy
  inline-edit message (issue #30).

  Newer WhatsApp clients send message edits as an encrypted envelope keyed by
  the ORIGINAL message's `messageContextInfo.messageSecret` (stashed per message
  id in the connection's `Amarula.MessageSecretStore` as messages arrive).
  `decrypt/2` finds the secret,
  verifies the editor is the original message's author, derives the key
  (`EditCrypto`), and returns the recovered inner `%Proto.Message{}` — which
  carries the legacy `protocolMessage.editedMessage` shape, so it re-enters
  `MessageContent.classify/1` as an ordinary `{:edit, key, new_text}`.

  Jid forms matter: the derivation uses the bare user jids **in the addressing
  form the editor encrypted with** (LID in a LID group, PN otherwise). We try
  the forms as received first; on GCM failure we retry once with the LID↔PN
  alternate forms from the mapping store — the same cross-addressing fallback
  WA Web's `decryptAddOn` does.

  ## Author check

  In a group, every recipient learns a message's `messageSecret` — so a
  malicious member could forge a valid envelope "editing" someone else's
  message. The stashed entry records the original stanza's server-attested
  author; an edit whose (equally server-attested) author is provably a
  different account is rejected. The check is permissive when it cannot judge
  (unknown LID↔PN mapping): it is defense-in-depth and must not suppress
  legitimate edits.
  """

  alias Amarula.Address
  alias Amarula.MessageSecretStore
  alias Amarula.Protocol.Binary.JID
  alias Amarula.Protocol.Messages.{EditCrypto, MessageContent}
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.LidMappingFileStore

  @typedoc """
  What the receive path knows about the edit stanza: the connection (for LID↔PN
  lookups), the profile (for the secret cache), and the stanza's `from` /
  `participant` attributes (the server-attested author of the edit).
  """
  @type ctx :: %{
          conn: Amarula.Conn.t(),
          profile: atom() | String.t(),
          stanza_from: String.t() | nil,
          participant: String.t() | nil
        }

  @doc """
  Decrypt `message`'s MESSAGE_EDIT envelope, if it carries one.

  Returns `{:ok, inner}` (the recovered legacy-shape edit message),
  `:not_an_edit_envelope` when the message carries no MESSAGE_EDIT envelope
  (including `:EVENT_EDIT` envelopes, which are out of scope), or
  `{:error, reason}` when it does but can't be decrypted — no stashed secret
  (`:no_message_secret`), a provably wrong author (`:author_mismatch`), or a
  key/form mismatch (`:decrypt_failed`).
  """
  @spec decrypt(Proto.Message.t(), ctx()) ::
          {:ok, Proto.Message.t()} | :not_an_edit_envelope | {:error, term()}
  def decrypt(%Proto.Message{} = message, ctx) do
    case MessageContent.secret_envelope(message) do
      %Proto.Message.SecretEncryptedMessage{
        secretEncType: :MESSAGE_EDIT,
        targetMessageKey: %Proto.MessageKey{id: target_id} = target
      } = env
      when is_binary(target_id) ->
        decrypt_envelope(env, target, ctx)

      _ ->
        :not_an_edit_envelope
    end
  end

  defp decrypt_envelope(env, target, ctx) do
    editor = normalized(ctx.participant || ctx.stanza_from)

    with {:editor, e} when not is_nil(e) <- {:editor, editor},
         {:ok, %{secret: secret, sender: stashed_sender}} <- fetch_secret(ctx, target.id),
         :ok <- check_author(ctx.conn, stashed_sender, editor) do
      base_ctx = %{
        message_secret: secret,
        target_msg_id: target.id,
        original_sender_jid: original_sender(target, editor),
        editor_jid: editor
      }

      decrypt_with_fallback(env, base_ctx, ctx.conn)
    else
      {:editor, nil} -> {:error, :no_editor_jid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_secret(ctx, target_id) do
    case MessageSecretStore.get(ctx.conn.message_secret_store, ctx.profile, target_id) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :no_message_secret}
    end
  end

  # The original message's author, for the key derivation. `targetMessageKey`
  # is written from the EDITOR'S perspective: `participant` when present (group),
  # else — since only the author can edit — a `fromMe` target means the editor
  # is also the original sender; a non-fromMe 1:1 target's author is `remoteJid`.
  defp original_sender(%Proto.MessageKey{participant: p}, _editor)
       when is_binary(p) and p != "",
       do: JID.jid_normalized_user(p)

  defp original_sender(%Proto.MessageKey{fromMe: true}, editor), do: editor

  defp original_sender(%Proto.MessageKey{remoteJid: r}, _editor) when is_binary(r) and r != "",
    do: JID.jid_normalized_user(r)

  # Degenerate key — fall back to the editor (the author edits their own
  # message); a wrong guess just fails GCM below.
  defp original_sender(_target, editor), do: editor

  # Reject only a PROVEN mismatch: same-kind accounts that differ, or cross-kind
  # accounts whose stored LID↔PN mapping shows different users. An unknown
  # mapping (or an unparsable stashed jid) passes — see the moduledoc.
  defp check_author(conn, stashed_sender, editor) do
    a = Address.parse(stashed_sender)
    b = Address.parse(editor)

    cond do
      a == nil or b == nil -> :ok
      a.kind == b.kind and Address.same_account?(a, b) -> :ok
      a.kind == b.kind -> {:error, :author_mismatch}
      true -> check_author_cross_kind(conn, a, b)
    end
  end

  defp check_author_cross_kind(conn, a, b) do
    {lid, pn} = if Address.lid?(a), do: {a, b}, else: {b, a}

    case LidMappingFileStore.pn_for_lid(conn, "#{lid.user}@lid") do
      nil -> :ok
      pn_user when pn_user == pn.user -> :ok
      _other -> {:error, :author_mismatch}
    end
  end

  # Try the jid forms as received; on GCM failure retry once with the LID↔PN
  # alternate forms (the editor encrypts with the chat's addressing form, which
  # can differ from how the stanza reached us — e.g. across a LID migration).
  defp decrypt_with_fallback(env, base_ctx, conn) do
    case EditCrypto.decrypt_edit(env, base_ctx) do
      {:error, :decrypt_failed} -> retry_alternate_forms(env, base_ctx, conn)
      other -> other
    end
  end

  defp retry_alternate_forms(env, base_ctx, conn) do
    alt_ctx = %{
      base_ctx
      | original_sender_jid: alternate(conn, base_ctx.original_sender_jid),
        editor_jid: alternate(conn, base_ctx.editor_jid)
    }

    if alt_ctx.original_sender_jid == base_ctx.original_sender_jid and
         alt_ctx.editor_jid == base_ctx.editor_jid do
      {:error, :decrypt_failed}
    else
      EditCrypto.decrypt_edit(env, alt_ctx)
    end
  end

  # The LID↔PN alternate form of a bare user jid, or the jid itself when no
  # mapping is known. The mapping store returns bare USER strings — rebuild the
  # full jid.
  defp alternate(conn, jid) do
    cond do
      JID.lid_user?(jid) ->
        case LidMappingFileStore.pn_for_lid(conn, jid) do
          nil -> jid
          user -> "#{user}@s.whatsapp.net"
        end

      JID.jid_user?(jid) ->
        case LidMappingFileStore.lid_for_pn(conn, jid) do
          nil -> jid
          user -> "#{user}@lid"
        end

      true ->
        jid
    end
  end

  defp normalized(nil), do: nil

  defp normalized(jid) do
    case JID.jid_normalized_user(jid) do
      "" -> nil
      normalized -> normalized
    end
  end
end
