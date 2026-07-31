begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select is(
  (
    select pg_catalog.count(*)
    from cron.job as job
    where job.jobname = 'list-chat-retention-daily'
  ),
  1::bigint,
  'exactly one stable List Chat retention job exists'
);

select is(
  (
    select pg_catalog.count(*)
    from cron.job as job
    where job.jobname = 'list-chat-retention-daily'
      and job.schedule = '47 4 * * *'
      and job.command =
        'select * from private.maintain_active_list_chat_retention();'
      and job.username = 'postgres'
      and job.database = pg_catalog.current_database()
      and job.active
  ),
  1::bigint,
  'the active daily 04:47 UTC job runs only the exact cleanup as postgres'
);

select ok(
  case
    when pg_catalog.current_setting('cron.timezone', true) is not null then
      pg_catalog.current_setting('cron.timezone') in ('UTC', 'GMT')
    else
      (
        select pg_catalog.string_to_array(
          pg_catalog.regexp_replace(
            extension_record.extversion,
            '[^0-9.].*$',
            ''
          ),
          '.'
        )::integer[] < array[1, 5]::integer[]
        from pg_catalog.pg_extension as extension_record
        where extension_record.extname = 'pg_cron'
      )
  end,
  'pg_cron uses an explicit UTC/GMT scheduler or its older fixed-GMT behavior'
);

select ok(
  (
    select
      function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'private.maintain_active_list_chat_retention(timestamptz,integer)'::regprocedure
  ),
  'the scheduled retention function remains hardened and postgres-owned'
);

select ok(
  pg_catalog.has_function_privilege(
    'postgres',
    'private.maintain_active_list_chat_retention(timestamptz,integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'public',
    'private.maintain_active_list_chat_retention(timestamptz,integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'anon',
    'private.maintain_active_list_chat_retention(timestamptz,integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'authenticated',
    'private.maintain_active_list_chat_retention(timestamptz,integer)',
    'EXECUTE'
  )
  and not pg_catalog.has_function_privilege(
    'service_role',
    'private.maintain_active_list_chat_retention(timestamptz,integer)',
    'EXECUTE'
  ),
  'only postgres can execute the scheduled retention function'
);

create temporary table list_chat_unrelated_cron_baseline
on commit drop
as
select job.*
from cron.job as job
where job.jobname <> 'list-chat-retention-daily';

insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at
)
values (
  'fa000000-0000-4000-8000-000000000001',
  'list-chat-retention-owner@example.test',
  '2025-01-01 00:00:00+00',
  '2025-01-01 00:00:00+00',
  '2025-01-01 00:00:00+00'
);

update public.profiles
set username = 'chat_retention_owner',
    display_name = 'List Chat Retention Owner'
where id = 'fa000000-0000-4000-8000-000000000001';

insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id,
  created_at,
  updated_at
)
values (
  'fb000000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'Retention schedule sentinel',
  'fc000000-0000-4000-8000-000000000001',
  '2025-01-01 00:00:00+00',
  '2025-01-01 00:00:00+00'
);

insert into public.active_list_chat_messages (
  id,
  list_id,
  message_position,
  sender_profile_id,
  body,
  created_at
)
values (
  'fd000000-0000-4000-8000-000000000001',
  'fb000000-0000-4000-8000-000000000001',
  pg_catalog.nextval(
    'private.active_list_chat_message_position_seq'::regclass
  ),
  'fa000000-0000-4000-8000-000000000001',
  'Eligible scheduling sentinel',
  '2025-01-01 00:00:00+00'
);

select lives_ok(
  $sql$
    do $body$
    declare
      existing_job_id bigint;
    begin
      if current_user <> 'postgres' then
        raise exception using
          errcode = '42501',
          message = 'list chat retention scheduling requires postgres';
      end if;

      for existing_job_id in
        select job.jobid
        from cron.job as job
        where job.jobname = 'list-chat-retention-daily'
        order by job.jobid
      loop
        perform cron.unschedule(existing_job_id);
      end loop;

      perform cron.schedule(
        'list-chat-retention-daily',
        '47 4 * * *',
        'select * from private.maintain_active_list_chat_retention();'
      );
    end;
    $body$;
  $sql$,
  'reapplying the reviewed scheduling logic succeeds'
);

select is(
  (
    select pg_catalog.count(*)
    from cron.job as job
    where job.jobname = 'list-chat-retention-daily'
      and job.schedule = '47 4 * * *'
      and job.command =
        'select * from private.maintain_active_list_chat_retention();'
      and job.username = 'postgres'
      and job.database = pg_catalog.current_database()
      and job.active
  ),
  1::bigint,
  'reapplying the scheduling logic converges on one active postgres job'
);

select is(
  (
    select pg_catalog.count(*)
    from public.active_list_chat_messages
    where id = 'fd000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'scheduling and rescheduling do not invoke cleanup'
);

select is(
  (
    select pg_catalog.count(*)
    from (
      (
        select job.*
        from cron.job as job
        where job.jobname <> 'list-chat-retention-daily'
        except all
        select baseline.*
        from list_chat_unrelated_cron_baseline as baseline
      )
      union all
      (
        select baseline.*
        from list_chat_unrelated_cron_baseline as baseline
        except all
        select job.*
        from cron.job as job
        where job.jobname <> 'list-chat-retention-daily'
      )
    ) as difference
  ),
  0::bigint,
  'unrelated Cron jobs remain byte-for-byte unchanged'
);

select * from finish();
rollback;
