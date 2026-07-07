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
    * `:own_devices` — our own linked-device set changed (a `<devices>` child)
    * `:ignore` — nothing we handle
  """
  @spec account_sync(Node.t()) ::
          {:disappearing, String.t() | nil} | {:blocklist, [map()]} | :own_devices | :ignore
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

      NodeUtils.get_binary_node_child(node, "devices") ->
        :own_devices

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
  Parse a `picture` notification into a `%{id, img_url, picture_id, author}` map:

    * `id` — whose avatar changed (normalized jid)
    * `img_url` — `"changed"` (a `<set>`/`<add>` child) or `"removed"` (a `<delete>`)
    * `picture_id` — the new picture's id (use it to fetch the CDN URL), `nil` on
      removal
    * `author` — who made the change (normalized jid; set on group avatars), or `nil`
  """
  @spec picture(Node.t()) :: %{
          id: String.t(),
          img_url: String.t(),
          picture_id: String.t() | nil,
          author: String.t() | nil
        }
  def picture(node) do
    id = node |> NodeUtils.get_attr("from") |> JID.jid_normalized_user()
    child = action_child(node)
    changed? = match?(%Node{tag: tag} when tag in ~w(set add), child)

    %{
      id: id,
      img_url: if(changed?, do: "changed", else: "removed"),
      picture_id: if(changed?, do: NodeUtils.get_attr(child, "id")),
      author: author(child)
    }
  end

  # The picture notification's action child: <set>/<add> (new avatar) or <delete>.
  defp action_child(node) do
    Enum.find(node.content || [], fn
      %Node{tag: tag} -> tag in ~w(set add delete)
      _ -> false
    end)
  end

  defp author(%Node{} = child) do
    case NodeUtils.get_attr(child, "author") do
      nil -> nil
      jid -> JID.jid_normalized_user(jid)
    end
  end

  defp author(_), do: nil
end
