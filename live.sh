#!/usr/bin/env bash
# Start an IEx session with Live loaded + connected, then drop to the prompt.
#
#   ./live.sh
#   iex> Live.send("120363....@g.us", "oi")     # group
#   iex> Live.send("5511999999999", "oi")        # 1:1
#   iex> Live.state()
#
# Reuses ./amarula_auth (QR only if unpaired). AMARULA_LOG_LEVEL=debug for more.
cd "$(dirname "$0")" || exit 1
exec iex --dot-iex examples/live_iex.exs -S mix
