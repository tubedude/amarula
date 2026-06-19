# Backlog: media retry (re-upload on expired/missing blob)

**Status:** not implemented. Backlog item with a feasibility study (below).
**Why it matters:** WhatsApp's media CDN drops a blob after a while, and
`Media.download/2` then dead-ends at `{:error, {:http, 404}}` with no recovery.
`docs/GOING_PROD.md` already warns consumers ("fetch-soon, not fetch-whenever"),
so this is a missing *feature*, not a doc bug.

## This is a real, wired-up feature in Baileys (verified)

Not dead code — the reference fully implements and uses it:
- **`messages-send.ts:1281` `updateMediaMessage(message)`** — the public API. Builds
  the request (`encryptMediaRetryRequest`), `sendNode`s it, and `Promise.all`-waits
  on the `messages.media-update` event correlated by `message.key.id`; on success
  sets `content.directPath`/`url` to the fresh values, on a non-`SUCCESS`
  `ResultType` raises a mapped error.
- **`messages-recv.ts:1053`** — the inbound side: a `notification` whose child tag
  is **`mediaretry`** is decoded by `decodeMediaRetryNode` and emitted as
  `messages.media-update`.
- Covered by the e2e suite (`send-receive-message.test-e2e.ts:149,171`).

## What the protocol does (reference: `src/Utils/messages-media.ts`)

When a download 404s, the client asks **the phone** to re-upload the media and
hand back a fresh URL:

1. **Send a retry request** — a `<receipt type="server-error">` stanza keyed by
   the original message id, addressed to our own jid (`meId`). It carries:
   - an `<rmr>` node (`jid` = remoteJid, `from_me`, `participant`) identifying the
     message;
   - an `<encrypt>` node with `<enc_p>` (ciphertext) + `<enc_iv>` (iv). The
     plaintext is a `ServerErrorReceipt{stanzaId: key.id}`, AES-256-GCM encrypted
     under a per-media **retry key** with the msg id as AAD.
     *(The reference notes this encrypt node is "actually pretty useless — the
     media is returned even without it"; it's kept for WA Web parity.)*
2. **Receive the reply** — a `notification` (or receipt) the server routes back,
   decoded by `decodeMediaRetryNode`: either an `<error code=...>` (re-upload
   failed) or an `<encrypt>` with `enc_p`/`enc_iv`.
3. **Decrypt the reply** — `decryptMediaRetryData` AES-GCM-decrypts the payload
   (same retry key, msg id as AAD) into a `MediaRetryNotification`, which contains
   the **new `directPath`**. Re-run the normal download against it.

### The retry key

    retryKey = HKDF-SHA256(mediaKey, 32, info: "WhatsApp Media Retry Notification")

Same `mediaKey` already on the message; only the HKDF `info` string differs from
the download keys.

## Feasibility: every primitive already exists

| Need | Have in Amarula |
|------|-----------------|
| HKDF-SHA256 (derive retry key) | `Crypto.hkdf/4` (`crypto.ex:158`) |
| AES-256-GCM encrypt/decrypt w/ AAD | `Crypto.aes_encrypt_gcm/4`, `aes_decrypt_gcm/4` (`crypto.ex:55,70`) |
| `ServerErrorReceipt` / `MediaRetryNotification` protos | present in `wa_proto.pb.ex` |
| Build + send a `<receipt>` stanza | the receipt senders in `connection.ex` (e.g. `send_delivery_receipt/2`, `:3206`) |
| Route an inbound notification → handler | `Router` + `dispatch_node/3` already route receipts/notifications |
| Re-download from a fresh `directPath` | `Media.download/2` already takes a ref with `direct_path` |

So this is **assembly of existing parts**, not new crypto or transport. No new
dependency.

## Work to implement (estimate: medium)

1. **`Media.encrypt_retry_request/3`** (pure) — port `encryptMediaRetryRequest`:
   derive the retry key, GCM-encrypt the `ServerErrorReceipt`, build the
   `<receipt type="server-error">` node. Unit-testable with no socket.
2. **`Media.decode_retry_node/1` + `decrypt_retry_data/3`** (pure) — port
   `decodeMediaRetryNode` / `decryptMediaRetryData` → `{:ok, new_direct_path}` or
   `{:error, code}`. Unit-testable.
3. **Wire it into `Connection`** — a `request_media_retry` send, a router entry +
   handler for the inbound media-retry notification, and IQ-style correlation so a
   caller can await the fresh URL. This is the only non-pure part.
4. **Public API** — either automatic (on a 404, `download_media` transparently
   requests a retry and re-downloads) or explicit (`Amarula.retry_media/2`).
   Automatic is friendlier but needs a live `conn` inside the download path, which
   today is socket-free (`Media.download/2` is a bare `Req.get`) — so the retry
   entry point must live on `Connection`, not in `Media.download/2`.

## Risks / open questions

- **Needs `conn`.** Download is currently connection-less (pure HTTP). Retry needs
  the websocket (send the receipt, await the phone's reply), so the retry API must
  be a `Connection` call — can't hide it inside `Media.download/2`. Decide:
  auto-retry wrapper on `Connection.download_media` vs an explicit `retry_media/2`.
- **Reply routing — answered.** The phone's response is a `notification` with a
  `<mediaretry>` child (`messages-recv.ts:1056`), correlated by message id. Add a
  `Router` case for `notification`/`mediaretry` → a media-retry handler. (Still
  worth capturing a real frame to lock the exact attrs.)
- **Timeout/coalescing.** A retry is a round-trip to the *phone* (not the server);
  it can be slow or never answered if the phone is offline. Needs a timeout and a
  clear `{:error, :media_retry_timeout}`.
- **`participant` for group media** — thread `participant` through the `<rmr>`
  node correctly for group messages.

## Suggested path

Land steps 1–2 (pure, fully tested) first — they're risk-free and verify the
crypto against a captured frame. Defer step 3/4 until there's a real expired-media
case to test the round-trip against. Until then, `GOING_PROD.md`'s "download on
receipt" guidance is the mitigation.
