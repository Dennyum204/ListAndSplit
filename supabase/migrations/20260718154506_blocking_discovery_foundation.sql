-- Active blocks are directional records. Either direction is considered by the
-- discovery contract, while only the blocker can manage their outgoing row.
create table public.user_blocks (
  blocker_id uuid not null references public.profiles (id),
  blocked_id uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  constraint user_blocks_pkey primary key (blocker_id, blocked_id),
  constraint user_blocks_no_self_block_check check (blocker_id <> blocked_id)
);

create index user_blocks_blocked_id_blocker_id_idx
on public.user_blocks (blocked_id, blocker_id);

alter table public.user_blocks enable row level security;

-- The application uses only the reviewed RPC contracts below. There are no
-- direct Data API table privileges or policies that expose block rows.
revoke all on table public.user_blocks
from public, anon, authenticated, service_role;

create function public.find_profile_by_username(search_username text)
returns table (
  profile_id uuid,
  username text,
  display_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  canonical_username text;
begin
  if caller_id is null then
    raise exception using
      errcode = '42501',
      message = 'authenticated profile required';
  end if;

  if not exists (
    select 1
    from public.profiles as caller_profile
    where caller_profile.id = caller_id
      and caller_profile.onboarding_completed_at is not null
  ) then
    raise exception using
      errcode = '42501',
      message = 'authenticated profile required';
  end if;

  canonical_username := pg_catalog.lower(
    pg_catalog.regexp_replace(
      search_username,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    )
  );

  if canonical_username is null
    or canonical_username !~ '^[a-z][a-z0-9_]{2,23}$'
  then
    raise exception using
      errcode = '22023',
      message = 'invalid username';
  end if;

  return query
  select
    target_profile.id,
    target_profile.username,
    target_profile.display_name
  from public.profiles as target_profile
  where target_profile.username = canonical_username
    and target_profile.onboarding_completed_at is not null
    and target_profile.id <> caller_id
    and not exists (
      select 1
      from public.user_blocks as active_block
      where (
        active_block.blocker_id = caller_id
        and active_block.blocked_id = target_profile.id
      )
      or (
        active_block.blocker_id = target_profile.id
        and active_block.blocked_id = caller_id
      )
    );
end;
$$;

create function public.block_profile(target_profile_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null
    or not exists (
      select 1
      from public.profiles as caller_profile
      where caller_profile.id = caller_id
        and caller_profile.onboarding_completed_at is not null
    )
  then
    raise exception using
      errcode = '42501',
      message = 'authenticated profile required';
  end if;

  if target_profile_id is null
    or target_profile_id = caller_id
    or not exists (
      select 1
      from public.profiles as target_profile
      where target_profile.id = target_profile_id
        and target_profile.onboarding_completed_at is not null
    )
  then
    raise exception using
      errcode = '22023',
      message = 'profile unavailable';
  end if;

  insert into public.user_blocks (blocker_id, blocked_id)
  values (caller_id, target_profile_id)
  on conflict (blocker_id, blocked_id) do nothing;
end;
$$;

create function public.unblock_profile(target_profile_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null
    or not exists (
      select 1
      from public.profiles as caller_profile
      where caller_profile.id = caller_id
        and caller_profile.onboarding_completed_at is not null
    )
  then
    raise exception using
      errcode = '42501',
      message = 'authenticated profile required';
  end if;

  if target_profile_id is null
    or target_profile_id = caller_id
    or not exists (
      select 1
      from public.profiles as target_profile
      where target_profile.id = target_profile_id
        and target_profile.onboarding_completed_at is not null
    )
  then
    raise exception using
      errcode = '22023',
      message = 'profile unavailable';
  end if;

  delete from public.user_blocks as active_block
  where active_block.blocker_id = caller_id
    and active_block.blocked_id = target_profile_id;
end;
$$;

create function public.list_blocked_profiles()
returns table (
  profile_id uuid,
  username text,
  display_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null
    or not exists (
      select 1
      from public.profiles as caller_profile
      where caller_profile.id = caller_id
        and caller_profile.onboarding_completed_at is not null
    )
  then
    raise exception using
      errcode = '42501',
      message = 'authenticated profile required';
  end if;

  return query
  select
    blocked_profile.id,
    blocked_profile.username,
    blocked_profile.display_name
  from public.user_blocks as active_block
  join public.profiles as blocked_profile
    on blocked_profile.id = active_block.blocked_id
  where active_block.blocker_id = caller_id
    and blocked_profile.onboarding_completed_at is not null
  order by blocked_profile.username;
end;
$$;

revoke all on function public.find_profile_by_username(text)
from public, anon, authenticated, service_role;
revoke all on function public.block_profile(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.unblock_profile(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_blocked_profiles()
from public, anon, authenticated, service_role;

grant execute on function public.find_profile_by_username(text)
to authenticated;
grant execute on function public.block_profile(uuid)
to authenticated;
grant execute on function public.unblock_profile(uuid)
to authenticated;
grant execute on function public.list_blocked_profiles()
to authenticated;

comment on table public.user_blocks is
  'Active directional user blocks; application access is RPC-only.';
comment on function public.find_profile_by_username(text) is
  'Returns one block-aware exact username match using the approved minimal projection.';
comment on function public.block_profile(uuid) is
  'Idempotently creates the authenticated caller''s outgoing block.';
comment on function public.unblock_profile(uuid) is
  'Idempotently removes only the authenticated caller''s outgoing block.';
comment on function public.list_blocked_profiles() is
  'Lists only the authenticated caller''s outgoing blocked profiles.';
