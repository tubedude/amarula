defmodule Amarula.Profile do
  @moduledoc """
  Profile reads and writes: fetch a profile-picture URL, set/remove your (or a
  group's) picture, and set your status/bio. The consumer-facing half of Baileys'
  `profilePictureUrl` / `updateProfilePicture` / `removeProfilePicture` /
  `updateProfileStatus`.

  Each function builds an IQ via `Amarula.Protocol.Profile.Ops`, sends it through
  `Amarula.Connection.query_iq/3`, and parses the reply. Re-exported from the
  `Amarula` facade (`Amarula.profile_picture_url/3`, `Amarula.update_profile_status/2`,
  `Amarula.update_profile_picture/3`, `Amarula.remove_profile_picture/2`).

  > #### Picture URL privacy token {: .info}
  > `picture_url/3` implements the common path. WhatsApp can require a per-contact
  > privacy token (`tctoken`) for *other* users' pictures; that path is not yet
  > implemented, so fetching some contacts' pictures may return `nil`. Your own and
  > group pictures are unaffected.
  """

  alias Amarula.Address
  alias Amarula.Connection
  alias Amarula.Protocol.Profile.Ops

  @type conn :: GenServer.server()

  @doc """
  Fetch the profile-picture URL for `jid` (a user or group). `type` is `:preview`
  (small, default) or `:image` (full). Returns `{:ok, url}`, `{:ok, nil}` when there
  is no picture (or it is not visible to you), or `{:error, reason}`.
  """
  @spec picture_url(conn(), String.t() | Address.t(), Ops.pic_type()) ::
          {:ok, String.t() | nil} | {:error, term()}
  def picture_url(conn, jid, type \\ :preview) do
    target = Address.to_wire!(jid)

    with {:ok, reply} <- Connection.query_iq(conn, Ops.picture_url_query(target, type)) do
      {:ok, Ops.parse_url(reply)}
    end
  end

  @doc """
  Set your own profile picture (or a group's, if `jid` is a group you administer)
  from already-encoded JPEG bytes. WhatsApp expects a small square JPEG; the caller
  must size it (Amarula does not resize — see the module note). Returns `:ok` or
  `{:error, reason}`.
  """
  @spec update_picture(conn(), String.t() | Address.t(), binary()) :: :ok | {:error, term()}
  def update_picture(conn, jid, jpeg_bytes) do
    target = target_for(conn, jid)

    with {:ok, _reply} <- Connection.query_iq(conn, Ops.set_picture(target, jpeg_bytes)), do: :ok
  end

  @doc "Remove your own (or a group's) profile picture. Returns `:ok` or `{:error, reason}`."
  @spec remove_picture(conn(), String.t() | Address.t()) :: :ok | {:error, term()}
  def remove_picture(conn, jid) do
    target = target_for(conn, jid)

    with {:ok, _reply} <- Connection.query_iq(conn, Ops.remove_picture(target)), do: :ok
  end

  @doc "Set your own profile status/bio text. Returns `:ok` or `{:error, reason}`."
  @spec update_status(conn(), String.t()) :: :ok | {:error, term()}
  def update_status(conn, status) when is_binary(status) do
    with {:ok, _reply} <- Connection.query_iq(conn, Ops.set_status(status)), do: :ok
  end

  # Resolve the `target` attr for a picture write: `nil` when `jid` is our own
  # account (Baileys omits target for self), else the wire jid. Falls back to the
  # wire jid if creds aren't available yet (e.g. not logged in).
  defp target_for(conn, jid) do
    addr = Address.parse!(jid)
    if own_account?(conn, addr), do: nil, else: Address.to_jid!(addr)
  end

  # `get_auth_creds` returns a map; `me` defaults to `%{}` before login, so no
  # address matches and we fall back to a targeted IQ — no special-casing needed.
  defp own_account?(conn, %Address{} = addr) do
    me = conn |> Connection.get_auth_creds() |> Map.get(:me, %{})

    [Map.get(me, :id), Map.get(me, :lid)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Address.parse/1)
    |> Enum.any?(fn mine -> mine && Address.same_account?(mine, addr) end)
  end
end
