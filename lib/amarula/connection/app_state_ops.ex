defmodule Amarula.Connection.AppStateOps do
  @moduledoc """
  App-state-sync helpers and storage/decode orchestration for `Amarula.Connection`.
  """

  require Logger

  alias Amarula.Protocol.AppState.{Keys, Patch, Sync}
  alias Amarula.Protocol.Binary.Node

  @doc """
  Extract any `appStateSyncKeyShare` keys carried in a message as
  `[{key_id_b64, key_data}]`. Returns `[]` for messages without a share.
  """
  @spec sync_keys(map()) :: [{String.t(), binary()}]
  def sync_keys(%{protocolMessage: %{appStateSyncKeyShare: %{keys: keys}}}) when is_list(keys) do
    Enum.flat_map(keys, fn
      %{keyId: %{keyId: id}, keyData: %{keyData: data}} when is_binary(id) and is_binary(data) ->
        [{Base.encode64(id), data}]

      _ ->
        []
    end)
  end

  def sync_keys(_msg), do: []

  @doc "All `appStateSyncKeyShare` keys across a batch of messages, flattened."
  @spec sync_keys_in(Enumerable.t()) :: [{String.t(), binary()}]
  def sync_keys_in(messages), do: Enum.flat_map(messages, &sync_keys/1)

  @doc """
  Partition decoded app-state changes into `{chats, contacts}` for the
  `:chats_update` / `:contacts_update` events.
  """
  @spec partition_changes([{:chat | :contact, term()}]) :: {[term()], [term()]}
  def partition_changes(changes) do
    chats = for {:chat, c} <- changes, do: c
    contacts = for {:contact, c} <- changes, do: c
    {chats, contacts}
  end

  @doc """
  Extract and persist any `appStateSyncKeyShare` keys in `messages`.
  Returns the number of keys stored (`0` when none were present).
  """
  @spec store_shared_keys(term(), term(), Enumerable.t()) :: non_neg_integer()
  def store_shared_keys(scope, profile, messages) do
    case sync_keys_in(messages) do
      [] ->
        0

      keys ->
        Enum.each(keys, fn {key_id_b64, key_data} ->
          Amarula.Storage.put(scope, profile, :app_state_sync_key, key_id_b64, key_data)
        end)

        length(keys)
    end
  end

  @doc """
  Build the `<iq xmlns=\"w:sync:app:state\">` request stanza for `names` using
  each collection's stored version.
  """
  @spec resync_iq(term(), term(), [String.t()]) :: Node.t()
  def resync_iq(scope, profile, names) do
    collections =
      Enum.map(names, fn name ->
        st = load_collection_state(scope, profile, name)
        {name, st.version, st.version == 0}
      end)

    Sync.request_iq(collections)
  end

  @doc """
  Reset the stored state of `names` (`:all` or list of collection names) to version 0
  and return the resolved list of collection names.
  """
  @spec reset_collections(term(), term(), :all | [String.t()]) :: [String.t()]
  def reset_collections(scope, profile, names) do
    resolved = if names == :all, do: Sync.collections(), else: names
    # Drop each collection's stored version/hash so the next resync_app_state/2 call
    # requests from version 0 — the server sees the same shape of request as a
    # first-ever sync (return_snapshot: true) and sends a full snapshot.
    Enum.each(resolved, &save_collection_state(scope, profile, &1, Patch.new_state()))
    resolved
  end

  @doc """
  Decode an app-state sync IQ `reply` against stored keys/versions, persist the
  updated collection state, and immediately invoke `on_collection.(chats, contacts)`
  for each collection.
  """
  @spec apply_reply(term(), term(), Node.t(), ([term()], [term()] -> any())) :: :ok
  def apply_reply(scope, profile, reply, on_collection \\ fn _chats, _contacts -> :ok end) do
    get_key = fn id_b64 ->
      case Amarula.Storage.get(scope, profile, :app_state_sync_key, id_b64) do
        {:ok, key_data} -> Keys.expand(key_data)
        :error -> nil
      end
    end

    reply
    |> Sync.extract_collections()
    |> Enum.each(fn %{name: name, patches: patches} ->
      prior = load_collection_state(scope, profile, name)

      {:ok, changes, new_state, mismatches} =
        Sync.decode_collection(patches, prior, get_key, name)

      # See Sync.decode_collection/5 moduledoc for the patch-MAC-vs-snapshot-MAC
      # handling this reports (ported from Baileys' chat-utils.ts resilience fix,
      # upstream PR #2456): neither kind aborts the collection outright, so a
      # single persistently-corrupt record can no longer freeze this collection's
      # sync at the same version forever.
      Enum.each(mismatches, fn reason ->
        Logger.warning("app-state sync for #{name}: #{inspect(reason)}")
      end)

      save_collection_state(scope, profile, name, new_state)
      {chats, contacts} = partition_changes(changes)
      on_collection.(chats, contacts)
    end)
  end

  defp load_collection_state(scope, profile, name) do
    case Amarula.Storage.get(scope, profile, :app_state_version, name) do
      {:ok, st} -> st
      :error -> Patch.new_state()
    end
  end

  defp save_collection_state(scope, profile, name, st) do
    Amarula.Storage.put(scope, profile, :app_state_version, name, st)
  end
end
