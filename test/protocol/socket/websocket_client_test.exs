defmodule Amarula.Protocol.Socket.WebSocketClientTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Socket.WebSocketClient

  describe "build_headers/3" do
    test "sends Origin and User-Agent on the opening handshake" do
      headers = WebSocketClient.build_headers([], "https://web.whatsapp.com", "Mozilla/5.0")

      assert {"Origin", "https://web.whatsapp.com"} in headers
      assert {"User-Agent", "Mozilla/5.0"} in headers
    end

    test "accepts headers given as a map" do
      headers =
        WebSocketClient.build_headers(
          %{"X-Custom" => "1"},
          "https://web.whatsapp.com",
          "Mozilla/5.0"
        )

      assert {"X-Custom", "1"} in headers
      assert {"Origin", "https://web.whatsapp.com"} in headers
      assert {"User-Agent", "Mozilla/5.0"} in headers
    end

    test "keeps caller-supplied headers instead of overriding them" do
      headers =
        WebSocketClient.build_headers(
          [{"User-Agent", "CustomAgent/1.0"}],
          "https://web.whatsapp.com",
          "Mozilla/5.0"
        )

      assert {"User-Agent", "CustomAgent/1.0"} in headers
      refute {"User-Agent", "Mozilla/5.0"} in headers
    end

    test "matches caller headers case-insensitively so none are duplicated" do
      headers =
        WebSocketClient.build_headers(
          [{"user-agent", "CustomAgent/1.0"}, {"origin", "https://example.com"}],
          "https://web.whatsapp.com",
          "Mozilla/5.0"
        )

      assert Enum.count(headers, fn {k, _} -> String.downcase(k) == "user-agent" end) == 1
      assert Enum.count(headers, fn {k, _} -> String.downcase(k) == "origin" end) == 1
    end

    test "tolerates a malformed :headers value" do
      assert [{"Origin", _}, {"User-Agent", _}] =
               WebSocketClient.build_headers(:garbage, "https://web.whatsapp.com", "Mozilla/5.0")
    end
  end
end
