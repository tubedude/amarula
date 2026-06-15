defmodule Amarula.Protocol.Auth.DeviceIdentity do
  @moduledoc """
  The pairing device-identity crypto: verify the primary's signed device identity,
  counter-sign it with our key, and derive the companion's signal identity. Pure
  (takes auth creds + the received identity, returns values) — extracted from
  `ConnectionManager` so the connection process keeps only socket/state concerns.

  Ported from Baileys' pair-success handling (`src/Socket/socket.ts`).
  """

  alias Amarula.Protocol.Crypto.{Constants, Crypto}
  alias Amarula.Protocol.Proto

  @doc """
  Verify the received `identity_hmac` (an `ADVSignedDeviceIdentityHMAC`) against
  our `auth_creds`, then return the account with our device signature added.
  `{:ok, signed_account}` or `{:error, reason}`.
  """
  @spec verify_and_sign(struct(), map()) :: {:ok, struct()} | {:error, term()}
  def verify_and_sign(identity_hmac, auth_creds) do
    account = Proto.ADVSignedDeviceIdentity.decode(identity_hmac.details)

    with :ok <- verify_hmac(identity_hmac, auth_creds.adv_secret_key),
         :ok <- verify_account_signature(account, auth_creds.signed_identity_key.public),
         device_signature <- device_signature(account, auth_creds.signed_identity_key) do
      {:ok, %{account | deviceSignature: device_signature}}
    end
  end

  @doc "The companion signal identity `%{identifier, identifierKey}` for `lid`."
  @spec signal_identity(String.t(), binary()) :: map()
  def signal_identity(lid, account_signature_key) do
    %{
      identifier: %{name: lid, deviceId: 0},
      identifierKey: Crypto.generate_signal_pub_key(account_signature_key)
    }
  end

  @doc """
  Encode an `ADVSignedDeviceIdentity` for the wire. Drops the account signature
  key unless `include_signature_key?` (or it's already empty).
  """
  @spec encode(struct(), boolean()) :: binary()
  def encode(account, include_signature_key?) do
    account =
      if include_signature_key? or byte_size(account.accountSignatureKey || <<>>) == 0 do
        account
      else
        %{account | accountSignatureKey: nil}
      end

    Proto.ADVSignedDeviceIdentity.encode(account)
  end

  # --- internals ---

  defp verify_hmac(identity_hmac, adv_secret_key_b64) do
    hmac_prefix =
      case identity_hmac.accountType do
        :HOSTED -> Constants.wa_adv_hosted_account_sig_prefix()
        _ -> <<>>
      end

    adv_secret_key = Base.decode64!(adv_secret_key_b64)
    expected = Crypto.hmac_sign(hmac_prefix <> identity_hmac.details, adv_secret_key)

    if identity_hmac.hmac == expected, do: :ok, else: {:error, :invalid_hmac}
  end

  defp verify_account_signature(account, signed_identity_public_key) do
    device_identity = Proto.ADVDeviceIdentity.decode(account.details)

    prefix =
      case device_identity.deviceType do
        :HOSTED -> Constants.wa_adv_hosted_account_sig_prefix()
        _ -> Constants.wa_adv_account_sig_prefix()
      end

    msg = prefix <> account.details <> signed_identity_public_key

    if Crypto.verify(msg, account.accountSignature, account.accountSignatureKey) do
      :ok
    else
      {:error, :invalid_account_signature}
    end
  end

  defp device_signature(account, signed_identity_key) do
    msg =
      Constants.wa_adv_device_sig_prefix() <>
        account.details <> signed_identity_key.public <> account.accountSignatureKey

    Crypto.sign(msg, signed_identity_key.private)
  end
end
