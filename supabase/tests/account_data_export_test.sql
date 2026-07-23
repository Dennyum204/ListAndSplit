begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

-- Exact function boundary, metadata, and privileges.
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc
    where oid = 'public.export_own_account_data()'::regprocedure
      and pronargs = 0
  ),
  1::bigint,
  'the account export has exactly one parameterless signature'
);

select is(
  pg_catalog.pg_get_function_result(
    'public.export_own_account_data()'::regprocedure
  ),
  'jsonb'::text,
  'the account export returns one JSONB document'
);

select ok(
  (
    select prosecdef
      and provolatile = 's'
      and proconfig @> array['search_path=""']
      and pg_catalog.pg_get_userbyid(proowner) = 'postgres'
    from pg_catalog.pg_proc
    where oid = 'public.export_own_account_data()'::regprocedure
  ),
  'the export is stable and uses a PostgreSQL-owned hardened definer boundary'
);

select is(
  pg_catalog.obj_description(
    'public.export_own_account_data()'::regprocedure,
    'pg_proc'
  ),
  'Returns schema-version-6 own data with Split settlement history only in fully exported caller-owned lists.',
  'the export boundary has a precise durable comment'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.export_own_account_data()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.export_own_account_data()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.export_own_account_data()',
    'EXECUTE'
  ),
  'only authenticated receives the exact export execution grant'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as procedure_record
    cross join lateral pg_catalog.aclexplode(procedure_record.proacl)
      as privilege_record
    where procedure_record.oid =
      'public.export_own_account_data()'::regprocedure
      and privilege_record.grantee = 0
      and privilege_record.privilege_type = 'EXECUTE'
  ),
  'default PUBLIC execution is revoked'
);

select is(
  (
    select pg_catalog.array_agg(tablename order by tablename)
    from pg_catalog.pg_tables
    where schemaname = 'public'
      and tablename in (
        'active_list_items',
        'active_lists',
        'profiles',
        'user_blocks',
        'user_notifications',
        'user_relationships'
      )
  ),
  array[
    'active_list_items',
    'active_lists',
    'profiles',
    'user_blocks',
    'user_notifications',
    'user_relationships'
  ]::name[],
  'the current export boundary sees only the six reviewed application tables'
);

select ok(
  not has_table_privilege('authenticated', 'public.user_blocks', 'SELECT')
  and not has_table_privilege(
    'authenticated',
    'public.user_relationships',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.user_notifications',
    'SELECT'
  )
  and not has_table_privilege('anon', 'public.profiles', 'SELECT')
  and not has_table_privilege('service_role', 'public.user_blocks', 'SELECT'),
  'the export adds no direct application-table privilege'
);

-- Verified complete/incomplete, unverified, and inconsistent fixtures.
insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at,
  last_sign_in_at
)
values
  ('11111111-1111-4111-8111-111111111111', 'alpha@example.test', now(), now() - interval '30 days', now() - interval '1 day', now() - interval '2 hours'),
  ('22222222-2222-4222-8222-222222222222', 'beta@example.test', now(), now(), now(), null),
  ('33333333-3333-4333-8333-333333333333', 'gamma@example.test', now(), now(), now(), null),
  ('44444444-4444-4444-8444-444444444444', 'delta@example.test', now(), now(), now(), null),
  ('55555555-5555-4555-8555-555555555555', 'epsilon@example.test', now(), now(), now(), null),
  ('66666666-6666-4666-8666-666666666666', 'zeta@example.test', now(), now(), now(), null),
  ('77777777-7777-4777-8777-777777777777', 'eta@example.test', now(), now(), now(), null),
  ('88888888-8888-4888-8888-888888888888', 'theta@example.test', now(), now(), now(), null),
  ('99999999-9999-4999-8999-999999999999', 'unverified@example.test', null, now(), now(), null),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'incomplete@example.test', now(), now(), now(), null),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'missing-profile@example.test', now(), now(), now(), null),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', null, now(), now(), now(), null);

delete from public.profiles
where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

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
      when 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' then 'no_email_user'
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
      when 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' then 'No Email User'
    end
