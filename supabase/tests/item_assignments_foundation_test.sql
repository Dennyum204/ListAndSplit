begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select no_plan();

-- Schema and RPC-only authorization boundary.
select has_table(
  'public',
  'active_list_item_assignments',
  'item assignments table exists'
);

select columns_are(
  'public',
  'active_list_item_assignments',
  array['list_id', 'item_id', 'assignee_profile_id', 'assigned_at'],
  'item assignments expose only the reviewed current-state columns'
);

select ok(
  (
    select assignment_class.relrowsecurity
      and assignment_class.relforcerowsecurity
    from pg_catalog.pg_class as assignment_class
    where assignment_class.oid =
      'public.active_list_item_assignments'::regclass
  ),
  'item assignments enable and force RLS'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'active_list_item_assignments'
      and policyname =
        'active_list_item_assignments_reject_direct_client_access'
      and permissive = 'RESTRICTIVE'
      and cmd = 'ALL'
      and roles = array['anon', 'authenticated']::name[]
      and qual = 'false'
      and with_check = 'false'
  ),
  1::bigint,
  'one restrictive policy explicitly rejects all direct client operations'
);

select ok(
  not has_table_privilege(
    'anon',
    'public.active_list_item_assignments',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.active_list_item_assignments',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.active_list_item_assignments',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'no Data API role has direct assignment CRUD privileges'
);

select is(
  (
    select pg_catalog.array_agg(conname order by conname)
    from pg_catalog.pg_constraint
    where conrelid = 'public.active_list_item_assignments'::regclass
  ),
  array[
    'active_list_item_assignments_assignee_fkey',
    'active_list_item_assignments_item_fkey',
    'active_list_item_assignments_pkey'
  ]::name[],
  'assignment identity and both cascade references are named'
);

select ok(
  (
    select constraint_record.confdeltype = 'c'
    from pg_catalog.pg_constraint as constraint_record
    where constraint_record.conname =
      'active_list_item_assignments_item_fkey'
  )
  and (
    select constraint_record.confdeltype = 'c'
    from pg_catalog.pg_constraint as constraint_record
    where constraint_record.conname =
      'active_list_item_assignments_assignee_fkey'
  ),
  'item/list and assignee deletion cascade assignment rows'
);

select is(
  (
    select pg_catalog.array_agg(
      attribute.attname
      order by key_column.ordinality
    )
    from pg_catalog.pg_constraint as constraint_record
    cross join lateral pg_catalog.unnest(constraint_record.conkey)
      with ordinality as key_column(attribute_number, ordinality)
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = constraint_record.conrelid
     and attribute.attnum = key_column.attribute_number
    where constraint_record.conname =
      'active_list_item_assignments_pkey'
  ),
  array['list_id', 'item_id', 'assignee_profile_id']::name[],
  'the primary key makes each item-assignee relationship unique'
);

select is(
  (
    select pg_catalog.array_agg(indexname order by indexname)
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'active_list_item_assignments'
  ),
  array[
    'active_list_item_assignments_assignee_idx',
    'active_list_item_assignments_pkey'
  ]::name[],
  'assignment cleanup and item lookup have only the reviewed indexes'
);

select ok(
  (
    select indexdef like
      '%(assignee_profile_id, list_id, item_id)%'
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'active_list_item_assignments_assignee_idx'
  ),
  'the cleanup index starts with assignee and deterministically covers list/item'
);

select is(
  (
    select pg_catalog.array_agg(
      column_name
      order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_notifications'
      and column_name in (
        'active_list_item_id',
        'assignment_item_version'
      )
  ),
  array['active_list_item_id', 'assignment_item_version']
    ::information_schema.sql_identifier[],
  'notifications store the reviewed assignment item identity and version'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.user_notifications'::regclass
      and conname = 'user_notifications_item_assignment_version_key'
      and contype = 'u'
  )
  and exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.user_notifications'::regclass
      and conname = 'user_notifications_active_list_item_fkey'
      and contype = 'f'
      and confdeltype = 'c'
  ),
  'assignment notifications are version-deduplicated and item-cascaded'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.list_active_list_items_v2(uuid)'::regprocedure,
      'public.create_active_list_item_v2(uuid,text,uuid,bigint,uuid[],bigint,text)'::regprocedure,
      'public.update_active_list_item_v2(uuid,uuid,text,bigint,text,uuid[],bigint,bigint)'::regprocedure,
      'public.list_notifications_v2(integer,timestamptz,uuid)'::regprocedure,
      'public.get_unread_notification_count_v2()'::regprocedure,
      'public.export_own_account_data_v7()'::regprocedure
    )
      and function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
  ),
  6::bigint,
  'all six public v2/v7 RPCs are postgres-owned hardened definer boundaries'
);

select ok(
  (
    select pg_catalog.bool_and(
      has_function_privilege(
        'authenticated',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'service_role',
        function_record.oid,
        'EXECUTE'
      )
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.list_active_list_items_v2(uuid)'::regprocedure,
      'public.create_active_list_item_v2(uuid,text,uuid,bigint,uuid[],bigint,text)'::regprocedure,
      'public.update_active_list_item_v2(uuid,uuid,text,bigint,text,uuid[],bigint,bigint)'::regprocedure,
      'public.list_notifications_v2(integer,timestamptz,uuid)'::regprocedure,
      'public.get_unread_notification_count_v2()'::regprocedure,
      'public.export_own_account_data_v7()'::regprocedure
    )
  ),
  'only authenticated receives the reviewed public v2/v7 RPC grants'
);

select ok(
  (
    select pg_catalog.bool_and(
      function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
      and not has_function_privilege(
        'anon',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'service_role',
        function_record.oid,
        'EXECUTE'
      )
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'private.build_active_list_item_assignees(uuid,uuid)'::regprocedure,
      'private.validate_active_list_item_assignee_set(uuid,uuid[])'::regprocedure,
      'private.enforce_active_list_item_assignment_eligibility()'::regprocedure,
      'private.lock_active_list_item_assignee_participants(uuid,uuid[])'::regprocedure,
      'private.lock_active_list_item_assignee_profiles(uuid[])'::regprocedure,
      'private.get_active_list_current_profile_ids(uuid)'::regprocedure,
      'private.lock_mutable_active_list(uuid,uuid)'::regprocedure,
      'private.cleanup_active_list_item_assignments_for_profile(uuid,uuid,timestamptz)'::regprocedure,
      'private.cleanup_active_list_item_assignments_before_profile_delete()'::regprocedure,
      'private.suppress_item_assignment_notifications_on_block()'::regprocedure
    )
  ),
  'private assignment helpers remain owner-only hardened boundaries'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc
    where oid in (
      'public.list_active_list_items(uuid)'::regprocedure,
      'public.create_active_list_item(uuid,text,uuid,bigint,bigint,text)'::regprocedure,
      'public.update_active_list_item(uuid,uuid,text,bigint,text,bigint,bigint)'::regprocedure,
      'public.list_notifications(integer,timestamptz,uuid)'::regprocedure,
      'public.get_unread_notification_count()'::regprocedure,
      'public.export_own_account_data()'::regprocedure
    )
  ),
  6::bigint,
  'all legacy list-item, notification, and export RPC signatures remain'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgrelid =
      'public.active_list_participants'::regclass
      and not trigger_record.tgisinternal
      and trigger_record.tgname like '%assignment%'
  ),
  'access-loss cleanup does not use a row trigger that already owns a participant lock'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'public.update_active_list_item_v2(uuid,uuid,text,bigint,text,uuid[],bigint,bigint)'::regprocedure
  ) like '%current_assignee_ids || canonical_assignee_ids%'
  and pg_catalog.pg_get_functiondef(
    'public.create_active_list_item_v2(uuid,text,uuid,bigint,uuid[],bigint,text)'::regprocedure
  ) like '%canonical_assignee_ids || array[caller_id]%'
  and pg_catalog.pg_get_functiondef(
    'public.update_active_list_item_v2(uuid,uuid,text,bigint,text,uuid[],bigint,bigint)'::regprocedure
  ) like '%canonical_assignee_ids || array[caller_id]%'
  and pg_catalog.pg_get_functiondef(
    'private.lock_active_list_item_assignee_profiles(uuid[])'::regprocedure
  ) like '%order by assignee.id%for key share%'
  and pg_catalog.pg_get_functiondef(
    'public.remove_active_list_member(uuid,uuid,bigint)'::regprocedure
  ) like '%array[caller_id, target_profile_id]%'
  and pg_catalog.pg_get_functiondef(
    'public.leave_active_list(uuid,bigint)'::regprocedure
  ) like '%array[caller_id, preflight_owner_id]%'
  and pg_catalog.pg_get_functiondef(
    'public.remove_active_list_member(uuid,uuid,bigint)'::regprocedure
  ) like '%order by item_record.id%for update%'
  and pg_catalog.pg_get_functiondef(
    'public.leave_active_list(uuid,bigint)'::regprocedure
  ) like '%order by item_record.id%for update%'
  and pg_catalog.pg_get_functiondef(
    'public.block_profile(uuid)'::regprocedure
  ) like '%order by item_record.list_id, item_record.id%for update%'
  and pg_catalog.pg_get_functiondef(
    'private.cleanup_active_list_dependents_before_profile_delete()'::regprocedure
  ) like '%order by item_record.list_id, item_record.id%for update%',
  'mutation and cleanup paths encode profile preflight plus deterministic current/desired and item lock ordering'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_record
    where not trigger_record.tgisinternal
      and trigger_record.tgname in (
        'active_list_item_assignments_enforce_eligibility',
        'profiles_cleanup_active_list_dependents_before_delete',
        'user_blocks_suppress_item_assignment_notifications'
      )
  ),
  3::bigint,
  'eligibility, account cleanup, and block suppression triggers exist'
);

