begin;

create extension if not exists pgtap with schema extensions;

select plan(75);

select has_table(
  'public',
  'user_blocks',
  'user_blocks is an application table in the public schema'
);

select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_blocks'
  ),
  3::bigint,
  'user_blocks has only the two identities and database timestamp'
);

select is(
  (
    select pg_catalog.array_agg(attribute.attname order by key_column.ordinality)
    from pg_catalog.pg_constraint as constraint_record
    cross join lateral pg_catalog.unnest(constraint_record.conkey)
      with ordinality as key_column(attribute_number, ordinality)
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = constraint_record.conrelid
      and attribute.attnum = key_column.attribute_number
    where constraint_record.conrelid = 'public.user_blocks'::regclass
      and constraint_record.contype = 'p'
  ),
  array['blocker_id', 'blocked_id']::name[],
  'the ordered pair is the primary key'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = 'public.user_blocks'::regclass
      and contype = 'f'
      and confdeltype = 'a'
  ),
  2::bigint,
  'both profile foreign keys use non-cascading deletion semantics'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.user_blocks'::regclass
      and conname = 'user_blocks_no_self_block_check'
      and contype = 'c'
  ),
  'the database has an explicit self-block constraint'
);

select ok(
  to_regclass('public.user_blocks_blocked_id_blocker_id_idx') is not null,
  'the reverse direction has a lookup index'
);

select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.user_blocks'::regclass
  ),
  'user_blocks has RLS enabled'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'user_blocks'
  ),
  0::bigint,
  'user_blocks has no direct client policies because application access is RPC-only'
);

select ok(
  not has_table_privilege('authenticated', 'public.user_blocks', 'SELECT')
  and not has_table_privilege('authenticated', 'public.user_blocks', 'INSERT')
  and not has_table_privilege('authenticated', 'public.user_blocks', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.user_blocks', 'DELETE'),
  'authenticated has no direct block table privileges'
);

select ok(
  not has_table_privilege('anon', 'public.user_blocks', 'SELECT')
  and not has_table_privilege('anon', 'public.user_blocks', 'INSERT')
  and not has_table_privilege('anon', 'public.user_blocks', 'UPDATE')
  and not has_table_privilege('anon', 'public.user_blocks', 'DELETE'),
  'anon has no block table privileges'
);

select ok(
  not has_table_privilege('service_role', 'public.user_blocks', 'SELECT')
  and not has_table_privilege('service_role', 'public.user_blocks', 'INSERT')
  and not has_table_privilege('service_role', 'public.user_blocks', 'UPDATE')
  and not has_table_privilege('service_role', 'public.user_blocks', 'DELETE'),
  'service_role receives no unnecessary block table grant'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure_record
    join pg_catalog.pg_namespace as namespace_record
      on namespace_record.oid = procedure_record.pronamespace
    where namespace_record.nspname = 'public'
      and procedure_record.proname in (
        'find_profile_by_username',
        'block_profile',
        'unblock_profile',
        'list_blocked_profiles'
      )
  ),
  4::bigint,
  'only the four intended public community RPC signatures are added'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure_record
    where procedure_record.oid in (
      'public.find_profile_by_username(text)'::regprocedure,
      'public.block_profile(uuid)'::regprocedure,
      'public.unblock_profile(uuid)'::regprocedure,
      'public.list_blocked_profiles()'::regprocedure
    )
      and procedure_record.prosecdef
  ),
  4::bigint,
  'all four narrow RPC boundaries use definer rights'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure_record
    where procedure_record.oid in (
      'public.find_profile_by_username(text)'::regprocedure,
      'public.block_profile(uuid)'::regprocedure,
      'public.unblock_profile(uuid)'::regprocedure,
      'public.list_blocked_profiles()'::regprocedure
    )
      and procedure_record.proconfig @> array['search_path=""']
  ),
  4::bigint,
  'every privileged function pins an empty search path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.find_profile_by_username(text)',
    'EXECUTE'
  )
  and has_function_privilege('authenticated', 'public.block_profile(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.unblock_profile(uuid)', 'EXECUTE')
  and has_function_privilege(
    'authenticated',
    'public.list_blocked_profiles()',
    'EXECUTE'
  ),
  'authenticated has exact execute grants for the four RPC contracts'
);

select ok(
  not has_function_privilege('anon', 'public.find_profile_by_username(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.block_profile(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.unblock_profile(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_blocked_profiles()', 'EXECUTE'),
  'anon cannot execute any community RPC'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.find_profile_by_username(text)',
    'EXECUTE'
  )
  and not has_function_privilege('service_role', 'public.block_profile(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.unblock_profile(uuid)', 'EXECUTE')
  and not has_function_privilege(
    'service_role',
    'public.list_blocked_profiles()',
    'EXECUTE'
  ),
  'service_role receives no unnecessary community RPC grant'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
  ),
  2::bigint,
  'the existing owner-only profile policy set is unchanged'
);

