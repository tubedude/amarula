defmodule Amarula.Config do
  @wa_version [2, 3000, 1_035_194_821]

  @moduledoc """
  Connection config + the single source of truth for protocol/connection defaults.

  There are two kinds of configuration:

  ## 1. Per-connection config — passed to `Amarula.new/1`

  A map; you supply only what differs (at minimum `:profile`), `merge/1` fills the
  rest from the defaults below.

  | Key | Default | Meaning |
  |-----|---------|---------|
  | `:profile` | — (**required**) | names + scopes this account's stored state |
  | `:storage` | `{Amarula.Storage.File, root: AMARULA_DATA_DIR || "./amarula_data"}` | storage backend `{module, opts}` |
  | `:retry_cache` | ETS (see `Amarula.RetryCache`) | sent-message cache backend |
  | `:registry` | `Amarula.ProfileRegistry` (local) | `{module, name}` or bare `name` for the profile→connection registry; swap for `Horde.Registry` to enforce one-conn-per-profile cluster-wide (default: per node). See `Amarula.ProfileRegistry` |
  | `:auth` | loaded from storage | explicit creds (advanced; normally Amarula loads/persists these itself) |
  | `:version` | `#{inspect(@wa_version)}` | WhatsApp Web *protocol* version — MUST track `src/Defaults/index.ts` or the handshake is rejected. (Distinct from Baileys *source* parity — see `Amarula.Baileys` / `docs/PARITY.md`.) |
  | `:browser` | `["Mac OS", "Chrome", "14.4.1"]` | browser triple `[os, client, version]` shown as the linked device. If the **client** (2nd element) contains `"Android"` (case-insensitive, e.g. `["MyApp", "Android", ""]`), the connection registers as an **Android client** instead of WhatsApp Web — see the impact note below. |
  | `:max_retries` | `5` | reconnect attempts |
  | `:retry_delay` | `1000` | base reconnect backoff (ms) |
  | `:connect_timeout_ms` | `30_000` | WebSocket connect timeout |
  | `:keep_alive_interval_ms` | `30_000` | WA-level keep-alive ping interval |
  | `:sync_full_history` | `true` | request full history on link |
  | `:mark_online_on_connect` | `true` | send presence available on connect |
  | `:fire_init_queries` | `true` | run the post-login init IQ queries |
  | `:country_code` | `"US"` | |
  | `:headers` / `:origin` / `:agent` | see defaults | HTTP/WS handshake |

      Amarula.new(%{profile: :me, sync_full_history: false}) |> Amarula.connect()

  ### Android browser mode (impact)

  Setting an Android `:browser` (e.g. `["MyApp", "Android", ""]`) registers the
  linked device as an **Android client** rather than WhatsApp Web. This changes
  the registration/login payload in three ways (mirroring Baileys #2201):

    * `ClientPayload.userAgent.platform` becomes `:ANDROID` (not `:WEB`).
    * `webInfo` is **omitted** (it's a web-client field).
    * `DeviceProps.platformType` becomes `:ANDROID_PHONE`.

  **Why you'd opt in:** an Android-registered session can **receive view-once
  media** that a Web session cannot.

  **Costs / caveats — opt in deliberately:**

    * **Experimental.** This is a newer, less-exercised WhatsApp path; upstream
      labels it experimental ("use at your own risk"). It may behave unexpectedly
      or be tightened by WhatsApp.
    * **The device shows as a phone/Android client**, not a desktop browser, in
      the user's "Linked devices" list.
    * Default (any non-Android `:browser`) is unchanged — full Web behaviour,
      `webInfo` sent, `platform: :WEB`. Existing configs are unaffected.

  ## 2. App-global config — `config :amarula, ...`

  Only the pluggable seams (apply to every connection that doesn't override them):

      config :amarula, :default_storage_adapter, Amarula.Storage.File
      config :amarula, :retry_cache_adapter, Amarula.RetryCache.ETS

  ## Logging

  Amarula logs through Elixir's `Logger`. Almost everything is `:debug`; only
  connection lifecycle, pairing, and errors are `:info`/`:warning`/`:error`. To
  keep your dev console clean, set the global level — or silence Amarula
  specifically without affecting your own logs:

      # your app's config
      config :logger, level: :info

      # or, mute just Amarula (Elixir 1.13+):
      Logger.put_module_level(Amarula.Connection, :warning)

  Telemetry (`Amarula.Telemetry`) is the structured, log-independent way to observe
  Amarula in production.
  """

  @defaults %{
    wa_websocket_url: "wss://web.whatsapp.com/ws/chat",
    version: @wa_version,
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
