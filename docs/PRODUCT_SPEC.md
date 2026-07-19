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
- Payment Control records expenses and settlements; it does not move real money.
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

- Account export and permanent account deletion are separate vertical slices.
  Export ships first and deletion remains planned until export is merged and
  manually verified.
- Any signed-in user with a verified email can download their data, including
  while profile onboarding is incomplete. The action is available from completed
  Profile and verified incomplete Onboarding; it does not weaken the existing
  configuration, authentication, or email-verification gates.
- **Download my data** produces one UTF-8 JSON document with product identifier,
  positive export schema version (initially `1`), server-generated UTC export
  time, the caller's allowlisted Auth identity and profile fields, outgoing
  blocks, active caller-visible relationships, and currently visible recipient
  notifications. Collections are deterministic arrays and are empty rather than
  null.
- The export includes nullable onboarding fields faithfully. It includes only the
  existing caller-visible block, relationship, and notification projections, so
  either-direction block suppression, dormant relationship privacy, notification
  suppression, and 180-day logical expiry remain authoritative.
- The export never includes passwords or hashes, tokens, sessions, raw Auth
  metadata, another person's email or Auth data, incoming blocks, raw dormant
  relationship state, reopening/requester internals, suppressed/expired/
  block-hidden notifications, server logs, security records, or unimplemented
  lists, templates, and ledger data.
- Export is generated synchronously on demand and returned to the caller. The
  server retains no export file or export record. The mobile app validates and
  pretty-prints the versioned document, writes it to OS-managed temporary/cache
  storage with a non-identifying UTC filename, and opens the native share sheet.
  Temporary cache cleanup is not guaranteed secure deletion.
- This is a product-level account-data download. It is not a claim of complete
  legal or regulatory data-portability compliance; those obligations remain open
  for explicit review.
- A later deletion slice will implement immediate permanent hard deletion after
  exact username confirmation for completed profiles or exact email confirmation
  for incomplete profiles, current-password reauthentication, and proof of a
  session no older than ten minutes. A future authenticated `delete-account` Edge
  Function will use a server-only privileged client, cascade the currently
  implemented profile/social/notification records, reserve a completed canonical
  username for 30 days without retaining email or user ID, and invalidate other
  sessions on subsequent validation.
- Re-registration after deletion creates a new identity and restores no prior
  data or relationships. Every future list, template, Storage, and ledger
  aggregate must extend the reviewed deletion rules before it ships. Hosted
  deletion QA will use a separately authorized disposable account and must never
  delete Fernando or Susana.

### Active and shared lists

- A user can create an active list.
- The creator can invite accepted friends. A non-friend cannot be invited.
- Members can add, edit, complete, and delete list items.
- An item has a quantity and may have a unit.
- An item can be assigned to more than one list member.
- A list has a general note that supports `@mentions` of relevant users.
- Payment Control can be enabled per active list. It is unavailable outside active
  lists and absent from lists where it is not enabled.

Detailed ownership roles, member removal, archival, and concurrent-edit behavior
are not yet decided.

### Templates

The product term is **Templates**; the former name **Internal Lists** should not be
used in new UI or documentation.

- A template contains reusable groups of items.
- A template is private or public.
- Users organize templates into their own personal categories.
- Adding a template to an active list creates a snapshot copy of its items. Future
  edits or deletion of the template cannot alter already imported items.
- Saving another user's public template creates a new, independent template owned
  by the recipient.
- Accepting a template sent by a friend likewise creates an independent copy owned
  by the recipient.
- Public templates are visible on user profiles and may appear in friends'
  community feeds.

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
  introduced; accepted account hard-deletion cleanup remains a later slice.
- The relationship row remains the authoritative action state when persistent
  friend-request notifications are added. Realtime, push delivery, public
  profiles, shared lists, and the final four-tab shell remain separate slices.
- Only accepted friends can be invited to a shared active list.
- A user's public templates can be viewed from that user's profile.
- The community feed shows recent public templates from accepted friends.
- Blocking effects on existing or future shared resources, including active-list
  membership, remain unresolved and must be decided before shared lists ship.
  Reporting, moderation, evidence retention, and appeals remain future work.

### Payment Control

- Payment Control is an expense ledger inside an active list where it has been
  enabled. It is explicitly not payment processing.
- Each Payment-Control-enabled list uses exactly one currency.
- An expense records one payer and a selected set of participating list members.
- Expenses support equal splitting and exact custom shares.
- All amounts and shares use integer minor units. Values such as binary
  floating-point `double` amounts are invalid at every layer.
- Members can record settlements between list members.
- Authoritative balance and debt calculations run server-side and are covered by
  unit tests.

Currency support, equal-split remainder allocation, editing/reversal rules, and
the presentation of simplified debts remain open decisions.

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
- Active-list invitations and templates sent by friends remain accepted future
  actionable types requiring Accept or Decline.
- Users receive informational notifications for new item assignments and note
  mentions.
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

The notification centre is opened from a bell affordance and is not a primary tab.
Authentication uses the mobile callback
`com.ferbatech.listandsplit://auth-callback`. The application resolves backend
configuration, authentication, email verification, and profile onboarding before
allowing access to an authenticated destination. The final signed-in route tree,
restoration, notification links, and feature deep links remain open.

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
- Blocks apply symmetrically to discovery and future community contact even though
  each block record is directional. Effects on existing shared resources remain
  unresolved.
- Reporting and moderation are required before the public-content experience is
  considered mature, but their detailed behavior is not yet designed.

### Reliability and offline direction

- Repositories are the app's data source of truth.
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

## Open product decisions

These decisions are intentionally unresolved; implementations must not silently
choose them:

- List ownership/administrator roles, member removal, leaving, archive, and delete
  semantics.
- Item quantity precision, validation, unit vocabulary, ordering, and duplicate
  handling.
- Note mention parsing, eligibility, editing, and notification deduplication.
- A support or administrator correction process for immutable usernames, including
  its authorization and audit requirements.
- Avatar storage, upload validation, privacy, replacement, and deletion lifecycle.
- The effects of blocking or ending a friendship on existing shared resources,
  including active-list membership and invitations.
- Template/category ordering, copy visibility defaults, version/provenance display,
  and feed ranking/retention.
- Invitation and sent-template expiry, revocation, and idempotent re-acceptance.
- Supported currencies, currency immutability after ledger use, equal-split
  remainder allocation, expense correction, settlement reversal, and debt
  simplification rules.
- Notification archive/delete/preferences, future types, push-safe payloads,
  physical cleanup, and account-lifecycle retention beyond the accepted
  friend-request behavior.
- Reporting scope, moderation workflow, evidence retention, and appeal behavior.
- Offline conflict resolution and which operations are permitted while offline.
- Shared-resource ownership/deletion, administrator-initiated deletion,
  moderation retention, Storage cleanup, and legal/compliance export obligations
  beyond the accepted current-aggregate account lifecycle.
- Which additional locales ship first.
