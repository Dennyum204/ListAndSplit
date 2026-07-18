# List & Split architecture

## Status and scope

This is the agreed target architecture for the product. It distinguishes durable
constraints from planned components; it is not an implementation-progress report.
Source code, tests, migrations, and pull requests are the evidence of implementation
status. Offline caching, push delivery, and later product areas remain sequenced by
the roadmap.

## Fixed platform choices

| Concern | Decision |
| --- | --- |
| Client | Flutter stable; Android and iOS only |
| Display name | `List & Split` |
| Dart/Flutter project name | `list_and_split` |
| Android application ID and namespace | `com.ferbatech.listandsplit` |
| iOS bundle identifier | `com.ferbatech.listandsplit` (derived test identifiers are allowed) |
| Design system | Material 3, with light and dark themes |
| Initial language | English, with localization-ready structure |
| State and dependency injection | Riverpod |
| Navigation | `go_router` |
| Backend | Supabase Auth, PostgreSQL, RLS, Realtime, Storage, database functions, and Edge Functions |
| Offline direction | Local SQLite cache, introduced in a later phase |
| Package policy | Current stable compatible releases; no prerelease packages |

## Client composition

The application composition path is intentionally small:

```text
main.dart
  -> ProviderScope
     -> app composition
        -> MaterialApp.router
           -> go_router route tree
              -> feature views
```

`main.dart` should contain process bootstrapping rather than feature behavior. The
`app/` layer owns the root widget, router, and only truly app-wide providers.
Shared configuration and themes live in `core/`; localization resources live in
`l10n/` and are consumed through Flutter's generated localization API.

The intended repository shape is:

```text
lib/
  main.dart
  app/
  core/
  l10n/              # ARB sources; generated Dart stays untracked
  features/
    <feature>/
      presentation/   # views, widgets, and MVVM-style view models/providers
      domain/         # feature rules and transport-independent models, when needed
      data/           # repository implementations, DTOs, and adapters
test/
supabase/
  migrations/
docs/
```

This shape is a direction, not a request to create empty directories. A feature
should remain shallow until its complexity justifies separation.

## Boundaries and dependency rules

### Presentation and state

- Widgets render immutable state and forward user intent. They do not query
  Supabase, SQLite, or HTTP clients directly.
- Riverpod providers/view models own UI state transitions, asynchronous loading,
  and coordination of repository operations.
- View models should expose meaningful feature state rather than transport DTOs or
  raw backend exceptions.
- App-wide state belongs in `app/` only when multiple features genuinely share its
  lifetime. Feature providers stay with their feature.

### Domain and repositories

- Repositories are the client data source of truth and the boundary through which
  feature code reads or mutates data.
- Repository contracts express product operations. Supabase row shapes, SQLite
  records, and realtime payloads are implementation details behind those contracts.
- Business rules should be implemented as small, deterministic Dart units where
  the client needs them, while authoritative authorization and monetary results
  remain server-side.
- Cross-feature helpers enter `core/` only when they are stable, non-product-specific,
  and used by more than one feature. Avoid a generic utilities dumping ground.

For the identity slice, an authentication repository owns session and credential
operations and a profile repository owns profile reads/onboarding updates.
Supabase-backed implementations remain in feature data layers. Riverpod providers
and view models depend on the repository contracts, so validation, asynchronous
state, sign-out, recovery, onboarding, and redirects can be tested with fakes and
without a live Supabase project.

The initial community slice follows the same boundary: a community repository owns
exact-username discovery and outgoing block management. Its Supabase implementation
calls only reviewed RPC contracts. Widgets and Riverpod controllers never query
profiles or block rows directly, and community behavior remains testable with
repository fakes.

Friend-request and friendship behavior extends that repository boundary with
caller-relative relationship summaries, active relationship lists, and reviewed
mutation RPCs. Widgets and controllers receive domain models rather than physical
relationship states or database rows. Repository failures, including stale-version
conflicts, are translated into privacy-safe feature outcomes and refresh behavior.

### Generated models

Freezed and JSON serialization may be used for immutable state and boundary
models. Generated files are regenerated with `build_runner`; they are not edited
by hand. Domain modeling should not be forced into serialization shapes merely
because code generation is available.

