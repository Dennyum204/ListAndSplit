begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function(
  'public', 'list_active_lists_v2',
  array['text', 'integer', 'timestamp with time zone', 'uuid'],
  'the participant-aware list page has the unchanged input signature'
);
select has_function(
  'public', 'get_active_list_v2', array['uuid'],
  'the participant-aware detail has the unchanged input signature'
);
select ok(
  (
    select pg_catalog.bool_and(
      not function_record.prosecdef
      and function_record.provolatile = 's'
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
      and pg_catalog.obj_description(function_record.oid, 'pg_proc') is not null
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.list_active_lists_v2(text,integer,timestamptz,uuid)'::regprocedure,
      'public.get_active_list_v2(uuid)'::regprocedure
    )
  ),
  'stable postgres-owned wrappers have an empty search path and no new definer authority'
);
select ok(
  (
    select pg_catalog.bool_and(
      pg_catalog.has_function_privilege('authenticated', function_record.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', function_record.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('service_role', function_record.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('public', function_record.oid, 'EXECUTE')
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.list_active_lists_v2(text,integer,timestamptz,uuid)'::regprocedure,
      'public.get_active_list_v2(uuid)'::regprocedure
    )
  ),
  'only authenticated receives each exact v2 execution grant'
);
select is(
  (
    select function_record.proargnames
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'public.list_active_lists(text,integer,timestamptz,uuid)'::regprocedure
  ),
  array[
    'requested_status', 'page_size', 'before_sort_at', 'before_list_id',
    'list_id', 'title', 'status', 'version', 'item_count', 'completed_item_count',
    'created_at', 'updated_at', 'archived_at', 'is_owner', 'owner_profile_id',
    'owner_username', 'owner_display_name', 'caller_access_version'
  ],
  'the legacy list RPC retains its exact argument and result names'
);
select is(
  (
    select function_record.proargnames
    from pg_catalog.pg_proc as function_record
    where function_record.oid = 'public.get_active_list(uuid)'::regprocedure
  ),
  array[
    'target_list_id', 'list_id', 'title', 'status', 'version', 'item_count',
    'completed_item_count', 'created_at', 'updated_at', 'archived_at', 'is_owner',
    'owner_profile_id', 'owner_username', 'owner_display_name', 'caller_access_version'
  ],
  'the legacy detail RPC retains its exact argument and result names'
);
select is(
  (
    select function_record.pronargdefaults
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'public.list_active_lists_v2(text,integer,timestamptz,uuid)'::regprocedure
  ),
  3::smallint,
  'v2 preserves the default page size and nullable cursor arguments'
);
select ok(
  (
    select pg_catalog.bool_and(
      function_record.proargnames[pg_catalog.array_length(function_record.proargnames, 1)]
        = 'participant_count'
      and function_record.proallargtypes[pg_catalog.array_length(function_record.proallargtypes, 1)]
        = 'bigint'::regtype
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.list_active_lists_v2(text,integer,timestamptz,uuid)'::regprocedure,
      'public.get_active_list_v2(uuid)'::regprocedure
    )
  ),
  'the only appended projection member is a bigint participant count'
);
select ok(
  not pg_catalog.has_table_privilege('authenticated', 'public.active_lists', 'SELECT,INSERT,UPDATE,DELETE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.active_list_participants', 'SELECT,INSERT,UPDATE,DELETE')
  and not pg_catalog.has_table_privilege('anon', 'public.active_list_participants', 'SELECT,INSERT,UPDATE,DELETE')
  and not pg_catalog.has_table_privilege('service_role', 'public.active_list_participants', 'SELECT,INSERT,UPDATE,DELETE'),
  'the read wrappers do not broaden direct list or participant privileges'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_attribute as column_record
    where column_record.attrelid in (
      'public.active_lists'::regclass, 'public.active_list_participants'::regclass
    )
      and column_record.attname = 'participant_count'
      and not column_record.attisdropped
  ),
  'the participant count is derived rather than stored'
);

