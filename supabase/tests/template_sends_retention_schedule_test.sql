begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select is(
  (
    select pg_catalog.count(*)
    from cron.job as job
    where job.jobname = 'template-send-retention-daily'
  ),
  1::bigint,
  'exactly one stable template-send retention job exists'
);

select is(
  (
    select pg_catalog.count(*)
    from cron.job as job
    where job.jobname = 'template-send-retention-daily'
      and job.schedule = '17 4 * * *'
      and job.command =
        'select * from private.maintain_template_send_retention();'
      and job.username = 'postgres'
      and job.database = pg_catalog.current_database()
      and job.active
  ),
  1::bigint,
  'the active daily 04:17 UTC job runs only the exact cleanup as postgres'
);

select is(
  pg_catalog.current_setting('TimeZone'),
  'UTC',
  'the scheduling database uses UTC'
);

select is(
  (
    select pg_catalog.count(*)
    from cron.job as job
    where (
      job.jobname = 'list-and-split-delete-expired-username-reservations'
      and job.schedule = '17 3 * * *'
      and job.command =
        'select private.delete_expired_username_reservations();'
      and job.username = 'postgres'
      and job.active
    ) or (
      job.jobname = 'public-template-moderation-retention-daily'
      and job.schedule = '47 3 * * *'
      and job.command =
        'select * from private.maintain_public_template_moderation_retention();'
      and job.username = 'postgres'
      and job.active
    )
  ),
  2::bigint,
  'the two existing scheduled jobs remain unchanged and non-colliding'
);

select ok(
  (
    select
      function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'private.maintain_template_send_retention(timestamptz)'::regprocedure
  ),
  'the scheduled retention function remains hardened and postgres-owned'
);

select ok(
  has_function_privilege(
    'postgres',
    'private.maintain_template_send_retention(timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.maintain_template_send_retention(timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.maintain_template_send_retention(timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'private.maintain_template_send_retention(timestamptz)',
    'EXECUTE'
  ),
  'only postgres can execute the scheduled retention function'
);

insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  (
    'f1000000-0000-4000-8000-000000000001',
    'retention-sender@example.test',
    now(),
    now(),
    now()
  ),
  (
    'f1000000-0000-4000-8000-000000000002',
    'retention-recipient@example.test',
    now(),
    now(),
    now()
  );

update public.profiles
set username = case id
      when 'f1000000-0000-4000-8000-000000000001'
        then 'retention_sender'
      else 'retention_recipient'
    end,
    display_name = case id
      when 'f1000000-0000-4000-8000-000000000001'
        then 'Retention Sender'
      else 'Retention Recipient'
    end
where id in (
  'f1000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000002'
);

insert into public.templates (
  id,
  owner_id,
  category_id,
  name,
  version,
  creation_request_id,
  created_at,
  updated_at
)
values
  (
    'f2000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000001',
    null,
    'Pending source',
    1,
    'f3000000-0000-4000-8000-000000000001',
    '2025-06-21 12:00:00+00',
    '2025-06-21 12:00:00+00'
  ),
  (
    'f2000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000002',
    null,
    'Accepted independent copy',
    1,
    'f3000000-0000-4000-8000-000000000002',
    '2026-01-28 12:00:00+00',
    '2026-01-28 12:00:00+00'
  ),
  (
    'f2000000-0000-4000-8000-000000000003',
    'f1000000-0000-4000-8000-000000000001',
    null,
    'Unrelated template',
    1,
    'f3000000-0000-4000-8000-000000000003',
    '2026-07-27 12:00:00+00',
    '2026-07-27 12:00:00+00'
  );

insert into public.template_sends (
  id,
  sender_id,
  recipient_id,
  source_template_id,
  snapshot_name,
  snapshot_item_count,
  state,
  version,
  accepted_template_id,
  state_changed_at,
  created_at,
  updated_at
)
values
  (
    'f4000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000002',
    'f2000000-0000-4000-8000-000000000001',
    'Old pending',
    0,
    'pending',
    1,
    null,
    '2025-06-22 12:00:00+00',
    '2025-06-21 12:00:00+00',
    '2025-06-22 12:00:00+00'
  ),
  (
    'f4000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000002',
    null,
    'Young terminal',
    0,
    'declined',
    2,
    null,
    '2026-01-28 12:00:01+00',
    '2026-01-27 12:00:00+00',
    '2026-01-28 12:00:01+00'
  ),
  (
    'f4000000-0000-4000-8000-000000000003',
    'f1000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000002',
    null,
    'Old accepted',
    1,
    'accepted',
    2,
    'f2000000-0000-4000-8000-000000000002',
    '2026-01-28 12:00:00+00',
    '2026-01-27 12:00:00+00',
    '2026-01-28 12:00:00+00'
  );

