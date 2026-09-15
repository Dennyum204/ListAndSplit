# Android release operations

The current status and exact source revisions live only in the README release
checkpoint. This document is the reviewable procedure, not deployment evidence.
Production creation, paid resources, deployment and publication are unapproved.
Do not use Dev or the unrelated discovered `Supabase Store` as Production.

## Source, toolchain and packaging

Use a clean commit from `codex/android-release-readiness`, stacked on PR #35 and
then #34/#33 until their individual review/acceptance gates pass. Never infer a
merged state from a successful build. `tools/release/toolchain.json` pins Flutter
3.47.4 (revision 9584c6713b324636289d067944a46fd6b49df14b), Dart bundled with it,
JDK 17, Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20, NDK 28.2.13676358, Android
minimum 24 and compile/target 36. The wrapper checksum and pubspec.lock are
committed. Only SDK-required Android plugin/transitive upgrades accompany this
toolchain change. Keep the Flutter SDK and release evidence outside the checkout.

Run repository checks before packaging. Use PowerShell 7, the pinned Flutter,
JDK and Android SDK on PATH and ANDROID_HOME. Import the existing release key
locally, then build with a never-used evidence directory:

```powershell
& tools/release/Import-ReleaseSigning.ps1
& tools/release/Build-AndroidRelease.ps1 -Environment prod `
  -ExpectedHead <full-reviewed-SHA> -VersionName 1.0.0 -VersionCode 2 `
  -PackagingOnly -OutputDirectory <new-absolute-directory>
```

Packaging-only creates an intentionally unconfigured APK/AAB; it cannot initialize
Supabase and must not be installed as a working Production app. The manifest marks
it non-distributable. After an approved project exists, commit its public reference
to `android/production.properties`, repeat affected config checks and CI, and use
`-ConfigurationFile <local-json>` instead of `-PackagingOnly`. That file contains
only `APP_ENV=prod`, `SUPABASE_URL=https://<approved-ref>.supabase.co` and
`SUPABASE_PUBLISHABLE_KEY=sb_publishable_...`. Never put privileged keys in it.
Native flavor, package and the compiled project pin must agree; caller-controlled
Dart defines cannot select Dev from a Production build. Values are not printed.

The build script uses locked dependencies, produces obfuscated APK/AAB plus Dart
symbols and Android mapping where generated, and records hashes/source/version.
Verification checks release certificate, package, version, non-debuggable flag,
min/target SDK, merged permission allowlist, TLS, disabled Android backup,
callback scheme, ZIP 16 KB alignment and every packaged arm64/x64 ELF segment.
Archive the manifest, exact source, lockfiles, APK/AAB, Dart symbols and mappings
together in owner-controlled storage. Never commit these artifacts or credentials.
For subsequent distribution use an unused, increasing versionCode; never reuse
one for a different binary.

## Signing continuity and installation gate

The protected Samsung unsuffixed package is an older debug-signed installation.
Its certificate is `acee26ad210976eb7796bb3884a02f7e404cba688fa96a51eccb6f6cf07a7055`.
The retained new RSA-4096 release certificate is pinned in
`tools/release/release-signer.sha256`; key and DPAPI-protected password are outside
Git under the current Windows user's `.listandsplit/signing` directory. No key
was discarded. `Export-ReleaseSigningBackup.ps1` makes an independently password-
protected backup at a new owner-selected external destination, verifies the
certificate and preserves the original; its password must be entered locally.
DPAPI alone is not an offline/reinstall backup. Verify a restore before release.

The new certificate cannot update the protected installed package. Owner must
choose signing continuity recovery, a separately approved parallel Production
application ID/callback, or a separately authorized data migration/uninstall.
Do not silently select an alternative ID, uninstall, clear data or attempt a
replacement installation. Play App Signing/upload-key selection is a later
distribution decision. Once resolved, inspect device serial/package/certificate,
use `adb install -r` only with compatible identity, launch and check startup,
Auth callback, persistence and network isolation. Stop on a signing mismatch.

## Concrete Production proposal requiring owner approval

