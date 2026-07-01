defmodule Amarula.RetryCacheTest do
  use ExUnit.Case, async: true

  alias Amarula.RetryCache

  # `seq` is a small ordinal (1, 2, 3…) standing in for send order. Map it to a
  # real, *recent* ms timestamp — a few seconds ago, well inside the 5-min TTL —
  # while preserving order (higher seq = newer), so eviction-by-oldest still drops
  # the lowest seqs first.
  defp entry(jid, seq) do
    ts = System.system_time(:millisecond) - (100 - seq) * 1000
    %{recipient_jid: jid, message: %{conversation: "hi"}, ts: ts}
  end

  # A timestamp just past the 5-min retry TTL — such an entry must be dropped.
  defp stale_ts, do: System.system_time(:millisecond) - (5 * 60 * 1000 + 1000)

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
        # Mirror Connection.init: create the adapter's process-owned resource (the
        # ETS table) owned by the test process before any put/get. No-op for DETS.
        :ok = RetryCache.ensure_local(scope, profile)
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

      test "reads for a never-started profile miss without minting atoms",
           %{scope: s} do
        # `profile` can be user-controlled; the read paths must not create the
        # table-name atom (atoms aren't GC'd — that would be an exhaustion vector).
        profile = "never_started_#{System.unique_integer([:positive])}"

        assert :error = RetryCache.get(s, profile, "id")
        assert RetryCache.count(s, profile) == 0

        if unquote(adapter) == Amarula.RetryCache.ETS do
          assert_raise ArgumentError, fn ->
            String.to_existing_atom("amarula_retry_cache_#{profile}")
          end
        end
      end

      test "evicts oldest beyond the cap (max_entries: 5)", %{scope: s, profile: p} do
        for i <- 1..8, do: RetryCache.put(s, p, "id#{i}", entry("a@s", i))

        assert RetryCache.count(s, p) == 5
        # Oldest three (ts 1..3) evicted; newest kept.
        assert :error = RetryCache.get(s, p, "id1")
        assert :error = RetryCache.get(s, p, "id3")
        assert {:ok, _} = RetryCache.get(s, p, "id8")
      end

      test "drops entries past the 5-min TTL", %{scope: s, profile: p} do
        stale = %{recipient_jid: "a@s", message: %{conversation: "old"}, ts: stale_ts()}
        RetryCache.put(s, p, "old", stale)
        RetryCache.put(s, p, "fresh", entry("a@s", 1))

        # `get` rejects the expired entry, and the next write evicted it.
        assert :error = RetryCache.get(s, p, "old")
        assert {:ok, _} = RetryCache.get(s, p, "fresh")
      end
    end
  end

  describe "ReadOnly adapter (consumer store)" do
    test "get/3 delegates to the consumer's function" do
      store = %{"id1" => %{recipient_jid: "a@s", message: %{conversation: "hi"}}}

      scope =
        RetryCache.scope(%{
          retry_cache:
            {Amarula.RetryCache.ReadOnly, get: fn _profile, id -> Map.fetch(store, id) end}
        })

      assert {:ok, %{recipient_jid: "a@s"}} = RetryCache.get(scope, :p, "id1")
      assert :error = RetryCache.get(scope, :p, "missing")
    end

    test "has no write side — Amarula never writes to the consumer's store" do
      # The guarantee is structural: ReadOnly does not implement the optional
      # put/4 callback, so there is no write path for Amarula to misuse.
      refute function_exported?(Amarula.RetryCache.ReadOnly, :put, 4)

      scope =
        RetryCache.scope(%{
          retry_cache: {Amarula.RetryCache.ReadOnly, get: fn _p, _id -> :error end}
        })

      # The facade `put` is a safe no-op for a read-only adapter (and must not raise).
      assert :ok = RetryCache.put(scope, :p, "id", %{recipient_jid: "a@s", message: %{}, ts: 0})
    end

    test "new/1 rejects a non-arity-2 :get" do
      assert_raise ArgumentError, ~r/arity 2/, fn ->
        RetryCache.scope(%{retry_cache: {Amarula.RetryCache.ReadOnly, get: fn _ -> :error end}})
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
