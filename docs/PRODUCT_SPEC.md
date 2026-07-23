# List & Split product specification

## Purpose and implementation status

List & Split is an Android and iOS application that combines collaborative active
lists, reusable list templates, a friends-based community, and an optional expense
ledger.

This document records the agreed product direction. It is not a statement that the
features below are implemented. Source code, tests, migrations, and pull requests
are the evidence of implementation status.

## Product principles

- Collaboration is based on mutual, accepted friendships rather than followers.
- Reusable content is copied by value. A user's active list or saved template must
  not change because its source changes later.
- **Split** is the current product and UI name for the optional expense ledger
  previously described as Payment Control. It records expenses and settlements;
  it never moves real money.
- Monetary values use integer minor units throughout. Floating-point money is
  prohibited.
- The mobile information architecture has four primary destinations. Notifications
  are important, but not a fifth tab.
- English is the initial UI language, while code and content structure remain ready
  for localization.

## Functional requirements

### Authentication and profile onboarding

- Initial authentication uses email and password only. Google, Apple, anonymous,
  magic-link-only, and other providers are outside the initial release.
- Email verification is mandatory before a user can enter the authenticated
  application.
- The identity flow includes sign-up, sign-in, sign-out, resend verification,
  forgotten-password request, and password recovery with a new password.
- New and replacement passwords require at least eight characters. Passwords and
  confirmations are compared exactly as entered; the client does not trim,
  lowercase, or impose composition rules.
- Authentication failures use generic wording where a more specific response
  would disclose whether an account exists.
- After verification, a user completes profile onboarding by choosing a username
  and display name.
- Username input is trimmed and converted to lowercase. The canonical username is
  globally unique, 3-24 characters, begins with a lowercase ASCII letter, and then
  contains only lowercase ASCII letters, digits, or underscores. Its canonical
  expression is `^[a-z][a-z0-9_]{2,23}$`.
- A username becomes immutable after onboarding. A future support or administrator
  correction path, if any, must be designed and audited separately.
- Display name is separate from username, non-unique, editable, trimmed, and 1-50
  characters.
- Email addresses remain private authentication data and are never copied into
  public profile fields.
- The initial profile capability is owner-only. Users can read and update only
  their own approved fields; cross-user search/discovery is deferred until it can
  account for blocking.
- Avatar editing is accepted future behavior. Image selection, upload, Storage
  buckets, object policies, and avatar lifecycle are outside the initial profile
  slice.

### Account data export and deletion lifecycle

- Account export and permanent account deletion are separate capabilities. Export
  was delivered and manually verified before deletion implementation began.
- Any signed-in user with a verified email can download their data, including
  while profile onboarding is incomplete. The action is available from completed
  Profile and verified incomplete Onboarding; it does not weaken the existing
  configuration, authentication, or email-verification gates.
- **Download my data** produces one UTF-8 JSON document with product identifier,
  positive export schema version, server-generated UTC export time, the caller's
  allowlisted Auth identity and profile fields, outgoing blocks, active
  caller-visible relationships, currently visible recipient notifications, and
  owned active lists with ordered items. Version `1` introduced the account/social
  sections; version `2` adds the explicit `active_lists` root array; version `3`
  adds privacy-minimal caller-relative shared-list access metadata; version `4`
  adds private template categories, templates, and ordered template items; version
  `5` adds Split expense data nested only under the caller's fully exported owned
  lists; version `6` adds that owned-list Split ledger's immutable settlement and
  one-time reversal history. Collections are deterministic arrays and are empty
  rather than null.
- The export includes nullable onboarding fields faithfully. It includes only the
  existing caller-visible block, relationship, and notification projections, so
  either-direction block suppression, dormant relationship privacy, notification
  suppression, and 180-day logical expiry remain authoritative.
- The list export contains both active and archived owned lists and only approved
  list/item identifiers, title/name, status, exact integer quantity thousandths,
  stable unit code, integer position, completion attribution/time, versions, and
  timestamps. Split export includes the persistent participant identities needed
  to understand expenses and settlements, settlement endpoints, recorder
  attribution, amounts, notes, reversal links/reasons, and server timestamps. It
  excludes creation/reversal request IDs, derived balances and suggestions, and
  internal locking or authorization details.
- After ownership transfer, the new owner receives the list only in the full owned
  projection and the former owner receives its caller-relative shared-access
  metadata. The internal retained owner-access state is never exported as shared
  membership.