Create a distinct project named **List & Split Production**, proposed EU Frankfurt
region, in an owner-selected organization. Do not copy Dev users, application data,
Storage objects or credentials. Current discovery did not identify an intended
Production project. Proposed baseline is Supabase Pro, approximately US$25/month
organization fee plus project compute/overages and external SMTP; verify the actual
checkout quote before purchase. Existing organization/compute credits affect the
total. Pro daily database backups provide a starting recovery facility; choose a
recovery objective and whether optional PITR (additional cost, currently starting
around US$100/month) is needed. Database backups do not contain Storage image
bytes. Arrange an encrypted, access-controlled object backup and a matched
database/object restore drill before treating avatars as recoverable.

Approve: organization/budget/region, project creation, SMTP provider/sender and
domain, exact public project ref, native application identity, key backup owner,
backup/restore objectives, and this migration/function/retention scope. Record
actual source SHA and configuration evidence at approval time. No project token,
DB password, service key or SMTP password belongs in chat or a committed file.

### Reviewed backend sequence

`tools/release/backend-manifest.json` is the exact ordered set of **30 migrations**
with normalized UTF-8/LF SHA-256 hashes and both reviewed function bundles. It
includes original avatar `20260907221034_profile_avatars.sql`, avatar forward fix
`20260914222013_profile_avatar_stale_conflict.sql`, and the new broader forward fix
`20260914232057_recoverable_business_conflicts.sql`. The last migration is locally
verified but **not deployed to Dev**; its Dev rollout needs explicit authorization
and a dry run proposing only that migration. Genuine SQLSTATE 40001 is preserved;
deliberate pinned business conflicts become PT409/HTTP 409 without retries.

For a newly approved empty Production project:

1. Confirm identity, region/status, reviewed clean source and passing CI. Read
   installed CLI help and current Supabase changes. Secure backup and Auth/SMTP
   settings; keep client distribution closed.
2. Run `Prepare-ProductionBackend.ps1 -ExpectedHead <SHA> -ProjectRef <ref>
   -EvidenceDirectory <new-dir>`. It verifies the exact named project, refuses Dev
   and the unrelated project, copies only reviewed Supabase source to an isolated
   operation directory, links there, checks empty migration/function history,
   captures advisors and runs supported `db push --dry-run`. It requires exactly
   the 30 manifest migrations, otherwise stops. Linking may prompt for the project
   database password locally. It makes no remote schema changes.
3. Only after actual owner authorization, create a local approval JSON with Source,
   ProjectRef and true OwnerAuthorized/BackupReviewed/AuthSmtpReviewed/
   RetentionSchedulesApproved. Run `Invoke-ApprovedProductionBackend.ps1` with
   that file and another new evidence directory. The file records authorization;
   creating it does not confer authorization. The script repeats preflight,
   applies the reviewed history once through `db push`, verifies exact history,
   then deploys **delete-account followed by profile-avatar**, including their
   manifest shared dependencies. Both preserve `withSupabase` user authentication
   and `verify_jwt=false`; disabling the legacy gateway check does not make them
   anonymous. No unrelated function or global config deployment occurs.
4. On failure or uncertainty stop, inspect authoritative history/function versions
   and bundle hashes before considering a separately reviewed continuation. Do
   not rerun fresh bootstrap against partial state, reapply migrations, reset,
   restart the project or downgrade the avatar-aware deletion service.

The scripts' remote happy path remains unexecuted until authorization; local source
hash, parser and negative-target checks are separate evidence, not a claimed
Production dry run. A missing migration-history table is accepted only after an
authoritative catalog check and zero application-table, Auth-user and Storage-
bucket counts; query errors never count as empty history.

### Auth, Storage, Realtime and retention

Configure confirmed email/password signup, reviewed password/rate limits and
leaked-password protection where available; default Supabase SMTP cannot serve
arbitrary public recipients. Set a verified owner web Site URL and exact Android
callback `com.ferbatech.listandsplit://auth-callback` (or the separately approved
replacement identity); allow no Dev callback or broad wildcard. Exercise signup,
confirmation, login, recovery, callback and logout using disposable accounts.
OAuth/social login is outside this release. Review SMTP delivery and abuse controls.

