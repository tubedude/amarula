defmodule Amarula.Protocol.Signal.Group.SenderKeyRecord do
  @moduledoc """
  Represents a sender key record containing multiple sender key states.

  A sender key record can contain up to 5 sender key states, allowing for
  key rotation and backward compatibility.
  """

  alias Amarula.Protocol.Signal.Group.SenderKeyState

  @type t :: %__MODULE__{
          sender_key_states: [SenderKeyState.t()]
        }

  defstruct sender_key_states: []

  @max_states 5

  @doc """
  Creates a new empty SenderKeyRecord.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{sender_key_states: []}
  end

  @doc """
  Adds a sender key state to the record.
  """
  @spec add_sender_key_state(t(), SenderKeyState.t()) :: t()
  def add_sender_key_state(%__MODULE__{sender_key_states: states} = record, new_state) do
    # Add new state and limit to max states
    new_states = [new_state | states] |> Enum.take(@max_states)
    %{record | sender_key_states: new_states}
  end

  @doc """
  Updates an existing sender key state in the record.
  If the state doesn't exist, adds it as a new state.
  """
  @spec update_sender_key_state(t(), SenderKeyState.t()) :: t()
  def update_sender_key_state(%__MODULE__{sender_key_states: states} = record, updated_state) do
    key_id = SenderKeyState.get_key_id(updated_state)

    # Remove existing state with same key ID and add the updated one
    filtered_states = Enum.reject(states, &(SenderKeyState.get_key_id(&1) == key_id))
    new_states = [updated_state | filtered_states] |> Enum.take(@max_states)

    %{record | sender_key_states: new_states}
  end

  @doc """
  Gets the sender key state with the given key ID.
  """
  @spec get_sender_key_state(t(), non_neg_integer()) ::
          {:ok, SenderKeyState.t()} | {:error, String.t()}
  def get_sender_key_state(%__MODULE__{sender_key_states: states}, key_id) do
    case Enum.find(states, &(SenderKeyState.get_key_id(&1) == key_id)) do
      nil -> {:error, "Sender key state not found for key ID #{key_id}"}
      state -> {:ok, state}
    end
  end

  @doc """
  Gets the first (most recent) sender key state.
  """
  @spec get_sender_key_state(t()) :: {:ok, SenderKeyState.t()} | {:error, String.t()}
  def get_sender_key_state(%__MODULE__{sender_key_states: []}),
    do: {:error, "No sender key states available"}

  def get_sender_key_state(%__MODULE__{sender_key_states: [state | _]}), do: {:ok, state}

  @doc """
  Checks if the record is empty.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{sender_key_states: []}), do: true
  def empty?(%__MODULE__{sender_key_states: [_ | _]}), do: false
end
