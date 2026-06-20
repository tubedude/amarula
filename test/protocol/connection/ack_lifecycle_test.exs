defmodule Amarula.Connection.AckLifecycleTest do
  @moduledoc """
  Unit tests for the parked-send / monitor seam — exercised over a bare state map,
  no Connection process. Side effects act on stored refs (timers, GenServer.reply
  targets) we create in-test, never on a connection pid.
  """
  use ExUnit.Case, async: true

  alias Amarula.Connection.AckLifecycle

  defp state(overrides \\ %{}) do
    Map.merge(%{pending_acks: %{}, sender_monitors: %{}, config: %{}}, overrides)
  end

  # A dummy timer we can cancel without a real Process.send_after.
  defp dummy_timer, do: Process.send_after(self(), :never, 60_000)

  describe "timeout_ms/1" do
    test "defaults to 30s, honors config override" do
      assert AckLifecycle.timeout_ms(state()) == 30_000
      assert AckLifecycle.timeout_ms(state(%{config: %{ack_timeout_ms: 500}})) == 500
    end
  end

  describe "park/6 and resolve/3" do
    test "fire-and-forget (from nil) parks nothing" do
      s = AckLifecycle.park(state(), "M1", nil, dummy_timer(), fn :ok -> :ok end, "j@x")
      assert s.pending_acks == %{}
    end

    test "a successful ack replies via on_ack and drops the entry" do
      from = {spawn_replier(self()), make_ref()}
      on_ack = fn :ok -> {:ok, "M1"} end

      s = AckLifecycle.park(state(), "M1", from, dummy_timer(), on_ack, "j@x")
      assert Map.has_key?(s.pending_acks, "M1")

      s = AckLifecycle.resolve(s, "M1", fn on_ack -> on_ack.(:ok) end)
      assert s.pending_acks == %{}
      assert_receive {:replied, {:ok, "M1"}}
    end

    test "an error reply bypasses on_ack" do
      from = {spawn_replier(self()), make_ref()}
      s = AckLifecycle.park(state(), "M1", from, dummy_timer(), fn :ok -> :ok end, "j@x")

      s = AckLifecycle.resolve(s, "M1", fn _on_ack -> {:error, :boom} end)
      assert s.pending_acks == %{}
      assert_receive {:replied, {:error, :boom}}
    end

    test "resolving an unknown id is a no-op" do
      s = state(%{pending_acks: %{"X" => :keep}})
      assert AckLifecycle.resolve(s, "missing", fn _ -> :x end) == s
    end
  end

  describe "monitors" do
    test "put_monitor / monitored?" do
      s = state()
      refute AckLifecycle.monitored?(s, "j@x")
      ref = make_ref()
      s = AckLifecycle.put_monitor(s, "j@x", ref)
      assert AckLifecycle.monitored?(s, "j@x")
      assert s.sender_monitors == %{"j@x" => ref}
    end

    test "drop_monitor_if_idle keeps the monitor while sends are still parked" do
      from = {spawn_replier(self()), make_ref()}

      s =
        state(%{sender_monitors: %{"j@x" => make_ref()}})
        |> AckLifecycle.park("M1", from, dummy_timer(), fn :ok -> :ok end, "j@x")

      assert AckLifecycle.drop_monitor_if_idle(s, "j@x") == s
    end

    test "pop_monitor_by_ref finds and removes the jid for a ref" do
      ref = make_ref()
      s = state(%{sender_monitors: %{"j@x" => ref, "k@y" => make_ref()}})

      assert {"j@x", s2} = AckLifecycle.pop_monitor_by_ref(s, ref)
      refute Map.has_key?(s2.sender_monitors, "j@x")
      assert Map.has_key?(s2.sender_monitors, "k@y")
    end

    test "pop_monitor_by_ref returns nil for an unknown ref" do
      s = state(%{sender_monitors: %{"j@x" => make_ref()}})
      assert {nil, ^s} = AckLifecycle.pop_monitor_by_ref(s, make_ref())
    end
  end

  describe "fail_recipient_sends/3" do
    test "fails only the crashed recipient's parked sends" do
      from_x = {spawn_replier(self()), make_ref()}
      from_y = {spawn_replier(self()), make_ref()}

      s =
        state()
        |> AckLifecycle.park("MX", from_x, dummy_timer(), fn :ok -> :ok end, "x@x")
        |> AckLifecycle.park("MY", from_y, dummy_timer(), fn :ok -> :ok end, "y@y")

      s = AckLifecycle.fail_recipient_sends(s, "x@x", :killed)

      assert_receive {:replied, {:error, {:sender_crashed, :killed}}}
      assert Map.keys(s.pending_acks) == ["MY"]
    end
  end

  # Spawns a process that, on receiving {tag, value} from GenServer.reply/2,
  # forwards {:replied, value} to `report`.
  defp spawn_replier(report) do
    spawn(fn ->
      receive do
        {_tag, value} -> send(report, {:replied, value})
      end
    end)
  end
end
