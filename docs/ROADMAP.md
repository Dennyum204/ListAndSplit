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
- Implement the accepted versioned account-data export as its own vertical slice,
  then merge and manually verify it before beginning the separate accepted account
  hard-deletion slice.
- Add RLS and database-function tests for every relationship transition.

The friend relationship schema gate O-A09 is resolved: one current row uses the
five accepted states, deterministic pair locking, monotonic versions, server-owned
state-change time, and no detailed event log. The subsequent notification slice
references that row without replacing its action authority and still excludes
Realtime, push delivery, other notification types, public profiles, shared lists,
and the final navigation shell. Shared-resource block effects must be resolved
before shared lists ship. Resolve the immutable-username support/admin correction
path and avatar storage lifecycle before the later slices that encode them.
Shared-resource ownership/deletion, administrator deletion, moderation/legal
retention, Storage cleanup, and compliance obligations remain open beyond the
accepted current-aggregate account lifecycle.

## Phase 2 — Active/shared lists (planned)

Goal: deliver the core collaborative-list experience for accepted friends.

Candidate slices:

- Active-list creation and the agreed owner/member role lifecycle.
- Friend-only list invitations with Accept/Decline notifications.
- Item add, edit, complete, and delete behavior with quantity and optional unit.
- Multi-member item assignment and assignment notifications.
- General note editing, member `@mentions`, and mention notifications.
- Supabase Realtime updates routed through repositories.
- Authorization and concurrent-update tests for lists, membership, items, and notes.

Required decisions include roles, leave/remove/archive/delete behavior, item quantity
and ordering, mention parsing, invitation expiry/revocation, and initial concurrency
handling.

## Phase 3 — Templates and community discovery (planned)

Goal: add reusable content while preserving strict copy independence.

Candidate slices:

- Private templates with ordered groups/items and personal categories.
- Atomic snapshot import of a template into an active list.
- Public template visibility on profiles.
- Saving a public template as an independent recipient-owned deep copy.
- Sending a template to a friend with Accept/Decline and idempotent copy creation.
- A friends-only feed of recent public templates.
- Block-aware public profile, template, and feed visibility in both directions.
- Tests proving that source changes/deletion never mutate snapshots or recipient
  copies.

Required decisions include category cardinality/order, copy visibility and
attribution, feed ranking/pagination, provenance, versioning, and send expiry.

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
  retry, realtime reconciliation, and reconnect behavior.
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

- Whether basic templates should precede full collaborative lists.
- Which minimum persistent-notification capability belongs in later
  action-producing phases beyond the accepted friend-request foundation.
- When the accepted compile-time configuration should expand into a full
  development/staging/production flavor model.
- Whether offline read caching can ship safely before offline mutations.
- What constitutes the minimum community/safety feature set for an external beta.
