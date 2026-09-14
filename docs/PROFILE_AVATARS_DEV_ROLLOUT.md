# Profile avatars: proposed Dev rollout

This is a reviewable plan, not deployment authorization or a record of deployment.
Both PRs remain draft/unmerged. The Samsung and emulator retain the PR #33 client;
the avatar-enabled client must not connect to hosted Dev before this rollout is
separately reviewed and authorized. Production is outside scope.

## Exact source and order

The sole new migration relative to the completed PR #33 base is
`supabase/migrations/20260907221034_profile_avatars.sql`. It creates the private
`profile-avatars` bucket, forced-RLS avatar metadata/file ledger and exact read and
server-only fenced-operation RPCs. It also replaces the existing account-deletion
coordinator to anonymize owned/surviving Split identities before FK actions. It
does not rewrite historical migrations, money rules, retention or Chat schema.

Use the final reviewed `codex/profile-avatars` SHA, which includes PR #33 SHA
`56273306eaf5fba23241ff174a46042ed639ece4`. Record the avatar SHA and artifact hashes
in the deployment record before proceeding. Preserve any newer remote work.

1. **Preflight, after authorization:** verify the target is **List & Split Dev**,
   project reference **`lzwsgxziqxpxwyalkfuy`**, and compare the actual applied
   migration history with the reviewed branch. Stop for any unexpected pending
   migration or drift; do not run a broad push that would apply extra migrations.
   Review the migration diff, both function bundles/locks, CI/local integration
   evidence, current backup/recovery arrangements and private bucket limits.
   This task has not accessed the hosted project's state.
2. **Apply only `20260907221034_profile_avatars.sql`.** Use the repository's reviewed
   migration process with an explicit Dev target. No reset, destructive repair,
   manual Dashboard-only schema change or retention invocation is authorized.
3. **Deploy the updated `delete-account` function first.** Its entry point is
   `supabase/functions/delete-account/index.ts`; include its handler/adapters,
   pinned `deno.json`/`deno.lock`, and imported shared avatar service/PNG modules.
   The authenticated wrapper derives the caller. Existing confirmation and fresh
   session validation run before fenced Storage cleanup, then caller-only hard
   Auth deletion. Cleanup failure preserves the account for retry; the image may
   already be gone. Keep the config's `verify_jwt = false` for the verified-user
   SDK wrapper; this is not an unauthenticated endpoint.
4. **Deploy `profile-avatar`.** Entry point
   `supabase/functions/profile-avatar/index.ts`, with `handler.ts`, its pinned
   dependency/lock files and `supabase/functions/_shared/avatar_service.ts` and
   `avatar_png.ts`. Preserve the same verified-user wrapper/config. GET resolves
   current contextual authorization before and after downloading private bytes;
   PUT/DELETE require exact version/request UUID; POST exports only the caller's
   v13 document. No public/signed URLs or direct client Storage grants.
5. **Verify the backend before distributing the client.** Use separately
   authorized disposable Dev test accounts and sanitized test images. Only after
   the checks below pass, build the Dev client from the reviewed avatar SHA and
   update the Dev package in place, retaining app data and signing identity.

The safe interval between steps 2 and 4 has no avatar upload client. Never deploy
the upload endpoint/client before the avatar-aware deletion service is in place.

## Verification required before client distribution

- Confirm the bucket remains private, capped at 327680 bytes per PNG, and the
  database's at-most-current-plus-staged/retired ledger invariant is enforced.
  Confirm exact grants: authenticated read RPCs only; writes/ledger operations
  server-only; no public/anon/client Storage listing, read or write access.
- Verify missing/invalid authentication is rejected; valid users cannot substitute
  another owner, bypass blocks, enumerate objects or read inaccessible identities.
  Nonfriends with authorized public-profile access may see the current photo.
- Exercise valid upload, invalid/oversized/metadata-bearing PNG rejection,
  replacement/removal, stale version, duplicate request, concurrent writes,
  interrupted Storage calls and the recovery fence. Verify no historic thumbnail,
  original photo, EXIF/GPS, signed URL or other user's bytes appear in responses.
- Verify Chat uses visible message context and Split uses authorized participant
  context. Deleted/anonymized identities must return the generic fallback.
- Verify own export v13 and legacy v1-v12 compatibility, including onboarding
  export behavior. Verify disposable account deletion with both owned and surviving
  Split histories, and a simulated cleanup failure that preserves the account.
  Do not invoke real users' export or deletion as a smoke test.
- Review safe operational errors without tokens, bytes, object paths or personal
  payloads. Preserve `no-store`, `nosniff`, the binary response and MIME header.

## Recovery

Stop distribution and restore the previous UI client if necessary. Keep the
additive migration, file ledger, private bucket and avatar-aware deletion service
while any avatar files can exist. Do not roll back to the old delete-account
function, drop metadata/bucket, bypass leases or shorten the fifteen-minute fence.
Use a reviewed forward repair and authorized retry after the fence expires.
Do not claim Storage and the Auth transaction are atomically reversible.

Official worker limits checked on September 14 remain 150 seconds on Free,
400 seconds on paid plans and a 150-second request idle timeout; revalidate at
rollout. The 15-minute fence exceeds these limits. See
[Edge Function limits](https://supabase.com/docs/guides/functions/limits) and
[Auth deletion constraints](https://supabase.com/docs/guides/auth/managing-user-data#deleting-users).

## Remaining physical QA

After the authorized backend rollout, use disposable accounts on Samsung and the
emulator for gallery selection/cancellation, Add/Update/Remove, repeat taps,
replacement/removal on a second device, current Profile/Community/Chat/Split
photos, missing-photo initials, both-direction blocks, inaccessible identities,
account switching, offline/failed/uncertain operations and export/deletion recovery.
Repeat English/Portuguese, light/dark, large text and TalkBack. iOS gallery
permission/cancellation remains a separate native gate. No template images.

PR #33's general positive visual feedback and its bounded Samsung dropdown/icon
checks do not establish that this avatar QA or all prior functional/accessibility
checks passed. Windows-local backend testing needs the WSL restart/Docker engine;
isolated CI backend results are separate evidence, not Samsung physical QA.

The next hosted action requires explicit authorization for this exact Dev migration,
the two functions in the stated order, disposable-account verification and then
the avatar-enabled Dev client update. No hosted step is performed by this plan.
