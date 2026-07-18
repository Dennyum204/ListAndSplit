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

- After basic blocking is available, a user can be found by a unique username
  through a block-aware discovery contract.
- A user can send, accept, or decline a friend request.
- An accepted request creates a mutual friendship; it does not create a one-way
  follower relationship.
- Only accepted friends can be invited to a shared active list.
- A user's public templates can be viewed from that user's profile.
- The community feed shows recent public templates from accepted friends.
- Basic blocking must be delivered in Phase 1 before friend discovery and requests.
  Detailed block effects and content/user reporting still require separate design.

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
- Friend requests, active-list invitations, and templates sent by friends are
  actionable and require Accept or Decline.
- Users receive informational notifications for new item assignments and note
  mentions.
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
- The initial profile capability exposes no cross-user reads. Basic blocking must
  precede friend discovery and requests; its effects on existing relationships,
  shared resources, and future public content are not yet designed.
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
- Friend-request cancellation, expiry, retry, crossed/duplicate-request behavior,
  unfriending, and the detailed effects of blocking.
- Template/category ordering, copy visibility defaults, version/provenance display,
  and feed ranking/retention.
- Invitation and sent-template expiry, revocation, and idempotent re-acceptance.
- Supported currencies, currency immutability after ledger use, equal-split
  remainder allocation, expense correction, settlement reversal, and debt
  simplification rules.
- Notification retention, read/archive behavior, badge counts, and push preferences.
- Blocking/reporting scope, moderation workflow, evidence retention, and appeal
  behavior.
- Offline conflict resolution and which operations are permitted while offline.
- Account deletion/export, retention and re-registration behavior, and initial
  additional locales.