set local role anon;
select throws_like(
  $$select * from public.list_active_lists_v2('active')$$,
  '%permission denied%', 'anonymous callers cannot list participant counts'
);
select throws_like(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')$$,
  '%permission denied%', 'anonymous callers cannot read a participant count by ID'
);
reset role;
set local role service_role;
select throws_like(
  $$select * from public.list_active_lists_v2('active')$$,
  '%permission denied%', 'the service API role cannot list participant counts'
);
select throws_like(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')$$,
  '%permission denied%', 'the service API role cannot read a participant count by ID'
);
reset role;

-- All identities and lifecycle mutations below are local transactional fixtures.
insert into auth.users (id, email, email_confirmed_at, created_at, updated_at)
select
  ('87000000-0000-4000-8000-' || pg_catalog.lpad(identity_number::text, 12, '0'))::uuid,
  'participant-count-' || identity_number::text || '@counts.test',
  case when identity_number = 10 then null else now() end,
  now(),
  now()
from pg_catalog.generate_series(1, 11) as identity_number;

insert into auth.users (id, email, email_confirmed_at, created_at, updated_at)
select
  ('87000000-0000-4000-8000-' || pg_catalog.lpad(identity_number::text, 12, '0'))::uuid,
  'participant-count-' || identity_number::text || '@counts.test',
  now(), now(), now()
from pg_catalog.generate_series(20, 38) as identity_number;

update public.profiles
set username = 'count_' || pg_catalog.right(id::text, 2),
    display_name = 'Count ' || pg_catalog.right(id::text, 2)
where id::text like '87000000-0000-4000-8000-%'
  and id <> '87000000-0000-4000-8000-000000000009';

insert into public.user_relationships (
  profile_low_id, profile_high_id, state, requester_id
)
select
  '87000000-0000-4000-8000-000000000001',
  profile_record.id,
  'friends',
  '87000000-0000-4000-8000-000000000001'
from public.profiles as profile_record
where profile_record.id::text like '87000000-0000-4000-8000-%'
  and profile_record.id <> '87000000-0000-4000-8000-000000000001'
  and profile_record.onboarding_completed_at is not null;

insert into public.active_lists (
  id, owner_id, title, status, version, creation_request_id,
  created_at, updated_at, archived_at
) values
  ('88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000001',
   'Counted shared list', 'active', 5, '89000000-0000-4000-8000-000000000001',
   '2026-08-01 08:00:00+00', '2026-08-01 08:00:00+00', null),
  ('88000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000001',
   'Empty solo list', 'active', 1, '89000000-0000-4000-8000-000000000002',
   '2026-08-02 08:00:00+00', '2026-08-02 08:00:00+00', null),
  ('88000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000008',
   'Unrelated private list', 'active', 1, '89000000-0000-4000-8000-000000000003',
   '2026-08-03 08:00:00+00', '2026-08-03 08:00:00+00', null),
  ('88000000-0000-4000-8000-000000000004', '87000000-0000-4000-8000-000000000001',
   'Archived shared list', 'archived', 2, '89000000-0000-4000-8000-000000000004',
   '2026-08-01 08:00:00+00', '2026-08-04 08:00:00+00', '2026-08-04 08:00:00+00'),
  ('88000000-0000-4000-8000-000000000010', '87000000-0000-4000-8000-000000000001',
   'Page A', 'active', 1, '89000000-0000-4000-8000-000000000010',
   '2026-08-03 08:00:00+00', '2026-08-03 08:00:00+00', null),
  ('88000000-0000-4000-8000-000000000011', '87000000-0000-4000-8000-000000000001',
   'Page B', 'active', 1, '89000000-0000-4000-8000-000000000011',
   '2026-08-03 08:00:00+00', '2026-08-03 08:00:00+00', null),
  ('88000000-0000-4000-8000-000000000012', '87000000-0000-4000-8000-000000000001',
   'Page C', 'active', 1, '89000000-0000-4000-8000-000000000012',
   '2026-08-03 08:00:00+00', '2026-08-03 08:00:00+00', null),
  ('88000000-0000-4000-8000-000000000020', '87000000-0000-4000-8000-000000000001',
   'Full participant list', 'active', 1, '89000000-0000-4000-8000-000000000020',
   '2026-07-31 08:00:00+00', '2026-07-31 08:00:00+00', null);

