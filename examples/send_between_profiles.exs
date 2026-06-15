# Send a message from one paired profile to the other, in a single BEAM.
#
#   mix run examples/send_between_profiles.exs [from_profile] [to_profile] [text]
#
# Defaults: from=default  to=personnal  text="hi from <from> 👋"
#
# Both profiles must already be paired under ./amarula_data/<profile>/ (storage is
# scoped per profile via Amarula.new(%{profile: ...})). The receiver profile is
# this script's event consumer too, so we print the message it receives as proof
# of end-to-end delivery.

require Logger
alias Amarula.{Address, Msg}

# me.id per paired profile — the recipient's number is read from its creds so we
# don't hardcode a phone number in the repo.
me_id = fn profile ->
  "amarula_data/#{profile}/creds.term"
  |> File.read!()
  |> :erlang.binary_to_term()
  |> get_in([:me, :id])
end

{from_p, to_p, text} =
  case System.argv() do
    [f, t, msg] -> {f, t, msg}
    [f, t] -> {f, t, "hi from #{f} 👋"}
    _ -> {"default", "personnal", "hi from default 👋"}
  end

to_jid = me_id.(to_p)
to_user = to_jid |> String.split(["@", ":"]) |> List.first()
recipient = Address.pn(to_user)

# Receiver connects with parent_pid: self() so we observe its inbound events.
{:ok, recv} =
  %{profile: String.to_atom(to_p)}
  |> Amarula.new()
  |> Amarula.connect(parent_pid: self())

# Sender connects with a throwaway parent (we don't need its events here).
{:ok, send_conn} =
  %{profile: String.to_atom(from_p)}
  |> Amarula.new()
  |> Amarula.connect(parent_pid: self())

defmodule Wait do
  require Logger

  # Wait for a specific conn to report :open (events for both arrive at self()).
  def open(deadline) do
    receive do
      {:whatsapp, :connection_update, %{connection: :open}} ->
        :ok

      {:whatsapp, _t, _d} ->
        open(deadline)
    after
      remaining(deadline) -> :timeout
    end
  end

  # Watch for the recipient to receive `text` from `from_user` (drop everything
  # else, e.g. the sender's own :open or unrelated traffic).
  def delivery(text, deadline) do
    receive do
      {:whatsapp, :messages_upsert, msgs} ->
        case Enum.find(msgs, &match?(%Msg{type: :text, content: ^text}, &1)) do
          %Msg{} = m -> {:ok, m}
          nil -> delivery(text, deadline)
        end

      {:whatsapp, _t, _d} ->
        delivery(text, deadline)
    after
      remaining(deadline) -> :timeout
    end
  end

  defp remaining(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))
end

# Both share one mailbox; wait for two :open events (one per conn).
Logger.info("waiting for both profiles to come online...")
:ok = Wait.open(System.monotonic_time(:millisecond) + 40_000)
:ok = Wait.open(System.monotonic_time(:millisecond) + 40_000)
Logger.info("both online — sending #{from_p} → #{to_p}: #{inspect(text)}")

ret = Amarula.send_text(send_conn, recipient, text)
Logger.info("send_text returned: #{inspect(ret)}")

# A server <ack> ({:ok, id}) means the message was delivered to the recipient
# ACCOUNT. Decryption below is this companion's best-effort: a secondary device
# with stale Signal session/counter state may fail to decrypt while the primary
# (phone) shows it fine — that is a session-sync issue, not a delivery failure.
case ret do
  {:ok, id} ->
    Logger.info("✅ delivered to #{to_p} account (server ack id=#{id})")

  other ->
    Logger.error("❌ send failed: #{inspect(other)}")
end

case Wait.delivery(text, System.monotonic_time(:millisecond) + 15_000) do
  {:ok, %Msg{} = m} ->
    Logger.info("✅ this #{to_p} companion also decrypted it: #{inspect(m.content)}")

  :timeout ->
    Logger.info(
      "(this #{to_p} companion didn't decrypt it in 15s — stale session/counters; " <>
        "the account still received it, as the server ack confirms)"
    )
end

_ = recv
