begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select has_table('private','profile_avatars','private current avatar state');
select has_table('private','profile_avatar_files','durable cleanup ledger');
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
  where oid in ('private.profile_avatars'::regclass,'private.profile_avatar_files'::regclass)), 'forced RLS');
select ok(not has_table_privilege('authenticated','private.profile_avatars','SELECT')
  and not has_table_privilege('service_role','private.profile_avatar_files','DELETE'), 'no direct client or admin Data API tables');
select ok((select not public and file_size_limit=327680 and allowed_mime_types=array['image/png']
  from storage.buckets where id='profile-avatars'),'bounded private PNG bucket');
select is((select count(*) from cron.job),4::bigint,'no new scheduled job');
select ok((select bool_and(proowner='postgres'::regrole and prosecdef and proconfig @> array['search_path=""']
  and not has_function_privilege('anon',oid,'EXECUTE') and not has_function_privilege('public',oid,'EXECUTE'))
  from pg_proc where pronamespace='public'::regnamespace and proname like '%profile_avatar%'),'new RPC security catalog');
select ok(has_function_privilege('authenticated','public.resolve_profile_avatar(text,uuid)','EXECUTE')
  and not has_function_privilege('service_role','public.resolve_profile_avatar(text,uuid)','EXECUTE'),'only user-scoped avatar reads');
select ok(has_function_privilege('service_role','public.begin_profile_avatar_operation(uuid,uuid,text,bigint)','EXECUTE')
  and not has_function_privilege('authenticated','public.begin_profile_avatar_operation(uuid,uuid,text,bigint)','EXECUTE'),'server-only writes');
insert into auth.users(id,email,email_confirmed_at,created_at,updated_at) values
  ('aa000000-0000-4000-8000-000000000001','avatar-one@example.test',now(),now(),now()),
  ('aa000000-0000-4000-8000-000000000002','avatar-two@example.test',now(),now(),now()),
  ('aa000000-0000-4000-8000-000000000003','avatar-incomplete@example.test',now(),now(),now());
update public.profiles set username='avatar' || right(id::text,1),display_name='Avatar fixture'
  where id in ('aa000000-0000-4000-8000-000000000001','aa000000-0000-4000-8000-000000000002');
create temporary table avatar_results(k text primary key,v jsonb);
grant all on avatar_results to authenticated,service_role;
set local role authenticated;
set local "request.jwt.claim.sub"='aa000000-0000-4000-8000-000000000001';
select is(public.get_own_profile_avatar(),'{"version":0,"has_image":false}'::jsonb,'initial avatar is absent');
select is(public.resolve_profile_avatar('profile','aa000000-0000-4000-8000-000000000002'),null::uuid,'absence does not invent a photo');
select throws_ok($$select public.stage_profile_avatar_file('aa000000-0000-4000-8000-000000000001',gen_random_uuid())$$,'42501',null,'user cannot bypass image validation');
reset role;
insert into avatar_results values('lease',public.begin_profile_avatar_operation(
  'aa000000-0000-4000-8000-000000000001','ab000000-0000-4000-8000-000000000001','first',0));
select throws_ok($$select public.begin_profile_avatar_operation('aa000000-0000-4000-8000-000000000001',gen_random_uuid(),'concurrent',0)$$,
 '55P03','avatar operation in progress','concurrent writes/deletion cannot pass active upload lease');
