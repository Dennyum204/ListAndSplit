do $$
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
$$;