select ok(
  (
    select pg_catalog.count(*) = 3
      and pg_catalog.bool_and(
        trigger_record.tgenabled = 'O'
        and trigger_record.tgfoid = expected.trigger_function
        and pg_catalog.pg_get_triggerdef(trigger_record.oid)
          like expected.definition_pattern
      )
    from (
      values
        (
          'active_list_item_assignments_enforce_eligibility',
          'public.active_list_item_assignments'::regclass,
          'private.enforce_active_list_item_assignment_eligibility()'::regprocedure,
          '%BEFORE INSERT OR UPDATE ON public.active_list_item_assignments%'
        ),
        (
          'profiles_cleanup_active_list_dependents_before_delete',
          'public.profiles'::regclass,
          'private.cleanup_active_list_dependents_before_profile_delete()'::regprocedure,
          '%BEFORE DELETE ON public.profiles%'
        ),
        (
          'user_blocks_suppress_item_assignment_notifications',
          'public.user_blocks'::regclass,
          'private.suppress_item_assignment_notifications_on_block()'::regprocedure,
          '%AFTER INSERT ON public.user_blocks%'
        )
    ) as expected(
      trigger_name,
      relation_id,
      trigger_function,
      definition_pattern
    )
    join pg_catalog.pg_trigger as trigger_record
      on trigger_record.tgname = expected.trigger_name
     and trigger_record.tgrelid = expected.relation_id
     and not trigger_record.tgisinternal
  ),
  'assignment eligibility, profile-delete cleanup, and block suppression triggers are bound to the exact hardened functions and events'
);

-- Direct table access and anonymous RPC execution stay denied.
set local role anon;
select throws_like(
  $$select * from public.active_list_item_assignments$$,
  '%permission denied%',
  'anonymous direct assignment SELECT is denied'
);
select throws_like(
  $$insert into public.active_list_item_assignments
    values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), now())$$,
  '%permission denied%',
  'anonymous direct assignment INSERT is denied'
);
select throws_like(
  $$update public.active_list_item_assignments
    set assigned_at = assigned_at$$,
  '%permission denied%',
  'anonymous direct assignment UPDATE is denied'
);
select throws_like(
  $$delete from public.active_list_item_assignments$$,
  '%permission denied%',
  'anonymous direct assignment DELETE is denied'
);
select throws_like(
  $$select * from public.list_active_list_items_v2(gen_random_uuid())$$,
  '%permission denied%function%',
  'anonymous assignment RPC execution is denied'
);
reset role;

set local role authenticated;
select throws_like(
  $$select * from public.active_list_item_assignments$$,
  '%permission denied%',
  'authenticated direct assignment SELECT is denied'
);
select throws_like(
  $$insert into public.active_list_item_assignments
    values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), now())$$,
  '%permission denied%',
  'authenticated direct assignment INSERT is denied'
);
select throws_like(
  $$update public.active_list_item_assignments
    set assigned_at = assigned_at$$,
  '%permission denied%',
  'authenticated direct assignment UPDATE is denied'
);
select throws_like(
  $$delete from public.active_list_item_assignments$$,
  '%permission denied%',
  'authenticated direct assignment DELETE is denied'
);
select throws_ok(
  $$select * from public.list_active_list_items_v2(gen_random_uuid())$$,
  '42501',
  'verified profile required',
  'authenticated role without a verified session is rejected'
);
reset role;

set local role service_role;
select throws_like(
  $$select * from public.active_list_item_assignments$$,
  '%permission denied%',
  'service role direct assignment SELECT is denied'
);
reset role;

-- Verified profiles and authoritative list-access fixtures.
insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('a1000000-0000-4000-8000-000000000001', 'assignment-owner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000002', 'assignment-member@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000003', 'assignment-second@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000004', 'assignment-pending@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000005', 'assignment-removed@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000006', 'assignment-stranger@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000007', 'assignment-other-owner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000008', 'assignment-block-owner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000009', 'assignment-block-member@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000010', 'assignment-delete-member@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000011', 'assignment-ineligible-owner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000012', 'assignment-ineligible-member@example.test', now(), now(), now());

update public.profiles
set username = 'assignment_' || right(id::text, 2),
    display_name = 'Assignment ' || right(id::text, 2)
where id::text like 'a1000000-0000-4000-8000-0000000000__';

insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id,
  created_at,
  updated_at
)
values
  (
    'a2000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'Assignment core',
    'a3000000-0000-4000-8000-000000000001',
    '2026-07-24 10:00:00+00',
    '2026-07-24 10:00:00+00'
  ),
  (
    'a2000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000007',
    'Foreign shared metadata',
    'a3000000-0000-4000-8000-000000000002',
    '2026-07-24 10:01:00+00',
    '2026-07-24 10:01:00+00'
  );

insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state,
  version
)
values
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002', 'member', 1),
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000003', 'member', 1),
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000004', 'pending', 1),
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000005', 'removed', 2),
  ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001', 'member', 1);

create temporary table assignment_test_values (
  label text primary key,
  value_id uuid,
  value_bigint bigint,
  value_time timestamptz,
  value_json jsonb
) on commit drop;
grant select, insert, update, delete on assignment_test_values
to authenticated;

delete from realtime.messages;

-- Initial full-set create, deterministic projection, notification, and Broadcast.
set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Milk',
    'a4000000-0000-4000-8000-000000000001',
    1,
    array[
      'a1000000-0000-4000-8000-000000000002'::uuid,
      'a1000000-0000-4000-8000-000000000001'::uuid
    ],
    1500,
    'ml'
  )$$,
  'owner atomically creates an item with a multi-assignee set'
);
reset role;

insert into assignment_test_values (
  label,
  value_id,
  value_bigint,
  value_time
)
select
  'core-item',
  item_record.id,
  item_record.version,
  assignment.assigned_at
from public.active_list_items as item_record
join public.active_list_item_assignments as assignment
  on assignment.list_id = item_record.list_id
 and assignment.item_id = item_record.id
 and assignment.assignee_profile_id =
   'a1000000-0000-4000-8000-000000000001'
where item_record.list_id = 'a2000000-0000-4000-8000-000000000001'
  and item_record.creation_request_id =
    'a4000000-0000-4000-8000-000000000001';

select ok(
  (
    select list_record.version = 2
    from public.active_lists as list_record
    where list_record.id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 2
    from public.active_list_item_assignments as assignment
    where assignment.list_id =
      'a2000000-0000-4000-8000-000000000001'
      and assignment.item_id = (
        select value_id
        from assignment_test_values
        where label = 'core-item'
      )
  )
  and (
    select item_record.version = 1
    from public.active_list_items as item_record
    where item_record.id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  ),
  'create advances list once and stores exactly two version-one assignments'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
insert into assignment_test_values (label, value_json)
select 'core-assignees', listed.assignees
from public.list_active_list_items_v2(
  'a2000000-0000-4000-8000-000000000001'
) as listed
where listed.item_id = (
  select value_id from assignment_test_values where label = 'core-item'
);
reset role;

select ok(
  (
    select pg_catalog.jsonb_array_length(value_json) = 2
      and value_json #>> '{0,profile_id}' =
        'a1000000-0000-4000-8000-000000000001'
      and value_json #>> '{0,is_owner}' = 'true'
      and value_json #>> '{1,profile_id}' =
        'a1000000-0000-4000-8000-000000000002'
      and value_json #>> '{1,is_owner}' = 'false'
      and value_json #>> '{0,assigned_at}' is not null
      and value_json #>> '{1,assigned_at}' is not null
    from assignment_test_values
    where label = 'core-assignees'
  ),
  'assignees are owner-first with exact identities, ownership flags, and timestamps'
);

select is(
  (
    select pg_catalog.array_agg(assignee_key order by assignee_key)
    from assignment_test_values
    cross join lateral pg_catalog.jsonb_object_keys(
      value_json -> 0
    ) as assignee_key
    where label = 'core-assignees'
  ),
  array[
    'assigned_at',
    'display_name',
    'is_owner',
    'profile_id',
    'username'
  ]::text[],
  'each assignee uses only the five reviewed fields'
);

select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and active_list_id =
        'a2000000-0000-4000-8000-000000000001'
      and active_list_item_id = (
        select value_id
        from assignment_test_values
        where label = 'core-item'
      )
      and recipient_id =
        'a1000000-0000-4000-8000-000000000002'
      and actor_id =
        'a1000000-0000-4000-8000-000000000001'
      and assignment_item_version = 1
  ),
  1::bigint,
  'one add-only notification is created for the other assignee'
);

select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and recipient_id =
        'a1000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'self-assignment creates no persistent notification'
);

select ok(
  (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:a1000000-0000-4000-8000-000000000001'
      and extension = 'broadcast'
      and event = 'invalidate'
      and payload - 'id' = '{"v":1}'::jsonb
      and private
  )
  and (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:a1000000-0000-4000-8000-000000000002'
      and extension = 'broadcast'
      and event = 'invalidate'
      and payload - 'id' = '{"v":1}'::jsonb
      and private
  )
  and (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:a1000000-0000-4000-8000-000000000003'
      and extension = 'broadcast'
      and event = 'invalidate'
      and payload - 'id' = '{"v":1}'::jsonb
      and private
  ),
  'v2 creation reuses private account invalidation for every accepted list member'
);

select pg_catalog.set_config(
  'assignment.realtime_before_retry',
  (select pg_catalog.count(*)::text from realtime.messages),
  true
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Milk',
    'a4000000-0000-4000-8000-000000000001',
    1,
    array[
      'a1000000-0000-4000-8000-000000000001'::uuid,
      'a1000000-0000-4000-8000-000000000002'::uuid
    ],
    1500,
    'ml'
  )$$,
  'same-payload creation retry is an idempotent no-op'
);
reset role;

