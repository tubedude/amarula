defmodule Amarula.Protocol.Call do
  @moduledoc """
  Parse inbound `<call>` stanzas, ported from Baileys `handleCall` /
  `getCallStatusFromNode` (`src/Socket/messages-recv.ts`).

  A `<call>` wraps a single info child whose tag carries the lifecycle event:
  `offer` / `offer_notice` (someone is calling), `terminate` (call ended —
  `reason="timeout"` = nobody answered), `reject`, `accept`, and the various
  in-progress tags (`preaccept`, `transport`, …) which map to `:ringing`.

  Pure parsing; the `Connection` acks the node and surfaces the result as a
  `:call_update` consumer event.
  """

  alias Amarula.Protocol.Binary.{Node, NodeUtils}

  @typedoc """
  A call lifecycle status (Baileys `WACallEvent['status']`):

    * `:offer`     — an incoming call is ringing (`offer` / `offer_notice`)
    * `:terminate` — the call ended (caller hung up / it was answered elsewhere)
    * `:timeout`   — a `terminate` with `reason="timeout"`: nobody answered
    * `:reject`    — the call was rejected
    * `:accept`    — the call was accepted
    * `:ringing`   — any other in-progress signalling tag
  """
  @type status :: :offer | :terminate | :timeout | :reject | :accept | :ringing

  @typedoc """
  A parsed inbound call event:

    * `:chat`      — the chat the call is in (`attrs.from`); for a 1:1 call this is
      the caller, for a group call the group
    * `:from`      — who started the call (`call-creator`)
    * `:id`        — the `call-id` (correlates offer→terminate for one call)
    * `:status`    — the lifecycle `status/0`
    * `:timestamp` — unix seconds (`attrs.t`), or `nil`
    * `:offline`   — `true` if delivered from the offline queue (not live)
    * `:video?`    — `true` for a video call (offer only; `false` otherwise)
    * `:group?`    — `true` for a group call
    * `:group_jid` — the group `Address` for a group call, else `nil`
  """
  @type t :: %{
          chat: Amarula.Address.t() | nil,
          from: Amarula.Address.t() | nil,
          id: String.t() | nil,
          status: status(),
          timestamp: integer() | nil,
          offline: boolean(),
          video?: boolean(),
          group?: boolean(),
          group_jid: Amarula.Address.t() | nil
        }

  @doc """
  Parse a `<call>` node into a `t/0`. Returns `{:error, :invalid}` for a node with
  no info child (the lifecycle tag we key the status off).
  """
  @spec parse(Node.t()) :: {:ok, t()} | {:error, :invalid}
  def parse(%Node{tag: "call", attrs: attrs} = node) do
    case NodeUtils.get_all_binary_node_children(node) do
      [%Node{} = info | _] -> {:ok, build(attrs, info)}
      _ -> {:error, :invalid}
    end
  end

  def parse(%Node{}), do: {:error, :invalid}

  defp build(attrs, %Node{tag: tag, attrs: info_attrs} = info) do
    status = status_from(tag, info_attrs)
    group_jid = info_attrs["group-jid"]

    %{
      chat: Amarula.Address.parse(attrs["from"]),
      from: Amarula.Address.parse(info_attrs["call-creator"]),
      id: info_attrs["call-id"],
      status: status,
      timestamp: parse_ts(attrs["t"]),
      offline: Map.has_key?(attrs, "offline"),
      video?: status == :offer and not is_nil(NodeUtils.get_binary_node_child(info, "video")),
      group?: info_attrs["type"] == "group" or not is_nil(group_jid),
      group_jid: Amarula.Address.parse(group_jid)
    }
  end

  defp status_from("offer", _attrs), do: :offer
  defp status_from("offer_notice", _attrs), do: :offer
  defp status_from("terminate", %{"reason" => "timeout"}), do: :timeout
  defp status_from("terminate", _attrs), do: :terminate
  defp status_from("reject", _attrs), do: :reject
  defp status_from("accept", _attrs), do: :accept
  defp status_from(_tag, _attrs), do: :ringing

  defp parse_ts(nil), do: nil

  defp parse_ts(t) when is_binary(t) do
    case Integer.parse(t) do
      {n, _} -> n
      :error -> nil
    end
  end
end
