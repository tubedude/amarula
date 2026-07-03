defmodule Amarula.Telemetry do
  @moduledoc """
  `:telemetry` events emitted by Amarula — the operational-observability surface.

  This is **orthogonal** to the consumer event stream (`{:amarula, type, data}`
  delivered to `parent_pid`): those are application callbacks carrying real
  content/JIDs; these are metrics for operators (counts, durations, kinds).

  ## Privacy

  Telemetry payloads NEVER carry phone numbers, JIDs, message content, or key
  material — only counts, byte sizes, durations, booleans, kinds, process
  references (e.g. an event-sink pid/name), and the connection's `:profile`. Every
  emit goes through `emit/3` / `span/4` here, which inject `:profile`, so this is
  the single file to audit for leaks.

  ## Events

  All events are prefixed `[:amarula, ...]`. Spans follow the `:telemetry.span/3`
  convention (`:start` / `:stop` / `:exception`).

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `[:amarula, :connection, :update]` | `%{count: 1}` | `%{profile, state}` |
  | `[:amarula, :sink, :down]` | `%{count: 1}` | `%{profile, sink, reason}` — the consumer event sink died; `sink` is the pid/name, `reason` the exit. Events drop until a new sink is attached (`set_parent/2`) or a name-based sink re-resolves. |
  | `[:amarula, :send, :start]` | `%{monotonic_time, system_time}` | `%{profile, kind, media?, media_kind}` |
  | `[:amarula, :send, :stop]` | `%{duration, bytes}` | `%{profile, kind, media?, media_kind, result, error_stage, error_reason}` — `result` is `:ok`/`:error`; on `:error`, `error_stage` is the failing pipe stage (`:resolve_devices`/`:ensure_sessions`/`:encrypt`/`:relay`) and `error_reason` a normalized, JID-free reason atom (e.g. `:not_on_whatsapp`, `:timeout`) or nil; all three are nil-safe tags on success (`:ok`/nil/nil) |
  | `[:amarula, :send, :exception]` | `%{duration}` | `%{profile, kind, kind: :error/:exit/:throw, reason}` |
  | `[:amarula, :send, :not_on_whatsapp]` | `%{count: 1}` | `%{profile}` |
  | `[:amarula, :send, :ack]` | `%{count}` | `%{profile, outcome, code}` — the server-side verdict on a relayed, tracked send (the send span closes at relay time, before the `<ack>`). `outcome` is `:ok` \| `:rejected` \| `:timeout` \| `:sender_crashed`; `code` the server's rejection code (only for `:rejected`, else nil). One event per tracked send (duplicate acks don't count); a sender crash emits once with `count` = the parked sends it took out. |
  | `[:amarula, :message, :received]` | `%{count: 1, media_bytes}` | `%{profile, from_me?, group?, offline?, media?, media_kind}` |
  | `[:amarula, :decrypt, :exception]` | `%{count: 1}` | `%{profile, reason}` |
  | `[:amarula, :reconnect, :scheduled]` | `%{count: 1, delay_ms, attempt}` | `%{profile}` |
  | `[:amarula, :stream_error, :restart]` / `:received` | `%{count: 1}` | `%{profile, code}` |
  | `[:amarula, :prekey, :upload]` | `%{count}` | `%{profile}` |
  | `[:amarula, :retry, :received]` | `%{count: 1}` | `%{profile}` |
  | `[:amarula, :retry, :sent]` | `%{count: 1, attempt}` | `%{profile}` — `attempt` = escalating per-peer retry count; a high/rising value flags an unrecoverable peer |
  | `[:amarula, :iq, :timeout]` | `%{count: 1}` | `%{profile, kind}` — an outbound IQ got no reply within the timeout (the primary sick-connection signal). `kind` is the tracked bootstrap kind (`:prekey_count`/`:digest`/`:app_state_sync`/…); a blocking waiter (send-path USync/bundle/metadata) carries no kind, so the key is absent. |

  `media_bytes` on `:message, :received` is the **declared** `fileLength` from the
  message (what the sender claims), not a downloaded size — Amarula doesn't
  download media eagerly. `bytes` on `:send, :stop` is the declared media size of
  the outgoing message (0 for text).

  > Deferred (planned, not yet emitted): the full `[:amarula, :iq, ...]`
  > round-trip latency span (the `[:amarula, :iq, :timeout]` counter above ships
  > in the interim), and `[:amarula, :handshake|:app_state, ...]` spans. See
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
      [:amarula, :sink, :down],
      [:amarula, :send, :start],
      [:amarula, :send, :stop],
      [:amarula, :send, :exception],
      [:amarula, :send, :not_on_whatsapp],
      [:amarula, :send, :ack],
      [:amarula, :message, :received],
      [:amarula, :decrypt, :exception],
      [:amarula, :reconnect, :scheduled],
      [:amarula, :stream_error, :restart],
      [:amarula, :stream_error, :received],
      [:amarula, :prekey, :upload],
      [:amarula, :retry, :received],
      [:amarula, :retry, :sent],
      [:amarula, :iq, :timeout]
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

  Unlike `:telemetry.span/3`, the `fun` returns `{result, extra_measurements}` —
  or `{result, extra_measurements, extra_metadata}` — so the `:stop` event can
  carry extra **measurements** (e.g. `bytes`) — those aggregate (sum/summary) in
  `telemetry_metrics`, where span metadata only tags — and extra **metadata**
  known only once the work ran (e.g. the send outcome), merged over the span's
  metadata. `:duration` (native time units) is always added. Returns `fun`'s
  `result`.
  """
  @spec span([atom()], profile(), map(), (-> {term(), map()} | {term(), map(), map()})) :: term()
  def span(name, profile, metadata, fun) do
    meta = Map.put(metadata, :profile, profile)
    start = System.monotonic_time()
    :telemetry.execute(name ++ [:start], %{system_time: System.system_time()}, meta)

    try do
      {result, extra_measurements, extra_metadata} =
        case fun.() do
          {result, extra_measurements, extra_metadata} ->
            {result, extra_measurements, extra_metadata}

          {result, extra_measurements} ->
            {result, extra_measurements, %{}}
        end

      duration = System.monotonic_time() - start
      measurements = Map.put(extra_measurements, :duration, duration)
      :telemetry.execute(name ++ [:stop], measurements, Map.merge(meta, extra_metadata))
      result
    rescue
      e ->
        duration = System.monotonic_time() - start
        :telemetry.execute(name ++ [:exception], %{duration: duration}, Map.put(meta, :reason, e))
        reraise e, __STACKTRACE__
    end
  end
end
