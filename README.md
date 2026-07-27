# List & Split

List & Split is an Android and iOS app for collaborative active lists,
reusable templates, a mutual-friend community, and an optional expense ledger.
The repository provides the runnable Flutter application and current identity,
community, account-lifecycle, and first active-list slices: verified email/password
authentication, session
routing, password recovery, owner-only profile onboarding, secure exact-username
discovery, directional block management, versioned friend requests, and mutual
friendship management. Persistent in-app friend-request notifications include an
unread badge, deterministic pagination, safe versioned actions, and block-aware
suppression. Versioned account-data export and immediate permanent self-service
account deletion are available to authenticated email-verified users from
completed Profile or incomplete Onboarding. The authenticated four-tab shell now
provides functional owned/shared Lists, private Templates with personal categories,
existing Community, and existing Profile; notifications remain available from the bell.
Friend-only list invitations, accepted-member item collaboration, member management,
multi-member item assignments, and persistent list-access/assignment notifications
are implemented. Active lists also have one optional shared General Note with
explicit current-member `@mentions`, persistent mention notifications, and
draft-preserving conflict reconciliation. Private account-scoped Supabase Broadcast
reconciles connected devices through the existing RPC repositories without carrying
application data.
Private templates support independent list snapshots and atomic selected-item list
creation/import. Owners can also publish templates explicitly on their block-aware
public profiles, where any fully onboarded authenticated nonblocked user may inspect
the live item-only source and save an independent private, Uncategorized copy. The
current source also adds exact-revision reporting, reporter-only hiding, an
empty-by-default UUID-authorized moderation queue, restriction-backed
takedown/restoration, safe owner outcomes, and 24-month closed-evidence retention;
its hosted rollout and physical QA remain separately controlled.
The template-send database/domain foundation adds immutable friend offers,
recipient-only atomic private-copy acceptance, sender revocation, persistent
Received/minimal Sent projections, notification v5, export v11, and private
Realtime invalidation. Flutter exposes localized Send, Received, Sent,
Accept/Decline/Revoke, notification routing, and strict export-v11 integration;
the 180-day terminal cleanup remains unscheduled until PR #25.
List-scoped Split
supports owner-selected CHF/EUR, exact integer equal and custom expense shares,
derived balances, deterministic settle-up suggestions, immutable full/partial
settlement records, one-time reversals, historical participants, and the same
private reconciliation path. Shared templates, template-send UI, global/friends
feeds, offline mutation queues, push delivery, and payment-provider integration
remain planned work.

The client uses Riverpod application scope and view models, repository boundaries,
`MaterialApp.router` with `go_router`, Material 3 light and dark themes, and English/
Portuguese localization wiring. Supabase is initialized only from public
compile-time configuration.

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
lib/l10n/           English/Portuguese ARB sources; generated localization code is ignored
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

The real two-client private-Broadcast smoke is intentionally environment-gated
and therefore skipped by the ordinary Flutter suite. After a clean local reset,
enforce it separately with the local-only values reported by `supabase status`:

```text
flutter test test/local/private_broadcast_transport_smoke_test.dart --dart-define=RUN_LOCAL_REALTIME_SMOKE=true --dart-define=LOCAL_SUPABASE_URL=<local-api-url> --dart-define=LOCAL_SUPABASE_PUBLISHABLE_KEY=<local-publishable-key> --dart-define=LOCAL_SUPABASE_SECRET_KEY=<local-secret-key>
```

### Item-assignment manual QA

After the reviewed migration reaches an authorized QA environment, use two current
accepted participants on the same active list and upgraded clients on two physical
devices:

1. On device A, create and edit items with zero, one, two, and several assignees,
   including self-assignment; verify device B updates without manual refresh.
2. Keep the same item editor open on device B while device A changes its fields or
   assignments; verify the stale editor closes once, discards its draft, and shows
   one localized reconciliation message.
3. Verify a newly assigned other user receives one informational notification with
   current list/item names. Self-assignment and unassignment must create none;
   removal followed by re-assignment may create one new notification.
4. Complete an item, correct its assignments, and verify archive makes the editor
   read-only. Save the list as a template and verify assignments are not copied.
5. Remove/leave/block a selected participant while the editor is open. Verify
   assignment cleanup, one safe editor close/navigation, automatic two-device
   reconciliation, and permanent notification suppression without privacy details.
6. Repeat the compact row/editor checks in English and Portuguese, light and dark
   themes, large system text, and with a screen reader.