insert into auth.users (id, email, created_at, updated_at)
values
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'alpha@example.test',
    now(),
    now()
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'beta@example.test',
    now(),
    now()
  ),
  (
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'gamma@example.test',
    now(),
    now()
  ),
  (
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'incomplete@example.test',
    now(),
    now()
  );

update public.profiles
set username = 'alpha_user', display_name = 'Alpha User'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

update public.profiles
set username = 'beta_user', display_name = 'Beta User'
where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

update public.profiles
set username = 'gamma_user', display_name = 'Gamma User'
where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

select throws_like(
  $$select * from public.find_profile_by_username('beta_user')$$,
  '%authenticated profile required%',
  'a direct unauthenticated invocation is rejected by the function boundary'
);

set local role anon;

select throws_like(
  $$select * from public.find_profile_by_username('beta_user')$$,
  '%permission denied%function%find_profile_by_username%',
  'anon cannot invoke discovery'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '';

select throws_like(
  $$select * from public.find_profile_by_username('beta_user')$$,
  '%authenticated profile required%',
  'an authenticated role without a verified caller identity is rejected'
);

set local "request.jwt.claim.sub" = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

select throws_like(
  $$select * from public.find_profile_by_username('beta_user')$$,
  '%authenticated profile required%',
  'an incomplete caller cannot use community discovery'
);

reset role;

select throws_like(
  $$
    insert into public.user_blocks (blocker_id, blocked_id)
    values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  $$,
  '%user_blocks_no_self_block_check%',
  'the database constraint rejects a self-block'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select throws_like(
  $$select public.block_profile('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  '%profile unavailable%',
  'the block RPC rejects self without a distinguishing disclosure'
);

select throws_like(
  $$select public.block_profile('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')$$,
  '%profile unavailable%',
  'the block RPC rejects a nonexistent target generically'
);

select throws_like(
  $$select public.block_profile('dddddddd-dddd-4ddd-8ddd-dddddddddddd')$$,
  '%profile unavailable%',
  'the block RPC rejects an incomplete target generically'
);

select throws_like(
  $$select public.block_profile(null)$$,
  '%profile unavailable%',
  'the block RPC rejects a null target generically'
);

select throws_like(
  $$select public.unblock_profile('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')$$,
  '%profile unavailable%',
  'the unblock RPC rejects a nonexistent target generically'
);

select throws_like(
  $$select public.unblock_profile(null)$$,
  '%profile unavailable%',
  'the unblock RPC rejects a null target generically'
);

select is(
  (
    select profile_id
    from public.find_profile_by_username('beta_user')
  ),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
  'exact username discovery returns the intended profile identity'
);

select is(
  (
    select to_jsonb(found_profile)
    from public.find_profile_by_username('beta_user') as found_profile
  ),
  '{"profile_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","username":"beta_user","display_name":"Beta User"}'::jsonb,
  'discovery returns only the approved minimal profile projection'
);

select is(
  (
    select profile_id
    from public.find_profile_by_username(E'\t  BETA_USER  \n')
  ),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
  'discovery trims and lowercases consistently with canonical usernames'
);

select throws_like(
  $$select * from public.find_profile_by_username('invalid username')$$,
  '%invalid username%',
  'the database rejects invalid username syntax defensively'
);

select is(
  (
    select count(*)
    from public.find_profile_by_username('missing_user')
  ),
  0::bigint,
  'a valid missing username returns no result'
);

select is(
  (
    select count(*)
    from public.find_profile_by_username('alpha_user')
  ),
  0::bigint,
  'discovery excludes the caller'
);

select is(
  (
    select count(*)
    from public.find_profile_by_username('incomplete_user')
  ),
  0::bigint,
  'discovery excludes incomplete profiles'
);

select is(
  (select count(*) from public.profiles),
  1::bigint,
  'the existing profile RLS still exposes only the caller profile'
);

select is(
  (
    select count(*)
    from public.profiles
    where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  0::bigint,
  'authenticated discovery did not broaden general cross-user profile reads'
);

select throws_like(
  $$select * from public.user_blocks$$,
  '%permission denied%user_blocks%',
  'authenticated clients cannot read block rows directly'
);

select throws_like(
  $$
    insert into public.user_blocks (blocker_id, blocked_id)
    values (
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    )
  $$,
  '%permission denied%user_blocks%',
  'authenticated clients cannot spoof a blocker through direct insert'
);

select lives_ok(
  $$select public.block_profile('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  'the caller can create an outgoing block'
);

reset role;

select is(
  (
    select count(*)
    from public.user_blocks
    where blocker_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and blocked_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  1::bigint,
  'the block RPC derives and stores the caller identity'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select lives_ok(
  $$select public.block_profile('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  'repeating block is safe'
);

reset role;

select is(
  (
    select count(*)
    from public.user_blocks
    where blocker_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and blocked_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  1::bigint,
  'repeating block remains idempotent'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  (select count(*) from public.find_profile_by_username('beta_user')),
  0::bigint,
  'an outgoing block suppresses discovery'
);

set local "request.jwt.claim.sub" = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select is(
  (select count(*) from public.find_profile_by_username('alpha_user')),
  0::bigint,
  'an incoming block suppresses discovery symmetrically'
);

select is(
  (select count(*) from public.find_profile_by_username('alpha_user')),
  (select count(*) from public.find_profile_by_username('missing_user')),
  'blocked and missing usernames have the same empty discovery result'
);

select is(
  (select count(*) from public.list_blocked_profiles()),
  0::bigint,
  'an incoming-only block is absent from the blocked-users list'
);

set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  (select count(*) from public.list_blocked_profiles()),
  1::bigint,
  'the blocker can privately list their outgoing block'
);

select is(
  (
    select to_jsonb(blocked_profile)
    from public.list_blocked_profiles() as blocked_profile
  ),
  '{"profile_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","username":"beta_user","display_name":"Beta User"}'::jsonb,
  'the private blocked-users list returns only approved profile fields'
);

set local "request.jwt.claim.sub" = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

select is(
  (select count(*) from public.list_blocked_profiles()),
  0::bigint,
  'unrelated users cannot see another caller''s outgoing blocks'
);

set local "request.jwt.claim.sub" = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select lives_ok(
  $$select public.unblock_profile('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  'removing a nonexistent outgoing direction is an idempotent no-op'
);

reset role;

select is(
  (
    select count(*)
    from public.user_blocks
    where blocker_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and blocked_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ),
  1::bigint,
  'a user cannot remove an incoming block through the RPC contract'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select lives_ok(
  $$select public.unblock_profile('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  'the blocker can remove their outgoing block'
);

reset role;

select is(
  (select count(*) from public.user_blocks),
  0::bigint,
  'unblock removes the intended active row'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select lives_ok(
  $$select public.unblock_profile('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  'repeating unblock is safe'
);

reset role;

select is(
  (select count(*) from public.user_blocks),
  0::bigint,
  'repeating unblock remains idempotent'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  (select count(*) from public.find_profile_by_username('beta_user')),
  1::bigint,
  'discovery resumes after the only active block is removed'
);

select lives_ok(
  $$select public.block_profile('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  'the first reciprocal direction can be created'
);

set local "request.jwt.claim.sub" = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select lives_ok(
  $$select public.block_profile('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  'the second reciprocal direction can be created independently'
);

reset role;

select is(
  (
    select count(*)
    from public.user_blocks
    where blocker_id in (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    )
      and blocked_id in (
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      )
  ),
  2::bigint,
  'reciprocal blocks coexist as two directional rows'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select lives_ok(
  $$select public.unblock_profile('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  'one reciprocal direction can be removed independently'
);

reset role;

select is(
  (
    select count(*)
    from public.user_blocks
    where blocker_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      and blocked_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ),
  1::bigint,
  'removing one reciprocal block preserves the reverse block'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  (select count(*) from public.find_profile_by_username('beta_user')),
  0::bigint,
  'the remaining incoming block continues to suppress discovery'
);

set local "request.jwt.claim.sub" = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select is(
  (select count(*) from public.find_profile_by_username('alpha_user')),
  0::bigint,
  'the remaining outgoing block suppresses discovery for its blocker too'
);

set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  (select count(*) from public.list_blocked_profiles()),
  0::bigint,
  'the user who unblocked has no outgoing blocked user listed'
);

set local "request.jwt.claim.sub" = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select is(
  (
    select to_jsonb(blocked_profile)
    from public.list_blocked_profiles() as blocked_profile
  ),
  '{"profile_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","username":"alpha_user","display_name":"Alpha User"}'::jsonb,
  'the reciprocal blocker still sees only their own outgoing blocked profile'
);

select lives_ok(
  $$select public.unblock_profile('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  'the remaining reciprocal direction can be removed'
);

reset role;

select is(
  (select count(*) from public.user_blocks),
  0::bigint,
  'both reciprocal rows are gone after both blockers remove their own row'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  (select count(*) from public.find_profile_by_username('beta_user')),
  1::bigint,
  'discovery resumes only after neither reciprocal block remains'
);

set local "request.jwt.claim.sub" = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

select lives_ok(
  $$select public.block_profile('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  'an unrelated caller can manage their own outgoing block'
);

set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select is(
  (select count(*) from public.list_blocked_profiles()),
  0::bigint,
  'another user''s outgoing block is absent from the caller''s private list'
);

set local "request.jwt.claim.sub" = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select is(
  (select count(*) from public.list_blocked_profiles()),
  0::bigint,
  'an unrelated incoming-only block is not disclosed to its target'
);

set local "request.jwt.claim.sub" = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

select is(
  (select count(*) from public.list_blocked_profiles()),
  1::bigint,
  'the unrelated blocker can list their own outgoing block'
);

select throws_like(
  $$
    delete from public.user_blocks
    where blocker_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
  $$,
  '%permission denied%user_blocks%',
  'authenticated clients cannot bypass the unblock RPC with direct delete'
);

select * from finish();
rollback;
