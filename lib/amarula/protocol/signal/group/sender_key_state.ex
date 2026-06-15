defmodule Amarula.Protocol.Signal.Group.SenderKeyState do
  @moduledoc """
  Represents the state of a sender key for group encryption.

  Manages the sender chain key, signing key, and message keys for a specific sender.
  """

  alias Amarula.Protocol.Signal.Group.{SenderChainKey, SenderMessageKey}

  @type signing_key :: %{
          public: binary(),
          private: binary() | nil
        }

  @type t :: %__MODULE__{
          sender_key_id: non_neg_integer(),
          sender_chain_key: SenderChainKey.t(),
          sender_signing_key: signing_key(),
          sender_message_keys: [SenderMessageKey.t()]
        }

  defstruct sender_key_id: 0,
            sender_chain_key: %SenderChainKey{},
            sender_signing_key: %{public: <<>>, private: nil},
            sender_message_keys: []

  @max_message_keys 2000

  @doc """
  Creates a new SenderKeyState.
  """
  @spec new(non_neg_integer(), non_neg_integer(), binary(), signing_key()) :: t()
  def new(sender_key_id, iteration, chain_key_seed, signing_key) do
    %__MODULE__{
      sender_key_id: sender_key_id,
      sender_chain_key: SenderChainKey.new(iteration, chain_key_seed),
      sender_signing_key: signing_key,
      sender_message_keys: []
    }
  end

  @doc """
  Gets the sender key ID.
  """
  @spec get_key_id(t()) :: non_neg_integer()
  def get_key_id(%__MODULE__{sender_key_id: sender_key_id}), do: sender_key_id

  @doc """
  Gets the current sender chain key.
  """
  @spec get_sender_chain_key(t()) :: SenderChainKey.t()
  def get_sender_chain_key(%__MODULE__{sender_chain_key: sender_chain_key}), do: sender_chain_key

  @doc """
  Sets the sender chain key.
  """
  @spec set_sender_chain_key(t(), SenderChainKey.t()) :: t()
  def set_sender_chain_key(state, sender_chain_key) do
    %{state | sender_chain_key: sender_chain_key}
  end

  @doc """
  Gets the public signing key.
  """
  @spec get_signing_key_public(t()) :: binary()
  def get_signing_key_public(%__MODULE__{sender_signing_key: %{public: public}}), do: public

  @doc """
  Gets the private signing key.
  """
  @spec get_signing_key_private(t()) :: binary() | nil
  def get_signing_key_private(%__MODULE__{sender_signing_key: %{private: private}}), do: private

  @doc """
  Adds a sender message key to the state.
  """
  @spec add_sender_message_key(t(), SenderMessageKey.t()) :: t()
  def add_sender_message_key(%__MODULE__{sender_message_keys: keys} = state, message_key) do
    # Add to the beginning and limit to max keys
    new_keys = [message_key | keys] |> Enum.take(@max_message_keys)
    %{state | sender_message_keys: new_keys}
  end

  @doc """
  Checks if a message key exists for the given iteration.
  """
  @spec has_sender_message_key(t(), non_neg_integer()) :: boolean()
  def has_sender_message_key(%__MODULE__{sender_message_keys: keys}, iteration) do
    Enum.any?(keys, &(SenderMessageKey.get_iteration(&1) == iteration))
  end

  @doc """
  Removes and returns a sender message key for the given iteration.
  """
  @spec remove_sender_message_key(t(), non_neg_integer()) :: {SenderMessageKey.t() | nil, t()}
  def remove_sender_message_key(%__MODULE__{sender_message_keys: keys} = state, iteration) do
    {found_key, remaining_keys} =
      Enum.split_with(keys, &(SenderMessageKey.get_iteration(&1) == iteration))

    case found_key do
      [key] -> {key, %{state | sender_message_keys: remaining_keys}}
      [] -> {nil, state}
    end
  end

  @doc """
  Checks if the state is valid.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{
        sender_key_id: id,
        sender_chain_key: chain_key,
        sender_signing_key: signing_key
      }) do
    id >= 0 and
      SenderChainKey.valid?(chain_key) and
      byte_size(signing_key.public) > 0
  end
end