Manual refresh must remain a working fallback. Use disposable QA list/item data;
do not use account deletion merely to exercise assignment cleanup.

### General Note and mention rollout

The General Note migration is deployed to List & Split Dev and its two-phone
physical QA passed. For regression QA, use two current accepted participants on
one active list and upgraded clients:

1. Create, edit, clear, and reopen the shared note, including multiline and
   2,000-code-point boundaries; verify the other device updates without a manual
   refresh.
2. Explicitly select self and other-member `@mentions`, repeat one token, and type
   an unresolved token manually. Verify only newly resolved other-member links
   create one notification and that plain text never becomes a link by itself.
3. Keep a dirty editor open while the other device changes the note or mention
   eligibility. Verify the draft remains available, one localized conflict message
   appears, and recovery is deterministic. Then separately remove caller access,
   archive, and delete the list; verify the editor closes/exits safely once with
   the appropriate localized outcome and no duplicate navigation.
4. Remove, leave, block, unblock, and reinvite. Verify literal note text remains,
   structured links are removed when access is lost, suppressed historical
   notifications never reappear, and only a later explicit selection can resolve
   a new link.
5. Verify archived notes are readable but not editable, templates never copy note
   text or links, and an imported template preserves the destination note.
6. Repeat in English and Portuguese, light and dark themes, large system text, and
   with a screen reader.

Manual refresh and app resume remain authoritative fallbacks. Use disposable QA
list/note data; any further hosted deployment still requires separate
authorization and must not be inferred from local automated verification.

### Public Template manual QA

The Public Template Foundation passed its required two-account manual QA. For
regression QA in an authorized environment, use two fully onboarded accounts on
current clients:

1. Publish named zero-item and populated templates, verify the owner state remains
   visibly Public after refresh, and confirm ordinary public edits preserve the
   publication time.
2. From the other account's exact-search and friendship rows, open the immutable-ID
   profile/detail routes, page public templates, inspect ordered quantities, and
   save independent private Uncategorized copies, including a zero-item copy.
3. Verify duplicate names route by ID, a repeated Save after a simulated uncertain
   response creates one copy, and stale source review never partially copies data.
4. Unpublish, delete, block in both directions, unblock, and resume the app. Verify
   unavailable profile/detail routes exit to Community once, no reverse block or
   friendship is disclosed, and completed copies never change.
5. Verify publishing, viewing, copying, and unpublishing create no notification and
   no public/global Realtime channel; manual refresh and resume remain the
   authoritative viewer fallbacks.
6. Repeat in English and Portuguese, light and dark themes, 200% text, and with a
   screen reader. Confirm publication state is not conveyed only by color.

O-P13 is resolved in the source contract, but do not begin an external
public-content rollout until its additive migration is separately reviewed and
deployed, a development moderator is explicitly granted, current clients are
distributed, and the reporting/moderation physical QA below passes.

### Public Template moderation operations

Migration `20260726072024_public_template_reporting_moderation.sql` deliberately
creates an empty moderator allowlist and no retention Cron job. Moderator
assignment and retention scheduling remain separately reviewed operations. Every
hosted action below requires explicit authorization and an unambiguous environment
target; Production needs its own independently reviewed target, identity, request
IDs, rollout, and evidence.

Use this order for a controlled development rollout:

1. Verify project name/reference, branch/commit, clean migration history, and that
   this is the only pending migration. Apply only the reviewed migration.
2. Verify the migration once, all seven private tables/RLS/rejection policies,
   exact hardened functions/grants, absence from Realtime publication, unchanged
   application counts, zero moderator rows, and no Cron job named
   `public-template-moderation-retention-daily`.
3. Verify the intended completed development Auth UUID out of band. Never use
   email, username, profile fields, a JWT role claim, or a copied Production UUID
   as moderator authority.
