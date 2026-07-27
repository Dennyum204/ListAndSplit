do $$
declare
  existing_job_id bigint;
begin
  if current_user <> 'postgres' then
    raise exception using
      errcode = '42501',
      message = 'moderation retention scheduling requires postgres';
  end if;

  for existing_job_id in
    select job.jobid
    from cron.job as job
    where job.jobname = 'public-template-moderation-retention-daily'
    order by job.jobid
  loop
    perform cron.unschedule(existing_job_id);
  end loop;

  perform cron.schedule(
    'public-template-moderation-retention-daily',
    '47 3 * * *',
    'select * from private.maintain_public_template_moderation_retention();'
  );
end;
$$;

comment on function
  private.maintain_public_template_moderation_retention(timestamptz) is
  'Postgres-only idempotent purge of fully closed evidence older than 24 months; scheduled daily where A-062 is deployed.';
