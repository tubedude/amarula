defmodule Amarula.Protocol.Signal.SessionCipher do
  @moduledoc """
  Signal v3 Double-Ratchet decryption, ported from
  `node_modules/libsignal/src/session_cipher.js` (decrypt path only).

  Operates on a `SessionRecord` plus a session store (for our identity / prekeys).
  Threads the record through and returns the updated record so the caller can
  persist the ratchet advance.

  v3 message framing: first byte is `(VERSION<<4)|VERSION = 0x33`.
  WhisperMessage     = `[0x33][protobuf][8-byte MAC]`
  PreKeyWhisperMessage = `[0x33][PreKeyWhisperMessage protobuf]` whose `.message`
  field is itself a full (version-tupled, MAC'd) WhisperMessage.
  """

  import Bitwise

  alias Amarula.Protocol.Crypto.Crypto

  alias Amarula.Protocol.Signal.{
    CryptoHelpers,
    DecryptError,
    SessionBuilder,
    SessionRecord,
    WhisperProtocol
  }

  # (VERSION << 4) | VERSION where VERSION = 3 → 0x33
  @version_byte 0x33

  @doc """
  Decrypt a PreKeyWhisperMessage. Builds the responder session from the prekey
  message if needed, then decrypts the embedded WhisperMessage.

  Returns `{:ok, plaintext, updated_record, used_pre_key_id}`.
  """
  @spec decrypt_pre_key_whisper_message(SessionRecord.t() | nil, binary(), map()) ::
          {:ok, binary(), SessionRecord.t(), non_neg_integer() | nil}
  def decrypt_pre_key_whisper_message(record, <<vbyte, body::binary>>, store) do
    check_version!(vbyte)
    pre_key_proto = WhisperProtocol.decode_pre_key_whisper_message(body)
    record = record || SessionRecord.new()

    {record, pre_key_id} = SessionBuilder.init_incoming(record, pre_key_proto, store)
    session = SessionRecord.get_session(record, pre_key_proto.base_key)

    {plaintext, session} = do_decrypt_whisper_message(pre_key_proto.message, session, store)
    record = SessionRecord.set_session(record, session)

    {:ok, plaintext, record, pre_key_id}
  end

  @doc """
  Encrypt `plaintext` for the open session in `record`, ported from
  `session_cipher.js` `encrypt`.

  Returns `{:ok, type, body, updated_record}` where `type` is `:pkmsg` (the
  session still has a pending prekey, so we wrap the WhisperMessage in a
  PreKeyWhisperMessage) or `:msg`. `body` is the full wire payload.
  """
  @spec encrypt(SessionRecord.t(), binary(), map()) ::
          {:ok, :pkmsg | :msg, binary(), SessionRecord.t()}
  def encrypt(record, plaintext, store) do
    session = SessionRecord.get_open_session(record)

    if is_nil(session) do
      raise "No open session"
    end

    ratchet = session.current_ratchet
    chain_key = ratchet.ephemeral_key_pair.public
    chain = SessionRecord.get_chain(session, chain_key)

    if chain.chain_type == SessionRecord.chain_receiving() do
      raise "Tried to encrypt on a receiving chain"
    end

    chain = fill_message_keys(chain, chain.chain_key.counter + 1)
    counter = chain.chain_key.counter
    message_key = Map.fetch!(chain.message_keys, counter)
    chain = %{chain | message_keys: Map.delete(chain.message_keys, counter)}

    [cipher_key, mac_key, iv_material] =
      CryptoHelpers.derive_secrets(message_key, :binary.copy(<<0>>, 32), "WhisperMessageKeys", 3)

    iv = binary_part(iv_material, 0, 16)
    ciphertext = CryptoHelpers.aes_cbc_encrypt(cipher_key, plaintext, iv)

    # ephemeralKey travels wire-form (33-byte 0x05-prefixed), like libsignal,
    # even though the chain is keyed on the raw 32-byte key.
    msg_proto =
      WhisperProtocol.encode_whisper_message(
        prefix5(chain_key),
        counter,
        ratchet.previous_counter,
        ciphertext
      )

    our_identity = store.our_identity

    # MAC input: ourIdentityPub(33) || remoteIdentityKey(33) || versionByte || msgProto.
    mac_input =
      prefix5(our_identity.public) <>
        prefix5(session.index_info.remote_identity_key) <>
        <<@version_byte>> <>
        msg_proto

    mac = binary_part(CryptoHelpers.calculate_mac(mac_key, mac_input), 0, 8)
    whisper = <<@version_byte>> <> msg_proto <> mac

    session = SessionRecord.put_chain(session, chain_key, chain)
    record = SessionRecord.set_session(record, session)

    case Map.get(session, :pending_pre_key) do
      nil ->
        {:ok, :msg, whisper, record}

      ppk ->
        pre_key_msg =
          WhisperProtocol.encode_pre_key_whisper_message(%{
            pre_key_id: Map.get(ppk, :pre_key_id),
            base_key: prefix5(ppk.base_key),
            identity_key: prefix5(our_identity.public),
            message: whisper,
            registration_id: store.our_registration_id,
            signed_pre_key_id: ppk.signed_key_id
          })

        {:ok, :pkmsg, <<@version_byte>> <> pre_key_msg, record}
    end
  end

  @doc """
  Decrypt a WhisperMessage, trying each session in the record until one works.

  Returns `{:ok, plaintext, updated_record}`.
  """
  @spec decrypt_whisper_message(SessionRecord.t(), binary(), map()) ::
          {:ok, binary(), SessionRecord.t()}
  def decrypt_whisper_message(record, data, store) do
    sessions = SessionRecord.get_sessions(record)

    if sessions == [] do
      raise "No session record"
    end

    {plaintext, session} = decrypt_with_sessions(data, sessions, store, [])
    session = put_in(session.index_info.used, now_ms())
    {:ok, plaintext, SessionRecord.set_session(record, session)}
  end

  defp decrypt_with_sessions(_data, [], _store, errs) do
    raise "No matching sessions found for message: #{inspect(errs)}"
  end

  defp decrypt_with_sessions(data, [session | rest], store, errs) do
    do_decrypt_whisper_message(data, session, store)
  rescue
    # Only the expected trial-decrypt signal moves us to the next session;
    # anything else is a real bug and must propagate.
    e in DecryptError -> decrypt_with_sessions(data, rest, store, [e | errs])
  end

  # Core ratchet decrypt. `message_buffer` is the version-tupled WhisperMessage
  # (`[0x33][proto][8-byte MAC]`).
  defp do_decrypt_whisper_message(<<vbyte, _::binary>> = message_buffer, session, store) do
    check_version!(vbyte)

    proto_len = byte_size(message_buffer) - 1 - 8
    <<_v, message_proto::binary-size(^proto_len), mac::binary-size(8)>> = message_buffer
    message = WhisperProtocol.decode_whisper_message(message_proto)

    session = maybe_step_ratchet(session, message.ephemeral_key, message.previous_counter)
    chain = SessionRecord.get_chain(session, message.ephemeral_key)

    if chain.chain_type == SessionRecord.chain_sending() do
      raise DecryptError, message: "Tried to decrypt on a sending chain"
    end

    chain = fill_message_keys(chain, message.counter)

    message_key =
      case Map.fetch(chain.message_keys, message.counter) do
        {:ok, mk} -> mk
        :error -> raise DecryptError, message: "Key used already or never filled"
      end

    chain = %{chain | message_keys: Map.delete(chain.message_keys, message.counter)}

    [cipher_key, mac_key, iv_material] =
      CryptoHelpers.derive_secrets(message_key, :binary.copy(<<0>>, 32), "WhisperMessageKeys", 3)

    our_identity = store.our_identity

    # MAC input (libsignal): remoteIdentityKey(33) || ourIdentityPub(33) ||
    # versionByte || messageProto. Both identity keys in wire form (0x05-prefixed).
    mac_input =
      prefix5(session.index_info.remote_identity_key) <>
        prefix5(our_identity.public) <>
        <<@version_byte>> <>
        message_proto

    CryptoHelpers.verify_mac(mac_input, mac_key, mac, 8)

    iv = binary_part(iv_material, 0, 16)
    plaintext = CryptoHelpers.aes_cbc_decrypt(cipher_key, message.ciphertext, iv)

    session = SessionRecord.put_chain(session, message.ephemeral_key, chain)
    session = Map.delete(session, :pending_pre_key)
    {plaintext, session}
  end

  # Derive message keys forward along the chain up to `counter`.
  defp fill_message_keys(%{chain_key: %{counter: cc}} = chain, counter) when cc >= counter do
    chain
  end

  defp fill_message_keys(%{chain_key: %{counter: cc}}, counter) when counter - cc > 2000 do
    raise DecryptError, message: "Over 2000 messages into the future!"
  end

  defp fill_message_keys(%{chain_key: %{key: nil}}, _counter) do
    raise DecryptError, message: "Chain closed"
  end

  defp fill_message_keys(chain, counter) do
    key = chain.chain_key.key
    message_key = CryptoHelpers.calculate_mac(key, <<1>>)
    next_chain_key = CryptoHelpers.calculate_mac(key, <<2>>)
    next_counter = chain.chain_key.counter + 1

    chain = %{
      chain
      | message_keys: Map.put(chain.message_keys, next_counter, message_key),
        chain_key: %{counter: next_counter, key: next_chain_key}
    }

    fill_message_keys(chain, counter)
  end

  # DH-ratchet step when the remote ephemeral key is new.
  defp maybe_step_ratchet(session, remote_key, previous_counter) do
    if SessionRecord.get_chain(session, remote_key) do
      session
    else
      ratchet = session.current_ratchet

      session =
        case SessionRecord.get_chain(session, ratchet.last_remote_ephemeral_key) do
          nil ->
            session

          prev_ratchet ->
            prev_ratchet = fill_message_keys(prev_ratchet, previous_counter)
            # Close the previous receiving chain
            prev_ratchet = put_in(prev_ratchet.chain_key.key, nil)
            SessionRecord.put_chain(session, ratchet.last_remote_ephemeral_key, prev_ratchet)
        end

      session = calculate_ratchet(session, remote_key, false)
      ratchet = session.current_ratchet

      # Rotate our sending ephemeral and open a new sending chain
      {session, ratchet} =
        case SessionRecord.get_chain(session, ratchet.ephemeral_key_pair.public) do
          nil ->
            {session, ratchet}

          prev_counter_chain ->
            ratchet = %{ratchet | previous_counter: prev_counter_chain.chain_key.counter}
            session = SessionRecord.delete_chain(session, ratchet.ephemeral_key_pair.public)
            {session, ratchet}
        end

      ratchet = %{ratchet | ephemeral_key_pair: Crypto.generate_key_pair()}
      session = %{session | current_ratchet: ratchet}
      session = calculate_ratchet(session, remote_key, true)

      ratchet = %{session.current_ratchet | last_remote_ephemeral_key: remote_key}
      %{session | current_ratchet: ratchet}
    end
  end

  defp calculate_ratchet(session, remote_key, sending) do
    ratchet = session.current_ratchet
    shared = dh(remote_key, ratchet.ephemeral_key_pair.private)

    [new_root, chain_key] =
      CryptoHelpers.derive_secrets(shared, ratchet.root_key, "WhisperRatchet", 2)

    chain_id_key = if sending, do: ratchet.ephemeral_key_pair.public, else: remote_key

    session
    |> SessionRecord.add_chain(chain_id_key, %{
      message_keys: %{},
      chain_key: %{counter: -1, key: chain_key},
      chain_type:
        if(sending, do: SessionRecord.chain_sending(), else: SessionRecord.chain_receiving())
    })
    |> put_in([:current_ratchet, :root_key], new_root)
  end

  # --- helpers ---

  defp check_version!(vbyte) do
    {max, min} = {vbyte >>> 4, vbyte &&& 0xF}

    if min > 3 or max < 3 do
      raise DecryptError, message: "Incompatible version number on WhisperMessage"
    end
  end

  defp dh(<<5, pub::binary-size(32)>>, priv), do: Crypto.shared_key(priv, pub)
  defp dh(<<pub::binary-size(32)>>, priv), do: Crypto.shared_key(priv, pub)

  # Identity keys for the MAC must be wire-form (33 bytes, 0x05-prefixed).
  defp prefix5(<<5, _::binary-size(32)>> = k), do: k
  defp prefix5(<<k::binary-size(32)>>), do: <<5>> <> k

  defp now_ms, do: System.system_time(:millisecond)
end
