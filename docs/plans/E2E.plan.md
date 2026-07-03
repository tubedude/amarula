> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Two-Amarula-client e2e (hands-off, plugin-driven)

Boot two `Amarula.Examples.Connection` GenServers (two real accounts we control)
on one VM and let them drive each other via recv-pipeline plugins. Validates the
whole messaging loop end to end with no phone tapping.

Accounts: `:primary` (already linked) + `:guest` = 5511999999999 (first run needs
a QR scan on its own profile dir).

## Layout (examples/, gitignored creds)
- `examples/e2e.exs` — runner: start both, print guest QR if unpaired, kick off
  one ping from primary, keep alive, log the auto-conversation.
- `examples/e2e/harness.ex` — `E2E.Harness`: starts the two Connections with the
  right profiles/names + attaches the role plugins.
- `examples/e2e/plugins.ex` — the test plugins (recv-pipeline steps).

## Roles (asymmetric → bounded, no infinite loop)
- **guest**: on incoming **text from primary** → reply `"ack: <text>"` (one text).
- **primary**: on incoming **text from guest** → react 👍 + `mark_read` (terminal:
  a reaction isn't text, so guest's text-trigger doesn't fire again).

One primary message → one round trip → stop.

      primary --"e2e ping"-->        guest
      guest   --"ack: e2e ping"-->   primary
      primary --👍 + read-->         guest      (STOP)

## Plugins (Req-style, parameterized at attach)
Each plugin needs: the *peer* address to match incoming, and the *own* connection
pid to send the response.

    Reply.attach(conn, from: primary_addr, via: self_pid, prefix: "ack: ")
    ReactRead.attach(conn, from: guest_addr, via: self_pid, emoji: "👍")

They're **recv steps**: inspect the classified message; if it's text from the
expected peer, fire the response (side effect) and `{:cont, ctx}` (don't drop —
still surface to logs). The response send is async (cast), so the recv pipeline
doesn't block.

NOTE: the recv step only has the message; to send a reaction it needs the
message **key** (remoteJid+id+fromMe). The :messages_upsert event carries id+from;
the step builds a MessageKey from those. (May need the step ctx to include the
message key — small addition to the recv ctx if not already there.)

## What it proves
- 1:1 send + receive (both directions)
- text classify on receive
- reactions (primary → guest)
- read receipts (primary → guest)
- (extend later) group send, media, edit/revoke by adding scripted kicks

## What it does NOT prove
- **app-state sync (C2)**: that syncs *within one account's devices*, not between
  two accounts. Two separate accounts don't trigger each other's app state. C2
  still needs a same-account second-device or a phone-side chat change to verify.

## Open / first-run
- guest pairing: `examples/e2e.exs` prints guest's QR (its profile is empty on
  first run); scan with the 5511999999999 phone once. Creds persist in
  amarula_data/guest/.
- primary creds: migrate existing (amarula_data/primary/) or re-pair.

## Steps to build
1. recv ctx: ensure a step can build the message MessageKey (id+from+fromMe).
2. plugins.ex: Reply + ReactRead recv-step plugins (parameterized attach).
3. harness.ex: start both Connections with profiles + attach role plugins.
4. e2e.exs: boot, pair guest if needed, send one primary→guest ping, stay alive.
5. live run: scan guest QR, watch the auto round-trip; confirm on both phones.