insert into public.active_list_participants (
  list_id, participant_profile_id, state, version
) values
  ('88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000002', 'member', 1),
  ('88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000003', 'pending', 1),
  ('88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000004', 'declined', 1),
  ('88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000005', 'cancelled', 1),
  ('88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000006', 'removed', 1),
  ('88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000007', 'left', 1),
  ('88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000011', 'member', 1),
  ('88000000-0000-4000-8000-000000000004', '87000000-0000-4000-8000-000000000002', 'member', 1);

insert into public.active_list_participants (list_id, participant_profile_id, state)
select
  '88000000-0000-4000-8000-000000000020',
  ('87000000-0000-4000-8000-' || pg_catalog.lpad(identity_number::text, 12, '0'))::uuid,
  'member'
from pg_catalog.generate_series(20, 38) as identity_number;

insert into public.active_list_items (
  id, list_id, name, position, creation_request_id, completed_at, completed_by
)
select
  ('88000000-0000-4000-8000-' || pg_catalog.lpad((100 + item_number)::text, 12, '0'))::uuid,
  '88000000-0000-4000-8000-000000000001',
  'Count item ' || item_number::text,
  item_number,
  ('89000000-0000-4000-8000-' || pg_catalog.lpad((100 + item_number)::text, 12, '0'))::uuid,
  case when item_number <= 2 then now() else null end,
  case when item_number <= 2 then '87000000-0000-4000-8000-000000000001'::uuid else null end
from pg_catalog.generate_series(1, 3) as item_number;

create temporary table participant_count_snapshot (label text primary key, value jsonb)
on commit drop;
grant select, insert on participant_count_snapshot to authenticated;
insert into participant_count_snapshot
select 'list', pg_catalog.to_jsonb(list_record)
from public.active_lists as list_record
where list_record.id = '88000000-0000-4000-8000-000000000001';
insert into participant_count_snapshot
select 'notifications', pg_catalog.to_jsonb(pg_catalog.count(*))
from public.user_notifications;
insert into participant_count_snapshot
select 'broadcasts', pg_catalog.to_jsonb(pg_catalog.count(*))
from realtime.messages;

set local role authenticated;
set local "request.jwt.claim.sub" = '';
select throws_ok(
  $$select * from public.list_active_lists_v2('active')$$,
  '42501', 'verified profile required', 'authenticated role alone grants no list access'
);
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')$$,
  '42501', 'verified profile required', 'authenticated role alone grants no detail access'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000009';
select throws_ok(
  $$select * from public.list_active_lists_v2('active')$$,
  '42501', 'verified profile required', 'incomplete profiles cannot list counts'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000010';
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')$$,
  '42501', 'verified profile required', 'unverified profiles cannot read counts'
);

