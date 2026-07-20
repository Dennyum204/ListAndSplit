begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_table(
  'private',
  'deleted_username_reservations',
  'deleted username reservations use a private table'
);

select is(
  (
    select pg_catalog.array_agg(column_name::text order by ordinal_position)
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'deleted_username_reservations'
  ),
  array['canonical_username', 'reserved_until']::text[],
  'the reservation has only canonical username and expiry'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'deleted_username_reservations'
      and column_name in (
        'email',
        'user_id',
        'auth_user_id',
        'profile_id',
        'display_name',
        'created_at',
        'updated_at'
      )
  ),
  'the reservation stores no identity or copied former-profile columns'
);

select ok(
  (
    select relrowsecurity and relforcerowsecurity
    from pg_catalog.pg_class
    where oid = 'private.deleted_username_reservations'::regclass
  ),
  'the private reservation table enables and forces RLS'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'private'
      and tablename = 'deleted_username_reservations'
      and policyname =
        'deleted_username_reservations_reject_direct_client_access'
      and cmd = 'ALL'
      and qual = 'false'
      and with_check = 'false'
  ),
  1::bigint,
  'the private table has an explicit direct-client rejection policy'
);

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE')
  and not has_schema_privilege('authenticated', 'private', 'USAGE')
  and not has_schema_privilege('service_role', 'private', 'USAGE'),
  'Data API roles cannot use the private schema'
);

