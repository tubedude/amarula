defmodule Amarula.Protocol.Crypto.Crypto do
  @moduledoc """
  Cryptographic utilities for WhatsApp Noise protocol implementation.

  This module provides functions for Curve25519 key operations, AES-GCM encryption,
  SHA256 hashing, HKDF key derivation, and HMAC signing required by the Noise protocol.
  """

  require Logger
  alias Amarula.Protocol.Crypto.{Constants, XEdDSA}

  @type key_pair :: %{
          private: binary(),
          public: binary()
        }

  @type encryption_result :: {:ok, binary()} | {:error, term()}
  @type decryption_result :: {:ok, binary()} | {:error, term()}

  @doc """
  Generate a Curve25519 key pair using built-in crypto.

  Returns a map with :private and :public keys as binaries.
  """
  @spec generate_key_pair() :: key_pair()
  def generate_key_pair do
    # Generate Curve25519 key pair using built-in crypto
    # Use X25519 (Curve25519) for key generation
    {public_key, private_key} = :crypto.generate_key(:ecdh, :x25519)

    %{
      private: private_key,
      public: public_key
    }
  end

  @doc """
  Calculate shared secret from private and public keys using Curve25519.

  Returns the shared secret as a binary.
  """
  @spec shared_key(binary(), binary()) :: binary()
  def shared_key(private_key, public_key) do
    # Calculate shared secret using built-in crypto
    # Note: :crypto.compute_key(:ecdh, PublicKey, PrivateKey, Curve) requires public key first
    :crypto.compute_key(:ecdh, public_key, private_key, :x25519)
  end

  @doc """
  Encrypt plaintext using AES-256-GCM.

  Returns {:ok, ciphertext} or {:error, reason}.
  """
  @spec aes_encrypt_gcm(binary(), binary(), binary(), binary()) :: encryption_result()
  def aes_encrypt_gcm(plaintext, key, iv, additional_data) do
    # :crypto.crypto_one_time_aead returns {CipherText, CipherTag} when encrypting.
    # Bad key/iv sizes raise ArgumentError — a caller bug, so let it crash.
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, additional_data, true)

    {:ok, ciphertext <> tag}
  end

  @doc """
  Decrypt ciphertext using AES-256-GCM.

  Returns {:ok, plaintext} or {:error, reason}.
  """
  @spec aes_decrypt_gcm(binary(), binary(), binary(), binary()) :: decryption_result()
  def aes_decrypt_gcm(ciphertext, key, iv, additional_data) do
    # Split ciphertext and auth tag
    tag_length = Constants.gcm_tag_length()

    {encrypted_data, auth_tag} =
      :erlang.split_binary(ciphertext, byte_size(ciphertext) - tag_length)

    # Decrypt with auth tag. :crypto returns :error on auth failure (a real,
    # expected outcome → tagged tuple); malformed sizes raise → let it crash.
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           key,
           iv,
           encrypted_data,
           additional_data,
           auth_tag,
           false
         ) do
      :error -> {:error, "GCM decryption authentication failed"}
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
    end
  end

  @doc """
  Encrypt plaintext using AES-256-CTR.

  Used by the link-code (phone-number) pairing flow to wrap ephemeral public
  keys. Mirrors Baileys `aesEncryptCTR`. Returns the ciphertext as a binary.
  """
  @spec aes_encrypt_ctr(binary(), binary(), binary()) :: binary()
  def aes_encrypt_ctr(plaintext, key, iv) do
    :crypto.crypto_one_time(:aes_256_ctr, key, iv, plaintext, true)
  end

  @doc """
  Decrypt ciphertext using AES-256-CTR.

  Mirrors Baileys `aesDecryptCTR`. Returns the plaintext as a binary.
  """
  @spec aes_decrypt_ctr(binary(), binary(), binary()) :: binary()
  def aes_decrypt_ctr(ciphertext, key, iv) do
    :crypto.crypto_one_time(:aes_256_ctr, key, iv, ciphertext, false)
  end

  @doc """
  Derive the link-code pairing key from the pairing code and salt.

  PBKDF2-HMAC-SHA256, 131_072 iterations (`2 << 16`), 32-byte output — matches
  Baileys `derivePairingCodeKey`.
  """
  @spec derive_pairing_code_key(binary(), binary()) :: binary()
  def derive_pairing_code_key(pairing_code, salt) do
    :crypto.pbkdf2_hmac(:sha256, pairing_code, salt, 131_072, 32)
  end

  @doc """
  Generate SHA-256 hash of input data.

  Returns the hash as a binary.
  """
  @spec sha256(binary()) :: binary()
  def sha256(data) do
    :crypto.hash(:sha256, data)
  end

  @doc """
  HMAC-SHA256 signing.

  Returns the HMAC signature as a binary.
  """
  @spec hmac_sign(binary(), binary()) :: binary()
  def hmac_sign(data, key) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  @doc "HMAC-SHA512 (used by app-state value MACs)."
  @spec hmac_sign_sha512(binary(), binary()) :: binary()
  def hmac_sign_sha512(data, key) do
    :crypto.mac(:hmac, :sha512, key, data)
  end

  @doc """
  HMAC-based Key Derivation Function (HKDF).

  Derives keys from input key material using HKDF with SHA-256.
  Returns the derived key as a binary.
  """
  @spec hkdf(binary(), non_neg_integer(), binary(), binary()) :: binary()
  def hkdf(input_key_material, output_length, salt \\ <<>>, info \\ <<>>) do
    # HKDF-Extract: PRK = HMAC-SHA256(salt, IKM)
    prk = hmac_sign(input_key_material, salt)

    # HKDF-Expand: OKM = HKDF-Expand(PRK, info, L)
    expand(prk, info, output_length, <<>>, 1, [])
  end

  @doc """
  Generate a random IV for AES-GCM encryption.

  Creates a 12-byte IV with the counter in the last 4 bytes.
  According to WhatsApp implementation (Baileys/whatsmeow):
  - 8 leading zero bytes
  - 4 bytes big-endian counter (bytes 8-11)
  This matches: 0x0000000000000000 || be32(counter)
  """
  @spec generate_iv(non_neg_integer()) :: binary()
  def generate_iv(counter) do
    # Create 12-byte IV with counter in last 4 bytes
    # Elixir's <<counter::32>> defaults to big-endian, which matches JavaScript's DataView.setUint32()
    <<0::64, counter::32>>
  end

  @doc """
  Generate random bytes of specified length.

  Returns random binary data.
  """
  @spec random_bytes(non_neg_integer()) :: binary()
  def random_bytes(length) do
    :crypto.strong_rand_bytes(length)
  end

  @doc """
  Generate a registration ID for Signal protocol.

  Returns a random 14-bit integer (0-16383), matching Baileys implementation.
  WhatsApp requires registration IDs to be within this range.
  """
  @spec generate_registration_id() :: non_neg_integer()
  def generate_registration_id do
    # Generate 2 random bytes and mask to 14 bits (0x3FFF = 16383)
    # Matches Baileys: Uint16Array.from(randomBytes(2))[0] & 16383
    <<id::16>> = random_bytes(2)
    Bitwise.band(id, 16_383)
  end

  @doc """
  Generate a signed pre-key ID.

  Returns a random 16-bit integer.
  """
  @spec generate_signed_pre_key_id() :: non_neg_integer()
  def generate_signed_pre_key_id do
    <<id::16>> = random_bytes(2)
    id
  end

  @doc """
  Sign data with a 32-byte X25519 private key using XEd25519
  (libsignal-compatible, matches Baileys `Curve.sign`).

  Returns the signature as a binary (64 bytes).
  """
  @spec sign(binary(), binary()) :: binary()
  def sign(data, private_key) do
    XEdDSA.sign(data, private_key)
  end

  @doc """
  Verify an XEd25519 signature against a 32-byte Montgomery (X25519) public key
  (libsignal-compatible, matches Baileys `Curve.verify`).

  Returns true if signature is valid, false otherwise.
  """
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(data, signature, public_key) do
    XEdDSA.verify(data, signature, public_key)
  end

  @doc """
  Generates a Signal Protocol public key by prefixing with key bundle type if needed.

  Signal Protocol expects public keys to be 33 bytes (1 byte type + 32 bytes key).
  If the key is already 33 bytes, return as-is. Otherwise, prefix with KEY_BUNDLE_TYPE.

  This matches Baileys: `pubKey.length === 33 ? pubKey : Buffer.concat([KEY_BUNDLE_TYPE, pubKey])`
  """
  @spec generate_signal_pub_key(binary()) :: binary()
  def generate_signal_pub_key(pub_key) when byte_size(pub_key) == 33 do
    pub_key
  end

  def generate_signal_pub_key(pub_key) when byte_size(pub_key) == 32 do
    Constants.key_bundle_type() <> pub_key
  end

  def generate_signal_pub_key(pub_key) do
    # Handle unexpected sizes - log warning but try to proceed
    Logger.warning("Unexpected public key size: #{byte_size(pub_key)} bytes")

    if byte_size(pub_key) > 33 do
      pub_key
    else
      Constants.key_bundle_type() <> pub_key
    end
  end

  # Private helper functions

  # HKDF-Expand implementation
  defp expand(_prk, _info, output_length, _t, _counter, acc)
       when length(acc) * 32 >= output_length do
    # Concatenate all T values and truncate to desired length
    result = :erlang.list_to_binary(:lists.reverse(acc))
    :binary.part(result, 0, output_length)
  end

  defp expand(prk, info, output_length, t, counter, acc) do
    # T(i) = HMAC-SHA256(PRK, T(i-1) | info | i)
    input = t <> info <> <<counter::8>>
    t_next = hmac_sign(input, prk)
    expand(prk, info, output_length, t_next, counter + 1, [t_next | acc])
  end
end