where id not in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);

insert into public.user_relationships (
  profile_low_id,
  profile_high_id,
  state,
  requester_id,
  reopen_by_id,
  version,
  created_at,
  state_changed_at
)
values
  ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'friends', '22222222-2222-4222-8222-222222222222', null, 5, now() - interval '10 days', now() - interval '1 hour'),
  ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'pending', '11111111-1111-4111-8111-111111111111', null, 6, now() - interval '9 days', now() - interval '2 hours'),
  ('11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444', 'pending', '44444444-4444-4444-8444-444444444444', null, 7, now() - interval '8 days', now() - interval '3 hours'),
  ('11111111-1111-4111-8111-111111111111', '55555555-5555-4555-8555-555555555555', 'declined', '11111111-1111-4111-8111-111111111111', '55555555-5555-4555-8555-555555555555', 8, now() - interval '7 days', now() - interval '4 hours'),
  ('11111111-1111-4111-8111-111111111111', '66666666-6666-4666-8666-666666666666', 'friends', '66666666-6666-4666-8666-666666666666', null, 9, now() - interval '6 days', now() - interval '5 hours');

insert into public.user_blocks (blocker_id, blocked_id, created_at)
values
  ('11111111-1111-4111-8111-111111111111', '88888888-8888-4888-8888-888888888888', now() - interval '2 days'),
  ('11111111-1111-4111-8111-111111111111', '77777777-7777-4777-8777-777777777777', now() - interval '1 day'),
  ('66666666-6666-4666-8666-666666666666', '11111111-1111-4111-8111-111111111111', now() - interval '3 days');

