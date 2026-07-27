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
Active List --1:1 scalar--> General Note state
Active List --< current resolved Note Mention >-- Profile

List Item --< current Item Assignment >-- current List Participant
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
Exact custom shares require no new version.

The existing parameterless `export_own_account_data()` remains the unchanged
schema-version-6 boundary for legacy clients. The separate parameterless
`export_own_account_data_v7()` preserves versions `1` through `6` and adds a
non-null deterministic `assignees` array to each fully exported caller-owned item.
Each assignment object allowlists only `profile_id`, `username`, `display_name`,
`is_owner`, and `assigned_at`, ordered owner first and then by canonical username/
profile ID. `shared_list_access` remains byte-for-byte metadata-only and gains no
assignment array, item identifier, item name, or assignment timestamp. Versions
`1` through `7` remain strictly readable by the assignment-aware client.

The separate parameterless `export_own_account_data_v8()` preserves versions `1`
through `7` and adds only to each fully exported caller-owned list its nullable
General Note object containing text, note version, note-update time, and a
deterministic currently resolved mention array. Each mention object allowlists
profile ID, current canonical username, and current display name. Removed links
leave only literal text. `shared_list_access` remains
byte-for-byte P-039 metadata and gains no item, assignment, note, mention, or
participant identity. Versions `1` through `8` remain strictly readable by the
General-Note-aware client; the v6 and v7 functions are unchanged.

The separate parameterless `export_own_account_data_v9()` preserves versions `1`
through `8` and adds only `is_public` plus nullable `published_at` to each
caller-owned template. The two fields agree exactly. It exports no other user's
public template and no source identity, provenance, copy request UUID, or
fingerprint. Versions `1` through `9` remain strictly readable; the v6, v7, and v8
functions and their exact document shapes are unchanged.

The separate parameterless `export_own_account_data_v10()` preserves versions `1`
through `9` and adds one deterministic `submitted_public_template_reports` array.
Each entry contains only the caller's stable general `reason_code`, nullable
trimmed explanation, and server submission time. It contains no report/group/
template/reporter/moderator identifier, lifecycle state, snapshot, fingerprint,
restriction, decision, private note, allowlist, or access-audit data. Versions `1`
through `10` remain strictly readable; the v6 through v9 functions and their exact
document shapes remain unchanged.

The separate parameterless `export_own_account_data_v11()` preserves versions `1`
through `10` and adds deterministic `sent_template_offers` and
`received_template_offers` arrays for unsuppressed current-friend-pair history.
Sent entries include only offer ID, recipient minimal profile, snapshot name/count,
state/version, and lifecycle times. They never include accepted-template or source
identity. Received entries include only offer ID, sender minimal profile, the
allowlisted immutable name/item/quantity/position snapshot, state/version, and
times. Neither role receives request UUIDs, fingerprints, source/copy provenance,
moderation internals, or hidden pair history. Flutter strictly consumes v11 and
continues decoding the retained v1-v10 document shapes.

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
foreign keys add the complete personal template aggregate. Assignment and mention
foreign keys add the owned-list current-state links. Owned-list deletion cascades
that list's assignment, resolved-mention, and Split aggregates. For a deleted
non-owner in another person's list, one parent-first profile-deletion coordinator
locks surviving affected lists before their children, removes current assignments
and resolved mention links while preserving literal note text, applies the
single-bump item/note/list rules, then clears the Split participant's snapshots and
  live profile link while preserving list-owned expense/share/settlement/reversal
  arithmetic. It supersedes the former child-first Split anonymization and later
  list-locking assignment cleanup paths, eliminating their lock-order inversion.
  Public-template moderation foreign keys use `ON DELETE SET NULL`, immediately
  anonymizing reporter, source-owner, and moderator identity without destroying
  open evidence or an active restriction. This removes or anonymizes every
  currently implemented record involving the deleted account in the
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
creation request UUID used only for idempotency, nullable normalized
`general_note_text`, positive `general_note_version` defaulting to `1`, and
database-owned creation, update, nullable archive, and nullable note-update
timestamps. Status and archive time are constrained to agree; note text is null or
1-2,000 Unicode code points after line-ending normalization and outer trimming.
`(owner_id, creation_request_id)` is unique; duplicate titles remain valid.

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
item version. A real assignment-set change also increments both list and item
versions; a combined item-field/assignment update still increments each only once.
Real state changes update the corresponding server timestamps once; idempotent
no-op retries update neither. Expected versions prevent stale overwrite with a
stable `40001` conflict. Creation request UUIDs are checked against their payload
for retry safety and never grant ownership.

