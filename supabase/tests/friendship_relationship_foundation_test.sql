begin;

create extension if not exists pgtap with schema extensions;

select plan(151);

-- Catalog shape, integrity, and RPC-only access boundary.
select has_table(
  'public',
  'user_relationships',
  'user_relationships is an application table in the public schema'
);

select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_relationships'
  ),
  8::bigint,
  'user_relationships retains only the current relationship fields'
);

select is(
  (
    select pg_catalog.array_agg(
      column_name || ':' || data_type
      order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_relationships'
  ),
  array[
    'profile_low_id:uuid',
    'profile_high_id:uuid',
    'state:text',
    'requester_id:uuid',
    'reopen_by_id:uuid',
    'version:bigint',
    'created_at:timestamp with time zone',
    'state_changed_at:timestamp with time zone'
  ],
  'relationship columns use the intended types and order'
);

select is(
  (
    select pg_catalog.array_agg(column_name order by ordinal_position)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_relationships'
      and is_nullable = 'NO'
  ),
  array[
    'profile_low_id',
    'profile_high_id',
    'state',
    'requester_id',
    'version',
    'created_at',
    'state_changed_at'
  ]::information_schema.sql_identifier[],
  'only the reopening controller is nullable'
);

select is(
  (
    select column_default::text
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_relationships'
      and column_name = 'version'
  ),
  '1'::text,
  'relationship versions start at one'
);

select ok(
  (
    select column_default like '%now()%'
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_relationships'
      and column_name = 'created_at'
  )
  and (
    select column_default like '%now()%'
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_relationships'
      and column_name = 'state_changed_at'
  ),
  'both retained timestamps are server-owned by default'
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
    where constraint_record.conrelid = 'public.user_relationships'::regclass
      and constraint_record.contype = 'p'
  ),
  array['profile_low_id', 'profile_high_id']::name[],
  'the normalized profile pair is the composite primary key'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = 'public.user_relationships'::regclass
      and contype = 'f'
      and confrelid = 'public.profiles'::regclass
      and confdeltype = 'a'
  ),
  2::bigint,
  'both participant foreign keys use non-cascading deletion semantics'
);

select is(
  (
    select pg_catalog.array_agg(conname order by conname)
    from pg_catalog.pg_constraint
    where conrelid = 'public.user_relationships'::regclass
      and contype = 'c'
  ),
  array[
    'user_relationships_ordered_pair_check',
    'user_relationships_positive_version_check',
    'user_relationships_reopen_participant_check',
    'user_relationships_reopen_state_check',
    'user_relationships_requester_participant_check',
    'user_relationships_state_check'
  ]::name[],
  'all relationship invariants have named check constraints'
);

select ok(
  to_regclass('public.user_relationships_high_participant_idx') is not null,
  'the reverse participant lookup has a dedicated index'
);

select is(
  (
    select pg_catalog.pg_get_indexdef(index_record.indexrelid)
    from pg_catalog.pg_index as index_record
    where index_record.indexrelid =
      'public.user_relationships_high_participant_idx'::regclass
  ),
  'CREATE INDEX user_relationships_high_participant_idx ON public.user_relationships USING btree (profile_high_id, profile_low_id)'::text,
  'the reverse index supports high-side participant lookup without extra indexes'
);

select ok(
  (
    select relrowsecurity
    from pg_catalog.pg_class
    where oid = 'public.user_relationships'::regclass
  ),
  'user_relationships has RLS enabled'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'user_relationships'
  ),
  1::bigint,
  'the RPC-only relationship table has exactly one explicit policy'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'user_relationships'
      and policyname = 'user_relationships_reject_direct_client_access'
      and cmd = 'ALL'
      and permissive = 'RESTRICTIVE'
      and roles = array['anon', 'authenticated']::name[]
      and qual = 'false'
      and with_check = 'false'
  ),
  'the restrictive policy rejects every anon and authenticated operation'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_class as table_record
    cross join lateral pg_catalog.aclexplode(table_record.relacl) as privilege_record
    where table_record.oid = 'public.user_relationships'::regclass
      and privilege_record.grantee = 0
      and privilege_record.privilege_type in (
        'SELECT',
        'INSERT',
        'UPDATE',
        'DELETE'
      )
  ),
  'PUBLIC has no direct relationship table privileges'
);

select ok(
  not has_table_privilege('anon', 'public.user_relationships', 'SELECT')
  and not has_table_privilege('anon', 'public.user_relationships', 'INSERT')
  and not has_table_privilege('anon', 'public.user_relationships', 'UPDATE')
  and not has_table_privilege('anon', 'public.user_relationships', 'DELETE'),
  'anon has no direct relationship table privileges'
);

