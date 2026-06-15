defmodule Amarula.Protocol.Signal.Types do
  @moduledoc """
  Core Signal Protocol types and data structures.

  Defines all the data structures used in the Signal Protocol implementation,
  including keys, sessions, addresses, and encryption options.
  """

  # ============================================================================
  # Core Key Types
  # ============================================================================

  @type key_pair :: %{
          public: binary(),
          private: binary()
        }

  @type signed_key_pair :: %{
          key_pair: key_pair(),
          signature: binary(),
          key_id: non_neg_integer(),
          timestamp_s: non_neg_integer() | nil
        }

  @type pre_key :: %{
          key_id: non_neg_integer(),
          public_key: binary()
        }

  @type signed_pre_key ::
          pre_key()
          | %{
              signature: binary()
            }

  # ============================================================================
  # Protocol Address and Identity
  # ============================================================================

  @type protocol_address :: %{
          # JID
          name: String.t(),
          device_id: non_neg_integer()
        }

  @type signal_identity :: %{
          identifier: protocol_address(),
          identifier_key: binary()
        }

  @type signal_creds :: %{
          signed_identity_key: key_pair(),
          signed_pre_key: signed_key_pair(),
          registration_id: non_neg_integer()
        }

  # ============================================================================
  # Session Types
  # ============================================================================

  @type e2e_session :: %{
          registration_id: non_neg_integer(),
          identity_key: binary(),
          signed_pre_key: signed_pre_key(),
          pre_key: pre_key()
        }

  @type session_state :: :active | :inactive | :pending | :expired

  @type session_info :: %{
          jid: String.t(),
          state: session_state(),
          created_at: DateTime.t(),
          last_used: DateTime.t() | nil,
          message_count: non_neg_integer()
        }

  # ============================================================================
  # LID Mapping Types
  # ============================================================================

  @type lid_mapping :: %{
          # Phone number
          pn: String.t(),
          # LID (Local ID)
          lid: String.t()
        }

  @type lid_mapping_result :: %{
          mappings: [lid_mapping()],
          missing: [String.t()]
        }

  # ============================================================================
  # Encryption/Decryption Options
  # ============================================================================

  @type message_type :: :pkmsg | :msg

  @type decrypt_opts :: %{
          jid: String.t(),
          type: message_type(),
          ciphertext: binary()
        }

  @type encrypt_opts :: %{
          jid: String.t(),
          data: binary()
        }

  @type encrypt_result :: %{
          type: message_type(),
          ciphertext: binary()
        }

  @type decrypt_group_opts :: %{
          group: String.t(),
          author_jid: String.t(),
          msg: binary()
        }

  @type encrypt_group_opts :: %{
          group: String.t(),
          data: binary(),
          me_id: String.t()
        }

  @type encrypt_group_result :: %{
          sender_key_distribution_message: binary(),
          ciphertext: binary()
        }

  # ============================================================================
  # Key Store Types
  # ============================================================================

  @type key_type :: :session | :prekey | :identity | :sender_key

  @type key_store_opts :: %{
          table_name: atom(),
          cleanup_interval: non_neg_integer(),
          max_size: non_neg_integer()
        }

  @type key_store_result :: %{
          success: boolean(),
          data: any() | nil,
          error: String.t() | nil
        }

  # ============================================================================
  # Validation Results
  # ============================================================================

  @type validation_result :: %{
          exists: boolean(),
          reason: String.t() | nil
        }

  @type migration_result :: %{
          migrated: non_neg_integer(),
          skipped: non_neg_integer(),
          total: non_neg_integer()
        }

  # ============================================================================
  # Error Types
  # ============================================================================

  @type signal_error :: %{
          type: atom(),
          message: String.t(),
          details: map() | nil
        }

  # ============================================================================
  # Configuration Types
  # ============================================================================

  @type signal_config :: %{
          key_store: key_store_opts(),
          session_timeout: non_neg_integer(),
          max_sessions: non_neg_integer(),
          enable_lid_mapping: boolean(),
          cache_ttl: non_neg_integer()
        }
end
