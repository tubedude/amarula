defmodule Amarula.Protocol.AppState.Mutation do
  @moduledoc """
  App-state MAC + value crypto, ported from Baileys (pre-WASM `chat-utils.ts`):
  `generateMac` / `generateSnapshotMac` / `generatePatchMac` and the AES-256-CBC
  value decrypt. Pure given the expanded `Amarula.Protocol.AppState.Keys`.

  The record value blob is `iv(16) ++ ciphertext ++ mac(32)`; we verify the value
  MAC then AES-CBC-decrypt into a `SyncActionData` proto.
  """

  alias Amarula.Protocol.Crypto.Crypto

  @doc """
  Value MAC: `HMAC-SHA512(value_mac_key, opByte ++ key_id ++ data ++ len8)[0..32]`,
  where `len8` is 8 bytes carrying `byte_size(opByte ++ key_id)` in its last byte.
  `operation` is `:set` | `:remove`.
  """
  @spec generate_mac(:set | :remove, binary(), binary(), binary()) :: binary()
  def generate_mac(operation, data, key_id, value_mac_key) do
    key_data = <<op_byte(operation)>> <> key_id
    last = <<0::size(7 * 8), byte_size(key_data)>>
    total = key_data <> data <> last
    <<mac::binary-32, _::binary>> = Crypto.hmac_sign_sha512(total, value_mac_key)
    mac
  end

  @doc "Snapshot MAC: `HMAC-SHA256(snapshot_mac_key, lthash ++ u64be(version) ++ name)`."
  @spec generate_snapshot_mac(binary(), non_neg_integer(), String.t(), binary()) :: binary()
  def generate_snapshot_mac(lthash, version, name, snapshot_mac_key) do
    Crypto.hmac_sign(lthash <> u64be(version) <> name, snapshot_mac_key)
  end

  @doc """
  Patch MAC: `HMAC-SHA256(patch_mac_key, snapshot_mac ++ value_macs ++
  u64be(version) ++ name)`.
  """
  @spec generate_patch_mac(binary(), [binary()], non_neg_integer(), String.t(), binary()) ::
          binary()
  def generate_patch_mac(snapshot_mac, value_macs, version, name, patch_mac_key) do
    total = snapshot_mac <> IO.iodata_to_binary(value_macs) <> u64be(version) <> name
    Crypto.hmac_sign(total, patch_mac_key)
  end

  @doc """
  Decrypt a record value blob (`iv ++ ciphertext`, the 32-byte value MAC already
  split off) with the value encryption key. Returns the plaintext
  `SyncActionData` bytes.
  """
  @spec decrypt_value(binary(), binary()) :: binary()
  def decrypt_value(<<iv::binary-16, ciphertext::binary>>, value_encryption_key) do
    padded = :crypto.crypto_one_time(:aes_256_cbc, value_encryption_key, iv, ciphertext, false)
    pkcs7_unpad(padded)
  end

  # 8-byte big-endian version, value in the low 32 bits (Baileys to64BitNetworkOrder).
  @spec u64be(non_neg_integer()) :: binary()
  def u64be(version), do: <<0::32, version::big-32>>

  defp op_byte(:set), do: 0x01
  defp op_byte(:remove), do: 0x02

  defp pkcs7_unpad(data) do
    pad = :binary.last(data)
    binary_part(data, 0, byte_size(data) - pad)
  end
end