select ok(
  (
    select version = 2
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.active_list_items
    where list_id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and active_list_item_id = (
        select value_id
        from assignment_test_values
        where label = 'core-item'
      )
  )
  and (
    select pg_catalog.count(*) =
      pg_catalog.current_setting(
        'assignment.realtime_before_retry'
      )::bigint
    from realtime.messages
  ),
  'idempotent retry creates no row, version, notification, or invalidation'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Milk',
    'a4000000-0000-4000-8000-000000000001',
    1,
    array['a1000000-0000-4000-8000-000000000001'::uuid],
    1500,
    'ml'
  )$$,
  '23505',
  'list item creation request conflict',
  'reused request ID with a different assignment payload is rejected'
);
reset role;

select ok(
  (
    select version = 2
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 2
    from public.active_list_item_assignments
    where item_id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  ),
  'conflicting retry rolls back without changing item or assignment state'
);

-- Legacy notification APIs hide the additive type; v2 reveals exact safe context.
set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000002';
select is(
  (
    select pg_catalog.count(*)
    from public.list_notifications(20, null, null)
    where notification_type = 'list_item_assigned'
  ),
  0::bigint,
  'legacy notification listing hides assignment notifications'
);
select is(
  public.get_unread_notification_count(),
  0::bigint,
  'legacy unread count hides assignment notifications'
);
select ok(
  (
    select listed.active_list_item_id = (
        select value_id
        from assignment_test_values
        where label = 'core-item'
      )
      and listed.active_list_item_name = 'Milk'
      and listed.assignment_item_version = 1
      and listed.action_status = 'unavailable'
      and listed.expected_relationship_version is null
      and listed.expected_access_version is null
    from public.list_notifications_v2(20, null, null) as listed
    where listed.notification_type = 'list_item_assigned'
  ),
  'v2 notification listing returns exact item context without an action contract'
);
select is(
  public.get_unread_notification_count_v2(),
  1::bigint,
  'v2 unread count includes the visible assignment notification'
);
select public.mark_notifications_read(
  array[
    (
      select notification_id
      from public.list_notifications_v2(20, null, null)
      where notification_type = 'list_item_assigned'
        and active_list_item_id = (
          select value_id
          from assignment_test_values
          where label = 'core-item'
        )
    )
  ]
);
select is(
  public.get_unread_notification_count_v2(),
  0::bigint,
  'existing mark-read RPC safely handles an assignment notification'
);
reset role;

-- Full-set update preserves retained timestamps and versions atomically.
delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000002';
select lives_ok(
  format(
    $$select * from public.update_active_list_item_v2(
      'a2000000-0000-4000-8000-000000000001',
      %L,
      'Whole milk',
      2000,
      'ml',
      array[
        'a1000000-0000-4000-8000-000000000003'::uuid,
        'a1000000-0000-4000-8000-000000000001'::uuid
      ],
      2,
      1
    )$$,
    (select value_id from assignment_test_values where label = 'core-item')
  ),
  'accepted member atomically replaces fields and the complete assignee set'
);
reset role;

select ok(
  (
    select item_record.name = 'Whole milk'
      and item_record.quantity_thousandths = 2000
      and item_record.version = 2
    from public.active_list_items as item_record
    where item_record.id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  )
  and (
    select list_record.version = 3
    from public.active_lists as list_record
    where list_record.id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.array_agg(
      assignment.assignee_profile_id
      order by assignment.assignee_profile_id
    ) = array[
      'a1000000-0000-4000-8000-000000000001'::uuid,
      'a1000000-0000-4000-8000-000000000003'::uuid
    ]
    from public.active_list_item_assignments as assignment
    where assignment.item_id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  )
  and (
    select assignment.assigned_at = (
      select value_time
      from assignment_test_values
      where label = 'core-item'
    )
    from public.active_list_item_assignments as assignment
    where assignment.item_id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
      and assignment.assignee_profile_id =
        'a1000000-0000-4000-8000-000000000001'
  ),
  'update advances each aggregate once, replaces the set, and preserves retained assigned_at'
);

select ok(
  (
    select pg_catalog.count(*) = 1
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and active_list_item_id = (
        select value_id
        from assignment_test_values
        where label = 'core-item'
      )
      and recipient_id =
        'a1000000-0000-4000-8000-000000000003'
      and actor_id =
        'a1000000-0000-4000-8000-000000000002'
      and assignment_item_version = 2
  )
  and (
    select pg_catalog.count(*) = 0
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and active_list_item_id = (
        select value_id
        from assignment_test_values
        where label = 'core-item'
      )
      and assignment_item_version = 2
      and recipient_id <>
        'a1000000-0000-4000-8000-000000000003'
  ),
  'only the newly added non-self assignee receives an update notification'
);

select ok(
  (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:a1000000-0000-4000-8000-000000000001'
      and event = 'invalidate'
  )
  and (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:a1000000-0000-4000-8000-000000000002'
      and event = 'invalidate'
  )
  and (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:a1000000-0000-4000-8000-000000000003'
      and event = 'invalidate'
  ),
  'v2 update invalidates every independently mounted accepted participant'
);

delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000002';
select lives_ok(
  format(
    $$select * from public.update_active_list_item_v2(
      'a2000000-0000-4000-8000-000000000001',
      %L,
      'Whole milk',
      2000,
      'ml',
      array[
        'a1000000-0000-4000-8000-000000000001'::uuid,
        'a1000000-0000-4000-8000-000000000003'::uuid
      ],
      2,
      1
    )$$,
    (select value_id from assignment_test_values where label = 'core-item')
  ),
  'same full-set update retry accepts immediately previous versions'
);
reset role;

select ok(
  (
    select version = 3
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select version = 2
    from public.active_list_items
    where id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  )
  and (
    select pg_catalog.count(*) = 0 from realtime.messages
  ),
  'exact update retry emits no versions or invalidations'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select throws_ok(
  format(
    $$select * from public.update_active_list_item_v2(
      'a2000000-0000-4000-8000-000000000001',
      %L,
      'Stale overwrite',
      3000,
      'ml',
      array['a1000000-0000-4000-8000-000000000001'::uuid],
      2,
      1
    )$$,
    (select value_id from assignment_test_values where label = 'core-item')
  ),
  '40001',
  'list item changed',
  'serialized stale full-set update loses safely'
);
reset role;

select ok(
  (
    select name = 'Whole milk' and version = 2
    from public.active_list_items
    where id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  )
  and (
    select version = 3
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 2
    from public.active_list_item_assignments
    where item_id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  )
  and (
    select pg_catalog.count(*) = 0 from realtime.messages
  ),
  'stale update creates no partial assignment, version, or invalidation'
);

-- Legacy clients retain exact behavior and never erase or create assignments.
insert into assignment_test_values (label, value_time)
select
  'retained-second-time',
  assignment.assigned_at
from public.active_list_item_assignments as assignment
where assignment.item_id = (
  select value_id
  from assignment_test_values
  where label = 'core-item'
)
  and assignment.assignee_profile_id =
    'a1000000-0000-4000-8000-000000000003';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select lives_ok(
  format(
    $$select * from public.update_active_list_item(
      'a2000000-0000-4000-8000-000000000001',
      %L,
      'Legacy-safe milk',
      2500,
      'ml',
      3,
      2
    )$$,
    (select value_id from assignment_test_values where label = 'core-item')
  ),
  'legacy item update remains available'
);
reset role;

select ok(
  (
    select item_record.name = 'Legacy-safe milk'
      and item_record.version = 3
    from public.active_list_items as item_record
    where item_record.id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  )
  and (
    select list_record.version = 4
    from public.active_lists as list_record
    where list_record.id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 2
    from public.active_list_item_assignments
    where item_id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  )
  and (
    select assignment.assigned_at = (
      select value_time
      from assignment_test_values
      where label = 'retained-second-time'
    )
    from public.active_list_item_assignments as assignment
    where assignment.item_id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
      and assignment.assignee_profile_id =
        'a1000000-0000-4000-8000-000000000003'
  ),
  'legacy update changes fields while preserving the exact assignment set and timestamps'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.create_active_list_item(
    'a2000000-0000-4000-8000-000000000001',
    'Legacy item',
    'a4000000-0000-4000-8000-000000000002',
    4,
    1000,
    null
  )$$,
  'legacy item creation remains available'
);
reset role;

select is(
  (
    select pg_catalog.count(*)
    from public.active_list_item_assignments as assignment
    join public.active_list_items as item_record
      on item_record.list_id = assignment.list_id
     and item_record.id = assignment.item_id
    where item_record.creation_request_id =
      'a4000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'legacy item creation starts with zero assignments'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select is(
  (
    select pg_catalog.count(*)
    from public.list_active_list_items(
      'a2000000-0000-4000-8000-000000000001'
    )
  ),
  2::bigint,
  'legacy item listing still returns every item through its unchanged shape'
);
select lives_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Unassigned item',
    'a4000000-0000-4000-8000-000000000003',
    5,
    '{}'::uuid[],
    1000,
    null
  )$$,
  'v2 creation accepts an explicit zero-assignee set'
);
reset role;

select is(
  (
    select pg_catalog.count(*)
    from public.active_list_item_assignments as assignment
    join public.active_list_items as item_record
      on item_record.list_id = assignment.list_id
     and item_record.id = assignment.item_id
    where item_record.creation_request_id =
      'a4000000-0000-4000-8000-000000000003'
  ),
  0::bigint,
  'zero-assignee v2 creation stores an empty set'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000002';
select lives_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Member-created item',
    'a4000000-0000-4000-8000-000000000004',
    6,
    array['a1000000-0000-4000-8000-000000000002'::uuid],
    1000,
    null
  )$$,
  'an accepted member may create and self-assign an item'
);
reset role;

