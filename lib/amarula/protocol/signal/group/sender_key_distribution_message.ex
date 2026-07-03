defmodule Amarula.Protocol.Signal.Group.SenderKeyDistributionMessage do
  @moduledoc """
  Sender key distribution message, ported from
  `src/Signal/Group/sender-key-distribution-message.ts`.

  Wire format: `[version byte][Proto.SenderKeyDistributionMessage]` where
  version = `(3 << 4) | 3 = 0x33`. No signature — the SKDM travels inside an
  already-encrypted Signal message.
  """

  import Bitwise

  alias Amarula.Protocol.Proto

  @current_version 3

  @type t :: %__MODULE__{
          id: integer(),
          iteration: integer(),
          chain_key: binary(),
          signature_key: binary(),
          serialized: binary()
        }

  defstruct id: nil, iteration: nil, chain_key: nil, signature_key: nil, serialized: nil

  @doc """
  Creates a new SenderKeyDistributionMessage. `signature_key` is the public
  signing key in wire form (33 bytes, 0x05-prefixed).
  """
  @spec new(integer(), integer(), binary(), binary()) :: t()
  def new(id, iteration, chain_key, signature_key) do
    version = @current_version <<< 4 ||| @current_version

    message =
      Proto.SenderKeyDistributionMessage.encode(%Proto.SenderKeyDistributionMessage{
        id: id,
        iteration: iteration,
        chainKey: chain_key,
        signingKey: signature_key
      })

    %__MODULE__{
      id: id,
      iteration: iteration,
      chain_key: chain_key,
      signature_key: signature_key,
      serialized: <<version>> <> message
    }
  end

  @doc """
  Parses a serialized SenderKeyDistributionMessage (`[version][protobuf]`).
  Malformed protobuf raises — let it crash.
  """
  @spec from_serialized(binary()) :: {:ok, t()} | {:error, String.t()}
  def from_serialized(<<_version, message::binary>> = serialized) do
    msg = Proto.SenderKeyDistributionMessage.decode(message)

    {:ok,
     %__MODULE__{
       id: msg.id,
       iteration: msg.iteration,
       chain_key: msg.chainKey,
       signature_key: msg.signingKey,
       serialized: serialized
     }}
  end

  def from_serialized(_), do: {:error, "Serialized SKDM too short"}
end
