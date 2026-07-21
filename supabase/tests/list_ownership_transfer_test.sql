begin;

create extension if not exists pgtap with schema extensions;
select plan(46);

select has_function(
  'public',
  'transfer_active_list_ownership',
  array['uuid', 'uuid', 'bigint', 'bigint'],
  'ownership transfer RPC exists with only reviewed arguments'
);
select ok(
  (
    select procedure.prosecdef
      and procedure.proowner = 'postgres'::regrole
      and procedure.proconfig @> array['search_path=""']
      and pg_catalog.obj_description(procedure.oid, 'pg_proc') is not null
    from pg_catalog.pg_proc as procedure
    where procedure.oid =
      'public.transfer_active_list_ownership(uuid,uuid,bigint,bigint)'::regprocedure
  ),
  'transfer RPC is a commented postgres-owned hardened definer boundary'
);
select ok(
  pg_catalog.has_function_privilege(
    'authenticated',
    'public.transfer_active_list_ownership(uuid,uuid,bigint,bigint)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'public.transfer_active_list_ownership(uuid,uuid,bigint,bigint)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'public.transfer_active_list_ownership(uuid,uuid,bigint,bigint)',
    'EXECUTE'
  ),
  'only authenticated receives the exact transfer RPC grant'
);
select ok(
  not pg_catalog.has_table_privilege(
    'authenticated',
    'public.active_lists',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'public.active_list_participants',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'public.user_notifications',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'ownership transfer adds no direct application-table grants'
);
select ok(
  (
    select pg_catalog.pg_get_constraintdef(constraint_record.oid)
      like '%owner%'
    from pg_catalog.pg_constraint as constraint_record
    where constraint_record.conrelid =
      'public.active_list_participants'::regclass
      and constraint_record.conname =
        'active_list_participants_state_check'
  ),
  'retained access state constraint includes internal owner state'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_record
    where trigger_record.tgname in (
      'active_list_participants_owner_access_consistency',
      'active_lists_owner_access_consistency'
    )
      and trigger_record.tgdeferrable
      and trigger_record.tginitdeferred
  ),
  2::bigint,
  'deferred consistency triggers protect both sides of the owner/access invariant'
);
select ok(
  (
    select pg_catalog.pg_get_constraintdef(constraint_record.oid)
      like '%list_ownership_transferred%'
    from pg_catalog.pg_constraint as constraint_record
    where constraint_record.conrelid = 'public.user_notifications'::regclass
      and constraint_record.conname = 'user_notifications_type_check'
  ),
  'notification type constraint includes ownership transfer'
);

set local role anon;
select throws_like(
  $$select * from public.transfer_active_list_ownership(
    gen_random_uuid(), gen_random_uuid(), 1, 1
  )$$,
  '%permission denied%',
  'anonymous transfer execution is denied'
);
reset role;

insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at
) values
  ('51000000-0000-4000-8000-000000000001', 'owner@transfer.test', now(), now(), now()),
  ('51000000-0000-4000-8000-000000000002', 'target@transfer.test', now(), now(), now()),
  ('51000000-0000-4000-8000-000000000003', 'member@transfer.test', now(), now(), now()),
  ('51000000-0000-4000-8000-000000000004', 'pending@transfer.test', now(), now(), now()),
  ('51000000-0000-4000-8000-000000000005', 'declined@transfer.test', now(), now(), now()),
  ('51000000-0000-4000-8000-000000000006', 'removed@transfer.test', now(), now(), now()),
  ('51000000-0000-4000-8000-000000000007', 'left@transfer.test', now(), now(), now()),
  ('51000000-0000-4000-8000-000000000008', 'unrelated@transfer.test', now(), now(), now()),
  ('51000000-0000-4000-8000-000000000009', 'blocked@transfer.test', now(), now(), now());

update public.profiles
set username = 'transfer_' || right(id::text, 1),
    display_name = 'Transfer ' || right(id::text, 1)
where id::text like '51000000-0000-4000-8000-00000000000_';

insert into public.active_lists (
  id,
  owner_id,
  title,
  version,
  creation_request_id,
  created_at,
  updated_at
) values (
  '52000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',
  'Transfer groceries',
  5,
  '52000000-0000-4000-8000-000000000011',
  '2026-07-21 08:00:00+00',
  '2026-07-21 08:00:00+00'
);

