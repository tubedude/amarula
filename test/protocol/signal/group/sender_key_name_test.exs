defmodule Amarula.Protocol.Signal.Group.SenderKeyNameTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Signal.Group.SenderKeyName

  describe "new/3" do
    test "creates a new SenderKeyName" do
      sender_key_name = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)

      assert sender_key_name.group_id == "group123"
      assert sender_key_name.sender.id == "user@s.whatsapp.net"
      assert sender_key_name.sender.device_id == 0
    end

    test "creates SenderKeyName with different device ID" do
      sender_key_name = SenderKeyName.new("group456", "user@s.whatsapp.net", 1)

      assert sender_key_name.group_id == "group456"
      assert sender_key_name.sender.id == "user@s.whatsapp.net"
      assert sender_key_name.sender.device_id == 1
    end
  end

  describe "to_string_repr/1" do
    test "converts SenderKeyName to string" do
      sender_key_name = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)
      string_repr = SenderKeyName.to_string_repr(sender_key_name)

      assert string_repr == "group123::user@s.whatsapp.net::0"
    end

    test "handles different device IDs" do
      sender_key_name = SenderKeyName.new("group456", "user@s.whatsapp.net", 42)
      string_repr = SenderKeyName.to_string_repr(sender_key_name)

      assert string_repr == "group456::user@s.whatsapp.net::42"
    end
  end

  describe "from_string/1" do
    test "parses valid string representation" do
      string = "group123::user@s.whatsapp.net::0"

      assert {:ok, sender_key_name} = SenderKeyName.from_string(string)
      assert sender_key_name.group_id == "group123"
      assert sender_key_name.sender.id == "user@s.whatsapp.net"
      assert sender_key_name.sender.device_id == 0
    end

    test "parses string with different device ID" do
      string = "group456::user@s.whatsapp.net::42"

      assert {:ok, sender_key_name} = SenderKeyName.from_string(string)
      assert sender_key_name.group_id == "group456"
      assert sender_key_name.sender.id == "user@s.whatsapp.net"
      assert sender_key_name.sender.device_id == 42
    end

    test "returns error for invalid format" do
      assert {:error, "Invalid SenderKeyName format: invalid"} =
               SenderKeyName.from_string("invalid")

      assert {:error, "Invalid SenderKeyName format: group::user"} =
               SenderKeyName.from_string("group::user")
    end

    test "returns error for invalid device ID" do
      assert {:error, "Invalid device ID: abc"} = SenderKeyName.from_string("group::user::abc")
    end
  end

  describe "hash_code/1" do
    test "generates consistent hash codes" do
      sender_key_name = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)
      hash1 = SenderKeyName.hash_code(sender_key_name)
      hash2 = SenderKeyName.hash_code(sender_key_name)

      assert hash1 == hash2
    end

    test "generates different hash codes for different names" do
      name1 = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)
      name2 = SenderKeyName.new("group456", "user@s.whatsapp.net", 0)

      hash1 = SenderKeyName.hash_code(name1)
      hash2 = SenderKeyName.hash_code(name2)

      assert hash1 != hash2
    end

    test "generates different hash codes for different device IDs" do
      name1 = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)
      name2 = SenderKeyName.new("group123", "user@s.whatsapp.net", 1)

      hash1 = SenderKeyName.hash_code(name1)
      hash2 = SenderKeyName.hash_code(name2)

      assert hash1 != hash2
    end
  end

  describe "equal?/2" do
    test "returns true for identical SenderKeyNames" do
      name1 = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)
      name2 = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)

      assert SenderKeyName.equal?(name1, name2)
    end

    test "returns false for different group IDs" do
      name1 = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)
      name2 = SenderKeyName.new("group456", "user@s.whatsapp.net", 0)

      refute SenderKeyName.equal?(name1, name2)
    end

    test "returns false for different sender IDs" do
      name1 = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)
      name2 = SenderKeyName.new("group123", "other@s.whatsapp.net", 0)

      refute SenderKeyName.equal?(name1, name2)
    end

    test "returns false for different device IDs" do
      name1 = SenderKeyName.new("group123", "user@s.whatsapp.net", 0)
      name2 = SenderKeyName.new("group123", "user@s.whatsapp.net", 1)

      refute SenderKeyName.equal?(name1, name2)
    end
  end

  describe "round-trip conversion" do
    test "from_string and to_string_repr are inverse operations" do
      original = SenderKeyName.new("group123", "user@s.whatsapp.net", 42)
      string_repr = SenderKeyName.to_string_repr(original)

      assert {:ok, reconstructed} = SenderKeyName.from_string(string_repr)
      assert SenderKeyName.equal?(original, reconstructed)
    end
  end
end
