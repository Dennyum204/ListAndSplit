# List & Split roadmap

## How to read this roadmap

This roadmap describes proposed delivery order and gates, not dates or completed
work. Source code, tests, migrations, and pull requests are the evidence of
implementation. A phase heading does not imply that its capabilities exist.

Product behavior should be delivered as tested vertical slices. Before a slice
introduces schema, its relevant open decisions in [`DECISIONS.md`](DECISIONS.md)
and [`DATA_MODEL.md`](DATA_MODEL.md) must be resolved and recorded.

## Phase 0 — Bootstrap foundation (initial delivery scope)

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

## Phase 1 — Identity, profiles, and friendships (planned)

Goal: establish authenticated identity and the mutual social graph that gates later
collaboration.

Candidate slices:

- Implement verified email/password sign-up, sign-in, sign-out, verification
  resend, forgotten-password, password recovery, and session routing through the
  registered mobile callback.
- Add migration-driven owner-only profiles and verified-user onboarding with
  canonical globally unique immutable usernames and editable display names.
- Implement active directional block/unblock, private outgoing-block management,
  and secure exact canonical-username discovery with symmetric either-direction
  separation.
- After that gate, implement the resolved RPC-only relationship model: atomic
  send/cancel/accept/decline/end transitions, caller-relative active lists, strict
  reopening control, expected-version conflict protection, and the versioned
  one-current-state-per-unordered-pair mutual friendship contract.
- Introduce RPC-only persistent in-app friend-request notifications with atomic
  creation/suppression, block-aware keyset listing, read state, a bell badge, and
  exact 180-day logical expiry.
- The versioned account-data export slice is implemented and manually verified.
  The separate permanent self-service deletion slice now implements exact
  confirmation, password-only-to-Auth reauthentication, ten-minute
  `auth.sessions` validation, Auth-root current-aggregate cascades, the private
  30-day username reservation, daily physical cleanup, response-loss
  reconciliation, and other-device resume validation.
- Add RLS and database-function tests for every relationship transition.

The friend relationship schema gate O-A09 is resolved: one current row uses the
five accepted states, deterministic pair locking, monotonic versions, server-owned
state-change time, and no detailed event log. The subsequent notification slice
references that row without replacing its action authority and still excludes
push delivery, other notification types, and public profiles. The four-tab
authenticated shell now includes secure shared-list membership and private
account-scoped Realtime reconciliation.
Resolve the immutable-username support/admin correction
path and avatar storage lifecycle before the later slices that encode them.
Shared-resource ownership/deletion, administrator deletion, moderation/legal
retention, Storage cleanup, and compliance obligations remain open beyond the
implemented self-service current-aggregate account lifecycle.

## Phase 2 — Active/shared lists (in progress)

Goal: deliver the core collaborative-list experience for accepted friends. This
phase is in progress through owner and accepted-member collaboration.

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

## Phase 3 — Templates and community discovery (in progress)

Goal: add reusable content while preserving strict copy independence.

Current private-template and Public Template Foundation slices:

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
- Existing private account invalidation is reused only for owner/copier/block
  accounts. No notification, new topic, public/global fanout, dependency, Edge
  Function, configuration, or platform change is introduced.

Later candidate slices:

- Sending a template to a friend with Accept/Decline and idempotent copy creation.
- A friends-only feed of recent public templates.
- Reporting/takedown workflow and tooling before any external public-content
  rollout.

Private category cardinality, copy atomicity, capacity, versioning, public
visibility/category placement, no-provenance behavior, and profile presentation
are resolved. Feed ranking/pagination/retention, sent-template expiry/acceptance,
and reporting/takedown remain open. O-P13 is a hard gate before external beta or
production public-content rollout.

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

## Phase 5 — Offline tolerance and push delivery (planned later)

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

## Phase 6 — Public safety, hardening, and release readiness (planned)

Goal: make public/community behavior supportable and prepare a production-quality
release.

Candidate slices:

- Extend Phase 1 basic blocking to public content and add content/user reporting
  with a reviewed moderation workflow.
- Privacy/retention hardening and abuse-response implementation beyond the Phase 1
  account lifecycle.
- Accessibility and localization audits.
- Security review of RLS, functions, storage, realtime, secrets, and dependency
  supply chain.
- Performance, resilience, observability, and migration rollback/recovery planning.
- Release signing, store metadata, supported-device testing, and production
  environment planning under separate explicit authorization.

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

## Sequencing decisions still open

- Which minimum persistent-notification capability belongs in later
  action-producing phases beyond the accepted friend-request, list, item-
  assignment, and General Note mention foundations.
- When the accepted compile-time configuration should expand into a full
  development/staging/production flavor model.
- Whether offline read caching can ship safely before offline mutations.
- What constitutes the minimum community/safety feature set for an external beta.
