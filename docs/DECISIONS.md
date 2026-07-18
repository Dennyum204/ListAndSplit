# Product and architecture decisions

## Record semantics

This log captures decisions agreed for List & Split as of 2026-07-18. **Accepted**
means the direction is agreed; it does not mean the behavior is implemented. Check
code, tests, migrations, and pull requests for implementation status.

Open questions are listed separately and must not be resolved implicitly in code.
When a decision changes, update this log and the affected product, architecture,
and data-model documents in the same pull request.

## Accepted decisions

### Product

| ID | Decision | Consequence |
| --- | --- | --- |
| P-001 | The product name is **List & Split**. The Flutter package/project name is `list_and_split`. | Human-facing and code identifiers deliberately differ. |
| P-002 | The application combines active/shared lists, templates, community, optional Payment Control, and notifications. | These are product areas, not claims of implementation status. |
| P-003 | The former term **Internal Lists** is replaced by **Templates**. | New UI, code, and documentation use “Templates.” |
| P-004 | Active-list members can add, edit, complete, and delete items with quantities, optional units, and multiple assignees. Lists also have a general note with `@mentions`. | Item/member/note authorization and notification behavior require explicit models. |
| P-005 | Only accepted friends can be invited to an active/shared list. | Friendship is a server-validated prerequisite for invitation creation. |
| P-006 | Templates contain reusable groups/items, can be private or public, and are organized by owners into personal categories. | Visibility and personal organization are separate concerns. |
| P-007 | Importing a template into an active list is a snapshot copy. Saving a public template or accepting a sent template creates an independent recipient-owned deep copy. | Source changes or deletion never mutate existing imports/copies. New identifiers and atomic/idempotent copy operations are required. |
| P-008 | Community relationships are mutual friendships, not followers. Block-aware discovery by unique username precedes sending, accepting, or declining friend requests. | Friendship has symmetric meaning even though requests are directional; discovery and requests do not precede basic blocking. |
| P-009 | Public templates appear on profiles, and the community feed shows recent public templates from friends. | Private templates are excluded; feed ranking details remain open. |
| P-010 | Public content must support basic blocking and eventually support reporting. | Phase 1 blocking precedes discovery; community maturity still depends on a future reporting/moderation design. |
| P-011 | Payment Control is available only when enabled inside an active list and is an expense ledger, not payment processing. Each enabled list has one currency. | No wallet/payment-provider integration; ledger access follows list membership. |
| P-012 | An expense has one payer and selected participants, with equal or exact custom splits. Settlements can be recorded between members. | Participant/share and settlement records require strict server validation. |
| P-013 | Money is represented only in integer minor units; authoritative balance and debt calculations run server-side and have unit tests. | Floating-point monetary values are prohibited at every boundary. |
| P-014 | The in-app notification centre is persistent. Friend requests, list invitations, and sent templates require Accept/Decline; assignments and mentions notify recipients. | Action state must survive sessions and be safe under retry/stale UI. |
| P-015 | The primary destinations are Lists, Templates, Community, and Profile. Notifications open from a bell, not a fifth tab. | The root navigation shell has exactly four primary destinations. |
| P-016 | English is the initial UI language, but the application remains localization-ready. | User-facing strings and layout must not assume English is permanent. |
| P-017 | Initial authentication uses email and password only. Email verification is mandatory before authenticated application access; sign-up, sign-in, sign-out, verification resend, forgotten-password, and password-recovery flows are required. New and replacement passwords require at least eight characters, and confirmation must match the unmodified password exactly. | Google, Apple, anonymous, magic-link-only, and other providers are excluded from the initial release. Authentication errors must not disclose account existence where that would be inappropriate. Passwords are not trimmed, lowercased, or subject to composition rules. |
| P-018 | A user chooses a username during onboarding after authentication and email verification. It is trimmed, lowercased, globally unique, matches `^[a-z][a-z0-9_]{2,23}$`, and becomes immutable after onboarding. Display name is separate, trimmed, non-unique, editable, and 1-50 characters. | PostgreSQL enforces canonicalization, validation, uniqueness, and immutability. Email remains private and is never copied into public profile data. |
| P-019 | The initial profile slice is owner-only: a user can read and update only their own approved profile fields. Cross-user discovery waits for a block-aware friendship slice. | A permissive interim profile-read policy is prohibited. Avatar editing remains accepted future behavior, outside the initial profile slice. |
| P-020 | Basic user blocking is sequenced in Phase 1 before username discovery and friend requests. | The blocking/discovery slice is independently reviewable and does not authorize friend request or friendship schema. |
| P-021 | Blocking is a silent, independently directional action, while any active block in either direction creates symmetric separation. Users privately manage only their outgoing blocks; block and unblock are idempotent, unblock removes only the caller's row, and no relationship is restored. | Exact discovery, future friend requests/contact, and future public profile/template/feed visibility exclude either-direction blocks. Missing and block-suppressed usernames share one generic result. Shared-resource effects and reporting/moderation remain open. |
| P-022 | Initial discovery is exact canonical-username lookup only. It trims/lowercases input, excludes self, incomplete profiles, and either-direction blocks, and returns at most one profile ID, username, and display name. | No directory, prefix, substring, fuzzy, recommendation, unrestricted profile read, email, Auth metadata, timestamp, or onboarding-state disclosure is permitted. |
| P-023 | Future friendships use one versioned current relationship state per unordered profile pair, separate from directional blocks. Duplicate sends are idempotent, crossed requests become friendship, senders can cancel, recipients can decline, requests do not initially expire, and the person declining/ending controls reopening. | Transitions are atomic and stale/retry-safe. Creating a block later cancels pending requests both ways and ends friendship, but this decision does not authorize friendship/request schema in the blocking/discovery slice. |

