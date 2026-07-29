# List & Split roadmap

## How to read this roadmap

This roadmap describes proposed delivery order and gates, not dates or completed
work. Source code, tests, migrations, and pull requests are the evidence of
implementation. A phase heading does not imply that its capabilities exist.

Product behavior should be delivered as tested vertical slices. Before a slice
introduces schema, its relevant open decisions in [`DECISIONS.md`](DECISIONS.md)
and [`DATA_MODEL.md`](DATA_MODEL.md) must be resolved and recorded.

The major foundations through PR #26 and the Android environment boundary in PR
#27 are implemented in source. That does not collapse the distinct states of
source-merged, deployed to List & Split Dev, physically verified, beta-released,
or Production-released. Production remains fail-closed and unconfigured.

## Next delivery sequence

1. PR #28 reconciles documentation and the roadmap.
2. The read-only List Chat product/security/architecture preflight resolves the
   bounded v1 contract.
3. PR #29 implements the secured database/domain foundation without deployment or
   reachable UI.
4. PR #30 implements the Flutter experience and scoped Realtime reconciliation;
   two-device Dev QA passed on 2026-07-29 and source merge remains separately
   controlled.
5. PR #31 separately schedules retention after authorized rollout and QA.
6. Freeze feature selection, classifying each remaining idea as required before
   redesign, post-beta, or rejected; historical ideas are not automatic promises.
7. Implement only the additional functionality Fernando explicitly selects.
8. Apply the Figma design system and UI refactor to stable functionality,
   screen by screen.
9. Finalize branding and adaptive, monochrome, and Play launcher icons.
10. Revalidate official requirements and implement Android release infrastructure:
   the supported toolchain, Play Console, Play App Signing and separate upload
   key, protected CI, signed AAB, symbols, versioning, and artifact retention.
11. Complete beta operations/compliance readiness and an internal Android beta.
12. Perform separately authorized Production Supabase and Play rollout.
13. Plan iOS/TestFlight as a later, separately approved release surface.

The Android beta-pipeline work previously considered for PR #28 is deferred.
There is no Play Console developer account and no approved final launcher icon.
Earlier toolchain recommendations are provisional research only and must be
revalidated when step 8 begins.

## Phase 0 — Bootstrap foundation (implemented)

Goal: establish a runnable, reviewable mobile foundation and safe development
workflow without implementing product features.

Scope:

- Create a Flutter stable project for Android and iOS only.
- Set project name `list_and_split`, display name `List & Split`, and exact Android
  and iOS identifier `com.ferbatech.listandsplit`.
- Start in `ProviderScope`, use `MaterialApp.router` and a small `go_router`, and
  show a minimal branded foundation screen.
- Establish light and dark Material 3 themes and localization-ready structure.
- Add compatible stable Riverpod, `go_router`, Supabase Flutter, Freezed annotation,
  and JSON annotation dependencies plus required generators/lints.
- Keep the app runnable without Supabase credentials.
- Add practical repository guidance and product/architecture documentation.
- Initialize standard Supabase local-development configuration and migration
  directories, with **no business tables or migrations**.
- Create at most the single authorized hosted development project, `List & Split
  Dev`, preferring Zurich (`eu-central-2`) and a free plan. Do not create production
  or Firebase projects.
- Add CI for dependency resolution, formatting, analysis, and tests.
- Add a meaningful foundation widget smoke test.

Exit evidence:

- Formatting, static analysis, tests, and `git diff --check` pass.
- A debug Android build is attempted when the local SDK is healthy; blockers are
  recorded rather than hidden.
- Platform identifiers, generated artifacts, secrets, and documentation claims are
  reviewed.
- Work is published only on the authorized task branch and draft pull request; it
  is not merged automatically.

## Phase 1 — Identity, profiles, and friendships (foundation implemented)

Goal: establish authenticated identity and the mutual social graph that gates later
collaboration.

Implemented slices:

- Verified email/password sign-up, sign-in, sign-out, verification
  resend, forgotten-password, password recovery, and session routing through the
  registered mobile callback.
- Migration-driven owner-only profiles and verified-user onboarding with
  canonical globally unique immutable usernames and editable display names.
- Active directional block/unblock, private outgoing-block management,
  and secure exact canonical-username discovery with symmetric either-direction
  separation.
- The resolved RPC-only relationship model: atomic
  send/cancel/accept/decline/end transitions, caller-relative active lists, strict
  reopening control, expected-version conflict protection, and the versioned
  one-current-state-per-unordered-pair mutual friendship contract.