select ok(
  not has_table_privilege(
    'anon',
    'private.deleted_username_reservations',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.deleted_username_reservations',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'private.deleted_username_reservations',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'anon, authenticated, and service_role have no reservation privileges'
);

set local role anon;
select throws_like(
  $$select * from private.deleted_username_reservations$$,
  '%permission denied%private%',
  'anonymous direct reservation reads are denied'
);
reset role;

set local role authenticated;
select throws_like(
  $$select * from private.deleted_username_reservations$$,
  '%permission denied%private%',
  'authenticated direct reservation reads are denied'
);
reset role;

set local role service_role;
select throws_like(
  $$select * from private.deleted_username_reservations$$,
  '%permission denied%private%',
  'service-role direct reservation reads are denied'
);
reset role;

select is(
  (
    select count(*)
    from pg_catalog.pg_constraint
    where conname in (
      'profiles_id_fkey',
      'user_blocks_blocker_id_fkey',
      'user_blocks_blocked_id_fkey',
      'user_relationships_profile_low_fkey',
      'user_relationships_profile_high_fkey',
      'user_notifications_recipient_fkey',
      'user_notifications_actor_fkey',
      'user_notifications_relationship_fkey'
    )
      and contype = 'f'
      and confdeltype = 'c'
  ),
  8::bigint,
  'all eight current account-root foreign keys cascade'
);

select ok(
  (
    select prosecdef
      and proowner = 'postgres'::regrole
      and proconfig @> array['search_path=""']
    from pg_catalog.pg_proc
    where oid =
      'private.assert_username_available(text,uuid)'::regprocedure
  )
  and (
    select prosecdef
      and proowner = 'postgres'::regrole
      and proconfig @> array['search_path=""']
    from pg_catalog.pg_proc
    where oid = 'private.reserve_deleted_username()'::regprocedure
  )
  and (
    select prosecdef
      and proowner = 'postgres'::regrole
      and proconfig @> array['search_path=""']
    from pg_catalog.pg_proc
    where oid =
      'private.delete_expired_username_reservations()'::regprocedure
  ),
  'reservation helpers are postgres-owned hardened definer functions'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.assert_username_available(text,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.assert_username_available(text,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'private.assert_username_available(text,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.reserve_deleted_username()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.reserve_deleted_username()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'private.reserve_deleted_username()',
    'EXECUTE'
  ),
  'reservation trigger and availability helpers expose no client execution'
);

select is(
  (
    select count(*)
    from cron.job
    where jobname = 'list-and-split-delete-expired-username-reservations'
      and schedule = '17 3 * * *'
      and command =
        'select private.delete_expired_username_reservations();'
  ),
  1::bigint,
  'one stable daily 03:17 UTC cleanup job is migration managed'
);

select function_returns(
  'public',
  'validate_account_deletion',
  array['text'],
  'boolean',
  'the deletion validation RPC returns only boolean success'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'validate_account_deletion'
  ),
  1::bigint,
  'there is exactly one narrow deletion validation signature'
);

select ok(
  (
    select prosecdef
      and provolatile = 's'
      and proowner = 'postgres'::regrole
      and proconfig @> array['search_path=""']
    from pg_catalog.pg_proc
    where oid = 'public.validate_account_deletion(text)'::regprocedure
  ),
  'deletion validation is a stable postgres-owned hardened definer RPC'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.validate_account_deletion(text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.validate_account_deletion(text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.validate_account_deletion(text)',
    'EXECUTE'
  ),
  'only authenticated can execute the exact validation signature'
);

insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at,
  last_sign_in_at
)
values
  ('11111111-1111-4111-8111-111111111111', 'delete-complete@example.test', now(), now(), now(), now()),
  ('22222222-2222-4222-8222-222222222222', 'survivor-one@example.test', now(), now(), now(), now()),
  ('33333333-3333-4333-8333-333333333333', 'survivor-two@example.test', now(), now(), now(), now()),
  ('44444444-4444-4444-8444-444444444444', 'survivor-three@example.test', now(), now(), now(), now()),
  ('55555555-5555-4555-8555-555555555555', 'delete-incomplete@example.test', now(), now(), now(), now()),
  ('66666666-6666-4666-8666-666666666666', 'claimant@example.test', now(), now(), now(), now()),
  ('77777777-7777-4777-8777-777777777777', 'unverified@example.test', null, now(), now(), now()),
  ('88888888-8888-4888-8888-888888888888', 'missing-profile@example.test', now(), now(), now(), now());

update public.profiles
set username = case id
      when '11111111-1111-4111-8111-111111111111' then 'delete_me'
      when '22222222-2222-4222-8222-222222222222' then 'survivor_one'
      when '33333333-3333-4333-8333-333333333333' then 'survivor_two'
      when '44444444-4444-4444-8444-444444444444' then 'survivor_three'
      when '77777777-7777-4777-8777-777777777777' then 'unverified_user'
      when '88888888-8888-4888-8888-888888888888' then 'missing_user'
    end,
    display_name = case id
      when '11111111-1111-4111-8111-111111111111' then 'Delete Me'
      when '22222222-2222-4222-8222-222222222222' then 'Survivor One'
      when '33333333-3333-4333-8333-333333333333' then 'Survivor Two'
      when '44444444-4444-4444-8444-444444444444' then 'Survivor Three'
      when '77777777-7777-4777-8777-777777777777' then 'Unverified User'
      when '88888888-8888-4888-8888-888888888888' then 'Missing User'
    end
where id not in (
  '55555555-5555-4555-8555-555555555555',
  '66666666-6666-4666-8666-666666666666'
);

insert into public.user_blocks (blocker_id, blocked_id)
values
  ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222'),
  ('33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111'),
  ('33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444');

insert into public.user_relationships (
  profile_low_id,
  profile_high_id,
  state,
  requester_id,
  version
)
values
  ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'friends', '22222222-2222-4222-8222-222222222222', 3),
  ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'pending', '33333333-3333-4333-8333-333333333333', 4),
  ('33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444', 'friends', '44444444-4444-4444-8444-444444444444', 5);

insert into public.user_notifications (
  id,
  recipient_id,
  actor_id,
  notification_type,
  relationship_low_id,
  relationship_high_id,
  relationship_version
)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'friend_request', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 3),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 'friend_request', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 3),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'friend_request', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 4),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444', 'friend_request', '33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444', 5);

insert into auth.sessions (id, user_id, created_at, updated_at)
values
  ('10000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', now() - interval '5 minutes', now()),
  ('10000000-0000-4000-8000-000000000002', '22222222-2222-4222-8222-222222222222', now() - interval '5 minutes', now()),
  ('10000000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', now() - interval '11 minutes', now()),
  ('10000000-0000-4000-8000-000000000004', '55555555-5555-4555-8555-555555555555', now() - interval '5 minutes', now()),
  ('10000000-0000-4000-8000-000000000005', '77777777-7777-4777-8777-777777777777', now() - interval '5 minutes', now()),
  ('10000000-0000-4000-8000-000000000006', '88888888-8888-4888-8888-888888888888', now() - interval '5 minutes', now());