### Architecture and delivery

| ID | Decision | Consequence |
| --- | --- | --- |
| A-001 | Use Flutter stable for Android and iOS only. | Other platform folders and support are outside current scope. |
| A-002 | Android application ID/namespace and iOS bundle identifier are exactly `com.ferbatech.listandsplit`. | No `com.example` or identifier containing `list_and_split` may remain in platform configuration. |
| A-003 | Use Material 3 with architectural support for light and dark themes. | The root app owns both theme modes. |
| A-004 | Organize code feature-first with MVVM-style presentation. | Views stay declarative; feature state/intent belongs in view models/providers; avoid speculative layers. |
| A-005 | Use Riverpod for state management and dependency injection. | Dependencies and feature state are provided/tested through Riverpod rather than globals. |
| A-006 | Use `go_router` for navigation and future deep links. | Route state is centralized and should be testable. |
| A-007 | Repositories are the client data source of truth. SQLite caching is introduced later for offline-tolerant active-list use. | UI cannot depend directly on Supabase/SQLite; cache and sync stay behind repositories. |
| A-008 | Use Supabase Auth, PostgreSQL, RLS, Realtime, Storage, database functions, and Edge Functions as backend capabilities. | Concrete use is phased; listing a service does not require premature scaffolding. |
| A-009 | Git-committed database migrations are the schema source of truth. | Avoid Dashboard-only schema edits; schema review and reproducibility are mandatory. |
| A-010 | Every application table has RLS and least-privilege policies from its creating migration. | Authorization is enforced server-side and tested for allowed/denied identities. |
| A-011 | Client Supabase configuration is supplied through compile-time `dart-define` values; real values are not hardcoded. | Commit placeholders only, and never include a service-role/privileged key in Flutter. |
| A-012 | Use only current stable compatible package versions, not prerelease releases. | Dependency upgrades must preserve compatibility and pass verification. |
| A-013 | The app remains runnable without Supabase credentials and presents a clear development-configuration destination when required public values are unavailable. | Missing configuration is an explicit application state rather than a startup crash or a mocked authenticated experience. |
| A-014 | Backend work targets local development and only an explicitly authorized hosted development project; production Supabase and Firebase projects require separate authorization. | Environment creation and remote schema changes remain deliberate and reviewable. |
| A-015 | CI verifies dependency resolution, formatting, analysis, and unit/widget tests; relevant Supabase changes also run reproducible migration/database/RLS tests. | Local and CI verification use the same stable Flutter and database expectations. |
| A-016 | Work uses the task's authorized branch, conventional commits, and a draft pull request; no force-push or automatic merge. | Publishing remains reviewable and non-destructive. |
| A-017 | Public Supabase client configuration uses the compile-time names `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. The mobile Auth callback is `com.ferbatech.listandsplit://auth-callback`. | Only public/publishable client values enter Flutter. Android and iOS register the callback without changing application identifiers. |
| A-018 | Session routing is centralized in `go_router` and gates destinations in this order: backend configuration, authentication, email verification, then profile onboarding. Password-recovery callbacks enter the new-password flow. | Redirect logic is deterministic, repository-backed, and testable without a live backend. |
| A-019 | The initial profile is a one-to-one application record for an `auth.users` identity. A server-owned creation mechanism allows nullable onboarding fields; RLS and explicit Data API grants permit authenticated owner read and approved-field update only. | Anonymous and cross-user access, plus client insert/delete, are denied. Authorization does not rely on user-editable Auth metadata. |
| A-020 | Active directional blocks use a narrowly scoped application table with RLS and RPC-only client access. Exact discovery and outgoing-block management use minimal privileged projections derived exclusively from `auth.uid()`, without broadening owner-only profile SELECT. | Privileged functions pin an empty `search_path`, fully qualify objects, validate completed profiles, revoke default execution, grant only exact authenticated signatures, and return only approved fields. |

