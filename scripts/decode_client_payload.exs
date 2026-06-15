#!/usr/bin/env elixir

# Script to decode and compare ClientPayload protobufs from Baileys and Amarula logs

Mix.install([
  {:protobuf, "~> 0.12"}
])

# Baileys ClientPayload (from logs)
baileys_hex = "18002a36080e120b080210b81718ed9394ea031a0330303022033030302a03302e313a074465736b746f704203302e3150005a02656e6202555332022000600168019a01d4010a04679af4e31201051a20526f4e041129b2243738f27987e351103513ee6b103963649bd7217c3c83dc7c22030000012a20788869257b1be4205273265cb4ad92040f90f08f561ab7defc56fe3c899aa18132403fa4612892651534f01ef9f436d84de9d17637c75d42a7571cf1ae2088ff9c45a75645fb0bf04ca8d84502f2f03ef09b1362913fd0fe87a6d0bb45b1a9505109"

# Amarula ClientPayload (from logs)
amarula_hex = "2a340a0b080210b81718ed9394ea03100b2203302e312a074465736b746f703203302e313a02656e42033030304a03303030520255533200600168019a01b0010a1054bb0d4e84a27cb53abb2633273c170812280a064d6163204f531007221408bede22100120012801300138014001480150012a06080a100f18071a046e33"

IO.puts("=" <> String.duplicate("=", 80))
IO.puts("DECODING CLIENTPAYLOAD PROTOBUFS")
IO.puts("=" <> String.duplicate("=", 80))

baileys_bytes = Base.decode16!(baileys_hex, case: :lower)
amarula_bytes = Base.decode16!(amarula_hex, case: :lower)

IO.puts("\n📊 SIZE COMPARISON:")
IO.puts("Baileys: #{byte_size(baileys_bytes)} bytes")
IO.puts("Amarula: #{byte_size(amarula_bytes)} bytes")
IO.puts("Difference: #{byte_size(baileys_bytes) - byte_size(amarula_bytes)} bytes")

IO.puts("\n" <> String.duplicate("-", 80))
IO.puts("PROTOBUF FIELD ANALYSIS")
IO.puts(String.duplicate("-", 80))

# Protobuf wire format analysis
# Each field is: (field_number << 3) | wire_type | value

IO.puts("\n📋 BAILEYS PROTOBUF STRUCTURE:")
IO.puts("First 64 bytes hex: #{Base.encode16(:binary.part(baileys_bytes, 0, min(64, byte_size(baileys_bytes))), case: :lower)}")
IO.puts("\nField breakdown:")

# Decode fields manually (simplified)
analyze_protobuf_fields(baileys_bytes, "Baileys")

IO.puts("\n📋 AMARULA PROTOBUF STRUCTURE:")
IO.puts("First 64 bytes hex: #{Base.encode16(:binary.part(amarula_bytes, 0, min(64, byte_size(amarula_bytes))), case: :lower)}")
IO.puts("\nField breakdown:")

analyze_protobuf_fields(amarula_bytes, "Amarula")

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("FIELD-BY-FIELD COMPARISON")
IO.puts("=" <> String.duplicate("=", 80))

IO.puts("""
According to ClientPayload.proto:
- Field 1: username (uint64)
- Field 3: passive (bool)
- Field 5: userAgent (UserAgent message)
- Field 6: webInfo (WebInfo message)
- Field 7: pushName (string)
- Field 9: sessionId (sfixed32)
- Field 10: shortConnect (bool)
- Field 12: connectType (ConnectType enum)
- Field 13: connectReason (ConnectReason enum)
- Field 14: shards (repeated int32)
- Field 18: device (uint32)
- Field 19: devicePairingData (DevicePairingRegistrationData message)
- Field 33: pull (bool)
- Field 41: lidDbMigrated (bool)
""")

defp analyze_protobuf_fields(bytes, label) do
  # Simplified protobuf field decoder
  IO.puts("\n#{label} protobuf fields (first 100 bytes):")
  decode_protobuf_fields(bytes, 0, 0, 100)
end

