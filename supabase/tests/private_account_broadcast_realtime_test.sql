begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'realtime'
      and tablename = 'messages'
      and policyname = 'authenticated_receive_own_account_broadcasts'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and with_check is null
      and qual like '%extension = ''broadcast''%'
      and qual like '%realtime.topic()%'
      and qual like '%''account:''%auth.uid()%'
  ),
  1::bigint,
  'one exact authenticated receive-only account Broadcast policy exists'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'realtime' and tablename = 'messages'
  ),
  1::bigint,
  'Realtime messages has no broad, send, Presence, or anonymous policy'
);

select ok(
  (
    select pg_catalog.bool_and(
      p.prosecdef
      and p.proowner = 'postgres'::regrole
      and p.proconfig @> array['search_path=""']
      and pg_catalog.obj_description(p.oid, 'pg_proc') is not null
      and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
    )
    from pg_catalog.pg_proc as p
    where p.oid in (
      'private.send_account_invalidations(uuid[])'::regprocedure,
      'private.broadcast_active_list_invalidation()'::regprocedure,
      'private.broadcast_active_list_participant_invalidation()'::regprocedure,
      'private.broadcast_notification_invalidation()'::regprocedure,
      'private.broadcast_relationship_invalidation()'::regprocedure,
      'private.broadcast_block_invalidation()'::regprocedure,
      'private.broadcast_profile_invalidation()'::regprocedure
    )
  ),
  'all private Realtime functions are commented postgres-owned hardened definer boundaries with no Data API execution'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'private.send_account_invalidations(uuid[])'::regprocedure
  ) like '%jsonb_build_object(''v'', 1)%'
  and pg_catalog.pg_get_functiondef(
    'private.send_account_invalidations(uuid[])'::regprocedure
  ) like '%''invalidate''%'
  and pg_catalog.pg_get_functiondef(
    'private.send_account_invalidations(uuid[])'::regprocedure
  ) like '%''account:'' || recipient_id::text%'
  and pg_catalog.pg_get_functiondef(
    'private.send_account_invalidations(uuid[])'::regprocedure
  ) like '%true%'
  and pg_catalog.pg_get_functiondef(
    'private.send_account_invalidations(uuid[])'::regprocedure
  ) not like '%broadcast_changes%'
  and pg_catalog.pg_get_functiondef(
    'private.send_account_invalidations(uuid[])'::regprocedure
  ) not like '%dynamic%sql%',
  'sender pins the fixed private event, account topic, opaque payload, and realtime.send contract'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger as trigger_record
    join pg_catalog.pg_class as table_record
      on table_record.oid = trigger_record.tgrelid
    join pg_catalog.pg_namespace as namespace_record
      on namespace_record.oid = table_record.relnamespace
    where namespace_record.nspname = 'public'
      and not trigger_record.tgisinternal
      and trigger_record.tgname like '%broadcast_invalidation%'
  ),
  11::bigint,
  'the reviewed list, participant, notification, relationship, block, profile, category, template, and Split triggers exist'
);

select ok(
  (
    select pg_catalog.bool_and(table_record.relrowsecurity)
    from pg_catalog.pg_class as table_record
    join pg_catalog.pg_namespace as namespace_record
      on namespace_record.oid = table_record.relnamespace
    where namespace_record.nspname = 'public'
      and table_record.relname in (
        'profiles', 'user_blocks', 'user_relationships', 'user_notifications',
        'active_lists', 'active_list_items', 'active_list_participants'
      )
  )
  and (
    select pg_catalog.bool_and(table_record.relforcerowsecurity)
    from pg_catalog.pg_class as table_record
    join pg_catalog.pg_namespace as namespace_record
      on namespace_record.oid = table_record.relnamespace
    where namespace_record.nspname = 'public'
      and table_record.relname in (
        'user_notifications', 'active_lists', 'active_list_items',
        'active_list_participants'
      )
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.active_lists', 'SELECT,INSERT,UPDATE,DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.active_list_items', 'SELECT,INSERT,UPDATE,DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated', 'public.active_list_participants', 'SELECT,INSERT,UPDATE,DELETE'
  ),
  'application forced RLS and direct table rejection remain unchanged'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
  ),
  'no application table is added to the Realtime publication'
);
select ok(
  not exists (
    select 1
    from information_schema.tables
    where table_schema in ('public', 'private')
      and table_name ~ '(outbox|queue|event_log|replay|presence)'
  ),
  'no outbox, queue, event log, replay, or Presence table is introduced'
);