A list has a hard addition capacity of 200 current item rows. Completed and
uncompleted rows count equally; physical deletion frees capacity immediately.
The existing list-row lock serializes ordinary creation and template copy/import
with every competing addition. Capacity is an insertion gate only: existing rows
remain editable, completable, reorderable, and deletable at capacity. A legacy
list above 200 remains intact and readable but cannot receive additions until its
count falls below 200.

### Implemented current item assignment

`public.active_list_item_assignments` contains exactly one current row per
`(list_id, item_id, assignee_profile_id)`, which is also its composite primary key.
The `(list_id, item_id)` reference cascades from the same-list item, the assignee
profile reference cascades from account deletion, and database-owned `assigned_at`
records when this current row was inserted. A reverse
`(assignee_profile_id, list_id, item_id)` index supports account/access cleanup.
The table contains no assigned-by identity, assignment-local version, soft-delete
state, event history, template link, or copied profile text.

An item has zero through 20 assignment rows, bounded by the current
list-participant capacity.
The exact eligible set is the current unblocked list owner plus current accepted
members. Pending, declined, cancelled, removed, left, foreign-list, deleted, or
otherwise ineligible profiles cannot be referenced through the application
boundary. Every current owner/member may assign or unassign any eligible
participant, including themselves, on active completed or uncompleted items.

`list_active_list_items_v2` returns each item with a non-null deterministic
`assignees` array. `create_active_list_item_v2` and
`update_active_list_item_v2` accept the complete assignee profile-ID array and
atomically validate item fields, caller authority, eligibility, uniqueness, and
expected versions before replacing the set. A real set change increments parent
list/item versions once; exact retries/no-ops change nothing; stale or invalid
requests create no partial row, notification, version, or Realtime output. Legacy
item listing/creation/update signatures remain unchanged: legacy creation has zero
assignments and legacy update preserves them.

Before a mutation can create or retain a profile-backed reference, it locks the
relevant profile identities in UUID order. Participant-set lifecycle operations
also recheck their sorted preflight snapshot after acquiring the list lock.
Account-deletion cleanup then locks each surviving list, its affected items, and
retained participant rows in deterministic order, avoiding profile/list foreign-key
deadlocks without making stable read RPCs lock rows.

Explicit unassignment and parent item deletion remove current rows. Member
leave/removal, block-driven access loss, and non-owner account deletion remove all
of that profile's current assignments on surviving lists, permanently suppress
their assignment notifications, increment each affected item once and its list
once, and emit no unassignment notification. List deletion cascades all assignment
rows. Ownership transfer preserves assignments because the new and former owner
remain current participants. No assignment survives as item history or copies into
a template.

### General note and mentions

The one optional General Note is scalar state on `active_lists`, not an item,
comment stream, rich-text document, or history record. CRLF and CR become LF,
outer whitespace is trimmed, an empty normalized value becomes null, and internal
whitespace, line breaks, and Unicode remain unchanged. PostgreSQL and Flutter
enforce a maximum of 2,000 Unicode code points.

`public.active_list_note_mentions` contains one current resolved row per
`(list_id, mentioned_profile_id)`, which is its primary key. The list reference
cascades list deletion, the profile reference cascades account deletion, and the
reverse `(mentioned_profile_id, list_id)` index supports deterministic lifecycle
cleanup. A server-owned `resolved_at` records when that current link was inserted.
It stores no username/display snapshot, token range/offset, actor, mention-local
version, soft deletion, or event history. Forced RLS, revoked API table privileges,
and an explicit restrictive direct-client policy preserve an RPC-only boundary.

