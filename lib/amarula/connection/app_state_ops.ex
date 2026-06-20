defmodule Amarula.Connection.AppStateOps do
  @moduledoc """
  Pure app-state-sync helpers for `Amarula.Connection`.

  The sync flow is Storage- and IQ-bound — requesting patches, persisting
  collection state, decoding against stored keys, emitting events — and stays on
  `Connection`. What's pure lives here: pulling shared sync-keys out of incoming
  messages, and partitioning decoded changes into the chat/contact event lists.
  """

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
end
