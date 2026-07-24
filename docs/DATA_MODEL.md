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
Active List --< Split Participant --payer/beneficiary--> Expense / allocated share
Active List --< immutable Settlement / one-time Reversal --payer/recipient/recorder--> Split Participant

Profile --owns--> Template --< Template Item
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

Schema version `3` adds caller-relative shared-list access metadata without list
contents or other identities. Schema version `4` adds deterministic
`template_categories` and `templates` arrays. Categories expose only their own
identity, name, version, and timestamps. Each template exposes its own identity,
nullable category identity, name, version, timestamps, and an ordered `items`
array containing only item identity, name, exact integer quantity thousandths,
position, version, and timestamps.

Schema version `5` adds a nullable `split` object to each fully exported owned
list. When enabled it allowlists currency/settings, persistent financial
participants and their live-or-anonymized display state, ordered expenses, payer
and editor participant IDs, and ordered explicit allocated shares. Those same rows
represent canonical equal and exact custom allocations; no allocation-mode field
is stored or exported. Balances are omitted because they are reproducible from
those integer records. Shared-list access stays metadata-only and never includes
another owner's Split contents.

Schema version `6` adds deterministic settlement and reversal arrays inside that
same caller-owned-list `split` object. It allowlists immutable settlement
identities, payer/recipient/recorder participant IDs, integer amounts, optional
notes, server timestamps, and the one-time reversal's recorder, reason, and link to
its settlement. Request IDs, derived balances, and suggested payments are omitted.
Exact custom shares require no version `7`; versions `1` through `6` remain
strictly readable.

Every nested object is built from an explicit field allowlist. The social arrays
apply the same directional-block, caller-relative active-relationship, recipient,
suppression, expiry, and either-direction block filters as their existing RPC
projections. Arrays are never null. Raw table rows, Auth metadata, credentials,
tokens, sessions, incoming blocks, dormant relationship internals, hidden actors,
and future aggregate data are outside the contract. Later schema versions must add
future public/shared-template sections deliberately and compatibly.

### Permanent deletion and username reservation

Immediate hard deletion of `auth.users` is the account aggregate's atomic root.
The profile foreign key cascades from Auth; both block participant references,
both normalized relationship participant references, notification recipient and
actor references, and the notification relationship reference cascade from the
profile/relationship rows they protect. Owned-list and list-item foreign keys add
the list aggregate to that same cascade. Private category/template ownership
foreign keys add the complete personal template aggregate. Owned-list deletion
cascades that list's Split aggregate. For a deleted non-owner in another person's
list, a profile-deletion trigger clears the Split participant's snapshots and live
profile link while preserving list-owned expense/share/settlement/reversal
arithmetic. This removes or
anonymizes every currently implemented record involving the deleted account in the
same root transaction, while unrelated rows, including lists created or filled
from template snapshots, remain unchanged.

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

A list has a hard addition capacity of 200 current item rows. Completed and
uncompleted rows count equally; physical deletion frees capacity immediately.
The existing list-row lock serializes ordinary creation and template copy/import
with every competing addition. Capacity is an insertion gate only: existing rows
remain editable, completable, reorderable, and deletable at capacity. A legacy
list above 200 remains intact and readable but cannot receive additions until its
count falls below 200.

No assignment or item-event table exists yet. Multi-member assignment and its
authorization/audit rules remain open with the collaborative-list phase.

### General note and mentions

An active list has one general note. Mentions connect relevant ranges or parsed
tokens to list members so notification delivery is not based solely on
unvalidated client text. The storage and parsing model, editing behavior, and
deduplication rules remain open.

## Private template aggregate and copy semantics

### Private template category

`public.template_categories` is owned by one completed profile and has a UUID
identity, canonical display name, normalized name, positive monotonic `bigint`
version, a payload-bound creation request UUID, and database-owned creation/update
times. Name normalization trims outer whitespace, collapses internal whitespace,
and lowercases only the comparison form. `(owner_id, normalized_name)` is unique,
while different owners may use the same normalized name. One owner may retain at
most 25 current categories, including empty categories.

### Private template and item

`public.templates` is owned by one completed profile and has a UUID identity,
nullable category reference, non-empty trimmed name, positive monotonic `bigint`
version, a payload-bound creation request UUID, and database-owned creation/update
times. The category must have the same owner. Names need not be unique. Each
template belongs to at most one category; null is Uncategorized. One owner may
retain at most 100 templates.

`public.template_items` has a UUID identity, one template reference, trimmed
1-120-character name, exact integer `quantity_thousandths` from `1` through
`999999999`, positive deterministic position, positive monotonic `bigint` version,
a payload-bound creation request UUID, and database-owned creation/update times.
It deliberately has no unit, completion, actor, reminder, date, membership,
source-list, or destination-list field. Duplicate names are valid.

