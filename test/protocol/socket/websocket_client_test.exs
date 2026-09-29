defmodule Amarula.Protocol.Socket.WebSocketClientTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Socket.WebSocketClient

  @origin "https://web.whatsapp.com"

  describe "build_headers/2" do
    test "adds Origin, and nothing else, when headers carries none" do
      assert WebSocketClient.build_headers([], @origin) == [{"Origin", @origin}]
    end

    test "accepts headers given as a map" do
      headers = WebSocketClient.build_headers(%{"X-Custom" => "1"}, @origin)

      assert {"X-Custom", "1"} in headers
      assert {"Origin", @origin} in headers
      assert length(headers) == 2
    end

    test "an explicit Origin in headers wins, case-insensitively" do
      headers = WebSocketClient.build_headers([{"origin", "https://custom.example.com"}], @origin)

      assert headers == [{"origin", "https://custom.example.com"}]
    end

    test "matches an atom header key case-insensitively too" do
      headers = WebSocketClient.build_headers([{:Origin, "https://custom.example.com"}], @origin)

      assert headers == [{:Origin, "https://custom.example.com"}]
    end

    test "unrelated caller headers are preserved alongside Origin" do
      headers = WebSocketClient.build_headers([{"X-Custom", "value"}], @origin)

      assert headers == [{"X-Custom", "value"}, {"Origin", @origin}]
    end

    test "never adds a User-Agent" do
      refute Enum.any?(WebSocketClient.build_headers([], @origin), fn {k, _} ->
               k |> to_string() |> String.downcase() == "user-agent"
             end)
    end

    test "tolerates a malformed headers value" do
      assert WebSocketClient.build_headers(:garbage, @origin) == [{"Origin", @origin}]
    end
  end
end
