defmodule Amarula.Content.Poll do
  @moduledoc """
  A received poll (the `content` of a `%Amarula.Msg{type: :poll}`).

    * `:name` — the poll question.
    * `:options` — the answer option names, in order (a list of strings).
    * `:selectable_count` — how many options a voter may pick (`1` = single-choice).
    * `:enc_key` — the poll's encryption key (votes arrive encrypted under it; see
      `Amarula.Protocol.Messages.PollCrypto`).
  """

  @type t :: %__MODULE__{
          name: String.t() | nil,
          options: [String.t()],
          selectable_count: non_neg_integer() | nil,
          enc_key: binary() | nil
        }

  defstruct name: nil, options: [], selectable_count: nil, enc_key: nil

  @doc "Normalize a `%Proto.Message.PollCreationMessage{}` (any version) into a `%Amarula.Content.Poll{}`."
  @spec from_proto(struct()) :: t()
  def from_proto(%{} = m) do
    %__MODULE__{
      name: Map.get(m, :name),
      options: m |> Map.get(:options, []) |> Enum.map(&option_name/1),
      selectable_count: Map.get(m, :selectableOptionsCount),
      enc_key: Map.get(m, :encKey)
    }
  end

  defp option_name(%{optionName: name}), do: name
  defp option_name(_), do: nil
end