Owner and current accepted unblocked members may read and update the note while
active; archived notes remain readable but immutable. Pending, removed, left,
historical, blocked, foreign, deleted, or otherwise unauthorized profiles cannot
read or write it. The dedicated update operation derives its actor from
`auth.uid()`, treats submitted profile IDs as an untrusted complete desired link
set, deduplicates/canonicalizes them independently of client order, and validates
each as:

- one fully onboarded current owner/member;
- unblocked in either direction; and
- represented in the normalized saved text by its complete immutable canonical
  `@username` token.

Token matching is ASCII case-insensitive. Before and after the token must be
start/end or a character other than an ASCII letter, digit, underscore, or `@`.
Punctuation, whitespace, and line boundaries therefore qualify; email-like text,
doubled `@`, and longer/partial username tokens do not. Manually typed unresolved
text remains plain text. Repeated occurrences resolve one row. Self-mentions may
resolve but never notify. Rendering joins the stable profile ID to current
username/display name, so display-name changes remain live.
Completed usernames cannot change; incomplete onboarding candidates are not
eligible and cannot affect a mention.

A real text or desired-link change advances `general_note_version` and the parent
list version once. No-op and payload-equivalent completed retry change nothing;
payload-different stale work returns `40001` without partial state. Removal,
leave, block separation, or account deletion removes only the affected link and
preserves literal text. Reinvitation, unblocking, or later reuse of the old
username does not restore it; only a new explicit selection/edit can create a
current link.

Cross-identity mutation locking follows one hierarchy: non-locking preflight,
relevant profiles in UUID order, relationship-pair advisory lock only for
relationship lifecycle operations, affected lists in list UUID order, then items,
access rows, assignments, mentions, and Split children in deterministic internal
order, followed by notification/suppression/Broadcast work. No path acquires a new
profile, pair, or parent list after child mutation begins.

The combined child cleanup removes assignments and mentions and returns its exact
effects to the high-level access-loss coordinator. After ordered Split work, that
coordinator applies permanent suppression and the operation's single parent-list
advance. Each affected item advances once, and the note advances only if a link
changed, even when access, assignment, and mention state all change together.
Profile deletion uses one parent-first coordinator for every surviving list
referenced by access, assignment, mention, Split history, or completion
attribution, repairing the former child-first Split/list inversion.

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
It deliberately has no unit, completion, actor, assignment, General Note, mention,
reminder, date, membership, source-list, or destination-list field. Duplicate
names are valid.

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
invitations, ownership, assignments, General Note text, resolved mentions,
notifications, reminders, dates, and list state are excluded. The new template and
items have new IDs and no live source dependency.

### Creating or filling a list from a private template

Creating a new list validates one exact caller-owned template version and 1-200
unique selected current item IDs, creates one active caller-owned list, and copies
the selected rows in template order as new uncompleted list items. The new list's
General Note is null at version `1`, with no note-update timestamp or mention rows.
Importing into an existing list additionally locks that active destination and
rechecks normal
owner/member authorization, exact list version, and remaining capacity as `200 -
current item count`.

Existing-list import changes no General Note text, note version, note-update
timestamp, or resolved mention row.

Both operations validate every source identifier and reject null, duplicate,
missing, foreign, or stale selections. Each copied row consumes one capacity place,
including normalized duplicate names. Possible duplicate-name detection is a UI
warning only and never merges quantities or rows. Copy/import request UUIDs bind
retries without adding a source foreign key. An exact-capacity copy succeeds;
overflow, authorization loss, source/destination staleness, or concurrent capacity
loss rolls back every row, version change, and Realtime message.

### Public template publication and copy idempotency

Public visibility is one nullable field on the existing source:
`public.templates.published_at`. Null is private. A real first publication or
republication stores a server-owned timestamp; ordinary edits preserve it and
unpublication clears it. A conditional constraint requires a public template name
to contain 1-120 Unicode code points after the existing canonical trim. A partial
`(owner_id, published_at DESC, id DESC)` index contains only public rows.

Publication does not broaden direct table access. Existing owner-only/RPC-only
rules still govern mutation. Narrow public-profile RPCs expose a completed owner's
profile ID/current username/display name and public template ID/name/version,
item count, publication time, and ordered item name/quantity/position only. They
expose no source item identity, category, normalized value, private count, quota,
request key, fingerprint, or other aggregate. Either-direction block and profile/
template publication state are rechecked for listing, detail, copy, and direct-ID
access.

