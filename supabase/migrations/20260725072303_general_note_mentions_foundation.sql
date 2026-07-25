begin;

create function private.normalize_active_list_general_note(raw_note text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select nullif(
    pg_catalog.btrim(
      pg_catalog.replace(
        pg_catalog.replace(raw_note, E'\r\n', E'\n'),
        E'\r',
        E'\n'
      ),
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    ),
    ''
  )
$$;

create function private.active_list_note_contains_username(
  note_text text,
  canonical_username text
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(
    pg_catalog.translate(
      note_text,
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      'abcdefghijklmnopqrstuvwxyz'
    ) ~ (
      '(^|[^A-Za-z0-9_@])@'
      || pg_catalog.translate(
        canonical_username,
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        'abcdefghijklmnopqrstuvwxyz'
      )
      || '([^A-Za-z0-9_@]|$)'
    ),
    false
  )
$$;

alter table public.active_lists
  add column general_note_text text,
  add column general_note_version bigint not null default 1,
  add column general_note_updated_at timestamptz,
  add constraint active_lists_general_note_text_check check (
    general_note_text is null
    or (
      general_note_text =
        private.normalize_active_list_general_note(general_note_text)
      and pg_catalog.char_length(general_note_text) between 1 and 2000
    )
  ),
  add constraint active_lists_general_note_version_check check (
    general_note_version > 0
  ),
  add constraint active_lists_general_note_time_check check (
    (general_note_text is null and general_note_updated_at is null)
    or (
      general_note_text is not null
      and general_note_updated_at is not null
      and general_note_updated_at >= created_at
    )
  );

create table public.active_list_note_mentions (
  list_id uuid not null,
  mentioned_profile_id uuid not null,
  resolved_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint active_list_note_mentions_pkey primary key (
    list_id,
    mentioned_profile_id
  ),
  constraint active_list_note_mentions_list_fkey foreign key (list_id)
    references public.active_lists(id) on delete cascade,
  constraint active_list_note_mentions_profile_fkey foreign key (
    mentioned_profile_id
  ) references public.profiles(id) on delete cascade
);

alter table public.active_list_note_mentions owner to postgres;

create index active_list_note_mentions_profile_list_idx
on public.active_list_note_mentions(mentioned_profile_id, list_id);

alter table public.active_list_note_mentions enable row level security;
alter table public.active_list_note_mentions force row level security;

revoke all on table public.active_list_note_mentions
from public, anon, authenticated, service_role;

create policy "active_list_note_mentions_reject_direct_client_access"
on public.active_list_note_mentions
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create function private.enforce_active_list_note_mention_eligibility()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  list_record public.active_lists%rowtype;
  target_username text;
begin
  select candidate.*
  into list_record
  from public.active_lists as candidate
  where candidate.id = new.list_id;

  select profile_record.username
  into target_username
  from public.profiles as profile_record
  where profile_record.id = new.mentioned_profile_id
    and profile_record.onboarding_completed_at is not null;

  if list_record.id is null
    or list_record.status <> 'active'
    or target_username is null
    or not (
      list_record.owner_id = new.mentioned_profile_id
      or exists (
        select 1
        from public.active_list_participants as access_record
        where access_record.list_id = new.list_id
          and access_record.participant_profile_id =
            new.mentioned_profile_id
          and access_record.state = 'member'
      )
    )
    or exists (
      select 1
      from public.user_blocks as block_record
      where (
        block_record.blocker_id = list_record.owner_id
        and block_record.blocked_id = new.mentioned_profile_id
      ) or (
        block_record.blocker_id = new.mentioned_profile_id
        and block_record.blocked_id = list_record.owner_id
      )
    )
    or not private.active_list_note_contains_username(
      list_record.general_note_text,
      target_username
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid note mentions';
  end if;

  return new;
end;
$$;

create constraint trigger active_list_note_mentions_enforce_eligibility
after insert or update
on public.active_list_note_mentions
deferrable initially immediate
for each row execute function
  private.enforce_active_list_note_mention_eligibility();

create function private.build_active_list_note_mentions(
  target_list_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'profile_id', profile_record.id,
        'username', profile_record.username,
        'display_name', profile_record.display_name
      )
      order by profile_record.username, profile_record.id
    ),
    '[]'::jsonb
  )
  from public.active_list_note_mentions as mention_record
  join public.profiles as profile_record
    on profile_record.id = mention_record.mentioned_profile_id
   and profile_record.onboarding_completed_at is not null
  join public.active_lists as list_record
    on list_record.id = mention_record.list_id
  where mention_record.list_id = target_list_id
    and (
      list_record.owner_id = profile_record.id
      or exists (
        select 1
        from public.active_list_participants as access_record
        where access_record.list_id = list_record.id
          and access_record.participant_profile_id = profile_record.id
          and access_record.state = 'member'
      )
    )
$$;

create function public.get_active_list_general_note(target_list_id uuid)
returns table (
  list_version bigint,
  general_note_text text,
  general_note_version bigint,
  general_note_updated_at timestamptz,
  mentions jsonb
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
    list_record.version,
    list_record.general_note_text,
    list_record.general_note_version,
    list_record.general_note_updated_at,
    private.build_active_list_note_mentions(list_record.id)
  from public.active_lists as list_record
  where list_record.id = target_list_id;
end;
$$;

create function public.update_active_list_general_note(
  target_list_id uuid,
  new_general_note_text text,
  mentioned_profile_ids uuid[],
  expected_general_note_version bigint
)
returns table (
  list_version bigint,
  general_note_text text,
  general_note_version bigint,
  general_note_updated_at timestamptz,
  mentions jsonb
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  canonical_note_text text :=
    private.normalize_active_list_general_note(new_general_note_text);
  canonical_mentioned_profile_ids uuid[];
  preflight_current_mentioned_profile_ids uuid[];
  current_mentioned_profile_ids uuid[];
  locked_profile_ids uuid[];
  list_record public.active_lists%rowtype;
  eligible_count integer;
  mutation_time timestamptz;
  resulting_note_version bigint;
begin
  if target_list_id is null
    or expected_general_note_version is null
    or expected_general_note_version < 1
    or mentioned_profile_ids is null
    or pg_catalog.cardinality(mentioned_profile_ids) > 100
    or pg_catalog.array_position(
      mentioned_profile_ids,
      null::uuid
    ) is not null
    or (
      canonical_note_text is not null
      and pg_catalog.char_length(canonical_note_text) > 2000
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid general note';
  end if;

  select coalesce(
    pg_catalog.array_agg(
      distinct submitted.profile_id
      order by submitted.profile_id
    ),
    '{}'::uuid[]
  )
  into canonical_mentioned_profile_ids
  from pg_catalog.unnest(mentioned_profile_ids)
    as submitted(profile_id);

  if pg_catalog.cardinality(canonical_mentioned_profile_ids) > 20
    or (
      canonical_note_text is null
      and pg_catalog.cardinality(canonical_mentioned_profile_ids) > 0
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid note mentions';
  end if;

  if not private.active_list_caller_is_member(
    target_list_id,
    caller_id
  ) then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  select pg_catalog.count(*)::integer
  into eligible_count
  from pg_catalog.unnest(canonical_mentioned_profile_ids)
    as submitted(profile_id)
  join public.profiles as profile_record
    on profile_record.id = submitted.profile_id
   and profile_record.onboarding_completed_at is not null
  join public.active_lists as candidate_list
    on candidate_list.id = target_list_id
  where (
      candidate_list.owner_id = profile_record.id
      or exists (
        select 1
        from public.active_list_participants as access_record
        where access_record.list_id = candidate_list.id
          and access_record.participant_profile_id = profile_record.id
          and access_record.state = 'member'
      )
    )
    and not exists (
      select 1
      from public.user_blocks as block_record
      where (
        block_record.blocker_id = caller_id
        and block_record.blocked_id = profile_record.id
      ) or (
        block_record.blocker_id = profile_record.id
        and block_record.blocked_id = caller_id
      )
    )
    and private.active_list_note_contains_username(
      canonical_note_text,
      profile_record.username
    );

  if eligible_count <>
    pg_catalog.cardinality(canonical_mentioned_profile_ids)
  then
    raise exception using
      errcode = '22023',
      message = 'invalid note mentions';
  end if;

  select coalesce(
    pg_catalog.array_agg(
      mention_record.mentioned_profile_id
      order by mention_record.mentioned_profile_id
    ),
    '{}'::uuid[]
  )
  into preflight_current_mentioned_profile_ids
  from public.active_list_note_mentions as mention_record
  where mention_record.list_id = target_list_id;

  select coalesce(
    pg_catalog.array_agg(
      distinct identity.profile_id
      order by identity.profile_id
    ),
    '{}'::uuid[]
  )
  into locked_profile_ids
  from pg_catalog.unnest(
    canonical_mentioned_profile_ids
      || preflight_current_mentioned_profile_ids
      || array[caller_id]
  ) as identity(profile_id);

  perform private.lock_active_list_item_assignee_profiles(
    locked_profile_ids
  );

  select candidate_list.*
  into list_record
  from public.active_lists as candidate_list
  where candidate_list.id = target_list_id
  for update;

  if not found
    or not private.active_list_caller_is_member(
      target_list_id,
      caller_id
    )
  then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  if list_record.status <> 'active' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  select coalesce(
    pg_catalog.array_agg(
      mention_record.mentioned_profile_id
      order by mention_record.mentioned_profile_id
    ),
    '{}'::uuid[]
  )
  into current_mentioned_profile_ids
  from public.active_list_note_mentions as mention_record
  where mention_record.list_id = target_list_id;

  if current_mentioned_profile_ids <>
    preflight_current_mentioned_profile_ids
  then
    raise exception using errcode = '40001', message = 'list changed';
  end if;

  perform 1
  from public.active_list_participants as access_record
  where access_record.list_id = target_list_id
    and access_record.participant_profile_id = any(
      canonical_mentioned_profile_ids || current_mentioned_profile_ids
    )
  order by access_record.participant_profile_id
  for update;

  perform 1
  from public.active_list_note_mentions as mention_record
  where mention_record.list_id = target_list_id
  order by mention_record.mentioned_profile_id
  for update;

  select pg_catalog.count(*)::integer
  into eligible_count
  from pg_catalog.unnest(canonical_mentioned_profile_ids)
    as submitted(profile_id)
  join public.profiles as profile_record
    on profile_record.id = submitted.profile_id
   and profile_record.onboarding_completed_at is not null
  where (
      list_record.owner_id = profile_record.id
      or exists (
        select 1
        from public.active_list_participants as access_record
        where access_record.list_id = target_list_id
          and access_record.participant_profile_id = profile_record.id
          and access_record.state = 'member'
      )
    )
    and not exists (
      select 1
      from public.user_blocks as block_record
      where (
        block_record.blocker_id = caller_id
        and block_record.blocked_id = profile_record.id
      ) or (
        block_record.blocker_id = profile_record.id
        and block_record.blocked_id = caller_id
      )
    )
    and private.active_list_note_contains_username(
      canonical_note_text,
      profile_record.username
    );

  if eligible_count <>
    pg_catalog.cardinality(canonical_mentioned_profile_ids)
  then
    raise exception using
      errcode = '22023',
      message = 'invalid note mentions';
  end if;

  select coalesce(
    pg_catalog.array_agg(
      mention_record.mentioned_profile_id
      order by mention_record.mentioned_profile_id
    ),
    '{}'::uuid[]
  )
  into current_mentioned_profile_ids
  from public.active_list_note_mentions as mention_record
  where mention_record.list_id = target_list_id;

  if list_record.general_note_text is not distinct from canonical_note_text
    and current_mentioned_profile_ids = canonical_mentioned_profile_ids
  then
    if expected_general_note_version not in (
      list_record.general_note_version,
      list_record.general_note_version - 1
    ) then
      raise exception using errcode = '40001', message = 'list changed';
    end if;

    return query
    select
      list_record.version,
      list_record.general_note_text,
      list_record.general_note_version,
      list_record.general_note_updated_at,
      private.build_active_list_note_mentions(list_record.id);
    return;
  end if;

  if expected_general_note_version <> list_record.general_note_version then
    raise exception using errcode = '40001', message = 'list changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  resulting_note_version := list_record.general_note_version + 1;

  set constraints public.active_list_note_mentions_enforce_eligibility
    deferred;

  delete from public.active_list_note_mentions as mention_record
  where mention_record.list_id = target_list_id
    and not (
      mention_record.mentioned_profile_id =
        any(canonical_mentioned_profile_ids)
    );

  insert into public.active_list_note_mentions (
    list_id,
    mentioned_profile_id,
    resolved_at
  )
  select target_list_id, submitted.profile_id, mutation_time
  from pg_catalog.unnest(canonical_mentioned_profile_ids)
    as submitted(profile_id)
  where not (
    submitted.profile_id = any(current_mentioned_profile_ids)
  )
  order by submitted.profile_id;

  insert into public.user_notifications (
    recipient_id,
    actor_id,
    notification_type,
    active_list_id,
    general_note_version,
    created_at,
    expires_at
  )
  select
    submitted.profile_id,
    caller_id,
    'list_note_mentioned',
    target_list_id,
    resulting_note_version,
    mutation_time,
    mutation_time + interval '180 days'
  from pg_catalog.unnest(canonical_mentioned_profile_ids)
    as submitted(profile_id)
  where submitted.profile_id <> caller_id
    and not (
      submitted.profile_id = any(current_mentioned_profile_ids)
    )
  order by submitted.profile_id
  on conflict do nothing;

  update public.active_lists as changed_list
  set general_note_text = canonical_note_text,
      general_note_version = resulting_note_version,
      general_note_updated_at = case
        when canonical_note_text is null then null
        else mutation_time
      end,
      version = changed_list.version + 1,
      updated_at = mutation_time
  where changed_list.id = target_list_id
  returning changed_list.* into list_record;

  set constraints public.active_list_note_mentions_enforce_eligibility
    immediate;

  return query
  select
    list_record.version,
    list_record.general_note_text,
    list_record.general_note_version,
    list_record.general_note_updated_at,
    private.build_active_list_note_mentions(list_record.id);
end;
$$;

alter table public.user_notifications
  drop constraint user_notifications_type_check,
  drop constraint user_notifications_reference_scope_check,
  drop constraint user_notifications_positive_version_check,
  add column general_note_version bigint;

alter table public.user_notifications
  add constraint user_notifications_type_check check (
    notification_type in (
      'friend_request',
      'list_invitation',
      'list_invitation_accepted',
      'list_invitation_declined',
      'list_member_left',
      'list_member_removed',
      'list_ownership_transferred',
      'list_item_assigned',
      'list_note_mentioned'
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
      and active_list_item_id is null
      and assignment_item_version is null
      and general_note_version is null
    ) or (
      notification_type not in (
        'friend_request',
        'list_item_assigned',
        'list_note_mentioned'
      )
      and relationship_low_id is null
      and relationship_high_id is null
      and relationship_version is null
      and active_list_id is not null
      and access_participant_id is not null
      and access_version is not null
      and active_list_item_id is null
      and assignment_item_version is null
      and general_note_version is null
    ) or (
      notification_type = 'list_item_assigned'
      and relationship_low_id is null
      and relationship_high_id is null
      and relationship_version is null
      and active_list_id is not null
      and access_participant_id is null
      and access_version is null
      and active_list_item_id is not null
      and assignment_item_version is not null
      and general_note_version is null
    ) or (
      notification_type = 'list_note_mentioned'
      and relationship_low_id is null
      and relationship_high_id is null
      and relationship_version is null
      and active_list_id is not null
      and access_participant_id is null
      and access_version is null
      and active_list_item_id is null
      and assignment_item_version is null
      and general_note_version is not null
    )
  ),
  add constraint user_notifications_positive_version_check check (
    coalesce(
      relationship_version,
      access_version,
      assignment_item_version,
      general_note_version
    ) > 0
  );

create unique index user_notifications_note_mention_version_key
on public.user_notifications (
  active_list_id,
  recipient_id,
  notification_type,
  general_note_version
)
where notification_type = 'list_note_mentioned';

create index user_notifications_note_privacy_cleanup_idx
on public.user_notifications (
  active_list_id,
  actor_id,
  recipient_id
)
where notification_type = 'list_note_mentioned'
  and suppressed_at is null;

create function private.cleanup_active_list_profile_link_children(
  target_list_id uuid,
  target_profile_id uuid,
  mutation_time timestamptz
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  affected_item_ids uuid[];
  mention_link_removed boolean := false;
begin
  select coalesce(
    pg_catalog.array_agg(
      distinct assignment.item_id
      order by assignment.item_id
    ),
    '{}'::uuid[]
  )
  into affected_item_ids
  from public.active_list_item_assignments as assignment
  where assignment.list_id =
      cleanup_active_list_profile_link_children.target_list_id
    and assignment.assignee_profile_id =
      cleanup_active_list_profile_link_children.target_profile_id;

  perform 1
  from public.active_list_item_assignments as assignment
  where assignment.list_id =
      cleanup_active_list_profile_link_children.target_list_id
    and assignment.assignee_profile_id =
      cleanup_active_list_profile_link_children.target_profile_id
  order by assignment.item_id
  for update;

  perform 1
  from public.active_list_note_mentions as mention_record
  where mention_record.list_id =
      cleanup_active_list_profile_link_children.target_list_id
    and mention_record.mentioned_profile_id =
      cleanup_active_list_profile_link_children.target_profile_id
  order by mention_record.mentioned_profile_id
  for update;

  delete from public.active_list_item_assignments as assignment
  where assignment.list_id =
      cleanup_active_list_profile_link_children.target_list_id
    and assignment.assignee_profile_id =
      cleanup_active_list_profile_link_children.target_profile_id;

  delete from public.active_list_note_mentions as mention_record
  where mention_record.list_id =
      cleanup_active_list_profile_link_children.target_list_id
    and mention_record.mentioned_profile_id =
      cleanup_active_list_profile_link_children.target_profile_id;
  mention_link_removed := found;

  if pg_catalog.cardinality(affected_item_ids) > 0 then
    update public.active_list_items as item_record
    set version = item_record.version + 1,
        updated_at =
          cleanup_active_list_profile_link_children.mutation_time
    where item_record.list_id =
        cleanup_active_list_profile_link_children.target_list_id
      and item_record.id = any(affected_item_ids);
  end if;

  return
    case when pg_catalog.cardinality(affected_item_ids) > 0 then 1 else 0 end
    + case when mention_link_removed then 2 else 0 end;
end;
$$;

create function private.suppress_active_list_profile_link_notifications(
  target_list_id uuid,
  target_profile_id uuid,
  mutation_time timestamptz
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.user_notifications as notification_record
  set suppressed_at = coalesce(
    notification_record.suppressed_at,
    suppress_active_list_profile_link_notifications.mutation_time
  )
  where notification_record.notification_type = 'list_item_assigned'
    and notification_record.active_list_id =
      suppress_active_list_profile_link_notifications.target_list_id
    and notification_record.recipient_id =
      suppress_active_list_profile_link_notifications.target_profile_id
    and notification_record.suppressed_at is null;

  update public.user_notifications as notification_record
  set suppressed_at = coalesce(
    notification_record.suppressed_at,
    suppress_active_list_profile_link_notifications.mutation_time
  )
  where notification_record.notification_type = 'list_note_mentioned'
    and notification_record.active_list_id =
      suppress_active_list_profile_link_notifications.target_list_id
    and (
      notification_record.recipient_id =
        suppress_active_list_profile_link_notifications.target_profile_id
      or notification_record.actor_id =
        suppress_active_list_profile_link_notifications.target_profile_id
    )
    and notification_record.suppressed_at is null;
end;
$$;

drop trigger active_list_participants_sync_split_identity
on public.active_list_participants;
create constraint trigger active_list_participants_sync_split_identity
after insert or update or delete
on public.active_list_participants
deferrable initially immediate
for each row execute function private.sync_active_list_split_participant();

drop trigger active_list_participants_broadcast_invalidation
on public.active_list_participants;
create constraint trigger active_list_participants_broadcast_invalidation
after insert or update or delete
on public.active_list_participants
deferrable initially immediate
for each row execute function
  private.broadcast_active_list_participant_invalidation();

create function private.cleanup_active_list_profile_links(
  target_list_id uuid,
  target_profile_id uuid,
  mutation_time timestamptz
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  cleanup_result integer;
begin
  select private.cleanup_active_list_profile_link_children(
    target_list_id,
    target_profile_id,
    mutation_time
  )
  into cleanup_result;

  return cleanup_result;
end;
$$;

create or replace function private.cleanup_active_list_item_assignments_for_profile(
  target_list_id uuid,
  target_profile_id uuid,
  mutation_time timestamptz
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  cleanup_result integer;
begin
  select private.cleanup_active_list_profile_links(
    target_list_id,
    target_profile_id,
    mutation_time
  )
  into cleanup_result;
  perform private.suppress_active_list_profile_link_notifications(
    target_list_id,
    target_profile_id,
    mutation_time
  );

  if cleanup_result <> 0 then
    update public.active_lists as list_record
    set version = list_record.version + 1,
        general_note_version = list_record.general_note_version
          + case when (cleanup_result & 2) = 2 then 1 else 0 end,
        general_note_updated_at = case
          when (cleanup_result & 2) = 2 then mutation_time
          else list_record.general_note_updated_at
        end,
        updated_at = mutation_time
    where list_record.id = target_list_id;
  end if;
end;
$$;

create or replace function private.suppress_item_assignment_notifications_on_block()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.user_notifications as notification_record
  set suppressed_at = coalesce(
    notification_record.suppressed_at,
    pg_catalog.clock_timestamp()
  )
  where notification_record.notification_type in (
      'list_item_assigned',
      'list_note_mentioned'
    )
    and notification_record.suppressed_at is null
    and (
      (
        notification_record.actor_id = new.blocker_id
        and notification_record.recipient_id = new.blocked_id
      ) or (
        notification_record.actor_id = new.blocked_id
        and notification_record.recipient_id = new.blocker_id
      )
    );
  return new;
end;
$$;

create or replace function public.remove_active_list_member(
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
  preflight_current_profile_ids uuid[];
  current_profile_ids uuid[];
  locked_profile_ids uuid[];
  access_record public.active_list_participants%rowtype;
  cleanup_result integer;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or target_profile_id is null
    or expected_access_version is null
    or expected_access_version < 1
  then
    raise exception using errcode = '22023', message = 'member unavailable';
  end if;

  preflight_current_profile_ids :=
    private.get_active_list_current_profile_ids(target_list_id);
  select coalesce(
    pg_catalog.array_agg(
      distinct identity.profile_id
      order by identity.profile_id
    ),
    '{}'::uuid[]
  )
  into locked_profile_ids
  from pg_catalog.unnest(
    preflight_current_profile_ids ||
      array[caller_id, target_profile_id]
  ) as identity(profile_id);

  perform private.lock_active_list_item_assignee_profiles(
    locked_profile_ids
  );
  perform private.lock_relationship_pair(caller_id, target_profile_id);

  perform 1
  from public.active_lists as list_record
  where list_record.id = target_list_id
    and list_record.owner_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  current_profile_ids :=
    private.get_active_list_current_profile_ids(target_list_id);
  if current_profile_ids is distinct from preflight_current_profile_ids then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  perform 1
  from public.active_list_items as item_record
  where item_record.list_id = target_list_id
    and exists (
      select 1
      from public.active_list_item_assignments as assignment
      where assignment.list_id = item_record.list_id
        and assignment.item_id = item_record.id
        and assignment.assignee_profile_id = target_profile_id
    )
  order by item_record.id
  for update;

  select current_access.*
  into access_record
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'member unavailable';
  end if;
  if access_record.state = 'removed'
    and expected_access_version = access_record.version - 1
  then
    return access_record.version;
  end if;
  if access_record.state <> 'member' then
    raise exception using errcode = 'P0002', message = 'member unavailable';
  end if;
  if access_record.version <> expected_access_version then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  set constraints
    public.active_list_participants_sync_split_identity deferred;
  set constraints
    public.active_list_participants_broadcast_invalidation deferred;

  update public.active_list_participants as current_access
  set state = 'removed',
      version = current_access.version + 1,
      state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id
  returning current_access.* into access_record;

  select private.cleanup_active_list_profile_links(
    target_list_id,
    target_profile_id,
    mutation_time
  )
  into cleanup_result;

  set constraints
    public.active_list_participants_sync_split_identity immediate;

  perform private.suppress_active_list_profile_link_notifications(
    target_list_id,
    target_profile_id,
    mutation_time
  );

  insert into public.user_notifications (
    recipient_id,
    actor_id,
    notification_type,
    active_list_id,
    access_participant_id,
    access_version,
    created_at,
    expires_at
  )
  values (
    target_profile_id,
    caller_id,
    'list_member_removed',
    target_list_id,
    target_profile_id,
    access_record.version,
    mutation_time,
    mutation_time + interval '180 days'
  )
  on conflict on constraint user_notifications_access_version_key do nothing;

  update public.active_lists as list_record
  set version = list_record.version + 1,
      general_note_version = list_record.general_note_version
        + case when (cleanup_result & 2) = 2 then 1 else 0 end,
      general_note_updated_at = case
        when (cleanup_result & 2) = 2 then mutation_time
        else list_record.general_note_updated_at
      end,
      updated_at = mutation_time
  where list_record.id = target_list_id;

  set constraints
    public.active_list_participants_broadcast_invalidation immediate;

  return access_record.version;
end;
$$;

create or replace function public.leave_active_list(
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
  preflight_owner_id uuid;
  preflight_current_profile_ids uuid[];
  current_profile_ids uuid[];
  locked_profile_ids uuid[];
  list_record public.active_lists%rowtype;
  access_record public.active_list_participants%rowtype;
  cleanup_result integer;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or expected_access_version is null
    or expected_access_version < 1
  then
    raise exception using
      errcode = '22023',
      message = 'membership unavailable';
  end if;

  select member_list.*
  into list_record
  from public.active_lists as member_list
  where member_list.id = target_list_id;
  if not found or list_record.owner_id = caller_id then
    raise exception using
      errcode = 'P0002',
      message = 'membership unavailable';
  end if;
  preflight_owner_id := list_record.owner_id;
  preflight_current_profile_ids :=
    private.get_active_list_current_profile_ids(target_list_id);

  select coalesce(
    pg_catalog.array_agg(
      distinct identity.profile_id
      order by identity.profile_id
    ),
    '{}'::uuid[]
  )
  into locked_profile_ids
  from pg_catalog.unnest(
    preflight_current_profile_ids ||
      array[caller_id, preflight_owner_id]
  ) as identity(profile_id);

  perform private.lock_active_list_item_assignee_profiles(
    locked_profile_ids
  );
  perform private.lock_relationship_pair(caller_id, preflight_owner_id);

  select member_list.*
  into list_record
  from public.active_lists as member_list
  where member_list.id = target_list_id
  for update;
  if not found or list_record.owner_id = caller_id then
    raise exception using
      errcode = 'P0002',
      message = 'membership unavailable';
  end if;
  if list_record.owner_id <> preflight_owner_id then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  current_profile_ids :=
    private.get_active_list_current_profile_ids(target_list_id);
  if current_profile_ids is distinct from preflight_current_profile_ids then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  perform 1
  from public.active_list_items as item_record
  where item_record.list_id = target_list_id
    and exists (
      select 1
      from public.active_list_item_assignments as assignment
      where assignment.list_id = item_record.list_id
        and assignment.item_id = item_record.id
        and assignment.assignee_profile_id = caller_id
    )
  order by item_record.id
  for update;

  select current_access.*
  into access_record
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'membership unavailable';
  end if;
  if access_record.state = 'left'
    and expected_access_version = access_record.version - 1
  then
    return access_record.version;
  end if;
  if access_record.state <> 'member' then
    raise exception using
      errcode = 'P0002',
      message = 'membership unavailable';
  end if;
  if access_record.version <> expected_access_version then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  set constraints
    public.active_list_participants_sync_split_identity deferred;
  set constraints
    public.active_list_participants_broadcast_invalidation deferred;

  update public.active_list_participants as current_access
  set state = 'left',
      version = current_access.version + 1,
      state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  returning current_access.* into access_record;

  select private.cleanup_active_list_profile_links(
    target_list_id,
    caller_id,
    mutation_time
  )
  into cleanup_result;

  set constraints
    public.active_list_participants_sync_split_identity immediate;

  perform private.suppress_active_list_profile_link_notifications(
    target_list_id,
    caller_id,
    mutation_time
  );

  insert into public.user_notifications (
    recipient_id,
    actor_id,
    notification_type,
    active_list_id,
    access_participant_id,
    access_version,
    created_at,
    expires_at
  )
  values (
    list_record.owner_id,
    caller_id,
    'list_member_left',
    target_list_id,
    caller_id,
    access_record.version,
    mutation_time,
    mutation_time + interval '180 days'
  )
  on conflict on constraint user_notifications_access_version_key do nothing;

  update public.active_lists as changed_list
  set version = changed_list.version + 1,
      general_note_version = changed_list.general_note_version
        + case when (cleanup_result & 2) = 2 then 1 else 0 end,
      general_note_updated_at = case
        when (cleanup_result & 2) = 2 then mutation_time
        else changed_list.general_note_updated_at
      end,
      updated_at = mutation_time
  where changed_list.id = target_list_id;

  set constraints
    public.active_list_participants_broadcast_invalidation immediate;

  return access_record.version;
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
  locked_profile_ids uuid[];
  preflight_list_ids uuid[];
  preflight_owner_ids uuid[];
  preflight_profile_ids uuid[];
  preflight_states text[];
  preflight_versions bigint[];
  current_list_ids uuid[];
  current_owner_ids uuid[];
  current_profile_ids uuid[];
  current_states text[];
  current_versions bigint[];
  cleanup_results integer[] := '{}'::integer[];
  new_access_versions bigint[] := '{}'::bigint[];
  new_state text;
  new_version bigint;
  mutation_time timestamptz;
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

  low_profile_id := least(caller_id, target_profile_id);
  high_profile_id := greatest(caller_id, target_profile_id);

  select
    coalesce(
      pg_catalog.array_agg(
        affected.list_id
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::uuid[]
    ),
    coalesce(
      pg_catalog.array_agg(
        affected.owner_id
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::uuid[]
    ),
    coalesce(
      pg_catalog.array_agg(
        affected.participant_profile_id
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::uuid[]
    ),
    coalesce(
      pg_catalog.array_agg(
        affected.state
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::text[]
    ),
    coalesce(
      pg_catalog.array_agg(
        affected.version
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::bigint[]
    )
  into
    preflight_list_ids,
    preflight_owner_ids,
    preflight_profile_ids,
    preflight_states,
    preflight_versions
  from (
    select
      list_record.id as list_id,
      list_record.owner_id,
      access_record.participant_profile_id,
      access_record.state,
      access_record.version
    from public.active_lists as list_record
    join public.active_list_participants as access_record
      on access_record.list_id = list_record.id
    where (
      list_record.owner_id = caller_id
      and access_record.participant_profile_id = target_profile_id
      and access_record.state in ('pending', 'member')
    ) or (
      list_record.owner_id = target_profile_id
      and access_record.participant_profile_id = caller_id
      and access_record.state in ('pending', 'member')
    ) or (
      list_record.owner_id not in (caller_id, target_profile_id)
      and access_record.participant_profile_id = caller_id
      and access_record.state = 'member'
      and exists (
        select 1
        from public.active_list_participants as other_access
        where other_access.list_id = list_record.id
          and other_access.participant_profile_id = target_profile_id
          and other_access.state = 'member'
      )
    )
  ) as affected;

  select coalesce(
    pg_catalog.array_agg(
      distinct identity.profile_id
      order by identity.profile_id
    ),
    '{}'::uuid[]
  )
  into locked_profile_ids
  from (
    select caller_id as profile_id
    union
    select target_profile_id
    union
    select owner_id
    from pg_catalog.unnest(preflight_owner_ids) as owner(owner_id)
    union
    select current_member.participant_profile_id
    from public.active_list_participants as current_member
    where current_member.list_id = any(preflight_list_ids)
      and current_member.state = 'member'
  ) as identity;

  perform private.lock_active_list_item_assignee_profiles(
    locked_profile_ids
  );
  perform private.lock_relationship_pair(caller_id, target_profile_id);

  perform 1
  from public.active_lists as list_record
  where list_record.id = any(preflight_list_ids)
  order by list_record.id
  for update;

  if not exists (
      select 1
      from public.profiles as caller_profile
      where caller_profile.id = caller_id
        and caller_profile.onboarding_completed_at is not null
    )
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

  select
    coalesce(
      pg_catalog.array_agg(
        affected.list_id
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::uuid[]
    ),
    coalesce(
      pg_catalog.array_agg(
        affected.owner_id
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::uuid[]
    ),
    coalesce(
      pg_catalog.array_agg(
        affected.participant_profile_id
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::uuid[]
    ),
    coalesce(
      pg_catalog.array_agg(
        affected.state
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::text[]
    ),
    coalesce(
      pg_catalog.array_agg(
        affected.version
        order by affected.list_id, affected.participant_profile_id
      ),
      '{}'::bigint[]
    )
  into
    current_list_ids,
    current_owner_ids,
    current_profile_ids,
    current_states,
    current_versions
  from (
    select
      list_record.id as list_id,
      list_record.owner_id,
      access_record.participant_profile_id,
      access_record.state,
      access_record.version
    from public.active_lists as list_record
    join public.active_list_participants as access_record
      on access_record.list_id = list_record.id
    where (
      list_record.owner_id = caller_id
      and access_record.participant_profile_id = target_profile_id
      and access_record.state in ('pending', 'member')
    ) or (
      list_record.owner_id = target_profile_id
      and access_record.participant_profile_id = caller_id
      and access_record.state in ('pending', 'member')
    ) or (
      list_record.owner_id not in (caller_id, target_profile_id)
      and access_record.participant_profile_id = caller_id
      and access_record.state = 'member'
      and exists (
        select 1
        from public.active_list_participants as other_access
        where other_access.list_id = list_record.id
          and other_access.participant_profile_id = target_profile_id
          and other_access.state = 'member'
      )
    )
  ) as affected;

  if current_list_ids is distinct from preflight_list_ids
    or current_owner_ids is distinct from preflight_owner_ids
    or current_profile_ids is distinct from preflight_profile_ids
    or current_states is distinct from preflight_states
    or current_versions is distinct from preflight_versions
    or exists (
      select 1
      from public.active_lists as list_record
      where list_record.id = any(current_list_ids)
        and (
          not (list_record.owner_id = any(locked_profile_ids))
          or exists (
            select 1
            from public.active_list_participants as current_member
            where current_member.list_id = list_record.id
              and current_member.state = 'member'
              and not (
                current_member.participant_profile_id =
                  any(locked_profile_ids)
              )
          )
        )
    )
  then
    raise exception using
      errcode = '40001',
      message = 'list access changed';
  end if;

  perform 1
  from public.active_list_items as item_record
  where exists (
    select 1
    from public.active_list_item_assignments as assignment
    where assignment.list_id = item_record.list_id
      and assignment.item_id = item_record.id
      and exists (
        select 1
        from pg_catalog.generate_subscripts(
          current_list_ids,
          1
        ) as affected(index)
        where current_states[affected.index] = 'member'
          and current_list_ids[affected.index] = assignment.list_id
          and current_profile_ids[affected.index] =
            assignment.assignee_profile_id
      )
  )
  order by item_record.list_id, item_record.id
  for update;

  perform 1
  from public.active_list_participants as access_record
  where exists (
    select 1
    from pg_catalog.generate_subscripts(
      current_list_ids,
      1
    ) as affected(index)
    where current_list_ids[affected.index] = access_record.list_id
      and current_profile_ids[affected.index] =
        access_record.participant_profile_id
  )
  order by access_record.list_id, access_record.participant_profile_id
  for update;

  mutation_time := pg_catalog.clock_timestamp();
  set constraints
    public.active_list_participants_sync_split_identity deferred;
  set constraints
    public.active_list_participants_broadcast_invalidation deferred;

  if pg_catalog.cardinality(current_list_ids) > 0 then
    for affected_index in 1..pg_catalog.cardinality(current_list_ids)
    loop
      new_state := case
        when current_states[affected_index] = 'pending' then 'cancelled'
        when current_owner_ids[affected_index] = caller_id then 'removed'
        else 'left'
      end;

      update public.active_list_participants as access_record
      set state = new_state,
          version = access_record.version + 1,
          state_changed_at = mutation_time
      where access_record.list_id = current_list_ids[affected_index]
        and access_record.participant_profile_id =
          current_profile_ids[affected_index]
      returning access_record.version into new_version;

      new_access_versions := pg_catalog.array_append(
        new_access_versions,
        new_version
      );
    end loop;

    for affected_index in 1..pg_catalog.cardinality(current_list_ids)
    loop
      cleanup_results := pg_catalog.array_append(
        cleanup_results,
        case
          when current_states[affected_index] = 'member' then
            private.cleanup_active_list_profile_links(
              current_list_ids[affected_index],
              current_profile_ids[affected_index],
              mutation_time
            )
          else 0
        end
      );
    end loop;
  end if;

  set constraints
    public.active_list_participants_sync_split_identity immediate;

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
      state_changed_at = mutation_time
  where relationship_row.profile_low_id = low_profile_id
    and relationship_row.profile_high_id = high_profile_id
    and relationship_row.state in ('pending', 'friends');

  update public.user_notifications as notification_record
  set suppressed_at = coalesce(
    notification_record.suppressed_at,
    mutation_time
  )
  where notification_record.relationship_low_id = low_profile_id
    and notification_record.relationship_high_id = high_profile_id
    and notification_record.suppressed_at is null;

  if pg_catalog.cardinality(current_list_ids) > 0 then
    for affected_index in 1..pg_catalog.cardinality(current_list_ids)
    loop
      if current_states[affected_index] = 'member' then
        perform private.suppress_active_list_profile_link_notifications(
          current_list_ids[affected_index],
          current_profile_ids[affected_index],
          mutation_time
        );
      end if;

      update public.user_notifications as notification_record
      set suppressed_at = coalesce(
        notification_record.suppressed_at,
        mutation_time
      )
      where notification_record.active_list_id =
          current_list_ids[affected_index]
        and notification_record.access_participant_id =
          current_profile_ids[affected_index]
        and notification_record.notification_type = 'list_invitation'
        and notification_record.suppressed_at is null;

      if current_owner_ids[affected_index] not in (
          caller_id,
          target_profile_id
        )
        and current_states[affected_index] = 'member'
      then
        insert into public.user_notifications (
          recipient_id,
          actor_id,
          notification_type,
          active_list_id,
          access_participant_id,
          access_version,
          created_at,
          expires_at
        )
        values (
          current_owner_ids[affected_index],
          caller_id,
          'list_member_left',
          current_list_ids[affected_index],
          caller_id,
          new_access_versions[affected_index],
          mutation_time,
          mutation_time + interval '180 days'
        )
        on conflict on constraint user_notifications_access_version_key
        do nothing;
      end if;
    end loop;

    for affected_index in 1..pg_catalog.cardinality(current_list_ids)
    loop
      update public.active_lists as list_record
      set version = list_record.version + 1,
          general_note_version = list_record.general_note_version
            + case
                when (cleanup_results[affected_index] & 2) = 2
                  then 1
                else 0
              end,
          general_note_updated_at = case
            when (cleanup_results[affected_index] & 2) = 2
              then mutation_time
            else list_record.general_note_updated_at
          end,
          updated_at = mutation_time
      where list_record.id = current_list_ids[affected_index];
    end loop;
  end if;

  set constraints
    public.active_list_participants_broadcast_invalidation immediate;
end;
$$;

drop trigger if exists profiles_anonymize_split_participants_before_delete
on public.profiles;
drop trigger if exists profiles_cleanup_item_assignments_before_delete
on public.profiles;
drop trigger if exists profiles_broadcast_invalidation_before_delete
on public.profiles;

create function private.cleanup_active_list_dependents_before_profile_delete()
returns trigger
language plpgsql
volatile
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
    select access_record.list_id
    from public.active_list_participants as access_record
    where access_record.participant_profile_id = old.id
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
    on list_record.id = affected.list_id
   and list_record.owner_id <> old.id;

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

create trigger profiles_cleanup_active_list_dependents_before_delete
before delete
on public.profiles
for each row execute function
  private.cleanup_active_list_dependents_before_profile_delete();

create or replace function public.list_notifications(
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
      when notification_record.notification_type = 'friend_request'
        and relationship_record.state = 'pending'
        and relationship_record.version =
          notification_record.relationship_version
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
        and relationship_record.version =
          notification_record.relationship_version
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
    on relationship_record.profile_low_id =
      notification_record.relationship_low_id
   and relationship_record.profile_high_id =
      notification_record.relationship_high_id
  left join public.active_lists as list_record
    on list_record.id = notification_record.active_list_id
  left join public.active_list_participants as access_record
    on access_record.list_id = notification_record.active_list_id
   and access_record.participant_profile_id =
      notification_record.access_participant_id
  where notification_record.recipient_id = caller_id
    and notification_record.notification_type not in (
      'list_item_assigned',
      'list_note_mentioned'
    )
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
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = caller_id
      ) or (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = notification_record.actor_id
      )
    )
  order by notification_record.created_at desc, notification_record.id desc
  limit page_size;
end;
$$;

create or replace function public.list_notifications_v2(
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
  expected_access_version bigint,
  active_list_item_id uuid,
  active_list_item_name text,
  assignment_item_version bigint
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
      when notification_record.notification_type = 'friend_request'
        and relationship_record.state = 'pending'
        and relationship_record.version =
          notification_record.relationship_version
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
        and relationship_record.version =
          notification_record.relationship_version
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
    end,
    case
      when notification_record.notification_type = 'list_item_assigned'
        then item_record.id
      else null::uuid
    end,
    case
      when notification_record.notification_type = 'list_item_assigned'
        then item_record.name
      else null::text
    end,
    case
      when notification_record.notification_type = 'list_item_assigned'
        then notification_record.assignment_item_version
      else null::bigint
    end
  from public.user_notifications as notification_record
  join public.profiles as actor_profile
    on actor_profile.id = notification_record.actor_id
   and actor_profile.onboarding_completed_at is not null
  left join public.user_relationships as relationship_record
    on relationship_record.profile_low_id =
      notification_record.relationship_low_id
   and relationship_record.profile_high_id =
      notification_record.relationship_high_id
  left join public.active_lists as list_record
    on list_record.id = notification_record.active_list_id
  left join public.active_list_participants as access_record
    on access_record.list_id = notification_record.active_list_id
   and access_record.participant_profile_id =
      notification_record.access_participant_id
  left join public.active_list_items as item_record
    on item_record.list_id = notification_record.active_list_id
   and item_record.id = notification_record.active_list_item_id
  where notification_record.recipient_id = caller_id
    and notification_record.notification_type <>
      'list_note_mentioned'
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
      notification_record.notification_type <> 'list_item_assigned'
      or (
        item_record.id is not null
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          caller_id
        )
      )
    )
    and (
      before_created_at is null
      or (notification_record.created_at, notification_record.id)
        < (before_created_at, before_notification_id)
    )
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = caller_id
      ) or (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = notification_record.actor_id
      )
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
   and access_record.participant_profile_id =
      notification_record.access_participant_id
  where notification_record.recipient_id = caller_id
    and notification_record.notification_type not in (
      'list_item_assigned',
      'list_note_mentioned'
    )
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
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = caller_id
      ) or (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = notification_record.actor_id
      )
    );
  return unread_count;
end;
$$;

create or replace function public.get_unread_notification_count_v2()
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
   and access_record.participant_profile_id =
      notification_record.access_participant_id
  left join public.active_list_items as item_record
    on item_record.list_id = notification_record.active_list_id
   and item_record.id = notification_record.active_list_item_id
  where notification_record.recipient_id = caller_id
    and notification_record.notification_type <>
      'list_note_mentioned'
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
    and (
      notification_record.notification_type <> 'list_item_assigned'
      or (
        item_record.id is not null
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          caller_id
        )
      )
    )
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = caller_id
      ) or (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = notification_record.actor_id
      )
    );
  return unread_count;
end;
$$;

create function public.list_notifications_v3(
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
  expected_access_version bigint,
  active_list_item_id uuid,
  active_list_item_name text,
  assignment_item_version bigint,
  general_note_version bigint
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
      when notification_record.notification_type = 'friend_request'
        and relationship_record.state = 'pending'
        and relationship_record.version =
          notification_record.relationship_version
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
        and relationship_record.version =
          notification_record.relationship_version
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
    end,
    case
      when notification_record.notification_type = 'list_item_assigned'
        then item_record.id
      else null::uuid
    end,
    case
      when notification_record.notification_type = 'list_item_assigned'
        then item_record.name
      else null::text
    end,
    case
      when notification_record.notification_type = 'list_item_assigned'
        then notification_record.assignment_item_version
      else null::bigint
    end,
    case
      when notification_record.notification_type = 'list_note_mentioned'
        then notification_record.general_note_version
      else null::bigint
    end
  from public.user_notifications as notification_record
  join public.profiles as actor_profile
    on actor_profile.id = notification_record.actor_id
   and actor_profile.onboarding_completed_at is not null
  left join public.user_relationships as relationship_record
    on relationship_record.profile_low_id =
      notification_record.relationship_low_id
   and relationship_record.profile_high_id =
      notification_record.relationship_high_id
  left join public.active_lists as list_record
    on list_record.id = notification_record.active_list_id
  left join public.active_list_participants as access_record
    on access_record.list_id = notification_record.active_list_id
   and access_record.participant_profile_id =
      notification_record.access_participant_id
  left join public.active_list_items as item_record
    on item_record.list_id = notification_record.active_list_id
   and item_record.id = notification_record.active_list_item_id
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
      notification_record.notification_type not in (
        'list_item_assigned',
        'list_note_mentioned'
      )
      or (
        notification_record.notification_type = 'list_item_assigned'
        and item_record.id is not null
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          caller_id
        )
      )
      or (
        notification_record.notification_type = 'list_note_mentioned'
        and list_record.id is not null
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          caller_id
        )
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          notification_record.actor_id
        )
      )
    )
    and (
      before_created_at is null
      or (notification_record.created_at, notification_record.id)
        < (before_created_at, before_notification_id)
    )
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = caller_id
      ) or (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = notification_record.actor_id
      )
    )
  order by notification_record.created_at desc, notification_record.id desc
  limit page_size;
end;
$$;

create function public.get_unread_notification_count_v3()
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
   and access_record.participant_profile_id =
      notification_record.access_participant_id
  left join public.active_lists as list_record
    on list_record.id = notification_record.active_list_id
  left join public.active_list_items as item_record
    on item_record.list_id = notification_record.active_list_id
   and item_record.id = notification_record.active_list_item_id
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
    and (
      notification_record.notification_type not in (
        'list_item_assigned',
        'list_note_mentioned'
      )
      or (
        notification_record.notification_type = 'list_item_assigned'
        and item_record.id is not null
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          caller_id
        )
      )
      or (
        notification_record.notification_type = 'list_note_mentioned'
        and list_record.id is not null
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          caller_id
        )
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          notification_record.actor_id
        )
      )
    )
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = caller_id
      ) or (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = notification_record.actor_id
      )
    );
  return unread_count;
end;
$$;

create or replace function public.mark_notifications_read(
  notification_ids uuid[]
)
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
  where notification_record.id = any(notification_ids)
    and notification_record.recipient_id = caller_id
    and notification_record.suppressed_at is null
    and (
      notification_record.expires_at > pg_catalog.now()
      or exists (
        select 1
        from public.active_list_participants as access_record
        where access_record.list_id = notification_record.active_list_id
          and access_record.participant_profile_id =
            notification_record.access_participant_id
          and access_record.state = 'pending'
          and access_record.version = notification_record.access_version
      )
    )
    and (
      notification_record.notification_type not in (
        'list_item_assigned',
        'list_note_mentioned'
      )
      or (
        notification_record.notification_type = 'list_item_assigned'
        and exists (
          select 1
          from public.active_list_items as item_record
          where item_record.list_id = notification_record.active_list_id
            and item_record.id = notification_record.active_list_item_id
        )
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          caller_id
        )
      )
      or (
        notification_record.notification_type = 'list_note_mentioned'
        and exists (
          select 1
          from public.active_lists as list_record
          where list_record.id = notification_record.active_list_id
        )
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          caller_id
        )
        and private.active_list_caller_is_member(
          notification_record.active_list_id,
          notification_record.actor_id
        )
      )
    )
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = notification_record.actor_id
        and pair_block.blocked_id = caller_id
      ) or (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = notification_record.actor_id
      )
    );
