# Conceptual data model

## Status and authority

This document describes the conceptual model and accepted invariants. It does not,
by itself, define final SQL names, columns, enums, indexes, or API contracts;
Git-committed migrations are the physical schema source of truth. The initial
profile contract below is sufficiently resolved for its reviewed migration. Later
aggregates remain conceptual until their open decisions are accepted.

The names below are illustrative so relationships and invariants can be discussed
without prematurely freezing the physical schema.

## Global modeling rules

- Supabase Auth owns authentication identities. Application profile data relates
  one-to-one to an authenticated user without duplicating email or credentials.
- Every application record has a stable identifier. Audit timestamps and soft
  delete/archive behavior are still to be decided per aggregate.
- Client-provided identity and authorization fields are untrusted. Ownership,
  membership, and recipient relationships are validated on the server.
- All monetary values are integer minor units. No SQL floating-point, Dart
  `double`, or floating JSON number is authoritative for money.
- Copies and snapshots receive new identifiers and independent ownership. A
  provenance reference, if retained, is informational and must not create live
  coupling to the source.
- Action acceptance and multi-record copies should be atomic and idempotent.

## Conceptual relationship map

```text
Auth User --1:1-- Profile
Profile --blocks (directional)--> Profile
Profile --< versioned Relationship state >-- Profile

Profile --creates--> Active List --< List Member >-- Profile
Active List --< List Item --< Item Assignment >-- List Member
Active List --< Expense --1 payer / many participant shares--> List Member
Active List --< Settlement --from/to--> List Member

Profile --owns--> Template --< Template Group --< Template Item
Profile --owns--> Personal Category --< category placement >-- Template

Profile --receives--> Notification
Profile --receives--> List Invitation / Sent Template / Friend Request
```

## Identity and social graph

### Profile

A profile represents a user in product surfaces and supports lookup through a
unique username. The initial physical record is `public.profiles`; its `id` is a
primary key and foreign key to `auth.users(id)`. The foreign key prevents orphaned
profile records, but automatic deletion is intentionally not encoded while the
account lifecycle remains open. Who may delete an account, export obligations,
retention, profile cleanup, and re-registration behavior require a later accepted
decision.

A server-owned creation mechanism creates one profile for each Auth identity.
`username` and `display_name` may remain null until a verified user completes
onboarding. Database-managed `created_at` and `updated_at` timestamps provide audit
timing, and nullable `onboarding_completed_at` is set when both onboarding fields
are valid. Clients cannot edit these timestamps.

Accepted field invariants are:

- Username input is trimmed and converted to lowercase before validation.
- A canonical username matches `^[a-z][a-z0-9_]{2,23}$` and is globally unique.
- Username can be set during onboarding and cannot change after onboarding. The
  database enforces this for direct API calls as well as application flows.
- Retrying the same canonical onboarding write is safe and does not count as a
  username change.
- Display name is trimmed, 1-50 characters, non-unique, and remains editable.
- Email remains private in Supabase Auth and is never copied into the profile.
- Anonymous users cannot read profiles. In the initial slice an authenticated
  user can read only their own profile and update only approved fields; clients
  cannot insert or delete profile records.

Cross-user identity is disclosed only through narrow block-aware contracts. Exact
canonical-username discovery returns at most one fully onboarded profile and only
its ID, username, and display name. It excludes the caller and any pair with a
block in either direction. A future support/administrator correction path for
immutable usernames, avatar storage/lifecycle, and account deletion/export remain
open decisions.

### Active directional block

An active block records one profile (`blocker`) silently blocking another
(`blocked`). The physical model uses one active row per ordered pair and prohibits
self-blocking. Reciprocal rows are valid because each user acts independently.
The creation time is database-managed; no unlimited block event/history record is
introduced.

Any active row in either direction creates symmetric separation for exact
discovery, future friend requests and contact, and future public profile/template/
feed visibility. Only the blocker can privately list or remove their outgoing
row. Blocking and unblocking are idempotent. Removing A's A-to-B row does not
remove B's B-to-A row, restore a relationship, or make discovery available while
the reciprocal row remains.

The blocker may receive the target's ID, username, and display name through the
private outgoing-block management projection. Incoming-only and unrelated blocks
are never disclosed. Account deletion/retention and shared-resource effects remain
open, so the block model does not select cascading profile deletion or active-list
membership behavior.

### Friend request

A friend request is directional: one authenticated user requests friendship with
another. It supports at least pending, accepted, and declined outcomes because the
recipient must explicitly Accept or Decline.

