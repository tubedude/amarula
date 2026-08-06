defmodule Amarula.Protocol.Messages.MessageDecryptor do
  @moduledoc """
  Decrypts the `<enc>` payloads of an incoming `message` node, ported from the
  routing in `src/Utils/decode-wa-message.ts` (`decryptMessageNode`).

  For each `<enc>` child it dispatches by `type`:
    * `pkmsg` / `msg` → 1:1 Signal session, decrypted through the record's
      `SessionCustodian` (the per-record lock, so an overlapping send-side encrypt
      can't clobber the ratchet)
    * `plaintext`     → passthrough
    * `skmsg`         → group sender-key

  The decrypted bytes are unpadded (random-max-16) and decoded as a
  `Proto.Message`, unwrapping `deviceSentMessage`. This module owns the per-message
  work (routing, unpad, proto decode); the load → cipher → store of a record lives
  in its custodian.
  """

  require Logger

  alias Amarula.Protocol.Binary.NodeUtils
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.{LidMappingFileStore, SessionCustodian}

  alias Amarula.Protocol.Signal.Group.SenderKeyName

  @doc """
  Decrypt all decryptable `<enc>` children of `node`.

  Returns `{:ok, [%Proto.Message{}], used_pre_key_ids, errors}` (one message per
  successfully decrypted enc, one error entry per enc that failed), or
  `{:ok, [], [], []}` if nothing decryptable.
  `used_pre_key_ids` lists our one-time prekey ids consumed by
  PreKeySignalMessages — the caller must delete them from storage, as
  libsignal's `session_cipher` does via `removePreKey`. `opts` requires:
    * `:store` — the cipher store from `SessionStore.build/1`
    * `:conn` — the `Amarula.Conn` scoping session persistence
    * `:instance_id` — to resolve each record's `SessionCustodian`
  """
  @spec decrypt_node(map(), keyword()) :: {:ok, [struct()], [integer()], [term()]}
  def decrypt_node(node, opts) do
    store = Keyword.fetch!(opts, :store)
    conn = Keyword.fetch!(opts, :conn)
    instance_id = Keyword.fetch!(opts, :instance_id)

    from = NodeUtils.get_attr(node, "from")
    participant = NodeUtils.get_attr(node, "participant")
    author = participant || from
    # LID-aware: for a PN sender we now know the LID of, resolve to the LID
    # signal-address (where handle_message just migrated their session). #15.
    addr = LidMappingFileStore.signal_address(conn, author)

    ctx = %{
      addr: addr,
      from: from,
      author: author,
      store: store,
      conn: conn,
      instance_id: instance_id
    }

    {messages, used_pre_key_ids, errors} =
      node
      |> NodeUtils.get_binary_node_children("enc")
      |> Enum.reduce({[], [], []}, &reduce_enc(&1, &2, ctx))

    {:ok, Enum.reverse(messages), Enum.reverse(used_pre_key_ids), Enum.reverse(errors)}
  end

  # Decrypt one <enc> child and fold it into {messages, used_pre_key_ids, errors}.
  defp reduce_enc(enc, {msgs, used_ids, errs}, ctx) do
    type = NodeUtils.get_attr(enc, "type")

    case decrypt_enc(type, enc.content, ctx) do
      {:ok, msg, pre_key_id} ->
        maybe_process_skdm(msg, ctx)
        {[msg | msgs], prepend_if(pre_key_id, used_ids), errs}

      {:error, reason} ->
        Logger.warning(
          "Failed to decrypt enc (type=#{type}, author=#{ctx.author}): #{inspect(reason)}"
        )

        {msgs, used_ids, [reason | errs]}
    end
  end

  defp prepend_if(nil, list), do: list
  defp prepend_if(value, list), do: [value | list]

  defp decrypt_enc(_type, content, _ctx) when not is_binary(content), do: {:error, :no_content}

  # 1:1 Signal: route the load → cipher → store through the record's custodian
  # (the per-record lock), so an overlapping send-side encrypt can't clobber it.
  defp decrypt_enc("pkmsg", content, ctx), do: decrypt_1to1(:pkmsg, content, ctx)
  defp decrypt_enc("msg", content, ctx), do: decrypt_1to1(:msg, content, ctx)

  defp decrypt_enc("skmsg", content, %{from: from, author: author, conn: conn, instance_id: iid}) do
    sender_key_name = SenderKeyName.from_jids(from, author)

    with {:ok, plaintext} <- SessionCustodian.group_decrypt(iid, conn, sender_key_name, content),
         {:ok, msg} <- decode_padded(plaintext) do
      {:ok, msg, nil}
    end
  end

  defp decrypt_enc("plaintext", content, _ctx) do
    with {:ok, msg} <- decode_proto(content), do: {:ok, msg, nil}
  end

  defp decrypt_enc(type, _content, _ctx), do: {:error, {:unsupported_enc_type, type}}

  defp decrypt_1to1(type, content, %{instance_id: iid, conn: conn, addr: addr, store: store}) do
    with {:ok, plaintext, pre_key_id} <-
           SessionCustodian.decrypt(iid, conn, addr, type, content, store),
         {:ok, msg} <- decode_padded(plaintext) do
      {:ok, msg, pre_key_id}
    end
  end

  defp decode_padded(plaintext) do
    with {:ok, bytes} <- unpad(plaintext), do: decode_proto(bytes)
  end

  # Proto.Message.decode/1 raises on malformed bytes — untrusted input, so
  # convert to a tuple here.
  defp decode_proto(bytes) do
    {:ok, decode_message(bytes)}
  rescue
    e -> {:error, e}
  end

  # proto.Message.decode, unwrapping deviceSentMessage.
  defp decode_message(bytes) do
    msg = Proto.Message.decode(bytes)

    case msg.deviceSentMessage do
      %{message: inner} when not is_nil(inner) -> carry_context_info(inner, msg)
      _ -> msg
    end
  end

  # WhatsApp fans a message we sent out to our linked devices wrapped in
  # `deviceSentMessage`, and the `messageContextInfo` can sit on the OUTER wrapper.
  # It carries `messageSecret`, which is the only key a later `secretEncryptedMessage`
  # edit of that message can be decrypted with — so unwrapping without carrying it
  # over silently threw away the secret. Symptom: send from your phone, then edit it
  # from your phone, and the edit arrived as `{:other, _}` instead of `{:edit, …}`.
  #
  # The inner value always wins; the outer only fills what the inner lacks. Mirrors
  # the `decode-wa-message.ts` half of Baileys PR #2743.
  defp carry_context_info(inner, %{messageContextInfo: nil}), do: inner

  defp carry_context_info(%{messageContextInfo: nil} = inner, outer),
    do: %{inner | messageContextInfo: outer.messageContextInfo}

  defp carry_context_info(%{messageContextInfo: %{messageSecret: nil} = ctx} = inner, outer),
    do: %{
      inner
      | messageContextInfo: %{ctx | messageSecret: outer.messageContextInfo.messageSecret}
    }

  defp carry_context_info(inner, _outer), do: inner

  # unpadRandomMax16: last byte is the pad length.
  defp unpad(<<>>), do: {:error, :empty_plaintext}

  defp unpad(bytes) do
    pad = :binary.last(bytes)

    if pad > byte_size(bytes) do
      {:error, {:bad_pad_length, pad, byte_size(bytes)}}
    else
      {:ok, binary_part(bytes, 0, byte_size(bytes) - pad)}
    end
  end

  # Process senderKeyDistributionMessage inside a just-decrypted group message —
  # through the sender's sender-key custodian (the per-record lock).
  defp maybe_process_skdm(msg, %{author: author, conn: conn, instance_id: iid}) do
    skdm = Map.get(msg, :senderKeyDistributionMessage)

    if skdm && skdm.groupId do
      sender_key_name = SenderKeyName.from_jids(skdm.groupId, author)

      case SessionCustodian.process_skdm(iid, conn, sender_key_name, skdm, author) do
        :ok ->
          :ok

        error ->
          Logger.warning(
            "Failed to process sender key distribution (author=#{author}): #{inspect(error)}"
          )
      end
    end
  end
end
