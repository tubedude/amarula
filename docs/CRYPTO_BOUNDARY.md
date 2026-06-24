# The crypto boundary

Amarula's cryptography is **pure** and **self-contained**: it implements the
Noise_XX handshake and the Signal Protocol (1:1 Double Ratchet + group sender
keys) with no dependency on WhatsApp, transport, or persistence. Everything
WhatsApp-specific lives *above* it and reaches the crypto only through a thin,
explicit seam.

This document draws that line. It is a real architectural contract — **the core
must never depend on the app** — and it is what would make the crypto extractable
as a standalone library (a pure-Elixir Signal/Noise implementation) without
untangling.

## The three layers

```
┌──────────────────────────────────────────────────────────────┐
│ App (Amarula.Connection, Messages, Storage, …)               │  WhatsApp client
├──────────────────────────────────────────────────────────────┤
│ Glue — the ONLY bridge: persistence + WhatsApp multi-device  │  5 + 1 modules
├──────────────────────────────────────────────────────────────┤
│ Core — pure Signal / Noise crypto. No Amarula.* app deps.    │  extraction-ready
└──────────────────────────────────────────────────────────────┘
```

**The dependency rule: arrows point down only.** App → Glue → Core. The Core never
references the Glue or the App; the Glue never reaches back into the App's
transport. A `Amarula.Conn` / `Amarula.Storage` reference inside a Core module is a
boundary violation.

## Core — pure crypto (no app coupling)

Depends only on Erlang `:crypto`, `Bitwise`, and other Core modules. Given keys and
bytes in, it returns keys and bytes out — it neither loads nor saves anything, and
knows nothing about JIDs, LIDs, sockets, or WhatsApp.

**`lib/amarula/protocol/crypto/`**
- `crypto.ex` — primitives (X25519, AES-GCM/CBC/CTR, HKDF, HMAC, random).
- `noise_handler.ex` — the Noise_XX handshake state machine.
- `xeddsa.ex` — XEdDSA sign/verify over X25519 keys.
- `constants.ex` — protocol constants.

**`lib/amarula/protocol/signal/` (1:1 Double Ratchet)**
- `session_cipher.ex` — encrypt/decrypt + ratchet advance (pure: record in,
  record out).
- `session_builder.ex` — X3DH session establishment.
- `session_record.ex` — the session/ratchet data structure.
- `whisper_protocol.ex` — WhisperMessage wire encode/decode.
- `crypto_helpers.ex` — Signal key-derivation helpers.
- `pre_keys.ex` — prekey generation.
- `lid_mapping.ex` — the *pure* LID/PN encode/decode (not the store).
- `repository.ex`, `types.ex` — shared structs/contracts.
- `key_store_behaviour.ex`, `sender_key_store_behaviour.ex` — the **behaviours**
  the Glue implements (the seam is defined here, in Core, and satisfied above).

**`lib/amarula/protocol/signal/group/` (group sender-key cipher)**
- everything *except* `sender_key_store.ex`: `group_cipher`,
  `group_session_builder`, `key_helper`, `sender_chain_key`,
  `sender_key_distribution_message`, `sender_key_message`, `sender_key_name`,
  `sender_key_record`, `sender_key_state`, `sender_message_key`.

## Glue — the only bridge (persistence + WhatsApp multi-device)

These are the **only** modules allowed to touch both Core crypto and
`Amarula.Conn` / `Amarula.Storage`. They are adapters: they persist Core's records,
and they encode WhatsApp's multi-device concepts (LID ↔ PN, device lists) that are
*not* part of Signal. They belong to Amarula, not to a standalone crypto library.

- `signal/session_store.ex` — persists `SessionRecord`s via `Amarula.Storage`
  (implements the Core session-store seam).
- `signal/group/sender_key_store.ex` — persists sender-key records (the group seam).
- `signal/session_injector.ex` — installs fetched prekey bundles into sessions.
- `signal/device_list_cache.ex` — caches a peer's device list (a WhatsApp concept).
- `signal/lid_mapping_store.ex` / `lid_mapping_file_store.ex` — persist LID ↔ PN
  mappings (WhatsApp multi-device addressing).

## Why the seam is a behaviour

Core defines `KeyStoreBehaviour` / `SenderKeyStoreBehaviour` (and the session store
shape) and depends on *those contracts*, not on a concrete store. The Glue provides
the concrete, `Amarula.Storage`-backed implementations. So Core is parameterised
over persistence: hand it any conforming store and it runs — which is exactly what
a standalone library needs.

## Status & extraction

The boundary is **already honored in the code** (verified: no Core module
references `Amarula.Conn`/`Amarula.Storage`). This doc makes it an explicit,
enforced-by-review contract rather than an accident.

The Core is therefore **extraction-ready in principle** — it could become a
standalone pure-Elixir Signal/Noise library, with the cross-language tests
(`session_cipher_crosslang_test`, `session_builder_crosslang_test`) as its proof of
byte-compatibility with libsignal. Extraction is **not** planned for now: it carries
a real maintenance and security-expectation cost (see the discussion in the project
notes), and the Glue would stay here regardless. This document is the prerequisite —
draw and hold the line first; decide on extraction later.

## Keeping the line

When adding or changing a crypto module, ask: **does it need `Amarula.Conn` or
`Amarula.Storage`?**
- **No** → it's Core. Keep it pure; depend only on `:crypto` and other Core modules.
- **Yes** → it's Glue. It implements a Core behaviour and lives at the seam; it must
  not leak app/transport concerns down into Core.

If a Core module starts needing storage, that's a signal to **split it**: the pure
algorithm stays in Core, the persistence moves to a Glue adapter behind a behaviour.
