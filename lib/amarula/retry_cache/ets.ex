defmodule Amarula.RetryCache.ETS do
  @moduledoc """
  In-memory `Amarula.RetryCache` adapter — the default.

  One `:public`, named ETS table per connection profile, holding
  `{msg_id, entry}`. Bounded to `@max_entries`; on overflow the oldest entries
  (by `entry.ts`) are evicted. State is lost on restart, which is acceptable:
  a retry receipt arrives within seconds of the original send.

  ## Ownership

  The table is created by `ensure_local/2`, called from `Connection.init`, so it
  is **owned by the Connection process** and named by profile. Because the table
  dies with its owner, a Connection crash/restart recreates it **empty** — so a
  poisoned entry can never outlive the restart it triggers (no crash-loop on a
  bad cached value).

  It must be `:public`, not `:protected`: it is written from **two** processes —
  `Connection` itself (on a retry receipt) and each per-recipient
  `ConversationSender` (the `Amarula.RetryCache.Step` in the send pipe records the
  sent message there) — while ownership (and thus the restart-clearing lifetime
  above) stays with Connection.

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
    with name when name != :undefined <- :ets.whereis(table(profile)),
         [{^msg_id, entry}] <- :ets.lookup(name, msg_id) do
      {:ok, entry}
    else
      _ -> :error
    end
  end

  @impl true
  def count(_state, profile) do
    case :ets.whereis(table(profile)) do
      :undefined -> 0
      name -> :ets.info(name, :size)
    end
  end

  @doc """
  Create the profile's table, owned by the calling process (`Connection`). Called
  from `Connection.init` before any reader, so we never create lazily on first
  use — no create race, no rescue. Idempotent.
  """
  @impl true
  @spec ensure_local(map(), atom() | String.t()) :: :ok
  def ensure_local(_state, profile) do
    name = table(profile)

    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
      _ -> name
    end

    :ok
  end

  # --- internals ---

  defp table(profile), do: :"amarula_retry_cache_#{profile}"

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
