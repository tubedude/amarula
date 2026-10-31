defmodule Amarula.Protocol.Groups.Notification do
  @moduledoc """
  Parse a `w:gp2` group notification into structured updates, ported from the
  group branch of Baileys `handleGroupNotification` (`Socket/messages-recv.ts`).

  A `w:gp2` notification's child nodes name the changes; we turn each into an
  `{action, payload}` the connection emits as a `:group_update` event. Only the
  common, high-value changes are decoded; unrecognised children yield
  `{:other, tag}` so nothing is silently lost.
  """

  alias Amarula.Address
  alias Amarula.Protocol.Binary.{JID, Node, NodeUtils}

  @type participant :: %{address: Address.t(), admin: String.t() | nil}

  @type action ::
          {:participants, :add | :remove | :promote | :demote | :leave, [participant()]}
          | {:subject, String.t()}
          | {:description, String.t() | nil}
          | {:announce, boolean()}
          | {:restrict, boolean()}
          | {:invite_code, String.t()}
          | {:other, String.t()}

  @type t :: %{
          group: Address.t(),
          author: Address.t() | nil,
          action: action()
        }

  @doc """
  Parse the first change child of a `w:gp2` notification node. Returns
  `{:ok, %{group, author, action}}` or `{:error, reason}` when there's no change
  child to interpret. See `parse_all/1` when a single notification may carry
  several change children (e.g. `<add>` and `<promote>` together).
  """
  @spec parse(Node.t()) :: {:ok, t()} | {:error, term()}
  def parse(%Node{} = node) do
    case parse_all(node) do
      {:ok, [first | _]} -> {:ok, first}
      {:error, _} = err -> err
    end
  end

  @doc """
  Parse all change children of a `w:gp2` notification node in order. Returns
  `{:ok, [t()]}` or `{:error, :no_change_child}` when the notification carries no
  child elements.
  """
  @spec parse_all(Node.t()) :: {:ok, [t()]} | {:error, term()}
  def parse_all(%Node{} = node) do
    case change_children(node) do
      [] ->
        {:error, :no_change_child}

      children ->
        group = address(NodeUtils.get_attr(node, "from"))
        author = address(NodeUtils.get_attr(node, "participant"))

        {:ok,
         Enum.map(children, fn child ->
           %{
             group: group,
             author: author,
             action: action(child)
           }
         end)}
    end
  end

  @doc """
  Extract `{lid, pn}` JID pairs from a `w:gp2` notification's author attributes
  and all `<participant>` children across every change child (whatsmeow #1278).
  """
  @spec lid_mappings(Node.t()) :: [{String.t(), String.t()}]
  def lid_mappings(%Node{} = node) do
    author_pairs = node_lid_pair(node, "participant", "participant_lid", "participant_pn")

    child_pairs =
      for child <- change_children(node),
          p <- NodeUtils.get_binary_node_children(child, "participant"),
          pair <- node_lid_pair(p, "jid", "lid", "phone_number"),
          do: pair

    Enum.uniq(author_pairs ++ child_pairs)
  end

  # --- change decoding ---

  # Map the tag to a fixed atom explicitly — never String.to_atom/1 on wire input,
  # even behind a guard (a later guard change must not become an atom-exhaustion
  # vector). An unlisted tag falls through to the {:other, tag} clause below.
  defp action(%Node{tag: "add"} = child), do: {:participants, :add, participants(child)}
  defp action(%Node{tag: "remove"} = child), do: {:participants, :remove, participants(child)}
  defp action(%Node{tag: "promote"} = child), do: {:participants, :promote, participants(child)}
  defp action(%Node{tag: "demote"} = child), do: {:participants, :demote, participants(child)}
  defp action(%Node{tag: "leave"} = child), do: {:participants, :leave, participants(child)}

  defp action(%Node{tag: "subject"} = child),
    do: {:subject, NodeUtils.get_attr(child, "subject")}

  defp action(%Node{tag: "description"} = child),
    do: {:description, body_text(child)}

  defp action(%Node{tag: tag}) when tag in ~w(announcement not_announcement),
    do: {:announce, tag == "announcement"}

  defp action(%Node{tag: tag}) when tag in ~w(locked unlocked),
    do: {:restrict, tag == "locked"}

  defp action(%Node{tag: "invite"} = child),
    do: {:invite_code, NodeUtils.get_attr(child, "code")}

  defp action(%Node{tag: tag}), do: {:other, tag}

  defp participants(child) do
    child
    |> NodeUtils.get_binary_node_children("participant")
    |> Enum.map(fn p ->
      %{address: address(NodeUtils.get_attr(p, "jid")), admin: NodeUtils.get_attr(p, "type")}
    end)
  end

  defp body_text(child) do
    case NodeUtils.get_binary_node_child(child, "body") do
      %Node{content: c} when is_binary(c) -> c
      _ -> nil
    end
  end

  defp change_children(%Node{content: content}) when is_list(content) do
    Enum.filter(content, &match?(%Node{}, &1))
  end

  defp change_children(_), do: []

  defp node_lid_pair(node, jid_attr, lid_attr, pn_attr) do
    jid = NodeUtils.get_attr(node, jid_attr)
    lid = NodeUtils.get_attr(node, lid_attr)
    pn = NodeUtils.get_attr(node, pn_attr)

    cond do
      JID.pn_user?(jid) and JID.lid_user?(lid) -> [{lid, jid}]
      JID.lid_user?(jid) and JID.pn_user?(pn) -> [{jid, pn}]
      true -> []
    end
  end

  defp address(nil), do: nil
  defp address(jid), do: Address.parse(jid)
end
