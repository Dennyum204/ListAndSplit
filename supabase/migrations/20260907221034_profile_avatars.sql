-- Private current avatars. Historical migrations and existing RPCs are preserved.
-- Fix the pre-existing owner-Split deletion failure: lock owned and surviving
-- parent lists together, then clear all identity columns before FK SET NULL.
create or replace function private.cleanup_active_list_dependents_before_profile_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_list_ids uuid[];
  access_effects boolean[];
  invalidation_recipient_ids uuid[];
  affected_list_id uuid;
  cleanup_results integer[] := '{}'::integer[];
  cleanup_index integer;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  select coalesce(
    pg_catalog.array_agg(
      distinct affected.list_id
      order by affected.list_id
    ),
    '{}'::uuid[]
  )
  into affected_list_ids
  from (
    select owned_list.id as list_id
    from public.active_lists as owned_list
    where owned_list.owner_id = old.id
    union
    select access_record.list_id
    from public.active_list_participants as access_record
    where access_record.participant_profile_id = old.id
    union
    select chat_message.list_id
    from public.active_list_chat_messages as chat_message
    where chat_message.sender_profile_id = old.id
    union
    select assignment.list_id
    from public.active_list_item_assignments as assignment
    where assignment.assignee_profile_id = old.id
    union
    select mention_record.list_id
    from public.active_list_note_mentions as mention_record
    where mention_record.mentioned_profile_id = old.id
    union
    select split_participant.list_id
    from public.active_list_split_participants as split_participant
    where split_participant.profile_id = old.id
    union
    select item_record.list_id
    from public.active_list_items as item_record
    where item_record.completed_by = old.id
  ) as affected
  join public.active_lists as list_record
    on list_record.id = affected.list_id;

  perform 1
  from public.active_lists as list_record
  where list_record.id = any(affected_list_ids)
  order by list_record.id
  for update;

  select coalesce(
    pg_catalog.array_agg(
      exists (
        select 1
        from public.active_list_participants as access_record
        where access_record.list_id = affected.list_id
          and access_record.participant_profile_id = old.id
          and access_record.state in ('pending', 'member')
      )
      order by affected.list_id
    ),
    '{}'::boolean[]
  )
  into access_effects
  from pg_catalog.unnest(affected_list_ids) as affected(list_id);

  select coalesce(
    pg_catalog.array_agg(
      distinct recipient.profile_id
      order by recipient.profile_id
    ),
    '{}'::uuid[]
  )
  into invalidation_recipient_ids
  from (
    select old.id as profile_id
    union
    select case
      when relationship.profile_low_id = old.id
        then relationship.profile_high_id
      else relationship.profile_low_id
    end
    from public.user_relationships as relationship
    where old.id in (
      relationship.profile_low_id,
      relationship.profile_high_id
    )
    union
    select case
      when block_record.blocker_id = old.id
        then block_record.blocked_id
      else block_record.blocker_id
    end
    from public.user_blocks as block_record
    where old.id in (
      block_record.blocker_id,
      block_record.blocked_id
    )
    union
    select list_record.owner_id
    from public.active_list_participants as own_access
    join public.active_lists as list_record
      on list_record.id = own_access.list_id
    where own_access.participant_profile_id = old.id
      and own_access.state in ('pending', 'member')
    union
    select peer_access.participant_profile_id
    from public.active_list_participants as own_access
    join public.active_list_participants as peer_access
      on peer_access.list_id = own_access.list_id
    where own_access.participant_profile_id = old.id
      and own_access.state = 'member'
      and peer_access.state = 'member'
    union
    select owned_access.participant_profile_id
    from public.active_lists as owned_list
    join public.active_list_participants as owned_access
      on owned_access.list_id = owned_list.id
    where owned_list.owner_id = old.id
      and owned_access.state in ('pending', 'member')
    union
    select notification_record.recipient_id
    from public.user_notifications as notification_record
    where notification_record.actor_id = old.id
    union
    select list_record.owner_id
    from public.active_lists as list_record
    where list_record.id = any(affected_list_ids)
    union
    select access_record.participant_profile_id
    from public.active_list_participants as access_record
    where access_record.list_id = any(affected_list_ids)
      and access_record.state = 'member'
  ) as recipient;

  perform 1
  from public.active_list_chat_states as chat_state
  where chat_state.list_id = any(affected_list_ids)
    and chat_state.profile_id = old.id
  order by chat_state.list_id, chat_state.profile_id
  for update;

  perform 1
  from public.active_list_chat_messages as chat_message
  where chat_message.sender_profile_id = old.id
  order by chat_message.list_id, chat_message.message_position
  for update;

  perform 1
  from private.active_list_chat_send_requests as request_record
  where request_record.list_id = any(affected_list_ids)
    and request_record.actor_id = old.id
  order by request_record.list_id, request_record.request_id
  for update;

  update public.active_list_chat_messages as chat_message
  set sender_profile_id = null,
      body = null,
      deleted_at = coalesce(chat_message.deleted_at, mutation_time),
      deletion_kind = 'account'
  where chat_message.sender_profile_id = old.id;

  perform 1
  from public.active_list_items as item_record
  where item_record.list_id = any(affected_list_ids)
    and (
      item_record.completed_by = old.id
      or exists (
        select 1
        from public.active_list_item_assignments as assignment
        where assignment.list_id = item_record.list_id
          and assignment.item_id = item_record.id
          and assignment.assignee_profile_id = old.id
      )
    )
  order by item_record.list_id, item_record.id
  for update;

  perform 1
  from public.active_list_participants as access_record
  where access_record.list_id = any(affected_list_ids)
    and access_record.participant_profile_id = old.id
  order by access_record.list_id, access_record.participant_profile_id
  for update;

  perform 1
  from public.active_list_item_assignments as assignment
  where assignment.list_id = any(affected_list_ids)
    and assignment.assignee_profile_id = old.id
  order by assignment.list_id, assignment.item_id
  for update;

  perform 1
  from public.active_list_note_mentions as mention_record
  where mention_record.list_id = any(affected_list_ids)
    and mention_record.mentioned_profile_id = old.id
  order by mention_record.list_id, mention_record.mentioned_profile_id
  for update;

  perform 1
  from public.active_list_split_participants as split_participant
  where split_participant.list_id = any(affected_list_ids)
    and split_participant.profile_id = old.id
  order by split_participant.list_id, split_participant.id
  for update;

  foreach affected_list_id in array affected_list_ids
  loop
    cleanup_results := pg_catalog.array_append(
      cleanup_results,
      private.cleanup_active_list_profile_links(
        affected_list_id,
        old.id,
        mutation_time
      )
    );
  end loop;

  update public.active_list_split_participants as split_participant
  set profile_id = null,
      username_snapshot = null,
      display_name_snapshot = null,
      updated_at = mutation_time
  where split_participant.list_id = any(affected_list_ids)
    and split_participant.profile_id = old.id;

  foreach affected_list_id in array affected_list_ids
  loop
    perform private.suppress_active_list_profile_link_notifications(
      affected_list_id,
      old.id,
      mutation_time
    );
  end loop;

  for cleanup_index in
    1..pg_catalog.cardinality(affected_list_ids)
  loop
    if cleanup_results[cleanup_index] <> 0
      or access_effects[cleanup_index]
    then
      update public.active_lists as list_record
      set version = list_record.version + 1,
          general_note_version = list_record.general_note_version
            + case
                when (cleanup_results[cleanup_index] & 2) = 2
                  then 1
                else 0
              end,
          general_note_updated_at = case
            when (cleanup_results[cleanup_index] & 2) = 2
              then mutation_time
            else list_record.general_note_updated_at
          end,
          updated_at = mutation_time
      where list_record.id = affected_list_ids[cleanup_index];
    end if;
  end loop;

  perform private.send_account_invalidations(
    invalidation_recipient_ids
  );

  return old;