delete from public.profiles
where id = '88888888-8888-4888-8888-888888888888';

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';
set local "request.jwt.claims" = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"10000000-0000-4000-8000-000000000001","iat":4102444800}';

select is(
  public.validate_account_deletion('delete_me'),
  true,
  'a completed profile with exact username and fresh matching session validates'
);

select throws_ok(
  $$select public.validate_account_deletion('Delete_Me')$$,
  '22023',
  'account deletion confirmation mismatch',
  'completed confirmation is case sensitive'
);

select throws_ok(
  $$select public.validate_account_deletion(' delete_me ')$$,
  '22023',
  'account deletion confirmation mismatch',
  'completed confirmation preserves whitespace exactly'
);

set local "request.jwt.claims" = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"10000000-0000-4000-8000-000000000002","iat":4102444800}';
select throws_ok(
  $$select public.validate_account_deletion('delete_me')$$,
  '55000',
  'recent authentication required',
  'a session belonging to another user cannot validate deletion'
);

set local "request.jwt.claims" = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"10000000-0000-4000-8000-000000000009","iat":4102444800}';
select throws_ok(
  $$select public.validate_account_deletion('delete_me')$$,
  '55000',
  'recent authentication required',
  'a nonexistent or revoked session cannot validate deletion'
);

set local "request.jwt.claims" = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"10000000-0000-4000-8000-000000000003","iat":4102444800}';
select throws_ok(
  $$select public.validate_account_deletion('delete_me')$$,
  '55000',
  'recent authentication required',
  'an eleven-minute-old session is rejected despite a future JWT iat'
);

reset role;

update auth.sessions
set refreshed_at = pg_catalog.now()::timestamp
where id = '10000000-0000-4000-8000-000000000003';

update auth.users
set last_sign_in_at = pg_catalog.now()
where id = '11111111-1111-4111-8111-111111111111';

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';
set local "request.jwt.claims" = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"10000000-0000-4000-8000-000000000003","iat":4102444800}';
select throws_ok(
  $$select public.validate_account_deletion('delete_me')$$,
  '55000',
  'recent authentication required',
  'token refresh and last sign-in timestamps cannot bypass session creation age'
);

set local "request.jwt.claims" = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
select throws_ok(
  $$select public.validate_account_deletion('delete_me')$$,
  '42501',
  'account authentication required',
  'a JWT without session_id cannot validate deletion'
);

