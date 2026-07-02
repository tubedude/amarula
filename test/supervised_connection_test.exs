defmodule Amarula.SupervisedConnectionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Amarula.Protocol.Auth.AuthUtils

  # An offline connection config (no socket), same shape Amarula.Testing uses.
  defp offline_config(profile, parent) do
    auth =
      Map.put(AuthUtils.init_auth_creds(), :me, %{
        id: "10000000000@s.whatsapp.net",
        lid: nil,
        name: "SC Test"
      })

    dir =
      Path.join(System.tmp_dir!(), "amarula_sc_#{profile}_#{System.unique_integer([:positive])}")

    %{
      profile: profile,
      parent: parent,
      offline: true,
      connection_state: :connected,
      auth: auth,
      storage: {Amarula.Storage.File, root: dir},
      max_retries: 1,
      retry_delay: 100
    }
  end

  defp uniq_profile, do: :"sc_#{System.unique_integer([:positive])}"

  defp eventually(_fun, 0), do: false

  defp eventually(fun, tries) do
    if fun.() do
      true
    else
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  defp eventually(fun), do: eventually(fun, 50)

  describe "child_spec/1" do
    test "builds a per-profile spec (id keyed by profile so several coexist)" do
      spec = Amarula.child_spec(profile: :alpha)

      assert spec.id == {Amarula, :alpha}
      assert spec.start == {Amarula.SupervisedConnection, :start_link, [%{profile: :alpha}]}
      assert spec.restart == :permanent
      assert spec.type == :worker

      # distinct profiles → distinct ids
      refute Amarula.child_spec(profile: :beta).id == spec.id
    end

    test "accepts a map as well as a keyword list" do
      assert Amarula.child_spec(%{profile: :gamma}).id == {Amarula, :gamma}
    end

    test "requires a profile" do
      assert_raise KeyError, fn -> Amarula.child_spec([]) end
    end
  end

  describe "supervised start (offline)" do
    test "brings the connection up under a supervisor, discoverable by profile" do
      profile = uniq_profile()

      {:ok, sup} =
        Supervisor.start_link([{Amarula, offline_config(profile, self())}],
          strategy: :one_for_one
        )

      assert eventually(fn -> is_pid(Amarula.whereis(profile)) end)
      on_exit(fn -> if Process.alive?(sup), do: Supervisor.stop(sup) end)

      assert is_pid(Amarula.whereis(profile))
      Supervisor.stop(sup)
    end

    test "adopts an already-running profile instead of crash-looping" do
      profile = uniq_profile()
      config = offline_config(profile, self())

      {:ok, existing} = config |> Amarula.new() |> Amarula.connect(parent: self())

      {:ok, sup} =
        Supervisor.start_link([{Amarula, config}], strategy: :one_for_one)

      # The owner adopts the live connection rather than starting a second one.
      assert eventually(fn -> Amarula.whereis(profile) == existing end)

      Supervisor.stop(sup)
    end

    test "a deliberate shutdown tears the connection down" do
      profile = uniq_profile()

      {:ok, sup} =
        Supervisor.start_link([{Amarula, offline_config(profile, self())}],
          strategy: :one_for_one
        )

      assert eventually(fn -> is_pid(Amarula.whereis(profile)) end)
      Supervisor.stop(sup)

      assert eventually(fn -> is_nil(Amarula.whereis(profile)) end)
    end

    test "survives a connection crash and re-adopts the restarted pid (owner stays up)" do
      profile = uniq_profile()

      {:ok, sup} =
        Supervisor.start_link([{Amarula, offline_config(profile, self())}],
          strategy: :one_for_one
        )

      assert eventually(fn -> is_pid(Amarula.whereis(profile)) end)
      [{_id, owner, _type, _mods}] = Supervisor.which_children(sup)
      conn1 = Amarula.whereis(profile)

      # Kill the connection; Amarula's rest_for_one restarts it under a new pid.
      Process.exit(conn1, :kill)

      # The owner re-adopts the restarted connection instead of dying.
      assert eventually(fn ->
               conn2 = Amarula.whereis(profile)
               is_pid(conn2) and conn2 != conn1
             end)

      assert Process.alive?(owner), "owner should survive the connection crash and re-adopt"
      Supervisor.stop(sup)
    end

    test "warns when started without a :parent (events would be dropped)" do
      profile = uniq_profile()
      config = profile |> offline_config(self()) |> Map.delete(:parent)

      log =
        capture_log(fn ->
          {:ok, sup} = Supervisor.start_link([{Amarula, config}], strategy: :one_for_one)
          assert eventually(fn -> is_pid(Amarula.whereis(profile)) end)
          Supervisor.stop(sup)
        end)

      assert log =~ "without a :parent"
    end
  end
end
