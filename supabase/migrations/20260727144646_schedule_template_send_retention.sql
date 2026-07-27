do $$
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
$$;

comment on function private.maintain_template_send_retention(timestamptz) is
  'Postgres-only idempotent purge of terminal template-send history at least 180 days old; scheduled daily at 04:17 UTC where this operational migration is deployed.';
