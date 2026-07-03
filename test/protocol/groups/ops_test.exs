defmodule Amarula.Protocol.Groups.OpsTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.{Node, NodeUtils}
  alias Amarula.Protocol.Groups.Ops

  @group "120363000000000000@g.us"

  # IQ-level attrs are a keyword list (like the metadata query); child attrs are
  # maps. Handle both.
  defp attr(%Node{attrs: attrs}, key) when is_list(attrs) do
    case List.keyfind(attrs, key, 0) do
      {_k, v} -> v
      nil -> nil
    end
  end

  defp attr(node, key), do: NodeUtils.get_attr(node, key)
  defp child(%Node{content: [c | _]}), do: c

  describe "IQ builders" do
    test "create carries subject, a key, and participant children" do
      iq = Ops.create("My Group", ["1@s.whatsapp.net", "2@s.whatsapp.net"])
      assert attr(iq, "xmlns") == "w:g2"
      assert attr(iq, "type") == "set"
      assert attr(iq, "to") == "@g.us"

      create = child(iq)
      assert create.tag == "create"
      assert attr(create, "subject") == "My Group"
      assert is_binary(attr(create, "key"))
      assert length(create.content) == 2
      assert Enum.all?(create.content, &(&1.tag == "participant"))
    end

    test "leave wraps the group id" do
      iq = Ops.leave(@group)
      leave = child(iq)
      assert leave.tag == "leave"
      assert attr(child(leave), "id") == @group
    end

    test "update_subject puts the subject as text content" do
      iq = Ops.update_subject(@group, "New Title")
      subject = child(iq)
      assert subject.tag == "subject"
      assert subject.content == "New Title"
    end

    test "update_description with text uses a body + id; clearing uses delete" do
      set = child(Ops.update_description(@group, "hello"))
      assert set.tag == "description"
      assert is_binary(attr(set, "id"))
      assert child(set).tag == "body"
      assert child(set).content == "hello"

      cleared = child(Ops.update_description(@group, nil))
      assert attr(cleared, "delete") == "true"
    end

    test "update_description carries prev when given" do
      set = child(Ops.update_description(@group, "hi", "PREVID"))
      assert attr(set, "prev") == "PREVID"
    end

    test "participants_update tags by action with participant children" do
      for action <- [:add, :remove, :promote, :demote] do
        node = child(Ops.participants_update(@group, ["x@s.whatsapp.net"], action))
        assert node.tag == Atom.to_string(action)
        assert child(node).tag == "participant"
        assert attr(child(node), "jid") == "x@s.whatsapp.net"
      end
    end

    test "setting_update is a bare tag" do
      for s <- [:announcement, :not_announcement, :locked, :unlocked] do
        assert child(Ops.setting_update(@group, s)).tag == Atom.to_string(s)
      end
    end

    test "toggle_ephemeral: 0 = not_ephemeral, else ephemeral with expiration" do
      assert child(Ops.toggle_ephemeral(@group, 0)).tag == "not_ephemeral"
      eph = child(Ops.toggle_ephemeral(@group, 86_400))
      assert eph.tag == "ephemeral"
      assert attr(eph, "expiration") == "86400"
    end

    test "invite_code is a get, accept_invite carries the code to @g.us" do
      assert attr(Ops.invite_code(@group), "type") == "get"
      iq = Ops.accept_invite("ABC123")
      assert attr(iq, "to") == "@g.us"
      assert attr(child(iq), "code") == "ABC123"
    end

    test "join_approval_mode nests group_join with state" do
      inner = child(child(Ops.join_approval_mode(@group, :on)))
      assert inner.tag == "group_join"
      assert attr(inner, "state") == "on"
    end
  end

  describe "reply parsers" do
    defp reply(tag, participants) do
      %Node{
        tag: "iq",
        attrs: %{"type" => "result"},
        content: [
          %Node{
            tag: tag,
            attrs: %{},
            content:
              Enum.map(participants, fn {jid, err} ->
                a = %{"jid" => jid} |> then(&if err, do: Map.put(&1, "error", err), else: &1)
                %Node{tag: "participant", attrs: a, content: nil}
              end)
          }
        ]
      }
    end

    test "parse_participants returns jid + status (default 200, else error code)" do
      r = reply("add", [{"1@s.whatsapp.net", nil}, {"2@s.whatsapp.net", "403"}])
      assert {:ok, affected} = Ops.parse_participants(r, :add)

      assert affected == [
               %{jid: "1@s.whatsapp.net", status: "200"},
               %{jid: "2@s.whatsapp.net", status: "403"}
             ]
    end

    test "parse_participants surfaces an error node" do
      r = %Node{
        tag: "iq",
        attrs: %{"type" => "error"},
        content: [
          %Node{tag: "error", attrs: %{"code" => "401", "text" => "not-authorized"}, content: nil}
        ]
      }

      assert {:error, {:group_op_failed, "401", "not-authorized"}} =
               Ops.parse_participants(r, :add)
    end

    test "parse_invite_code reads the code" do
      r = %Node{
        tag: "iq",
        attrs: %{},
        content: [%Node{tag: "invite", attrs: %{"code" => "XYZ"}, content: nil}]
      }

      assert {:ok, "XYZ"} = Ops.parse_invite_code(r)
    end

    test "parse_accepted_jid reads the joined group jid" do
      r = %Node{
        tag: "iq",
        attrs: %{},
        content: [%Node{tag: "group", attrs: %{"jid" => @group}, content: nil}]
      }

      assert {:ok, @group} = Ops.parse_accepted_jid(r)
    end

    test "parse_invite_code errors when the code attr is missing" do
      r = %Node{
        tag: "iq",
        attrs: %{},
        content: [%Node{tag: "invite", attrs: %{}, content: nil}]
      }

      assert {:error, :unexpected_reply} = Ops.parse_invite_code(r)
    end

    test "parse_accepted_jid errors when the jid attr is missing" do
      r = %Node{
        tag: "iq",
        attrs: %{},
        content: [%Node{tag: "group", attrs: %{}, content: nil}]
      }

      assert {:error, :unexpected_reply} = Ops.parse_accepted_jid(r)
    end

    test "parse_request_update reads the affected participants" do
      inner = reply("approve", [{"1@s.whatsapp.net", nil}])

      r = %Node{
        tag: "iq",
        attrs: %{"type" => "result"},
        content: [%Node{tag: "membership_requests_action", attrs: %{}, content: inner.content}]
      }

      assert {:ok, [%{jid: "1@s.whatsapp.net", status: "200"}]} =
               Ops.parse_request_update(r, :approve)
    end

    test "parse_request_update surfaces an error node instead of {:ok, []}" do
      r = %Node{
        tag: "iq",
        attrs: %{"type" => "error"},
        content: [
          %Node{tag: "error", attrs: %{"code" => "403", "text" => "forbidden"}, content: nil}
        ]
      }

      assert {:error, {:group_op_failed, "403", "forbidden"}} =
               Ops.parse_request_update(r, :approve)
    end
  end
end
