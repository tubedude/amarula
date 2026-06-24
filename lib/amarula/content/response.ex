defmodule Amarula.Content.Response do
  @moduledoc """
  A reply a user made to an interactive message — a button tap, list selection,
  template-button reply, or interactive response. Unified into one shape since they
  all share one shape: the user picked an option identified by `id`, shown as `text`.

    * `:kind` — `:button | :list | :template | :interactive`.
    * `:id` — the selected option's id (what your app keys off).
    * `:text` — the option's display text.

  For anything beyond the selection itself, read `msg.raw`.
  """

  @type kind :: :button | :list | :template | :interactive

  @type t :: %__MODULE__{kind: kind(), id: String.t() | nil, text: String.t() | nil}

  @enforce_keys [:kind]
  defstruct [:kind, :id, :text]

  @doc """
  Normalize one of the interactive-response protos into a `%Amarula.Content.Response{}`.
  `kind` says which proto it is; the id/text fields differ per proto and are mapped
  to the unified `id`/`text`.
  """
  @spec from_proto(kind(), struct()) :: t()
  def from_proto(:button, %{} = m),
    do: %__MODULE__{
      kind: :button,
      id: Map.get(m, :selectedButtonId),
      text: oneof_text(Map.get(m, :response))
    }

  def from_proto(:template, %{} = m),
    do: %__MODULE__{
      kind: :template,
      id: Map.get(m, :selectedId),
      text: Map.get(m, :selectedDisplayText)
    }

  def from_proto(:list, %{} = m) do
    reply = Map.get(m, :singleSelectReply) || %{}
    %__MODULE__{kind: :list, id: Map.get(reply, :selectedRowId), text: Map.get(m, :title)}
  end

  def from_proto(:interactive, %{} = m) do
    # interactiveResponseMessage carries a nativeFlowResponseMessage with the params
    # JSON; surface the body text and leave the structured payload to msg.raw.
    %__MODULE__{kind: :interactive, id: nil, text: text_of(Map.get(m, :body))}
  end

  defp text_of(%{text: t}), do: t
  defp text_of(_), do: nil

  # ButtonsResponseMessage packs its display text in a `:response` oneof
  # (`{:selectedDisplayText, text}`).
  defp oneof_text({:selectedDisplayText, t}), do: t
  defp oneof_text(_), do: nil
end
