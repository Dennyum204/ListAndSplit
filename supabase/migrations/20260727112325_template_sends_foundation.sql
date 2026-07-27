create table public.template_sends (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  sender_id uuid not null,
  recipient_id uuid not null,
  source_template_id uuid,
  snapshot_name text not null,
  snapshot_item_count integer not null,
  state text not null default 'pending',
  version bigint not null default 1,
  accepted_template_id uuid,
  state_changed_at timestamptz not null default pg_catalog.statement_timestamp(),
  suppressed_at timestamptz,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  constraint template_sends_sender_fkey foreign key (sender_id)
    references public.profiles(id) on delete cascade,
  constraint template_sends_recipient_fkey foreign key (recipient_id)
    references public.profiles(id) on delete cascade,
  constraint template_sends_source_fkey foreign key (source_template_id)
    references public.templates(id) on delete set null,
  constraint template_sends_accepted_template_fkey
    foreign key (recipient_id, accepted_template_id)
    references public.templates(owner_id, id)
    on delete set null (accepted_template_id),
  constraint template_sends_distinct_profiles_check
    check (sender_id <> recipient_id),
  constraint template_sends_snapshot_name_check check (
    snapshot_name = pg_catalog.btrim(snapshot_name)
    and pg_catalog.char_length(snapshot_name) >= 1
  ),
  constraint template_sends_snapshot_item_count_check
    check (snapshot_item_count between 0 and 200),
  constraint template_sends_state_check check (
    state in ('pending', 'accepted', 'declined', 'revoked', 'unavailable')
  ),
  constraint template_sends_version_check check (version > 0),
  constraint template_sends_lifecycle_check check (
    (
      state = 'pending'
      and source_template_id is not null
      and accepted_template_id is null
    )
    or (
      state = 'accepted'
    )
    or (
      state in ('declined', 'revoked', 'unavailable')
      and accepted_template_id is null
    )
  ),
  constraint template_sends_time_check check (
    state_changed_at >= created_at
    and updated_at >= created_at
    and (
      suppressed_at is null
      or suppressed_at >= created_at
    )
  ),
  constraint template_sends_participant_id_key
    unique (sender_id, recipient_id, id)
);

create table public.template_send_items (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  template_send_id uuid not null,
  name text not null,
  quantity_thousandths bigint not null,
  position integer not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint template_send_items_send_fkey foreign key (template_send_id)
    references public.template_sends(id) on delete cascade,
  constraint template_send_items_name_check check (
    name = pg_catalog.btrim(name)
    and pg_catalog.char_length(name) between 1 and 120
  ),
  constraint template_send_items_quantity_check check (
    quantity_thousandths between 1 and 999999999
  ),
  constraint template_send_items_position_check check (
    position between 1 and 200
  ),
  constraint template_send_items_send_position_key
    unique (template_send_id, position)
);

create table private.template_send_requests (
  actor_id uuid not null,
  request_id uuid not null,
  operation text not null,
  request_fingerprint bytea not null,
  template_send_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (actor_id, request_id),
  constraint template_send_requests_actor_fkey foreign key (actor_id)
    references public.profiles(id) on delete cascade,
  constraint template_send_requests_send_fkey foreign key (template_send_id)
    references public.template_sends(id) on delete cascade,
  constraint template_send_requests_operation_check check (
    operation in ('send', 'accept', 'decline', 'revoke')
  ),
  constraint template_send_requests_fingerprint_check check (
    pg_catalog.octet_length(request_fingerprint) = 32
  )
);

alter table public.template_sends owner to postgres;
alter table public.template_send_items owner to postgres;
alter table private.template_send_requests owner to postgres;

create unique index template_sends_one_pending_key
on public.template_sends (sender_id, source_template_id, recipient_id)
where state = 'pending';

create index template_sends_recipient_keyset_idx
on public.template_sends (
  recipient_id,
  state_changed_at desc,
  id desc
)
where suppressed_at is null;

create index template_sends_sender_keyset_idx
on public.template_sends (
  sender_id,
  state_changed_at desc,
  id desc
)
where suppressed_at is null;

create index template_sends_source_pending_idx
on public.template_sends (source_template_id, id)
where state = 'pending';

create index template_sends_terminal_retention_idx
on public.template_sends (state_changed_at, id)
where state <> 'pending';

create index template_sends_recipient_accepted_template_idx
on public.template_sends (recipient_id, accepted_template_id)
where accepted_template_id is not null;

create index template_send_items_send_order_idx
on public.template_send_items (template_send_id, position, id);

create index template_send_requests_send_idx
on private.template_send_requests (template_send_id);

alter table public.template_sends enable row level security;
alter table public.template_sends force row level security;
alter table public.template_send_items enable row level security;
alter table public.template_send_items force row level security;
alter table private.template_send_requests enable row level security;
alter table private.template_send_requests force row level security;

revoke all on table public.template_sends
from public, anon, authenticated, service_role;
revoke all on table public.template_send_items
from public, anon, authenticated, service_role;
revoke all on table private.template_send_requests
from public, anon, authenticated, service_role;

create policy "template_sends_reject_direct_client_access"
on public.template_sends
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "template_send_items_reject_direct_client_access"
on public.template_send_items
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "template_send_requests_reject_direct_client_access"
on private.template_send_requests
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create function private.template_send_pair_is_eligible(
  first_profile_id uuid,
  second_profile_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_relationships as relationship_record
    where relationship_record.profile_low_id =
        least(first_profile_id, second_profile_id)
      and relationship_record.profile_high_id =
        greatest(first_profile_id, second_profile_id)
      and relationship_record.state = 'friends'
  )
  and not exists (
    select 1
    from public.user_blocks as block_record
    where (
      block_record.blocker_id = first_profile_id
      and block_record.blocked_id = second_profile_id
    ) or (
      block_record.blocker_id = second_profile_id
      and block_record.blocked_id = first_profile_id
    )
  );
$$;

create function private.template_send_fingerprint(
  source_template_id uuid,
  recipient_profile_id uuid,
  expected_template_version bigint
)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'operation', 'send',
        'source_template_id', source_template_id,
        'recipient_profile_id', recipient_profile_id,
        'expected_template_version', expected_template_version
      )::text,
      'UTF8'
    ),
    'sha256'
  );
$$;

