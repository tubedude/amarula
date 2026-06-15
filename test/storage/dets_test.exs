defmodule Amarula.Storage.DETSTest do
  use ExUnit.Case, async: true

  alias Amarula.Storage

  @profile :test

  setup do
    root =
      Path.join(System.tmp_dir!(), "amarula_storage_dets_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(root) end)
    {:ok, scope: Storage.scope({Storage.DETS, root: root}), root: root}
  end

  test "put/get round-trips an arbitrary term", %{scope: s} do
    value = %{record: <<1, 2, 3>>, atom: :keys, nested: %{n: 1}}
    assert :ok = Storage.put(s, @profile, :session, "alice.0", value)
    assert {:ok, ^value} = Storage.get(s, @profile, :session, "alice.0")
  end

  test "get returns :error on a miss", %{scope: s} do
    assert :error = Storage.get(s, @profile, :session, "nobody.0")
  end

  test "fetch returns the default on a miss", %{scope: s} do
    assert nil == Storage.fetch(s, @profile, :session, "nobody.0")
    assert :gone == Storage.fetch(s, @profile, :session, "nobody.0", :gone)
  end

  test "put overwrites", %{scope: s} do
    Storage.put(s, @profile, :device_list, "5511", [%{device: 0}])
    Storage.put(s, @profile, :device_list, "5511", [%{device: 1}])
    assert {:ok, [%{device: 1}]} = Storage.get(s, @profile, :device_list, "5511")
  end

  test "delete removes; deleting a missing key is :ok", %{scope: s} do
    Storage.put(s, @profile, :lid_mapping, "5511", "94")
    assert :ok = Storage.delete(s, @profile, :lid_mapping, "5511")
    assert :error = Storage.get(s, @profile, :lid_mapping, "5511")
    assert :ok = Storage.delete(s, @profile, :lid_mapping, "5511")
  end

  test "namespaces are isolated under the same key", %{scope: s} do
    Storage.put(s, @profile, :session, "k", :in_session)
    Storage.put(s, @profile, :sender_key, "k", :in_sender_key)
    assert {:ok, :in_session} = Storage.get(s, @profile, :session, "k")
    assert {:ok, :in_sender_key} = Storage.get(s, @profile, :sender_key, "k")
  end

  test "profiles are isolated (separate tables)", %{scope: s} do
    Storage.put(s, :a, :session, "k", :for_a)
    Storage.put(s, :b, :session, "k", :for_b)
    assert {:ok, :for_a} = Storage.get(s, :a, :session, "k")
    assert {:ok, :for_b} = Storage.get(s, :b, :session, "k")
  end

  test "creds singleton at :self round-trips", %{scope: s} do
    creds = %{me: %{id: "x"}, registration_id: 7}
    assert :ok = Storage.put(s, @profile, :creds, :self, creds)
    assert {:ok, ^creds} = Storage.get(s, @profile, :creds, :self)
  end

  test "writes a per-profile .dets file under the root", %{scope: s, root: root} do
    Storage.put(s, @profile, :session, "alice.0", :x)
    assert File.exists?(Path.join([root, to_string(@profile), "storage.dets"]))
  end

  test "persists across a reopen (new scope, same root)", %{scope: s, root: root} do
    Storage.put(s, @profile, :session, "k", :durable)
    # A fresh scope over the same root must see the prior write.
    s2 = Storage.scope({Storage.DETS, root: root})
    assert {:ok, :durable} = Storage.get(s2, @profile, :session, "k")
  end

  test "clear/2 wipes the profile's table", %{scope: s, root: root} do
    Storage.put(s, @profile, :creds, :self, %{me: 1})
    assert :ok = Storage.clear(s, @profile)
    refute File.exists?(Path.join([root, to_string(@profile)]))
    # reopen works (fresh empty table)
    assert :error = Storage.get(s, @profile, :creds, :self)
  end
end
