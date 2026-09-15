begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
 where oid in ('private.push_devices'::regclass,'private.push_deliveries'::regclass)), 'forced RLS on both operational tables');
select ok(not has_table_privilege('authenticated','private.push_devices','SELECT')
 and not has_table_privilege('service_role','private.push_devices','UPDATE'), 'no direct token/table access');
select ok(not has_function_privilege('anon','public.register_push_device(uuid,uuid,text,uuid,boolean)','EXECUTE')
 and has_function_privilege('authenticated','public.register_push_device(uuid,uuid,text,uuid,boolean)','EXECUTE'), 'new registrations require authentication');
select ok(not has_function_privilege('authenticated','public.claim_push_deliveries(integer)','EXECUTE')
 and has_function_privilege('service_role','public.claim_push_deliveries(integer)','EXECUTE'), 'only worker can claim tokens');
select ok((select bool_and(proowner='postgres'::regrole and prosecdef and proconfig @> array['search_path=""'])
 from pg_proc where pronamespace in ('private'::regnamespace,'public'::regnamespace) and proname like '%push%'), 'exact hardened definer ownership/search path');
select is((select count(*) from cron.job where jobname='list-and-split-push-minute'
 and schedule='* * * * *' and username='postgres' and active),1::bigint,'one bounded operational minute job');
select is((select count(*) from private.push_deliveries),0::bigint,'no history backfill');

insert into auth.users(id,email,email_confirmed_at,created_at,updated_at) values
 ('ba000000-0000-4000-8000-000000000001','push-one@example.test',now(),now(),now()),
 ('ba000000-0000-4000-8000-000000000002','push-two@example.test',now(),now(),now());
update public.profiles set username='push' || right(id::text,1), display_name='Push local fixture'
 where id in ('ba000000-0000-4000-8000-000000000001','ba000000-0000-4000-8000-000000000002');
insert into auth.sessions(id,user_id,created_at) values
 ('bb000000-0000-4000-8000-000000000001','ba000000-0000-4000-8000-000000000001',now());
set local role authenticated;
set local "request.jwt.claims"='{"sub":"ba000000-0000-4000-8000-000000000001","session_id":"bb000000-0000-4000-8000-000000000001"}';
select lives_ok($$select public.register_push_device('bc000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','local-token-for-fixture-one','ba000000-0000-4000-8000-000000000001')$$,'authenticated own enrollment');
select throws_ok($$select public.register_push_device(gen_random_uuid(),gen_random_uuid(),'local-token-for-fixture-two','ba000000-0000-4000-8000-000000000002')$$,'22023','invalid device registration','caller cannot enroll another account');
set local "request.jwt.claims"='{"sub":"ba000000-0000-4000-8000-000000000002"}';
select public.send_friend_request('ba000000-0000-4000-8000-000000000001',null);
reset role;
select is((select count(*) from private.push_deliveries),1::bigint,'committed event creates exactly one delivery');
create temp table push_claim as select * from public.claim_push_deliveries(20);
select is((select count(*) from push_claim),1::bigint,'one initial lease');
select is((select count(*) from public.claim_push_deliveries(20)),0::bigint,'concurrent claim does not repeat leased work');
select ok(public.prepare_push_delivery((select delivery_id from push_claim),(select delivery_lease from push_claim)) is not null,'authoritative prepare is authorized');
select is(public.prepare_push_delivery((select delivery_id from push_claim),gen_random_uuid()),null::jsonb,'wrong lease cannot prepare');
select public.finish_push_delivery((select delivery_id from push_claim),gen_random_uuid(),'sent');
select is((select status from private.push_deliveries),'pending','stale completion does not change state');
select public.finish_push_delivery((select delivery_id from push_claim),(select delivery_lease from push_claim),'retry');
select ok((select next_attempt_at >= now()+interval '60 seconds' and attempts=1 from private.push_deliveries),'backoff, not an immediate retry');
select is((select count(*) from public.claim_push_deliveries(20)),0::bigint,'no application retry loop');
update private.push_deliveries set next_attempt_at=now();
delete from push_claim; insert into push_claim select * from public.claim_push_deliveries(20);
select public.finish_push_delivery((select delivery_id from push_claim),(select delivery_lease from push_claim),'retry');
update private.push_deliveries set next_attempt_at=now();
delete from push_claim; insert into push_claim select * from public.claim_push_deliveries(20);
select public.finish_push_delivery((select delivery_id from push_claim),(select delivery_lease from push_claim),'retry');
update private.push_deliveries set next_attempt_at=now();
delete from push_claim; insert into push_claim select * from public.claim_push_deliveries(20);
select public.finish_push_delivery((select delivery_id from push_claim),(select delivery_lease from push_claim),'retry');
select ok((select attempts=4 and status='failed' and lease_id is null from private.push_deliveries),'four attempts is a hard delivery bound');
select is((select count(*) from public.claim_push_deliveries(20)),0::bigint,'exhausted work cannot be reclaimed');
select is(public.rotate_push_token(gen_random_uuid(),'bd000000-0000-4000-8000-000000000001','local-token-for-fixture-one','local-token-new-fixture-one'),false,'unrelated capability cannot rotate');
select is(public.rotate_push_token('bc000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','local-token-for-fixture-one','local-token-new-fixture-one'),true,'bound background token rotation');
select is(public.rotate_push_token('bc000000-0000-4000-8000-000000000001','bd000000-0000-4000-8000-000000000001','local-token-for-fixture-one','local-token-other-fixture'),false,'stale token cannot rotate again');
delete from auth.sessions where id='bb000000-0000-4000-8000-000000000001';
select is((select count(*) from private.push_devices),0::bigint,'session revocation cascades device');
select is((select count(*) from private.push_deliveries),0::bigint,'revocation cascades pending/terminal delivery metadata');
select * from finish();
rollback;
