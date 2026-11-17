defmodule Amarula.Protocol.AppState.Sync do
  @moduledoc """
  App-state sync orchestration helpers, ported from Baileys `resyncAppState`
  (`src/Socket/chats.ts`). Builds the patch-request IQ, extracts the per-collection
  patches from the reply, and decodes them through `AppState.Patch` +
  `AppState.SyncAction` into consumer changes — given a key lookup and the prior
  collection state.

  The wire round-trip + storage live in `Connection`; this module is the
  pure glue between them and the decode stack.
  """

  alias Amarula.Protocol.AppState.{LTHash, Mutation, Patch, SyncAction}
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
  `{:ok, changes, new_state, mismatches}` — `changes` are `SyncAction.decode/1`
  results (`{:chat, _}` / `{:contact, _}` / …); `mismatches` is a list of
  `{:snapshot_mac_mismatch | :patch_mac_mismatch, name}`, one per patch whose
  aggregate collection MAC didn't verify.

  `name` is the collection name — it feeds the snapshot/patch MACs. With
  `validate_macs: true` (default), each patch's **patch MAC** (authenticating the
  patch's mutations) and **snapshot MAC** (authenticating the resulting LTHash) are
  checked against the app-state-sync key, in addition to the per-record value/index
  MACs `Patch.decode_mutations/4` already enforces per record. The two checks are
  NOT equivalent to a single collection abort (Baileys `chat-utils.ts`
  `decodeSyncdPatch` / `decodePatches`, upstream PR #2456), each is handled
  differently:

  - A **patch MAC** mismatch means the patch's mutations aren't authenticated
    against this collection at all — they are dropped entirely (never decoded),
    exactly as `decodeSyncdPatch` throws before calling `decodeSyncdMutations`.
    The collection version still advances to this patch's version, and decoding
    continues to the next patch — so a single bad patch can no longer freeze the
    collection at the same version forever (the original bug this ports away
    from: the old behavior kept re-requesting the same version, which kept
    hitting the same mismatch).
  - A **snapshot MAC** mismatch means the resulting LTHash doesn't match the
    server's bookkeeping. Since every record's *individual* value/index MAC
    already authenticated it before this check runs, the patch's own mutations
    still apply. Decoding continues when the patch directly follows the local
    state, as WhatsApp Web does (whatsmeow #1319). It **stops for the rest of this
    batch** when local state is obviously missing: a skipped version, or an empty
    hash on a patch other than the first. The rest is picked up on the next resync.

  A patch whose key isn't available yet decodes to no mutations, so there is
  nothing to authenticate (not a mismatch).
  """
  @spec decode_collection(
          [Proto.SyncdPatch.t()],
          Patch.state(),
          (String.t() -> map() | nil),
          String.t(),
          keyword()
        ) :: {:ok, [SyncAction.result()], Patch.state(), [{atom(), String.t()}]}
  def decode_collection(patches, state, get_key, name, opts \\ []) do
    validate? = Keyword.get(opts, :validate_macs, true)

    {changes, new_state, mismatches} =
      Enum.reduce_while(patches, {[], state, []}, fn patch, acc ->
        decode_one_patch(patch, acc, validate?, get_key, name)
      end)

    {:ok, changes, new_state, Enum.reverse(mismatches)}
  end

  # --- internals ---

  # One reduce_while step: bump the version, then patchMac ⇒ snapshotMac. See the
  # decode_collection/5 moduledoc for what each branch means.
  defp decode_one_patch(patch, {acc, prior, mismatches}, validate?, get_key, name) do
    st = bump(prior, patch)

    case verify_patch_mac(validate?, patch, st, name, get_key) do
      :ok ->
        {:ok, muts, new_st} =
          Patch.decode_mutations(patch.mutations, st, get_key, validate_macs: validate?)

        changes = acc ++ Enum.map(muts, &SyncAction.decode/1)

        continue_after_decode(
          patch,
          changes,
          new_st,
          prior,
          mismatches,
          {validate?, get_key, name}
        )

      {:error, reason} ->
        {:cont, {acc, st, [reason | mismatches]}}
    end
  end

  defp continue_after_decode(
         patch,
         changes,
         new_st,
         prior,
         mismatches,
         {validate?, get_key, name}
       ) do
    case verify_snapshot_mac(validate?, patch, new_st, name, get_key) do
      :ok ->
        {:cont, {changes, new_st, mismatches}}

      {:error, reason} ->
        step = if follows_local_state?(prior, new_st), do: :cont, else: :halt
        {step, {changes, new_st, [reason | mismatches]}}
    end
  end

  defp follows_local_state?(prior, new_st) do
    new_st.version == prior.version + 1 and
      (new_st.version == 1 or prior.hash != LTHash.zero())
  end

  # The patch MAC covers the patch's OWN value MACs (as sent by the server, off
  # `patch.mutations` — not yet decoded), authenticating that this exact set of
  # mutations was issued by the key holder for this collection/version. Checked
  # BEFORE decoding, matching decodeSyncdPatch: a mismatch here means the patch's
  # mutations are never decoded at all.
  defp verify_patch_mac(false, _patch, _st, _name, _get_key), do: :ok

  defp verify_patch_mac(true, patch, st, name, get_key) do
    case patch_key(patch, get_key) do
      nil ->
        :ok

      key ->
        value_macs = Enum.map(patch.mutations, &value_mac/1)

        patch_mac =
          Mutation.generate_patch_mac(
            patch.snapshotMac,
            value_macs,
            st.version,
            name,
            key.patch_mac_key
          )

        if mac_equal?(patch_mac, patch.patchMac),
          do: :ok,
          else: {:error, {:patch_mac_mismatch, name}}
    end
  end

  # The snapshot MAC covers the resulting LTHash after this patch's mutations are
  # applied — checked AFTER decoding, against the post-decode state. A mismatch
  # doesn't undo the mutations that already applied; the caller decides whether
  # to keep decoding this batch.
  defp verify_snapshot_mac(false, _patch, _st, _name, _get_key), do: :ok

  defp verify_snapshot_mac(true, patch, st, name, get_key) do
    case patch_key(patch, get_key) do
      nil ->
        :ok

      key ->
        snapshot_mac =
          Mutation.generate_snapshot_mac(st.hash, st.version, name, key.snapshot_mac_key)

        if mac_equal?(snapshot_mac, patch.snapshotMac),
          do: :ok,
          else: {:error, {:snapshot_mac_mismatch, name}}
    end
  end

  # The app-state-sync key for a patch: the patch's own keyId, falling back to the
  # first record's when the patch keyId is absent OR doesn't resolve (all records in
  # a patch share one key). The fallback keeps the collection MACs covering a patch
  # that decoded to real mutations even if its own keyId didn't resolve.
  defp patch_key(%Proto.SyncdPatch{keyId: %{id: id}} = patch, get_key)
       when is_binary(id) and id != "" do
    get_key.(Base.encode64(id)) || patch_key_from_records(patch, get_key)
  end

  defp patch_key(%Proto.SyncdPatch{} = patch, get_key),
    do: patch_key_from_records(patch, get_key)

  defp patch_key_from_records(%Proto.SyncdPatch{mutations: [mutation | _]}, get_key) do
    case record_key_id(mutation) do
      id when is_binary(id) -> get_key.(Base.encode64(id))
      _ -> nil
    end
  end

  defp patch_key_from_records(_patch, _get_key), do: nil

  defp record_key_id(%Proto.SyncdMutation{record: %{keyId: %{id: id}}}), do: id
  defp record_key_id(%Proto.SyncdRecord{keyId: %{id: id}}), do: id
  defp record_key_id(_), do: nil

  defp value_mac(%Proto.SyncdMutation{record: %{value: %{blob: blob}}}), do: last32(blob)
  defp value_mac(%Proto.SyncdRecord{value: %{blob: blob}}), do: last32(blob)

  defp last32(blob) when is_binary(blob) and byte_size(blob) >= 32,
    do: binary_part(blob, byte_size(blob) - 32, 32)

  defp last32(_), do: <<>>

  # Constant-time compare; a nil/short/absent MAC is a mismatch.
  defp mac_equal?(a, b) when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b),
    do: :crypto.hash_equals(a, b)

  defp mac_equal?(_a, _b), do: false

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
