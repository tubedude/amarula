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

    test "readopt exhaustion: a tree that stays gone is re-established fresh" do
      # The connection dies AND never comes back (the whole tree is stopped, so
      # Amarula's internal rest_for_one can't re-register the profile). The owner
      # polls the registry to exhaustion (~2s) and only then starts a fresh tree —
      # it must not race a competing connect against a possible in-flight restart.
      profile = uniq_profile()

      {:ok, sup} =
        Supervisor.start_link([{Amarula, offline_config(profile, self())}],
          strategy: :one_for_one
        )

      on_exit(fn -> if Process.alive?(sup), do: Supervisor.stop(sup) end)

      assert eventually(fn -> is_pid(Amarula.whereis(profile)) end)
      [{_id, owner, _type, _mods}] = Supervisor.which_children(sup)
      conn1 = Amarula.whereis(profile)

      # Tear the WHOLE tree down (not just the Connection): nothing re-registers.
      :ok = Amarula.stop(profile)

      # During the poll window the owner waits rather than immediately starting a
      # competing fresh tree.
      refute eventually(fn -> is_pid(Amarula.whereis(profile)) end, 5)

      # After the poll is exhausted the owner establishes a fresh connection under
      # a new pid — and survives the whole episode.
      assert eventually(
               fn ->
                 conn2 = Amarula.whereis(profile)
                 is_pid(conn2) and conn2 != conn1
               end,
               200
             )

      assert Process.alive?(owner), "owner should establish fresh, not die"
      Supervisor.stop(sup)
    end

    @tag :capture_log
    test "a non-deliberate owner exit leaves the connection for the restarted owner to re-adopt" do
      # terminate/2 tears the connection down only on a DELIBERATE shutdown
      # (:normal/:shutdown). A crash-shaped exit must leave it running so the
      # supervisor's replacement owner re-adopts the very same pid.
      profile = uniq_profile()

      {:ok, sup} =
        Supervisor.start_link([{Amarula, offline_config(profile, self())}],
          strategy: :one_for_one
        )

      on_exit(fn -> if Process.alive?(sup), do: Supervisor.stop(sup) end)

      assert eventually(fn -> is_pid(Amarula.whereis(profile)) end)
      [{_id, owner1, _type, _mods}] = Supervisor.which_children(sup)
      conn1 = Amarula.whereis(profile)

      # A non-normal exit signal: trap_exit turns it into {:EXIT, _, :boom} →
      # {:stop, :boom} → terminate(:boom) — NOT deliberate, connection kept.
      Process.exit(owner1, :boom)

      assert eventually(fn ->
               case Supervisor.which_children(sup) do
                 [{_id, owner2, _type, _mods}] -> is_pid(owner2) and owner2 != owner1
                 _ -> false
               end
             end)

      # The connection never died: same pid, still registered, adopted anew.
      assert Amarula.whereis(profile) == conn1
      assert Process.alive?(conn1)
      Supervisor.stop(sup)
    end

    test "a stray :readopt tick while already connected is ignored" do
      # The superseded-poll-tick guard: a {:readopt, _} arriving when the owner
      # already holds a live connection must change nothing (and not crash).
      profile = uniq_profile()

      {:ok, sup} =
        Supervisor.start_link([{Amarula, offline_config(profile, self())}],
          strategy: :one_for_one
        )

      on_exit(fn -> if Process.alive?(sup), do: Supervisor.stop(sup) end)

      assert eventually(fn -> is_pid(Amarula.whereis(profile)) end)
      [{_id, owner, _type, _mods}] = Supervisor.which_children(sup)
      conn1 = Amarula.whereis(profile)

      send(owner, {:readopt, 3})

      # Synchronize on the owner having processed the message.
      _ = :sys.get_state(owner)
      assert Process.alive?(owner)
      assert Amarula.whereis(profile) == conn1
      Supervisor.stop(sup)
    end

    test "a :normal EXIT signal does not shut the owner down" do
      # The owner traps exits; a :normal exit from something it may be linked to
      # is not a supervisor shutdown and must be ignored.
      profile = uniq_profile()

      {:ok, sup} =
        Supervisor.start_link([{Amarula, offline_config(profile, self())}],
          strategy: :one_for_one
        )

      on_exit(fn -> if Process.alive?(sup), do: Supervisor.stop(sup) end)

      assert eventually(fn -> is_pid(Amarula.whereis(profile)) end)
      [{_id, owner, _type, _mods}] = Supervisor.which_children(sup)

      Process.exit(owner, :normal)

      _ = :sys.get_state(owner)
      assert Process.alive?(owner)
      assert is_pid(Amarula.whereis(profile))
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
