-- Friend requests and mutual friendships share one retained, versioned row per
-- normalized profile pair. Clients interact only through the reviewed RPCs.
create table public.user_relationships (
  profile_low_id uuid not null,
  profile_high_id uuid not null,
  state text not null,
  requester_id uuid not null,
  reopen_by_id uuid,
  version bigint not null default 1,
  created_at timestamptz not null default pg_catalog.now(),
  state_changed_at timestamptz not null default pg_catalog.now(),
  constraint user_relationships_pkey primary key (
    profile_low_id,
    profile_high_id
  ),
  constraint user_relationships_profile_low_fkey foreign key (profile_low_id)
    references public.profiles (id) on delete no action,
  constraint user_relationships_profile_high_fkey foreign key (profile_high_id)
    references public.profiles (id) on delete no action,
  constraint user_relationships_ordered_pair_check check (
    profile_low_id < profile_high_id
  ),
  constraint user_relationships_state_check check (
    state in ('pending', 'friends', 'cancelled', 'declined', 'ended')
  ),
  constraint user_relationships_requester_participant_check check (
    requester_id = profile_low_id or requester_id = profile_high_id
  ),
  constraint user_relationships_reopen_participant_check check (
    reopen_by_id is null
    or reopen_by_id = profile_low_id
    or reopen_by_id = profile_high_id
  ),
  constraint user_relationships_reopen_state_check check (
    (
      state in ('declined', 'ended')
      and reopen_by_id is not null
    )
    or (
      state not in ('declined', 'ended')
      and reopen_by_id is null
    )
  ),
  constraint user_relationships_positive_version_check check (version > 0)
);

create index user_relationships_high_participant_idx
on public.user_relationships (profile_high_id, profile_low_id);

alter table public.user_relationships enable row level security;

revoke all on table public.user_relationships
from public, anon, authenticated, service_role;

create policy "user_relationships_reject_direct_client_access"
on public.user_relationships
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

-- Every mutation affecting a relationship/block pair takes this transaction
-- advisory lock before inspecting blocks or relationship state. Hash collisions
-- can only serialize unrelated pairs; they cannot weaken correctness.
create function private.lock_relationship_pair(
  first_profile_id uuid,
  second_profile_id uuid
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  normalized_pair text;
begin
  if first_profile_id is null
    or second_profile_id is null
    or first_profile_id = second_profile_id
  then
    raise exception using
      errcode = '22023',
      message = 'profile unavailable';
  end if;

  normalized_pair := case
    when first_profile_id < second_profile_id
      then first_profile_id::text || ':' || second_profile_id::text
    else second_profile_id::text || ':' || first_profile_id::text
  end;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('list-and-split:relationship:' || normalized_pair, 0)
  );
end;
$$;

revoke all on function private.lock_relationship_pair(uuid, uuid)
from public, anon, authenticated, service_role;

create function private.require_verified_friendship_caller()
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null
    or not exists (
      select 1
      from auth.users as caller_auth
      join public.profiles as caller_profile
        on caller_profile.id = caller_auth.id
      where caller_auth.id = caller_id
        and caller_auth.email_confirmed_at is not null
        and caller_profile.onboarding_completed_at is not null
    )
  then
    raise exception using
      errcode = '42501',
      message = 'verified profile required';
  end if;

  return caller_id;
end;
$$;

revoke all on function private.require_verified_friendship_caller()
from public, anon, authenticated, service_role;

create function public.get_relationship_summary(target_profile_id uuid)
returns table (
  profile_id uuid,
  username text,
  display_name text,
  relationship_status text,
  version bigint,
  state_changed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
  low_profile_id uuid;
  high_profile_id uuid;
begin
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

  low_profile_id := case
    when caller_id < target_profile_id then caller_id
    else target_profile_id
  end;
  high_profile_id := case
    when caller_id < target_profile_id then target_profile_id
    else caller_id
  end;

  return query
  select
    target_profile.id,
    target_profile.username,
    target_profile.display_name,
    case
      when active_block.blocked_pair then 'unavailable'
      when relationship_record.state is null then 'can-send'
      when relationship_record.state = 'pending'
        and relationship_record.requester_id = caller_id
        then 'outgoing-pending'
      when relationship_record.state = 'pending'
        then 'incoming-pending'
      when relationship_record.state = 'friends' then 'friends'
      when relationship_record.state = 'cancelled' then 'can-send'
      when relationship_record.reopen_by_id = caller_id then 'can-send'
      else 'unavailable'
    end,
    case
      when active_block.blocked_pair then null::bigint
      when relationship_record.state is null then null::bigint
      when relationship_record.state in ('declined', 'ended')
        and relationship_record.reopen_by_id <> caller_id
        then null::bigint
      else relationship_record.version
    end,
    null::timestamptz
  from public.profiles as target_profile
  left join public.user_relationships as relationship_record
    on relationship_record.profile_low_id = low_profile_id
    and relationship_record.profile_high_id = high_profile_id
  cross join lateral (
    select exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = target_profile_id
      )
      or (
        pair_block.blocker_id = target_profile_id
        and pair_block.blocked_id = caller_id
      )
    ) as blocked_pair
  ) as active_block
  where target_profile.id = target_profile_id;