end;
$$;

create function private.build_active_list_general_note_export(
  target_list_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when list_record.general_note_text is null then null::jsonb
    else pg_catalog.jsonb_build_object(
      'text', list_record.general_note_text,
      'version', list_record.general_note_version,
      'updated_at', list_record.general_note_updated_at,
      'mentions', private.build_active_list_note_mentions(list_record.id)
    )
  end
  from public.active_lists as list_record
  where list_record.id = target_list_id
$$;

create function public.export_own_account_data_v8()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  base_export jsonb;
  enriched_lists jsonb;
begin
  base_export := public.export_own_account_data_v7();

  select coalesce(
    pg_catalog.jsonb_agg(
      owned_list.document || pg_catalog.jsonb_build_object(
        'general_note',
        private.build_active_list_general_note_export(
          (owned_list.document ->> 'id')::uuid
        )
      )
      order by owned_list.ordinality
    ),
    '[]'::jsonb
  )
  into enriched_lists
  from pg_catalog.jsonb_array_elements(base_export -> 'active_lists')
    with ordinality as owned_list(document, ordinality);

  return pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(base_export, '{schema_version}', '8'::jsonb),
    '{active_lists}',
    enriched_lists
  );
end;
$$;

alter function private.normalize_active_list_general_note(text)
owner to postgres;
alter function private.active_list_note_contains_username(text, text)
owner to postgres;
alter function private.enforce_active_list_note_mention_eligibility()
owner to postgres;
alter function private.build_active_list_note_mentions(uuid)
owner to postgres;
alter function public.get_active_list_general_note(uuid)
owner to postgres;
alter function public.update_active_list_general_note(
  uuid,
  text,
  uuid[],
  bigint
) owner to postgres;
alter function private.cleanup_active_list_profile_link_children(
  uuid,
  uuid,
  timestamptz
) owner to postgres;
alter function private.suppress_active_list_profile_link_notifications(
  uuid,
  uuid,
  timestamptz
) owner to postgres;
alter function private.cleanup_active_list_profile_links(
  uuid,
  uuid,
  timestamptz
) owner to postgres;
alter function private.cleanup_active_list_item_assignments_for_profile(
  uuid,
  uuid,
  timestamptz
) owner to postgres;
alter function private.suppress_item_assignment_notifications_on_block()
owner to postgres;
alter function private.cleanup_active_list_dependents_before_profile_delete()
owner to postgres;
alter function public.list_notifications(integer, timestamptz, uuid)
owner to postgres;
alter function public.list_notifications_v2(integer, timestamptz, uuid)
owner to postgres;
alter function public.get_unread_notification_count()
owner to postgres;
alter function public.get_unread_notification_count_v2()
owner to postgres;
alter function public.list_notifications_v3(integer, timestamptz, uuid)
owner to postgres;
alter function public.get_unread_notification_count_v3()
owner to postgres;
alter function public.mark_notifications_read(uuid[])
owner to postgres;
alter function private.build_active_list_general_note_export(uuid)
owner to postgres;
alter function public.export_own_account_data_v8()
owner to postgres;

