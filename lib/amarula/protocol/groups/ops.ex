defmodule Amarula.Protocol.Groups.Ops do
  @moduledoc """
  Group management operations: build the `w:g2` IQs that CHANGE a group, and parse
  their replies. Port of the group op builders in Baileys `groups.ts` (the write
  side; `Groups.Metadata` is the read side).

  Every op is a `<iq xmlns="w:g2" type=get|set to=<group>>` with a single child
  naming the action. Builders return a `%Node{}`; parsers turn the reply into the
  affected participants / invite code / etc. The IQ round-trip lives in
  `Connection` (via `send_waiter_iq`).
  """

  alias Amarula.Address
  alias Amarula.Protocol.Binary.{Node, NodeUtils}

  @group_server "@g.us"

  @type action :: :add | :remove | :promote | :demote
  @type setting :: :announcement | :not_announcement | :locked | :unlocked
  @type affected :: %{jid: String.t() | nil, status: String.t()}

  # --- IQ builders ---

  @doc "Create a group with `subject` and initial `participants` (jids)."
  @spec create(String.t(), [String.t()]) :: Node.t()
  def create(subject, participants) do
    iq(@group_server, "set", [
      %Node{
        tag: "create",
        attrs: %{"subject" => subject, "key" => key()},
        content: Enum.map(participants, &participant_node/1)
      }
    ])
  end

  @doc "Leave group `id` (a bare id or full jid)."
  @spec leave(String.t()) :: Node.t()
  def leave(id) do
    iq(@group_server, "set", [
      %Node{
        tag: "leave",
        attrs: %{},
        content: [%Node{tag: "group", attrs: %{"id" => id}, content: nil}]
      }
    ])
  end

  @doc "Change the group subject (title)."
  @spec update_subject(String.t(), String.t()) :: Node.t()
  def update_subject(group_jid, subject) do
    iq(group_jid, "set", [%Node{tag: "subject", attrs: %{}, content: subject}])
  end

  @doc """
  Set or clear the group description. `nil`/`""` clears it; `prev` is the previous
  description id (from metadata) when editing.
  """
  @spec update_description(String.t(), String.t() | nil, String.t() | nil) :: Node.t()
  def update_description(group_jid, description, prev \\ nil)

  def update_description(group_jid, description, prev)
      when is_binary(description) and description != "" do
    attrs = %{"id" => key()} |> maybe_put("prev", prev)
    body = %Node{tag: "body", attrs: %{}, content: description}
    iq(group_jid, "set", [%Node{tag: "description", attrs: attrs, content: [body]}])
  end

  def update_description(group_jid, _empty, prev) do
    attrs = %{"delete" => "true"} |> maybe_put("prev", prev)
    iq(group_jid, "set", [%Node{tag: "description", attrs: attrs, content: nil}])
  end

  @doc "Add/remove/promote/demote `participants` (jids) in a group."
  @spec participants_update(String.t(), [String.t()], action()) :: Node.t()
  def participants_update(group_jid, participants, action)
      when action in [:add, :remove, :promote, :demote] do
    iq(group_jid, "set", [
      %Node{
        tag: Atom.to_string(action),
        attrs: %{},
        content: Enum.map(participants, &participant_node/1)
      }
    ])
  end

  @doc "Change a group setting: announcement (admins-only msgs) / locked (admins-only edit)."
  @spec setting_update(String.t(), setting()) :: Node.t()
  def setting_update(group_jid, setting)
      when setting in [:announcement, :not_announcement, :locked, :unlocked] do
    iq(group_jid, "set", [%Node{tag: Atom.to_string(setting), attrs: %{}, content: nil}])
  end

  @doc "Toggle disappearing messages. `0` turns it off; else seconds of expiration."
  @spec toggle_ephemeral(String.t(), non_neg_integer()) :: Node.t()
  def toggle_ephemeral(group_jid, 0) do
    iq(group_jid, "set", [%Node{tag: "not_ephemeral", attrs: %{}, content: nil}])
  end

  def toggle_ephemeral(group_jid, expiration) when is_integer(expiration) do
    child = %Node{
      tag: "ephemeral",
      attrs: %{"expiration" => Integer.to_string(expiration)},
      content: nil
    }

    iq(group_jid, "set", [child])
  end

  @doc "Who may add members: `:admin_add` or `:all_member_add`."
  @spec member_add_mode(String.t(), :admin_add | :all_member_add) :: Node.t()
  def member_add_mode(group_jid, mode) when mode in [:admin_add, :all_member_add] do
    iq(group_jid, "set", [
      %Node{tag: "member_add_mode", attrs: %{}, content: Atom.to_string(mode)}
    ])
  end

  @doc "Turn join-approval (admin must approve joiners) on/off."
  @spec join_approval_mode(String.t(), :on | :off) :: Node.t()
  def join_approval_mode(group_jid, mode) when mode in [:on, :off] do
    child = %Node{tag: "group_join", attrs: %{"state" => Atom.to_string(mode)}, content: nil}
    iq(group_jid, "set", [%Node{tag: "membership_approval_mode", attrs: %{}, content: [child]}])
  end

  @doc "Fetch the group's invite code (`get`)."
  @spec invite_code(String.t()) :: Node.t()
  def invite_code(group_jid),
    do: iq(group_jid, "get", [%Node{tag: "invite", attrs: %{}, content: nil}])

  @doc "Revoke + regenerate the group's invite code (`set`)."
  @spec revoke_invite(String.t()) :: Node.t()
  def revoke_invite(group_jid),
    do: iq(group_jid, "set", [%Node{tag: "invite", attrs: %{}, content: nil}])

  @doc "Accept an invite by `code` — joins the group."
  @spec accept_invite(String.t()) :: Node.t()
  def accept_invite(code) do
    iq(@group_server, "set", [%Node{tag: "invite", attrs: %{"code" => code}, content: nil}])
  end

  @doc "Look up a group's metadata from an invite `code` without joining (`get`)."
  @spec invite_info(String.t()) :: Node.t()
  def invite_info(code) do
    iq(@group_server, "get", [%Node{tag: "invite", attrs: %{"code" => code}, content: nil}])
  end

  @doc "List pending join-approval requests (`get`)."
  @spec request_list(String.t()) :: Node.t()
  def request_list(group_jid) do
    iq(group_jid, "get", [%Node{tag: "membership_approval_requests", attrs: %{}, content: nil}])
  end

  @doc "Approve/reject pending join requests for `participants` (jids)."
  @spec request_update(String.t(), [String.t()], :approve | :reject) :: Node.t()
  def request_update(group_jid, participants, action) when action in [:approve, :reject] do
    inner = %Node{
      tag: Atom.to_string(action),
      attrs: %{},
      content: Enum.map(participants, &participant_node/1)
    }

    iq(group_jid, "set", [%Node{tag: "membership_requests_action", attrs: %{}, content: [inner]}])
  end

  # --- reply parsers ---

  @doc "Parse the affected-participants list from an add/remove/promote/demote reply."
  @spec parse_participants(Node.t(), action()) :: {:ok, [affected()]} | {:error, term()}
  def parse_participants(reply, action) do
    case NodeUtils.get_binary_node_child(reply, Atom.to_string(action)) do
      %Node{} = node -> {:ok, affected(node)}
      _ -> {:error, parse_error(reply)}
    end
  end

  @doc "Parse the invite code from an invite/revoke reply."
  @spec parse_invite_code(Node.t()) :: {:ok, String.t()} | {:error, term()}
  def parse_invite_code(reply) do
    case NodeUtils.get_binary_node_child(reply, "invite") do
      %Node{} = invite -> {:ok, NodeUtils.get_attr(invite, "code")}
      _ -> {:error, parse_error(reply)}
    end
  end

  @doc "Parse the joined group's jid from an accept-invite reply."
  @spec parse_accepted_jid(Node.t()) :: {:ok, String.t()} | {:error, term()}
  def parse_accepted_jid(reply) do
    case NodeUtils.get_binary_node_child(reply, "group") do
      %Node{} = group -> {:ok, NodeUtils.get_attr(group, "jid")}
      _ -> {:error, parse_error(reply)}
    end
  end

  @doc """
  Parse pending join requests into a list of clean maps:
  `%{jid: Address, requested_at: integer | nil}` (the requester and when they asked).
  """
  @spec parse_request_list(Node.t()) :: {:ok, [%{jid: Address.t(), requested_at: integer | nil}]}
  def parse_request_list(reply) do
    requests =
      case NodeUtils.get_binary_node_child(reply, "membership_approval_requests") do
        %Node{} = node -> NodeUtils.get_binary_node_children(node, "membership_approval_request")
        _ -> []
      end

    {:ok, Enum.map(requests, &request_from_attrs/1)}
  end

  defp request_from_attrs(%Node{attrs: attrs}) do
    %{
      jid: attrs |> Map.get("jid", "") |> Address.parse(),
      requested_at: parse_int(Map.get(attrs, "t"))
    }
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  @doc "Parse the affected participants from an approve/reject reply."
  @spec parse_request_update(Node.t(), :approve | :reject) :: {:ok, [affected()]}
  def parse_request_update(reply, action) do
    with %Node{} = outer <- NodeUtils.get_binary_node_child(reply, "membership_requests_action"),
         %Node{} = inner <- NodeUtils.get_binary_node_child(outer, Atom.to_string(action)) do
      {:ok, affected(inner)}
    else
      _ -> {:ok, []}
    end
  end

  # --- internals ---

  defp iq(to, type, content) do
    %Node{tag: "iq", attrs: [{"type", type}, {"xmlns", "w:g2"}, {"to", to}], content: content}
  end

  defp participant_node(jid), do: %Node{tag: "participant", attrs: %{"jid" => jid}, content: nil}

  defp affected(node) do
    node
    |> NodeUtils.get_binary_node_children("participant")
    |> Enum.map(fn p ->
      %{jid: NodeUtils.get_attr(p, "jid"), status: NodeUtils.get_attr(p, "error") || "200"}
    end)
  end

  defp parse_error(reply) do
    case NodeUtils.get_binary_node_child(reply, "error") do
      %Node{} = error ->
        {:group_op_failed, NodeUtils.get_attr(error, "code"), NodeUtils.get_attr(error, "text")}

      _ ->
        :unexpected_reply
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # A fresh key for create/description (Baileys generateMessageIDV2).
  defp key, do: "3EB0" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :upper))
end