## Navigation

`go_router` owns a single root route graph and future deep-link handling. The
planned main shell has four destinations: Lists, Templates, Community, and
Profile. Notifications open from a bell and must not become a fifth destination.

Routing resolves these gates in order before entering an authenticated destination:

1. Required public backend configuration is available.
2. An authenticated session exists.
3. The session's email is verified.
4. The current user's profile onboarding is complete.

The missing-configuration state has a clear non-secret development screen. An
unauthenticated user sees authentication flows; an authenticated but unverified
user sees verification-pending/resend behavior; and a verified user with an
incomplete profile sees onboarding. Password-recovery Auth events route to the
new-password flow rather than normal signed-in content. A non-secret local marker
preserves that recovery gate across process restarts until password update,
explicit sign-out, or a normal sign-in succeeds; it is navigation state only and
is never treated as authentication or authorization evidence.

The registered mobile Auth callback is
`com.ferbatech.listandsplit://auth-callback` on both Android and iOS, without
changing either platform identifier. Final signed-in route nesting, restoration,
notification-link behavior, and other feature deep links remain open. Redirect
decisions are centralized and covered by navigation/widget tests.

Exact community discovery and blocked-user management are authenticated,
post-onboarding routes. They use the same configuration, session, verification,
recovery, and onboarding gates as the foundation and profile destinations. This
does not introduce the planned four-tab root shell.

Friendship management and request actions use those same gates and are reachable
from Community. Their delivery does not introduce persistent notifications,
Realtime, push delivery, public profiles, shared lists, or the final four-tab
shell.

## Backend architecture

### Supabase responsibilities

- **Auth** identifies the current user; application authorization is still enforced
  by RLS and server-side checks. The initial release uses verified email/password
  accounts only and supports sign-up, sign-in, sign-out, resend verification,
  forgotten-password, and password recovery.
- **PostgreSQL** stores authoritative product records and relationships.
- **Row Level Security** restricts every application table by identity,
  membership, ownership, or recipient relationship.
- **Realtime** will deliver relevant list and notification changes after its
  authorization and reconciliation behavior is designed.
- **Storage** is available for future binary objects, with object policies aligned
  to the owning application records. No concrete storage use is yet agreed.
- **Database functions** and, where appropriate, **Edge Functions** hold atomic or
  privileged server operations. Authoritative balance and debt calculations run
  server-side and require unit tests.

Database migrations committed under `supabase/migrations/` are the only schema
source of truth. Every schema change must be introduced by a reviewed migration
with database/RLS tests. The conceptual contracts are in
[`DATA_MODEL.md`](DATA_MODEL.md).

### Initial profile boundary

`public.profiles` has a one-to-one primary-key/foreign-key relationship with
`auth.users`. A controlled server-owned mechanism creates the record with nullable
onboarding fields when an Auth identity is created. Email and credentials stay in
Auth and are never copied into the profile.

PostgreSQL, rather than Flutter alone, canonicalizes and validates usernames,
enforces global uniqueness, and prevents username changes after onboarding.
Display name remains an approved editable field. The database-managed
`onboarding_completed_at` timestamp is set when both onboarding fields are valid,
so route gating does not infer completion from UI state. `created_at`, `updated_at`,
and onboarding completion are not client-editable.

RLS is enabled when the profile table is created. The Data API receives explicit
least-privilege grants: an authenticated user can select their own profile and
update only `username` and `display_name`. Anonymous access, cross-user
read/mutation, and direct client insert/delete are denied. Authorization is based
on `auth.uid()`, never `user_metadata` or another user-editable JWT field. Any
server function that crosses the Auth/application boundary uses qualified object
names, a pinned safe `search_path`, revoked default execution, and the minimum
required rights.

### Blocking and discovery boundary

Active blocks are directional rows between two fully onboarded profiles, with one
active row per direction, a self-block constraint, and a database-managed creation
timestamp. They remain separate from the friendship relationship state.
Account deletion behavior is unresolved, so block foreign keys do not silently
select cascading deletion semantics.

