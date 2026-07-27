begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select is(
  (
    select pg_catalog.count(*)
    from cron.job as job
    where job.jobname = 'public-template-moderation-retention-daily'
  ),
  1::bigint,
  'exactly one stable moderation retention job exists'
);

select is(
  (
    select pg_catalog.count(*)
    from cron.job as job
    where job.jobname = 'public-template-moderation-retention-daily'
      and job.schedule = '47 3 * * *'
      and job.command =
        'select * from private.maintain_public_template_moderation_retention();'
      and job.username = 'postgres'
      and job.database = pg_catalog.current_database()
      and job.active
  ),
  1::bigint,
  'the active daily 03:47 UTC job runs the exact cleanup as postgres'
);

select ok(
  (
    select
      function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'private.maintain_public_template_moderation_retention(timestamptz)'::regprocedure
  ),
  'the scheduled retention function remains hardened and postgres-owned'
);

select ok(
  has_function_privilege(
    'postgres',
    'private.maintain_public_template_moderation_retention(timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.maintain_public_template_moderation_retention(timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.maintain_public_template_moderation_retention(timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'private.maintain_public_template_moderation_retention(timestamptz)',
    'EXECUTE'
  ),
  'only postgres can execute the scheduled retention function'
);

select lives_ok(
  $sql$
    select cron.schedule(
      'public-template-moderation-retention-daily',
      '47 3 * * *',
      'select * from private.maintain_public_template_moderation_retention();'
    )
  $sql$,
  'repeating the stable schedule operation succeeds'
);

select is(
  (
    select pg_catalog.count(*)
    from cron.job as job
    where job.jobname = 'public-template-moderation-retention-daily'
      and job.schedule = '47 3 * * *'
      and job.command =
        'select * from private.maintain_public_template_moderation_retention();'
      and job.username = 'postgres'
      and job.active
  ),
  1::bigint,
  'repeated scheduling converges on one active postgres job'
);

select * from finish();
rollback;
