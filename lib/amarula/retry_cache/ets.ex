defmodule Amarula.RetryCache.ETS do
  @moduledoc """
  In-memory `Amarula.RetryCache` adapter — the default.

  One `:public`, named ETS table per connection profile, holding
  `{msg_id, entry}`. State is lost on restart, which is acceptable: a retry
  receipt arrives within seconds of the original send.

  ## Bound

  A message only needs to be held for as long as a retry could still arrive for
  it. The protocol bounds that two ways, and this cache mirrors both (matching the
  reference implementation):

    * **TTL — `@ttl_ms` (5 min).** A retry receipt normally lands within seconds;
      after a few minutes it won't come (and the message is stale anyway). Entries
      older than the TTL (by `entry.ts`) are dropped on the next write.
    * **Hard cap — `:max_entries` (default 512).** A safety ceiling on memory; past
      it, the oldest entries are evicted. Size this to your peak *sends per ~5 min*
      so a burst can't push a still-unacked message out before its retry arrives.

  If you already persist your sent messages, consider a read-only custom adapter
  pointed at your own store instead — see `Amarula.RetryCache` ("Using your own
  message store").

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

    * `:max_entries` — hard cap before oldest-eviction (default 512).
  """

  @behaviour Amarula.RetryCache

  @default_max 512
  # A retry receipt that hasn't arrived in 5 minutes won't; the message is dead.
  @ttl_ms 5 * 60 * 1000

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
    cutoff = now_ms() - @ttl_ms

    with name when name != :undefined <- :ets.whereis(table(profile)),
         [{^msg_id, %{ts: ts} = entry}] when ts >= cutoff <- :ets.lookup(name, msg_id) do
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
    # The one place the table-name atom is minted: once per started profile, from
    # Connection.init. A profile that gets here already owns a supervision tree,
    # so this can't exhaust the atom table any faster than the process table.
    name = :"amarula_retry_cache_#{profile}"

    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
      _ -> name
    end

    :ok
  end

  # --- internals ---

  # Read/write paths never mint atoms — `profile` can be user-controlled, and
  # atoms aren't GC'd. An unknown profile resolves to :undefined (no such table).
  defp table(profile) do
    String.to_existing_atom("amarula_retry_cache_#{profile}")
  rescue
    ArgumentError -> :undefined
  end

  # Write-triggered eviction: first drop everything past the TTL, then, if still
  # over the hard cap, drop the oldest until back under it.
  defp evict(table, max) do
    cutoff = now_ms() - @ttl_ms

    expired = :ets.select(table, [{{:"$1", %{ts: :"$2"}}, [{:<, :"$2", cutoff}], [:"$1"]}])
    Enum.each(expired, &:ets.delete(table, &1))

    over = :ets.info(table, :size) - max

    if over > 0 do
      :ets.foldl(fn {id, %{ts: ts}}, acc -> [{ts, id} | acc] end, [], table)
      |> Enum.sort()
      |> Enum.take(over)
      |> Enum.each(fn {_ts, id} -> :ets.delete(table, id) end)
    end
  end

  defp now_ms, do: System.system_time(:millisecond)
end
