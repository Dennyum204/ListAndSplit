begin;

alter table public.active_list_items
  add constraint active_list_items_list_id_id_key unique (list_id, id);

create table public.active_list_item_assignments (
  list_id uuid not null,
  item_id uuid not null,
  assignee_profile_id uuid not null,
  assigned_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint active_list_item_assignments_pkey primary key (
    list_id,
    item_id,
    assignee_profile_id
  ),
  constraint active_list_item_assignments_item_fkey foreign key (
    list_id,
    item_id
  ) references public.active_list_items (list_id, id) on delete cascade,
  constraint active_list_item_assignments_assignee_fkey foreign key (
    assignee_profile_id
  ) references public.profiles (id) on delete cascade
);

alter table public.active_list_item_assignments owner to postgres;

create index active_list_item_assignments_assignee_idx
on public.active_list_item_assignments (
  assignee_profile_id,
  list_id,
  item_id
);

alter table public.active_list_item_assignments enable row level security;
alter table public.active_list_item_assignments force row level security;

revoke all on table public.active_list_item_assignments
from public, anon, authenticated, service_role;

create policy "active_list_item_assignments_reject_direct_client_access"
on public.active_list_item_assignments
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

alter table public.user_notifications
  drop constraint user_notifications_type_check,
  drop constraint user_notifications_reference_scope_check,
  drop constraint user_notifications_positive_version_check,
  add column active_list_item_id uuid,
  add column assignment_item_version bigint;

alter table public.user_notifications
  add constraint user_notifications_active_list_item_fkey foreign key (
    active_list_id,
    active_list_item_id
  ) references public.active_list_items (list_id, id) on delete cascade,
  add constraint user_notifications_type_check check (
    notification_type in (
      'friend_request',
      'list_invitation',
      'list_invitation_accepted',
      'list_invitation_declined',
      'list_member_left',
      'list_member_removed',
      'list_ownership_transferred',
      'list_item_assigned'
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
    ) or (
      notification_type not in ('friend_request', 'list_item_assigned')
      and relationship_low_id is null
      and relationship_high_id is null
      and relationship_version is null
      and active_list_id is not null
      and access_participant_id is not null
      and access_version is not null
      and active_list_item_id is null
      and assignment_item_version is null
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
    )
  ),
  add constraint user_notifications_positive_version_check check (
    coalesce(
      relationship_version,
      access_version,
      assignment_item_version
    ) > 0
  ),
  add constraint user_notifications_item_assignment_version_key unique (
    active_list_id,
    active_list_item_id,
    recipient_id,
    notification_type,
    assignment_item_version
  );

create function private.build_active_list_item_assignees(
  target_list_id uuid,
  target_item_id uuid
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
        'profile_id', assignment.assignee_profile_id,
        'username', assignee.username,
        'display_name', assignee.display_name,
        'is_owner', list_record.owner_id = assignment.assignee_profile_id,
        'assigned_at', assignment.assigned_at
      )
      order by
        (list_record.owner_id = assignment.assignee_profile_id) desc,
        assignee.username,
        assignment.assignee_profile_id
    ),
    '[]'::jsonb
  )
  from public.active_list_item_assignments as assignment
  join public.active_lists as list_record
    on list_record.id = assignment.list_id
  join public.profiles as assignee
    on assignee.id = assignment.assignee_profile_id
   and assignee.onboarding_completed_at is not null
  where assignment.list_id = target_list_id
    and assignment.item_id = target_item_id;
$$;

create function private.validate_active_list_item_assignee_set(
  target_list_id uuid,
  target_assignee_profile_ids uuid[]
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  submitted_count integer;
  distinct_count integer;
begin
  if target_list_id is null
    or target_assignee_profile_ids is null
    or pg_catalog.array_position(
      target_assignee_profile_ids,
      null::uuid
    ) is not null
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item assignees';
  end if;

  submitted_count := pg_catalog.cardinality(target_assignee_profile_ids);
  select pg_catalog.count(distinct submitted.profile_id)::integer
  into distinct_count
  from pg_catalog.unnest(target_assignee_profile_ids)
    as submitted(profile_id);

  if submitted_count > 20 or distinct_count <> submitted_count then
    raise exception using
      errcode = '22023',
      message = 'invalid list item assignees';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(target_assignee_profile_ids)
      as submitted(profile_id)
    where not exists (
      select 1
      from public.active_lists as list_record
      join public.profiles as candidate
        on candidate.id = submitted.profile_id
       and candidate.onboarding_completed_at is not null
      where list_record.id = target_list_id
        and (
          list_record.owner_id = submitted.profile_id
          or exists (
            select 1
            from public.active_list_participants as access_record
            where access_record.list_id = list_record.id
              and access_record.participant_profile_id = submitted.profile_id
              and access_record.state = 'member'
          )
        )
    )
  ) then
    raise exception using
      errcode = '22023',
      message = 'list item assignee unavailable';
  end if;

  if exists (
    select 1
    from public.user_blocks as pair_block
    where exists (
      select 1
      from pg_catalog.unnest(target_assignee_profile_ids)
        as submitted(profile_id)
      where submitted.profile_id in (
        pair_block.blocker_id,
        pair_block.blocked_id
      )
    )
      and pair_block.blocker_id in (
        select list_record.owner_id
        from public.active_lists as list_record
        where list_record.id = target_list_id
        union all
        select access_record.participant_profile_id
        from public.active_list_participants as access_record
        where access_record.list_id = target_list_id
          and access_record.state = 'member'
      )
      and pair_block.blocked_id in (
        select list_record.owner_id
        from public.active_lists as list_record
        where list_record.id = target_list_id
        union all
        select access_record.participant_profile_id
        from public.active_list_participants as access_record
        where access_record.list_id = target_list_id
          and access_record.state = 'member'
      )
  ) then
    raise exception using
      errcode = '22023',
      message = 'list item assignee unavailable';
  end if;
end;
$$;

create function private.enforce_active_list_item_assignment_eligibility()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.validate_active_list_item_assignee_set(
    new.list_id,
    array[new.assignee_profile_id]
  );
  return new;
end;
$$;