select ok(
  (
    select version = 7
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.active_list_item_assignments as assignment
    join public.active_list_items as item_record
      on item_record.list_id = assignment.list_id
     and item_record.id = assignment.item_id
    where item_record.creation_request_id =
      'a4000000-0000-4000-8000-000000000004'
      and assignment.assignee_profile_id =
        'a1000000-0000-4000-8000-000000000002'
  )
  and (
    select pg_catalog.count(*) = 0
    from public.user_notifications as notification_record
    join public.active_list_items as item_record
      on item_record.list_id = notification_record.active_list_id
     and item_record.id = notification_record.active_list_item_id
    where item_record.creation_request_id =
      'a4000000-0000-4000-8000-000000000004'
  ),
  'member mutation advances once and self-assignment remains notification-free'
);

-- Shape, membership, privacy, cross-list, and trigger validation.
delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Duplicate invalid',
    'a4000000-0000-4000-8000-000000000005',
    7,
    array[
      'a1000000-0000-4000-8000-000000000001'::uuid,
      'a1000000-0000-4000-8000-000000000001'::uuid
    ]
  )$$,
  '22023',
  'invalid list item assignees',
  'duplicate assignee IDs are rejected before list mutation'
);
select throws_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Null invalid',
    'a4000000-0000-4000-8000-000000000006',
    7,
    array[null::uuid]
  )$$,
  '22023',
  'invalid list item assignees',
  'null assignee IDs are rejected'
);
select throws_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Pending invalid',
    'a4000000-0000-4000-8000-000000000007',
    7,
    array['a1000000-0000-4000-8000-000000000004'::uuid]
  )$$,
  '22023',
  'list item assignee unavailable',
  'pending invitees cannot be assigned'
);
select throws_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Removed invalid',
    'a4000000-0000-4000-8000-000000000008',
    7,
    array['a1000000-0000-4000-8000-000000000005'::uuid]
  )$$,
  '22023',
  'list item assignee unavailable',
  'removed historical participants cannot be assigned'
);
select throws_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Stranger invalid',
    'a4000000-0000-4000-8000-000000000009',
    7,
    array['a1000000-0000-4000-8000-000000000006'::uuid]
  )$$,
  '22023',
  'list item assignee unavailable',
  'unrelated profiles cannot be assigned'
);
select throws_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Too many invalid',
    'a4000000-0000-4000-8000-000000000010',
    7,
    pg_catalog.array_fill(
      'a1000000-0000-4000-8000-000000000001'::uuid,
      array[21]
    )
  )$$,
  '22023',
  'invalid list item assignees',
  'more than twenty submitted positions are rejected'
);
reset role;

select ok(
  (
    select version = 7
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 4
    from public.active_list_items
    where list_id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 0
    from realtime.messages
  ),
  'all invalid assignee sets leave rows, versions, and invalidations unchanged'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000006';
select throws_ok(
  $$select * from public.list_active_list_items_v2(
    'a2000000-0000-4000-8000-000000000001'
  )$$,
  'P0002',
  'list unavailable',
  'unrelated caller cannot read assignment projections'
);
reset role;

select throws_ok(
  format(
    $$insert into public.active_list_item_assignments (
      list_id,
      item_id,
      assignee_profile_id
    ) values (
      'a2000000-0000-4000-8000-000000000001',
      %L,
      'a1000000-0000-4000-8000-000000000004'
    )$$,
    (select value_id from assignment_test_values where label = 'core-item')
  ),
  '22023',
  'list item assignee unavailable',
  'eligibility trigger rejects even privileged malformed pending assignment writes'
);

select ok(
  (
    select function_record.provolatile = 's'
      and function_record.proconfig = array['search_path=""']
      and pg_catalog.pg_get_functiondef(function_record.oid)
        not like '%for key share%'
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'private.require_verified_active_list_caller()'::regprocedure
  ),
  'verified-caller reads retain their established stable non-locking contract'
);

select ok(
  (
    select pg_catalog.bool_and(
      function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'private.lock_mutable_active_list(uuid,uuid)'::regprocedure,
      'public.invite_active_list_member(uuid,uuid,bigint)'::regprocedure,
      'public.accept_active_list_invitation(uuid,bigint)'::regprocedure,
      'public.decline_active_list_invitation(uuid,bigint)'::regprocedure,
      'public.transfer_active_list_ownership(uuid,uuid,bigint,bigint)'::regprocedure,
      'public.enable_active_list_split(uuid,text,bigint)'::regprocedure
    )
  ),
  'all same-list profile-FK writers remain postgres-owned hardened definer boundaries'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.lock_mutable_active_list(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.lock_mutable_active_list(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'private.lock_mutable_active_list(uuid,uuid)',
    'EXECUTE'
  )
  and (
    select pg_catalog.bool_and(
      has_function_privilege(
        'authenticated',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'service_role',
        function_record.oid,
        'EXECUTE'
      )
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.invite_active_list_member(uuid,uuid,bigint)'::regprocedure,
      'public.accept_active_list_invitation(uuid,bigint)'::regprocedure,
      'public.decline_active_list_invitation(uuid,bigint)'::regprocedure,
      'public.transfer_active_list_ownership(uuid,uuid,bigint,bigint)'::regprocedure,
      'public.enable_active_list_split(uuid,text,bigint)'::regprocedure
    )
  ),
  'profile-lock hardening preserves private and authenticated RPC grants'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'private.lock_mutable_active_list(uuid,uuid)'::regprocedure
  ) like '%array[caller_id]%'
  and pg_catalog.pg_get_functiondef(
    'public.invite_active_list_member(uuid,uuid,bigint)'::regprocedure
  ) like '%array[caller_id, target_profile_id]%'
  and pg_catalog.pg_get_functiondef(
    'public.accept_active_list_invitation(uuid,bigint)'::regprocedure
  ) like '%array[caller_id, preflight_owner_id]%'
  and pg_catalog.pg_get_functiondef(
    'public.decline_active_list_invitation(uuid,bigint)'::regprocedure
  ) like '%array[caller_id, preflight_owner_id]%'
  and pg_catalog.pg_get_functiondef(
    'public.transfer_active_list_ownership(uuid,uuid,bigint,bigint)'::regprocedure
  ) like '%array[caller_id, target_profile_id]%'
  and pg_catalog.pg_get_functiondef(
    'public.enable_active_list_split(uuid,text,bigint)'::regprocedure
  ) like '%current_profile_ids is distinct from preflight_profile_ids%',
  'each direct same-list profile writer prelocks exact identities and split rechecks its snapshot'
);

-- Dedicated cleanup and cascade aggregates.
insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id,
  created_at,
  updated_at
)
values
  (
    'a2000000-0000-4000-8000-000000000010',
    'a1000000-0000-4000-8000-000000000001',
    'Remove cleanup',
    'a3000000-0000-4000-8000-000000000010',
    '2026-07-24 11:00:00+00',
    '2026-07-24 11:00:00+00'
  ),
  (
    'a2000000-0000-4000-8000-000000000011',
    'a1000000-0000-4000-8000-000000000001',
    'Leave cleanup',
    'a3000000-0000-4000-8000-000000000011',
    '2026-07-24 11:01:00+00',
    '2026-07-24 11:01:00+00'
  ),
  (
    'a2000000-0000-4000-8000-000000000012',
    'a1000000-0000-4000-8000-000000000008',
    'Block cleanup',
    'a3000000-0000-4000-8000-000000000012',
    '2026-07-24 11:02:00+00',
    '2026-07-24 11:02:00+00'
  ),
  (
    'a2000000-0000-4000-8000-000000000013',
    'a1000000-0000-4000-8000-000000000001',
    'Account cleanup',
    'a3000000-0000-4000-8000-000000000013',
    '2026-07-24 11:03:00+00',
    '2026-07-24 11:03:00+00'
  ),
  (
    'a2000000-0000-4000-8000-000000000014',
    'a1000000-0000-4000-8000-000000000001',
    'Item cascade',
    'a3000000-0000-4000-8000-000000000014',
    '2026-07-24 11:04:00+00',
    '2026-07-24 11:04:00+00'
  ),
  (
    'a2000000-0000-4000-8000-000000000015',
    'a1000000-0000-4000-8000-000000000001',
    'List cascade',
    'a3000000-0000-4000-8000-000000000015',
    '2026-07-24 11:05:00+00',
    '2026-07-24 11:05:00+00'
  ),
  (
    'a2000000-0000-4000-8000-000000000016',
    'a1000000-0000-4000-8000-000000000011',
    'Blocked eligibility',
    'a3000000-0000-4000-8000-000000000016',
    '2026-07-24 11:06:00+00',
    '2026-07-24 11:06:00+00'
  );

insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state,
  version
)
values
  ('a2000000-0000-4000-8000-000000000010', 'a1000000-0000-4000-8000-000000000002', 'member', 1),
  ('a2000000-0000-4000-8000-000000000011', 'a1000000-0000-4000-8000-000000000003', 'member', 1),
  ('a2000000-0000-4000-8000-000000000012', 'a1000000-0000-4000-8000-000000000009', 'member', 1),
  ('a2000000-0000-4000-8000-000000000013', 'a1000000-0000-4000-8000-000000000010', 'member', 1),
  ('a2000000-0000-4000-8000-000000000014', 'a1000000-0000-4000-8000-000000000003', 'member', 1),
  ('a2000000-0000-4000-8000-000000000015', 'a1000000-0000-4000-8000-000000000003', 'member', 1),
  ('a2000000-0000-4000-8000-000000000016', 'a1000000-0000-4000-8000-000000000012', 'member', 1);

insert into public.user_blocks (blocker_id, blocked_id)
values (
  'a1000000-0000-4000-8000-000000000011',
  'a1000000-0000-4000-8000-000000000012'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000011';
select throws_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000016',
    'Blocked assignment',
    'a4000000-0000-4000-8000-000000000016',
    1,
    array['a1000000-0000-4000-8000-000000000012'::uuid]
  )$$,
  '22023',
  'list item assignee unavailable',
  'a block between current participants rejects assignment even in an inconsistent retained fixture'
);
reset role;