revoke all on function private.normalize_active_list_general_note(text)
from public, anon, authenticated, service_role;
revoke all on function
  private.active_list_note_contains_username(text, text)
from public, anon, authenticated, service_role;
revoke all on function
  private.enforce_active_list_note_mention_eligibility()
from public, anon, authenticated, service_role;
revoke all on function private.build_active_list_note_mentions(uuid)
from public, anon, authenticated, service_role;
revoke all on function private.cleanup_active_list_profile_link_children(
  uuid,
  uuid,
  timestamptz
) from public, anon, authenticated, service_role;
revoke all on function
  private.suppress_active_list_profile_link_notifications(
    uuid,
    uuid,
    timestamptz
  )
from public, anon, authenticated, service_role;
revoke all on function private.cleanup_active_list_profile_links(
  uuid,
  uuid,
  timestamptz
) from public, anon, authenticated, service_role;
revoke all on function
  private.cleanup_active_list_item_assignments_for_profile(
    uuid,
    uuid,
    timestamptz
  )
from public, anon, authenticated, service_role;
revoke all on function
  private.suppress_item_assignment_notifications_on_block()
from public, anon, authenticated, service_role;
revoke all on function
  private.cleanup_active_list_dependents_before_profile_delete()
from public, anon, authenticated, service_role;
revoke all on function
  private.build_active_list_general_note_export(uuid)
