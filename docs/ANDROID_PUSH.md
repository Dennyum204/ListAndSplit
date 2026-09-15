# Private-beta Android push

P-063/A-079 authorize only a dedicated free Firebase Spark project for FCM and the
existing List & Split Dev backend. Supabase remains the only account system.
Firebase Auth, Analytics, Firestore, Storage, Hosting, Cloud Functions, billing
and HomeOffice resources are not used. iOS/APNs and Production remain deferred.

## Delivery and privacy contract

The existing in-app bell remains authoritative. New friend requests, list
invitations/ownership transfers, assignments, note mentions, template offers and
moderation outcomes can enqueue push hints. New Chat messages notify currently
authorized other participants. There is no self notification or history backfill.
Registration after an event never creates delivery for that event.

An insert trigger creates operational delivery rows in the business transaction;
rollback removes them. No external HTTP runs there. Enqueue overflow/failure can
lose the optional hint but never the business action or persistent bell. A
10,000-row soft overflow cap (concurrent transactions may briefly exceed it) and
15-minute expiry bound the small private-beta queue. One minute Cron tick cleans
at most 5,000 expired delivery rows and 100 old devices, then invokes the worker
only if due work exists and exact Dev Vault settings exist. At most 20 deliveries
are claimed, four HTTP sends run concurrently, each with an eight-second timeout,
and each delivery has at most four leased attempts with 60/120/240-second minimum
backoff (bounded Retry-After is honored). Lease expiry permits recovery after a
worker exit. Successful FCM acceptance is not proof of delivery to a phone.

Immediately before HTTP, the worker rechecks the current device binding, original
Auth session, current membership, Chat join/read boundary, blocks, source state,
notification suppression/read state and expiry. A concurrent revocation after that
check cannot retract an already accepted FCM packet; the phone also checks its
current binding and every tap resolves through an authenticated current-access RPC.
No message body, username, list title, financial value, photograph or credential is
in the payload. Only opaque delivery/binding/account/list IDs and kind/version are
sent. The Android service renders generic localized text.

## Registration and Android lifecycle

The authenticated registration RPC derives the account from `auth.uid()`, checks
the supplied expected account only as a stale-operation guard, verifies the real
Auth session and serializes a ten-device-per-account limit. A random 128-bit
installation capability and separate random binding ID live in private Android
preferences; the database stores only the installation hash. They are never
returned by an API or included in a push. Knowing an account ID cannot enroll a
device for that account. Direct device/queue access is denied even to service-role
Data API clients; only exact worker RPC grants expose dispatch material.

Background token rotation requires the installation capability, binding and exact
previous token, plus the original live Auth session and registration. That narrow
RPC can update only this existing token; it cannot enroll an account/device,
change its binding, or extend the 30-day registration expiry. New enrollment
still requires verified Supabase authentication. Wrong/stale capability calls
return false. This supports FCM's native background token callback without copying
Supabase passwords/refresh tokens into a second native authentication system.
Signed-in resume re-registers the current token and renews the device lifetime.

Profile explains push and asks Android permission only when the user enables it.
It offers an enable switch, recoverable retry and Android notification settings.
Token auto-initialization is off until consent. Logout clears the local binding
and alerts before changing Auth, including offline; server unregister is best
effort and original-session revocation also cascades registrations. Account
switching replaces the binding and discards old delivery work. Account deletion
cascades devices/queue without changing avatar-aware deletion or user exports.

FCM data-only packets use HIGH priority and at most five minutes of transport TTL.
The native service works without a Flutter engine during ordinary background or
terminated delivery. It rejects malformed/expanded envelopes, mismatched accounts
or bindings, and duplicates. A 15-minute device receipt ledger holds at most 1,024
IDs; overflow drops additional hints instead of repeating prior alerts. Android
notification tags are delivery IDs and use only-alert-once. The process-local
foreground flag and current Chat route suppress redundant visible-conversation
alerts; a killed process cannot retain a stale foreground flag. Delivery opens
only an authenticated resolved Chat route or the existing notification centre.

Android **Force Stop** suspends delivery until the user opens the app again.
Battery restrictions, missing Google Play services, connectivity and FCM priority
deprioritization can delay/drop hints. They do not change the bell or authoritative
Chat. No guaranteed-delivery or force-stopped-delivery claim is made.

## Configuration and reproducible checks

Android Firebase Messaging is pinned to 25.1.3, verified against Google's official
Maven metadata. Public `FIREBASE_PROJECT_ID`, `FIREBASE_APP_ID`,
`FIREBASE_SENDER_ID` and `FIREBASE_API_KEY` go in the same local client JSON as Dev
Supabase settings. Gradle generates native resources from these defines; no
Google services plugin or server JSON enters the APK. All four must be present or
absent. Absent configuration leaves push visibly unavailable and performs no
registration, preserving an explicitly labelled interim Dev build.

