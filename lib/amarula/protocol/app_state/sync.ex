defmodule Amarula.Protocol.AppState.Sync do
  @moduledoc """
  App-state sync orchestration helpers, ported from Baileys `resyncAppState`
  (`src/Socket/chats.ts`). Builds the patch-request IQ, extracts the per-collection
  patches from the reply, and decodes them through `AppState.Patch` +
  `AppState.SyncAction` into consumer changes — given a key lookup and the prior
  collection state.

  The wire round-trip + storage live in `ConnectionManager`; this module is the
  pure glue between them and the decode stack.
  """

  alias Amarula.Protocol.AppState.{Patch, SyncAction}
  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Proto

  # The five app-state collections, smallest/most-critical first.
  @collections ~w(critical_block critical_unblock_low regular_high regular regular_low)

  @doc "The collection names we sync."
  @spec collections() :: [String.t()]
  def collections, do: @collections

  @doc """
  Build the patch-request IQ for `collections`, each a `{name, version,
  snapshot?}` tuple:

      <iq xmlns="w:sync:app:state" type="set"><sync>
        <collection name= version= return_snapshot=/>…</sync></iq>
  """
  @spec request_iq([{String.t(), non_neg_integer(), boolean()}]) :: Node.t()
  def request_iq(collections) do
    nodes =
      Enum.map(collections, fn {name, version, snapshot?} ->
        %Node{
          tag: "collection",
          attrs: %{
            "name" => name,
            "version" => Integer.to_string(version),
            "return_snapshot" => to_string(snapshot?)
          },
          content: nil
        }
      end)

    %Node{
      tag: "iq",
      attrs: [{"xmlns", "w:sync:app:state"}, {"type", "set"}],
      content: [%Node{tag: "sync", attrs: %{}, content: nodes}]
    }
  end

  @doc """
  Pull the `<collection>` results out of a sync IQ reply. Returns a list of
  `%{name, patches: [%SyncdPatch{}], has_more: bool}`. (Snapshots delivered as an
  external blob reference are noted but not downloaded here.)
  """
  @spec extract_collections(Node.t()) :: [map()]
  def extract_collections(reply) do
    case NodeUtils.get_binary_node_child(reply, "sync") do
      %Node{} = sync ->
        sync
        |> NodeUtils.get_binary_node_children("collection")
        |> Enum.map(&collection/1)

      _ ->
        []
    end
  end

  @doc """
  Decode a collection's patches against `state` with `get_key`, returning
  `{:ok, changes, new_state}` where `changes` are `SyncAction.decode/1` results
  (`{:chat, _}` / `{:contact, _}` / …).
  """
  @spec decode_collection([Proto.SyncdPatch.t()], Patch.state(), (String.t() -> map() | nil)) ::
          {:ok, [SyncAction.result()], Patch.state()}
  def decode_collection(patches, state, get_key) do
    {changes, final_state} =
      Enum.reduce(patches, {[], state}, fn patch, {acc, st} ->
        records = patch.mutations |> Enum.map(& &1)
        {:ok, muts, st} = Patch.decode_mutations(records, bump(st, patch), get_key)
        {acc ++ Enum.map(muts, &SyncAction.decode/1), st}
      end)

    {:ok, changes, final_state}
  end

  # --- internals ---

  defp collection(node) do
    patches_node = NodeUtils.get_binary_node_child(node, "patches") || node

    patches =
      patches_node
      |> NodeUtils.get_binary_node_children("patch")
      |> Enum.flat_map(&decode_patch_node/1)

    %{
      name: NodeUtils.get_attr(node, "name"),
      patches: patches,
      has_more: NodeUtils.get_attr(node, "has_more_patches") == "true"
    }
  end

  defp decode_patch_node(%Node{content: content}) when is_binary(content) do
    [Proto.SyncdPatch.decode(content)]
  end

  defp decode_patch_node(_), do: []

  # Advance the collection version to the patch's version (if present).
  defp bump(state, %Proto.SyncdPatch{version: %{version: v}}) when is_integer(v),
    do: %{state | version: v}

  defp bump(state, _patch), do: state
end
