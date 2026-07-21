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
  read-only enforcement. The next additive slice caps current rows at 200 without
  changing or deleting legacy data.
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

Remaining candidate slices:

- Multi-member item assignment and assignment notifications.
- General note editing, member `@mentions`, and mention notifications.
- Authorization and concurrent-update tests for future membership and notes.

Required decisions still include mention parsing and offline conflict behavior.
Role lifecycle, ownership transfer, invitation retention/revocation,
shared-resource blocking, archive/delete, item quantity/order, and online
concurrency are resolved.

## Phase 3 — Templates and community discovery (in progress)

Goal: add reusable content while preserving strict copy independence.

Current private-template slice:

- Private templates with ordered items, optional single personal category,
  100-template/25-category quotas, and 200 current items per template.
- Private category create/rename/delete with normalized per-owner uniqueness,
  visible empty categories, and atomic move to Uncategorized on deletion.
- Saving an accessible active/archived list as an independent private template,
  creating a new active list from a template, and atomic selected-item import into
  an existing active list from either template detail or the already-open active
  list with a fixed destination.
- A non-destructive 200-current-item shopping-list capacity enforced for ordinary
  creation and every copy/import path under existing list locks.
- Search across template/item names, one category filter, Recently updated/A-Z/
  Newest created sorts, private account Realtime reconciliation, and account export
  schema version `4`/Auth-root deletion integration.

Later candidate slices:

- Public template visibility on profiles.
- Saving a public template as an independent recipient-owned deep copy.
- Sending a template to a friend with Accept/Decline and idempotent copy creation.
- A friends-only feed of recent public templates.
- Block-aware public profile, template, and feed visibility in both directions.
- Tests proving that source changes/deletion never mutate snapshots or recipient
  copies.

Private category cardinality, copy atomicity, capacity, and versioning are resolved.
Public copy visibility/category placement and attribution, feed ranking/pagination,
provenance presentation, and sent-template expiry remain open.

## Phase 4 — Payment Control ledger (planned)

Goal: provide an optional, correct expense ledger inside active lists without
processing payments.

Candidate slices:

- Enable Payment Control with a single list currency and explicit lifecycle rules.
- Record expenses with one payer and selected participants.
- Support equal splits with deterministic integer remainder allocation.
- Support exact custom integer-minor-unit shares with server validation.
- Record settlements between list members.
- Calculate authoritative balances and debts server-side.
- Add comprehensive server unit tests, RLS tests, and client presentation tests.

This phase must not start schema implementation until supported currencies, amount
ranges, rounding/remainder, correction/reversal, member-removal, and debt-output
rules are accepted. Payment-provider or money-transfer integration is out of scope.

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
  action-producing phases beyond the accepted friend-request foundation.
- When the accepted compile-time configuration should expand into a full
  development/staging/production flavor model.
- Whether offline read caching can ship safely before offline mutations.
- What constitutes the minimum community/safety feature set for an external beta.
