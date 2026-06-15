defmodule Amarula.Config do
  @moduledoc """
  Connection config defaults.

  A consumer supplies only what differs (at minimum `:profile`); `merge/1` fills
  the rest. This is the single source of truth for protocol/connection tunables,
  so examples and callers don't repeat them. The WhatsApp Web `:version` MUST
  track the pinned Baileys version (`src/Defaults/index.ts`) or the server
  rejects the handshake.
  """

  @defaults %{
    wa_websocket_url: "wss://web.whatsapp.com/ws/chat",
    version: [2, 3000, 1_035_194_821],
    browser: ["Mac OS", "Chrome", "14.4.1"],
    # connection tunables
    max_retries: 5,
    retry_delay: 1000,
    connect_timeout_ms: 30_000,
    keep_alive_interval_ms: 30_000,
    fire_init_queries: true,
    mark_online_on_connect: true,
    sync_full_history: true,
    country_code: "US",
    # http/ws handshake
    headers: [],
    origin: "https://web.whatsapp.com",
    agent: nil
  }

  @doc "The default config map (without `:profile`/`:auth`/`:storage`, which are caller-supplied)."
  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc "Merge `config` over the defaults (caller values win)."
  @spec merge(map()) :: map()
  def merge(config) when is_map(config), do: Map.merge(@defaults, config)
end
