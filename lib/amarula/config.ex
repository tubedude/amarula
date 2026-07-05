defmodule Amarula.Config do
  @wa_version [2, 3000, 1_042_537_629]

  @moduledoc """
  Connection config + the single source of truth for protocol/connection defaults.

  There are two kinds of configuration:

  ## 1. Per-connection config — passed to `Amarula.new/1`

  A map; you supply only what differs (at minimum `:profile`), `merge/1` fills the
  rest from the defaults below.

  | Key | Default | Meaning |
  |-----|---------|---------|
  | `:profile` | — (**required**) | names + scopes this account's stored state |
  | `:storage` | `{Amarula.Storage.File, root: "./amarula_data"}` (root uses `AMARULA_DATA_DIR` when set) | storage backend `{module, opts}` |
  | `:retry_cache` | ETS (see `Amarula.RetryCache`) | sent-message cache backend + opts, e.g. `{Amarula.RetryCache.ETS, max_entries: 1000}` to raise the cap (default 200, evicts oldest). See `Amarula.RetryCache` |
  | `:registry` | `Amarula.ProfileRegistry` (local) | `{module, name}` or bare `name` for the profile→connection registry; swap for `Horde.Registry` to enforce one-conn-per-profile cluster-wide (default: per node). See `Amarula.ProfileRegistry` |
  | `:auth` | loaded from storage | explicit creds (advanced; normally Amarula loads/persists these itself) |
  | `:version` | `#{inspect(@wa_version)}` | WhatsApp Web *protocol* version — MUST track a version WhatsApp still accepts or the handshake is rejected. The live value drifts; override the pinned default without recompiling via the `AMARULA_WA_VERSION` env var (see `wa_version/0`), or bump the pinned literal with `mix run scripts/update_wa_version.exs`. (Distinct from Baileys *source* parity — see `Amarula.Baileys` / `docs/PARITY.md`.) |
  | `:browser` | `["Mac OS", "Chrome", "14.4.1"]` | browser triple `[os, client, version]` shown as the linked device. If the **client** (2nd element) contains `"Android"` (case-insensitive, e.g. `["MyApp", "Android", ""]`), the connection registers as an **Android client** instead of WhatsApp Web — see the impact note below. |
  | `:max_retries` | `5` | reconnect attempts |
  | `:retry_delay` | `1000` | base reconnect backoff (ms) |
  | `:connect_timeout_ms` | `30_000` | WebSocket connect timeout |
  | `:keep_alive_interval_ms` | `30_000` | WA-level keep-alive ping interval |
  | `:sender_idle_ms` | `1_000` | how long a per-recipient `ConversationSender` stays warm after its last send before stopping. Larger = fewer respawns/session re-reads under bursty traffic (useful with a disk-backed store); smaller = sheds processes faster after a fan-out |
  | `:sync_full_history` | `true` | request full history on link |
  | `:mark_online_on_connect` | `true` | send presence-available on connect. `false` keeps this session **unavailable** — it appears offline to others and the **primary phone keeps receiving push notifications** (live messages are then queued offline rather than pushed to this session). |
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

  @doc """
  The default config map (without `:profile`/`:auth`/`:storage`, which are caller-supplied).

  `:version` is the pinned `#{inspect(@wa_version)}` unless the `AMARULA_WA_VERSION`
  env var overrides it (see `wa_version/0`).
  """
  @spec defaults() :: map()
  def defaults, do: %{@defaults | version: wa_version()}

  @doc "Merge `config` over the defaults (caller values win)."
  @spec merge(map()) :: map()
  def merge(config) when is_map(config), do: Map.merge(defaults(), config)

  @doc """
  The WhatsApp Web protocol version to present on the wire.

  Returns the compiled-in pinned default (`#{inspect(@wa_version)}`) unless the
  `AMARULA_WA_VERSION` env var is set to a dotted triple (e.g. `"2.3000.1042537629"`),
  which lets a consumer track a newer WhatsApp version without recompiling. A
  malformed value is ignored (with a warning) and the pinned default is used.
  """
  @spec wa_version() :: [non_neg_integer()]
  def wa_version do
    case System.get_env("AMARULA_WA_VERSION") do
      nil -> @wa_version
      raw -> parse_version(raw) || @wa_version
    end
  end

  defp parse_version(raw) do
    parts = raw |> String.trim() |> String.split(".", trim: true)

    with 3 <- length(parts),
         [_, _, _] = ints <- Enum.map(parts, &parse_int/1),
         false <- Enum.any?(ints, &is_nil/1) do
      ints
    else
      _ ->
        require Logger

        Logger.warning(
          "ignoring malformed AMARULA_WA_VERSION #{inspect(raw)}; expected \"a.b.c\""
        )

        nil
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end
end
