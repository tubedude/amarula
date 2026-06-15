defmodule Amarula.Telemetry do
  @moduledoc """
  `:telemetry` events emitted by Amarula — the operational-observability surface.

  This is **orthogonal** to the consumer event stream (`{:whatsapp, type, data}`
  delivered to `parent_pid`): those are application callbacks carrying real
  content/JIDs; these are metrics for operators (counts, durations, kinds).

  ## Privacy

  Telemetry payloads NEVER carry phone numbers, JIDs, message content, or key
  material — only counts, byte sizes, durations, booleans, kinds, and the
  connection's `:profile`. Every emit goes through `emit/3` / `span/4` here, which
  inject `:profile`, so this is the single file to audit for leaks.

  ## Events

  All events are prefixed `[:amarula, ...]`. Spans follow the `:telemetry.span/3`
  convention (`:start` / `:stop` / `:exception`).

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `[:amarula, :connection, :update]` | `%{count: 1}` | `%{profile, state}` |
  | `[:amarula, :send, :start]` | `%{monotonic_time, system_time}` | `%{profile, kind, media?, media_kind}` |
  | `[:amarula, :send, :stop]` | `%{duration, bytes}` | `%{profile, kind, media?, media_kind}` |
  | `[:amarula, :send, :exception]` | `%{duration}` | `%{profile, kind, kind: :error/:exit/:throw, reason}` |
  | `[:amarula, :send, :not_on_whatsapp]` | `%{count: 1}` | `%{profile}` |
  | `[:amarula, :message, :received]` | `%{count: 1, media_bytes}` | `%{profile, from_me?, group?, offline?, media?, media_kind}` |
  | `[:amarula, :decrypt, :exception]` | `%{count: 1}` | `%{profile, reason}` |
  | `[:amarula, :reconnect, :scheduled]` | `%{count: 1, delay_ms, attempt}` | `%{profile}` |
  | `[:amarula, :stream_error, :restart]` / `:received` | `%{count: 1}` | `%{profile, code}` |
  | `[:amarula, :prekey, :upload]` | `%{count}` | `%{profile}` |
  | `[:amarula, :retry, :received]` | `%{count: 1}` | `%{profile}` |
  | `[:amarula, :retry, :sent]` | `%{count: 1, attempt}` | `%{profile}` — `attempt` = escalating per-peer retry count; a high/rising value flags an unrecoverable peer |

  `media_bytes` on `:message, :received` is the **declared** `fileLength` from the
  message (what the sender claims), not a downloaded size — Amarula doesn't
  download media eagerly. `bytes` on `:send, :stop` is the declared media size of
  the outgoing message (0 for text).

  > Deferred (planned, not yet emitted): an `[:amarula, :iq, ...]` round-trip
  > latency span, and `[:amarula, :handshake|:app_state, ...]` spans. See
  > `docs/plans/TELEMETRY.plan.md`.

  ## Attaching handlers

      :telemetry.attach_many(
        "my-app-amarula",
        Amarula.Telemetry.events(),
        &MyApp.handle_event/4,
        nil
      )

  Or with `telemetry_metrics` (a *consumer* dep — Amarula stays backend-agnostic):

      Telemetry.Metrics.summary("amarula.send.stop.duration", tags: [:profile, :kind])
      Telemetry.Metrics.sum("amarula.send.stop.bytes", tags: [:profile])
      Telemetry.Metrics.sum("amarula.message.received.media_bytes", tags: [:profile])
  """

  @typedoc "A connection profile (atom or string), injected into every payload."
  @type profile :: atom() | String.t()

  @doc "Every event name Amarula emits — for `:telemetry.attach_many/4`."
  @spec events() :: [[atom()]]
  def events do
    [
      [:amarula, :connection, :update],
      [:amarula, :send, :start],
      [:amarula, :send, :stop],
      [:amarula, :send, :exception],
      [:amarula, :send, :not_on_whatsapp],
      [:amarula, :message, :received],
      [:amarula, :decrypt, :exception],
      [:amarula, :reconnect, :scheduled],
      [:amarula, :stream_error, :restart],
      [:amarula, :stream_error, :received],
      [:amarula, :prekey, :upload],
      [:amarula, :retry, :received],
      [:amarula, :retry, :sent]
    ]
  end

  @doc """
  Emit a single event. `profile` is injected into metadata. A `:count` of 1 is the
  default measurement when none is given.
  """
  @spec emit([atom()], profile(), map(), map()) :: :ok
  def emit(name, profile, measurements \\ %{count: 1}, metadata \\ %{}) do
    :telemetry.execute(name, measurements, Map.put(metadata, :profile, profile))
  end

  @doc """
  Run `fun` as a span, emitting `name ++ [:start]` then `name ++ [:stop]` (or
  `[:exception]` if `fun` raises), with `:profile` injected into metadata.

  Unlike `:telemetry.span/3`, the `fun` returns `{result, extra_measurements}` so
  the `:stop` event can carry extra **measurements** (e.g. `bytes`) — those
  aggregate (sum/summary) in `telemetry_metrics`, where span metadata only tags.
  `:duration` (native time units) is always added. Returns `fun`'s `result`.
  """
  @spec span([atom()], profile(), map(), (-> {term(), map()})) :: term()
  def span(name, profile, metadata, fun) do
    meta = Map.put(metadata, :profile, profile)
    start = System.monotonic_time()
    :telemetry.execute(name ++ [:start], %{system_time: System.system_time()}, meta)

    try do
      {result, extra_measurements} = fun.()
      duration = System.monotonic_time() - start
      measurements = Map.put(extra_measurements, :duration, duration)
      :telemetry.execute(name ++ [:stop], measurements, meta)
      result
    rescue
      e ->
        duration = System.monotonic_time() - start
        :telemetry.execute(name ++ [:exception], %{duration: duration}, Map.put(meta, :reason, e))
        reraise e, __STACKTRACE__
    end
  end
end
