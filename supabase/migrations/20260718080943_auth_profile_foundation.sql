create schema if not exists private;

revoke all on schema private from public, anon, authenticated, service_role;

create table public.profiles (
  id uuid primary key references auth.users (id),
  username text unique,
  display_name text,
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format_check check (
    username is null
    or (
      username = pg_catalog.lower(
        pg_catalog.regexp_replace(
          username,
          '^[[:space:]]+|[[:space:]]+$',
          '',
          'g'
        )
      )
      and username ~ '^[a-z][a-z0-9_]{2,23}$'
    )
  ),
  constraint profiles_display_name_format_check check (
    display_name is null
    or (
      display_name = pg_catalog.regexp_replace(
        display_name,
        '^[[:space:]]+|[[:space:]]+$',
        '',
        'g'
      )
      and char_length(display_name) between 1 and 50
    )
  ),
  constraint profiles_onboarding_state_check check (
    (
      onboarding_completed_at is null
      and (username is null or display_name is null)
    )
    or (
      onboarding_completed_at is not null
      and username is not null
      and display_name is not null
    )
  )
);

alter table public.profiles enable row level security;

revoke all on table public.profiles from public, anon, authenticated, service_role;

grant select (
  id,
  username,
  display_name,
  onboarding_completed_at
) on public.profiles to authenticated;

grant update (username, display_name) on public.profiles to authenticated;

create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create function private.prepare_profile_write()
returns trigger
language plpgsql
security invoker
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

  if new.onboarding_completed_at is null
    and new.username is not null
    and new.display_name is not null
  then
    new.onboarding_completed_at := pg_catalog.now();
  end if;

  return new;
end;
$$;

revoke execute on function private.prepare_profile_write()
from public, anon, authenticated, service_role;

create trigger prepare_profile_write
before insert or update on public.profiles
for each row execute function private.prepare_profile_write();

create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke execute on function private.handle_new_auth_user()
from public, anon, authenticated, service_role;

create trigger create_profile_after_auth_user_insert
after insert on auth.users
for each row execute function private.handle_new_auth_user();
