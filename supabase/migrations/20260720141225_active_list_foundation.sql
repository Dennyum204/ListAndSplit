begin;

create table public.active_lists (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  title text not null,
  status text not null default 'active',
  version bigint not null default 1,
  creation_request_id uuid not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  archived_at timestamptz,
  constraint active_lists_owner_fkey foreign key (owner_id)
    references public.profiles (id) on delete cascade,
  constraint active_lists_title_check check (
    title = pg_catalog.regexp_replace(
      title,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    )
    and pg_catalog.char_length(title) between 1 and 80
  ),
  constraint active_lists_status_check check (
    status in ('active', 'archived')
  ),
  constraint active_lists_positive_version_check check (version > 0),
  constraint active_lists_archive_state_check check (
    (status = 'active' and archived_at is null)
    or (status = 'archived' and archived_at is not null)
  ),
  constraint active_lists_owner_creation_request_key unique (
    owner_id,
    creation_request_id
  )
);

create table public.active_list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null,
  name text not null,
  quantity_thousandths bigint not null default 1000,
  unit_code text,
  position integer not null,
  version bigint not null default 1,
  creation_request_id uuid not null,
  completed_at timestamptz,
  completed_by uuid,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint active_list_items_list_fkey foreign key (list_id)
    references public.active_lists (id) on delete cascade,
  constraint active_list_items_completed_by_fkey foreign key (completed_by)
    references public.profiles (id) on delete set null,
  constraint active_list_items_name_check check (
    name = pg_catalog.regexp_replace(
      name,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    )
    and pg_catalog.char_length(name) between 1 and 120
  ),
  constraint active_list_items_quantity_check check (
    quantity_thousandths between 1 and 999999999
  ),
  constraint active_list_items_unit_check check (
    unit_code is null
    or unit_code in (
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
  ),
  constraint active_list_items_position_check check (position > 0),
  constraint active_list_items_positive_version_check check (version > 0),
  constraint active_list_items_completion_check check (
    completed_at is not null or completed_by is null
  ),
  constraint active_list_items_list_creation_request_key unique (
    list_id,
    creation_request_id
  ),
  constraint active_list_items_list_position_key unique (list_id, position)
);

alter table public.active_lists owner to postgres;
alter table public.active_list_items owner to postgres;

create index active_lists_owner_status_updated_idx
on public.active_lists (owner_id, status, updated_at desc, id desc);

create index active_lists_owner_archived_idx
on public.active_lists (owner_id, archived_at desc, id desc)
where status = 'archived';

create index active_list_items_completed_by_idx
on public.active_list_items (completed_by, id)
where completed_by is not null;

alter table public.active_lists enable row level security;
alter table public.active_lists force row level security;
alter table public.active_list_items enable row level security;
alter table public.active_list_items force row level security;

revoke all on table public.active_lists
from public, anon, authenticated, service_role;
revoke all on table public.active_list_items
from public, anon, authenticated, service_role;

create policy "active_lists_reject_direct_client_access"
on public.active_lists
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "active_list_items_reject_direct_client_access"
on public.active_list_items
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create function private.require_verified_active_list_caller()
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null
    or not exists (
      select 1
      from auth.users as caller_auth
      join public.profiles as caller_profile
        on caller_profile.id = caller_auth.id
      where caller_auth.id = caller_id
        and caller_auth.email_confirmed_at is not null
        and caller_profile.onboarding_completed_at is not null
    )
  then
    raise exception using
      errcode = '42501',
      message = 'verified profile required';
  end if;

  return caller_id;
end;
$$;

alter function private.require_verified_active_list_caller()
owner to postgres;

revoke all on function private.require_verified_active_list_caller()
from public, anon, authenticated, service_role;

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
  archived_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