4. Through a privileged `postgres` database session, make one audited grant with a
   stable new request UUID. Provision standard `PGHOST`/`PGPORT`/`PGDATABASE`/
   `PGUSER`/`PGPASSWORD` variables, `LIST_AND_SPLIT_MODERATOR_AUTH_UUID`, and
   `LIST_AND_SPLIT_MODERATOR_REQUEST_ID` through the approved secret mechanism
   rather than command history or repository files. Then run:

   ```powershell
   $env:PGOPTIONS = "-c app.list_and_split_moderator_uuid=$($env:LIST_AND_SPLIT_MODERATOR_AUTH_UUID) -c app.list_and_split_moderator_request_id=$($env:LIST_AND_SPLIT_MODERATOR_REQUEST_ID)"
   psql --no-psqlrc --set=ON_ERROR_STOP=1 --command "select private.grant_public_template_moderator(current_setting('app.list_and_split_moderator_uuid')::uuid, 'list-and-split-dev-controlled-bootstrap', current_setting('app.list_and_split_moderator_request_id')::uuid);"
   ```

   Retry only the identical UUID/operator/request tuple after an uncertain
   response. Verify an aggregate count and the intended signed-in client's
   `is_public_template_moderator()` result; do not list or log allowlisted UUIDs.
   Clear the task-specific and standard PostgreSQL secret environment variables
   immediately afterwards.
5. Distribute the matching development client only after the migration and grant
   checks pass, then complete physical QA. An empty allowlist is the safe
   fail-closed state and does not block reporting or owner-private template use.
6. Retention scheduling is owned by additive migration
   `20260727095449_schedule_public_template_moderation_retention.sql`. It first
   unschedules every same-name job through `cron.unschedule`, then installs exactly
   one active daily 03:47 UTC job named
   `public-template-moderation-retention-daily`, executing as `postgres`:

   ```sql
   select cron.schedule(
     'public-template-moderation-retention-daily',
     '47 3 * * *',
     'select * from private.maintain_public_template_moderation_retention();'
   );
   ```

   The migration preserves `postgres`-only execute privilege and does not invoke
   cleanup during deployment. Verify exactly one active job without exposing or
   modifying moderation evidence:

   ```sql
   select
     has_function_privilege(
       'postgres',
       'private.maintain_public_template_moderation_retention(timestamptz)',
       'EXECUTE'
     ) as postgres_can_execute,
     not has_function_privilege(
       'anon',
       'private.maintain_public_template_moderation_retention(timestamptz)',
       'EXECUTE'
     ) as anon_denied,
     not has_function_privilege(
       'authenticated',
       'private.maintain_public_template_moderation_retention(timestamptz)',
       'EXECUTE'
     ) as authenticated_denied,
     not has_function_privilege(
       'service_role',
       'private.maintain_public_template_moderation_retention(timestamptz)',
       'EXECUTE'
     ) as service_role_denied;

   select jobname, schedule, command, active, username, database
   from cron.job
   where jobname = 'public-template-moderation-retention-daily';

   select status, count(*)
   from cron.job_run_details
   where jobid = (
     select jobid
     from cron.job
     where jobname = 'public-template-moderation-retention-daily'
   )
   group by status
   order by status;
   ```

For controlled revocation, use a fresh stable request UUID and the same protected
environment mechanism, substituting
`private.revoke_public_template_moderator(...)` and operator label
`list-and-split-dev-controlled-revoke`. Revocation is immediately authoritative;
the current client clears protected state and exits once. Do not delete the access
audit. If only retention scheduling must be rolled back, add a new reviewed
forward-only migration that calls `cron.unschedule` for every job named
`public-template-moderation-retention-daily`, then verify zero same-name jobs and
leave the retention function, schema, and evidence untouched. For a wider rollout
rollback, roll the client back first and revoke every development moderator through
the documented audited operation. Never edit prior migrations, repair migration
history, manually delete evidence, or use evidence deletion as rollback.

Mixed versions are fail-safe: older public reads/copy calls receive the server's
reporter/restriction filtering, older owner publication attempts are rejected
while restricted, notification v1-v3 exclude moderation outcomes, and export
v1-v9 remains unchanged. Older clients have no report or moderator UI, so the
current client is still required for safety operations and outcome presentation.

### Public Template reporting and moderation physical QA

After the separately authorized development migration, audited moderator grant,
and client distribution, use a template owner, a different reporter/viewer, and
the intended moderator. Use disposable Public Templates and, for deletion tests,
only explicitly authorized disposable identities:

1. Report an exact populated revision with every localized reason. Verify the
   conditional 500-character explanation rules and copyright notice, cancellation,
   rapid repeated confirmation, retry, and stale-revision rejection.
2. Confirm success hides the source only from that reporter across profile, detail,
   refresh, resume, and copy; another nonblocked viewer still sees it, no owner
   notification appears, and optional **Block user** remains separate.