insert into public.user_notifications (
  id,
  recipient_id,
  actor_id,
  notification_type,
  relationship_low_id,
  relationship_high_id,
  relationship_version,
  created_at,
  expires_at,
  read_at,
  suppressed_at
)
values
  ('ffffffff-ffff-4fff-8fff-ffffffffffff', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'friend_request', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 5, now() - interval '1 hour', now() - interval '1 hour' + interval '180 days', null, null),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', '11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444', 'friend_request', '11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444', 7, now() - interval '1 hour', now() - interval '1 hour' + interval '180 days', now() - interval '30 minutes', null),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'friend_request', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 5, now() - interval '2 hours', now() - interval '2 hours' + interval '180 days', null, null),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccd', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'friend_request', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 4, now() - interval '3 hours', now() - interval '3 hours' + interval '180 days', null, now() - interval '2 hours'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbc', '11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444', 'friend_request', '11111111-1111-4111-8111-111111111111', '44444444-4444-4444-8444-444444444444', 6, now() - interval '181 days', now() - interval '1 day', null, null),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab', '11111111-1111-4111-8111-111111111111', '66666666-6666-4666-8666-666666666666', 'friend_request', '11111111-1111-4111-8111-111111111111', '66666666-6666-4666-8666-666666666666', 9, now() - interval '4 hours', now() - interval '4 hours' + interval '180 days', null, null),
  ('99999999-9999-4999-8999-999999999998', '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 'friend_request', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 5, now() - interval '5 hours', now() - interval '5 hours' + interval '180 days', null, null);

insert into public.active_lists (
  id,
  owner_id,
  title,
  status,
  version,
  creation_request_id,
  created_at,
  updated_at,
  archived_at
)
values
  ('10000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'Active export list', 'active', 4, '11000000-0000-4000-8000-000000000001', '2026-01-01 08:00:00+00', '2026-01-03 08:00:00+00', null),
  ('10000000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'Archived export list', 'archived', 7, '11000000-0000-4000-8000-000000000002', '2026-01-01 07:00:00+00', '2026-01-02 08:00:00+00', '2026-01-02 08:00:00+00'),
  ('10000000-0000-4000-8000-000000000003', '22222222-2222-4222-8222-222222222222', 'Foreign list', 'active', 2, '11000000-0000-4000-8000-000000000003', '2026-01-01 06:00:00+00', '2026-01-04 08:00:00+00', null);

insert into public.active_list_items (
  id,
  list_id,
  name,
  quantity_thousandths,
  unit_code,
  position,
  version,
  creation_request_id,
  completed_at,
  completed_by,
  created_at,
  updated_at
)
values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Second position', 1500, 'kg', 2, 3, '21000000-0000-4000-8000-000000000001', null, null, '2026-01-01 08:02:00+00', '2026-01-03 08:00:00+00'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'First position', 1, null, 1, 2, '21000000-0000-4000-8000-000000000002', '2026-01-03 07:00:00+00', '11111111-1111-4111-8111-111111111111', '2026-01-01 08:01:00+00', '2026-01-03 07:00:00+00'),
  ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000002', 'Archived item', 999999999, 'box', 1, 1, '21000000-0000-4000-8000-000000000003', null, null, '2026-01-01 07:01:00+00', '2026-01-01 07:01:00+00'),
  ('20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000003', 'Foreign item', 1000, 'piece', 1, 1, '21000000-0000-4000-8000-000000000004', null, null, '2026-01-01 06:01:00+00', '2026-01-01 06:01:00+00');

-- Authorization failures are privacy-safe, including malformed identity input.
set local role anon;

select throws_like(
  $$select public.export_own_account_data()$$,
  '%permission denied%function%export_own_account_data%',
  'anonymous clients cannot execute account export'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '';

select throws_ok(
  $$select public.export_own_account_data()$$,
  '42501',
  'verified account required',
  'an authenticated role without an identity is rejected generically'
);

set local "request.jwt.claim.sub" = 'not-a-uuid';

select throws_ok(
  $$select public.export_own_account_data()$$,
  '42501',
  'verified account required',
  'a malformed identity is translated to the same privacy-safe failure'
);

set local "request.jwt.claim.sub" = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

select throws_ok(
  $$select public.export_own_account_data()$$,
  '42501',
  'verified account required',
  'a missing Auth user is rejected generically'
);

set local "request.jwt.claim.sub" = '99999999-9999-4999-8999-999999999999';

select throws_ok(
  $$select public.export_own_account_data()$$,
  '42501',
  'verified account required',
  'an unverified Auth user is rejected generically'
);

set local "request.jwt.claim.sub" = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

select throws_ok(
  $$select public.export_own_account_data()$$,
  '42501',
  'verified account required',
  'a verified Auth user missing its required profile is rejected generically'
);

set local "request.jwt.claim.sub" = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

select throws_ok(
  $$select public.export_own_account_data()$$,
  '42501',
  'verified account required',
  'an inconsistent confirmed identity without email is rejected generically'
);

reset role;

create temporary table account_export_documents (
  fixture text primary key,
  document jsonb not null
) on commit drop;

grant select, insert on account_export_documents to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

insert into account_export_documents (fixture, document)
values ('incomplete', public.export_own_account_data());

select ok(
  (
    select document -> 'profile' -> 'username' = 'null'::jsonb
      and document -> 'profile' -> 'display_name' = 'null'::jsonb
      and document -> 'profile' -> 'onboarding_completed_at' = 'null'::jsonb
      and document -> 'outgoing_blocks' = '[]'::jsonb
      and document -> 'active_relationships' = '[]'::jsonb
      and document -> 'visible_notifications' = '[]'::jsonb
      and document -> 'active_lists' = '[]'::jsonb
    from account_export_documents
    where fixture = 'incomplete'
  ),
  'a verified incomplete profile exports faithful null scalars and empty arrays'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

insert into account_export_documents (fixture, document)
values ('complete', public.export_own_account_data());

reset role;

-- Exact allowlisted JSON contract.
select is(
  (
    select pg_catalog.array_agg(root_key order by root_key)
    from account_export_documents
    cross join lateral pg_catalog.jsonb_object_keys(document) as root_key
    where fixture = 'complete'
  ),
  array[
    'active_lists',
    'active_relationships',
    'auth_identity',
    'exported_at',
    'outgoing_blocks',
    'product',
    'profile',
    'schema_version',
    'shared_list_access',
    'template_categories',
    'templates',
    'visible_notifications'
  ]::text[],
  'the export has exactly the twelve schema-version-six root keys'
);

select ok(
  (
    select document ->> 'product' = 'list_and_split'
      and document -> 'schema_version' = '6'::jsonb
      and (document ->> 'exported_at')::timestamptz
        between pg_catalog.transaction_timestamp()
        and pg_catalog.clock_timestamp()
    from account_export_documents
    where fixture = 'complete'
  ),
  'the root contains the product, schema version six, and server export time'
);

select is(
  (
    select pg_catalog.array_agg(auth_key order by auth_key)
    from account_export_documents
    cross join lateral pg_catalog.jsonb_object_keys(
      document -> 'auth_identity'
    ) as auth_key
    where fixture = 'complete'
  ),
  array[
    'created_at',
    'email',
    'email_confirmed_at',
    'id',
    'last_sign_in_at',
    'updated_at'
  ]::text[],
  'Auth identity contains only the six approved fields'
);

select ok(
  (
    select document #>> '{auth_identity,id}' =
        '11111111-1111-4111-8111-111111111111'
      and document #>> '{auth_identity,email}' = 'alpha@example.test'
      and document::text not like '%beta@example.test%'
      and document::text not like '%incomplete@example.test%'
    from account_export_documents
    where fixture = 'complete'
  ),
  'the Auth section belongs only to the caller and contains no other email'
);

select is(
  (
    select pg_catalog.array_agg(profile_key order by profile_key)
    from account_export_documents
    cross join lateral pg_catalog.jsonb_object_keys(
      document -> 'profile'
    ) as profile_key
    where fixture = 'complete'
  ),
  array[
    'created_at',
    'display_name',
    'id',
    'onboarding_completed_at',
    'updated_at',
    'username'
  ]::text[],
  'profile contains only the six approved fields'
);

select is(
  (
    select pg_catalog.array_agg(block ->> 'profile_id' order by ordinal_position)
    from account_export_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'outgoing_blocks'
    ) with ordinality as blocked(block, ordinal_position)
    where fixture = 'complete'
  ),
  array[
    '88888888-8888-4888-8888-888888888888',
    '77777777-7777-4777-8777-777777777777'
  ]::text[],
  'outgoing blocks are deterministic and never reveal an incoming-only block'
);

select is(
  (
    select pg_catalog.array_agg(block_key order by block_key)
    from account_export_documents
    cross join lateral pg_catalog.jsonb_object_keys(
      document -> 'outgoing_blocks' -> 0
    ) as block_key
    where fixture = 'complete'
  ),
  array['created_at', 'display_name', 'profile_id', 'username']::text[],
  'each outgoing block uses the exact approved projection'
);

select is(
  (
    select pg_catalog.array_agg(
      relationship ->> 'status'
      order by ordinal_position
    )
    from account_export_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'active_relationships'
    ) with ordinality as active(relationship, ordinal_position)
    where fixture = 'complete'
  ),
  array['friends', 'outgoing-pending', 'incoming-pending']::text[],
  'relationships contain only deterministically ordered active caller states'
);

select ok(
  (
    select pg_catalog.jsonb_array_length(
      document -> 'active_relationships'
    ) = 3
      and document::text not like '%epsilon_user%'
      and document::text not like '%zeta_user%'
      and document::text not like '%declined%'
    from account_export_documents
    where fixture = 'complete'
  ),
  'dormant and block-hidden relationships and raw state stay absent'
);

select is(
  (
    select pg_catalog.array_agg(relationship_key order by relationship_key)
    from account_export_documents
    cross join lateral pg_catalog.jsonb_object_keys(
      document -> 'active_relationships' -> 0
    ) as relationship_key
    where fixture = 'complete'
  ),
  array[
    'display_name',
    'profile_id',
    'state_changed_at',
    'status',
    'username',
    'version'
  ]::text[],
  'active relationships use only the existing caller-relative projection'
);

select is(
  (
    select pg_catalog.array_agg(
      notification ->> 'id'
      order by ordinal_position
    )
    from account_export_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'visible_notifications'
    ) with ordinality as visible(notification, ordinal_position)
    where fixture = 'complete'
  ),
  array[
    'ffffffff-ffff-4fff-8fff-ffffffffffff',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  ]::text[],
  'notifications are newest-first with ID tie-breaker and exclude hidden rows'
);

select is(
  (
    select pg_catalog.array_agg(
      notification ->> 'action_status'
      order by ordinal_position
    )
    from account_export_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'visible_notifications'
    ) with ordinality as visible(notification, ordinal_position)
    where fixture = 'complete'
  ),
  array['friends', 'actionable', 'unavailable']::text[],
  'visible notification actions preserve caller-relative semantics'
);

select ok(
  (
    select document #> '{visible_notifications,0,expected_relationship_version}'
        = 'null'::jsonb
      and document #> '{visible_notifications,1,expected_relationship_version}'
        = '7'::jsonb
      and document #> '{visible_notifications,2,expected_relationship_version}'
        = 'null'::jsonb
    from account_export_documents
    where fixture = 'complete'
  ),
  'expected relationship version is disclosed only for an actionable row'
);

select is(
  (
    select pg_catalog.array_agg(notification_key order by notification_key)
    from account_export_documents
    cross join lateral pg_catalog.jsonb_object_keys(
      document -> 'visible_notifications' -> 0
    ) as notification_key
    where fixture = 'complete'
  ),
  array[
    'action_status',
    'actor_display_name',
    'actor_profile_id',
    'actor_username',
    'created_at',
    'expected_relationship_version',
    'expires_at',
    'id',
    'is_read',
    'read_at',
    'type'
  ]::text[],
  'visible notifications use only the eleven approved fields'
);

select is(
  (
    select pg_catalog.jsonb_array_length(document -> 'active_lists')
    from account_export_documents
    where fixture = 'complete'
  ),
  2,
  'export includes both active and archived lists owned by the caller only'
);

select is(
  (
    select pg_catalog.array_agg(list_key order by list_key)
    from account_export_documents
    cross join lateral pg_catalog.jsonb_object_keys(
      document -> 'active_lists' -> 0
    ) as list_key
    where fixture = 'complete'
  ),
  array[
    'archived_at',
    'created_at',
    'id',
    'items',
    'split',
    'status',
    'title',
    'updated_at',
    'version'
  ]::text[],
  'exported lists use only the nine approved fields including nullable Split'
);

select ok(
  (
    select document #>> '{active_lists,0,id}' =
        '10000000-0000-4000-8000-000000000001'
      and document #>> '{active_lists,0,status}' = 'active'
      and document #>> '{active_lists,1,id}' =
        '10000000-0000-4000-8000-000000000002'
      and document #>> '{active_lists,1,status}' = 'archived'
      and not (document -> 'active_lists') @> pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'id',
          '10000000-0000-4000-8000-000000000003'
        )
      )
    from account_export_documents
    where fixture = 'complete'
  ),
  'list export ordering is deterministic and excludes another owner aggregate'
);

