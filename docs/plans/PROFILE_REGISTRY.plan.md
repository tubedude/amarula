> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Plan: profile-keyed connection registry (one-per-node + cluster seam)

## Goals

1. **Stable consumer handle.** A consumer refers to its connection by `profile`,
   not a raw pid. Survives a Connection restart (pid changes, profile doesn't).
2. **One connection per profile (per node).** Starting a profile that's already
   running returns the existing handle / an error — never a second websocket.
   (Two sockets on one `creds.term` corrupt the Signal ratchet — a correctness
   bug, not just waste.)
3. **Cluster-ready, not cluster-opinionated.** The registry is a config seam so a
   clustered consumer can swap the local `Registry` for `Horde.Registry` / a
   `:global`-backed module to get cluster-wide uniqueness — without the library
   depending on any clustering stack or imposing a CAP choice.

Out of scope (deliberately): built-in cluster singleton, Horde dep, netsplit
arbitration. Cross-node uniqueness is the consumer's deployment concern; we only
provide the seam + docs. (See "Cluster notes" below.)

## The uniqueness key: `profile`

The registry key is the **`profile`** — the consumer's connection label, which
already scopes storage (`creds.term` lives under it). The library treats one profile
as one set of credentials and dedups on that.

**Uniqueness is the consumer's responsibility.** The library trusts `profile ⇔ creds`
1:1; it does NOT derive a fingerprint from the credentials or validate that a profile
is reused with consistent creds. A consumer that distributes creds across a cluster
already owns identity placement, so it owns the labeling too. If two configs reuse
one profile name for different creds (or split one set of creds across two profiles),
that is a provisioning bug on the consumer side — the library won't catch it.

This keeps the library simple: no fingerprint code, profile is already everywhere
(storage scope, `Conn.profile`), and the registry just reuses it as the key.

## Uniqueness reach = the registry's reach

The library enforces "one active conn per profile **within the registry it is
given**." The consumer chooses the reach:
- default local `Registry` → one-per-**node**;
- a cluster registry (`Horde.Registry`, a `:global`/`:pg` shim) → one-per-**cluster**,
  for free, because "already registered" now means "running anywhere in the cluster."

So: **the consumer distributes creds + picks the registry; Amarula enforces
uniqueness against whatever reach that registry has.** The library never decides
clustering — it trusts the `:via` contract.

## Duplicate start = error (not idempotent)

A second start for a live profile returns `{:error, {:already_running, pid}}`.
Chosen over idempotent `{:ok, existing_pid}` so a real double-start (the bug we are
preventing — two sockets on one ratchet) is surfaced, never silently swallowed.
`Amarula.whereis/1` is the explicit "give me the existing one" path.

## Design

### A profile registry, separate from the per-instance Registry

The existing per-instance `Registry` (keyed `{instance_id, role}` + `recipient_jid`)
is intra-tree wiring and stays. This adds a **second, app-level registry** keyed by
`profile`, mapping `profile -> Connection pid`. One registry for the whole node (or
cluster, if swapped), not one per instance.

Started once in the application supervisor:

```
Amarula.Application
└── {Registry, keys: :unique, name: Amarula.ProfileRegistry}   # default (local)
```

(If the app isn't started — library-embedded with no `Application` — `make_socket`
ensures it lazily, or we require the host to add it. Lean: start it in our
`Application`; document the embed case.)

### Connection registers under its profile

`Connection.start_link` registers a second name: the profile, via the configured
registry module. Two registrations:
- intra-tree: `{:via, Registry, {per_instance_reg, {instance_id, :connection}}}` (today)
- app-level:  `{:via, reg_mod, {profile_reg, profile}}` (new)

A GenServer can only take one `name:`. So the profile registration is a separate
`Registry.register/3` call inside `Connection.init` (or `handle_continue`), not the
`name:` arg. On restart, `init` re-registers the same profile key → the consumer's
profile ref keeps resolving. Registry auto-unregisters on death.

### make_socket / start_instance: enforce one-per-profile

Before starting the tree, check the profile registry:

```elixir
case whereis_profile(conn.profile) do
  pid when is_pid(pid) -> {:error, {:already_running, pid}}
  nil -> ConnectionSupervisor.start_instance(conn, opts)
end
```

Race: two near-simultaneous starts both see `nil`. The registration inside
`Connection.init` is the atomic tiebreaker — the second Connection's
`Registry.register` returns `{:error, {:already_registered, pid}}`; it then stops
`:normal` and `start_instance` surfaces `{:error, {:already_running, pid}}`. (So the
check is a fast-path; the registry is the real guard.)

### Facade: refer by profile

`Amarula.connect/2` still returns a handle, but the handle becomes
**profile-addressable**. Options:

- **A. Return the pid as today, but add `Amarula.whereis(profile)` + accept a
  profile atom anywhere a `conn()` is accepted.** The `conn()` type widens to
  `pid() | profile`. Each facade call resolves a profile to the live pid via the
  registry. Backward-friendly, explicit.
- B. Return an opaque handle struct `%Amarula.Ref{profile: ...}`. Cleaner but
  churns every call site + the consumer's stored handle.

Pick **A** (smaller, and a bare pid still works). Internals: a private
`resolve(conn_or_profile) -> pid` at the top of each delegating call (or push it
into `Connection` once). `connect` returns the pid for continuity;
`Amarula.whereis(profile)` and passing the profile atom are the restart-safe paths.

### Config seam for the registry module

`config[:registry]` (default `Registry` / `Amarula.ProfileRegistry`). A clustered
consumer sets e.g. `registry: {Horde.Registry, MyApp.HordeReg}`. The library calls
through a tiny indirection:

```elixir
defp via(conn, profile), do: {:via, reg_mod(conn), {reg_name(conn), profile}}
```

`Horde.Registry` and `:global` (via a shim) implement the same `:via` contract, so
swapping is config-only. Document the two known-good swaps.

## Files

- `lib/amarula/application.ex` — start `Amarula.ProfileRegistry` (default local).
- `lib/amarula/connection.ex` — `init` registers the profile via the seam;
  `make_socket` does the pre-check + maps `{:already_registered, pid}` →
  `{:error, {:already_running, pid}}`; add `whereis/1`.
- `lib/amarula/protocol/socket/connection_supervisor.ex` — thread the registry
  module/name (from `conn.config`) so the check uses the configured registry.
- `lib/amarula.ex` — `connect` unchanged return; add `whereis/1`; `resolve/1`
  helper so facade calls accept a profile atom; widen `conn()` typespec.
- `lib/amarula/config.ex` — document `:registry` (default local Registry).
- `docs/INFRASTRUCTURE.md` — add the profile-registry layer + cluster notes.

## Tests

- start a profile twice → second returns `{:error, {:already_running, pid}}`, only
  one websocket/tree exists.
- `Amarula.whereis(profile)` returns the live pid; nil when not running.
- facade call by profile atom routes to the live pid.
- Connection restart re-registers the profile (whereis resolves to the NEW pid).
- death unregisters (whereis → nil after stop).
- custom registry module via config is honored (use a stub `:via`-compatible
  module to prove the seam without a Horde dep).

## Cluster notes (for the doc, not code)

- Default local `Registry` = one-per-**node**. Two nodes can still each start the
  same profile — that's the consumer's deployment problem.
- For one-per-**cluster**: swap in `Horde.Registry` (+ Horde.DynamicSupervisor for
  handoff) or a `:global`/`:pg` shim. `:global` is best-effort: a netsplit can
  briefly allow two registrations that reconcile (one killed) on heal — acceptable
  for many, not all.
- The robust production answer is usually external: a DB row / Redis lease the
  consumer's orchestrator holds per profile, deciding which node runs it. The
  library's seam composes with that — it doesn't replace it.
