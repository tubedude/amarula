defmodule Amarula.Protocol.Signal.Group.GroupCipher do
  @moduledoc """
  Handles encryption and decryption of group messages using the Signal protocol.

  This module provides the main interface for group message encryption/decryption,
  managing sender keys and coordinating with the sender key store.
  """

  alias Amarula.Protocol.Signal.DecryptError

  alias Amarula.Protocol.Signal.Group.{
    SenderKeyName,
    SenderKeyRecord,
    SenderKeyState,
    SenderKeyMessage,
    SenderChainKey,
    SenderMessageKey
  }

  @max_future_messages 2000

  @doc """
  Encrypts a message for group communication.

  ## Parameters
  - `sender_key_store` - The store for managing sender keys
  - `sender_key_name` - The name identifying the sender key
  - `plaintext` - The message to encrypt

  ## Returns
  - `{:ok, encrypted_message}` - Success with encrypted message
  - `{:error, reason}` - Error with reason
  """
  @spec encrypt(map(), SenderKeyName.t(), binary()) :: {:ok, binary()} | {:error, String.t()}
  def encrypt(sender_key_store, sender_key_name, plaintext) do
    case sender_key_store.load_sender_key.(sender_key_name) do
      {:ok, record} ->
        encrypt_with_record(record, sender_key_store, sender_key_name, plaintext)

      {:error, :not_found} ->
        {:error, "No SenderKeyRecord found for encryption"}

      {:error, reason} ->
        {:error, "Failed to load sender key: #{reason}"}
    end
  end

  @doc """
  Decrypts a group message.

  ## Parameters
  - `sender_key_store` - The store for managing sender keys
  - `sender_key_name` - The name identifying the sender key
  - `encrypted_message` - The encrypted message to decrypt

  ## Returns
  - `{:ok, plaintext}` - Success with decrypted message
  - `{:error, reason}` - Error with reason. `reason` is a `String.t()` for every
    genuine failure (parse, signature, padding, ...); the one exception is a
    `%DecryptError{reason: :key_unavailable}` when the sender-key ratchet
    already advanced past this message's iteration and the skipped key isn't
    cached — a structural signal, matching the 1:1 session path, that a retry
    can never succeed (almost always a redelivery of an already-consumed
    message).
  """
  @spec decrypt(map(), SenderKeyName.t(), binary()) ::
          {:ok, binary()} | {:error, String.t() | DecryptError.t()}
  def decrypt(sender_key_store, sender_key_name, encrypted_message) do
    case sender_key_store.load_sender_key.(sender_key_name) do
      {:ok, record} ->
        decrypt_with_record(record, sender_key_store, sender_key_name, encrypted_message)

      {:error, :not_found} ->
        {:error, "No SenderKeyRecord found for decryption"}

      {:error, reason} ->
        {:error, "Failed to load sender key: #{reason}"}
    end
  end

  # ============================================================================
  # Private Implementation Functions
  # ============================================================================

  @spec encrypt_with_record(SenderKeyRecord.t(), map(), SenderKeyName.t(), binary()) ::
          {:ok, binary()} | {:error, String.t()}
  defp encrypt_with_record(record, sender_key_store, sender_key_name, plaintext) do
    with {:ok, sender_key_state} <- SenderKeyRecord.get_sender_key_state(record),
         # TS group_cipher.ts: iteration === 0 ? 0 : iteration + 1
         chain_iteration =
           SenderChainKey.get_iteration(SenderKeyState.get_sender_chain_key(sender_key_state)),
         target = if(chain_iteration == 0, do: 0, else: chain_iteration + 1),
         {:ok, sender_key, updated_state} <- get_sender_key(sender_key_state, target),
         {:ok, ciphertext} <- encrypt_message(sender_key, plaintext),
         :ok <-
           sender_key_store.store_sender_key.(
             sender_key_name,
             SenderKeyRecord.update_sender_key_state(record, updated_state)
           ) do
      {:ok,
       SenderKeyMessage.serialize(
         SenderKeyMessage.new(
           SenderKeyState.get_key_id(updated_state),
           SenderMessageKey.get_iteration(sender_key),
           ciphertext,
           SenderKeyState.get_signing_key_private(updated_state)
         )
       )}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec decrypt_with_record(SenderKeyRecord.t(), map(), SenderKeyName.t(), binary()) ::
          {:ok, binary()} | {:error, String.t() | DecryptError.t()}
  defp decrypt_with_record(record, sender_key_store, sender_key_name, encrypted_message) do
    with {:ok, sender_key_message} <- parse_sender_key_message(encrypted_message),
         {:ok, sender_key_state} <-
           SenderKeyRecord.get_sender_key_state(
             record,
             SenderKeyMessage.get_key_id(sender_key_message)
           ),
         :ok <-
           SenderKeyMessage.verify_signature(
             sender_key_message,
             SenderKeyState.get_signing_key_public(sender_key_state)
           ),
         {:ok, sender_key, updated_state} <-
           get_sender_key(sender_key_state, SenderKeyMessage.get_iteration(sender_key_message)),
         {:ok, plaintext} <-
           decrypt_message(sender_key, SenderKeyMessage.get_ciphertext(sender_key_message)),
         :ok <-
           sender_key_store.store_sender_key.(
             sender_key_name,
             SenderKeyRecord.update_sender_key_state(record, updated_state)
           ) do
      {:ok, plaintext}
    end
  end

  # Only deserialization failures get the parse-error label; later steps
  # (signature check, counter, padding) keep their own reasons.
  @spec parse_sender_key_message(binary()) :: {:ok, SenderKeyMessage.t()} | {:error, String.t()}
  defp parse_sender_key_message(encrypted_message) do
    case SenderKeyMessage.from_serialized(encrypted_message) do
      {:ok, sender_key_message} -> {:ok, sender_key_message}
      {:error, reason} -> {:error, "Failed to parse sender key message: #{reason}"}
    end
  end

  @spec get_sender_key(SenderKeyState.t(), non_neg_integer()) ::
          {:ok, SenderMessageKey.t(), SenderKeyState.t()}
          | {:error, String.t() | DecryptError.t()}
  defp get_sender_key(sender_key_state, iteration) do
    sender_chain_key = SenderKeyState.get_sender_chain_key(sender_key_state)
    current_iteration = SenderChainKey.get_iteration(sender_chain_key)

    cond do
      # Handle old messages (backward compatibility)
      current_iteration > iteration ->
        if SenderKeyState.has_sender_message_key(sender_key_state, iteration) do
          case SenderKeyState.remove_sender_message_key(sender_key_state, iteration) do
            {message_key, updated_state} when not is_nil(message_key) ->
              {:ok, message_key, updated_state}

            {nil, _updated_state} ->
              {:error, "No sender message key found for iteration"}
          end
        else
          # The ratchet already advanced past this iteration and the skipped
          # message key isn't cached — the key material is gone, so a retry
          # can never succeed. Same "already consumed" condition
          # %DecryptError{reason: :key_unavailable} flags for the 1:1 path
          # (see its moduledoc); tagged structurally here, at the source,
          # instead of leaving callers to pattern-match error prose.
          {:error,
           %DecryptError{
             reason: :key_unavailable,
             message: "Received message with old counter: #{current_iteration}, #{iteration}"
           }}
        end

      # Handle future messages
      iteration - current_iteration > @max_future_messages ->
        {:error, "Over #{@max_future_messages} messages into the future!"}

      # Handle normal case - advance chain key if needed
      true ->
        advance_chain_key(sender_key_state, iteration)
    end
  end

  # Mirrors TS getSenderKey tail: skipped message keys go into state, then the
  # chain is set ONE PAST the used iteration (setSenderChainKey(getNext())) so
  # the used key can't be re-derived.
  @spec advance_chain_key(SenderKeyState.t(), non_neg_integer()) ::
          {:ok, SenderMessageKey.t(), SenderKeyState.t()} | {:error, String.t()}
  defp advance_chain_key(sender_key_state, target_iteration) do
    sender_chain_key = SenderKeyState.get_sender_chain_key(sender_key_state)

    {final_chain_key, updated_state} =
      advance_chain_key_to_iteration(sender_key_state, sender_chain_key, target_iteration)

    message_key = SenderChainKey.get_sender_message_key(final_chain_key)

    updated_state =
      SenderKeyState.set_sender_chain_key(updated_state, SenderChainKey.get_next(final_chain_key))

    {:ok, message_key, updated_state}
  end

  @spec advance_chain_key_to_iteration(SenderKeyState.t(), SenderChainKey.t(), non_neg_integer()) ::
          {SenderChainKey.t(), SenderKeyState.t()}
  defp advance_chain_key_to_iteration(sender_key_state, chain_key, target_iteration) do
    current_iteration = SenderChainKey.get_iteration(chain_key)

    if current_iteration >= target_iteration do
      {chain_key, sender_key_state}
    else
      # Add message key for current iteration
      message_key = SenderChainKey.get_sender_message_key(chain_key)
      updated_state = SenderKeyState.add_sender_message_key(sender_key_state, message_key)

      # Advance to next iteration
      next_chain_key = SenderChainKey.get_next(chain_key)
      advance_chain_key_to_iteration(updated_state, next_chain_key, target_iteration)
    end
  end

  # Bad key/iv sizes are programming errors; CBC needs block-aligned ciphertext,
  # checked explicitly. Anything else crashing means a bug — let it crash.
  @spec encrypt_message(SenderMessageKey.t(), binary()) :: {:ok, binary()}
  defp encrypt_message(sender_key, plaintext) do
    iv = SenderMessageKey.get_iv(sender_key)
    cipher_key = SenderMessageKey.get_cipher_key(sender_key)
    padded_plaintext = add_pkcs7_padding(plaintext, 16)

    {:ok, :crypto.crypto_one_time(:aes_256_cbc, cipher_key, iv, padded_plaintext, true)}
  end

  @spec decrypt_message(SenderMessageKey.t(), binary()) :: {:ok, binary()} | {:error, String.t()}
  defp decrypt_message(_sender_key, ciphertext)
       when byte_size(ciphertext) == 0 or rem(byte_size(ciphertext), 16) != 0 do
    {:error, "Ciphertext is not block-aligned"}
  end

  defp decrypt_message(sender_key, ciphertext) do
    iv = SenderMessageKey.get_iv(sender_key)
    cipher_key = SenderMessageKey.get_cipher_key(sender_key)

    padded_plaintext = :crypto.crypto_one_time(:aes_256_cbc, cipher_key, iv, ciphertext, false)

    case remove_pkcs7_padding(padded_plaintext) do
      {:ok, plaintext} -> {:ok, plaintext}
      :error -> {:error, "Invalid PKCS7 padding"}
    end
  end

  # ============================================================================
  # PKCS7 Padding Functions
  # ============================================================================

  @spec add_pkcs7_padding(binary(), non_neg_integer()) :: binary()
  defp add_pkcs7_padding(data, block_size) do
    padding_length = block_size - rem(byte_size(data), block_size)
    padding = :binary.copy(<<padding_length>>, padding_length)
    data <> padding
  end

  @spec remove_pkcs7_padding(binary()) :: {:ok, binary()} | :error
  defp remove_pkcs7_padding(data) do
    padding_length = :binary.last(data)

    if padding_length in 1..16 and padding_length <= byte_size(data) do
      {:ok, binary_part(data, 0, byte_size(data) - padding_length)}
    else
      :error
    end
  end
end
