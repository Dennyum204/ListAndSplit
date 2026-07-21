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
implemented authenticated `StatefulShellRoute.indexedStack` has four destinations:
Lists, Templates, Community, and Profile. Each branch preserves its navigation
stack and state when another tab is selected. Notifications open above the shell
from a bell and must not become a fifth destination.

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
changing either platform identifier. Notification-link behavior and later feature
deep links remain open. Redirect decisions are centralized and covered by
navigation/widget tests.

Exact community discovery and blocked-user management are authenticated,
post-onboarding routes within the Community branch. They use the same
configuration, session, verification, recovery, and onboarding gates as Lists,
Templates, and Profile.

Friendship management and request actions use those same gates and are reachable
from Community. The notification centre uses the same gates and opens on the root
navigator from a bell rather than a fifth destination. The shell introduces no
push delivery, feature deep links, or public profile table access. Its outer
session lifecycle owns one private account Realtime coordinator after verified
onboarding; screens do not create channels.

### Active-list client boundary

The Lists feature follows the existing feature-first
repository/Riverpod pattern under `lib/features/lists/`. Widgets render state and
emit intent; controllers own load, pagination, refresh, mutation,
duplicate-submit, and stale-conflict state; the repository alone translates
domain operations to exact Supabase RPC calls. Backend maps/DTOs do not escape the
data layer.

List providers are keyed by the current verified user identity and are invalidated
on sign-out, account deletion, invalid-session recovery, or identity change. No
global list/member/invitation payload survives a session boundary. There is no
SQLite, offline mutation queue, or optimistic server success. Realtime is an
opaque invalidation input to repository refresh only; stale `40001` failures refresh current
state and never overwrite it. Exact quantity parsing is a domain value that stores
positive integer thousandths and never converts through `double`.

## Backend architecture

### Supabase responsibilities

- **Auth** identifies the current user; application authorization is still enforced
  by RLS and server-side checks. The initial release uses verified email/password
  accounts only and supports sign-up, sign-in, sign-out, resend verification,
  forgotten-password, and password recovery.
- **PostgreSQL** stores authoritative product records and relationships.
- **Row Level Security** restricts every application table by identity,
  membership, ownership, or recipient relationship.
- **Realtime** delivers private, account-scoped, content-free invalidations; RPC
  repositories remain the only state and authorization authority.
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

### Active-list database boundary

`public.active_lists`, `public.active_list_items`, and
`public.active_list_participants` are an RPC-only aggregate. All tables enable and
force RLS, explicitly reject every direct `anon` and
`authenticated` operation, and revoke all table privileges from `PUBLIC`, `anon`,
`authenticated`, and `service_role`. Owner/list cascade foreign keys integrate the
aggregate with Auth-root deletion. A nullable completion-actor foreign key uses
`ON DELETE SET NULL`, so future actor deletion cannot remove an item.

Participant rows retain one non-owner's versioned `pending`, `member`, `declined`,
`cancelled`, `removed`, or `left` state. List-row locking serializes the 20-person
capacity including pending reservations. Pair locks precede deterministic list-row
locks for friendship/block effects. No detailed access history exists.

Exact `postgres`-owned `SECURITY DEFINER` functions derive authority only from
`auth.uid()`, require a confirmed fully onboarded profile, pin an empty
`search_path`, fully qualify objects, expose allowlisted projections, revoke
default execution from every client/admin API role, and grant only exact
signatures to `authenticated`. Listing is bounded keyset pagination: active lists
use `(updated_at, id)` descending; archived lists use `(archived_at, id)`
descending. Aggregate counts are returned in the same list query rather than by
N+1 calls.

Mutations lock the list row before item rows; when multiple items are locked they
use UUID order. Expected positive `bigint` versions reject stale writes with
SQLSTATE `40001`. List metadata changes increment only list version. Item
create/delete/reorder increment list version; item edit/complete/reopen increment
both list and item versions. Real changes update their server timestamps once;
completed retries/no-ops update neither. Creation request UUIDs are payload-bound
idempotency tokens rather than authority. Reorder validates that the submitted
array is non-null and unique and exactly equals the current item set before writing
contiguous positive integer positions in one short transaction. Owner-or-member
item access is rechecked inside each transaction; owner-only metadata and access
operations never trust caller-supplied role or identity.

