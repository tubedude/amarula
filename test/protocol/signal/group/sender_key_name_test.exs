defmodule Amarula.Protocol.Signal.Group.SenderKeyNameTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Signal.Group.SenderKeyName

  # to_string_repr/1 pins the "group::sender::device" storage-key format the
  # sender-key store relies on.
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
end