select private.send_account_invalidations(array[
  '41000000-0000-4000-8000-000000000001'::uuid,
  '41000000-0000-4000-8000-000000000002'::uuid
]);
insert into realtime.messages(topic, extension, payload, event, private)
values (
  'account:41000000-0000-4000-8000-000000000001',
  'presence',
  '{}'::jsonb,
  'sync',
  true
);

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
set local realtime.topic = 'account:41000000-0000-4000-8000-000000000001';
select is(
  (
    select pg_catalog.count(*)
    from realtime.messages
    where extension = 'broadcast'
      and event = 'invalidate'
      and topic = 'account:41000000-0000-4000-8000-000000000001'
      and payload - 'id' = '{"v":1}'::jsonb
      and private
  ),
  1::bigint,
  'authenticated caller receives the fixed application payload on only their own exact account topic'
);
select is(
  (select pg_catalog.count(*) from realtime.messages where extension = 'presence'),
  0::bigint,
  'Presence receive is denied even on the own account topic'
);
set local realtime.topic = 'account:41000000-0000-4000-8000-000000000002';
select is(
  (select pg_catalog.count(*) from realtime.messages),
  0::bigint,
  'authenticated caller cannot receive another account topic'
);
set local realtime.topic = 'account:41000000-0000-4000-8000-000000000001-extra';
select is(
  (select pg_catalog.count(*) from realtime.messages),
  0::bigint,
  'similar-prefix and malformed topics do not authorize'
);
set local realtime.topic = 'account:41000000-0000-4000-8000-000000000001';
select throws_like(
  $$insert into realtime.messages(topic,extension,payload,event,private)
    values ('account:41000000-0000-4000-8000-000000000001','broadcast','{"v":1}','invalidate',true)$$,
  '%row-level security%',
  'authenticated client Broadcast send is denied'
);
select throws_like(
  $$insert into realtime.messages(topic,extension,payload,event,private)
    values ('account:41000000-0000-4000-8000-000000000001','presence','{}','track',true)$$,
  '%row-level security%',
  'authenticated Presence write is denied'
);
reset role;

set local role anon;
set local realtime.topic = 'account:41000000-0000-4000-8000-000000000001';
select is(
  (select pg_catalog.count(*) from realtime.messages),
  0::bigint,
  'anonymous receive is denied'
);
reset role;
delete from realtime.messages;

create function pg_temp.broadcast_count(target_profile_id uuid)
returns bigint
language sql
stable
set search_path = ''
as $$
  select pg_catalog.count(*)
  from realtime.messages as message
  where message.topic = 'account:' || target_profile_id::text
    and message.extension = 'broadcast'
    and message.event = 'invalidate'
    and message.private
    and message.payload - 'id' = '{"v":1}'::jsonb
$$;

create function pg_temp.clear_broadcasts()
returns void
language sql
volatile
set search_path = ''
as $$ delete from realtime.messages $$;

insert into auth.users(id,email,email_confirmed_at,created_at,updated_at) values
  ('41000000-0000-4000-8000-000000000001','owner@realtime.test',now(),now(),now()),
  ('41000000-0000-4000-8000-000000000002','member@realtime.test',now(),now(),now()),
  ('41000000-0000-4000-8000-000000000003','invitee@realtime.test',now(),now(),now()),
  ('41000000-0000-4000-8000-000000000004','unrelated@realtime.test',now(),now(),now());
update public.profiles
set username = 'realtime_' || right(id::text, 1),
    display_name = 'Realtime ' || right(id::text, 1)
where id::text like '41000000-0000-4000-8000-00000000000_';
insert into public.user_relationships(
  profile_low_id, profile_high_id, state, requester_id
) values
  ('41000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000002','friends','41000000-0000-4000-8000-000000000001'),
  ('41000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000003','friends','41000000-0000-4000-8000-000000000001');
select pg_temp.clear_broadcasts();