Realtime uses exactly one private `account:<auth.uid()>` channel per completed
authenticated session, event `invalidate`, and application payload `{"v":1}`.
`realtime.messages` has one authenticated `SELECT` policy requiring extension
`broadcast` and exact equality between `realtime.topic()` and the caller-derived
account topic. There is no authenticated `INSERT` policy, anonymous policy,
Presence policy, public channel, or application-table publication.
The Supabase project Realtime setting **Allow public access** must be disabled;
private configuration is still explicit on both database sends and Flutter joins.

Postgres-owned hardened triggers call `realtime.send(..., true)` inside the same
transaction as real list, participant, notification, relationship, block, and
profile changes. Fanout targets affected account topics and sends no row, resource,
actor, transition, timestamp, or authorization data. A failed or rolled-back
mutation commits no message; duplicate transport signals are harmless.

Only the injected Supabase adapter uses the channel API. A session-scoped
coordinator starts after verified onboarding, removes the old channel before an
account switch, relies on the pinned SDK for token refresh and error/timeout
rejoin, replaces an unexpected closed channel, and reconciles after every
`SUBSCRIBED` state and app resume. Mounted feature controllers register
repository refresh work. One pass runs at a time; bursts mark one dirty follow-up
and are cooldown-bounded. Cached UI remains usable on transport failure. Access
revocation clears inaccessible detail/member content and navigates once to Lists
with generic localized wording. Manual refresh remains a required fallback.

Broadcast is best-effort and has no replay or durable-history promise. Presence,
Broadcast Replay, Postgres Changes client subscriptions, client sends, REST/Edge
fanout, push delivery, and offline mutation are deliberately deferred.

### Account export boundary

Account data export is a parameterless authenticated PostgreSQL RPC that derives
identity only from `auth.uid()`. It requires a confirmed `auth.users` identity and
exactly one corresponding profile but deliberately does not require completed
onboarding. This keeps export available from both verified incomplete Onboarding
and completed Profile without exposing it to anonymous or unverified sessions.

The RPC returns one `jsonb` schema-version-3 document built exclusively from
explicit key allowlists. Version `2` preserves all version-1 account/social roots
and adds the deterministic `active_lists` array with active/archived owned lists and
ordered items. Version `3` adds only caller-relative metadata for lists owned by
others and excludes their items, owner identity, other participants, and internal
authorization data. It is a hardened `SECURITY DEFINER`
boundary because it must read the caller's approved Auth columns and RPC-only
social tables: ownership
is `postgres`, `search_path` is empty, every object is qualified, default
execution is revoked, and only the exact parameterless signature is granted to
`authenticated`. No Auth schema, table privilege, or direct social-table access is
exposed to Flutter.

The export reuses the existing caller-relative privacy contracts. It selects only
outgoing blocks; only active, non-blocked relationship projections; and only
caller-owned notifications that are unsuppressed, unexpired, and not hidden by a
block in either direction. List/item objects likewise use explicit public fields,
exact integer `quantity_thousandths`, and deterministic list/item order while
excluding creation request IDs and internal authorization details. Objects are
constructed field by field rather than by serializing physical rows. The function
is stable and read-only: it does not mark
notifications read, mutate relationships, update Auth, or persist an export job,
file, audit row, Storage object, signed URL, or background task.

Flutter owns version validation and temporary-file presentation behind repository
and injectable file/share-service boundaries. The feature controller is scoped to
the verified session identity, never stores export JSON in global presentation
state, prevents concurrent requests, and clears transient state when identity
changes. The file service writes pretty UTF-8 JSON to application-scoped
temporary/cache storage and invokes the Android/iOS native share sheet with a
privacy-safe UTC filename and JSON MIME type. It never falls back to public shared
storage or promises guaranteed cache deletion. Production responses must be
version `2`; the parser deliberately retains strict version-1 support for
historical fixtures and previously downloaded documents.

