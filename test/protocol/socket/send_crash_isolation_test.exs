defmodule Amarula.Protocol.Socket.SendCrashIsolationTest do
  @moduledoc """
  Regression tests for crash isolation of a connection from its consumer.

  Two failure modes used to take down the calling consumer process:

    1. A `ConversationSender` start failure (e.g. `:max_children`) raised a
       `CaseClauseError` inside `Connection`, crashing the connection process.
       `ConversationSender.deliver/2` must instead return `{:error, reason}`.

    2. The per-connection tree was started with `Supervisor.start_link/3`, linking
       it to the caller of `connect/2` — so any tree termination signalled (and
       killed) the consumer. The tree must be owned by the library's
       `Amarula.ConnectionsSupervisor`, never linked to the caller.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Amarula.Protocol.Messages.ConversationSender
  alias Amarula.Protocol.Socket.ConnectionSupervisor

  describe "sending to an address we cannot address (#50)" do
    # An offline connection: no socket, but a real Connection GenServer, which is
    # what these assertions are about — it has to survive the refusal.
    defp offline_conn do
      profile = :"si_#{System.unique_integer([:positive])}"

      auth =
        Map.put(Amarula.Protocol.Auth.AuthUtils.init_auth_creds(), :me, %{
          id: "10000000000@s.whatsapp.net",
          lid: nil,
          name: "SI Test"
        })

      dir = Path.join(System.tmp_dir!(), "amarula_si_#{profile}")

      {:ok, pid} =
        %{
          profile: profile,
          parent: self(),
          offline: true,
          connection_state: :connected,
          auth: auth,
          storage: {Amarula.Storage.File, root: dir}
        }
        |> Amarula.new()
        |> Amarula.connect(parent: self())

      on_exit(fn -> File.rm_rf(dir) end)
      pid
    end

    test "a status-post channel is refused with a reason, and the connection lives" do
      conn = offline_conn()
      status = Amarula.Address.parse("status@broadcast")

      assert {:error, {:unsupported, "broadcast"}} = Amarula.send_text(conn, status, "hi")

      # THE assertion. Before #50 this raised inside the GenServer, so replying to
      # a friend's story took the whole connection down and restarted it.
      assert Process.alive?(conn)
    end

    test "the empty address is refused too, and the connection lives" do
      conn = offline_conn()

      assert {:error, :no_jid} = Amarula.send_text(conn, Amarula.Address.empty(), "hi")
      assert Process.alive?(conn)
    end

    test "sandbox mode agrees with the live path instead of reporting a false :ok" do
      conn = offline_conn()

      # Offline sends normally short-circuit to {:ok, id}. The addressability check
      # deliberately runs FIRST, so a bot exercised in the sandbox learns it cannot
      # reply to a status rather than discovering it in production.
      assert {:ok, _id} = Amarula.send_text(conn, Amarula.Address.pn("5511999"), "hi")
      assert {:error, {:unsupported, _}} = Amarula.send_text(conn, "x@newsletter", "hi")
    end
  end

  describe "ConversationSender.deliver/2 start failure" do
    test "returns {:error, reason} instead of raising when the supervisor is full" do
      instance_id = make_ref()
      registry = ConnectionSupervisor.registry_name(instance_id)

      # A sender DynamicSupervisor that refuses every child.
      {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one, max_children: 0)

      opts = [
        registry: registry,
        supervisor: sup,
        instance_id: instance_id,
        recipient_jid: "10000000001@s.whatsapp.net",
        cm: self(),
        conn: %{},
        creds: %{}
      ]

      assert {:error, :max_children} = ConversationSender.deliver(opts, %{msg_id: "m1"})
    end
  end

  describe "connection tree ownership" do
    test "start_instance/2 returns a tree not linked to the caller" do
      Process.flag(:trap_exit, true)

      conn = test_conn()
      {:ok, sup, connection} = ConnectionSupervisor.start_instance(conn, parent_pid: self())

      # The tree's supervisor is a child of the library-owned DynamicSupervisor,
      # not linked to this (the calling) process.
      {:links, links} = Process.info(self(), :links)
      refute sup in links
      refute connection in links

      children = DynamicSupervisor.which_children(Amarula.Supervisor.connections_supervisor())
      assert Enum.any?(children, fn {_, pid, _, _} -> pid == sup end)

      # Killing the whole tree must NOT deliver an exit signal to the caller.
      Process.exit(sup, :kill)
      refute_receive {:EXIT, ^sup, _}, 200
      assert Process.alive?(self())
    end
  end

  describe "off-process task supervision" do
    # Connection's heavy off-process work (media encrypt+upload, history-sync
    # downloads) runs under a Task.Supervisor that Connection starts LINKED in its
    # own init. So a Connection crash takes the supervisor — and every in-flight
    # task — down with it: a task holds the crashed Connection's pid, and one that
    # outlived it would run against a stale pid.
    test "a task under Connection's linked Task.Supervisor dies when Connection crashes" do
      conn = test_conn()
      {:ok, sup, connection} = ConnectionSupervisor.start_instance(conn, parent_pid: self())
      on_exit(fn -> if Process.alive?(sup), do: Process.exit(sup, :kill) end)

      instance_id = GenServer.call(connection, :instance_id)
      task_sup = :sys.get_state(connection).task_supervisor
      custodian_sup = ConnectionSupervisor.whereis(instance_id, :custodian_supervisor)
      assert is_pid(task_sup)

      # A sentinel task standing in for a media-prep / history-sync job, started
      # under Connection's Task.Supervisor exactly as production does.
      {:ok, task} = Task.Supervisor.start_child(task_sup, fn -> Process.sleep(:infinity) end)
      task_ref = Process.monitor(task)
      sup_ref = Process.monitor(task_sup)

      Process.exit(connection, :kill)

      # The linked supervisor dies with Connection, and the task with it — not
      # orphaned against the dead Connection's pid.
      assert_receive {:DOWN, ^sup_ref, :process, ^task_sup, _}, 1000
      assert_receive {:DOWN, ^task_ref, :process, ^task, _}, 1000

      # Custodians sit BEFORE Connection in the `:rest_for_one` order, so the same
      # crash leaves them untouched (still the same pid).
      assert Process.alive?(custodian_sup)
      assert custodian_sup == ConnectionSupervisor.whereis(instance_id, :custodian_supervisor)
    end
  end

  defp test_conn do
    dir = Path.join(System.tmp_dir!(), "amarula_crashiso_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    %{
      wa_websocket_url: "wss://test.example.com/ws",
      max_retries: 1,
      retry_delay: 100,
      connection_state: :connected,
      frame_sink: self(),
      profile: :"crashiso_#{System.unique_integer([:positive])}",
      storage: {Amarula.Storage.File, root: dir},
      auth: test_creds()
    }
    |> Amarula.Conn.new()
  end

  defp test_creds do
    kp = Amarula.Protocol.Crypto.Crypto.generate_key_pair()

    %{
      registration_id: 4242,
      signed_identity_key: %{public: kp.public, private: kp.private},
      signed_pre_key: %{key_id: 1, key_pair: kp},
      pre_keys: %{},
      me: %{id: "10000000002@s.whatsapp.net", lid: nil, name: "Tester"}
    }
  end
end