create temporary table realtime_values(
  label text primary key,
  value uuid
) on commit drop;
grant select, insert, update on realtime_values to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
insert into realtime_values
select 'list', list_id
from public.create_active_list(
  'Realtime groceries',
  '42000000-0000-4000-8000-000000000001'
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000004') = 0,
  'list creation invalidates only the owner among fixtures'
);
select pg_temp.clear_broadcasts();

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select * from public.invite_active_list_member(
  (select value from realtime_values where label = 'list'),
  '41000000-0000-4000-8000-000000000002',
  null
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000004') = 0,
  'invitation fanout reaches owner and pending recipient without unrelated disclosure'
);
select pg_temp.clear_broadcasts();

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select * from public.invite_active_list_member(
  (select value from realtime_values where label = 'list'),
  '41000000-0000-4000-8000-000000000002',
  null
);
reset role;
select is(
  (select pg_catalog.count(*) from realtime.messages),
  0::bigint,
  'idempotent duplicate invitation emits no required invalidation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select throws_ok(
  format(
    $$select public.cancel_active_list_invitation(%L,'41000000-0000-4000-8000-000000000002',99)$$,
    (select value from realtime_values where label = 'list')
  ),
  '40001',
  'list access changed',
  'rejected stale invitation mutation emits no committed message'
);
reset role;
select is((select pg_catalog.count(*) from realtime.messages), 0::bigint,
  'stale mutation message insertion rolled back with the rejected statement');