- RPC-only persistent in-app friend-request notifications with atomic
  creation/suppression, block-aware keyset listing, read state, a bell badge, and
  exact 180-day logical expiry.
- The versioned account-data export slice is implemented and manually verified.
  The separate permanent self-service deletion slice now implements exact
  confirmation, password-only-to-Auth reauthentication, ten-minute
  `auth.sessions` validation, Auth-root current-aggregate cascades, the private
  30-day username reservation, daily physical cleanup, response-loss
  reconciliation, and other-device resume validation.
- RLS and database-function coverage for every relationship transition.

The friend relationship schema gate O-A09 is resolved: one current row uses the
five accepted states, deterministic pair locking, monotonic versions, server-owned
state-change time, and no detailed event log. The subsequent notification slice
references that row without replacing its action authority and still excludes
push delivery, other notification types, and public profiles. The four-tab
authenticated shell now includes secure shared-list membership and private
account-scoped Realtime reconciliation.
The immutable-username support/admin correction path and avatar storage lifecycle
remain open and must be resolved before a later slice encodes either.
Shared-resource ownership/deletion and the Public Template v1 moderation/retention
contract are resolved. Administrator deletion, appeal/compliance, moderation/legal
retention beyond that contract, Storage cleanup, and broader compliance obligations
remain open beyond the implemented self-service current-aggregate lifecycle.

## Phase 2 — Active/shared lists (core scope complete)

Goal: deliver the core collaborative-list experience for accepted friends. The
selected online owner/member foundation is implemented; optional extensions remain
subject to feature-freeze selection.

Implemented slices:

- A state-preserving authenticated shell with Lists, Templates, Community, and
  Profile; notifications remain a bell destination above the shell.
- One-owner lists with create/read/rename/archive/restore/permanent-delete,
  active/archived keyset listing, aggregate counts, exact expected versions, and
  retry-safe creation.
- Owner list items with exact integer-thousandths quantities, stable unit codes,
  add/edit/complete/reopen/delete, atomic deterministic reorder, and archived
  read-only enforcement, plus a hard 200-current-item limit that never changes or
  deletes legacy over-capacity data.
- RPC-only tables with forced RLS, explicit rejection policies, reviewed
  definer-rights functions, Auth-root deletion cascade, and account export schema
  version `3`.
- One retained versioned access lineage, owner-managed persistent invitations,
  member item access, 20-person capacity, accepted participant projections, and
  archived-list access rules.
- Atomic friendship/block effects, actionable/informational list notifications,
  privacy-minimal account export schema version `3`, and deletion-impact warning.
- Private account-scoped Supabase Broadcast receive authorization, transaction-local
  opaque database invalidations, and generation-safe Flutter reconciliation after
  joins, events, reconnects, and app resume. RPCs and manual refresh remain
  authoritative fallbacks.
- Immediate current-owner-to-accepted-member ownership transfer with explicit
  confirmation, monotonic retained access versions, unchanged capacity/content,
  informational notification, lifecycle projection updates, and private Realtime
  reconciliation.
- Current zero-to-20 item assignments for the owner and accepted members,
  including self-assignment, completed-item editing, atomic initial/full-set writes,
  exact version protection, legacy item-client compatibility, and automatic
  access-loss cleanup. Assignments remain current state only and never copy into
  templates.
- Informational notifications only when another user newly assigns the recipient,
  with live-resolved names, normal 180-day logical expiry, permanent block/access-
  loss suppression, private Realtime reconciliation, and localized accessible
  English/Portuguese presentation.
- Assignment-aware account export schema version `7` for caller-owned item
  contents through the new `export_own_account_data_v7()` RPC. The existing
  schema-version-6 endpoint remains unchanged, and shared lists remain
  metadata-only without item or assignment data.

Implemented General Note delivery:

- One optional list-level General Note with active owner/member editing, archived
  read-only display, normalized 2,000-code-point text, explicit stable-profile-ID
  current-member `@mentions`, persistent mention notifications, private Realtime
  reconciliation, and draft-preserving note/version/mention-eligibility conflict
  recovery. Access loss/deletion and remote archive use the established safe
  one-time exit/read-only behavior.
- Notification v3 adds mention-aware listing/count while v1/v2 preserve their
  strict type sets. Stored suppression remains permanent, and the unchanged
  mark-read public boundary applies note-aware access/privacy predicates.
- Account export schema version `8` adds General Note text and minimal current
  resolved mentions only inside caller-owned full lists while preserving versions
  `1` through `7` and P-039 shared-list metadata privacy.
- General Note templates remain item-only. Save never copies note/mentions,
  create-list starts with null note/version `1`/no links, and existing-list import
  preserves its destination note.
