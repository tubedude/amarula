defmodule Amarula.Protocol.Crypto.Constants do
  @moduledoc """
  WhatsApp protocol constants for Noise protocol implementation.

  These constants define the Noise protocol mode, headers, and WhatsApp-specific
  configuration values used throughout the handshake and encryption process.
  """

  # Noise protocol mode string
  @noise_mode "Noise_XX_25519_AESGCM_SHA256\0\0\0\0"

  # Dictionary version for WhatsApp protocol
  @dict_version 3

  # WhatsApp Noise header: "WA" + version + dict_version
  @noise_wa_header <<87, 65, 6, @dict_version>>

  # Key bundle type prefix for Curve25519 keys
  @key_bundle_type <<5>>

  # WhatsApp ADV (Advanced Device Verification) signature prefixes
  @wa_adv_account_sig_prefix <<6, 0>>
  @wa_adv_device_sig_prefix <<6, 1>>
  @wa_adv_hosted_account_sig_prefix <<6, 5>>
  @wa_adv_hosted_device_sig_prefix <<6, 6>>

  # WhatsApp server JID
  @s_whatsapp_net "@s.whatsapp.net"

  # WhatsApp Web protocol version. `Amarula.Config` is the source of truth for the
  # on-the-wire version (the connection's `:version`); keep this in sync with it.
  @wa_version [2, 3000, 1_042_537_629]

  # Default origin for WebSocket connections
  @default_origin "https://web.whatsapp.com"

  # GCM tag length in bytes (128 bits = 16 bytes)
  @gcm_tag_length 16

  # HKDF output length for key derivation
  @hkdf_output_length 64

  # Exported constants for external use

  def noise_mode, do: @noise_mode
  def dict_version, do: @dict_version
  def noise_wa_header, do: @noise_wa_header
  def key_bundle_type, do: @key_bundle_type
  def wa_adv_account_sig_prefix, do: @wa_adv_account_sig_prefix
  def wa_adv_device_sig_prefix, do: @wa_adv_device_sig_prefix
  def wa_adv_hosted_account_sig_prefix, do: @wa_adv_hosted_account_sig_prefix
  def wa_adv_hosted_device_sig_prefix, do: @wa_adv_hosted_device_sig_prefix
  def s_whatsapp_net, do: @s_whatsapp_net
  def wa_version, do: @wa_version
  def default_origin, do: @default_origin
  def gcm_tag_length, do: @gcm_tag_length
  def hkdf_output_length, do: @hkdf_output_length
end
