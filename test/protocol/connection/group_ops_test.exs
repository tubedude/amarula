defmodule Amarula.Connection.GroupOpsTest do
  @moduledoc "Pure unit tests for the group-query builders — no socket, no state."
  use ExUnit.Case, async: true

  alias Amarula.Connection.GroupOps
  alias Amarula.Protocol.Binary.Node

  # A minimal <group> reply node, mirroring the server's metadata IQ result.
  defp group_node(id, subject) do
    %Node{
      tag: "group",
      attrs: %{"id" => id, "subject" => subject},
      content: [%Node{tag: "participant", attrs: %{"jid" => "1@s.whatsapp.net"}, content: nil}]
    }
  end

  describe "metadata/1" do
    test "builds a metadata query IQ for the group" do
      {iq, transform} = GroupOps.metadata("123-456@g.us")

      assert %Node{tag: "iq"} = iq
      assert is_function(transform, 1)
    end

    test "transform parses an ok reply into an %Amarula.Group{}" do
      {_iq, transform} = GroupOps.metadata("120363@g.us")
      reply = %Node{tag: "result", attrs: %{}, content: [group_node("120363@g.us", "Team")]}

      assert {:ok, %Amarula.Group{subject: "Team"}} = transform.({:ok, reply})
    end

    test "transform passes a server error node straight through" do
      {_iq, transform} = GroupOps.metadata("123-456@g.us")
      err = %Node{tag: "error"}

      assert transform.({:error, err}) == {:error, err}
    end
  end

  describe "list/0" do
    test "builds the query-all IQ and a 1-arity transform" do
      {iq, transform} = GroupOps.list()

      assert %Node{tag: "iq"} = iq
      assert is_function(transform, 1)
    end

    test "transform parses an ok reply into a list of %Amarula.Group{}" do
      {_iq, transform} = GroupOps.list()

      groups = %Node{
        tag: "groups",
        attrs: %{},
        content: [group_node("111@g.us", "A"), group_node("222@g.us", "B")]
      }

      reply = %Node{tag: "iq", attrs: %{}, content: [groups]}

      assert {:ok, [%Amarula.Group{subject: "A"}, %Amarula.Group{subject: "B"}]} =
               transform.({:ok, reply})
    end

    test "transform passes a server error node straight through" do
      {_iq, transform} = GroupOps.list()
      err = %Node{tag: "error"}

      assert transform.({:error, err}) == {:error, err}
    end
  end
end
