defmodule Amarula.Protocol.Signal.CryptoHelpers do
  @moduledoc """
  Crypto primitives for the Signal v3 session cipher, ported byte-for-byte from
  `node_modules/libsignal/src/crypto.js` (the implementation Baileys runs).

  - `derive_secrets/4` — RFC 5869 HKDF-SHA256 returning the first N 32-byte chunks
  - `calculate_mac/2` — HMAC-SHA256
  - `verify_mac/4` — constant-length truncated MAC check (raises on mismatch)
  - `aes_cbc_decrypt/3` — AES-256-CBC (WhatsApp message payload cipher; NOT GCM)

  These deliberately mirror libsignal, not the Noise/transport crypto in
  `Amarula.Protocol.Crypto`.
  """

  alias Amarula.Protocol.Signal.DecryptError

  @doc "HMAC-SHA256 of `data` keyed by `key`."
  @spec calculate_mac(binary(), binary()) :: binary()
  def calculate_mac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)

  @doc """
  HKDF-SHA256 (RFC 5869) returning the first `chunks` (1..3) 32-byte output blocks.

  Matches libsignal deriveSecrets: PRK = HMAC(salt, input); then
  T(i) = HMAC(PRK, T(i-1) || info || i), with T(0) empty. Salt must be 32 bytes.
  """
  @spec derive_secrets(binary(), binary(), binary(), 1..3) :: [binary()]
  def derive_secrets(input, salt, info, chunks \\ 3)
      when byte_size(salt) == 32 and chunks in 1..3 do
    prk = calculate_mac(salt, input)
    expand(prk, info, chunks, 1, <<>>, [])
  end

  defp expand(_prk, _info, chunks, counter, _prev, acc) when counter > chunks do
    Enum.reverse(acc)
  end

  defp expand(prk, info, chunks, counter, prev, acc) do
    block = calculate_mac(prk, prev <> info <> <<counter>>)
    expand(prk, info, chunks, counter + 1, block, [block | acc])
  end

  @doc """
  Verify that the first `length` bytes of HMAC-SHA256(key, data) equal `mac`.
  Raises `DecryptError` ("Bad MAC" / "Bad MAC length") on failure, matching
  libsignal verifyMAC — the trial-decrypt signal.
  """
  @spec verify_mac(binary(), binary(), binary(), non_neg_integer()) :: :ok
  def verify_mac(data, key, mac, length) do
    calculated = binary_part(calculate_mac(key, data), 0, length)

    cond do
      byte_size(mac) != length -> raise DecryptError, message: "Bad MAC length"
      not secure_compare(mac, calculated) -> raise DecryptError, message: "Bad MAC"
      true -> :ok
    end
  end

  @doc """
  AES-256-CBC decrypt. `:crypto` does no padding, so we strip PKCS#7 ourselves to
  match node's createDecipheriv (which auto-removes it), as libsignal relies on.
  """
  @spec aes_cbc_decrypt(binary(), binary(), binary()) :: binary()
  def aes_cbc_decrypt(key, data, iv) do
    :crypto.crypto_one_time(:aes_256_cbc, key, iv, data, false)
    |> unpad_pkcs7()
  end

  @doc "AES-256-CBC encrypt with PKCS7 padding (inverse of aes_cbc_decrypt/3)."
  @spec aes_cbc_encrypt(binary(), binary(), binary()) :: binary()
  def aes_cbc_encrypt(key, data, iv) do
    :crypto.crypto_one_time(:aes_256_cbc, key, iv, pad_pkcs7(data), true)
  end

  defp pad_pkcs7(data) do
    pad = 16 - rem(byte_size(data), 16)
    data <> :binary.copy(<<pad>>, pad)
  end

  defp unpad_pkcs7(<<>>), do: <<>>

  defp unpad_pkcs7(data) do
    pad = :binary.last(data)

    if pad >= 1 and pad <= 16 and pad <= byte_size(data) do
      binary_part(data, 0, byte_size(data) - pad)
    else
      data
    end
  end

  # Constant-time comparison (hash_equals requires OTP 25+, which we target —
  # no variable-time fallback for secret material).
  defp secure_compare(a, b) when byte_size(a) == byte_size(b), do: :crypto.hash_equals(a, b)
  defp secure_compare(_, _), do: false
end