select ok(
  not has_table_privilege('authenticated', 'public.user_relationships', 'SELECT')
  and not has_table_privilege('authenticated', 'public.user_relationships', 'INSERT')
  and not has_table_privilege('authenticated', 'public.user_relationships', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.user_relationships', 'DELETE'),
  'authenticated has no direct relationship table privileges'
);

select ok(
  not has_table_privilege('service_role', 'public.user_relationships', 'SELECT')
  and not has_table_privilege('service_role', 'public.user_relationships', 'INSERT')
  and not has_table_privilege('service_role', 'public.user_relationships', 'UPDATE')
  and not has_table_privilege('service_role', 'public.user_relationships', 'DELETE'),
  'service_role receives no direct relationship table privileges'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure_record
    join pg_catalog.pg_namespace as namespace_record
      on namespace_record.oid = procedure_record.pronamespace
    where namespace_record.nspname = 'public'
      and procedure_record.oid in (
        'public.get_relationship_summary(uuid)'::regprocedure,
        'public.list_active_relationships()'::regprocedure,
        'public.send_friend_request(uuid,bigint)'::regprocedure,
        'public.cancel_friend_request(uuid,bigint)'::regprocedure,
        'public.accept_friend_request(uuid,bigint)'::regprocedure,
        'public.decline_friend_request(uuid,bigint)'::regprocedure,
        'public.end_friendship(uuid,bigint)'::regprocedure
      )
  ),
  7::bigint,
  'all seven explicit public friendship RPC signatures exist'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc
    where oid in (
      'public.get_relationship_summary(uuid)'::regprocedure,
      'public.list_active_relationships()'::regprocedure,
      'public.send_friend_request(uuid,bigint)'::regprocedure,
      'public.cancel_friend_request(uuid,bigint)'::regprocedure,
      'public.accept_friend_request(uuid,bigint)'::regprocedure,
      'public.decline_friend_request(uuid,bigint)'::regprocedure,
      'public.end_friendship(uuid,bigint)'::regprocedure
    )
      and prosecdef
  ),
  7::bigint,
  'all friendship RPCs use reviewed definer-rights boundaries'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc
    where oid in (
      'public.get_relationship_summary(uuid)'::regprocedure,
      'public.list_active_relationships()'::regprocedure,
      'public.send_friend_request(uuid,bigint)'::regprocedure,
      'public.cancel_friend_request(uuid,bigint)'::regprocedure,
      'public.accept_friend_request(uuid,bigint)'::regprocedure,
      'public.decline_friend_request(uuid,bigint)'::regprocedure,
      'public.end_friendship(uuid,bigint)'::regprocedure
    )
      and proconfig @> array['search_path=""']
  ),
  7::bigint,
  'every privileged friendship RPC pins an empty search path'
);

select ok(
  not (
    select prosecdef
    from pg_catalog.pg_proc
    where oid = 'private.lock_relationship_pair(uuid,uuid)'::regprocedure
  )
  and not (
    select prosecdef
    from pg_catalog.pg_proc
    where oid = 'private.require_verified_friendship_caller()'::regprocedure
  ),
  'internal validation and pair locking helpers retain invoker rights'
);

select ok(
  (
    select proconfig @> array['search_path=""']
    from pg_catalog.pg_proc
    where oid = 'private.lock_relationship_pair(uuid,uuid)'::regprocedure
  )
  and (
    select proconfig @> array['search_path=""']
    from pg_catalog.pg_proc
    where oid = 'private.require_verified_friendship_caller()'::regprocedure
  ),
  'both internal friendship helpers pin an empty search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.lock_relationship_pair(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.require_verified_friendship_caller()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.lock_relationship_pair(uuid,uuid)',
    'EXECUTE'
  ),
  'Data API roles cannot invoke internal friendship helpers'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_relationship_summary(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.list_active_relationships()',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.send_friend_request(uuid,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.cancel_friend_request(uuid,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.accept_friend_request(uuid,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.decline_friend_request(uuid,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.end_friendship(uuid,bigint)',
    'EXECUTE'
  ),
  'authenticated has execute on exactly the intended friendship contracts'
);

select ok(
  not has_function_privilege('anon', 'public.get_relationship_summary(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_active_relationships()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.send_friend_request(uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.cancel_friend_request(uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.accept_friend_request(uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.decline_friend_request(uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.end_friendship(uuid,bigint)', 'EXECUTE'),
  'anon cannot execute any friendship RPC'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as procedure_record
    cross join lateral pg_catalog.aclexplode(procedure_record.proacl)
      as privilege_record
    where procedure_record.oid in (
      'public.get_relationship_summary(uuid)'::regprocedure,
      'public.list_active_relationships()'::regprocedure,
      'public.send_friend_request(uuid,bigint)'::regprocedure,
      'public.cancel_friend_request(uuid,bigint)'::regprocedure,
      'public.accept_friend_request(uuid,bigint)'::regprocedure,
      'public.decline_friend_request(uuid,bigint)'::regprocedure,
      'public.end_friendship(uuid,bigint)'::regprocedure
    )
      and privilege_record.grantee = 0
      and privilege_record.privilege_type = 'EXECUTE'
  ),
  'default PUBLIC execution is revoked from every friendship RPC'
);

