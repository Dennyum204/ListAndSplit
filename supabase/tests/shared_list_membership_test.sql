begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public', 'active_list_participants', 'participant access table exists');
select columns_are(
  'public', 'active_list_participants',
  array['list_id','participant_profile_id','state','version','created_at','state_changed_at'],
  'participant access has only reviewed current-state columns'
);
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_catalog.pg_class
   where oid = 'public.active_list_participants'::regclass),
  'participant access enables and forces RLS'
);
select is(
  (select pg_catalog.count(*) from pg_catalog.pg_policies
   where schemaname = 'public' and tablename = 'active_list_participants'
     and policyname = 'active_list_participants_reject_direct_client_access'
     and cmd = 'ALL' and roles = array['anon','authenticated']::name[]
     and qual = 'false' and with_check = 'false'),
  1::bigint,
  'one explicit restrictive direct-access rejection policy exists'
);
select ok(
  not has_table_privilege('anon','public.active_list_participants','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.active_list_participants','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','public.active_list_participants','SELECT,INSERT,UPDATE,DELETE'),
  'all Data API roles lack direct participant CRUD'
);
select is(
  (select pg_catalog.count(*) from pg_catalog.pg_constraint
   where conrelid = 'public.active_list_participants'::regclass
     and conname in (
       'active_list_participants_pkey','active_list_participants_list_fkey',
       'active_list_participants_profile_fkey','active_list_participants_state_check',
       'active_list_participants_positive_version_check','active_list_participants_time_check'
     )),
  6::bigint,
  'all participant constraints exist'
);

select ok(
  (select pg_catalog.bool_and(
     p.prosecdef and p.proowner = 'postgres'::regrole
     and p.proconfig @> array['search_path=""']
     and obj_description(p.oid, 'pg_proc') is not null
   ) from pg_catalog.pg_proc as p where p.oid in (
    'public.list_active_list_participants(uuid)'::regprocedure,
    'public.list_pending_active_list_invitations(uuid)'::regprocedure,
    'public.list_eligible_active_list_invitees(uuid)'::regprocedure,
    'public.get_active_list_invitation(uuid)'::regprocedure,
    'public.invite_active_list_member(uuid,uuid,bigint)'::regprocedure,
    'public.cancel_active_list_invitation(uuid,uuid,bigint)'::regprocedure,
    'public.accept_active_list_invitation(uuid,bigint)'::regprocedure,
    'public.decline_active_list_invitation(uuid,bigint)'::regprocedure,
    'public.remove_active_list_member(uuid,uuid,bigint)'::regprocedure,
    'public.leave_active_list(uuid,bigint)'::regprocedure,
    'public.get_account_deletion_list_impact()'::regprocedure
  )),
  'new RPCs are commented postgres-owned hardened definer boundaries'
);
select ok(
  (select pg_catalog.bool_and(
     has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and not has_function_privilege('anon', p.oid, 'EXECUTE')
     and not has_function_privilege('service_role', p.oid, 'EXECUTE')
   ) from pg_catalog.pg_proc as p where p.oid in (
    'public.list_active_list_participants(uuid)'::regprocedure,
    'public.list_pending_active_list_invitations(uuid)'::regprocedure,
    'public.list_eligible_active_list_invitees(uuid)'::regprocedure,
    'public.get_active_list_invitation(uuid)'::regprocedure,
    'public.invite_active_list_member(uuid,uuid,bigint)'::regprocedure,
    'public.cancel_active_list_invitation(uuid,uuid,bigint)'::regprocedure,
    'public.accept_active_list_invitation(uuid,bigint)'::regprocedure,
    'public.decline_active_list_invitation(uuid,bigint)'::regprocedure,
    'public.remove_active_list_member(uuid,uuid,bigint)'::regprocedure,
    'public.leave_active_list(uuid,bigint)'::regprocedure,
    'public.get_account_deletion_list_impact()'::regprocedure
  )),
  'only authenticated receives each new exact RPC grant'
);

set local role anon;
select throws_like($$select * from public.active_list_participants$$,'%permission denied%','anon SELECT denied');
select throws_like($$insert into public.active_list_participants values (gen_random_uuid(),gen_random_uuid(),'pending',1,now(),now())$$,'%permission denied%','anon INSERT denied');
reset role;
set local role authenticated;
select throws_like($$select * from public.active_list_participants$$,'%permission denied%','authenticated SELECT denied');
select throws_like($$delete from public.active_list_participants$$,'%permission denied%','authenticated DELETE denied');
reset role;
set local role service_role;
select throws_like($$select * from public.active_list_participants$$,'%permission denied%','service role direct SELECT denied');
reset role;

