create policy "authenticated_receive_own_account_broadcasts"
on realtime.messages
for select
to authenticated
using (
  extension = 'broadcast'
  and (select realtime.topic()) = 'account:' || (select auth.uid())::text
);

create function private.send_account_invalidations(recipient_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient_id uuid;
begin
  for recipient_id in
    select distinct candidate.recipient_id
    from pg_catalog.unnest(recipient_ids) as candidate(recipient_id)
    where candidate.recipient_id is not null
    order by candidate.recipient_id
  loop
    perform realtime.send(
      pg_catalog.jsonb_build_object('v', 1),
      'invalidate',
      'account:' || recipient_id::text,
      true
    );
  end loop;
end;
$$;

comment on function private.send_account_invalidations(uuid[]) is
  'Emits the fixed private account invalidation contract to distinct affected profiles inside the caller transaction.';

create function private.broadcast_active_list_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_list_id uuid := case when tg_op = 'DELETE' then old.id else new.id end;
  target_owner_id uuid := case when tg_op = 'DELETE' then old.owner_id else new.owner_id end;
  recipient_ids uuid[];
begin
  recipient_ids := array(
    select target_owner_id
    union
    select access_record.participant_profile_id
    from public.active_list_participants as access_record
    where access_record.list_id = target_list_id
      and access_record.state in ('pending', 'member')
  );
  perform private.send_account_invalidations(recipient_ids);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function private.broadcast_active_list_invalidation() is
  'Invalidates the owner plus current member and pending projections for a changed list; BEFORE DELETE preserves cascade recipients.';

create function private.broadcast_active_list_participant_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_list_id uuid := case when tg_op = 'DELETE' then old.list_id else new.list_id end;
  target_profile_id uuid := case
    when tg_op = 'DELETE' then old.participant_profile_id
    else new.participant_profile_id
  end;
  affects_member_projection boolean :=
    (tg_op <> 'INSERT' and old.state = 'member')
    or (tg_op <> 'DELETE' and new.state = 'member');
  recipient_ids uuid[];
begin
  recipient_ids := array(
    select list_record.owner_id
    from public.active_lists as list_record
    where list_record.id = target_list_id
    union
    select target_profile_id
    union
    select access_record.participant_profile_id
    from public.active_list_participants as access_record
    where affects_member_projection
      and access_record.list_id = target_list_id
      and access_record.state = 'member'
  );
  perform private.send_account_invalidations(recipient_ids);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function private.broadcast_active_list_participant_invalidation() is
  'Invalidates the owner and affected participant, plus accepted peers only when the visible member projection changes.';

create function private.broadcast_notification_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.send_account_invalidations(
    array[
      case when tg_op <> 'INSERT' then old.recipient_id end,
      case when tg_op <> 'DELETE' then new.recipient_id end
    ]
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function private.broadcast_notification_invalidation() is
  'Invalidates only old and new persistent-notification recipients without exposing notification content.';

create function private.broadcast_relationship_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.send_account_invalidations(
    array[
      case when tg_op = 'DELETE' then old.profile_low_id else new.profile_low_id end,
      case when tg_op = 'DELETE' then old.profile_high_id else new.profile_high_id end
    ]
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function private.broadcast_relationship_invalidation() is
  'Invalidates both caller-relative relationship projections without disclosing relationship state.';

create function private.broadcast_block_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.send_account_invalidations(
    array[
      case when tg_op = 'DELETE' then old.blocker_id else new.blocker_id end,
      case when tg_op = 'DELETE' then old.blocked_id else new.blocked_id end
    ]
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function private.broadcast_block_invalidation() is
  'Invalidates both affected account projections without disclosing block direction or state.';

create function private.broadcast_profile_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile_id uuid := case when tg_op = 'DELETE' then old.id else new.id end;
  recipient_ids uuid[];
begin
  recipient_ids := array(
    select target_profile_id
    union
    select case
      when relationship.profile_low_id = target_profile_id then relationship.profile_high_id
      else relationship.profile_low_id
    end
    from public.user_relationships as relationship
    where target_profile_id in (relationship.profile_low_id, relationship.profile_high_id)
    union
    select case
      when block_record.blocker_id = target_profile_id then block_record.blocked_id
      else block_record.blocker_id
    end
    from public.user_blocks as block_record
    where target_profile_id in (block_record.blocker_id, block_record.blocked_id)
    union
    select list_record.owner_id
    from public.active_list_participants as own_access
    join public.active_lists as list_record on list_record.id = own_access.list_id
    where own_access.participant_profile_id = target_profile_id
      and own_access.state in ('pending', 'member')
    union
    select peer_access.participant_profile_id
    from public.active_list_participants as own_access
    join public.active_list_participants as peer_access
      on peer_access.list_id = own_access.list_id
    where own_access.participant_profile_id = target_profile_id
      and own_access.state = 'member'
      and peer_access.state = 'member'
    union
    select owned_access.participant_profile_id
    from public.active_lists as owned_list
    join public.active_list_participants as owned_access
      on owned_access.list_id = owned_list.id
    where owned_list.owner_id = target_profile_id
      and owned_access.state in ('pending', 'member')
    union
    select notification.recipient_id
    from public.user_notifications as notification
    where notification.actor_id = target_profile_id
  );
  perform private.send_account_invalidations(recipient_ids);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function private.broadcast_profile_invalidation() is
  'Invalidates accounts with an existing projection of a changed profile and captures affected list recipients before profile-delete cascades.';

alter function private.send_account_invalidations(uuid[]) owner to postgres;
alter function private.broadcast_active_list_invalidation() owner to postgres;
alter function private.broadcast_active_list_participant_invalidation() owner to postgres;
alter function private.broadcast_notification_invalidation() owner to postgres;
alter function private.broadcast_relationship_invalidation() owner to postgres;
alter function private.broadcast_block_invalidation() owner to postgres;
alter function private.broadcast_profile_invalidation() owner to postgres;

revoke all on function private.send_account_invalidations(uuid[])
from public, anon, authenticated, service_role;
revoke all on function private.broadcast_active_list_invalidation()
from public, anon, authenticated, service_role;
revoke all on function private.broadcast_active_list_participant_invalidation()
from public, anon, authenticated, service_role;
revoke all on function private.broadcast_notification_invalidation()
from public, anon, authenticated, service_role;
revoke all on function private.broadcast_relationship_invalidation()
from public, anon, authenticated, service_role;
revoke all on function private.broadcast_block_invalidation()
from public, anon, authenticated, service_role;
revoke all on function private.broadcast_profile_invalidation()
from public, anon, authenticated, service_role;

create trigger active_lists_broadcast_invalidation_after_write
after insert or update on public.active_lists
for each row execute function private.broadcast_active_list_invalidation();

create trigger active_lists_broadcast_invalidation_before_delete
before delete on public.active_lists
for each row execute function private.broadcast_active_list_invalidation();

create trigger active_list_participants_broadcast_invalidation
after insert or update or delete on public.active_list_participants
for each row execute function private.broadcast_active_list_participant_invalidation();

create trigger user_notifications_broadcast_invalidation
after insert or update or delete on public.user_notifications
for each row execute function private.broadcast_notification_invalidation();

create trigger user_relationships_broadcast_invalidation
after insert or update or delete on public.user_relationships
for each row execute function private.broadcast_relationship_invalidation();

create trigger user_blocks_broadcast_invalidation
after insert or update or delete on public.user_blocks
for each row execute function private.broadcast_block_invalidation();

create trigger profiles_broadcast_invalidation_after_projection_update
after update of username, display_name, onboarding_completed_at on public.profiles
for each row
when (
  old.username is distinct from new.username
  or old.display_name is distinct from new.display_name
  or old.onboarding_completed_at is distinct from new.onboarding_completed_at
)
execute function private.broadcast_profile_invalidation();

create trigger profiles_broadcast_invalidation_before_delete
before delete on public.profiles
for each row execute function private.broadcast_profile_invalidation();