select is(
  (
    select pg_catalog.array_agg(item_key order by item_key)
    from account_export_documents
    cross join lateral pg_catalog.jsonb_object_keys(
      document -> 'active_lists' -> 0 -> 'items' -> 0
    ) as item_key
    where fixture = 'complete'
  ),
  array[
    'completed_at',
    'completed_by',
    'created_at',
    'id',
    'name',
    'position',
    'quantity_thousandths',
    'unit_code',
    'updated_at',
    'version'
  ]::text[],
  'exported items use only the ten approved fields'
);

select ok(
  (
    select document #>> '{active_lists,0,items,0,id}' =
        '20000000-0000-4000-8000-000000000002'
      and document #> '{active_lists,0,items,0,quantity_thousandths}' =
        '1'::jsonb
      and document #>> '{active_lists,0,items,1,id}' =
        '20000000-0000-4000-8000-000000000001'
      and document #> '{active_lists,0,items,1,quantity_thousandths}' =
        '1500'::jsonb
      and document #>> '{active_lists,1,items,0,quantity_thousandths}' =
        '999999999'
    from account_export_documents
    where fixture = 'complete'
  ),
  'items are position ordered and quantities remain exact JSON integers'
);

create function pg_temp.contains_forbidden_json_key(
  document jsonb,
  forbidden_keys text[]
)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  object_entry record;
  array_entry jsonb;