- The export never includes passwords or hashes, tokens, sessions, raw Auth
  metadata, another person's email or Auth data, incoming blocks, raw dormant
  relationship state, reopening/requester internals, suppressed/expired/
  block-hidden notifications, server logs, security records, other participants
  or shared-list contents, public/shared-template data, or Split data from a list
  the caller does not own. Shared-list export remains privacy-minimal metadata.
- Export is generated synchronously on demand and returned to the caller. The
  server retains no export file or export record. The mobile app validates and
  pretty-prints the versioned document, writes it to OS-managed temporary/cache
  storage with a non-identifying UTC filename, and opens the native share sheet.
  Temporary cache cleanup is not guaranteed secure deletion.
- This is a product-level account-data download. It is not a claim of complete
  legal or regulatory data-portability compliance; those obligations remain open
  for explicit review.
- Permanent account deletion is immediate and irreversible, with no grace period,
  soft-deletion state, recovery window, or restoration. It is available to every
  signed-in email-verified user, including while onboarding is incomplete. Export
  is offered first but is never mandatory.
- A completed profile must enter its exact stored canonical username. An
  incomplete profile must enter its exact stored Auth email. Confirmation is
  compared exactly without trimming, lowercasing, case folding, or other
  transformation. The user must also give a final explicit acknowledgement of the
  irreversible result.
- The current password is required and is sent unchanged only to Supabase Auth for
  `signInWithPassword` reauthentication using the current email. It is never sent
  to the Edge Function or database, retained in Riverpod/global state, logged,
  analyzed, or reported. The new exact session returned by reauthentication must
  become the active client session.
- The authenticated `delete-account` Edge Function receives only the exact
  confirmation. Before invoking the server-only Auth Admin hard-delete operation
  for the authenticated caller, it uses a narrow database RPC to require the JWT's
  `session_id` to match that user's `auth.sessions` row whose actual `created_at`
  is no more than ten minutes old. JWT `iat`, access-token refresh time, and
  user-level `last_sign_in_at` are not freshness evidence.
- Deleting the Auth user is the atomic root operation. Database cascades remove
  the profile, incoming and outgoing blocks, relationships in either participant
  position, notifications where the user is recipient or actor, notifications
  attached to a deleted relationship, every owned list and item, and every private
  template, template item, and category. No
  application cleanup transaction is committed separately before the Auth
  deletion. On another owner's list, the deleted account's Split identity is
  anonymized in that same root transaction while its integer expense, settlement,
  and reversal arithmetic remains valid.
- Deleting a completed profile reserves only its canonical username for exactly
  30 days from deletion. The private reservation contains no email, Auth user ID,
  profile ID, display name, or copied user data. Active reservations block
  onboarding; expired reservations permit a claim and are physically removed once
  daily at 03:17 UTC by migration-managed database Cron. Incomplete profiles
  create no reservation.
- Successful deletion clears all local session-bound state and returns to sign-in.
  If a response is lost, the client authoritatively checks Auth: a confirmed
  missing user is treated as local success, an existing user remains signed in
  for safe retry, and an offline/transient validation failure neither claims
  success nor signs out a valid user. On application resume, an authoritative
  missing/invalid Auth user signs that device out; transient network failures
  preserve its session.
- Re-registration after deletion creates a new Auth UUID and restores no profile,
  blocks, relationships, notifications, or other data. Every future Storage,
  moderation/legal-retention, or administrator-deletion aggregate must extend this
  contract before shipping. This product lifecycle is
  not a claim of complete legal or regulatory compliance. Hosted deletion QA uses
  separately authorized disposable accounts and must never delete or modify
  Fernando or Susana.

### Active and shared lists

Each list has one fully onboarded owner and retained, versioned access rows.
Assignment, note, mention, and offline cache records are not implemented. Private
templates and the first Split expense-ledger slice use separate list-integrated
aggregates.

- The owner can create, list, open, rename, archive, restore, and permanently
  delete a list. Duplicate titles are allowed; titles are trimmed and contain
  1-80 characters. Status is exactly `active` or `archived`.
- Active lists are ordered by most recent update, then ID. Archived lists are
  ordered by most recent archive time, then ID. Both use bounded keyset
  pagination and show total/completed item counts.
- Archived lists remain readable and explicitly read-only. Every server mutation,
  including item changes and reorder, is rejected while archived. Restore is the
  only transition out of that state. Deleting a list permanently removes its
  current items after explicit confirmation.
