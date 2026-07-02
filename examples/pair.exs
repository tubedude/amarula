# Pair (link) a WhatsApp account to a named profile — by QR code or phone code.
#
#   # QR: prints a scannable QR in the terminal
#   mix run examples/pair.exs <profile>
#   mix run examples/pair.exs guest
#
#   # Phone code: prints an 8-char code you type into WhatsApp instead of scanning
#   mix run examples/pair.exs <profile> <phone-e164>
#   mix run examples/pair.exs guest 5511999999999
#
# QR: scan it with the phone you want to link (WhatsApp → Linked Devices → Link a
# device). Phone code: on the phone, WhatsApp → Linked Devices → "Link with phone
# number instead", then type the 8-char code this prints. Both paths link the same
# way; the phone code is handy when you can't scan a screen (headless/CI, a remote
# box, or a consumer like jido_chat driving pairing programmatically).
#
# Creds persist under amarula_data/<profile>/, so later runs (e2e, send_message)
# reuse them without re-pairing. If the profile is already paired this just
# connects and exits.

Code.require_file("examples/connection.ex")

require Logger
alias Amarula.Examples.Connection

{profile, phone} =
  case System.argv() do
    [p] ->
      {String.to_atom(p), nil}

    [p, phone] ->
      digits = String.replace(phone, ~r/\D/, "")

      if digits == "",
        do: raise(~s|phone must be E.164 digits, e.g. 5511999999999|)

      {String.to_atom(p), digits}

    _ ->
      raise ~s|usage: mix run examples/pair.exs <profile> [phone-e164]  (e.g. guest 5511999999999)|
  end

# Phone-code pairing is opt-in via `pairing: {:phone, digits}`: the Connection
# GenServer then requests a link-code on the first QR window and prints it, instead
# of rendering the QR (see examples/connection.ex).
start_opts = [profile: profile]
start_opts = if phone, do: Keyword.put(start_opts, :pairing, {:phone, phone}), else: start_opts

if phone do
  Logger.info("Pairing profile #{inspect(profile)} by phone code for +#{phone} — watch for the 8-char code below.")
else
  Logger.info("Pairing profile #{inspect(profile)} — scan the QR with the target phone.")
end

{:ok, conn} = Connection.start_link(start_opts)

# Pairing is multi-phase: link (QR scan / phone code entered) → pairing_success →
# stream-error 515 → reconnect → login → :open → history-sync (chat list arrives,
# phone goes active). Pairing is DONE when the history-sync lands — a real state
# signal, not a timer. Wait for it, then exit. (180s cap is just a give-up bound,
# not the success path.)
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
    Logger.error("Timed out before history-sync — link faster, or check the logs.")
end
