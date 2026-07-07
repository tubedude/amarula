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
  state. A genuinely corrupt or unreadable entry is logged and treated as a miss,
  matching the prior stores' fail-soft behaviour — but a valid, self-written term
  is always recovered, even when it carries atoms not yet loaded on a cold BEAM
  (see `decode/2`).

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

  @impl true
  def list_profiles(%{root: root}) do
    creds_file = Map.fetch!(@prefixes, :creds) <> ".term"

    case File.ls(root) do
      {:ok, entries} ->
        profiles =
          for name <- entries,
              File.dir?(Path.join(root, name)),
              File.exists?(Path.join([root, name, creds_file])),
              do: name

        {:ok, profiles}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- internals ---

  # `[:safe]` refuses to mint new atoms or instantiate funs/refs/external terms from
  # the payload — so a tampered .term file can't exhaust the atom table or smuggle in
  # an unsafe term. We try it first as a cheap guard.
  #
  # But these files are *self-written, trusted* data: we wrote them with
  # `term_to_binary/1`. A legitimate creds term carries struct atoms (e.g.
  # `Amarula.Protocol.Proto.ADVSignedDeviceIdentity`) that `[:safe]` refuses to mint
  # when the generated proto module hasn't been loaded yet — load-order dependent on a
  # cold BEAM. Treating that as a miss silently logs the session out and forces a
  # re-pair. So on the `[:safe]`-specific rejection we fall back to an unsafe decode of
  # our own file; only if *that* also fails is the file genuinely corrupt.
  defp decode(bin, path) do
    {:ok, :erlang.binary_to_term(bin, [:safe])}
  rescue
    ArgumentError ->
      # `[:safe]` rejected an atom/term it wouldn't mint. The file is ours and was a
      # valid term when written, so decode it without `[:safe]` (which also loads the
      # atoms, so subsequent `[:safe]` reads of the same shape pass).
      decode_trusted(bin, path)
  end

  defp decode_trusted(bin, path) do
    {:ok, :erlang.binary_to_term(bin)}
  rescue
    _ ->
      Logger.warning("Storage.File: corrupt entry at #{path} — treating as miss")
      :error
  end

  # Per-connection directory: <root>/<profile>.
  #
  # The profile becomes a path segment, so it must not escape the root. A consumer
  # that wires untrusted input into `profile` (e.g. a multi-tenant bot) could
  # otherwise pass "../../etc" and have us read/write/`rm_rf` outside the store.
  # We require the profile to be a single, literal path segment and raise on
  # anything else — a traversal attempt is abuse, not an expected miss, so failing
  # loud beats a fail-soft `:error` that would look like a cache miss.
  defp dir(root, profile), do: Path.join(root, safe_segment(profile))

  defp safe_segment(profile) do
    str = to_string(profile)

    if str != "" and str not in [".", ".."] and Path.basename(str) == str and
         not String.contains?(str, ["/", "\\", <<0>>]) do
      str
    else
      raise ArgumentError,
            "unsafe storage profile #{inspect(profile)}: must be a single path segment " <>
              "(no path separators, no traversal)"
    end
  end

  @impl true
  def list_keys(%{root: root}, profile, namespace) do
    prefix = Map.fetch!(@prefixes, namespace)

    case File.ls(dir(root, profile)) do
      {:ok, entries} ->
        keys =
          for name <- entries,
              String.starts_with?(name, prefix),
              String.ends_with?(name, ".term"),
              key = decode_key(name, prefix),
              not is_nil(key),
              do: key

        {:ok, keys}

      # No directory yet → nothing stored.
      {:error, :enoent} ->
        {:ok, []}

      {:error, _reason} = err ->
        err
    end
  end

  # Recover the raw key from a "<prefix><base64url(key)>.term" filename. Returns
  # nil for a name that doesn't decode (a foreign file, or the singleton creds file
  # whose key is :self, not a base64 string) so it's skipped, not crashed on.
  defp decode_key(name, prefix) do
    name
    |> String.replace_prefix(prefix, "")
    |> String.replace_suffix(".term", "")
    |> Base.url_decode64(padding: false)
    |> case do
      {:ok, key} -> key
      :error -> nil
    end
  end

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
