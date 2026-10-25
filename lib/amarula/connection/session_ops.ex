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
  # LID-aware, so it matches wherever the session actually lives after a PN→LID migration.
  def wipe_identity_sessions(conn, instance_id, from) do
    with signal_user when is_binary(signal_user) <- LidMappingFileStore.signal_user(conn, from),
         {:ok, keys} <- SessionStore.list_session_keys(conn) do
      prefix = signal_user <> "."

      # Delete each device's session THROUGH its custodian, so an in-flight encrypt
      # on that address serializes against the wipe and can't resurrect it.
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
  # The migrated_pn_sessions guard also spares a storage read for repeat senders.
  def maybe_migrate_sender_session(state, node) do
    author = NodeUtils.get_attr(node, "participant") || NodeUtils.get_attr(node, "from")

    with true <- JID.pn_user?(author),
         %{user: pn_user} <- JID.decode(author),
         false <- MapSet.member?(state.migrated_pn_sessions, pn_user),
         lid_user when is_binary(lid_user) <- LidMappingFileStore.lid_for_pn(state.conn, author),
         {:ok, keys} <- SessionStore.list_session_keys(state.conn) do
      # Ignore the :migrated/:none result on purpose: the receive path never
      # force-fetches a bundle. A :none (no PN session to move) just means an
      # inbound pkmsg will establish the session on decrypt — fetching is a
      # send-side concern (see the migrate_pn_sessions handler).
      {state, _result} = migrate_pn_user(state, pn_user, lid_user, keys)
      state
    else
      # A storage adapter that can't enumerate keys can't migrate in place; the
      # decrypt lookup will then miss the still-PN-keyed ratchet. Rare (File/DETS
      # both enumerate) but not silent.
      {:error, reason} ->
        Logger.warning(
          "PN→LID migrate on receive: cannot enumerate sessions (#{inspect(reason)})"
        )

        state

      # Every other else case is routine, not an anomaly: not a PN user, already
      # migrated, or no LID mapping. `jid_user?` having passed guarantees
      # `JID.decode/1` returns a map, so that clause can't fail.
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
    # Enumerate the session store ONCE for the whole batch (not per pair), then
    # move each pair's ratchet; the lids that had nothing to move fall back to a
    # fresh bundle fetch.
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
  # Both the PN and LID records are mutated through their SessionCustodians, so a
  # concurrent send/decrypt on either can't clobber the migration mid-flight. The
  # residual hazard is the cross-record sequencing (read PN, then write LID) — see
  # migrate_pn_records, which uses install_if_absent so a session a concurrent send
  # injected on the LID address wins instead of being overwritten.
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

  # Move each of pn_user's device sessions onto the LID address THROUGH the
  # custodians (the per-record lock). Cross-record and non-atomic, so it is written
  # to be safe under a concurrent send that injects a LID session mid-migration:
  #   1. read the PN record,
  #   2. install it on the LID address ONLY IF no live session is already there
  #      (install_if_absent) — a concurrently-injected LID session WINS; we never
  #      clobber a live ratchet with the migrated record,
  #   3. drop the PN source only after (2) succeeded — :ok or already-present both
  #      mean the LID side is settled — and only count the pair when the delete
  #      itself landed. A failure at any step leaves the PN record for a later
  #      re-migration (idempotent: step 2 then finds the LID session and skips).
  # (The PN side has no concurrent mutator here — inbound PN decrypts run in this
  # same Connection process, and sends resolve to the LID address.) Returns moved.
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

  # Migrate one newly-mapped {lid, pn} pair (over the batch's pre-listed `keys`),
  # threading state and emitting the lid into the fetch list ONLY when there was no
  # PN session to re-key (:none) — a migrated contact must not be force-refreshed,
  # which would clobber the moved ratchet. Shaped for Enum.flat_map_reduce/3.
  defp migrate_pair({lid, pn}, state, keys) do
    # store_mappings accepts pairs in either order; guard the orientation here so a
    # reversed pair can't migrate the wrong direction.
    with true <- JID.lid_user?(lid),
         %{user: pn_user} <- JID.decode(pn),
         %{user: lid_user} <- JID.decode(lid) do
      case migrate_pn_user(state, pn_user, lid_user, keys) do
        {state, :none} -> {[lid], state}
        {state, _} -> {[], state}
      end
    else
      # The pairs come from USync, so a mis-oriented or undecodable jid is an
      # upstream anomaly, not routine — surface it (JID-free) rather than drop it.
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
  # LID → PN canonicalization. Non-LID jids and unmapped LIDs pass through.
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
    if JID.pn_user?(jid) do
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
