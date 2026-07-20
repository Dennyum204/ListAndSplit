begin;

create extension if not exists pg_cron with schema pg_catalog;

create table private.deleted_username_reservations (
  canonical_username text primary key,
  reserved_until timestamptz not null
);

alter table private.deleted_username_reservations owner to postgres;
alter table private.deleted_username_reservations enable row level security;
alter table private.deleted_username_reservations force row level security;

revoke all on table private.deleted_username_reservations
from public, anon, authenticated, service_role;

create policy "deleted_username_reservations_reject_direct_client_access"
on private.deleted_username_reservations
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create function private.assert_username_available(
  candidate_username text,
  candidate_profile_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if candidate_username is null then
    return;
  end if;

  -- Lock a conflicting live owner before checking the reservation. If that row
  -- is being deleted, this waits for its deletion trigger to commit the hold.
  perform 1
  from public.profiles as active_profile
  where active_profile.username = candidate_username
    and active_profile.id <> candidate_profile_id
  for key share;

  if found then
    raise exception using
      errcode = '23505',
      message = 'username unavailable',
      constraint = 'profiles_username_key';
  end if;

  perform 1
  from private.deleted_username_reservations as reservation
  where reservation.canonical_username = candidate_username
    and reservation.reserved_until > pg_catalog.statement_timestamp()
  for share;

  if found then
    raise exception using
      errcode = '23505',
      message = 'username unavailable',
      constraint = 'profiles_username_key';
  end if;
end;
$$;

alter function private.assert_username_available(text, uuid)
owner to postgres;

revoke all on function private.assert_username_available(text, uuid)
from public, anon, authenticated, service_role;

create or replace function private.prepare_profile_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.username is not null then
    new.username := pg_catalog.lower(
      pg_catalog.regexp_replace(
        new.username,
        '^[[:space:]]+|[[:space:]]+$',
        '',
        'g'
      )
    );
  end if;

  if new.display_name is not null then
    new.display_name := pg_catalog.regexp_replace(
      new.display_name,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    );
  end if;

  if tg_op = 'UPDATE' then
    if old.onboarding_completed_at is not null
      and new.username is distinct from old.username
    then
      raise exception using
        errcode = '22023',
        message = 'username cannot be changed after onboarding is complete';
    end if;

    new.created_at := old.created_at;
    new.onboarding_completed_at := old.onboarding_completed_at;
    new.updated_at := pg_catalog.now();
  end if;

  perform private.assert_username_available(new.username, new.id);

  if new.onboarding_completed_at is null
    and new.username is not null
    and new.display_name is not null
  then
    new.onboarding_completed_at := pg_catalog.now();
  end if;

  return new;
end;
$$;

alter function private.prepare_profile_write() owner to postgres;

revoke all on function private.prepare_profile_write()
from public, anon, authenticated, service_role;

create function private.reserve_deleted_username()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  reservation_expiry timestamptz;
begin
  if old.onboarding_completed_at is null or old.username is null then
    return old;
  end if;

  reservation_expiry := pg_catalog.clock_timestamp() + interval '30 days';

  insert into private.deleted_username_reservations (
    canonical_username,
    reserved_until
  )
  values (
    old.username,
    reservation_expiry
  )
  on conflict (canonical_username) do update
  set reserved_until = case
    when private.deleted_username_reservations.reserved_until
      > excluded.reserved_until
      then private.deleted_username_reservations.reserved_until
    else excluded.reserved_until
  end;

  return old;
end;
$$;

alter function private.reserve_deleted_username() owner to postgres;

revoke all on function private.reserve_deleted_username()
from public, anon, authenticated, service_role;

create trigger reserve_username_before_profile_delete
before delete on public.profiles
for each row execute function private.reserve_deleted_username();

create function private.delete_expired_username_reservations()
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  deleted_count bigint;
begin
  delete from private.deleted_username_reservations as reservation
  where reservation.reserved_until <= pg_catalog.clock_timestamp();

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

alter function private.delete_expired_username_reservations()
owner to postgres;

revoke all on function private.delete_expired_username_reservations()
from public, anon, authenticated, service_role;

do $$
declare
  existing_job_id bigint;
begin
  select job.jobid
  into existing_job_id
  from cron.job as job
  where job.jobname = 'list-and-split-delete-expired-username-reservations';

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;

  perform cron.schedule(
    'list-and-split-delete-expired-username-reservations',
    '17 3 * * *',
    'select private.delete_expired_username_reservations();'
  );
end;
$$;

alter table public.user_notifications
  drop constraint user_notifications_relationship_fkey,
  add constraint user_notifications_relationship_fkey foreign key (
    relationship_low_id,
    relationship_high_id
  ) references public.user_relationships (
    profile_low_id,
    profile_high_id
  ) on delete cascade;

alter table public.user_notifications
  drop constraint user_notifications_recipient_fkey,
  add constraint user_notifications_recipient_fkey foreign key (recipient_id)
    references public.profiles (id) on delete cascade,
  drop constraint user_notifications_actor_fkey,
  add constraint user_notifications_actor_fkey foreign key (actor_id)
    references public.profiles (id) on delete cascade;

alter table public.user_relationships
  drop constraint user_relationships_profile_low_fkey,
  add constraint user_relationships_profile_low_fkey foreign key (
    profile_low_id
  ) references public.profiles (id) on delete cascade,
  drop constraint user_relationships_profile_high_fkey,
  add constraint user_relationships_profile_high_fkey foreign key (
    profile_high_id
  ) references public.profiles (id) on delete cascade;

alter table public.user_blocks
  drop constraint user_blocks_blocker_id_fkey,
  add constraint user_blocks_blocker_id_fkey foreign key (blocker_id)
    references public.profiles (id) on delete cascade,
  drop constraint user_blocks_blocked_id_fkey,
  add constraint user_blocks_blocked_id_fkey foreign key (blocked_id)
    references public.profiles (id) on delete cascade;

alter table public.profiles
  drop constraint profiles_id_fkey,
  add constraint profiles_id_fkey foreign key (id)
    references auth.users (id) on delete cascade;

create function public.validate_account_deletion(
  deletion_confirmation text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  caller_session_id uuid;
  caller_email text;
  caller_username text;
  caller_onboarding_completed_at timestamptz;
  validation_time timestamptz := pg_catalog.statement_timestamp();
begin
  begin
    caller_id := (select auth.uid());
    caller_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception
    when others then
      raise exception using
        errcode = '42501',
        message = 'account authentication required';
  end;

  if caller_id is null or caller_session_id is null then
    raise exception using
      errcode = '42501',
      message = 'account authentication required';
  end if;

  select auth_user.email
  into caller_email
  from auth.users as auth_user
  where auth_user.id = caller_id
    and auth_user.email is not null
    and auth_user.email_confirmed_at is not null;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'account authentication required';
  end if;

  select profile.username, profile.onboarding_completed_at
  into caller_username, caller_onboarding_completed_at
  from public.profiles as profile
  where profile.id = caller_id;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'account authentication required';
  end if;

  if not exists (
    select 1
    from auth.sessions as caller_session
    where caller_session.id = caller_session_id
      and caller_session.user_id = caller_id
      and caller_session.created_at is not null
      and caller_session.created_at >= validation_time - interval '10 minutes'
      and caller_session.created_at <= validation_time
      and (
        caller_session.not_after is null
        or caller_session.not_after > validation_time
      )
  ) then
    raise exception using
      errcode = '55000',
      message = 'recent authentication required';
  end if;

  if deletion_confirmation is distinct from (
    case
      when caller_onboarding_completed_at is not null then caller_username
      else caller_email
    end
  ) then
    raise exception using
      errcode = '22023',
      message = 'account deletion confirmation mismatch';
  end if;

  return true;
end;
$$;

alter function public.validate_account_deletion(text) owner to postgres;

revoke all on function public.validate_account_deletion(text)
from public, anon, authenticated, service_role;

grant execute on function public.validate_account_deletion(text)
to authenticated;

comment on table private.deleted_username_reservations is
  'Private canonical usernames reserved for exactly 30 days after completed-profile deletion.';
comment on function private.assert_username_available(text, uuid) is
  'Serializes live-profile conflicts and rejects active deleted-username reservations.';
comment on function private.reserve_deleted_username() is
  'Reserves only a completed profile canonical username before account-root deletion.';
comment on function private.delete_expired_username_reservations() is
  'Physically removes only expired deleted-username reservations.';
comment on function public.validate_account_deletion(text) is
  'Validates exact account-deletion confirmation against a matching fresh Auth session without mutating data.';

commit;
