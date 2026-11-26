# Does live WhatsApp Web define top-level Message fields our proto lacks?
#
#   scripts/extract_proto.sh /tmp/wa.proto
#   mix run --no-start scripts/check_proto_drift.exs /tmp/wa.proto
#
# Exits 1 when it finds new fields: those message types decode to `:other` until
# the proto is regenerated (see CLAUDE.md).

[path] = System.argv()

# Field names declared directly in `message Message { ... }` (not nested types).
live =
  path
  |> File.read!()
  |> String.split("\n")
  |> Enum.reduce({nil, MapSet.new()}, fn line, {depth, acc} ->
    opens = line |> String.graphemes() |> Enum.count(&(&1 == "{"))
    closes = line |> String.graphemes() |> Enum.count(&(&1 == "}"))

    cond do
      depth == nil and line =~ ~r/^message Message \{/ ->
        {1, acc}

      depth == 1 ->
        acc =
          case Regex.run(~r/^\s+(?:optional |repeated )?[\w.]+ (\w+) = \d+;/, line) do
            [_, name] -> MapSet.put(acc, name)
            nil -> acc
          end

        {if(depth + opens - closes == 0, do: :done, else: depth + opens - closes), acc}

      is_integer(depth) ->
        {depth + opens - closes, acc}

      true ->
        {depth, acc}
    end
  end)
  |> elem(1)

ours =
  Amarula.Protocol.Proto.Message.__message_props__().field_props
  |> Map.values()
  |> MapSet.new(&to_string(&1.name))

case live |> MapSet.difference(ours) |> Enum.sort() do
  [] ->
    IO.puts("Proto is current: no new top-level Message fields (#{MapSet.size(live)} live).")

  new ->
    IO.puts("Live WhatsApp Web has #{length(new)} Message field(s) we lack:")
    Enum.each(new, &IO.puts("  #{&1}"))
    System.halt(1)
end
