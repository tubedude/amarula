# LID vs PN — Identity in Amarula

WhatsApp gives every person **two addresses for the same human**:

- **PN** — `<number>@s.whatsapp.net` — their **phone number**. The old, public identity.
- **LID** — `<id>@lid` — a **privacy "Linked ID"**. An opaque handle that doesn't
  leak the phone number.

Same person, two names. WhatsApp is migrating to LID so people can talk without
exposing numbers. Both can show up on the wire for one contact.

In code, `:pn` and `:lid` are two of `Amarula.Address`'s four `:kind`s. The other
two are `:group` (a group chat) and `:none` (the empty address — "no identity",
returned instead of `nil`).

## First, What's a JID?

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

## The One Rule: LID > PN

When we have a LID↔PN mapping for someone, **their cryptographic identity is the
LID**. Amarula stores the Signal session and fetches prekey bundles under the
**LID address**, not the PN — even when the app is addressing them by phone
number.

Why:

- The server **serves prekey bundles keyed by LID** for lid-mapped users. Ask for
  a PN bundle and you get **silence** — the request just goes unanswered.
- Inbound messages from that person arrive under their **LID** Signal address. If
  we *sent* under the PN address, we'd build a second, divergent session and the
  ratchets desync — undecryptable messages on one or both ends.

So we pick one identity for the crypto, and the server forces the choice: **LID
wins whenever a mapping exists.** `LidMappingFileStore.signal_address/2` is the
chokepoint — give it any jid, it returns the LID-based Signal address if mapped,
else the plain PN one.

## The Gotcha: Envelope vs. Lock

Think of an outgoing message as a **letter**:

- **The envelope** — the wire `<to jid>` — carries the name you *addressed*. If you
  sent to `5511…@s.whatsapp.net`, the envelope stays that **PN**. That's the
  addressing the server routes on.
- **The lock inside** — the Signal session that encrypted the ciphertext — is keyed
  to the person's **crypto identity**, which is the **LID** once a mapping exists.

So one packet leaves with a **PN on the envelope** but its contents were sealed with
the **LID's** keys. This split is deliberate, not a bug:

| Layer                       | Address used                                     |
| --------------------------- | ------------------------------------------------ |
| **Wire `<to jid>`** (envelope) | whatever you addressed (PN if you sent to a PN) |
| **Signal session storage** (lock) | LID (when mapped) — e.g. `20000000001_1.0`  |
| **Prekey bundle fetch** (lock) | LID (when mapped) — server requires it         |

The actual read-modify-write of a session record — on both the send side
(`ConversationSender`) and the receive side (`Connection`/`MessageDecryptor`) — is
serialized per-record through `SessionCustodian`, so a concurrent send and receive
to the same contact can't race on the ratchet. See
[`docs/INFRASTRUCTURE.md`](INFRASTRUCTURE.md#session-custody) for how that lock
works; this document only covers which address (PN or LID) a given layer uses.

`send_flow_test.exs` pins exactly this: the session lives at the LID address while
`<to>` is still the PN.

## What You Have to Keep to Address Properly (the 400)

Amarula picks the *lock* (LID) for you. **You** are responsible for the *envelope* —
and the envelope must be a **PN for a DM**. This is the part that bites:

> **Address DMs by PN. Never send a DM straight to a raw `@lid`.**

Why: to encrypt, Amarula first has to resolve the recipient's **devices**, and
WhatsApp's device directory (USync) is **keyed by phone number**. Hand it a bare
LID and the lookup gets **no answer** — you'll see a USync timeout, or the server
rejecting the request as a **400 / bad-request**, and the send fails before any
ciphertext is built. (Groups sidestep this: group metadata hands you each member's
PN to look up with.)

So the one thing to **keep** is the **PN↔LID mapping**, so you can turn a LID back
into a sendable PN:

- You often only *have* a LID — e.g. a `:messages_upsert` from a **group member**
  arrives under their LID. You can't DM that LID directly.
- Translate it first: `Amarula.Contacts.pn_for_lid(conn, lid)` returns the PN
  **if the profile has learned the mapping**. Send to *that* PN.
- If it returns `nil`, the profile never learned the pairing — populate it once with
  `Amarula.Contacts.resolve_lid(conn, [phone])` (a USync), or wait for a
  `:lid_mapping_update`, then retry. **Sending before the mapping exists is exactly
  the 400 you hit.**

In short: the LID is for reading identity and for the crypto Amarula handles
internally; the **PN is what you put on the envelope**. Keep the mapping so you can
always get back to a PN.

## Where the Mapping Comes From

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

## How a Consumer Should Keep Them

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

## Mental Model

> A contact has a public name (PN) and a private name (LID). You may *call* them by
> either, and the envelope keeps the name you used — but their **identity for
> encryption is always the LID once you know it**, because that's the one the server
> hands out keys for and the one they encrypt back with.

## Key Code Pointers

| Concept                          | File                                                          |
| -------------------------------- | ------------------------------------------------------------ |
| Address kinds (`:pn`/`:lid`/`:group`/`:none`) | `lib/amarula/address.ex`                         |
| Mapping store API                | `lib/amarula/protocol/signal/lid_mapping_file_store.ex`       |
| LID-priority session injection   | `lib/amarula/protocol/signal/session_injector.ex`            |
| LID-priority encrypt (resolves the address, then hands off to the session lock) | `lib/amarula/protocol/messages/conversation_sender.ex` |
| Per-record session lock (send + receive) | `lib/amarula/protocol/signal/session_custodian.ex`     |
| Group metadata cross-mapping     | `lib/amarula/protocol/groups/metadata.ex`                    |
| Explicit resolve & store         | `lib/amarula/contacts.ex`                                     |
| Wire-vs-storage assertions       | `test/protocol/socket/send_flow_test.exs`                    |
