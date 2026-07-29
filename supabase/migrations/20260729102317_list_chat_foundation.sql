begin;

create sequence private.active_list_chat_message_position_seq
  as bigint
  increment by 1
  minvalue 1
  no maxvalue
  start with 1
  no cycle;

alter sequence private.active_list_chat_message_position_seq owner to postgres;

create function private.normalize_active_list_chat_body(raw_body text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select nullif(
    pg_catalog.btrim(
      pg_catalog.replace(
        pg_catalog.replace(raw_body, E'\r\n', E'\n'),
        E'\r',
        E'\n'
      ),
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'
    ),
    ''
  )
$$;

create function private.active_list_chat_body_has_only_allowed_controls(
  normalized_body text
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select coalesce(
    not exists (
      select 1
      from pg_catalog.generate_series(
        1,
        pg_catalog.char_length(normalized_body)
      ) as character_offset(position)
      where pg_catalog.ascii(
        pg_catalog.substr(
          normalized_body,
          character_offset.position,
          1
        )
      ) between 0 and 8
        or pg_catalog.ascii(
          pg_catalog.substr(
            normalized_body,
            character_offset.position,
            1
          )
        ) between 11 and 31
        or pg_catalog.ascii(
          pg_catalog.substr(
            normalized_body,
            character_offset.position,
            1
          )
        ) between 127 and 159
    ),
    false
  )
$$;

create table public.active_list_chat_messages (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null,
  message_position bigint not null,
  sender_profile_id uuid,
  body text,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  deleted_at timestamptz,
  deletion_kind text,
  constraint active_list_chat_messages_list_fkey
    foreign key (list_id)
    references public.active_lists(id)
    on delete cascade,
  constraint active_list_chat_messages_sender_fkey
    foreign key (sender_profile_id)
    references public.profiles(id)
    on delete set null,
  constraint active_list_chat_messages_position_key
    unique (message_position),
  constraint active_list_chat_messages_list_id_id_key
    unique (list_id, id),
  constraint active_list_chat_messages_position_check
    check (message_position > 0),
  constraint active_list_chat_messages_body_check
    check (
      body is null
      or (
        body = private.normalize_active_list_chat_body(body)
        and pg_catalog.char_length(body) between 1 and 2000
        and private.active_list_chat_body_has_only_allowed_controls(body)
      )
    ),
  constraint active_list_chat_messages_deletion_kind_check
    check (
      deletion_kind is null
      or deletion_kind in ('sender', 'owner', 'account')
    ),
  constraint active_list_chat_messages_shape_check
    check (
      (
        sender_profile_id is not null
        and body is not null
        and deleted_at is null
        and deletion_kind is null
      ) or (
        sender_profile_id is not null
        and body is null
        and deleted_at is not null
        and deletion_kind in ('sender', 'owner')
      ) or (
        sender_profile_id is null
        and body is null
        and deleted_at is not null
        and deletion_kind = 'account'
      )
    ),
  constraint active_list_chat_messages_deleted_time_check
    check (deleted_at is null or deleted_at >= created_at)
);

alter table public.active_list_chat_messages owner to postgres;
alter table public.active_list_chat_messages enable row level security;
alter table public.active_list_chat_messages force row level security;

create policy active_list_chat_messages_reject_direct_clients
on public.active_list_chat_messages
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create table public.active_list_chat_states (
  list_id uuid not null,
  profile_id uuid not null,
  visible_after_message_position bigint not null,
  last_read_message_position bigint not null,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint active_list_chat_states_pkey primary key (list_id, profile_id),
  constraint active_list_chat_states_list_fkey
    foreign key (list_id)
    references public.active_lists(id)
    on delete cascade,
  constraint active_list_chat_states_profile_fkey
    foreign key (profile_id)
    references public.profiles(id)
    on delete cascade,
  constraint active_list_chat_states_positions_check
    check (
      visible_after_message_position >= 0
      and last_read_message_position >= visible_after_message_position
    )
);

alter table public.active_list_chat_states owner to postgres;
alter table public.active_list_chat_states enable row level security;
alter table public.active_list_chat_states force row level security;

create policy active_list_chat_states_reject_direct_clients
on public.active_list_chat_states
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create table private.active_list_chat_send_requests (
  actor_id uuid not null,
  request_id uuid not null,
  list_id uuid not null,
  message_id uuid not null,
  fingerprint bytea not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint active_list_chat_send_requests_pkey
    primary key (actor_id, request_id),
  constraint active_list_chat_send_requests_actor_fkey
    foreign key (actor_id)
    references public.profiles(id)
    on delete cascade,
  constraint active_list_chat_send_requests_list_fkey
    foreign key (list_id)
    references public.active_lists(id)
    on delete cascade,
  constraint active_list_chat_send_requests_message_fkey
    foreign key (list_id, message_id)
    references public.active_list_chat_messages(list_id, id)
    on delete cascade,
  constraint active_list_chat_send_requests_message_key
    unique (list_id, message_id),
  constraint active_list_chat_send_requests_fingerprint_check
    check (pg_catalog.octet_length(fingerprint) = 32)
);

alter table private.active_list_chat_send_requests owner to postgres;
alter table private.active_list_chat_send_requests enable row level security;
alter table private.active_list_chat_send_requests force row level security;

create policy active_list_chat_send_requests_reject_direct_clients
on private.active_list_chat_send_requests
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create index active_list_chat_messages_list_position_idx
  on public.active_list_chat_messages (list_id, message_position desc);

create index active_list_chat_messages_sender_rate_idx
  on public.active_list_chat_messages (
    list_id,
    sender_profile_id,
    created_at desc
  )
  where sender_profile_id is not null;

create index active_list_chat_messages_retention_idx
  on public.active_list_chat_messages (created_at, message_position);

create index active_list_chat_messages_sender_cleanup_idx
  on public.active_list_chat_messages (
    sender_profile_id,
    list_id,
    message_position
  )
  where sender_profile_id is not null;

create index active_list_chat_states_profile_idx
  on public.active_list_chat_states (profile_id, list_id);

create function private.reject_active_list_chat_message_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
    or new.list_id is distinct from old.list_id
    or new.message_position is distinct from old.message_position
    or new.created_at is distinct from old.created_at
  then
    raise exception using
      errcode = '55000',
      message = 'chat message is immutable';
  end if;

  if new is not distinct from old then
    return new;
  end if;

  if old.sender_profile_id is not null
    and old.body is not null
    and old.deleted_at is null
    and old.deletion_kind is null
    and new.sender_profile_id = old.sender_profile_id
    and new.body is null
    and new.deleted_at is not null
    and new.deletion_kind in ('sender', 'owner')
  then
    return new;
  end if;

  if old.sender_profile_id is not null
    and new.sender_profile_id is null
    and new.body is null
    and new.deleted_at is not null
    and new.deletion_kind = 'account'
  then
    return new;
  end if;

  raise exception using
    errcode = '55000',
    message = 'chat message is immutable';
end;
$$;

create trigger active_list_chat_messages_reject_update
before update on public.active_list_chat_messages
for each row execute function private.reject_active_list_chat_message_update();

create function private.active_list_chat_latest_position(target_list_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    pg_catalog.max(message_record.message_position),
    0
  )
  from public.active_list_chat_messages as message_record
  where message_record.list_id = target_list_id
$$;

create function private.initialize_active_list_chat_owner_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  boundary_position bigint :=
    private.active_list_chat_latest_position(new.id);
begin
  insert into public.active_list_chat_states (
    list_id,
    profile_id,
    visible_after_message_position,
    last_read_message_position
  )
  values (
    new.id,
    new.owner_id,
    boundary_position,
    boundary_position
  )
  on conflict (list_id, profile_id) do nothing;

  return new;
end;
$$;

create trigger active_lists_initialize_chat_owner_state
after insert on public.active_lists
for each row execute function private.initialize_active_list_chat_owner_state();

create function private.sync_active_list_chat_participant_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_has_access boolean := false;
  new_has_access boolean := false;
  target_list_id uuid;
  target_profile_id uuid;
  boundary_position bigint;
begin
  if tg_op = 'INSERT' then
    new_has_access := new.state in ('member', 'owner');
    target_list_id := new.list_id;
    target_profile_id := new.participant_profile_id;
  elsif tg_op = 'DELETE' then
    old_has_access := old.state in ('member', 'owner');
    target_list_id := old.list_id;
    target_profile_id := old.participant_profile_id;
  else
    old_has_access := old.state in ('member', 'owner');
    new_has_access := new.state in ('member', 'owner');
    target_list_id := new.list_id;
    target_profile_id := new.participant_profile_id;
  end if;

  if old_has_access and not new_has_access then
    delete from public.active_list_chat_states as chat_state
    where chat_state.list_id = target_list_id
      and chat_state.profile_id = target_profile_id;
  elsif not old_has_access and new_has_access then
    boundary_position :=
      private.active_list_chat_latest_position(target_list_id);

    insert into public.active_list_chat_states (
      list_id,
      profile_id,
      visible_after_message_position,
      last_read_message_position
    )
    values (
      target_list_id,
      target_profile_id,
      boundary_position,
      boundary_position
    )
    on conflict (list_id, profile_id) do nothing;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger active_list_participants_sync_chat_state
before insert or delete or update of state
on public.active_list_participants
for each row execute function private.sync_active_list_chat_participant_state();

insert into public.active_list_chat_states (
  list_id,
  profile_id,
  visible_after_message_position,
  last_read_message_position
)
select
  current_access.list_id,
  current_access.profile_id,
  0,
  0
from (
  select list_record.id as list_id, list_record.owner_id as profile_id
  from public.active_lists as list_record
  union
  select
    access_record.list_id,
    access_record.participant_profile_id
  from public.active_list_participants as access_record
  where access_record.state in ('member', 'owner')
) as current_access
on conflict (list_id, profile_id) do nothing;

create function private.active_list_chat_send_fingerprint(
  target_list_id uuid,
  normalized_body text
)
returns bytea
language sql
immutable
security invoker
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(
      pg_catalog.jsonb_build_object(
        'operation', 'active-list-chat-send-v1',
        'list_id', target_list_id,
        'body', normalized_body
      )::text,
      'UTF8'
    ),
    'sha256'
  )
$$;

create function private.build_active_list_chat_message(
  target_message_id uuid,
  caller_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'id', message_record.id,
    'message_position', message_record.message_position,
    'body', message_record.body,
    'created_at', message_record.created_at,
    'deleted_at', message_record.deleted_at,
    'deletion_kind', message_record.deletion_kind,
    'sender_username', sender_profile.username,
    'sender_display_name', sender_profile.display_name,
    'is_mine', coalesce(
      message_record.sender_profile_id = caller_id,
      false
    )
  )
  from public.active_list_chat_messages as message_record
  left join public.profiles as sender_profile
    on sender_profile.id = message_record.sender_profile_id
  where message_record.id = target_message_id
$$;

create function private.send_chat_account_invalidations(
  recipient_ids uuid[]
)
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
      'chat_invalidate',
      'account:' || recipient_id::text,
      true
    );
  end loop;
