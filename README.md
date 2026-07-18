# List & Split

List & Split is a planned Android and iOS app for collaborative active lists,
reusable templates, a mutual-friend community, and an optional expense ledger.
The repository currently contains the runnable Flutter foundation, not those
product features or their business database schema.

The implemented foundation provides Riverpod application scope,
`MaterialApp.router` with `go_router`, Material 3 light and dark themes,
English localization wiring, a branded startup screen, and optional Supabase
client initialization.

## Project identity

| Setting | Value |
| --- | --- |
| Display name | `List & Split` |
| Dart package | `list_and_split` |
| Android application ID and namespace | `com.ferbatech.listandsplit` |
| iOS bundle identifier | `com.ferbatech.listandsplit` |

## Prerequisites

- Flutter stable with its bundled Dart SDK (`>=3.3.4 <4.0.0` as declared in
  `pubspec.yaml`).
- Git and an Android toolchain for Android development.
- macOS, Xcode, and the iOS toolchain for iOS development.
- Optionally, the Supabase CLI and a running Docker-compatible container runtime
  for the local backend stack.

Check the local mobile toolchain before starting:

```text
flutter doctor
flutter devices
```

## Get started

Install dependencies from the repository root:

```text
flutter pub get
```

Run on an available Android or iOS target:

```text
flutter run -d <device-id>
```

Supabase credentials are optional during the foundation phase. With neither
configuration value supplied, backend initialization is skipped and the app still
runs. Supply both values or neither; a partial configuration fails fast.

```text
flutter run -d <device-id> --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

Use placeholder or local-development values in documentation and source control.
Keep real environment values outside the repository.

## Verify changes

Run the standard checks from the repository root:

```text
dart format .
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
git diff --check
```

For platform-affecting changes, also run the relevant build when the local
toolchain is healthy, for example:

```text
flutter build apk --debug
```

## Repository layout

```text
lib/main.dart       Process entry point and startup
lib/app/            App composition, router, and foundation screen
lib/core/           Cross-feature configuration, themes, and primitives
lib/l10n/           English ARB source; generated localization code is ignored
lib/features/       Future feature-first modules, added only when implemented
test/               Unit and widget tests
supabase/           Local Supabase configuration and future migrations
docs/               Product, architecture, data-model, roadmap, and decisions
.github/workflows/  Continuous integration
```

Widgets should render state and emit intent. Riverpod view models/providers
coordinate use cases, and repositories remain the data source of truth. UI code
must not call Supabase or other persistence transports directly.

## Local Supabase workflow

The repository is already initialized for local Supabase development. Install the
[Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started),
start a Docker-compatible runtime, and discover the commands supported by the
installed CLI before using it:

```text
supabase --help
supabase start
supabase status
supabase stop
```

All business schema changes must be represented by reviewed SQL migrations in
`supabase/migrations/`; do not make Dashboard-only schema changes. A typical local
workflow is:

```text
supabase migration new <descriptive_name>
# Edit the generated migration file.
supabase db reset --local
supabase migration list --local
```

`db reset --local` recreates the local database and removes uncommitted local data.
Never run a destructive reset against a linked remote project. Applying reviewed
migrations remotely requires separate, explicit authorization.

Every application table must enable Row Level Security in its creating migration
and use least-privilege policies. Flutter may receive only a public publishable
client key. Never put a Supabase `service_role` key, secret key, access token,
database password, signing material, or other privileged credential in Flutter or
Git.

## Project documentation

- [Product specification](docs/PRODUCT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Conceptual data model](docs/DATA_MODEL.md)
- [Roadmap](docs/ROADMAP.md)
- [Decision log](docs/DECISIONS.md)
- [Repository guidance for coding agents](AGENTS.md)

## Intentional deferrals

The bootstrap does not implement product flows, authentication flows, business
tables or migrations, RLS policies, realtime behavior, server-side ledger logic,
SQLite caching or offline synchronization, push notifications, Firebase setup, or
a production backend. Open product and architecture choices are recorded in the
project documentation and must be decided before their implementation phases.
