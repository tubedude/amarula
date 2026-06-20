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
  Upload target for a given server count: the big initial batch when the server
  holds none, otherwise the min top-up count.
  """
  @spec upload_target(non_neg_integer()) :: pos_integer()
  def upload_target(0), do: PreKeys.initial_pre_key_count()
  def upload_target(_server_count), do: PreKeys.min_pre_key_count()

  @doc """
  Whether to upload, given the server count and our creds. True when the server
  is at/below the target, or our most-recently-generated prekey is gone locally
  (Baileys `verifyCurrentPreKeyExists`).
  """
  @spec upload_needed?(non_neg_integer(), pos_integer(), map()) :: boolean()
  def upload_needed?(server_count, target, creds) do
    server_count <= target or missing_current_pre_key?(creds)
  end

  @doc "True when the last-generated one-time prekey is no longer in local storage."
  @spec missing_current_pre_key?(map()) :: boolean()
  def missing_current_pre_key?(creds) do
    current_id = Map.get(creds, :next_pre_key_id, 1) - 1
    current_id > 0 and not Map.has_key?(Map.get(creds, :pre_keys, %{}), current_id)
  end
end
