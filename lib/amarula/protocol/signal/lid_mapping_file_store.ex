defmodule Amarula.Protocol.Signal.LidMappingFileStore do
  @moduledoc """
  File-backed LID ↔ PN mapping store, ported from Baileys
  `LIDMappingStore.storeLIDPNMappings` / `getLIDForPN` / `getPNForLID`.

  Persistence mirrors `Amarula.Protocol.Signal.SessionStore`: one entry per
  mapping in the `:lid_mapping` namespace. We key by the
  *user* part of the JID (the device/server are reconstructed by the caller),
  matching Baileys which stores `pnUser → lidUser` plus a `<lidUser>_reverse`
  entry.

      lidmap-<pnUser>.term            holds the lidUser
      lidmap-<lidUser>_reverse.term   holds the pnUser

  This is intentionally process-free (no GenServer) and crash-safe. Persistence
  goes through the pluggable `Amarula.Storage` seam (`:lid_mapping` namespace),
  scoped to the connection `conn` (`Amarula.Conn`).
  """

  require Logger

  alias Amarula.Conn
  alias Amarula.Protocol.Binary.JID
  alias Amarula.Storage

  @doc """
  Store a batch of `{lid, pn}` JID pairs. Each side may be given as either the
  LID or the PN (Baileys accepts both orders); pairs that aren't a valid
  PN/LID combination are skipped.

  Returns `{stored_count, newly_stored}` where `stored_count` counts every
  valid pair persisted (including ones that already matched) and `newly_stored`
  lists the input `{lid, pn}` pairs that were *not* already present — the ones
  a caller may want to force-refresh sessions for.
  """
  @spec store_mappings(Conn.t(), [{String.t(), String.t()}]) ::
          {non_neg_integer(), [{String.t(), String.t()}]}
  def store_mappings(conn, pairs) do
    Enum.reduce(pairs, {0, []}, fn pair, {count, new} ->
      case store_pair(conn, pair) do
        :stored -> {count + 1, [pair | new]}
        :exists -> {count + 1, new}
        :skip -> {count, new}
      end
    end)
    |> then(fn {count, new} -> {count, Enum.reverse(new)} end)
  end

  defp store_pair(conn, pair) do
    case normalize_pair(pair) do
      {:ok, pn_user, lid_user} -> put(conn, pn_user, lid_user)
      :skip -> :skip
    end
  end

  @doc "Look up the LID user for a PN JID (or PN user string). nil if unmapped."
  @spec lid_for_pn(Conn.t(), String.t()) :: String.t() | nil
  def lid_for_pn(conn, pn) do
    case user_of(pn) do
      nil -> nil
      pn_user -> read(conn, pn_user)
    end
  end

  @doc "Look up the PN user for a LID JID (or LID user string). nil if unmapped."
  @spec pn_for_lid(Conn.t(), String.t()) :: String.t() | nil
  def pn_for_lid(conn, lid) do
    case user_of(lid) do
      nil -> nil
      lid_user -> read(conn, "#{lid_user}_reverse")
    end
  end

  @doc """
  LID-priority signal address for a device JID, port of Baileys
  `resolveLIDSignalAddress`. If `jid` is a PN user with a stored LID mapping,
  return the signal address under the LID identity (`<lidUser>_1.<device>`);
  otherwise return the plain signal address of `jid`.

  Used so a session keyed by a recipient's LID is found even when we address
  them by phone number on the wire.
  """
  @spec signal_address(Conn.t(), String.t()) :: String.t()
  def signal_address(conn, jid) do
    with true <- JID.jid_user?(jid) and not JID.lid_user?(jid),
         lid_user when is_binary(lid_user) <- lid_for_pn(conn, jid),
         %{} = decoded <- JID.decode(jid) do
      device = Map.get(decoded, :device, 0) || 0
      plain_signal_address(JID.encode(%{user: lid_user, server: "lid", device: device}))
    else
      _ -> plain_signal_address(jid)
    end
  end

  @doc """
  LID-priority *wire* jid: a PN device jid mapped to its LID equivalent
  (preserving the device), else the jid unchanged. Mirrors Baileys
  assertSessions `wireJids` — the server serves prekey bundles keyed by the LID
  for lid-mapped users; a PN fetch for such a user goes unanswered.
  """
  @spec wire_jid(Conn.t(), String.t()) :: String.t()
  def wire_jid(conn, jid) do
    with true <- JID.jid_user?(jid) and not JID.lid_user?(jid),
         lid_user when is_binary(lid_user) <- lid_for_pn(conn, jid),
         %{} = decoded <- JID.decode(jid) do
      device = Map.get(decoded, :device, 0) || 0
      JID.encode(%{user: lid_user, server: "lid", device: device})
    else
      _ -> jid
    end
  end

  @doc """
  Plain signal address for a JID (no LID resolution): `<user>.<device>`, with a
  `_<domainType>` suffix for non-WA domains (jidToSignalProtocolAddress).
  """
  @spec plain_signal_address(String.t()) :: String.t()
  def plain_signal_address(jid) do
    case JID.decode(jid) do
      %{user: user} = decoded ->
        dt = Map.get(decoded, :domain_type, 0)
        device = Map.get(decoded, :device, 0) || 0
        signal_user = if dt == 0, do: user, else: "#{user}_#{dt}"
        "#{signal_user}.#{device}"

      _ ->
        raise "could not decode JID for signal address: #{inspect(jid)}"
    end
  end

  # --- internals ---

  # Persist forward + reverse. Returns :exists if the mapping already matched,
  # :stored on a fresh write, :skip if a write failed.
  defp put(conn, pn_user, lid_user) do
    cond do
      read(conn, pn_user) == lid_user ->
        :exists

      write(conn, pn_user, lid_user) == :ok and
          write(conn, "#{lid_user}_reverse", pn_user) == :ok ->
        :stored

      true ->
        Logger.warning("Failed to persist LID mapping #{pn_user} ↔ #{lid_user}")
        :skip
    end
  end

  # Sort the pair into {pn_user, lid_user}; accept either argument order.
  defp normalize_pair({a, b}) do
    cond do
      JID.lid_user?(a) and pn?(b) -> with_users(b, a)
      JID.lid_user?(b) and pn?(a) -> with_users(a, b)
      true -> :skip
    end
  end

  defp with_users(pn, lid) do
    case {user_of(pn), user_of(lid)} do
      {pn_user, lid_user} when is_binary(pn_user) and is_binary(lid_user) ->
        {:ok, pn_user, lid_user}

      _ ->
        :skip
    end
  end

  # A PN user is a normal s.whatsapp.net user (not a LID/group/etc.).
  defp pn?(jid), do: JID.jid_user?(jid) and not JID.lid_user?(jid)

  defp user_of(jid) do
    case JID.decode(jid) do
      %{user: user} when is_binary(user) -> user
      _ -> if is_binary(jid) and jid != "", do: jid, else: nil
    end
  end

  defp read(%Conn{storage: scope, profile: profile}, key) do
    Storage.fetch(scope, profile, :lid_mapping, key)
  end

  defp write(%Conn{storage: scope, profile: profile}, key, value) do
    Storage.put(scope, profile, :lid_mapping, key, value)
  end
end