end;
$$;

create function public.list_active_list_chat_messages(
  target_list_id uuid,
  page_size integer default 20,
  before_message_position bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  visibility_boundary bigint;
  messages jsonb;
  has_more boolean;
  next_before_position bigint;
begin
  if not private.active_list_caller_is_member(
    target_list_id,
    caller_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  select chat_state.visible_after_message_position
  into visibility_boundary
  from public.active_list_chat_states as chat_state
  where chat_state.list_id = target_list_id
    and chat_state.profile_id = caller_id;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if page_size is null
    or page_size not between 1 and 50
    or (
      before_message_position is not null
      and before_message_position < 1
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid chat page';
  end if;

  with candidates as (
    select
      message_record.id,
      message_record.message_position,
      message_record.body,
      message_record.created_at,
      message_record.deleted_at,
      message_record.deletion_kind,
      sender_profile.username as sender_username,
      sender_profile.display_name as sender_display_name,
      coalesce(
        message_record.sender_profile_id = caller_id,
        false
      ) as is_mine,
      pg_catalog.row_number() over (
        order by message_record.message_position desc
      ) as ordinal
    from public.active_list_chat_messages as message_record
    left join public.profiles as sender_profile
      on sender_profile.id = message_record.sender_profile_id
    where message_record.list_id = target_list_id
      and message_record.message_position > visibility_boundary
      and (
        before_message_position is null
        or message_record.message_position < before_message_position
      )
    order by message_record.message_position desc
    limit page_size + 1
  )
  select
    coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', candidate.id,
          'message_position', candidate.message_position,
          'body', candidate.body,
          'created_at', candidate.created_at,
          'deleted_at', candidate.deleted_at,
          'deletion_kind', candidate.deletion_kind,
          'sender_username', candidate.sender_username,
          'sender_display_name', candidate.sender_display_name,
          'is_mine', candidate.is_mine
        )
        order by candidate.message_position desc
      ) filter (where candidate.ordinal <= page_size),
      '[]'::jsonb
    ),
    coalesce(
      pg_catalog.bool_or(candidate.ordinal > page_size),
      false
    ),
    case
      when coalesce(
        pg_catalog.bool_or(candidate.ordinal > page_size),
        false
      )
      then pg_catalog.min(candidate.message_position)
        filter (where candidate.ordinal <= page_size)
      else null
    end
  into messages, has_more, next_before_position
  from candidates as candidate;

  return pg_catalog.jsonb_build_object(
    'messages', messages,
    'has_more', has_more,
    'next_before_message_position', next_before_position
  );
