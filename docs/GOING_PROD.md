# Going to Production

What a consumer must decide before running Amarula for real. The library ships
sensible defaults for local dev; production forces three choices it deliberately
leaves to you:

1. **[Credential storage](#1-credential-storage)** — where the auth state lives.
2. **[The profile registry](#2-the-profile-registry)** — single node or cluster.
3. **[Message storage](#3-message-storage)** — what to keep, how to read it back.

Amarula has no opinion on any of these by design. It gives you seams; you pick the
backend and the policy. This doc points at the seams and the gotchas.

---

## 1. Credential storage

Everything Amarula must remember across a restart — auth creds, 1:1 Signal
sessions, group sender keys, LID↔PN mappings, the device-list cache, app-state —
flows through one seam: the `Amarula.Storage` behaviour, scoped by
`{profile, namespace, key}`. **Lose this and you re-pair from a QR.** So in prod
it must be durable, backed up, and concurrency-safe.

### Pick an adapter

Pass `:storage` on the config (`Amarula.new/1`). Two adapters ship:

| Adapter | Spec | Use |
|---------|------|-----|
| `Amarula.Storage.File` (default) | `{Amarula.Storage.File, root: "./amarula_data"}` | single node, simple. One `<root>/<profile>/` dir per profile, atomic writes. |
| `Amarula.Storage.DETS` | `{Amarula.Storage.DETS, ...}` | single node, fewer inodes. |

If you pass no `:storage`, the default is the File adapter rooted at
`./amarula_data` (override with the `AMARULA_DATA_DIR` env var). This directory
holds live credentials and Signal sessions — **treat it like a secret**. Amarula
ignores it inside its *own* repo, but that ignore rule does **not** travel with the
dependency, so in your app you must add it to your `.gitignore` yourself:

```gitignore
# Amarula credential + session storage — never commit
/amarula_data/
```

(Match whatever root you configure; if you set `AMARULA_DATA_DIR` or a custom
`:storage` root, ignore that path instead.)

Both adapters are **node-local on disk**. For multi-node, or for "creds must survive the
box dying," write a DB/object-store adapter — implement the four required callbacks
(`new/get/put/delete`); `clear` and `list_profiles` are optional. Pass
`{YourAdapter, opts}`. The protocol layer only ever says "save this session" /
"load that mapping"; it never touches your backend directly.

### Gotchas

- **Your adapter receives live Elixir terms** — nested maps/structs with atom keys
  and raw binaries, not a pre-serialized blob. Serialize them opaquely and
  losslessly (the File adapter uses `:erlang.term_to_binary/1`); a DB adapter should
  store one blob column, not try to map fields. The terms are **not** interchangeable
  with Baileys' JSON state.
- **Concurrency.** Adapters must be safe to call from multiple processes for the
  same scope. The File adapter does atomic temp-file + rename; a DB adapter gets
  this for free per row.
- **Profile = tenant key, and it becomes a path segment in the File adapter.**
  Never wire untrusted input straight into `:profile` — the File adapter raises on
  traversal (`"../.."`), but a multi-tenant bot should validate/namespace profiles
  itself.
- **Back it up.** Re-pairing means a human scans a QR. Treat the store like a
  password vault.
- **Decode is `[:safe]`** — a tampered `.term` file can't mint atoms or smuggle
  funs; it's treated as a cache miss. Don't rely on that for trust; keep the store
  private.

### One profile = one credential set

`:profile` names the account's stored creds. The next run with the same profile
reconnects without a QR. Keep `profile ↔ credentials` strictly 1:1 — the library
trusts this and does not validate it.

---

## 2. The profile registry

Amarula enforces **one live connection per profile**. Two WebSockets on one
credential set corrupt the shared Signal ratchet — this is a correctness
invariant, not deduplication. *How far* "one" reaches is your choice, set by the
`:registry` config seam.

**WhatsApp enforces this too, server-side.** One credential set is one device. If
a second connection authenticates on the same creds, the server **drops the
first** — it sends a `conflict`/`replaced` stream error and disconnects it
(`connectionReplaced`, code 440). So racing two connections doesn't give you two
live sessions; it gives you a flapping connection as each kicks the other off, and
a corrupted ratchet in the crossfire. The local registry exists to stop you ever
getting there. Treat 440 / `replaced` as "someone else took my profile," not a
transient error to auto-reconnect through.

**Uniqueness reach = the registry's reach.** The library only uses the standard
`Registry`/`:via` contract:

| `:registry` | Reach | When |
|-------------|-------|------|
| default `Amarula.ProfileRegistry` (local) | one per profile **per node** | single node |
| `:via`-cluster registry (`Horde.Registry`, a `:global`/`:pg` shim) | one per profile **cluster-wide** | distributed |

The consumer distributes the credentials and picks the registry; Amarula enforces
one-per-profile against whatever reach that registry has. **The library never
decides clustering.**

### Distributed gotcha

A cluster registry built on `:global` is only *best-effort* at uniqueness. If the
cluster splits in two (a network partition), each half can register the same
profile, because neither half can see the other. Now you have two live
connections on one profile until the network heals — long enough to corrupt the
ratchet.

So in a real cluster, don't rely on the registry alone. Add an **external lease**:
a single row in your database (or a Redis key) that one node must hold before it's
allowed to connect a given profile. The database stays consistent across a
partition where `:global` doesn't, so it's the real guard; the registry just keeps
things tidy within a healthy cluster. You use both — the lease for safety, the
`:registry` seam for the fast in-cluster check.

### Handles

- `Amarula.whereis(profile)` → current pid (restart-safe; the pid changes on
  restart, the profile keeps resolving).
- `Amarula.via(profile)` → a `:via` handle usable anywhere a `conn()` is accepted.
- Raw pid from `connect/2` goes **stale** on restart — prefer the profile handle
  in long-lived code.
- `disconnect/1` closes the socket but **keeps the profile registered** (it may
  reconnect). To free the slot (and let another node claim it), use
  `Amarula.stop/1`.

---

## 3. Message storage

**Amarula does not persist messages. That is your job.** An inbound message is
delivered **once** as `{:amarula, :messages_upsert, %{from, id, messages:
[%Amarula.Msg{}]}}` to your `parent_pid`, then forgotten. No replay, no inbox.

### What to store

Store the **consumer struct**, not the raw protobuf. Each `%Amarula.Msg{}` carries
the friendly view:

| field | keep for |
|-------|----------|
| `id` | dedup key + reply/quote/revoke target |
| `channel` | **the reply handle** — peer in 1:1, the group in a group |
| `from` / `to` | who wrote it / real recipient (matters for `from_me` fan-out) |
| `from_me` | tells your own sent messages apart |
| `timestamp` | ordering |
| `type` + `content` | `:text` / `:media` / `:reaction` / `:edit` / `:revoke` / … |
| `pushname` | sender display name off the stanza (name a contact with no fetch) |

`msg.raw` is the full `%Proto.Message{}` escape hatch — keep it only if you need a
field Amarula doesn't surface; it's large.

### Reading the body — text and media

`msg.content` shape depends on `msg.type`. Match on the type:

```elixir
case msg.type do
  :text ->
    text = msg.content          # content IS the String
    save_text(msg.id, text)

  :media ->
    # content is an %Amarula.Content.Media{} descriptor (URL + keys), not bytes.
    # Its :kind is :image | :video | :audio | :document | :sticker.
    %{kind: kind} = msg.content
    # ...store the descriptor; fetch bytes on demand (below)

  _ ->
    :ok                          # reactions, edits, polls, … — see the type table
end
```

**Media is not downloaded for you.** The inbound message carries only a
*descriptor* (URL + decryption keys), never the file. To get the bytes, call:

```elixir
{:ok, bytes} = Amarula.download_media(msg)   # pass the whole %Msg{}
```

What to do with the bytes is your decision, and it drives **what you store**:

- **Don't store bytes in your message DB.** They're large and the WhatsApp media
  URL is short-lived, so you can't lazily re-fetch later from the descriptor alone
  forever. Decide up front.
- **Download once, on receipt, to your own object store** (S3/disk), and store
  *its* URL/path next to the message. This is the usual choice — the WhatsApp URL
  expires; yours doesn't.
- Deferring is risky: WhatsApp's CDN drops the blob after a while, and a later
  download then returns `{:error, {:http, 404}}`. The recovery is to ask the
  **phone to re-upload** the media via `Amarula.retry_media/2`, which returns a
  refreshed descriptor you hand back to `download_media/1`. But that only works
  while the phone still has the message and is reachable, so treat the descriptor
  as fetch-soon, not fetch-whenever.

So: text → store the string. Media → download to storage you control, store the
pointer (and the `kind`), not the raw bytes in your row.

### Best practices

- **Dedup by `id`.** On a single connection you do **not** echo your own sends, so
  no self-dedup needed. The one case that needs cross-connection dedup by `id`:
  **two connections on the same account** (each receives the other's sends).
- **Reply by `channel`.** Put `msg.channel` straight into a send target — routes
  back to the same conversation. Don't reconstruct from `from`/`to`.
- **Media is lazy.** A `:media` message's `content` is a descriptor; call
  `Amarula.download_media/1` to fetch bytes. Store the descriptor if you want to
  download later; bytes aren't kept by the library.
- **Edits/revokes/reactions point at an earlier `id`** via a `MessageKey` in
  `content`. To apply them you need the original stored — another reason to keep an
  `id`-keyed store.
- **Persist on receipt, synchronously enough not to lose on crash.** The event
  fires once; if your handler crashes before writing, the message is gone.

### History sync

On first pair, WhatsApp pushes a history-sync blob (recent chats/contacts/messages).
It arrives as its **own** `:history_sync` event, **not** as `:messages_upsert` — so
handle both: seed your store from `:history_sync`, then rely on live
`:messages_upsert` going forward. Pull more on demand with `fetch_history/4`.

---

## Quick checklist

- [ ] Durable, backed-up `:storage` adapter (not the dev `./amarula_data` File default).
- [ ] `profile ↔ credentials` 1:1, profiles validated if tenant-derived.
- [ ] Registry reach matches your topology (local vs cluster), + an external lease
      if `:global`.
- [ ] A message store you own, keyed by `id`, persisted on `:messages_upsert`.
- [ ] Reply via `msg.channel`; dedup by `id` only across connections.

## See also

- [`INFRASTRUCTURE.md`](INFRASTRUCTURE.md) — supervision tree, send/ack semantics,
  the two registries.
- `Amarula.Storage` — the storage behaviour + namespaces.
- `Amarula.Msg` — the received-message struct (addressing, `from_me`, `pushname`).
- `Amarula` — the public facade (`new/1`, `connect/2`, `whereis/1`, `stop/1`).