Every category, template, and item mutation derives the owner only from
`auth.uid()`. Category/template counts are serialized by a caller-scoped
transaction lock; template item counts and item mutations are serialized by the
template-row lock. A template may retain at most 200 current items. Deletion frees
capacity immediately; edit, reorder, and delete remain valid at capacity. Template
and item versions never decrement or reset for an existing UUID. New identities
after physical deletion begin independent lineages.

Renaming a category changes only that category's version. Deleting a category
locks affected templates deterministically, advances each affected template once,
sets its category to null, and deletes the category in one transaction. Template
metadata changes advance the template version once. Item add/delete/reorder advance
the template version once; item edit advances both template and item once.

All three tables are RPC-only with enabled and forced RLS, explicit restrictive
`FOR ALL` rejection policies for `anon` and `authenticated`, and no direct client
or service-role table grants. Auth-root owner deletion cascades templates, items,
and categories; category deletion does not delete templates.

### Shopping-list snapshot into a private template

An authenticated owner or accepted member may snapshot an accessible active or
archived list into a new private template. The transaction validates the exact
list version and 1-200 unique selected current item IDs against authoritative rows,
locks the source list/items and the caller's template quota, then copies only name,
quantity, and source order. Completed state, unit, attribution, participants,
invitations, ownership, reminders, dates, and list state are excluded. The new
template and items have new IDs and no live source dependency.

### Creating or filling a list from a private template

Creating a new list validates one exact caller-owned template version and 1-200
unique selected current item IDs, creates one active caller-owned list, and copies
the selected rows in template order as new uncompleted list items. Importing into
an existing list additionally locks that active destination and rechecks normal
owner/member authorization, exact list version, and remaining capacity as `200 -
current item count`.

Both operations validate every source identifier and reject null, duplicate,
missing, foreign, or stale selections. Each copied row consumes one capacity place,
including normalized duplicate names. Possible duplicate-name detection is a UI
warning only and never merges quantities or rows. Copy/import request UUIDs bind
retries without adding a source foreign key. An exact-capacity copy succeeds;
overflow, authorization loss, source/destination staleness, or concurrent capacity
loss rolls back every row, version change, and Realtime message.

Public visibility, saving another account's template, sent-template actions,
attribution/provenance presentation, and community feed behavior remain future
aggregates and create no schema in this slice.

## Split expense-ledger aggregate

Split exists only for a main list where the owner has enabled it. It is a ledger,
not a payment rail. The physical aggregate comprises list settings, persistent
list-scoped financial participants, expenses, explicit allocated shares, immutable
settlements, and append-only one-time reversal records.

### Currency and integer representation

- A list has one currency for its ledger. The first explicit catalog is exactly
  `CHF` and `EUR`; both use two minor-unit decimal digits.
- Expense totals, shares, settlement amounts, and balances use signed or unsigned
  `bigint` minor units as appropriate. Accepted expense totals are `1` through
  `999999999`; a settlement has no separate expense-size cap and is bounded by the
  authoritative balances it adjusts.
- Flutter parses/formats decimal text directly to/from integers. Neither Flutter,
  JSON, SQL, nor tests use binary floating point as monetary authority.
- Only the owner sets currency. It may change only while the authoritative expense
  count is zero and no settlement history has ever existed. The first settlement
  locks it permanently even after reversal, so historical integers are never
  reinterpreted.

Use a sufficiently wide integer type and explicit range validation. Never infer an
amount by multiplying a floating-point value.

### Expense, payer, participants, and shares

Each enabled list owns independently generated persistent financial participant
UUIDs distinct from current access, Auth, and profile IDs. A live identity links to
one profile and snapshots its username/display name. The partial
`(list_id, profile_id)` uniqueness boundary reuses it after leave/removal and
reacceptance. Acceptance after Split enablement materializes or reuses exactly one
identity; ownership transfer keeps those same identities. Account deletion changes
the row to an anonymous state with null profile/snapshots and no deletion timestamp;
membership removal alone does not.

An expense belongs to one enabled list, has a trimmed 1-120-character description,
a positive bounded integer total, one payer participant, creator/last-editor
participant IDs, timestamps, a positive version, and one or more explicit shares.
Same-list composite foreign keys prevent cross-list references. At most 200 current
expenses may exist; physical deletion frees capacity without modifying legacy
over-capacity data. Direct client writes are denied.

Creation also stores a payload-bound request UUID unique within the list. Matching
lost-response retries are idempotent; reuse for different content is invalid. The
request UUID is never returned or exported.

