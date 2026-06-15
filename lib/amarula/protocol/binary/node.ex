defmodule Amarula.Protocol.Binary.Node do
  @moduledoc """
  Binary node structure for WhatsApp protocol.

  Represents a node in the WhatsApp binary protocol tree structure.
  Each node has a tag, attributes, and content.
  """

  @type t :: %__MODULE__{
          tag: binary(),
          attrs: map() | [{binary(), binary()}],
          content: binary() | [t()] | nil
        }

  defstruct [:tag, :attrs, :content]

  @doc """
  Creates a new node with the given tag, attributes, and content.

  ## Examples

      iex> Node.new("iq", %{id: "1"}, nil)
      %Node{tag: "iq", attrs: %{id: "1"}, content: nil}

      iex> Node.new("message", %{}, "Hello")
      %Node{tag: "message", attrs: %{}, content: "Hello"}
  """
  @spec new(binary(), map(), binary() | [t()] | nil) :: t()
  def new(tag, attrs \\ %{}, content \\ nil) do
    %__MODULE__{tag: tag, attrs: attrs, content: content}
  end

  @doc """
  Creates a new node with the given tag, attributes, and content.
  This is an alias for new/3 for compatibility with the messages module.
  """
  @spec create(binary(), map(), binary() | [t()] | nil) :: t()
  def create(tag, attrs \\ %{}, content \\ nil) do
    new(tag, attrs, content)
  end

  @doc """
  Checks if a node has children (nested nodes).
  """
  @spec has_children?(t()) :: boolean()
  def has_children?(%__MODULE__{content: content}) when is_list(content) do
    length(content) > 0
  end

  def has_children?(_), do: false

  @doc """
  Gets the number of child nodes.
  """
  @spec child_count(t()) :: non_neg_integer()
  def child_count(%__MODULE__{content: content}) when is_list(content) do
    length(content)
  end

  def child_count(_), do: 0

  @doc """
  Gets a child node by index.
  """
  @spec get_child(t(), non_neg_integer()) :: t() | nil
  def get_child(%__MODULE__{content: content}, index) when is_list(content) do
    Enum.at(content, index)
  end

  def get_child(_, _), do: nil

  @doc """
  Checks if the node has binary content.
  """
  @spec has_binary_content?(t()) :: boolean()
  def has_binary_content?(%__MODULE__{content: content}) when is_binary(content) do
    true
  end

  def has_binary_content?(_), do: false

  @doc """
  Checks if the node has string content.
  """
  @spec has_string_content?(t()) :: boolean()
  def has_string_content?(%__MODULE__{content: content}) when is_binary(content) do
    true
  end

  def has_string_content?(_), do: false

  @doc """
  Checks if the node has no content.
  """
  @spec is_empty?(t()) :: boolean()
  def is_empty?(%__MODULE__{content: nil}), do: true
  def is_empty?(%__MODULE__{content: ""}), do: true
  def is_empty?(%__MODULE__{content: []}), do: true
  def is_empty?(_), do: false
end
