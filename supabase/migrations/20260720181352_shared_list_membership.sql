begin;

create table public.active_list_participants (
  list_id uuid not null,
  participant_profile_id uuid not null,
  state text not null,
  version bigint not null default 1,
  created_at timestamptz not null default pg_catalog.now(),
  state_changed_at timestamptz not null default pg_catalog.now(),
  constraint active_list_participants_pkey primary key (
    list_id,
    participant_profile_id
  ),
  constraint active_list_participants_list_fkey foreign key (list_id)
    references public.active_lists (id) on delete cascade,
  constraint active_list_participants_profile_fkey foreign key (
    participant_profile_id
  ) references public.profiles (id) on delete cascade,
  constraint active_list_participants_state_check check (
    state in ('pending', 'member', 'declined', 'cancelled', 'removed', 'left')
  ),
  constraint active_list_participants_positive_version_check check (
    version > 0
  ),
  constraint active_list_participants_time_check check (
    state_changed_at >= created_at
  )
);

alter table public.active_list_participants owner to postgres;

create index active_list_participants_profile_state_idx
on public.active_list_participants (
  participant_profile_id,
  state,
  state_changed_at desc,
  list_id
);

create index active_list_participants_list_state_idx
on public.active_list_participants (list_id, state, participant_profile_id);

alter table public.active_list_participants enable row level security;
alter table public.active_list_participants force row level security;

revoke all on table public.active_list_participants
from public, anon, authenticated, service_role;

create policy "active_list_participants_reject_direct_client_access"
on public.active_list_participants
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create function private.reject_active_list_owner_participant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.active_lists as list_record
    where list_record.id = new.list_id
      and list_record.owner_id = new.participant_profile_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'list owner cannot be a participant row';
  end if;
  return new;
end;
$$;

alter function private.reject_active_list_owner_participant()
owner to postgres;
revoke all on function private.reject_active_list_owner_participant()
from public, anon, authenticated, service_role;

create trigger active_list_participants_reject_owner
before insert or update of list_id, participant_profile_id
on public.active_list_participants
for each row execute function private.reject_active_list_owner_participant();

create function private.active_list_caller_is_member(
  target_list_id uuid,
  caller_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.active_lists as list_record
    where list_record.id = target_list_id
      and (
        list_record.owner_id = caller_id
        or exists (
          select 1
          from public.active_list_participants as access_record
          where access_record.list_id = list_record.id
            and access_record.participant_profile_id = caller_id
            and access_record.state = 'member'
        )
      )
      and not exists (
        select 1
        from public.user_blocks as pair_block
        where (
          pair_block.blocker_id = caller_id
          and pair_block.blocked_id = list_record.owner_id
        ) or (
          pair_block.blocker_id = list_record.owner_id
          and pair_block.blocked_id = caller_id
        )
      )
  );
$$;

alter function private.active_list_caller_is_member(uuid, uuid)
owner to postgres;
revoke all on function private.active_list_caller_is_member(uuid, uuid)
from public, anon, authenticated, service_role;