set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000001';
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  3::bigint,
  'the owner counts themselves and accepted members, excluding every pending/dormant state'
);
select ok(
  (select participant_count = 3 and item_count = 3 and completed_item_count = 2
   from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  'multiple items do not multiply participants or corrupt item/completion counts'
);
select ok(
  (select participant_count = 1 and item_count = 0 and completed_item_count = 0
   from public.get_active_list_v2('88000000-0000-4000-8000-000000000002')),
  'an empty solo list still contains its one owner'
);
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000020')),
  20::bigint,
  'a list at the accepted participant limit counts its owner and nineteen members'
);
select is(
  (select pg_catalog.to_jsonb(current_summary) - 'participant_count'
   from public.get_active_list_v2('88000000-0000-4000-8000-000000000001') as current_summary),
  (select pg_catalog.to_jsonb(legacy_summary)
   from public.get_active_list('88000000-0000-4000-8000-000000000001') as legacy_summary),
  'v2 detail preserves every legacy field and adds only participant_count'
);
select is(
  (select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(current_summary) - 'participant_count'
     order by current_summary.updated_at desc, current_summary.list_id desc)
   from public.list_active_lists_v2('active') as current_summary),
  (select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(legacy_summary)
     order by legacy_summary.updated_at desc, legacy_summary.list_id desc)
   from public.list_active_lists('active') as legacy_summary),
  'v2 listing preserves legacy content, eligibility and order'
);
select ok(
  (select pg_catalog.bool_and(list_summary.participant_count = (
      select pg_catalog.count(*) from public.list_active_list_participants(list_summary.list_id)
    ))
   from public.list_active_lists_v2('active') as list_summary),
  'every listed count matches the independently authorized participant projection'
);
select is(
  (select pg_catalog.count(*) from public.list_active_lists_v2('active')
   where list_id = '88000000-0000-4000-8000-000000000003'),
  0::bigint,
  'a list owner cannot discover another account private list through counts'
);
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000003')$$,
  'P0002', 'list unavailable', 'a foreign list ID cannot reveal its count'
);
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000099')$$,
  'P0002', 'list unavailable', 'a nonexistent list has the same unavailable outcome'
);
select throws_ok(
  $$select * from public.get_active_list_v2(null)$$,
  'P0002', 'list unavailable', 'a null list ID preserves the legacy outcome'
);
select throws_ok(
  $$select * from public.list_active_lists_v2('other')$$,
  '22023', 'invalid list status', 'v2 preserves status validation'
);
select throws_ok(
  $$select * from public.list_active_lists_v2('active', 51)$$,
  '22023', 'invalid list page size', 'v2 retains the maximum fifty-row page'
);
select throws_ok(
  $$select * from public.list_active_lists_v2('active', 0)$$,
  '22023', 'invalid list page size', 'v2 rejects an empty page bound'
);
select throws_ok(
  $$select * from public.list_active_lists_v2('active', 20, now(), null)$$,
  '22023', 'invalid list cursor', 'v2 rejects a partial timestamp cursor'
);
select throws_ok(
  $$select * from public.list_active_lists_v2('active', 20, null, '88000000-0000-4000-8000-000000000001')$$,
  '22023', 'invalid list cursor', 'v2 rejects a partial identity cursor'
);
select is(
  (select pg_catalog.array_agg(list_id order by ordinality)
   from public.list_active_lists_v2('active', 2) with ordinality),
  array['88000000-0000-4000-8000-000000000012', '88000000-0000-4000-8000-000000000011']::uuid[],
  'equal timestamps are ordered by descending list ID before pagination'
);
select is(
  (select pg_catalog.array_agg(list_id order by ordinality)
   from public.list_active_lists_v2(
     'active', 2, '2026-08-03 08:00:00+00', '88000000-0000-4000-8000-000000000011'
   ) with ordinality),
  array['88000000-0000-4000-8000-000000000010', '88000000-0000-4000-8000-000000000002']::uuid[],
  'the exclusive keyset cursor neither skips nor repeats a timestamp tie'
);
select ok(
  (select participant_count = 2 and status = 'archived'
   from public.list_active_lists_v2('archived')
   where list_id = '88000000-0000-4000-8000-000000000004'),
  'archived overview rows contain their current owner and accepted members'
);
insert into participant_count_snapshot
select 'export', public.export_own_account_data_v12() - 'exported_at';
select ok(
  not exists (
    select 1
    from pg_catalog.jsonb_array_elements(public.export_own_account_data_v12() -> 'active_lists') as owned_list
    where owned_list ? 'participant_count'
  ),
  'export v12 does not acquire a participant count field'
);

