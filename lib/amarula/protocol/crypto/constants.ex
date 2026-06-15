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

  # WhatsApp certificate details
  @wa_cert_details %{serial: 0, issuer: "WhatsApp"}

  # Key bundle type prefix for Curve25519 keys
  @key_bundle_type <<5>>

  # WhatsApp ADV (Advanced Device Verification) signature prefixes
  @wa_adv_account_sig_prefix <<6, 0>>
  @wa_adv_device_sig_prefix <<6, 1>>
  @wa_adv_hosted_account_sig_prefix <<6, 5>>
  @wa_adv_hosted_device_sig_prefix <<6, 6>>

  # WhatsApp server JID
  @s_whatsapp_net "@s.whatsapp.net"

  # WhatsApp version used by Baileys (updated Nov 2025)
  @wa_version [2, 3000, 1_029_710_215]

  # Default origin for WebSocket connections
  @default_origin "https://web.whatsapp.com"

  # GCM tag length in bytes (128 bits = 16 bytes)
  @gcm_tag_length 16

  # HKDF output length for key derivation
  @hkdf_output_length 64

  # Maximum frame size (3 bytes for length header)
  @max_frame_size 0xFFFFFF

  # Exported constants for external use

  def noise_mode, do: @noise_mode
  def dict_version, do: @dict_version
  def noise_wa_header, do: @noise_wa_header
  def wa_cert_details, do: @wa_cert_details
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
  def max_frame_size, do: @max_frame_size
end
