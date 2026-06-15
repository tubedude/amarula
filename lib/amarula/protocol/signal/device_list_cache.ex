defmodule Amarula.Protocol.Signal.DeviceListCache do
  @moduledoc """
  Per-user cache of a contact's device list, ported from Baileys'
  `userDevicesCache` (the `getUSyncDevices` cache). Lets a send skip the USync
  round-trip when we already know a user's devices.

  Keyed by JID *user* (the part before `@`), value = the list of device maps
  `%{user, device, server, jid}` that `USync.Devices.extract/4` produces.

  Persistence goes through the pluggable `Amarula.Storage` seam (`:device_list`
  namespace, keyed by user), scoped to the connection `conn` (`Amarula.Conn`).
  Entries carry a stored-at timestamp and expire after `@ttl_ms` so a stale
  device list is eventually re-fetched even without a server staleness signal
  (Baileys uses an LRU with a TTL; phash-based invalidation is disabled
  upstream). TTL is enforced here in the cache, not in the storage adapter.
  """

  alias Amarula.Conn
  alias Amarula.Protocol.Binary.JID
  alias Amarula.Storage
  # 1 hour — short enough that add/remove-device churn self-heals, long enough
  # to spare a USync on back-to-back sends.
  @ttl_ms 60 * 60 * 1000

  @type device :: %{
          user: String.t(),
          device: non_neg_integer(),
          server: String.t(),
          jid: String.t()
        }

  @doc """
  Fetch the cached device list for a JID (or user string). Returns `nil` on a
  miss or when the entry has expired.
  """
  @spec get(Conn.t(), String.t()) :: [device()] | nil
  def get(conn, jid), do: get(conn, jid, now_ms())

  @doc false
  @spec get(Conn.t(), String.t(), integer()) :: [device()] | nil
  def get(conn, jid, now) do
    with user when is_binary(user) <- user_of(jid),
         {stored_at, devices} when now - stored_at < @ttl_ms <- read(conn, user) do
      devices
    else
      _ -> nil
    end
  end

  @doc """
  Look up several users at once. Returns `{hits, misses}` where `hits` is a
  `user => devices` map and `misses` is the list of users with no fresh entry.
  """
  @spec get_many(Conn.t(), [String.t()]) :: {%{String.t() => [device()]}, [String.t()]}
  def get_many(conn, jids) do
    now = now_ms()

    Enum.reduce(jids, {%{}, []}, fn jid, {hits, misses} ->
      user = user_of(jid)

      case user && get(conn, jid, now) do
        nil -> {hits, [user | misses]}
        devices -> {Map.put(hits, user, devices), misses}
      end
    end)
    |> then(fn {hits, misses} -> {hits, misses |> Enum.reject(&is_nil/1) |> Enum.reverse()} end)
  end

  @doc """
  Store `devices` for `user` (overwriting any prior entry). `devices` is the
  full list for that user; pass the user JID or bare user string.
  """
  @spec put(Conn.t(), String.t(), [device()]) :: :ok | {:error, term()}
  def put(conn, jid, devices) do
    case user_of(jid) do
      nil -> {:error, :bad_jid}
      user -> write(conn, user, {now_ms(), devices})
    end
  end

  @doc """
  Store device lists for many users at once. `by_user` is `user => devices`.
  Returns :ok.
  """
  @spec put_many(Conn.t(), %{String.t() => [device()]}) :: :ok
  def put_many(conn, by_user) do
    Enum.each(by_user, fn {user, devices} -> put(conn, user, devices) end)
  end

  @doc "Drop a user's cached device list (e.g. on a device-list-change notification)."
  @spec delete(Conn.t(), String.t()) :: :ok
  def delete(conn, jid) do
    case user_of(jid) do
      nil -> :ok
      user -> do_delete(conn, user)
    end
  end

  # --- internals ---

  defp read(%Conn{storage: scope, profile: profile}, user) do
    Storage.fetch(scope, profile, :device_list, user)
  end

  defp write(%Conn{storage: scope, profile: profile}, user, value) do
    Storage.put(scope, profile, :device_list, user, value)
  end

  defp do_delete(%Conn{storage: scope, profile: profile}, user) do
    Storage.delete(scope, profile, :device_list, user)
  end

  defp user_of(jid) do
    case JID.decode(jid) do
      %{user: user} when is_binary(user) -> user
      _ -> if is_binary(jid) and jid != "", do: jid, else: nil
    end
  end

  defp now_ms, do: System.system_time(:millisecond)
end
