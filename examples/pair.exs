# Pair (link) a WhatsApp account to a named profile by scanning a QR.
#
#   mix run examples/pair.exs <profile>
#   mix run examples/pair.exs guest
#
# Prints the QR in the terminal (also /tmp/whatsapp_qr.txt). Scan it with the
# phone you want to link. Creds persist under amarula_data/<profile>/, so later
# runs (e2e, send_message) reuse them without re-pairing. If the profile is
# already paired this just connects and exits.

Code.require_file("examples/connection.ex")

require Logger
alias Amarula.Examples.Connection

profile =
  case System.argv() do
    [p] -> String.to_atom(p)
    _ -> raise ~s|usage: mix run examples/pair.exs <profile>  (e.g. guest)|
  end

Logger.info("Pairing profile #{inspect(profile)} — scan the QR with the target phone.")
{:ok, conn} = Connection.start_link(profile: profile)

# Pairing is multi-phase: QR scan → pairing_success → stream-error 515 →
# reconnect → login → :open → history-sync (chat list arrives, phone goes
# active). Pairing is DONE when the history-sync lands — a real state signal, not
# a timer. Wait for it, then exit. (180s cap is just a give-up bound, not the
# success path.)
deadline = System.monotonic_time(:millisecond) + 180_000

wait = fn wait ->
  cond do
    Connection.synced?(conn) ->
      :synced

    System.monotonic_time(:millisecond) > deadline ->
      :timeout

    true ->
      Process.sleep(500)
      wait.(wait)
  end
end

case wait.(wait) do
  :synced ->
    Logger.info("✅ Profile #{inspect(profile)} paired + synced. Creds under amarula_data/#{profile}/.")
    # Brief grace for the final creds_update to persist.
    Process.sleep(1000)

  :timeout ->
    Logger.error("Timed out before history-sync — scan faster, or check the logs.")
end
