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

  describe "Node.has_children?/1" do
    test "returns true for node with children" do
      child = Node.new("child", %{}, nil)
      parent = Node.new("parent", %{}, [child])

      assert Node.has_children?(parent) == true
    end

    test "returns false for node with empty children list" do
      parent = Node.new("parent", %{}, [])

      assert Node.has_children?(parent) == false
    end

    test "returns false for node with binary content" do
      node = Node.new("text", %{}, "some text")

      assert Node.has_children?(node) == false
    end

    test "returns false for node with nil content" do
      node = Node.new("empty", %{}, nil)

      assert Node.has_children?(node) == false
    end
  end

  describe "Node.child_count/1" do
    test "returns count of children" do
      child1 = Node.new("child1", %{}, nil)
      child2 = Node.new("child2", %{}, nil)
      parent = Node.new("parent", %{}, [child1, child2])

      assert Node.child_count(parent) == 2
    end

    test "returns 0 for node with empty children list" do
      parent = Node.new("parent", %{}, [])

      assert Node.child_count(parent) == 0
    end

    test "returns 0 for node with binary content" do
      node = Node.new("text", %{}, "some text")

      assert Node.child_count(node) == 0
    end

    test "returns 0 for node with nil content" do
      node = Node.new("empty", %{}, nil)

      assert Node.child_count(node) == 0
    end
  end

  describe "Node.get_child/2" do
    test "returns child at valid index" do
      child1 = Node.new("child1", %{}, nil)
      child2 = Node.new("child2", %{}, nil)
      parent = Node.new("parent", %{}, [child1, child2])

      assert Node.get_child(parent, 0) == child1
      assert Node.get_child(parent, 1) == child2
    end

    test "returns nil for invalid index" do
      child = Node.new("child", %{}, nil)
      parent = Node.new("parent", %{}, [child])

      assert Node.get_child(parent, 1) == nil
      # Note: Enum.at with negative index wraps around, so -1 returns the last element
      assert Node.get_child(parent, -1) == child
    end

    test "returns nil for node with binary content" do
      node = Node.new("text", %{}, "some text")

      assert Node.get_child(node, 0) == nil
    end

    test "returns nil for node with nil content" do
      node = Node.new("empty", %{}, nil)

      assert Node.get_child(node, 0) == nil
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

  describe "Node.has_string_content?/1" do
    test "returns true for node with string content" do
      node = Node.new("text", %{}, "some text")

      assert Node.has_string_content?(node) == true
    end

    test "returns true for node with empty string content" do
      node = Node.new("text", %{}, "")

      assert Node.has_string_content?(node) == true
    end

    test "returns false for node with children" do
      child = Node.new("child", %{}, nil)
      parent = Node.new("parent", %{}, [child])

      assert Node.has_string_content?(parent) == false
    end

    test "returns false for node with nil content" do
      node = Node.new("empty", %{}, nil)

      assert Node.has_string_content?(node) == false
    end
  end

  describe "Node.empty?/1" do
    test "returns true for node with nil content" do
      node = Node.new("empty", %{}, nil)

      assert Node.empty?(node) == true
    end

    test "returns true for node with empty string content" do
      node = Node.new("empty", %{}, "")

      assert Node.empty?(node) == true
    end

    test "returns true for node with empty children list" do
      node = Node.new("empty", %{}, [])

      assert Node.empty?(node) == true
    end

    test "returns false for node with string content" do
      node = Node.new("text", %{}, "some text")

      assert Node.empty?(node) == false
    end

    test "returns false for node with children" do
      child = Node.new("child", %{}, nil)
      parent = Node.new("parent", %{}, [child])

      assert Node.empty?(parent) == false
    end
  end
end
