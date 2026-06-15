defmodule Amarula.Contact do
  @moduledoc """
  A contact update from app-state sync — the consumer view of a `contactAction`
  (a saved name) or the local push-name setting. `address` is the contact.
  """

  alias Amarula.Address

  @type t :: %__MODULE__{
          address: Address.t() | nil,
          full_name: String.t() | nil,
          first_name: String.t() | nil
        }

  @enforce_keys [:address]
  defstruct [:address, :full_name, :first_name]
end
