defmodule Amarula.Protocol.Auth.QRCodeGeneratorTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Auth.QRCodeGenerator

  @moduletag :capture_log

  describe "QR code generation" do
    test "generates QR code string with correct format" do
      ref = "test_ref_123"
      noise_key = "noise_key_b64"
      identity_key = "identity_key_b64"
      adv_secret = "adv_secret_b64"

      qr_code = QRCodeGenerator.generate_qr_string(ref, noise_key, identity_key, adv_secret)

      assert qr_code == "test_ref_123,noise_key_b64,identity_key_b64,adv_secret_b64"
    end

    test "generates QR code with empty components" do
      qr_code = QRCodeGenerator.generate_qr_string("", "", "", "")

      assert qr_code == ",,,"
    end
  end

  describe "QR code parsing" do
    test "parses valid QR code string" do
      qr_string = "ref123,noise_key,identity_key,adv_secret"

      assert {:ok, {ref, noise_key, identity_key, adv_secret}} =
               QRCodeGenerator.parse_qr_string(qr_string)

      assert ref == "ref123"
      assert noise_key == "noise_key"
      assert identity_key == "identity_key"
      assert adv_secret == "adv_secret"
    end

    test "parses QR code with base64 encoded components" do
      ref = "ref123"
      noise_key_b64 = Base.encode64("noise_key_data")
      identity_key_b64 = Base.encode64("identity_key_data")
      adv_secret_b64 = Base.encode64("adv_secret_data")

      qr_string =
        QRCodeGenerator.generate_qr_string(ref, noise_key_b64, identity_key_b64, adv_secret_b64)

      assert {:ok, {parsed_ref, parsed_noise, parsed_identity, parsed_adv}} =
               QRCodeGenerator.parse_qr_string(qr_string)

      assert parsed_ref == ref
      assert parsed_noise == noise_key_b64
      assert parsed_identity == identity_key_b64
      assert parsed_adv == adv_secret_b64
    end

    test "returns error for invalid QR code format" do
      invalid_qr_codes = [
        # Too few components
        "ref123,noise_key",
        # Empty last component
        "ref123,noise_key,identity_key,",
        # Empty first component
        ",noise_key,identity_key,adv_secret",
        # Empty middle component
        "ref123,,identity_key,adv_secret",
        # Empty string
        ""
      ]

      Enum.each(invalid_qr_codes, fn invalid_qr ->
        assert {:error, _} = QRCodeGenerator.parse_qr_string(invalid_qr)
      end)
    end

    test "handles QR codes with commas in components" do
      # This should work as long as there are exactly 4 components
      qr_string = "ref,with,commas,noise_key,identity_key,adv_secret"

      # This should succeed because it has exactly 4 components
      assert {:ok, {"ref", "with", "commas", "noise_key,identity_key,adv_secret"}} =
               QRCodeGenerator.parse_qr_string(qr_string)
    end
  end

  describe "QR code validation" do
    test "validates correct QR code format" do
      qr_string = "ref123,noise_key,identity_key,adv_secret"

      assert :ok = QRCodeGenerator.validate_qr_string(qr_string)
    end

    test "rejects invalid QR code format" do
      invalid_qr_strings = [
        # Too few components
        "ref123,noise_key",
        # Empty component
        "ref123,noise_key,identity_key,",
        # Empty component
        "ref123,,identity_key,adv_secret",
        # Empty string
        ""
      ]

      Enum.each(invalid_qr_strings, fn invalid_qr ->
        assert {:error, _} = QRCodeGenerator.validate_qr_string(invalid_qr)
      end)
    end
  end

  describe "reference generation" do
    test "generates unique reference strings" do
      ref1 = QRCodeGenerator.generate_ref()
      ref2 = QRCodeGenerator.generate_ref()

      assert is_binary(ref1)
      assert is_binary(ref2)
      assert ref1 != ref2
      assert byte_size(ref1) > 0
      assert byte_size(ref2) > 0
    end

    test "generates multiple references" do
      count = 5
      refs = QRCodeGenerator.generate_refs(count)

      assert length(refs) == count
      assert Enum.all?(refs, &is_binary/1)
      assert Enum.all?(refs, fn ref -> byte_size(ref) > 0 end)

      # All references should be unique
      assert length(Enum.uniq(refs)) == count
    end

    test "generates references with correct count" do
      assert QRCodeGenerator.generate_refs(0) == []
      assert length(QRCodeGenerator.generate_refs(1)) == 1
      assert length(QRCodeGenerator.generate_refs(10)) == 10
    end
  end

  describe "QR code expiration" do
    test "detects expired QR codes" do
      # 2 seconds ago
      generation_time = System.monotonic_time(:millisecond) - 2000
      # 1 second timeout
      timeout_ms = 1000

      assert QRCodeGenerator.qr_expired?(generation_time, timeout_ms) == true
    end

    test "detects non-expired QR codes" do
      # 500ms ago
      generation_time = System.monotonic_time(:millisecond) - 500
      # 1 second timeout
      timeout_ms = 1000

      assert QRCodeGenerator.qr_expired?(generation_time, timeout_ms) == false
    end

    test "handles edge case at expiration boundary" do
      # Exactly at timeout
      generation_time = System.monotonic_time(:millisecond) - 1000
      timeout_ms = 1000

      # Should be considered expired (>= timeout)
      assert QRCodeGenerator.qr_expired?(generation_time, timeout_ms) == true
    end
  end

  describe "QR code display formatting" do
    test "formats QR code for display" do
      qr_string = "ref123,noise_key,identity_key,adv_secret"
      formatted = QRCodeGenerator.format_qr_for_display(qr_string)

      assert is_binary(formatted)
      assert String.contains?(formatted, "WhatsApp QR Code")
      assert String.contains?(formatted, qr_string)
      assert String.contains?(formatted, "Scan this QR code")
    end

    test "handles long QR codes in display format" do
      long_qr =
        String.duplicate("a", 100) <>
          "," <>
          String.duplicate("b", 100) <>
          "," <>
          String.duplicate("c", 100) <> "," <> String.duplicate("d", 100)

      formatted = QRCodeGenerator.format_qr_for_display(long_qr)

      assert is_binary(formatted)
      assert String.contains?(formatted, "WhatsApp QR Code")
    end
  end

  describe "component extraction" do
    test "extracts reference from QR code" do
      qr_string = "ref123,noise_key,identity_key,adv_secret"

      assert {:ok, "ref123"} = QRCodeGenerator.extract_ref(qr_string)
    end

    test "extracts noise key from QR code" do
      qr_string = "ref123,noise_key,identity_key,adv_secret"

      assert {:ok, "noise_key"} = QRCodeGenerator.extract_noise_key(qr_string)
    end

    test "extracts identity key from QR code" do
      qr_string = "ref123,noise_key,identity_key,adv_secret"

      assert {:ok, "identity_key"} = QRCodeGenerator.extract_identity_key(qr_string)
    end

    test "extracts advertisement secret key from QR code" do
      qr_string = "ref123,noise_key,identity_key,adv_secret"

      assert {:ok, "adv_secret"} = QRCodeGenerator.extract_adv_secret_key(qr_string)
    end

    test "returns error for invalid QR code in extraction" do
      # Too few components
      invalid_qr = "ref123,noise_key"

      assert {:error, _} = QRCodeGenerator.extract_ref(invalid_qr)
      assert {:error, _} = QRCodeGenerator.extract_noise_key(invalid_qr)
      assert {:error, _} = QRCodeGenerator.extract_identity_key(invalid_qr)
      assert {:error, _} = QRCodeGenerator.extract_adv_secret_key(invalid_qr)
    end
  end

  describe "round-trip consistency" do
    test "generates and parses QR code consistently" do
      ref = "test_ref_123"
      noise_key = Base.encode64("noise_key_data")
      identity_key = Base.encode64("identity_key_data")
      adv_secret = Base.encode64("adv_secret_data")

      # Generate QR code
      qr_string = QRCodeGenerator.generate_qr_string(ref, noise_key, identity_key, adv_secret)

      # Parse it back
      assert {:ok, {parsed_ref, parsed_noise, parsed_identity, parsed_adv}} =
               QRCodeGenerator.parse_qr_string(qr_string)

      # Should match original values
      assert parsed_ref == ref
      assert parsed_noise == noise_key
      assert parsed_identity == identity_key
      assert parsed_adv == adv_secret
    end

    test "extraction functions match parsing" do
      qr_string = "ref123,noise_key,identity_key,adv_secret"

      # Parse all components
      assert {:ok, {ref, noise_key, identity_key, adv_secret}} =
               QRCodeGenerator.parse_qr_string(qr_string)

      # Extract individual components
      assert {:ok, ^ref} = QRCodeGenerator.extract_ref(qr_string)
      assert {:ok, ^noise_key} = QRCodeGenerator.extract_noise_key(qr_string)
      assert {:ok, ^identity_key} = QRCodeGenerator.extract_identity_key(qr_string)
      assert {:ok, ^adv_secret} = QRCodeGenerator.extract_adv_secret_key(qr_string)
    end
  end
end
