defmodule Amarula.Protocol.Signal.Group.SenderKeyMessage do
  @moduledoc """
  Sender key message for group encryption, ported from
  `src/Signal/Group/sender-key-message.ts`.

  Wire format: `[version byte][Proto.SenderKeyMessage][64-byte XEd25519 sig]`
  where version = `(3 << 4) | 3 = 0x33` and the signature is XEd25519
  (Curve25519 keys, same scheme as the identity key) over version + protobuf.
  """

  import Bitwise

  alias Amarula.Protocol.Crypto.XEdDSA
  alias Amarula.Protocol.Proto

  @signature_length 64
  @current_version 3
  @senderkey_type 4

  @type t :: %__MODULE__{
          message_version: non_neg_integer(),
          key_id: non_neg_integer(),
          iteration: non_neg_integer(),
          ciphertext: binary(),
          signature: binary(),
          serialized: binary()
        }

  defstruct message_version: @current_version,
            key_id: nil,
            iteration: nil,
            ciphertext: <<>>,
            signature: <<>>,
            serialized: <<>>

  @doc """
  Creates a new SenderKeyMessage, signing with the Curve25519 private
  `signature_key`.
  """
  @spec new(non_neg_integer(), non_neg_integer(), binary(), binary()) :: t()
  def new(key_id, iteration, ciphertext, signature_key) do
    version = @current_version <<< 4 ||| @current_version

    message =
      Proto.SenderKeyMessage.encode(%Proto.SenderKeyMessage{
        id: key_id,
        iteration: iteration,
        ciphertext: ciphertext
      })

    signature = XEdDSA.sign(<<version>> <> message, strip5(signature_key))
    serialized = <<version>> <> message <> signature

    %__MODULE__{
      message_version: @current_version,
      key_id: key_id,
      iteration: iteration,
      ciphertext: ciphertext,
      signature: signature,
      serialized: serialized
    }
  end

  @doc """
  Creates a SenderKeyMessage from serialized bytes.
  """
  @spec from_serialized(binary()) :: {:ok, t()} | {:error, String.t()}
  def from_serialized(serialized) when byte_size(serialized) < @signature_length + 1 do
    {:error, "Serialized message too short"}
  end

  # Malformed protobuf raises (Protobuf.DecodeError) — let it crash; the
  # caller's process boundary handles it.
  def from_serialized(serialized) do
    body_len = byte_size(serialized) - @signature_length - 1

    <<version, message_part::binary-size(^body_len), signature::binary-size(@signature_length)>> =
      serialized

    msg = Proto.SenderKeyMessage.decode(message_part)

    {:ok,
     %__MODULE__{
       message_version: version >>> 4,
       key_id: msg.id,
       iteration: msg.iteration,
       ciphertext: msg.ciphertext,
       signature: signature,
       serialized: serialized
     }}
  end

  @doc """
  Gets the key ID.
  """
  @spec get_key_id(t()) :: non_neg_integer()
  def get_key_id(%__MODULE__{key_id: key_id}), do: key_id

  @doc """
  Gets the iteration.
  """
  @spec get_iteration(t()) :: non_neg_integer()
  def get_iteration(%__MODULE__{iteration: iteration}), do: iteration

  @doc """
  Gets the ciphertext.
  """
  @spec get_ciphertext(t()) :: binary()
  def get_ciphertext(%__MODULE__{ciphertext: ciphertext}), do: ciphertext

  @doc """
  Verifies the XEd25519 signature against the Curve25519 public `signature_key`
  (raw 32 bytes or 0x05-prefixed 33 bytes).
  """
  @spec verify_signature(t(), binary()) :: :ok | {:error, String.t()}
  def verify_signature(%__MODULE__{serialized: serialized, signature: signature}, signature_key) do
    message_part = binary_part(serialized, 0, byte_size(serialized) - @signature_length)

    if XEdDSA.verify(message_part, signature, strip5(signature_key)) do
      :ok
    else
      {:error, "Invalid signature"}
    end
  end

  @doc """
  Serializes the message to binary.
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{serialized: serialized}), do: serialized

  @doc """
  Gets the message type.
  """
  @spec get_type(t()) :: non_neg_integer()
  def get_type(_), do: @senderkey_type

  # Accept wire-form (33-byte 0x05-prefixed) or raw 32-byte Curve25519 keys.
  defp strip5(<<5, key::binary-size(32)>>), do: key
  defp strip5(<<key::binary-size(32)>>), do: key
end
