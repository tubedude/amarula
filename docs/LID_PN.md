# LID vs PN — identity in Amarula

WhatsApp gives every person **two addresses for the same human**:

- **PN** — `<number>@s.whatsapp.net` — their **phone number**. The old, public identity.
- **LID** — `<id>@lid` — a **privacy "Linked ID"**. An opaque handle that doesn't
  leak the phone number.

Same person, two names. WhatsApp is migrating to LID so people can talk without
exposing numbers. Both can show up on the wire for one contact.

In code these are the two `:kind`s of an `Amarula.Address` (`:pn` / `:lid`), the
third being `:group`.

## First, what's a JID?

A **JID** ("Jabber ID") is the raw wire string WhatsApp speaks:
`user@server`, optionally carrying a device and/or agent:

```
5511999998888@s.whatsapp.net      a PN, account-level
5511999998888:3@s.whatsapp.net    the same PN, device 3
20000000001@lid                   a LID, account-level
120363000000000001@g.us           a group
```

- **server** picks the identity kind: `s.whatsapp.net` → PN, `lid` → LID,
  `g.us` → group (plus `c.us`, `broadcast`, … for special jids).
- **device** is one client of the account. **Device 0 (and "no device") emit no
  suffix** — a `user:0@…` jid is malformed and the server silently ignores it
  (e.g. prekey-bundle fetches). Account-level = no device.

`Amarula.Address` is the **parsed, friendly form** of a JID, and it's what the
public API and events speak. `Address.parse/1` turns a jid string into an
`Address`; `Address.to_jid/1` turns it back. Under the hood the protocol still
speaks jid strings; the API also accepts a raw string and parses it for you.

An `Address` is **parsed-only** — a pure value carrying just `user` + `kind` +
`device`. It does **not** carry resolved data: a PN's LID, a group's members, a
device list. Those need connection state and change over time, so they stay
internal. Don't expect `Address.pn(...)` to "know" its LID.

## The one rule: **LID > PN**

When we have a LID↔PN mapping for someone, **their cryptographic identity is the
LID**. Concretely, Amarula stores the Signal session and fetches prekey bundles
under the **LID address**, not the PN — even when the app is addressing them by
phone number.

Why this matters (and isn't optional):

- The server **serves prekey bundles keyed by LID** for lid-mapped users. Ask for
  a PN bundle and you get **silence** — the request just goes unanswered.
- Inbound messages from that person arrive under their **LID** Signal address. If
  we *sent* under the PN address, we'd build a second, divergent session and the
  ratchets desync — undecryptable messages on one or both ends.

So we pick one identity for the crypto, and the server forces the choice: **LID
wins whenever a mapping exists.** `LidMappingFileStore.signal_address/2` is the
chokepoint — give it any jid, it returns the LID-based Signal address if mapped,
else the plain PN one.

## The gotcha: storage is LID, **the wire stays PN**

This trips people up, so hold both ideas at once:

| Layer                       | Address used                                     |
| --------------------------- | ------------------------------------------------ |
| **Signal session storage**  | LID (when mapped) — e.g. `20000000001_1.0`       |
| **Prekey bundle fetch**     | LID (when mapped) — server requires it           |
| **Wire `<to jid>`**         | whatever you addressed (PN if you sent to a PN)  |

You message `5511…@s.whatsapp.net`. The `<participants><to jid="…@s.whatsapp.net">`
on the wire **stays that PN device jid** — that's the addressing the server expects
from a sender. But the ciphertext inside was encrypted with the session stored
under the **LID**. Wire identity ≠ crypto identity, and that's correct, not a bug.

`send_flow_test.exs` pins exactly this: the session lives at the LID address while
`<to>` is still the PN.

## Where the mapping comes from

We don't invent LIDs — we **learn** the pairing and persist it
(`LidMappingFileStore.store_mappings/2`, which also reports which pairs are *new*
so we can force-refresh those sessions):

1. **USync device queries** — the `:lid` protocol returns `<lid val="…">` next to a
   contact's devices.
2. **Group metadata** — participants carry the cross-mapped half (`lid` on a PN id,
   `phone_number` on a LID id).
3. **Explicit lookup** — `Amarula.Contacts.resolve_lid/2` runs a USync purely to
   fetch + store the mapping.

Newly-learned pairs are surfaced to the consumer as a `:lid_mapping_update` event.

## How a consumer should keep them

Amarula owns the *crypto* identity choice (LID > PN, internally). But **you** decide
how to key your own contacts/chats/DB — and the duality has two traps:

**1. Key by the account, not the device.** Strip the device with
`Address.normalize/1` before using an address as a map/DB key. Devices are
ephemeral plumbing (a person adds/drops linked devices); the account is the stable
unit.

**2. PN and LID do *not* compare equal.** `Address.same_account?/2` matches on
`user` **and** `kind`, so `…@s.whatsapp.net` and `…@lid` for the *same human* are
**not** the same account. Address equality alone will never unify them — **only the
mapping does.** If you dedupe people by Address equality, one contact will show up
twice.

So, the recommended shape:

- **Subscribe to `:lid_mapping_update`** and keep your own PN↔LID union (a small
  two-way table, or union-find). When a pairing arrives, **merge** the two records
  into one person. You can also pull mappings on demand with
  `Amarula.Contacts.resolve_lid/2`.
- **Pick the LID as the canonical key once you know it** — it's where the crypto
  identity lives and where the platform is heading. Keep the PN as a display value
  / lookup alias. Until a LID is known, key by PN and re-point (or alias) to the
  LID when the mapping lands.
- **Store the account-level (device-stripped) address.** Don't persist a
  device-suffixed jid as an identity, and don't try to derive one identity from the
  other — they're opaque to each other without the mapping.
- **Don't assume a contact has only one.** A person may surface as PN-only,
  LID-only, or both over time; your model should tolerate learning the second half
  later and stitching them together.

## Mental model

> A contact has a public name (PN) and a private name (LID). You may *call* them by
> either, and the envelope keeps the name you used — but their **identity for
> encryption is always the LID once you know it**, because that's the one the server
> hands out keys for and the one they encrypt back with.

## Key code pointers

| Concept                          | File                                                          |
| -------------------------------- | ------------------------------------------------------------ |
| Address kinds (`:pn`/`:lid`)     | `lib/amarula/address.ex`                                      |
| Mapping store API                | `lib/amarula/protocol/signal/lid_mapping_file_store.ex`       |
| LID-priority session injection   | `lib/amarula/protocol/signal/session_injector.ex`            |
| LID-priority encrypt + storage   | `lib/amarula/protocol/messages/conversation_sender.ex`       |
| Group metadata cross-mapping     | `lib/amarula/protocol/groups/metadata.ex`                    |
| Explicit resolve & store         | `lib/amarula/contacts.ex`                                     |
| Wire-vs-storage assertions       | `test/protocol/socket/send_flow_test.exs`                    |