end;
$$;

create function public.send_active_list_chat_message(
  target_list_id uuid,
  raw_body text,
  request_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  normalized_body text :=
    private.normalize_active_list_chat_body(raw_body);
  list_record public.active_lists%rowtype;
  chat_state public.active_list_chat_states%rowtype;
  existing_request private.active_list_chat_send_requests%rowtype;
  existing_message public.active_list_chat_messages%rowtype;
  created_message public.active_list_chat_messages%rowtype;
  fingerprint bytea;
  recent_send_count integer;
  message_position bigint;
  mutation_time timestamptz;
  recipient_ids uuid[];
begin
  if not private.active_list_caller_is_member(
    target_list_id,
    caller_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  perform private.lock_active_list_item_assignee_profiles(
    array[caller_id]
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
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;
  if list_record.status <> 'active' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  select current_state.*
  into chat_state
  from public.active_list_chat_states as current_state
  where current_state.list_id = target_list_id
    and current_state.profile_id = caller_id
  for update;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if request_id is null
    or normalized_body is null
    or pg_catalog.char_length(normalized_body) > 2000
    or not private.active_list_chat_body_has_only_allowed_controls(
      normalized_body
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid chat message';
  end if;

  fingerprint := private.active_list_chat_send_fingerprint(
    target_list_id,
    normalized_body
  );

  select request_record.*
  into existing_request
  from private.active_list_chat_send_requests as request_record
  where request_record.actor_id = caller_id
    and request_record.request_id =
      send_active_list_chat_message.request_id
  for update;

  if found then
    if existing_request.fingerprint <> fingerprint
      or existing_request.list_id <> target_list_id
    then
      raise exception using
        errcode = '23505',
        message = 'chat send request conflict',
        constraint = 'active_list_chat_send_requests_pkey';
    end if;

    select message_record.*
    into existing_message
    from public.active_list_chat_messages as message_record
    where message_record.id = existing_request.message_id
      and message_record.list_id = target_list_id
      and message_record.sender_profile_id = caller_id
      and message_record.message_position >
        chat_state.visible_after_message_position
    for update;
    if not found then
      raise exception using
        errcode = 'P0002',
        message = 'list unavailable';
    end if;

    return private.build_active_list_chat_message(
      existing_message.id,
      caller_id
    );
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  select pg_catalog.count(*)::integer
  into recent_send_count
  from public.active_list_chat_messages as message_record
  where message_record.list_id = target_list_id
    and message_record.sender_profile_id = caller_id
    and message_record.created_at >
      mutation_time - interval '60 seconds'
    and message_record.created_at <= mutation_time;

  if recent_send_count >= 20 then
    raise exception using
      errcode = 'P0001',
      message = 'chat rate limit reached';
  end if;

  message_position := pg_catalog.nextval(
    'private.active_list_chat_message_position_seq'::pg_catalog.regclass
  );

  insert into public.active_list_chat_messages (
    list_id,
    message_position,
    sender_profile_id,
    body,
    created_at
  )
  values (
    target_list_id,
    message_position,
    caller_id,
    normalized_body,
    mutation_time
  )
  returning * into created_message;

  insert into private.active_list_chat_send_requests (
    actor_id,
    request_id,
    list_id,
    message_id,
    fingerprint,
    created_at
  )
  values (
    caller_id,
    send_active_list_chat_message.request_id,
    target_list_id,
    created_message.id,
    fingerprint,
    mutation_time
  );

  recipient_ids :=
    private.get_active_list_current_profile_ids(target_list_id);
  perform private.send_chat_account_invalidations(recipient_ids);

  return private.build_active_list_chat_message(
    created_message.id,
    caller_id
  );
end;
$$;

create function public.delete_active_list_chat_message(
  target_list_id uuid,
  target_message_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  chat_state public.active_list_chat_states%rowtype;
  message_record public.active_list_chat_messages%rowtype;
  selected_deletion_kind text;
  mutation_time timestamptz;
begin
  if not private.active_list_caller_is_member(
    target_list_id,
    caller_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  perform private.lock_active_list_item_assignee_profiles(
    array[caller_id]
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
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;
  if list_record.status <> 'active' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  select current_state.*
  into chat_state
  from public.active_list_chat_states as current_state
  where current_state.list_id = target_list_id
    and current_state.profile_id = caller_id
  for update;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if target_message_id is null then
    raise exception using
      errcode = '22023',
      message = 'invalid chat message';
  end if;

  select candidate_message.*
  into message_record
  from public.active_list_chat_messages as candidate_message
  where candidate_message.id = target_message_id
    and candidate_message.list_id = target_list_id
    and candidate_message.message_position >
      chat_state.visible_after_message_position
  for update;
  if not found
    or (
      message_record.sender_profile_id is distinct from caller_id
      and list_record.owner_id <> caller_id
    )
  then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if message_record.deletion_kind is not null then
    return private.build_active_list_chat_message(
      message_record.id,
      caller_id
    );
  end if;

  selected_deletion_kind := case
    when message_record.sender_profile_id = caller_id then 'sender'
    else 'owner'
  end;
  mutation_time := pg_catalog.clock_timestamp();

  update public.active_list_chat_messages as changed_message
  set body = null,
      deleted_at = mutation_time,
      deletion_kind = selected_deletion_kind
  where changed_message.id = message_record.id
  returning changed_message.* into message_record;

  perform private.send_chat_account_invalidations(
    private.get_active_list_current_profile_ids(target_list_id)
  );

  return private.build_active_list_chat_message(
    message_record.id,
    caller_id
  );
end;
$$;

create function public.mark_active_list_chat_read(
  target_list_id uuid,
  through_message_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  chat_state public.active_list_chat_states%rowtype;
  target_position bigint;
  mutation_time timestamptz;
begin
  if not private.active_list_caller_is_member(
    target_list_id,
    caller_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  perform private.lock_active_list_item_assignee_profiles(
    array[caller_id]
  );

  perform 1
  from public.active_lists as candidate_list
  where candidate_list.id = target_list_id
  for update;
  if not found
    or not private.active_list_caller_is_member(
      target_list_id,
      caller_id
    )
  then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  select current_state.*
  into chat_state
  from public.active_list_chat_states as current_state
  where current_state.list_id = target_list_id
    and current_state.profile_id = caller_id
  for update;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if through_message_id is null then
    raise exception using
      errcode = '22023',
      message = 'invalid chat cursor';
  end if;

  select message_record.message_position
  into target_position
  from public.active_list_chat_messages as message_record
  where message_record.id = through_message_id
    and message_record.list_id = target_list_id
    and message_record.message_position >
      chat_state.visible_after_message_position
  for update;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if target_position <= chat_state.last_read_message_position then
    return pg_catalog.jsonb_build_object(
      'last_read_message_position',
      chat_state.last_read_message_position,
      'changed',
      false
    );
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_chat_states as changed_state
  set last_read_message_position = target_position,
      updated_at = mutation_time
  where changed_state.list_id = target_list_id
    and changed_state.profile_id = caller_id
  returning changed_state.* into chat_state;

  perform private.send_chat_account_invalidations(array[caller_id]);

  return pg_catalog.jsonb_build_object(
    'last_read_message_position',
    chat_state.last_read_message_position,
    'changed',
    true
  );
end;
$$;

create function public.get_active_list_chat_unread_count(
  target_list_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  chat_state public.active_list_chat_states%rowtype;
  bounded_count integer;
begin
  if not private.active_list_caller_is_member(
    target_list_id,
    caller_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  select current_state.*
  into chat_state
  from public.active_list_chat_states as current_state
  where current_state.list_id = target_list_id
    and current_state.profile_id = caller_id;
  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  select pg_catalog.count(*)::integer
  into bounded_count
  from (
    select 1
    from public.active_list_chat_messages as message_record
    where message_record.list_id = target_list_id
      and message_record.message_position >
        chat_state.visible_after_message_position
      and message_record.message_position >
        chat_state.last_read_message_position
      and message_record.sender_profile_id is not null
      and message_record.sender_profile_id <> caller_id
      and message_record.body is not null
      and message_record.deletion_kind is null
    order by message_record.message_position
    limit 100
  ) as unread_message;

  return pg_catalog.jsonb_build_object(
    'count', bounded_count,
    'is_capped', bounded_count = 100
  );
end;
$$;

create function private.maintain_active_list_chat_retention(
  as_of timestamptz default pg_catalog.clock_timestamp(),
  batch_size integer default 500
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  candidate_message_ids uuid[];
  candidate_list_ids uuid[];
  deleted_list_ids uuid[];
  invalidation_recipient_ids uuid[];
  deleted_count bigint := 0;
begin
  if as_of is null
    or batch_size is null
    or batch_size not between 1 and 1000
  then
    raise exception using
      errcode = '22023',
      message = 'invalid chat retention request';
  end if;

  select coalesce(
    pg_catalog.array_agg(
      candidate.id
      order by candidate.created_at, candidate.message_position
    ),
    '{}'::uuid[]
  )
  into candidate_message_ids
  from (
    select
      message_record.id,
      message_record.created_at,
      message_record.message_position
    from public.active_list_chat_messages as message_record
    where message_record.created_at <= as_of - interval '365 days'
    order by message_record.created_at, message_record.message_position
    limit batch_size
  ) as candidate;

  if pg_catalog.cardinality(candidate_message_ids) = 0 then
    return 0;
  end if;

  select coalesce(
    pg_catalog.array_agg(
      distinct message_record.list_id
      order by message_record.list_id
    ),
    '{}'::uuid[]
  )
  into candidate_list_ids
  from public.active_list_chat_messages as message_record
  where message_record.id = any(candidate_message_ids);

  perform 1
  from public.active_lists as list_record
  where list_record.id = any(candidate_list_ids)
  order by list_record.id
  for update;

  perform 1
  from public.active_list_chat_messages as message_record
  where message_record.id = any(candidate_message_ids)
  order by message_record.list_id, message_record.message_position
  for update;

  with deleted as (
    delete from public.active_list_chat_messages as message_record
    where message_record.id = any(candidate_message_ids)
      and message_record.created_at <= as_of - interval '365 days'
    returning message_record.list_id
  )
  select
    pg_catalog.count(*),
    coalesce(
      pg_catalog.array_agg(
        distinct deleted.list_id
        order by deleted.list_id
      ),
      '{}'::uuid[]
    )
  into deleted_count, deleted_list_ids
  from deleted;

  if deleted_count > 0 then
    select coalesce(
      pg_catalog.array_agg(
        distinct recipient.profile_id
        order by recipient.profile_id
      ),
      '{}'::uuid[]
    )
    into invalidation_recipient_ids
    from (
      select list_record.owner_id as profile_id
      from public.active_lists as list_record
      where list_record.id = any(deleted_list_ids)
      union
      select access_record.participant_profile_id
      from public.active_list_participants as access_record
      where access_record.list_id = any(deleted_list_ids)
        and access_record.state = 'member'
    ) as recipient;

    perform private.send_chat_account_invalidations(
      invalidation_recipient_ids
    );
  end if;

  return deleted_count;
end;
$$;

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

create function public.export_own_account_data_v12()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  base_export jsonb;
  authored_chat_messages jsonb;
begin
  base_export := public.export_own_account_data_v11();

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'message_id', message_record.id,
        'body', message_record.body,
        'created_at', message_record.created_at,
        'deleted_at', message_record.deleted_at,
        'deletion_kind', message_record.deletion_kind,
        'conversation_available', access_context.is_available,
        'list_id', case
          when access_context.is_available then list_record.id
          else null
        end,
        'list_title', case
          when access_context.is_available then list_record.title
          else null
        end,
        'list_status', case
          when access_context.is_available then list_record.status
          else null
        end
      )
      order by message_record.message_position, message_record.id
    ),
    '[]'::jsonb
  )
  into authored_chat_messages
  from public.active_list_chat_messages as message_record
  join public.active_lists as list_record
    on list_record.id = message_record.list_id
  cross join lateral (
    select private.active_list_caller_is_member(
      message_record.list_id,
      caller_id
    ) as is_available
  ) as access_context
  where message_record.sender_profile_id = caller_id;

  return base_export || pg_catalog.jsonb_build_object(
    'schema_version', 12,
    'authored_chat_messages', authored_chat_messages
  );
end;
$$;

alter function private.normalize_active_list_chat_body(text)
  owner to postgres;
alter function private.active_list_chat_body_has_only_allowed_controls(text)
  owner to postgres;
alter function private.reject_active_list_chat_message_update()
  owner to postgres;
alter function private.active_list_chat_latest_position(uuid)
  owner to postgres;
alter function private.initialize_active_list_chat_owner_state()
  owner to postgres;
alter function private.sync_active_list_chat_participant_state()
  owner to postgres;
alter function private.active_list_chat_send_fingerprint(uuid, text)
  owner to postgres;
alter function private.build_active_list_chat_message(uuid, uuid)
  owner to postgres;
alter function private.send_chat_account_invalidations(uuid[])
  owner to postgres;
alter function private.maintain_active_list_chat_retention(
  timestamptz,
  integer
) owner to postgres;
alter function private.cleanup_active_list_dependents_before_profile_delete()
  owner to postgres;
alter function public.list_active_list_chat_messages(uuid, integer, bigint)
  owner to postgres;
alter function public.send_active_list_chat_message(uuid, text, uuid)
  owner to postgres;
alter function public.delete_active_list_chat_message(uuid, uuid)
  owner to postgres;
alter function public.mark_active_list_chat_read(uuid, uuid)
  owner to postgres;
alter function public.get_active_list_chat_unread_count(uuid)
  owner to postgres;
alter function public.export_own_account_data_v12()
  owner to postgres;

revoke all on sequence private.active_list_chat_message_position_seq
from public, anon, authenticated, service_role;

revoke all on table public.active_list_chat_messages
from public, anon, authenticated, service_role;
revoke all on table public.active_list_chat_states
from public, anon, authenticated, service_role;
revoke all on table private.active_list_chat_send_requests
from public, anon, authenticated, service_role;

revoke all on function private.normalize_active_list_chat_body(text)
from public, anon, authenticated, service_role;
revoke all on function private.active_list_chat_body_has_only_allowed_controls(text)
from public, anon, authenticated, service_role;
revoke all on function private.reject_active_list_chat_message_update()
from public, anon, authenticated, service_role;
revoke all on function private.active_list_chat_latest_position(uuid)
from public, anon, authenticated, service_role;
revoke all on function private.initialize_active_list_chat_owner_state()
from public, anon, authenticated, service_role;
revoke all on function private.sync_active_list_chat_participant_state()
from public, anon, authenticated, service_role;
revoke all on function private.active_list_chat_send_fingerprint(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function private.build_active_list_chat_message(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function private.send_chat_account_invalidations(uuid[])
from public, anon, authenticated, service_role;
revoke all on function private.maintain_active_list_chat_retention(
  timestamptz,
  integer
) from public, anon, authenticated, service_role;
revoke all on function private.cleanup_active_list_dependents_before_profile_delete()
from public, anon, authenticated, service_role;

revoke all on function public.list_active_list_chat_messages(
  uuid,
  integer,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.send_active_list_chat_message(uuid, text, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.delete_active_list_chat_message(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.mark_active_list_chat_read(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_active_list_chat_unread_count(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data_v12()
from public, anon, authenticated, service_role;

grant execute on function public.list_active_list_chat_messages(
  uuid,
  integer,
  bigint
) to authenticated;
grant execute on function public.send_active_list_chat_message(uuid, text, uuid)
to authenticated;
grant execute on function public.delete_active_list_chat_message(uuid, uuid)
to authenticated;
grant execute on function public.mark_active_list_chat_read(uuid, uuid)
to authenticated;
grant execute on function public.get_active_list_chat_unread_count(uuid)
to authenticated;
grant execute on function public.export_own_account_data_v12()
to authenticated;

comment on sequence private.active_list_chat_message_position_seq is
  'Noncycling server-only global Chat order allocated only inside the locked send transaction.';
comment on table public.active_list_chat_messages is
  'RPC-only retained active-list Chat messages and one-way privacy tombstones.';
comment on table public.active_list_chat_states is
  'Private per-list visibility and monotonic unread cursor projection for current access windows.';
comment on table private.active_list_chat_send_requests is
  'Server-only payload-bound Chat send idempotency ledger.';
comment on column public.active_list_chat_messages.message_position is
  'Immutable strict total order used for visibility, pagination, and unread cursors.';
comment on column public.active_list_chat_messages.sender_profile_id is
  'Live sender identity only; account deletion clears it without retaining a name snapshot.';
comment on column public.active_list_chat_messages.body is
  'Normalized plain text, null only after an approved tombstone transition.';
comment on column public.active_list_chat_states.visible_after_message_position is
  'Exclusive first-join or rejoin history boundary; never an authorization source.';
comment on column public.active_list_chat_states.last_read_message_position is
  'Monotonic private cursor that may outlive retention of its referenced message.';

comment on function private.normalize_active_list_chat_body(text) is
  'Normalizes CRLF/CR and the General Note Unicode edge-whitespace set for Chat.';
comment on function private.active_list_chat_body_has_only_allowed_controls(text) is
  'Allows internal tab and LF while rejecting other C0, DEL, and C1 controls.';
comment on function private.reject_active_list_chat_message_update() is
  'Rejects every Chat message update except one-way sender/owner or account tombstones.';
comment on function private.active_list_chat_latest_position(uuid) is
  'Returns the latest retained position for transactional access-window initialization.';
comment on function private.initialize_active_list_chat_owner_state() is
  'Initializes one new-list owner Chat window without changing the list aggregate version.';
comment on function private.sync_active_list_chat_participant_state() is
  'Creates fresh accepted-member Chat windows and removes state immediately on access loss.';
comment on function private.active_list_chat_send_fingerprint(uuid, text) is
  'Builds the domain-separated 32-byte normalized Chat send fingerprint.';
comment on function private.build_active_list_chat_message(uuid, uuid) is
  'Builds the strict message DTO with current sender names and no profile identifier.';
comment on function private.send_chat_account_invalidations(uuid[]) is
  'Sends only chat_invalidate and opaque version 1 to exact private account topics.';
comment on function private.maintain_active_list_chat_retention(
  timestamptz,
  integer
) is
  'Deletes at most one deterministic batch older than 365 days and emits content-free Chat invalidations; unscheduled.';
comment on function private.cleanup_active_list_dependents_before_profile_delete() is
  'Locks surviving lists parent-first, anonymizes retained authored Chat, and preserves established assignment, mention, Split, notification, and Broadcast cleanup.';
comment on function public.list_active_list_chat_messages(
  uuid,
  integer,
  bigint
) is
  'Returns one authorized maximum-50 newest-first message_position keyset page without a total count.';
comment on function public.send_active_list_chat_message(uuid, text, uuid) is
  'Sends one normalized active-list Chat message with locked authorization, rate limiting, durable ordering, and payload-bound retry.';
comment on function public.delete_active_list_chat_message(uuid, uuid) is
  'Applies one active-list sender/owner tombstone without changing list version or timestamps.';
comment on function public.mark_active_list_chat_read(uuid, uuid) is
  'Monotonically advances only the caller Chat cursor through one server-resolved visible message.';
comment on function public.get_active_list_chat_unread_count(uuid) is
  'Returns the caller-only unread count bounded at 100 plus its 99+ cap indicator.';
comment on function public.export_own_account_data_v12() is
  'Preserves v11 and adds only caller-authored retained Chat with privacy-minimal current-or-unavailable conversation context.';

commit;