- The additive note/mention delivery adopts the global profile→pair-when-needed
  →list→ordered-child→notification hierarchy and replaces the prior account-
  deletion Split-child/list inversion with one parent-first coordinator.

The General Note/mention slice is merged, deployed to List & Split Dev, and passed
its required two-phone physical QA. Further environment rollout still requires
separate authorization.

Mention parsing, representation, eligibility, notification, template, export, and
online conflict behavior are resolved by P-049/P-050 and A-054 through A-057.
Offline mutation/conflict behavior remains open.
Role lifecycle, ownership transfer, invitation retention/revocation,
shared-resource blocking, archive/delete, item quantity/order, item-assignment
permissions/lifecycle/notifications/export, and online assignment concurrency are
resolved.

### Next capability: List Chat in three bounded PRs

P-058/A-070 resolve List Chat's database/domain contract. PR #29 adds the
RPC-only forced-RLS message/state/request model, durable server-owned position
order, lifecycle-safe idempotent sends/tombstones/unread, export v12, opaque
`chat_invalidate`, strict Dart repository support, and an unscheduled bounded
365-day retention function. PR #29 itself did not deploy the migration or expose
Chat to a user; the migration was later separately deployed and verified only in
List & Split Dev.

PR #30 adds the separate accessible/localized Lists route, controller, composer,
history/unread UI, and scoped authoritative reconciliation on the existing
recovered private account channel. Its automated verification belongs to the PR,
and two-device Dev QA passed on 2026-07-29. PR #31 separately schedules
`list-chat-retention-daily` at 04:47 UTC after separate authorization; the cleanup
remains unscheduled until then.

Attachments, images/files, Markdown enrichment, reactions, typing indicators,
audio/video, persistent notifications, push, read receipts, offline sends, E2EE
claims, and general private messages remain outside v1. Terms acceptance,
content/user reporting, and operational moderation are a mandatory gate before
public distribution, not part of PR #29.

## Phase 3 — Templates and community discovery (core scope complete)

Goal: add reusable content while preserving strict copy independence.

Current private-template and Public Template slices:

- Private templates with ordered items, optional single personal category,
  100-template/25-category quotas, and 200 current items per template.
- Private category create/rename/delete with normalized per-owner uniqueness,
  visible empty categories, and atomic move to Uncategorized on deletion.
- Saving an accessible active/archived list as an independent private template,
  creating a new active list from a template, and atomic selected-item import into
  an existing active list from either template detail or the already-open active
  list with a fixed destination.
- Template copies remain item-only: General Note text and resolved mentions are
  never saved, a newly created list starts with a null version-1 note/no links, and
  import preserves the existing destination note and links.
- A non-destructive 200-current-item shopping-list capacity enforced for ordinary
  creation and every copy/import path under existing list locks.
- Search across template/item names, one category filter, Recently updated/A-Z/
  Newest created sorts, private account Realtime reconciliation, and account export
  schema version `4`/Auth-root deletion integration.
- Explicit owner publication/unpublication with private default, versioned
  desired-state idempotency, public-name eligibility, visible Private/Public state,
  and owner-only mutation.
- Block-aware profile-only public-template pages/details for fully onboarded
  authenticated friends and nonfriends, with strict minimal field allowlists,
  stable bounded publication-time/UUID keyset pagination, immutable-ID Community
  routes, manual refresh, and app-resume reconciliation.
- Atomic Save a copy into a caller-owned private Uncategorized template, with new
  UUIDs, no provenance, exact source-version/block/quota reauthorization,
  payload-bound retry idempotency, and complete source independence.
- Account export schema version `9` adds only caller-owned publication state/time
  while versions `1` through `8` and their endpoints remain unchanged.
- Exact-revision reporting for every authenticated non-owner across eight stable
  reasons, conditional bounded explanation, immutable public-content snapshots/
  fingerprints, one report per reporter/template revision, and immediate
  reporter-only hiding without an implicit block.
- An initially empty immutable-Auth-UUID moderator allowlist, protected bounded
  Open/Taken down/Closed review, current-versus-snapshot comparison, dismiss,
  template-level takedown, and restore without automatic republication.
- Restricted owners retain private edit/delete/item access while publication is
  denied. Takedown/restoration create exactly one privacy-safe actor-null owner
  notification through notification v4; report/dismiss create none.
- Account export schema version `10` adds only the caller's own submitted report
  reason, nullable explanation, and date, while versions `1` through `9` and their
  endpoints remain unchanged.
