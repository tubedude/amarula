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
    table = table(profile)
    :ets.insert(table, {msg_id, entry})
    evict(table, max)
    :ok
  end

  @doc "Look up a cached received message by id. `{:ok, entry}` or `:error`."
  @spec get(atom() | String.t(), String.t()) :: {:ok, entry()} | :error
  def get(profile, msg_id) when is_binary(msg_id) do
    case :ets.lookup(table(profile), msg_id) do
      [{^msg_id, entry}] -> {:ok, entry}
      _ -> :error
    end
  end

  def get(_profile, _), do: :error

  @doc "Number of cached messages for `profile`."
  @spec count(atom() | String.t()) :: non_neg_integer()
  def count(profile), do: :ets.info(table(profile), :size)

  # --- internals ---

  defp table(profile) do
    name = :"amarula_message_cache_#{profile}"

    case :ets.whereis(name) do
      :undefined ->
        # Lazy, first-use creation. Two processes can race here; the loser's
        # :ets.new raises ArgumentError (table already exists) and we just reuse
        # the name. This is the same idiom as Amarula.RetryCache.ETS — the rescue
        # is a create-race guard, not error-swallowing.
        try do
          :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
        rescue
          ArgumentError -> name
        end

      _ ->
        name
    end
  end

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