### Permanent account-deletion boundary

Permanent account deletion remains separate from export but is available from the
same completed Profile and verified incomplete Onboarding surfaces. Flutter owns a
session-scoped account-deletion repository/controller boundary. It compares the
stored username or Auth email exactly, collects the current password only in the
local obscured field, reauthenticates directly with Supabase Auth without changing
either value, makes the returned session active, and invokes `delete-account` with
only the confirmation. Passwords never enter Riverpod state, an Edge Function,
database call, log, analytic, or error payload.

`delete-account` is a POST-only authenticated Edge Function. Its legacy platform
JWT check is disabled so the pinned `@supabase/server` `auth: 'user'` wrapper is
the sole authentication boundary under the publishable/secret-key system. The
wrapper verifies the user session JWT and builds both the caller-scoped client and
a server-only admin client from platform-injected configuration. The handler
accepts one bounded exact `confirmation` string, first calls the authenticated
validation RPC, and only then calls Auth Admin hard deletion with
`shouldSoftDelete: false` for the wrapper-authenticated caller ID. It never accepts
a target identity or exposes a secret to Flutter.

The narrow `validate_account_deletion(text)` RPC derives user identity from
`auth.uid()` and session identity only from `auth.jwt()`'s `session_id`. A hardened
`postgres`-owned definer boundary verifies one confirmed Auth user, one profile,
and the matching `auth.sessions(id, user_id)` row. Freshness is based only on that
row's actual `created_at`, which must be no more than ten minutes old; JWT `iat`,
token refresh timestamps, and `auth.users.last_sign_in_at` are deliberately
ignored. The RPC compares the completed profile's canonical username or incomplete
profile's Auth email exactly, returns only `true`, and never deletes or mutates.

Auth Admin deletion of `auth.users` is the single atomic database root. Cascading
foreign keys remove the profile, either direction of blocks, either relationship
participant, notification recipient/actor rows, and notifications whose
relationship disappears, plus every list owned by the profile and the list's
items. A `BEFORE DELETE` profile trigger reserves only a
completed canonical username in `private.deleted_username_reservations` with an
expiry exactly 30 days after deletion. A hardened availability helper coordinates
concurrent profile deletion/onboarding, active reservations reject claims, and
expired reservations do not. Migration-managed `pg_cron` physically removes only
expired reservations once daily at 03:17 UTC.

On confirmed success Flutter invalidates session-scoped account, profile, lists,
community, friendship, and notification state, removes the local Auth session,
and routes to sign-in. A lost response triggers authoritative `getUser`
reconciliation: confirmed absence becomes local success, confirmed continued
existence permits a retry, and transient/offline failure preserves the account and
session. The smallest app-resume boundary performs the same authoritative
validation so other devices sign out after deletion without polling or
deletion-specific Realtime.

### Blocking and discovery boundary

Active blocks are directional rows between two fully onboarded profiles, with one
active row per direction, a self-block constraint, and a database-managed creation
timestamp. They remain separate from the friendship relationship state.
Both block participant foreign keys cascade only from the reviewed profile/Auth
account-deletion root. This changes no interactive block behavior.

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
have a reopening controller. Participant foreign keys cascade only from the
reviewed profile/Auth account-deletion root, so either participant's account
removal deletes the current relationship atomically.

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

### Friend-request notification boundary

Friend-request notifications extend the repository boundary without becoming a
second relationship state machine. A notification repository calls only three
reviewed authenticated RPCs: bounded keyset listing, unread count, and bounded
caller-owned mark-read. Flutter receives a domain model with minimal actor profile
data and caller-relative `actionable`, `friends`, or `unavailable` presentation;
it never reads or mutates notification rows directly.