insert into public.active_list_items (
  id,
  list_id,
  name,
  quantity_thousandths,
  unit_code,
  position,
  version,
  creation_request_id,
  created_at,
  updated_at
) values
  (
    '52000000-0000-4000-8000-000000000101',
    '52000000-0000-4000-8000-000000000001',
    'Milk', 1500, 'l', 1, 3,
    '52000000-0000-4000-8000-000000000111',
    '2026-07-21 08:01:00+00', '2026-07-21 08:02:00+00'
  ),
  (
    '52000000-0000-4000-8000-000000000102',
    '52000000-0000-4000-8000-000000000001',
    'Bread', 1000, 'piece', 2, 1,
    '52000000-0000-4000-8000-000000000112',
    '2026-07-21 08:03:00+00', '2026-07-21 08:03:00+00'
  );

insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state,
  version,
  created_at,
  state_changed_at
) values
  ('52000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000002', 'member', 7, '2026-07-21 08:10:00+00', '2026-07-21 08:11:00+00'),
  ('52000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000003', 'member', 3, '2026-07-21 08:12:00+00', '2026-07-21 08:13:00+00'),
  ('52000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000004', 'pending', 2, '2026-07-21 08:14:00+00', '2026-07-21 08:15:00+00'),
  ('52000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000005', 'declined', 4, '2026-07-21 08:16:00+00', '2026-07-21 08:17:00+00'),
  ('52000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000006', 'removed', 5, '2026-07-21 08:18:00+00', '2026-07-21 08:19:00+00'),
  ('52000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000007', 'left', 6, '2026-07-21 08:20:00+00', '2026-07-21 08:21:00+00');

create temporary table transfer_snapshots (
  label text primary key,
  value jsonb
) on commit drop;

insert into transfer_snapshots values (
  'items',
  (
    select pg_catalog.jsonb_agg(to_jsonb(item_record) order by item_record.id)
    from public.active_list_items as item_record
    where item_record.list_id = '52000000-0000-4000-8000-000000000001'
  )
), (
  'other-access',
  (
    select pg_catalog.jsonb_agg(to_jsonb(access_record) order by access_record.participant_profile_id)
    from public.active_list_participants as access_record
    where access_record.list_id = '52000000-0000-4000-8000-000000000001'
      and access_record.participant_profile_id not in (
        '51000000-0000-4000-8000-000000000001',
        '51000000-0000-4000-8000-000000000002'
      )
  )
), (
  'capacity',
  to_jsonb((
    select pg_catalog.count(*)
    from public.active_list_participants as access_record
    where access_record.list_id = '52000000-0000-4000-8000-000000000001'
      and access_record.state in ('pending', 'member')
  ))
);

delete from realtime.messages;

set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000001';
select ok(
  (
    select result.owner_profile_id = '51000000-0000-4000-8000-000000000002'
      and result.previous_owner_profile_id = '51000000-0000-4000-8000-000000000001'
      and result.list_version = 6
      and result.previous_owner_access_version = 1
      and result.owner_access_version = 8
    from public.transfer_active_list_ownership(
      '52000000-0000-4000-8000-000000000001',
      '51000000-0000-4000-8000-000000000002',
      5,
      7
    ) as result
  ),
  'current owner transfers to an exact accepted member with allowlisted authoritative versions'
);
reset role;