insert into realtime_values
select 'member-invitation-notification', id
from public.user_notifications
where recipient_id = '41000000-0000-4000-8000-000000000002'
  and notification_type = 'list_invitation';

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000002';
select public.mark_notifications_read(
  array[(select value from realtime_values where label = 'member-invitation-notification')]
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') = 0,
  'notification read fanout targets only the persistent-notification recipient'
);
select pg_temp.clear_broadcasts();

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000002';
select public.accept_active_list_invitation(
  (select value from realtime_values where label = 'list'), 1
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 1,
  'invitation acceptance reconciles both list and persistent-notification projections'
);
select pg_temp.clear_broadcasts();

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000002';
insert into realtime_values
select 'item', item_id
from public.create_active_list_item(
  (select value from realtime_values where label = 'list'),
  'Milk',
  '42000000-0000-4000-8000-000000000002',
  1,
  1000,
  'piece'
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 1
  and not exists (
    select 1 from public.user_notifications where notification_type not in (
      'list_invitation', 'list_invitation_accepted'
    )
  ),
  'item creation invalidates owner/member accounts and creates no routine persistent notification'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000002';
select * from public.update_active_list_item(
  (select value from realtime_values where label = 'list'),
  (select value from realtime_values where label = 'item'),
  'Whole milk', 2000, 'ml', 2, 1
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 1,
  'item edit fanout reaches every accepted account including the actor other devices'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000002';
select * from public.update_active_list_item(
  (select value from realtime_values where label = 'list'),
  (select value from realtime_values where label = 'item'),
  'Whole milk', 2000, 'ml', 3, 2
);
reset role;
select is((select pg_catalog.count(*) from realtime.messages), 0::bigint,
  'idempotent item no-op emits no required invalidation');

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000002';
select * from public.set_active_list_item_completed(
  (select value from realtime_values where label = 'list'),
  (select value from realtime_values where label = 'item'), true, 3, 2
);
select * from public.set_active_list_item_completed(
  (select value from realtime_values where label = 'list'),
  (select value from realtime_values where label = 'item'), false, 4, 3
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 2
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 2,
  'item complete and reopen each invalidate all accepted accounts'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000002';
insert into realtime_values
select 'item-2', item_id
from public.create_active_list_item(
  (select value from realtime_values where label = 'list'),
  'Bread',
  '42000000-0000-4000-8000-000000000003',
  5
);
select public.reorder_active_list_items(
  (select value from realtime_values where label = 'list'),
  array[
    (select value from realtime_values where label = 'item-2'),
    (select value from realtime_values where label = 'item')
  ],
  6
);
select public.delete_active_list_item(
  (select value from realtime_values where label = 'list'),
  (select value from realtime_values where label = 'item-2'),
  7, 1
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 3
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 3,
  'item add, reorder, and delete fanout follows the parent list version mutation'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select * from public.rename_active_list(
  (select value from realtime_values where label = 'list'), 'Renamed list', 8
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 1,
  'list rename fans out to the owner and accepted member'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select * from public.set_active_list_archived(
  (select value from realtime_values where label = 'list'), true, 9
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 1,
  'list archive fans out to the owner and accepted member'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select * from public.set_active_list_archived(
  (select value from realtime_values where label = 'list'), false, 10
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 1,
  'list restore fans out to the owner and accepted member'
);

select pg_temp.clear_broadcasts();
savepoint rolled_back_list_change;
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select * from public.rename_active_list(
  (select value from realtime_values where label = 'list'), 'Rolled back', 11
);
reset role;
rollback to savepoint rolled_back_list_change;
select is((select pg_catalog.count(*) from realtime.messages), 0::bigint,
  'rolled-back authoritative mutation leaves no committed invalidation message');

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select * from public.invite_active_list_member(
  (select value from realtime_values where label = 'list'),
  '41000000-0000-4000-8000-000000000003', null
);
reset role;
select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000003';
select public.decline_active_list_invitation(
  (select value from realtime_values where label = 'list'), 1
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000003') >= 1,
  'invitation decline resolves owner and recipient projections'
);
select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select * from public.invite_active_list_member(
  (select value from realtime_values where label = 'list'),
  '41000000-0000-4000-8000-000000000003', 2
);
select public.cancel_active_list_invitation(
  (select value from realtime_values where label = 'list'),
  '41000000-0000-4000-8000-000000000003', 3
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 2
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000003') >= 2,
  'reinvite and cancel each invalidate only affected invitation projections'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select public.remove_active_list_member(
  (select value from realtime_values where label = 'list'),
  '41000000-0000-4000-8000-000000000002', 2
);
select * from public.invite_active_list_member(
  (select value from realtime_values where label = 'list'),
  '41000000-0000-4000-8000-000000000002', 3
);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000002';
select public.accept_active_list_invitation(
  (select value from realtime_values where label = 'list'), 4
);
select public.leave_active_list(
  (select value from realtime_values where label = 'list'), 5
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 4
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 4,
  'remove, deliberate reinvite/accept, and leave all reconcile owner and member projections'
);

-- Re-establish one accepted member so deletion can prove BEFORE DELETE capture.
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select * from public.invite_active_list_member(
  (select value from realtime_values where label = 'list'),
  '41000000-0000-4000-8000-000000000002', 6
);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000002';
select public.accept_active_list_invitation(
  (select value from realtime_values where label = 'list'), 7
);
reset role;
select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select public.delete_active_list(
  (select value from realtime_values where label = 'list'), 11
);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000002') >= 1,
  'list deletion captures the previously authorized member before cascades remove access rows'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
insert into realtime_values
select 'pending-list', list_id
from public.create_active_list(
  'Pending friendship list',
  '42000000-0000-4000-8000-000000000004'
);
select * from public.invite_active_list_member(
  (select value from realtime_values where label = 'pending-list'),
  '41000000-0000-4000-8000-000000000003', null
);
reset role;
select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '41000000-0000-4000-8000-000000000001';
select public.end_friendship('41000000-0000-4000-8000-000000000003', 1);
reset role;
select ok(
  pg_temp.broadcast_count('41000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('41000000-0000-4000-8000-000000000003') >= 1
  and exists (
    select 1 from public.active_list_participants
    where list_id = (select value from realtime_values where label = 'pending-list')
      and participant_profile_id = '41000000-0000-4000-8000-000000000003'
      and state = 'cancelled'
  ),
  'unfriend pending-invitation cancellation invalidates both relationship and invitation projections'
);

-- Blocking fanout covers each shared-list consequence without exposing direction.
insert into auth.users(id,email,email_confirmed_at,created_at,updated_at) values
  ('43000000-0000-4000-8000-000000000001','block-owner@realtime.test',now(),now(),now()),
  ('43000000-0000-4000-8000-000000000002','block-member@realtime.test',now(),now(),now()),
  ('43000000-0000-4000-8000-000000000003','block-peer@realtime.test',now(),now(),now()),
  ('43000000-0000-4000-8000-000000000004','block-fourth@realtime.test',now(),now(),now());
update public.profiles
set username = 'block_rt_' || right(id::text, 1), display_name = 'Block fixture'
where id::text like '43000000-0000-4000-8000-00000000000_';
insert into public.active_lists(id,owner_id,title,creation_request_id) values
  ('43000000-0000-4000-8000-000000000010','43000000-0000-4000-8000-000000000001','Owner block','43000000-0000-4000-8000-000000000011'),
  ('43000000-0000-4000-8000-000000000020','43000000-0000-4000-8000-000000000001','Member block owner','43000000-0000-4000-8000-000000000021'),
  ('43000000-0000-4000-8000-000000000030','43000000-0000-4000-8000-000000000001','Peer block','43000000-0000-4000-8000-000000000031');
insert into public.active_list_participants(list_id,participant_profile_id,state) values
  ('43000000-0000-4000-8000-000000000010','43000000-0000-4000-8000-000000000002','member'),
  ('43000000-0000-4000-8000-000000000020','43000000-0000-4000-8000-000000000003','member'),
  ('43000000-0000-4000-8000-000000000030','43000000-0000-4000-8000-000000000002','member'),
  ('43000000-0000-4000-8000-000000000030','43000000-0000-4000-8000-000000000004','member');
select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '43000000-0000-4000-8000-000000000004';
select public.block_profile('43000000-0000-4000-8000-000000000002');
reset role;
select ok(
  pg_temp.broadcast_count('43000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('43000000-0000-4000-8000-000000000002') >= 1
  and pg_temp.broadcast_count('43000000-0000-4000-8000-000000000004') >= 1,
  'member-blocks-member separation invalidates the owner and affected members'
);
select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '43000000-0000-4000-8000-000000000001';
select public.block_profile('43000000-0000-4000-8000-000000000002');
reset role;
select ok(
  pg_temp.broadcast_count('43000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('43000000-0000-4000-8000-000000000002') >= 1,
  'owner-blocks-member removal invalidates both affected account projections'
);
select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = '43000000-0000-4000-8000-000000000003';
select public.block_profile('43000000-0000-4000-8000-000000000001');
reset role;
select ok(
  pg_temp.broadcast_count('43000000-0000-4000-8000-000000000001') >= 1
  and pg_temp.broadcast_count('43000000-0000-4000-8000-000000000003') >= 1,
  'member-blocks-owner leave invalidates both affected account projections'
);

-- Account deletion fanout is captured before profile/list/access cascades.
insert into auth.users(id,email,email_confirmed_at,created_at,updated_at) values
  ('44000000-0000-4000-8000-000000000001','delete-owner@realtime.test',now(),now(),now()),
  ('44000000-0000-4000-8000-000000000002','delete-member@realtime.test',now(),now(),now());
update public.profiles
set username = 'delete_rt_' || right(id::text, 1), display_name = 'Delete fixture'
where id::text like '44000000-0000-4000-8000-00000000000_';
insert into public.active_lists(id,owner_id,title,creation_request_id)
values ('44000000-0000-4000-8000-000000000010','44000000-0000-4000-8000-000000000001','Deletion list','44000000-0000-4000-8000-000000000011');
insert into public.active_list_participants(list_id,participant_profile_id,state)
values ('44000000-0000-4000-8000-000000000010','44000000-0000-4000-8000-000000000002','member');
select pg_temp.clear_broadcasts();
delete from auth.users where id = '44000000-0000-4000-8000-000000000002';
select ok(
  pg_temp.broadcast_count('44000000-0000-4000-8000-000000000001') >= 1
  and exists (
    select 1 from public.active_lists
    where id = '44000000-0000-4000-8000-000000000010'
  ),
  'member deletion invalidates the owner while preserving the owner aggregate'
);

insert into auth.users(id,email,email_confirmed_at,created_at,updated_at)
values ('44000000-0000-4000-8000-000000000003','delete-member-two@realtime.test',now(),now(),now());
update public.profiles set username = 'delete_rt_3', display_name = 'Delete member two'
where id = '44000000-0000-4000-8000-000000000003';
insert into public.active_list_participants(list_id,participant_profile_id,state)
values ('44000000-0000-4000-8000-000000000010','44000000-0000-4000-8000-000000000003','member');
select pg_temp.clear_broadcasts();
delete from auth.users where id = '44000000-0000-4000-8000-000000000001';
select ok(
  pg_temp.broadcast_count('44000000-0000-4000-8000-000000000003') >= 1
  and not exists (
    select 1 from public.active_lists
    where id = '44000000-0000-4000-8000-000000000010'
  ),
  'owner deletion invalidates surviving participants before cascading the owned list'
);

select * from finish();
rollback;