insert into auth.users (id,email,email_confirmed_at,created_at,updated_at) values
 ('10000000-0000-4000-8000-000000000001','owner@membership.test',now(),now(),now()),
 ('10000000-0000-4000-8000-000000000002','member@membership.test',now(),now(),now()),
 ('10000000-0000-4000-8000-000000000003','invitee@membership.test',now(),now(),now()),
 ('10000000-0000-4000-8000-000000000004','stranger@membership.test',now(),now(),now()),
 ('10000000-0000-4000-8000-000000000005','third@membership.test',now(),now(),now()),
 ('10000000-0000-4000-8000-000000000006','blocked@membership.test',now(),now(),now());
update public.profiles set
 username = 'member_' || right(id::text, 1),
 display_name = 'Member ' || right(id::text, 1)
where id::text like '10000000-0000-4000-8000-00000000000_';

insert into public.user_relationships (
 profile_low_id,profile_high_id,state,requester_id
) values
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','friends','10000000-0000-4000-8000-000000000001'),
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000003','friends','10000000-0000-4000-8000-000000000001'),
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000006','friends','10000000-0000-4000-8000-000000000001'),
 ('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000005','friends','10000000-0000-4000-8000-000000000002'),
 ('10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000005','friends','10000000-0000-4000-8000-000000000003');

create temporary table membership_values (label text primary key,list_id uuid,version bigint) on commit drop;
grant select,insert,update on membership_values to authenticated;
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
insert into membership_values
select 'owner-list',list_id,version from public.create_active_list(
 'Shared groceries','20000000-0000-4000-8000-000000000001'
);