## Deferred but accepted direction

These items are part of the agreed direction but intentionally deferred:

- Local SQLite caching for offline-tolerant active-list usage.
- Supabase Realtime integration after repository reconciliation rules exist.
- FCM and APNs push delivery; Firebase project creation requires separate explicit
  authorization.
- Friend request/friendship schema after the accepted blocking/discovery slice;
  shared-resource block effects and reporting/moderation remain deferred.
- Production backend/environment creation under a separate explicit authorization.

## Open product decisions

| ID | Question |
| --- | --- |
| O-P01 | What are the active-list owner/admin/member roles and rules for inviting, removing, leaving, archiving, deleting, and transferring ownership? |
| O-P02 | What quantity precision, unit vocabulary, item ordering, duplicate, completion-audit, and concurrent-edit rules apply? |
| O-P03 | How are `@mentions` parsed, validated, edited, deduplicated, and rendered? |
| O-P04 | What support or administrator correction path, if any, exists for an immutable username, and what audit/authorization rules govern it? |
| O-P05 | How do blocking or friendship termination affect existing shared resources, including list membership and invitations? |
| O-P06 | Can templates be in multiple categories; what are ordering, default copied visibility/category, attribution, and provenance rules? |
| O-P07 | What defines “recent” and ranking/pagination/retention in the friends' public-template feed? |
| O-P08 | When do list invitations and sent-template offers expire or become revocable, and what should repeated acceptance return? |
| O-P09 | Which currencies are supported, can currency change after ledger use, and what amount ranges/zero rules apply? |
| O-P10 | How is an equal-split remainder allocated deterministically; may the payer be excluded; and how are exact shares validated? |
| O-P11 | What are expense correction/deletion, member-removal, settlement direction/reversal, and debt-simplification/display rules? |
| O-P12 | What are notification read/archive/retention/badge/preferences rules and what content is safe for push? |
| O-P13 | What are the reporting, moderation, evidence-retention, and appeal workflows? |
| O-P14 | Which operations work offline, how are conflicts presented, and what promise can the UI make while disconnected? |
| O-P15 | What are the account deletion/export, data-retention, re-registration, and related identity-lifecycle rules, and which additional locales ship first? |
| O-P16 | When does avatar editing ship, where are avatar objects stored, and what validation, privacy, replacement, and deletion lifecycle applies? |

## Open architecture and data decisions

| ID | Question |
| --- | --- |
| O-A01 | What exact feature folder depth, domain/use-case boundaries, and Riverpod code-generation conventions should be adopted as features arrive? |
| O-A02 | What final authenticated route topology, state-restoration behavior, and notification-link contract are required beyond the accepted Auth callback and gating order? |
| O-A03 | What development/staging/production flavor and environment-separation model should build on the accepted compile-time configuration names? |
| O-A04 | Which atomic operations belong in PostgreSQL functions versus Edge Functions? |
| O-A05 | What versioning/concurrency fields, idempotency keys, and transaction boundaries support list edits and template copies? |
| O-A06 | What realtime subscription scope, event ordering, reconnect/replay, and repository reconciliation rules apply? |
| O-A07 | Which SQLite package, cache schema, mutation queue, tombstone, retry, and conflict algorithm should be used? |
| O-A08 | What physical identifiers, audit timestamps, archival/soft-delete conventions, indexes, and enum/check-constraint strategy should later aggregates use beyond the accepted profile record? |
| O-A09 | What exact columns, states, indexes, transition versioning, and limited audit retention implement the accepted one-current-state-per-unordered-pair friendship model? |
| O-A10 | What is the mention-storage model and which layer owns parsing? |
| O-A11 | What server algorithm and stable output contract calculate balances and debts, and are derived results computed on demand or projected? |
| O-A12 | What notification payload, localization, retention, push-token, and delivery-attempt schema is needed? |
| O-A13 | Which Storage use cases exist and what object lifecycle/policies follow their parent records? |
| O-A14 | Which logging, analytics, crash reporting, privacy controls, and performance budgets are appropriate? |
| O-A15 | What extended automated environment will exercise Realtime, Storage, and later cross-service integration tests beyond the accepted local/CI migration, database-function, and RLS coverage? |

## Decision discipline

- Resolve the smallest decision set needed for the next vertical slice.
- Record decisions before or with implementation, especially when they affect
  authorization, money, copies, retention, or irreversible migrations.
- Prefer invariants enforced by database constraints and RLS over client-only
  assumptions.
- Treat schema migrations as forward-reviewed production artifacts even while
  operating only a development project.
- Do not close an open decision merely because one implementation happens to be
  convenient.
