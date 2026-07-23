# Pitfalls & Diagnostics

Amarula speaks the real WhatsApp Web protocol, so the failures you hit are
WhatsApp's own — not a library abstraction's. This guide collects the non-obvious
ones: the failures that *look like success*. To get connected in the first place,
see the [Quick start](../README.md#quick-start); for the identity model behind
several of these traps, see [LID vs PN](LID_PN.md).

Only use accounts and contacts you are authorized to message — see the
[usage warning](../README.md) in the README.

## Validate a number, then send to the address the server returns

Use E.164 digits only — no `+`, spaces, parentheses, or hyphens. Check
availability with `Amarula.Contacts.on_whatsapp/2` and send to the `Address` it
returns, **not** to the string you typed: the server can canonicalize the number.

Brazilian mobile numbers are the classic trap — the "9th digit" may or may not be
part of the canonical address. Probe both forms and use whichever resolves:

```elixir
defmodule Number do
  alias Amarula.{Address, Contacts}

  # Try without the extra mobile "9" first, then with it.
  def resolve(conn) do
    ["551187654321", "5511987654321"]
    |> Enum.reduce_while({:error, :not_on_whatsapp}, fn candidate, _acc ->
      case Contacts.on_whatsapp(conn, candidate) do
        {:ok, [%{exists: true, address: %Address{} = address}]} ->
          {:halt, {:ok, address}}

        {:ok, _} ->
          {:cont, {:error, :not_on_whatsapp}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
end
```

Both forms can resolve to the *same* canonical address, so don't assume the
9-digit input is the JID used on send. Always send to the `Address` returned by
`on_whatsapp/2`.

## `{:ok, message_id}` means accepted, not read

`Amarula.send_text/3` returning `{:ok, message_id}` means the **server accepted**
the message — not that the recipient received or read it. Delivery and read
status arrive later as `:receipt_update` events.

## Send only after `connection: :open`

Don't send before the `{:amarula, :connection_update, %{connection: :open}}`
event fires. Sending during pairing or the handshake can fail outright or leave
an incomplete session.

## `{:error, {:send_rejected, "463"}}` — the first 1:1 to a new contact

WhatsApp gates a device's **first** 1:1 message to a contact behind an anti-spam
"trusted contact" check. Until that trust exists, the socket accepts your frame
but the server rejects it at the application layer with ack error `463`
(`MessageAccountRestriction`). This surfaces **only** in the return value of
`send_text/3`, as `{:error, {:send_rejected, "463"}}` — never as a socket-level
error, so it's invisible unless you inspect the result.

Do **not** retry in a loop: each extra attempt can worsen the restriction. Wait
for a legitimate interaction from the contact — a message from them to you
establishes the trust — then send. Trust is per-identity, so see
[LID vs PN](LID_PN.md) for how one contact appears under both a phone number and
a LID.

## PN, LID, and sessions — don't hand-build identities

A phone number (PN) and a LID are two identities for the *same* contact. Never
construct a LID by hand. Amarula learns the PN↔LID mapping during USync and
resolves Signal sessions on the LID when needed. To reply to an inbound message,
reuse `msg.channel` rather than reassembling a number from parts. The full model
is in [LID vs PN](LID_PN.md).

## History is delivered, not stored

`{:amarula, :messages_upsert, ...}` hands messages to your consumer process, but
Amarula keeps no conversation archive of its own. If you need search, history, or
an audit trail, persist the events into your own storage.

## Examples are for development; production is supervised

The scripts under `examples/` (e.g. `mix run examples/pair.exs guest`) are for
local development. In production, keep a **supervised** connection, register a
process to receive the `{:amarula, …}` events, and own reconnection and telemetry
in your app. Never expose the contents of `amarula_data/` — the per-profile
credentials and Signal sessions — in logs, container images, or support tickets.
