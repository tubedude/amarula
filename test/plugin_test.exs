defmodule Amarula.PluginTest do
  use ExUnit.Case, async: true

  alias Amarula.{Conn, Plugin, RetryCache}

  describe "Plugin.run/2" do
    test "threads ctx through steps, transforming" do
      steps = [
        fn ctx -> {:cont, Map.update!(ctx, :n, &(&1 + 1))} end,
        fn ctx -> {:cont, Map.update!(ctx, :n, &(&1 * 10))} end
      ]

      assert {:cont, %{n: 10}} = Plugin.run(steps, %{n: 0})
    end

    test "halts at the first halting step; later steps don't run" do
      parent = self()

      steps = [
        fn _ctx -> {:halt, :blocked} end,
        fn ctx ->
          send(parent, :ran)
          {:cont, ctx}
        end
      ]

      assert {:halt, :blocked} = Plugin.run(steps, %{})
      refute_received :ran
    end

    test "empty pipeline is a pass-through" do
      assert {:cont, %{a: 1}} = Plugin.run([], %{a: 1})
    end
  end

  describe "attach via Conn helpers" do
    setup do
      conn = Conn.new(%{profile: :test, retry_cache: Amarula.RetryCache.ETS})
      {:ok, conn: conn}
    end

    test "on_send appends a send step (after the default cache step)", %{conn: conn} do
      step = fn ctx -> {:cont, ctx} end
      conn = Plugin.on_send(conn, step)
      assert List.last(conn.send_steps) == step
      # the built-in retry-cache step is still present
      assert length(conn.send_steps) == 2
    end

    test "on_recv appends a recv step", %{conn: conn} do
      step = fn ctx -> {:cont, ctx} end
      conn = Plugin.on_recv(conn, step)
      assert conn.recv_steps == [step]
    end
  end

  describe "RetryCache.Step default send step" do
    test "records the outgoing message in the cache" do
      scope = RetryCache.scope(%{retry_cache: Amarula.RetryCache.ETS})
      profile = :"p_#{System.unique_integer([:positive])}"
      # Mirror Connection.init: create the ETS table before the step writes to it.
      :ok = RetryCache.ensure_local(scope, profile)

      ctx = %{
        message: %{conversation: "hi"},
        to: "5511@s.whatsapp.net",
        profile: profile,
        msg_id: "ID1",
        retry_cache: scope
      }

      assert {:cont, ^ctx} = Amarula.RetryCache.Step.record(ctx)

      assert {:ok, %{recipient_jid: "5511@s.whatsapp.net"}} =
               RetryCache.get(scope, profile, "ID1")
    end

    test "is a no-op when ctx carries no cache scope" do
      assert {:cont, %{x: 1}} = Amarula.RetryCache.Step.record(%{x: 1})
    end
  end
end