- The owner and accepted members can add, edit, complete, reopen, reorder, and
  permanently delete items while the list is active. Only the owner can rename,
  archive, restore, permanently delete, invite, cancel, or remove members.
- Quantity defaults to `1`, must be positive, supports at most three decimal
  places, and is at most `999999.999`. Authority is an integer number of
  thousandths (`1` = `1000`, `1.5` = `1500`, `0.001` = `1`); Flutter never parses
  through binary floating point and display removes unnecessary trailing zeros.
- Unit is optional and stored only as null or the stable code `piece`, `kg`, `g`,
  `l`, `ml`, `pack`, `box`, `bottle`, `can`, or `bag`. Display labels are localized.
- Initial item order follows successful creation. Drag reorder is atomic,
  deterministic, integer-based, and requires exactly the current unique item ID
  set.
- A shopping list may contain at most 200 current items. Completed and uncompleted
  items both count; permanently deleted items do not and immediately free one
  place. Capacity is enforced under the list lock for ordinary creation and every
  template copy/import path. Existing over-capacity lists remain readable and
  editable but reject additions until their current count falls below 200; no
  migration deletes, truncates, or rewrites existing items.
- Completion stores database-owned `completed_at` and the authenticated owner as
  `completed_by`; reopen clears both. A later deleted actor may leave the
  completion time with a null actor, but actor deletion can never delete the item.
- Positive monotonic versions prevent stale overwrite. List metadata changes
  increment list version; item create/delete/reorder increment list version; item
  edit/complete/reopen increment list and item versions. Real changes update the
  corresponding timestamps once; completed retries/no-ops update neither.
  Creation is retry-safe through a payload-bound client request UUID that never
  grants authority. Stale conflicts refresh instead of silently overwriting.

- Only accepted friends can be invited. Invitations are persistent, do not expire,
  reserve one of the 20 participant places, and retain one monotonic current access
  row in `pending`, `member`, `declined`, `cancelled`, `removed`, `left`, or the
  internal transfer-only `owner` state.
  Accept, decline, cancel, remove, leave, and reinvite use exact versions and are
  idempotent for completed retries. Owners cannot leave; members may leave archived
  lists; active-list ownership transfer follows the accepted contract below.
- Archiving atomically cancels pending invitations. Archived content remains readable,
  members may leave and owners may remove members, but invitation creation/acceptance
  and content mutation are rejected. Restore revives no access state.
- Ending friendship cancels pending invitations and preserves accepted membership.
  Blocking atomically separates the pair: an owner removes the member, a member
  leaves when blocking the owner, and a member who blocks another member leaves
  their shared third-party lists. Unblocking restores nothing and notification text
  never discloses block direction or cause.
- Routine item changes create no persistent notifications. Real invitation
  transitions create one actionable notification for the exact access version;
  owners receive generic accepted/declined/member-left information and removed
  recipients receive generic information. A pending invitation remains actionable
  beyond normal notification expiry; resolved notifications use normal retention.
- Accepted participants see only profile ID, username, and display name for the owner
  and accepted members. Pending recipients are visible only to the owner and that
  recipient.
- Only the current owner may immediately transfer an active list to one current
  accepted member after an explicit confirmation naming that member. Friendship is
  not re-required, but either-direction blocks and every existing membership rule
  remain authoritative. The recipient becomes the sole owner atomically; the
  former owner remains an accepted member, capacity and list content remain
  unchanged, and no password reauthentication or offline transfer is supported.
- A real transfer increments the list version exactly once, preserves monotonic
  retained access versions for both identities, and creates exactly one
  informational notification for the new owner. Stale, unauthorized, archived,
  blocked, ineligible, failed, or rolled-back attempts change nothing and emit no
  notification or Realtime invalidation. The new owner gains and the former owner
  loses every owner-only capability immediately; transferring back is a new
  confirmed operation by the then-current owner.
- Connected authenticated devices subscribe to one private account-scoped
  Broadcast channel after onboarding. The fixed `invalidate` event carries only
  application payload `{"v":1}`; it is best-effort notice that authoritative
  visible state may have changed, never content or authorization evidence.
  Valid events, successful subscription joins, and app resume reconcile mounted
  list, detail, member, notification, badge, and relevant community projections
  through existing repositories. Remote rename updates mounted list titles; remote
  archive/restore moves the list between projections, and a remotely archived open
  detail returns to Lists once. Manual refresh remains available.

