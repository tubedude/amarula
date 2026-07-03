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
  Checks if the node has binary content.
  """
  @spec has_binary_content?(t()) :: boolean()
  def has_binary_content?(%__MODULE__{content: content}) when is_binary(content) do
    true
  end

  def has_binary_content?(_), do: false
end
