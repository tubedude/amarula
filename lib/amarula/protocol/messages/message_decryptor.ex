defmodule Amarula.Protocol.Messages.MessageDecryptor do
  @moduledoc """
  Decrypts the `<enc>` payloads of an incoming `message` node, ported from the
  routing in `src/Utils/decode-wa-message.ts` (`decryptMessageNode`).

  For each `<enc>` child it dispatches by `type`:
    * `pkmsg` / `msg` → 1:1 Signal session cipher (`SessionCipher`)
    * `plaintext`     → passthrough
    * `skmsg`         → group sender-key (not handled here yet; left to caller)

  The decrypted bytes are unpadded (random-max-16) and decoded as a
  `Proto.Message`, unwrapping `deviceSentMessage`.

  Sessions are loaded/stored via `SessionStore` keyed by the sender's signal
  address. This module is pure aside from the session file I/O.
  """

  require Logger

  alias Amarula.Protocol.Binary.{JID, NodeUtils}
  alias Amarula.Protocol.Proto
  alias Amarula.Protocol.Signal.{SessionCipher, SessionStore}

  alias Amarula.Protocol.Signal.Group.{
    GroupCipher,
    GroupSessionBuilder,
    SenderKeyName,
    SenderKeyStore
  }

  @whatsapp_domain 0

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
  """
  @spec decrypt_node(map(), keyword()) :: {:ok, [struct()], [integer()], [term()]}
  def decrypt_node(node, opts) do
    store = Keyword.fetch!(opts, :store)
    conn = Keyword.fetch!(opts, :conn)
    sk_store = SenderKeyStore.build(conn)

    from = NodeUtils.get_attr(node, "from")
    participant = NodeUtils.get_attr(node, "participant")
    author = participant || from
    addr = signal_address(author)

    ctx = %{
      addr: addr,
      from: from,
      author: author,
      store: store,
      sk_store: sk_store,
      conn: conn
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

    case decrypt_enc(
           type,
           enc.content,
           ctx.addr,
           ctx.from,
           ctx.author,
           ctx.store,
           ctx.sk_store,
           ctx.conn
         ) do
      {:ok, msg, pre_key_id} ->
        maybe_process_skdm(msg, ctx.author, ctx.sk_store)
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

  defp decrypt_enc(_type, content, _addr, _from, _author, _store, _sk_store, _conn)
       when not is_binary(content),
       do: {:error, :no_content}

  defp decrypt_enc("pkmsg", content, addr, _from, _author, store, _sk_store, conn) do
    record = SessionStore.load_session(conn, addr)

    with {:ok, plaintext, record, pre_key_id} <-
           run_cipher(fn ->
             SessionCipher.decrypt_pre_key_whisper_message(record, content, store)
           end) do
      SessionStore.store_session(conn, addr, record)

      with {:ok, msg} <- decode_padded(plaintext), do: {:ok, msg, pre_key_id}
    end
  end

  defp decrypt_enc("msg", content, addr, _from, _author, store, _sk_store, conn) do
    with record when not is_nil(record) <- SessionStore.load_session(conn, addr),
         {:ok, plaintext, record} <-
           run_cipher(fn -> SessionCipher.decrypt_whisper_message(record, content, store) end) do
      SessionStore.store_session(conn, addr, record)

      with {:ok, msg} <- decode_padded(plaintext), do: {:ok, msg, nil}
    else
      nil -> {:error, :no_session}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decrypt_enc("skmsg", content, _addr, from, author, _store, sk_store, _conn) do
    sender_key_name = SenderKeyName.from_jids(from, author)

    with {:ok, plaintext} <- GroupCipher.decrypt(sk_store, sender_key_name, content),
         {:ok, msg} <- decode_padded(plaintext) do
      {:ok, msg, nil}
    end
  end

  defp decrypt_enc("plaintext", content, _addr, _from, _author, _store, _sk_store, _conn) do
    with {:ok, msg} <- decode_proto(content), do: {:ok, msg, nil}
  end

  defp decrypt_enc(type, _content, _addr, _from, _author, _store, _sk_store, _conn) do
    {:error, {:unsupported_enc_type, type}}
  end

  # The Signal cipher signals failure by raising (libsignal-shaped); convert to a
  # tuple at this one boundary so a bad <enc> becomes an error entry, not a crash.
  defp run_cipher(fun) do
    fun.()
  rescue
    e -> {:error, e}
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
      %{message: inner} when not is_nil(inner) -> inner
      _ -> msg
    end
  end

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

  # Process senderKeyDistributionMessage inside a just-decrypted group message.
  defp maybe_process_skdm(msg, author, sk_store) do
    skdm = Map.get(msg, :senderKeyDistributionMessage)

    if skdm && skdm.groupId do
      builder = GroupSessionBuilder.new(sk_store)

      case GroupSessionBuilder.process_sender_key_distribution_message(
             builder,
             sk_store,
             skdm,
             author
           ) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to process sender key distribution (author=#{author}): #{inspect(reason)}"
          )
      end
    end
  end

  # Group message sender key name: group JID as group, author JID as sender.
  # jidToSignalProtocolAddress: "<user>.<device>", with "_<domainType>" suffix for
  # non-WhatsApp domains (lid, etc.).
  defp signal_address(jid) do
    case JID.decode(jid) do
      %{user: user} = decoded ->
        dt = Map.get(decoded, :domain_type, @whatsapp_domain)
        device = Map.get(decoded, :device, 0)
        signal_user = if dt == @whatsapp_domain, do: user, else: "#{user}_#{dt}"
        "#{signal_user}.#{device}"

      _ ->
        raise "could not decode JID for signal address: #{inspect(jid)}"
    end
  end
end
