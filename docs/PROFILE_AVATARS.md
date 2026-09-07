# Private profile avatars

## Approved contract (2026-09-08)

P-060: Fernando selected an optional current gallery photograph, replacement and
removal, used on existing authorized identity surfaces including Profile, Chat
and Split. Any verified, completed caller authorized to view a profile may view
its current avatar. Friendship is not required; either-direction blocks deny
access. No anonymous URL, historical photograph snapshot, new Chat identity
field, camera, list cover, template image or category-icon feature is included.

Fernando explicitly approved deleting the photograph before deleting the Auth
account. A failure preserves the account for retry, but its photograph may already
have been removed. The existing confirmation, fresh-session check, caller-only
hard deletion and database anonymization remain mandatory.

A-075: A private Storage bucket holds bounded canonical 256x256 PNG thumbnails.
Gallery input is resized and re-encoded locally; the server independently checks
the complete PNG structure, CRCs, dimensions, decompressed size and filters and
rejects metadata, animation and trailing content. Original images and EXIF/GPS
are never uploaded. Neither signed URLs nor direct client Storage access is used.
The authenticated SDK Edge boundary serves bytes only after contextual SQL
authorization and rechecks authorization after downloading. Chat resolves the
sender through a visible message ID, never a new exposed profile UUID.

All writes are server-only and share a database-issued, fenced operation lease.
Short transactions serialize one owner's replace/remove/export/account-deletion
work; no database transaction spans a Storage call. Every possible uploaded key
is recorded durably before upload. Non-current files are inaccessible and cleaned
before subsequent writes/deletion. The ledger restricts profile deletion until
Storage cleanup succeeds. A crashed/uncertain operation fails closed for fifteen
minutes before recovery; this exceeds the hosted worker limit of 400 seconds and
request idle timeout of 150 seconds. Revalidate these limits before rollout.
There is no scheduled background cleanup or claimed automatic physical purge of
interrupted uploads. At most one current and one staged/retired image are allowed.
Removal and account deletion clean both, with retries, before confirming success.

The current sanitized photograph is included only in its owner's transient export
v13, assembled by the authenticated Edge endpoint from unchanged export v12 plus
the own image. Export RPCs and document versions 1-12 remain compatible. No other
person's image, asset path or bearer URL enters an export.

## Delivery and rollout gates

This is a separate draft feature stacked on PR #33, not a deployment. The reviewed
additive migration, avatar Edge Function and updated delete-account Edge Function
must be rolled out together under separate environment authorization before the
new client is distributed. Old clients retain their existing profile/export APIs.
Never deploy a client alone or roll back delete-account while avatar files exist.
Production remains untouched. No Cron job, notification type or Realtime topic
is added; existing opaque account invalidations and authoritative refresh are used.

Before release, test two different accounts for replacement/removal, blocking in
both directions, public-profile access without friendship, Chat/Split anonymity,
offline recovery, repeated submissions, account switching, export and failed
account deletion after image removal. Test EN/PT, light/dark, TalkBack, large text
and Android gallery cancellation. iOS photo-library permission requires native QA.

## Database and transport contracts

- Authenticated only: `get_own_profile_avatar()` and
  `resolve_profile_avatar(text, uuid)`. Both derive the caller from the existing
  verified completed-profile boundary; unknown/blocked targets return no image.
- Server only: `begin_profile_avatar_operation(uuid,uuid,text,bigint)`,
  `stage_profile_avatar_file(uuid,uuid)`,
  `forget_profile_avatar_file(uuid,uuid,uuid)`,
  `commit_profile_avatar(uuid,uuid,uuid,uuid,text)` and
  `finish_profile_avatar_operation(uuid,uuid)`. `PUBLIC`, `anon` and
  `authenticated` cannot execute these writes. Tables reject direct access.
- These narrow privileged functions are postgres-owned with empty search paths.
  The internal lease-lock helper uses invoker rights and has no API grants.
- `profile-avatar` uses the pinned `@supabase/server` authenticated-user wrapper
  with legacy `verify_jwt=false`, as does `delete-account`. User identity never
  comes from a request body. GET returns `application/octet-stream` for the pinned
  Flutter Functions client's binary decoder, with `x-avatar-content-type:
  image/png`, `no-store` and `nosniff`. PUT/DELETE require an exact version and
  request UUID; POST exports only the caller's v13 document.
- Current friends/list peers receive existing opaque account invalidations.
  Unknown nonfriend profile viewers refresh on resume/reload, not through a new
  public audience. Avatar providers clear on session change, reconciliation and
  disposal; no persistent avatar disk cache is introduced.

## Authorized account-deletion regression fix

Before this migration, deleting an Auth user who owned a Split-enabled list could
fail `active_list_split_participants_identity_state_check`: the profile FK set
only `profile_id` to null before the deeper owned-list cascade, leaving identity
snapshots non-null. This was reproduced on the pre-avatar migration history.
The new migration replaces only the existing deletion coordinator, includes owned
and surviving list parents in the same sorted lock set, and anonymizes all three
identity fields together before FK actions. No historical migration, expense RPC,
amount, share, settlement or reversal is rewritten.

## Local verification and operational recovery

Run the normal Flutter checks and both frozen Deno task suites. The local pgTAP
avatar suites exercise authorization, private catalog grants, version/request
guards, real concurrent sessions, expired-worker fencing, block/Chat visibility,
and account deletion with owned and surviving Split histories. Run all other
pgTAP suites after a clean local reset as regression protection.

`avatar.local.test.ts` is a separately invoked real local Storage/Auth/RPC smoke
test, not the network-free CI unit task. It accepts only loopback port 54321;
provide `AVATAR_LOCAL_URL`, `AVATAR_LOCAL_ANON` and `AVATAR_LOCAL_SERVICE` from
captured local CLI status without printing values, and remove these process
variables afterwards. It creates/deletes only its generated local fixture. A
failed uncertain smoke operation leaves the isolated fixture for diagnosis and a
local reset; never bypass a lease or apply this cleanup to a linked database.

For an authorized future rollout: verify exact environment/history first; apply
only this migration, deploy updated `delete-account`, then `profile-avatar`, and
only then distribute the client. Verify private bucket limits, exact grants,
failed direct Storage reads, successful current-image access and full deletion
using separately authorized disposable accounts. Do not invoke real users' exports
or deletion as a deployment smoke test. No environment is deployed by this PR.

Rollback is forward-only. Revert the new UI client first if needed, but retain the
avatar-aware deletion service and cleanup metadata while any file ledger exists.
Do not drop the bucket/tables or restore the old delete-account function around
existing avatars. Uncertain writes may require waiting for the fifteen-minute
recovery fence; repeated retries must not shorten it. Native gallery and iOS
permission behavior, two-device photo refresh and temporary Storage/Auth failures
remain required QA before distribution. No automated moderation of photos or
broader legal-compliance guarantee is implied by this feature.

The cross-service sequencing follows the official
[Auth deletion constraints](https://supabase.com/docs/guides/auth/managing-user-data#deleting-users)
and [Edge worker limits](https://supabase.com/docs/guides/functions/limits).
Storage and the Auth transaction cannot form one distributed atomic transaction;
the explicit pre-deletion warning and recoverable fence are intentional.