end;
$$;

create table private.profile_avatars (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  version bigint not null default 0 check (version >= 0),
  current_file uuid,
  lease uuid,
  lease_until timestamptz,
  last_request uuid,
  last_fingerprint text,
  check ((lease is null) = (lease_until is null)),
  check ((last_request is null) = (last_fingerprint is null))
);
create table private.profile_avatar_files (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index profile_avatar_files_profile_idx on private.profile_avatar_files(profile_id);
alter table private.profile_avatars enable row level security;
alter table private.profile_avatars force row level security;
alter table private.profile_avatar_files enable row level security;
alter table private.profile_avatar_files force row level security;
create policy profile_avatars_reject on private.profile_avatars as restrictive
  for all to anon, authenticated using (false) with check (false);
create policy profile_avatar_files_reject on private.profile_avatar_files as restrictive
  for all to anon, authenticated using (false) with check (false);
revoke all on private.profile_avatars, private.profile_avatar_files
  from public, anon, authenticated, service_role;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('profile-avatars', 'profile-avatars', false, 327680, array['image/png']);
-- Only the SDK-authenticated Edge boundary uses the server Storage client.
-- A restrictive policy prevents later broad client policies exposing this bucket.
create policy profile_avatar_objects_reject on storage.objects as restrictive
  for all to anon, authenticated
  using (bucket_id <> 'profile-avatars')
  with check (bucket_id <> 'profile-avatars');

create function public.get_own_profile_avatar()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  caller uuid := private.require_verified_friendship_caller();
  avatar private.profile_avatars%rowtype;
begin
  select * into avatar from private.profile_avatars where profile_id = caller;
  return jsonb_build_object('version', coalesce(avatar.version, 0),
    'has_image', avatar.current_file is not null);
end;
$$;

create function public.resolve_profile_avatar(target_kind text, target_id uuid)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare
  caller uuid := private.require_verified_friendship_caller();
  target uuid;
begin
  if target_kind = 'profile' then
    target := target_id;
  elsif target_kind = 'chat' then
    select m.sender_profile_id into target
    from public.active_list_chat_messages m
    join public.active_list_chat_states s on s.list_id = m.list_id and s.profile_id = caller
    where m.id = target_id and m.message_position > s.visible_after_message_position
      and m.deleted_at is null
      and private.active_list_caller_is_member(m.list_id, caller);
  elsif target_kind = 'split' then
    select p.profile_id into target from public.active_list_split_participants p
    where p.id = target_id and private.active_list_caller_is_member(p.list_id, caller);
  else
    raise exception using errcode = '22023', message = 'invalid avatar target';
  end if;
  if target is null or not exists (
    select 1 from public.profiles p where p.id = target and p.onboarding_completed_at is not null
  ) or exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = caller and b.blocked_id = target)
       or (b.blocker_id = target and b.blocked_id = caller)
  ) then return null; end if;
  return (select current_file from private.profile_avatars where profile_id = target);
