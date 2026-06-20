defmodule Amarula.Connection.GroupOpsTest do
  @moduledoc "Pure unit tests for the group-query builders — no socket, no state."
  use ExUnit.Case, async: true

  alias Amarula.Connection.GroupOps
  alias Amarula.Protocol.Binary.Node

  describe "metadata/1" do
    test "builds a metadata query IQ for the group" do
      {iq, transform} = GroupOps.metadata("123-456@g.us")

      assert %Node{tag: "iq"} = iq
      assert is_function(transform, 1)
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

    test "transform passes a server error node straight through" do
      {_iq, transform} = GroupOps.list()
      err = %Node{tag: "error"}

      assert transform.({:error, err}) == {:error, err}
    end
  end
end