begin
  if pg_catalog.jsonb_typeof(document) = 'object' then
    for object_entry in
      select key, value
      from pg_catalog.jsonb_each(document)
    loop
      if object_entry.key = any (forbidden_keys)
        or pg_temp.contains_forbidden_json_key(
          object_entry.value,
          forbidden_keys
        )
      then
        return true;
      end if;
    end loop;
  elsif pg_catalog.jsonb_typeof(document) = 'array' then
    for array_entry in
      select value
      from pg_catalog.jsonb_array_elements(document)
    loop
      if pg_temp.contains_forbidden_json_key(array_entry, forbidden_keys) then
        return true;
      end if;
    end loop;
  end if;

  return false;
end;
$$;

select ok(
  not pg_temp.contains_forbidden_json_key(
    (select document from account_export_documents where fixture = 'complete'),
    array[
      'password',
      'password_hash',
      'encrypted_password',
      'access_token',
      'refresh_token',
      'confirmation_token',
      'recovery_token',
      'reauthentication_token',
      'email_change_token_current',
      'email_change_token_new',
      'raw_app_meta_data',
      'raw_user_meta_data',
      'phone',
      'sessions',
      'identities',
      'factors',
      'blocker_id',
      'blocked_id',
      'requester_id',
      'reopen_by_id',
      'relationship_low_id',
      'relationship_high_id',
      'suppressed_at',
      'creation_request_id',
      'owner_id',
      'list_id'
    ]::text[]
  ),
  'recursive JSON inspection finds no credential, Auth, or privacy-internal key'
);

