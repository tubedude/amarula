defmodule Amarula.Protocol.Auth.AuthUtils do
  @moduledoc """
  Authentication utilities for WhatsApp credential generation and management.

  This module provides functions for generating and managing authentication
  credentials required for WhatsApp WebSocket connections, including noise keys,
  signed identity keys, pre-keys, and registration data.
  """

  alias Amarula.Protocol.Crypto.{Crypto, Constants}
  alias Amarula.Protocol.Proto

  @type auth_creds :: %{
          noise_key: Crypto.key_pair(),
          signed_identity_key: Crypto.key_pair(),
          signed_pre_key: %{
            key_pair: Crypto.key_pair(),
            signature: binary(),
            key_id: non_neg_integer()
          },
          registration_id: non_neg_integer(),
          adv_secret_key: binary(),
          next_pre_key_id: non_neg_integer(),
          first_unuploaded_pre_key_id: non_neg_integer(),
          pre_keys: map(),
          me: %{id: String.t(), name: String.t(), lid: String.t()} | nil,
          account: map() | nil,
          signal_identities: list(map()),
          platform: String.t() | nil,
          # Link-code (phone-number) pairing — ephemeral key the server wraps,
          # the minted 8-char code, and whether this device has registered.
          pairing_ephemeral_key_pair: Crypto.key_pair(),
          pairing_code: String.t() | nil,
          registered: boolean()
        }

  @type socket_config :: %{
          version: list(non_neg_integer()),
          browser: list(String.t()),
          country_code: String.t(),
          sync_full_history: boolean()
        }

  @doc """
  Initialize new authentication credentials.

  Generates all required keys and credentials for a new WhatsApp connection.
  Returns a map with all authentication data.
  """
  @spec init_auth_creds() :: auth_creds()
  def init_auth_creds do
    # Generate noise key (Curve25519 key pair)
    noise_key = Crypto.generate_key_pair()

    # Generate signed identity key (X25519 key pair, signs via XEd25519 — matches Baileys Curve.generateKeyPair)
    signed_identity_key = Crypto.generate_key_pair()

    # Generate signed pre-key
    signed_pre_key = generate_signed_pre_key(signed_identity_key)

    # Generate registration ID
    registration_id = Crypto.generate_registration_id()

    # Generate adv secret key (base64 encoded)
    adv_secret_key = Crypto.random_bytes(32) |> Base.encode64()

    %{
      noise_key: noise_key,
      signed_identity_key: signed_identity_key,
      signed_pre_key: signed_pre_key,
      registration_id: registration_id,
      adv_secret_key: adv_secret_key,
      # One-time prekey watermarks + storage (Baileys initAuthCreds: both ids start at 1)
      next_pre_key_id: 1,
      first_unuploaded_pre_key_id: 1,
      pre_keys: %{},
      me: nil,
      account: nil,
      signal_identities: [],
      platform: nil,
      # Link-code (phone-number) pairing state (Baileys initAuthCreds).
      pairing_ephemeral_key_pair: Crypto.generate_key_pair(),
      pairing_code: nil,
      registered: false
    }
  end

  @doc """
  Generate registration node for new connections.

  Creates a ClientPayload for device registration with WhatsApp servers.
  """
  @spec generate_registration_node(any(), socket_config()) :: %Proto.ClientPayload{}
  def generate_registration_node(creds, config) do
    # Create app version hash (MD5 of version string)
    app_version_hash = :crypto.hash(:md5, Enum.join(config.version, "."))

    # Create device properties
    device_props = create_device_props(config)
    device_props_binary = Proto.DeviceProps.encode(device_props)

    # Create registration payload
    # IMPORTANT: Baileys explicitly sets passive=false and pull=false for registration
    # These MUST be included to match the expected payload size and structure
    registration_payload = %Proto.ClientPayload{
      userAgent: create_user_agent(config),
      webInfo: create_web_info(config),
      connectType: :WIFI_UNKNOWN,
      connectReason: :USER_ACTIVATED,
      # Explicitly set to false (required for registration)
      passive: false,
      # Explicitly set to false (required for registration)
      pull: false,
      devicePairingData: %Proto.ClientPayload.DevicePairingRegistrationData{
        buildHash: app_version_hash,
        deviceProps: device_props_binary,
        eRegid: encode_big_endian(creds.registration_id),
        eKeytype: Constants.key_bundle_type(),
        eIdent: creds.signed_identity_key.public,
        eSkeyId: encode_big_endian(creds.signed_pre_key.key_id, 3),
        eSkeyVal: creds.signed_pre_key.key_pair.public,
        eSkeySig: creds.signed_pre_key.signature
      }
    }

    registration_payload
  end

  @doc """
  Generate login node for existing sessions.

  Creates a ClientPayload for logging into an existing WhatsApp session.
  """
  @spec generate_login_node(binary(), socket_config()) :: %Proto.ClientPayload{}
  def generate_login_node(user_jid, config) do
    # Parse JID to extract user and device
    {user, device} = parse_jid(user_jid)

    login_payload = %Proto.ClientPayload{
      username: String.to_integer(user),
      passive: true,
      userAgent: create_user_agent(config),
      webInfo: create_web_info(config),
      pushName: nil,
      sessionId: nil,
      shortConnect: false,
      connectType: :WIFI_UNKNOWN,
      connectReason: :USER_ACTIVATED,
      shards: [],
      device: device,
      devicePairingData: nil,
      pull: true,
      lidDbMigrated: false
    }

    login_payload
  end

  @doc """
  Create user agent information for ClientPayload.
  """
  @spec create_user_agent(socket_config()) :: Proto.ClientPayload.UserAgent.t()
  def create_user_agent(config) do
    %Proto.ClientPayload.UserAgent{
      appVersion: %Proto.ClientPayload.UserAgent.AppVersion{
        primary: Enum.at(config.version, 0),
        secondary: Enum.at(config.version, 1),
        tertiary: Enum.at(config.version, 2)
      },
      platform: :WEB,
      releaseChannel: :RELEASE,
      osVersion: "0.1",
      device: "Desktop",
      osBuildNumber: "0.1",
      localeLanguageIso6391: "en",
      mnc: "000",
      mcc: "000",
      localeCountryIso31661Alpha2: config.country_code || "US"
    }
  end

  @doc """
  Create web info for ClientPayload.
  """
  @spec create_web_info(socket_config()) :: Proto.ClientPayload.WebInfo.t()
  def create_web_info(config) do
    web_sub_platform =
      if config.sync_full_history and is_desktop_browser(config.browser) do
        platform_to_web_sub_platform(Enum.at(config.browser, 0))
      else
        :WEB_BROWSER
      end

    %Proto.ClientPayload.WebInfo{
      webSubPlatform: web_sub_platform
    }
  end

  @doc """
  Create device properties for registration.
  """
  @spec create_device_props(socket_config()) :: Proto.DeviceProps.t()
  def create_device_props(config) do
    %Proto.DeviceProps{
      os: Enum.at(config.browser, 0),
      platformType: browser_to_platform_type(Enum.at(config.browser, 1)),
      requireFullSync: config.sync_full_history,
      historySyncConfig: %Proto.DeviceProps.HistorySyncConfig{
        storageQuotaMb: 10240,
        inlineInitialPayloadInE2EeMsg: true,
        supportCallLogHistory: false,
        supportBotUserAgentChatHistory: true,
        supportCagReactionsAndPolls: true,
        supportBizHostedMsg: true,
        supportRecentSyncChunkMessageCountTuning: true,
        supportHostedGroupMsg: true,
        supportFbidBotChatHistory: true,
        supportMessageAssociation: true,
        supportGroupHistory: false
      },
      version: %Proto.DeviceProps.AppVersion{
        primary: 10,
        secondary: 15,
        tertiary: 7
      }
    }
  end

  # Private helper functions

  defp generate_signed_pre_key(identity_key_pair) do
    # Generate pre-key (Curve25519)
    pre_key_pair = Crypto.generate_key_pair()
    pre_key_id = Crypto.generate_signed_pre_key_id()

    # Add version byte to public key for signing
    public_key_with_version = Constants.key_bundle_type() <> pre_key_pair.public

    # Sign the public key with Ed25519 identity key
    signature = Crypto.sign(public_key_with_version, identity_key_pair.private)

    %{
      key_pair: pre_key_pair,
      signature: signature,
      key_id: pre_key_id
    }
  end

  defp encode_big_endian(value, bytes \\ 4) do
    # Encode integer as big-endian binary
    <<value::size(bytes * 8)>>
  end

  defp parse_jid(jid) do
    # Parse JID like "1234567890@s.whatsapp.net" to extract user and device
    case String.split(jid, "@") do
      [user_part, _domain] ->
        case String.split(user_part, ":") do
          # Default device
          [user] -> {user, 0}
          [user, device] -> {user, String.to_integer(device)}
        end

      # Default values
      _ ->
        {"0", 0}
    end
  end

  defp is_desktop_browser(browser) do
    browser && Enum.at(browser, 1) == "Desktop"
  end

  defp platform_to_web_sub_platform(platform) do
    case platform do
      "Mac OS" -> :DARWIN
      "Windows" -> :WIN32
      _ -> :WEB_BROWSER
    end
  end

  defp browser_to_platform_type(browser_type) do
    case String.upcase(browser_type) do
      "CHROME" -> :CHROME
      "FIREFOX" -> :FIREFOX
      "SAFARI" -> :SAFARI
      "EDGE" -> :EDGE
      "DESKTOP" -> :DESKTOP
      # Default
      _ -> :CHROME
    end
  end
end
