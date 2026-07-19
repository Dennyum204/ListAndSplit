begin;

create table public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null,
  actor_id uuid not null,
  notification_type text not null,
  relationship_low_id uuid not null,
  relationship_high_id uuid not null,
  relationship_version bigint not null,
  created_at timestamptz not null default pg_catalog.now(),
  expires_at timestamptz not null default (
    pg_catalog.now() + interval '180 days'
  ),
  read_at timestamptz,
  suppressed_at timestamptz,
  constraint user_notifications_recipient_fkey foreign key (recipient_id)
    references public.profiles (id) on delete no action,
  constraint user_notifications_actor_fkey foreign key (actor_id)
    references public.profiles (id) on delete no action,
  constraint user_notifications_relationship_fkey foreign key (
    relationship_low_id,
    relationship_high_id
  ) references public.user_relationships (
    profile_low_id,
    profile_high_id
  ) on delete no action,
  constraint user_notifications_type_check check (
    notification_type in ('friend_request')
  ),
  constraint user_notifications_distinct_participants_check check (
    actor_id <> recipient_id
  ),
  constraint user_notifications_ordered_pair_check check (
    relationship_low_id < relationship_high_id
  ),
  constraint user_notifications_pair_participants_check check (
    (
      actor_id = relationship_low_id
      and recipient_id = relationship_high_id
    )
    or (
      actor_id = relationship_high_id
      and recipient_id = relationship_low_id
    )
  ),
  constraint user_notifications_positive_version_check check (
    relationship_version > 0
  ),
  constraint user_notifications_exact_expiry_check check (
    expires_at = created_at + interval '180 days'
  ),
  constraint user_notifications_read_time_check check (
    read_at is null or read_at >= created_at
  ),
  constraint user_notifications_suppression_time_check check (
    suppressed_at is null or suppressed_at >= created_at
  ),
  constraint user_notifications_pair_version_key unique (
    relationship_low_id,
    relationship_high_id,
    recipient_id,
    notification_type,
    relationship_version
  )
);

alter table public.user_notifications owner to postgres;
alter table public.user_notifications enable row level security;

revoke all on table public.user_notifications
from public, anon, authenticated, service_role;

create policy "user_notifications_reject_direct_client_access"
on public.user_notifications
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create index user_notifications_recipient_visible_created_idx
on public.user_notifications (recipient_id, created_at desc, id desc)
where suppressed_at is null;

create index user_notifications_recipient_unread_expiry_idx
on public.user_notifications (recipient_id, expires_at)
where read_at is null and suppressed_at is null;

create function public.list_notifications(
  page_size integer default 20,
  before_created_at timestamptz default null,
  before_notification_id uuid default null
)
returns table (
  notification_id uuid,
  notification_type text,
  created_at timestamptz,
  is_read boolean,
  actor_profile_id uuid,
  actor_username text,
  actor_display_name text,
  action_status text,
  expected_relationship_version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
begin
  if page_size is null or page_size < 1 or page_size > 50 then
    raise exception using
      errcode = '22023',
      message = 'invalid notification page size';
  end if;

  if (before_created_at is null) <> (before_notification_id is null) then
    raise exception using
      errcode = '22023',
      message = 'invalid notification cursor';
  end if;

  return query
  select
    notification_record.id,
    notification_record.notification_type,
    notification_record.created_at,
    notification_record.read_at is not null,
    actor_profile.id,
    actor_profile.username,
    actor_profile.display_name,
    case
      when relationship_record.state = 'pending'
        and relationship_record.version = notification_record.relationship_version
        and relationship_record.requester_id = notification_record.actor_id
        and notification_record.recipient_id = caller_id
        then 'actionable'
      when relationship_record.state = 'friends' then 'friends'
      else 'unavailable'
    end,
    case
      when relationship_record.state = 'pending'
        and relationship_record.version = notification_record.relationship_version
        and relationship_record.requester_id = notification_record.actor_id
        and notification_record.recipient_id = caller_id
        then notification_record.relationship_version
      else null::bigint
    end
  from public.user_notifications as notification_record
  join public.profiles as actor_profile
    on actor_profile.id = notification_record.actor_id
    and actor_profile.onboarding_completed_at is not null
  join public.user_relationships as relationship_record
    on relationship_record.profile_low_id = notification_record.relationship_low_id
    and relationship_record.profile_high_id = notification_record.relationship_high_id
  where notification_record.recipient_id = caller_id
    and notification_record.suppressed_at is null
    and notification_record.expires_at > pg_catalog.now()
    and (
      before_created_at is null
      or (
        notification_record.created_at,
        notification_record.id
      ) < (
        before_created_at,
        before_notification_id
      )
    )
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = notification_record.recipient_id
      )
      or (
        pair_block.blocker_id = notification_record.recipient_id
        and pair_block.blocked_id = notification_record.actor_id
      )
    )
  order by notification_record.created_at desc, notification_record.id desc
  limit page_size;