set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000002';
select ok(
  (select not is_owner and participant_count = 3 and caller_access_version = 1
   from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  'an accepted member sees the same count and unchanged caller-relative metadata'
);
select is(
  (select participant_count from public.list_active_lists_v2('active')
   where list_id = '88000000-0000-4000-8000-000000000001'),
  3::bigint, 'members receive participant counts on overview pages'
);
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000004')),
  2::bigint, 'accepted members can read archived participant counts'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')$$,
  'P0002', 'list unavailable', 'a pending invitation grants no count read access'
);
select is(
  (select pg_catalog.count(*) from public.list_active_lists_v2('active')),
  0::bigint, 'pending invitees receive no list overview projection'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000006';
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')$$,
  'P0002', 'list unavailable', 'retained removed access grants no count read access'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000008';
select is(
  (select pg_catalog.count(*) from public.list_active_lists_v2('active')
   where list_id = '88000000-0000-4000-8000-000000000001'),
  0::bigint, 'an unrelated account cannot discover the shared-list count'
);

reset role;
select is(
  (select pg_catalog.to_jsonb(list_record) from public.active_lists as list_record
   where list_record.id = '88000000-0000-4000-8000-000000000001'),
  (select value from participant_count_snapshot where label = 'list'),
  'count reads leave list versions and every stored field unchanged'
);
select is(
  (select pg_catalog.to_jsonb(pg_catalog.count(*)) from public.user_notifications),
  (select value from participant_count_snapshot where label = 'notifications'),
  'count reads create no notification rows'
);
select is(
  (select pg_catalog.to_jsonb(pg_catalog.count(*)) from realtime.messages),
  (select value from participant_count_snapshot where label = 'broadcasts'),
  'count reads emit no Broadcast messages'
);
set local role authenticated;
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000001';
select is(
  public.export_own_account_data_v12() - 'exported_at',
  (select value from participant_count_snapshot where label = 'export'),
  'count reads leave the complete version-twelve export unchanged'
);

-- Exercise actual accepted access transitions rather than updating count data.
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000003';
select is(
  public.accept_active_list_invitation('88000000-0000-4000-8000-000000000001', 1),
  2::bigint, 'the pending fixture accepts its invitation'
);
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  4::bigint, 'acceptance adds exactly one current participant'
);
select is(
  public.accept_active_list_invitation('88000000-0000-4000-8000-000000000001', 1),
  2::bigint, 'an accepted invitation retry remains idempotent'
);
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  4::bigint, 'acceptance retry does not count a participant twice'
);
select is(
  public.leave_active_list('88000000-0000-4000-8000-000000000001', 2),
  3::bigint, 'the participant leaves through the existing access boundary'
);
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')$$,
  'P0002', 'list unavailable', 'a departed member immediately loses count read access'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000001';
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  3::bigint, 'departure reduces the owner-visible count'
);
select lives_ok(
  $$select * from public.invite_active_list_member(
    '88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000003', 3
  )$$,
  'the owner reinvites the departed friend'
);
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  3::bigint, 'reinvitation alone does not restore the count'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000003';
select is(
  public.accept_active_list_invitation('88000000-0000-4000-8000-000000000001', 4),
  5::bigint, 'the former participant accepts the new invitation version'
);
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  4::bigint, 'reacceptance adds the participant exactly once'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000001';
select is(
  public.remove_active_list_member(
    '88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000003', 5
  ),
  6::bigint, 'the owner removes the accepted member'
);
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  3::bigint, 'owner removal reduces the count without counting its retained access row'
);
select lives_ok(
  $$select * from public.invite_active_list_member(
    '88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000003', 6
  )$$,
  'the owner reinvites the removed member for block-lifecycle coverage'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000003';
select is(
  public.accept_active_list_invitation('88000000-0000-4000-8000-000000000001', 7),
  8::bigint, 'the removed member accepts the later invitation'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.block_profile('87000000-0000-4000-8000-000000000003')$$,
  'owner blocking applies the existing membership separation'
);
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  3::bigint, 'block-driven access loss reduces the count'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')$$,
  'P0002', 'list unavailable', 'a blocked former member cannot read the count by ID'
);
select is(
  (select pg_catalog.count(*) from public.list_active_lists_v2('active')),
  0::bigint, 'a blocked former member cannot see the count in overview'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.unblock_profile('87000000-0000-4000-8000-000000000003')$$,
  'unblocking follows the existing relationship boundary'
);
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  3::bigint, 'unblocking never restores the old participant count'
);

