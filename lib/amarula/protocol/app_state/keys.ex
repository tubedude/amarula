defmodule Amarula.Protocol.AppState.Keys do
  @moduledoc """
  Expand an app-state-sync key into the five mutation sub-keys, ported from
  Baileys `mutationKeys`/`expandAppStateKeys` (pre-WASM `chat-utils.ts`):

      HKDF(key_data, 160, salt="", info="WhatsApp Mutation Keys")

  sliced into 5 × 32 bytes, in order:

    * `index_key`            — HMAC the record index
    * `value_encryption_key` — AES-256-CBC the record value
    * `value_mac_key`        — HMAC (SHA-512) the value MAC
    * `snapshot_mac_key`     — HMAC the snapshot (LTHash) MAC
    * `patch_mac_key`        — HMAC the patch MAC
  """

  alias Amarula.Protocol.Crypto.Crypto

  @info "WhatsApp Mutation Keys"

  @type t :: %{
          index_key: binary(),
          value_encryption_key: binary(),
          value_mac_key: binary(),
          snapshot_mac_key: binary(),
          patch_mac_key: binary()
        }

  @doc "Expand the 32-byte app-state-sync `key_data` into the five sub-keys."
  @spec expand(binary()) :: t()
  def expand(key_data) when is_binary(key_data) do
    <<index_key::binary-32, value_encryption_key::binary-32, value_mac_key::binary-32,
      snapshot_mac_key::binary-32, patch_mac_key::binary-32>> =
      Crypto.hkdf(key_data, 160, <<>>, @info)

    %{
      index_key: index_key,
      value_encryption_key: value_encryption_key,
      value_mac_key: value_mac_key,
      snapshot_mac_key: snapshot_mac_key,
      patch_mac_key: patch_mac_key
    }
  end
end