select ok(
  (
    select version = 1
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000016'
  )
  and not exists (
    select 1
    from public.active_list_items
    where list_id = 'a2000000-0000-4000-8000-000000000016'
  ),
  'blocked assignment rolls back the provisional item and list version'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select * from public.create_active_list_item_v2(
  'a2000000-0000-4000-8000-000000000010',
  'Remove me',
  'a4000000-0000-4000-8000-000000000010',
  1,
  array['a1000000-0000-4000-8000-000000000002'::uuid]
);
select * from public.create_active_list_item_v2(
  'a2000000-0000-4000-8000-000000000011',
  'Leave me',
  'a4000000-0000-4000-8000-000000000011',
  1,
  array['a1000000-0000-4000-8000-000000000003'::uuid]
);
select * from public.create_active_list_item_v2(
  'a2000000-0000-4000-8000-000000000013',
  'Delete account assignee',
  'a4000000-0000-4000-8000-000000000013',
  1,
  array['a1000000-0000-4000-8000-000000000010'::uuid]
);
select * from public.create_active_list_item_v2(
  'a2000000-0000-4000-8000-000000000014',
  'Delete item',
  'a4000000-0000-4000-8000-000000000014',
  1,
  array['a1000000-0000-4000-8000-000000000003'::uuid]
);
select * from public.create_active_list_item_v2(
  'a2000000-0000-4000-8000-000000000015',
  'Delete list',
  'a4000000-0000-4000-8000-000000000015',
  1,
  array['a1000000-0000-4000-8000-000000000003'::uuid]
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000008';
select * from public.create_active_list_item_v2(
  'a2000000-0000-4000-8000-000000000012',
  'Block me',
  'a4000000-0000-4000-8000-000000000012',
  1,
  array['a1000000-0000-4000-8000-000000000009'::uuid]
);
reset role;

delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select is(
  public.remove_active_list_member(
    'a2000000-0000-4000-8000-000000000010',
    'a1000000-0000-4000-8000-000000000002',
    1
  ),
  2::bigint,
  'owner removes an assigned member'
);
reset role;

select ok(
  not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'a2000000-0000-4000-8000-000000000010'
      and assignee_profile_id =
        'a1000000-0000-4000-8000-000000000002'
  )
  and (
    select item_record.version = 2
    from public.active_list_items as item_record
    where item_record.list_id =
      'a2000000-0000-4000-8000-000000000010'
  )
  and (
    select list_record.version = 3
    from public.active_lists as list_record
    where list_record.id = 'a2000000-0000-4000-8000-000000000010'
  )
  and (
    select access_record.state = 'removed'
      and access_record.version = 2
    from public.active_list_participants as access_record
    where access_record.list_id =
      'a2000000-0000-4000-8000-000000000010'
      and access_record.participant_profile_id =
        'a1000000-0000-4000-8000-000000000002'
  )
  and (
    select pg_catalog.bool_and(
      notification_record.suppressed_at is not null
    )
    from public.user_notifications as notification_record
    where notification_record.notification_type =
      'list_item_assigned'
      and notification_record.active_list_id =
        'a2000000-0000-4000-8000-000000000010'
  ),
  'member removal cleans assignments, suppresses context, and advances each affected version once'
);

select ok(
  (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:a1000000-0000-4000-8000-000000000001'
      and event = 'invalidate'
  )
  and (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:a1000000-0000-4000-8000-000000000002'
      and event = 'invalidate'
  ),
  'access-loss assignment cleanup reuses private account invalidation'
);

delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select is(
  public.remove_active_list_member(
    'a2000000-0000-4000-8000-000000000010',
    'a1000000-0000-4000-8000-000000000002',
    1
  ),
  2::bigint,
  'repeated remove returns the committed access version'
);
reset role;

select ok(
  (
    select version = 3
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000010'
  )
  and (
    select pg_catalog.count(*) = 0 from realtime.messages
  ),
  'idempotent repeated remove creates no version or invalidation'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000003';
select is(
  public.leave_active_list(
    'a2000000-0000-4000-8000-000000000011',
    1
  ),
  2::bigint,
  'assigned member may leave'
);
reset role;

select ok(
  not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'a2000000-0000-4000-8000-000000000011'
  )
  and (
    select version = 2
    from public.active_list_items
    where list_id = 'a2000000-0000-4000-8000-000000000011'
  )
  and (
    select version = 3
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000011'
  )
  and (
    select state = 'left' and version = 2
    from public.active_list_participants
    where list_id = 'a2000000-0000-4000-8000-000000000011'
      and participant_profile_id =
        'a1000000-0000-4000-8000-000000000003'
  ),
  'leave applies the same atomic cleanup and version contract'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000008';
select lives_ok(
  $$select public.block_profile(
    'a1000000-0000-4000-8000-000000000009'
  )$$,
  'blocking an assigned member succeeds'
);
reset role;

select ok(
  exists (
    select 1
    from public.user_blocks
    where blocker_id = 'a1000000-0000-4000-8000-000000000008'
      and blocked_id = 'a1000000-0000-4000-8000-000000000009'
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'a2000000-0000-4000-8000-000000000012'
  )
  and (
    select state = 'removed'
    from public.active_list_participants
    where list_id = 'a2000000-0000-4000-8000-000000000012'
      and participant_profile_id =
        'a1000000-0000-4000-8000-000000000009'
  )
  and (
    select pg_catalog.bool_and(suppressed_at is not null)
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and active_list_id = 'a2000000-0000-4000-8000-000000000012'
  ),
  'blocking removes now-ineligible assignments and permanently suppresses their notifications'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000008';
select lives_ok(
  $$select public.unblock_profile(
    'a1000000-0000-4000-8000-000000000009'
  )$$,
  'unblock remains available'
);
reset role;

select ok(
  not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'a2000000-0000-4000-8000-000000000012'
  )
  and (
    select pg_catalog.bool_and(suppressed_at is not null)
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and active_list_id = 'a2000000-0000-4000-8000-000000000012'
  ),
  'unblocking neither restores assignments nor unsuppresses history'
);

-- Cross-list substitution, unauthorized writes, completion, and archive behavior.
select pg_catalog.set_config(
  'list_and_split_test.cross_list_item_id',
  (
    select id::text
    from public.active_list_items
    where list_id = 'a2000000-0000-4000-8000-000000000014'
  ),
  true
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select throws_ok(
  format(
    $$select * from public.update_active_list_item_v2(
      'a2000000-0000-4000-8000-000000000001',
      %L,
      'Cross-list overwrite',
      1000,
      null,
      '{}'::uuid[],
      7,
      1
    )$$,
    pg_catalog.current_setting('list_and_split_test.cross_list_item_id')::uuid
  ),
  'P0002',
  'list item unavailable',
  'cross-list item ID substitution is rejected'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000006';
select throws_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000001',
    'Unauthorized create',
    'a4000000-0000-4000-8000-000000000020',
    7,
    '{}'::uuid[]
  )$$,
  'P0002',
  'list unavailable',
  'unrelated authenticated profile cannot create an assigned item'
);
select throws_ok(
  format(
    $$select * from public.update_active_list_item_v2(
      'a2000000-0000-4000-8000-000000000001',
      %L,
      'Unauthorized update',
      1000,
      null,
      '{}'::uuid[],
      7,
      3
    )$$,
    (select value_id from assignment_test_values where label = 'core-item')
  ),
  'P0002',
  'list unavailable',
  'unrelated authenticated profile cannot update assignments'
);
reset role;

select ok(
  (
    select version = 7
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000001'
  )
  and (
    select name = 'Legacy-safe milk' and version = 3
    from public.active_list_items
    where id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  ),
  'cross-list and unauthorized attempts leave aggregate versions unchanged'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select ok(
  (
    select list_version = 8
      and version = 4
      and completed_at is not null
    from public.set_active_list_item_completed(
      'a2000000-0000-4000-8000-000000000001',
      (select value_id from assignment_test_values where label = 'core-item'),
      true,
      7,
      3
    )
  ),
  'assigned item may be completed'
);
select lives_ok(
  format(
    $$select * from public.update_active_list_item_v2(
      'a2000000-0000-4000-8000-000000000001',
      %L,
      'Completed assigned item',
      2500,
      'ml',
      array[
        'a1000000-0000-4000-8000-000000000001'::uuid,
        'a1000000-0000-4000-8000-000000000003'::uuid
      ],
      8,
      4
    )$$,
    (select value_id from assignment_test_values where label = 'core-item')
  ),
  'completion does not prevent assignment editing'
);
select ok(
  (
    select status = 'archived' and version = 10
    from public.set_active_list_archived(
      'a2000000-0000-4000-8000-000000000001',
      true,
      9
    )
  ),
  'owner archives the assigned list'
);
select throws_ok(
  format(
    $$select * from public.update_active_list_item_v2(
      'a2000000-0000-4000-8000-000000000001',
      %L,
      'Archived overwrite',
      2500,
      'ml',
      '{}'::uuid[],
      10,
      5
    )$$,
    (select value_id from assignment_test_values where label = 'core-item')
  ),
  '55000',
  'archived list is read only',
  'archived list rejects assignment edits'
);
select ok(
  (
    select status = 'active' and version = 11
    from public.set_active_list_archived(
      'a2000000-0000-4000-8000-000000000001',
      false,
      10
    )
  ),
  'restore reopens the assigned list'
);
reset role;

select ok(
  (
    select completed_at is not null
      and completed_by =
        'a1000000-0000-4000-8000-000000000001'
      and version = 5
    from public.active_list_items
    where id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  )
  and (
    select pg_catalog.count(*) = 2
    from public.active_list_item_assignments
    where item_id = (
      select value_id
      from assignment_test_values
      where label = 'core-item'
    )
  ),
  'completion and archive/restore preserve the current assignment set'
);

-- Unassignment is silent; a later real re-add creates one new version-bound event.
set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select * from public.update_active_list_item_v2(
  'a2000000-0000-4000-8000-000000000001',
  (select value_id from assignment_test_values where label = 'core-item'),
  'Completed assigned item',
  2500,
  'ml',
  array['a1000000-0000-4000-8000-000000000001'::uuid],
  11,
  5
);
select * from public.update_active_list_item_v2(
  'a2000000-0000-4000-8000-000000000001',
  (select value_id from assignment_test_values where label = 'core-item'),
  'Completed assigned item',
  2500,
  'ml',
  array[
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'a1000000-0000-4000-8000-000000000003'::uuid
  ],
  12,
  6
);
reset role;

select ok(
  (
    select pg_catalog.count(*) = 2
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and active_list_item_id = (
        select value_id
        from assignment_test_values
        where label = 'core-item'
      )
      and recipient_id =
        'a1000000-0000-4000-8000-000000000003'
  )
  and (
    select pg_catalog.array_agg(
      assignment_item_version
      order by assignment_item_version
    ) = array[2::bigint, 7::bigint]
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and active_list_item_id = (
        select value_id
        from assignment_test_values
        where label = 'core-item'
      )
      and recipient_id =
        'a1000000-0000-4000-8000-000000000003'
  ),
  'unassignment emits nothing while a later re-add creates one distinct version event'
);

select ok(
  (
    select pg_catalog.bool_and(
      expires_at = created_at + interval '180 days'
    )
    from public.user_notifications
    where notification_type = 'list_item_assigned'
  ),
  'every assignment notification uses the established exact 180-day retention'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000002';
select is(
  (
    select pg_catalog.count(*)
    from public.list_notifications_v2(50, null, null)
    where notification_type = 'list_item_assigned'
      and active_list_id =
        'a2000000-0000-4000-8000-000000000010'
  ),
  0::bigint,
  'removed member can no longer retrieve stale item-assignment context'
);
reset role;

-- Exact twenty-assignee bound.
insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at
)
select
  (
    'a1000000-0000-4000-8000-' ||
    pg_catalog.lpad(series.value::text, 12, '0')
  )::uuid,
  'assignment-cap-' || series.value::text || '@example.test',
  now(),
  now(),
  now()
from pg_catalog.generate_series(13, 31) as series(value);

update public.profiles
set username = 'assignment_cap_' || right(id::text, 2),
    display_name = 'Assignment cap ' || right(id::text, 2)
where id::text like 'a1000000-0000-4000-8000-0000000000__'
  and right(id::text, 2)::integer between 13 and 31;

insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values (
  'a2000000-0000-4000-8000-000000000020',
  'a1000000-0000-4000-8000-000000000001',
  'Exact twenty',
  'a3000000-0000-4000-8000-000000000020'
);

insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state
)
select
  'a2000000-0000-4000-8000-000000000020',
  (
    'a1000000-0000-4000-8000-' ||
    pg_catalog.lpad(series.value::text, 12, '0')
  )::uuid,
  'member'
from pg_catalog.generate_series(13, 31) as series(value);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.create_active_list_item_v2(
    'a2000000-0000-4000-8000-000000000020',
    'Twenty people',
    'a4000000-0000-4000-8000-000000000020',
    1,
    (
      select pg_catalog.array_agg(profile_id order by profile_id)
      from (
        select 'a1000000-0000-4000-8000-000000000001'::uuid as profile_id
        union all
        select (
          'a1000000-0000-4000-8000-' ||
          pg_catalog.lpad(series.value::text, 12, '0')
        )::uuid
        from pg_catalog.generate_series(13, 31) as series(value)
      ) as exact_set
    )
  )$$,
  'exactly twenty distinct current participants may be assigned'
);
reset role;

select ok(
  (
    select pg_catalog.count(*) = 20
    from public.active_list_item_assignments
    where list_id = 'a2000000-0000-4000-8000-000000000020'
  )
  and (
    select pg_catalog.count(*) = 19
    from public.user_notifications
    where notification_type = 'list_item_assigned'
      and active_list_id =
        'a2000000-0000-4000-8000-000000000020'
  )
  and (
    select version = 2
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000020'
  ),
  'exact-twenty create stores every position, excludes self notification, and versions once'
);

-- Template snapshots intentionally do not copy assignment relationships.
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'private_template_items'
      and column_name like '%assign%'
  ),
  'template item schema contains no assignment field'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