Accepted lifecycle invariants for the future implementation:

- A user cannot request themselves.
- Duplicate request sends are idempotent.
- Crossed pending requests atomically become a friendship.
- The sender may cancel; only the recipient may decline.
- Requests do not automatically expire in the initial design.
- Acceptance creates the mutual friendship atomically and idempotently.
- A block in either direction prevents request creation. Creating a block later
  atomically cancels pending requests in both directions and ends the friendship.
- The person who declines or ends a friendship controls reopening by initiating
  the next request.
- All transitions are versioned, atomic, and safe under stale or duplicate input.

### Friendship

A friendship is an unordered, mutual relationship between two profiles. Neither
side is a follower. Each unordered pair will have one versioned current
relationship state rather than contradictory independent states or an unlimited
event log. Active directional blocks remain separate from this state. Ending a
friendship and the effects of relationship/block changes on existing shared lists
remain unresolved.

## Active-list aggregate

### Active list and membership

An active list is created by a user and has members. The conceptual record holds
its identity, display attributes, general note, Payment Control enabled state, and
one currency when Payment Control is enabled. A membership associates a profile
with the list.

The creator/owner role is conceptually required to attribute creation, but the full
role model and administrative permissions are open. Only accepted friends may be
invited; existing membership and friendship are distinct relationships so a later
friendship change does not silently rewrite historical list data.

### List invitation

A list invitation links an inviting authorized member, an active list, and an
accepted friend as recipient. It has an actionable state with at least pending,
accepted, and declined outcomes. Acceptance creates membership once and must be
atomic/idempotent. Expiry, revocation, who may invite, and reinvitation rules remain
open.

### List item and assignment

A list item belongs to exactly one active list and conceptually includes item text,
quantity, optional unit, completion state, and ordering information. An assignment
join permits zero, one, or multiple list members to be assigned to the same item.
The data layer must reject assignments to non-members.

Quantity representation, units, ordering, completion attribution/timestamps, and
delete versus archive behavior are unresolved.

### General note and mentions

An active list has one general note. Mentions connect relevant ranges or parsed
tokens to list members so notification delivery is not based solely on
unvalidated client text. The storage and parsing model, editing behavior, and
deduplication rules remain open.

## Template aggregate and copy semantics

### Template, group, and item

A template is owned by one profile, has private or public visibility, and contains
ordered groups of reusable items. Groups contain ordered template items. Exact
item fields should align with importable list-item content without sharing live
records.

### Personal categories

A personal category is owned by one profile and organizes that user's templates.
Whether a template can appear in one or many categories, and how uncategorized or
copied templates are handled, is not yet decided. Categories are personal metadata
and must not alter another user's source template.

### Snapshot into an active list

Adding a template to an active list reads a consistent template version and creates
new active-list item records. The operation must follow these rules:

- Imported items and any imported grouping metadata are copied by value and get
  new identifiers.
- Future template edits, visibility changes, or deletion cannot mutate or delete
  imported active-list items.
- The target list's authorization rules are validated server-side.
- The snapshot is atomic: a retry cannot create an accidental partial or duplicate
  import.
- Optional provenance may identify the source/version for display or diagnostics,
  but it is never a foreign-key dependency that grants access or drives updates.

### Saving or receiving a template

Saving a public template or accepting a template sent by a friend creates a deep,
independent copy of the template, its groups, and its items, owned by the recipient.
The source owner can no longer affect that copy. The copied template's default
visibility, category placement, attribution display, and behavior if the source is
removed are open decisions.

A sent-template action should reference the offered source/version while pending;
acceptance creates the independent copy exactly once. A notification may point to
the action but should not be the authoritative action-state record.

## Payment Control aggregate

Payment Control exists only for an active list where it is enabled. It is a ledger,
not a payment rail.

### Currency and integer representation

- A list has one currency for its ledger.
- Expense totals, exact shares, settlements, balances, and debts use integer minor
  units (`amount_minor` conceptually).
- Currency code validation and the minor-unit exponent source must be consistent on
  client and server. Supported currencies and zero-/three-decimal behavior remain
  open.
- Changing a list currency after ledger activity must not reinterpret existing
  integers; whether it is prohibited or handled through a separate workflow is an
  open decision.

Use a sufficiently wide integer type and explicit range validation. Never infer an
amount by multiplying a floating-point value.

### Expense, payer, participants, and shares

An expense belongs to one enabled active list, has one payer who is a list member,
an integer total, and one or more selected participating members. A participant
share records each participant's integer obligation.

Expected invariants:

- Payer and participants are active list members at the time required by the final
  lifecycle rules.
- Exact custom shares sum exactly to the expense total.
- Equal splitting produces integer shares whose sum is exactly the total; the
  deterministic remainder allocation rule is not yet chosen.
- Negative/zero amount rules, payer participation, expense editing, member removal,
  and correction/audit behavior require explicit decisions.

### Settlement

A settlement records an integer amount transferred conceptually from one list
member to another within the ledger. It records a debt adjustment, not proof that
List & Split processed money. Sender/recipient terminology, direction, reversal,
attachments, and validation against current debt are open decisions.

### Balances and debts

Balances and pairwise/simplified debts are derived server-side from authoritative
expenses, shares, and settlements. They are not client-authored source records.
Any cached projection must be reproducible from the ledger and transactionally
consistent enough for the selected design.

The calculation implementation requires unit tests for integer conservation,
rounding/remainders, exact shares, settlements, zero balances, multiple payers,
deterministic output, invalid inputs, and relevant lifecycle corrections.

## Notifications and actions

### Persistent notification

A notification belongs to one recipient and conceptually stores its type, safe
display/reference data, creation time, and read state. Notification types include:

- actionable friend request;
- actionable active-list invitation;
- actionable sent template;
- informational item assignment; and
- informational note mention.

Action state belongs to the underlying request/invitation/send record; a
notification references it. Accept/Decline must remain safe under duplicate taps,
retries, and a stale notification. Retention, archive/delete behavior, badge
semantics, and payload localization are open.

Push tokens and delivery attempts are future infrastructure for FCM/APNs and are
outside the initial identity/profile schema. Device token ownership, rotation,
invalidation, and privacy rules must be designed before push implementation.

## Future safety records

Directional blocking and exact block-aware username discovery precede friend
requests in Phase 1. Reporting remains required before public content is
considered mature. Reporting records, moderation roles, evidence retention,
appeals, and block effects on existing shared resources are intentionally not
designed here.

## Row Level Security expectations

Every future application table must enable RLS in its creating migration. Policy
tests must cover authenticated allowed cases, authenticated cross-user denial, and
anonymous denial unless public read is explicitly intended.

| Data area | Minimum expected access boundary |
| --- | --- |
| Profiles | Direct access remains authenticated owner-only select and approved-field update; exact cross-user discovery uses only the approved block-aware minimal projection |
| Active blocks | RPC-only application access; the caller can create/remove/list only outgoing blocks, while incoming and unrelated rows remain private |
| Friend requests | Requester and recipient only; only recipient changes Accept/Decline state |
| Friendships | The two members only, except deliberately exposed public relationship data if later approved |
| Active lists and memberships | Current authorized members; invitees see only invitation-safe list data |
| Items, assignments, notes, mentions | Authorized list members, with mutations limited by the final role model |
| Invitations | Recipient and authorized inviters/list administrators |
| Private templates/categories | Owner only |
| Public templates | Readable according to approved public-profile policy; mutation remains owner-only |
| Template sends | Sender and recipient; acceptance only by recipient |
| Expenses, shares, settlements, balances | Authorized members of the enabled active list, subject to final ledger roles |
| Notifications | Recipient only; related actors do not gain notification-row access |
| Storage objects | Same ownership/membership rules as the parent application record |
| Future reports | Strictly limited to the reporter and authorized moderation paths |

Policies must derive identity from `auth.uid()` and server-owned relationships, not
from a user ID supplied by the Flutter client. Privileged functions require
explicit grants, protected search paths, and adversarial policy/function tests.

## Physical-model decisions still required

- Identifier types, timestamp/audit conventions, soft delete, and archival for
  later aggregates beyond the accepted profile record.
- Support/administrator correction and audit rules for immutable usernames.
- Avatar Storage, validation, replacement, retention, and deletion lifecycle.
- Exact relationship-state values, version-transition storage, and any limited
  relationship audit retention beyond the accepted one-current-state model.
- Block effects on existing shared resources and later account deletion/retention.
- List role model and membership lifecycle.
- Quantity/unit types and ordering strategy.
- Mention representation and parser ownership.
- Template category cardinality, version/provenance representation, and copy
  idempotency keys.
- Currency catalog, amount ranges, expense/settlement lifecycle, remainder and debt
  algorithms.
- Notification payload schema, retention, localization, and push token tables.
- Optimistic concurrency/version fields, realtime publication, offline mutation
  identifiers, tombstones, and conflict resolution.
- Reporting schema and moderation authorization.