- Existing private account invalidation is reused for affected reporters,
  moderators, and owners. Moderation tables are not published and no new topic,
  public/global fanout, dependency, Edge Function, configuration, or platform
  change is introduced.
- Fully closed inactive evidence has a 24-month retention contract and a private
  idempotent cleanup to nonidentifying tombstones. The separate additive A-062
  operational migration owns its stable daily schedule per explicitly authorized
  environment; it is not part of the O-P13 schema migration.
- Template-send database/domain foundation for owned private/public zero-to-200
  item immutable friend offers, with five states, one pending triple, exact
  version and payload-bound request idempotency, atomic private Uncategorized
  acceptance, persistent Received/minimal Sent projections, and relationship/
  block/source/moderation/account lifecycle.
- Notification v5 adds exactly one recipient template-send notification while
  v1-v4 remain unaware. Export v11 adds role-specific provenance-free offer
  projections while v1-v10 remain unchanged. Opaque private account invalidation
  is reused. The strict Dart repository, localized Shared Templates UI,
  notification-v5 routing, and export-v11 client are implemented.
- Terminal template-send history has an idempotent 180-day cleanup function. The
  bounded A-065 operational migration defines one stable daily 04:17 UTC schedule
  per explicitly authorized environment without invoking cleanup during
  deployment. Production remains unscheduled until separately authorized.
- A friends-only Community feed reads current accepted relationships and the
  existing public-template safety predicates at request time. It excludes self,
  blocks, active restrictions, and caller-reported templates; orders by
  publication time/UUID; and uses bounded keyset pages without a stored feed,
  count, age cutoff, ranking, retention, notification, or new Realtime fan-out.
  Freshness is explicit refresh/resume plus applicable private invalidations.

Completed delivery:

- PR #24: localized, accessible Send/Received/Sent/Accept/Decline/Revoke UI,
  notification-v5 actions, export-v11 client integration, and two-device
  reconciliation over the PR #23 server/domain contract.
- PR #25: forward-only, same-name-convergent scheduling for the existing
  template-send terminal-retention function, with local catalog and retention
  boundary coverage. Its migration was separately deployed and verified in List &
  Split Dev; Production remains a separate rollout gate.
- PR #26: P-056/A-066 chronological friends-only public-template feed with one
  hardened read-through RPC and localized Community UI. Its migration was
  separately deployed to List & Split Dev and its two-device physical QA passed;
  neither fact is beta or Production release evidence.

Private category cardinality, copy atomicity, capacity, versioning, public
visibility/category placement, no-provenance behavior, and profile presentation
are resolved. Reporting/takedown/restoration/retention is resolved by P-053/P-054
and A-060 through A-062, closing O-P13 and owning the separate daily retention
schedule. Moderator assignment, client distribution, physical QA, and each hosted
environment remain explicit operational evidence and authorization gates rather
than consequences of a source merge.
Feed-v1 recency, pagination, and no-retention semantics are resolved by
P-056/A-066; global/ranked/recommended discovery remains deferred. Template-send
product/database semantics, Flutter UI, and source-controlled retention schedule
are resolved by P-055 and A-063 through A-065; hosted rollout remains
environment-specific, with the Dev schedule deployed and Production unscheduled.

## Phase 4 — Split expense ledger (core scope complete)

Goal: provide an optional, correct expense ledger inside active lists without
processing payments.

Current slices:

- Owner-enabled list-scoped Split with one `CHF`/`EUR` currency. It may change only
  while no expense exists and no settlement history has ever existed; the first
  settlement locks it permanently.
- Versioned active-list expense create/edit/delete for current owners and accepted
  members, with persistent historical financial identities.
- Transactional equal splits in integer minor units with deterministic UUID-order
  remainder allocation and on-demand settlement-adjusted balances.
- Exact custom CHF/EUR minor-unit shares with positive unique participant amounts,
  exact conservation, zero-as-deselection, payer exclusion, retained historical
  roles, Equal/Custom conversion, and no persisted allocation-mode field.
- Deterministic largest-balance-first suggested payments with stable participant-ID
  tie-breaks. They are deliberately not described as mathematically minimum.
- Full and partial external-bookkeeping settlement records, server-derived recorder
  attribution, immutable history, one-time append-only reversals, historical
  participant endpoints, and bounded newest-first keyset pages.
- Archived read-only history, payload-bound retry idempotency, stale/concurrent
  protection, private Realtime invalidation/reconciliation, caller-owned-list Split
  export schema version `6`, and hard-deletion-safe anonymization.