insert into assignment_test_values (label, value_id)
select 'assignment-template', saved.template_id
from public.save_active_list_as_template(
  'a2000000-0000-4000-8000-000000000001',
  array[
    (select value_id from assignment_test_values where label = 'core-item')
  ],
  'Assignment snapshot',
  null,
  'a5000000-0000-4000-8000-000000000001',
  13
) as saved;

insert into assignment_test_values (label, value_id)
select 'assignment-template-item', listed.item_id
from public.list_private_template_items(
  (select value_id from assignment_test_values where label = 'assignment-template')
) as listed;

insert into assignment_test_values (label, value_id)
select 'assignment-template-list', created.list_id
from public.create_active_list_from_template(
  (select value_id from assignment_test_values where label = 'assignment-template'),
  array[
    (
      select value_id
      from assignment_test_values
      where label = 'assignment-template-item'
    )
  ],
  'Assignment-independent copy',
  'a5000000-0000-4000-8000-000000000002',
  array['a5000000-0000-4000-8000-000000000003'::uuid],
  1
) as created;
reset role;

select is(
  (
    select pg_catalog.count(*)
    from public.active_list_item_assignments
    where list_id = (
      select value_id
      from assignment_test_values
      where label = 'assignment-template-list'
    )
  ),
  0::bigint,
  'save-as-template and create-from-template copy item fields but no assignments'
);

-- Profile, item, and list deletion cleanup.
delete from auth.users
where id = 'a1000000-0000-4000-8000-000000000010';

select ok(
  not exists (
    select 1
    from public.profiles
    where id = 'a1000000-0000-4000-8000-000000000010'
  )
  and exists (
    select 1
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000013'
      and version = 3
  )
  and exists (
    select 1
    from public.active_list_items
    where list_id = 'a2000000-0000-4000-8000-000000000013'
      and version = 2
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'a2000000-0000-4000-8000-000000000013'
  )
  and not exists (
    select 1
    from public.active_list_participants
    where list_id = 'a2000000-0000-4000-8000-000000000013'
      and participant_profile_id =
        'a1000000-0000-4000-8000-000000000010'
  ),
  'account deletion removes assignments from surviving lists without deleting items and versions both aggregates once'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select is(
  public.delete_active_list_item(
    'a2000000-0000-4000-8000-000000000014',
    pg_catalog.current_setting(
      'list_and_split_test.cross_list_item_id'
    )::uuid,
    2,
    1
  ),
  3::bigint,
  'item deletion succeeds for an assigned item'
);
reset role;

select ok(
  not exists (
    select 1
    from public.active_list_items
    where list_id = 'a2000000-0000-4000-8000-000000000014'
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'a2000000-0000-4000-8000-000000000014'
  )
  and not exists (
    select 1
    from public.user_notifications
    where active_list_id = 'a2000000-0000-4000-8000-000000000014'
      and notification_type = 'list_item_assigned'
  ),
  'item deletion cascades assignment rows and their item-scoped notifications'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.delete_active_list(
    'a2000000-0000-4000-8000-000000000015',
    2
  )$$,
  'list deletion succeeds with assigned items'
);
reset role;

select ok(
  not exists (
    select 1
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-000000000015'
  )
  and not exists (
    select 1
    from public.active_list_items
    where list_id = 'a2000000-0000-4000-8000-000000000015'
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'a2000000-0000-4000-8000-000000000015'
  )
  and not exists (
    select 1
    from public.user_notifications
    where active_list_id = 'a2000000-0000-4000-8000-000000000015'
  ),
  'list deletion cascades items, assignments, participants, and notifications'
);

-- Version 7 enriches only owned items; version 6 and shared metadata stay exact.
insert into public.active_list_items (
  id,
  list_id,
  name,
  position,
  creation_request_id
)
values (
  'a6000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000002',
  'Foreign shared item name',
  1,
  'a6000000-0000-4000-8000-000000000002'
);
insert into public.active_list_item_assignments (
  list_id,
  item_id,
  assignee_profile_id
)
values (
  'a2000000-0000-4000-8000-000000000002',
  'a6000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001'
);

select pg_catalog.set_config(
  'assignment.export_assignment_count',
  (select pg_catalog.count(*)::text
   from public.active_list_item_assignments),
  true
);
select pg_catalog.set_config(
  'assignment.export_item_count',
  (select pg_catalog.count(*)::text from public.active_list_items),
  true
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'a1000000-0000-4000-8000-000000000001';
insert into assignment_test_values (label, value_json)
values
  ('export-v6', public.export_own_account_data()),
  ('export-v7', public.export_own_account_data_v7());
reset role;

select ok(
  (
    select value_json -> 'schema_version' = '6'::jsonb
    from assignment_test_values
    where label = 'export-v6'
  )
  and not exists (
    select 1
    from assignment_test_values as export_document
    cross join lateral pg_catalog.jsonb_array_elements(
      export_document.value_json -> 'active_lists'
    ) as owned_list(document)
    cross join lateral pg_catalog.jsonb_array_elements(
      owned_list.document -> 'items'
    ) as owned_item(document)
    where export_document.label = 'export-v6'
      and owned_item.document ? 'assignees'
  ),
  'unchanged public export remains schema six with its exact legacy item shape'
);

select ok(
  (
    select value_json -> 'schema_version' = '7'::jsonb
    from assignment_test_values
    where label = 'export-v7'
  )
  and not exists (
    select 1
    from assignment_test_values as export_document
    cross join lateral pg_catalog.jsonb_array_elements(
      export_document.value_json -> 'active_lists'
    ) as owned_list(document)
    cross join lateral pg_catalog.jsonb_array_elements(
      owned_list.document -> 'items'
    ) as owned_item(document)
    where export_document.label = 'export-v7'
      and not (owned_item.document ? 'assignees')
  ),
  'schema seven adds a non-null assignee array to every owned item only'
);

select ok(
  exists (
    select 1
    from assignment_test_values as export_document
    cross join lateral pg_catalog.jsonb_array_elements(
      export_document.value_json -> 'active_lists'
    ) as owned_list(document)
    cross join lateral pg_catalog.jsonb_array_elements(
      owned_list.document -> 'items'
    ) as owned_item(document)
    where export_document.label = 'export-v7'
      and owned_item.document ->> 'id' = (
        select value_id::text
        from assignment_test_values
        where label = 'core-item'
      )
      and pg_catalog.jsonb_array_length(
        owned_item.document -> 'assignees'
      ) = 2
      and owned_item.document #>> '{assignees,0,profile_id}' =
        'a1000000-0000-4000-8000-000000000001'
      and owned_item.document #>> '{assignees,0,is_owner}' = 'true'
      and owned_item.document #>> '{assignees,1,profile_id}' =
        'a1000000-0000-4000-8000-000000000003'
  ),
  'owned-item export uses the same deterministic owner-first assignment projection'
);

select ok(
  (
    select v7.value_json -> 'shared_list_access' =
      v6.value_json -> 'shared_list_access'
    from assignment_test_values as v7
    cross join assignment_test_values as v6
    where v7.label = 'export-v7'
      and v6.label = 'export-v6'
  )
  and not exists (
    select 1
    from assignment_test_values as export_document
    cross join lateral pg_catalog.jsonb_array_elements(
      export_document.value_json -> 'shared_list_access'
    ) as shared_list(document)
    where export_document.label = 'export-v7'
      and (
        shared_list.document ? 'items'
        or shared_list.document ? 'assignments'
        or shared_list.document ? 'assignees'
      )
  )
  and (
    select value_json::text not like '%Foreign shared item name%'
    from assignment_test_values
    where label = 'export-v7'
  ),
  'v7 leaves shared-list access metadata-only and byte-equivalent to v6'
);

select ok(
  (
    select pg_catalog.count(*) =
      pg_catalog.current_setting(
        'assignment.export_assignment_count'
      )::bigint
    from public.active_list_item_assignments
  )
  and (
    select pg_catalog.count(*) =
      pg_catalog.current_setting(
        'assignment.export_item_count'
      )::bigint
    from public.active_list_items
  ),
  'both exports are read-only and retain all rows'
);

-- Real multi-session races: the pre-profile phase prevents the former
-- list-versus-profile cycle, then list serialization makes cleanup authoritative.
select extensions.dblink_connect(
  'assignment_race_setup',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=assignment_race_setup'
);
select extensions.dblink_connect(
  'assignment_race_hold',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=assignment_race_hold'
);
select extensions.dblink_connect(
  'assignment_race_mutation',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=assignment_race_mutation'
);
select extensions.dblink_connect(
  'assignment_race_delete',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=assignment_race_delete'
);
select extensions.dblink_connect(
  'assignment_race_remove',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=assignment_race_remove'
);

-- Clear any residue from an interrupted prior local run.
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    delete from auth.users
    where id in (
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000002',
      'b1000000-0000-4000-8000-000000000003',
      'b1000000-0000-4000-8000-000000000004'
    )
  $remote$
);
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    delete from private.deleted_username_reservations
    where canonical_username like 'asgn_%'
  $remote$
);

