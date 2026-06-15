defmodule Amarula.MessageCacheTest do
  use ExUnit.Case, async: true

  alias Amarula.MessageCache

  defp entry(ts), do: %{message: %{x: 1}, chat: :c, sender: :s, ts: ts}

  test "put/get round-trips by id, scoped per profile" do
    p = :"cache_#{System.unique_integer([:positive])}"
    assert :ok = MessageCache.put(p, "ID1", entry(1))
    assert {:ok, %{message: %{x: 1}}} = MessageCache.get(p, "ID1")
    assert :error = MessageCache.get(p, "nope")
  end

  test "get is :error for a nil/non-binary id" do
    assert :error = MessageCache.get(:p, nil)
  end

  test "evicts oldest past the cap" do
    p = :"cache_evict_#{System.unique_integer([:positive])}"
    # cap of 10 → inserting 15 drops the oldest.
    for i <- 1..15, do: MessageCache.put(p, "ID#{i}", entry(i), 10)
    assert MessageCache.count(p) <= 10
    # the very oldest is gone, the newest is kept
    assert :error = MessageCache.get(p, "ID1")
    assert {:ok, _} = MessageCache.get(p, "ID15")
  end
end