`private.public_template_copy_requests` is not provenance. Its physical fields are:

- destination `owner_id`;
- caller-generated `request_id`;
- a 32-byte domain-separated one-way fingerprint of the source ID/version
  arguments;
- `copied_template_id`, constrained to a destination owned by that same profile;
  and
- a server-owned `created_at`.

`(owner_id, request_id)` is the primary identity. Owner or destination deletion
cascades the row. The table enables and forces RLS, explicitly rejects direct
client operations, and grants no API-role table access. It is omitted from account
export and public RPCs.

Save a copy locks/rechecks completed profile identities, either-direction blocks,
the destination owner quota, source template/publication/version, and ordered
source items. It inserts a caller-owned, private, null-category template plus new
item UUIDs and the ledger row in one transaction. The destination stores no raw
source ID/profile/username, foreign key, attribution, or visible provenance.
Identical retry returns the existing copy; conflicting request reuse is invalid.
Every failed race writes nothing. Later source, relationship, block, username, or
account lifecycle cannot change a completed copy.

### Friends public-template feed projection

The friends feed is not a stored aggregate. A read-through RPC joins the caller's
one current normalized relationship row per pair to completed friend profiles and
currently public templates. Eligibility additionally excludes either-direction
blocks, active template restrictions, the caller's own profile, and any template
the caller successfully reported.

Only the existing public allowlist is projected: owner profile ID, current
username/display name, template ID/name/version, item count, and publication time.
Pages use the exclusive `(published_at, template_id)` descending keyset, default
20 and bounded 1-50, with no count or age cutoff. Friendship loss, blocking,
unpublication, deletion, restriction, reporting, or account deletion changes only
the next authoritative projection; refriending or unblocking may restore a
currently eligible row. No feed identifier, row, soft-delete state, view history,
retention rule, notification, export member, or Realtime publication exists.

### Public template reporting and moderation

The private moderation aggregate comprises:

- `public_template_moderators`, an initially empty Auth-UUID-only allowlist;
- append-only `public_template_moderator_access_events` for audited administrative
  grant/revoke requests;
- `public_template_report_groups`, keyed by an immutable public-template revision
  and 32-byte content fingerprint and retaining the exact allowlisted public
  snapshot;
- `public_template_reports`, retaining every individual reporter/reason/
  explanation/submission with uniqueness on reporter, template, and revision;
- one template-keyed `public_template_moderation_restrictions` current enforcement
  row;
- append-only `public_template_moderation_events` for dismiss, takedown, restore,
  and content-deleted decisions; and
- `public_template_moderation_tombstones`, containing only nonidentifying aggregate
  counts after detailed retention expiry.

All seven tables are in `private`, force RLS, explicitly reject direct client
operations, revoke API-role table privileges, and are omitted from Realtime
publication. Exact hardened RPCs are the only Flutter boundary. Administrative
allowlist and retention functions are `postgres`-only. Client-visible report and
moderation functions derive `auth.uid()`, recheck access or allowlist membership,
have empty `search_path`, fully qualify objects, revoke default/anonymous
execution, and grant only their exact authenticated signatures.

One report transaction locks the template moderation scope, rechecks the exact
public revision, block state, caller/non-owner rules, and active restriction, then
constructs this immutable snapshot:

- trimmed public template name; and
- ordered objects containing only item name, exact `quantity_thousandths`, and
  position.

No category, item UUID, username snapshot, email/Auth field, IP/device value,
private count, saved-copy information, or unrelated content is captured. The
domain-separated fingerprint is generated from the template ID, revision, and
canonical snapshot by PostgreSQL. A report row belongs to one matching group;
every report remains individual even when groups share template/revision content.
A unique reporter/template/revision key and the moderation-scope lock make
concurrent duplicate submission converge without duplicate evidence.

Group status is exactly `open`, `dismissed`, `taken_down`, or `content_deleted`.
Dismiss closes only the selected group. Takedown is template-level: one active
restriction makes the source private, blocks future publication, closes every open
group for the template, and appends one decision. Restore deactivates only an
active restriction and appends a restore event; it does not publish. Group,
restriction, source-template, and request versions/fingerprints make stale,
invalid, duplicate, lost-response, and concurrent transitions atomic and
idempotent. Decision request UUID reuse is payload-bound.