defp decode_protobuf_fields(<<>>, _offset, _field_count, _max_bytes), do: :ok
defp decode_protobuf_fields(_bytes, offset, _field_count, max_bytes) when offset >= max_bytes, do: :ok

defp decode_protobuf_fields(<<varint::unsigned-little-integer-size(1), rest::binary>>, offset, field_count, max_bytes) do
  field_number = varint >>> 3
  wire_type = varint &&& 0x07

  {value_size, value_bytes} = case wire_type do
    0 ->
      # Varint - need to decode full varint
      case decode_varint(rest, 0, 0) do
        {value, remaining} -> {1, <<value::unsigned-little-integer-size(1)>>}
      end
    1 ->
      # Fixed64 - 8 bytes
      if byte_size(rest) >= 8, do: {8, :binary.part(rest, 0, 8)}, else: {0, <<>>}
    2 ->
      # Length-delimited - first varint is length
      case decode_varint(rest, 0, 0) do
        {length, _} when length > 0 and byte_size(rest) > 1 ->
          len_bytes = :binary.part(rest, 1, min(length + 1, byte_size(rest) - 1))
          {min(length + 1, byte_size(rest)), len_bytes}
        _ -> {1, :binary.part(rest, 0, min(1, byte_size(rest)))}
      end
    5 ->
      # Fixed32 - 4 bytes
      if byte_size(rest) >= 4, do: {4, :binary.part(rest, 0, 4)}, else: {0, <<>>}
    _ ->
      {1, :binary.part(rest, 0, min(1, byte_size(rest)))}
  end

  field_name = case field_number do
    1 -> "username"
    3 -> "passive"
    5 -> "userAgent ⭐"
    6 -> "webInfo ⭐"
    7 -> "pushName"
    9 -> "sessionId"
    10 -> "shortConnect"
    12 -> "connectType"
    13 -> "connectReason"
    14 -> "shards"
    18 -> "device"
    19 -> "devicePairingData ⭐"
    33 -> "pull"
    41 -> "lidDbMigrated"
    _ -> "field_#{field_number}"
  end

  wire_type_name = case wire_type do
    0 -> "varint"
    1 -> "fixed64"
    2 -> "length-delimited"
    5 -> "fixed32"
    _ -> "wire_#{wire_type}"
  end

  value_preview = case value_bytes do
    <<>> -> ""
    val when byte_size(val) > 0 ->
      preview = if byte_size(val) <= 16 do
        Base.encode16(val, case: :lower)
      else
        Base.encode16(:binary.part(val, 0, 16), case: :lower) <> "..."
      end
      " (#{preview})"
  end

  IO.puts("  Field #{field_number} (#{field_name}): wire_type=#{wire_type_name}, size=#{value_size}#{value_preview}")

  # Continue decoding
  remaining_offset = offset + 1 + value_size
  remaining_bytes = :binary.part(bytes, remaining_offset, byte_size(bytes) - remaining_offset)

  if remaining_offset < max_bytes and byte_size(remaining_bytes) > 0 do
    decode_protobuf_fields(remaining_bytes, remaining_offset, field_count + 1, max_bytes)
  end
end

defp decode_varint(<<byte::unsigned-integer-size(8), rest::binary>>, value, shift) when byte &&& 0x80 == 0 do
  final_value = value ||| (byte <<< shift)
  {final_value, rest}
end

defp decode_varint(<<byte::unsigned-integer-size(8), rest::binary>>, value, shift) do
  new_value = value ||| ((byte &&& 0x7F) <<< shift)
  decode_varint(rest, new_value, shift + 7)
end

defp decode_varint(<<>>, value, _shift), do: {value, <<>>}

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("KEY DIFFERENCES")
IO.puts("=" <> String.duplicate("=", 80))

IO.puts("""
Looking at the hex prefixes:

Baileys:  18002a36080e120b080210b81718ed9394ea03...
Amarula:  2a340a0b080210b81718ed9394ea03100b2203...

The first few fields appear to differ. Let's check if the protobuf library
can decode these properly to see field values.
""")
