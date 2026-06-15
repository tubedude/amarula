defmodule Amarula.Protocol.Signal.WhisperProtocol do
  @moduledoc """
  Minimal protobuf decode for the two Signal v3 message types
  (libsignal WhisperTextProtocol). These are tiny — a few bytes/uint32 fields —
  so we decode them directly rather than dragging them through the WAProto build.

  Field tags (from node_modules/libsignal/src/WhisperTextProtocol.js):

  WhisperMessage:
    1 ephemeralKey   bytes
    2 counter        uint32
    3 previousCounter uint32
    4 ciphertext     bytes

  PreKeyWhisperMessage:
    1 preKeyId       uint32
    2 baseKey        bytes
    3 identityKey    bytes
    4 message        bytes  (a full WhisperMessage, version-tupled)
    5 registrationId uint32
    6 signedPreKeyId uint32
  """

  import Bitwise

  @type whisper_message :: %{
          ephemeral_key: binary() | nil,
          counter: non_neg_integer(),
          previous_counter: non_neg_integer(),
          ciphertext: binary() | nil
        }

  @type pre_key_whisper_message :: %{
          pre_key_id: non_neg_integer() | nil,
          base_key: binary() | nil,
          identity_key: binary() | nil,
          message: binary() | nil,
          registration_id: non_neg_integer() | nil,
          signed_pre_key_id: non_neg_integer() | nil
        }

  @doc """
  Encode a WhisperMessage protobuf body (without the version byte/MAC).
  Fields in number order: ephemeralKey(1), counter(2), previousCounter(3),
  ciphertext(4) — matching protobufjs output so the MAC over these bytes agrees
  with the peer.
  """
  @spec encode_whisper_message(binary(), non_neg_integer(), non_neg_integer(), binary()) ::
          binary()
  def encode_whisper_message(ephemeral_key, counter, previous_counter, ciphertext) do
    encode_bytes(1, ephemeral_key) <>
      encode_varint_field(2, counter) <>
      encode_varint_field(3, previous_counter) <>
      encode_bytes(4, ciphertext)
  end

  @doc """
  Encode a PreKeyWhisperMessage protobuf body (without the version byte).
  Fields in number order; `pre_key_id` is optional (omitted when nil).
  """
  @spec encode_pre_key_whisper_message(map()) :: binary()
  def encode_pre_key_whisper_message(m) do
    if(m.pre_key_id, do: encode_varint_field(1, m.pre_key_id), else: <<>>) <>
      encode_bytes(2, m.base_key) <>
      encode_bytes(3, m.identity_key) <>
      encode_bytes(4, m.message) <>
      encode_varint_field(5, m.registration_id) <>
      encode_varint_field(6, m.signed_pre_key_id)
  end

  @doc "Decode a WhisperMessage protobuf body (without the version byte/MAC)."
  @spec decode_whisper_message(binary()) :: whisper_message()
  def decode_whisper_message(bin) do
    fields = decode_fields(bin, %{})

    %{
      ephemeral_key: fields[1],
      counter: fields[2] || 0,
      previous_counter: fields[3] || 0,
      ciphertext: fields[4]
    }
  end

  @doc "Decode a PreKeyWhisperMessage protobuf body (without the version byte)."
  @spec decode_pre_key_whisper_message(binary()) :: pre_key_whisper_message()
  def decode_pre_key_whisper_message(bin) do
    fields = decode_fields(bin, %{})

    %{
      pre_key_id: fields[1],
      base_key: fields[2],
      identity_key: fields[3],
      message: fields[4],
      registration_id: fields[5],
      signed_pre_key_id: fields[6]
    }
  end

  # --- minimal protobuf wire writer ---

  defp encode_bytes(field, bin) when is_binary(bin) do
    write_varint(bsl(field, 3) ||| 2) <> write_varint(byte_size(bin)) <> bin
  end

  defp encode_varint_field(field, value) when is_integer(value) do
    write_varint(bsl(field, 3)) <> write_varint(value)
  end

  defp write_varint(value) when value < 0x80, do: <<value>>

  defp write_varint(value) do
    <<1::1, band(value, 0x7F)::7>> <> write_varint(bsr(value, 7))
  end

  # --- minimal protobuf wire reader (varint + length-delimited only) ---

  defp decode_fields(<<>>, acc), do: acc

  defp decode_fields(bin, acc) do
    {tag, rest} = read_varint(bin)
    field_num = bsr(tag, 3)
    wire_type = band(tag, 0x7)

    case wire_type do
      0 ->
        {value, rest} = read_varint(rest)
        decode_fields(rest, Map.put(acc, field_num, value))

      2 ->
        {len, rest} = read_varint(rest)
        <<value::binary-size(len), rest::binary>> = rest
        decode_fields(rest, Map.put(acc, field_num, value))

      _ ->
        raise "unsupported wire type #{wire_type} in Whisper protobuf"
    end
  end

  defp read_varint(bin), do: read_varint(bin, 0, 0)

  defp read_varint(<<1::1, low::7, rest::binary>>, shift, acc) do
    read_varint(rest, shift + 7, acc ||| bsl(low, shift))
  end

  defp read_varint(<<0::1, low::7, rest::binary>>, shift, acc) do
    {acc ||| bsl(low, shift), rest}
  end
end
