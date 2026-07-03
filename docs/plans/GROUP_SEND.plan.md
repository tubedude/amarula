> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Group send — fold into the existing send pipe

## Key facts

- Group **receive** already works when we hold the sender's key (a real group
  message was decrypted live: "Consegue, mas pra que?"). The skmsg failures are
  members whose SKDM we never received — the correct retry path, not a bug.
- Group **send** crypto already exists:
  - `GroupSessionBuilder.create_sender_key_distribution_message/4` — generates our
    sender-key state + the SKDM to distribute.
  - `GroupCipher.encrypt/3` — produces the `skmsg` ciphertext.
  What's missing is **orchestration** + group-metadata fetch + relay stanza shape.

## Design: same 4-step pipe, `ctx.kind` set once from the jid

`ctx.kind` = `:dm | :group`, decided at send start from `JID.is_jid_group?/1`.
The pipe is unchanged in shape; steps dispatch on `kind`. No top-level branch in
the flow — one field set early, then polymorphic steps.

| step | :dm (today) | :group (new) |
|------|-------------|--------------|
| resolve_recipients | USync the user's devices | fetch group metadata → participant jids → USync each → their devices |
| ensure_sessions | per-device pkmsg sessions | **same** (needed for SKDM distribution) |
| encrypt | msg per device | `GroupCipher.encrypt` once (skmsg) + SKDM encrypted per device (reuses dm per-device encrypt) |
| relay | `<participants>` of `<to><enc>` | `<enc v=2 type=skmsg>` + `<participants>` of the SKDM `<to><enc>` |

`resolve_recipients` is where the **group-metadata fetch** lives — simply absent
for :dm (matches the "a step that's a no-op for 1:1" intuition).

## New pieces

1. **Group metadata fetch** (ConversationSender, via `query_iq`):
   `<iq type=get xmlns=w:g2 to=<group>><query request=interactive/></iq>`
   → parse `<group>` participants (jids + admin flags) into a participant list.
   New module `Amarula.Protocol.Groups.Metadata` (pure parse) + the IQ build.
   (Baileys: groupQuery / extractGroupMetadata in src/Socket/groups.ts.)

2. **resolve_recipients/:group**: metadata → participant jids (+ our own jid for
   our other devices) → USync devices for all → flatten. Reuses `USync` +
   `USync.Devices.extract` + `DeviceListCache` exactly as DM does. (Optionally a
   group-metadata cache later; skip first pass.)

3. **encrypt/:group**:
   - ensure our sender key for this group: `create_sender_key_distribution_message`
     (idempotent — creates state if absent, returns SKDM).
   - `skmsg` = `GroupCipher.encrypt(group_sender_key_name, plaintext)`.
   - SKDM message = wrap the real message with `senderKeyDistributionMessage`
     {groupId, axolotl bytes}; encrypt THAT per participant device (the dm
     per-device path). First send to a group distributes keys to everyone; later
     sends can skip redistribution (Baileys tracks who has the key — defer, send
     SKDM every time first pass; correct if wasteful).
   - DSM still applies to our own devices.

4. **relay/:group**: stanza content = `[<enc skmsg>, <participants>…, device-identity?]`.
   Extend `Relay` with a group stanza builder (or generalize
   build_multi_device_stanza to take leading enc nodes).

## Steps to implement

1. `Groups.Metadata` — build the w:g2 query IQ + parse the result (participants).
2. ConversationSender: set `ctx.kind` from jid; `resolve_recipients` dispatches
   (dm = today; group = metadata + participant USync).
3. encrypt/relay dispatch on kind; group encrypt builds skmsg + SKDM fan-out.
4. `Relay` group stanza shape.
5. Tests: group send flow (metadata IQ → participant USyncs → bundles → stanza
   with skmsg + SKDM participants), following [[no-pii-in-tests]] (fake group jid
   + participant jids).

## Open questions

- **SKDM redistribution tracking**: resend SKDM every group send (simple, wasteful)
  vs track recipients who already have our key (Baileys does this). Lean: every
  send first pass; optimize later.
- **Group metadata cache**: skip first pass; add alongside DeviceListCache later.
- **Sender identity (PN vs LID)** for the group sender-key name — check what the
  live group uses (the failing author was `…@lid`); align our sender-key identity.
