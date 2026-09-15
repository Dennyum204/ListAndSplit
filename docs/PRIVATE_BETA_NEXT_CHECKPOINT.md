# Next private-beta checkpoint — 2026-09-15

Base: main `9d6ef896d0d7d00af9afd49546960a90307ed4ea` (PRs 33–36 merged).
Worktree: `C:/Work/Projects/Mobile/ListAndSplit-BetaNext`. Fernando and Susana
report successful use of their existing accounts. Preserve every real account,
session and item, including the adopted QA account and “Coisas para Casa 😁”.
Never use or repair the damaged ProjectListsApp checkout.

## Three draft deliveries

- [PR #37](https://github.com/Dennyum204/ListAndSplit/pull/37),
  `codex/chat-login-stability`, `1d75bf8`: stable bubble action geometry,
  fixed-origin history, smooth tail following, history-position preservation and
  accessible Login hints without floating labels. Existing confirmed-only,
  request-bound retry/reconciliation remains authoritative. CI passed at that
  head (34930574900). 42 focused widget checks include identity/geometry,
  pagination anchors, viewport changes and EN/PT light/dark filled-field semantics.
- [PR #38](https://github.com/Dennyum204/ListAndSplit/pull/38),
  `codex/launcher-welcome`, `4ec3649`, stacked on #37: original gold/charcoal
  shared-list mark, adaptive/legacy/monochrome sources and a concurrent cold-start
  cover. 45 startup/application checks cover restored signed-out/signed-in/recovery
  routes, urgent/reduced-motion bypass, no resume replay and EN/PT at 200%.
  Initial CI passed (34931256387); resulting-head CI pending after the scope fix. Preview: `assets/branding/launcher-preview.png`.
- `codex/android-push`, stacked on #38: native FCM bridge and Profile preference,
  session-bound registrations and narrow token rotation, private committed-event
  outbox, bounded worker and authenticated tap resolution. Full contract and exact
  deployment/recovery sequence: [ANDROID_PUSH.md](ANDROID_PUSH.md).

All new PRs must remain draft, unmerged and without auto-merge. No old merged PR
is reused. The final artifact manifest records the exact integrated source SHA.

## Integrated local verification

- Flutter formatting and analysis pass. Complete suite: **993 passed, one existing
  opt-in skip**. Four initial Profile fixture failures were missing the new push
  repository mock; the corrected fixtures retain all avatar/draft assertions.
- Native Dev debug compilation and three Kotlin envelope/binding tests pass.
  This compilation APK has no client configuration and must never be installed.
- Isolated `beta_push_local_20260915`: **2,057 database assertions / 34 files** pass.
  Fresh migration application, public/private schema lint and local security
  advisors pass. No hosted reset, unrelated Docker project or volume was touched.
- Six Edge checks pass, including actual signed OAuth/FCM HTTP adapter calls to a
  mock transport, one-attempt response mapping and worker authorization. These
  are not proof of real Google delivery.
- Actual isolated Auth/PostgREST HTTP lifecycle passes: enrollment authorization,
  two devices, no historical replay/self-alert, token rotation and stale token
  rejection, invitation invalidation, Chat request deduplication, logout,
  account switching, blocking, unchanged fresh-token binding after old invalid
  response, bounded retries and deletion of only the local task fixtures.
- Existing avatar/delete-account bundles are byte-identical. New source inventory
  is 31 migrations and three function bundles. Production preparation intentionally
  remains closed to this new inventory until separately reviewed/authorized.

## External setup and distribution

Firebase CLI 15.30.1 / Node 24.21.0 are installed. CLI account inventory is empty;
the owner's local Firebase login remains the actual setup blocker. No Firebase
project, service account, hosted push migration, worker or Vault setting has been
created. No billing, Production, SMTP or existing hosted content has changed.

The user permits a clearly labelled interim configured Dev APK. Until real FCM
setup and end-to-end acceptance pass, omit all four Firebase public settings:
Profile reports push unavailable, no registration RPC/permission is attempted,
and the existing 30-migration Dev backend remains compatible. Retain package
`com.ferbatech.listandsplit.dev` and the exact distributed v3 signer. VersionCode 5
is the corrected release: version 4 was installed only for QA and is withheld. APK, checksum,
signer verification and installation notes belong outside Git in a unique
`C:/Work/QA/ListAndSplit/private-beta-20260915-v5` release folder.

Final device checks are pending at this source checkpoint; never infer spoken
TalkBack or physical delivery from widget/semantics tests. Emulator is connected;
Samsung currently requires USB reconnection. Capture the signed-in UI immediately
before updating, install with replacement only, then verify session retention.
Do not uninstall, clear data, send test notifications to real users or modify the
protected unsuffixed app. New FCM enable/denied/background/terminated/tap/account
QA must wait for backend setup and use task-owned fixtures. Public distribution,
APNs, template images, offline queues and Production remain deferred.

## Device-found startup correction

The first integrated v4 QA installation exposed a Riverpod scope error: public
Dev settings were compiled, but ordinary dependent providers inherited the
welcome ancestor default rather than the nested configured scope. No sign-out
or data removal was performed. Version 4 is withheld, not shareable. PR #38 now
places the welcome and configured application in independent sibling root
scopes. A delayed-initialization regression proves the configured dependency
and mounted destination survive cover dismissal. This fix is merged normally
into #39; repeat integrated Flutter/build/device gates for the corrected source.