set local "request.jwt.claims" = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"not-a-uuid"}';
select throws_ok(
  $$select public.validate_account_deletion('delete_me')$$,
  '42501',
  'account authentication required',
  'a malformed JWT session_id fails without disclosure'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '55555555-5555-4555-8555-555555555555';
set local "request.jwt.claims" = '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated","session_id":"10000000-0000-4000-8000-000000000004"}';

select is(
  public.validate_account_deletion('delete-incomplete@example.test'),
  true,
  'a verified incomplete profile validates with its exact Auth email'
);

select throws_ok(
  $$select public.validate_account_deletion('DELETE-INCOMPLETE@example.test')$$,
  '22023',
  'account deletion confirmation mismatch',
  'incomplete email confirmation is case sensitive'
);

select throws_ok(
  $$select public.validate_account_deletion('delete-incomplete@example.test ')$$,
  '22023',
  'account deletion confirmation mismatch',
  'incomplete email confirmation preserves whitespace exactly'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '77777777-7777-4777-8777-777777777777';
set local "request.jwt.claims" = '{"sub":"77777777-7777-4777-8777-777777777777","role":"authenticated","session_id":"10000000-0000-4000-8000-000000000005"}';
select throws_ok(
  $$select public.validate_account_deletion('unverified_user')$$,
  '42501',
  'account authentication required',
  'an unverified Auth user cannot validate deletion'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '88888888-8888-4888-8888-888888888888';
set local "request.jwt.claims" = '{"sub":"88888888-8888-4888-8888-888888888888","role":"authenticated","session_id":"10000000-0000-4000-8000-000000000006"}';
select throws_ok(
  $$select public.validate_account_deletion('missing-profile@example.test')$$,
  '42501',
  'account authentication required',
  'a confirmed Auth user without exactly one profile cannot validate deletion'
);

reset role;

select is(
  (select count(*) from auth.users),
  8::bigint,
  'validation calls delete no Auth users'
);

select is(
  (select count(*) from public.user_relationships),
  3::bigint,
  'validation calls mutate no relationships'
);

select is(
  (select count(*) from public.user_notifications),
  4::bigint,
  'validation calls mutate no notifications'
);

delete from auth.users
where id = '11111111-1111-4111-8111-111111111111';

select ok(
  not exists (
    select 1
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  'Auth-root deletion cascades the completed profile'
);

select is(
  (select count(*) from public.user_blocks),
  1::bigint,
  'incoming and outgoing blocks involving the deleted profile are removed'
);

select ok(
  exists (
    select 1
    from public.user_blocks
    where blocker_id = '33333333-3333-4333-8333-333333333333'
      and blocked_id = '44444444-4444-4444-8444-444444444444'
  ),
  'an unrelated block survives account deletion'
);

select is(
  (select count(*) from public.user_relationships),
  1::bigint,
  'relationships are deleted with the account in either participant position'
);

select ok(
  exists (
    select 1
    from public.user_relationships
    where profile_low_id = '33333333-3333-4333-8333-333333333333'
      and profile_high_id = '44444444-4444-4444-8444-444444444444'
  ),
  'an unrelated relationship survives account deletion'
);

select is(
  (select count(*) from public.user_notifications),
  1::bigint,
  'recipient, actor, and relationship cascades remove every related notification'
);

select ok(
  exists (
    select 1
    from public.user_notifications
    where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  ),
  'an unrelated notification survives account deletion'
);

select is(
  (
    select count(*)
    from private.deleted_username_reservations
    where canonical_username = 'delete_me'
      and reserved_until > pg_catalog.clock_timestamp() + interval '29 days 23 hours'
      and reserved_until <= pg_catalog.clock_timestamp() + interval '30 days'
  ),
  1::bigint,
  'completed deletion creates exactly one canonical 30-day reservation'
);

delete from auth.users
where id = '55555555-5555-4555-8555-555555555555';

select is(
  (
    select count(*)
    from private.deleted_username_reservations
    where canonical_username = 'delete-incomplete@example.test'
  ),
  0::bigint,
  'incomplete profile deletion creates no username reservation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-6666-4666-8666-666666666666';
select throws_ok(
  $$
    update public.profiles
    set username = 'delete_me', display_name = 'Claimant'
    where id = '66666666-6666-4666-8666-666666666666'
  $$,
  '23505',
  'username unavailable',
  'an active reservation rejects onboarding with the deleted username'
);
reset role;

update private.deleted_username_reservations
set reserved_until = pg_catalog.clock_timestamp() - interval '1 second'
where canonical_username = 'delete_me';

set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-6666-4666-8666-666666666666';
select lives_ok(
  $$
    update public.profiles
    set username = 'delete_me', display_name = 'Claimant'
    where id = '66666666-6666-4666-8666-666666666666'
  $$,
  'an expired reservation permits username reuse before cleanup'
);
reset role;

select is(
  (
    select username
    from public.profiles
    where id = '66666666-6666-4666-8666-666666666666'
  ),
  'delete_me',
  'the reused username retains canonical onboarding behavior'
);

delete from auth.users
where id = '66666666-6666-4666-8666-666666666666';

select is(
  (
    select count(*)
    from private.deleted_username_reservations
    where canonical_username = 'delete_me'
      and reserved_until > pg_catalog.clock_timestamp() + interval '29 days 23 hours'
  ),
  1::bigint,
  'repeated reservation creation safely replaces the expired hold'
);

insert into private.deleted_username_reservations (
  canonical_username,
  reserved_until
)
values
  ('cleanup_expired', pg_catalog.clock_timestamp() - interval '1 second'),
  ('cleanup_future', pg_catalog.clock_timestamp() + interval '1 day');

select is(
  private.delete_expired_username_reservations(),
  1::bigint,
  'the cleanup function reports one physically deleted expired row'
);

select ok(
  not exists (
    select 1
    from private.deleted_username_reservations
    where canonical_username = 'cleanup_expired'
  )
  and exists (
    select 1
    from private.deleted_username_reservations
    where canonical_username = 'cleanup_future'
  ),
  'cleanup physically removes only expired reservations'
);

select * from finish();

rollback;
