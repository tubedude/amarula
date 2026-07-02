defmodule Amarula.SupervisedConnection do
  @moduledoc """
  The process behind `Amarula.child_spec/1` — a thin owner that ties one Amarula
  connection to *your* supervision tree, so a fixed set of (already-paired)
  profiles come up at boot.

  You normally don't reference this module directly; you list `{Amarula, config}`
  as a child (see `Amarula.child_spec/1`). This owner exists because of how a
  connection reconnects.

  **Reconnection is protocol logic the `Connection` owns in-process.** WhatsApp
  *requires* reconnects — most notably the stream-error `515` ("restart required")
  the server sends right after first-time pairing, which the client must answer by
  tearing down the stream and re-logging-in. `Connection` drives that itself
  (`schedule_reconnect/1` → `handle_info(:reconnect, …)`): it swaps its internal
  websocket but keeps the **same pid and the same profile registration** across the
  whole QR → `pairing_success` → 515 → re-login → `:open` sequence and every later
  socket drop. That's why the connection is supervised inside Amarula's *own*
  application tree — it can't be a passive process your supervisor cold-restarts,
  and a crash there never signals your app.

  `Amarula.connect/2` hands back that leaf `Connection` pid, which is **not linked**
  to your supervisor. Handing it straight to your supervisor would break supervision
  (unlinked) and, if reconnection were ever moved to a crash-restart model, spam it
  with restarts. So this owner is the supervised child instead. It:

    * `start_link`s into your supervisor (proper supervision + shutdown);
    * connects on start, adopting an already-running profile as success so a
      restart never crash-loops on the one-per-profile guard;
    * *monitors* (not links) the connection. Routine reconnects (515/pairing,
      socket drops) are in-process and keep the pid, so they're invisible here —
      the monitor only fires on true process death: a `Connection` crash that
      `rest_for_one` replaces (→ poll the registry and re-adopt the new pid), or
      the whole tree dying (→ start fresh, or escalate to your supervisor);
    * stops the connection on a deliberate shutdown of this child.

  Inbound events go to the `:parent` sink you configure, exactly as with
  `Amarula.connect/2` — this owner does not relay them.
  """

  use GenServer

  require Logger

  # After the connection dies, poll the registry for Amarula's own rest_for_one
  # restart to re-register the profile, rather than sleeping a fixed window and
  # then guessing. We adopt the restarted pid the moment it reappears, and only
  # conclude the tree is truly gone (→ start fresh) after the poll is exhausted.
  # `@readopt_max_tries * @readopt_interval_ms` (≈2s) comfortably exceeds a
  # rest_for_one restart even with slow (DETS) storage init.
  @readopt_interval_ms 100
  @readopt_max_tries 20

  @doc false
  def start_link(config) when is_map(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)
    {sink, config} = pop_parent(config)
    conn = Amarula.new(config)

    if is_nil(sink) do
      Logger.warning(
        "Amarula.SupervisedConnection for #{inspect(conn.profile)} started without a :parent — " <>
          "inbound events (messages, receipts, connection updates) are delivered nowhere and " <>
          "silently dropped. Pass parent: <registered name> to receive them."
      )
    end

    state = %{conn: conn, profile: conn.profile, sink: sink, connection: nil, monitor: nil}
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case establish(state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  @impl true
  # The connection process we were watching actually died — rare, since routine
  # reconnects (515/pairing, socket drops) are in-process and keep the pid. Start
  # polling the registry: Amarula's own rest_for_one restart re-registers the
  # profile under a new pid, which we adopt (see handle_info({:readopt, _})).
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state) do
    Process.send_after(self(), {:readopt, @readopt_max_tries}, @readopt_interval_ms)
    {:noreply, %{state | connection: nil, monitor: nil}}
  end

  # Already re-adopted (a superseded poll tick) — ignore.
  def handle_info({:readopt, _tries}, %{connection: pid} = state) when is_pid(pid) do
    {:noreply, state}
  end

  def handle_info({:readopt, tries}, state) do
    case Amarula.whereis(state.profile) do
      pid when is_pid(pid) ->
        # The in-flight restart re-registered — adopt the new pid.
        {:noreply, adopt(state, pid)}

      nil when tries > 0 ->
        # Not back yet; keep waiting for the internal restart rather than racing
        # a competing fresh tree against it.
        Process.send_after(self(), {:readopt, tries - 1}, @readopt_interval_ms)
        {:noreply, state}

      nil ->
        # The profile stayed gone well past a rest_for_one restart — the tree is
        # really dead. Start fresh, or escalate to our supervisor if that fails.
        case establish(state) do
          {:ok, state} -> {:noreply, state}
          {:error, reason} -> {:stop, reason, state}
        end
    end
  end

  # Our supervisor is shutting us down (trap_exit turns the signal into a message).
  # A `:normal` EXIT from anything we might later be linked to is not a shutdown.
  def handle_info({:EXIT, _from, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _from, reason}, state), do: {:stop, reason, state}

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    # A deliberate shutdown (supervisor termination / normal stop) tears the
    # connection down too. A crash leaves it running so our restart re-adopts it.
    if deliberate?(reason) and is_binary_or_atom(state.profile) do
      Amarula.stop(state.profile)
    end

    :ok
  end

  # --- helpers ---

  # Bring the connection up: adopt it if the profile is already registered
  # (started elsewhere, or an already-settled restart), otherwise start a fresh
  # tree. An already-running race is adopted, not treated as an error.
  defp establish(%{profile: profile} = state) do
    case Amarula.whereis(profile) do
      pid when is_pid(pid) ->
        {:ok, adopt(state, pid)}

      nil ->
        case Amarula.connect(state.conn, parent: state.sink) do
          {:ok, pid} ->
            {:ok, adopt(state, pid)}

          {:error, {:already_running, pid}} ->
            {:ok, adopt(state, pid)}

          {:error, reason} = err ->
            Logger.warning(
              "SupervisedConnection #{inspect(profile)} connect failed: #{inspect(reason)}"
            )

            err
        end
    end
  end

  # Point the connection at our sink and start watching it.
  defp adopt(%{sink: sink} = state, pid) do
    if sink, do: Amarula.set_parent(pid, sink)
    %{state | connection: pid, monitor: Process.monitor(pid)}
  end

  defp pop_parent(config) do
    {Map.get(config, :parent) || Map.get(config, :parent_pid),
     Map.drop(config, [:parent, :parent_pid])}
  end

  defp deliberate?(:normal), do: true
  defp deliberate?(:shutdown), do: true
  defp deliberate?({:shutdown, _}), do: true
  defp deliberate?(_), do: false

  defp is_binary_or_atom(v), do: is_binary(v) or is_atom(v)
end