Source update/unpublish/delete triggers record changed/unpublished/deleted state
without rewriting the snapshot. Deletion closes open groups as `content_deleted`
and leaves evidence. Auth deletion nulls matching reporter/owner/moderator foreign
keys. Open groups and active restrictions are never retention candidates. Once a
template has no open group, no active restriction, and every closure/event is at
least 24 months old, the private idempotent maintenance function writes only
aggregate count tombstones and deletes reports, groups, events, and inactive
restrictions. The reviewed additive Cron migration owns one stable daily 03:47 UTC
job, removes
same-name predecessors before scheduling, executes the existing maintenance
function as `postgres`, and changes no evidence table or retention eligibility
rule.

### Template send offer and immutable snapshot

`public.template_sends` stores one sender, recipient, nullable live source
template, immutable snapshot name/count, five-state lifecycle, positive version,
state/update/create times, optional permanent suppression time, and a nullable
recipient-owned accepted template reference. Its states are `pending`, `accepted`,
`declined`, `revoked`, and `unavailable`. A partial unique index permits one
pending sender/source/recipient triple. Source deletion sets the source reference
null only after the pending lifecycle trigger closes the offer; accepted-copy
references may become null if the recipient later deletes that independent copy.

`public.template_send_items` contains only a new row ID, parent send ID, ordered
1-200 position, trimmed 1-120-character name, exact positive integer
`quantity_thousandths`, and server creation time. Snapshot updates are rejected;
parent retention/account deletion may cascade physical deletion. Duplicate names
remain separate positions. Zero snapshot rows and exactly 200 are valid; a legacy
source above 200 is left intact and cannot be sent.

`private.template_send_requests` is a forced-RLS, no-client-grant ledger keyed by
actor/request UUID. It stores only operation, 32-byte payload fingerprint, send
ID, and server time. Identical retry converges; reuse for another payload or
operation returns `23505`. No request UUID or fingerprint enters an RPC response,
notification, Realtime payload, accepted template, or export.

The recipient-only Accept transition creates one ordinary recipient-owned private
Uncategorized template and independent new item rows in the same transaction.
Recipient quota failure changes no offer, template, item, request, notification,
or Realtime row. Decline is recipient-only and Revoke sender-only. Every action
requires the exact pending version. Friendship loss, either-direction block,
source deletion, and active moderation restriction close pending offers as
`unavailable`; pair loss/block permanently suppresses all pair history, and
moderation suppresses affected source projections. Accepted copies remain
independent.

Terminal rows are eligible for privileged physical deletion only when
`state_changed_at` is at least 180 days old. Pending rows never expire
automatically. The maintenance function is idempotent. A separate operational
migration owns one stable daily 04:17 UTC `postgres` schedule per explicitly
authorized environment, replaces every same-name predecessor, and never invokes
cleanup during deployment. Production remains unscheduled until separately
authorized. The chronological friends feed is a read-through projection and
therefore has no retention model.

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

A notification belongs to one recipient. The current
`public.user_notifications` record contains:

- a database-generated UUID primary key;
- a recipient profile reference that cascades through account deletion and a
  nullable actor reference for system-authored moderation outcomes and
  template-send v1-v4 isolation;
- a check-constrained friend-request, list-access, ownership-transfer,
  `list_item_assigned`, `list_note_mentioned`, `public_template_taken_down`, or
  `public_template_restored` type, plus `template_send_received`;
- type-specific nullable relationship, participant-access, list, assignment-item,
  General Note, moderation, or template-send context and the positive
  authoritative version that caused the notification;
- database-managed creation time and expiry exactly 180 days later;
- nullable database-managed read time; and
- nullable permanent suppression time.

Named constraints require non-null actors and actor/recipient separation for
user-authored types, require a null actor for system-authored moderation outcomes,
enforce each type's exact reference shape, require valid normalized relationship
ordering and positive versions, preserve exact expiry, and prevent
read/suppression timestamps from preceding creation. Type-specific
recipient/resource/version uniqueness prevents duplicate creation. The row stores
no username, display name, list title, item name, email, Auth metadata, arbitrary
message, or independent action state.

