# Conceptual data model

## Status and authority

This document describes the conceptual model and accepted invariants.
Git-committed migrations remain the physical schema source of truth. The profile
and versioned-relationship sections below record sufficiently resolved physical
contracts for their reviewed migrations; names in later sections remain
illustrative until their open decisions are accepted.

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

Profile --owns--> Active List --< List Item
Active List --< retained participant access >-- Profile

Future: List Item --< Item Assignment >-- List Member
Active List --< Expense --1 payer / many participant shares--> List Member
Active List --< Settlement --from/to--> List Member

Profile --owns--> Template --< Template Group --< Template Item
Profile --owns--> Personal Category --< category placement >-- Template

Profile --receives--> Notification
Profile --receives--> List Invitation / Sent Template
Profile --authorizes--> private account Broadcast topic (transport only)
```

## Identity and social graph

### Profile

A profile represents a user in product surfaces and supports lookup through a
unique username. The initial physical record is `public.profiles`; its `id` is a
primary key and foreign key to `auth.users(id)`. The foreign key prevents orphaned
profiles and cascades only when the Auth identity is hard-deleted through the
reviewed account-deletion boundary.

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
immutable usernames and avatar storage/lifecycle remain separate open concerns.
Export is governed by the non-persistent contract below.

### Versioned account export document

The account export is a transient document, not a table or retained server record.
Schema version `1` introduced these root sections:

- `product`, `schema_version`, and server-generated `exported_at`;
- `auth_identity`, containing only the caller's ID, email, confirmation time,
  creation time, update time, and nullable last-sign-in time;
- `profile`, containing ID, nullable username/display name, creation/update times,
  and nullable onboarding-completion time;
- deterministic `outgoing_blocks`, `active_relationships`, and
  `visible_notifications` arrays.

Schema version `2` preserves those roots and adds exactly one `active_lists` array.
It includes both active and archived lists owned by the caller. Each list contains
an ordered `items` array. Explicit allowlists expose list/item IDs, title/name,
status, versions, exact `quantity_thousandths`, nullable stable unit code, integer
position, completion attribution/time, and approved timestamps; request
idempotency keys and locking/authorization internals remain private.

Every nested object is built from an explicit field allowlist. The social arrays
apply the same directional-block, caller-relative active-relationship, recipient,
suppression, expiry, and either-direction block filters as their existing RPC
projections. Arrays are never null. Raw table rows, Auth metadata, credentials,
tokens, sessions, incoming blocks, dormant relationship internals, hidden actors,
and future aggregate data are outside the contract. Later schema versions must add
future template/shared-membership/ledger sections deliberately and compatibly.

### Permanent deletion and username reservation

Immediate hard deletion of `auth.users` is the account aggregate's atomic root.
The profile foreign key cascades from Auth; both block participant references,
both normalized relationship participant references, notification recipient and
actor references, and the notification relationship reference cascade from the
profile/relationship rows they protect. Owned-list and list-item foreign keys add
the list aggregate to that same cascade. This removes every currently implemented
application record involving the deleted account in the same root transaction,
while unrelated rows remain unchanged.

Before a completed profile disappears, a trigger upserts
`private.deleted_username_reservations` with exactly two fields:

- `canonical_username text` as the primary key; and
- `reserved_until timestamptz`, exactly 30 days after profile deletion.

No email, Auth user ID, profile ID, display name, timestamps beyond expiry, or
copied profile data is retained. Incomplete profiles create no reservation. The
profile write boundary locks a conflicting active canonical username before
checking the private reservation, preventing concurrent deletion/onboarding from
bypassing the hold. An active reservation rejects onboarding with the existing
username-unavailable contract; an expired reservation permits reuse even before
the once-daily 03:17 UTC `pg_cron` cleanup physically deletes it. A repeated later
reservation for the same username keeps the later expiry.

The private table is owned by `postgres`, has RLS enabled as defense in depth, and
has no access for `PUBLIC`, `anon`, `authenticated`, or `service_role`. Its trigger,
availability, and cleanup functions use empty `search_path`, fully qualified
objects, revoked default execution, and no client grants.

The authenticated validation RPC accepts only exact confirmation text, derives
the caller from `auth.uid()` and the session from `auth.jwt()` `session_id`, and
returns only `true`. It requires one confirmed Auth user, one profile, and that
exact user's `auth.sessions` row with an actual creation time no older than ten
minutes. Completed profiles compare the canonical username; incomplete profiles
compare Auth email. It never mutates or deletes. Re-registration after deletion
creates a new UUID and restores nothing.

### Active directional block

An active block records one profile (`blocker`) silently blocking another
(`blocked`). The physical model uses one active row per ordered pair and prohibits
self-blocking. Reciprocal rows are valid because each user acts independently.
The creation time is database-managed; no unlimited block event/history record is
introduced.

Any active row in either direction creates symmetric separation for exact
discovery, friend requests and contact, and future public profile/template/
feed visibility. Only the blocker can privately list or remove their outgoing
row. Blocking and unblocking are idempotent. Removing A's A-to-B row does not
remove B's B-to-A row, restore a relationship, or make discovery available while
the reciprocal row remains.

The blocker may receive the target's ID, username, display name, and block creation
time through their account export; interactive outgoing-block management retains
its existing narrower projection. Incoming-only and unrelated blocks are never
disclosed. An active block in either direction makes the separate
relationship-summary RPC return no row and no target profile fields. Accepted
shared-list and ownership-transfer effects remain authoritative. Both block
foreign keys cascade only through the reviewed account-deletion root;
shared-list block effects follow the accepted participant-lifecycle contract.

### Versioned friend request and friendship relationship

A friend request is directional while friendship is unordered and mutual. Both
concepts share one persistent current row per unordered pair; there are no separate
request and friendship tables and no detailed relationship event log.

The accepted physical record contains:

- `profile_low_id` and `profile_high_id`, both references to `public.profiles`
  that cascade only through account deletion, as a composite primary key; fully
  onboarded participation is an RPC precondition rather than a foreign-key
  property;
- a named ordering constraint requiring `profile_low_id < profile_high_id`;
- check-constrained text `state` with exactly `pending`, `friends`, `cancelled`,
  `declined`, and `ended`;
- `requester_id`, constrained to one of the two participants and retaining the
  most recent requester after transition for authorization and idempotency;
- nullable `reopen_by_id`, constrained to a participant, required exactly for
  declined and ended states, and null for every other state;
- a positive `bigint` version starting at one;
- database-managed `created_at`; and
- database-managed `state_changed_at`.

The low/high normalization makes pair identity deterministic. The primary-key
order supports low-participant lookup; a justified reverse-participant index
supports listing rows where the caller is `profile_high_id`. Requester and
reopening-controller values need no redundant foreign keys because their named
constraints prove that they equal a participant. Their participant foreign keys
cascade only through the reviewed account-deletion root.

Accepted transition invariants are:

- No row becomes pending with the caller as requester.
- A duplicate send by the same pending requester is unchanged.
- A send by the opposite participant while pending atomically becomes friends.
- Only the pending recipient accepts or declines; only the requester cancels.
- Either current friend may end the friendship.
- Cancelled rows may be reopened by either participant. Declined and ended rows
  may be reopened only by their recorded reopening controller.
- Blocking a pending pair changes the state to cancelled; blocking friends changes
  it to ended with the blocker as reopening controller. Blocking a dormant pair
  creates no misleading relationship transition, and unblocking never restores a
  request or friendship.
- A block in either direction rejects sends and other active transitions. Block
  creation and its relationship transition are one protected atomic operation.
- Every real transition increments the version exactly once and updates
  `state_changed_at`. Duplicate no-ops change neither value.
- Mutations after initial send require the caller's expected version. Send accepts
  a nullable expected version: null is valid only for first, duplicate-pending, or
  crossed-pending sends, while reopening a cancelled, declined, or ended row
  requires its exact current version. Once a send reopens a dormant row to pending,
  a duplicate retry or opposite crossed send may use that immediately prior dormant
  version as well as the current pending version; older values remain stale. Stale
  or ineligible actions fail safely without overwriting a newer state.
- All operations normalize and lock the same pair in one deterministic order so
  concurrent first sends, crossed sends, blocks, and transitions cannot produce
  duplicate or contradictory rows.

The table is RPC-only: RLS is enabled; table privileges are revoked from `PUBLIC`,
`anon`, `authenticated`, and `service_role`; and one restrictive `FOR ALL` policy
targets `anon` and `authenticated` with `USING (false)` and `WITH CHECK (false)`.
Narrow authenticated functions return caller-relative results rather than physical
rows.
A caller may receive only the other participant's profile ID, username, display
name, one of `can-send`, `incoming-pending`, `outgoing-pending`, `friends`, or
`unavailable`, and nullable version/state-change values where an eligible action
or active-list ordering requires them. Privacy-safe `unavailable` results expose
neither version nor state-change metadata; an eligible dormant reopener receives
the version required for the next send. `unavailable` applies to dormant
declined/ended reopening privacy; an active either-direction block suppresses the
entire summary/profile row.
Raw declined/ended state and `reopen_by_id` are not disclosed to the other
participant; email/Auth metadata, incoming block identity, unrelated rows, and
unnecessary internal timestamps are never returned.

Requests do not expire in the initial design. A persistent notification may
reference the exact pending relationship version but never becomes authoritative
for its transition. Realtime invalidation, push delivery, public profiles, the
navigation shell, shared lists, and detailed audit history remain outside the
relationship record itself. Current relationship-row account deletion cleanup is implemented by the
Auth-root cascade. Accepted shared-list access and the effects of friendship/block
changes follow P-035 through P-039.

## Active-list aggregate

### Implemented active/shared list

`public.active_lists` has a UUID primary key, one non-null `owner_id` referencing
`public.profiles(id) ON DELETE CASCADE`, a trimmed 1-80-character title, checked
`active`/`archived` status, positive monotonic `bigint` version, a caller-generated
creation request UUID used only for idempotency, and database-owned creation,
update, and nullable archive timestamps. Status and archive time are constrained
to agree. `(owner_id, creation_request_id)` is unique; duplicate titles remain
valid.

The owner can create, read, rename, archive, restore, permanently delete, and manage
access. Accepted members can read the list and mutate items only while active.
Archived rows remain readable; only owner restore/removal and member leave remain
valid transitions. Active listing orders by `(updated_at, id)` descending;
archived listing orders by `(archived_at, id)` descending. Both use a bounded
exclusive keyset cursor and aggregate item total/completed counts in the same
projection.

Membership and friendship are distinct. Ending friendship cancels pending list
invitations but preserves accepted membership; blocking applies the accepted
symmetric separation rules.

Only the current owner may transfer an active list to one exact accepted member.
`active_lists.owner_id` remains the sole ownership authority. The transaction
advances the list version once, preserves every item/content field, and swaps the
two profiles' retained access roles without changing capacity.

### Implemented participant access row

`public.active_list_participants` retains one current row per `(list_id,
participant_profile_id)` access lineage. Its exact states are `pending`, `member`,
`declined`, `cancelled`, `removed`, `left`, and the internal transfer-only `owner`;
version is a positive monotonic
`bigint`; creation and state-change times are database-owned. A constraint/trigger
prevents a committed owner duplicate with any state other than `owner`, and an
`owner` row may match only the authoritative list owner. Legacy/original owners
need no row until their first transfer. Dormant rows may reopen to a new pending
version.

Only the owner invites, cancels, and removes. Only the recipient accepts/declines,
and only a member leaves. Capacity counts the owner plus `pending`/`member` rows and
is limited to 20 under serialized list locking. Pending invitations do not expire.
The table is RPC-only with enabled/forced RLS, an explicit restrictive rejection
policy, and no direct API-role grants. Auth-root owner deletion cascades the list;
non-owner deletion removes only that person's access row.

During a transfer, the target's existing `member` row becomes `owner` at the next
version instead of being deleted. The former owner's existing `owner` row becomes
`member` at the next version, or a first retained `member` row starts at version
one. This prevents participant-state ABA/version reuse and preserves notification
foreign keys across repeated transfers. Exact expected list and target-access
versions reject stale attempts; pair-before-list locking serializes concurrent
block and transfer actions.

### Implemented list item

`public.active_list_items` has a UUID primary key, non-null `list_id` referencing
the list `ON DELETE CASCADE`, trimmed 1-120-character name, positive integer
`quantity_thousandths` from `1` through `999999999` (default `1000`), nullable
checked unit code, positive deterministic integer `position`, positive monotonic
`bigint` version, a creation request UUID, nullable completion time and actor, and
database-owned creation/update times. `(list_id, creation_request_id)` and
`(list_id, position)` are unique; duplicate names remain valid.

Unit is null or exactly `piece`, `kg`, `g`, `l`, `ml`, `pack`, `box`, `bottle`,
`can`, or `bag`. Flutter parses at most three decimal places directly into integer
thousandths and formats without insignificant zeros; no authoritative boundary
uses binary floating point. Initial position follows committed creation order.
Reorder validates an exact unique current item-ID set, locks consistently, and
writes contiguous positive positions atomically. Completion records server time
and the authenticated owner; reopen clears both. The nullable actor reference uses
`ON DELETE SET NULL`, allowing a retained completion time without deleting the
item if a future actor identity disappears.

List rename/archive/restore increments list version only. Item create/delete/
reorder increments list version. Item edit/complete/reopen increments both list and
item version. Real state changes update the corresponding server timestamps once;
idempotent no-op retries update neither. Expected versions prevent stale overwrite
with a stable `40001` conflict. Creation request UUIDs are checked against their
payload for retry safety and never grant ownership.

No assignment or item-event table exists yet. Multi-member assignment and its
authorization/audit rules remain open with the collaborative-list phase.

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

A notification belongs to one recipient. The accepted initial physical record is
`public.user_notifications` and contains:

- a database-generated UUID primary key;
- recipient and actor profile references that cascade through account deletion;
- a check-constrained type, initially only `friend_request`;
- normalized low/high relationship participant IDs and a composite relationship
  reference that cascades when account deletion removes the relationship;
- the positive relationship version that caused the notification;
- database-managed creation time and expiry exactly 180 days later;
- nullable database-managed read time; and
- nullable permanent suppression time.

Named constraints require actor and recipient to differ, prove they are exactly
the normalized relationship participants, require valid pair ordering and a
positive version, preserve exact expiry, and prevent read/suppression timestamps
from preceding creation. A unique recipient/type/pair/version constraint prevents
duplicate creation. The row stores no username, display name, email, Auth metadata,
arbitrary message, or independent action state.

Every real transition into a new pending relationship version creates one
notification for that recipient. A same-requester retry, crossed send into
friendship, or historical relationship row creates none. A valid dormant reopening
creates one for its new pending version.

The RPC-only boundary lists the current recipient's visible rows newest first by
deterministic `(created_at, id)` keyset, returns a matching unread count, and marks
a bounded set of caller-owned displayed IDs read. Listing resolves only the actor's
ID, username, and display name and projects `actionable`, `friends`, or generic
`unavailable` from the current relationship. Only the exact matching pending
version with the actor as requester and recipient as caller is actionable.

Expired rows and permanently suppressed rows are excluded from listing and badge
counts. Creating a block suppresses every existing pair notification in the same
transaction, regardless of recipient direction; unblocking does not restore them.
No scheduled or physical cleanup is introduced in this slice.

Accepted informational notification types also include ownership transfer. The
new owner is the recipient, the former owner is the actor, and the reference uses
the former owner's resulting retained member-access version. No copied profile or
list text is stored.

Accepted future notification types remain:

- actionable sent template;
- informational item assignment; and
- informational note mention.

Invitation and sent-template action state will belong to their underlying records,
as friend-request action state belongs to the relationship. Archive/delete and
preference controls, future-type payload localization, physical cleanup, and
retention beyond the implemented current-aggregate account deletion remain open.

Push tokens and delivery attempts are future infrastructure for FCM/APNs and are
outside the initial identity/profile schema. Device token ownership, rotation,
invalidation, and privacy rules must be designed before push implementation.

## Future safety records

Directional blocking and exact block-aware username discovery preceded friend
requests in Phase 1. Reporting remains required before public content is
considered mature. Reporting records, moderation roles, evidence retention,
appeals, and public-content safety behavior are intentionally not designed here.

## Realtime invalidation transport

Realtime adds no application entity, history, outbox, queue, or authorization
record. Each completed authenticated profile may join only the private topic
`account:<auth.uid()>` for Broadcast receive. The sole application event is
`invalidate` with payload exactly `{"v":1}`. Supabase transport metadata is not
application data, and no list, item, profile, notification, relationship, block,
operation, version, or timestamp enters the application payload.

Hardened database triggers derive affected profile IDs from authoritative rows
and call private `realtime.send` inside the successful mutation transaction. List
changes reach the owner plus current accepted/pending projections as applicable;
item changes fan out through their required parent-list version update;
participant changes reach the owner, affected participant, and accepted peers
when their visible member projection changes; notifications reach only their
recipient; relationship/block changes reach both accounts. Profile deletion
captures surviving list recipients before cascades remove their IDs.
Ownership transfer changes both visible authority/access projections and creates
the new-owner notification in the same transaction, so the existing list,
participant, and notification triggers invalidate both affected accounts without
changing the wire contract.

The one `realtime.messages` receive policy compares the requested channel topic
with `auth.uid()` and restricts the extension to `broadcast`. There is no client
send or Presence policy and no application table in `supabase_realtime`.
Messages are ephemeral invalidations; current RPC projections, access-row versions,
and persistent notifications remain authoritative.

## Row Level Security expectations

Every future application table must enable RLS in its creating migration. Policy
tests must cover authenticated allowed cases, authenticated cross-user denial, and
anonymous denial unless public read is explicitly intended.

| Data area | Minimum expected access boundary |
| --- | --- |
| Profiles | Direct access remains authenticated owner-only select and approved-field update; exact cross-user discovery uses only the approved block-aware minimal projection |
| Active blocks | RPC-only application access; the caller can create/remove/list only outgoing blocks, while incoming and unrelated rows remain private |
| Friend relationships | RPC-only current-state access for the two participants through caller-relative summaries/lists and version-checked transitions; no direct table access or raw dormant-state disclosure |
| Active/shared lists | RPC-only owner/accepted-member reads; owner-only metadata/access management; member item mutations while active |
| Active-list participants | RPC-only caller-derived transitions; pending visible only to owner/recipient; minimal accepted participant projection |
| List items | RPC-only through the owner/accepted-member boundary; archived lists reject mutations |
| Future assignments, notes, mentions | Authorized list members, with mutations limited by later accepted rules |
| Invitations | Exact recipient and owner through versioned participant-access RPCs |
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
  later aggregates beyond the accepted profile, relationship, notification, and
  owner-list records.
- Support/administrator correction and audit rules for immutable usernames.
- Avatar Storage, validation, replacement, retention, and deletion lifecycle.
- Mention representation and parser ownership.
- Template category cardinality, version/provenance representation, and copy
  idempotency keys.
- Currency catalog, amount ranges, expense/settlement lifecycle, remainder and debt
  algorithms.
- Future notification-type payload/localization, archive/preferences, physical
  cleanup, account-lifecycle retention, and push-token tables.
- Offline mutation identifiers, tombstones, cache reconciliation, and conflict
  resolution.
- Reporting schema and moderation authorization.
