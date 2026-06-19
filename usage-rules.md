# Amarula usage rules

Amarula is a WhatsApp Web client for Elixir — an idiomatic OTP port of Baileys. You
connect the way the web/desktop app does: pair once by scanning a QR code (or with a
phone-number link code), then send and receive messages from Elixir.

These rules describe how to **use** the `Amarula.*` public API correctly. They are for
agents writing consumer code against the library, not for working on the library itself.

## Core mental model

- **There is no global connection.** Every call takes a `conn` handle (first argument).
  You can run many WhatsApp accounts side by side; each is an independent supervision
  tree. Do not reach for an implicit/singleton connection — there isn't one.
- **A `conn` is a pid, a registered name, or a `:via` tuple.** Get one from
  `connect/2`; resolve a profile back to a live handle with `Amarula.whereis/1` or get a
  restart-safe handle with `Amarula.via/1`.
- **Don't store the raw pid from `connect/2` long-term.** On a crash the connection
  restarts under a new pid and the old one is dead. For anything held across time
  (GenServer state, a long-lived process), store the **profile** and use
  `Amarula.via(profile)` — it always resolves to the current pid.
- **A `:profile` is the account's identity + storage scope.** Naming a profile is what
  lets the next run reconnect without a fresh QR. Pass `%{profile: :name}` to `new/1`.
- **Amarula is NOT a message store.** It keeps only what the protocol needs (creds,
  Signal sessions, device/LID maps). It does NOT keep a chat list, contact list, inbox,
  or scrollback. Incoming messages are delivered **once** via an event, then forgotten.
  If your app needs history or an inbox, persist it yourself from the events.

## Connecting

The builder is Req-style: `new/1` builds a `%Amarula.Conn{}` value, then `connect/2`
starts it. Events go to `:parent_pid` (default: the caller).

```elixir
{:ok, conn} =
  Amarula.new(%{profile: :me})
  |> Amarula.connect(parent_pid: self())
```

`new/1` fills in all protocol defaults; you usually pass only `:profile` (plus optional
`:storage` and overrides). Only one connection per profile may run at a time —
connecting an already-live profile returns `{:error, {:already_running, pid}}`; use
`Amarula.whereis(profile)` to get the existing one.

Lifecycle:
- `disconnect/1` — close the websocket; keep the tree up (pair with `reconnect/1`).
- `stop/1` — take the whole tree down and free the profile slot (accepts a pid or a profile name).
- `wipe_credentials/1` — destructive: unlink on WhatsApp's side, wipe all local storage, disconnect. Requires re-pairing.

List stored accounts without connecting via `Amarula.list_profiles/1` /
`list_profiles_with_metadata/1`, passing a storage spec (e.g. `storage: "./auth"`).

## Pairing (first run)

Events arrive as `{:amarula, type, data}`. On first run you receive a QR code to render:

```elixir
receive do
  {:amarula, :connection_update, %{qr: qr}} when is_binary(qr) ->
    qr |> QRCode.create() |> QRCode.render(:png) |> QRCode.save("qr.png")
end
```

- The `qr` is a **plain string** — YOU render it (terminal, PNG, `<img>`). There is no
  built-in renderer. Render it **as-is**; do not reformat it.
- The `ref` inside rotates ~every 20s, so each rotation emits a fresh
  `:connection_update` with a new `qr`. Re-render on each one.
- After the user scans: `:pairing_success`, then an automatic 515 restart, then
  `:connection_update` with `connection: :open`. **Wait for `:open` before sending.**

Phone-number (link-code) pairing instead of QR: during the QR window (on the first
`qr` event), call `Amarula.request_pairing_code(conn, phone, opts)`. Returns
`{:ok, code}` — an 8-char code the user types into WhatsApp → Linked Devices → "Link
with phone number". Also delivered as a `:pairing_code` event.

## Addressing

A send target (`jid`) is either:
- a **wire jid string** — `"<number>@s.whatsapp.net"` for a person, `"<id>@g.us"` for a
  group, or
- an **`Amarula.Address`** — build one from a bare number with `Amarula.Address.pn/1`.

WhatsApp multi-device uses both **LID** (`<n>@lid`) and **phone-number**
(`<n>@s.whatsapp.net`) addresses for the same person. Amarula tracks the mapping and
resolves addressing for you on send, so you rarely need to convert by hand.

## Sending

All sends return `{:ok, msg_id}` or `{:error, reason}` (e.g. `:not_on_whatsapp`).
Sends are synchronous (they block until the send pipeline finishes); sends to different
recipients complete independently.

```elixir
Amarula.send_text(conn, jid, "hello")
Amarula.send_media(conn, jid, :image, File.read!("pic.jpg"), caption: "hi")   # raw bytes, not a path/base64; :image|:video|:audio|:document|:sticker
Amarula.send_reaction(conn, message_key, "👍")   # "" removes the reaction
Amarula.send_edit(conn, message_key, "fixed typo")
Amarula.send_revoke(conn, message_key)            # delete for everyone
Amarula.send_location(conn, jid, lat, lng, name: "...")
Amarula.send_contact(conn, jid, display_name, vcard)

{:ok, msg_id, secret} = Amarula.send_poll(conn, jid, "Q?", ["A", "B"], selectable: 1)
# Keep `secret` to tally votes (Amarula.Protocol.Messages.Poll).
```

A `message_key` (for reactions/edits/deletes) is the **`key` field of a message you
received** — that is how you point at a specific message.

Presence/typing: `set_presence/2` (`:available`/`:unavailable`),
`send_chatstate/3` (`:composing`/`:recording`/`:paused`), `subscribe_presence/2`,
`mark_read/4` (`mark_read(conn, jid, message_ids, participant \\ nil)`).

## Receiving

