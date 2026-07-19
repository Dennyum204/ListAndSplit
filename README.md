# List & Split

List & Split is an Android and iOS app for collaborative active lists,
reusable templates, a mutual-friend community, and an optional expense ledger.
The repository provides the runnable Flutter foundation and current Phase 1
identity/community slices: verified email/password authentication, session
routing, password recovery, owner-only profile onboarding, secure exact-username
discovery, directional block management, versioned friend requests, and mutual
friendship management. Persistent in-app friend-request notifications include an
unread badge, deterministic pagination, safe versioned actions, and block-aware
suppression. Lists, templates, other notification types, and the expense ledger
remain planned work.

The client uses Riverpod application scope and view models, repository boundaries,
`MaterialApp.router` with `go_router`, Material 3 light and dark themes, and English
localization wiring. Supabase is initialized only from public compile-time
configuration.

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
- For local Auth, migration, and database-policy work, the Supabase CLI and a
  running Docker-compatible container runtime.

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

Authentication requires both public Supabase configuration values. If either is
missing, the app remains runnable and shows a non-secret development-configuration
screen rather than entering an authentication flow.

```text
flutter run -d <device-id> --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

Use placeholder or local-development values in documentation and source control.
Keep real environment values outside the repository. Only the public publishable
key belongs in a Flutter build; never use a secret or `service_role` key.

The registered mobile Auth callback is:

```text
com.ferbatech.listandsplit://auth-callback
```

Android and iOS platform files register this URI. Do not change the application or
bundle identifiers when configuring deep links.

## Verify changes

Run the standard checks from the repository root:

```text
flutter pub get
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
lib/app/            App composition, router, and app-wide providers
lib/core/           Cross-feature configuration, themes, and primitives
lib/l10n/           English ARB source; generated localization code is ignored
lib/features/       Feature-first presentation, domain, and data modules
test/               Unit and widget tests
supabase/           Local configuration, reviewed migrations, and database tests
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
supabase test db
```

For a local client build, use the local API URL and public publishable/anonymous
key reported by `supabase status` as the two `dart-define` values. Never copy the
reported `service_role` key into Flutter or source control. Local verification
messages are available through the local mail viewer reported by the CLI.

Local Auth and Flutter require at least eight characters for new and replacement
passwords. Passwords are submitted exactly as entered; they are not trimmed,
lowercased, or subject to additional composition rules.

`db reset --local` recreates the local database and removes uncommitted local data.
Never run a destructive reset against a linked remote project. Applying reviewed
migrations remotely requires separate, explicit authorization.

Every application table must enable Row Level Security in its creating migration
and use least-privilege policies. Flutter may receive only a public publishable
client key. Never put a Supabase `service_role` key, secret key, access token,
database password, signing material, or other privileged credential in Flutter or
Git.

Community discovery and block management use only the reviewed
`find_profile_by_username`, `block_profile`, `unblock_profile`, and
`list_blocked_profiles` RPC contracts. The `user_blocks` table has RLS enabled but
no direct client grants, and direct profile reads remain owner-only. Discovery is
an exact canonical-username lookup and returns only profile ID, username, and
display name; missing and block-suppressed profiles share the same empty result.

Friend requests and friendships use one retained, versioned
`user_relationships` row per normalized profile pair. The Flutter client uses
only reviewed summary, active-list, send, cancel, accept, decline, and end RPCs;
it never reads or writes the relationship table directly. Caller-relative
results expose only actionable status and minimal profile data. Declined/ended
state, reopening control, block direction, and unavailable-state version metadata
remain private. An active block in either direction returns no relationship
summary or target profile fields; only private outgoing-block management exposes a
blocker's own blocked-user projection. Block creation atomically cancels a pending
request or ends a friendship, while unblocking restores no relationship.

Friend-request notifications use only the reviewed `list_notifications`,
`get_unread_notification_count`, and `mark_notifications_read` RPC contracts;
Flutter never reads or writes `user_notifications` directly. A real transition
into a pending relationship version creates one notification atomically, while
duplicate and crossed sends create none. Listing and badge results exclude
expired, suppressed, or block-hidden rows, and block creation permanently
suppresses existing pair notifications in the same transaction.

### Hosted development Auth configuration

Migrations configure database objects, but they do not configure hosted Auth email
or redirect settings. For each explicitly authorized hosted development project,
complete these steps in the Supabase Dashboard before testing email verification
or password recovery:

1. Open **Authentication > URL Configuration** and add
   `com.ferbatech.listandsplit://auth-callback` to **Redirect URLs**.
2. Open **Authentication > Providers > Email**, enable email/password sign-in and
   **Confirm email**, set the minimum password length to `8`, leave required
   character composition disabled, then save.
3. Keep other providers and anonymous sign-ins disabled for the initial release.
4. Use a test account to verify that both confirmation and password-recovery links
   return to the mobile callback and that the app reaches the expected gated flow.

Do not compensate for missing hosted Auth settings by weakening client routing,
email-verification requirements, or database authorization. Hosted schema changes
must still be applied from committed migration history, never by pasting untracked
SQL into the Dashboard.

## Project documentation

- [Product specification](docs/PRODUCT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Conceptual data model](docs/DATA_MODEL.md)
- [Roadmap](docs/ROADMAP.md)
- [Decision log](docs/DECISIONS.md)
- [Repository guidance for coding agents](AGENTS.md)

## Intentional deferrals

The current slices do not implement unrestricted profile/directory search,
avatars, lists, templates, notification types beyond friend requests,
notification archive/preferences or physical cleanup, reporting, Realtime,
server-side ledger logic, SQLite caching/offline synchronization, push delivery,
Firebase setup, account deletion/export, or a production backend. Effects of
blocks or friendship changes on future shared resources remain open. Other open
product and architecture choices are recorded in the project documentation and
must be decided before their implementation slices.
