# List & Split product specification

## Purpose and implementation status

List & Split is an Android and iOS application that combines collaborative active
lists, reusable list templates, a friends-based community, and an optional expense
ledger.

This document records the agreed product direction. It is not a statement that the
features below are implemented. The bootstrap phase establishes only the Flutter
foundation, development workflow, and Supabase development infrastructure; product
features and the business database schema are planned work.

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

- A user can be found by a unique username.
- A user can send, accept, or decline a friend request.
- An accepted request creates a mutual friendship; it does not create a one-way
  follower relationship.
- Only accepted friends can be invited to a shared active list.
- A user's public templates can be viewed from that user's profile.
- The community feed shows recent public templates from accepted friends.
- Public content must eventually support user blocking and content/user reporting.

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
- The bootstrap phase does not create a Firebase project.

### Navigation

The four primary destinations are:

1. Lists
2. Templates
3. Community
4. Profile

The notification centre is opened from a bell affordance and is not a primary tab.
Route and deep-link details have not yet been specified.

## Cross-cutting behavior

### Privacy and authorization

- Private templates are not community content.
- Shared-list data is available only to authorized members and relevant invitees.
- Friendship, invitation, notification, and ledger data is disclosed only to the
  users who require it.
- PostgreSQL Row Level Security is a mandatory server-side authorization layer; UI
  visibility is not an authorization control.
- Blocking and reporting are required before the public-content experience is
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
- No production Supabase project or business schema in the bootstrap phase.
- No Firebase project or push delivery in the bootstrap phase.
- No promise of fully offline operation until cache and conflict rules are defined.

## Open product decisions

These decisions are intentionally unresolved; implementations must not silently
choose them:

- List ownership/administrator roles, member removal, leaving, archive, and delete
  semantics.
- Item quantity precision, validation, unit vocabulary, ordering, and duplicate
  handling.
- Note mention parsing, eligibility, editing, and notification deduplication.
- Username normalization, case sensitivity, rename policy, and profile privacy.
- Friend-request cancellation, expiry, retry, and behavior after blocking.
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
- Authentication methods, account deletion/export policy, and initial additional
  locales.