Every real transition into a new pending relationship version creates one
notification for that recipient. A same-requester retry, crossed send into
friendship, or historical relationship row creates none. A valid dormant reopening
creates one for its new pending version.

The RPC-only boundary lists the current recipient's visible rows newest first by
deterministic `(created_at, id)` keyset, returns a matching unread count, and marks
a bounded set of caller-owned displayed IDs read. Listing resolves only currently
authorized actor/resource fields and projects action state from the authoritative
relationship or participant row. Only the exact matching pending version with the
actor as requester and recipient as caller is actionable.

Expired rows and permanently suppressed rows are excluded from listing and badge
counts. Creating a block suppresses every existing pair notification in the same
transaction, regardless of recipient direction; unblocking does not restore them.
No scheduled or physical cleanup is introduced in this slice.

Accepted informational notification types also include ownership transfer. The
new owner is the recipient, the former owner is the actor, and the reference uses
the former owner's resulting retained member-access version. No copied profile or
list text is stored.

`list_item_assigned` is informational. One real absent-to-present assignment
creates one row only for each newly assigned recipient other than the authenticated
actor, keyed by the resulting item version. A retry/no-op, self-assignment,
unassignment, other item edit, cleanup, or rejection creates none. Removing then
later re-adding the same assignee may create one new row at the new item version.
The item foreign key cascades item/list deletion. Names are joined live only while
the recipient retains current list access; access loss or either-direction block
permanently suppresses the row, so later reinvitation/unblocking cannot restore it.
Normal 180-day logical expiry otherwise applies.

Legacy notification listing/count functions exclude `list_item_assigned`, while
the v2 functions include all legacy types plus its current authorized list/item
projection. The shared mark-read function remains bounded, caller-owned, and
idempotent. This preserves strict old clients without duplicating the notification
table or creating a second action authority.

`list_note_mentioned` is informational. One real newly resolved link creates one
row for each other-user recipient, uniquely bounded by `(active_list_id,
recipient_id, notification_type, general_note_version)`. Retained mentions,
repeated tokens, self-mentions, removal, unrelated text edits, retry/no-op, cleanup,
and rejection create none. A later explicit re-resolution may create one new row
at the later note version. The row stores no note text/excerpt or copied actor/list
identity and has no deep-link action.

V1 listing/count explicitly excludes assignments and mention notifications. V2
continues to include assignments while excluding mentions. V3 includes both and
returns a mention only while recipient and actor retain list access, neither
direction is blocked, the list/context exists, and the row is unsuppressed and
unexpired. Each unread count uses its corresponding listing predicates. The shared
mark-read function keeps its signature/limits but repeats the v3 note authorization
and privacy checks, leaving inaccessible, suppressed, blocked, foreign, expired, or
deleted-context IDs unread.

V4 listing/count adds the two system-authored moderation outcomes while preserving
v1-v3 shapes. Their actor fields are null. The only payload references the
recipient-owned template, immutable moderation event, safe template-name snapshot,
and general reason. It contains no reporter, explanation, report count, moderator,
private note, or queue state. Event uniqueness yields exactly one notification per
successful takedown/restoration; report and dismiss create none.

V5 listing/count adds `template_send_received` while preserving v1-v4 shapes and
behavior. A real Send inserts exactly one actor-null row keyed by recipient, send,
and initial send version. V5 resolves the current sender and action state through
the protected offer; only the exact unsuppressed pending version is actionable.
V1-v4 exclude the type because its stored actor is null and it is not a moderation
outcome. Accept/Decline/Revoke create no sender notification. Mark-read retains its
signature and adds the same current pair/offer privacy predicate.

Access loss by the mention actor or recipient and either-direction blocking set
`suppressed_at = coalesce(suppressed_at, mutation_time)`. No operation clears that
timestamp. Reinvitation/unblocking cannot restore the historical row, although a
later new explicit mention may create a new unsuppressed version. Profile and list
deletion use the established physical cascades.

