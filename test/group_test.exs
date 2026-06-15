defmodule Amarula.GroupTest do
  use ExUnit.Case, async: true

  alias Amarula.{Address, Group}
  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Groups.Metadata

  defp group_node(id, opts \\ []) do
    parts =
      Keyword.get(opts, :participants, [])
      |> Enum.map(fn {jid, type} ->
        attrs = %{"jid" => jid} |> then(&if type, do: Map.put(&1, "type", type), else: &1)
        %Node{tag: "participant", attrs: attrs, content: nil}
      end)

    attrs =
      %{
        "id" => id,
        "subject" => Keyword.get(opts, :subject),
        "creator" => Keyword.get(opts, :owner)
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    %Node{tag: "group", attrs: attrs, content: parts}
  end

  describe "from_metadata via single group parse" do
    test "builds a %Group{} with Address participants + admin kinds" do
      node =
        group_node("120363@g.us",
          subject: "Team",
          owner: "10000000001@s.whatsapp.net",
          participants: [
            {"10000000001@s.whatsapp.net", "superadmin"},
            {"10000000002@s.whatsapp.net", "admin"},
            {"20000000003@lid", nil}
          ]
        )

      {:ok, meta} = Metadata.parse(%Node{tag: "result", attrs: %{}, content: [node]})
      group = Group.from_metadata(meta)

      assert %Group{subject: "Team", size: 3} = group
      assert %Address{user: "120363", kind: :group} = group.address
      assert %Address{kind: :pn} = group.owner

      assert [
               %{address: %Address{kind: :pn}, admin: :superadmin},
               %{address: %Address{kind: :pn}, admin: :admin},
               %{address: %Address{kind: :lid}, admin: nil}
             ] = group.participants
    end
  end

  describe "parse_all → list of groups" do
    test "parses <groups><group>… into metadata list" do
      groups =
        %Node{
          tag: "groups",
          attrs: %{},
          content: [
            group_node("111@g.us", subject: "A", participants: [{"1@s.whatsapp.net", nil}]),
            group_node("222@g.us", subject: "B", participants: [{"2@s.whatsapp.net", "admin"}])
          ]
        }

      result = %Node{tag: "iq", attrs: %{}, content: [groups]}
      {:ok, metas} = Metadata.parse_all(result)
      assert length(metas) == 2

      [a, b] = Enum.map(metas, &Group.from_metadata/1)
      assert a.subject == "A"
      assert b.subject == "B"
      assert %Address{kind: :group, user: "111"} = a.address
    end

    test "empty when no <groups>" do
      assert {:ok, []} = Metadata.parse_all(%Node{tag: "iq", attrs: %{}, content: []})
    end
  end

  test "query_all_iq targets @g.us / w:g2" do
    iq = Metadata.query_all_iq()
    attrs = Map.new(iq.attrs)
    assert attrs["to"] == "@g.us"
    assert attrs["xmlns"] == "w:g2"
    assert %Node{tag: "participating"} = NodeUtils.get_binary_node_child(iq, "participating")
  end
end