select is(
  (
    select list_record.owner_id
    from public.active_lists as list_record
    where list_record.id = '52000000-0000-4000-8000-000000000001'
  ),
  '51000000-0000-4000-8000-000000000002'::uuid,
  'recipient becomes the sole authoritative owner'
);
select is(
  (
    select pg_catalog.count(*)
    from public.active_list_participants as access_record
    where access_record.list_id = '52000000-0000-4000-8000-000000000001'
      and access_record.state = 'owner'
      and access_record.participant_profile_id =
        '51000000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'exactly one retained owner lineage matches the authoritative owner'
);
select ok(
  exists (
    select 1
    from public.active_list_participants as access_record
    where access_record.list_id = '52000000-0000-4000-8000-000000000001'
      and access_record.participant_profile_id =
        '51000000-0000-4000-8000-000000000001'
      and access_record.state = 'member'
      and access_record.version = 1
  ),
  'former owner remains an accepted member with a retained version lineage'
);
select is(
  (
    select pg_catalog.count(*)
    from public.active_list_participants as access_record
    where access_record.list_id = '52000000-0000-4000-8000-000000000001'
      and access_record.state in ('pending', 'member')
  ),
  ((select value from transfer_snapshots where label = 'capacity') #>> '{}')::bigint,
  'participant capacity is unchanged by the owner/member swap'
);
select is(
  (
    select pg_catalog.jsonb_agg(to_jsonb(item_record) order by item_record.id)
    from public.active_list_items as item_record
    where item_record.list_id = '52000000-0000-4000-8000-000000000001'
  ),
  (select value from transfer_snapshots where label = 'items'),
  'items, completion, quantity, order, versions, and timestamps are unchanged'
);
select is(
  (
    select pg_catalog.jsonb_agg(to_jsonb(access_record) order by access_record.participant_profile_id)
    from public.active_list_participants as access_record
    where access_record.list_id = '52000000-0000-4000-8000-000000000001'
      and access_record.participant_profile_id not in (
        '51000000-0000-4000-8000-000000000001',
        '51000000-0000-4000-8000-000000000002'
      )
  ),
  (select value from transfer_snapshots where label = 'other-access'),
  'pending and other member access rows remain byte-for-byte unchanged'
);
select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications as notification_record
    where notification_record.active_list_id =
      '52000000-0000-4000-8000-000000000001'
      and notification_record.notification_type =
        'list_ownership_transferred'
      and notification_record.recipient_id =
        '51000000-0000-4000-8000-000000000002'
      and notification_record.actor_id =
        '51000000-0000-4000-8000-000000000001'
      and notification_record.access_participant_id =
        '51000000-0000-4000-8000-000000000001'
      and notification_record.access_version = 1
  ),
  1::bigint,
  'exactly one reference-only informational notification is created for the new owner'
);
select ok(
  (
    select pg_catalog.count(*) > 0
    from realtime.messages as message
    where message.topic =
      'account:51000000-0000-4000-8000-000000000001'
      and message.event = 'invalidate'
      and message.private
      and message.payload - 'id' = '{"v":1}'::jsonb
  ) and (
    select pg_catalog.count(*) > 0
    from realtime.messages as message
    where message.topic =
      'account:51000000-0000-4000-8000-000000000002'
      and message.event = 'invalidate'
      and message.private
      and message.payload - 'id' = '{"v":1}'::jsonb
  ) and (
    select pg_catalog.count(*) > 0
    from realtime.messages as message
    where message.topic =
      'account:51000000-0000-4000-8000-000000000003'
      and message.event = 'invalidate'
      and message.private
      and message.payload - 'id' = '{"v":1}'::jsonb
  ) and (
    select pg_catalog.count(*) > 0
    from realtime.messages as message
    where message.topic =
      'account:51000000-0000-4000-8000-000000000004'
      and message.event = 'invalidate'
      and message.private
      and message.payload - 'id' = '{"v":1}'::jsonb
  ) and not exists (
    select 1
    from realtime.messages as message
    where message.topic =
      'account:51000000-0000-4000-8000-000000000008'
  ),
  'opaque Realtime invalidation reaches every changed owner/member/pending projection and no unrelated account'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000002';
select ok(
  (
    select notification_record.notification_type =
        'list_ownership_transferred'
      and notification_record.action_status = 'unavailable'
      and notification_record.active_list_title = 'Transfer groceries'
      and notification_record.expected_access_version is null
    from public.list_notifications(20, null, null) as notification_record
    where notification_record.notification_type =
      'list_ownership_transferred'
  ),
  'new owner lists the transfer as non-actionable informational notification'
);
select lives_ok(
  $$select * from public.rename_active_list(
    '52000000-0000-4000-8000-000000000001', 'Transferred groceries', 6
  )$$,
  'new owner immediately gains owner-only rename authority'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.rename_active_list(
    '52000000-0000-4000-8000-000000000001', 'Denied former owner', 7
  )$$,
  'P0002',
  'list unavailable',
  'former owner immediately loses owner-only rename authority'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000001',
    '51000000-0000-4000-8000-000000000003', 5, 3
  )$$,
  'P0002',
  'list unavailable',
  'duplicate or crossed old-owner transfer cannot create a second owner'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000002';
select ok(
  (
    select result.list_version = 8
      and result.owner_access_version = 2
      and result.previous_owner_access_version = 9
    from public.transfer_active_list_ownership(
      '52000000-0000-4000-8000-000000000001',
      '51000000-0000-4000-8000-000000000001', 7, 1
    ) as result
  ),
  'new owner can explicitly transfer back while both access lineages advance'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000001';
select ok(
  (
    select result.list_version = 9
      and result.owner_access_version = 10
      and result.previous_owner_access_version = 3
    from public.transfer_active_list_ownership(
      '52000000-0000-4000-8000-000000000001',
      '51000000-0000-4000-8000-000000000002', 8, 9
    ) as result
  ),
  'repeated transfer cycle never reuses an earlier participant version'
);
reset role;

select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications as notification_record
    where notification_record.active_list_id =
      '52000000-0000-4000-8000-000000000001'
      and notification_record.notification_type =
        'list_ownership_transferred'
  ),
  3::bigint,
  'each real transfer creates exactly one notification and rejected retries create none'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000002';
select ok(
  (
    select pg_catalog.jsonb_array_length(exported -> 'active_lists') = 1
      and pg_catalog.jsonb_array_length(exported -> 'shared_list_access') = 0
    from (
      select public.export_own_account_data() as exported
    ) as export_result
  ),
  'new owner export classifies the transferred list only as fully owned'
);
select ok(
  (
    select result.owned_shared_list_count = 1
      and result.affected_participant_count = 2
    from public.get_account_deletion_list_impact() as result
  ),
  'new owner deletion impact includes the transferred aggregate and accepted members'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000001';
select ok(
  (
    select pg_catalog.jsonb_array_length(exported -> 'active_lists') = 0
      and (exported -> 'shared_list_access' -> 0 ->> 'list_id')::uuid =
        '52000000-0000-4000-8000-000000000001'
      and exported -> 'shared_list_access' -> 0 ->> 'access_state' = 'member'
    from (
      select public.export_own_account_data() as exported
    ) as export_result
  ),
  'former owner export classifies the transferred list as caller-relative shared access'
);
select ok(
  (
    select result.owned_shared_list_count = 0
      and result.affected_participant_count = 0
    from public.get_account_deletion_list_impact() as result
  ),
  'former owner deletion impact no longer claims the transferred aggregate'
);
reset role;

savepoint delete_former_owner;
delete from auth.users
where id = '51000000-0000-4000-8000-000000000001';
select ok(
  exists (
    select 1 from public.active_lists
    where id = '52000000-0000-4000-8000-000000000001'
      and owner_id = '51000000-0000-4000-8000-000000000002'
  ),
  'deleting the former owner preserves the transferred list'
);
rollback to savepoint delete_former_owner;

savepoint delete_new_owner;
delete from auth.users
where id = '51000000-0000-4000-8000-000000000002';
select ok(
  not exists (
    select 1 from public.active_lists
    where id = '52000000-0000-4000-8000-000000000001'
  ),
  'deleting the new owner follows the existing owner aggregate cascade'
);
rollback to savepoint delete_new_owner;

-- Independent fixtures exercise every rejected state without changing the
-- successful transfer aggregate.
insert into public.active_lists (
  id, owner_id, title, status, version, creation_request_id,
  created_at, updated_at, archived_at
) values
  ('52000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000001', 'Rejected targets', 'active', 4, '52000000-0000-4000-8000-000000000012', now(), now(), null),
  ('52000000-0000-4000-8000-000000000003', '51000000-0000-4000-8000-000000000001', 'Archived transfer', 'archived', 2, '52000000-0000-4000-8000-000000000013', now(), now(), now()),
  ('52000000-0000-4000-8000-000000000004', '51000000-0000-4000-8000-000000000001', 'Blocked transfer', 'active', 3, '52000000-0000-4000-8000-000000000014', now(), now(), null),
  ('52000000-0000-4000-8000-000000000005', '51000000-0000-4000-8000-000000000001', 'Rollback transfer', 'active', 1, '52000000-0000-4000-8000-000000000015', now(), now(), null);

insert into public.active_list_participants (
  list_id, participant_profile_id, state, version
) values
  ('52000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000004', 'pending', 2),
  ('52000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000005', 'declined', 4),
  ('52000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000006', 'removed', 5),
  ('52000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000007', 'left', 6),
  ('52000000-0000-4000-8000-000000000002', '51000000-0000-4000-8000-000000000003', 'member', 3),
  ('52000000-0000-4000-8000-000000000003', '51000000-0000-4000-8000-000000000003', 'member', 1),
  ('52000000-0000-4000-8000-000000000004', '51000000-0000-4000-8000-000000000009', 'member', 1),
  ('52000000-0000-4000-8000-000000000005', '51000000-0000-4000-8000-000000000003', 'member', 1);

insert into public.user_blocks (blocker_id, blocked_id)
values (
  '51000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000009'
);

delete from realtime.messages;

set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000001', 4, 1
  )$$,
  '22023', 'profile unavailable', 'self transfer is rejected'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000004', 4, 2
  )$$,
  '22023', 'profile unavailable', 'pending target is rejected'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000005', 4, 4
  )$$,
  '22023', 'profile unavailable', 'declined target is rejected'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000006', 4, 5
  )$$,
  '22023', 'profile unavailable', 'removed target is rejected'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000007', 4, 6
  )$$,
  '22023', 'profile unavailable', 'left target is rejected'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000008', 4, 1
  )$$,
  '22023', 'profile unavailable', 'unrelated target is rejected'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000004',
    '51000000-0000-4000-8000-000000000009', 3, 1
  )$$,
  '22023', 'profile unavailable', 'blocked accepted target is rejected'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000003',
    '51000000-0000-4000-8000-000000000003', 2, 1
  )$$,
  '55000', 'archived list is read only', 'archived-list transfer is rejected'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000003', 3, 3
  )$$,
  '40001', 'list changed', 'stale list version is rejected'
);
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000003', 4, 2
  )$$,
  '40001', 'list access changed', 'stale accepted-access version is rejected'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000002',
    '51000000-0000-4000-8000-000000000002', 4, 1
  )$$,
  'P0002', 'list unavailable', 'non-owner initiation is rejected'
);
reset role;

