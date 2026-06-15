defmodule Amarula.MessageCache do
  @moduledoc """
  A small in-memory cache of recently-RECEIVED messages, keyed by message id, so a
  quoted reply can be resolved to its original without a server round-trip.

  This is deliberately simpler than `Amarula.RetryCache`: it is best-effort,
  ephemeral (lost on restart), and not pluggable — a cache miss just falls through
  to a server resend (`Amarula.resolve_quoted/2` → placeholder resend). One public,
  named ETS table per connection profile, bounded with oldest-first eviction.

  Stores the raw `%Proto.Message{}` (+ chat/sender/ts envelope) so a resolver can
  rebuild an `Amarula.Msg`.
  """

  @default_max 500

  @type entry :: %{message: struct(), chat: term(), sender: term(), ts: integer()}

  @doc "Cache a received message by id (best-effort; evicts oldest past the cap)."
  @spec put(atom() | String.t(), String.t(), entry(), non_neg_integer()) :: :ok
  def put(profile, msg_id, entry, max \\ @default_max) when is_binary(msg_id) do
    # ensure_table is idempotent; in production the TableOwner already made it.
    table = ensure_table(profile)
    :ets.insert(table, {msg_id, entry})
    evict(table, max)
    :ok
  end

  @doc "Look up a cached received message by id. `{:ok, entry}` or `:error`."
  @spec get(atom() | String.t(), String.t()) :: {:ok, entry()} | :error
  def get(profile, msg_id) when is_binary(msg_id) do
    with name when name != :undefined <- :ets.whereis(table(profile)),
         [{^msg_id, entry}] <- :ets.lookup(name, msg_id) do
      {:ok, entry}
    else
      _ -> :error
    end
  end

  def get(_profile, _), do: :error

  @doc "Number of cached messages for `profile` (0 if no table yet)."
  @spec count(atom() | String.t()) :: non_neg_integer()
  def count(profile) do
    case :ets.whereis(table(profile)) do
      :undefined -> 0
      name -> :ets.info(name, :size)
    end
  end

  @doc """
  Create the profile's table. Called once by the supervised `TableOwner` at
  connection start, before any reader runs — so the cache never creates tables
  lazily (no first-use race, no rescue). Idempotent.
  """
  @spec ensure_table(atom() | String.t()) :: atom()
  def ensure_table(profile) do
    name = table(profile)

    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
      _ -> name
    end
  end

  # --- internals ---

  defp table(profile), do: :"amarula_message_cache_#{profile}"

  defp evict(table, max) do
    if :ets.info(table, :size) > max do
      # Drop the oldest ~10% by ts so we don't evict on every insert.
      to_drop = div(max, 10) + 1

      :ets.tab2list(table)
      |> Enum.sort_by(fn {_id, %{ts: ts}} -> ts end)
      |> Enum.take(to_drop)
      |> Enum.each(fn {id, _} -> :ets.delete(table, id) end)
    end

    :ok
  end
end
