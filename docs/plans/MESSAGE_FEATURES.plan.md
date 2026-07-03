> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Message features to re-implement (on the real send path)

The legacy stack (`sender.ex`, `receiver.ex`, `messages.ex`, `reactions.ex`,
`edit.ex`, `media.ex`, `events.ex`) was deleted on 2026-06-13. It was dead,
unencrypted (`<plaintext>` stub), and used a duplicate socket path
(`Socket.send_message` → `ConnectionManager.send_data`). The real architecture
is the only one now:

```
Socket.send_text → ConversationSender.deliver → encrypt (Signal) → Relay → ConnectionManager.relay_stanza → send_binary_node → noise → ws
incoming:  ConnectionManager.handle_message → MessageDecryptor.decrypt_node → emit :messages_upsert
```

When re-adding features, build them ON THIS path (encode the right `proto.Message`
content, hand it to `ConversationSender`/`Relay`), not a parallel one.

## Reactions
- Build `%Proto.Message{reactionMessage: %{key: target_key, text: emoji, senderTimestampMs: ...}}`.
- Remove reaction = empty `text`.
- Replies = set `messageContextInfo`/`contextInfo` with `stanzaId`, `participant`, `quotedMessage` on the outgoing message; send via ConversationSender.
- Baileys ref: `generateWAMessageContent` reaction path.

## Edit / Delete (revoke)
- Edit: `%Proto.Message{protocolMessage: %{type: :MESSAGE_EDIT, key: target, editedMessage: %{...}}}` (+ `editedMessage` wrapper; check Baileys current proto).
- Delete-for-everyone: `protocolMessage{type: :REVOKE, key: target}`.
- The old edit.ex `edit_message/delete_message` were empty stubs — nothing to salvage.

## Media (image/video/audio/document/sticker)
- WhatsApp media is NOT raw AES-CBC with the media key (the deleted media.ex did
  this — WRONG). Real flow (Baileys `Utils/messages-media.ts`):
  1. `mediaKey = random(32)`
  2. expand via HKDF-SHA256 (info = per-type app-info string, e.g. "WhatsApp Image Keys") → iv(16) + cipherKey(32) + macKey(32) + refKey(32)
  3. ciphertext = AES-CBC(cipherKey, iv, data); mac = HMAC-SHA256(macKey, iv||ciphertext)[0..10]; enc = ciphertext || mac
  4. `fileEncSha256 = sha256(enc)`, `fileSha256 = sha256(plaintext)`, `fileLength = len(plaintext)`
  5. upload enc to the media conn (`mediaconn` IQ → hosts), get `directPath`/`url`
  6. send `%Proto.Message{imageMessage: %{url, directPath, mediaKey, fileEncSha256, fileSha256, fileLength, mimetype, ...}}` via ConversationSender
- Download = reverse: HKDF, verify mac, AES-CBC decrypt.

## Receive (already covered)
- `MessageDecryptor` is the real receive path. The deleted `receiver.ex` was the
  old duplicate. Incoming protocolMessages (history sync, app-state-key-share,
  reactions, edits, revokes) are currently decrypted but NOT acted on — handle
  them in/near `handle_message`.

## Events
- The deleted `events.ex` GenServer was unused. Subscription/event delivery
  already happens via `emit_to_subscribers`/`emit_event` in ConnectionManager →
  parent pid. Build any pub/sub on that, not a separate GenServer.
