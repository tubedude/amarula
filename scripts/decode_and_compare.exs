#!/usr/bin/env elixir

# Decode and compare ClientPayload from Baileys and Amarula logs

# From Baileys logs (line 15, clientPayload hex):
baileys_hex = "18002a36080e120b080210b81718ed9394ea031a0330303022033030302a03302e313a074465736b746f704203302e3150005a02656e6202555332022000600168019a01d4010a04679af4e31201051a20526f4e041129b2243738f27987e351103513ee6b103963649bd7217c3c83dc7c22030000012a20788869257b1be4205273265cb4ad92040f90f08f561ab7defc56fe3c899aa18132403fa4612892651534f01ef9f436d84de9d17637c75d42a7571cf1ae2088ff9c45a75645fb0bf04ca8d84502f2f03ef09b1362913fd0fe87a6d0bb45b1a9505109"

# From Amarula logs (line 300):
amarula_hex = "2a340a0b080210b81718ed9394ea03100b2203302e312a074465736b746f703203302e313a02656e42033030304a033030305202555332020803600168019a01b2010a1054bb0d4e84a27cb53abb2633273c1708122a0a064d6163204f5310071801221408bede22100120012801300138014001480150012a06080a100f18071a04054c21712201052a20a29d610c374095f4e2814f8337839c46d455211feb0e14c363f1ff9b7c199c4632030009273a205ab023bcbd8ec659a5451b50d77fdbd6b717b1ad3029464f10615527fb3a5b0b4220a3092b8b82cfcec5a6a505189aa83920fc8500e64dd87de911f31ea3ad81020c"

IO.puts("=" <> String.duplicate("=", 80))
IO.puts("CLIENTPAYLOAD FIELD-BY-FIELD COMPARISON")
IO.puts("=" <> String.duplicate("=", 80))

IO.puts("\n📊 SIZES:")
IO.puts("Baileys: #{byte_size(Base.decode16!(baileys_hex, case: :lower))} bytes")
IO.puts("Amarula: #{byte_size(Base.decode16!(amarula_hex, case: :lower))} bytes")

IO.puts("\n📋 FIELD ANALYSIS:")
IO.puts("\nAccording to ClientPayload.proto field numbers:")
IO.puts("1 = username")
IO.puts("3 = passive")
IO.puts("5 = userAgent")
IO.puts("6 = webInfo")
IO.puts("7 = pushName")
IO.puts("9 = sessionId")
IO.puts("10 = shortConnect")
IO.puts("12 = connectType")
IO.puts("13 = connectReason")
IO.puts("14 = shards (repeated)")
IO.puts("18 = device")
IO.puts("19 = devicePairingData")
IO.puts("33 = pull")
IO.puts("41 = lidDbMigrated")

IO.puts("\n🔍 HEX PREFIX ANALYSIS:")
IO.puts("\nBaileys starts: #{String.slice(baileys_hex, 0, 40)}...")
IO.puts("Amarula starts: #{String.slice(amarula_hex, 0, 40)}...")

IO.puts("\nKey difference: Baileys starts with '1800' (field 3=passive)")
IO.puts("Amarula starts with '2a34' (field 5=userAgent)")

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("CONCLUSION")
IO.puts("=" <> String.duplicate("=", 80))

IO.puts("""
The protobuf field ordering is different:

Baileys order: 3(passive) -> 5(userAgent) -> 6(webInfo) -> 19(devicePairingData) -> 33(pull) -> 12(connectType) -> 13(connectReason)
Amarula order: 5(userAgent) -> 6(webInfo) -> 19(devicePairingData) -> 33(pull) -> 12(connectType) -> 13(connectReason)

Amarula is missing field 3 (passive=false) at the start.

However, protobuf encoding order shouldn't matter for correctness - the server should decode
both correctly. But the 41-byte size difference suggests there might be other missing fields
or different encoding of nested messages.

The key question: Does Baileys' `fromObject()` add default values that Amarula's direct
struct encoding is missing?
""")
