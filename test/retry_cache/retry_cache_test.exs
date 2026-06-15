defmodule Amarula.RetryCacheTest do
  use ExUnit.Case, async: true

  alias Amarula.RetryCache

  defp entry(jid, ts), do: %{recipient_jid: jid, message: %{conversation: "hi"}, ts: ts}

  # Per-adapter opts (DETS needs a root dir; ETS doesn't).
  defp opts(Amarula.RetryCache.ETS, _dir), do: [max_entries: 5]
  defp opts(Amarula.RetryCache.DETS, dir), do: [root: dir, max_entries: 5]

  # Run the same behaviour contract against both shipped adapters.
  for adapter <- [Amarula.RetryCache.ETS, Amarula.RetryCache.DETS] do
    describe "#{inspect(adapter)} adapter" do
      setup do
        dir = Path.join(System.tmp_dir!(), "amarula_rc_#{System.unique_integer([:positive])}")
        on_exit(fn -> File.rm_rf(dir) end)
        # Unique profile per test so the ETS named table / DETS file don't collide.
        profile = :"p_#{System.unique_integer([:positive])}"
        scope = RetryCache.scope(%{retry_cache: {unquote(adapter), opts(unquote(adapter), dir)}})
        {:ok, scope: scope, profile: profile}
      end

      test "put then get round-trips", %{scope: s, profile: p} do
        :ok = RetryCache.put(s, p, "id1", entry("a@s", 1))
        assert {:ok, %{recipient_jid: "a@s"}} = RetryCache.get(s, p, "id1")
      end

      test "get returns :error on a miss", %{scope: s, profile: p} do
        assert :error = RetryCache.get(s, p, "nope")
      end

      test "profiles are isolated", %{scope: s, profile: p} do
        other = :"#{p}_other"
        RetryCache.put(s, p, "id", entry("a@s", 1))
        assert :error = RetryCache.get(s, other, "id")
      end

      test "evicts oldest beyond the cap (max_entries: 5)", %{scope: s, profile: p} do
        for i <- 1..8, do: RetryCache.put(s, p, "id#{i}", entry("a@s", i))

        assert RetryCache.count(s, p) == 5
        # Oldest three (ts 1..3) evicted; newest kept.
        assert :error = RetryCache.get(s, p, "id1")
        assert :error = RetryCache.get(s, p, "id3")
        assert {:ok, _} = RetryCache.get(s, p, "id8")
      end
    end
  end

  test "defaults to the ETS adapter when config has no :retry_cache" do
    assert RetryCache.scope(%{}).adapter == Amarula.RetryCache.ETS
  end

  test "scope/1 accepts a bare opts list (→ default adapter)" do
    assert RetryCache.scope(%{retry_cache: [max_entries: 10]}).adapter == Amarula.RetryCache.ETS
  end
end
