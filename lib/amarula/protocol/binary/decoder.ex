defmodule Amarula.Protocol.Binary.Decoder do
  @moduledoc """
  Binary decoder for WhatsApp protocol.

  Decodes binary data into Node structures following the WhatsApp binary protocol.
  Ported from src/WABinary/decode.ts
  """

  import Bitwise
  alias Amarula.Protocol.Binary.{Node, Constants}

  @doc """
  Decodes binary data into a Node structure.

  ## Examples

      iex> Decoder.decode(<<248, 1, 25, 0>>)
      %Node{tag: "iq", attrs: %{}, content: nil}
  """
  @spec decode(binary()) :: Node.t()
  def decode(binary) when is_binary(binary) do
    {node, _index} = decode_node(binary, 0)
    node
  end

  # Private helper functions

  @spec decode_node(binary(), non_neg_integer()) :: {Node.t(), non_neg_integer()}
  defp decode_node(binary, index) do
    {list_size, index} = read_list_size(binary, index)
    {tag, index} = read_string(binary, index)

    case {list_size, tag} do
      {0, ""} ->
        # Completely empty node
        {%Node{tag: "", attrs: %{}, content: nil}, index}

      {0, _} ->
        # list_size is 0 but tag is not empty - invalid
        raise "invalid node"

      {_, ""} ->
        # tag is empty but list_size is not 0 - invalid
        raise "invalid node"

      {list_size, tag} ->
        # Valid node with content
        {attrs, index} = read_attributes(binary, index, list_size)

        {content, index} =
          if rem(list_size, 2) == 0 do
            read_content(binary, index)
          else
            {nil, index}
          end

        {%Node{tag: tag, attrs: attrs, content: content}, index}
    end
  end

  @spec read_list_size(binary(), non_neg_integer()) :: {non_neg_integer(), non_neg_integer()}
  defp read_list_size(binary, index) do
    tag = binary_at(binary, index)
    index = index + 1

    case tag do
      # LIST_EMPTY
      0 -> {0, index}
      # LIST_8
      248 -> {binary_at(binary, index), index + 1}
      # LIST_16 — read_int already returns {value, advanced_index}
      249 -> read_int(binary, index, 2)
      _ -> raise "invalid tag for list size: #{tag}"
    end
  end

  @spec read_string(binary(), non_neg_integer()) :: {binary(), non_neg_integer()}
  defp read_string(binary, index) do
    tag = binary_at(binary, index)
    index = index + 1

    cond do
      # Single byte tokens (indices 1–235; Baileys: tag < singleByteTokens.length)
      tag >= 1 and tag <= 235 ->
        token = Constants.token_to_string(tag) || ""
        {token, index}

      # Dictionary tokens
      tag in [236, 237, 238, 239] ->
        dict_index = tag - 236
        token_index = binary_at(binary, index)
        index = index + 1
        token = get_double_token(dict_index, token_index)
        {token, index}

      # LIST_EMPTY
      tag == 0 ->
        {"", index}

      # BINARY_8
      tag == 252 ->
        length = binary_at(binary, index)
        index = index + 1

        if index + length > byte_size(binary) do
          raise "end of stream"
        end

        data = binary_part(binary, index, length)
        {data, index + length}

      # BINARY_20
      tag == 253 ->
        {length, index} = read_int20(binary, index)

        if index + length > byte_size(binary) do
          raise "end of stream"
        end

        data = binary_part(binary, index, length)
        {data, index + length}

      # BINARY_32
      tag == 254 ->
        {length, index} = read_int(binary, index, 4)

        if index + length > byte_size(binary) do
          raise "end of stream"
        end

        data = binary_part(binary, index, length)
        {data, index + length}

      # JID_PAIR - each part is itself a string (token, nibble-packed number, etc.)
      # Matches Baileys readJidPair: readString(readByte()) for user and server.
      tag == 250 ->
        {user, index} = read_string(binary, index)
        {server, index} = read_string(binary, index)

        jid = if server != "", do: "#{user}@#{server}", else: user
        {jid, index}

      # AD_JID - domain byte, device byte, then the user as a string
      # Matches Baileys readAdJid: readByte, readByte, readString(readByte()).
      tag == 247 ->
        domain_type = binary_at(binary, index)
        device = binary_at(binary, index + 1)
        {user, index} = read_string(binary, index + 2)

        server =
          case domain_type do
            0 -> "s.whatsapp.net"
            1 -> "lid"
            2 -> "hosted"
            3 -> "hosted.lid"
            _ -> "s.whatsapp.net"
          end

        jid = if device == 0, do: "#{user}@#{server}", else: "#{user}:#{device}@#{server}"
        {jid, index}

      # HEX_8 - packed hex string
      tag == 251 ->
        read_packed8(binary, index, :hex)

      # NIBBLE_8 - packed nibble string
      tag == 255 ->
        read_packed8(binary, index, :nibble)

      true ->
        raise "invalid string with tag: #{tag}"
    end
  end

  @spec read_attributes(binary(), non_neg_integer(), non_neg_integer()) ::
          {map(), non_neg_integer()}
  defp read_attributes(binary, index, list_size) do
    attributes_length = div(list_size - 1, 2)
    read_attributes(binary, index, attributes_length, %{})
  end

  @spec read_attributes(binary(), non_neg_integer(), non_neg_integer(), map()) ::
          {map(), non_neg_integer()}
  defp read_attributes(_binary, index, 0, attrs), do: {attrs, index}

  defp read_attributes(binary, index, remaining, attrs) do
    {key, index} = read_string(binary, index)
    {value, index} = read_string(binary, index)
    read_attributes(binary, index, remaining - 1, Map.put(attrs, key, value))
  end

  @spec read_content(binary(), non_neg_integer()) :: {any(), non_neg_integer()}
  defp read_content(binary, index) do
    tag = binary_at(binary, index)
    index = index + 1

    cond do
      # LIST_EMPTY - return nil directly
      tag == 0 ->
        {nil, index}

      # List tags
      tag in [248, 249] ->
        read_list(binary, index, tag)

      # JID_PAIR content (special case)
      tag == 250 ->
        # Re-read with the tag
        {content, index} = read_string(binary, index - 1)
        {content, index}

      # Binary content
      tag in [252, 253, 254] ->
        # Re-read with the tag
        {content, index} = read_string(binary, index - 1)
        {content, index}

      # String content
      true ->
        # Re-read with the tag
        {content, index} = read_string(binary, index - 1)
        {content, index}
    end
  end

  @spec read_list(binary(), non_neg_integer(), integer()) :: {[Node.t()], non_neg_integer()}
  defp read_list(binary, index, _tag) do
    # Re-read with the tag
    {size, index} = read_list_size(binary, index - 1)
    read_list_items(binary, index, size, [])
  end

  @spec read_list_items(binary(), non_neg_integer(), non_neg_integer(), [Node.t()]) ::
          {[Node.t()], non_neg_integer()}
  defp read_list_items(_binary, index, 0, items), do: {Enum.reverse(items), index}

  defp read_list_items(binary, index, remaining, items) do
    {node, index} = decode_node(binary, index)
    read_list_items(binary, index, remaining - 1, [node | items])
  end

  @spec read_int(binary(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  defp read_int(binary, index, n) do
    read_int(binary, index, n, 0)
  end

  @spec read_int(binary(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  defp read_int(_binary, index, 0, val), do: {val, index}

  defp read_int(binary, index, n, val) do
    byte = binary_at(binary, index)
    val = val ||| byte <<< ((n - 1) * 8)
    read_int(binary, index + 1, n - 1, val)
  end

  @spec read_int20(binary(), non_neg_integer()) :: {non_neg_integer(), non_neg_integer()}
  defp read_int20(binary, index) do
    # Baileys readInt20: ((b1 & 15) << 16) | (b2 << 8) | b3 — only the low 4 bits
    # of the first byte are part of the length.
    byte1 = binary_at(binary, index)
    byte2 = binary_at(binary, index + 1)
    byte3 = binary_at(binary, index + 2)
    val = (byte1 &&& 15) <<< 16 ||| byte2 <<< 8 ||| byte3
    {val, index + 3}
  end

  @spec get_double_token(non_neg_integer(), non_neg_integer()) :: binary()
  defp get_double_token(dict_index, token_index) do
    case Constants.tag_to_string({dict_index, token_index}) do
      nil -> raise "Invalid double token (#{dict_index}, #{token_index})"
      token -> token
    end
  end

  @spec binary_at(binary(), non_neg_integer()) :: non_neg_integer()
  defp binary_at(binary, index) do
    if index >= byte_size(binary) do
      raise "end of stream"
    end

    :binary.at(binary, index)
  end

  # Packed string decoding (HEX_8 and NIBBLE_8)
  @spec read_packed8(binary(), non_neg_integer(), :hex | :nibble) :: {binary(), non_neg_integer()}
  defp read_packed8(binary, index, type) do
    start_byte = binary_at(binary, index)
    index = index + 1

    # Extract count from lower 7 bits
    count = start_byte &&& 127
    # Extract padding flag from highest bit
    has_padding = start_byte >>> 7 != 0

    # Read packed bytes and unpack nibbles
    {value, index} = read_packed_bytes(binary, index, count, type, "")

    # Remove last character if padding bit is set
    value = if has_padding, do: String.slice(value, 0..-2//1), else: value

    {value, index}
  end

  @spec read_packed_bytes(
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          :hex | :nibble,
          binary()
        ) :: {binary(), non_neg_integer()}
  defp read_packed_bytes(_binary, index, 0, _type, acc), do: {acc, index}

  defp read_packed_bytes(binary, index, count, type, acc) do
    cur_byte = binary_at(binary, index)
    index = index + 1

    # Extract high and low nibbles
    high_nibble = (cur_byte &&& 0xF0) >>> 4
    low_nibble = cur_byte &&& 0x0F

    # Unpack nibbles to characters
    high_char = unpack_nibble(type, high_nibble)
    low_char = unpack_nibble(type, low_nibble)

    # Accumulate characters
    acc = acc <> <<high_char::utf8>> <> <<low_char::utf8>>

    read_packed_bytes(binary, index, count - 1, type, acc)
  end

  @spec unpack_nibble(:hex | :nibble, non_neg_integer()) :: non_neg_integer()
  defp unpack_nibble(:hex, value) do
    cond do
      value >= 0 and value < 10 -> ?0 + value
      value >= 10 and value < 16 -> ?A + value - 10
      true -> raise "invalid hex nibble: #{value}"
    end
  end

  defp unpack_nibble(:nibble, value) do
    cond do
      value >= 0 and value <= 9 -> ?0 + value
      value == 10 -> ?-
      value == 11 -> ?.
      # null terminator
      value == 15 -> 0
      true -> raise "invalid nibble: #{value}"
    end
  end
end