create function private.lock_active_list_item_assignee_participants(
  target_list_id uuid,
  target_assignee_profile_ids uuid[]
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform 1
  from public.active_list_participants as access_record
  where access_record.list_id = target_list_id
    and access_record.participant_profile_id =
      any(target_assignee_profile_ids)
  order by access_record.participant_profile_id
  for update;
end;
$$;

create function private.lock_active_list_item_assignee_profiles(
  target_assignee_profile_ids uuid[]
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform 1
  from public.profiles as assignee
  where assignee.id = any(target_assignee_profile_ids)
  order by assignee.id
  for key share;
end;
$$;

create function private.get_active_list_current_profile_ids(
  target_list_id uuid
)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    pg_catalog.array_agg(
      current_participant.profile_id
      order by current_participant.profile_id
    ),
    '{}'::uuid[]
  )
  from (
    select profile_snapshot_list.owner_id as profile_id
    from public.active_lists as profile_snapshot_list
    where profile_snapshot_list.id = target_list_id
    union
    select profile_snapshot_access.participant_profile_id
    from public.active_list_participants as profile_snapshot_access
    where profile_snapshot_access.list_id = target_list_id
      and profile_snapshot_access.state = 'member'
  ) as current_participant
$$;

create or replace function private.lock_mutable_active_list(
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
  perform private.lock_active_list_item_assignee_profiles(
    array[caller_id]
  );

  select candidate.*
  into list_record
  from public.active_lists as candidate
  where candidate.id = target_list_id
  for update;
  if not found
    or not private.active_list_caller_is_member(
      target_list_id,
      caller_id
    )
  then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;
  return list_record;
end;
$$;

create trigger active_list_item_assignments_enforce_eligibility
before insert or update
on public.active_list_item_assignments
for each row execute function
  private.enforce_active_list_item_assignment_eligibility();

create function public.list_active_list_items_v2(target_list_id uuid)
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
  updated_at timestamptz,
  assignees jsonb
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
    item_record.id,
    item_record.name,
    item_record.quantity_thousandths,
    item_record.unit_code,
    item_record.position,
    item_record.version,
    item_record.completed_at,
    item_record.completed_by,
    item_record.created_at,
    item_record.updated_at,
    private.build_active_list_item_assignees(
      item_record.list_id,
      item_record.id
    )
  from public.active_list_items as item_record
  where item_record.list_id = target_list_id
  order by item_record.position, item_record.id;
end;
$$;

create function public.create_active_list_item_v2(
  target_list_id uuid,
  new_name text,
  creation_request_id uuid,
  expected_list_version bigint,
  target_assignee_profile_ids uuid[],
  new_quantity_thousandths bigint default 1000,
  new_unit_code text default null
)
returns table (
  item_id uuid,
  list_version bigint,
  name text,
  quantity_thousandths bigint,
  unit_code text,
  "position" integer,
  version bigint,
  completed_at timestamptz,
  completed_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
  assignees jsonb
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  canonical_name text := pg_catalog.regexp_replace(
    new_name,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  canonical_assignee_ids uuid[];
  current_assignee_ids uuid[];
  locked_assignee_ids uuid[];
  locked_profile_ids uuid[];
  submitted_assignee_count integer;
  list_record public.active_lists%rowtype;
  item_record public.active_list_items%rowtype;
  existing_item_found boolean;
  next_position integer;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or create_active_list_item_v2.creation_request_id is null
    or expected_list_version is null
    or expected_list_version < 1
    or canonical_name is null
    or pg_catalog.char_length(canonical_name) not between 1 and 120
    or new_quantity_thousandths is null
    or new_quantity_thousandths not between 1 and 999999999
    or (
      new_unit_code is not null
      and new_unit_code not in (
        'piece',
        'kg',
        'g',
        'l',
        'ml',
        'pack',
        'box',
        'bottle',
        'can',
        'bag'
      )
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item creation';
  end if;

  if target_assignee_profile_ids is null
    or pg_catalog.array_position(
      target_assignee_profile_ids,
      null::uuid
    ) is not null
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item assignees';
  end if;

  select
    coalesce(
      pg_catalog.array_agg(
        distinct submitted.profile_id
        order by submitted.profile_id
      ),
      '{}'::uuid[]
    ),
    pg_catalog.count(*)::integer
  into canonical_assignee_ids, submitted_assignee_count
  from pg_catalog.unnest(target_assignee_profile_ids)
    as submitted(profile_id);

  if submitted_assignee_count > 20
    or submitted_assignee_count <>
      pg_catalog.cardinality(canonical_assignee_ids)
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item assignees';
  end if;

  select coalesce(
    pg_catalog.array_agg(
      distinct profile_id
      order by profile_id
    ),
    '{}'::uuid[]
  )
  into locked_profile_ids
  from pg_catalog.unnest(
    canonical_assignee_ids || array[caller_id]
  ) as identity(profile_id);

  perform private.lock_active_list_item_assignee_profiles(
    locked_profile_ids
  );

  list_record := private.lock_mutable_active_list(target_list_id, caller_id);
  select existing.* into item_record
  from public.active_list_items as existing
  where existing.list_id = target_list_id
    and existing.creation_request_id =
      create_active_list_item_v2.creation_request_id
  for update;
  existing_item_found := found;

  if existing_item_found then
    select coalesce(
      pg_catalog.array_agg(
        assignment.assignee_profile_id
        order by assignment.assignee_profile_id
      ),
      '{}'::uuid[]
    )
    into current_assignee_ids
    from public.active_list_item_assignments as assignment
    where assignment.list_id = target_list_id
      and assignment.item_id = item_record.id;

    select coalesce(
      pg_catalog.array_agg(
        distinct participant_id
        order by participant_id
      ),
      '{}'::uuid[]
    )
    into locked_assignee_ids
    from pg_catalog.unnest(
      current_assignee_ids || canonical_assignee_ids
    ) as participant(participant_id);

    perform private.lock_active_list_item_assignee_participants(
      target_list_id,
      locked_assignee_ids
    );
    perform private.validate_active_list_item_assignee_set(
      target_list_id,
      target_assignee_profile_ids
    );

    if item_record.name <> canonical_name
      or item_record.quantity_thousandths <> new_quantity_thousandths
      or item_record.unit_code is distinct from new_unit_code
      or current_assignee_ids <> canonical_assignee_ids
    then
      raise exception using
        errcode = '23505',
        message = 'list item creation request conflict',
        constraint = 'active_list_items_list_creation_request_key';
    end if;

    if expected_list_version not in (
      list_record.version,
      list_record.version - 1
    ) then
      raise exception using errcode = '40001', message = 'list changed';
    end if;

    return query
    select
      item_record.id,
      list_record.version,
      item_record.name,
      item_record.quantity_thousandths,
      item_record.unit_code,
      item_record.position,
      item_record.version,
      item_record.completed_at,
      item_record.completed_by,
      item_record.created_at,
      item_record.updated_at,
      private.build_active_list_item_assignees(
        item_record.list_id,
        item_record.id
      );
    return;
  end if;

  if expected_list_version <> list_record.version then
    raise exception using errcode = '40001', message = 'list changed';
  end if;

  if (
    select pg_catalog.count(*)
    from public.active_list_items as current_item
    where current_item.list_id = target_list_id
  ) >= 200 then
    raise exception using
      errcode = '54000',
      message = 'list item capacity reached';
  end if;

  select coalesce(pg_catalog.max(existing.position), 0) + 1
  into next_position
  from public.active_list_items as existing
  where existing.list_id = target_list_id;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.active_list_items (
    list_id,
    name,
    quantity_thousandths,
    unit_code,
    position,
    creation_request_id,
    created_at,
    updated_at
  ) values (
    target_list_id,
    canonical_name,
    new_quantity_thousandths,
    new_unit_code,
    next_position,
    create_active_list_item_v2.creation_request_id,
    mutation_time,
    mutation_time
  )
  returning * into item_record;

  perform private.lock_active_list_item_assignee_participants(
    target_list_id,
    canonical_assignee_ids
  );
  perform private.validate_active_list_item_assignee_set(
    target_list_id,
    target_assignee_profile_ids
  );

  insert into public.active_list_item_assignments (
    list_id,
    item_id,
    assignee_profile_id,
    assigned_at
  )
  select
    target_list_id,
    item_record.id,
    submitted.profile_id,
    mutation_time
  from pg_catalog.unnest(canonical_assignee_ids)
    as submitted(profile_id);

  insert into public.user_notifications (
    recipient_id,
    actor_id,
    notification_type,
    active_list_id,
    active_list_item_id,
    assignment_item_version,
    created_at,
    expires_at
  )
  select
    submitted.profile_id,
    caller_id,
    'list_item_assigned',
    target_list_id,
    item_record.id,
    item_record.version,
    mutation_time,
    mutation_time + interval '180 days'
  from pg_catalog.unnest(canonical_assignee_ids)
    as submitted(profile_id)
  where submitted.profile_id <> caller_id
  on conflict on constraint
    user_notifications_item_assignment_version_key do nothing;

  update public.active_lists as changed_list
  set version = changed_list.version + 1,
      updated_at = mutation_time
  where changed_list.id = target_list_id
  returning changed_list.* into list_record;

  return query
  select
    item_record.id,
    list_record.version,
    item_record.name,
    item_record.quantity_thousandths,
    item_record.unit_code,
    item_record.position,
    item_record.version,
    item_record.completed_at,
    item_record.completed_by,
    item_record.created_at,
    item_record.updated_at,
    private.build_active_list_item_assignees(
      item_record.list_id,
      item_record.id
    );
end;
$$;

create function public.update_active_list_item_v2(
  target_list_id uuid,
  target_item_id uuid,
  new_name text,
  new_quantity_thousandths bigint,
  new_unit_code text,
  target_assignee_profile_ids uuid[],
  expected_list_version bigint,
  expected_item_version bigint
)
returns table (
  item_id uuid,
  list_version bigint,
  name text,
  quantity_thousandths bigint,
  unit_code text,
  "position" integer,
  version bigint,
  completed_at timestamptz,
  completed_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
  assignees jsonb
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  canonical_name text := pg_catalog.regexp_replace(
    new_name,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  canonical_assignee_ids uuid[];
  current_assignee_ids uuid[];
  locked_assignee_ids uuid[];
  locked_profile_ids uuid[];
  added_assignee_ids uuid[];
  submitted_assignee_count integer;
  list_record public.active_lists%rowtype;
  item_record public.active_list_items%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or target_item_id is null
    or expected_list_version is null
    or expected_list_version < 1
    or expected_item_version is null
    or expected_item_version < 1
    or canonical_name is null
    or pg_catalog.char_length(canonical_name) not between 1 and 120
    or new_quantity_thousandths is null
    or new_quantity_thousandths not between 1 and 999999999
    or (
      new_unit_code is not null
      and new_unit_code not in (
        'piece',
        'kg',
        'g',
        'l',
        'ml',
        'pack',
        'box',
        'bottle',
        'can',
        'bag'
      )
    )
    or target_assignee_profile_ids is null
    or pg_catalog.array_position(
      target_assignee_profile_ids,
      null::uuid
    ) is not null
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item update';
  end if;

  select
    coalesce(
      pg_catalog.array_agg(
        distinct submitted.profile_id
        order by submitted.profile_id
      ),
      '{}'::uuid[]
    ),
    pg_catalog.count(*)::integer
  into canonical_assignee_ids, submitted_assignee_count
  from pg_catalog.unnest(target_assignee_profile_ids)
    as submitted(profile_id);

  if submitted_assignee_count > 20
    or submitted_assignee_count <>
      pg_catalog.cardinality(canonical_assignee_ids)
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item assignees';
  end if;

  select coalesce(
    pg_catalog.array_agg(
      distinct profile_id
      order by profile_id
    ),
    '{}'::uuid[]
  )
  into locked_profile_ids
  from pg_catalog.unnest(
    canonical_assignee_ids || array[caller_id]
  ) as identity(profile_id);

  perform private.lock_active_list_item_assignee_profiles(
    locked_profile_ids
  );

  list_record := private.lock_mutable_active_list(target_list_id, caller_id);
  select existing.* into item_record
  from public.active_list_items as existing
  where existing.id = target_item_id
    and existing.list_id = target_list_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'list item unavailable';
  end if;

  select coalesce(
    pg_catalog.array_agg(
      assignment.assignee_profile_id
      order by assignment.assignee_profile_id
    ),
    '{}'::uuid[]
  )
  into current_assignee_ids
  from public.active_list_item_assignments as assignment
  where assignment.list_id = target_list_id
    and assignment.item_id = target_item_id;

  select coalesce(
    pg_catalog.array_agg(
      distinct participant_id
      order by participant_id
    ),
    '{}'::uuid[]
  )
  into locked_assignee_ids
  from pg_catalog.unnest(
    current_assignee_ids || canonical_assignee_ids
  ) as participant(participant_id);

  perform private.lock_active_list_item_assignee_participants(
    target_list_id,
    locked_assignee_ids
  );
  perform private.validate_active_list_item_assignee_set(
    target_list_id,
    target_assignee_profile_ids
  );

  if item_record.name = canonical_name
    and item_record.quantity_thousandths = new_quantity_thousandths
    and item_record.unit_code is not distinct from new_unit_code
    and current_assignee_ids = canonical_assignee_ids
    and (
      (
        expected_list_version = list_record.version
        and expected_item_version = item_record.version
      ) or (
        expected_list_version = list_record.version - 1
        and expected_item_version = item_record.version - 1
      )
    )
  then
    return query
    select
      item_record.id,
      list_record.version,
      item_record.name,
      item_record.quantity_thousandths,
      item_record.unit_code,
      item_record.position,
      item_record.version,
      item_record.completed_at,
      item_record.completed_by,
      item_record.created_at,
      item_record.updated_at,
      private.build_active_list_item_assignees(
        item_record.list_id,
        item_record.id
      );
    return;
  end if;

  if expected_list_version <> list_record.version
    or expected_item_version <> item_record.version
  then
    raise exception using errcode = '40001', message = 'list item changed';
  end if;

  select coalesce(
    pg_catalog.array_agg(added.profile_id order by added.profile_id),
    '{}'::uuid[]
  )
  into added_assignee_ids
  from (
    select submitted.profile_id
    from pg_catalog.unnest(canonical_assignee_ids)
      as submitted(profile_id)
    except
    select existing.profile_id
    from pg_catalog.unnest(current_assignee_ids)
      as existing(profile_id)
  ) as added;

  mutation_time := pg_catalog.clock_timestamp();

  delete from public.active_list_item_assignments as assignment
  where assignment.list_id = target_list_id
    and assignment.item_id = target_item_id
    and not (
      assignment.assignee_profile_id = any(canonical_assignee_ids)
    );

  insert into public.active_list_item_assignments (
    list_id,
    item_id,
    assignee_profile_id,
    assigned_at
  )
  select
    target_list_id,
    target_item_id,
    added.profile_id,
    mutation_time
  from pg_catalog.unnest(added_assignee_ids) as added(profile_id);

  update public.active_list_items as changed_item
  set name = canonical_name,
      quantity_thousandths = new_quantity_thousandths,
      unit_code = new_unit_code,
      version = changed_item.version + 1,
      updated_at = mutation_time
  where changed_item.id = target_item_id
  returning changed_item.* into item_record;

  insert into public.user_notifications (
    recipient_id,
    actor_id,
    notification_type,
    active_list_id,
    active_list_item_id,
    assignment_item_version,
    created_at,
    expires_at
  )
  select
    added.profile_id,
    caller_id,
    'list_item_assigned',
    target_list_id,
    target_item_id,
    item_record.version,
    mutation_time,
    mutation_time + interval '180 days'
  from pg_catalog.unnest(added_assignee_ids) as added(profile_id)
  where added.profile_id <> caller_id
  on conflict on constraint
    user_notifications_item_assignment_version_key do nothing;

  update public.active_lists as changed_list
  set version = changed_list.version + 1,
      updated_at = mutation_time
  where changed_list.id = target_list_id
  returning changed_list.* into list_record;

  return query
  select
    item_record.id,
    list_record.version,
    item_record.name,
    item_record.quantity_thousandths,
    item_record.unit_code,
    item_record.position,
    item_record.version,
    item_record.completed_at,
    item_record.completed_by,
    item_record.created_at,
    item_record.updated_at,
    private.build_active_list_item_assignees(
      item_record.list_id,
      item_record.id
    );
end;
$$;

create or replace function public.invite_active_list_member(
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
  if target_list_id is null
    or target_profile_id is null
    or target_profile_id = caller_id
    or (
      expected_access_version is not null
      and expected_access_version < 1
    )
  then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  perform private.lock_active_list_item_assignee_profiles(
    array[caller_id, target_profile_id]
  );
  perform private.lock_relationship_pair(caller_id, target_profile_id);

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  if not exists (
    select 1
    from public.user_relationships as relationship_record
    where relationship_record.profile_low_id =
        least(caller_id, target_profile_id)
      and relationship_record.profile_high_id =
        greatest(caller_id, target_profile_id)
      and relationship_record.state = 'friends'
  ) or exists (
    select 1
    from public.user_blocks as pair_block
    where target_profile_id in (
      pair_block.blocker_id,
      pair_block.blocked_id
    )
      and exists (
        select 1
        from (
          select caller_id as profile_id
          union all
          select member_record.participant_profile_id
          from public.active_list_participants as member_record
          where member_record.list_id = target_list_id
            and member_record.state = 'member'
        ) as participant
        where participant.profile_id in (
          pair_block.blocker_id,
          pair_block.blocked_id
        )
      )
  ) then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;

  select current_access.*
  into access_record
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id
  for update;

  if found
    and access_record.state = 'pending'
    and (
      expected_access_version is null
      or expected_access_version in (
        access_record.version,
        access_record.version - 1
      )
    )
  then
    return query
    select
      access_record.participant_profile_id,
      access_record.state,
      access_record.version,
      access_record.created_at,
      access_record.state_changed_at;
    return;
  end if;
  if found and access_record.state = 'member' then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;
  if found
    and expected_access_version is distinct from access_record.version
  then
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
    raise exception using
      errcode = '54000',
      message = 'list participant capacity reached';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  if found then
    update public.active_list_participants as current_access
    set state = 'pending',
        version = current_access.version + 1,
        state_changed_at = mutation_time
    where current_access.list_id = target_list_id
      and current_access.participant_profile_id = target_profile_id
    returning current_access.* into access_record;
  else
    insert into public.active_list_participants (
      list_id,
      participant_profile_id,
      state,
      created_at,
      state_changed_at
    )
    values (
      target_list_id,
      target_profile_id,
      'pending',
      mutation_time,
      mutation_time
    )
    returning * into access_record;
  end if;

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
    'list_invitation',
    target_list_id,
    target_profile_id,
    access_record.version,
    mutation_time,
    mutation_time + interval '180 days'
  )
  on conflict on constraint user_notifications_access_version_key
  do nothing;

  return query
  select
    access_record.participant_profile_id,
    access_record.state,
    access_record.version,
    access_record.created_at,
    access_record.state_changed_at;
end;
$$;

create or replace function public.accept_active_list_invitation(
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
  list_record public.active_lists%rowtype;
  access_record public.active_list_participants%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or expected_access_version is null
    or expected_access_version < 1
  then
    raise exception using
      errcode = '22023',
      message = 'invitation unavailable';
  end if;

  select invited_list.*
  into list_record
  from public.active_lists as invited_list
  where invited_list.id = target_list_id;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'invitation unavailable';
  end if;
  preflight_owner_id := list_record.owner_id;

  perform private.lock_active_list_item_assignee_profiles(
    array[caller_id, preflight_owner_id]
  );
  perform private.lock_relationship_pair(caller_id, preflight_owner_id);

  select invited_list.*
  into list_record
  from public.active_lists as invited_list
  where invited_list.id = target_list_id
  for update;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'invitation unavailable';
  end if;
  if list_record.owner_id <> preflight_owner_id then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;
  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  select current_access.*
  into access_record
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  for update;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'invitation unavailable';
  end if;
  if access_record.state = 'member'
    and expected_access_version = access_record.version - 1
  then
    return access_record.version;
  end if;
  if access_record.state <> 'pending' then
    raise exception using
      errcode = 'P0002',
      message = 'invitation unavailable';
  end if;
  if access_record.version <> expected_access_version then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  if not exists (
    select 1
    from public.user_relationships as relationship_record
    where relationship_record.profile_low_id =
        least(caller_id, list_record.owner_id)
      and relationship_record.profile_high_id =
        greatest(caller_id, list_record.owner_id)
      and relationship_record.state = 'friends'
  ) or exists (
    select 1
    from public.user_blocks as pair_block
    where caller_id in (
      pair_block.blocker_id,
      pair_block.blocked_id
    )
      and exists (
        select 1
        from (
          select list_record.owner_id as profile_id
          union all
          select member_record.participant_profile_id
          from public.active_list_participants as member_record
          where member_record.list_id = target_list_id
            and member_record.state = 'member'
        ) as participant
        where participant.profile_id in (
          pair_block.blocker_id,
          pair_block.blocked_id
        )
      )
  ) then
    raise exception using
      errcode = '22023',
      message = 'invitation unavailable';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_participants as current_access
  set state = 'member',
      version = current_access.version + 1,
      state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  returning current_access.* into access_record;

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
    'list_invitation_accepted',
    target_list_id,
    caller_id,
    access_record.version,
    mutation_time,
    mutation_time + interval '180 days'
  )
  on conflict on constraint user_notifications_access_version_key
  do nothing;
  return access_record.version;
end;
$$;

create or replace function public.decline_active_list_invitation(
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
  list_record public.active_lists%rowtype;
  access_record public.active_list_participants%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or expected_access_version is null
    or expected_access_version < 1
  then
    raise exception using
      errcode = '22023',
      message = 'invitation unavailable';
  end if;

  select invited_list.*
  into list_record
  from public.active_lists as invited_list
  where invited_list.id = target_list_id;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'invitation unavailable';
  end if;
  preflight_owner_id := list_record.owner_id;

  perform private.lock_active_list_item_assignee_profiles(
    array[caller_id, preflight_owner_id]
  );
  perform private.lock_relationship_pair(caller_id, preflight_owner_id);

  select invited_list.*
  into list_record
  from public.active_lists as invited_list
  where invited_list.id = target_list_id
  for update;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'invitation unavailable';
  end if;
  if list_record.owner_id <> preflight_owner_id then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  select current_access.*
  into access_record
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  for update;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'invitation unavailable';
  end if;
  if access_record.state = 'declined'
    and expected_access_version = access_record.version - 1
  then
    return access_record.version;
  end if;
  if access_record.state <> 'pending' then
    raise exception using
      errcode = 'P0002',
      message = 'invitation unavailable';
  end if;
  if access_record.version <> expected_access_version then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_participants as current_access
  set state = 'declined',
      version = current_access.version + 1,
      state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  returning current_access.* into access_record;

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
    'list_invitation_declined',
    target_list_id,
    caller_id,
    access_record.version,
    mutation_time,
    mutation_time + interval '180 days'
  )
  on conflict on constraint user_notifications_access_version_key
  do nothing;
  return access_record.version;
end;
$$;

create or replace function public.transfer_active_list_ownership(
  target_list_id uuid,
  target_profile_id uuid,
  expected_list_version bigint,
  expected_target_access_version bigint
)
returns table (
  list_id uuid,
  previous_owner_profile_id uuid,
  owner_profile_id uuid,
  list_version bigint,
  previous_owner_access_version bigint,
  owner_access_version bigint,
  transferred_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  target_access public.active_list_participants%rowtype;
  previous_owner_access public.active_list_participants%rowtype;
  previous_owner_has_access boolean;
  participant_count_before bigint;
  participant_count_after bigint;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or target_profile_id is null
    or target_profile_id = caller_id
    or expected_list_version is null
    or expected_list_version < 1
    or expected_target_access_version is null
    or expected_target_access_version < 1
  then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  perform private.lock_active_list_item_assignee_profiles(
    array[caller_id, target_profile_id]
  );
  perform private.lock_relationship_pair(caller_id, target_profile_id);

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
  for update;

  if not found or list_record.owner_id <> caller_id then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  if list_record.status <> 'active' then
    raise exception using errcode = '55000', message = 'archived list is read only';
  end if;
  if list_record.version <> expected_list_version then
    raise exception using errcode = '40001', message = 'list changed';
  end if;

  perform 1
  from public.active_list_participants as lock_access
  where lock_access.list_id = target_list_id
    and lock_access.participant_profile_id in (
      caller_id,
      target_profile_id
    )
  order by lock_access.participant_profile_id
  for update;

  select current_access.*
  into target_access
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id;
  if not found then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;
  if target_access.version <> expected_target_access_version then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;
  if target_access.state <> 'member' then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;

  select current_access.*
  into previous_owner_access
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id;
  previous_owner_has_access := found;

  if previous_owner_has_access
    and previous_owner_access.state <> 'owner'
  then
    raise exception using
      errcode = '23514',
      message = 'list owner access state is inconsistent';
  end if;

  if not exists (
    select 1
    from auth.users as target_auth
    join public.profiles as target_profile
      on target_profile.id = target_auth.id
    where target_auth.id = target_profile_id
      and target_auth.email_confirmed_at is not null
      and target_profile.onboarding_completed_at is not null
  ) or exists (
    select 1
    from public.user_blocks as pair_block
    where (
      pair_block.blocker_id = caller_id
      and pair_block.blocked_id = target_profile_id
    ) or (
      pair_block.blocker_id = target_profile_id
      and pair_block.blocked_id = caller_id
    )
  ) then
    raise exception using errcode = '22023', message = 'profile unavailable';
  end if;

  select pg_catalog.count(*)
  into participant_count_before
  from public.active_list_participants as access_record
  where access_record.list_id = target_list_id
    and access_record.state in ('pending', 'member');
  if participant_count_before < 1 or participant_count_before > 19 then
    raise exception using
      errcode = '23514',
      message = 'list participant capacity is inconsistent';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  update public.active_lists as changed_list
  set owner_id = target_profile_id,
      version = changed_list.version + 1,
      updated_at = mutation_time
  where changed_list.id = target_list_id
  returning changed_list.* into list_record;

  update public.active_list_participants as current_access
  set state = 'owner',
      version = current_access.version + 1,
      state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id
  returning current_access.* into target_access;

  if previous_owner_has_access then
    update public.active_list_participants as current_access
    set state = 'member',
        version = current_access.version + 1,
        state_changed_at = mutation_time
    where current_access.list_id = target_list_id
      and current_access.participant_profile_id = caller_id
    returning current_access.* into previous_owner_access;
  else
    insert into public.active_list_participants (
      list_id,
      participant_profile_id,
      state,
      version,
      created_at,
      state_changed_at
    )
    values (
      target_list_id,
      caller_id,
      'member',
      1,
      mutation_time,
      mutation_time
    )
    returning * into previous_owner_access;
  end if;

  select pg_catalog.count(*)
  into participant_count_after
  from public.active_list_participants as access_record
  where access_record.list_id = target_list_id
    and access_record.state in ('pending', 'member');
  if participant_count_after <> participant_count_before then
    raise exception using
      errcode = '23514',
      message = 'list participant capacity changed during transfer';
  end if;

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
    'list_ownership_transferred',
    target_list_id,
    caller_id,
    previous_owner_access.version,
    mutation_time,
    mutation_time + interval '180 days'
  );

  return query
  select
    list_record.id,
    caller_id,
    list_record.owner_id,
    list_record.version,
    previous_owner_access.version,
    target_access.version,
    mutation_time;
end;
$$;

create or replace function public.enable_active_list_split(
  target_list_id uuid,
  new_currency_code text,
  expected_list_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  preflight_profile_ids uuid[];
  current_profile_ids uuid[];
  list_record public.active_lists%rowtype;
  settings_record public.active_list_split_settings%rowtype;
begin
  if target_list_id is null
    or new_currency_code is null
    or new_currency_code not in ('CHF', 'EUR')
    or expected_list_version is null
    or expected_list_version < 1
  then
    raise exception using errcode = '22023', message = 'invalid split setup';
  end if;

  preflight_profile_ids :=
    private.get_active_list_current_profile_ids(target_list_id);

  perform private.lock_active_list_item_assignee_profiles(
    preflight_profile_ids
  );

  select current_list.*
  into list_record
  from public.active_lists as current_list
  where current_list.id = target_list_id
  for update;
  if not found or list_record.owner_id <> caller_id then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  if list_record.status <> 'active' then
    raise exception using errcode = '55000', message = 'archived list is read only';
  end if;
  if list_record.version <> expected_list_version then
    raise exception using errcode = '40001', message = 'list changed';
  end if;

  current_profile_ids :=
    private.get_active_list_current_profile_ids(target_list_id);

  if current_profile_ids is distinct from preflight_profile_ids then
    raise exception using errcode = '40001', message = 'list access changed';
  end if;

  select current_settings.*
  into settings_record
  from public.active_list_split_settings as current_settings
  where current_settings.list_id = target_list_id
  for update;
  if found then
    if settings_record.currency_code <> new_currency_code then
      raise exception using
        errcode = '22023',
        message = 'split is already enabled';
    end if;
    perform private.upsert_active_list_split_participants(target_list_id);
    return private.build_active_list_split_projection(
      target_list_id,
      caller_id
    );
  end if;

  insert into public.active_list_split_settings (
    list_id,
    currency_code
  )
  values (target_list_id, new_currency_code);
  perform private.upsert_active_list_split_participants(target_list_id);
  return private.build_active_list_split_projection(
    target_list_id,
    caller_id
  );
end;
$$;

create function private.cleanup_active_list_item_assignments_for_profile(
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
  affected_item_ids uuid[];
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
      cleanup_active_list_item_assignments_for_profile.target_list_id
    and assignment.assignee_profile_id =
      cleanup_active_list_item_assignments_for_profile.target_profile_id;

  delete from public.active_list_item_assignments as assignment
  where assignment.list_id =
      cleanup_active_list_item_assignments_for_profile.target_list_id
    and assignment.assignee_profile_id =
      cleanup_active_list_item_assignments_for_profile.target_profile_id;

  update public.user_notifications as notification_record
  set suppressed_at = coalesce(
    notification_record.suppressed_at,
    cleanup_active_list_item_assignments_for_profile.mutation_time
  )
  where notification_record.notification_type = 'list_item_assigned'
    and notification_record.active_list_id =
      cleanup_active_list_item_assignments_for_profile.target_list_id
    and notification_record.recipient_id =
      cleanup_active_list_item_assignments_for_profile.target_profile_id
    and notification_record.suppressed_at is null;

  if pg_catalog.cardinality(affected_item_ids) > 0 then
    update public.active_list_items as item_record
    set version = item_record.version + 1,
        updated_at =
          cleanup_active_list_item_assignments_for_profile.mutation_time
    where item_record.list_id =
        cleanup_active_list_item_assignments_for_profile.target_list_id
      and item_record.id = any(affected_item_ids);

    update public.active_lists as list_record
    set version = list_record.version + 1,
        updated_at =
          cleanup_active_list_item_assignments_for_profile.mutation_time
    where list_record.id =
      cleanup_active_list_item_assignments_for_profile.target_list_id;
  end if;
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
      distinct profile_id
      order by profile_id
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
  perform private.cleanup_active_list_item_assignments_for_profile(
    target_list_id,
    target_profile_id,
    mutation_time
  );

  update public.active_list_participants as current_access
  set state = 'removed',
      version = current_access.version + 1,
      state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = target_profile_id
  returning current_access.* into access_record;

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
      distinct profile_id
      order by profile_id
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
  perform private.cleanup_active_list_item_assignments_for_profile(
    target_list_id,
    caller_id,
    mutation_time
  );

  update public.active_list_participants as current_access
  set state = 'left',
      version = current_access.version + 1,
      state_changed_at = mutation_time
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id
  returning current_access.* into access_record;

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
  affected record;
  new_state text;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
  new_version bigint;
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
    select list_record.owner_id
    from public.active_lists as list_record
    where exists (
      select 1
      from public.active_list_participants as access_record
      where access_record.list_id = list_record.id
        and (
          (
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
                and other_access.participant_profile_id =
                  target_profile_id
                and other_access.state = 'member'
            )
          )
        )
    )
    union
    select current_member.participant_profile_id
    from public.active_list_participants as current_member
    join public.active_lists as list_record
      on list_record.id = current_member.list_id
    where current_member.state = 'member'
      and exists (
        select 1
        from public.active_list_participants as access_record
        where access_record.list_id = list_record.id
          and (
            (
              list_record.owner_id = caller_id
              and access_record.participant_profile_id =
                target_profile_id
              and access_record.state in ('pending', 'member')
            ) or (
              list_record.owner_id = target_profile_id
              and access_record.participant_profile_id = caller_id
              and access_record.state in ('pending', 'member')
            ) or (
              list_record.owner_id not in (
                caller_id,
                target_profile_id
              )
              and access_record.participant_profile_id = caller_id
              and access_record.state = 'member'
              and exists (
                select 1
                from public.active_list_participants as other_access
                where other_access.list_id = list_record.id
                  and other_access.participant_profile_id =
                    target_profile_id
                  and other_access.state = 'member'
              )
            )
          )
      )
  ) as identity;

  perform private.lock_active_list_item_assignee_profiles(
    locked_profile_ids
  );
  perform private.lock_relationship_pair(caller_id, target_profile_id);

  perform 1
  from public.active_lists as list_record
  where exists (
    select 1
    from public.active_list_participants as access_record
    where access_record.list_id = list_record.id
      and (
        (
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
      )
  )
  order by list_record.id
  for update;

  perform 1
  from public.active_list_items as item_record
  where exists (
    select 1
    from public.active_list_item_assignments as assignment
    join public.active_list_participants as access_record
      on access_record.list_id = assignment.list_id
     and access_record.participant_profile_id =
       assignment.assignee_profile_id
    join public.active_lists as list_record
      on list_record.id = access_record.list_id
    where assignment.list_id = item_record.list_id
      and assignment.item_id = item_record.id
      and (
        (
          list_record.owner_id = caller_id
          and access_record.participant_profile_id = target_profile_id
          and access_record.state = 'member'
        ) or (
          list_record.owner_id = target_profile_id
          and access_record.participant_profile_id = caller_id
          and access_record.state = 'member'
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
      )
  )
  order by item_record.list_id, item_record.id
  for update;

  perform 1
  from public.active_list_participants as access_record
  join public.active_lists as list_record
    on list_record.id = access_record.list_id
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
  order by access_record.list_id, access_record.participant_profile_id
  for update of access_record;

  if exists (
    select 1
    from public.active_lists as list_record
    join public.active_list_participants as access_record
      on access_record.list_id = list_record.id
    where (
      (
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
    )
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
  ) then
    raise exception using
      errcode = '40001',
      message = 'list access changed';
  end if;

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

  for affected in
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
    order by list_record.id, access_record.participant_profile_id
  loop
    new_state := case
      when affected.state = 'pending' then 'cancelled'
      when affected.owner_id = caller_id then 'removed'
      else 'left'
    end;

    if affected.state = 'member' then
      perform private.cleanup_active_list_item_assignments_for_profile(
        affected.list_id,
        affected.participant_profile_id,
        mutation_time
      );
    end if;

    update public.active_list_participants as access_record
    set state = new_state,
        version = access_record.version + 1,
        state_changed_at = mutation_time
    where access_record.list_id = affected.list_id
      and access_record.participant_profile_id =
        affected.participant_profile_id
    returning access_record.version into new_version;

    update public.user_notifications as notification_record
    set suppressed_at = coalesce(
      notification_record.suppressed_at,
      mutation_time
    )
    where notification_record.active_list_id = affected.list_id
      and notification_record.access_participant_id =
        affected.participant_profile_id
      and notification_record.notification_type = 'list_invitation'
      and notification_record.suppressed_at is null;

    if affected.owner_id not in (caller_id, target_profile_id)
      and affected.state = 'member'
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
        affected.owner_id,
        caller_id,
        'list_member_left',
        affected.list_id,
        caller_id,
        new_version,
        mutation_time,
        mutation_time + interval '180 days'
      )
      on conflict on constraint user_notifications_access_version_key
      do nothing;
    end if;
  end loop;
end;
$$;

create function private.cleanup_active_list_item_assignments_before_profile_delete()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  affected_list_ids uuid[];
  affected record;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  select coalesce(
    pg_catalog.array_agg(
      distinct assignment.list_id
      order by assignment.list_id
    ),
    '{}'::uuid[]
  )
  into affected_list_ids
  from public.active_list_item_assignments as assignment
  join public.active_lists as list_record
    on list_record.id = assignment.list_id
   and list_record.owner_id <> old.id
  where assignment.assignee_profile_id = old.id;

  perform 1
  from public.active_lists as list_record
  where list_record.id = any(affected_list_ids)
  order by list_record.id
  for update;

  perform 1
  from public.active_list_items as item_record
  where item_record.list_id = any(affected_list_ids)
    and exists (
      select 1
      from public.active_list_item_assignments as assignment
      where assignment.list_id = item_record.list_id
        and assignment.item_id = item_record.id
        and assignment.assignee_profile_id = old.id
    )
  order by item_record.list_id, item_record.id
  for update;

  perform 1
  from public.active_list_participants as access_record
  where access_record.list_id = any(affected_list_ids)
    and access_record.participant_profile_id = old.id
  order by access_record.list_id, access_record.participant_profile_id
  for update;

  for affected in
    select
      assignment.list_id,
      pg_catalog.array_agg(
        distinct assignment.item_id
        order by assignment.item_id
      ) as item_ids
    from public.active_list_item_assignments as assignment
    join public.active_lists as list_record
      on list_record.id = assignment.list_id
     and list_record.owner_id <> old.id
    where assignment.assignee_profile_id = old.id
    group by assignment.list_id
    order by assignment.list_id
  loop
    perform private.cleanup_active_list_item_assignments_for_profile(
      affected.list_id,
      old.id,
      mutation_time
    );
  end loop;

  return old;
end;
$$;

create trigger profiles_cleanup_item_assignments_before_delete
before delete
on public.profiles
for each row execute function
  private.cleanup_active_list_item_assignments_before_profile_delete();

create function private.suppress_item_assignment_notifications_on_block()
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
  where notification_record.notification_type = 'list_item_assigned'
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

create trigger user_blocks_suppress_item_assignment_notifications
after insert
on public.user_blocks
for each row execute function
  private.suppress_item_assignment_notifications_on_block();

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
    and notification_record.notification_type <> 'list_item_assigned'
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

create function public.list_notifications_v2(
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
    and notification_record.notification_type <> 'list_item_assigned'
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

create function public.get_unread_notification_count_v2()
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
      notification_record.notification_type <> 'list_item_assigned'
      or (
        exists (
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

create function public.export_own_account_data_v7()
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
  base_export := public.export_own_account_data();

  select coalesce(
    pg_catalog.jsonb_agg(
      owned_list.document || pg_catalog.jsonb_build_object(
        'items',
        coalesce(
          (
            select pg_catalog.jsonb_agg(
              owned_item.document || pg_catalog.jsonb_build_object(
                'assignees',
                private.build_active_list_item_assignees(
                  (owned_list.document ->> 'id')::uuid,
                  (owned_item.document ->> 'id')::uuid
                )
              )
              order by owned_item.ordinality
            )
            from pg_catalog.jsonb_array_elements(
              owned_list.document -> 'items'
            ) with ordinality as owned_item(document, ordinality)
          ),
          '[]'::jsonb
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
    pg_catalog.jsonb_set(base_export, '{schema_version}', '7'::jsonb),
    '{active_lists}',
    enriched_lists
  );
end;
$$;

alter function private.build_active_list_item_assignees(uuid, uuid)
owner to postgres;
alter function private.validate_active_list_item_assignee_set(uuid, uuid[])
owner to postgres;
alter function private.enforce_active_list_item_assignment_eligibility()
owner to postgres;
alter function
  private.lock_active_list_item_assignee_participants(uuid, uuid[])
owner to postgres;
alter function private.lock_active_list_item_assignee_profiles(uuid[])
owner to postgres;
alter function private.get_active_list_current_profile_ids(uuid)
owner to postgres;
alter function private.lock_mutable_active_list(uuid, uuid)
owner to postgres;
alter function public.list_active_list_items_v2(uuid)
owner to postgres;
alter function public.create_active_list_item_v2(
  uuid,
  text,
  uuid,
  bigint,
  uuid[],
  bigint,
  text
) owner to postgres;
alter function public.update_active_list_item_v2(
  uuid,
  uuid,
  text,
  bigint,
  text,
  uuid[],
  bigint,
  bigint
) owner to postgres;
alter function private.cleanup_active_list_item_assignments_for_profile(
  uuid,
  uuid,
  timestamptz
)
owner to postgres;
alter function
  private.cleanup_active_list_item_assignments_before_profile_delete()
owner to postgres;
alter function private.suppress_item_assignment_notifications_on_block()
owner to postgres;
alter function public.list_notifications(integer, timestamptz, uuid)
owner to postgres;
alter function public.list_notifications_v2(integer, timestamptz, uuid)
owner to postgres;
alter function public.get_unread_notification_count()
owner to postgres;
alter function public.get_unread_notification_count_v2()
owner to postgres;
alter function public.mark_notifications_read(uuid[])
owner to postgres;
alter function public.export_own_account_data_v7()
owner to postgres;

revoke all on function private.build_active_list_item_assignees(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function
  private.validate_active_list_item_assignee_set(uuid, uuid[])
from public, anon, authenticated, service_role;
revoke all on function
  private.enforce_active_list_item_assignment_eligibility()
from public, anon, authenticated, service_role;
revoke all on function
  private.lock_active_list_item_assignee_participants(uuid, uuid[])
from public, anon, authenticated, service_role;
revoke all on function
  private.lock_active_list_item_assignee_profiles(uuid[])
from public, anon, authenticated, service_role;
revoke all on function
  private.get_active_list_current_profile_ids(uuid)
from public, anon, authenticated, service_role;
revoke all on function private.lock_mutable_active_list(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function
  private.cleanup_active_list_item_assignments_for_profile(
    uuid,
    uuid,
    timestamptz
  )
from public, anon, authenticated, service_role;
revoke all on function
  private.cleanup_active_list_item_assignments_before_profile_delete()
from public, anon, authenticated, service_role;
revoke all on function
  private.suppress_item_assignment_notifications_on_block()
from public, anon, authenticated, service_role;

revoke all on function public.list_active_list_items_v2(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.create_active_list_item_v2(
  uuid,
  text,
  uuid,
  bigint,
  uuid[],
  bigint,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.update_active_list_item_v2(
  uuid,
  uuid,
  text,
  bigint,
  text,
  uuid[],
  bigint,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.list_notifications(integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function
  public.list_notifications_v2(integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count()
from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count_v2()
from public, anon, authenticated, service_role;
revoke all on function public.mark_notifications_read(uuid[])
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data_v7()
from public, anon, authenticated, service_role;

grant execute on function public.list_active_list_items_v2(uuid)
to authenticated;
grant execute on function public.create_active_list_item_v2(
  uuid,
  text,
  uuid,
  bigint,
  uuid[],
  bigint,
  text
) to authenticated;
grant execute on function public.update_active_list_item_v2(
  uuid,
  uuid,
  text,
  bigint,
  text,
  uuid[],
  bigint,
  bigint
) to authenticated;
grant execute on function public.list_notifications(integer, timestamptz, uuid)
to authenticated;
grant execute on function
  public.list_notifications_v2(integer, timestamptz, uuid)
to authenticated;
grant execute on function public.get_unread_notification_count()
to authenticated;
grant execute on function public.get_unread_notification_count_v2()
to authenticated;
grant execute on function public.mark_notifications_read(uuid[])
to authenticated;
grant execute on function public.export_own_account_data_v7()
to authenticated;

comment on table public.active_list_item_assignments is
  'RPC-only current multi-assignee state for active-list items; rows are removed when the item, assignee, or list access disappears.';
comment on function private.build_active_list_item_assignees(uuid, uuid) is
  'Builds one deterministic allowlisted current-assignee projection for an exact list item.';
comment on function
  private.validate_active_list_item_assignee_set(uuid, uuid[]) is
  'Validates one bounded unique full assignee set against authoritative current list access and block state.';
comment on function
  private.enforce_active_list_item_assignment_eligibility() is
  'Defends assignment-row eligibility for privileged or malformed internal writes.';
comment on function
  private.lock_active_list_item_assignee_participants(uuid, uuid[]) is
  'Locks submitted retained participant rows in deterministic UUID order after the list and item lock phases.';
comment on function
  private.lock_active_list_item_assignee_profiles(uuid[]) is
  'Prelocks all profile identities referenced by assignment or cleanup writes in deterministic UUID order before any list lock, preventing profile-deletion FK deadlocks.';
comment on function
  private.get_active_list_current_profile_ids(uuid) is
  'Builds one deterministic owner-plus-current-members profile snapshot for pre-list profile locking and post-list race checks.';
comment on function private.lock_mutable_active_list(uuid, uuid) is
  'Prelocks the caller profile before locking one active list and rechecking owner-or-member mutation authorization.';
comment on function public.invite_active_list_member(uuid, uuid, bigint) is
  'Prelocks invitation profile identities, then retry-safely creates or reopens one bounded pending invitation.';
comment on function public.accept_active_list_invitation(uuid, bigint) is
  'Prelocks caller and owner identities, rechecks the owner snapshot, and accepts one invitation atomically.';
comment on function public.decline_active_list_invitation(uuid, bigint) is
  'Prelocks caller and owner identities, rechecks the owner snapshot, and declines one invitation atomically.';
comment on function public.transfer_active_list_ownership(
  uuid,
  uuid,
  bigint,
  bigint
) is
  'Prelocks both owner identities before atomically transferring one active list to an accepted member.';
comment on function public.enable_active_list_split(uuid, text, bigint) is
  'Prelocks and rechecks the complete current-participant profile snapshot before initial Split participant persistence.';
comment on function public.list_active_list_items_v2(uuid) is
  'Returns ordered items and deterministic current assignees to an authorized owner or accepted member.';
comment on function public.create_active_list_item_v2(
  uuid,
  text,
  uuid,
  bigint,
  uuid[],
  bigint,
  text
) is
  'Retry-safely creates one item and its validated initial full assignee set atomically.';
comment on function public.update_active_list_item_v2(
  uuid,
  uuid,
  text,
  bigint,
  text,
  uuid[],
  bigint,
  bigint
) is
  'Version-checks item fields and one complete validated assignee set as a single atomic mutation.';
comment on function
  private.cleanup_active_list_item_assignments_for_profile(
    uuid,
    uuid,
    timestamptz
  ) is
  'Removes one profile assignment set after callers acquire deterministic list, item, and participant locks, then suppresses notifications and advances affected versions.';
comment on function
  private.cleanup_active_list_item_assignments_before_profile_delete() is
  'Locks surviving lists, assigned items, and retained participant rows in deterministic order before removing a deleting profile from assignments and advancing authoritative versions.';
comment on function
  private.suppress_item_assignment_notifications_on_block() is
  'Permanently suppresses assignment notifications between a newly blocked pair.';
comment on function public.list_notifications(integer, timestamptz, uuid) is
  'Returns the legacy bounded notification contract while hiding assignment types unknown to older clients.';
comment on function
  public.list_notifications_v2(integer, timestamptz, uuid) is
  'Returns bounded caller-owned notifications including privacy-gated item-assignment context.';
comment on function public.get_unread_notification_count() is
  'Counts legacy-visible unread notifications while hiding assignment types unknown to older clients.';
comment on function public.get_unread_notification_count_v2() is
  'Counts all caller-visible unread notifications including current-access assignment events.';
comment on function public.mark_notifications_read(uuid[]) is
  'Idempotently marks a bounded caller-owned visible notification set read, including access-gated assignment events.';
comment on function public.export_own_account_data_v7() is
  'Returns schema-version-7 own data with current assignments only under caller-owned list items while preserving the public schema-version-6 export unchanged.';

commit;
