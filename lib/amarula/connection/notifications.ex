defmodule Amarula.Connection.Notifications do
  @moduledoc """
  Pure notification parsers for `Amarula.Connection`.

  Server `<notification>` stanzas are acked + dispatched by `Connection` (it
  emits events, mutates creds, drops caches, runs IQ continuations — all
  socket/state-bound). The *parsing* of a node into an event payload or a
  decision is pure, and lives here: `account_sync`, `devices`, and `picture`.
  The handlers stay on `Connection` and call these to get the data to act on.
  """

  alias Amarula.Protocol.Binary.{JID, Node, NodeUtils}

  @doc """
  Classify an `account_sync` notification:

    * `{:disappearing, duration}` — default disappearing-mode changed
    * `{:blocklist, [%{jid, action}]}` — blocklist additions/removals
    * `:ignore` — nothing we handle
  """
  @spec account_sync(Node.t()) ::
          {:disappearing, String.t() | nil} | {:blocklist, [map()]} | :ignore
  def account_sync(node) do
    cond do
      child = NodeUtils.get_binary_node_child(node, "disappearing_mode") ->
        {:disappearing, NodeUtils.get_attr(child, "duration")}

      child = NodeUtils.get_binary_node_child(node, "blocklist") ->
        items =
          child
          |> NodeUtils.get_binary_node_children("item")
          |> Enum.map(fn item ->
            %{jid: NodeUtils.get_attr(item, "jid"), action: NodeUtils.get_attr(item, "action")}
          end)

        {:blocklist, items}

      true ->
        :ignore
    end
  end

  @doc """
  Parse a `devices` notification into `{tag, normalized_users}` where `tag` is
  `"add"`/`"remove"`/`"update"`, or `:ignore` for an unrecognized shape. The
  caller drops cached device lists (and, for "remove", sessions) for the users.
  """
  @spec devices(Node.t()) :: {String.t(), [String.t()]} | :ignore
  def devices(node) do
    case node.content do
      [%Node{tag: tag} = child | _] when tag in ~w(add remove update) ->
        users =
          child
          |> NodeUtils.get_binary_node_children("device")
          |> Enum.map(&NodeUtils.get_attr(&1, "jid"))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&JID.jid_normalized_user/1)
          |> Enum.uniq()

        {tag, users}

      _ ->
        :ignore
    end
  end

  @doc """
  Parse a `picture` notification into `{from, img_url}` where `img_url` is
  `"changed"` (a `<set>` is present) or `"removed"`.
  """
  @spec picture(Node.t()) :: {String.t(), String.t()}
  def picture(node) do
    from = node |> NodeUtils.get_attr("from") |> JID.jid_normalized_user()
    img_url = if NodeUtils.get_binary_node_child(node, "set"), do: "changed", else: "removed"
    {from, img_url}
  end
end
