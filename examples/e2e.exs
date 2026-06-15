# Two-client e2e: boot two paired Amarula accounts that auto-respond to each
# other (plugin-driven), send one ping from primary, watch the round trip.
#
#   1. pair both first:  mix run examples/pair.exs primary
#                        mix run examples/pair.exs guest
#   2. run:              mix run examples/e2e.exs <primary_pn> <guest_pn>
#                        mix run examples/e2e.exs 5511999999999 5511999999999
#
# Expected (hands-off):
#   primary → guest:  "e2e ping"
#   guest   → primary: "ack: e2e ping"
#   primary → guest:  👍 + read   (terminal)

Code.require_file("examples/connection.ex")
Code.require_file("examples/e2e/plugins.ex")
Code.require_file("examples/e2e/harness.ex")

require Logger
alias Amarula.Examples.E2E.Harness

{primary_pn, guest_pn} =
  case System.argv() do
    [a, b] -> {a, b}
    _ -> raise ~s|usage: mix run examples/e2e.exs <primary_pn> <guest_pn>|
  end

# Profiles default to :default (your main account, already synced) and :guest,
# overridable via env: PRIMARY_PROFILE / GUEST_PROFILE.
primary_profile = System.get_env("PRIMARY_PROFILE", "default") |> String.to_atom()
guest_profile = System.get_env("GUEST_PROFILE", "guest") |> String.to_atom()

primary_addr = Harness.pn(primary_pn)
guest_addr = Harness.pn(guest_pn)

conns =
  Harness.start(
    primary_profile: primary_profile,
    guest_profile: guest_profile,
    primary_addr: primary_addr,
    guest_addr: guest_addr
  )

case Harness.await_open(conns, 60_000) do
  :ok ->
    Logger.info("both :open — sending one ping (then watch the auto round trip)")
    Harness.ping(conns, guest_addr, "e2e ping #{:rand.uniform(999)}")
    # Stay alive so the auto-conversation completes and is logged.
    Process.sleep(30_000)
    Logger.info("e2e window done")

  :timeout ->
    Logger.error("one or both connections didn't open — paired? run examples/pair.exs first")
end
