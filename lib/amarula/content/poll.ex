defmodule Amarula.Content.Poll do
  @moduledoc """
  A received poll (`content` of a `%Amarula.Msg{type: :poll}`).

    * `:name` — the poll question.
    * `:options` — the answer option names, in order (a list of strings).
    * `:selectable` — how many options a voter may pick (`1` = single-choice);
      mirrors the `:selectable` option on `Amarula.send_poll/5`.
    * `:enc_key` — the poll's encryption key (votes arrive encrypted under it; see
      `Amarula.Protocol.Messages.PollCrypto`).
  """

  @type t :: %__MODULE__{
          name: String.t() | nil,
          options: [String.t()],
          selectable: non_neg_integer() | nil,
          enc_key: binary() | nil
        }

  defstruct [:name, :selectable, :enc_key, options: []]

  @doc "Normalize a `%Proto.Message.PollCreationMessage{}` (any version) into a `%Amarula.Content.Poll{}`."
  @spec from_proto(struct()) :: t()
  def from_proto(%{} = m) do
    %__MODULE__{
      name: Map.get(m, :name),
      options: m |> Map.get(:options, []) |> Enum.flat_map(&option_name/1),
      selectable: Map.get(m, :selectableOptionsCount),
      enc_key: Map.get(m, :encKey)
    }
  end

  defp option_name(%{optionName: name}) when is_binary(name), do: [name]
  defp option_name(_), do: []
end
