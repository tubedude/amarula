defmodule Amarula.Connection.AckLifecycle do
  @moduledoc """
  The parked-send / sender-monitor seam for `Amarula.Connection` — shared by the
  send path, the receive `<ack>` handler, and the sender `:DOWN`/`:ack_timeout`
  handlers.

  A send parks the consumer's `from` under its `msg_id` (in `state.pending_acks`,
  keyed `{from, on_ack, timer, jid}`) and is answered only when the server's
  `<ack>` arrives, the send fails, the timeout fires, or the recipient's sender
  crashes. One monitor per recipient (`state.sender_monitors`) covers all of that
  recipient's in-flight sends.

  This module owns those two maps' transformations. It is a *state* module (like
  `Socket.IQ`), not pure-pure: it threads `state` and performs side effects on
  *stored* refs/froms (`Process.cancel_timer`, `Process.demonitor`,
  `GenServer.reply`) — none of which need the connection's own pid. Creating a
  timer/monitor (which needs `self()`) stays on `Connection`, which passes the
  ready `timer`/`ref` in.
  """

  @default_ack_timeout_ms 30_000

  @type state :: map()

  @doc "The ack timeout, overridable via `config[:ack_timeout_ms]` (tests)."
  @spec timeout_ms(state()) :: pos_integer()
  def timeout_ms(%{config: %{ack_timeout_ms: ms}}) when is_integer(ms), do: ms
  def timeout_ms(_state), do: @default_ack_timeout_ms

  @doc """
  Park a send. `from` nil = fire-and-forget (nothing parked: no caller waits, so
  a missing ack is fine). Otherwise store `{from, on_ack, timer, jid}` under
  `msg_id`, where `on_ack` applies the success shape. `timer` is created by the
  caller (it needs `self()`).
  """
  @spec park(state(), String.t(), GenServer.from() | nil, reference(), (term() -> term()), String.t()) ::
          state()
  def park(state, _msg_id, nil, _timer, _on_ack, _jid), do: state

  def park(state, msg_id, from, timer, on_ack, jid) do
    %{state | pending_acks: Map.put(state.pending_acks, msg_id, {from, on_ack, timer, jid})}
  end

  @doc """
  Resolve a parked send: reply `reply_fun.(on_ack)` to the caller, cancel its
  timeout timer, drop the entry, and stop monitoring the recipient once it has no
  more parked sends. An unknown `msg_id` (already resolved, fire-and-forget, or
  not ours) is a no-op — the same id never resolves twice.
  """
  @spec resolve(state(), String.t(), ((term() -> term()) -> term())) :: state()
  def resolve(state, msg_id, reply_fun) do
    case Map.pop(state.pending_acks, msg_id) do
      {nil, _acks} ->
        state

      {{from, on_ack, timer, jid}, acks} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, reply_fun.(on_ack))
        drop_monitor_if_idle(%{state | pending_acks: acks}, jid)
    end
  end

  @doc "Record a recipient's sender monitor `ref` (first parked send only)."
  @spec put_monitor(state(), String.t(), reference()) :: state()
  def put_monitor(state, jid, ref) do
    %{state | sender_monitors: Map.put(state.sender_monitors, jid, ref)}
  end

  @doc "True once we already monitor `jid`'s sender — the caller then skips creating one."
  @spec monitored?(state(), String.t()) :: boolean()
  def monitored?(state, jid), do: Map.has_key?(state.sender_monitors, jid)

  @doc """
  Drop `jid`'s monitor once it has no remaining parked sends, so monitor refs
  don't leak and we don't hold a stale monitor on a sender that will idle-stop.
  """
  @spec drop_monitor_if_idle(state(), String.t()) :: state()
  def drop_monitor_if_idle(state, jid) do
    if any_parked_for?(state, jid) do
      state
    else
      case Map.pop(state.sender_monitors, jid) do
        {nil, _} ->
          state

        {ref, monitors} ->
          Process.demonitor(ref, [:flush])
          %{state | sender_monitors: monitors}
      end
    end
  end

  @doc """
  Find which recipient a `:DOWN` ref belonged to and drop that monitor entry,
  returning `{jid | nil, state}`. The monitor already fired, so no demonitor.
  """
  @spec pop_monitor_by_ref(state(), reference()) :: {String.t() | nil, state()}
  def pop_monitor_by_ref(state, ref) do
    case Enum.find(state.sender_monitors, fn {_jid, r} -> r == ref end) do
      nil ->
        {nil, state}

      {jid, ^ref} ->
        {jid, %{state | sender_monitors: Map.delete(state.sender_monitors, jid)}}
    end
  end

  @doc """
  Fail every parked send for a crashed recipient with
  `{:error, {:sender_crashed, reason}}`, cancelling their timers. (The monitor
  entry was already removed by `pop_monitor_by_ref/2`.)
  """
  @spec fail_recipient_sends(state(), String.t(), term()) :: state()
  def fail_recipient_sends(state, jid, reason) do
    {mine, rest} =
      Map.split_with(state.pending_acks, fn {_id, {_f, _o, _t, j}} -> j == jid end)

    Enum.each(mine, fn {_id, {from, _on_ack, timer, _j}} ->
      Process.cancel_timer(timer)
      GenServer.reply(from, {:error, {:sender_crashed, reason}})
    end)

    %{state | pending_acks: rest}
  end

  defp any_parked_for?(state, jid) do
    Enum.any?(state.pending_acks, fn {_id, {_f, _o, _t, j}} -> j == jid end)
  end
end
