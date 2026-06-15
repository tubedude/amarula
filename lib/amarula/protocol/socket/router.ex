defmodule Amarula.Protocol.Socket.Router do
  @moduledoc """
  Pure routing decision for inbound server nodes — cluster 3 of the
  `Connection` split (see `docs/plans/CM_SPLIT.plan.md`).

  `Connection.process_server_node/2` used to inline a ~20-arm `case` over
  `{tag, type, first_child, xmlns}` that both *decided* which handler runs and
  *ran* it. This module isolates the decision: `route/1` maps a node to a handler
  tag (an atom) plus, where the routing key implies it, a sub-kind. CM keeps the
  handlers and just dispatches on the returned tag.

  Keeping the table pure makes the protocol's dispatch surface testable without a
  live socket, and turns "which frames do we handle?" into one readable list.
  """

  alias Amarula.Protocol.Binary.{Node, NodeUtils}

  @typedoc """
  The handler a node routes to. CM maps each to its handler function. `:unhandled`
  is the explicit catch-all (CM logs it loudly).
  """
  @type handler ::
          :pair_device
          | :pair_success
          | :auth_success
          | :message
          | :stream_error
          | :connection_failure
          | :server_ping
          | :ping_response
          | :iq_response
          | :xml_stream_end
          | :offline_preview
          | :offline_complete
          | :edge_routing
          | :dirty
          | :ignore
          | :notification
          | :retry_receipt
          | :receipt_ack
          | :call_ack
          | :message_ack
          | :unhandled

  @doc """
  Decide which handler an inbound node routes to. Pure: depends only on the node's
  tag, `type`/`xmlns` attrs, and first-child tag — never on connection state.
  """
  @spec route(Node.t()) :: handler()
  def route(%Node{} = node) do
    first_child = NodeUtils.get_first_child_tag(node)
    xmlns = NodeUtils.get_attr(node, "xmlns")
    class = NodeUtils.get_attr(node, "class")

    case {node.tag, NodeUtils.get_attr(node, "type"), first_child, xmlns} do
      {"iq", "set", "pair-device", _} -> :pair_device
      {"iq", _, "pair-success", _} -> :pair_success
      {"success", _, _, _} -> :auth_success
      {"message", _, _, _} -> :message
      {"stream:error", _, _, _} -> :stream_error
      {"failure", _, _, _} -> :connection_failure
      {"iq", "get", _, "urn:xmpp:ping"} -> :server_ping
      {"iq", _, "ping", _} -> :ping_response
      {"iq", "result", _, _} -> :iq_response
      {"iq", "error", _, _} -> :iq_response
      {"xmlstreamend", _, _, _} -> :xml_stream_end
      {"ib", _, "offline_preview", _} -> :offline_preview
      {"ib", _, "offline", _} -> :offline_complete
      {"ib", _, "edge_routing", _} -> :edge_routing
      {"ib", _, "dirty", _} -> :dirty
      {"ib", _, "thread_metadata", _} -> :ignore
      {"notification", _, _, _} -> :notification
      # Only a class="message" ack confirms a send we parked by msg_id. Other
      # acks (receipts, notifications, …) carry no send correlation — ignore them.
      {"ack", _, _, _} when class == "message" -> :message_ack
      {"ack", _, _, _} -> :ignore
      {"receipt", "retry", _, _} -> :retry_receipt
      {"receipt", _, _, _} -> :receipt_ack
      {"call", _, _, _} -> :call_ack
      _ -> :unhandled
    end
  end
end
