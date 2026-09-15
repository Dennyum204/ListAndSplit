begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select no_plan();
-- Isolated local-only fixtures; no image bytes or hosted identities.
select extensions.dblink_connect('avatar_first','host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=avatar_first');
select extensions.dblink_connect('avatar_second','host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=avatar_second');
select extensions.dblink_exec('avatar_first',$sql$
 insert into auth.users(id,email,email_confirmed_at,created_at,updated_at) values
 ('ab100000-0000-4000-8000-000000000001','avatar-race@example.test',now(),now(),now());
$sql$);
select extensions.dblink_exec('avatar_second',$sql$
 create function pg_temp.attempt_avatar() returns text language plpgsql as $body$
 begin
   perform public.begin_profile_avatar_operation('ab100000-0000-4000-8000-000000000001',gen_random_uuid(),'remove',0);
   return 'unexpected success';
 exception when others then return SQLSTATE;
 end; $body$;
$sql$);
select extensions.dblink_exec('avatar_first','begin');
create temporary table avatar_race_result as
 select result from extensions.dblink('avatar_first',$sql$
 select public.begin_profile_avatar_operation('ab100000-0000-4000-8000-000000000001',gen_random_uuid(),'upload',0)
 $sql$) as t(result jsonb);
select extensions.dblink_send_query('avatar_second','select pg_temp.attempt_avatar()');
-- Observe the actual lock wait instead of relying on an arbitrary sleep.
do $$
declare deadline timestamptz := clock_timestamp()+interval '5 seconds';
begin
 loop
   exit when exists(select 1 from pg_stat_activity where application_name='avatar_second' and wait_event_type='Lock');
   if clock_timestamp()>deadline then raise exception 'avatar competitor never reached the lock'; end if;
   perform pg_sleep(0.01);
 end loop;
end $$;
select is(extensions.dblink_is_busy('avatar_second'),1,'concurrent operation waits for the same profile lock');
select extensions.dblink_exec('avatar_first','commit');
select is((select result from extensions.dblink_get_result('avatar_second') as t(result text)),'55P03','committed upload fence rejects competing remove/export/deletion');
select * from extensions.dblink_get_result('avatar_second') as t(result text);
select is((select count(*) from private.profile_avatars where profile_id='ab100000-0000-4000-8000-000000000001'),1::bigint,'concurrent beginnings create one metadata row');
select is((select version from private.profile_avatars where profile_id='ab100000-0000-4000-8000-000000000001'),0::bigint,'losing operation cannot advance version');
select is((select count(*) from private.profile_avatar_files where profile_id='ab100000-0000-4000-8000-000000000001'),0::bigint,'losing operation cannot stage an object');
-- Only the fixture is deleted; no avatar upload occurred, and every remote
-- transaction has ended. This also proves stale worker tokens cannot resurrect.
select extensions.dblink_exec('avatar_first',$sql$
 delete from auth.users where id='ab100000-0000-4000-8000-000000000001';
$sql$);
select throws_ok($sql$
 select public.commit_profile_avatar('ab100000-0000-4000-8000-000000000001',
 (select(result->>'lease')::uuid from avatar_race_result),null,gen_random_uuid(),'late')
$sql$,'55P03','avatar lease unavailable','deleted-account worker cannot commit');
select extensions.dblink_disconnect('avatar_first');
select extensions.dblink_disconnect('avatar_second');
select * from finish();
rollback;
