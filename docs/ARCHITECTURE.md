# List & Split architecture

## Status and scope

This is the agreed target architecture for the product. It distinguishes durable
constraints from planned components; it is not an implementation-progress report.
At bootstrap, only a small runnable application foundation is expected. Product
features, business tables, offline caching, push delivery, and most backend logic
remain unimplemented until their roadmap phases.

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

The bootstrap path is intentionally small:

```text
main.dart
  -> ProviderScope
     -> app composition
        -> MaterialApp.router
           -> go_router route tree
              -> feature views
```

`main.dart` should contain process bootstrapping rather than feature behavior. The
The `app/` layer owns the root widget, router, and only truly app-wide providers.
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

### Generated models

Freezed and JSON serialization may be used for immutable state and boundary
models. Generated files are regenerated with `build_runner`; they are not edited
by hand. Domain modeling should not be forced into serialization shapes merely
because code generation is available.

## Navigation

`go_router` owns a single root route graph and future deep-link handling. The
planned main shell has four destinations: Lists, Templates, Community, and
Profile. Notifications open from a bell and must not become a fifth destination.

Authentication redirects, nested route names, deep-link URLs, restoration, and
notification-link behavior remain open. Route decisions should be centralized and
covered by navigation/widget tests as flows are introduced.

## Backend architecture

### Supabase responsibilities

- **Auth** identifies the current user; application authorization is still enforced
  by RLS and server-side checks.
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
source of truth. The bootstrap phase initializes Supabase tooling but intentionally
creates no application tables or business migrations. The conceptual model is in
[`DATA_MODEL.md`](DATA_MODEL.md).

### Client configuration

The Flutter client must eventually receive its public Supabase configuration at
build/run time. Real values are not hardcoded or committed. A placeholder-only
example is:

```text
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

The bootstrap conditionally initializes the Supabase client only when both values
are supplied; with neither value, the foundation remains runnable. Only a public
anonymous/publishable client key may enter Flutter. A service-role key or any
other privileged secret must never be included in a client binary.

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
- Test RLS policies and database functions with allowed and denied identities when
  business migrations begin.
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

- Authentication providers, session bootstrap, and account lifecycle.
- Precise feature folder layering and whether Riverpod code generation is used.
- Route topology, auth redirects, deep-link formats, and state restoration.
- Public client configuration names and development/staging/production flavor
  strategy.
- PostgreSQL-function versus Edge-Function placement for each atomic server action.
- Realtime subscription granularity, reconnect/replay behavior, and event ordering.
- SQLite library, cache schema, synchronization algorithm, conflict policy, and
  background execution limits.
- Stable identifiers/version fields needed for optimistic concurrency.
- Storage use cases and object retention.
- Logging, analytics, crash reporting, performance budgets, and privacy controls.
- FCM/APNs registration, token lifecycle, and notification deep links.