begin
  if requested_status is null
    or requested_status not in ('active', 'archived')
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list status';
  end if;

  if page_size is null or page_size < 1 or page_size > 50 then
    raise exception using
      errcode = '22023',
      message = 'invalid list page size';
  end if;

  if (before_sort_at is null) <> (before_list_id is null) then
    raise exception using
      errcode = '22023',
      message = 'invalid list cursor';
  end if;

  return query
  select
    list_record.id,
    list_record.title,
    list_record.status,
    list_record.version,
    pg_catalog.count(item_record.id)::bigint,
    pg_catalog.count(item_record.id) filter (
      where item_record.completed_at is not null
    )::bigint,
    list_record.created_at,
    list_record.updated_at,
    list_record.archived_at
  from public.active_lists as list_record
  left join public.active_list_items as item_record
    on item_record.list_id = list_record.id
  where list_record.owner_id = caller_id
    and list_record.status = requested_status
    and (
      before_sort_at is null
      or (
        case
          when requested_status = 'active' then list_record.updated_at
          else list_record.archived_at
        end,
        list_record.id
      ) < (before_sort_at, before_list_id)
    )
  group by list_record.id
  order by
    case
      when requested_status = 'active' then list_record.updated_at
      else list_record.archived_at
    end desc,
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
  archived_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
begin
  if target_list_id is null then
    raise exception using
      errcode = '22023',
      message = 'invalid list identifier';
  end if;

  if not exists (
    select 1
    from public.active_lists as owned_list
    where owned_list.id = target_list_id
      and owned_list.owner_id = caller_id
  )
  then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  return query
  select
    list_record.id,
    list_record.title,
    list_record.status,
    list_record.version,
    pg_catalog.count(item_record.id)::bigint,
    pg_catalog.count(item_record.id) filter (
      where item_record.completed_at is not null
    )::bigint,
    list_record.created_at,
    list_record.updated_at,
    list_record.archived_at
  from public.active_lists as list_record
  left join public.active_list_items as item_record
    on item_record.list_id = list_record.id
  where list_record.id = target_list_id
    and list_record.owner_id = caller_id
  group by list_record.id;
end;
$$;

create function public.list_active_list_items(target_list_id uuid)
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
  if target_list_id is null then
    raise exception using
      errcode = '22023',
      message = 'invalid list identifier';
  end if;

  if not exists (
    select 1
    from public.active_lists as owned_list
    where owned_list.id = target_list_id
      and owned_list.owner_id = caller_id
  )
  then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
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
    item_record.updated_at
  from public.active_list_items as item_record
  where item_record.list_id = target_list_id
  order by item_record.position, item_record.id;
end;
$$;

create function public.create_active_list(
  new_title text,
  creation_request_id uuid
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
  canonical_title text;
  existing_list public.active_lists%rowtype;
  created_list public.active_lists%rowtype;
begin
  canonical_title := pg_catalog.regexp_replace(
    new_title,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );

  if creation_request_id is null
    or canonical_title is null
    or pg_catalog.char_length(canonical_title) not between 1 and 80
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list creation';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'list-and-split:list-create:'
        || caller_id::text
        || ':'
        || creation_request_id::text,
      0
    )
  );

  select list_record.*
  into existing_list
  from public.active_lists as list_record
  where list_record.owner_id = caller_id
    and list_record.creation_request_id = create_active_list.creation_request_id
  for update;

  if found then
    if existing_list.title <> canonical_title then
      raise exception using
        errcode = '23505',
        message = 'list creation request conflict',
        constraint = 'active_lists_owner_creation_request_key';
    end if;

    return query
    select
      existing_list.id,
      existing_list.title,
      existing_list.status,
      existing_list.version,
      existing_list.created_at,
      existing_list.updated_at,
      existing_list.archived_at;
    return;
  end if;

  insert into public.active_lists (
    owner_id,
    title,
    creation_request_id
  )
  values (
    caller_id,
    canonical_title,
    create_active_list.creation_request_id
  )
  returning * into created_list;

  return query
  select
    created_list.id,
    created_list.title,
    created_list.status,
    created_list.version,
    created_list.created_at,
    created_list.updated_at,
    created_list.archived_at;
end;
$$;