create function public.list_active_list_participants(target_list_id uuid)
returns table (
  profile_id uuid,
  username text,
  display_name text,
  is_owner boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
begin
  if target_list_id is null
    or not private.active_list_caller_is_member(target_list_id, caller_id)
  then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  return query
  select
    profile_record.id,
    profile_record.username,
    profile_record.display_name,
    participant.is_owner
  from (
    select list_record.owner_id as profile_id, true as is_owner
    from public.active_lists as list_record
    where list_record.id = target_list_id
    union all
    select access_record.participant_profile_id, false
    from public.active_list_participants as access_record
    where access_record.list_id = target_list_id
      and access_record.state = 'member'
  ) as participant
  join public.profiles as profile_record
    on profile_record.id = participant.profile_id
    and profile_record.onboarding_completed_at is not null
  order by participant.is_owner desc, profile_record.username, profile_record.id;
end;
$$;

create function public.list_pending_active_list_invitations(target_list_id uuid)
returns table (
  profile_id uuid,
  username text,
  display_name text,
  access_version bigint,
  created_at timestamptz,
  state_changed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
begin
  if target_list_id is null or not exists (
    select 1 from public.active_lists as list_record
    where list_record.id = target_list_id and list_record.owner_id = caller_id
  ) then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  return query
  select profile_record.id, profile_record.username, profile_record.display_name,
    access_record.version, access_record.created_at, access_record.state_changed_at
  from public.active_list_participants as access_record
  join public.profiles as profile_record
    on profile_record.id = access_record.participant_profile_id
    and profile_record.onboarding_completed_at is not null
  where access_record.list_id = target_list_id
    and access_record.state = 'pending'
  order by access_record.state_changed_at, profile_record.username, profile_record.id;
end;
$$;

create function public.list_eligible_active_list_invitees(target_list_id uuid)
returns table (
  profile_id uuid,
  username text,
  display_name text,
  current_access_version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
begin
  if target_list_id is null or not exists (
    select 1 from public.active_lists as list_record
    where list_record.id = target_list_id and list_record.owner_id = caller_id
  ) then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  return query
  select profile_record.id, profile_record.username, profile_record.display_name,
    access_record.version
  from public.user_relationships as relationship_record
  join public.profiles as profile_record
    on profile_record.id = case
      when relationship_record.profile_low_id = caller_id
        then relationship_record.profile_high_id
      else relationship_record.profile_low_id
    end
    and profile_record.onboarding_completed_at is not null
  left join public.active_list_participants as access_record
    on access_record.list_id = target_list_id
    and access_record.participant_profile_id = profile_record.id
  where relationship_record.state = 'friends'
    and caller_id in (
      relationship_record.profile_low_id,
      relationship_record.profile_high_id
    )
    and coalesce(access_record.state, 'cancelled') not in ('pending', 'member')
    and not exists (
      select 1 from public.user_blocks as pair_block
      where profile_record.id in (pair_block.blocker_id, pair_block.blocked_id)
        and exists (
          select 1
          from (
            select caller_id as existing_profile_id
            union all
            select member_access.participant_profile_id
            from public.active_list_participants as member_access
            where member_access.list_id = target_list_id
              and member_access.state = 'member'
          ) as existing
          where existing.existing_profile_id in (
            pair_block.blocker_id,
            pair_block.blocked_id
          )
        )
    )
  order by profile_record.username, profile_record.id;
end;
$$;

create function public.get_active_list_invitation(target_list_id uuid)
returns table (
  list_id uuid,
  list_title text,
  list_status text,
  owner_profile_id uuid,
  owner_username text,
  owner_display_name text,
  access_version bigint,
  created_at timestamptz,
  state_changed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
begin
  return query
  select list_record.id, list_record.title, list_record.status,
    owner_profile.id, owner_profile.username, owner_profile.display_name,
    access_record.version, access_record.created_at, access_record.state_changed_at
  from public.active_list_participants as access_record
  join public.active_lists as list_record on list_record.id = access_record.list_id
  join public.profiles as owner_profile on owner_profile.id = list_record.owner_id
  where access_record.list_id = target_list_id
    and access_record.participant_profile_id = caller_id
    and access_record.state = 'pending'
    and not exists (
      select 1 from public.user_blocks as pair_block
      where (pair_block.blocker_id = caller_id and pair_block.blocked_id = list_record.owner_id)
         or (pair_block.blocker_id = list_record.owner_id and pair_block.blocked_id = caller_id)
    );

  if not found then
    raise exception using errcode = 'P0002', message = 'invitation unavailable';
  end if;
end;
$$;

comment on table public.active_list_participants is
  'RPC-only retained versioned non-owner access for active and archived lists.';
comment on function private.reject_active_list_owner_participant() is
  'Prevents an owner identity from being duplicated as a non-owner participant.';
comment on function private.active_list_caller_is_member(uuid, uuid) is
  'Returns whether a verified caller is the owner or a current unblocked accepted member.';
comment on function public.list_active_list_participants(uuid) is
  'Returns the owner and accepted members through the approved minimal profile projection.';
comment on function public.list_pending_active_list_invitations(uuid) is
  'Returns pending invitation recipients only to the owning caller.';
comment on function public.list_eligible_active_list_invitees(uuid) is
  'Returns accepted friends eligible for an owner invitation without exposing blocks.';
comment on function public.get_active_list_invitation(uuid) is
  'Returns one actionable invitation only to its exact pending recipient.';

alter table public.user_notifications
  alter column relationship_low_id drop not null,
  alter column relationship_high_id drop not null,
  alter column relationship_version drop not null,
  add column active_list_id uuid,
  add column access_participant_id uuid,
  add column access_version bigint,
  drop constraint user_notifications_type_check,
  drop constraint user_notifications_ordered_pair_check,
  drop constraint user_notifications_pair_participants_check,
  drop constraint user_notifications_positive_version_check;

alter table public.user_notifications
  add constraint user_notifications_active_list_fkey foreign key (
    active_list_id
  ) references public.active_lists (id) on delete cascade,
  add constraint user_notifications_access_fkey foreign key (
    active_list_id,
    access_participant_id
  ) references public.active_list_participants (
    list_id,
    participant_profile_id
  ) on delete cascade,
  add constraint user_notifications_type_check check (
    notification_type in (
      'friend_request',
      'list_invitation',
      'list_invitation_accepted',
      'list_invitation_declined',
      'list_member_left',
      'list_member_removed'
    )
  ),
  add constraint user_notifications_reference_scope_check check (
    (
      notification_type = 'friend_request'
      and relationship_low_id is not null
      and relationship_high_id is not null
      and relationship_version is not null
      and active_list_id is null
      and access_participant_id is null
      and access_version is null
    ) or (
      notification_type <> 'friend_request'
      and relationship_low_id is null
      and relationship_high_id is null
      and relationship_version is null
      and active_list_id is not null
      and access_participant_id is not null
      and access_version is not null
    )
  ),
  add constraint user_notifications_ordered_pair_check check (
    relationship_low_id is null
    or relationship_low_id < relationship_high_id
  ),
  add constraint user_notifications_pair_participants_check check (
    notification_type <> 'friend_request'
    or (
      actor_id = relationship_low_id
      and recipient_id = relationship_high_id
    )
    or (
      actor_id = relationship_high_id
      and recipient_id = relationship_low_id
    )
  ),
  add constraint user_notifications_positive_version_check check (
    coalesce(relationship_version, access_version) > 0
  ),
  add constraint user_notifications_access_version_key unique (
    active_list_id,
    recipient_id,
    notification_type,
    access_version
  );

create index user_notifications_active_list_idx
on public.user_notifications (active_list_id, access_participant_id)
where active_list_id is not null;

alter table public.user_notifications force row level security;

drop function public.list_notifications(integer, timestamptz, uuid);

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
  expected_relationship_version bigint,
  active_list_id uuid,
  active_list_title text,
  active_list_status text,
  expected_access_version bigint
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
    raise exception using errcode = '22023', message = 'invalid notification page size';
  end if;
  if (before_created_at is null) <> (before_notification_id is null) then
    raise exception using errcode = '22023', message = 'invalid notification cursor';
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
      when notification_record.notification_type = 'friend_request'
        and relationship_record.state = 'pending'
        and relationship_record.version = notification_record.relationship_version
        and relationship_record.requester_id = notification_record.actor_id
        then 'actionable'
      when notification_record.notification_type = 'friend_request'
        and relationship_record.state = 'friends' then 'friends'
      when notification_record.notification_type = 'list_invitation'
        and access_record.state = 'pending'
        and access_record.version = notification_record.access_version
        and list_record.status = 'active' then 'actionable'
      when notification_record.notification_type = 'list_invitation'
        and access_record.state = 'member' then 'accepted'
      else 'unavailable'
    end,
    case
      when notification_record.notification_type = 'friend_request'
        and relationship_record.state = 'pending'
        and relationship_record.version = notification_record.relationship_version
        and relationship_record.requester_id = notification_record.actor_id
        then notification_record.relationship_version
      else null::bigint
    end,
    list_record.id,
    list_record.title,
    list_record.status,
    case
      when notification_record.notification_type = 'list_invitation'
        and access_record.state = 'pending'
        and access_record.version = notification_record.access_version
        and list_record.status = 'active'
        then notification_record.access_version
      else null::bigint
    end
  from public.user_notifications as notification_record
  join public.profiles as actor_profile
    on actor_profile.id = notification_record.actor_id
    and actor_profile.onboarding_completed_at is not null
  left join public.user_relationships as relationship_record
    on relationship_record.profile_low_id = notification_record.relationship_low_id
    and relationship_record.profile_high_id = notification_record.relationship_high_id
  left join public.active_lists as list_record
    on list_record.id = notification_record.active_list_id
  left join public.active_list_participants as access_record
    on access_record.list_id = notification_record.active_list_id
    and access_record.participant_profile_id = notification_record.access_participant_id
  where notification_record.recipient_id = caller_id
    and notification_record.suppressed_at is null
    and (
      notification_record.expires_at > pg_catalog.now()
      or (
        notification_record.notification_type = 'list_invitation'
        and access_record.state = 'pending'
        and access_record.version = notification_record.access_version
      )
    )
    and (
      before_created_at is null
      or (notification_record.created_at, notification_record.id)
        < (before_created_at, before_notification_id)
    )
    and not exists (
      select 1 from public.user_blocks as pair_block
      where (pair_block.blocker_id = notification_record.actor_id and pair_block.blocked_id = caller_id)
         or (pair_block.blocker_id = caller_id and pair_block.blocked_id = notification_record.actor_id)
    )
  order by notification_record.created_at desc, notification_record.id desc
  limit page_size;
end;
$$;

create or replace function public.get_unread_notification_count()
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
  select pg_catalog.count(*) into unread_count
  from public.user_notifications as notification_record
  left join public.active_list_participants as access_record
    on access_record.list_id = notification_record.active_list_id
    and access_record.participant_profile_id = notification_record.access_participant_id
  where notification_record.recipient_id = caller_id
    and notification_record.read_at is null
    and notification_record.suppressed_at is null
    and (
      notification_record.expires_at > pg_catalog.now()
      or (
        notification_record.notification_type = 'list_invitation'
        and access_record.state = 'pending'
        and access_record.version = notification_record.access_version
      )
    )
    and not exists (
      select 1 from public.user_blocks as pair_block
      where (pair_block.blocker_id = notification_record.actor_id and pair_block.blocked_id = caller_id)
         or (pair_block.blocker_id = caller_id and pair_block.blocked_id = notification_record.actor_id)
    );
  return unread_count;
end;
$$;

create or replace function public.mark_notifications_read(notification_ids uuid[])
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
    raise exception using errcode = '22023', message = 'invalid notification identifiers';
  end if;
  if pg_catalog.cardinality(notification_ids) = 0 then return; end if;

  update public.user_notifications as notification_record
  set read_at = coalesce(notification_record.read_at, pg_catalog.clock_timestamp())
  where notification_record.id = any (notification_ids)
    and notification_record.recipient_id = caller_id
    and notification_record.suppressed_at is null
    and (
      notification_record.expires_at > pg_catalog.now()
      or exists (
        select 1 from public.active_list_participants as access_record
        where access_record.list_id = notification_record.active_list_id
          and access_record.participant_profile_id = notification_record.access_participant_id
          and access_record.state = 'pending'
          and access_record.version = notification_record.access_version
      )
    )
    and not exists (
      select 1 from public.user_blocks as pair_block
      where (pair_block.blocker_id = notification_record.actor_id and pair_block.blocked_id = caller_id)
         or (pair_block.blocker_id = caller_id and pair_block.blocked_id = notification_record.actor_id)
    );
end;
$$;

comment on function public.list_notifications(integer, timestamptz, uuid) is
  'Returns bounded caller-owned friend and list-access notifications with exact actionable versions.';
comment on function public.get_unread_notification_count() is
  'Counts caller-owned visible unread notifications, retaining exact pending invitations beyond normal expiry.';
comment on function public.mark_notifications_read(uuid[]) is
  'Idempotently marks a bounded caller-owned visible notification set read.';

create function public.invite_active_list_member(
  target_list_id uuid,
  target_profile_id uuid,
  expected_access_version bigint default null
)
returns table (
  participant_profile_id uuid,
  access_state text,
  access_version bigint,
  created_at timestamptz,
  state_changed_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  access_record public.active_list_participants%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null or target_profile_id is null
    or target_profile_id = caller_id
    or expected_access_version is not null and expected_access_version < 1
  then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;

  select owned_list.* into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id and owned_list.owner_id = caller_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  perform private.lock_relationship_pair(caller_id, target_profile_id);

  select owned_list.* into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id and owned_list.owner_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  if list_record.status = 'archived' then
    raise exception using errcode = '55000', message = 'archived list is read only';
  end if;

  if not exists (
    select 1 from public.user_relationships as relationship_record
    where relationship_record.profile_low_id = least(caller_id, target_profile_id)
      and relationship_record.profile_high_id = greatest(caller_id, target_profile_id)
      and relationship_record.state = 'friends'
  ) or exists (
    select 1 from public.user_blocks as pair_block
    where target_profile_id in (pair_block.blocker_id, pair_block.blocked_id)
      and exists (
        select 1 from (
          select caller_id as profile_id
          union all
          select member_record.participant_profile_id
          from public.active_list_participants as member_record
          where member_record.list_id = target_list_id
            and member_record.state = 'member'
        ) as participant
        where participant.profile_id in (pair_block.blocker_id, pair_block.blocked_id)
      )
  ) then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;

  select current_access.* into access_record
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id
  for update;

  if found and access_record.state = 'pending'
    and (expected_access_version is null or expected_access_version in (
      access_record.version, access_record.version - 1
    ))
  then
    return query select access_record.participant_profile_id, access_record.state,
      access_record.version, access_record.created_at, access_record.state_changed_at;
    return;
  end if;

  if found and access_record.state = 'member' then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;
  if found and expected_access_version is distinct from access_record.version then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;
  if not found and expected_access_version is not null then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  if (
    select pg_catalog.count(*)
    from public.active_list_participants as capacity_record
    where capacity_record.list_id = target_list_id
      and capacity_record.state in ('pending', 'member')
  ) >= 19 then
    raise exception using errcode = '54000', message = 'list participant capacity reached';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  if found then
    update public.active_list_participants as current_access
    set state = 'pending', version = current_access.version + 1,
      state_changed_at = mutation_time
    where current_access.list_id = target_list_id
      and current_access.participant_profile_id = target_profile_id
    returning current_access.* into access_record;
  else
    insert into public.active_list_participants (
      list_id, participant_profile_id, state, created_at, state_changed_at
    ) values (
      target_list_id, target_profile_id, 'pending', mutation_time, mutation_time
    ) returning * into access_record;
  end if;

  insert into public.user_notifications (
    recipient_id, actor_id, notification_type, active_list_id,
    access_participant_id, access_version, created_at, expires_at
  ) values (
    target_profile_id, caller_id, 'list_invitation', target_list_id,
    target_profile_id, access_record.version, mutation_time,
    mutation_time + interval '180 days'
  ) on conflict on constraint user_notifications_access_version_key do nothing;

  return query select access_record.participant_profile_id, access_record.state,
    access_record.version, access_record.created_at, access_record.state_changed_at;
end;
$$;

create function public.cancel_active_list_invitation(
  target_list_id uuid,
  target_profile_id uuid,
  expected_access_version bigint
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  access_record public.active_list_participants%rowtype;
begin
  if target_list_id is null or target_profile_id is null
    or expected_access_version is null or expected_access_version < 1
  then raise exception using errcode = '22023', message = 'invitation unavailable'; end if;

  perform private.lock_relationship_pair(caller_id, target_profile_id);
  perform 1 from public.active_lists as list_record
  where list_record.id = target_list_id and list_record.owner_id = caller_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'list unavailable'; end if;

  select current_access.* into access_record
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'invitation unavailable'; end if;
  if access_record.state = 'cancelled' and expected_access_version = access_record.version - 1 then
    return access_record.version;
  end if;
  if access_record.state <> 'pending' then raise exception using errcode = 'P0002', message = 'invitation unavailable'; end if;
  if access_record.version <> expected_access_version then raise exception using errcode = '40001', message = 'list access changed'; end if;

  update public.active_list_participants as current_access
  set state = 'cancelled', version = current_access.version + 1,
    state_changed_at = pg_catalog.clock_timestamp()
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id
  returning current_access.* into access_record;
  update public.user_notifications as notification_record
  set suppressed_at = coalesce(notification_record.suppressed_at, pg_catalog.clock_timestamp())
  where notification_record.active_list_id = target_list_id
    and notification_record.access_participant_id = target_profile_id
    and notification_record.notification_type = 'list_invitation'
    and notification_record.suppressed_at is null;
  return access_record.version;
end;
$$;

create function public.accept_active_list_invitation(
  target_list_id uuid,
  expected_access_version bigint
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  access_record public.active_list_participants%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null or expected_access_version is null or expected_access_version < 1
  then raise exception using errcode = '22023', message = 'invitation unavailable'; end if;
  select invited_list.* into list_record from public.active_lists as invited_list
  where invited_list.id = target_list_id;
  if not found then raise exception using errcode = 'P0002', message = 'invitation unavailable'; end if;
  perform private.lock_relationship_pair(caller_id, list_record.owner_id);
  select invited_list.* into list_record from public.active_lists as invited_list
  where invited_list.id = target_list_id for update;
  if list_record.status = 'archived' then raise exception using errcode = '55000', message = 'archived list is read only'; end if;

  select current_access.* into access_record
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  for update;
  if not found then raise exception using errcode = 'P0002', message = 'invitation unavailable'; end if;
  if access_record.state = 'member' and expected_access_version = access_record.version - 1 then return access_record.version; end if;
  if access_record.state <> 'pending' then raise exception using errcode = 'P0002', message = 'invitation unavailable'; end if;
  if access_record.version <> expected_access_version then raise exception using errcode = '40001', message = 'list access changed'; end if;

  if not exists (
    select 1 from public.user_relationships as relationship_record
    where relationship_record.profile_low_id = least(caller_id, list_record.owner_id)
      and relationship_record.profile_high_id = greatest(caller_id, list_record.owner_id)
      and relationship_record.state = 'friends'
  ) or exists (
    select 1 from public.user_blocks as pair_block
    where caller_id in (pair_block.blocker_id, pair_block.blocked_id)
      and exists (
        select 1 from (
          select list_record.owner_id as profile_id
          union all
          select member_record.participant_profile_id
          from public.active_list_participants as member_record
          where member_record.list_id = target_list_id and member_record.state = 'member'
        ) as participant
        where participant.profile_id in (pair_block.blocker_id, pair_block.blocked_id)
      )
  ) then raise exception using errcode = '22023', message = 'invitation unavailable'; end if;

  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_participants as current_access
  set state = 'member', version = current_access.version + 1,
    state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  returning current_access.* into access_record;
  insert into public.user_notifications (
    recipient_id, actor_id, notification_type, active_list_id,
    access_participant_id, access_version, created_at, expires_at
  ) values (
    list_record.owner_id, caller_id, 'list_invitation_accepted', target_list_id,
    caller_id, access_record.version, mutation_time, mutation_time + interval '180 days'
  ) on conflict on constraint user_notifications_access_version_key do nothing;
  return access_record.version;
end;
$$;

create function public.decline_active_list_invitation(
  target_list_id uuid,
  expected_access_version bigint
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  access_record public.active_list_participants%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null or expected_access_version is null or expected_access_version < 1
  then raise exception using errcode = '22023', message = 'invitation unavailable'; end if;
  select invited_list.* into list_record from public.active_lists as invited_list
  where invited_list.id = target_list_id;
  if not found then raise exception using errcode = 'P0002', message = 'invitation unavailable'; end if;
  perform private.lock_relationship_pair(caller_id, list_record.owner_id);
  perform 1 from public.active_lists as invited_list where invited_list.id = target_list_id for update;
  select current_access.* into access_record from public.active_list_participants as current_access
  where current_access.list_id = target_list_id and current_access.participant_profile_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'invitation unavailable'; end if;
  if access_record.state = 'declined' and expected_access_version = access_record.version - 1 then return access_record.version; end if;
  if access_record.state <> 'pending' then raise exception using errcode = 'P0002', message = 'invitation unavailable'; end if;
  if access_record.version <> expected_access_version then raise exception using errcode = '40001', message = 'list access changed'; end if;
  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_participants as current_access
  set state = 'declined', version = current_access.version + 1, state_changed_at = mutation_time
  where current_access.list_id = target_list_id and current_access.participant_profile_id = caller_id
  returning current_access.* into access_record;
  insert into public.user_notifications (
    recipient_id, actor_id, notification_type, active_list_id,
    access_participant_id, access_version, created_at, expires_at
  ) values (
    list_record.owner_id, caller_id, 'list_invitation_declined', target_list_id,
    caller_id, access_record.version, mutation_time, mutation_time + interval '180 days'
  ) on conflict on constraint user_notifications_access_version_key do nothing;
  return access_record.version;
end;
$$;

create function public.remove_active_list_member(
  target_list_id uuid,
  target_profile_id uuid,
  expected_access_version bigint
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  access_record public.active_list_participants%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null or target_profile_id is null
    or expected_access_version is null or expected_access_version < 1
  then raise exception using errcode = '22023', message = 'member unavailable'; end if;
  perform private.lock_relationship_pair(caller_id, target_profile_id);
  perform 1 from public.active_lists as list_record
  where list_record.id = target_list_id and list_record.owner_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'list unavailable'; end if;
  select current_access.* into access_record from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'member unavailable'; end if;
  if access_record.state = 'removed' and expected_access_version = access_record.version - 1 then return access_record.version; end if;
  if access_record.state <> 'member' then raise exception using errcode = 'P0002', message = 'member unavailable'; end if;
  if access_record.version <> expected_access_version then raise exception using errcode = '40001', message = 'list access changed'; end if;
  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_participants as current_access
  set state = 'removed', version = current_access.version + 1, state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id
  returning current_access.* into access_record;
  insert into public.user_notifications (
    recipient_id, actor_id, notification_type, active_list_id,
    access_participant_id, access_version, created_at, expires_at
  ) values (
    target_profile_id, caller_id, 'list_member_removed', target_list_id,
    target_profile_id, access_record.version, mutation_time, mutation_time + interval '180 days'
  ) on conflict on constraint user_notifications_access_version_key do nothing;
  return access_record.version;
end;
$$;

create function public.leave_active_list(
  target_list_id uuid,
  expected_access_version bigint
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  access_record public.active_list_participants%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null or expected_access_version is null or expected_access_version < 1
  then raise exception using errcode = '22023', message = 'membership unavailable'; end if;
  select member_list.* into list_record from public.active_lists as member_list
  where member_list.id = target_list_id;
  if not found or list_record.owner_id = caller_id then
    raise exception using errcode = 'P0002', message = 'membership unavailable';
  end if;
  perform private.lock_relationship_pair(caller_id, list_record.owner_id);
  perform 1 from public.active_lists as member_list where member_list.id = target_list_id for update;
  select current_access.* into access_record from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'membership unavailable'; end if;
  if access_record.state = 'left' and expected_access_version = access_record.version - 1 then return access_record.version; end if;
  if access_record.state <> 'member' then raise exception using errcode = 'P0002', message = 'membership unavailable'; end if;
  if access_record.version <> expected_access_version then raise exception using errcode = '40001', message = 'list access changed'; end if;
  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_participants as current_access
  set state = 'left', version = current_access.version + 1, state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  returning current_access.* into access_record;
  insert into public.user_notifications (
    recipient_id, actor_id, notification_type, active_list_id,
    access_participant_id, access_version, created_at, expires_at
  ) values (
    list_record.owner_id, caller_id, 'list_member_left', target_list_id,
    caller_id, access_record.version, mutation_time, mutation_time + interval '180 days'
  ) on conflict on constraint user_notifications_access_version_key do nothing;
  return access_record.version;
end;
$$;

create or replace function public.set_active_list_archived(
  target_list_id uuid,
  should_archive boolean,
  expected_list_version bigint
)
returns table (
  list_id uuid,
  title text,
  status text,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz,
  archived_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  mutation_time timestamptz;
  desired_status text;
begin
  if target_list_id is null or should_archive is null
    or expected_list_version is null or expected_list_version < 1
  then raise exception using errcode = '22023', message = 'invalid list archive transition'; end if;
  desired_status := case when should_archive then 'archived' else 'active' end;
  select owned_list.* into list_record from public.active_lists as owned_list
  where owned_list.id = target_list_id and owned_list.owner_id = caller_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'list unavailable'; end if;
  if list_record.status = desired_status and expected_list_version in (list_record.version, list_record.version - 1) then
    return query select list_record.id, list_record.title, list_record.status,
      list_record.version, list_record.created_at, list_record.updated_at, list_record.archived_at;
    return;
  end if;
  if expected_list_version <> list_record.version then raise exception using errcode = '40001', message = 'list changed'; end if;
  mutation_time := pg_catalog.clock_timestamp();
  if should_archive then
    update public.active_list_participants as access_record
    set state = 'cancelled', version = access_record.version + 1,
      state_changed_at = mutation_time
    where access_record.list_id = target_list_id and access_record.state = 'pending';
    update public.user_notifications as notification_record
    set suppressed_at = coalesce(notification_record.suppressed_at, mutation_time)
    where notification_record.active_list_id = target_list_id
      and notification_record.notification_type = 'list_invitation'
      and notification_record.suppressed_at is null;
  end if;
  update public.active_lists as owned_list
  set status = desired_status,
    archived_at = case when should_archive then mutation_time else null end,
    version = owned_list.version + 1, updated_at = mutation_time
  where owned_list.id = list_record.id returning owned_list.* into list_record;
  return query select list_record.id, list_record.title, list_record.status,
    list_record.version, list_record.created_at, list_record.updated_at, list_record.archived_at;
end;
$$;

comment on function public.invite_active_list_member(uuid, uuid, bigint) is
  'Idempotently invites one eligible accepted friend while serializing capacity and access version.';
comment on function public.cancel_active_list_invitation(uuid, uuid, bigint) is
  'Version-checks owner cancellation of one pending invitation.';
comment on function public.accept_active_list_invitation(uuid, bigint) is
  'Version-checks recipient acceptance after revalidating friendship, blocks, and list state.';
comment on function public.decline_active_list_invitation(uuid, bigint) is
  'Version-checks recipient decline of one pending invitation.';
comment on function public.remove_active_list_member(uuid, uuid, bigint) is
  'Version-checks owner removal of one accepted member, including archived lists.';
comment on function public.leave_active_list(uuid, bigint) is
  'Version-checks a non-owner member leaving an active or archived list.';
comment on function public.set_active_list_archived(uuid, boolean, bigint) is
  'Version-checks owner archive/restore and atomically cancels pending invitations on archive.';

drop function public.list_active_lists(text, integer, timestamptz, uuid);
drop function public.get_active_list(uuid);

create function public.list_active_lists(
  requested_status text,
  page_size integer default 20,
  before_sort_at timestamptz default null,
  before_list_id uuid default null
)
returns table (
  list_id uuid,
  title text,
  status text,
  version bigint,
  item_count bigint,
  completed_item_count bigint,
  created_at timestamptz,
  updated_at timestamptz,
  archived_at timestamptz,
  is_owner boolean,
  owner_profile_id uuid,
  owner_username text,
  owner_display_name text,
  caller_access_version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
begin
  if requested_status is null or requested_status not in ('active', 'archived')
  then raise exception using errcode = '22023', message = 'invalid list status'; end if;
  if page_size is null or page_size < 1 or page_size > 50
  then raise exception using errcode = '22023', message = 'invalid list page size'; end if;
  if (before_sort_at is null) <> (before_list_id is null)
  then raise exception using errcode = '22023', message = 'invalid list cursor'; end if;

  return query
  select list_record.id, list_record.title, list_record.status, list_record.version,
    pg_catalog.count(item_record.id)::bigint,
    pg_catalog.count(item_record.id) filter (where item_record.completed_at is not null)::bigint,
    list_record.created_at, list_record.updated_at, list_record.archived_at,
    list_record.owner_id = caller_id, owner_profile.id, owner_profile.username,
    owner_profile.display_name, access_record.version
  from public.active_lists as list_record
  join public.profiles as owner_profile on owner_profile.id = list_record.owner_id
  left join public.active_list_participants as access_record
    on access_record.list_id = list_record.id
    and access_record.participant_profile_id = caller_id
    and access_record.state = 'member'
  left join public.active_list_items as item_record on item_record.list_id = list_record.id
  where (list_record.owner_id = caller_id or access_record.state = 'member')
    and list_record.status = requested_status
    and not exists (
      select 1 from public.user_blocks as pair_block
      where (pair_block.blocker_id = caller_id and pair_block.blocked_id = list_record.owner_id)
         or (pair_block.blocker_id = list_record.owner_id and pair_block.blocked_id = caller_id)
    )
    and (
      before_sort_at is null
      or (
        case when requested_status = 'active' then list_record.updated_at else list_record.archived_at end,
        list_record.id
      ) < (before_sort_at, before_list_id)
    )
  group by list_record.id, owner_profile.id, access_record.version
  order by case when requested_status = 'active' then list_record.updated_at else list_record.archived_at end desc,
    list_record.id desc
  limit page_size;
end;
$$;

create function public.get_active_list(target_list_id uuid)
returns table (
  list_id uuid,
  title text,
  status text,
  version bigint,
  item_count bigint,
  completed_item_count bigint,
  created_at timestamptz,
  updated_at timestamptz,
  archived_at timestamptz,
  is_owner boolean,
  owner_profile_id uuid,
  owner_username text,
  owner_display_name text,
  caller_access_version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
begin
  if target_list_id is null or not private.active_list_caller_is_member(target_list_id, caller_id)
  then raise exception using errcode = 'P0002', message = 'list unavailable'; end if;
  return query
  select list_record.id, list_record.title, list_record.status, list_record.version,
    pg_catalog.count(item_record.id)::bigint,
    pg_catalog.count(item_record.id) filter (where item_record.completed_at is not null)::bigint,
    list_record.created_at, list_record.updated_at, list_record.archived_at,
    list_record.owner_id = caller_id, owner_profile.id, owner_profile.username,
    owner_profile.display_name, access_record.version
  from public.active_lists as list_record
  join public.profiles as owner_profile on owner_profile.id = list_record.owner_id
  left join public.active_list_participants as access_record
    on access_record.list_id = list_record.id
    and access_record.participant_profile_id = caller_id
    and access_record.state = 'member'
  left join public.active_list_items as item_record on item_record.list_id = list_record.id
  where list_record.id = target_list_id
  group by list_record.id, owner_profile.id, access_record.version;
end;
$$;

create or replace function public.list_active_list_items(target_list_id uuid)
returns table (
  item_id uuid,
  name text,
  quantity_thousandths bigint,
  unit_code text,
  "position" integer,
  version bigint,
  completed_at timestamptz,
  completed_by uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
begin
  if target_list_id is null or not private.active_list_caller_is_member(target_list_id, caller_id)
  then raise exception using errcode = 'P0002', message = 'list unavailable'; end if;
  return query
  select item_record.id, item_record.name, item_record.quantity_thousandths,
    item_record.unit_code, item_record.position, item_record.version,
    item_record.completed_at, item_record.completed_by, item_record.created_at,
    item_record.updated_at
  from public.active_list_items as item_record
  where item_record.list_id = target_list_id
  order by item_record.position, item_record.id;
end;
$$;

comment on function public.list_active_lists(text, integer, timestamptz, uuid) is
  'Returns one bounded owner-or-member list page with minimal owner and access projections.';
comment on function public.get_active_list(uuid) is
  'Returns one allowlisted owner-or-member list detail projection.';
comment on function public.list_active_list_items(uuid) is
  'Returns ordered items to the owner or a current accepted unblocked member.';

create function private.lock_mutable_active_list(
  target_list_id uuid,
  caller_id uuid
)
returns public.active_lists
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  list_record public.active_lists%rowtype;
begin
  select candidate.* into list_record
  from public.active_lists as candidate
  where candidate.id = target_list_id
  for update;
  if not found or not private.active_list_caller_is_member(target_list_id, caller_id)
  then raise exception using errcode = 'P0002', message = 'list unavailable'; end if;
  if list_record.status = 'archived'
  then raise exception using errcode = '55000', message = 'archived list is read only'; end if;
  return list_record;
end;
$$;

alter function private.lock_mutable_active_list(uuid, uuid) owner to postgres;
revoke all on function private.lock_mutable_active_list(uuid, uuid)
from public, anon, authenticated, service_role;
comment on function private.lock_mutable_active_list(uuid, uuid) is
  'Locks one active list and rechecks owner-or-member authorization for an item mutation.';

create or replace function public.create_active_list_item(
  target_list_id uuid,
  new_name text,
  creation_request_id uuid,
  expected_list_version bigint,
  new_quantity_thousandths bigint default 1000,
  new_unit_code text default null
)
returns table (
  item_id uuid, list_version bigint, name text, quantity_thousandths bigint,
  unit_code text, "position" integer, version bigint, completed_at timestamptz,
  completed_by uuid, created_at timestamptz, updated_at timestamptz
)
language plpgsql volatile security definer set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  canonical_name text := pg_catalog.regexp_replace(new_name, '^[[:space:]]+|[[:space:]]+$', '', 'g');
  list_record public.active_lists%rowtype;
  item_record public.active_list_items%rowtype;
  next_position integer;
  mutation_time timestamptz;
begin
  if target_list_id is null or creation_request_id is null
    or expected_list_version is null or expected_list_version < 1
    or canonical_name is null or pg_catalog.char_length(canonical_name) not between 1 and 120
    or new_quantity_thousandths is null or new_quantity_thousandths not between 1 and 999999999
    or new_unit_code is not null and new_unit_code not in ('piece','kg','g','l','ml','pack','box','bottle','can','bag')
  then raise exception using errcode = '22023', message = 'invalid list item creation'; end if;
  list_record := private.lock_mutable_active_list(target_list_id, caller_id);
  select existing.* into item_record from public.active_list_items as existing
  where existing.list_id = target_list_id
    and existing.creation_request_id = create_active_list_item.creation_request_id for update;
  if found then
    if item_record.name <> canonical_name
      or item_record.quantity_thousandths <> new_quantity_thousandths
      or item_record.unit_code is distinct from new_unit_code
    then raise exception using errcode = '23505', message = 'list item creation request conflict',
      constraint = 'active_list_items_list_creation_request_key'; end if;
    if expected_list_version not in (list_record.version, list_record.version - 1)
    then raise exception using errcode = '40001', message = 'list changed'; end if;
    return query select item_record.id, list_record.version, item_record.name,
      item_record.quantity_thousandths, item_record.unit_code, item_record.position,
      item_record.version, item_record.completed_at, item_record.completed_by,
      item_record.created_at, item_record.updated_at;
    return;
  end if;
  if expected_list_version <> list_record.version
  then raise exception using errcode = '40001', message = 'list changed'; end if;
  select coalesce(pg_catalog.max(existing.position), 0) + 1 into next_position
  from public.active_list_items as existing where existing.list_id = target_list_id;
  mutation_time := pg_catalog.clock_timestamp();
  insert into public.active_list_items (
    list_id, name, quantity_thousandths, unit_code, position,
    creation_request_id, created_at, updated_at
  ) values (
    target_list_id, canonical_name, new_quantity_thousandths, new_unit_code,
    next_position, create_active_list_item.creation_request_id, mutation_time, mutation_time
  ) returning * into item_record;
  update public.active_lists as changed_list
  set version = changed_list.version + 1, updated_at = mutation_time
  where changed_list.id = target_list_id returning changed_list.* into list_record;
  return query select item_record.id, list_record.version, item_record.name,
    item_record.quantity_thousandths, item_record.unit_code, item_record.position,
    item_record.version, item_record.completed_at, item_record.completed_by,
    item_record.created_at, item_record.updated_at;
end;
$$;

create or replace function public.update_active_list_item(
  target_list_id uuid, target_item_id uuid, new_name text,
  new_quantity_thousandths bigint, new_unit_code text,
  expected_list_version bigint, expected_item_version bigint
)
returns table (
  item_id uuid, list_version bigint, name text, quantity_thousandths bigint,
  unit_code text, "position" integer, version bigint, completed_at timestamptz,
  completed_by uuid, created_at timestamptz, updated_at timestamptz
)
language plpgsql volatile security definer set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  canonical_name text := pg_catalog.regexp_replace(new_name, '^[[:space:]]+|[[:space:]]+$', '', 'g');
  list_record public.active_lists%rowtype;
  item_record public.active_list_items%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null or target_item_id is null
    or expected_list_version is null or expected_list_version < 1
    or expected_item_version is null or expected_item_version < 1
    or canonical_name is null or pg_catalog.char_length(canonical_name) not between 1 and 120
    or new_quantity_thousandths is null or new_quantity_thousandths not between 1 and 999999999
    or new_unit_code is not null and new_unit_code not in ('piece','kg','g','l','ml','pack','box','bottle','can','bag')
  then raise exception using errcode = '22023', message = 'invalid list item update'; end if;
  list_record := private.lock_mutable_active_list(target_list_id, caller_id);
  select existing.* into item_record from public.active_list_items as existing
  where existing.id = target_item_id and existing.list_id = target_list_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'list item unavailable'; end if;
  if item_record.name = canonical_name
    and item_record.quantity_thousandths = new_quantity_thousandths
    and item_record.unit_code is not distinct from new_unit_code
    and ((expected_list_version = list_record.version and expected_item_version = item_record.version)
      or (expected_list_version = list_record.version - 1 and expected_item_version = item_record.version - 1))
  then
    return query select item_record.id, list_record.version, item_record.name,
      item_record.quantity_thousandths, item_record.unit_code, item_record.position,
      item_record.version, item_record.completed_at, item_record.completed_by,
      item_record.created_at, item_record.updated_at;
    return;
  end if;
  if expected_list_version <> list_record.version or expected_item_version <> item_record.version
  then raise exception using errcode = '40001', message = 'list item changed'; end if;
  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_items as changed_item
  set name = canonical_name, quantity_thousandths = new_quantity_thousandths,
    unit_code = new_unit_code, version = changed_item.version + 1, updated_at = mutation_time
  where changed_item.id = target_item_id returning changed_item.* into item_record;
  update public.active_lists as changed_list
  set version = changed_list.version + 1, updated_at = mutation_time
  where changed_list.id = target_list_id returning changed_list.* into list_record;
  return query select item_record.id, list_record.version, item_record.name,
    item_record.quantity_thousandths, item_record.unit_code, item_record.position,
    item_record.version, item_record.completed_at, item_record.completed_by,
    item_record.created_at, item_record.updated_at;
end;
$$;

create or replace function public.set_active_list_item_completed(
  target_list_id uuid, target_item_id uuid, should_complete boolean,
  expected_list_version bigint, expected_item_version bigint
)
returns table (
  item_id uuid, list_version bigint, name text, quantity_thousandths bigint,
  unit_code text, "position" integer, version bigint, completed_at timestamptz,
  completed_by uuid, created_at timestamptz, updated_at timestamptz
)
language plpgsql volatile security definer set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  item_record public.active_list_items%rowtype;
  mutation_time timestamptz;
  already_desired boolean;
begin
  if target_list_id is null or target_item_id is null or should_complete is null
    or expected_list_version is null or expected_list_version < 1
    or expected_item_version is null or expected_item_version < 1
  then raise exception using errcode = '22023', message = 'invalid list item completion'; end if;
  list_record := private.lock_mutable_active_list(target_list_id, caller_id);
  select existing.* into item_record from public.active_list_items as existing
  where existing.id = target_item_id and existing.list_id = target_list_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'list item unavailable'; end if;
  already_desired := should_complete = (item_record.completed_at is not null);
  if already_desired and ((expected_list_version = list_record.version and expected_item_version = item_record.version)
    or (expected_list_version = list_record.version - 1 and expected_item_version = item_record.version - 1))
  then
    return query select item_record.id, list_record.version, item_record.name,
      item_record.quantity_thousandths, item_record.unit_code, item_record.position,
      item_record.version, item_record.completed_at, item_record.completed_by,
      item_record.created_at, item_record.updated_at;
    return;
  end if;
  if expected_list_version <> list_record.version or expected_item_version <> item_record.version
  then raise exception using errcode = '40001', message = 'list item changed'; end if;
  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_items as changed_item
  set completed_at = case when should_complete then mutation_time else null end,
    completed_by = case when should_complete then caller_id else null end,
    version = changed_item.version + 1, updated_at = mutation_time
  where changed_item.id = target_item_id returning changed_item.* into item_record;
  update public.active_lists as changed_list
  set version = changed_list.version + 1, updated_at = mutation_time
  where changed_list.id = target_list_id returning changed_list.* into list_record;
  return query select item_record.id, list_record.version, item_record.name,
    item_record.quantity_thousandths, item_record.unit_code, item_record.position,
    item_record.version, item_record.completed_at, item_record.completed_by,
    item_record.created_at, item_record.updated_at;
end;
$$;

create or replace function public.delete_active_list_item(
  target_list_id uuid, target_item_id uuid,
  expected_list_version bigint, expected_item_version bigint
)
returns bigint
language plpgsql volatile security definer set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  item_record public.active_list_items%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null or target_item_id is null
    or expected_list_version is null or expected_list_version < 1
    or expected_item_version is null or expected_item_version < 1
  then raise exception using errcode = '22023', message = 'invalid list item deletion'; end if;
  list_record := private.lock_mutable_active_list(target_list_id, caller_id);
  select existing.* into item_record from public.active_list_items as existing
  where existing.id = target_item_id and existing.list_id = target_list_id for update;
  if not found then raise exception using errcode = 'P0002', message = 'list item unavailable'; end if;
  if expected_list_version <> list_record.version or expected_item_version <> item_record.version
  then raise exception using errcode = '40001', message = 'list item changed'; end if;
  mutation_time := pg_catalog.clock_timestamp();
  delete from public.active_list_items as deleted_item where deleted_item.id = target_item_id;
  update public.active_lists as changed_list
  set version = changed_list.version + 1, updated_at = mutation_time
  where changed_list.id = target_list_id returning changed_list.* into list_record;
  return list_record.version;
end;
$$;

create or replace function public.reorder_active_list_items(
  target_list_id uuid, ordered_item_ids uuid[], expected_list_version bigint
)
returns bigint
language plpgsql volatile security definer set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  current_item_ids uuid[];
  item_count integer;
  mutation_time timestamptz;
begin
  if target_list_id is null or ordered_item_ids is null
    or expected_list_version is null or expected_list_version < 1
    or pg_catalog.array_position(ordered_item_ids, null::uuid) is not null
  then raise exception using errcode = '22023', message = 'invalid list item order'; end if;
  if pg_catalog.cardinality(ordered_item_ids) <> (
    select pg_catalog.count(distinct submitted_id)
    from pg_catalog.unnest(ordered_item_ids) as submitted(submitted_id)
  ) then raise exception using errcode = '22023', message = 'invalid list item order'; end if;
  list_record := private.lock_mutable_active_list(target_list_id, caller_id);
  perform 1 from public.active_list_items as lock_item
  where lock_item.list_id = target_list_id order by lock_item.id for update;
  select coalesce(pg_catalog.array_agg(item_record.id order by item_record.position), '{}'::uuid[]),
    pg_catalog.count(*)::integer into current_item_ids, item_count
  from public.active_list_items as item_record where item_record.list_id = target_list_id;
  if pg_catalog.cardinality(ordered_item_ids) <> item_count
    or exists (
      select 1 from pg_catalog.unnest(ordered_item_ids) as submitted(item_id)
      where not exists (
        select 1 from public.active_list_items as current_item
        where current_item.list_id = target_list_id and current_item.id = submitted.item_id
      )
    )
  then raise exception using errcode = '22023', message = 'invalid list item order'; end if;
  if current_item_ids = ordered_item_ids
    and expected_list_version in (list_record.version, list_record.version - 1)
  then return list_record.version; end if;
  if expected_list_version <> list_record.version
  then raise exception using errcode = '40001', message = 'list changed'; end if;
  if item_count = 0 then return list_record.version; end if;
  update public.active_list_items as item_record
  set position = item_record.position + item_count
  where item_record.list_id = target_list_id;
  update public.active_list_items as item_record
  set position = submitted.ordinality::integer
  from pg_catalog.unnest(ordered_item_ids) with ordinality as submitted(item_id, ordinality)
  where item_record.list_id = target_list_id and item_record.id = submitted.item_id;
  mutation_time := pg_catalog.clock_timestamp();
  update public.active_lists as changed_list
  set version = changed_list.version + 1, updated_at = mutation_time
  where changed_list.id = target_list_id returning changed_list.* into list_record;
  return list_record.version;
end;
$$;

comment on function public.create_active_list_item(uuid, text, uuid, bigint, bigint, text) is
  'Retry-safely appends one item for the active-list owner or a current accepted member.';
comment on function public.update_active_list_item(uuid, uuid, text, bigint, text, bigint, bigint) is
  'Version-checks owner-or-member list item content changes.';
comment on function public.set_active_list_item_completed(uuid, uuid, boolean, bigint, bigint) is
  'Version-checks owner-or-member completion or reopening with caller attribution.';
comment on function public.delete_active_list_item(uuid, uuid, bigint, bigint) is
  'Version-checks permanent item deletion by the owner or a current accepted member.';
comment on function public.reorder_active_list_items(uuid, uuid[], bigint) is
  'Atomically version-checks exact item order by the owner or a current accepted member.';

create or replace function public.end_friendship(
  target_profile_id uuid,
  expected_relationship_version bigint
)
returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_friendship_caller();
  low_profile_id uuid;
  high_profile_id uuid;
  relationship_record public.user_relationships%rowtype;
  mutation_time timestamptz;
begin
  if target_profile_id is null or target_profile_id = caller_id or not exists (
    select 1 from public.profiles as target_profile
    where target_profile.id = target_profile_id
      and target_profile.onboarding_completed_at is not null
  ) then raise exception using errcode = '22023', message = 'profile unavailable'; end if;
  low_profile_id := least(caller_id, target_profile_id);
  high_profile_id := greatest(caller_id, target_profile_id);
  perform private.lock_relationship_pair(caller_id, target_profile_id);
  if exists (
    select 1 from public.user_blocks as active_block
    where (active_block.blocker_id = caller_id and active_block.blocked_id = target_profile_id)
       or (active_block.blocker_id = target_profile_id and active_block.blocked_id = caller_id)
  ) then raise exception using errcode = '22023', message = 'relationship unavailable'; end if;
  select current_relationship.* into relationship_record
  from public.user_relationships as current_relationship
  where current_relationship.profile_low_id = low_profile_id
    and current_relationship.profile_high_id = high_profile_id for update;
  if not found then raise exception using errcode = '22023', message = 'relationship unavailable'; end if;
  if relationship_record.state = 'ended' and relationship_record.reopen_by_id = caller_id
    and expected_relationship_version = relationship_record.version - 1 then return; end if;
  if relationship_record.state <> 'friends' or expected_relationship_version is null
  then raise exception using errcode = '22023', message = 'relationship unavailable'; end if;
  if expected_relationship_version <> relationship_record.version
  then raise exception using errcode = '40001', message = 'relationship changed'; end if;

  perform 1
  from public.active_lists as list_record
  join public.active_list_participants as access_record
    on access_record.list_id = list_record.id and access_record.state = 'pending'
  where (list_record.owner_id = caller_id and access_record.participant_profile_id = target_profile_id)
     or (list_record.owner_id = target_profile_id and access_record.participant_profile_id = caller_id)
  order by list_record.id for update of list_record;

  mutation_time := pg_catalog.clock_timestamp();
  update public.user_relationships as current_relationship
  set state = 'ended', reopen_by_id = caller_id,
    version = current_relationship.version + 1, state_changed_at = mutation_time
  where current_relationship.profile_low_id = low_profile_id
    and current_relationship.profile_high_id = high_profile_id;

  update public.active_list_participants as access_record
  set state = 'cancelled', version = access_record.version + 1,
    state_changed_at = mutation_time
  from public.active_lists as list_record
  where list_record.id = access_record.list_id and access_record.state = 'pending'
    and ((list_record.owner_id = caller_id and access_record.participant_profile_id = target_profile_id)
      or (list_record.owner_id = target_profile_id and access_record.participant_profile_id = caller_id));
  update public.user_notifications as notification_record
  set suppressed_at = coalesce(notification_record.suppressed_at, mutation_time)
  from public.active_lists as list_record
  where list_record.id = notification_record.active_list_id
    and notification_record.notification_type = 'list_invitation'
    and notification_record.suppressed_at is null
    and ((list_record.owner_id = caller_id and notification_record.access_participant_id = target_profile_id)
      or (list_record.owner_id = target_profile_id and notification_record.access_participant_id = caller_id));
end;
$$;

create or replace function public.block_profile(target_profile_id uuid)
returns void
language plpgsql volatile security definer set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  low_profile_id uuid;
  high_profile_id uuid;
  affected record;
  new_state text;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
  new_version bigint;
begin
  if caller_id is null or not exists (
    select 1 from public.profiles as caller_profile
    where caller_profile.id = caller_id and caller_profile.onboarding_completed_at is not null
  ) then raise exception using errcode = '42501', message = 'authenticated profile required'; end if;
  if target_profile_id is null or target_profile_id = caller_id or not exists (
    select 1 from public.profiles as target_profile
    where target_profile.id = target_profile_id and target_profile.onboarding_completed_at is not null
  ) then raise exception using errcode = '22023', message = 'profile unavailable'; end if;
  low_profile_id := least(caller_id, target_profile_id);
  high_profile_id := greatest(caller_id, target_profile_id);
  perform private.lock_relationship_pair(caller_id, target_profile_id);

  insert into public.user_blocks (blocker_id, blocked_id)
  values (caller_id, target_profile_id)
  on conflict (blocker_id, blocked_id) do nothing;
  update public.user_relationships as relationship_row
  set state = case when relationship_row.state = 'pending' then 'cancelled' else 'ended' end,
    reopen_by_id = case when relationship_row.state = 'friends' then caller_id else null end,
    version = relationship_row.version + 1, state_changed_at = mutation_time
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id
    and relationship_row.state in ('pending', 'friends');
  update public.user_notifications as notification_record
  set suppressed_at = coalesce(notification_record.suppressed_at, mutation_time)
  where notification_record.relationship_low_id = low_profile_id
    and notification_record.relationship_high_id = high_profile_id
    and notification_record.suppressed_at is null;

  perform 1 from public.active_lists as list_record
  where exists (
    select 1 from public.active_list_participants as access_record
    where access_record.list_id = list_record.id
      and (
        (list_record.owner_id = caller_id and access_record.participant_profile_id = target_profile_id
          and access_record.state in ('pending', 'member'))
        or (list_record.owner_id = target_profile_id and access_record.participant_profile_id = caller_id
          and access_record.state in ('pending', 'member'))
        or (list_record.owner_id not in (caller_id, target_profile_id)
          and access_record.participant_profile_id = caller_id and access_record.state = 'member'
          and exists (
            select 1 from public.active_list_participants as other_access
            where other_access.list_id = list_record.id
              and other_access.participant_profile_id = target_profile_id
              and other_access.state = 'member'
          ))
      )
  ) order by list_record.id for update;

  for affected in
    select list_record.id as list_id, list_record.owner_id,
      access_record.participant_profile_id, access_record.state, access_record.version
    from public.active_lists as list_record
    join public.active_list_participants as access_record on access_record.list_id = list_record.id
    where (list_record.owner_id = caller_id
        and access_record.participant_profile_id = target_profile_id
        and access_record.state in ('pending', 'member'))
      or (list_record.owner_id = target_profile_id
        and access_record.participant_profile_id = caller_id
        and access_record.state in ('pending', 'member'))
      or (list_record.owner_id not in (caller_id, target_profile_id)
        and access_record.participant_profile_id = caller_id
        and access_record.state = 'member'
        and exists (
          select 1 from public.active_list_participants as other_access
          where other_access.list_id = list_record.id
            and other_access.participant_profile_id = target_profile_id
            and other_access.state = 'member'
        ))
    order by list_record.id
  loop
    new_state := case
      when affected.state = 'pending' then 'cancelled'
      when affected.owner_id = caller_id then 'removed'
      else 'left'
    end;
    update public.active_list_participants as access_record
    set state = new_state, version = access_record.version + 1,
      state_changed_at = mutation_time
    where access_record.list_id = affected.list_id
      and access_record.participant_profile_id = affected.participant_profile_id
    returning access_record.version into new_version;
    update public.user_notifications as notification_record
    set suppressed_at = coalesce(notification_record.suppressed_at, mutation_time)
    where notification_record.active_list_id = affected.list_id
      and notification_record.access_participant_id = affected.participant_profile_id
      and notification_record.notification_type = 'list_invitation'
      and notification_record.suppressed_at is null;
    if affected.owner_id not in (caller_id, target_profile_id)
      and affected.state = 'member'
    then
      insert into public.user_notifications (
        recipient_id, actor_id, notification_type, active_list_id,
        access_participant_id, access_version, created_at, expires_at
      ) values (
        affected.owner_id, caller_id, 'list_member_left', affected.list_id,
        caller_id, new_version, mutation_time, mutation_time + interval '180 days'
      ) on conflict on constraint user_notifications_access_version_key do nothing;
    end if;
  end loop;
end;
$$;

comment on function public.end_friendship(uuid, bigint) is
  'Version-checks friendship end and atomically cancels pending invitations between the pair.';
comment on function public.block_profile(uuid) is
  'Creates one directional block and atomically applies privacy-safe relationship, notification, and shared-list separation.';

alter function public.export_own_account_data()
rename to export_own_account_data_v2_base;
alter function public.export_own_account_data_v2_base()
set schema private;
revoke all on function private.export_own_account_data_v2_base()
from public, anon, authenticated, service_role;

create function public.export_own_account_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  base_export jsonb;
  shared_list_access jsonb := '[]'::jsonb;
begin
  base_export := private.export_own_account_data_v2_base();
  caller_id := (select auth.uid());
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'list_id', list_record.id,
        'list_title', list_record.title,
        'list_status', list_record.status,
        'access_state', access_record.state,
        'access_version', access_record.version,
        'created_at', access_record.created_at,
        'state_changed_at', access_record.state_changed_at
      ) order by access_record.state_changed_at desc, list_record.id
    ),
    '[]'::jsonb
  ) into shared_list_access
  from public.active_list_participants as access_record
  join public.active_lists as list_record on list_record.id = access_record.list_id
  where access_record.participant_profile_id = caller_id;

  return base_export || pg_catalog.jsonb_build_object(
    'schema_version', 3,
    'shared_list_access', shared_list_access
  );
end;
$$;

create function public.get_account_deletion_list_impact()
returns table (
  owned_shared_list_count bigint,
  affected_participant_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null or not exists (
    select 1 from auth.users as caller_auth
    join public.profiles as caller_profile on caller_profile.id = caller_auth.id
    where caller_auth.id = caller_id and caller_auth.email_confirmed_at is not null
  ) then raise exception using errcode = '42501', message = 'verified account required'; end if;

  return query
  select
    pg_catalog.count(distinct list_record.id) filter (
      where access_record.participant_profile_id is not null
    )::bigint,
    pg_catalog.count(access_record.participant_profile_id)::bigint
  from public.active_lists as list_record
  left join public.active_list_participants as access_record
    on access_record.list_id = list_record.id and access_record.state = 'member'
  where list_record.owner_id = caller_id;
end;
$$;

comment on function private.export_own_account_data_v2_base() is
  'Internal frozen schema-version-2 allowlist used only to compose version 3.';
comment on function public.export_own_account_data() is
  'Returns schema-version-3 own data with privacy-minimal caller-relative shared-list access.';
comment on function public.get_account_deletion_list_impact() is
  'Returns only owned shared-list and accepted-participant counts for deletion confirmation.';

alter function public.list_active_list_participants(uuid) owner to postgres;
alter function public.list_pending_active_list_invitations(uuid) owner to postgres;
alter function public.list_eligible_active_list_invitees(uuid) owner to postgres;
alter function public.get_active_list_invitation(uuid) owner to postgres;
alter function public.invite_active_list_member(uuid, uuid, bigint) owner to postgres;
alter function public.cancel_active_list_invitation(uuid, uuid, bigint) owner to postgres;
alter function public.accept_active_list_invitation(uuid, bigint) owner to postgres;
alter function public.decline_active_list_invitation(uuid, bigint) owner to postgres;
alter function public.remove_active_list_member(uuid, uuid, bigint) owner to postgres;
alter function public.leave_active_list(uuid, bigint) owner to postgres;
alter function public.list_active_lists(text, integer, timestamptz, uuid) owner to postgres;
alter function public.get_active_list(uuid) owner to postgres;
alter function public.list_notifications(integer, timestamptz, uuid) owner to postgres;
alter function public.get_account_deletion_list_impact() owner to postgres;
alter function public.export_own_account_data() owner to postgres;
alter function public.get_unread_notification_count() owner to postgres;
alter function public.mark_notifications_read(uuid[]) owner to postgres;
alter function public.end_friendship(uuid, bigint) owner to postgres;
alter function public.block_profile(uuid) owner to postgres;
alter function public.set_active_list_archived(uuid, boolean, bigint) owner to postgres;
alter function public.list_active_list_items(uuid) owner to postgres;
alter function public.create_active_list_item(uuid, text, uuid, bigint, bigint, text) owner to postgres;
alter function public.update_active_list_item(uuid, uuid, text, bigint, text, bigint, bigint) owner to postgres;
alter function public.set_active_list_item_completed(uuid, uuid, boolean, bigint, bigint) owner to postgres;
alter function public.delete_active_list_item(uuid, uuid, bigint, bigint) owner to postgres;
alter function public.reorder_active_list_items(uuid, uuid[], bigint) owner to postgres;

revoke all on function public.list_active_list_participants(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_pending_active_list_invitations(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_eligible_active_list_invitees(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_active_list_invitation(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.invite_active_list_member(uuid, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.cancel_active_list_invitation(uuid, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.accept_active_list_invitation(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.decline_active_list_invitation(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.remove_active_list_member(uuid, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.leave_active_list(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.list_active_lists(text, integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_active_list(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_notifications(integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_account_deletion_list_impact()
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data()
from public, anon, authenticated, service_role;

grant execute on function public.list_active_list_participants(uuid) to authenticated;
grant execute on function public.list_pending_active_list_invitations(uuid) to authenticated;
grant execute on function public.list_eligible_active_list_invitees(uuid) to authenticated;
grant execute on function public.get_active_list_invitation(uuid) to authenticated;
grant execute on function public.invite_active_list_member(uuid, uuid, bigint) to authenticated;
grant execute on function public.cancel_active_list_invitation(uuid, uuid, bigint) to authenticated;
grant execute on function public.accept_active_list_invitation(uuid, bigint) to authenticated;
grant execute on function public.decline_active_list_invitation(uuid, bigint) to authenticated;
grant execute on function public.remove_active_list_member(uuid, uuid, bigint) to authenticated;
grant execute on function public.leave_active_list(uuid, bigint) to authenticated;
grant execute on function public.list_active_lists(text, integer, timestamptz, uuid) to authenticated;
grant execute on function public.get_active_list(uuid) to authenticated;
grant execute on function public.list_notifications(integer, timestamptz, uuid) to authenticated;
grant execute on function public.get_account_deletion_list_impact() to authenticated;
grant execute on function public.export_own_account_data() to authenticated;

commit;