end;
$$;

-- All following RPCs are server-only. target_profile is always supplied by the
-- verified SDK wrapper, never copied from an HTTP request body.
create function public.begin_profile_avatar_operation(
  target_profile uuid, request_id uuid, fingerprint text, expected_version bigint
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  avatar private.profile_avatars%rowtype;
  token uuid := gen_random_uuid();
  completed boolean;
begin
  if target_profile is null or request_id is null or fingerprint is null
    or length(fingerprint) not between 1 and 80 then
    raise exception using errcode = '22023', message = 'invalid avatar operation';
  end if;
  perform 1 from public.profiles p join auth.users u on u.id = p.id
    where p.id = target_profile and u.email_confirmed_at is not null for update of p;
  if not found then
    raise exception using errcode = '42501', message = 'verified account required';
  end if;
  insert into private.profile_avatars(profile_id) values(target_profile) on conflict do nothing;
  select * into avatar from private.profile_avatars where profile_id = target_profile for update;
  if avatar.lease_until > clock_timestamp() then
    raise exception using errcode = '55P03', message = 'avatar operation in progress';
  end if;
  completed := coalesce(avatar.last_request = request_id, false);
  if completed and avatar.last_fingerprint <> fingerprint then
    raise exception using errcode = '22023', message = 'conflicting avatar request';
  end if;
  if not completed and expected_version is not null and avatar.version <> expected_version then
    raise exception using errcode = '40001', message = 'avatar changed';
  end if;
  update private.profile_avatars set lease = token, lease_until = clock_timestamp() + interval '15 minutes'
    where profile_id = target_profile;
  return jsonb_build_object('lease', token, 'version', avatar.version,
    'current_file', avatar.current_file, 'completed', completed,
    'files', coalesce((select jsonb_agg(id order by id) from private.profile_avatar_files
      where profile_id = target_profile), '[]'::jsonb));
end;
$$;

create function private.lock_profile_avatar_lease(target_profile uuid, token uuid)
returns private.profile_avatars language plpgsql volatile security invoker set search_path = '' as $$
declare avatar private.profile_avatars%rowtype;
begin
  perform 1 from public.profiles where id = target_profile for update;
  select * into avatar from private.profile_avatars where profile_id = target_profile for update;
  if avatar.lease is distinct from token or token is null
    or avatar.lease_until <= clock_timestamp() then
    raise exception using errcode = '55P03', message = 'avatar lease unavailable';
  end if;
  return avatar;
end;
$$;

create function public.stage_profile_avatar_file(target_profile uuid, token uuid)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare file_id uuid;
begin
  perform private.lock_profile_avatar_lease(target_profile, token);
  if (select count(*) from private.profile_avatar_files where profile_id = target_profile) >= 2 then
    raise exception using errcode = '55000', message = 'avatar cleanup required';
  end if;
  insert into private.profile_avatar_files(profile_id) values(target_profile) returning id into file_id;
  return file_id;
end;
$$;

create function public.forget_profile_avatar_file(target_profile uuid, token uuid, file_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare avatar private.profile_avatars%rowtype;
begin
  avatar := private.lock_profile_avatar_lease(target_profile, token);
  if avatar.current_file = file_id then
    raise exception using errcode = '22023', message = 'current avatar cannot be forgotten';
  end if;
  delete from private.profile_avatar_files where id = file_id and profile_id = target_profile;
end;
$$;

create function public.commit_profile_avatar(
  target_profile uuid, token uuid, file_id uuid, request_id uuid, fingerprint text
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare avatar private.profile_avatars%rowtype;
begin
  avatar := private.lock_profile_avatar_lease(target_profile, token);
  if request_id is null or fingerprint is null then
    raise exception using errcode = '22023', message = 'invalid avatar request';
  end if;
  if file_id is not null and not exists(select 1 from private.profile_avatar_files
    where id = file_id and profile_id = target_profile) then
    raise exception using errcode = '22023', message = 'avatar file unavailable';
  end if;
  if avatar.last_request = request_id then
    if avatar.last_fingerprint <> fingerprint then
      raise exception using errcode = '22023', message = 'conflicting avatar request';
    end if;
  else
    update private.profile_avatars set current_file = file_id,
      version = version + case when current_file is distinct from file_id then 1 else 0 end,
      last_request = request_id, last_fingerprint = fingerprint where profile_id = target_profile
      returning * into avatar;
  end if;
  return jsonb_build_object('version', avatar.version, 'has_image', avatar.current_file is not null);
end;
$$;

create function public.finish_profile_avatar_operation(target_profile uuid, token uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  perform private.lock_profile_avatar_lease(target_profile, token);
  update private.profile_avatars set lease = null, lease_until = null where profile_id = target_profile;
end;
$$;

alter table private.profile_avatars owner to postgres;
alter table private.profile_avatar_files owner to postgres;
alter function public.get_own_profile_avatar() owner to postgres;
alter function public.resolve_profile_avatar(text,uuid) owner to postgres;
revoke all on function public.get_own_profile_avatar(), public.resolve_profile_avatar(text,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_own_profile_avatar(), public.resolve_profile_avatar(text,uuid) to authenticated;
alter function public.begin_profile_avatar_operation(uuid,uuid,text,bigint) owner to postgres;
alter function private.lock_profile_avatar_lease(uuid,uuid) owner to postgres;
alter function public.stage_profile_avatar_file(uuid,uuid) owner to postgres;
alter function public.forget_profile_avatar_file(uuid,uuid,uuid) owner to postgres;
alter function public.commit_profile_avatar(uuid,uuid,uuid,uuid,text) owner to postgres;
alter function public.finish_profile_avatar_operation(uuid,uuid) owner to postgres;
revoke all on function private.lock_profile_avatar_lease(uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function public.begin_profile_avatar_operation(uuid,uuid,text,bigint),
  public.stage_profile_avatar_file(uuid,uuid), public.forget_profile_avatar_file(uuid,uuid,uuid),
  public.commit_profile_avatar(uuid,uuid,uuid,uuid,text), public.finish_profile_avatar_operation(uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.begin_profile_avatar_operation(uuid,uuid,text,bigint),
  public.stage_profile_avatar_file(uuid,uuid), public.forget_profile_avatar_file(uuid,uuid,uuid),
  public.commit_profile_avatar(uuid,uuid,uuid,uuid,text), public.finish_profile_avatar_operation(uuid,uuid)
  to service_role;

create function private.broadcast_avatar_invalidation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.send_account_invalidations(array(
    select new.profile_id
    union
    select case when r.profile_low_id = new.profile_id then r.profile_high_id else r.profile_low_id end
      from public.user_relationships r where new.profile_id in (r.profile_low_id, r.profile_high_id)
    union
    select l.owner_id from public.active_lists l
      where private.active_list_caller_is_member(l.id, new.profile_id)
    union
    select p.participant_profile_id from public.active_list_participants p
      where p.state = 'member' and private.active_list_caller_is_member(p.list_id, new.profile_id)
  ));
  return new;
end;
$$;
alter function private.broadcast_avatar_invalidation() owner to postgres;
revoke all on function private.broadcast_avatar_invalidation() from public, anon, authenticated, service_role;
create trigger profile_avatars_broadcast after update of current_file on private.profile_avatars
  for each row when (old.current_file is distinct from new.current_file)
  execute function private.broadcast_avatar_invalidation();