from public, anon, authenticated, service_role;

revoke all on function public.get_active_list_general_note(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.update_active_list_general_note(
  uuid,
  text,
  uuid[],
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.list_notifications(integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function
  public.list_notifications_v2(integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function
  public.list_notifications_v3(integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count()
from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count_v2()
from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count_v3()
from public, anon, authenticated, service_role;
revoke all on function public.mark_notifications_read(uuid[])
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data_v8()
from public, anon, authenticated, service_role;

grant execute on function public.get_active_list_general_note(uuid)
to authenticated;
grant execute on function public.update_active_list_general_note(
  uuid,
  text,
  uuid[],
  bigint
) to authenticated;
grant execute on function public.list_notifications(integer, timestamptz, uuid)
to authenticated;
grant execute on function
  public.list_notifications_v2(integer, timestamptz, uuid)
to authenticated;
grant execute on function
  public.list_notifications_v3(integer, timestamptz, uuid)
to authenticated;
grant execute on function public.get_unread_notification_count()
to authenticated;
grant execute on function public.get_unread_notification_count_v2()
to authenticated;
grant execute on function public.get_unread_notification_count_v3()
to authenticated;
grant execute on function public.mark_notifications_read(uuid[])
to authenticated;
grant execute on function public.export_own_account_data_v8()
to authenticated;

comment on column public.active_lists.general_note_text is
  'Optional normalized plain-text shared General Note, never copied through templates.';
comment on column public.active_lists.general_note_version is
  'Independent optimistic-concurrency version for General Note text and resolved mention state.';
comment on table public.active_list_note_mentions is
  'RPC-only current stable-profile-ID resolution state for explicit General Note mentions; literal note text remains on cleanup.';
comment on function public.get_active_list_general_note(uuid) is
  'Returns the optional General Note and current live mention projection to an owner or accepted member, including archived lists.';
comment on function public.update_active_list_general_note(
  uuid,
  text,
  uuid[],
  bigint
) is
  'Atomically normalizes and version-checks one active-list General Note plus an explicitly resolved validated mention set.';
comment on function private.cleanup_active_list_profile_links(
  uuid,
  uuid,
  timestamptz
) is
  'Runs combined assignment and resolved-mention child cleanup and returns an effect bitmask; high-level coordinators perform later Split work, suppression, and one parent bump.';
comment on function private.cleanup_active_list_profile_link_children(
  uuid,
  uuid,
  timestamptz
) is
  'Removes one profile assignment and mention child links, advances affected item versions, and returns an assignment/mention effect bitmask without acquiring notification or parent-list rows.';
comment on function
  private.suppress_active_list_profile_link_notifications(
    uuid,
    uuid,
    timestamptz
  ) is
  'Permanently suppresses one profile assignment and General Note notifications after list and Split child work is complete.';
comment on function
  private.cleanup_active_list_item_assignments_for_profile(
    uuid,
    uuid,
    timestamptz
  ) is
  'Compatibility wrapper that delegates combined child cleanup, then preserves legacy suppression and one-parent-bump behavior for any older internal caller.';
comment on function
  private.suppress_item_assignment_notifications_on_block() is
  'Permanently suppresses assignment and General Note mention notifications between a newly blocked pair.';
comment on function
  private.cleanup_active_list_dependents_before_profile_delete() is
  'Coordinates surviving-list cleanup parent-first and suppresses notifications only after Split child mutation, eliminating the former Split-child-before-list lock inversion.';
comment on function public.list_notifications(integer, timestamptz, uuid) is
  'Returns the legacy v1 notification contract while hiding assignment and General Note mention types unknown to older clients.';
comment on function
  public.list_notifications_v2(integer, timestamptz, uuid) is
  'Returns the v2 notification contract including assignments while hiding General Note mention types unknown to v2 clients.';
comment on function
  public.list_notifications_v3(integer, timestamptz, uuid) is
  'Returns bounded caller-owned notifications including privacy-gated assignments and General Note mentions without note text.';
comment on function public.get_unread_notification_count_v3() is
  'Counts unread v3-visible notifications with current access, block, suppression, context, and expiry checks.';
comment on function public.mark_notifications_read(uuid[]) is
  'Idempotently marks a bounded caller-owned visible notification set read with v3 General Note privacy predicates.';
comment on function public.export_own_account_data_v8() is
  'Returns schema-version-8 own data with General Notes and minimal current resolved mentions only under caller-owned lists while preserving versions 1 through 7.';

commit;
