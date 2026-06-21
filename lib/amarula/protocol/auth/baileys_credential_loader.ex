defmodule Amarula.Protocol.Auth.BaileysCredentialLoader do
  @moduledoc """
  Utility to load Baileys-formatted credentials into Amarula format.

  This allows testing Amarula with the exact same credentials that work in Baileys.
  """

  require Logger
  alias Amarula.Protocol.Auth.Types
  alias Amarula.Protocol.Crypto.{Crypto, Constants}

  @doc """
  Load credentials from a Baileys creds.json file.

  Returns credentials in Amarula's internal format.
  """
  @spec load_from_file(String.t()) :: {:ok, Types.auth_creds()} | {:error, term()}
  def load_from_file(file_path) do
    with {:ok, content} <- read_file(file_path),
         {:ok, creds_map} <- decode_json(content) do
      convert_to_amarula_format(creds_map)
    end
  end

  defp read_file(file_path) do
    case File.read(file_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  defp decode_json(content) do
    case Jason.decode(content) do
      {:ok, creds_map} -> {:ok, creds_map}
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  @doc """
  Convert Baileys credential format to Amarula format.

  Baileys format uses Buffer wrapper objects: {"type": "Buffer", "data": "base64"}
  Amarula format uses raw binaries.
  """
  @spec convert_to_amarula_format(map()) :: {:ok, Types.auth_creds()}
  def convert_to_amarula_format(baileys_creds) do
    # Extract and convert noise key
    noise_key = extract_key_pair(baileys_creds, "noiseKey")

    # Extract and convert signed identity key
    signed_identity_key = extract_identity_key_pair(baileys_creds, "signedIdentityKey")

    # Extract and convert signed pre-key
    signed_pre_key = extract_signed_pre_key(baileys_creds)

    # Extract registration ID
    registration_id = Map.get(baileys_creds, "registrationId", 0)

    # Extract adv secret key
    adv_secret_key = extract_buffer(baileys_creds, "advSecretKey")

    # Extract pairing ephemeral key (if present)
    pairing_ephemeral_key = extract_key_pair(baileys_creds, "pairingEphemeralKeyPair")

    # Extract me (if registered)
    me = extract_me(baileys_creds)

    # Build Amarula format
    amarula_creds = %{
      noise_key: noise_key,
      signed_identity_key: signed_identity_key,
      signed_pre_key: signed_pre_key,
      registration_id: registration_id,
      adv_secret_key: adv_secret_key,
      pairing_ephemeral_key_pair: pairing_ephemeral_key,
      me: me,
      account: Map.get(baileys_creds, "account"),
      signal_identities: convert_signal_identities(baileys_creds),
      platform: Map.get(baileys_creds, "platform"),
      registered: Map.get(baileys_creds, "registered", false),
      processed_history_messages: Map.get(baileys_creds, "processedHistoryMessages", []),
      next_pre_key_id: Map.get(baileys_creds, "nextPreKeyId", 1),
      first_unuploaded_pre_key_id: Map.get(baileys_creds, "firstUnuploadedPreKeyId", 1),
      account_sync_counter: Map.get(baileys_creds, "accountSyncCounter", 0),
      account_settings: Map.get(baileys_creds, "accountSettings", %{"unarchiveChats" => false})
    }

    Logger.debug("Loaded Baileys credentials from file")

    Logger.debug(
      "Noise key public (hex): #{Base.encode16(amarula_creds.noise_key.public, case: :lower)}"
    )

    Logger.debug("Registration ID: #{amarula_creds.registration_id}")
    Logger.debug("Registered: #{amarula_creds.registered}")

    {:ok, amarula_creds}
  end

  # Extract a Curve25519 key pair from Baileys format
  defp extract_key_pair(creds_map, key) do
    case Map.get(creds_map, key) do
      nil ->
        # Generate new if missing
        Crypto.generate_key_pair()

      key_map ->
        private = extract_buffer(key_map, "private")
        public = extract_buffer(key_map, "public")
        %{private: private, public: public}
    end
  end

  # Extract the X25519 identity key pair (signs via XEd25519)
  defp extract_identity_key_pair(creds_map, key) do
    case Map.get(creds_map, key) do
      nil ->
        Crypto.generate_key_pair()

      key_map ->
        private = extract_buffer(key_map, "private")
        public = extract_buffer(key_map, "public")
        %{private: private, public: public}
    end
  end

  # Extract signed pre-key with keyId and signature
  defp extract_signed_pre_key(creds_map) do
    case Map.get(creds_map, "signedPreKey") do
      nil ->
        # Generate default signed pre-key if missing
        identity_key = extract_identity_key_pair(creds_map, "signedIdentityKey")

        signed_pre_key =
          case Code.ensure_loaded(Amarula.Protocol.Auth.AuthUtils) do
            {:module, _} ->
              # If module is loaded, we can use it, but since generate_signed_pre_key is private,
              # we'll generate it ourselves
              pre_key_pair = Crypto.generate_key_pair()
              pre_key_id = Crypto.generate_signed_pre_key_id()
              public_key_with_version = Constants.key_bundle_type() <> pre_key_pair.public
              signature = Crypto.sign(public_key_with_version, identity_key.private)
              %{key_id: pre_key_id, key_pair: pre_key_pair, signature: signature}

            _ ->
              # Fallback: generate minimal signed pre-key
              pre_key_pair = Crypto.generate_key_pair()
              %{key_id: 1, key_pair: pre_key_pair, signature: :crypto.strong_rand_bytes(64)}
          end

        signed_pre_key

      pre_key_map ->
        key_id = Map.get(pre_key_map, "keyId", 1)
        key_pair = extract_key_pair(pre_key_map, "keyPair")
        signature = extract_buffer(pre_key_map, "signature")
        %{key_id: key_id, key_pair: key_pair, signature: signature}
    end
  end

  # Extract a Buffer value from Baileys format
  # Handles both {"type": "Buffer", "data": "base64"} and plain base64 strings
  defp extract_buffer(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil ->
        nil

      %{"type" => "Buffer", "data" => base64_data} ->
        Base.decode64!(base64_data)

      base64_string when is_binary(base64_string) ->
        # Sometimes it's just a base64 string
        Base.decode64!(base64_string)

      other ->
        Logger.warning("Unexpected format for #{key}: #{inspect(other, limit: 50)}")
        nil
    end
  end

  defp extract_buffer(_map, _key), do: nil

  # Extract me (contact info) if present
  defp extract_me(creds_map) do
    case Map.get(creds_map, "me") do
      nil -> nil
      me_map -> me_map
    end
  end

  # Convert signal identities array
  defp convert_signal_identities(creds_map) do
    case Map.get(creds_map, "signalIdentities", []) do
      identities when is_list(identities) -> identities
      _ -> []
    end
  end
end
