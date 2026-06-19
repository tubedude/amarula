defmodule Amarula.Protocol.Binary.NodeUtils do
  @moduledoc """
  Utility functions for working with binary nodes.

  Provides helper functions for inspecting, traversing, and manipulating
  binary node structures used in the WhatsApp protocol.
  """

  alias Amarula.Protocol.Binary.Node

  @doc """
  Get the first child node with the specified tag.

  Returns the first child node matching the tag, or nil if not found.

  ## Examples

      iex> node = %Node{tag: "iq", content: [%Node{tag: "pair-device"}, %Node{tag: "ref"}]}
      iex> NodeUtils.get_binary_node_child(node, "pair-device")
      %Node{tag: "pair-device"}

      iex> NodeUtils.get_binary_node_child(node, "nonexistent")
      nil
  """
  @spec get_binary_node_child(Node.t(), String.t()) :: Node.t() | nil
  def get_binary_node_child(%Node{content: content}, tag) when is_list(content) do
    Enum.find(content, fn
      %Node{tag: ^tag} -> true
      _ -> false
    end)
  end

  def get_binary_node_child(_node, _tag), do: nil

  @doc """
  Get all child nodes with the specified tag.

  Returns a list of all child nodes matching the tag.

  ## Examples

      iex> node = %Node{tag: "iq", content: [%Node{tag: "ref"}, %Node{tag: "ref"}]}
      iex> NodeUtils.get_binary_node_children(node, "ref")
      [%Node{tag: "ref"}, %Node{tag: "ref"}]

      iex> NodeUtils.get_binary_node_children(node, "nonexistent")
      []
  """
  @spec get_binary_node_children(Node.t(), String.t()) :: [Node.t()]
  def get_binary_node_children(%Node{content: content}, tag) when is_list(content) do
    Enum.filter(content, fn
      %Node{tag: ^tag} -> true
      _ -> false
    end)
  end

  def get_binary_node_children(_node, _tag), do: []

  @doc """
  Get all child nodes from a node.

  Returns a list of all child nodes, or empty list if no children.

  ## Examples

      iex> node = %Node{tag: "iq", content: [%Node{tag: "ref"}, %Node{tag: "pair-device"}]}
      iex> NodeUtils.get_all_binary_node_children(node)
      [%Node{tag: "ref"}, %Node{tag: "pair-device"}]

      iex> NodeUtils.get_all_binary_node_children(%Node{tag: "empty"})
      []
  """
  @spec get_all_binary_node_children(Node.t()) :: [Node.t()]
  def get_all_binary_node_children(%Node{content: content}) when is_list(content) do
    Enum.filter(content, fn
      %Node{} -> true
      _ -> false
    end)
  end

  def get_all_binary_node_children(_node), do: []

  @doc """
  Convert a binary node to a readable string representation.

  Useful for debugging and logging node structures.

  ## Examples

      iex> node = %Node{tag: "iq", attrs: %{"type" => "set", "id" => "123"}, content: [%Node{tag: "ping"}]}
      iex> NodeUtils.binary_node_to_string(node)
      "<iq type=\"set\" id=\"123\"><ping/></iq>"
  """
  @spec binary_node_to_string(Node.t()) :: String.t()
  def binary_node_to_string(%Node{tag: tag, attrs: attrs, content: content}) do
    attrs_str =
      (attrs || %{})
      |> Enum.map_join(" ", fn {k, v} -> "#{k}=\"#{v}\"" end)

    attrs_str = if attrs_str == "", do: "", else: " #{attrs_str}"

    content_str =
      case content do
        nil ->
          ""

        content when is_list(content) ->
          Enum.map_join(content, "", &binary_node_to_string/1)

        content when is_binary(content) ->
          content
      end

    if content_str == "" do
      "<#{tag}#{attrs_str}/>"
    else
      "<#{tag}#{attrs_str}>#{content_str}</#{tag}>"
    end
  end

  @doc """
  Get the first child node's tag.

  Returns the tag of the first child node, or empty string if no children.

  ## Examples

      iex> node = %Node{tag: "iq", content: [%Node{tag: "pair-device"}, %Node{tag: "ref"}]}
      iex> NodeUtils.get_first_child_tag(node)
      "pair-device"

      iex> NodeUtils.get_first_child_tag(%Node{tag: "empty"})
      ""
  """
  @spec get_first_child_tag(Node.t()) :: String.t()
  def get_first_child_tag(%Node{content: content}) when is_list(content) do
    case content do
      [%Node{tag: tag} | _] -> tag
      _ -> ""
    end
  end

  def get_first_child_tag(_node), do: ""

  @doc """
  Check if a node has a specific attribute value.

  ## Examples

      iex> node = %Node{tag: "iq", attrs: %{"type" => "set", "id" => "123"}}
      iex> NodeUtils.has_attr_value?(node, "type", "set")
      true

      iex> NodeUtils.has_attr_value?(node, "type", "get")
      false
  """
  @spec has_attr_value?(Node.t(), String.t(), String.t()) :: boolean()
  def has_attr_value?(%Node{attrs: attrs}, key, value) do
    Map.get(attrs, key) == value
  end

  @doc """
  Extract content from a child node.

  Returns the content of the first child node with the specified tag,
  or nil if not found.

  ## Examples

      iex> node = %Node{tag: "iq", content: [%Node{tag: "ref", content: "abc123"}]}
      iex> NodeUtils.get_child_content(node, "ref")
      "abc123"

      iex> NodeUtils.get_child_content(node, "nonexistent")
      nil
  """
  @spec get_child_content(Node.t(), String.t()) :: any()
  def get_child_content(node, tag) do
    case get_binary_node_child(node, tag) do
      %Node{content: content} -> content
      nil -> nil
    end
  end

  @doc """
  Extract attribute value from a node.

  Returns the value of the specified attribute, or nil if not found.

  ## Examples

      iex> node = %Node{tag: "iq", attrs: %{"type" => "set", "id" => "123"}}
      iex> NodeUtils.get_attr(node, "type")
      "set"

      iex> NodeUtils.get_attr(node, "nonexistent")
      nil
  """
  @spec get_attr(Node.t(), String.t()) :: any()
  def get_attr(%Node{attrs: attrs}, key) do
    Map.get(attrs, key)
  end
end
