defmodule Amarula.Protocol.Signal.Group.SenderChainKey do
  @moduledoc """
  Represents a sender chain key for group encryption.

  The sender chain key is used to derive message keys for sequential messages.
  Each iteration produces a new message key and advances the chain.
  """

  alias Amarula.Protocol.Signal.CryptoHelpers
  alias Amarula.Protocol.Signal.Group.SenderMessageKey

  # libsignal sender-chain-key.ts derivation seeds
  @message_key_seed <<0x01>>
  @chain_key_seed <<0x02>>

  @type t :: %__MODULE__{
          iteration: non_neg_integer(),
          seed: binary()
        }

  defstruct iteration: 0, seed: <<>>

  @doc """
  Creates a new SenderChainKey.
  """
  @spec new(non_neg_integer(), binary()) :: t()
  def new(iteration, seed) do
    %__MODULE__{
      iteration: iteration,
      seed: seed
    }
  end

  @doc """
  Gets the current iteration number.
  """
  @spec get_iteration(t()) :: non_neg_integer()
  def get_iteration(%__MODULE__{iteration: iteration}), do: iteration

  @doc """
  Gets the seed used to derive keys.
  """
  @spec get_seed(t()) :: binary()
  def get_seed(%__MODULE__{seed: seed}), do: seed

  @doc """
  Generates the next chain key in the sequence.
  """
  @spec get_next(t()) :: t()
  def get_next(%__MODULE__{iteration: iteration, seed: seed}) do
    new(iteration + 1, CryptoHelpers.calculate_mac(seed, @chain_key_seed))
  end

  @doc """
  Generates a message key for the current iteration.
  """
  @spec get_sender_message_key(t()) :: SenderMessageKey.t()
  def get_sender_message_key(%__MODULE__{iteration: iteration, seed: seed}) do
    SenderMessageKey.new(iteration, CryptoHelpers.calculate_mac(seed, @message_key_seed))
  end

  @doc """
  Checks if this chain key is valid.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{iteration: iteration, seed: seed}) do
    iteration >= 0 and byte_size(seed) == 32
  end
end