create function private.template_send_action_fingerprint(
  operation text,
  target_template_send_id uuid,
  expected_template_send_version bigint
)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'operation', operation,
        'template_send_id', target_template_send_id,
        'expected_template_send_version', expected_template_send_version
      )::text,
      'UTF8'
    ),
    'sha256'
  );
$$;

create function private.template_send_request_replay(
  caller_id uuid,
  supplied_request_id uuid,
  supplied_operation text,
  supplied_fingerprint bytea
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  existing_request private.template_send_requests%rowtype;
begin
  select request_record.*
  into existing_request
  from private.template_send_requests as request_record
  where request_record.actor_id = caller_id
    and request_record.request_id = supplied_request_id;

  if not found then
    return null;
  end if;

  if existing_request.operation <> supplied_operation
    or existing_request.request_fingerprint <> supplied_fingerprint
  then
    raise exception using
      errcode = '23505',
      message = 'template send request identity conflict';
  end if;

  return existing_request.template_send_id;
end;
$$;

create function private.template_send_source_is_moderated(
  target_template_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.public_template_moderation_restrictions as restriction_record
    where restriction_record.template_id = target_template_id
      and restriction_record.active
  );
$$;

create function private.broadcast_template_send_invalidation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_sender_id uuid := case when tg_op <> 'INSERT' then old.sender_id end;
  old_recipient_id uuid :=
    case when tg_op <> 'INSERT' then old.recipient_id end;
  new_sender_id uuid := case when tg_op <> 'DELETE' then new.sender_id end;
  new_recipient_id uuid :=
    case when tg_op <> 'DELETE' then new.recipient_id end;
begin
  perform private.send_account_invalidations(
    array[
      old_sender_id,
      old_recipient_id,
      new_sender_id,
      new_recipient_id
    ]
  );
  return coalesce(new, old);
end;
$$;

create trigger template_sends_broadcast_invalidation
after insert or update or delete on public.template_sends
for each row execute function private.broadcast_template_send_invalidation();

create function private.reject_template_send_item_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'template send snapshots are immutable';
end;
$$;

create trigger template_send_items_reject_update
before update on public.template_send_items
for each row execute function private.reject_template_send_item_update();

alter table public.user_notifications
  drop constraint user_notifications_type_check,
  drop constraint user_notifications_reference_scope_check,
  drop constraint user_notifications_positive_version_check,
  add column template_send_id uuid,
  add column template_send_version bigint;

alter table public.user_notifications
  add constraint user_notifications_template_send_fkey
    foreign key (template_send_id)
    references public.template_sends(id)
    on delete cascade,
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
      'list_note_mentioned',
      'public_template_taken_down',
      'public_template_restored',
      'template_send_received'
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
      and public_template_id is null
      and public_template_name is null
      and moderation_reason_code is null
      and moderation_event_id is null
      and template_send_id is null
      and template_send_version is null
      and actor_id is not null
    ) or (
      notification_type not in (
        'friend_request',
        'list_item_assigned',
        'list_note_mentioned',
        'public_template_taken_down',
        'public_template_restored',
        'template_send_received'
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
      and public_template_id is null
      and public_template_name is null
      and moderation_reason_code is null
      and moderation_event_id is null
      and template_send_id is null
      and template_send_version is null
      and actor_id is not null
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
      and public_template_id is null
      and public_template_name is null
      and moderation_reason_code is null
      and moderation_event_id is null
      and template_send_id is null
      and template_send_version is null
      and actor_id is not null
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
      and public_template_id is null
      and public_template_name is null
      and moderation_reason_code is null
      and moderation_event_id is null
      and template_send_id is null
      and template_send_version is null
      and actor_id is not null
    ) or (
      notification_type in (
        'public_template_taken_down',
        'public_template_restored'
      )
      and relationship_low_id is null
      and relationship_high_id is null
      and relationship_version is null
      and active_list_id is null
      and access_participant_id is null
      and access_version is null
      and active_list_item_id is null
      and assignment_item_version is null
      and general_note_version is null
      and public_template_id is not null
      and public_template_name is not null
      and public_template_name = pg_catalog.btrim(public_template_name)
      and pg_catalog.char_length(public_template_name) between 1 and 120
      and moderation_reason_code in (
        'spam_scam_deceptive',
        'hate_harassment_bullying',
        'sexual_content',
        'violence_dangerous',
        'illegal_regulated',
        'personal_confidential_information',
        'copyright_trademark',
        'other'
      )
      and moderation_event_id is not null
      and template_send_id is null
      and template_send_version is null
      and actor_id is null
    ) or (
      notification_type = 'template_send_received'
      and relationship_low_id is null
      and relationship_high_id is null
      and relationship_version is null
      and active_list_id is null
      and access_participant_id is null
      and access_version is null
      and active_list_item_id is null
      and assignment_item_version is null
      and general_note_version is null
      and public_template_id is null
      and public_template_name is null
      and moderation_reason_code is null
      and moderation_event_id is null
      and template_send_id is not null
      and template_send_version is not null
      and actor_id is null
    )
  ),
  add constraint user_notifications_positive_version_check check (
    coalesce(
      relationship_version,
      access_version,
      assignment_item_version,
      general_note_version,
      template_send_version
    ) > 0
    or moderation_event_id is not null
  );

create unique index user_notifications_template_send_version_key
on public.user_notifications (
  recipient_id,
  notification_type,
  template_send_id,
  template_send_version
)
where notification_type = 'template_send_received';

create index user_notifications_template_send_idx
on public.user_notifications (template_send_id)
where template_send_id is not null;

create function public.list_eligible_template_send_recipients(
  target_template_id uuid,
  page_size integer default 20,
  after_username text default null,
  after_profile_id uuid default null
)
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
  caller_id uuid := private.require_verified_template_caller();