insert into public.template_send_items (
  id,
  template_send_id,
  name,
  quantity_thousandths,
  position,
  created_at
)
values (
  'f5000000-0000-4000-8000-000000000001',
  'f4000000-0000-4000-8000-000000000003',
  'Accepted snapshot item',
  1000,
  1,
  '2026-01-27 12:00:00+00'
);

insert into private.template_send_requests (
  actor_id,
  request_id,
  operation,
  request_fingerprint,
  template_send_id,
  created_at
)
values (
  'f1000000-0000-4000-8000-000000000002',
  'f6000000-0000-4000-8000-000000000001',
  'accept',
  pg_catalog.decode(pg_catalog.repeat('ab', 32), 'hex'),
  'f4000000-0000-4000-8000-000000000003',
  '2026-01-28 12:00:00+00'
);

insert into public.user_notifications (
  id,
  recipient_id,
  actor_id,
  notification_type,
  created_at,
  expires_at,
  template_send_id,
  template_send_version
)
values
  (
    'f7000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000002',
    null,
    'template_send_received',
    '2026-01-27 12:00:00+00',
    '2026-07-26 12:00:00+00',
    'f4000000-0000-4000-8000-000000000003',
    2
  ),
  (
    'f7000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000002',
    null,
    'template_send_received',
    '2025-06-21 12:00:00+00',
    '2025-12-18 12:00:00+00',
    'f4000000-0000-4000-8000-000000000001',
    1
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
          message = 'template send retention scheduling requires postgres';
      end if;

      for existing_job_id in
        select job.jobid
        from cron.job as job
        where job.jobname = 'template-send-retention-daily'
        order by job.jobid
      loop
        perform cron.unschedule(existing_job_id);
      end loop;

      perform cron.schedule(
        'template-send-retention-daily',
        '17 4 * * *',
        'select * from private.maintain_template_send_retention();'
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
    where job.jobname = 'template-send-retention-daily'
      and job.schedule = '17 4 * * *'
      and job.command =
        'select * from private.maintain_template_send_retention();'
      and job.username = 'postgres'
      and job.active
  ),
  1::bigint,
  'reapplying the scheduling logic converges on one active postgres job'
);

select is(
  (
    select pg_catalog.count(*)
    from public.template_sends
    where id in (
      'f4000000-0000-4000-8000-000000000001',
      'f4000000-0000-4000-8000-000000000002',
      'f4000000-0000-4000-8000-000000000003'
    )
  ),
  3::bigint,
  'scheduling and rescheduling do not invoke cleanup'
);

select is(
  private.maintain_template_send_retention(
    '2026-07-27 12:00:00+00'::timestamptz
  ),
  1::bigint,
  'explicit cleanup deletes terminal history at the exact 180-day boundary'
);

select ok(
  exists (
    select 1
    from public.template_sends
    where id = 'f4000000-0000-4000-8000-000000000001'
      and state = 'pending'
  ),
  'pending invitations survive regardless of age'
);

select ok(
  exists (
    select 1
    from public.template_sends
    where id = 'f4000000-0000-4000-8000-000000000002'
      and state = 'declined'
  ),
  'terminal invitations younger than 180 days survive'
);

select ok(
  not exists (
    select 1
    from public.template_sends
    where id = 'f4000000-0000-4000-8000-000000000003'
  ),
  'terminal invitations at least 180 days old are physically deleted'
);

select ok(
  exists (
    select 1
    from public.templates
    where id = 'f2000000-0000-4000-8000-000000000002'
      and owner_id = 'f1000000-0000-4000-8000-000000000002'
  ),
  'an accepted independent private template survives offer cleanup'
);

select is(
  (
    select pg_catalog.count(*)
    from public.template_send_items
    where template_send_id = 'f4000000-0000-4000-8000-000000000003'
  ),
  0::bigint,
  'snapshot items cascade with purged terminal history'
);

select is(
  (
    select pg_catalog.count(*)
    from private.template_send_requests
    where template_send_id = 'f4000000-0000-4000-8000-000000000003'
  ),
  0::bigint,
  'request ledgers cascade with purged terminal history'
);

select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where template_send_id = 'f4000000-0000-4000-8000-000000000003'
  ),
  0::bigint,
  'associated template-send notifications cascade with purged history'
);

select ok(
  exists (
    select 1
    from public.user_notifications
    where id = 'f7000000-0000-4000-8000-000000000002'
      and template_send_id = 'f4000000-0000-4000-8000-000000000001'
  )
  and exists (
    select 1
    from public.templates
    where id = 'f2000000-0000-4000-8000-000000000003'
  ),
  'unrelated notification and template data remain untouched'
);

select is(
  private.maintain_template_send_retention(
    '2026-07-27 12:00:00+00'::timestamptz
  ),
  0::bigint,
  'template-send retention remains idempotent'
);

select * from finish();
rollback;