select ok(
 (select access_state = 'pending' and access_version = 1
  from public.invite_active_list_member(
   (select list_id from membership_values where label='owner-list'),
   '10000000-0000-4000-8000-000000000002',null)),
 'owner can invite an accepted friend'
);
reset role;
select is(
 (select pg_catalog.count(*) from public.user_notifications
  where notification_type='list_invitation' and access_version=1),
 1::bigint,'real pending transition creates one notification'
);
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select lives_ok(format(
 $$select * from public.invite_active_list_member(%L,'10000000-0000-4000-8000-000000000002',null)$$,
 (select list_id from membership_values where label='owner-list')),
 'duplicate invite is idempotent'
);
select is(
 (select pg_catalog.count(*) from public.list_pending_active_list_invitations(
  (select list_id from membership_values where label='owner-list'))),
 1::bigint,'duplicate invite creates no notification'
);
select throws_ok(format(
 $$select * from public.invite_active_list_member(%L,'10000000-0000-4000-8000-000000000004',null)$$,
 (select list_id from membership_values where label='owner-list')),
 '22023','profile unavailable','stranger invite is denied'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
select ok(
 (select expected_access_version=1 and active_list_title='Shared groceries'
  from public.list_notifications(20,null,null)
  where notification_type='list_invitation' and action_status='actionable'),
 'recipient sees an actionable exact-version notification'
);
select is(public.accept_active_list_invitation(
 (select list_id from membership_values where label='owner-list'),1),2::bigint,
 'recipient accepts into member version two'
);
select is(public.accept_active_list_invitation(
 (select list_id from membership_values where label='owner-list'),1),2::bigint,
 'repeated accept is idempotent'
);
select is(
 (select pg_catalog.count(*) from public.list_active_lists('active',20)
  where not is_owner and owner_username='member_1'),
 1::bigint,'accepted member lists shared projection'
);
select is(
 (select pg_catalog.count(*) from public.list_active_list_participants(
  (select list_id from membership_values where label='owner-list'))),
 2::bigint,'accepted member sees owner and accepted members only'
);
select lives_ok(format(
 $$select * from public.create_active_list_item(%L,'Member item','20000000-0000-4000-8000-000000000002',1)$$,
 (select list_id from membership_values where label='owner-list')),
 'accepted member can add an item'
);
select throws_ok(format(
 $$select * from public.rename_active_list(%L,'Denied',2)$$,
 (select list_id from membership_values where label='owner-list')),
 'P0002','list unavailable','member cannot rename'
);

set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select ok(
 (select pg_catalog.count(*)=0 from public.list_pending_active_list_invitations(
  (select list_id from membership_values where label='owner-list'))),
 'accepted member is absent from pending owner projection'
);
select ok(
 (select access_state='pending' and access_version=1 from public.invite_active_list_member(
  (select list_id from membership_values where label='owner-list'),
  '10000000-0000-4000-8000-000000000003',null)),
 'second accepted friend can be invited'
);
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000003';
select is(public.decline_active_list_invitation(
 (select list_id from membership_values where label='owner-list'),1),2::bigint,
 'recipient can decline'
);
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select ok(
 (select access_version=3 from public.invite_active_list_member(
  (select list_id from membership_values where label='owner-list'),
  '10000000-0000-4000-8000-000000000003',2)),
 'owner can reinvite a declined access row at a new version'
);
select throws_ok(format(
 $$select public.cancel_active_list_invitation(%L,'10000000-0000-4000-8000-000000000003',2)$$,
 (select list_id from membership_values where label='owner-list')),
 '40001','list access changed','stale cancel is denied safely'
);
select is(public.cancel_active_list_invitation(
 (select list_id from membership_values where label='owner-list'),
 '10000000-0000-4000-8000-000000000003',3),4::bigint,
 'owner cancels the current pending version'
);

-- Pending reservations count toward the exact twenty-person capacity.
reset role;
insert into auth.users (id,email,email_confirmed_at,created_at,updated_at)
select gen_random_uuid(), 'capacity-'||n||'@membership.test', now(),now(),now()
from generate_series(1,19) as n;
update public.profiles set username='capacity_'||substr(id::text,1,8),
 display_name='Capacity user' where username is null;
insert into public.active_list_participants(list_id,participant_profile_id,state)
select (select list_id from membership_values where label='owner-list'),p.id,'pending'
from public.profiles as p
where p.username like 'capacity_%' order by p.id limit 18;
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select throws_ok(format(
 $$select * from public.invite_active_list_member(%L,'10000000-0000-4000-8000-000000000003',4)$$,
 (select list_id from membership_values where label='owner-list')),
 '54000','list participant capacity reached','owner plus pending/member is capped at twenty'
);
reset role;
delete from public.active_list_participants where participant_profile_id in (
 select id from public.profiles where username like 'capacity_%'
);

-- Archive cancels pending, preserves reads, rejects content/accept, and permits leave/remove.
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select * from public.invite_active_list_member(
 (select list_id from membership_values where label='owner-list'),
 '10000000-0000-4000-8000-000000000003',4);
select lives_ok(format(
 $$select * from public.set_active_list_archived(%L,true,2)$$,
 (select list_id from membership_values where label='owner-list')),
 'owner archives and cancels pending invitations atomically'
);
reset role;
select ok(
 (select state='cancelled' from public.active_list_participants
  where list_id=(select list_id from membership_values where label='owner-list')
   and participant_profile_id='10000000-0000-4000-8000-000000000003'),
 'archive cancels pending access'
);
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
select is((select pg_catalog.count(*) from public.list_active_list_items(
 (select list_id from membership_values where label='owner-list'))),1::bigint,
 'member can read archived items');
select throws_ok(format(
 $$select * from public.create_active_list_item(%L,'No','20000000-0000-4000-8000-000000000099',3)$$,
 (select list_id from membership_values where label='owner-list')),
 '55000','archived list is read only','member cannot mutate archived content'
);
select is(public.leave_active_list(
 (select list_id from membership_values where label='owner-list'),2),3::bigint,
 'member may leave an archived list'
);

-- Export v6 preserves the privacy-minimal v3 shared access and deletion impact.
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select ok(
 public.export_own_account_data()->>'schema_version'='6'
 and public.export_own_account_data() ? 'shared_list_access',
 'export schema v6 preserves the shared access root'
);
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
select ok(
 (public.export_own_account_data()->'shared_list_access'->0) ?&
  array['list_id','list_title','list_status','access_state','access_version','created_at','state_changed_at']
 and not (public.export_own_account_data()->'shared_list_access'->0) ?| array['items','owner_id','participants'],
 'shared export contains only caller-relative metadata'
);
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select ok(
 (select owned_shared_list_count=0 and affected_participant_count=0
  from public.get_account_deletion_list_impact()),
 'deletion impact excludes former members who no longer have access'
);

-- Blocking owner/member removes access and unblock restores nothing.
select lives_ok($$select public.set_active_list_archived(
 (select list_id from membership_values where label='owner-list'),false,3)$$,
 'owner restores without restoring cancelled/left access');
select ok((select access_version=4 from public.invite_active_list_member(
 (select list_id from membership_values where label='owner-list'),
 '10000000-0000-4000-8000-000000000002',3)),
 'owner may reinvite a former member');
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
select is(public.accept_active_list_invitation(
 (select list_id from membership_values where label='owner-list'),4),5::bigint,
 'former member accepts again');
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select lives_ok($$select public.block_profile('10000000-0000-4000-8000-000000000002')$$,
 'owner block atomically removes accepted member');
reset role;
select ok(
 (select state='removed' from public.active_list_participants
  where list_id=(select list_id from membership_values where label='owner-list')
   and participant_profile_id='10000000-0000-4000-8000-000000000002'),
 'owner block removes the member without a block-reason notification'
);
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select lives_ok($$select public.unblock_profile('10000000-0000-4000-8000-000000000002')$$,
 'unblock succeeds');
reset role;
select ok(
 (select state='removed' from public.active_list_participants
  where list_id=(select list_id from membership_values where label='owner-list')
   and participant_profile_id='10000000-0000-4000-8000-000000000002'),
 'unblock restores no membership'
);

-- Ending friendship cancels pending invitations across lists but preserves members.
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
select ok((select access_version=7 from public.invite_active_list_member(
 (select list_id from membership_values where label='owner-list'),
 '10000000-0000-4000-8000-000000000003',6)),
 'owner can reinvite after an archive cancellation');
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000003';
select is(public.accept_active_list_invitation(
 (select list_id from membership_values where label='owner-list'),7),8::bigint,
 'recipient accepts the reopened invitation');
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000001';
insert into membership_values
select 'pending-list',list_id,version from public.create_active_list(
 'Pending friendship list','20000000-0000-4000-8000-000000000003'
);
select * from public.invite_active_list_member(
 (select list_id from membership_values where label='pending-list'),
 '10000000-0000-4000-8000-000000000003',null);
select lives_ok(
 $$select public.end_friendship('10000000-0000-4000-8000-000000000003',1)$$,
 'ending friendship applies pending-list effects atomically');
reset role;
select ok(
 (select state='member' from public.active_list_participants
  where list_id=(select list_id from membership_values where label='owner-list')
   and participant_profile_id='10000000-0000-4000-8000-000000000003')
 and (select state='cancelled' from public.active_list_participants
  where list_id=(select list_id from membership_values where label='pending-list')
   and participant_profile_id='10000000-0000-4000-8000-000000000003'),
 'unfriend preserves accepted membership and cancels pending invitation'
);

-- A member blocking another member leaves a third-party list without removing target.
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000005';
insert into membership_values
select 'third-list',list_id,version from public.create_active_list(
 'Third party list','20000000-0000-4000-8000-000000000004'
);
select * from public.invite_active_list_member(
 (select list_id from membership_values where label='third-list'),
 '10000000-0000-4000-8000-000000000002',null);
select * from public.invite_active_list_member(
 (select list_id from membership_values where label='third-list'),
 '10000000-0000-4000-8000-000000000003',null);
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
select is(public.accept_active_list_invitation(
 (select list_id from membership_values where label='third-list'),1),2::bigint,
 'first third-party member accepts');
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000003';
select is(public.accept_active_list_invitation(
 (select list_id from membership_values where label='third-list'),1),2::bigint,
 'second third-party member accepts');
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
select lives_ok($$select public.block_profile('10000000-0000-4000-8000-000000000003')$$,
 'member can block another member without third-party removal authority');
reset role;
select ok(
 (select state='left' from public.active_list_participants
  where list_id=(select list_id from membership_values where label='third-list')
   and participant_profile_id='10000000-0000-4000-8000-000000000002')
 and (select state='member' from public.active_list_participants
  where list_id=(select list_id from membership_values where label='third-list')
   and participant_profile_id='10000000-0000-4000-8000-000000000003'),
 'blocker leaves and cannot remove the other member from a third-party list'
);
select is(
 (select pg_catalog.count(*) from public.user_notifications
  where recipient_id='10000000-0000-4000-8000-000000000005'
   and notification_type='list_member_left'
   and active_list_id=(select list_id from membership_values where label='third-list')),
 1::bigint,'third-party owner receives one generic member-left notification'
);

-- Owner removal works while archived, and member-blocks-owner leaves without restoration.
set local role authenticated;
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000005';
select lives_ok(format($$select * from public.set_active_list_archived(%L,true,1)$$,
 (select list_id from membership_values where label='third-list')),
 'third owner archives their list');
select is(public.remove_active_list_member(
 (select list_id from membership_values where label='third-list'),
 '10000000-0000-4000-8000-000000000003',2),3::bigint,
 'owner may remove an accepted member while archived');
select lives_ok(format($$select * from public.set_active_list_archived(%L,false,2)$$,
 (select list_id from membership_values where label='third-list')),
 'third owner restores without restoring members');
-- Remove the member-member block, then reopen the caller's left row.
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
select public.unblock_profile('10000000-0000-4000-8000-000000000003');
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000005';
select * from public.invite_active_list_member(
 (select list_id from membership_values where label='third-list'),
 '10000000-0000-4000-8000-000000000002',3);
set local "request.jwt.claim.sub" = '10000000-0000-4000-8000-000000000002';
select is(public.accept_active_list_invitation(
 (select list_id from membership_values where label='third-list'),4),5::bigint,
 'former third-party member accepts a deliberate reinvite');
select lives_ok($$select public.block_profile('10000000-0000-4000-8000-000000000005')$$,
 'member blocking owner leaves the list');
reset role;
select ok(
 (select state='left' from public.active_list_participants
  where list_id=(select list_id from membership_values where label='third-list')
   and participant_profile_id='10000000-0000-4000-8000-000000000002'),
 'member-blocks-owner results in caller leave and unblock cannot restore it'
);

-- Auth-root deletion isolates member data, nulls completion attribution, then cascades owner aggregate.
insert into auth.users (id,email,email_confirmed_at,created_at,updated_at) values
 ('30000000-0000-4000-8000-000000000001','delete-owner@membership.test',now(),now(),now()),
 ('30000000-0000-4000-8000-000000000002','delete-member@membership.test',now(),now(),now());
update public.profiles set username=case
 when id='30000000-0000-4000-8000-000000000001' then 'delete_owner'
 else 'delete_member' end,
 display_name='Deletion fixture'
where id in ('30000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002');
insert into public.active_lists(id,owner_id,title,creation_request_id)
values ('30000000-0000-4000-8000-000000000010','30000000-0000-4000-8000-000000000001',
 'Deletion list','30000000-0000-4000-8000-000000000011');
insert into public.active_list_participants(list_id,participant_profile_id,state)
values ('30000000-0000-4000-8000-000000000010','30000000-0000-4000-8000-000000000002','member');
insert into public.active_list_items(
 id,list_id,name,position,creation_request_id,completed_at,completed_by
) values (
 '30000000-0000-4000-8000-000000000012','30000000-0000-4000-8000-000000000010',
 'Retained item',1,'30000000-0000-4000-8000-000000000013',now(),
 '30000000-0000-4000-8000-000000000002'
);
delete from auth.users where id='30000000-0000-4000-8000-000000000002';
select ok(
 exists(select 1 from public.active_lists where id='30000000-0000-4000-8000-000000000010')
 and exists(select 1 from public.active_list_items where id='30000000-0000-4000-8000-000000000012' and completed_at is not null and completed_by is null)
 and not exists(select 1 from public.active_list_participants where participant_profile_id='30000000-0000-4000-8000-000000000002'),
 'member deletion preserves another owner list/item, removes access, and nulls actor attribution'
);
delete from auth.users where id='30000000-0000-4000-8000-000000000001';
select ok(
 not exists(select 1 from public.active_lists where id='30000000-0000-4000-8000-000000000010')
 and not exists(select 1 from public.active_list_items where id='30000000-0000-4000-8000-000000000012'),
 'owner deletion cascades the complete owned shared-list aggregate'
);

select ok(
 not exists (
  select 1 from pg_catalog.pg_publication_tables
  where pubname='supabase_realtime' and tablename='active_list_participants'
 ),
 'membership adds no Realtime publication object'
);

select * from finish();
rollback;