begin
  if target_template_id is null
    or page_size is null
    or page_size < 1
    or page_size > 50
    or (after_username is null) <> (after_profile_id is null)
  then
    raise exception using
      errcode = '22023',
      message = 'invalid template recipient query';
  end if;

  if not exists (
    select 1
    from public.templates as template_record
    where template_record.id = target_template_id
      and template_record.owner_id = caller_id
  ) or private.template_send_source_is_moderated(target_template_id)
  then
    raise exception using
      errcode = 'P0002',
      message = 'template unavailable';
  end if;

  return query
  select
    friend_profile.id,
    friend_profile.username,
    friend_profile.display_name
  from public.user_relationships as relationship_record
  join public.profiles as friend_profile
    on friend_profile.id = case
      when relationship_record.profile_low_id = caller_id
        then relationship_record.profile_high_id
      else relationship_record.profile_low_id
    end
  where relationship_record.state = 'friends'
    and caller_id in (
      relationship_record.profile_low_id,
      relationship_record.profile_high_id
    )
    and friend_profile.onboarding_completed_at is not null
    and friend_profile.username is not null
    and friend_profile.display_name is not null
    and private.template_send_pair_is_eligible(
      caller_id,
      friend_profile.id
    )
    and (
      after_username is null
      or (
        pg_catalog.lower(friend_profile.username),
        friend_profile.id
      ) > (
        pg_catalog.lower(after_username),
        after_profile_id
      )
    )
  order by pg_catalog.lower(friend_profile.username), friend_profile.id
  limit page_size;
end;
$$;