### Templates

The product term is **Templates**; the former name **Internal Lists** should not be
used in new UI or documentation. This slice implements only private personal
templates. Public, shared, sent, friend-owned, and collaborative templates remain
future work.

- A template is one account-owned reusable ordered collection of item names and
  quantities. Template items have no completion state, actor attribution, unit,
  reminder, date, membership, or live link to a list item.
- Template names need not be unique and must be non-empty after trimming. Blank
  templates with zero items are valid and may remain empty after item deletion.
- An account may own at most 100 templates. A template may contain at most 200
  current items. Each item follows the existing list-item trimmed 1-120-character
  name and integer-thousandths quantity limits. Deleting an item immediately frees
  one place; at capacity existing items may still be edited, reordered, or deleted.
- Owners may create, rename, recategorize, and permanently delete templates, and
  may add, edit, reorder, and permanently delete their items. Template deletion
  requires confirmation and changes no shopping list.
- Categories are optional private account metadata. Each template belongs to zero
  or one category; no category is presented as **Uncategorized**. An account may
  own at most 25 categories, including empty visible categories.
- Category names are trimmed, collapse runs of whitespace, and are unique per
  account after case-insensitive normalization. Different accounts may use the
  same name. Renaming keeps template placement; deleting a category atomically
  moves its templates to Uncategorized without deleting them.
- The Templates destination opens on All Templates. It provides a prominent
  create action, category management and one active category filter (including
  Uncategorized), search across template and item names, details and management
  actions, and Recently updated, A-Z, and Newest created sorts. Empty categories
  remain visible.

An owner or accepted member may save any active or archived shopping list they can
still access as their own private template. The preview includes completed and
uncompleted items, selects all by default, permits deselection, and requires 1-200
selected items. Only the selected names, quantities, and current order are copied.
The template is an independent snapshot that survives later source changes,
deletion, access loss, friendship changes, or blocking.

A private template can be used in two ways:

1. Create a new active shopping list owned by the caller, with an editable name
   prefilled from the template and 1-200 selected items copied atomically as
   uncompleted items. It starts without other members, invitations, reminders, or
   dates.
2. Import selected template items into an existing active shopping list where the
   caller may normally add items. Remaining capacity is `200` minus the
   authoritative current destination-item count. Confirmation is disabled for no
   selection or a selection larger than that remaining capacity. The user may
   start from a template and choose a destination, or start from an already-open
   active list and choose one of their private templates. The list-first path
   keeps that list fixed through preview and returns directly to it after success.

Both previews select all items by default and preserve selected template order.
Every imported row is a new independent list item. Possible duplicates are marked
when normalized names match existing destination items, ignoring capitalization
and extra spaces, but remain selected by default. Keeping a possible duplicate
creates a separate item; quantities are never merged and existing items are never
replaced or edited.

All save/copy/import operations revalidate caller access, exact source and
destination versions, every selected source identifier, state, and capacity in one
transaction. Duplicate, missing, foreign, stale, unauthorized, or over-capacity
requests fail without partial rows, version changes, or Realtime invalidations.
Destination capacity changes never silently reduce the selection. Exact-capacity
copies succeed; duplicate-name rows each consume one place.

### Community

- Initial discovery is a deliberate exact lookup of one canonical username.
  Input is trimmed and lowercased under the profile username rules; prefix,
  substring, fuzzy, recommendation, directory, and all-user search are excluded.
- Discovery excludes the current user, incomplete profiles, and any pair with an
  active block in either direction. At most one result is returned, containing
  only the target profile ID, username, and display name.
- Invalid username syntax may be explained locally. A valid username that is
  absent or unavailable because of blocking produces the same generic not-found
  or unavailable result and never reveals who blocked whom.
- Blocking is an independently directional, silent action. Either person's active
  block creates symmetric separation for discovery, contact, friend
  requests, public profiles, public templates, and community feeds.
- A user can privately list and remove only blocks they created. Blocking and
  unblocking are idempotent; unblocking removes only the caller's outgoing block,
  restores no relationship, and permits discovery again only after neither
  directional block remains.
- The blocker may see the username and display name associated with their own
  outgoing blocks only through the private blocked-users management contract.
- An active block in either direction makes the relationship-summary contract
  return no row at all. It does not return an `unavailable` row or any target
  profile fields; the private outgoing-block contract remains the only exception.
