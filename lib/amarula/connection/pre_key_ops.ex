defmodule Amarula.Connection.PreKeyOps do
  @moduledoc """
  Pure pre-key decision logic for `Amarula.Connection` (Baileys
  `uploadPreKeysToServerIfRequired`).

  The socket-bound parts — sending the count IQ, the upload round-trip, the
  tracked-IQ continuations, `finish_login` — stay on `Connection`, since they
  drive the login lifecycle. What lives here is pure: building the count-query
  node, reading the server's count, choosing the upload target, and deciding
  whether an upload is needed. No socket, no `state`; testable directly.
  """

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Crypto.Constants
  alias Amarula.Protocol.Signal.PreKeys

  @doc "The `<iq type=get xmlns=encrypt><count/></iq>` that asks how many one-time prekeys the server holds."
  @spec count_query_node() :: Node.t()
  def count_query_node do
    %Node{
      tag: "iq",
      attrs: [
        {"xmlns", "encrypt"},
        {"type", "get"},
        {"to", Constants.s_whatsapp_net()}
      ],
      content: [%Node{tag: "count", attrs: %{}, content: nil}]
    }
  end

  @doc "Read the `<count value=…>` the server returned (defaults to 0 when absent)."
  @spec server_count(Node.t()) :: non_neg_integer()
  def server_count(node) do
    case NodeUtils.get_binary_node_child(node, "count") do
      nil -> 0
      count_node -> String.to_integer(NodeUtils.get_attr(count_node, "value") || "0")
    end
  end

  @doc """
  How many new prekeys to upload for a given server count: enough to restore the
  server pool back to `initial_pre_key_count` (never fewer than `min_pre_key_count`).

  Baileys only uploaded the deep batch when the server held *exactly* 0, and topped
  up by `min` (5) otherwise — so the pool idled near-empty and dropped first-contact
  messages (#2643). Refilling toward the initial count keeps the pool healthy.
  """
  @spec upload_target(non_neg_integer()) :: pos_integer()
  def upload_target(server_count) do
    max(PreKeys.min_pre_key_count(), PreKeys.initial_pre_key_count() - server_count)
  end

  @doc """
  Whether to upload, given the server count and our creds. True when the server
  pool has dropped to/below the low-water mark, or our most-recently-generated
  prekey is gone locally (Baileys `verifyCurrentPreKeyExists`). `target` is unused
  here (kept for call-site symmetry with `upload_target/1`).
  """
  @spec upload_needed?(non_neg_integer(), pos_integer(), map()) :: boolean()
  def upload_needed?(server_count, _target, creds) do
    server_count <= PreKeys.low_water_pre_key_count() or missing_current_pre_key?(creds)
  end

  @doc "True when the last-generated one-time prekey is no longer in local storage."
  @spec missing_current_pre_key?(map()) :: boolean()
  def missing_current_pre_key?(creds) do
    current_id = Map.get(creds, :next_pre_key_id, 1) - 1
    current_id > 0 and not Map.has_key?(Map.get(creds, :pre_keys, %{}), current_id)
  end
end
