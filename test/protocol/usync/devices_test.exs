defmodule Amarula.Protocol.USync.DevicesTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.USync.Devices

  defp entry(jid, device_list),
    do: %{"devices" => %{device_list: device_list}, id: jid}

  defp device(id, key_index, hosted? \\ false),
    do: %{id: id, key_index: key_index, is_hosted: hosted?}

  describe "extract/4" do
    test "expands devices to per-device jids" do
      list = [entry("1234@s.whatsapp.net", [device(0, nil), device(2, 7)])]

      result = Devices.extract(list, "5555@s.whatsapp.net", nil, false)

      assert result == [
               %{user: "1234", device: 0, server: "s.whatsapp.net", jid: "1234@s.whatsapp.net"},
               %{user: "1234", device: 2, server: "s.whatsapp.net", jid: "1234:2@s.whatsapp.net"}
             ]
    end

    test "exclude_zero_devices? drops device 0" do
      list = [entry("1234@s.whatsapp.net", [device(0, nil), device(1, 3)])]

      result = Devices.extract(list, "5555@s.whatsapp.net", nil, true)

      assert Enum.map(result, & &1.device) == [1]
    end

    test "drops our own sending device but keeps our other devices" do
      # me = 1234 device 0; recipient list is our own multi-device fanout
      list = [entry("1234@s.whatsapp.net", [device(0, nil), device(5, 9)])]

      result = Devices.extract(list, "1234:0@s.whatsapp.net", nil, false)

      # device 0 (our sender) dropped, device 5 kept
      assert Enum.map(result, & &1.device) == [5]
    end

    test "matches own user via lid too" do
      list = [entry("99@lid", [device(0, nil), device(1, 2)])]

      # my lid user is 99, sending device 0 → drop 99:0, keep 99:1
      result = Devices.extract(list, "1234:0@s.whatsapp.net", "99@lid", false)

      assert Enum.map(result, & &1.device) == [1]
    end

    test "drops non-zero devices missing a key_index" do
      list = [entry("1234@s.whatsapp.net", [device(0, nil), device(3, nil), device(4, 1)])]

      result = Devices.extract(list, "5555@s.whatsapp.net", nil, false)

      # device 3 has no key_index → bad request → dropped; 0 and 4 kept
      assert Enum.map(result, & &1.device) == [0, 4]
    end

    test "returns [] for an empty result list" do
      assert Devices.extract([], "9@s.whatsapp.net", nil, false) == []
    end

    test "expands multiple users in one result" do
      list = [
        entry("1111@s.whatsapp.net", [device(0, nil)]),
        entry("2222@s.whatsapp.net", [device(0, nil), device(1, 5)])
      ]

      result = Devices.extract(list, "9@s.whatsapp.net", nil, false)

      assert Enum.map(result, & &1.jid) == [
               "1111@s.whatsapp.net",
               "2222@s.whatsapp.net",
               "2222:1@s.whatsapp.net"
             ]
    end

    test "skips entries without a device list" do
      list = [%{id: "1234@s.whatsapp.net"}, entry("5678@s.whatsapp.net", [device(0, nil)])]

      result = Devices.extract(list, "9@s.whatsapp.net", nil, false)

      assert Enum.map(result, & &1.user) == ["5678"]
    end
  end
end