end;
$$;

create function public.get_unread_notification_count()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
  unread_count bigint;
begin
  select pg_catalog.count(*)
  into unread_count
  from public.user_notifications as notification_record
  where notification_record.recipient_id = caller_id
    and notification_record.read_at is null
    and notification_record.suppressed_at is null
    and notification_record.expires_at > pg_catalog.now()
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = notification_record.recipient_id
      )
      or (
        pair_block.blocker_id = notification_record.recipient_id
        and pair_block.blocked_id = notification_record.actor_id
      )
    );

  return unread_count;
end;
$$;

create function public.mark_notifications_read(notification_ids uuid[])
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
begin
  if notification_ids is null
    or pg_catalog.cardinality(notification_ids) > 50
    or pg_catalog.array_position(notification_ids, null::uuid) is not null
  then
    raise exception using
      errcode = '22023',
      message = 'invalid notification identifiers';
  end if;

  if pg_catalog.cardinality(notification_ids) = 0 then
    return;
  end if;

  update public.user_notifications as notification_record
  set read_at = coalesce(
    notification_record.read_at,
    pg_catalog.clock_timestamp()
  )
  where notification_record.id = any (notification_ids)
    and notification_record.recipient_id = caller_id
    and notification_record.suppressed_at is null
    and notification_record.expires_at > pg_catalog.now()
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = notification_record.recipient_id
      )
      or (
        pair_block.blocker_id = notification_record.recipient_id
        and pair_block.blocked_id = notification_record.actor_id
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
  created_relationship_version bigint;
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
    )
    returning version into created_relationship_version;

    insert into public.user_notifications (
      recipient_id,
      actor_id,
      notification_type,
      relationship_low_id,
      relationship_high_id,
      relationship_version
    )
    values (
      target_profile_id,
      caller_id,
      'friend_request',
      low_profile_id,
      high_profile_id,
      created_relationship_version
    )
    on conflict on constraint user_notifications_pair_version_key do nothing;
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
    and relationship_row.profile_high_id = high_profile_id
  returning relationship_row.version into created_relationship_version;

  insert into public.user_notifications (
    recipient_id,
    actor_id,
    notification_type,
    relationship_low_id,
    relationship_high_id,
    relationship_version
  )
  values (
    target_profile_id,
    caller_id,
    'friend_request',
    low_profile_id,
    high_profile_id,
    created_relationship_version
  )
  on conflict on constraint user_notifications_pair_version_key do nothing;
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

  update public.user_notifications as notification_record
  set suppressed_at = coalesce(
    notification_record.suppressed_at,
    pg_catalog.clock_timestamp()
  )
  where notification_record.relationship_low_id = low_profile_id
    and notification_record.relationship_high_id = high_profile_id
    and notification_record.suppressed_at is null;
end;
$$;

alter function public.list_notifications(integer, timestamptz, uuid)
owner to postgres;
alter function public.get_unread_notification_count()
owner to postgres;
alter function public.mark_notifications_read(uuid[])
owner to postgres;
alter function public.send_friend_request(uuid, bigint)
owner to postgres;
alter function public.block_profile(uuid)
owner to postgres;

revoke all on function public.list_notifications(integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count()
from public, anon, authenticated, service_role;
revoke all on function public.mark_notifications_read(uuid[])
from public, anon, authenticated, service_role;
revoke all on function public.send_friend_request(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.block_profile(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.list_notifications(integer, timestamptz, uuid)
to authenticated;
grant execute on function public.get_unread_notification_count()
to authenticated;
grant execute on function public.mark_notifications_read(uuid[])
to authenticated;
grant execute on function public.send_friend_request(uuid, bigint)
to authenticated;
grant execute on function public.block_profile(uuid)
to authenticated;

comment on table public.user_notifications is
  'RPC-only persistent in-app notifications; initially friend requests only.';
comment on function public.list_notifications(integer, timestamptz, uuid) is
  'Lists one bounded block-aware notification page for the authenticated recipient.';
comment on function public.get_unread_notification_count() is
  'Counts the authenticated recipient''s unread visible unexpired notifications.';
comment on function public.mark_notifications_read(uuid[]) is
  'Idempotently marks a bounded set of the authenticated recipient''s visible notifications read.';
comment on function public.send_friend_request(uuid, bigint) is
  'Creates, retries, crosses, or eligibly reopens a versioned friend request.';
comment on function public.block_profile(uuid) is
  'Idempotently creates the caller''s outgoing block and atomically deactivates an active relationship.';

commit;