create function public.send_template_to_friend(
  source_template_id uuid,
  recipient_profile_id uuid,
  expected_template_version bigint,
  request_id uuid
)
returns table (
  template_send_id uuid,
  state text,
  version bigint,
  snapshot_name text,
  snapshot_item_count integer,
  created_at timestamptz,
  state_changed_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  fingerprint bytea;
  replay_send_id uuid;
  source_record public.templates%rowtype;
  new_send public.template_sends%rowtype;
  source_item_count integer;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if source_template_id is null
    or recipient_profile_id is null
    or recipient_profile_id = caller_id
    or expected_template_version is null
    or expected_template_version < 1
    or request_id is null
  then
    raise exception using
      errcode = '22023',
      message = 'invalid template send';
  end if;

  fingerprint := private.template_send_fingerprint(
    source_template_id,
    recipient_profile_id,
    expected_template_version
  );
  replay_send_id := private.template_send_request_replay(
    caller_id,
    request_id,
    'send',
    fingerprint
  );

  if replay_send_id is not null then
    return query
    select
      send_record.id,
      send_record.state,
      send_record.version,
      send_record.snapshot_name,
      send_record.snapshot_item_count,
      send_record.created_at,
      send_record.state_changed_at
    from public.template_sends as send_record
    where send_record.id = replay_send_id
      and send_record.sender_id = caller_id;
    return;
  end if;

  perform private.lock_public_template_moderation_scope(source_template_id);
  perform private.lock_active_list_item_assignee_profiles(
    array[caller_id, recipient_profile_id]
  );
  perform private.lock_relationship_pair(caller_id, recipient_profile_id);

  select template_record.*
  into source_record
  from public.templates as template_record
  where template_record.id = source_template_id
    and template_record.owner_id = caller_id
  for update;

  if not found
    or not exists (
      select 1
      from public.profiles as recipient_profile
      where recipient_profile.id = recipient_profile_id
        and recipient_profile.onboarding_completed_at is not null
    )
  then
    raise exception using
      errcode = 'P0002',
      message = 'template send unavailable';
  end if;

  if source_record.version <> expected_template_version then
    raise exception using
      errcode = '40001',
      message = 'template changed';
  end if;
  if private.template_send_source_is_moderated(source_template_id) then
    raise exception using
      errcode = '42501',
      message = 'template unavailable';
  end if;
  if not private.template_send_pair_is_eligible(
    caller_id,
    recipient_profile_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'friendship required';
  end if;

  replay_send_id := private.template_send_request_replay(
    caller_id,
    request_id,
    'send',
    fingerprint
  );
  if replay_send_id is not null then
    return query
    select
      send_record.id,
      send_record.state,
      send_record.version,
      send_record.snapshot_name,
      send_record.snapshot_item_count,
      send_record.created_at,
      send_record.state_changed_at
    from public.template_sends as send_record
    where send_record.id = replay_send_id
      and send_record.sender_id = caller_id;
    return;
  end if;

  select pg_catalog.count(*)::integer
  into source_item_count
  from public.template_items as item_record
  where item_record.template_id = source_template_id;

  if source_item_count > 200 then
    raise exception using
      errcode = '54000',
      message = 'template exceeds send capacity';
  end if;

  begin
    insert into public.template_sends (
      sender_id,
      recipient_id,
      source_template_id,
      snapshot_name,
      snapshot_item_count,
      state,
      version,
      state_changed_at,
      created_at,
      updated_at
    )
    values (
      caller_id,
      recipient_profile_id,
      source_template_id,
      source_record.name,
      source_item_count,
      'pending',
      1,
      mutation_time,
      mutation_time,
      mutation_time
    )
    returning * into new_send;
  exception
    when unique_violation then
      raise exception using
        errcode = '23505',
        message = 'pending template send already exists';
  end;

  insert into public.template_send_items (
    template_send_id,
    name,
    quantity_thousandths,
    position,
    created_at
  )
  select
    new_send.id,
    item_record.name,
    item_record.quantity_thousandths,
    item_record.position,
    mutation_time
  from public.template_items as item_record
  where item_record.template_id = source_template_id
  order by item_record.position, item_record.id;

  insert into private.template_send_requests (
    actor_id,
    request_id,
    operation,
    request_fingerprint,
    template_send_id,
    created_at
  )
  values (
    caller_id,
    request_id,
    'send',
    fingerprint,
    new_send.id,
    mutation_time
  );

  insert into public.user_notifications (
    recipient_id,
    actor_id,
    notification_type,
    template_send_id,
    template_send_version,
    created_at,
    expires_at
  )
  values (
    recipient_profile_id,
    null,
    'template_send_received',
    new_send.id,
    new_send.version,
    mutation_time,
    mutation_time + interval '180 days'
  );

  return query select
    new_send.id,
    new_send.state,
    new_send.version,
    new_send.snapshot_name,
    new_send.snapshot_item_count,
    new_send.created_at,
    new_send.state_changed_at;
end;
$$;

create function public.list_received_template_sends(
  state_filter text default 'pending',
  page_size integer default 20,
  before_state_changed_at timestamptz default null,
  before_template_send_id uuid default null
)
returns table (
  template_send_id uuid,
  sender_profile_id uuid,
  sender_username text,
  sender_display_name text,
  snapshot_name text,
  snapshot_item_count integer,
  state text,
  version bigint,
  created_at timestamptz,
  state_changed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
begin
  if state_filter not in ('pending', 'history')
    or page_size is null
    or page_size < 1
    or page_size > 50
    or (before_state_changed_at is null) <>
      (before_template_send_id is null)
  then
    raise exception using
      errcode = '22023',
      message = 'invalid received template send query';
  end if;

  return query
  select
    send_record.id,
    sender_profile.id,
    sender_profile.username,
    sender_profile.display_name,
    send_record.snapshot_name,
    send_record.snapshot_item_count,
    send_record.state,
    send_record.version,
    send_record.created_at,
    send_record.state_changed_at
  from public.template_sends as send_record
  join public.profiles as sender_profile
    on sender_profile.id = send_record.sender_id
   and sender_profile.onboarding_completed_at is not null
  where send_record.recipient_id = caller_id
    and send_record.suppressed_at is null
    and (
      (state_filter = 'pending' and send_record.state = 'pending')
      or (state_filter = 'history' and send_record.state <> 'pending')
    )
    and private.template_send_pair_is_eligible(
      send_record.sender_id,
      send_record.recipient_id
    )
    and (
      before_state_changed_at is null
      or (
        send_record.state_changed_at,
        send_record.id
      ) < (
        before_state_changed_at,
        before_template_send_id
      )
    )
  order by send_record.state_changed_at desc, send_record.id desc
  limit page_size;
end;
$$;

create function public.list_sent_template_sends(
  state_filter text default 'pending',
  page_size integer default 20,
  before_state_changed_at timestamptz default null,
  before_template_send_id uuid default null
)
returns table (
  template_send_id uuid,
  recipient_profile_id uuid,
  recipient_username text,
  recipient_display_name text,
  snapshot_name text,
  snapshot_item_count integer,
  state text,
  version bigint,
  created_at timestamptz,
  state_changed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
begin
  if state_filter not in ('pending', 'history')
    or page_size is null
    or page_size < 1
    or page_size > 50
    or (before_state_changed_at is null) <>
      (before_template_send_id is null)
  then
    raise exception using
      errcode = '22023',
      message = 'invalid sent template send query';
  end if;

  return query
  select
    send_record.id,
    recipient_profile.id,
    recipient_profile.username,
    recipient_profile.display_name,
    send_record.snapshot_name,
    send_record.snapshot_item_count,
    send_record.state,
    send_record.version,
    send_record.created_at,
    send_record.state_changed_at
  from public.template_sends as send_record
  join public.profiles as recipient_profile
    on recipient_profile.id = send_record.recipient_id
   and recipient_profile.onboarding_completed_at is not null
  where send_record.sender_id = caller_id
    and send_record.suppressed_at is null
    and (
      (state_filter = 'pending' and send_record.state = 'pending')
      or (state_filter = 'history' and send_record.state <> 'pending')
    )
    and private.template_send_pair_is_eligible(
      send_record.sender_id,
      send_record.recipient_id
    )
    and (
      before_state_changed_at is null
      or (
        send_record.state_changed_at,
        send_record.id
      ) < (
        before_state_changed_at,
        before_template_send_id
      )
    )
  order by send_record.state_changed_at desc, send_record.id desc
  limit page_size;
end;
$$;

create function public.get_received_template_send(
  target_template_send_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  result_document jsonb;
begin
  if target_template_send_id is null then
    raise exception using
      errcode = '22023',
      message = 'invalid template send identifier';
  end if;

  select pg_catalog.jsonb_build_object(
    'template_send_id', send_record.id,
    'sender', pg_catalog.jsonb_build_object(
      'profile_id', sender_profile.id,
      'username', sender_profile.username,
      'display_name', sender_profile.display_name
    ),
    'snapshot_name', send_record.snapshot_name,
    'snapshot_item_count', send_record.snapshot_item_count,
    'state', send_record.state,
    'version', send_record.version,
    'accepted_template_id', send_record.accepted_template_id,
    'created_at', send_record.created_at,
    'state_changed_at', send_record.state_changed_at,
    'items', coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'name', item_record.name,
            'quantity_thousandths', item_record.quantity_thousandths,
            'position', item_record.position
          )
          order by item_record.position, item_record.id
        )
        from public.template_send_items as item_record
        where item_record.template_send_id = send_record.id
      ),
      '[]'::jsonb
    )
  )
  into result_document
  from public.template_sends as send_record
  join public.profiles as sender_profile
    on sender_profile.id = send_record.sender_id
   and sender_profile.onboarding_completed_at is not null
  where send_record.id = target_template_send_id
    and send_record.recipient_id = caller_id
    and send_record.suppressed_at is null
    and private.template_send_pair_is_eligible(
      send_record.sender_id,
      send_record.recipient_id
    );

  if result_document is null then
    raise exception using
      errcode = 'P0002',
      message = 'template send unavailable';
  end if;
  return result_document;
end;
$$;

create function public.accept_template_send(
  target_template_send_id uuid,
  expected_template_send_version bigint,
  request_id uuid
)
returns table (
  template_send_id uuid,
  state text,
  version bigint,
  accepted_template_id uuid,
  state_changed_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  fingerprint bytea;
  replay_send_id uuid;
  preflight_send public.template_sends%rowtype;
  send_record public.template_sends%rowtype;
  copied_template public.templates%rowtype;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if target_template_send_id is null
    or expected_template_send_version is null
    or expected_template_send_version < 1
    or request_id is null
  then
    raise exception using
      errcode = '22023',
      message = 'invalid template send acceptance';
  end if;

  fingerprint := private.template_send_action_fingerprint(
    'accept',
    target_template_send_id,
    expected_template_send_version
  );
  replay_send_id := private.template_send_request_replay(
    caller_id,
    request_id,
    'accept',
    fingerprint
  );
  if replay_send_id is not null then
    return query
    select
      current_send.id,
      current_send.state,
      current_send.version,
      current_send.accepted_template_id,
      current_send.state_changed_at
    from public.template_sends as current_send
    where current_send.id = replay_send_id
      and current_send.recipient_id = caller_id;
    return;
  end if;

  select current_send.*
  into preflight_send
  from public.template_sends as current_send
  where current_send.id = target_template_send_id
    and current_send.recipient_id = caller_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'template send unavailable';
  end if;

  if preflight_send.source_template_id is not null then
    perform private.lock_public_template_moderation_scope(
      preflight_send.source_template_id
    );
  end if;
  perform private.lock_active_list_item_assignee_profiles(
    array[preflight_send.sender_id, preflight_send.recipient_id]
  );
  perform private.lock_relationship_pair(
    preflight_send.sender_id,
    preflight_send.recipient_id
  );
  perform private.lock_template_owner(caller_id);

  select current_send.*
  into send_record
  from public.template_sends as current_send
  where current_send.id = target_template_send_id
    and current_send.recipient_id = caller_id
  for update;

  if not found
    or send_record.suppressed_at is not null
    or not private.template_send_pair_is_eligible(
      send_record.sender_id,
      send_record.recipient_id
    )
    or (
      send_record.source_template_id is not null
      and private.template_send_source_is_moderated(
        send_record.source_template_id
      )
    )
  then
    raise exception using
      errcode = 'P0002',
      message = 'template send unavailable';
  end if;

  replay_send_id := private.template_send_request_replay(
    caller_id,
    request_id,
    'accept',
    fingerprint
  );
  if replay_send_id is not null then
    return query
    select
      current_send.id,
      current_send.state,
      current_send.version,
      current_send.accepted_template_id,
      current_send.state_changed_at
    from public.template_sends as current_send
    where current_send.id = replay_send_id
      and current_send.recipient_id = caller_id;
    return;
  end if;

  if send_record.state <> 'pending' then
    raise exception using
      errcode = '55000',
      message = 'template send is no longer pending';
  end if;
  if send_record.version <> expected_template_send_version then
    raise exception using
      errcode = '40001',
      message = 'template send changed';
  end if;
  if (
    select pg_catalog.count(*)
    from public.templates as template_record
    where template_record.owner_id = caller_id
  ) >= 100 then
    raise exception using
      errcode = '54000',
      message = 'template capacity reached';
  end if;

  insert into public.templates (
    owner_id,
    category_id,
    name,
    version,
    creation_request_id,
    created_at,
    updated_at,
    published_at
  )
  values (
    caller_id,
    null,
    send_record.snapshot_name,
    1,
    pg_catalog.gen_random_uuid(),
    mutation_time,
    mutation_time,
    null
  )
  returning * into copied_template;

  insert into public.template_items (
    template_id,
    name,
    quantity_thousandths,
    position,
    version,
    creation_request_id,
    created_at,
    updated_at
  )
  select
    copied_template.id,
    snapshot_item.name,
    snapshot_item.quantity_thousandths,
    snapshot_item.position,
    1,
    pg_catalog.gen_random_uuid(),
    mutation_time,
    mutation_time
  from public.template_send_items as snapshot_item
  where snapshot_item.template_send_id = send_record.id
  order by snapshot_item.position, snapshot_item.id;

  update public.template_sends as current_send
  set state = 'accepted',
      version = current_send.version + 1,
      accepted_template_id = copied_template.id,
      state_changed_at = mutation_time,
      updated_at = mutation_time
  where current_send.id = send_record.id
  returning * into send_record;

  insert into private.template_send_requests (
    actor_id,
    request_id,
    operation,
    request_fingerprint,
    template_send_id,
    created_at
  )
  values (
    caller_id,
    request_id,
    'accept',
    fingerprint,
    send_record.id,
    mutation_time
  );

  return query select
    send_record.id,
    send_record.state,
    send_record.version,
    send_record.accepted_template_id,
    send_record.state_changed_at;
end;
$$;

create function private.resolve_template_send(
  target_template_send_id uuid,
  expected_template_send_version bigint,
  request_id uuid,
  desired_operation text
)
returns public.template_sends
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  fingerprint bytea;
  replay_send_id uuid;
  preflight_send public.template_sends%rowtype;
  send_record public.template_sends%rowtype;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if target_template_send_id is null
    or expected_template_send_version is null
    or expected_template_send_version < 1
    or request_id is null
    or desired_operation not in ('decline', 'revoke')
  then
    raise exception using
      errcode = '22023',
      message = 'invalid template send resolution';
  end if;

  fingerprint := private.template_send_action_fingerprint(
    desired_operation,
    target_template_send_id,
    expected_template_send_version
  );
  replay_send_id := private.template_send_request_replay(
    caller_id,
    request_id,
    desired_operation,
    fingerprint
  );
  if replay_send_id is not null then
    select current_send.*
    into send_record
    from public.template_sends as current_send
    where current_send.id = replay_send_id
      and (
        (
          desired_operation = 'decline'
          and current_send.recipient_id = caller_id
        )
        or (
          desired_operation = 'revoke'
          and current_send.sender_id = caller_id
        )
      );
    return send_record;
  end if;

  select current_send.*
  into preflight_send
  from public.template_sends as current_send
  where current_send.id = target_template_send_id
    and (
      (
        desired_operation = 'decline'
        and current_send.recipient_id = caller_id
      )
      or (
        desired_operation = 'revoke'
        and current_send.sender_id = caller_id
      )
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'template send unavailable';
  end if;

  perform private.lock_active_list_item_assignee_profiles(
    array[preflight_send.sender_id, preflight_send.recipient_id]
  );
  perform private.lock_relationship_pair(
    preflight_send.sender_id,
    preflight_send.recipient_id
  );

  select current_send.*
  into send_record
  from public.template_sends as current_send
  where current_send.id = target_template_send_id
    and (
      (
        desired_operation = 'decline'
        and current_send.recipient_id = caller_id
      )
      or (
        desired_operation = 'revoke'
        and current_send.sender_id = caller_id
      )
    )
  for update;

  if not found
    or send_record.suppressed_at is not null
    or not private.template_send_pair_is_eligible(
      send_record.sender_id,
      send_record.recipient_id
    )
  then
    raise exception using
      errcode = 'P0002',
      message = 'template send unavailable';
  end if;

  replay_send_id := private.template_send_request_replay(
    caller_id,
    request_id,
    desired_operation,
    fingerprint
  );
  if replay_send_id is not null then
    select current_send.*
    into send_record
    from public.template_sends as current_send
    where current_send.id = replay_send_id;
    return send_record;
  end if;

  if send_record.state <> 'pending' then
    raise exception using
      errcode = '55000',
      message = 'template send is no longer pending';
  end if;
  if send_record.version <> expected_template_send_version then
    raise exception using
      errcode = '40001',
      message = 'template send changed';
  end if;

  update public.template_sends as current_send
  set state = case
        when desired_operation = 'decline' then 'declined'
        else 'revoked'
      end,
      version = current_send.version + 1,
      state_changed_at = mutation_time,
      updated_at = mutation_time
  where current_send.id = send_record.id
  returning * into send_record;

  insert into private.template_send_requests (
    actor_id,
    request_id,
    operation,
    request_fingerprint,
    template_send_id,
    created_at
  )
  values (
    caller_id,
    request_id,
    desired_operation,
    fingerprint,
    send_record.id,
    mutation_time
  );

  return send_record;
end;
$$;

create function public.decline_template_send(
  target_template_send_id uuid,
  expected_template_send_version bigint,
  request_id uuid
)
returns table (
  template_send_id uuid,
  state text,
  version bigint,
  state_changed_at timestamptz
)
language sql
volatile
security definer
set search_path = ''
as $$
  select
    resolved.id,
    resolved.state,
    resolved.version,
    resolved.state_changed_at
  from private.resolve_template_send(
    target_template_send_id,
    expected_template_send_version,
    request_id,
    'decline'
  ) as resolved;
$$;

create function public.revoke_template_send(
  target_template_send_id uuid,
  expected_template_send_version bigint,
  request_id uuid
)
returns table (
  template_send_id uuid,
  state text,
  version bigint,
  state_changed_at timestamptz
)
language sql
volatile
security definer
set search_path = ''
as $$
  select
    resolved.id,
    resolved.state,
    resolved.version,
    resolved.state_changed_at
  from private.resolve_template_send(
    target_template_send_id,
    expected_template_send_version,
    request_id,
    'revoke'
  ) as resolved;
$$;

create function public.list_notifications_v5(
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
  general_note_version bigint,
  public_template_id uuid,
  public_template_name text,
  moderation_reason_code text,
  template_send_id uuid,
  template_send_name text,
  template_send_item_count integer,
  expected_template_send_version bigint
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
      when notification_record.notification_type =
          'template_send_received'
        and send_record.state = 'pending'
        and send_record.version =
          notification_record.template_send_version
        then 'actionable'
      when notification_record.notification_type =
          'template_send_received'
        then send_record.state
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
    end,
    notification_record.public_template_id,
    notification_record.public_template_name,
    notification_record.moderation_reason_code,
    case
      when notification_record.notification_type =
          'template_send_received'
        then send_record.id
      else null::uuid
    end,
    case
      when notification_record.notification_type =
          'template_send_received'
        then send_record.snapshot_name
      else null::text
    end,
    case
      when notification_record.notification_type =
          'template_send_received'
        then send_record.snapshot_item_count
      else null::integer
    end,
    case
      when notification_record.notification_type =
          'template_send_received'
        and send_record.state = 'pending'
        and send_record.version =
          notification_record.template_send_version
        then notification_record.template_send_version
      else null::bigint
    end
  from public.user_notifications as notification_record
  left join public.template_sends as send_record
    on send_record.id = notification_record.template_send_id
   and send_record.recipient_id = caller_id
  left join public.profiles as actor_profile
    on actor_profile.id = coalesce(
      notification_record.actor_id,
      send_record.sender_id
    )
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
      notification_record.notification_type = 'template_send_received'
      or notification_record.expires_at > pg_catalog.now()
      or (
        notification_record.notification_type = 'list_invitation'
        and access_record.state = 'pending'
        and access_record.version = notification_record.access_version
      )
    )
    and (
      notification_record.notification_type in (
        'public_template_taken_down',
        'public_template_restored'
      )
      or (
        notification_record.notification_type = 'template_send_received'
        and send_record.id is not null
        and send_record.suppressed_at is null
        and actor_profile.id is not null
        and private.template_send_pair_is_eligible(
          send_record.sender_id,
          send_record.recipient_id
        )
      )
      or (
        notification_record.notification_type <>
          'template_send_received'
        and actor_profile.id is not null
        and (
          notification_record.notification_type not in (
            'list_item_assigned',
            'list_note_mentioned'
          )
          or (
            notification_record.notification_type =
              'list_item_assigned'
            and item_record.id is not null
            and private.active_list_caller_is_member(
              notification_record.active_list_id,
              caller_id
            )
          )
          or (
            notification_record.notification_type =
              'list_note_mentioned'
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
      )
    )
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
    and (
      notification_record.actor_id is null
      or not exists (
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
    )
  order by notification_record.created_at desc, notification_record.id desc
  limit page_size;
end;
$$;

create function public.get_unread_notification_count_v5()
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
  left join public.template_sends as send_record
    on send_record.id = notification_record.template_send_id
   and send_record.recipient_id = caller_id
  left join public.profiles as actor_profile
    on actor_profile.id = coalesce(
      notification_record.actor_id,
      send_record.sender_id
    )
   and actor_profile.onboarding_completed_at is not null
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
      notification_record.notification_type = 'template_send_received'
      or notification_record.expires_at > pg_catalog.now()
      or (
        notification_record.notification_type = 'list_invitation'
        and access_record.state = 'pending'
        and access_record.version = notification_record.access_version
      )
    )
    and (
      notification_record.notification_type in (
        'public_template_taken_down',
        'public_template_restored'
      )
      or (
        notification_record.notification_type = 'template_send_received'
        and send_record.id is not null
        and send_record.suppressed_at is null
        and actor_profile.id is not null
        and private.template_send_pair_is_eligible(
          send_record.sender_id,
          send_record.recipient_id
        )
      )
      or (
        notification_record.notification_type <>
          'template_send_received'
        and actor_profile.id is not null
        and (
          notification_record.notification_type not in (
            'list_item_assigned',
            'list_note_mentioned'
          )
          or (
            notification_record.notification_type =
              'list_item_assigned'
            and item_record.id is not null
            and private.active_list_caller_is_member(
              notification_record.active_list_id,
              caller_id
            )
          )
          or (
            notification_record.notification_type =
              'list_note_mentioned'
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
      )
    )
    and (
      notification_record.actor_id is null
      or not exists (
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
      (
        notification_record.notification_type =
          'template_send_received'
        and exists (
          select 1
          from public.template_sends as send_record
          where send_record.id = notification_record.template_send_id
            and send_record.recipient_id = caller_id
            and send_record.suppressed_at is null
            and private.template_send_pair_is_eligible(
              send_record.sender_id,
              send_record.recipient_id
            )
        )
      )
      or (
        notification_record.notification_type <>
          'template_send_received'
        and (
          notification_record.expires_at > pg_catalog.now()
          or exists (
            select 1
            from public.active_list_participants as access_record
            where access_record.list_id =
                notification_record.active_list_id
              and access_record.participant_profile_id =
                notification_record.access_participant_id
              and access_record.state = 'pending'
              and access_record.version =
                notification_record.access_version
          )
        )
        and (
          notification_record.notification_type in (
            'public_template_taken_down',
            'public_template_restored'
          )
          or (
            notification_record.actor_id is not null
            and (
              notification_record.notification_type not in (
                'list_item_assigned',
                'list_note_mentioned'
              )
              or (
                notification_record.notification_type =
                  'list_item_assigned'
                and exists (
                  select 1
                  from public.active_list_items as item_record
                  where item_record.list_id =
                      notification_record.active_list_id
                    and item_record.id =
                      notification_record.active_list_item_id
                )
                and private.active_list_caller_is_member(
                  notification_record.active_list_id,
                  caller_id
                )
              )
              or (
                notification_record.notification_type =
                  'list_note_mentioned'
                and exists (
                  select 1
                  from public.active_lists as list_record
                  where list_record.id =
                    notification_record.active_list_id
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
          )
        )
        and (
          notification_record.actor_id is null
          or not exists (
            select 1
            from public.user_blocks as pair_block
            where (
              pair_block.blocker_id = notification_record.actor_id
              and pair_block.blocked_id = caller_id
            ) or (
              pair_block.blocker_id = caller_id
              and pair_block.blocked_id =
                notification_record.actor_id
            )
          )
        )
      )
    );
end;
$$;

create function private.close_template_sends_for_pair(
  first_profile_id uuid,
  second_profile_id uuid,
  mutation_time timestamptz
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  affected_count bigint;
begin
  with affected as (
    update public.template_sends as send_record
    set state = case
          when send_record.state = 'pending' then 'unavailable'
          else send_record.state
        end,
        version = case
          when send_record.state = 'pending'
            then send_record.version + 1
          else send_record.version
        end,
        state_changed_at = case
          when send_record.state = 'pending'
            then mutation_time
          else send_record.state_changed_at
        end,
        suppressed_at = coalesce(
          send_record.suppressed_at,
          mutation_time
        ),
        updated_at = mutation_time
    where (
      send_record.sender_id = first_profile_id
      and send_record.recipient_id = second_profile_id
    ) or (
      send_record.sender_id = second_profile_id
      and send_record.recipient_id = first_profile_id
    )
    returning send_record.id
  )
  select pg_catalog.count(*) into affected_count from affected;

  update public.user_notifications as notification_record
  set suppressed_at = coalesce(
    notification_record.suppressed_at,
    mutation_time
  )
  where notification_record.notification_type =
      'template_send_received'
    and notification_record.template_send_id in (
      select send_record.id
      from public.template_sends as send_record
      where (
        send_record.sender_id = first_profile_id
        and send_record.recipient_id = second_profile_id
      ) or (
        send_record.sender_id = second_profile_id
        and send_record.recipient_id = first_profile_id
      )
    )
    and notification_record.suppressed_at is null;

  return affected_count;
end;
$$;

create function private.close_template_sends_after_friendship_loss()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.state = 'friends' and new.state <> 'friends' then
    perform private.close_template_sends_for_pair(
      new.profile_low_id,
      new.profile_high_id,
      pg_catalog.clock_timestamp()
    );
  end if;
  return new;
end;
$$;

create trigger user_relationships_close_template_sends
after update of state on public.user_relationships
for each row execute function
  private.close_template_sends_after_friendship_loss();

create function private.close_template_sends_after_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.close_template_sends_for_pair(
    new.blocker_id,
    new.blocked_id,
    pg_catalog.clock_timestamp()
  );
  return new;
end;
$$;

create trigger user_blocks_close_template_sends
after insert on public.user_blocks
for each row execute function private.close_template_sends_after_block();

create function private.close_template_sends_before_source_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  update public.template_sends as send_record
  set state = 'unavailable',
      version = send_record.version + 1,
      state_changed_at = mutation_time,
      updated_at = mutation_time
  where send_record.source_template_id = old.id
    and send_record.state = 'pending'
    and exists (
      select 1
      from public.profiles as sender_profile
      where sender_profile.id = send_record.sender_id
    )
    and exists (
      select 1
      from public.profiles as recipient_profile
      where recipient_profile.id = send_record.recipient_id
    );
  return old;
end;
$$;

create trigger templates_close_pending_sends_before_delete
before delete on public.templates
for each row execute function
  private.close_template_sends_before_source_delete();

create function private.suppress_template_sends_after_moderation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if not new.active then
    return new;
  end if;

  update public.template_sends as send_record
  set state = case
        when send_record.state = 'pending' then 'unavailable'
        else send_record.state
      end,
      version = case
        when send_record.state = 'pending'
          then send_record.version + 1
        else send_record.version
      end,
      state_changed_at = case
        when send_record.state = 'pending'
          then mutation_time
        else send_record.state_changed_at
      end,
      suppressed_at = coalesce(
        send_record.suppressed_at,
        mutation_time
      ),
      updated_at = mutation_time
  where send_record.source_template_id = new.template_id;

  update public.user_notifications as notification_record
  set suppressed_at = coalesce(
    notification_record.suppressed_at,
    mutation_time
  )
  where notification_record.notification_type =
      'template_send_received'
    and notification_record.template_send_id in (
      select send_record.id
      from public.template_sends as send_record
      where send_record.source_template_id = new.template_id
    )
    and notification_record.suppressed_at is null;

  return new;
end;
$$;

create trigger moderation_restrictions_suppress_template_sends
after insert or update of active
on private.public_template_moderation_restrictions
for each row execute function
  private.suppress_template_sends_after_moderation();

create function private.maintain_template_send_retention(
  as_of timestamptz default pg_catalog.clock_timestamp()
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  deleted_count bigint;
begin
  if as_of is null then
    raise exception using
      errcode = '22023',
      message = 'invalid retention time';
  end if;

  with deleted as (
    delete from public.template_sends as send_record
    where send_record.state <> 'pending'
      and send_record.state_changed_at <= as_of - interval '180 days'
    returning send_record.id
  )
  select pg_catalog.count(*) into deleted_count from deleted;

  return deleted_count;
end;
$$;

create function public.export_own_account_data_v11()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  base_export jsonb;
  sent_offers jsonb;
  received_offers jsonb;
begin
  base_export := public.export_own_account_data_v10();

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'template_send_id', send_record.id,
        'recipient', pg_catalog.jsonb_build_object(
          'profile_id', recipient_profile.id,
          'username', recipient_profile.username,
          'display_name', recipient_profile.display_name
        ),
        'snapshot_name', send_record.snapshot_name,
        'snapshot_item_count', send_record.snapshot_item_count,
        'state', send_record.state,
        'version', send_record.version,
        'created_at', send_record.created_at,
        'state_changed_at', send_record.state_changed_at
      )
      order by send_record.created_at, send_record.id
    ),
    '[]'::jsonb
  )
  into sent_offers
  from public.template_sends as send_record
  join public.profiles as recipient_profile
    on recipient_profile.id = send_record.recipient_id
  where send_record.sender_id = caller_id
    and send_record.suppressed_at is null
    and private.template_send_pair_is_eligible(
      send_record.sender_id,
      send_record.recipient_id
    );

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'template_send_id', send_record.id,
        'sender', pg_catalog.jsonb_build_object(
          'profile_id', sender_profile.id,
          'username', sender_profile.username,
          'display_name', sender_profile.display_name
        ),
        'snapshot_name', send_record.snapshot_name,
        'snapshot_item_count', send_record.snapshot_item_count,
        'state', send_record.state,
        'version', send_record.version,
        'created_at', send_record.created_at,
        'state_changed_at', send_record.state_changed_at,
        'items', coalesce(
          (
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'name', item_record.name,
                'quantity_thousandths',
                  item_record.quantity_thousandths,
                'position', item_record.position
              )
              order by item_record.position, item_record.id
            )
            from public.template_send_items as item_record
            where item_record.template_send_id = send_record.id
          ),
          '[]'::jsonb
        )
      )
      order by send_record.created_at, send_record.id
    ),
    '[]'::jsonb
  )
  into received_offers
  from public.template_sends as send_record
  join public.profiles as sender_profile
    on sender_profile.id = send_record.sender_id
  where send_record.recipient_id = caller_id
    and send_record.suppressed_at is null
    and private.template_send_pair_is_eligible(
      send_record.sender_id,
      send_record.recipient_id
    );

  return pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(
      pg_catalog.jsonb_set(
        base_export,
        '{schema_version}',
        '11'::jsonb
      ),
      '{sent_template_offers}',
      sent_offers
    ),
    '{received_template_offers}',
    received_offers
  );
end;
$$;

revoke all on function
  public.list_eligible_template_send_recipients(
    uuid,
    integer,
    text,
    uuid
  ),
  public.send_template_to_friend(uuid, uuid, bigint, uuid),
  public.list_received_template_sends(
    text,
    integer,
    timestamptz,
    uuid
  ),
  public.list_sent_template_sends(
    text,
    integer,
    timestamptz,
    uuid
  ),
  public.get_received_template_send(uuid),
  public.accept_template_send(uuid, bigint, uuid),
  public.decline_template_send(uuid, bigint, uuid),
  public.revoke_template_send(uuid, bigint, uuid),
  public.list_notifications_v5(integer, timestamptz, uuid),
  public.get_unread_notification_count_v5(),
  public.export_own_account_data_v11()
from public, anon, authenticated, service_role;

grant execute on function
  public.list_eligible_template_send_recipients(
    uuid,
    integer,
    text,
    uuid
  ),
  public.send_template_to_friend(uuid, uuid, bigint, uuid),
  public.list_received_template_sends(
    text,
    integer,
    timestamptz,
    uuid
  ),
  public.list_sent_template_sends(
    text,
    integer,
    timestamptz,
    uuid
  ),
  public.get_received_template_send(uuid),
  public.accept_template_send(uuid, bigint, uuid),
  public.decline_template_send(uuid, bigint, uuid),
  public.revoke_template_send(uuid, bigint, uuid),
  public.list_notifications_v5(integer, timestamptz, uuid),
  public.get_unread_notification_count_v5(),
  public.export_own_account_data_v11()
to authenticated;

revoke all on function
  private.template_send_pair_is_eligible(uuid, uuid),
  private.template_send_fingerprint(uuid, uuid, bigint),
  private.template_send_action_fingerprint(text, uuid, bigint),
  private.template_send_request_replay(uuid, uuid, text, bytea),
  private.template_send_source_is_moderated(uuid),
  private.broadcast_template_send_invalidation(),
  private.reject_template_send_item_update(),
  private.resolve_template_send(uuid, bigint, uuid, text),
  private.close_template_sends_for_pair(uuid, uuid, timestamptz),
  private.close_template_sends_after_friendship_loss(),
  private.close_template_sends_after_block(),
  private.close_template_sends_before_source_delete(),
  private.suppress_template_sends_after_moderation(),
  private.maintain_template_send_retention(timestamptz)
from public, anon, authenticated, service_role;

comment on table public.template_sends is
  'RPC-only template offers with immutable send-time snapshots and a five-state lifecycle.';
comment on table public.template_send_items is
  'Immutable ordered name-and-quantity snapshot rows owned by one template send.';
comment on table private.template_send_requests is
  'Private payload-bound idempotency ledger for template send mutations.';
comment on function private.broadcast_template_send_invalidation() is
  'Sends opaque private account invalidations to both template-send participants.';
comment on function public.send_template_to_friend(
  uuid,
  uuid,
  bigint,
  uuid
) is
  'Snapshots one owned non-moderated 0-200 item template for one current friend.';
comment on function public.accept_template_send(
  uuid,
  bigint,
  uuid
) is
  'Atomically accepts one pending offer into one independent private Uncategorized copy.';
comment on function private.maintain_template_send_retention(
  timestamptz
) is
  'Idempotently removes only terminal template-send history at least 180 days old; intentionally unscheduled.';
comment on function public.export_own_account_data_v11() is
  'Exports schema v11 with role-specific privacy-safe sent and received template offer projections.';
