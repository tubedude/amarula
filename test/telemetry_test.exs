defmodule Amarula.TelemetryTest do
  @moduledoc """
  Pins the `Amarula.Telemetry` contract: the span start/stop/exception envelope
  (duration + centrally injected `:profile`), the outcome-metadata extension the
  send span uses, `emit/4`'s defaults, and the event catalog `events/0`
  advertises. Handlers forward to the test process via `:telemetry_test`
  (bundled with the `:telemetry` dep).
  """

  use ExUnit.Case, async: true

  alias Amarula.Telemetry

  # Event names here are test-only ([:amarula, :test_*]) so parallel suites
  # can't cross-talk; the ref in each message pins the handler anyway.
  defp attach(events) do
    ref = :telemetry_test.attach_event_handlers(self(), events)
    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  describe "span/4" do
    test "emits :start and :stop with duration, extra measurements, and injected :profile" do
      ref = attach([[:amarula, :test_span, :start], [:amarula, :test_span, :stop]])

      result =
        Telemetry.span([:amarula, :test_span], :prof, %{kind: :dm}, fn ->
          {:the_result, %{bytes: 42}}
        end)

      # The fun's result comes back to the caller unchanged.
      assert result == :the_result

      assert_received {[:amarula, :test_span, :start], ^ref, %{system_time: st}, start_meta}
      assert is_integer(st)
      assert start_meta.profile == :prof
      assert start_meta.kind == :dm

      assert_received {[:amarula, :test_span, :stop], ^ref, meas, stop_meta}
      assert is_integer(meas.duration) and meas.duration >= 0
      assert meas.bytes == 42
      assert stop_meta.profile == :prof
      assert stop_meta.kind == :dm
    end

    test "merges the fun's extra metadata into :stop (the send-outcome shape)" do
      ref = attach([[:amarula, :test_span, :stop]])

      result =
        Telemetry.span([:amarula, :test_span], :prof, %{kind: :dm}, fn ->
          {{:error, :boom}, %{bytes: 0},
           %{result: :error, error_stage: :encrypt, error_reason: :boom}}
        end)

      assert result == {:error, :boom}

      assert_received {[:amarula, :test_span, :stop], ^ref, %{duration: _}, meta}
      assert meta.result == :error
      assert meta.error_stage == :encrypt
      assert meta.error_reason == :boom
      # The centrally injected tags survive the merge.
      assert meta.profile == :prof
      assert meta.kind == :dm
    end

    test "a raise emits :exception (duration + reason) and re-raises; no :stop" do
      ref = attach([[:amarula, :test_span, :stop], [:amarula, :test_span, :exception]])

      assert_raise RuntimeError, "kaboom", fn ->
        Telemetry.span([:amarula, :test_span], :prof, %{kind: :dm}, fn -> raise "kaboom" end)
      end

      assert_received {[:amarula, :test_span, :exception], ^ref, %{duration: d}, meta}
      assert is_integer(d) and d >= 0
      assert %RuntimeError{message: "kaboom"} = meta.reason
      assert meta.profile == :prof
      refute_received {[:amarula, :test_span, :stop], ^ref, _, _}
    end
  end

  describe "emit/4" do
    test "defaults to %{count: 1} and injects :profile" do
      ref = attach([[:amarula, :test_event]])

      Telemetry.emit([:amarula, :test_event], "prof-string")

      assert_received {[:amarula, :test_event], ^ref, %{count: 1}, %{profile: "prof-string"}}
    end

    test "passes explicit measurements and metadata through (the ack-outcome shape)" do
      ref = attach([[:amarula, :test_event]])

      Telemetry.emit([:amarula, :test_event], :p, %{count: 3}, %{outcome: :rejected, code: "479"})

      assert_received {[:amarula, :test_event], ^ref, %{count: 3}, meta}
      assert meta == %{profile: :p, outcome: :rejected, code: "479"}
    end
  end

  describe "events/0" do
    test "includes the outcome events" do
      events = Telemetry.events()
      assert [:amarula, :send, :stop] in events
      assert [:amarula, :send, :ack] in events
      assert [:amarula, :iq, :timeout] in events
    end

    test "every advertised event is an [:amarula | _] atom list, with no duplicates" do
      events = Telemetry.events()
      assert events == Enum.uniq(events)

      Enum.each(events, fn [prefix | rest] = event ->
        assert prefix == :amarula
        assert rest != []
        assert Enum.all?(event, &is_atom/1)
      end)
    end
  end
end