Server-only `FCM_SERVICE_ACCOUNT_JSON`, `FCM_PROJECT_ID` and `PUSH_WORKER_SECRET`
belong in Supabase Edge secrets. The worker is configured `verify_jwt=false` and
uses `withSupabase(auth:none)` only to construct clients; a constant-time dedicated
worker credential check runs before all database/FCM work. It never accepts a
publishable key or user JWT as worker authority. Error logs contain no payloads.

Checks: full Flutter suite/analysis; `./gradlew testDevDebugUnitTest` after a Dev
build; `deno task --config supabase/functions/push-dispatch/deno.json check` and
`test`; all pgTAP tests plus `push_delivery.local.test.ts` against explicitly
loopback Supabase. The HTTP integration test provisions/deletes only its own
isolated accounts. Current result/evidence is in PRIVATE_BETA_NEXT_CHECKPOINT.md.
Unit/SQL tests are not evidence of real FCM delivery or spoken TalkBack.

## Exact Dev rollout and recovery

1. Complete the owner's local Firebase CLI login. Verify account/project access;
   create one dedicated `List & Split Private Beta` Spark project with a unique
   `list-and-split-...` ID and Android app `com.ferbatech.listandsplit.dev`. Record
   the actual ID/app ID and verify billing is disabled. Enable only FCM HTTP v1.
   Provision a dedicated service account with FCM send permission in that project;
   retain its key outside Git/chat. Do not use the default broad Admin SDK role
   if a narrow sender role can be configured.
2. Recheck exact clean source, synchronized branch and CI. Inspect CLI version/help,
   verify hosted identity `List & Split Dev / lzwsgxziqxpxwyalkfuy`, the existing 30
   migration history and the source/function inventory. Stop on unexpected push
   objects/functions, drift or additional pending migrations. Supported
   `supabase db push --dry-run --linked` must propose **only**
   `20260915050418_android_push_delivery.sql` (from `supabase migration new`).
3. Apply that additive migration once. Its new worker schedule is dormant without
   exact Vault settings. Verify history, private RLS/grants, constraints and the
   single named schedule. Existing delete-account/profile-avatar functions remain
   unchanged. Record the hosted advisor baseline and compare post-deploy findings.
4. Set the three server secrets locally without printing them; deploy only the
   reviewed `push-dispatch` bundle/config using supported CLI help. Verify its
   actual version and authentication rejection over HTTP. Do not deploy unrelated
   functions or alter SMTP. Store exact Dev endpoint as Vault
   `list_split_push_url` and the same worker credential as
   `list_split_push_worker_key`; the Cron helper accepts only the exact Dev URL.
5. With new task-owned accounts/devices, verify new-event registration and current
   access over HTTP, actual FCM foreground/background/ordinary-terminated delivery,
   visible-Chat suppression, denied permission, tap routing, token rotation,
   logout/switch, bounded retry/deduplication and fixture-only cleanup. Never send
   automated test content to Fernando or Susana without their participation.
6. Only after backend checks, build the configured signed Dev APK with all four
   Firebase settings and verify signer/version/package/hash. Update in place;
   retain immediate before/after session evidence. A new distributed versionCode
   is required if an interim APK has already used version 4.

On an uncertain migration/function result, inspect authoritative history/version
before any retry. To suspend delivery, remove/disable only this worker's Vault
credential or unschedule only `list-and-split-push-minute` through reviewed
operations; retain business data and registrations for diagnosis. Rotate only
the dedicated sender key if compromised. Recover by fixing forward and restoring
the reviewed credential/schedule; expired hints are not replayed. Never roll back
the avatar-aware deletion service, reset Dev, clear phone data or invoke existing
content-retention jobs as recovery. Private-beta account/export/signing backup
limitations remain those in ANDROID_RELEASE.md. Push tokens/capabilities/outbox are
operational, short-lived state, deliberately excluded from export v13.

The old Production preparation scripts still reject the new full migration count
and have no approved native target. A separately reviewed Production push rollout,
credentials/scheduler target, legal/moderation and Play gates remain future work.

Authoritative references checked 2026-09-15: [FCM Android setup](https://firebase.google.com/docs/cloud-messaging/android/get-started),
[Android receive](https://firebase.google.com/docs/cloud-messaging/android/receive-messages),
[HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api),
[FCM no-cost pricing](https://firebase.google.com/pricing),
[Supabase function authentication](https://supabase.com/docs/guides/functions/auth),
[Cron/Vault scheduling](https://supabase.com/docs/guides/functions/schedule-functions).
The current Supabase changelog was reviewed; no relevant breaking change requires
altering the existing Realtime/Auth wrappers or upgrading repository dependencies.