3. Verify the moderator's Settings entry, Open/Taken down/Closed keyset pages,
   immutable group-ID routing, individual reporters, and snapshot/current
   changed/unpublished/deleted/restricted indicators.
4. Dismiss one group and confirm the source remains public with no notification.
   Create multiple open revision groups, take down one, and confirm all close, the
   source becomes private, editing/deletion remains available, publication is
   denied, and exactly one safe actor-free owner notification appears.
5. Restore the active restriction. Confirm one safe owner notification, no
   automatic republication, and explicit owner publication works only afterwards.
   Repeat uncertain-response/retry and concurrent action attempts to confirm one
   decision and no duplicate notification/navigation/message.
6. Revoke the moderator while queue/detail is mounted. Confirm cached case/report
   data clears immediately, the route exits once, the Settings entry disappears,
   and direct route re-entry is denied without stale private content.
7. Edit, unpublish, and delete reported sources; verify immutable snapshots remain
   understandable and deletion closes open evidence. If separately authorized,
   delete only disposable reporter/owner/moderator identities and verify retained
   evidence becomes generic without exposing deleted identity.
8. Verify the current v11 export retains the caller-only v10 report projection
   while another account's reports and all moderation evidence, state, identities,
   notes, restrictions, allowlist, and audit data remain absent.
9. Exercise an older client alongside the current client: restricted/reporter-
   hidden sources remain unavailable, old publication cannot bypass restriction,
   old notification parsers receive no new type, and old export versions remain
   readable.
10. Repeat reporting, owner outcomes, queue/detail/actions, revocation, and
    authoritative refresh in English and Portuguese, light and dark themes, 200%
    text, screen reader, and two connected devices. Verify private Realtime carries
    only opaque invalidation and duplicate signals never duplicate UI effects.

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

Split tables are likewise RPC-only: direct client operations are explicitly denied
and every read/mutation rechecks current unblocked list access. Hardened transactional
functions enforce currency, integer money, equal/custom-share conservation,
participant, version, archive, capacity, settlement, one-time-reversal,
idempotency, and stale-write invariants; opaque Realtime invalidations carry no
financial content. Explicit expense-share rows remain the durable truth; the
Equal/Custom editor choice is inferred rather than persisted. Any environment
must receive the reviewed custom-share migration before a client that calls its
versioned expense RPCs is distributed.

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

Legacy notification clients retain the reviewed `list_notifications` and
`get_unread_notification_count` contracts and never receive assignment, note-
mention, or moderation types. Assignment-aware v2 clients likewise never receive
note mentions or moderation outcomes, and v3 includes notes while excluding
moderation. Current Flutter uses `list_notifications_v5`,
`get_unread_notification_count_v5`, and the compatible hardened
`mark_notifications_read` boundary; it never reads or writes
`user_notifications` directly. A real transition into a pending relationship
version creates one notification atomically, while duplicate and crossed sends
create none. Listing and badge results exclude expired, suppressed, or
block-hidden rows, and block creation permanently suppresses existing pair
notifications in the same transaction. A newly resolved `list_note_mentioned`
row contains references and the resulting note version, never note text; access
loss or blocking stores permanent suppression that reinvitation or unblocking
cannot clear. System-authored Public Template takedown/restoration rows have no
actor and expose only the owner's safe template-name snapshot and general reason;
they never contain reporter, explanation, report count, moderator, private note,
or queue state. Template-send-aware v5 adds one actionable recipient row with the
allowlisted sender and snapshot summary; terminal rows are informational, and no
accepted-copy or source identity is exposed.

Active lists, items, current item assignments, resolved note mentions, and retained
participant access rows use only reviewed authenticated RPCs. The tables
have forced RLS, explicit direct-access rejection policies, and no client table
grants. Titles and item names are trimmed/check-constrained while duplicates are
allowed. Quantities are exact positive integer thousandths with stable nullable
unit codes, positions are deterministic integers, archived lists are server-side
read-only, and positive versions plus creation request UUIDs protect stale writes
and retries. Owners manage access; accepted members can read lists and mutate items
and their complete zero-to-20 assignment sets while active, including assigning
or unassigning themselves. Assignment writes validate only the current unblocked
owner/accepted-member set, update list/item versions once, create notifications
only for newly assigned other users, and preserve legacy item APIs. Capacity is 20
including the owner and pending invitations. Account-root deletion cascades owned
lists, items, current assignments, participant rows, and related notifications.
One optional list-level General Note is normalized and limited to 2,000 Unicode
code points. Current owner/accepted members may edit it only while active;
archived lists expose it read-only. Explicit stable-profile-ID mention links are
server-validated against the saved complete canonical `@username` tokens and
current unblocked membership. Literal text survives access cleanup, while removed
links never reactivate automatically.
Cross-identity writes follow the accepted profile-to-parent-to-ordered-child lock
hierarchy. One parent-first account-deletion coordinator cleans surviving list
assignment, mention, Split-history, and completion references, eliminating the
former Split-child/list lock inversion.

