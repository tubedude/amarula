defmodule Amarula.Protocol.Binary.NodeTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Binary.Node

  describe "Node.new/3" do
    test "creates node with tag, attrs, and content" do
      node = Node.new("iq", %{id: "1"}, "test content")

      assert node.tag == "iq"
      assert node.attrs == %{id: "1"}
      assert node.content == "test content"
    end

    test "creates node with default attrs and content" do
      node = Node.new("message")

      assert node.tag == "message"
      assert node.attrs == %{}
      assert node.content == nil
    end

    test "creates node with attrs but no content" do
      node = Node.new("iq", %{type: "get"})

      assert node.tag == "iq"
      assert node.attrs == %{type: "get"}
      assert node.content == nil
    end

    test "creates node with nested content" do
      child = Node.new("child", %{}, "child content")
      parent = Node.new("parent", %{}, [child])

      assert parent.tag == "parent"
      assert is_list(parent.content)
      assert length(parent.content) == 1
      assert Enum.at(parent.content, 0).tag == "child"
    end
  end

  describe "Node.create/3" do
    test "creates node same as new/3" do
      node1 = Node.new("iq", %{id: "1"}, "content")
      node2 = Node.create("iq", %{id: "1"}, "content")

      assert node1 == node2
    end

    test "creates node with defaults" do
      node = Node.create("message")

      assert node.tag == "message"
      assert node.attrs == %{}
      assert node.content == nil
    end
  end

  describe "Node.has_binary_content?/1" do
    test "returns true for node with binary content" do
      node = Node.new("text", %{}, "some text")

      assert Node.has_binary_content?(node) == true
    end

    test "returns true for node with empty binary content" do
      node = Node.new("text", %{}, "")

      assert Node.has_binary_content?(node) == true
    end

    test "returns false for node with children" do
      child = Node.new("child", %{}, nil)
      parent = Node.new("parent", %{}, [child])

      assert Node.has_binary_content?(parent) == false
    end

    test "returns false for node with nil content" do
      node = Node.new("empty", %{}, nil)

      assert Node.has_binary_content?(node) == false
    end
  end
end
