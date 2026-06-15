defmodule Amarula.Storage.File do
  @moduledoc """
  Filesystem `Amarula.Storage` adapter — the default plugin.

  Isolates each connection by its `profile` in a subfolder under a configured root:

      <root>/<profile>/<prefix><base64url(key)>.term

  where `<prefix>` is fixed per namespace (`creds`/`session-`/`sender-key-`/
  `lidmap-`/`devices-`). Values are `:erlang.term_to_binary/1` — lossless for
  Elixir terms (the creds/record maps hold atom keys and raw binaries), so the
  file is Elixir-specific, not interchangeable with Baileys' JSON state.

  Writes are atomic (temp file + rename) so a crash mid-write can't corrupt
  state. A corrupt or unreadable entry is logged and treated as a miss, matching
  the prior stores' fail-soft behaviour.

  ## Options

    * `:root` — the base directory holding one subfolder per connection profile
      (required).
  """

  use Amarula.Storage.Adapter

  require Logger

  @prefixes %{
    creds: "creds",
    session: "session-",
    sender_key: "sender-key-",
    lid_mapping: "lidmap-",
    device_list: "devices-",
    app_state_sync_key: "appkey-",
    app_state_version: "appver-"
  }

  @impl true
  def new(opts), do: %{root: Keyword.fetch!(opts, :root)}

  @impl true
  def get(%{root: root}, profile, namespace, key) do
    path = path(root, profile, namespace, key)

    case File.read(path) do
      {:ok, bin} ->
        decode(bin, path)

      {:error, :enoent} ->
        :error

      {:error, reason} ->
        Logger.warning("Storage.File: could not read #{path}: #{inspect(reason)}")
        :error
    end
  end

  @impl true
  def put(%{root: root}, profile, namespace, key, value) do
    dir = dir(root, profile)
    path = path(root, profile, namespace, key)
    tmp = path <> ".tmp"

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(tmp, :erlang.term_to_binary(value)),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, reason} = err ->
        Logger.error("Storage.File: failed to write #{path}: #{inspect(reason)}")
        err
    end
  end

  @impl true
  def delete(%{root: root}, profile, namespace, key) do
    case File.rm(path(root, profile, namespace, key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def clear(%{root: root}, profile) do
    case File.rm_rf(dir(root, profile)) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  # --- internals ---

  defp decode(bin, path) do
    {:ok, :erlang.binary_to_term(bin)}
  rescue
    _ ->
      Logger.warning("Storage.File: corrupt entry at #{path} — treating as miss")
      :error
  end

  # Per-connection directory: <root>/<profile>.
  defp dir(root, profile), do: Path.join(root, to_string(profile))

  # The singleton creds file is "<dir>/creds.term"; everything else is
  # "<dir>/<prefix><base64url(key)>.term".
  defp path(root, profile, :creds, :self) do
    Path.join(dir(root, profile), Map.fetch!(@prefixes, :creds) <> ".term")
  end

  defp path(root, profile, namespace, key) when is_binary(key) do
    safe = Base.url_encode64(key, padding: false)
    Path.join(dir(root, profile), Map.fetch!(@prefixes, namespace) <> safe <> ".term")
  end
end