select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    insert into auth.users (
      id,
      email,
      email_confirmed_at,
      created_at,
      updated_at
    )
    values
      (
        'b1000000-0000-4000-8000-000000000001',
        'assignment-race-owner@example.test',
        now(),
        now(),
        now()
      ),
      (
        'b1000000-0000-4000-8000-000000000002',
        'assignment-race-delete@example.test',
        now(),
        now(),
        now()
      ),
      (
        'b1000000-0000-4000-8000-000000000003',
        'assignment-race-remove-owner@example.test',
        now(),
        now(),
        now()
      ),
      (
        'b1000000-0000-4000-8000-000000000004',
        'assignment-race-remove-member@example.test',
        now(),
        now(),
        now()
      )
  $remote$
);
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    update public.profiles
    set username = case id
          when 'b1000000-0000-4000-8000-000000000001'
            then 'asgn_race_owner'
          when 'b1000000-0000-4000-8000-000000000002'
            then 'asgn_race_delete'
          when 'b1000000-0000-4000-8000-000000000003'
            then 'asgn_rm_owner'
          else 'asgn_rm_member'
        end,
        display_name = 'Assignment race'
    where id in (
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000002',
      'b1000000-0000-4000-8000-000000000003',
      'b1000000-0000-4000-8000-000000000004'
    )
  $remote$
);
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    insert into public.active_lists (
      id,
      owner_id,
      title,
      creation_request_id
    )
    values
      (
        'b2000000-0000-4000-8000-000000000001',
        'b1000000-0000-4000-8000-000000000001',
        'Profile delete race',
        'b3000000-0000-4000-8000-000000000001'
      ),
      (
        'b2000000-0000-4000-8000-000000000002',
        'b1000000-0000-4000-8000-000000000003',
        'Member removal race',
        'b3000000-0000-4000-8000-000000000002'
      )
  $remote$
);
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    insert into public.active_list_participants (
      list_id,
      participant_profile_id,
      state
    )
    values
      (
        'b2000000-0000-4000-8000-000000000001',
        'b1000000-0000-4000-8000-000000000002',
        'member'
      ),
      (
        'b2000000-0000-4000-8000-000000000002',
        'b1000000-0000-4000-8000-000000000004',
        'member'
      )
  $remote$
);
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    insert into public.active_list_items (
      id,
      list_id,
      name,
      position,
      creation_request_id
    )
    values
      (
        'b4000000-0000-4000-8000-000000000001',
        'b2000000-0000-4000-8000-000000000001',
        'Existing assigned race item',
        1,
        'b5000000-0000-4000-8000-000000000001'
      ),
      (
        'b4000000-0000-4000-8000-000000000002',
        'b2000000-0000-4000-8000-000000000002',
        'Removal race item',
        1,
        'b5000000-0000-4000-8000-000000000002'
      )
  $remote$
);
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    insert into public.active_list_item_assignments (
      list_id,
      item_id,
      assignee_profile_id
    )
    values (
      'b2000000-0000-4000-8000-000000000001',
      'b4000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000002'
    )
  $remote$
);

-- Hold the list, queue assignment first (it must prelock the profile), then
-- queue profile deletion. Releasing the list would deadlock under list-first
-- assignment ordering but now deterministically commits mutation then cleanup.
select extensions.dblink_exec('assignment_race_hold', 'begin');
select extensions.dblink_exec(
  'assignment_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'b2000000-0000-4000-8000-000000000001'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('assignment_race_mutation', 'begin');
select extensions.dblink_exec(
  'assignment_race_mutation',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'assignment_race_mutation',
  $remote$
    set local "request.jwt.claim.sub" =
      'b1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'assignment_race_mutation',
    $remote$
      select *
      from public.create_active_list_item_v2(
        'b2000000-0000-4000-8000-000000000001',
        'Concurrent assigned item',
        'b5000000-0000-4000-8000-000000000003',
        1,
        array[
          'b1000000-0000-4000-8000-000000000002'::uuid
        ]
      )
    $remote$
  ),
  1,
  'profile-race assignment query starts asynchronously'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('assignment_race_mutation') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'assignment_race_mutation'
      and wait_event_type = 'Lock'
  ),
  'assignment has reached its list wait after prelocking desired profile'
);

select is(
  extensions.dblink_send_query(
    'assignment_race_delete',
    $remote$
      with deleted as (
        delete from auth.users
        where id = 'b1000000-0000-4000-8000-000000000002'
        returning id
      )
      select pg_catalog.count(*)::bigint as deleted_count
      from deleted
    $remote$
  ),
  1,
  'profile deletion starts while assignment owns the profile prelock'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('assignment_race_delete') = 1,
  'profile deletion waits without forming a lock cycle'
);

select extensions.dblink_exec('assignment_race_hold', 'commit');
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('assignment_race_mutation')
      as mutation_result(
        item_id uuid,
        list_version bigint,
        name text,
        quantity_thousandths bigint,
        unit_code text,
        "position" integer,
        version bigint,
        completed_at timestamptz,
        completed_by uuid,
        created_at timestamptz,
        updated_at timestamptz,
        assignees jsonb
      )
  ),
  1::bigint,
  'assignment completes once the held list is released'
);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('assignment_race_mutation')
      as mutation_drain(status text)
  ),
  0::bigint,
  'profile-race assignment result queue is fully drained'
);
select extensions.dblink_exec('assignment_race_mutation', 'commit');
select is(
  (
    select deleted_count
    from extensions.dblink_get_result('assignment_race_delete')
      as delete_result(deleted_count bigint)
  ),
  1::bigint,
  'profile deletion completes after assignment commits without deadlock'
);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('assignment_race_delete')
      as deletion_drain(status text)
  ),
  0::bigint,
  'profile deletion result queue is fully drained'
);

select ok(
  not exists (
    select 1
    from public.profiles
    where id = 'b1000000-0000-4000-8000-000000000002'
  )
  and (
    select pg_catalog.count(*) = 2
    from public.active_list_items
    where list_id = 'b2000000-0000-4000-8000-000000000001'
      and version = 2
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select version = 3
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000001'
  ),
  'profile-delete race preserves both items, removes all assignments, and applies each serialized version'
);

