defmodule Amarula.Protocol.Binary.NodeTest do
  use ExUnit.Case, async: true
  alias Amarula.Protocol.Binary.Node

  describe "Node struct" do
    test "creates node with basic fields" do
      node = %Node{tag: "iq", attrs: %{id: "1"}, content: nil}
      assert node.tag == "iq"
      assert node.attrs.id == "1"
      assert node.content == nil
    end

    test "creates node with empty attrs" do
      node = %Node{tag: "message", attrs: %{}, content: "Hello"}
      assert node.tag == "message"
      assert node.attrs == %{}
      assert node.content == "Hello"
    end

    test "creates node with nested content" do
      child = %Node{tag: "child", attrs: %{}, content: nil}
      parent = %Node{tag: "parent", attrs: %{}, content: [child]}

      assert parent.tag == "parent"
      assert length(parent.content) == 1
      assert Enum.at(parent.content, 0).tag == "child"
    end

    test "creates node with binary content" do
      binary_data = <<1, 2, 3, 4>>
      node = %Node{tag: "binary", attrs: %{}, content: binary_data}

      assert node.content == binary_data
      assert is_binary(node.content)
    end

    test "creates node with string content" do
      node = %Node{tag: "text", attrs: %{}, content: "Hello World"}

      assert node.content == "Hello World"
      assert is_binary(node.content)
    end

    test "creates node with complex attrs" do
      attrs = %{
        id: "123",
        type: "get",
        to: "user@s.whatsapp.net"
      }

      node = %Node{tag: "iq", attrs: attrs, content: nil}

      assert node.attrs.id == "123"
      assert node.attrs.type == "get"
      assert node.attrs.to == "user@s.whatsapp.net"
    end

    test "creates deeply nested nodes" do
      grandchild = %Node{tag: "grandchild", attrs: %{}, content: nil}
      child = %Node{tag: "child", attrs: %{}, content: [grandchild]}
      parent = %Node{tag: "parent", attrs: %{}, content: [child]}

      assert parent.tag == "parent"
      assert length(parent.content) == 1

      first_child = Enum.at(parent.content, 0)
      assert first_child.tag == "child"
      assert length(first_child.content) == 1

      first_grandchild = Enum.at(first_child.content, 0)
      assert first_grandchild.tag == "grandchild"
    end
  end

  describe "Node validation" do
    test "allows nil content" do
      node = %Node{tag: "empty", attrs: %{}, content: nil}
      assert node.content == nil
    end

    test "allows empty attrs" do
      node = %Node{tag: "simple", attrs: %{}, content: "test"}
      assert node.attrs == %{}
    end

    test "allows empty tag" do
      node = %Node{tag: "", attrs: %{}, content: nil}
      assert node.tag == ""
    end
  end

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
