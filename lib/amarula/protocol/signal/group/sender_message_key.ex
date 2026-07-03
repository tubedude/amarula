defmodule Amarula.Protocol.Signal.Group.SenderMessageKey do
  @moduledoc """
  Represents a sender message key for group encryption.

  Each message in a group uses a unique key derived from the sender chain key.
  This key is used for both encryption and decryption of individual messages.
  """

  alias Amarula.Protocol.Signal.CryptoHelpers

  @type t :: %__MODULE__{
          iteration: non_neg_integer(),
          seed: binary(),
          iv: binary(),
          cipher_key: binary()
        }

  defstruct iteration: 0, seed: <<>>, iv: <<>>, cipher_key: <<>>

  @doc """
  Creates a new SenderMessageKey from iteration and seed.

  Mirrors libsignal sender-message-key.ts: HKDF(seed, zeros32, "WhisperGroup")
  → derivative blocks D0, D1; iv = D0[0..15], cipher_key = D0[16..31] ++ D1[0..15].
  """
  @spec new(non_neg_integer(), binary()) :: t()
  def new(iteration, seed) do
    [d0, d1] = CryptoHelpers.derive_secrets(seed, :binary.copy(<<0>>, 32), "WhisperGroup", 2)

    %__MODULE__{
      iteration: iteration,
      seed: seed,
      iv: binary_part(d0, 0, 16),
      cipher_key: binary_part(d0, 16, 16) <> binary_part(d1, 0, 16)
    }
  end

  @doc """
  Gets the iteration number.
  """
  @spec get_iteration(t()) :: non_neg_integer()
  def get_iteration(%__MODULE__{iteration: iteration}), do: iteration

  @doc """
  Gets the IV for encryption/decryption.
  """
  @spec get_iv(t()) :: binary()
  def get_iv(%__MODULE__{iv: iv}), do: iv

  @doc """
  Gets the cipher key for encryption/decryption.
  """
  @spec get_cipher_key(t()) :: binary()
  def get_cipher_key(%__MODULE__{cipher_key: cipher_key}), do: cipher_key
end