-- Export does not mutate lifecycle state, and existing projections still work.
select is(
  (select pg_catalog.count(*) from auth.users),
  12::bigint,
  'export creates or deletes no Auth user'
);

select is(
  (select pg_catalog.count(*) from public.profiles),
  11::bigint,
  'export creates or deletes no profile'
);

select is(
  (select pg_catalog.count(*) from public.user_blocks),
  3::bigint,
  'export creates or deletes no block'
);

select is(
  (select pg_catalog.count(*) from public.user_relationships),
  5::bigint,
  'export creates or deletes no relationship'
);

select is(
  (select pg_catalog.count(*) from public.user_notifications),
  7::bigint,
  'export creates or deletes no notification'
);

select is(
  (select pg_catalog.count(*) from public.active_lists),
  3::bigint,
  'export creates or deletes no active list'
);

select is(
  (select pg_catalog.count(*) from public.active_list_items),
  4::bigint,
  'export creates or deletes no active list item'
);

select ok(
  (
    select pg_catalog.count(*) filter (where read_at is not null) = 1
      and pg_catalog.count(*) filter (where suppressed_at is not null) = 1
    from public.user_notifications
  ),
  'export neither marks notifications read nor changes suppression'
);

select ok(
  (
    select pg_catalog.array_agg(version order by profile_high_id)
      = array[5, 6, 7, 8, 9]::bigint[]
    from public.user_relationships
    where profile_low_id = '11111111-1111-4111-8111-111111111111'
  ),
  'export changes no relationship version or state'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select is(
  (select pg_catalog.count(*) from public.list_blocked_profiles()),
  2::bigint,
  'the existing outgoing-block RPC still works after export'
);

select is(
  (select pg_catalog.count(*) from public.list_active_relationships()),
  3::bigint,
  'the existing active-relationship RPC still works after export'
);

select is(
  (select pg_catalog.count(*) from public.list_notifications(20, null, null)),
  3::bigint,
  'the existing visible-notification RPC matches export privacy filtering'
);

reset role;

select * from finish();

rollback;