insert into avatar_results select 'file',to_jsonb(public.stage_profile_avatar_file('aa000000-0000-4000-8000-000000000001',(v->>'lease')::uuid)) from avatar_results where k='lease';
select throws_ok($$delete from auth.users where id='aa000000-0000-4000-8000-000000000001'$$,'23503',null,'Auth deletion fails closed until binary ledger is cleaned');
insert into avatar_results select 'published',public.commit_profile_avatar('aa000000-0000-4000-8000-000000000001',
  (l.v->>'lease')::uuid,(f.v#>>'{}')::uuid,'ab000000-0000-4000-8000-000000000001','first')
  from avatar_results l,avatar_results f where l.k='lease' and f.k='file';
select is((select v from avatar_results where k='published'),'{"version":1,"has_image":true}'::jsonb,'publish increments once');
select is(public.commit_profile_avatar('aa000000-0000-4000-8000-000000000001',
  (select (v->>'lease')::uuid from avatar_results where k='lease'),(select (v#>>'{}')::uuid from avatar_results where k='file'),
  'ab000000-0000-4000-8000-000000000001','first'),'{"version":1,"has_image":true}'::jsonb,'identical commit retry is idempotent');
select public.finish_profile_avatar_operation('aa000000-0000-4000-8000-000000000001',(select(v->>'lease')::uuid from avatar_results where k='lease'));
select throws_ok($$select public.begin_profile_avatar_operation('aa000000-0000-4000-8000-000000000001','ab000000-0000-4000-8000-000000000001','conflict',0)$$,
 '22023','conflicting avatar request','UUID reuse cannot change payload');
select throws_ok($$select public.begin_profile_avatar_operation('aa000000-0000-4000-8000-000000000001',gen_random_uuid(),'stale',0)$$,
 '40001','avatar changed','stale version cannot overwrite photo');
set local role authenticated;
set local "request.jwt.claim.sub"='aa000000-0000-4000-8000-000000000002';
select is(public.resolve_profile_avatar('profile','aa000000-0000-4000-8000-000000000001'),
 (select(v#>>'{}')::uuid from avatar_results where k='file'),'authorized nonfriend can view photo');
select is(public.resolve_profile_avatar('chat',gen_random_uuid()),null::uuid,'unknown message cannot enumerate identities');
select is(public.resolve_profile_avatar('split',gen_random_uuid()),null::uuid,'unknown Split context has no photo');
reset role;
insert into public.active_lists(id,owner_id,title,creation_request_id) values
 ('ac000000-0000-4000-8000-000000000001','aa000000-0000-4000-8000-000000000001','Avatar list',gen_random_uuid());
set local role authenticated;
set local "request.jwt.claim.sub"='aa000000-0000-4000-8000-000000000001';
insert into avatar_results values('older_message',public.send_active_list_chat_message('ac000000-0000-4000-8000-000000000001','Before joining',gen_random_uuid()));
reset role;
insert into public.active_list_participants(list_id,participant_profile_id,state) values
 ('ac000000-0000-4000-8000-000000000001','aa000000-0000-4000-8000-000000000002','member');
set local role authenticated;
set local "request.jwt.claim.sub"='aa000000-0000-4000-8000-000000000001';
insert into avatar_results values('message',public.send_active_list_chat_message('ac000000-0000-4000-8000-000000000001','Visible message',gen_random_uuid()));
set local "request.jwt.claim.sub"='aa000000-0000-4000-8000-000000000002';
select is(public.resolve_profile_avatar('chat',(select(v->>'id')::uuid from avatar_results where k='older_message')),null::uuid,'Chat visibility boundary is preserved');
select is(public.resolve_profile_avatar('chat',(select(v->>'id')::uuid from avatar_results where k='message')),
 (select(v#>>'{}')::uuid from avatar_results where k='file'),'visible Chat resolves without exposing sender profile ID');
reset role;
insert into public.active_list_split_settings(list_id,currency_code) values('ac000000-0000-4000-8000-000000000001','CHF');
insert into public.active_list_split_participants(id,list_id,profile_id,username_snapshot,display_name_snapshot) values
 ('ad000000-0000-4000-8000-000000000001','ac000000-0000-4000-8000-000000000001','aa000000-0000-4000-8000-000000000001','avatar1','Avatar fixture');
set local role authenticated;
select is(public.resolve_profile_avatar('split','ad000000-0000-4000-8000-000000000001'),
 (select(v#>>'{}')::uuid from avatar_results where k='file'),'authorized Split context resolves current avatar');
reset role;
insert into avatar_results select 'peer_broadcasts',to_jsonb(count(*)) from realtime.messages
 where topic='account:aa000000-0000-4000-8000-000000000002' and event='invalidate';
insert into avatar_results select 'avatar_notifications',to_jsonb(count(*)) from public.user_notifications;
-- Trusted fixture write isolates the trigger without changing request/version tests.
update private.profile_avatars set current_file=null where profile_id='aa000000-0000-4000-8000-000000000001';
select is((select count(*) from realtime.messages where topic='account:aa000000-0000-4000-8000-000000000002' and event='invalidate'),
 (select(v#>>'{}')::bigint+1 from avatar_results where k='peer_broadcasts'),'current accepted list peer receives one avatar invalidation');
select ok((select bool_and(private and payload-'id'='{"v":1}'::jsonb) from realtime.messages
 where topic='account:aa000000-0000-4000-8000-000000000002' and event='invalidate'),'avatar fanout is private and opaque');
select is((select to_jsonb(count(*)) from public.user_notifications),(select v from avatar_results where k='avatar_notifications'),'avatar changes create no notification rows');
update private.profile_avatars set current_file=(select(v#>>'{}')::uuid from avatar_results where k='file')
 where profile_id='aa000000-0000-4000-8000-000000000001';
set local role authenticated;
select public.block_profile('aa000000-0000-4000-8000-000000000001');
select is(public.resolve_profile_avatar('profile','aa000000-0000-4000-8000-000000000001'),null::uuid,'outgoing block hides photo');
set local "request.jwt.claim.sub"='aa000000-0000-4000-8000-000000000001';
select is(public.resolve_profile_avatar('profile','aa000000-0000-4000-8000-000000000002'),null::uuid,'incoming block hides photo');
set local "request.jwt.claim.sub"='aa000000-0000-4000-8000-000000000002';
select is(public.resolve_profile_avatar('chat',(select(v->>'id')::uuid from avatar_results where k='message')),null::uuid,'removed member loses Chat photo access');
select is(public.resolve_profile_avatar('split','ad000000-0000-4000-8000-000000000001'),null::uuid,'removed member loses Split photo access');
set local "request.jwt.claim.sub"='aa000000-0000-4000-8000-000000000003';
select throws_ok($$select public.get_own_profile_avatar()$$,'42501','verified profile required','incomplete profile cannot edit photo');
reset role;
-- Simulate a crashed operation and deterministic expiry without sleeping.
insert into avatar_results values('recovery',public.begin_profile_avatar_operation(
 'aa000000-0000-4000-8000-000000000001',gen_random_uuid(),'remove',1));
select public.stage_profile_avatar_file('aa000000-0000-4000-8000-000000000001',(select(v->>'lease')::uuid from avatar_results where k='recovery'));
select throws_ok($$select public.stage_profile_avatar_file('aa000000-0000-4000-8000-000000000001',(select(v->>'lease')::uuid from avatar_results where k='recovery'))$$,
 '55000','avatar cleanup required','current plus staging are bounded to two files');
update private.profile_avatars set lease_until=clock_timestamp()-interval '1 second' where profile_id='aa000000-0000-4000-8000-000000000001';
select throws_ok($$select public.commit_profile_avatar('aa000000-0000-4000-8000-000000000001',(select(v->>'lease')::uuid from avatar_results where k='recovery'),null,gen_random_uuid(),'late')$$,
 '55P03','avatar lease unavailable','expired workers cannot publish');
insert into avatar_results values('delete',public.begin_profile_avatar_operation('aa000000-0000-4000-8000-000000000001',gen_random_uuid(),'account-delete',null));
select is((select jsonb_array_length(v->'files') from avatar_results where k='delete'),2,'recovery includes both durable cleanup keys');
select public.commit_profile_avatar('aa000000-0000-4000-8000-000000000001',(select(v->>'lease')::uuid from avatar_results where k='delete'),null,gen_random_uuid(),'account-delete');
select public.forget_profile_avatar_file('aa000000-0000-4000-8000-000000000001',(select(v->>'lease')::uuid from avatar_results where k='delete'),id)
 from private.profile_avatar_files where profile_id='aa000000-0000-4000-8000-000000000001';
-- The same departing identity also has financial history in a surviving list.
insert into public.active_lists(id,owner_id,title,creation_request_id) values
 ('ac000000-0000-4000-8000-000000000002','aa000000-0000-4000-8000-000000000002','Surviving history',gen_random_uuid());
insert into public.active_list_split_settings(list_id,currency_code) values
 ('ac000000-0000-4000-8000-000000000002','EUR');
insert into public.active_list_split_participants(id,list_id,profile_id,username_snapshot,display_name_snapshot) values
 ('ad000000-0000-4000-8000-000000000002','ac000000-0000-4000-8000-000000000002','aa000000-0000-4000-8000-000000000001','avatar1','Avatar fixture'),
 ('ad000000-0000-4000-8000-000000000003','ac000000-0000-4000-8000-000000000002','aa000000-0000-4000-8000-000000000002','avatar2','Avatar fixture');
insert into public.active_list_expenses(id,list_id,description,amount_minor,payer_participant_id,
 creator_participant_id,last_editor_participant_id,creation_request_id) values
 ('af000000-0000-4000-8000-000000000001','ac000000-0000-4000-8000-000000000002','Retained expense',100,
 'ad000000-0000-4000-8000-000000000002','ad000000-0000-4000-8000-000000000002','ad000000-0000-4000-8000-000000000002',gen_random_uuid());
insert into public.active_list_expense_shares(list_id,expense_id,participant_id,amount_minor) values
 ('ac000000-0000-4000-8000-000000000002','af000000-0000-4000-8000-000000000001','ad000000-0000-4000-8000-000000000003',100);
insert into public.active_list_settlements(list_id,payer_participant_id,recipient_participant_id,recorded_by_participant_id,amount_minor,creation_request_id) values
 ('ac000000-0000-4000-8000-000000000002','ad000000-0000-4000-8000-000000000003','ad000000-0000-4000-8000-000000000002','ad000000-0000-4000-8000-000000000002',40,gen_random_uuid());
insert into avatar_results select 'retained_expense',to_jsonb(e) from public.active_list_expenses e where e.id='af000000-0000-4000-8000-000000000001';
insert into avatar_results select 'retained_settlement',to_jsonb(s) from public.active_list_settlements s where s.list_id='ac000000-0000-4000-8000-000000000002';
select lives_ok($$delete from auth.users where id='aa000000-0000-4000-8000-000000000001'$$,'after acknowledged binary cleanup Auth-root deletion succeeds');
select is((select count(*) from private.profile_avatars where profile_id='aa000000-0000-4000-8000-000000000001'),0::bigint,'avatar metadata cascades');
select is((select profile_id from public.active_list_split_participants where id='ad000000-0000-4000-8000-000000000001'),null::uuid,'no historical avatar identity survives account deletion');
select is((select count(*) from public.active_lists where id='ac000000-0000-4000-8000-000000000001'),0::bigint,'owned Split list cascades');
select ok(exists(select 1 from public.active_list_split_participants where id='ad000000-0000-4000-8000-000000000002'
 and profile_id is null and username_snapshot is null and display_name_snapshot is null),'surviving financial endpoint remains but all identity fields are anonymized together');
select is((select to_jsonb(e) from public.active_list_expenses e where e.id='af000000-0000-4000-8000-000000000001'),
 (select v from avatar_results where k='retained_expense'),'expense amounts and attribution endpoint IDs remain unchanged');
select is((select to_jsonb(s) from public.active_list_settlements s where s.list_id='ac000000-0000-4000-8000-000000000002'),
 (select v from avatar_results where k='retained_settlement'),'immutable settlement history remains byte-for-byte unchanged');
select is((select sum(amount_minor) from public.active_list_expense_shares where list_id='ac000000-0000-4000-8000-000000000002'),100::numeric,'retained shares preserve exact arithmetic');
set local role authenticated;
set local "request.jwt.claim.sub"='aa000000-0000-4000-8000-000000000002';
select is(public.resolve_profile_avatar('split','ad000000-0000-4000-8000-000000000002'),null::uuid,'anonymized financial identity never resolves a photograph');
-- Reproduce the original bug through real owner RPCs, with no avatar metadata.
insert into avatar_results select 'rpc_list',to_jsonb(l) from public.create_active_list('No-avatar owner',gen_random_uuid()) l;
select lives_ok($$select public.enable_active_list_split((select(v->>'list_id')::uuid from avatar_results where k='rpc_list'),'CHF',1)$$,'ordinary owner enables Split without avatar');
reset role;
select lives_ok($$delete from auth.users where id='aa000000-0000-4000-8000-000000000002'$$,'owner Auth deletion also succeeds without any avatar');
select * from finish();
rollback;