- Friend requests are directional while friendship is mutual rather than
  follower-based. Each unordered profile pair has one persistent, versioned
  current relationship row with a physical state of `pending`, `friends`,
  `cancelled`, `declined`, or `ended`; requests and friendships are not separate
  tables and this slice keeps no relationship event log.
- A pending row identifies the current requester. The most recent requester is
  retained internally after a transition for authorization and idempotency, but
  is not exposed unnecessarily. Declined and ended rows identify the participant
  who controls reopening.
- Duplicate sends and repeated already-completed caller-authorized actions are
  idempotent. Crossed pending requests atomically become friendship. The requester
  may cancel, the recipient may accept or decline, either friend may end the
  friendship, and requests do not automatically expire in the initial design.
- Either participant may send again after cancellation. Only the participant who
  declined or ended a friendship may initiate the next request after that outcome.
  Blocking a pending request changes it to cancelled and permits either participant
  to send again after all blocks are removed. Blocking friends changes the state to
  ended with the blocker controlling reopening. Unblocking never restores a
  request or friendship.
- Every real relationship transition increments a positive, monotonically
  increasing version and updates a server-owned state-change timestamp. Duplicate
  no-ops change neither value, and stale conflicting actions fail without
  overwriting newer state.
- A send from a first-load or preloaded result may omit an expected version for
  first, duplicate-pending, or crossed-pending behavior. Reopening a cancelled,
  declined, or ended row requires its exact current version. If that send has
  already reopened the row to pending, the same sender's retry and the opposite
  participant's crossed send may reuse the immediately prior dormant version;
  materially older versions remain stale.
- Client-facing relationship results use caller-relative states such as `can-send`,
  `incoming-pending`, `outgoing-pending`, `friends`, or `unavailable`. They do not
  reveal raw declined/ended state or the reopening controller to the other
  participant. `unavailable` is the privacy-safe dormant-state projection; active
  blocks suppress the entire relationship and profile projection instead.
- Only the current row, version, creation and state-change times, most recent
  requester, and reopening controller are retained. Detailed audit history is not
  introduced; implemented account hard deletion cascades this current row.
- The relationship row remains the authoritative friendship action state; the
  retained list-access row independently remains authoritative for invitations.
- A user's public templates can be viewed from that user's profile.
- The community feed shows recent public templates from accepted friends.
- Blocking applies the symmetric shared-list separation rules in the active/shared
  list section. Friendship ending alone preserves accepted list membership.
  Reporting, moderation, evidence retention, and appeals remain future work.

### Split expense ledger

- Split is an optional expense ledger inside a main list, not payment processing.
  Only the current owner can enable it. An enabled list has exactly one validated
  currency: this slice supports `CHF` and `EUR`, both with two decimal minor-unit
  digits. The owner may change currency only while no expense exists and no
  settlement history has ever existed. The first recorded settlement permanently
  locks the list's currency, even after reversal.
- Expenses store and calculate positive amounts as integer minor units only.
  Descriptions are trimmed to 1-120 characters, amounts are `1` through
  `999999999` minor units, and a list may contain at most 200 current expenses.
  Physical expense deletion immediately frees capacity; existing over-capacity
  data remains readable/editable/deletable but cannot grow.
- The owner and current accepted, unblocked members may create, edit, and delete
  expenses while the list is active. Archived lists retain readable Split history
  and balances but reject every Split mutation. These operations create no
  persistent notification or unread-badge change.
- A new expense has one eligible current payer and a non-empty subset of eligible
  current participants. The payer need not be a beneficiary. PR #14 supports only
  equal splitting; custom amounts and percentages remain future work.
- For total `A` and `N` selected participants, each share begins at
  `floor(A / N)`. The first `A mod N` participants in ascending immutable
  list-scoped participant-ID order receive one additional minor unit. Explicit
  stored shares therefore sum exactly to the expense total and are stable across
  devices.
- A participant's authoritative balance is expense total paid minus expense total
  owed, plus non-reversed settlements paid and minus non-reversed settlements
  received. Positive means they are owed money, negative means they owe money, and
  zero means settled up. Balances are derived rather than stored, never display
  negative zero, and always sum exactly to zero for the list.