The block table is not a general client-readable or client-writable Data API
surface. Authenticated application access uses narrowly granted functions for:

- exact canonical-username discovery;
- idempotent block creation;
- idempotent removal of the caller's outgoing block; and
- the caller's private outgoing-block projection.

These contracts derive the actor only from `auth.uid()`, require completed caller
and target profiles where relevant, and return only profile ID, username, and
display name. Discovery excludes self and any pair blocked in either direction.
Missing and block-suppressed targets have the same empty result. The existing
owner-only profile policy is not broadened. The relationship-summary RPC follows
the same separation rule: an active block in either direction returns no row and
no target profile projection. Only the private outgoing-block management RPC may
show a blocker the profile they blocked.

Cross-user profile projection requires a deliberately small `security definer`
boundary. Every privileged function has an empty pinned `search_path`, fully
qualified references, explicit caller validation, revoked default execution, and
an exact `authenticated` signature grant. Anonymous execution and unrestricted
table access remain denied. Block/unblock operations are atomic and idempotent.

Friend requests and friendships use one persistent, versioned current relationship
row per unordered profile pair rather than contradictory directional states,
separate request/friendship tables, or an unlimited event log. Blocks remain
directional records outside that state. Creating a block and any resulting
relationship transition occur atomically; unblocking changes only the block row.

### Friendship relationship boundary

The physical relationship row uses the normalized low/high profile IDs as its
composite identity. It stores one check-constrained text state (`pending`,
`friends`, `cancelled`, `declined`, or `ended`), the most recent requester, an
optional reopening controller, a positive monotonic version, a server-owned
creation time, and a server-owned state-change time. Only declined and ended rows
have a reopening controller. Participant foreign keys do not cascade while account
deletion and retention remain unresolved.

The relationship table is RPC-only. Its creating migration enables RLS, revokes
table privileges from `PUBLIC`, `anon`, `authenticated`, and `service_role`, and
adds one restrictive `FOR ALL` policy for `anon` and `authenticated` with
`USING (false)` and `WITH CHECK (false)`. Existing owner-only profile policies
remain unchanged. Authenticated application access is limited to reviewed
functions for:

- a caller-relative summary for one target;
- the caller's active incoming, outgoing, and friend lists;
- sending a request;
- cancelling an outgoing request;
- accepting or declining an incoming request; and
- ending a friendship.

These functions derive the actor only from `auth.uid()`, require a verified,
fully onboarded caller and a fully onboarded target, reject self-pairs, normalize
the pair deterministically, and recheck either-direction blocks inside the
protected transition. Mutations use one
consistent transaction-level pair lock and row lock strategy so concurrent first
sends, crossed sends, blocks, and relationship actions cannot create contradictory
state or deadlock through inconsistent ordering.

Duplicate sends and repeated already-completed caller-authorized actions are
no-ops: they do not change the version or timestamp. Every real transition
increments the version exactly once and updates the state-change time. Mutations
other than the initial send require the caller's expected version. Send accepts a
nullable expected version: null supports first, duplicate-pending, and crossed-
pending sends from a preloaded result, while reopening a cancelled, declined, or
ended row requires the exact current version. After reopening produces a pending
row, a duplicate retry or crossed send may safely reuse that immediately prior
dormant version; materially older versions still fail stale. Stale or ineligible
actions fail generically without overwriting newer state. A crossed send can
atomically promote a pending request to friendship even when both users acted from
the same dormant preloaded result.

The existing `block_profile(uuid)` signature, identity derivation, pinned empty
`search_path`, exact authenticated grant, and revoked default/anon/service-role
execution remain unchanged. Its implementation is extended in the additive
migration so inserting a block and cancelling/ending an active relationship use
the same pair lock and one atomic transaction.

Caller-facing projections expose only the target profile ID, canonical username,
display name, a relative status (`can-send`, `incoming-pending`,
`outgoing-pending`, `friends`, or `unavailable`), plus nullable version and
state-change time. Privacy-safe `unavailable` results expose neither version nor
state-change metadata; eligible dormant reopeners receive the version required
for the next send. `unavailable` protects declined/ended reopening details; active
blocks return no relationship-summary/profile row at all. They never expose
email/Auth metadata, block direction, raw
declined/ended state to the non-controller, the reopening-controller column,
unrelated relationships, or unnecessary internal timestamps.