- Additive versioned expense RPCs with normalized custom-pair validation, unchanged
  read shapes, legacy equal-client compatibility, and a guard that prevents an old
  client from replacing non-equal custom shares. The migration must deploy before
  distributing the client; export remains version `6` with versions `1` through
  `6` compatibility.
- Comprehensive server constraint/RLS/RPC and Flutter repository/controller/widget
  coverage.

Percentage/weight/ratio or automatic proportional allocation, recipient approval/
disputes, backdating, attachments, a mathematically minimum solver, and
payment-provider or money-transfer integration remain out of scope.

## Phase 5 — Offline tolerance and push delivery (optional later backlog)

Goal: improve reliability and timeliness after online data flows are stable.

Candidate slices:

- Introduce SQLite behind repository boundaries for active-list caching.
- Define and test mutation queues, idempotency, conflict resolution, tombstones,
  retry, and cache reconciliation around the accepted online Realtime boundary.
- Decide which mutations, if any, are safe while offline.
- Add FCM and APNs registration, delivery, preferences, and notification deep links.
- Handle device-token rotation/removal and redact sensitive notification content.

This phase requires an explicit sync design. It does not itself authorize creation
of a Firebase project.

## Phase 6 — Public safety implemented; release readiness deferred

Goal: make public/community behavior supportable and prepare a production-quality
release.

Implemented foundation:

- Public-content block symmetry plus exact Public Template reporting, private
  reviewed moderation, restriction-backed takedown/restoration, safe owner
  outcomes, account-export v10, and 24-month detailed-evidence retention.
- Explicit default-deny moderation storage, UUID-only allowlisting, audit events,
  immediate revocation, account-deletion anonymization, and no client/private
  evidence in Realtime.
- Android Dev/Production identity separation: Dev uses the `.dev` package, Dev
  label/callback, and exact Dev-host allowlist; Production keeps the unsuffixed
  identity and callback but fails closed without an approved backend contract.
  PR #27 physical QA verified separate installation/storage, existing Dev data,
  session persistence, and Dev callback routing on one physical Android device
  and one Android emulator. This is not beta or Production release evidence.

Remaining candidate slices:

- Maintain the environment-specific moderator/bootstrap and A-062 retention
  scheduling runbooks; Production remains independently authorized and verified.
- Appeal, administrator/compliance, legal-retention, evidence-export, and
  abuse-response behavior beyond the intentionally bounded v1 workflow.
- Accessibility and localization audits.
- Security review of RLS, functions, storage, realtime, secrets, and dependency
  supply chain.
- Performance, resilience, observability, and migration rollback/recovery planning.
- After the feature/Figma/branding gates, revalidated release signing, store
  metadata, supported-device testing, and Production planning under separate
  explicit authorization.

No production Supabase project is implied by this roadmap. Creating one requires a
future, explicit task with environment and cost approval.

## Gates that apply to every phase

- Resolve behavior that changes authorization, data invariants, or user-visible
  outcomes before encoding it in schema or code.
- Commit schema changes only as reviewed migrations; enable and test RLS in each
  application table's creating migration.
- Use integer minor units for every monetary path and test conservation of value.
- Keep repositories as the client data source of truth.
- Follow the accepted global profile→pair-when-needed→parent→ordered-child
  →notification/Broadcast lock hierarchy and prove cross-aggregate races with real
  sessions rather than timing-only tests.
- Add unit, repository/view-model, widget, database-function, and RLS tests in
  proportion to the slice.
- Update product, architecture, data-model, roadmap, and decision documentation when
  their contracts change.
- Pass formatting, analysis, tests, diff checks, and relevant platform builds.
- Review for secrets, privileged client keys, generated output, unrelated changes,
  and overstated completion.
- Publish through a focused task branch and draft pull request. Never auto-merge.

## Optional backlog, not release promises

The feature-freeze review may defer or reject these ideas. Their presence here
does not make them prerequisites for redesign, beta, or Production:

- offline read caching and a separately designed offline mutation queue;
- push delivery plus notification preferences/archive;
- avatars and image uploads;
- expanded notification and feature deep links;
- advanced Split percentages, receipts, recurring expenses, and charts;
- additional locales;
- advanced moderation and administrator tooling;
- observability and analytics; and
- payment processing or provider integration.

List Chat's bounded v1 is the only accepted next capability. P-058/A-070 resolve
its database/domain foundation and A-071 records PR #30 client reconciliation.
PR #30 physical QA is complete; PR #31 retention scheduling and the exact
public-release reporting/moderation workflow remain open.
Play/signing/AAB/icon/store work is deferred by A-069, and Production remains
separately authorized.
