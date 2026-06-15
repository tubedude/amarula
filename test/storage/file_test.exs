defmodule Amarula.Storage.FileTest do
  use ExUnit.Case, async: true

  alias Amarula.Storage

  @profile :test

  setup do
    root =
      Path.join(System.tmp_dir!(), "amarula_storage_test_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(root) end)
    {:ok, scope: Storage.scope({Storage.File, root: root}), root: root}
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

  test "profiles are isolated under the same key", %{scope: s} do
    Storage.put(s, :a, :session, "k", :for_a)
    Storage.put(s, :b, :session, "k", :for_b)
    assert {:ok, :for_a} = Storage.get(s, :a, :session, "k")
    assert {:ok, :for_b} = Storage.get(s, :b, :session, "k")
  end

  test "creds is a singleton at :self → <root>/<profile>/creds.term", %{scope: s, root: root} do
    creds = %{me: %{id: "x"}, registration_id: 7}
    assert :ok = Storage.put(s, @profile, :creds, :self, creds)
    assert {:ok, ^creds} = Storage.get(s, @profile, :creds, :self)
    assert File.exists?(Path.join([root, to_string(@profile), "creds.term"]))
  end

  test "writes under a per-profile subfolder", %{scope: s, root: root} do
    Storage.put(s, @profile, :session, "alice.0", :x)
    safe = Base.url_encode64("alice.0", padding: false)
    assert File.exists?(Path.join([root, to_string(@profile), "session-#{safe}.term"]))
  end

  test "a corrupt entry reads as a miss", %{scope: s, root: root} do
    safe = Base.url_encode64("bad", padding: false)
    profile_dir = Path.join(root, to_string(@profile))
    File.mkdir_p!(profile_dir)
    File.write!(Path.join(profile_dir, "session-#{safe}.term"), "not a term")
    assert :error = Storage.get(s, @profile, :session, "bad")
  end

  test "scope/1 accepts a bare opts list (default adapter)", %{root: root} do
    s = Storage.scope(root: root)
    assert :ok = Storage.put(s, @profile, :creds, :self, %{ok: true})
    assert {:ok, %{ok: true}} = Storage.get(s, @profile, :creds, :self)
  end

  test "clear/2 wipes everything for a profile (only that profile)", %{scope: s, root: root} do
    Storage.put(s, @profile, :creds, :self, %{me: 1})
    Storage.put(s, @profile, :session, "a.0", :x)
    Storage.put(s, :other, :creds, :self, %{me: 2})

    assert :ok = Storage.clear(s, @profile)
    assert :error = Storage.get(s, @profile, :creds, :self)
    assert :error = Storage.get(s, @profile, :session, "a.0")
    refute File.exists?(Path.join(root, to_string(@profile)))
    # other profile untouched
    assert {:ok, %{me: 2}} = Storage.get(s, :other, :creds, :self)
  end
end
