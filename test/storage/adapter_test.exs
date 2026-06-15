defmodule Amarula.Storage.AdapterTest do
  use ExUnit.Case, async: true

  alias Amarula.Storage

  # An in-test adapter using only the macro's default new/1 (no override),
  # backed by the process dictionary so it needs no real per-conn state. It keys
  # by {profile, ns, key} to show profile-scoping is the adapter's job.
  defmodule PdictStore do
    use Amarula.Storage.Adapter

    @impl true
    def get(_state, profile, ns, key) do
      case Process.get({profile, ns, key}) do
        nil -> :error
        value -> {:ok, value}
      end
    end

    @impl true
    def put(_state, profile, ns, key, value) do
      Process.put({profile, ns, key}, value)
      :ok
    end

    @impl true
    def delete(_state, profile, ns, key) do
      Process.delete({profile, ns, key})
      :ok
    end
  end

  test "use injects @behaviour and a default new/1 returning opts as a map" do
    assert PdictStore.new(a: 1, b: 2) == %{a: 1, b: 2}
    assert Amarula.Storage in (PdictStore.module_info(:attributes)[:behaviour] || [])
  end

  test "an adapter authored via the macro works through the Storage API" do
    s = Storage.scope({PdictStore, []})
    assert :error = Storage.get(s, :p, :session, "x")
    assert :ok = Storage.put(s, :p, :session, "x", :hi)
    assert {:ok, :hi} = Storage.get(s, :p, :session, "x")
    assert :ok = Storage.delete(s, :p, :session, "x")
    assert :error = Storage.get(s, :p, :session, "x")
  end

  test "the adapter isolates by profile" do
    s = Storage.scope({PdictStore, []})
    Storage.put(s, :a, :session, "x", :for_a)
    Storage.put(s, :b, :session, "x", :for_b)
    assert {:ok, :for_a} = Storage.get(s, :a, :session, "x")
    assert {:ok, :for_b} = Storage.get(s, :b, :session, "x")
  end

  test "File adapter is authored via the macro (new/1 overridden)" do
    assert %{root: "/tmp/x"} = Amarula.Storage.File.new(root: "/tmp/x")
  end
end