For new expenses, payer and beneficiaries must be the current owner or accepted
unblocked members; the payer may be outside the beneficiary subset. On edit, an
ineligible historical participant may remain only in roles already held on that
expense and cannot be newly introduced. An attached historical beneficiary may
retain or change their amount; omission removes that exception until the account
becomes eligible again.

Equal is the default input mode and is calculated only by the server. It uses
`floor(total / count)`; the first `total mod count` immutable participant UUIDs in
ascending order each receive one additional unit. Custom input consists only of
exact CHF/EUR minor-unit amounts. Zero deselects the participant before submission;
every submitted custom share is positive, identities are unique, and the complete
set must sum exactly to the expense total. No percentage, weight, ratio,
proportional allocation, automatic remainder correction, or partial adjustment
exists.

Stored share rows remain the only durable allocation truth. There is no persisted
Equal/Custom classification. Flutter infers Equal only by comparing the complete
stored share set with the canonical UUID-ordered equal result, so custom input
identical to that result may reopen as Equal. Equal-to-Custom prefills the current
canonical shares; Custom-to-Equal causes the server to recalculate on confirmed
Save. Equal allocation may retain a zero share when the positive total contains
fewer minor units than selected beneficiaries; custom submissions never store a
zero share.

Versioned create/update RPCs replace the entire share set atomically and enforce
list/settings/expense versions. On creation, request IDs bind the deterministically
normalized participant/minor-unit pairs, so identical logical retries are
idempotent and conflicting allocation reuse is invalid. On update, those complete
pairs participate in exact no-op comparison under the existing expected-version
contract; there is no update request ID. The legacy equal create contract remains
supported, while its update rejects an existing non-equal expense before mutation.
Every rejection leaves rows, versions, notifications, and Realtime output
unchanged.

### Settlement and reversal

A settlement records external bookkeeping, not proof that List & Split processed
money. It belongs to one enabled list and has one same-list payer, recipient, and
server-derived recorder participant; a positive integer minor-unit amount; an
optional trimmed note of at most 120 characters; a server timestamp; and a
payload-bound request UUID that is never returned or exported. Payer and recipient
must differ. Current unblocked owners/members may record, but cannot choose the
recorder identity.

At creation, the payer must have an authoritative negative balance, the recipient
an authoritative positive balance, and the amount must not exceed
`min(abs(payer_balance), recipient_balance)`. Either endpoint may be a removed or
anonymized historical participant. This permits full and partial settlement
without inventing a current membership identity.

Settlement rows are immutable. An incorrect entry is corrected by exactly one
append-only reversal record rather than edit or deletion. The original recorder or
current owner may reverse; a reversal records its server-derived actor, required
trimmed 1-120-character reason and server timestamp, and derives the full opposite
direction and original amount. A reversal remains valid after later ledger changes
because it corrects history rather than asserting a new current payment.

Creation and reversal request UUIDs are payload-bound and list-scoped. Exact retries
are idempotent, conflicting reuse is invalid, and expected Split versions serialize
concurrent work. There is no lifetime settlement count limit. Newest-first history
uses bounded deterministic `(created_at, id)` keyset pages.

### Balances and debts

Current balances are derived server-side on demand as
`expense_paid - expense_owed + non_reversed_settlements_paid -
non_reversed_settlements_received`. Positive means receivable, negative means owed,
zero means settled, and all participant nets sum exactly to zero. A mutable balance
aggregate is prohibited.

Suggested payments are also derived rather than stored. Debtors sort by largest
absolute debt then participant UUID; creditors sort by largest receivable then
participant UUID. Each match uses the smaller remaining side and advances every
zeroed participant. The deterministic output conserves all integer minor units and
has at most `debtors + creditors - 1` rows, but is not guaranteed to minimize the
number of transactions.

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
| Private templates/categories | RPC-only owner access; copies into accessible lists recheck destination membership and state |
| Public templates | Readable according to approved public-profile policy; mutation remains owner-only |
| Template sends | Sender and recipient; acceptance only by recipient |
| Split settings, participants, expenses, shares, settlements, reversals, balances, suggestions | RPC-only current unblocked owner/member reads; owner-only setup; active owner/member expense and settlement mutations; original recorder/current owner reversal |
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
- Public-template visibility/copy placement, sent-template version/provenance,
  attribution, and offer idempotency.
- Future notification-type payload/localization, archive/preferences, physical
  cleanup, account-lifecycle retention, and push-token tables.
- Offline mutation identifiers, tombstones, cache reconciliation, and conflict
  resolution.
- Reporting schema and moderation authorization.