end;
$$;

create function public.list_active_relationships()
returns table (
  profile_id uuid,
  username text,
  display_name text,
  relationship_status text,
  version bigint,
  state_changed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
begin
  return query
  select
    target_profile.id,
    target_profile.username,
    target_profile.display_name,
    case
      when relationship_record.state = 'friends' then 'friends'
      when relationship_record.requester_id = caller_id then 'outgoing-pending'
      else 'incoming-pending'
    end,
    relationship_record.version,
    relationship_record.state_changed_at
  from public.user_relationships as relationship_record
  join public.profiles as target_profile
    on target_profile.id = case
      when relationship_record.profile_low_id = caller_id
        then relationship_record.profile_high_id
      else relationship_record.profile_low_id
    end
  where (
    relationship_record.profile_low_id = caller_id
    or relationship_record.profile_high_id = caller_id
  )
    and relationship_record.state in ('pending', 'friends')
    and target_profile.onboarding_completed_at is not null
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = target_profile.id
      )
      or (
        pair_block.blocker_id = target_profile.id
        and pair_block.blocked_id = caller_id
      )
    )
  order by relationship_record.state_changed_at desc, target_profile.username;
end;
$$;

create function public.send_friend_request(
  target_profile_id uuid,
  expected_relationship_version bigint
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
  low_profile_id uuid;
  high_profile_id uuid;
  relationship_record public.user_relationships%rowtype;
begin
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

  low_profile_id := case
    when caller_id < target_profile_id then caller_id
    else target_profile_id
  end;
  high_profile_id := case
    when caller_id < target_profile_id then target_profile_id
    else caller_id
  end;

  perform private.lock_relationship_pair(caller_id, target_profile_id);

  if exists (
    select 1
    from public.user_blocks as active_block
    where (
      active_block.blocker_id = caller_id
      and active_block.blocked_id = target_profile_id
    )
    or (
      active_block.blocker_id = target_profile_id
      and active_block.blocked_id = caller_id
    )
  )
  then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  select relationship_row.*
  into relationship_record
  from public.user_relationships as relationship_row
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id
  for update;

  if not found then
    if expected_relationship_version is not null then
      raise exception using
        errcode = '22023',
        message = 'relationship unavailable';
    end if;

    insert into public.user_relationships (
      profile_low_id,
      profile_high_id,
      state,
      requester_id
    )
    values (
      low_profile_id,
      high_profile_id,
      'pending',
      caller_id
    );
    return;
  end if;

  if relationship_record.state = 'pending' then
    if expected_relationship_version is not null
      and expected_relationship_version <> relationship_record.version
    then
      raise exception using
        errcode = '40001',
        message = 'relationship changed';
    end if;

    if relationship_record.requester_id = caller_id then
      return;
    end if;

    update public.user_relationships as relationship_row
    set state = 'friends',
        requester_id = caller_id,
        reopen_by_id = null,
        version = relationship_row.version + 1,
        state_changed_at = pg_catalog.clock_timestamp()
    where relationship_row.profile_low_id = low_profile_id
      and relationship_row.profile_high_id = high_profile_id;
    return;
  end if;

  if relationship_record.state = 'friends' then
    if expected_relationship_version is not null
      and expected_relationship_version <> relationship_record.version
    then
      raise exception using
        errcode = '40001',
        message = 'relationship changed';
    end if;

    return;
  end if;

  if relationship_record.state <> 'cancelled'
    and relationship_record.reopen_by_id <> caller_id
  then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if expected_relationship_version is null
    or expected_relationship_version <> relationship_record.version
  then
    raise exception using
      errcode = '40001',
      message = 'relationship changed';
  end if;

  update public.user_relationships as relationship_row
  set state = 'pending',
      requester_id = caller_id,
      reopen_by_id = null,
      version = relationship_row.version + 1,
      state_changed_at = pg_catalog.clock_timestamp()
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id;
end;
$$;

create function public.cancel_friend_request(
  target_profile_id uuid,
  expected_relationship_version bigint
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
  low_profile_id uuid;
  high_profile_id uuid;
  relationship_record public.user_relationships%rowtype;
begin
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

  low_profile_id := case
    when caller_id < target_profile_id then caller_id
    else target_profile_id
  end;
  high_profile_id := case
    when caller_id < target_profile_id then target_profile_id
    else caller_id
  end;

  perform private.lock_relationship_pair(caller_id, target_profile_id);

  if exists (
    select 1
    from public.user_blocks as active_block
    where (
      active_block.blocker_id = caller_id
      and active_block.blocked_id = target_profile_id
    )
    or (
      active_block.blocker_id = target_profile_id
      and active_block.blocked_id = caller_id
    )
  )
  then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  select relationship_row.*
  into relationship_record
  from public.user_relationships as relationship_row
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id
  for update;

  if not found then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if relationship_record.state = 'cancelled'
    and relationship_record.requester_id = caller_id
    and expected_relationship_version is not null
    and expected_relationship_version = relationship_record.version - 1
  then
    return;
  end if;

  if relationship_record.state <> 'pending'
    or relationship_record.requester_id <> caller_id
  then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if expected_relationship_version is null then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if expected_relationship_version <> relationship_record.version then
    raise exception using
      errcode = '40001',
      message = 'relationship changed';
  end if;

  update public.user_relationships as relationship_row
  set state = 'cancelled',
      reopen_by_id = null,
      version = relationship_row.version + 1,
      state_changed_at = pg_catalog.clock_timestamp()
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id;
end;
$$;

create function public.accept_friend_request(
  target_profile_id uuid,
  expected_relationship_version bigint
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
  low_profile_id uuid;
  high_profile_id uuid;
  relationship_record public.user_relationships%rowtype;
begin
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

  low_profile_id := case
    when caller_id < target_profile_id then caller_id
    else target_profile_id
  end;
  high_profile_id := case
    when caller_id < target_profile_id then target_profile_id
    else caller_id
  end;

  perform private.lock_relationship_pair(caller_id, target_profile_id);

  if exists (
    select 1
    from public.user_blocks as active_block
    where (
      active_block.blocker_id = caller_id
      and active_block.blocked_id = target_profile_id
    )
    or (
      active_block.blocker_id = target_profile_id
      and active_block.blocked_id = caller_id
    )
  )
  then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  select relationship_row.*
  into relationship_record
  from public.user_relationships as relationship_row
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id
  for update;

  if not found then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if relationship_record.state = 'friends'
    and relationship_record.requester_id <> caller_id
    and expected_relationship_version is not null
    and expected_relationship_version = relationship_record.version - 1
  then
    return;
  end if;

  if relationship_record.state <> 'pending'
    or relationship_record.requester_id = caller_id
  then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if expected_relationship_version is null then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if expected_relationship_version <> relationship_record.version then
    raise exception using
      errcode = '40001',
      message = 'relationship changed';
  end if;

  update public.user_relationships as relationship_row
  set state = 'friends',
      reopen_by_id = null,
      version = relationship_row.version + 1,
      state_changed_at = pg_catalog.clock_timestamp()
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id;
end;
$$;

create function public.decline_friend_request(
  target_profile_id uuid,
  expected_relationship_version bigint
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
  low_profile_id uuid;
  high_profile_id uuid;
  relationship_record public.user_relationships%rowtype;
begin
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

  low_profile_id := case
    when caller_id < target_profile_id then caller_id
    else target_profile_id
  end;
  high_profile_id := case
    when caller_id < target_profile_id then target_profile_id
    else caller_id
  end;

  perform private.lock_relationship_pair(caller_id, target_profile_id);

  if exists (
    select 1
    from public.user_blocks as active_block
    where (
      active_block.blocker_id = caller_id
      and active_block.blocked_id = target_profile_id
    )
    or (
      active_block.blocker_id = target_profile_id
      and active_block.blocked_id = caller_id
    )
  )
  then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  select relationship_row.*
  into relationship_record
  from public.user_relationships as relationship_row
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id
  for update;

  if not found then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if relationship_record.state = 'declined'
    and relationship_record.reopen_by_id = caller_id
    and relationship_record.requester_id <> caller_id
    and expected_relationship_version is not null
    and expected_relationship_version = relationship_record.version - 1
  then
    return;
  end if;

  if relationship_record.state <> 'pending'
    or relationship_record.requester_id = caller_id
  then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if expected_relationship_version is null then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if expected_relationship_version <> relationship_record.version then
    raise exception using
      errcode = '40001',
      message = 'relationship changed';
  end if;

  update public.user_relationships as relationship_row
  set state = 'declined',
      reopen_by_id = caller_id,
      version = relationship_row.version + 1,
      state_changed_at = pg_catalog.clock_timestamp()
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id;
end;
$$;

create function public.end_friendship(
  target_profile_id uuid,
  expected_relationship_version bigint
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
  low_profile_id uuid;
  high_profile_id uuid;
  relationship_record public.user_relationships%rowtype;
begin
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

  low_profile_id := case
    when caller_id < target_profile_id then caller_id
    else target_profile_id
  end;
  high_profile_id := case
    when caller_id < target_profile_id then target_profile_id
    else caller_id
  end;

  perform private.lock_relationship_pair(caller_id, target_profile_id);

  if exists (
    select 1
    from public.user_blocks as active_block
    where (
      active_block.blocker_id = caller_id
      and active_block.blocked_id = target_profile_id
    )
    or (
      active_block.blocker_id = target_profile_id
      and active_block.blocked_id = caller_id
    )
  )
  then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  select relationship_row.*
  into relationship_record
  from public.user_relationships as relationship_row
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id
  for update;

  if not found then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if relationship_record.state = 'ended'
    and relationship_record.reopen_by_id = caller_id
    and expected_relationship_version is not null
    and expected_relationship_version = relationship_record.version - 1
  then
    return;
  end if;

  if relationship_record.state <> 'friends' then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if expected_relationship_version is null then
    raise exception using
      errcode = '22023',
      message = 'relationship unavailable';
  end if;

  if expected_relationship_version <> relationship_record.version then
    raise exception using
      errcode = '40001',
      message = 'relationship changed';
  end if;

  update public.user_relationships as relationship_row
  set state = 'ended',
      reopen_by_id = caller_id,
      version = relationship_row.version + 1,
      state_changed_at = pg_catalog.clock_timestamp()
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id;
end;
$$;

create or replace function public.block_profile(target_profile_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  low_profile_id uuid;
  high_profile_id uuid;
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

  low_profile_id := case
    when caller_id < target_profile_id then caller_id
    else target_profile_id
  end;
  high_profile_id := case
    when caller_id < target_profile_id then target_profile_id
    else caller_id
  end;

  perform private.lock_relationship_pair(caller_id, target_profile_id);

  insert into public.user_blocks (blocker_id, blocked_id)
  values (caller_id, target_profile_id)
  on conflict (blocker_id, blocked_id) do nothing;

  update public.user_relationships as relationship_row
  set state = case
        when relationship_row.state = 'pending' then 'cancelled'
        else 'ended'
      end,
      reopen_by_id = case
        when relationship_row.state = 'friends' then caller_id
        else null
      end,
      version = relationship_row.version + 1,
      state_changed_at = pg_catalog.clock_timestamp()
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id
    and relationship_row.state in ('pending', 'friends');
end;
$$;

create or replace function public.unblock_profile(target_profile_id uuid)
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

  perform private.lock_relationship_pair(caller_id, target_profile_id);

  delete from public.user_blocks as active_block
  where active_block.blocker_id = caller_id
    and active_block.blocked_id = target_profile_id;
end;
$$;

revoke all on function public.get_relationship_summary(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_active_relationships()
from public, anon, authenticated, service_role;
revoke all on function public.send_friend_request(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.cancel_friend_request(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.accept_friend_request(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.decline_friend_request(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.end_friendship(uuid, bigint)
from public, anon, authenticated, service_role;

grant execute on function public.get_relationship_summary(uuid)
to authenticated;
grant execute on function public.list_active_relationships()
to authenticated;
grant execute on function public.send_friend_request(uuid, bigint)
to authenticated;
grant execute on function public.cancel_friend_request(uuid, bigint)
to authenticated;
grant execute on function public.accept_friend_request(uuid, bigint)
to authenticated;
grant execute on function public.decline_friend_request(uuid, bigint)
to authenticated;
grant execute on function public.end_friendship(uuid, bigint)
to authenticated;

comment on table public.user_relationships is
  'RPC-only current friend-request and mutual-friendship state per normalized profile pair.';
comment on function private.lock_relationship_pair(uuid, uuid) is
  'Serializes every relationship and block mutation for one normalized profile pair.';
comment on function private.require_verified_friendship_caller() is
  'Returns the verified, fully onboarded caller identity or rejects the RPC.';
comment on function public.get_relationship_summary(uuid) is
  'Returns one minimal caller-relative relationship summary without dormant-state disclosure.';
comment on function public.list_active_relationships() is
  'Lists only the caller''s active incoming requests, outgoing requests, and friendships.';
comment on function public.send_friend_request(uuid, bigint) is
  'Creates, retries, crosses, or eligibly reopens a versioned friend request.';
comment on function public.cancel_friend_request(uuid, bigint) is
  'Version-checks cancellation of the caller''s outgoing pending request.';
comment on function public.accept_friend_request(uuid, bigint) is
  'Version-checks acceptance of the caller''s incoming pending request.';
comment on function public.decline_friend_request(uuid, bigint) is
  'Version-checks decline of the caller''s incoming pending request.';
comment on function public.end_friendship(uuid, bigint) is
  'Version-checks ending a friendship and records the caller as reopening controller.';
comment on function public.block_profile(uuid) is
  'Idempotently creates the caller''s outgoing block and atomically deactivates an active relationship.';
comment on function public.unblock_profile(uuid) is
  'Idempotently removes only the caller''s outgoing block without restoring relationship state.';
