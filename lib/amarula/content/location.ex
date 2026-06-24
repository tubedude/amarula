defmodule Amarula.Content.Location do
  @moduledoc """
  A received location (`content` of a `%Amarula.Msg{type: :location}`, and the
  `:location` of an event).

    * `:latitude` / `:longitude` — coordinates (degrees).
    * `:name` / `:address` — place label and street address (`nil` if absent).
    * `:url` — an attached link.
    * `:live?` — `true` for a live (updating) location.
  """

  @type t :: %__MODULE__{
          latitude: float() | nil,
          longitude: float() | nil,
          name: String.t() | nil,
          address: String.t() | nil,
          url: String.t() | nil,
          live?: boolean()
        }

  defstruct [:latitude, :longitude, :name, :address, :url, live?: false]

  @doc "Normalize a `%Proto.Message.LocationMessage{}` into a `%Amarula.Content.Location{}`."
  @spec from_proto(struct()) :: t()
  def from_proto(%{} = m) do
    %__MODULE__{
      latitude: Map.get(m, :degreesLatitude),
      longitude: Map.get(m, :degreesLongitude),
      name: Map.get(m, :name),
      address: Map.get(m, :address),
      url: Map.get(m, :url),
      live?: Map.get(m, :isLive) == true
    }
  end
end