select ok(
  not has_function_privilege('service_role', 'public.get_relationship_summary(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.list_active_relationships()', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.send_friend_request(uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.cancel_friend_request(uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.accept_friend_request(uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.decline_friend_request(uuid,bigint)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.end_friendship(uuid,bigint)', 'EXECUTE'),
  'service_role receives no unnecessary friendship RPC execution grant'
);

select is(
  (
    select pg_catalog.array_agg(parameter_name order by ordinal_position)
    from information_schema.parameters
    where specific_schema = 'public'
      and specific_name like 'get_relationship_summary_%'
      and parameter_mode = 'OUT'
  ),
  array[
    'profile_id',
    'username',
    'display_name',
    'relationship_status',
    'version',
    'state_changed_at'
  ]::information_schema.sql_identifier[],
  'single-target summaries expose only documented output fields'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
  ),
  2::bigint,
  'friendship support does not widen the owner-only profile policy set'
);

-- Verified/onboarded, verified/incomplete, and unverified fixtures.
insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('11111111-1111-4111-8111-111111111111', 'alpha@example.test', now(), now(), now()),
  ('22222222-2222-4222-8222-222222222222', 'beta@example.test', now(), now(), now()),
  ('33333333-3333-4333-8333-333333333333', 'gamma@example.test', now(), now(), now()),
  ('44444444-4444-4444-8444-444444444444', 'delta@example.test', now(), now(), now()),
  ('55555555-5555-4555-8555-555555555555', 'epsilon@example.test', now(), now(), now()),
  ('66666666-6666-4666-8666-666666666666', 'zeta@example.test', now(), now(), now()),
  ('77777777-7777-4777-8777-777777777777', 'eta@example.test', now(), now(), now()),
  ('88888888-8888-4888-8888-888888888888', 'theta@example.test', now(), now(), now()),
  ('99999999-9999-4999-8999-999999999999', 'unverified@example.test', null, now(), now()),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'incomplete@example.test', now(), now(), now());

update public.profiles
set username = case id
      when '11111111-1111-4111-8111-111111111111' then 'alpha_user'
      when '22222222-2222-4222-8222-222222222222' then 'beta_user'
      when '33333333-3333-4333-8333-333333333333' then 'gamma_user'
      when '44444444-4444-4444-8444-444444444444' then 'delta_user'
      when '55555555-5555-4555-8555-555555555555' then 'epsilon_user'
      when '66666666-6666-4666-8666-666666666666' then 'zeta_user'
      when '77777777-7777-4777-8777-777777777777' then 'eta_user'
      when '88888888-8888-4888-8888-888888888888' then 'theta_user'
      when '99999999-9999-4999-8999-999999999999' then 'unverified_user'
    end,
    display_name = case id
      when '11111111-1111-4111-8111-111111111111' then 'Alpha User'
      when '22222222-2222-4222-8222-222222222222' then 'Beta User'
      when '33333333-3333-4333-8333-333333333333' then 'Gamma User'
      when '44444444-4444-4444-8444-444444444444' then 'Delta User'
      when '55555555-5555-4555-8555-555555555555' then 'Epsilon User'
      when '66666666-6666-4666-8666-666666666666' then 'Zeta User'
      when '77777777-7777-4777-8777-777777777777' then 'Eta User'
      when '88888888-8888-4888-8888-888888888888' then 'Theta User'
      when '99999999-9999-4999-8999-999999999999' then 'Unverified User'
    end
where id <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

create temporary table friendship_test_snapshots (
  label text primary key,
  version bigint not null,
  state_changed_at timestamptz not null
);

-- Direct table and unauthenticated/ineligible caller denial.
set local role anon;

select throws_like(
  $$select * from public.user_relationships$$,
  '%permission denied%user_relationships%',
  'anonymous clients cannot select relationship rows directly'
);

select throws_like(
  $$
    insert into public.user_relationships (
      profile_low_id,
      profile_high_id,
      state,
      requester_id
    ) values (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'pending',
      '11111111-1111-4111-8111-111111111111'
    )
  $$,
  '%permission denied%user_relationships%',
  'anonymous clients cannot insert relationship rows directly'
);

select throws_like(
  $$update public.user_relationships set state = state$$,
  '%permission denied%user_relationships%',
  'anonymous clients cannot update relationship rows directly'
);

select throws_like(
  $$delete from public.user_relationships$$,
  '%permission denied%user_relationships%',
  'anonymous clients cannot delete relationship rows directly'
);

select throws_like(
  $$select * from public.list_active_relationships()$$,
  '%permission denied%function%list_active_relationships%',
  'anon cannot invoke the active relationship projection'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '';

select throws_like(
  $$select * from public.list_active_relationships()$$,
  '%verified profile required%',
  'an authenticated role without a caller identity is rejected'
);

set local "request.jwt.claim.sub" = '99999999-9999-4999-8999-999999999999';

select throws_like(
  $$select * from public.list_active_relationships()$$,
  '%verified profile required%',
  'an unverified caller cannot use friendship RPCs'
);

set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select throws_like(
  $$select * from public.list_active_relationships()$$,
  '%verified profile required%',
  'a verified but incomplete caller cannot use friendship RPCs'
);

set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select throws_like(
  $$select * from public.get_relationship_summary('11111111-1111-4111-8111-111111111111')$$,
  '%profile unavailable%',
  'single-target summary rejects self relationships generically'
);

select throws_like(
  $$select public.send_friend_request('11111111-1111-4111-8111-111111111111', null)$$,
  '%profile unavailable%',
  'send rejects self relationships generically'
);

select throws_like(
  $$select public.send_friend_request(null, null)$$,
  '%profile unavailable%',
  'send rejects a null target generically'
);

select throws_like(
  $$select public.send_friend_request('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', null)$$,
  '%profile unavailable%',
  'send rejects a nonexistent target generically'
);

select throws_like(
  $$select public.send_friend_request('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', null)$$,
  '%profile unavailable%',
  'send rejects an incomplete target generically'
);

select throws_like(
  $$select * from public.user_relationships$$,
  '%permission denied%user_relationships%',
  'authenticated clients cannot select relationship rows directly'
);

select throws_like(
  $$
    insert into public.user_relationships (
      profile_low_id,
      profile_high_id,
      state,
      requester_id
    ) values (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'pending',
      '11111111-1111-4111-8111-111111111111'
    )
  $$,
  '%permission denied%user_relationships%',
  'authenticated clients cannot insert relationship rows directly'
);

select throws_like(
  $$update public.user_relationships set state = state$$,
  '%permission denied%user_relationships%',
  'authenticated clients cannot update relationship rows directly'
);

select throws_like(
  $$delete from public.user_relationships$$,
  '%permission denied%user_relationships%',
  'authenticated clients cannot delete relationship rows directly'
);

select is(
  (select count(*) from public.profiles),
  1::bigint,
  'friendship RPC access leaves direct profile reads owner-only'
);

reset role;

-- Database constraints reject malformed direct writes even for privileged code.
select throws_like(
  $$
    insert into public.user_relationships values (
      '22222222-2222-4222-8222-222222222222',
      '11111111-1111-4111-8111-111111111111',
      'pending',
      '11111111-1111-4111-8111-111111111111',
      null,
      1,
      now(),
      now()
    )
  $$,
  '%user_relationships_ordered_pair_check%',
  'the table rejects a non-normalized pair'
);

select throws_like(
  $$
    insert into public.user_relationships values (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'unknown',
      '11111111-1111-4111-8111-111111111111',
      null,
      1,
      now(),
      now()
    )
  $$,
  '%user_relationships_state_check%',
  'the table rejects unsupported physical states'
);

select throws_like(
  $$
    insert into public.user_relationships values (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'pending',
      '33333333-3333-4333-8333-333333333333',
      null,
      1,
      now(),
      now()
    )
  $$,
  '%user_relationships_requester_participant_check%',
  'the current requester must be one of the two participants'
);

select throws_like(
  $$
    insert into public.user_relationships values (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'declined',
      '11111111-1111-4111-8111-111111111111',
      '33333333-3333-4333-8333-333333333333',
      1,
      now(),
      now()
    )
  $$,
  '%user_relationships_reopen_participant_check%',
  'the reopening controller must be one of the two participants'
);

select throws_like(
  $$
    insert into public.user_relationships values (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'pending',
      '11111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-111111111111',
      1,
      now(),
      now()
    )
  $$,
  '%user_relationships_reopen_state_check%',
  'active and cancelled states cannot retain a reopening controller'
);

select throws_like(
  $$
    insert into public.user_relationships values (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'ended',
      '11111111-1111-4111-8111-111111111111',
      null,
      1,
      now(),
      now()
    )
  $$,
  '%user_relationships_reopen_state_check%',
  'declined and ended states require a reopening controller'
);

select throws_like(
  $$
    insert into public.user_relationships values (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'pending',
      '11111111-1111-4111-8111-111111111111',
      null,
      0,
      now(),
      now()
    )
  $$,
  '%user_relationships_positive_version_check%',
  'relationship versions must remain positive'
);

-- First send, duplicate retry, crossed request, projections, and stale writes.
set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select is(
  (
    select relationship_status
    from public.get_relationship_summary('11111111-1111-4111-8111-111111111111')
  ),
  'can-send',
  'a pair without a row has a caller-relative can-send summary'
);

select ok(
  (
    select version is null and state_changed_at is null
    from public.get_relationship_summary('11111111-1111-4111-8111-111111111111')
  ),
  'a pair without a row exposes no internal version or timestamp'
);

select throws_like(
  $$select public.send_friend_request('11111111-1111-4111-8111-111111111111', 1)$$,
  '%relationship unavailable%',
  'a nonexistent pair rejects a stale non-null initial version generically'
);

reset role;

select is(
  (select count(*) from public.user_relationships),
  0::bigint,
  'a rejected stale first send creates no relationship row'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select lives_ok(
  $$select public.send_friend_request('11111111-1111-4111-8111-111111111111', null)$$,
  'a verified caller can create the first request'
);

reset role;

select ok(
  exists (
    select 1
    from public.user_relationships
    where profile_low_id = '11111111-1111-4111-8111-111111111111'
      and profile_high_id = '22222222-2222-4222-8222-222222222222'
      and state = 'pending'
      and requester_id = '22222222-2222-4222-8222-222222222222'
      and reopen_by_id is null
      and version = 1
      and created_at is not null
      and state_changed_at is not null
  ),
  'first send normalizes the unordered pair and creates pending version one'
);

insert into friendship_test_snapshots
select 'first-send', version, state_changed_at
from public.user_relationships
where profile_low_id = '11111111-1111-4111-8111-111111111111'
  and profile_high_id = '22222222-2222-4222-8222-222222222222';

set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select lives_ok(
  $$select public.send_friend_request('11111111-1111-4111-8111-111111111111', null)$$,
  'a duplicate send with a null preloaded version is an idempotent retry'
);

select lives_ok(
  $$select public.send_friend_request('11111111-1111-4111-8111-111111111111', 1)$$,
  'a duplicate send with the current version is an idempotent retry'
);

select throws_ok(
  $$select public.send_friend_request('11111111-1111-4111-8111-111111111111', 99)$$,
  '40001',
  'relationship changed',
  'a duplicate sender with the wrong non-null version receives a stale conflict'
);

reset role;

select ok(
  (
    select current_row.version = snapshot.version
      and current_row.state_changed_at = snapshot.state_changed_at
    from public.user_relationships as current_row
    join friendship_test_snapshots as snapshot on snapshot.label = 'first-send'
    where current_row.profile_low_id = '11111111-1111-4111-8111-111111111111'
      and current_row.profile_high_id = '22222222-2222-4222-8222-222222222222'
  ),
  'duplicate sends do not increment version or state-change timestamp'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$select public.send_friend_request('22222222-2222-4222-8222-222222222222', null)$$,
  'an opposite send from stale preloaded UI atomically crosses into friendship'
);

reset role;

select ok(
  (
    select state = 'friends'
      and requester_id = '11111111-1111-4111-8111-111111111111'
      and reopen_by_id is null
      and version = 2
    from public.user_relationships
    where profile_low_id = '11111111-1111-4111-8111-111111111111'
      and profile_high_id = '22222222-2222-4222-8222-222222222222'
  ),
  'a crossed request is one real transition and records the most recent requester'
);

select ok(
  (
    select current_row.state_changed_at > snapshot.state_changed_at
    from public.user_relationships as current_row
    join friendship_test_snapshots as snapshot on snapshot.label = 'first-send'
    where current_row.profile_low_id = '11111111-1111-4111-8111-111111111111'
      and current_row.profile_high_id = '22222222-2222-4222-8222-222222222222'
  ),
  'a real crossed-send transition advances the server-owned state-change timestamp'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select is(
  (
    select relationship_status
    from public.get_relationship_summary('22222222-2222-4222-8222-222222222222')
  ),
  'friends',
  'the first participant sees the caller-relative friends status'
);

select is(
  (
    select pg_catalog.array_agg(key order by key)
    from public.get_relationship_summary('22222222-2222-4222-8222-222222222222') as summary
    cross join lateral jsonb_object_keys(to_jsonb(summary)) as key
  ),
  array[
    'display_name',
    'profile_id',
    'relationship_status',
    'state_changed_at',
    'username',
    'version'
  ],
  'single-target projection contains only documented minimal fields'
);

select ok(
  (
    select profile_id = '22222222-2222-4222-8222-222222222222'
      and username = 'beta_user'
      and display_name = 'Beta User'
      and version = 2
    from public.get_relationship_summary('22222222-2222-4222-8222-222222222222')
  ),
  'single-target projection returns only the target profile and relationship values'
);

select is(
  (
    select count(*)
    from public.list_active_relationships()
    where profile_id = '22222222-2222-4222-8222-222222222222'
      and relationship_status = 'friends'
      and version = 2
      and state_changed_at is not null
  ),
  1::bigint,
  'active list includes the current friendship with its ordering timestamp'
);

set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select is(
  (
    select relationship_status
    from public.get_relationship_summary('11111111-1111-4111-8111-111111111111')
  ),
  'friends',
  'the second participant sees the same mutual friendship'
);

set local "request.jwt.claim.sub" = '33333333-3333-4333-8333-333333333333';

select is(
  (select count(*) from public.list_active_relationships()),
  0::bigint,
  'an unrelated caller sees no active relationships belonging to others'
);

select is(
  (
    select relationship_status
    from public.get_relationship_summary('22222222-2222-4222-8222-222222222222')
  ),
  'can-send',
  'single-target summary does not leak an unrelated pair state'
);

set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select throws_ok(
  $$select public.end_friendship('22222222-2222-4222-8222-222222222222', 1)$$,
  '40001',
  'relationship changed',
  'a stale end fails with the stable conflict discriminator'
);

reset role;

select ok(
  (
    select state = 'friends' and version = 2
    from public.user_relationships
    where profile_low_id = '11111111-1111-4111-8111-111111111111'
      and profile_high_id = '22222222-2222-4222-8222-222222222222'
  ),
  'a stale end leaves the newer friendship unchanged'
);

-- Pending recipient/requester authorization, accept, cancel, and active-list privacy.
delete from public.user_relationships;

set local role authenticated;
set local "request.jwt.claim.sub" = '33333333-3333-4333-8333-333333333333';

select lives_ok(
  $$select public.send_friend_request('44444444-4444-4444-8444-444444444444', null)$$,
  'a separate pair can create an outgoing pending request'
);

select throws_like(
  $$select public.end_friendship('44444444-4444-4444-8444-444444444444', 1)$$,
  '%relationship unavailable%',
  'a pending participant cannot end a relationship before friendship exists'
);

select throws_like(
  $$select public.decline_friend_request('44444444-4444-4444-8444-444444444444', 1)$$,
  '%relationship unavailable%',
  'the requester cannot decline their own outgoing request'
);

select is(
  (
    select relationship_status
    from public.get_relationship_summary('44444444-4444-4444-8444-444444444444')
  ),
  'outgoing-pending',
  'the requester sees outgoing-pending'
);

select is(
  (
    select count(*)
    from public.list_active_relationships()
    where profile_id = '44444444-4444-4444-8444-444444444444'
      and relationship_status = 'outgoing-pending'
  ),
  1::bigint,
  'the requester active list includes the outgoing request'
);

select throws_like(
  $$select public.accept_friend_request('44444444-4444-4444-8444-444444444444', 1)$$,
  '%relationship unavailable%',
  'the requester cannot accept their own outgoing request'
);

reset role;

select ok(
  (
    select state = 'pending' and version = 1
    from public.user_relationships
  ),
  'an unauthorized accept does not mutate the pending request'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '44444444-4444-4444-8444-444444444444';

select is(
  (
    select relationship_status
    from public.get_relationship_summary('33333333-3333-4333-8333-333333333333')
  ),
  'incoming-pending',
  'the recipient sees incoming-pending'
);

select is(
  (
    select count(*)
    from public.list_active_relationships()
    where profile_id = '33333333-3333-4333-8333-333333333333'
      and relationship_status = 'incoming-pending'
  ),
  1::bigint,
  'the recipient active list includes the incoming request'
);

select throws_like(
  $$select public.cancel_friend_request('33333333-3333-4333-8333-333333333333', 1)$$,
  '%relationship unavailable%',
  'the recipient cannot cancel another user''s request'
);

select lives_ok(
  $$select public.accept_friend_request('33333333-3333-4333-8333-333333333333', 1)$$,
  'the pending recipient can accept the request'
);

select lives_ok(
  $$select public.accept_friend_request('33333333-3333-4333-8333-333333333333', 1)$$,
  'repeating the same caller-authorized accept is idempotent'
);

reset role;

select ok(
  (
    select state = 'friends'
      and requester_id = '33333333-3333-4333-8333-333333333333'
      and version = 2
    from public.user_relationships
  ),
  'accept creates friendship with one exact version increment'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '33333333-3333-4333-8333-333333333333';

select throws_like(
  $$select public.cancel_friend_request('44444444-4444-4444-8444-444444444444', 1)$$,
  '%relationship unavailable%',
  'a stale cancel cannot probe or overwrite an accepted request'
);

reset role;

select ok(
  (select state = 'friends' and version = 2 from public.user_relationships),
  'stale cancellation leaves the friendship unchanged'
);

-- Cancellation is idempotent and either participant can reopen it.
delete from public.user_relationships;

set local role authenticated;
set local "request.jwt.claim.sub" = '77777777-7777-4777-8777-777777777777';

select lives_ok(
  $$select public.send_friend_request('88888888-8888-4888-8888-888888888888', null)$$,
  'the cancellation scenario starts pending'
);

select lives_ok(
  $$select public.cancel_friend_request('88888888-8888-4888-8888-888888888888', 1)$$,
  'the requester can cancel an outgoing pending request'
);

reset role;

insert into friendship_test_snapshots
select 'cancelled', version, state_changed_at
from public.user_relationships;

select ok(
  (select state = 'cancelled' and version = 2 from public.user_relationships),
  'cancellation is one real transition to version two'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '77777777-7777-4777-8777-777777777777';

select lives_ok(
  $$select public.cancel_friend_request('88888888-8888-4888-8888-888888888888', 1)$$,
  'repeating the completed cancellation is a caller-authorized no-op'
);

reset role;

select ok(
  (
    select current_row.version = snapshot.version
      and current_row.state_changed_at = snapshot.state_changed_at
    from public.user_relationships as current_row
    join friendship_test_snapshots as snapshot on snapshot.label = 'cancelled'
  ),
  'a repeated cancellation changes neither version nor timestamp'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '88888888-8888-4888-8888-888888888888';

select lives_ok(
  $$select public.send_friend_request('77777777-7777-4777-8777-777777777777', 2)$$,
  'the other participant may reopen a cancelled relationship'
);

select lives_ok(
  $$select public.cancel_friend_request('77777777-7777-4777-8777-777777777777', 3)$$,
  'the new requester can cancel the reopened request'
);

set local "request.jwt.claim.sub" = '77777777-7777-4777-8777-777777777777';

select lives_ok(
  $$select public.send_friend_request('88888888-8888-4888-8888-888888888888', 4)$$,
  'the original participant may also reopen a later cancelled state'
);

reset role;

select ok(
  (
    select state = 'pending'
      and requester_id = '77777777-7777-4777-8777-777777777777'
      and version = 5
    from public.user_relationships
  ),
  'each real cancel/reopen transition increments the retained version exactly once'
);

-- Decline privacy and decliner-only reopening.
delete from public.user_relationships;

set local role authenticated;
set local "request.jwt.claim.sub" = '55555555-5555-4555-8555-555555555555';

select lives_ok(
  $$select public.send_friend_request('66666666-6666-4666-8666-666666666666', null)$$,
  'the decline scenario starts pending'
);

set local "request.jwt.claim.sub" = '66666666-6666-4666-8666-666666666666';

select lives_ok(
  $$select public.decline_friend_request('55555555-5555-4555-8555-555555555555', 1)$$,
  'the pending recipient can decline'
);

select lives_ok(
  $$select public.decline_friend_request('55555555-5555-4555-8555-555555555555', 1)$$,
  'repeating the same caller-authorized decline is idempotent'
);

select is(
  (
    select relationship_status
    from public.get_relationship_summary('55555555-5555-4555-8555-555555555555')
  ),
  'can-send',
  'the decliner sees only the caller-relative ability to reopen'
);

select is(
  (
    select version
    from public.get_relationship_summary('55555555-5555-4555-8555-555555555555')
  ),
  2::bigint,
  'the decliner receives the version needed for an eligible reopen'
);

set local "request.jwt.claim.sub" = '55555555-5555-4555-8555-555555555555';

select is(
  (
    select relationship_status
    from public.get_relationship_summary('66666666-6666-4666-8666-666666666666')
  ),
  'unavailable',
  'the other participant cannot distinguish a decline from another unavailable state'
);

select ok(
  (
    select version is null and state_changed_at is null
    from public.get_relationship_summary('66666666-6666-4666-8666-666666666666')
  ),
  'the non-controller receives no dormant version or state-change timestamp'
);

select is(
  (select count(*) from public.list_active_relationships()),
  0::bigint,
  'declined rows never appear in the active list'
);

select throws_like(
  $$select public.send_friend_request('66666666-6666-4666-8666-666666666666', 2)$$,
  '%relationship unavailable%',
  'the non-decliner cannot reopen a declined relationship'
);

reset role;

select ok(
  (
    select state = 'declined'
      and reopen_by_id = '66666666-6666-4666-8666-666666666666'
      and version = 2
    from public.user_relationships
  ),
  'an ineligible declined reopen leaves the internal state unchanged'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '66666666-6666-4666-8666-666666666666';

select throws_ok(
  $$select public.send_friend_request('55555555-5555-4555-8555-555555555555', 1)$$,
  '40001',
  'relationship changed',
  'the eligible decliner must still present the exact current version'
);

select lives_ok(
  $$select public.send_friend_request('55555555-5555-4555-8555-555555555555', 2)$$,
  'the decliner can reopen with the exact version'
);

reset role;

select ok(
  (
    select state = 'pending'
      and requester_id = '66666666-6666-4666-8666-666666666666'
      and reopen_by_id is null
      and version = 3
    from public.user_relationships
  ),
  'decliner reopening creates one new pending transition'
);

-- Friendship ending privacy, idempotency, and ender-only reopening.
delete from public.user_relationships;

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$select public.send_friend_request('22222222-2222-4222-8222-222222222222', null)$$,
  'the ending scenario starts pending'
);

set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select lives_ok(
  $$select public.accept_friend_request('11111111-1111-4111-8111-111111111111', 1)$$,
  'the ending scenario establishes friendship'
);

set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$select public.end_friendship('22222222-2222-4222-8222-222222222222', 2)$$,
  'either current friend can end the friendship'
);

reset role;

insert into friendship_test_snapshots
select 'ended', version, state_changed_at
from public.user_relationships;

select ok(
  (
    select state = 'ended'
      and reopen_by_id = '11111111-1111-4111-8111-111111111111'
      and version = 3
    from public.user_relationships
  ),
  'ending records the caller as reopen controller and increments once'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$select public.end_friendship('22222222-2222-4222-8222-222222222222', 2)$$,
  'repeating the same caller-authorized end is idempotent'
);

reset role;

select ok(
  (
    select current_row.version = snapshot.version
      and current_row.state_changed_at = snapshot.state_changed_at
    from public.user_relationships as current_row
    join friendship_test_snapshots as snapshot on snapshot.label = 'ended'
  ),
  'a repeated end changes neither version nor timestamp'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select is(
  (
    select relationship_status
    from public.get_relationship_summary('11111111-1111-4111-8111-111111111111')
  ),
  'unavailable',
  'the non-ender sees a privacy-safe unavailable summary'
);

select throws_like(
  $$select public.send_friend_request('11111111-1111-4111-8111-111111111111', 3)$$,
  '%relationship unavailable%',
  'the non-ender cannot reopen an ended friendship'
);

set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select is(
  (
    select relationship_status
    from public.get_relationship_summary('22222222-2222-4222-8222-222222222222')
  ),
  'can-send',
  'the ender sees only the caller-relative ability to reopen'
);

select lives_ok(
  $$select public.send_friend_request('22222222-2222-4222-8222-222222222222', 3)$$,
  'the ender can reopen with the exact version'
);

reset role;

select ok(
  (
    select state = 'pending'
      and requester_id = '11111111-1111-4111-8111-111111111111'
      and reopen_by_id is null
      and version = 4
    from public.user_relationships
  ),
  'ender reopening creates one new pending transition'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '33333333-3333-4333-8333-333333333333';

select throws_like(
  $$select public.end_friendship('22222222-2222-4222-8222-222222222222', 4)$$,
  '%relationship unavailable%',
  'a nonparticipant cannot end another pair''s relationship'
);

reset role;

select ok(
  (select state = 'pending' and version = 4 from public.user_relationships),
  'a nonparticipant end attempt leaves the unrelated pair unchanged'
);

-- Blocking atomically deactivates active relationships and unblock never restores.
delete from public.user_relationships;
delete from public.user_blocks;

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$select public.send_friend_request('22222222-2222-4222-8222-222222222222', null)$$,
  'the pending-block scenario starts pending'
);

set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select lives_ok(
  $$select public.block_profile('11111111-1111-4111-8111-111111111111')$$,
  'creating a block while pending succeeds atomically'
);

reset role;

select ok(
  exists (
    select 1
    from public.user_blocks
    where blocker_id = '22222222-2222-4222-8222-222222222222'
      and blocked_id = '11111111-1111-4111-8111-111111111111'
  )
  and (
    select state = 'cancelled'
      and reopen_by_id is null
      and version = 2
    from public.user_relationships
  ),
  'block creation and pending cancellation commit as one protected transition'
);

insert into friendship_test_snapshots
select 'blocked-pending', version, state_changed_at
from public.user_relationships;

set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select lives_ok(
  $$select public.block_profile('11111111-1111-4111-8111-111111111111')$$,
  'repeating a block remains idempotent'
);

select throws_like(
  $$select public.accept_friend_request('11111111-1111-4111-8111-111111111111', 1)$$,
  '%relationship unavailable%',
  'an active block rejects accept inside the protected transition'
);

set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select throws_like(
  $$select public.send_friend_request('22222222-2222-4222-8222-222222222222', 2)$$,
  '%relationship unavailable%',
  'an either-direction block rejects send inside the protected transition'
);

select is(
  (
    select relationship_status
    from public.get_relationship_summary('22222222-2222-4222-8222-222222222222')
  ),
  'unavailable',
  'a blocked pair has a privacy-safe unavailable summary'
);

select ok(
  (
    select version is null and state_changed_at is null
    from public.get_relationship_summary('22222222-2222-4222-8222-222222222222')
  ),
  'a blocked summary reveals no relationship version or state-change metadata'
);

select is(
  (select count(*) from public.list_active_relationships()),
  0::bigint,
  'a blocked pair is absent from active relationships'
);

reset role;

select ok(
  (
    select current_row.version = snapshot.version
      and current_row.state_changed_at = snapshot.state_changed_at
    from public.user_relationships as current_row
    join friendship_test_snapshots as snapshot on snapshot.label = 'blocked-pending'
  ),
  'repeated block and rejected actions do not add dormant transitions'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select lives_ok(
  $$select public.unblock_profile('11111111-1111-4111-8111-111111111111')$$,
  'the blocker can remove the pending-pair block'
);

reset role;

select ok(
  (select count(*) = 0 from public.user_blocks)
  and (select state = 'cancelled' and version = 2 from public.user_relationships),
  'unblocking removes only the block and never restores the request'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$select public.send_friend_request('22222222-2222-4222-8222-222222222222', 2)$$,
  'either participant may reopen a block-cancelled request after all blocks are gone'
);

set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select lives_ok(
  $$select public.accept_friend_request('11111111-1111-4111-8111-111111111111', 3)$$,
  'the reopened request can become friendship'
);

select lives_ok(
  $$select public.block_profile('11111111-1111-4111-8111-111111111111')$$,
  'creating a block while friends atomically ends the friendship'
);

reset role;

select ok(
  (
    select state = 'ended'
      and reopen_by_id = '22222222-2222-4222-8222-222222222222'
      and version = 5
    from public.user_relationships
  ),
  'friendship blocking records the blocker as reopen controller and increments once'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select lives_ok(
  $$select public.unblock_profile('11111111-1111-4111-8111-111111111111')$$,
  'the friendship blocker can unblock'
);

reset role;

select ok(
  (select count(*) = 0 from public.user_blocks)
  and (
    select state = 'ended'
      and reopen_by_id = '22222222-2222-4222-8222-222222222222'
      and version = 5
    from public.user_relationships
  ),
  'unblocking never restores a friendship or changes its version'
);

-- Reciprocal blocks remain directional and do not create extra dormant transitions.
set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$select public.block_profile('22222222-2222-4222-8222-222222222222')$$,
  'the first reciprocal block direction can be created on a dormant pair'
);

set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

select lives_ok(
  $$select public.block_profile('11111111-1111-4111-8111-111111111111')$$,
  'the reverse reciprocal block direction remains independently valid'
);

reset role;

select ok(
  (select count(*) = 2 from public.user_blocks)
  and (select state = 'ended' and version = 5 from public.user_relationships),
  'reciprocal blocks coexist without adding transitions to an already dormant row'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$select public.unblock_profile('22222222-2222-4222-8222-222222222222')$$,
  'one reciprocal direction can be removed independently'
);

select throws_like(
  $$select public.send_friend_request('22222222-2222-4222-8222-222222222222', 5)$$,
  '%relationship unavailable%',
  'the remaining incoming reciprocal block continues to reject send'
);

reset role;

select ok(
  exists (
    select 1
    from public.user_blocks
    where blocker_id = '22222222-2222-4222-8222-222222222222'
      and blocked_id = '11111111-1111-4111-8111-111111111111'
  )
  and not exists (
    select 1
    from public.user_blocks
    where blocker_id = '11111111-1111-4111-8111-111111111111'
      and blocked_id = '22222222-2222-4222-8222-222222222222'
  ),
  'removing one reciprocal direction preserves the reverse block'
);

select * from finish();
rollback;