Incoming events arrive at `parent_pid` as `{:amarula, type, data}`. The main one is
`:messages_upsert`, whose `data.messages` is `[%Amarula.Msg{}]` — the consumer-friendly
view (`type` + `content`), **never the raw protobuf**. Match on `msg.type`.

```elixir
def handle_info({:amarula, :messages_upsert, %{messages: messages}}, state) do
  for msg <- messages, do: handle_message(msg)
  {:noreply, state}
end
```

Event types (see `t:Amarula.event/0` for the full list): `:connection_update`,
`:messages_upsert`, `:chats_update`, `:contacts_update`, `:group_update`,
`:receipt_update`, `:presence_update`, `:blocklist_update`, `:pairing_code`,
`:pairing_success`, `:history_sync`, `:error`.

There is **no `:creds_update`** — Amarula persists credentials itself, scoped to the
profile. Do not write credential-saving code; name a profile and it reloads on connect.

### Media

Inbound media carries only metadata (directPath/mediaKey), **not the bytes**. Fetch them
lazily:

```elixir
%Amarula.Msg{type: :media} = msg
{:ok, bytes} = Amarula.download_media(msg)   # {:error, :bad_mac} on integrity failure
```

### Avoiding self-send feedback loops

To ignore messages this app/device itself sent (e.g. an agent in a self-chat), read your
own device id **once** and compare per message:

```elixir
own_device = Amarula.own_address(conn).device   # constant after login; read once
# per message:
if msg.from_me and msg.from.device == own_device, do: :ignore
```

### Replies / quoted messages

`Amarula.resolve_quoted(conn, msg)` resolves the message a reply quotes: returns
`{:ok, %Amarula.Msg{}}` if WhatsApp shipped the inline copy, else `{:requested, id}`
(the original re-arrives async via `:messages_upsert`), or `{:error, :not_a_reply}`.

## History sync

`:history_sync` events deliver WhatsApp's own history (chats/contacts/messages) **as
events to store** — not a queryable archive Amarula maintains. Request older history on
demand with `Amarula.fetch_history(conn, oldest_key, oldest_ts, count)`; it arrives
**asynchronously** via a later `:history_sync` event.

## Groups

All group operations live on **`Amarula.Group`**. Group jids are `"<id>@g.us"`.

Read: `Amarula.Group.metadata(conn, group)`, `Amarula.Group.list(conn)`.

Manage (all return `:ok`/`{:ok, ...}`/`{:error, {:group_op_failed, code, text}}`):
`Group.create/3`, `Group.leave/2`, `Group.update_subject/3`,
`Group.update_description/3`, `Group.participants/4` (`:add`/`:remove`/`:promote`/
`:demote`), `Group.update_setting/3` (`:announcement`/`:locked` …),
`Group.member_add_mode/3`, `Group.join_approval_mode/3`, `Group.toggle_ephemeral/3`,
`Group.invite_code/2`, `Group.revoke_invite/2`, `Group.accept_invite/2`,
`Group.invite_info/2`, `Group.requests/2`, `Group.request_update/4`.

## Contacts & profile

Contacts on **`Amarula.Contacts`**: `on_whatsapp(conn, phones)`,
`fetch_status(conn, jids)`, `resolve_lid(conn, phones)`.

Profile on **`Amarula.Profile`**: `picture_url(conn, jid, type)`,
`update_status(conn, status)`, `update_picture(conn, jid, jpeg)`,
`remove_picture(conn, jid)`.

## Testing your bot

To test message-handling logic — "when a message like X arrives, does my bot reply
with Y?" — use `Amarula.Testing`, **not** Mox. Mox mocks behaviours your code *calls
out to*; the bot's input is an event in its mailbox and its reply is a call *into*
Amarula, so there is nothing for Mox to attach to. Instead, run an **offline sandbox
connection**: inbound messages are the ones you deliver, and outbound sends
short-circuit to `{:ok, msg_id}` without touching any network.

```elixir
{:ok, conn} = Amarula.Testing.start_offline(profile: :test)

# Feed an inbound message (runs the REAL decode/classify pipeline → a true %Msg{}).
Amarula.Testing.deliver_text(conn, from: "15551234567@s.whatsapp.net", text: "ping")

# Your bot receives :messages_upsert and replies. In sandbox mode the reply
# returns {:ok, id} and sends nothing — no encrypt, no frame, no real message.
assert_receive {:amarula, :messages_upsert, %{messages: [%Amarula.Msg{}]}}
```

- `start_offline/1` returns the same `conn` handle as `connect/2`; pass it to
  `send_text/3` etc. Events go to `:parent_pid` (default: the caller), so
  `assert_receive` works in the calling test.
- Equivalent to a normal connection built with `Amarula.new(%{profile: x, offline:
  true})` — `offline:` is a real connection property, not test-only magic.
- `deliver/2` takes any `%Amarula.Protocol.Proto.Message{}` for media/reactions/etc.
- `send_media/5` is the one send that does NOT work offline (it uploads media, which
  needs a live socket).

## Common mistakes to avoid

- Calling a send before `connection: :open` — wait for the open event.
- Expecting a "list my chats/conversations" call — there is none; build it from events.
- Treating `:messages_upsert` as queryable/replayable — it fires once per message.
- Writing credential-persistence code — Amarula owns creds; just name a profile.
- Reformatting the QR string, or expecting a built-in QR image — render the raw string yourself.
- Reaching for a global/singleton connection — every call takes an explicit `conn`.
- Stashing the raw pid from `connect/2` in long-lived state — it dies on a restart; store the profile and use `Amarula.via/1`.
- Assuming inbound media includes bytes — call `download_media/1`.
- Reaching for Mox to test your bot — use `Amarula.Testing` (offline sandbox) instead.
