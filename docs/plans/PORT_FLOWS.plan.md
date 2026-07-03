> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Effort C — chat & group discovery (scope)

Goal: let a consumer find out which chats/groups exist and reference them (by
`%Amarula.Address{}`), incl. group participants.

**Critical split:** "discovery" is TWO very different subsystems with very
different cost. Don't conflate them.

---

## C1 — Group discovery (SMALL, do first)

Groups are queryable on demand via IQ — no app-state, no crypto. We already have
single-group metadata (`Amarula.Protocol.Groups.Metadata.query_iq/parse`, used by
the group send path). Two pieces to add:

1. **Fetch one group's metadata** — already exists; just surface it on the facade:
   `Amarula.group_metadata(conn, group_addr)` → `%Group{address, subject,
   participants: [%Address{}], ...}`.
2. **Fetch ALL participating groups** — Baileys `groupFetchAllParticipating`
   (groups.ts:38): one IQ `<iq to="@g.us" xmlns="w:g2" type="get"><participating>
   <participants/><description/></participating>`, returns `<groups><group>…`.
   Parse each via the metadata extractor we already have.
   `Amarula.list_groups(conn)` → `[%Group{}]`.

New: a `%Amarula.Group{}` value (address + subject + participants[] + admins +
owner + announce/restrict flags) and a parser (extend `Groups.Metadata.parse` to
the list shape). `participants` are `%Address{}` — uses effort A/B's type.

Effort: ~half a day. No crypto, no new auth state. Reachable now.
Also cheap to add alongside (Baileys groups.ts): groupCreate, groupLeave,
groupUpdateSubject, group participant add/remove, invite code — all plain IQs.
Out of scope unless wanted.

## C1 caveat — LID/PN in participants
Baileys flags "TODO: properly parse LID / PN DATA" in groupFetchAllParticipating.
Group participant jids may be LID or PN; `%Address{}` already distinguishes by
`:kind`, but resolving LID↔PN for them is the same internal concern as the send
path. Surface participants as the addresses the server gives (kind set
correctly); leave resolution internal.

---

## C2 — Chat list / history (LARGE, separate project)

The full conversation list (1:1 chats, last message, unread, pin/mute/archive,
contact push-names) does NOT come from a query. It comes from **app-state sync** —
the same mechanism that syncs contacts, chat mutations, etc. This is a big,
crypto-heavy subsystem we have NOT ported:

- **app-state-sync-keys** — a new key type, shared from the primary device.
- **resyncAppState** (chats.ts:550) — fetch patches per "collection"
  (`critical_block`, `regular`, `regular_high`, `regular_low`), each a set of
  encrypted mutations.
- **LTHash** — the WhatsApp app-state hashing scheme; verify the snapshot/patch
  MAC (`appStateMacVerification`), maintain a running hash per collection version.
- **mutation decryption** — AES + HMAC per mutation, then decode into typed
  actions (chat mutate, contact, star, etc.).
- **state persistence** — `app-state-sync-version` per collection (a new Storage
  namespace).
- **history sync** — the initial `messaging-history.set` (chats/contacts/messages
  notification on first link), separate from incremental app-state.

This is the single largest unported subsystem — comparable in size to the Signal
session work. It needs: LTHash impl, app-state key handling, patch
fetch+decrypt+verify, action decode, and storage for versions. Easily a
multi-session effort on its own.

Recommendation: **do C1 now** (groups, cheap, high value, uses Address). Treat
**C2 as its own dedicated project** later — scope it separately when chat-list
sync is actually needed; it's not a quick add.

---

## Suggested split
- **C1a**: `%Group{}` + `list_groups` + `group_metadata` facade (½ day).
- **C1b** (optional): group admin ops (create/leave/subject/participants) — plain
  IQs, add as needed.
- **C2**: app-state sync — separate project, own plan, when needed.
