defmodule Amarula.Config do
  @wa_version [2, 3000, 1_044_539_926]

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
  | `:version` | `#{inspect(@wa_version)}` | WhatsApp Web *protocol* version — MUST track a version WhatsApp still accepts or the handshake is rejected. The live value drifts; override the pinned default without recompiling via the `AMARULA_WA_VERSION` env var (see `wa_version/0`), or bump the pinned literal with `mix run scripts/update_wa_version.exs`. (Distinct from Baileys *source* parity — see `docs/PARITY.md`.) |
  | `:browser` | `["Mac OS", "Chrome", "14.4.1"]` | browser triple `[os, client, version]` shown as the linked device. If the **client** (2nd element) contains `"Android"` (case-insensitive, e.g. `["MyApp", "Android", ""]`), the connection registers as an **Android client** instead of WhatsApp Web — see the impact note below. |
  | `:max_retries` | `5` | reconnect attempts |
  | `:retry_delay` | `1000` | base reconnect backoff (ms) |
  | `:connect_timeout_ms` | `30_000` | WebSocket connect timeout |
  | `:keep_alive_interval_ms` | `30_000` | WA-level keep-alive ping interval |
  | `:sender_idle_ms` | `1_000` | how long a per-recipient `ConversationSender` stays warm after its last send before stopping. Larger = fewer respawns/session re-reads under bursty traffic (useful with a disk-backed store); smaller = sheds processes faster after a fan-out |
  | `:custodian_idle_ms` | `30_000` | how long a per-record `SessionCustodian` (the Signal-session/sender-key lock) stays warm after its last op before shedding. Write-through means an idle-stop loses nothing; the next op restarts it. Larger = fewer respawns/session re-reads for chatty peers; smaller = sheds idle locks faster |
  | `:sync_full_history` | `true` | at **pairing**, ask the phone for *full* history vs a recent window (desktop only). A *depth* knob — distinct from `:sync_history`, which decides whether history is processed at all. |
  | `:sync_history` | `true` | process pushed history-sync notifications (download → decrypt → emit `:history_sync`). `false` still **acks** them (so the phone doesn't show this device as "Paused") but skips the download/decrypt/emit — lighter for ephemeral connects that don't need backfill. You then forgo offline-message recovery (see `:history_sync`). |
  | `:sync_app_state` | `true` | resync app-state (chats/contacts metadata: mute/pin/archive, names) when the server signals a change (`server_sync`/`account_sync`, or a fresh app-state-sync key). `false` skips the resync — no `:chats_update`/`:contacts_update` from app-state — for connects that only send. Shared keys are still stored, so re-enabling later works. |
  | `:mark_online_on_connect` | `true` | send presence-available on connect. `false` keeps this session **unavailable** — it appears offline to others and the **primary phone keeps receiving push notifications** (live messages are then queued offline rather than pushed to this session). |
  | `:fire_init_queries` | `true` | run the post-login init IQ queries (props/blocklist/privacy). `false` skips them — one more lever for a minimal ephemeral connect. |
  | `:country_code` | `"US"` | |
  | `:resolve_pn_to_lid` | `false` | **Experimental.** Address a 1:1 send to the contact's LID when we already hold the mapping, instead of keeping the phone number you passed on the wire envelope. Off by default — see `Amarula.Connection.resolve_pn_to_lid?/1`. |
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

  A few knobs are read from application env instead of per-connection — they're
  process-wide policy, set once for the whole app. Everything else is per-account
  and lives on the `Conn`, not here.

      config :amarula, :default_storage_adapter, Amarula.Storage.File
      config :amarula, :retry_cache_adapter, Amarula.RetryCache.ETS
      config :amarula, send_call_timeout_ms: :timer.minutes(30)
      config :amarula, req_options: [receive_timeout: :timer.minutes(30)]

  The two adapters pick a default backend *module*; a connection can still override
  either by naming its own `{module, opts}` in `:storage` / `:retry_cache` above.

  `:send_call_timeout_ms` (default `90_000`) is the `GenServer.call` deadline shared by
  every send/fetch. Raise it for large media — the whole encrypt + upload + relay
  must fit inside it — and raise `:req_options[:receive_timeout]` with it, or the
  CDN upload request times out first.

  These point at **behaviours** you can implement yourself to decide *where* this
  state lives (disk, DETS, Postgres, S3, Redis, …):

    * `Amarula.Storage` — durable auth/session/mapping state. **Losing it means
      re-pairing from a QR**, so back it up; see the callbacks + namespaces there,
      and `docs/GOING_PROD.md` for choosing/writing an adapter.
    * `Amarula.RetryCache` — short-lived sent-message cache for retry/decrypt
      recovery; safe to lose (it self-heals), so an in-memory ETS default is fine.

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
    sync_history: true,
    sync_app_state: true,
    resolve_pn_to_lid: false,
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