The account lifecycle separates versioned account-data export from permanent
deletion. Export uses parameterless, allowlist-only RPCs for any authenticated
email-verified user, including before onboarding, followed by a validated UTF-8
JSON file in app-scoped temporary cache and the native share sheet. The server
retains no export file. The existing `export_own_account_data()` remains schema
version `6` and unchanged for legacy clients, and
`export_own_account_data_v7()` remains unchanged for assignment-aware legacy
clients, and `export_own_account_data_v8()` remains unchanged for
General-Note-aware legacy clients, while `export_own_account_data_v9()` remains
unchanged for public-template-aware legacy clients.
`export_own_account_data_v10()` preserves versions `1` through `9`,
retains v9's caller-owned `is_public`/nullable `published_at`, and adds only the
caller's own submitted report reason, nullable explanation, and submission time.
`export_own_account_data_v11()` preserves v1-v10 and adds
role-specific, unsuppressed sent/received template-offer projections with no
source/copy provenance, request UUID, or fingerprint. The Flutter export client
strictly parses v11 while retaining v1-v10 compatibility.
It never exports other users' public templates/reports, target identity, report
status/group, evidence snapshot/fingerprint, provenance, copy request UUID,
moderator/private note, decision, restriction, allowlist, or access audit. Shared
lists remain caller-relative metadata-only and export no items, assignments,
General Note text, or mention identities.
Split allocation and settlement
contracts remain unchanged. Shared owner/participant identity, Split contents,
request IDs, derived balances/suggestions, and internal authority details remain
excluded.

Deletion is immediate and irreversible. Completed profiles confirm with their
exact stored canonical username; incomplete profiles confirm with their exact
Auth email. Flutter sends the current password unchanged only to Supabase Auth for
reauthentication, then invokes the authenticated `delete-account` Edge Function
with only the exact confirmation. A database validation RPC proves that the
matching `auth.sessions` row was created no more than ten minutes earlier before a
server-only admin client hard-deletes the caller's Auth user. That Auth deletion
atomically cascades through the current profile, blocks, relationships,
notifications, owned lists, list items, and each owned list's Split ledger. On a
surviving list, a deleted non-owner's financial identity and settlement history are
retained anonymously. Retained Public Template moderation evidence immediately
nulls matching reporter, owner, or moderator identities while preserving open
evidence/restrictions and no identity snapshot. A completed username is retained alone
in a private 30-day
reservation and expired reservations are physically removed daily at 03:17 UTC.
No email, Auth/profile identifier, or copied former-user data enters the
reservation. These product behaviors are not a guarantee of complete legal or
regulatory compliance; extended lifecycle obligations remain open in the decision
log.

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
avatars, shared templates, template-send screens/actions, a public feed, rich-text
notes, note
history/comments, notification archive/preferences, assignment or mention deep
links, report withdrawal/unhide/appeal/evidence attachments, automated moderation,
or scheduled template-send retention cleanup,
percentage/weight/ratio expense allocation,
automatic custom-share remainder correction, a mathematically minimum settlement
solver, SQLite caching/offline
synchronization, push delivery,
Firebase setup, administrator-initiated deletion, or a production backend.
Private Realtime Broadcast is implemented as best-effort account invalidation:
the event is `invalidate`, the application payload is exactly `{"v":1}`, and every
valid event, successful join, or app resume reloads authoritative state through
repositories. Presence, Broadcast Replay, Postgres Changes, client-originated
Broadcast, push delivery, and an offline mutation queue remain deliberately absent.
Remote list metadata and active/archive projection changes reconcile in place;
remotely archived open detail returns safely to Lists once. Dirty General Note
drafts are preserved through remote note/version/mention-eligibility conflicts and
require an explicit recovery choice. Access loss, archive, and deletion use the
established one-time safe exit behavior. Other open product and architecture
choices are recorded in the project documentation and must be decided before
their implementation slices.