Verify private `profile-avatars` bucket, 327680-byte limit, PNG MIME restriction,
RLS/grants, and absence of direct client upload/list/download privileges. Reads
must use authenticated context-aware profile-avatar; public/inaccessible/blocked
reads must fail. Confirm JWT wrappers, export v13, leases/file ledger and private
account-scoped Realtime channels and authorized subscriptions. See
`PROFILE_AVATARS.md` and `PROFILE_AVATARS_DEV_ROLLOUT.md` for exact contracts.

The history schedules these existing reviewed postgres jobs, without immediately
invoking cleanup: username reservations 03:17 UTC, closed public-template
moderation evidence 03:47 (24 months), terminal template sends 04:17 (180 days),
and Chat 04:47 (365 days). Verify exactly one of each stable job name and its SQL,
then observe natural execution. Do not manually invoke retention for a smoke test.
Avatar operation leases/cleanup remain request-driven; do not invent an avatar cron.

### Verification, monitoring and recovery

Before client distribution capture migration history, function active versions and
bundle hashes, advisor baseline/delta, bucket limits, policies/grants, cron rows,
Auth settings (names/status only), backup inventory and recovery owner. Investigate
new advisors; known intentional SECURITY DEFINER warnings require explicit review,
not blind suppression. Monitor Auth delivery/errors, Edge status/latency, database
CPU/locks/connections, Realtime disconnects and Storage/orphan growth. Avoid user
content, tokens and passwords in logs; Supabase client debug logging is disabled.
Thresholds/on-call response and retention commitments require owner decisions.

Run a bounded set of named disposable accounts and synthetic images/lists:
one upload, duplicate/stale request with a five-second deadline and no retry,
replacement, removal, fresh success, authorized/non-authorized/block reads,
own export, and deletion with both owned and surviving financial history. Test
quick-add duplicate prevention/recoverable offline drafts, unread/access removal,
settlement/reversal and cross-device Realtime. Never export/delete real accounts.
Keep a fixture ownership ledger; preserve any account to which the owner adds
content and clean only explicitly task-owned data. Inspect authoritative state
before retrying failed destructive operations. Local failure-injection evidence
does not authorize deliberate hosted outages.

Recovery is forward-only for schema: halt distribution, retain diagnostic state,
identify affected operations, review a forward migration/function repair and rerun
bounded smoke. Never restore old avatar-unaware deletion while files or ledger
entries can exist. For actual data loss, restore matched database and Storage
backups to a separate isolated target first, verify authorization/financial and
avatar invariants, and obtain explicit cutover approval. No automatic destructive
rollback is provided. Retention-deleted data is not recoverable merely by
unscheduling jobs. The previous compatible APK plus symbols remains archived;
Android downgrades/data clearing are never an implicit rollback mechanism.

## Public/store gate and references

Private owner installation and public/store release are separate approvals.
O-P18 remains open: proposed next decision is versioned terms acceptance before
Chat posting, in-app report-message/report-user plus existing block access,
UUID-authorized moderator queue, evidence access/retention, takedown notice and
appeal channel, and owner-approved response targets. These are proposals, not
implemented promises. Approve precise retention/authorization contracts before
schema or policy implementation. No silent feature disabling is planned.

`PUBLIC_RELEASE_DRAFTS.md` contains review drafts; final owner identity/contact,
policy URLs, external account-deletion resource, moderation commitments, age
policy, final branding and Play declarations remain required. The repository
launcher placeholder is not approved final branding.

Current official sources reviewed 2026-09-15:

- [Flutter Android release](https://docs.flutter.dev/deployment/android) and
  [SDK archive](https://docs.flutter.dev/install/archive).
- [Android 16 KB support](https://developer.android.com/guide/practices/page-sizes),
  [AGP 8.11 compatibility](https://developer.android.com/build/releases/agp-8-11-0-release-notes),
  [Play target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878).
- [Supabase production checklist](https://supabase.com/docs/guides/deployment/going-into-prod),
  [pricing](https://supabase.com/pricing), [backups](https://supabase.com/docs/guides/platform/backups),
  [SMTP](https://supabase.com/docs/guides/auth/auth-smtp) and
  [business conflict retry behavior](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b).
- [Play UGC](https://support.google.com/googleplay/android-developer/answer/9876937),
  [user data](https://support.google.com/googleplay/android-developer/answer/10144311),
  [account deletion](https://support.google.com/googleplay/android-developer/answer/13327111).