select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where active_list_id in (
      '52000000-0000-4000-8000-000000000002',
      '52000000-0000-4000-8000-000000000003',
      '52000000-0000-4000-8000-000000000004'
    )
      and notification_type = 'list_ownership_transferred'
  ),
  0::bigint,
  'rejected transfers create no notification'
);
select is(
  (select pg_catalog.count(*) from realtime.messages),
  0::bigint,
  'rejected transfers commit no Realtime invalidation'
);

savepoint rolled_back_transfer;
set local role authenticated;
set local "request.jwt.claim.sub" = '51000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.transfer_active_list_ownership(
    '52000000-0000-4000-8000-000000000005',
    '51000000-0000-4000-8000-000000000003',
    1,
    1
  )$$,
  'successful transfer can remain inside a caller-controlled transaction'
);
reset role;
rollback to savepoint rolled_back_transfer;
select ok(
  exists (
    select 1 from public.active_lists
    where id = '52000000-0000-4000-8000-000000000005'
      and owner_id = '51000000-0000-4000-8000-000000000001'
      and version = 1
  )
  and not exists (
    select 1 from public.user_notifications
    where active_list_id = '52000000-0000-4000-8000-000000000005'
      and notification_type = 'list_ownership_transferred'
  )
  and not exists (
    select 1 from realtime.messages
  ),
  'rolled-back transfer preserves ownership and commits no notification or invalidation'
);

select throws_ok(
  $test$
    do $body$
    begin
      update public.active_lists
      set owner_id = '51000000-0000-4000-8000-000000000003'
      where id = '52000000-0000-4000-8000-000000000002';
      set constraints active_lists_owner_access_consistency immediate;
    end
    $body$
  $test$,
  '23514',
  'list owner access state is inconsistent',
  'deferred invariant rejects a committed owner/member duplicate'
);

select * from finish();
rollback;