-- Assignment versus member removal: both start against version one;
-- assignment serializes first, then removal authoritatively cleans it.
select extensions.dblink_exec('assignment_race_hold', 'begin');
select extensions.dblink_exec(
  'assignment_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'b2000000-0000-4000-8000-000000000002'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('assignment_race_mutation', 'begin');
select extensions.dblink_exec(
  'assignment_race_mutation',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'assignment_race_mutation',
  $remote$
    set local "request.jwt.claim.sub" =
      'b1000000-0000-4000-8000-000000000003'
  $remote$
);
select extensions.dblink_exec('assignment_race_remove', 'begin');
select extensions.dblink_exec(
  'assignment_race_remove',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'assignment_race_remove',
  $remote$
    set local "request.jwt.claim.sub" =
      'b1000000-0000-4000-8000-000000000003'
  $remote$
);

select is(
  extensions.dblink_send_query(
    'assignment_race_mutation',
    $remote$
      select *
      from public.update_active_list_item_v2(
        'b2000000-0000-4000-8000-000000000002',
        'b4000000-0000-4000-8000-000000000002',
        'Removal race item',
        1000,
        null,
        array[
          'b1000000-0000-4000-8000-000000000004'::uuid
        ],
        1,
        1
      )
    $remote$
  ),
  1,
  'concurrent assignment update starts first'
);
select pg_catalog.pg_sleep(0.2);
select is(
  extensions.dblink_send_query(
    'assignment_race_remove',
    $remote$
      select public.remove_active_list_member(
        'b2000000-0000-4000-8000-000000000002',
        'b1000000-0000-4000-8000-000000000004',
        1
      ) as access_version
    $remote$
  ),
  1,
  'concurrent member removal queues behind the same list'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('assignment_race_mutation') = 1
  and extensions.dblink_is_busy('assignment_race_remove') = 1,
  'both assignment and removal remain bounded on the held list lock'
);

select extensions.dblink_exec('assignment_race_hold', 'commit');
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('assignment_race_mutation')
      as mutation_result(
        item_id uuid,
        list_version bigint,
        name text,
        quantity_thousandths bigint,
        unit_code text,
        "position" integer,
        version bigint,
        completed_at timestamptz,
        completed_by uuid,
        created_at timestamptz,
        updated_at timestamptz,
        assignees jsonb
      )
  ),
  1::bigint,
  'queued assignment commits first'
);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('assignment_race_mutation')
      as mutation_drain(status text)
  ),
  0::bigint,
  'removal-race assignment result queue is fully drained'
);
select extensions.dblink_exec('assignment_race_mutation', 'commit');
select is(
  (
    select access_version
    from extensions.dblink_get_result('assignment_race_remove')
      as remove_result(access_version bigint)
  ),
  2::bigint,
  'queued removal then commits the expected access version'
);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('assignment_race_remove')
      as removal_drain(status text)
  ),
  0::bigint,
  'member-removal result queue is fully drained'
);
select extensions.dblink_exec('assignment_race_remove', 'commit');

select ok(
  (
    select state = 'removed' and version = 2
    from public.active_list_participants
    where list_id = 'b2000000-0000-4000-8000-000000000002'
      and participant_profile_id =
        'b1000000-0000-4000-8000-000000000004'
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'b2000000-0000-4000-8000-000000000002'
  )
  and (
    select version = 3
    from public.active_list_items
    where id = 'b4000000-0000-4000-8000-000000000002'
  )
  and (
    select version = 3
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000002'
  ),
  'simultaneous assignment/removal never leaves an ineligible row and preserves serialized versions'
);

-- Reverse serialization: access loss owns the list first, so a queued member
-- mutation must wake, re-authorize, and fail without any assignment side effect.
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    do $block$
    begin
      update public.active_list_participants
      set state = 'member',
          version = 3,
          state_changed_at = now()
      where list_id = 'b2000000-0000-4000-8000-000000000002'
        and participant_profile_id =
          'b1000000-0000-4000-8000-000000000004';

      delete from public.user_notifications
      where active_list_id = 'b2000000-0000-4000-8000-000000000002';
    end
    $block$
  $remote$
);
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    delete from realtime.messages
    where topic like 'account:b1000000-0000-4000-8000-%'
  $remote$
);

select extensions.dblink_exec('assignment_race_remove', 'begin');
select extensions.dblink_exec(
  'assignment_race_remove',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'assignment_race_remove',
  $remote$
    set local "request.jwt.claim.sub" =
      'b1000000-0000-4000-8000-000000000003'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'assignment_race_remove',
    $remote$
      select public.remove_active_list_member(
        'b2000000-0000-4000-8000-000000000002',
        'b1000000-0000-4000-8000-000000000004',
        3
      ) as access_version
    $remote$
  ),
  1,
  'reverse race starts member removal first'
);
select is(
  (
    select access_version
    from extensions.dblink_get_result('assignment_race_remove')
      as remove_result(access_version bigint)
  ),
  4::bigint,
  'access loss is applied while its transaction retains the list lock'
);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('assignment_race_remove')
      as removal_drain(status text)
  ),
  0::bigint,
  'reverse-race member-removal result queue is fully drained'
);

select extensions.dblink_exec('assignment_race_mutation', 'begin');
select extensions.dblink_exec(
  'assignment_race_mutation',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'assignment_race_mutation',
  $remote$
    set local "request.jwt.claim.sub" =
      'b1000000-0000-4000-8000-000000000004'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'assignment_race_mutation',
    $remote$
      select *
      from public.update_active_list_item_v2(
        'b2000000-0000-4000-8000-000000000002',
        'b4000000-0000-4000-8000-000000000002',
        'Forbidden after removal',
        1000,
        null,
        array[
          'b1000000-0000-4000-8000-000000000004'::uuid
        ],
        3,
        3
      )
    $remote$
  ),
  1,
  'removed member mutation queues behind the uncommitted access loss'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('assignment_race_mutation') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'assignment_race_mutation'
      and wait_event_type = 'Lock'
  ),
  'removed member mutation reaches a bounded lock wait before re-authorization'
);

select extensions.dblink_exec('assignment_race_remove', 'commit');
select throws_like(
  $$select *
    from extensions.dblink_get_result('assignment_race_mutation')
      as mutation_result(
        item_id uuid,
        list_version bigint,
        name text,
        quantity_thousandths bigint,
        unit_code text,
        "position" integer,
        version bigint,
        completed_at timestamptz,
        completed_by uuid,
        created_at timestamptz,
        updated_at timestamptz,
        assignees jsonb
      )$$,
  '%list unavailable%',
  'queued mutation re-authorizes after access loss and rejects the removed caller'
);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('assignment_race_mutation')
      as mutation_drain(status text)
  ),
  0::bigint,
  'rejected reverse-race mutation result queue is fully drained'
);
select extensions.dblink_exec('assignment_race_mutation', 'rollback');

select ok(
  (
    select state = 'removed' and version = 4
    from public.active_list_participants
    where list_id = 'b2000000-0000-4000-8000-000000000002'
      and participant_profile_id =
        'b1000000-0000-4000-8000-000000000004'
  )
  and (
    select version = 4
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000002'
  )
  and (
    select name = 'Removal race item' and version = 3
    from public.active_list_items
    where id = 'b4000000-0000-4000-8000-000000000002'
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'b2000000-0000-4000-8000-000000000002'
  )
  and (
    select pg_catalog.count(*) = 0
    from public.user_notifications
    where active_list_id = 'b2000000-0000-4000-8000-000000000002'
      and notification_type = 'list_item_assigned'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.user_notifications
    where active_list_id = 'b2000000-0000-4000-8000-000000000002'
      and notification_type = 'list_member_removed'
      and access_version = 4
  ),
  'access-loss-first serialization leaves no assignment, item, version, or notification side effect'
);

select ok(
  (
    select pg_catalog.count(*) = 4
      and pg_catalog.bool_and(
        extension = 'broadcast'
        and event = 'invalidate'
        and payload - 'id' = '{"v":1}'::jsonb
        and private
        and topic in (
          'account:b1000000-0000-4000-8000-000000000003',
          'account:b1000000-0000-4000-8000-000000000004'
        )
      )
    from realtime.messages
    where topic like 'account:b1000000-0000-4000-8000-%'
  )
  and (
    select pg_catalog.count(*) = 2
    from realtime.messages
    where topic =
      'account:b1000000-0000-4000-8000-000000000003'
  )
  and (
    select pg_catalog.count(*) = 2
    from realtime.messages
    where topic =
      'account:b1000000-0000-4000-8000-000000000004'
  ),
  'failed queued assignment emits no invalidation beyond the exact access-loss and notification events'
);

-- Remove autonomous fixtures and their deliberate username reservations.
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    delete from auth.users
    where id in (
      'b1000000-0000-4000-8000-000000000001',
      'b1000000-0000-4000-8000-000000000003',
      'b1000000-0000-4000-8000-000000000004'
    )
  $remote$
);
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    delete from private.deleted_username_reservations
    where canonical_username like 'asgn_%'
  $remote$
);
select extensions.dblink_exec(
  'assignment_race_setup',
  $remote$
    delete from realtime.messages
    where topic like 'account:b1000000-0000-4000-8000-%'
  $remote$
);
select ok(
  not exists (
    select 1
    from auth.users
    where id::text like 'b1000000-0000-4000-8000-%'
  )
  and not exists (
    select 1
    from public.active_lists
    where id::text like 'b2000000-0000-4000-8000-%'
  )
  and not exists (
    select 1
    from private.deleted_username_reservations
    where canonical_username like 'asgn_%'
  )
  and not exists (
    select 1
    from realtime.messages
    where topic like 'account:b1000000-0000-4000-8000-%'
  ),
  'autonomous race fixtures, reservations, and Broadcast rows are fully removed'
);

select extensions.dblink_disconnect('assignment_race_hold');
select extensions.dblink_disconnect('assignment_race_mutation');
select extensions.dblink_disconnect('assignment_race_delete');
select extensions.dblink_disconnect('assignment_race_remove');
select extensions.dblink_disconnect('assignment_race_setup');

select * from finish();
rollback;
