defmodule Amarula.Protocol.Binary.NodeUtilsTest do
  use ExUnit.Case, async: true

  alias Amarula.Protocol.Binary.{Node, NodeUtils}

  describe "get_binary_node_child/2" do
    test "finds the first child with the tag, else nil" do
      node = %Node{tag: "iq", content: [%Node{tag: "pair-device"}, %Node{tag: "ref"}]}
      assert NodeUtils.get_binary_node_child(node, "pair-device") == %Node{tag: "pair-device"}
      assert NodeUtils.get_binary_node_child(node, "nonexistent") == nil
    end
  end

  describe "get_binary_node_children/2" do
    test "returns all matching children, else []" do
      node = %Node{tag: "iq", content: [%Node{tag: "ref"}, %Node{tag: "ref"}]}

      assert NodeUtils.get_binary_node_children(node, "ref") == [
               %Node{tag: "ref"},
               %Node{tag: "ref"}
             ]

      assert NodeUtils.get_binary_node_children(node, "nonexistent") == []
    end
  end

  describe "fallback clauses (non-list / binary content)" do
    test "child accessors return empty defaults on binary content" do
      node = %Node{tag: "msg", content: <<1, 2, 3>>}

      assert NodeUtils.get_binary_node_child(node, "x") == nil
      assert NodeUtils.get_binary_node_children(node, "x") == []
      assert NodeUtils.get_all_binary_node_children(node) == []
      assert NodeUtils.get_first_child_tag(node) == ""
    end

    test "get_all_binary_node_children drops non-Node entries" do
      node = %Node{tag: "iq", content: [%Node{tag: "a"}, "loose", %Node{tag: "b"}]}
      assert NodeUtils.get_all_binary_node_children(node) == [%Node{tag: "a"}, %Node{tag: "b"}]
    end
  end

  describe "binary_node_to_string/1" do
    test "renders a binary (text) content node" do
      node = %Node{tag: "ref", content: "abc123"}
      assert NodeUtils.binary_node_to_string(node) == "<ref>abc123</ref>"
    end

    test "renders nested children" do
      node = %Node{
        tag: "iq",
        attrs: %{"type" => "set"},
        content: [%Node{tag: "ping"}]
      }

      assert NodeUtils.binary_node_to_string(node) == "<iq type=\"set\"><ping/></iq>"
    end

    test "self-closes an empty node with no attrs" do
      assert NodeUtils.binary_node_to_string(%Node{tag: "ping"}) == "<ping/>"
    end
  end

  describe "get_child_content/2" do
    test "returns nil when the child tag is absent" do
      node = %Node{tag: "iq", content: [%Node{tag: "ref", content: "v"}]}
      assert NodeUtils.get_child_content(node, "missing") == nil
    end
  end

  describe "get_attr/2 and has_attr_value?/3" do
    test "missing attr is nil / false" do
      node = %Node{tag: "iq", attrs: %{"id" => "1"}}
      assert NodeUtils.get_attr(node, "type") == nil
      refute NodeUtils.has_attr_value?(node, "type", "set")
    end
  end
end
