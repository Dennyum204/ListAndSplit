begin;

alter table public.active_list_participants
  drop constraint active_list_participants_state_check;

alter table public.active_list_participants
  add constraint active_list_participants_state_check check (
    state in (
      'pending',
      'member',
      'declined',
      'cancelled',
      'removed',
      'left',
      'owner'
    )
  );

create function private.check_active_list_owner_access_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_list_id uuid;
begin
  if tg_table_name = 'active_lists' then
    target_list_id := new.id;
  elsif tg_op = 'DELETE' then
    target_list_id := old.list_id;
  else
    target_list_id := new.list_id;
  end if;

  if exists (
    select 1
    from public.active_lists as list_record
    join public.active_list_participants as access_record
      on access_record.list_id = list_record.id
    where list_record.id = target_list_id
      and (
        (
          access_record.participant_profile_id = list_record.owner_id
          and access_record.state <> 'owner'
        )
        or (
          access_record.state = 'owner'
          and access_record.participant_profile_id <> list_record.owner_id
        )
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'list owner access state is inconsistent';
  end if;

  return null;
end;
$$;

alter function private.check_active_list_owner_access_consistency()
owner to postgres;

revoke all on function private.check_active_list_owner_access_consistency()
from public, anon, authenticated, service_role;

create constraint trigger active_list_participants_owner_access_consistency
after insert or update or delete on public.active_list_participants
deferrable initially deferred
for each row execute function private.check_active_list_owner_access_consistency();

create constraint trigger active_lists_owner_access_consistency
after update of owner_id on public.active_lists
deferrable initially deferred
for each row execute function private.check_active_list_owner_access_consistency();

alter table public.user_notifications
  drop constraint user_notifications_type_check;

alter table public.user_notifications
  add constraint user_notifications_type_check check (
    notification_type in (
      'friend_request',
      'list_invitation',
      'list_invitation_accepted',
      'list_invitation_declined',
      'list_member_left',
      'list_member_removed',
      'list_ownership_transferred'
    )
  );

create function public.transfer_active_list_ownership(
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

  select owned_list.* into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  perform private.lock_relationship_pair(caller_id, target_profile_id);

  select owned_list.* into list_record
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
    and lock_access.participant_profile_id in (caller_id, target_profile_id)
  order by lock_access.participant_profile_id
  for update;

  select current_access.* into target_access
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

  select current_access.* into previous_owner_access
  from public.active_list_participants as current_access
  where current_access.list_id = target_list_id
    and current_access.participant_profile_id = caller_id;
  previous_owner_has_access := found;

  if previous_owner_has_access and previous_owner_access.state <> 'owner' then
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

  select pg_catalog.count(*) into participant_count_before
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
    ) values (
      target_list_id,
      caller_id,
      'member',
      1,
      mutation_time,
      mutation_time
    ) returning * into previous_owner_access;
  end if;

  select pg_catalog.count(*) into participant_count_after
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
  ) values (
    target_profile_id,
    caller_id,
    'list_ownership_transferred',
    target_list_id,
    caller_id,
    previous_owner_access.version,
    mutation_time,
    mutation_time + interval '180 days'
  );

  return query select
    list_record.id,
    caller_id,
    list_record.owner_id,
    list_record.version,
    previous_owner_access.version,
    target_access.version,
    mutation_time;
end;
$$;

create or replace function public.export_own_account_data()
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
  where access_record.participant_profile_id = caller_id
    and list_record.owner_id <> caller_id
    and access_record.state <> 'owner';

  return base_export || pg_catalog.jsonb_build_object(
    'schema_version', 3,
    'shared_list_access', shared_list_access
  );
end;
$$;

alter function public.transfer_active_list_ownership(uuid, uuid, bigint, bigint)
owner to postgres;
alter function public.export_own_account_data()
owner to postgres;

revoke all on function public.transfer_active_list_ownership(uuid, uuid, bigint, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data()
from public, anon, authenticated, service_role;

grant execute on function public.transfer_active_list_ownership(uuid, uuid, bigint, bigint)
to authenticated;
grant execute on function public.export_own_account_data()
to authenticated;

comment on function private.check_active_list_owner_access_consistency() is
  'Defers validation that retained owner access rows match the authoritative list owner.';
comment on function public.transfer_active_list_ownership(uuid, uuid, bigint, bigint) is
  'Atomically transfers one active list to an exact accepted member while preserving monotonic access versions.';
comment on function public.export_own_account_data() is
  'Returns schema-version-3 own data with privacy-minimal caller-relative shared-list access.';
comment on table public.active_list_participants is
  'RPC-only retained versioned access lineages; owner state preserves transfer version monotonicity.';
comment on function private.reject_active_list_owner_participant() is
  'Prevents inserting or retargeting a participant identity that is already the list owner.';

commit;
