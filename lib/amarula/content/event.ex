defmodule Amarula.Content.Event do
  @moduledoc """
  A received event (`content` of a `%Amarula.Msg{type: :event}`).

    * `:name` — the event title.
    * `:description` — its description (`nil` if none).
    * `:location` — an `%Amarula.Content.Location{}` if the event has one, else `nil`.
    * `:join_link` — a call/meeting link.
    * `:start_time` / `:end_time` — unix-seconds timestamps (`nil` if absent).
    * `:extra_guests_allowed?` — whether guests may invite others.
    * `:canceled?` — whether the event was canceled.
  """

  alias Amarula.Content.Location

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          location: Location.t() | nil,
          join_link: String.t() | nil,
          start_time: integer() | nil,
          end_time: integer() | nil,
          extra_guests_allowed?: boolean(),
          canceled?: boolean()
        }

  defstruct [
    :name,
    :description,
    :location,
    :join_link,
    :start_time,
    :end_time,
    extra_guests_allowed?: false,
    canceled?: false
  ]

  @doc "Normalize a `%Proto.Message.EventMessage{}` into a `%Amarula.Content.Event{}`."
  @spec from_proto(struct()) :: t()
  def from_proto(%{} = m) do
    %__MODULE__{
      name: Map.get(m, :name),
      description: Map.get(m, :description),
      location: normalize_location(Map.get(m, :location)),
      join_link: Map.get(m, :joinLink),
      start_time: Map.get(m, :startTime),
      end_time: Map.get(m, :endTime),
      extra_guests_allowed?: Map.get(m, :extraGuestsAllowed) == true,
      canceled?: Map.get(m, :isCanceled) == true
    }
  end

  defp normalize_location(nil), do: nil
  defp normalize_location(%{} = loc), do: Location.from_proto(loc)
end
