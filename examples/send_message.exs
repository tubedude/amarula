# Send one WhatsApp message through the GenServer connection from connection.ex,
# then exit. Shows how a real app sends: start the supervised connection process,
# wait for it to come :open, call its API.
#
#   mix run examples/send_message.exs "<number-or-jid>" "<message>"
#
#   mix run examples/send_message.exs 5511999999999 "hello from amarula"
#   mix run examples/send_message.exs "120363000000000000@g.us" "hi group"
#
# A bare number becomes an %Amarula.Address{} PN; a full jid is parsed.
# Requires an already-paired ./amarula_data — run connection.ex to pair first.

Code.require_file("examples/connection.ex")

require Logger
alias Amarula.{Address, Examples.Connection}

{to, text} =
  case System.argv() do
    [to, text] -> {to, text}
    _ -> raise ~s|usage: mix run examples/send_message.exs "<number-or-jid>" "<message>"|
  end

# The send API accepts an %Address{} (or a plain jid string). Build an Address:
# a bare number → PN; anything with an @ is parsed to its kind (pn/lid/group).
address = if String.contains?(to, "@"), do: Address.parse(to), else: Address.pn(to)

# Start the connection process (the same one you'd put under a supervisor).
{:ok, conn} = Connection.start_link()

# Wait for it to reach :open, then send. Polling state/1 here keeps the example
# linear; a long-running app would just call send_text/3 whenever it needs to.
defmodule Wait do
  def until_open(_conn, 0), do: :timeout

  def until_open(conn, tries) do
    case Amarula.Examples.Connection.state(conn) do
      :open -> :ok
      _ -> Process.sleep(500) && until_open(conn, tries - 1)
    end
  end
end

case Wait.until_open(conn, 40) do
  :ok ->
    Logger.info("send_text → #{inspect(Connection.send_text(conn, address, text))}")
    # Give the server a moment to ack before the script exits.
    Process.sleep(3_000)

  :timeout ->
    Logger.error("Connection never opened (need pairing? run connection.ex) — exiting.")
end