Implemented invitation action state belongs to participant access, as
friend-request action state belongs to the relationship. Template-send action
state belongs to `template_sends`; the Shared Templates UI localizes and renders
that server-owned state. Archive/delete
and preference controls, later-type payload localization, physical cleanup beyond
the accepted offer cascade/retention, and retention beyond the implemented
current-aggregate account deletion remain open.

Push tokens and delivery attempts are future infrastructure for FCM/APNs and are
outside the initial identity/profile schema. Device token ownership, rotation,
invalidation, and privacy rules must be designed before push implementation.

## Public-content safety records

Directional blocking and exact block-aware username discovery preceded friend
requests in Phase 1. The accepted Public Template safety model is the private
reporting/moderation aggregate above: individual reports, immutable revision
snapshots, grouped review, UUID allowlisted moderators, restriction-backed
takedown/restoration, append-only decisions, 24-month detailed retention, and
nonidentifying tombstones.

Report withdrawal, reporter follow-up, appeal, user unhide, attachments, automated
moderation, strikes, administrator/compliance tooling, and broader public-feed
safety remain outside this first contract. Those capabilities require separate
product and retention decisions before schema or code is added.

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
Assignment create/update/cleanup likewise changes parent item/list versions and
uses the same list fanout; a `list_item_assigned` insert additionally invalidates
its recipient through the existing notification trigger. No assignment identifier,
content, actor, item, or version enters the Broadcast payload.

General Note update/mention cleanup likewise uses the parent-list fanout; a
`list_note_mentioned` insert additionally invalidates only its recipient. No note
text, mention identity, actor, list, or version enters the payload, and no new
topic, event, channel, policy, or transport record is added.

Public Template report success invalidates the reporter account. Moderator
grant/revoke/action, takedown/restoration notification, and source-lifecycle
changes invalidate only server-derived affected moderators/owners through the same
opaque contract. No reason, explanation, snapshot, fingerprint, report count,
moderator, decision, private note, or restriction state enters the payload, and no
moderation table is in a Realtime publication.

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
| Current item assignments | RPC-only full-set v2 item mutations by current unblocked owner/members; eligible current participants only; direct CRUD denied |
| General Note and current resolved mentions | RPC-only current unblocked owner/accepted-member read; active-only update through exact server-validated text/link replacement; archived read-only; direct mention-table CRUD denied |
| Invitations | Exact recipient and owner through versioned participant-access RPCs |
| Private templates/categories | RPC-only owner access; copies into accessible lists recheck destination membership and state |
| Public templates | Readable according to approved public-profile and current-friends feed policies; mutation remains owner-only |
| Template sends | RPC-only current unblocked friend pair; sender may Send/Revoke and see minimal status, recipient may read snapshot and Accept/Decline; sender never sees accepted-copy identity; direct CRUD denied |
| Split settings, participants, expenses, shares, settlements, reversals, balances, suggestions | RPC-only current unblocked owner/member reads; owner-only setup; active owner/member expense and settlement mutations; original recorder/current owner reversal |
| Notifications | Recipient only; related actors do not gain notification-row access |
| Storage objects | Same ownership/membership rules as the parent application record |
| Public Template reports and moderation | Reporter may submit only through the exact report RPC; only the UUID allowlisted moderator may read/action the private queue; all direct client table access is rejected |

Policies must derive identity from `auth.uid()` and server-owned relationships, not
from a user ID supplied by the Flutter client. Privileged functions require
explicit grants, protected search paths, and adversarial policy/function tests.

## Physical-model decisions still required

- Identifier types, timestamp/audit conventions, soft delete, and archival for
  later aggregates beyond the accepted profile, relationship, notification,
  owner-list, and current-assignment records.
- Support/administrator correction and audit rules for immutable usernames.
- Avatar Storage, validation, replacement, retention, and deletion lifecycle.
- Global/ranked public-template discovery beyond the accepted chronological
  friends feed.
- Later notification-type payload/localization, archive/preferences, physical
  cleanup, account-lifecycle retention, and push-token tables.
- Offline mutation identifiers, tombstones, cache reconciliation, and conflict
  resolution.
- Appeal, administrator/compliance, and later moderation-automation contracts
  beyond the accepted Public Template report/review lifecycle.
