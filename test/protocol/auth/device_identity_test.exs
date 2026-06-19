defmodule Amarula.Protocol.Auth.DeviceIdentityTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Auth.{AuthUtils, DeviceIdentity}
  alias Amarula.Protocol.Crypto.{Constants, Crypto}
  alias Amarula.Protocol.Proto

  # Build a primary-signed ADVSignedDeviceIdentityHMAC exactly as the phone would,
  # so verify_and_sign/2 has a genuinely valid input to accept (and we can tamper
  # each field to drive the rejection branches). No mocks — real curve ops.
  defp valid_identity(creds, opts \\ []) do
    account_type = Keyword.get(opts, :account_type, :E2EE)

    # The "primary" account signature keypair (the phone's), separate from our creds.
    account_kp = Crypto.generate_key_pair()

    device_identity =
      Proto.ADVDeviceIdentity.encode(%Proto.ADVDeviceIdentity{
        rawId: 1,
        timestamp: 1_700_000_000,
        keyIndex: 1,
        accountType: account_type,
        deviceType: account_type
      })

    sig_prefix =
      case account_type do
        :HOSTED -> Constants.wa_adv_hosted_account_sig_prefix()
        _ -> Constants.wa_adv_account_sig_prefix()
      end

    account_signature =
      Crypto.sign(
        sig_prefix <> device_identity <> creds.signed_identity_key.public,
        account_kp.private
      )

    details =
      Proto.ADVSignedDeviceIdentity.encode(%Proto.ADVSignedDeviceIdentity{
        details: device_identity,
        accountSignatureKey: account_kp.public,
        accountSignature: account_signature
      })

    hmac_prefix =
      case account_type do
        :HOSTED -> Constants.wa_adv_hosted_account_sig_prefix()
        _ -> <<>>
      end

    hmac =
      Crypto.hmac_sign(hmac_prefix <> details, Base.decode64!(creds.adv_secret_key))

    %Proto.ADVSignedDeviceIdentityHMAC{
      details: details,
      hmac: hmac,
      accountType: account_type
    }
  end

  setup do
    {:ok, creds: AuthUtils.init_auth_creds()}
  end

  describe "verify_and_sign/2" do
    test "accepts a correctly-signed identity and adds our device signature", %{creds: creds} do
      hmac = valid_identity(creds)

      assert {:ok, signed} = DeviceIdentity.verify_and_sign(hmac, creds)
      assert is_binary(signed.deviceSignature)
      assert byte_size(signed.deviceSignature) > 0

      # The device signature we add must verify against our own identity key over
      # the device-sig-prefixed message.
      msg =
        Constants.wa_adv_device_sig_prefix() <>
          signed.details <> creds.signed_identity_key.public <> signed.accountSignatureKey

      assert Crypto.verify(msg, signed.deviceSignature, creds.signed_identity_key.public)
    end

    test "rejects a tampered hmac", %{creds: creds} do
      hmac = valid_identity(creds)
      bad = %{hmac | hmac: :crypto.strong_rand_bytes(byte_size(hmac.hmac))}

      assert {:error, :invalid_hmac} = DeviceIdentity.verify_and_sign(bad, creds)
    end

    test "rejects an hmac computed under a different adv_secret_key", %{creds: creds} do
      # Valid against other_creds, presented against creds → hmac mismatch.
      other = AuthUtils.init_auth_creds()
      hmac = valid_identity(other)

      assert {:error, :invalid_hmac} = DeviceIdentity.verify_and_sign(hmac, creds)
    end

    test "rejects a bad account signature (hmac ok, signature wrong)", %{creds: creds} do
      hmac = valid_identity(creds)
      account = Proto.ADVSignedDeviceIdentity.decode(hmac.details)

      tampered_details =
        Proto.ADVSignedDeviceIdentity.encode(%{
          account
          | accountSignature: :crypto.strong_rand_bytes(64)
        })

      # Recompute the hmac so it stays valid; only the inner signature is broken.
      new_hmac = Crypto.hmac_sign(tampered_details, Base.decode64!(creds.adv_secret_key))
      bad = %{hmac | details: tampered_details, hmac: new_hmac}

      assert {:error, :invalid_account_signature} = DeviceIdentity.verify_and_sign(bad, creds)
    end

    test "handles a HOSTED account (different sig prefixes)", %{creds: creds} do
      hmac = valid_identity(creds, account_type: :HOSTED)

      assert {:ok, signed} = DeviceIdentity.verify_and_sign(hmac, creds)
      assert is_binary(signed.deviceSignature)
    end
  end

  describe "signal_identity/2" do
    test "wraps the lid and a 33-byte signal pub key" do
      kp = Crypto.generate_key_pair()
      identity = DeviceIdentity.signal_identity("12345@lid", kp.public)

      assert identity.identifier == %{name: "12345@lid", deviceId: 0}
      assert byte_size(identity.identifierKey) == 33
    end
  end

  describe "encode/2" do
    setup %{creds: creds} do
      {:ok, signed} = DeviceIdentity.verify_and_sign(valid_identity(creds), creds)
      {:ok, account: signed}
    end

    test "keeps the account signature key when asked", %{account: account} do
      bin = DeviceIdentity.encode(account, true)
      decoded = Proto.ADVSignedDeviceIdentity.decode(bin)

      assert decoded.accountSignatureKey == account.accountSignatureKey
      assert byte_size(decoded.accountSignatureKey) > 0
    end

    test "drops the account signature key when not asked", %{account: account} do
      bin = DeviceIdentity.encode(account, false)
      decoded = Proto.ADVSignedDeviceIdentity.decode(bin)

      assert decoded.accountSignatureKey in [nil, <<>>]
    end

    test "round-trips details and signatures regardless of the key flag", %{account: account} do
      decoded = account |> DeviceIdentity.encode(true) |> Proto.ADVSignedDeviceIdentity.decode()

      assert decoded.details == account.details
      assert decoded.accountSignature == account.accountSignature
      assert decoded.deviceSignature == account.deviceSignature
    end
  end
end
