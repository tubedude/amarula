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
