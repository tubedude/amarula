defmodule Amarula.Protocol.AppState.Patch do
  @moduledoc """
  Decode app-state syncd mutations/patches into `SyncActionData` mutations and the
  next LTHash collection state. Ported from Baileys `decodeSyncdMutations` /
  `decodeSyncdPatch` (`chat-utils.ts`).

  Pure given a key lookup: `get_key.(key_id_base64)` → the expanded
  `Amarula.Protocol.AppState.Keys` (or `nil` if the app-state-sync key isn't
  available yet — then the record is skipped and the caller may park the
  collection until `APP_STATE_SYNC_KEY_SHARE` arrives).

  Collection state is `%{version, hash, index_value_map}` where `index_value_map`
  maps `base64(index_mac) => value_mac` (so a later REMOVE can subtract the right
  value mac from the LTHash).
  """

  alias Amarula.Protocol.AppState.{LTHash, Mutation}
  alias Amarula.Protocol.Proto

  @type state :: %{version: non_neg_integer(), hash: binary(), index_value_map: map()}
  @type mutation :: %{operation: :set | :remove, action: struct(), index: [String.t()]}

  @doc "A fresh, empty collection state."
  @spec new_state() :: state()
  def new_state, do: %{version: 0, hash: LTHash.zero(), index_value_map: %{}}

  @doc """
  Decode `records` (a list of `SyncdRecord` / `SyncdMutation`) against `state`,
  returning `{:ok, mutations, new_state}`. `get_key` resolves a record's
  app-state-sync key. With `validate_macs: true` (default), the value MAC and
  index MAC are checked; a record that fails MAC, can't decrypt, or has a missing
  key is skipped.
  """
  @spec decode_mutations([struct()], state(), (String.t() -> map() | nil), keyword()) ::
          {:ok, [mutation()], state()}
  def decode_mutations(records, state, get_key, opts \\ []) do
    validate? = Keyword.get(opts, :validate_macs, true)

    {mutations, adds, subs, ivm} =
      Enum.reduce(records, {[], [], [], state.index_value_map}, fn rec, acc ->
        fold_record(rec, get_key, validate?, acc)
      end)

    new_hash = LTHash.subtract_then_add(state.hash, subs, adds)
    new_state = %{state | hash: new_hash, index_value_map: ivm}
    {:ok, Enum.reverse(mutations), new_state}
  end

  # --- internals ---

  defp fold_record(rec, get_key, validate?, {muts, adds, subs, ivm} = acc) do
    {operation, record} = operation_and_record(rec)

    with key when not is_nil(key) <- get_key.(key_id_b64(record)),
         {:ok, mutation, value_mac, index_mac} <- decode_one(operation, record, key, validate?) do
      {ivm, adds, subs} = mix(ivm, adds, subs, operation, index_mac, value_mac)
      {[mutation | muts], adds, subs, ivm}
    else
      _ -> acc
    end
  end

  # A SyncdMutation carries an operation + record; a bare SyncdRecord is a SET.
  defp operation_and_record(%Proto.SyncdMutation{operation: op, record: record}) do
    {op_atom(op), record}
  end

  defp operation_and_record(%Proto.SyncdRecord{} = record), do: {:set, record}

  defp decode_one(operation, record, key, validate?) do
    blob = record.value.blob
    enc = binary_part(blob, 0, byte_size(blob) - 32)
    value_mac = binary_part(blob, byte_size(blob) - 32, 32)
    key_id = record.keyId.id

    with :ok <- check_value_mac(validate?, operation, enc, key_id, key.value_mac_key, value_mac),
         plaintext <- Mutation.decrypt_value(enc, key.value_encryption_key),
         action = Proto.SyncActionData.decode(plaintext),
         :ok <- check_index_mac(validate?, action.index, key.index_key, record.index.blob) do
      mutation = %{operation: operation, action: action, index: decode_index(action.index)}
      {:ok, mutation, value_mac, record.index.blob}
    end
  end

  defp check_value_mac(false, _op, _enc, _key_id, _k, _mac), do: :ok

  defp check_value_mac(true, op, enc, key_id, value_mac_key, expected) do
    if Mutation.generate_mac(op, enc, key_id, value_mac_key) == expected, do: :ok, else: :bad_mac
  end

  defp check_index_mac(false, _index, _key, _expected), do: :ok

  defp check_index_mac(true, index, index_key, expected) do
    if :crypto.mac(:hmac, :sha256, index_key, index) == expected, do: :ok, else: :bad_index_mac
  end

  # LTHash mix: SET adds its value mac (and subtracts the prior one for this
  # index, if any); REMOVE subtracts the prior value mac and drops the index.
  defp mix(ivm, adds, subs, :set, index_mac, value_mac) do
    k = Base.encode64(index_mac)
    subs = if prev = Map.get(ivm, k), do: [prev | subs], else: subs
    {Map.put(ivm, k, value_mac), [value_mac | adds], subs}
  end

  defp mix(ivm, adds, subs, :remove, index_mac, _value_mac) do
    k = Base.encode64(index_mac)

    case Map.pop(ivm, k) do
      {nil, ivm} -> {ivm, adds, subs}
      {prev, ivm} -> {ivm, adds, [prev | subs]}
    end
  end

  defp decode_index(index_bytes) do
    case Jason.decode(index_bytes) do
      {:ok, list} when is_list(list) -> list
      _ -> [to_string(index_bytes)]
    end
  end

  defp key_id_b64(record), do: Base.encode64(record.keyId.id)

  defp op_atom(:SET), do: :set
  defp op_atom(:REMOVE), do: :remove
  defp op_atom(0), do: :set
  defp op_atom(1), do: :remove
end
