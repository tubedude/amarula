defmodule Amarula.RetryCache.DETS do
  @moduledoc """
  On-disk `Amarula.RetryCache` adapter — survives restart.

  One DETS table per connection profile (`<root>/<profile>/retry_cache.dets`),
  holding `{msg_id, entry}`. Bounded the same way as the ETS adapter — entries
  past the `@ttl_ms` (5 min) retry window are dropped, then the oldest beyond
  `:max_entries` (default 512). Independent of `Amarula.Storage` — its location is
  its own (`:root`), not borrowed from the durable-storage backend.

  Opened lazily and kept open per `{root, profile}`; DETS auto-repairs an
  uncleanly-closed table on reopen.

  ## Options

    * `:root`        — base dir holding one `.dets` file per profile (default
      `AMARULA_CACHE_DIR` or `./amarula_cache`).
    * `:max_entries` — hard cap before oldest-eviction (default 512).
  """

  @behaviour Amarula.RetryCache

  @default_root "./amarula_cache"
  @default_max 512
  @ttl_ms 5 * 60 * 1000

  @impl true
  def new(opts) do
    %{
      root: Keyword.get(opts, :root) || System.get_env("AMARULA_CACHE_DIR", @default_root),
      max_entries: Keyword.get(opts, :max_entries, @default_max)
    }
  end

  @impl true
  def put(%{root: root, max_entries: max}, profile, msg_id, entry) do
    table = open(root, profile)
    :dets.insert(table, {msg_id, entry})
    evict(table, max)
    :ok
  end

  @impl true
  def get(%{root: root}, profile, msg_id) do
    cutoff = now_ms() - @ttl_ms

    case :dets.lookup(open(root, profile), msg_id) do
      [{^msg_id, %{ts: ts} = entry}] when ts >= cutoff -> {:ok, entry}
      _ -> :error
    end
  end

  @impl true
  def count(%{root: root}, profile), do: :dets.info(open(root, profile), :size)

  # --- internals ---

  defp open(root, profile) do
    dir = Path.join(root, to_string(profile))
    File.mkdir_p!(dir)
    path = dir |> Path.join("retry_cache.dets") |> String.to_charlist()
    name = :"amarula_retry_cache_#{:erlang.phash2({root, profile})}"

    case :dets.open_file(name, file: path, type: :set) do
      {:ok, table} -> table
      {:error, reason} -> raise "could not open retry-cache DETS at #{path}: #{inspect(reason)}"
    end
  end

  # Write-triggered eviction: drop entries past the TTL first, then trim the
  # oldest down to the hard cap.
  defp evict(table, max) do
    cutoff = now_ms() - @ttl_ms

    expired =
      :dets.select(table, [{{:"$1", %{ts: :"$2"}}, [{:<, :"$2", cutoff}], [:"$1"]}])

    Enum.each(expired, &:dets.delete(table, &1))

    over = :dets.info(table, :size) - max

    if over > 0 do
      :dets.foldl(fn {id, %{ts: ts}}, acc -> [{ts, id} | acc] end, [], table)
      |> Enum.sort()
      |> Enum.take(over)
      |> Enum.each(fn {_ts, id} -> :dets.delete(table, id) end)
    end
  end

  defp now_ms, do: System.system_time(:millisecond)
end
