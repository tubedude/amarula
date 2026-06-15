defmodule Amarula.Protocol.Signal.Group.SenderKeyRecord do
  @moduledoc """
  Represents a sender key record containing multiple sender key states.

  A sender key record can contain up to 5 sender key states, allowing for
  key rotation and backward compatibility.
  """

  alias Amarula.Protocol.Signal.Group.{SenderKeyState, SenderChainKey, SenderMessageKey}

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
  Creates a SenderKeyRecord from serialized data.
  """
  @spec from_serialized([map()]) :: t()
  def from_serialized(serialized_states) when is_list(serialized_states) do
    sender_key_states = Enum.map(serialized_states, &deserialize_state/1)
    %__MODULE__{sender_key_states: sender_key_states}
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

  @doc """
  Gets the number of sender key states in the record.
  """
  @spec state_count(t()) :: non_neg_integer()
  def state_count(%__MODULE__{sender_key_states: states}), do: length(states)

  @doc """
  Serializes the record to a list of maps.
  """
  @spec serialize(t()) :: [map()]
  def serialize(%__MODULE__{sender_key_states: states}) do
    Enum.map(states, &serialize_state/1)
  end

  # Private helper functions

  @spec serialize_state(SenderKeyState.t()) :: map()
  defp serialize_state(%SenderKeyState{
         sender_key_id: sender_key_id,
         sender_chain_key: %{iteration: iteration, seed: seed},
         sender_signing_key: %{public: public, private: private},
         sender_message_keys: message_keys
       }) do
    %{
      sender_key_id: sender_key_id,
      sender_chain_key: %{
        iteration: iteration,
        seed: seed
      },
      sender_signing_key: %{
        public: public,
        private: private
      },
      sender_message_keys:
        Enum.map(message_keys, fn %{iteration: iter, seed: msg_seed} ->
          %{iteration: iter, seed: msg_seed}
        end)
    }
  end

  @spec deserialize_state(map()) :: SenderKeyState.t()
  defp deserialize_state(%{
         sender_key_id: sender_key_id,
         sender_chain_key: %{iteration: iteration, seed: seed},
         sender_signing_key: %{public: public, private: private},
         sender_message_keys: message_keys
       }) do
    # Reconstruct the sender key state
    signing_key = %{public: public, private: private}
    chain_key = SenderChainKey.new(iteration, seed)

    # Reconstruct message keys
    reconstructed_message_keys =
      Enum.map(message_keys, fn %{iteration: iter, seed: msg_seed} ->
        SenderMessageKey.new(iter, msg_seed)
      end)

    %SenderKeyState{
      sender_key_id: sender_key_id,
      sender_chain_key: chain_key,
      sender_signing_key: signing_key,
      sender_message_keys: reconstructed_message_keys
    }
  end
end
