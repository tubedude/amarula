defmodule Amarula.Protocol.Binary.Encoder do
  @moduledoc """
  Binary encoder for WhatsApp protocol.

  Encodes Node structures into binary data following the WhatsApp binary protocol.
  Ported from src/WABinary/encode.ts
  """

  import Bitwise
  alias Amarula.Protocol.Binary.{Node, Constants}

  @doc """
  Encodes a Node structure into binary data.

  Returns `{:ok, binary}` on success.
  """
  @spec encode(Node.t()) :: {:ok, binary()}
  def encode(node) do
    # Start with initial byte
    buffer = [0]
    encoded = encode_node_inner(node, buffer)
    # Skip the initial byte (0) and convert to binary
    binary = :erlang.list_to_binary(tl(encoded))
    {:ok, binary}
  end

  @spec encode_node_inner(Node.t(), [non_neg_integer()]) :: [non_neg_integer()]
  defp encode_node_inner(%Node{tag: tag, attrs: attrs, content: content}, buffer) do
    # Filter out undefined/null attributes
    # Keep as list if it's a list (preserves order), otherwise convert from map
    valid_attrs =
      Enum.filter(attrs || %{}, fn {_k, v} ->
        v != nil and v != :undefined
      end)

    # Count attributes (works for both list and map)
    attr_count = length(valid_attrs)

    # Calculate list size: 2 * attributes + 1 (tag) + 1 (content if present and not nil)
    # But if tag is empty and no content, list size should be 0
    list_size =
      if tag == "" and content == nil and attr_count == 0 do
        0
      else
        2 * attr_count + 1 + if content != nil, do: 1, else: 0
      end

    # Write list start
    buffer = write_list_start(list_size, buffer)

    # Write tag
    buffer = write_string(tag, buffer)

    # Write attributes (order is preserved for lists)
    buffer =
      Enum.reduce(valid_attrs, buffer, fn {key, value}, acc ->
        acc = write_string(key, acc)
        write_string(value, acc)
      end)

    # Write content
    buffer = write_content(content, buffer)

    buffer
  end

  @spec write_list_start(non_neg_integer(), [non_neg_integer()]) :: [non_neg_integer()]
  defp write_list_start(0, buffer), do: push_byte(Constants.tag(:list_empty), buffer)

  defp write_list_start(size, buffer) when size < 256 do
    buffer = push_byte(Constants.tag(:list_8), buffer)
    push_byte(size, buffer)
  end

  defp write_list_start(size, buffer) when size < 65536 do
    buffer = push_byte(Constants.tag(:list_16), buffer)
    push_int16(size, buffer)
  end

  @spec write_string(String.t() | nil, [non_neg_integer()]) :: [non_neg_integer()]
  defp write_string(nil, buffer), do: push_byte(Constants.tag(:list_empty), buffer)
  # Empty string is token 0
  defp write_string("", buffer), do: push_byte(0, buffer)

  defp write_string(str, buffer) do
    cond do
      # Non-UTF-8 binary content (protobuf blobs) can't be a JID or a token —
      # write it directly as length-prefixed raw bytes.
      not String.valid?(str) ->
        write_string_raw(str, buffer)

      String.contains?(str, "@") ->
        write_jid(str, buffer)

      token = Constants.string_to_tag(str) ->
        write_token(token, buffer)

      true ->
        write_string_raw(str, buffer)
    end
  end

  # Encode a JID, matching Baileys jidDecode/writeJid exactly:
  #   device-suffixed jids → AD_JID(247) | domainType | device | <user>
  #   plain jids           → JID_PAIR(250) | <user> | <server>
  # The server string is NOT written for AD_JID — the server is carried solely by
  # domainType. Encoding a device jid as a plain JID_PAIR (the old bug) produced a
  # wire jid the server can't parse, so it SILENTLY DROPPED every frame addressing
  # a device (the `<key>` bundle fetch and the `<message>` participants).
  @spec write_jid(String.t(), [non_neg_integer()]) :: [non_neg_integer()]
  defp write_jid(jid, buffer) do
    case decode_jid(jid) do
      {:ok, %{user: user, device: device, domain_type: domain_type}} when not is_nil(device) ->
        buffer = push_byte(Constants.tag(:ad_jid), buffer)
        buffer = push_byte(domain_type, buffer)
        buffer = push_byte(device, buffer)
        write_string_inner(user, buffer)

      {:ok, %{user: user, server: server}} ->
        buffer = push_byte(Constants.tag(:jid_pair), buffer)
        buffer = write_jid_user(user, buffer)
        write_string_inner(server, buffer)

      :error ->
        write_string_raw(jid, buffer)
    end
  end

  # Parse "<user>[_<agent>][:<device>]@<server>" into its parts + domainType.
  @spec decode_jid(String.t()) :: {:ok, map()} | :error
  defp decode_jid(jid) do
    case String.split(jid, "@", parts: 2) do
      [user_combined, server] ->
        {user_agent, device} = split_device(user_combined)
        {user, agent} = split_agent(user_agent)

        {:ok,
         %{user: user, server: server, device: device, domain_type: domain_type(server, agent)}}

      _ ->
        :error
    end
  end

  defp split_device(user_combined) do
    case String.split(user_combined, ":", parts: 2) do
      [ua, dev] -> {ua, String.to_integer(dev)}
      [ua] -> {ua, nil}
    end
  end

  defp split_agent(user_agent) do
    case String.split(user_agent, "_", parts: 2) do
      [u, a] -> {u, a}
      [u] -> {u, nil}
    end
  end

  defp domain_type("lid", _agent), do: 1
  defp domain_type("hosted", _agent), do: 128
  defp domain_type("hosted.lid", _agent), do: 129
  defp domain_type(_server, nil), do: 0
  defp domain_type(_server, agent), do: String.to_integer(agent)

  defp write_jid_user("", buffer), do: push_byte(Constants.tag(:list_empty), buffer)
  defp write_jid_user(user, buffer), do: write_string_inner(user, buffer)

  # Internal string writer that doesn't check for JIDs (prevents infinite recursion)
  @spec write_string_inner(String.t(), [non_neg_integer()]) :: [non_neg_integer()]
  defp write_string_inner("", buffer), do: push_byte(0, buffer)

  defp write_string_inner(str, buffer) do
    case Constants.string_to_tag(str) do
      nil -> write_string_raw(str, buffer)
      token -> write_token(token, buffer)
    end
  end

  # Write a token: single-byte tokens are one byte; double-byte (dictionary)
  # tokens are a DICTIONARY_<n> marker byte followed by the index, matching
  # Baileys writeString.
  @spec write_token(integer() | {integer(), integer()}, [non_neg_integer()]) ::
          [non_neg_integer()]
  defp write_token(index, buffer) when is_integer(index), do: push_byte(index, buffer)

  defp write_token({dict, index}, buffer) do
    buffer = push_byte(Constants.tag(:dictionary_0) + dict, buffer)
    push_byte(index, buffer)
  end

  @spec write_string_raw(binary(), [non_neg_integer()]) :: [non_neg_integer()]
  defp write_string_raw(str, buffer) do
    # Nibble-pack only valid all-digit UTF-8 strings. Arbitrary binary content
    # (e.g. protobuf blobs in device-identity) is written as length-prefixed raw
    # bytes — never run through String.to_charlist, which raises on non-UTF-8.
    if String.valid?(str) and String.match?(str, ~r/^\d+$/) do
      write_packed_nibbles(str, buffer)
    else
      bytes = :binary.bin_to_list(str)
      buffer = write_byte_length(byte_size(str), buffer)
      buffer ++ bytes
    end
  end

  @spec write_packed_nibbles(String.t(), [non_neg_integer()]) :: [non_neg_integer()]
  defp write_packed_nibbles(str, buffer) do
    # Write NIBBLE_8 tag
    buffer = push_byte(Constants.tag(:nibble_8), buffer)

    # Calculate packed byte count (2 nibbles per byte)
    nibble_count = String.length(str)
    has_padding = rem(nibble_count, 2) != 0
    packed_byte_count = div(nibble_count + 1, 2)

    # Write start byte: highest bit = padding flag, lower 7 bits = packed byte count
    start_byte = if has_padding, do: 128 ||| packed_byte_count, else: packed_byte_count
    buffer = push_byte(start_byte, buffer)

    # Convert string digits to nibble-packed bytes
    digits = String.to_charlist(str)
    buffer = pack_nibbles(digits, buffer, has_padding)

    buffer
  end

  @spec pack_nibbles([char()], [non_neg_integer()], boolean()) :: [non_neg_integer()]
  defp pack_nibbles([], buffer, _), do: buffer

  defp pack_nibbles([d1], buffer, true) do
    # Odd length: pad final nibble with 0xF (Baileys packNibble('\0') = 15)
    byte = (d1 - ?0) <<< 4 ||| 0xF
    push_byte(byte, buffer)
  end

  defp pack_nibbles([d1, d2 | rest], buffer, has_padding) do
    # Pack two nibbles into one byte
    byte = (d1 - ?0) <<< 4 ||| d2 - ?0
    buffer = push_byte(byte, buffer)
    pack_nibbles(rest, buffer, has_padding)
  end

  @spec write_byte_length(non_neg_integer(), [non_neg_integer()]) :: [non_neg_integer()]
  defp write_byte_length(length, buffer) when length < 256 do
    buffer = push_byte(Constants.tag(:binary_8), buffer)
    push_byte(length, buffer)
  end

  defp write_byte_length(length, buffer) when length < 1_048_576 do
    buffer = push_byte(Constants.tag(:binary_20), buffer)
    push_int20(length, buffer)
  end

  defp write_byte_length(length, buffer) do
    buffer = push_byte(Constants.tag(:binary_32), buffer)
    push_int32(length, buffer)
  end

  @spec write_content(any(), [non_neg_integer()]) :: [non_neg_integer()]
  defp write_content(nil, buffer), do: buffer

  defp write_content(content, buffer) when is_binary(content) do
    write_string(content, buffer)
  end

  defp write_content(content, buffer) when is_list(content) do
    # Filter valid content items
    valid_content =
      Enum.filter(content, fn item ->
        case item do
          %Node{} -> true
          _ when is_binary(item) -> true
          _ -> false
        end
      end)

    buffer = write_list_start(length(valid_content), buffer)

    Enum.reduce(valid_content, buffer, fn item, acc ->
      case item do
        %Node{} -> encode_node_inner(item, acc)
        _ when is_binary(item) -> write_string(item, acc)
      end
    end)
  end

  # Helper functions for pushing bytes
  @spec push_byte(non_neg_integer(), [non_neg_integer()]) :: [non_neg_integer()]
  defp push_byte(value, buffer), do: buffer ++ [value &&& 0xFF]

  @spec push_int16(non_neg_integer(), [non_neg_integer()]) :: [non_neg_integer()]
  defp push_int16(value, buffer) do
    buffer ++ [value >>> 8 &&& 0xFF, value &&& 0xFF]
  end

  @spec push_int20(non_neg_integer(), [non_neg_integer()]) :: [non_neg_integer()]
  defp push_int20(value, buffer) do
    buffer ++ [value >>> 16 &&& 0x0F, value >>> 8 &&& 0xFF, value &&& 0xFF]
  end

  @spec push_int32(non_neg_integer(), [non_neg_integer()]) :: [non_neg_integer()]
  defp push_int32(value, buffer) do
    buffer ++ [value >>> 24 &&& 0xFF, value >>> 16 &&& 0xFF, value >>> 8 &&& 0xFF, value &&& 0xFF]
  end
end
