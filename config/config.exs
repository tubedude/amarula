import Config

config :amarula, :websocket_url, "wss://web.whatsapp.com/ws/chat"
config :amarula, :connect_timeout_ms, 30_000
config :amarula, :keep_alive_interval_ms, 30_000

config :amarula, :browser, %{
  "User-Agent" =>
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Origin" => "https://web.whatsapp.com"
}

config :amarula, :auth, %{}
config :amarula, :print_qr_in_terminal, true
config :amarula, :default_query_timeout_ms, 60_000

config :logger, level: :debug