### Client configuration

The Flutter client receives its public Supabase configuration at build/run time
through the standardized compile-time names `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY`. Real values are not hardcoded or committed. A
placeholder-only example is:

```text
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

Both values are required for backend-dependent flows. Missing or incomplete
configuration routes to the development-configuration screen while keeping the
app runnable. Only a public anonymous/publishable client key may enter Flutter. A
service-role key or any other privileged secret must never be included in a client
binary.

### Server operation shape

Operations that span records or enforce important invariants should be atomic and
idempotent where retries are possible. Likely examples include accepting an
invitation, accepting/saving a template copy, creating a template snapshot in an
active list, and recording a ledger change. Whether each operation is best served
by a PostgreSQL function or an Edge Function is an open implementation decision.

## Money boundary

- Monetary amount, share, settlement, balance, and debt values are signed or
  unsigned integers in the currency's minor unit, as appropriate to the concept.
- Flutter, JSON contracts, SQL, and tests must not convert authoritative money to
  binary floating point.
- A Payment-Control-enabled active list has one currency; expenses inherit that
  context rather than performing foreign-exchange conversion.
- The server validates participant membership, share totals, settlement endpoints,
  and all calculation invariants.
- Derived balances/debts may be displayed or cached, but the client is not their
  authority.

## Planned offline and realtime model

SQLite will later sit behind repository implementations as an offline-tolerant
cache for active-list usage. Supabase remains authoritative.

A safe future flow is conceptually:

```text
view/view model -> repository -> local cache and sync coordinator -> Supabase
                                      ^                         |
                                      +------ realtime --------+
```

This diagram does not select a synchronization algorithm. Record versioning,
mutation queues, conflict resolution, deletion tombstones, retry semantics, and
the boundary between optimistic and confirmed state must be decided before offline
writes are implemented. Realtime events must be treated as inputs to repository
reconciliation, not as direct UI mutations.

## Error handling, testing, and observability

- Translate infrastructure errors into feature-meaningful failures at repository
  boundaries without discarding diagnostic causes.
- Unit-test deterministic business behavior and view-model transitions without
  network access.
- Use repository contract/fake tests and widget tests for feature flows.
- Test profile routing, verification, recovery, onboarding, and authentication
  view-model transitions with repository fakes rather than a live backend.
- Test RLS policies, database constraints, triggers, and functions with allowed
  and denied identities for every business migration.
- Payment server tests must cover integer arithmetic, equal and exact shares,
  validation, settlements, balances, and debt output.
- Logging must redact tokens, secrets, personal content, and notification payloads.
  A concrete telemetry/crash-reporting service has not been selected.

## Security constraints

- Treat all client input as untrusted, including claimed ownership, list
  membership, payer identity, and notification recipient.
- RLS is required on every application table from the table's first migration.
- Use least-privilege grants and policies, and restrict realtime and storage with
  the same relationship model as database access.
- Prefer invoker-rights functions. Security-definer functions require a fixed
  `search_path`, qualified objects, minimal execution grants, and explicit tests.
- Never expose privileged keys in Flutter or Git.
- Never use destructive commands against a linked remote database.

## Open architecture decisions

- Account deletion/export, retention, and related Auth/profile/block lifecycle.
- Precise feature folder layering and whether Riverpod code generation is used.
- Final authenticated route topology, state restoration, notification links, and
  non-Auth feature deep links.
- Development/staging/production flavor and environment-separation strategy.
- PostgreSQL-function versus Edge-Function placement for each atomic server action.
- Realtime subscription granularity, reconnect/replay behavior, and event ordering.
- SQLite library, cache schema, synchronization algorithm, conflict policy, and
  background execution limits.
- How blocking or relationship changes affect existing shared resources.
- Avatar and other Storage use cases, upload validation, object policies, and
  retention.
- Logging, analytics, crash reporting, performance budgets, and privacy controls.
- FCM/APNs registration, token lifecycle, and notification deep links.
