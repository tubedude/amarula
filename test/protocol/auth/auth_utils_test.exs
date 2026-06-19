defmodule Amarula.Protocol.Auth.AuthUtilsTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Auth.AuthUtils
  alias Amarula.Protocol.Crypto.Constants
  alias Amarula.Protocol.Proto

  @config %{
    version: [2, 3000, 1_035_194_821],
    browser: ["Mac OS", "Chrome", "14.4.1"],
    country_code: "BR",
    sync_full_history: true
  }

  describe "init_auth_creds/0" do
    test "mints a complete, distinct credential set" do
      creds = AuthUtils.init_auth_creds()

      assert byte_size(creds.signed_identity_key.public) == 32
      assert byte_size(creds.signed_identity_key.private) == 32
      assert is_integer(creds.registration_id)
      assert {:ok, raw} = Base.decode64(creds.adv_secret_key)
      assert byte_size(raw) == 32

      # The signed pre-key carries a signature over its own public key.
      assert byte_size(creds.signed_pre_key.key_pair.public) == 32
      assert byte_size(creds.signed_pre_key.signature) > 0
    end

    test "is random per call" do
      a = AuthUtils.init_auth_creds()
      b = AuthUtils.init_auth_creds()

      assert a.signed_identity_key.public != b.signed_identity_key.public
      assert a.adv_secret_key != b.adv_secret_key
    end
  end

  describe "generate_registration_node/2" do
    setup do
      creds = AuthUtils.init_auth_creds()
      {:ok, creds: creds, payload: AuthUtils.generate_registration_node(creds, @config)}
    end

    test "marks the payload as an active registration (passive/pull false)", %{payload: p} do
      assert p.passive == false
      assert p.pull == false
      assert p.connectReason == :USER_ACTIVATED
    end

    test "build hash is the MD5 of the dotted version string", %{payload: p} do
      expected = :crypto.hash(:md5, "2.3000.1035194821")
      assert p.devicePairingData.buildHash == expected
    end

    test "wires our credentials into the device pairing data", %{creds: creds, payload: p} do
      d = p.devicePairingData
      assert d.eIdent == creds.signed_identity_key.public
      assert d.eSkeyVal == creds.signed_pre_key.key_pair.public
      assert d.eSkeySig == creds.signed_pre_key.signature
      assert d.eKeytype == Constants.key_bundle_type()
    end

    test "the payload re-encodes through the proto round-trip", %{payload: p} do
      assert p |> Proto.ClientPayload.encode() |> Proto.ClientPayload.decode() == p
    end
  end

  describe "generate_login_node/2" do
    test "is passive, carries the username/device parsed from the jid" do
      payload = AuthUtils.generate_login_node("5511999999999:7@s.whatsapp.net", @config)

      assert payload.username == 5_511_999_999_999
      assert payload.device == 7
      assert payload.passive == true
      assert payload.pull == true
      assert payload.devicePairingData == nil
    end

    test "defaults the device to 0 when the jid has none" do
      payload = AuthUtils.generate_login_node("5511999999999@s.whatsapp.net", @config)
      assert payload.device == 0
    end
  end

  describe "create_user_agent/1" do
    test "splits the version triple into primary/secondary/tertiary" do
      ua = AuthUtils.create_user_agent(@config)

      assert ua.appVersion.primary == 2
      assert ua.appVersion.secondary == 3000
      assert ua.appVersion.tertiary == 1_035_194_821
      assert ua.platform == :WEB
    end

    test "carries the configured country code" do
      ua = AuthUtils.create_user_agent(@config)
      assert ua.localeCountryIso31661Alpha2 == "BR"
    end

    test "falls back to US when no country code is set" do
      ua = AuthUtils.create_user_agent(%{@config | country_code: nil})
      assert ua.localeCountryIso31661Alpha2 == "US"
    end
  end

  describe "create_device_props/1" do
    test "reflects the browser triple and full-sync flag" do
      props = AuthUtils.create_device_props(@config)

      assert props.os == "Mac OS"
      assert props.requireFullSync == true
    end

    test "requireFullSync follows sync_full_history" do
      props = AuthUtils.create_device_props(%{@config | sync_full_history: false})
      assert props.requireFullSync == false
    end
  end

  describe "create_web_info/1" do
    test "is a plain web browser when not doing a full desktop sync" do
      info = AuthUtils.create_web_info(%{@config | sync_full_history: false})
      assert info.webSubPlatform == :WEB_BROWSER
    end
  end
end