- Split retains a list-scoped participant identity and display snapshot separately
  from live membership. Removing a member preserves their understandable identity,
  expenses, shares, and paid/owed totals. A removed person cannot enter a new
  expense; an edit may retain only their associations already on that expense.
  Once removed from that expense they cannot be re-added until accepted again.
  Reaccepting the same account reuses its existing list identity. Permanent account
  deletion instead clears the snapshots and live link, leaving a localized generic
  deleted-participant identity and preserving arithmetic without retaining deleted
  profile data. A member accepted after Split is enabled receives or reuses exactly
  one financial identity and becomes eligible without re-enabling Split.
- Creates use a payload-bound request UUID for safe lost-response retries. Creates,
  edits, and deletes are atomic, version checked, and reconcile stale
  membership, archive, deletion, and concurrent changes to authoritative state.
  Private account Realtime invalidations refresh mounted Split projections and
  forms; manual refresh and resume reconciliation remain available.
- A settlement records external bookkeeping only; List & Split never initiates,
  proves, or processes a payment. A current unblocked owner or accepted member may
  record a full or partial settlement between any same-list debtor and creditor,
  including a removed or anonymized historical participant. The server derives
  and exposes the recorder identity. The payer must currently have a negative
  balance, the recipient a positive balance, and the positive integer amount may
  not exceed the smaller authoritative outstanding side. It has no separate
  expense-size cap. An optional trimmed note is at most 120 characters.
- Settlements are immutable and cannot be edited or deleted. The original recorder
  or current owner may append exactly one full reversal; a reversal derives the
  opposite direction and original amount and requires a trimmed 1-120-character
  reason. A current member cannot reverse another recorder's settlement. A
  reversal remains allowed after later ledger changes so incorrect history can be
  corrected without rewriting it.
- Suggested payments are derived server-side from current integer balances.
  Debtors are ordered by largest absolute debt then participant UUID, creditors by
  largest receivable then participant UUID, and each step transfers the smaller
  remaining side before advancing a zeroed participant. The output is stable and
  conserves every minor unit, but is not guaranteed or described as a
  mathematically minimum transaction set.
- Existing expense create/edit/delete permissions remain unchanged after
  settlements exist. Every accepted expense, settlement, or reversal mutation
  immediately recomputes authoritative balances and suggestions without rewriting
  settlement history.
- Settlement history has no lifetime row cap and is fetched newest-first in
  bounded deterministic keyset pages. Archived lists keep balances, suggestions,
  and history readable but reject settlement/reversal writes. List deletion
  cascades the ledger; account deletion anonymizes surviving participant and
  recorder references without changing arithmetic.
- Settlement and reversal creates use payload-bound request UUIDs, exact expected
  Split versions, server-side serialization, and atomic validation. Stale,
  duplicate-conflict, concurrent, archived, deleted, or unauthorized requests add
  no partial row, advance no version, and emit no invalidation. Identical
  lost-response retries are idempotent. There is no offline mutation queue;
  transport failure preserves safe retry and authoritative refresh behavior.
- Successful settlement/reversal writes recalculate balances and suggestions
  immediately and send the existing content-free private account invalidation to
  current accepted accounts. They create no persistent notification or unread
  badge. Duplicate invalidations are harmless and must not duplicate navigation,
  messages, or submission state.
- The Split UI localizes participant, direction, currency, history, reversal, and
  error text. Payment direction and reversed state are not conveyed by color alone;
  controls have semantic labels, remain scrollable with large system text, and use
  the existing Material 3 light/dark themes.
- Custom shares, conversion, guests, receipts, categories, charts, recurring
  expenses, payment-provider integration, recipient approval/disputes, attachments,
  backdating, and a mathematically minimum solver remain deferred.

### Notifications and actionable requests

- The app has a persistent in-app notification centre.
- Every real friend-request transition into `pending` creates one persistent
  notification for the recipient and relationship version. Duplicate sends and
  crossed sends do not create another notification; reopening an eligible dormant
  relationship creates one for its new pending version. Existing relationship
  history is not backfilled.
- The relationship row, not the notification, remains authoritative. Accept and
  Decline use its exact expected version, so duplicate taps, retries, and stale
  notifications cannot overwrite newer state.
- Notifications do not copy usernames, display names, email, Auth metadata, or
  arbitrary messages. The visible actor's minimal profile is resolved through a
  block-aware server contract.
- The centre lists visible notifications newest first with bounded deterministic
  keyset pagination. Successfully displaying a page marks only those displayed
  notification IDs read, and repeated marking is safe.
- The bell badge counts the current recipient's unread, unsuppressed, unexpired,
  block-visible notifications.
- Blocking in either direction permanently suppresses existing notifications
  between that pair in the same transaction. Unblocking never restores them.
