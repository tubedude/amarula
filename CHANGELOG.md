# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-19

A consumer-API cleanup pass: leaner, more consistent `Amarula` facade with no
protocol types leaked. **All breaking changes are mechanical** — rename the call
or swap two arguments; behaviour is unchanged.

### Changed (breaking)

**Namespaced the group / profile / contact families** — these moved off the flat
`Amarula` facade onto dedicated modules, shrinking the top-level surface and
dropping the prefix-stutter. Every operation is unchanged; only the module differs:

| Before | After |
|--------|-------|
| `Amarula.group_create/3`, `group_leave/2`, … (all `group_*`) | `Amarula.Group.create/3`, `Amarula.Group.leave/2`, … (drop the `group_` prefix) |
| `Amarula.group_metadata/2`, `Amarula.list_groups/1` | `Amarula.Group.metadata/2`, `Amarula.Group.list/1` |
| `Amarula.on_whatsapp/2`, `fetch_profile_status/2` | `Amarula.Contacts.on_whatsapp/2`, `Amarula.Contacts.fetch_status/2` |
| `Amarula.profile_picture_url/3`, `update_profile_*`, `remove_profile_picture/2` | `Amarula.Profile.picture_url/3`, `update_picture/3`, `update_status/2`, `remove_picture/2` |

**Event tag** — consumer events are now tagged `:amarula`, not `:whatsapp`, so the
origin is clear and the tag won't collide with other libraries:

```elixir
# before
{:whatsapp, :messages_upsert, data}
# after
{:amarula, :messages_upsert, data}
```

Update every `receive`/`handle_info` clause that matches the event tuple.

**Renamed functions** (same behaviour, clearer name):

| Before | After |
|--------|-------|
| `Amarula.Address.to_wire/1`, `to_wire!/1` | `Amarula.Address.to_jid/1`, `to_jid!/1` (now accept a string *or* an `Address`) |
| `Amarula.fetch_status/2` | `Amarula.fetch_profile_status/2` |
| `Amarula.presence_subscribe/2` | `Amarula.subscribe_presence/2` |
| `Amarula.group_setting/3` | `Amarula.group_update_setting/3` |
| `Amarula.group_ephemeral/3` | `Amarula.group_toggle_ephemeral/3` |

**Argument order** — `jid` now always comes right after `conn`, matching every
other send:

- `Amarula.mark_read(conn, message_ids, jid, participant)` →
  `Amarula.mark_read(conn, jid, message_ids, participant)`
- `Amarula.send_media(conn, type, jid, data, opts)` →
  `Amarula.send_media(conn, jid, type, data, opts)`

**Return shape** — `Amarula.group_requests/2` now returns clean
`[%{jid: Amarula.Address.t(), requested_at: integer | nil}]` instead of raw
string-keyed wire attributes.

### Removed (breaking)

Removed from the `Amarula` facade. These were either a protocol leak or internal
plumbing the library handles for you; the underlying function still exists for
power users:

| Removed | Use instead |
|---------|-------------|
| `Amarula.send_message/3` (took a raw `%Proto.Message{}`) | `Amarula.send_text/3` & friends, or `Amarula.Connection.send_message/3` |
| `Amarula.request_resend/2` | `Amarula.Connection.request_resend/2` |
| `Amarula.resolve_lid/2` | `Amarula.Contacts.resolve_lid/2` (addressing resolves automatically on send) |
| `Amarula.normalize_jid/2` (was `canonical_jid`) | `Amarula.Connection.canonical_jid/2` |

### Documentation

- Dropped internal jargon ("wire jid", "boundary", "total function", "canonical")
  from the consumer-facing docs in favour of plain language.

## [0.1.0] - 2026-06-19

First public release.

### Added

- **Offline sandbox + `Amarula.Testing`** — test your bot's receive→reply logic
  with no WhatsApp connection. `Amarula.new(%{profile: x, offline: true})` runs a
  connection with no socket whose `send_*` calls short-circuit to `{:ok, msg_id}`
  (no encrypt, no frame, no real-world effect). `Amarula.Testing.start_offline/1`
  starts one; `deliver_text/2` and `deliver/2` feed synthetic inbound messages
  through the real decode/classify pipeline, so your bot receives a true
  `%Amarula.Msg{}`. `send_media/5` is unsupported offline (needs a live socket).
- `Amarula.list_profiles/1` — list the profiles that have stored credentials in a
  given storage source (a `Conn`, a `Storage.Scope`, or a `{adapter, opts}` /
  bare-opts storage spec). Returns the names you'd pass as `:profile` to reconnect.
- `Amarula.list_profiles_with_metadata/1` — like `list_profiles/1`, but each entry
  carries the logged-in identity read from that profile's creds
  (`%{profile, jid, lid, name}`), for building account pickers.
- `Amarula.Storage` gains an optional `list_profiles/1` behaviour callback,
  implemented by the `File` and `DETS` adapters. Adapters that don't implement it
  report `{:error, :not_supported}`.

### Changed

- **Teardown API reworked.** `wipe_credentials/1` is now the single destructive
  path: it unlinks the companion server-side (`remove-companion-device`, the phone
  drops the device), wipes **all** local storage for the profile, then disconnects.
  After it, the profile must be re-paired.

### Removed

- **`Amarula.logout/1` removed.** For a non-destructive teardown that keeps
  credentials, use `disconnect/1` (closes the websocket only) or `stop/1` (takes
  the supervision tree down and frees the profile slot). The server-side
  device-unlink now lives only in `wipe_credentials/1`.

[Unreleased]: https://github.com/tubedude/amarula/compare/v0.1.1...HEAD
