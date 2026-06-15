defmodule Amarula.Protocol.Groups.Metadata do
  @moduledoc """
  Group metadata: build the `w:g2` query IQ and parse its result into the bits a
  group send needs. Port of Baileys `groupQuery`/`extractGroupMetadata`
  (`src/Socket/groups.ts`), trimmed to the send-relevant fields (participants +
  addressing mode); description/community/etc. are skipped until a consumer needs
  them.

  Usage (the IQ goes through `Connection.query_iq/2`):

      iq = Metadata.query_iq(group_jid)
      {:ok, reply} = Connection.query_iq(conn, iq)
      {:ok, meta} = Metadata.parse(reply)
  """

  alias Amarula.Protocol.Binary.{JID, Node, NodeUtils}

  @type participant :: %{
          id: String.t(),
          lid: String.t() | nil,
          phone_number: String.t() | nil,
          admin: String.t() | nil
        }

  @type t :: %{
          id: String.t(),
          subject: String.t() | nil,
          owner: String.t() | nil,
          addressing_mode: :pn | :lid,
          size: non_neg_integer(),
          participants: [participant()]
        }

  @doc """
  Build the interactive group-metadata query IQ:

      <iq type=get xmlns=w:g2 to=<group>><query request=interactive/></iq>
  """
  @spec query_iq(String.t()) :: Node.t()
  def query_iq(group_jid) do
    %Node{
      tag: "iq",
      attrs: [{"type", "get"}, {"xmlns", "w:g2"}, {"to", group_jid}],
      content: [%Node{tag: "query", attrs: %{"request" => "interactive"}, content: nil}]
    }
  end

  @doc """
  Parse a group-metadata IQ result. Returns `{:ok, metadata}` or
  `{:error, reason}` (missing `<group>`, surfaced `<error>`, or missing id).
  """
  @spec parse(Node.t()) :: {:ok, t()} | {:error, term()}
  def parse(%Node{} = result) do
    case NodeUtils.get_binary_node_child(result, "group") do
      nil -> {:error, parse_error(result)}
      group -> from_group_node(group)
    end
  end

  @doc """
  Build the "all participating groups" query IQ (Baileys
  `groupFetchAllParticipating`):

      <iq to="@g.us" xmlns="w:g2" type="get">
        <participating><participants/><description/></participating></iq>
  """
  @spec query_all_iq() :: Node.t()
  def query_all_iq do
    %Node{
      tag: "iq",
      attrs: [{"type", "get"}, {"xmlns", "w:g2"}, {"to", "@g.us"}],
      content: [
        %Node{
          tag: "participating",
          attrs: %{},
          content: [
            %Node{tag: "participants", attrs: %{}, content: nil},
            %Node{tag: "description", attrs: %{}, content: nil}
          ]
        }
      ]
    }
  end

  @doc """
  Parse an "all participating" IQ result (`<groups><group>…</groups>`) into a
  list of metadata maps. Unparseable group nodes are skipped.
  """
  @spec parse_all(Node.t()) :: {:ok, [t()]}
  def parse_all(%Node{} = result) do
    groups =
      case NodeUtils.get_binary_node_child(result, "groups") do
        nil -> []
        groups_node -> NodeUtils.get_binary_node_children(groups_node, "group")
      end

    metas =
      Enum.flat_map(groups, fn group ->
        case from_group_node(group) do
          {:ok, meta} -> [meta]
          {:error, _} -> []
        end
      end)

    {:ok, metas}
  end

  # --- internals ---

  defp from_group_node(group) do
    case NodeUtils.get_attr(group, "id") do
      nil ->
        {:error, :missing_group_id}

      id ->
        participants = NodeUtils.get_binary_node_children(group, "participant")

        {:ok,
         %{
           id: normalize_group_id(id),
           subject: NodeUtils.get_attr(group, "subject"),
           owner: NodeUtils.get_attr(group, "creator") || NodeUtils.get_attr(group, "owner"),
           addressing_mode: addressing_mode(group),
           size: size(group, participants),
           participants: Enum.map(participants, &participant/1)
         }}
    end
  end

  # A participant's id may be a LID or a PN; carry the cross-mapped counterpart
  # when present (Baileys keeps lid for pn ids and phone_number for lid ids).
  defp participant(node) do
    jid = NodeUtils.get_attr(node, "jid")
    lid = NodeUtils.get_attr(node, "lid")
    phone = NodeUtils.get_attr(node, "phone_number")

    %{
      id: jid,
      lid: if(pn_user?(jid) and lid_user?(lid), do: lid),
      phone_number: if(lid_user?(jid) and pn_user?(phone), do: phone),
      admin: NodeUtils.get_attr(node, "type")
    }
  end

  defp addressing_mode(group) do
    if NodeUtils.get_attr(group, "addressing_mode") == "lid", do: :lid, else: :pn
  end

  defp size(group, participants) do
    case NodeUtils.get_attr(group, "size") do
      nil -> length(participants)
      s -> String.to_integer(s)
    end
  end

  # jidEncode(id, 'g.us') unless already a full jid.
  defp normalize_group_id(id) do
    if String.contains?(id, "@"), do: id, else: JID.encode(%{user: id, server: "g.us"})
  end

  defp parse_error(result) do
    case NodeUtils.get_binary_node_child(result, "error") do
      nil ->
        :missing_group_node

      error ->
        {:group_query_failed, NodeUtils.get_attr(error, "code"),
         NodeUtils.get_attr(error, "text")}
    end
  end

  defp pn_user?(jid), do: is_binary(jid) and JID.is_jid_user?(jid) and not JID.is_lid_user?(jid)
  defp lid_user?(jid), do: is_binary(jid) and JID.is_lid_user?(jid)
end