create function public.rename_active_list(
  target_list_id uuid,
  new_title text,
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
  canonical_title text;
  list_record public.active_lists%rowtype;
begin
  canonical_title := pg_catalog.regexp_replace(
    new_title,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );

  if target_list_id is null
    or expected_list_version is null
    or expected_list_version < 1
    or canonical_title is null
    or pg_catalog.char_length(canonical_title) not between 1 and 80
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list rename';
  end if;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  if list_record.title = canonical_title
    and expected_list_version in (
      list_record.version,
      list_record.version - 1
    )
  then
    return query
    select
      list_record.id,
      list_record.title,
      list_record.status,
      list_record.version,
      list_record.created_at,
      list_record.updated_at,
      list_record.archived_at;
    return;
  end if;

  if expected_list_version <> list_record.version then
    raise exception using
      errcode = '40001',
      message = 'list changed';
  end if;

  update public.active_lists as owned_list
  set title = canonical_title,
      version = owned_list.version + 1,
      updated_at = pg_catalog.clock_timestamp()
  where owned_list.id = list_record.id
  returning owned_list.* into list_record;

  return query
  select
    list_record.id,
    list_record.title,
    list_record.status,
    list_record.version,
    list_record.created_at,
    list_record.updated_at,
    list_record.archived_at;
end;
$$;

create function public.set_active_list_archived(
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
  if target_list_id is null
    or should_archive is null
    or expected_list_version is null
    or expected_list_version < 1
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list archive transition';
  end if;

  desired_status := case when should_archive then 'archived' else 'active' end;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if list_record.status = desired_status
    and expected_list_version in (
      list_record.version,
      list_record.version - 1
    )
  then
    return query
    select
      list_record.id,
      list_record.title,
      list_record.status,
      list_record.version,
      list_record.created_at,
      list_record.updated_at,
      list_record.archived_at;
    return;
  end if;

  if expected_list_version <> list_record.version then
    raise exception using
      errcode = '40001',
      message = 'list changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();

  update public.active_lists as owned_list
  set status = desired_status,
      archived_at = case when should_archive then mutation_time else null end,
      version = owned_list.version + 1,
      updated_at = mutation_time
  where owned_list.id = list_record.id
  returning owned_list.* into list_record;

  return query
  select
    list_record.id,
    list_record.title,
    list_record.status,
    list_record.version,
    list_record.created_at,
    list_record.updated_at,
    list_record.archived_at;
end;
$$;

create function public.delete_active_list(
  target_list_id uuid,
  expected_list_version bigint
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
begin
  if target_list_id is null
    or expected_list_version is null
    or expected_list_version < 1
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list deletion';
  end if;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  if expected_list_version <> list_record.version then
    raise exception using
      errcode = '40001',
      message = 'list changed';
  end if;

  delete from public.active_lists as owned_list
  where owned_list.id = list_record.id;
end;
$$;

create function public.create_active_list_item(
  target_list_id uuid,
  new_name text,
  creation_request_id uuid,
  expected_list_version bigint,
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
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  canonical_name text;
  list_record public.active_lists%rowtype;
  existing_item public.active_list_items%rowtype;
  created_item public.active_list_items%rowtype;
  next_position integer;
  mutation_time timestamptz;
begin
  canonical_name := pg_catalog.regexp_replace(
    new_name,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );

  if target_list_id is null
    or creation_request_id is null
    or expected_list_version is null
    or expected_list_version < 1
    or canonical_name is null
    or pg_catalog.char_length(canonical_name) not between 1 and 120
    or new_quantity_thousandths is null
    or new_quantity_thousandths not between 1 and 999999999
    or (
      new_unit_code is not null
      and new_unit_code not in (
        'piece', 'kg', 'g', 'l', 'ml', 'pack', 'box', 'bottle', 'can', 'bag'
      )
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item creation';
  end if;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  select item_record.*
  into existing_item
  from public.active_list_items as item_record
  where item_record.list_id = list_record.id
    and item_record.creation_request_id =
      create_active_list_item.creation_request_id
  for update;

  if found then
    if existing_item.name <> canonical_name
      or existing_item.quantity_thousandths <> new_quantity_thousandths
      or existing_item.unit_code is distinct from new_unit_code
    then
      raise exception using
        errcode = '23505',
        message = 'list item creation request conflict',
        constraint = 'active_list_items_list_creation_request_key';
    end if;

    if expected_list_version not in (
      list_record.version,
      list_record.version - 1
    )
    then
      raise exception using
        errcode = '40001',
        message = 'list changed';
    end if;

    return query
    select
      existing_item.id,
      list_record.version,
      existing_item.name,
      existing_item.quantity_thousandths,
      existing_item.unit_code,
      existing_item.position,
      existing_item.version,
      existing_item.completed_at,
      existing_item.completed_by,
      existing_item.created_at,
      existing_item.updated_at;
    return;
  end if;

  if expected_list_version <> list_record.version then
    raise exception using
      errcode = '40001',
      message = 'list changed';
  end if;

  select coalesce(pg_catalog.max(item_record.position), 0) + 1
  into next_position
  from public.active_list_items as item_record
  where item_record.list_id = list_record.id;

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
  )
  values (
    list_record.id,
    canonical_name,
    new_quantity_thousandths,
    new_unit_code,
    next_position,
    create_active_list_item.creation_request_id,
    mutation_time,
    mutation_time
  )
  returning * into created_item;

  update public.active_lists as owned_list
  set version = owned_list.version + 1,
      updated_at = mutation_time
  where owned_list.id = list_record.id
  returning owned_list.* into list_record;

  return query
  select
    created_item.id,
    list_record.version,
    created_item.name,
    created_item.quantity_thousandths,
    created_item.unit_code,
    created_item.position,
    created_item.version,
    created_item.completed_at,
    created_item.completed_by,
    created_item.created_at,
    created_item.updated_at;
end;
$$;

create function public.update_active_list_item(
  target_list_id uuid,
  target_item_id uuid,
  new_name text,
  new_quantity_thousandths bigint,
  new_unit_code text,
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
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  canonical_name text;
  list_record public.active_lists%rowtype;
  item_record public.active_list_items%rowtype;
  mutation_time timestamptz;
begin
  canonical_name := pg_catalog.regexp_replace(
    new_name,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );

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
        'piece', 'kg', 'g', 'l', 'ml', 'pack', 'box', 'bottle', 'can', 'bag'
      )
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item update';
  end if;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  select owned_item.*
  into item_record
  from public.active_list_items as owned_item
  where owned_item.id = target_item_id
    and owned_item.list_id = list_record.id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list item unavailable';
  end if;

  if item_record.name = canonical_name
    and item_record.quantity_thousandths = new_quantity_thousandths
    and item_record.unit_code is not distinct from new_unit_code
    and (
      (
        expected_list_version = list_record.version
        and expected_item_version = item_record.version
      )
      or (
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
      item_record.updated_at;
    return;
  end if;

  if expected_list_version <> list_record.version
    or expected_item_version <> item_record.version
  then
    raise exception using
      errcode = '40001',
      message = 'list item changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();

  update public.active_list_items as owned_item
  set name = canonical_name,
      quantity_thousandths = new_quantity_thousandths,
      unit_code = new_unit_code,
      version = owned_item.version + 1,
      updated_at = mutation_time
  where owned_item.id = item_record.id
  returning owned_item.* into item_record;

  update public.active_lists as owned_list
  set version = owned_list.version + 1,
      updated_at = mutation_time
  where owned_list.id = list_record.id
  returning owned_list.* into list_record;

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
    item_record.updated_at;
end;
$$;

create function public.set_active_list_item_completed(
  target_list_id uuid,
  target_item_id uuid,
  should_complete boolean,
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
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  item_record public.active_list_items%rowtype;
  mutation_time timestamptz;
  already_desired boolean;
begin
  if target_list_id is null
    or target_item_id is null
    or should_complete is null
    or expected_list_version is null
    or expected_list_version < 1
    or expected_item_version is null
    or expected_item_version < 1
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item completion';
  end if;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  select owned_item.*
  into item_record
  from public.active_list_items as owned_item
  where owned_item.id = target_item_id
    and owned_item.list_id = list_record.id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list item unavailable';
  end if;

  already_desired := should_complete = (item_record.completed_at is not null);

  if already_desired
    and (
      (
        expected_list_version = list_record.version
        and expected_item_version = item_record.version
      )
      or (
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
      item_record.updated_at;
    return;
  end if;

  if expected_list_version <> list_record.version
    or expected_item_version <> item_record.version
  then
    raise exception using
      errcode = '40001',
      message = 'list item changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();

  update public.active_list_items as owned_item
  set completed_at = case when should_complete then mutation_time else null end,
      completed_by = case when should_complete then caller_id else null end,
      version = owned_item.version + 1,
      updated_at = mutation_time
  where owned_item.id = item_record.id
  returning owned_item.* into item_record;

  update public.active_lists as owned_list
  set version = owned_list.version + 1,
      updated_at = mutation_time
  where owned_list.id = list_record.id
  returning owned_list.* into list_record;

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
    item_record.updated_at;
end;
$$;

create function public.delete_active_list_item(
  target_list_id uuid,
  target_item_id uuid,
  expected_list_version bigint,
  expected_item_version bigint
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
  item_record public.active_list_items%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or target_item_id is null
    or expected_list_version is null
    or expected_list_version < 1
    or expected_item_version is null
    or expected_item_version < 1
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item deletion';
  end if;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  select owned_item.*
  into item_record
  from public.active_list_items as owned_item
  where owned_item.id = target_item_id
    and owned_item.list_id = list_record.id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list item unavailable';
  end if;

  if expected_list_version <> list_record.version
    or expected_item_version <> item_record.version
  then
    raise exception using
      errcode = '40001',
      message = 'list item changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();

  delete from public.active_list_items as owned_item
  where owned_item.id = item_record.id;

  update public.active_lists as owned_list
  set version = owned_list.version + 1,
      updated_at = mutation_time
  where owned_list.id = list_record.id
  returning owned_list.* into list_record;

  return list_record.version;
end;
$$;

create function public.reorder_active_list_items(
  target_list_id uuid,
  ordered_item_ids uuid[],
  expected_list_version bigint
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
  current_item_ids uuid[];
  item_count integer;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or ordered_item_ids is null
    or expected_list_version is null
    or expected_list_version < 1
    or pg_catalog.array_position(ordered_item_ids, null::uuid) is not null
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item order';
  end if;

  if pg_catalog.cardinality(ordered_item_ids) <> (
    select pg_catalog.count(distinct submitted_id)
    from pg_catalog.unnest(ordered_item_ids) as submitted(submitted_id)
  )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item order';
  end if;

  select owned_list.*
  into list_record
  from public.active_lists as owned_list
  where owned_list.id = target_list_id
    and owned_list.owner_id = caller_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'list unavailable';
  end if;

  if list_record.status = 'archived' then
    raise exception using
      errcode = '55000',
      message = 'archived list is read only';
  end if;

  perform 1
  from public.active_list_items as lock_item
  where lock_item.list_id = list_record.id
  order by lock_item.id
  for update;

  select
    coalesce(
      pg_catalog.array_agg(item_record.id order by item_record.position),
      '{}'::uuid[]
    ),
    pg_catalog.count(*)::integer
  into current_item_ids, item_count
  from public.active_list_items as item_record
  where item_record.list_id = list_record.id;

  if pg_catalog.cardinality(ordered_item_ids) <> item_count
    or exists (
      select 1
      from pg_catalog.unnest(ordered_item_ids) as submitted(item_id)
      where not exists (
        select 1
        from public.active_list_items as current_item
        where current_item.list_id = list_record.id
          and current_item.id = submitted.item_id
      )
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid list item order';
  end if;

  if current_item_ids = ordered_item_ids
    and expected_list_version in (
      list_record.version,
      list_record.version - 1
    )
  then
    return list_record.version;
  end if;

  if expected_list_version <> list_record.version then
    raise exception using
      errcode = '40001',
      message = 'list changed';
  end if;

  if item_count = 0 then
    return list_record.version;
  end if;

  update public.active_list_items as item_record
  set position = item_record.position + item_count
  where item_record.list_id = list_record.id;

  update public.active_list_items as item_record
  set position = submitted.ordinality::integer
  from pg_catalog.unnest(ordered_item_ids) with ordinality
    as submitted(item_id, ordinality)
  where item_record.list_id = list_record.id
    and item_record.id = submitted.item_id;

  mutation_time := pg_catalog.clock_timestamp();

  update public.active_lists as owned_list
  set version = owned_list.version + 1,
      updated_at = mutation_time
  where owned_list.id = list_record.id
  returning owned_list.* into list_record;

  return list_record.version;
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
  caller_auth jsonb;
  caller_profile jsonb;
  outgoing_blocks jsonb := '[]'::jsonb;
  active_relationships jsonb := '[]'::jsonb;
  visible_notifications jsonb := '[]'::jsonb;
  active_lists jsonb := '[]'::jsonb;
begin
  begin
    caller_id := (select auth.uid());
  exception
    when others then
      raise exception using
        errcode = '42501',
        message = 'verified account required';
  end;

  if caller_id is null
    or (
      select pg_catalog.count(*)
      from auth.users as caller
      where caller.id = caller_id
        and caller.email is not null
        and caller.email_confirmed_at is not null
    ) <> 1
  then
    raise exception using
      errcode = '42501',
      message = 'verified account required';
  end if;

  if (
    select pg_catalog.count(*)
    from public.profiles as profile_record
    where profile_record.id = caller_id
  ) <> 1
  then
    raise exception using
      errcode = '42501',
      message = 'verified account required';
  end if;

  select pg_catalog.jsonb_build_object(
    'id', caller.id,
    'email', caller.email,
    'email_confirmed_at', caller.email_confirmed_at,
    'created_at', caller.created_at,
    'updated_at', caller.updated_at,
    'last_sign_in_at', caller.last_sign_in_at
  )
  into strict caller_auth
  from auth.users as caller
  where caller.id = caller_id;

  select pg_catalog.jsonb_build_object(
    'id', profile_record.id,
    'username', profile_record.username,
    'display_name', profile_record.display_name,
    'created_at', profile_record.created_at,
    'updated_at', profile_record.updated_at,
    'onboarding_completed_at', profile_record.onboarding_completed_at
  )
  into strict caller_profile
  from public.profiles as profile_record
  where profile_record.id = caller_id;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'profile_id', blocked_profile.id,
        'username', blocked_profile.username,
        'display_name', blocked_profile.display_name,
        'created_at', block_record.created_at
      )
      order by block_record.created_at, blocked_profile.id
    ),
    '[]'::jsonb
  )
  into outgoing_blocks
  from public.user_blocks as block_record
  join public.profiles as blocked_profile
    on blocked_profile.id = block_record.blocked_id
    and blocked_profile.onboarding_completed_at is not null
  where block_record.blocker_id = caller_id;

  if (caller_profile ->> 'onboarding_completed_at') is not null then
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'profile_id', relationship.profile_id,
          'username', relationship.username,
          'display_name', relationship.display_name,
          'status', relationship.relationship_status,
          'version', relationship.version,
          'state_changed_at', relationship.state_changed_at
        )
        order by
          relationship.state_changed_at desc,
          relationship.username,
          relationship.profile_id
      ),
      '[]'::jsonb
    )
    into active_relationships
    from public.list_active_relationships() as relationship;

    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', notification_record.id,
          'type', notification_record.notification_type,
          'created_at', notification_record.created_at,
          'is_read', notification_record.read_at is not null,
          'read_at', notification_record.read_at,
          'expires_at', notification_record.expires_at,
          'actor_profile_id', actor_profile.id,
          'actor_username', actor_profile.username,
          'actor_display_name', actor_profile.display_name,
          'action_status', case
            when relationship_record.state = 'pending'
              and relationship_record.version =
                notification_record.relationship_version
              and relationship_record.requester_id =
                notification_record.actor_id
              and notification_record.recipient_id = caller_id
              then 'actionable'
            when relationship_record.state = 'friends' then 'friends'
            else 'unavailable'
          end,
          'expected_relationship_version', case
            when relationship_record.state = 'pending'
              and relationship_record.version =
                notification_record.relationship_version
              and relationship_record.requester_id =
                notification_record.actor_id
              and notification_record.recipient_id = caller_id
              then notification_record.relationship_version
            else null::bigint
          end
        )
        order by notification_record.created_at desc, notification_record.id desc
      ),
      '[]'::jsonb
    )
    into visible_notifications
    from public.user_notifications as notification_record
    join public.profiles as actor_profile
      on actor_profile.id = notification_record.actor_id
      and actor_profile.onboarding_completed_at is not null
    join public.user_relationships as relationship_record
      on relationship_record.profile_low_id =
        notification_record.relationship_low_id
      and relationship_record.profile_high_id =
        notification_record.relationship_high_id
    where notification_record.recipient_id = caller_id
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
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', list_record.id,
        'title', list_record.title,
        'status', list_record.status,
        'version', list_record.version,
        'created_at', list_record.created_at,
        'updated_at', list_record.updated_at,
        'archived_at', list_record.archived_at,
        'items', coalesce(
          (
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'id', item_record.id,
                'name', item_record.name,
                'quantity_thousandths', item_record.quantity_thousandths,
                'unit_code', item_record.unit_code,
                'position', item_record.position,
                'version', item_record.version,
                'completed_at', item_record.completed_at,
                'completed_by', item_record.completed_by,
                'created_at', item_record.created_at,
                'updated_at', item_record.updated_at
              )
              order by item_record.position, item_record.id
            )
            from public.active_list_items as item_record
            where item_record.list_id = list_record.id
          ),
          '[]'::jsonb
        )
      )
      order by
        case when list_record.status = 'active' then 0 else 1 end,
        case
          when list_record.status = 'active' then list_record.updated_at
          else list_record.archived_at
        end desc,
        list_record.id desc
    ),
    '[]'::jsonb
  )
  into active_lists
  from public.active_lists as list_record
  where list_record.owner_id = caller_id;

  return pg_catalog.jsonb_build_object(
    'product', 'list_and_split',
    'schema_version', 2,
    'exported_at', pg_catalog.statement_timestamp(),
    'auth_identity', caller_auth,
    'profile', caller_profile,
    'outgoing_blocks', outgoing_blocks,
    'active_relationships', active_relationships,
    'visible_notifications', visible_notifications,
    'active_lists', active_lists
  );
