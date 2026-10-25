defmodule Amarula.Connection.SessionOps do
  @moduledoc """
  Signal session migration, peer identity-change wiping, and LID-mapping helpers
  for `Amarula.Connection`.
  """

  require Logger

  alias Amarula.Protocol.Binary.{JID, Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Constants
  alias Amarula.Protocol.Signal.{LidMappingFileStore, SessionCustodian, SessionStore}

  @doc """
  Delete all of `from`'s 1:1 sessions (every device) through `SessionCustodian`.
  Returns the count deleted, or `0` when the user or store cannot be enumerated.
  """
  @spec wipe_identity_sessions(term(), reference() | nil, String.t()) :: non_neg_integer()
  def wipe_identity_sessions(conn, instance_id, from) do
    with signal_user when is_binary(signal_user) <- LidMappingFileStore.signal_user(conn, from),
         {:ok, keys} <- SessionStore.list_session_keys(conn) do
      prefix = signal_user <> "."

      keys
      |> Enum.filter(&String.starts_with?(&1, prefix))
      |> Enum.reduce(0, &wipe_one_session(&1, instance_id, conn, &2))
    else
      _ -> 0
    end
  end

  defp wipe_one_session(addr, instance_id, conn, deleted) do
    case SessionCustodian.replace(instance_id, conn, addr, nil) do
      :ok -> deleted + 1
      _ -> deleted
    end
  end

  @doc """
  Before decrypting, if the sender is PN-addressed and we know their LID, move
  their PN session onto the LID address (idempotent per PN user per connection).
  """
  @spec maybe_migrate_sender_session(map(), Node.t()) :: map()
  def maybe_migrate_sender_session(state, node) do
    author = NodeUtils.get_attr(node, "participant") || NodeUtils.get_attr(node, "from")

    with true <- is_binary(author) and JID.jid_user?(author) and not JID.lid_user?(author),
         %{user: pn_user} <- JID.decode(author),
         false <- MapSet.member?(state.migrated_pn_sessions, pn_user),
         lid_user when is_binary(lid_user) <- LidMappingFileStore.lid_for_pn(state.conn, author),
         {:ok, keys} <- SessionStore.list_session_keys(state.conn) do
      {state, _result} = migrate_pn_user(state, pn_user, lid_user, keys)
      state
    else
      {:error, reason} ->
        Logger.warning(
          "PN→LID migrate on receive: cannot enumerate sessions (#{inspect(reason)})"
        )

        state

      _ ->
        state
    end
  end

  @doc """
  Migrate a batch of `{lid, pn}` pairs onto their LID addresses, returning
  `{:ok, needs_fetch_lids, updated_state}` or `{:error, reason}`.
  """
  @spec migrate_pairs([{String.t(), String.t()}], map()) ::
          {:ok, [String.t()], map()} | {:error, term()}
  def migrate_pairs(pairs, state) do
    case SessionStore.list_session_keys(state.conn) do
      {:ok, keys} ->
        {needs_fetch, state} = Enum.flat_map_reduce(pairs, state, &migrate_pair(&1, &2, keys))
        {:ok, needs_fetch, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Idempotently re-key one PN user's sessions onto their LID from pre-listed `keys`.
  """
  @spec migrate_pn_user(map(), String.t(), String.t(), [String.t()]) ::
          {map(), :migrated | :none | :already}
  def migrate_pn_user(state, pn_user, lid_user, keys) do
    if MapSet.member?(state.migrated_pn_sessions, pn_user) do
      {state, :already}
    else
      state = %{state | migrated_pn_sessions: MapSet.put(state.migrated_pn_sessions, pn_user)}

      case migrate_pn_records(state.conn, state.instance_id, pn_user, lid_user, keys) do
        0 -> {state, :none}
        _ -> {state, :migrated}
      end
    end
  end

  defp migrate_pn_records(conn, iid, pn_user, lid_user, keys) do
    pn_prefix = pn_user <> "."

    keys
    |> Enum.filter(&String.starts_with?(&1, pn_prefix))
    |> Enum.reduce(0, fn pn_addr, moved ->
      device = String.replace_prefix(pn_addr, pn_prefix, "")
      lid_addr = "#{lid_user}_1.#{device}"

      with {:ok, record} when not is_nil(record) <-
             SessionCustodian.record(iid, conn, pn_addr),
           installed when installed in [:ok, {:skipped, :session_exists}] <-
             SessionCustodian.install_if_absent(iid, conn, lid_addr, record),
           :ok <- SessionCustodian.replace(iid, conn, pn_addr, nil) do
        moved + 1
      else
        _ -> moved
      end
    end)
  end

  defp migrate_pair({lid, pn}, state, keys) do
    with true <- JID.lid_user?(lid),
         %{user: pn_user} <- JID.decode(pn),
         %{user: lid_user} <- JID.decode(lid) do
      case migrate_pn_user(state, pn_user, lid_user, keys) do
        {state, :none} -> {[lid], state}
        {state, _} -> {[], state}
      end
    else
      _ ->
        Logger.warning("migrate_pn_sessions: skipping a mis-oriented or undecodable mapping pair")
        {[], state}
    end
  end

  @doc """
  Persist LID↔PN pairs from a history-sync blob and return the parsed
  `[%{lid: %Amarula.Address{}, pn: %Amarula.Address{}}]` list for newly learned mappings.
  """
  @spec store_and_format_lid_mappings(term(), [{String.t(), String.t()}]) :: [map()]
  def store_and_format_lid_mappings(_conn, []), do: []

  def store_and_format_lid_mappings(conn, pairs) do
    {count, newly} = LidMappingFileStore.store_mappings(conn, pairs)
    if count > 0, do: Logger.debug("Stored #{count} LID↔PN mapping(s) from history sync")
    format_lid_mappings(newly)
  end

  @doc "Format `{lid, pn}` JID pairs as `[%{lid: %Amarula.Address{}, pn: %Amarula.Address{}}]`."
  @spec format_lid_mappings([{String.t(), String.t()}]) :: [map()]
  def format_lid_mappings(pairs) do
    Enum.map(pairs, fn {lid, pn} ->
      %{lid: Amarula.Address.parse(lid), pn: Amarula.Address.parse(pn)}
    end)
  end

  @doc ~S(Build the `<iq xmlns="encrypt" type="get">` stanza to force-refresh sessions for `jids`.)
  @spec force_refresh_iq([String.t()]) :: Node.t()
  def force_refresh_iq(jids) do
    user_nodes =
      Enum.map(jids, fn jid ->
        %Node{tag: "user", attrs: %{"jid" => jid, "reason" => "identity"}, content: nil}
      end)

    %Node{
      tag: "iq",
      attrs: [{"xmlns", "encrypt"}, {"type", "get"}, {"to", Constants.s_whatsapp_net()}],
      content: [%Node{tag: "key", attrs: %{}, content: user_nodes}]
    }
  end

  @doc "Resolve a LID JID to its canonical `@s.whatsapp.net` PN JID when mapped (preserving device)."
  @spec canonical_jid(term(), String.t()) :: String.t()
  def canonical_jid(conn, jid) do
    with true <- JID.lid_user?(jid),
         pn_user when is_binary(pn_user) <- LidMappingFileStore.pn_for_lid(conn, jid),
         %{} = decoded <- JID.decode(jid) do
      device = Map.get(decoded, :device, 0) || 0
      JID.encode(%{user: pn_user, server: "s.whatsapp.net", device: device})
    else
      _ -> jid
    end
  end

  @doc "Opt-in PN→LID re-addressing for outbound sends when `resolve_pn_to_lid?` is enabled."
  @spec lid_target(term(), boolean(), String.t()) :: String.t()
  def lid_target(conn, true, jid) do
    if JID.jid_user?(jid) and not JID.lid_user?(jid) do
      case LidMappingFileStore.lid_for_pn(conn, JID.jid_normalized_user(jid)) do
        lid when is_binary(lid) -> JID.encode(%{user: lid, server: "lid"})
        _ -> jid
      end
    else
      jid
    end
  end

  def lid_target(_conn, _resolve?, jid), do: jid
end
