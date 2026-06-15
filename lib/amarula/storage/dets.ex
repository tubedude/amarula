defmodule Amarula.Storage.DETS do
  @moduledoc """
  DETS `Amarula.Storage` adapter for durable account state — a peer to
  `Amarula.Storage.File`.

  One DETS table per connection profile (`<root>/<profile>/storage.dets`),
  holding every entry keyed by `{namespace, key}`. Select it per connection:

      Amarula.new(%{profile: :primary, storage: {Amarula.Storage.DETS, root: "./data"}})
      |> Amarula.connect()

  or as the default for all connections:

      config :amarula, default_storage_adapter: Amarula.Storage.DETS

  ## Trade-offs vs. `File`

  `File` writes one term file per entry; `DETS` keeps a single on-disk table per
  profile — fewer files, O(1) keyed access, but a table lifecycle. The table is
  opened lazily on first use (per `{root, profile}`) and left open for the VM's
  lifetime; DETS auto-repairs an uncleanly-closed table on reopen and serialises
  concurrent ops. A corrupt/unreadable lookup is treated as a miss, matching
  `File`'s fail-soft behaviour.

  ## Options

    * `:root` — base directory holding one `.dets` file per profile (required).
  """

  use Amarula.Storage.Adapter

  require Logger

  @impl true
  def new(opts), do: %{root: Keyword.fetch!(opts, :root)}

  @impl true
  def get(%{root: root}, profile, namespace, key) do
    case :dets.lookup(open(root, profile), {namespace, key}) do
      [{_k, value}] -> {:ok, value}
      [] -> :error
    end
  rescue
    e ->
      Logger.warning("Storage.DETS: get failed (#{inspect(e)}) — treating as miss")
      :error
  end

  @impl true
  def put(%{root: root}, profile, namespace, key, value) do
    :dets.insert(open(root, profile), {{namespace, key}, value})
  end

  @impl true
  def delete(%{root: root}, profile, namespace, key) do
    :dets.delete(open(root, profile), {namespace, key})
  end

  @impl true
  def clear(%{root: root}, profile) do
    # Wipe all of the profile's data: empty the open table, then close + remove
    # its file. delete_all_objects ensures a subsequent reopen sees nothing even
    # if the named table is still cached.
    table = open(root, profile)
    :dets.delete_all_objects(table)
    :dets.close(table)
    File.rm_rf!(Path.join([root, to_string(profile)]))
    :ok
  end

  # --- internals ---

  # Open (idempotently) the per-profile DETS table, named by {root, profile} so
  # repeated opens return the same table.
  defp open(root, profile) do
    dir = Path.join(root, to_string(profile))
    File.mkdir_p!(dir)
    path = dir |> Path.join("storage.dets") |> String.to_charlist()
    name = :"amarula_storage_#{:erlang.phash2({root, profile})}"

    case :dets.open_file(name, file: path, type: :set) do
      {:ok, table} -> table
      {:error, reason} -> raise "could not open storage DETS at #{path}: #{inspect(reason)}"
    end
  end
end