end;
$$;

alter function public.list_active_lists(text, integer, timestamptz, uuid)
owner to postgres;
alter function public.get_active_list(uuid) owner to postgres;
alter function public.list_active_list_items(uuid) owner to postgres;
alter function public.create_active_list(text, uuid) owner to postgres;
alter function public.rename_active_list(uuid, text, bigint) owner to postgres;
alter function public.set_active_list_archived(uuid, boolean, bigint)
owner to postgres;
alter function public.delete_active_list(uuid, bigint) owner to postgres;
alter function public.create_active_list_item(
  uuid,
  text,
  uuid,
  bigint,
  bigint,
  text
) owner to postgres;
alter function public.update_active_list_item(
  uuid,
  uuid,
  text,
  bigint,
  text,
  bigint,
  bigint
) owner to postgres;
alter function public.set_active_list_item_completed(
  uuid,
  uuid,
  boolean,
  bigint,
  bigint
) owner to postgres;
alter function public.delete_active_list_item(uuid, uuid, bigint, bigint)
owner to postgres;
alter function public.reorder_active_list_items(uuid, uuid[], bigint)
owner to postgres;
alter function public.export_own_account_data() owner to postgres;

revoke all on function public.list_active_lists(
  text,
  integer,
  timestamptz,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function public.get_active_list(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_active_list_items(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.create_active_list(text, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.rename_active_list(uuid, text, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.set_active_list_archived(uuid, boolean, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.delete_active_list(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.create_active_list_item(
  uuid,
  text,
  uuid,
  bigint,
  bigint,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.update_active_list_item(
  uuid,
  uuid,
  text,
  bigint,
  text,
  bigint,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.set_active_list_item_completed(
  uuid,
  uuid,
  boolean,
  bigint,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.delete_active_list_item(
  uuid,
  uuid,
  bigint,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.reorder_active_list_items(uuid, uuid[], bigint)
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data()
from public, anon, authenticated, service_role;

grant execute on function public.list_active_lists(
  text,
  integer,
  timestamptz,
  uuid
) to authenticated;
grant execute on function public.get_active_list(uuid) to authenticated;
grant execute on function public.list_active_list_items(uuid) to authenticated;
grant execute on function public.create_active_list(text, uuid) to authenticated;
grant execute on function public.rename_active_list(uuid, text, bigint)
to authenticated;
grant execute on function public.set_active_list_archived(uuid, boolean, bigint)
to authenticated;
grant execute on function public.delete_active_list(uuid, bigint)
to authenticated;
grant execute on function public.create_active_list_item(
  uuid,
  text,
  uuid,
  bigint,
  bigint,
  text
) to authenticated;
grant execute on function public.update_active_list_item(
  uuid,
  uuid,
  text,
  bigint,
  text,
  bigint,
  bigint
) to authenticated;
grant execute on function public.set_active_list_item_completed(
  uuid,
  uuid,
  boolean,
  bigint,
  bigint
) to authenticated;
grant execute on function public.delete_active_list_item(
  uuid,
  uuid,
  bigint,
  bigint
) to authenticated;
grant execute on function public.reorder_active_list_items(uuid, uuid[], bigint)
to authenticated;
grant execute on function public.export_own_account_data()
to authenticated;

comment on table public.active_lists is
  'RPC-only owner active lists with archive state and optimistic versions.';
comment on table public.active_list_items is
  'RPC-only ordered owner-list items with exact quantities and completion attribution.';
comment on function private.require_verified_active_list_caller() is
  'Returns the confirmed, fully onboarded active-list caller or rejects access.';
comment on function public.list_active_lists(text, integer, timestamptz, uuid) is
  'Returns one bounded owner list page with aggregate item counts.';
comment on function public.get_active_list(uuid) is
  'Returns one allowlisted owner-only list detail projection.';
comment on function public.list_active_list_items(uuid) is
  'Returns one owner list item collection in deterministic integer order.';
comment on function public.create_active_list(text, uuid) is
  'Retry-safely creates one active list for the authenticated owner.';
comment on function public.rename_active_list(uuid, text, bigint) is
  'Version-checks and renames one mutable owner list.';
comment on function public.set_active_list_archived(uuid, boolean, bigint) is
  'Version-checks an idempotent owner list archive or restore transition.';
comment on function public.delete_active_list(uuid, bigint) is
  'Version-checks permanent deletion of one active owner list and its items.';
comment on function public.create_active_list_item(
  uuid,
  text,
  uuid,
  bigint,
  bigint,
  text
) is 'Retry-safely appends one exact-quantity item to a mutable owner list.';
comment on function public.update_active_list_item(
  uuid,
  uuid,
  text,
  bigint,
  text,
  bigint,
  bigint
) is 'Version-checks owner list item content changes.';
comment on function public.set_active_list_item_completed(
  uuid,
  uuid,
  boolean,
  bigint,
  bigint
) is 'Version-checks owner completion or reopening with server attribution.';
comment on function public.delete_active_list_item(uuid, uuid, bigint, bigint) is
  'Version-checks permanent deletion of one owner list item.';
comment on function public.reorder_active_list_items(uuid, uuid[], bigint) is
  'Atomically validates and version-checks one exact owner list item order.';
comment on function public.export_own_account_data() is
  'Returns the verified caller''s schema-version-2 allowlisted account export without persistence or mutation.';

commit;
