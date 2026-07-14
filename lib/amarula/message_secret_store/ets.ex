defmodule Amarula.MessageSecretStore.ETS do
  @moduledoc """
  In-memory `Amarula.MessageSecretStore` adapter — the default.

  One named ETS table per connection profile, holding
  `{msg_id, ts, secret, sender}`. State is lost on restart, which is usually
  fine: a message edit lands within minutes of the original (point a
  `Amarula.MessageSecretStore.ReadOnly` adapter at your own store if you need
  edits to survive restarts).

  ## Bound

  Entries live for `:ttl_ms` (default 15 minutes — WhatsApp's edit window; a
  secret older than that can't correspond to a still-editable message). Reads
  lazily skip expired entries, and every write sweeps them, so the table holds
  at most ~one edit window of inbound traffic.

  ## Ownership

  The table is created by `ensure_local/2`, called from `Connection.init`, so it
  is **owned by the Connection process**, named by profile, and dies (recreated
  empty) with it — a poisoned entry can never outlive the restart it triggers.

  Unlike the retry cache's table it is `:protected`, not `:public`: only the
  Connection process ever reads or writes it (both the stash on receive and the
  lookup on edit happen in `handle_message`).

  ## Options

    * `:ttl_ms` — how long a secret is retained (default #{15 * 60 * 1000}).
  """

  @behaviour Amarula.MessageSecretStore

  # WhatsApp's edit window. A secret older than this can't correspond to a
  # still-editable message, so entries past it are dead weight.
  @default_ttl_ms 15 * 60 * 1000

  @impl true
  def new(opts), do: %{ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms)}

  @impl true
  def put(state, profile, msg_id, entry), do: put(state, profile, msg_id, entry, now_ms())

  @doc false
  def put(%{ttl_ms: ttl}, profile, msg_id, %{secret: secret, sender: sender}, now) do
    case table(profile) do
      :undefined ->
        :ok

      table ->
        sweep(table, now, ttl)
        :ets.insert(table, {msg_id, now, secret, sender})
        :ok
    end
  end

  @impl true
  def get(state, profile, msg_id), do: get(state, profile, msg_id, now_ms())

  @doc false
  def get(%{ttl_ms: ttl}, profile, msg_id, now) do
    cutoff = now - ttl

    with table when table != :undefined <- table(profile),
         [{^msg_id, ts, secret, sender}] when ts >= cutoff <- :ets.lookup(table, msg_id) do
      {:ok, %{secret: secret, sender: sender}}
    else
      _ -> :error
    end
  end

  @impl true
  def count(_state, profile) do
    case table(profile) do
      :undefined -> 0
      table -> :ets.info(table, :size)
    end
  end

  @doc """
  Create the profile's table, owned by the calling process (`Connection`).
  Called from `Connection.init` before any reader — no create race. Idempotent.
  """
  @impl true
  def ensure_local(_state, profile) do
    # The one place the table-name atom is minted: once per started profile,
    # from Connection.init (same rationale as RetryCache.ETS.ensure_local/2).
    name = :"amarula_msg_secret_#{profile}"

    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:set, :protected, :named_table])
      _ -> name
    end

    :ok
  end

  # --- internals ---

  # Read/write paths never mint atoms — `profile` can be user-controlled, and
  # atoms aren't GC'd. An unknown profile resolves to :undefined (no such table).
  defp table(profile) do
    name = String.to_existing_atom("amarula_msg_secret_#{profile}")
    if :ets.whereis(name) == :undefined, do: :undefined, else: name
  rescue
    ArgumentError -> :undefined
  end

  # Drop every row past the TTL in one pass. The table is small (one edit
  # window of inbound traffic), so a per-write sweep stays cheap.
  defp sweep(table, now, ttl) do
    cutoff = now - ttl
    :ets.select_delete(table, [{{:_, :"$1", :_, :_}, [{:<, :"$1", cutoff}], [true]}])
  end

  defp now_ms, do: System.system_time(:millisecond)
end
