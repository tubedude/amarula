# C2 — App-state sync (chat list, contacts, chat mutations)

The big subsystem. Source: `src/Utils/chat-utils.ts`, `lt-hash.ts`,
`sync-action-utils.ts`, `src/Socket/chats.ts` (`resyncAppState`). Current Baileys
delegates LTHash to a rust bridge, but the algorithm is known and portable.

## What it delivers
Incremental sync of app state across the primary↔companion link: the **chat list**
(1:1 + group convos with archive/pin/mute/unread/last-msg-ts), **contacts**
(push names), stars, and other chat mutations. Arrives as encrypted *patches* per
*collection*, verified by per-collection **LTHash** + MACs, decoded into typed
**sync actions**, applied to local state.

## The pipeline (per collection)
1. **Request** patches: `<iq xmlns="w:sync:app:state" type="set"><sync>
   <collection name=.. version=.. return_snapshot=..></sync></iq>` for each of:
   `critical_block`, `critical_unblock_low`, `regular`, `regular_high`,
   `regular_low`.
2. **Extract** (`extractSyncdPatches`): pull `<collection>` → snapshot + patches.
3. **Decode patch** (`decodeSyncdPatch`/`decodeSyncdMutations`):
   - per record: derive keys (`mutationKeys` = HKDF-expand the app-state-sync-key
     → indexKey/valueEncryptionKey/valueMacKey/snapshotMacKey/patchMacKey),
   - verify value MAC (`generateMac`: HMAC over opByte‖encContent‖keyId),
   - AES-256-CBC decrypt value → `SyncActionData` proto,
   - verify index MAC, verify patch MAC (`generatePatchMac`),
   - **LTHash mix** (add/subtract valueMacs) → new 128-byte hash; verify
     snapshot MAC (`generateSnapshotMac`).
4. **Decode action** (`sync-action-utils`): `SyncActionData` → typed mutation
   (chat archive/pin/mute/markRead, contact, star, …) keyed by a parsed index.
5. **Apply** → emit `chats.set/upsert/update`, `contacts.set/update` equivalents;
   persist new collection `{version, hash, indexValueMap}`.

## Pieces to build (Elixir)
- **Proto**: SyncdPatch, SyncdMutation, SyncdRecord, SyncdValue, SyncActionData,
  SyncActionValue, ExternalBlobReference, AppStateSyncKey* — check they're in
  `wa_proto.pb.ex` (likely yes; verify).
- **AppState.Keys** — HKDF expand app-state-sync-key (info "WhatsApp Mutation
  Keys", 5 sub-keys). Pure crypto, testable.
- **AppState.LTHash** — DEMYSTIFIED via the pre-WASM pure-JS impl
  (git `4d91c733d9~1:src/Utils/lt-hash.ts`). Algorithm in full:
  hash = 128 bytes = 64 little-endian uint16 words; each mac →
  `HKDF(mac, 128, salt="", info="WhatsApp Patch Integrity")` → 64 words; add/sub =
  pointwise uint16 with wraparound (mod 2^16); `subtract_then_add(base, subs,
  adds)` = subtract subs then add adds. ~40 lines of Elixir, we have `Crypto.hkdf`.
  No rust needed. (NOTE arg order: current WASM `subtractThenAdd(base, subtract,
  add)` vs old JS `subtractThenAdd(e, addList, subtractList)` — params are NAMED
  add/subtract; go by the verify result, test both orders against captured data.)
- **AppState.Mutation** — per-record decrypt+MAC verify (generateMac /
  generatePatchMac / generateSnapshotMac), AES-CBC. Pure given keys.
- **AppState.Patch** — decode a patch/snapshot, drive LTHash mix, return mutations
  + new state. Pure given keys + state.
- **AppState.SyncActions** — SyncActionData → typed action + index parse.
- **app-state-sync-key handling** — receive APP_STATE_SYNC_KEY_SHARE (in an
  incoming message's protocolMessage), store keys (new Storage namespace
  `:app_state_sync_key`). Without keys, sync is Blocked until the share arrives.
- **Collection state storage** — `{version, hash, indexValueMap}` per collection
  name (new Storage namespace `:app_state_version`).
- **Orchestrator** (ConnectionManager) — resyncAppState: request → extract →
  decode → apply → persist; handle `<ib>…dirty type=account_sync`/the
  notification trigger; park-and-retry on missing key.
- **Events** — emit chat/contact set/update to the consumer (as %Address{} /
  a new %Chat{} value).
- **History sync** — `messaging-history.set` on first link (the initial bulk
  chats/contacts/messages) is RELATED but separate; can be a follow-up.

## Risk / order
1. **LTHash first, in isolation, with a known-answer test.** If we can't match a
   reference hash, the whole chain fails MAC verify silently. Highest risk —
   prove it before building on it. (May need to capture a real snapshot from a
   live sync to get a test vector.)
2. Key expand + mutation decrypt (pure, testable with captured data).
3. Patch decode + state.
4. Sync-action decode + %Chat{} + events.
5. Orchestrator + key-share handling + storage.
6. (later) history sync.

## Reality
This is multi-session. LTHash is the gate. Recommend: build LTHash + key-expand +
mutation-decrypt as pure, unit-tested modules first (no wire), validate against a
captured real patch, THEN wire the orchestrator. Don't wire end-to-end until the
crypto verifies offline.
