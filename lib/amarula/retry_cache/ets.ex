defmodule Amarula.RetryCache.ETS do
  @moduledoc """
  In-memory `Amarula.RetryCache` adapter — the default.

  One public, named ETS table per connection profile, holding
  `{msg_id, entry}`. Bounded to `@max_entries`; on overflow the oldest entries
  (by `entry.ts`) are evicted. State is lost on VM restart, which is acceptable:
  a retry receipt arrives within seconds of the original send.

  The table is created lazily on first use and named by profile, so any process
  on the node can reach it. (A retry cache is shared, low-contention state; ETS's
  concurrent read/write suffices.)

  ## Options

    * `:max_entries` — cap before eviction (default 200).
  """

  @behaviour Amarula.RetryCache

  @default_max 200

  @impl true
  def new(opts), do: %{max_entries: Keyword.get(opts, :max_entries, @default_max)}

  @impl true
  def put(%{max_entries: max}, profile, msg_id, entry) do
    table = table(profile)
    :ets.insert(table, {msg_id, entry})
    evict(table, max)
    :ok
  end

  @impl true
  def get(_state, profile, msg_id) do
    case :ets.lookup(table(profile), msg_id) do
      [{^msg_id, entry}] -> {:ok, entry}
      _ -> :error
    end
  end

  @impl true
  def count(_state, profile), do: :ets.info(table(profile), :size)

  # --- internals ---

  # The per-profile table, created (idempotently) on first use.
  defp table(profile) do
    name = :"amarula_retry_cache_#{profile}"

    case :ets.whereis(name) do
      :undefined ->
        # read_concurrency for the get-heavy retry path; another process may win
        # the race to create it, so tolerate the already-exists badarg.
        try do
          :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
        rescue
          ArgumentError -> name
        end

      _tid ->
        name
    end
  end

  defp evict(table, max) do
    over = :ets.info(table, :size) - max

    if over > 0 do
      :ets.foldl(fn {id, %{ts: ts}}, acc -> [{ts, id} | acc] end, [], table)
      |> Enum.sort()
      |> Enum.take(over)
      |> Enum.each(fn {_ts, id} -> :ets.delete(table, id) end)
    end
  end
end
