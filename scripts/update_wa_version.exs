#!/usr/bin/env elixir

# Fetch the current live WhatsApp Web protocol version and rewrite the pinned
# literal in the source, so a maintainer can review the diff and commit it.
#
# Usage:
#   mix run scripts/update_wa_version.exs          # fetch + rewrite the source literals
#   mix run scripts/update_wa_version.exs --check   # print live vs pinned, change nothing
#
# WhatsApp bumps this version periodically; a stale value silently breaks new-device
# pairing (see docs / CLAUDE.md "WhatsApp Version"). This is a maintainer tool — the
# running library never fetches the version itself.

require Logger

files = [
  "lib/amarula/config.ex",
  "lib/amarula/protocol/crypto/constants.ex"
]

# Group digits into underscore-separated thousands, matching the source style
# (e.g. 1042537629 -> "1_042_537_629").
group = fn n ->
  n
  |> Integer.to_string()
  |> String.reverse()
  |> String.replace(~r/(\d{3})(?=\d)/, "\\1_")
  |> String.reverse()
end

check_only? = "--check" in System.argv()

# Fetch the live version from WhatsApp Web's own service worker (the `client_revision`
# field), mirroring Baileys' fetchLatestWaWebVersion(). Inlined here because this
# maintainer script is its only caller — the running library never fetches.
fetch_latest = fn ->
  headers = [
    {"sec-fetch-site", "none"},
    {"user-agent",
     "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"}
  ]

  case Req.get("https://web.whatsapp.com/sw.js",
         headers: headers,
         decode_body: false,
         retry: false
       ) do
    {:ok, %{status: 200, body: body}} when is_binary(body) ->
      # `client_revision` appears JSON-escaped in the bundle (\"client_revision\":123).
      case Regex.run(~r/\\?"client_revision\\?":\s*(\d+)/, body, capture: :all_but_first) do
        [rev] -> {:ok, [2, 3000, String.to_integer(rev)]}
        nil -> {:error, :revision_not_found}
      end

    {:ok, %{status: status}} ->
      {:error, {:http, status}}

    {:error, reason} ->
      {:error, reason}
  end
end

case fetch_latest.() do
  {:ok, [2, 3000, rev] = live} ->
    pinned = Amarula.Config.wa_version()
    IO.puts("live:   #{inspect(live)}")
    IO.puts("pinned: #{inspect(pinned)}")

    cond do
      live == pinned ->
        IO.puts("\nAlready up to date — nothing to change.")

      check_only? ->
        IO.puts("\nOut of date. Re-run without --check to rewrite the source literals.")

      true ->
        new_literal = "@wa_version [2, 3000, #{group.(rev)}]"

        Enum.each(files, fn path ->
          src = File.read!(path)
          updated = Regex.replace(~r/@wa_version \[2, 3000, [\d_]+\]/, src, new_literal)

          if updated == src do
            Logger.warning("no @wa_version literal found (or already current) in #{path}")
          else
            File.write!(path, updated)
            IO.puts("updated #{path} -> #{new_literal}")
          end
        end)

        IO.puts("\nDone. Review the diff (git diff), update CLAUDE.md if desired, then commit.")
    end

  {:ok, other} ->
    IO.puts(:stderr, "Unexpected version shape from WhatsApp: #{inspect(other)}")
    System.halt(1)

  {:error, reason} ->
    IO.puts(:stderr, "Failed to fetch live version: #{inspect(reason)}")
    System.halt(1)
end
