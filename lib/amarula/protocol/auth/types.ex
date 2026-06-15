defmodule Amarula.Protocol.Auth.Types do
  @moduledoc """
  Authentication types and data structures for WhatsApp protocol.

  This module defines the core types used throughout the authentication system,
  including credentials, session state, and device information.
  """

  @type key_pair :: %{
          public: binary(),
          private: binary()
        }

  @type signal_creds :: %{
          registration_id: integer(),
          signed_pre_key: key_pair(),
          signed_identity_key: key_pair(),
          signed_pre_key_id: integer(),
          signed_pre_key_signature: binary()
        }

  @type account_settings :: %{
          unarchive_chats: boolean() | nil,
          default_disappearing_mode: map() | nil,
          disappearing_mode_duration: integer() | nil,
          display_name: String.t() | nil,
          link_previews: boolean() | nil,
          business_verified: boolean() | nil,
          mark_read_on_return: boolean() | nil,
          call_add_to_contacts: boolean() | nil,
          pin_invite_to_parent: boolean() | nil,
          ephemeral_expiration: integer() | nil,
          ephemeral_setting_timestamp: integer() | nil
        }

  @type signal_identity :: %{
          identifier: String.t(),
          identifier_type: integer(),
          device_id: integer()
        }

  @type contact :: %{
          id: String.t(),
          name: String.t() | nil,
          notify: String.t() | nil,
          verified_name: String.t() | nil,
          img_url: String.t() | nil,
          status: String.t() | nil
        }

  @type authentication_creds :: %{
          # Signal protocol credentials
          registration_id: integer(),
          signed_pre_key: key_pair(),
          signed_identity_key: key_pair(),
          signed_pre_key_id: integer(),
          signed_pre_key_signature: binary(),

          # Noise protocol credentials
          noise_key: key_pair(),
          pairing_ephemeral_key_pair: key_pair(),
          adv_secret_key: String.t(),

          # User information
          me: contact() | nil,
          account: map() | nil,
          signal_identities: list(signal_identity()) | nil,
          my_app_state_key_id: String.t() | nil,

          # Pre-key management
          first_unuploaded_pre_key_id: integer(),
          next_pre_key_id: integer(),

          # Session state
          last_account_sync_timestamp: integer() | nil,
          platform: String.t() | nil,
          processed_history_messages: list(map()),
          account_sync_counter: integer(),
          account_settings: account_settings(),
          registered: boolean(),
          pairing_code: String.t() | nil,
          last_prop_hash: String.t() | nil,
          routing_info: binary() | nil,
          additional_data: map() | nil
        }

  @type authentication_state :: %{
          creds: authentication_creds(),
          keys: module()
        }

  @type socket_config :: %{
          wa_web_socket_url: String.t(),
          connect_timeout_ms: integer(),
          logger: module(),
          keep_alive_interval_ms: integer(),
          browser: list(String.t()),
          version: list(String.t()),
          country_code: String.t(),
          sync_full_history: boolean(),
          print_qr_in_terminal: boolean(),
          default_query_timeout_ms: integer(),
          qr_timeout: integer(),
          mobile: boolean()
        }

  @type connection_state ::
          :connecting | :open | :closed | :connecting_qr | :open_unpaired | :pairing

  @type connection_update :: %{
          connection: connection_state(),
          qr: String.t() | nil,
          last_disconnect: map() | nil,
          is_new_login: boolean() | nil,
          is_online: boolean() | nil,
          received_offline_notifications: boolean() | nil
        }

  @type device_props :: %{
          os: String.t(),
          platform_type: atom(),
          require_full_sync: boolean()
        }

  @type user_agent :: %{
          app_version: map(),
          platform: atom(),
          release_channel: atom(),
          os_version: String.t(),
          device: String.t(),
          os_build_number: String.t(),
          locale_language_iso6391: String.t(),
          mnc: String.t(),
          mcc: String.t(),
          locale_country_iso31661_alpha2: String.t()
        }

  @type web_info :: %{
          web_sub_platform: atom()
        }

  @type client_payload :: %{
          connect_type: atom(),
          connect_reason: atom(),
          user_agent: user_agent(),
          web_info: web_info() | nil,
          passive: boolean() | nil,
          pull: boolean() | nil,
          username: integer() | nil,
          device: integer() | nil,
          lid_db_migrated: boolean() | nil,
          companion: device_props() | nil
        }
end