select lives_ok(
  $$select * from public.transfer_active_list_ownership(
    '88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000002',
    (select version from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')), 1
  )$$,
  'ownership transfers to an existing accepted member'
);
select ok(
  (select participant_count = 3 and not is_owner
   from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  'the former owner stays counted exactly once as a member'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000002';
select ok(
  (select participant_count = 3 and is_owner
   from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  'the new owner retained owner row is not counted a second time'
);
select lives_ok(
  $$select * from public.transfer_active_list_ownership(
    '88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000001',
    (select version from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')), 1
  )$$,
  'a second transfer reuses both retained access lineages'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000001';
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  3::bigint, 'repeated transfer preserves the current participant count'
);

reset role;
delete from auth.users where id = '87000000-0000-4000-8000-000000000011';
set local role authenticated;
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000001';
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
  2::bigint, 'non-owner account deletion removes that participant from the count'
);
select lives_ok(
  $$select * from public.invite_active_list_member(
    '88000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000004', 1
  )$$,
  'the owner opens a pending invitation before archive'
);
select lives_ok(
  $$select * from public.set_active_list_archived(
    '88000000-0000-4000-8000-000000000001', true,
    (select version from public.get_active_list_v2('88000000-0000-4000-8000-000000000001'))
  )$$,
  'the owner archives through the unchanged lifecycle boundary'
);
select is(
  (select participant_count from public.list_active_lists_v2('archived')
   where list_id = '88000000-0000-4000-8000-000000000001'),
  2::bigint, 'archive cancels pending access without changing current participant count'
);
select is(
  (select pg_catalog.array_agg(list_id order by ordinality)
   from public.list_active_lists_v2('archived', 1) with ordinality),
  array['88000000-0000-4000-8000-000000000001']::uuid[],
  'archived pages use archive time rather than active-list update ordering'
);
select is(
  (select pg_catalog.array_agg(list_id order by ordinality)
   from public.list_active_lists_v2(
     'archived', 1,
     (select archived_at from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')),
     '88000000-0000-4000-8000-000000000001'
   ) with ordinality),
  array['88000000-0000-4000-8000-000000000004']::uuid[],
  'archived keyset pagination remains exclusive and deterministic'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000002';
select is(
  public.leave_active_list(
    '88000000-0000-4000-8000-000000000001',
    (select caller_access_version from public.get_active_list_v2('88000000-0000-4000-8000-000000000001'))
  ),
  4::bigint, 'the retained member may leave while archived'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000001';
select is(
  (select participant_count from public.list_active_lists_v2('archived')
   where list_id = '88000000-0000-4000-8000-000000000001'),
  1::bigint, 'archived-member departure leaves only the owner in the count'
);
select lives_ok(
  $$select * from public.set_active_list_archived(
    '88000000-0000-4000-8000-000000000001', false,
    (select version from public.get_active_list_v2('88000000-0000-4000-8000-000000000001'))
  )$$,
  'the owner restores the list'
);
select is(
  (select participant_count from public.list_active_lists_v2('active')
   where list_id = '88000000-0000-4000-8000-000000000001'),
  1::bigint, 'restore never resurrects departed or cancelled access'
);
select lives_ok(
  $$select public.delete_active_list(
    '88000000-0000-4000-8000-000000000001',
    (select version from public.get_active_list_v2('88000000-0000-4000-8000-000000000001'))
  )$$,
  'the owner permanently deletes the list through the existing boundary'
);
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000001')$$,
  'P0002', 'list unavailable', 'list deletion leaves no retained count to read'
);
select is(
  (select pg_catalog.count(*) from public.list_active_lists_v2('active')
   where list_id = '88000000-0000-4000-8000-000000000001'),
  0::bigint, 'list deletion removes the entire overview projection'
);
reset role;
delete from auth.users where id = '87000000-0000-4000-8000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000002';
select is(
  (select pg_catalog.count(*) from public.list_active_lists_v2('archived')),
  0::bigint, 'owner account deletion removes surviving shared-list counts for members'
);
select throws_ok(
  $$select * from public.get_active_list_v2('88000000-0000-4000-8000-000000000004')$$,
  'P0002', 'list unavailable', 'owner account deletion makes surviving list IDs unavailable'
);
set local "request.jwt.claim.sub" = '87000000-0000-4000-8000-000000000008';
select is(
  (select participant_count from public.get_active_list_v2('88000000-0000-4000-8000-000000000003')),
  1::bigint, 'another owner account and count remain unchanged after deletion'
);

reset role;
select * from finish();
rollback;
