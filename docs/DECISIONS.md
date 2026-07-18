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
| P-002 | The application combines active/shared lists, templates, community, optional Payment Control, and notifications. | These are product areas, not claims of bootstrap implementation. |
| P-003 | The former term **Internal Lists** is replaced by **Templates**. | New UI, code, and documentation use “Templates.” |
| P-004 | Active-list members can add, edit, complete, and delete items with quantities, optional units, and multiple assignees. Lists also have a general note with `@mentions`. | Item/member/note authorization and notification behavior require explicit models. |
| P-005 | Only accepted friends can be invited to an active/shared list. | Friendship is a server-validated prerequisite for invitation creation. |
| P-006 | Templates contain reusable groups/items, can be private or public, and are organized by owners into personal categories. | Visibility and personal organization are separate concerns. |
| P-007 | Importing a template into an active list is a snapshot copy. Saving a public template or accepting a sent template creates an independent recipient-owned deep copy. | Source changes or deletion never mutate existing imports/copies. New identifiers and atomic/idempotent copy operations are required. |
| P-008 | Community relationships are mutual friendships, not followers. Users are searchable by unique username and can send, accept, or decline friend requests. | Friendship has symmetric meaning even though requests are directional. |
| P-009 | Public templates appear on profiles, and the community feed shows recent public templates from friends. | Private templates are excluded; feed ranking details remain open. |
| P-010 | Public content must eventually support blocking and reporting. | Community maturity depends on a future safety/moderation design. |
| P-011 | Payment Control is available only when enabled inside an active list and is an expense ledger, not payment processing. Each enabled list has one currency. | No wallet/payment-provider integration; ledger access follows list membership. |
| P-012 | An expense has one payer and selected participants, with equal or exact custom splits. Settlements can be recorded between members. | Participant/share and settlement records require strict server validation. |
| P-013 | Money is represented only in integer minor units; authoritative balance and debt calculations run server-side and have unit tests. | Floating-point monetary values are prohibited at every boundary. |
| P-014 | The in-app notification centre is persistent. Friend requests, list invitations, and sent templates require Accept/Decline; assignments and mentions notify recipients. | Action state must survive sessions and be safe under retry/stale UI. |
| P-015 | The primary destinations are Lists, Templates, Community, and Profile. Notifications open from a bell, not a fifth tab. | The root navigation shell has exactly four primary destinations. |
| P-016 | English is the initial UI language, but the application remains localization-ready. | User-facing strings and layout must not assume English is permanent. |

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
| A-011 | Client Supabase configuration will be supplied through compile-time environment values such as `dart-define`; real values are not hardcoded. | Commit placeholders only, and never include a service-role/privileged key in Flutter. |
| A-012 | Use only current stable compatible package versions, not prerelease releases. | Dependency upgrades must preserve compatibility and pass verification. |
| A-013 | The bootstrap app remains runnable without Supabase credentials and does not implement product features. | Initial UI is a branded foundation shell, not mocked completed functionality. |
| A-014 | Bootstrap creates no business tables/migrations, production Supabase project, or Firebase project. | Only local Supabase tooling and the separately authorized development project are in initial scope. |
| A-015 | CI verifies dependency resolution, formatting, analysis, and unit/widget tests on relevant pushes and pull requests. | Local and CI verification use the same stable Flutter expectations. |
| A-016 | Work uses a task branch, conventional commits, and a draft pull request; no force-push or automatic merge. The bootstrap branch is `chore/bootstrap-foundation`. | Publishing remains reviewable and non-destructive. |

## Deferred but accepted direction

These items are part of the agreed direction but intentionally deferred:

- Local SQLite caching for offline-tolerant active-list usage.
- Supabase Realtime integration after repository reconciliation rules exist.
- FCM and APNs push delivery; no Firebase project during bootstrap.
- Blocking and reporting for public/community content.
- Production backend/environment creation under a separate explicit authorization.

## Open product decisions

| ID | Question |
| --- | --- |
| O-P01 | What are the active-list owner/admin/member roles and rules for inviting, removing, leaving, archiving, deleting, and transferring ownership? |
| O-P02 | What quantity precision, unit vocabulary, item ordering, duplicate, completion-audit, and concurrent-edit rules apply? |
| O-P03 | How are `@mentions` parsed, validated, edited, deduplicated, and rendered? |
| O-P04 | How are usernames normalized/cased, how often may they change, and which profile fields are discoverable? |
| O-P05 | How do crossed/duplicate requests, cancellation, expiry, re-request, unfriending, and blocking affect friendships? |
| O-P06 | Can templates be in multiple categories; what are ordering, default copied visibility/category, attribution, and provenance rules? |
| O-P07 | What defines “recent” and ranking/pagination/retention in the friends' public-template feed? |
| O-P08 | When do list invitations and sent-template offers expire or become revocable, and what should repeated acceptance return? |
| O-P09 | Which currencies are supported, can currency change after ledger use, and what amount ranges/zero rules apply? |
| O-P10 | How is an equal-split remainder allocated deterministically; may the payer be excluded; and how are exact shares validated? |
| O-P11 | What are expense correction/deletion, member-removal, settlement direction/reversal, and debt-simplification/display rules? |
| O-P12 | What are notification read/archive/retention/badge/preferences rules and what content is safe for push? |
| O-P13 | What precisely does blocking hide or revoke, and what are reporting, moderation, evidence, retention, and appeal workflows? |
| O-P14 | Which operations work offline, how are conflicts presented, and what promise can the UI make while disconnected? |
| O-P15 | Which authentication methods, account deletion/export rules, and additional locales ship first? |

## Open architecture and data decisions

| ID | Question |
| --- | --- |
| O-A01 | What exact feature folder depth, domain/use-case boundaries, and Riverpod code-generation conventions should be adopted as features arrive? |
| O-A02 | What route topology, auth redirects, deep-link formats, restoration behavior, and notification-link contract are required? |
| O-A03 | What development/staging/production flavor model and compile-time configuration names should be standardized? |
| O-A04 | Which atomic operations belong in PostgreSQL functions versus Edge Functions? |
| O-A05 | What versioning/concurrency fields, idempotency keys, and transaction boundaries support list edits and template copies? |
| O-A06 | What realtime subscription scope, event ordering, reconnect/replay, and repository reconciliation rules apply? |
| O-A07 | Which SQLite package, cache schema, mutation queue, tombstone, retry, and conflict algorithm should be used? |
| O-A08 | What physical identifiers, audit timestamps, archival/soft-delete conventions, indexes, and enum/check-constraint strategy should migrations use? |
| O-A09 | What is the physical friendship uniqueness/history model and how is block state enforced across RLS policies? |
| O-A10 | What is the mention-storage model and which layer owns parsing? |
| O-A11 | What server algorithm and stable output contract calculate balances and debts, and are derived results computed on demand or projected? |
| O-A12 | What notification payload, localization, retention, push-token, and delivery-attempt schema is needed? |
| O-A13 | Which Storage use cases exist and what object lifecycle/policies follow their parent records? |
| O-A14 | Which logging, analytics, crash reporting, privacy controls, and performance budgets are appropriate? |
| O-A15 | What automated environment will exercise migration, database-function, Realtime, Storage, and RLS integration tests? |

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
