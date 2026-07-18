begin;

create or replace function public.get_relationship_summary(target_profile_id uuid)
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
  if target_profile_id is null or target_profile_id = caller_id then
    return;
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
  where target_profile.id = target_profile_id
    and target_profile.onboarding_completed_at is not null
    and not exists (
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
    );
end;
$$;

create or replace function public.send_friend_request(
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

  if relationship_record.state = 'friends' then
    return;
  end if;

  if relationship_record.state = 'pending' then
    if expected_relationship_version is not null
      and expected_relationship_version <> relationship_record.version
      and not (
        relationship_record.version > 1
        and expected_relationship_version = relationship_record.version - 1
      )
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

commit;