The physical `public.user_notifications` table is initially constrained to
`friend_request`. It records a generated UUID, recipient and actor profile IDs,
normalized relationship participants, the positive relationship version that
created the notification, database-owned creation and exact 180-day expiry,
nullable read time, and nullable permanent suppression time. Profile and
relationship foreign keys cascade only from the reviewed account-deletion root,
including notifications removed through a deleted relationship. A
unique recipient/type/pair/version boundary makes notification creation
idempotent without storing copied profile text, email, Auth metadata, or arbitrary
messages.

The table is RPC-only: RLS is enabled at creation, all direct privileges are
revoked from `PUBLIC`, `anon`, `authenticated`, and `service_role`, and one
restrictive `FOR ALL` policy rejects both client roles. The public RPC signatures
derive identity only from `auth.uid()`, require a verified fully onboarded caller,
pin an empty `search_path`, fully qualify every object, revoke default execution,
and grant only exact signatures to `authenticated`.

Listing orders by `(created_at, id)` newest first with an exclusive cursor and a
safe server maximum. It excludes expired, suppressed, and either-direction-blocked
rows and resolves only actor ID, username, and display name. A row is actionable
only while the current relationship remains the exact pending version with that
actor as requester and the caller as recipient; friendship is projected as
`friends`, and every other visible state is generically `unavailable`. Count uses
the same visibility boundary. Mark-read accepts only a bounded ID array, updates
only caller-owned visible rows, and never accepts a caller identity or client
timestamp.

`send_friend_request(uuid,bigint)` creates the notification in the same locked
transaction only for a real transition into pending. `block_profile(uuid)`
permanently suppresses all unsuppressed pair notifications in the same locked
block transaction. Their public signatures and existing friendship/block
semantics remain unchanged; unblocking never reverses suppression.

Riverpod owns paginated centre state, badge state, in-flight actions, refresh, and
session identity. Opening the centre, pull-to-refresh, app resume, relevant local
friendship actions, and notification actions refresh the appropriate state.
Provider reconstruction on sign-out or identity replacement clears pages,
cursors, actor projections, badge counts, errors, and in-flight actions. A scoped
widget lifecycle observer drives resume refresh without a global observer or
continuous polling.

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
idempotent where retries are possible. The owner-only list aggregate uses exact
PostgreSQL RPCs because its validation, locking, version checks, and writes belong
in one short database transaction. Future examples include accepting an
invitation, accepting/saving a template copy, creating a template snapshot in an
active list, and recording a ledger change; placement for those operations remains
open.

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

## Implemented realtime and planned offline model

SQLite will later sit behind repository implementations as an offline-tolerant
cache for active-list usage. Supabase remains authoritative.

The current online flow and future cache placement are conceptually:

```text
view/view model -> repository -> local cache and sync coordinator -> Supabase
                                      ^                         |
                                      +------ realtime --------+
```

Realtime currently enters the repository reconciliation side of this boundary;
it never mutates UI state directly. The diagram does not select an offline
synchronization algorithm. Record versioning,
mutation queues, conflict resolution, deletion tombstones, retry semantics, and
the boundary between optimistic and confirmed state must be decided before offline
writes are implemented.

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

- Shared-resource ownership/deletion, administrator deletion, moderation/legal
  retention, Storage cleanup, and compliance obligations beyond the implemented
  current-aggregate account lifecycle.
- Precise feature folder layering and whether Riverpod code generation is used.
- Notification links and later non-Auth feature deep links beyond the accepted
  four-tab shell.
- Development/staging/production flavor and environment-separation strategy.
- PostgreSQL-function versus Edge-Function placement for each atomic server action.
- SQLite library, cache schema, synchronization algorithm, conflict policy, and
  background execution limits.
- Avatar and other Storage use cases, upload validation, object policies, and
  retention.
- Logging, analytics, crash reporting, performance budgets, and privacy controls.
- Notification archive/delete/preferences, future-type payload/localization,
  physical cleanup, and account-lifecycle retention.
- FCM/APNs registration, token lifecycle, push-safe content, and notification deep
  links.
