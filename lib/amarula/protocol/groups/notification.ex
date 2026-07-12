defmodule Amarula.Protocol.Groups.Notification do
  @moduledoc """
  Parse a `w:gp2` group notification into a structured update, ported from the
  group branch of Baileys `handleGroupNotification` (`Socket/messages-recv.ts`).

  A `w:gp2` notification's first child names the change; we turn it into a
  `{action, payload}` the connection emits as a `:group_update` event. Only the
  common, high-value changes are decoded; unrecognised children yield
  `{:other, tag}` so nothing is silently lost.
  """

  alias Amarula.Address
  alias Amarula.Protocol.Binary.{Node, NodeUtils}

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
  Parse a `w:gp2` notification node. Returns `{:ok, %{group, author, action}}` or
  `{:error, reason}` when there's no change child to interpret.
  """
  @spec parse(Node.t()) :: {:ok, t()} | {:error, term()}
  def parse(%Node{} = node) do
    with %Node{} = child <- first_child(node) do
      {:ok,
       %{
         group: address(NodeUtils.get_attr(node, "from")),
         author: address(NodeUtils.get_attr(node, "participant")),
         action: action(child)
       }}
    else
      _ -> {:error, :no_change_child}
    end
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

  defp first_child(%Node{content: [%Node{} = c | _]}), do: c
  defp first_child(_), do: nil

  defp address(nil), do: nil
  defp address(jid), do: Address.parse(jid)
end