- Notifications expire logically exactly 180 days after creation and are then
  omitted from listing and badge counts. Physical cleanup remains a documented
  pre-production follow-up and no scheduled deletion is introduced here.
- Templates sent by friends remain an accepted future actionable type requiring
  Accept or Decline. Active-list invitation actions are implemented.
- Users receive informational notifications for new item assignments and note
  mentions.
- A successful ownership transfer creates one informational notification for the
  new owner without copying profile or list text into the notification row.
- User-facing archive, delete, mark-unread, preference, and notification-history
  controls are not part of the friend-request slice.
- Push notifications are planned for a later phase using Firebase Cloud Messaging
  and Apple Push Notification service.
- Creating a Firebase project requires separate explicit authorization.

### Navigation

The four primary destinations are:

1. Lists
2. Templates
3. Community
4. Profile

The implemented signed-in shell preserves an independent navigation stack for each
destination. Lists and private Templates have dedicated flows, while the existing
Community and Profile flows live in their respective tabs. The
notification centre is opened above the shell from a bell affordance and is not a
primary tab.
Authentication uses the mobile callback
`com.ferbatech.listandsplit://auth-callback`. The application resolves backend
configuration, authentication, email verification, and profile onboarding before
allowing access to an authenticated destination. Notification links and later
feature deep-link contracts remain open.

## Cross-cutting behavior

### Privacy and authorization

- Private templates are not community content.
- Shared-list data is available only to authorized members and relevant invitees.
- Friendship, invitation, notification, and ledger data is disclosed only to the
  users who require it.
- PostgreSQL Row Level Security is a mandatory server-side authorization layer; UI
  visibility is not an authorization control.
- The profile table remains owner-only. Cross-user identity is disclosed only by
  narrow block-aware contracts that return the approved minimal profile fields.
- Blocks apply symmetrically to discovery and contact even though each block record
  is directional, and atomically apply the accepted shared-list separation rules.
- Reporting and moderation are required before the public-content experience is
  considered mature, but their detailed behavior is not yet designed.

### Reliability and offline direction

- Repositories are the app's data source of truth.
- Private Broadcast is receive-only and best-effort. Reconnection and app resume
  always reconcile through authoritative RPCs; event delivery is not a durable
  history or a guarantee.
- Local SQLite caching is planned later to make active-list usage tolerant of
  intermittent connectivity.
- Offline edits, synchronization ordering, and conflict resolution must be decided
  and tested before offline mutation is advertised.

### Accessibility and localization

- Material 3 light and dark themes are part of the application foundation.
- User-facing strings should be centralized/localization-ready even while English
  is the only initial language.
- New flows should support semantic labels, scalable text, adequate contrast, and
  non-color-only state cues.

## Explicit non-goals and deferrals

- No real payment initiation, wallet, card processing, or money custody.
- No follower model.
- No fifth navigation tab for notifications.
- No social providers, anonymous authentication, or magic-link-only
  authentication in the initial release.
- No cross-user profile discovery before block-aware access rules exist.
- No avatar upload or Storage bucket in the initial profile slice.
- No production Supabase or Firebase project without separate explicit
  authorization.
- No promise of fully offline operation until cache and conflict rules are defined.
- No Presence, Broadcast Replay, Postgres Changes subscription, client-originated
  Broadcast, or push delivery is part of the implemented Realtime contract.

## Open product decisions

These decisions are intentionally unresolved; implementations must not silently
choose them:

- Note mention parsing, eligibility, editing, and notification deduplication.
- A support or administrator correction process for immutable usernames, including
  its authorization and audit requirements.
- Avatar storage, upload validation, privacy, replacement, and deletion lifecycle.
- Public-template copied visibility/category defaults, attribution and provenance
  display, and community-feed ranking/retention.
- Invitation and sent-template expiry, revocation, and idempotent re-acceptance.
- Exact custom-share validation.
- Notification archive/delete/preferences, future types, push-safe payloads,
  physical cleanup, and account-lifecycle retention beyond the accepted
  friend-request behavior.
- Reporting scope, moderation workflow, evidence retention, and appeal behavior.
- Offline conflict resolution and which operations are permitted while offline.
- Shared-resource ownership/deletion, administrator-initiated deletion,
  moderation retention, Storage cleanup, and legal/compliance export obligations
  beyond the accepted current-aggregate account lifecycle.
- Which additional locales ship first.
