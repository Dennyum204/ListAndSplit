create table public.template_categories (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  owner_id uuid not null,
  name text not null,
  normalized_name text not null,
  version bigint not null default 1,
  creation_request_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint template_categories_owner_fkey foreign key (owner_id)
    references public.profiles(id) on delete cascade,
  constraint template_categories_name_check check (
    name = pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(name, '^[[:space:]]+|[[:space:]]+$', '', 'g'),
      '[[:space:]]+', ' ', 'g'
    )
    and pg_catalog.char_length(name) >= 1
  ),
  constraint template_categories_normalized_name_check check (
    normalized_name = pg_catalog.lower(name)
  ),
  constraint template_categories_version_check check (version > 0),
  constraint template_categories_time_check check (updated_at >= created_at),
  constraint template_categories_owner_name_key unique (owner_id, normalized_name),
  constraint template_categories_owner_request_key unique (owner_id, creation_request_id),
  constraint template_categories_owner_id_key unique (owner_id, id)
);

create table public.templates (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  owner_id uuid not null,
  category_id uuid,
  name text not null,
  version bigint not null default 1,
  creation_request_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint templates_owner_fkey foreign key (owner_id)
    references public.profiles(id) on delete cascade,
  constraint templates_owner_category_fkey foreign key (owner_id, category_id)
    references public.template_categories(owner_id, id),
  constraint templates_name_check check (
    name = pg_catalog.regexp_replace(name, '^[[:space:]]+|[[:space:]]+$', '', 'g')
    and pg_catalog.char_length(name) >= 1
  ),
  constraint templates_version_check check (version > 0),
  constraint templates_time_check check (updated_at >= created_at),
  constraint templates_owner_request_key unique (owner_id, creation_request_id),
  constraint templates_owner_id_key unique (owner_id, id)
);

create table public.template_items (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  template_id uuid not null,
  name text not null,
  quantity_thousandths bigint not null default 1000,
  position integer not null,
  version bigint not null default 1,
  creation_request_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint template_items_template_fkey foreign key (template_id)
    references public.templates(id) on delete cascade,
  constraint template_items_name_check check (
    name = pg_catalog.regexp_replace(name, '^[[:space:]]+|[[:space:]]+$', '', 'g')
    and pg_catalog.char_length(name) between 1 and 120
  ),
  constraint template_items_quantity_check check (
    quantity_thousandths between 1 and 999999999
  ),
  constraint template_items_position_check check (position > 0),
  constraint template_items_version_check check (version > 0),
  constraint template_items_time_check check (updated_at >= created_at),
  constraint template_items_template_position_key unique (template_id, position),
  constraint template_items_template_request_key unique (template_id, creation_request_id)
);

alter table public.template_categories owner to postgres;
alter table public.templates owner to postgres;
alter table public.template_items owner to postgres;

create index templates_owner_updated_idx
  on public.templates (owner_id, updated_at desc, id desc);
create index templates_owner_created_idx
  on public.templates (owner_id, created_at desc, id desc);
create index templates_owner_category_idx
  on public.templates (owner_id, category_id, updated_at desc, id desc);
create index template_items_template_order_idx
  on public.template_items (template_id, position, id);

alter table public.template_categories enable row level security;
alter table public.template_categories force row level security;
alter table public.templates enable row level security;
alter table public.templates force row level security;
alter table public.template_items enable row level security;
alter table public.template_items force row level security;

revoke all on table public.template_categories
from public, anon, authenticated, service_role;
revoke all on table public.templates
from public, anon, authenticated, service_role;
revoke all on table public.template_items
from public, anon, authenticated, service_role;

create policy "template_categories_reject_direct_client_access"
on public.template_categories
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "templates_reject_direct_client_access"
on public.templates
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "template_items_reject_direct_client_access"
on public.template_items
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create function private.require_verified_template_caller()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null or not exists (
    select 1
    from auth.users as caller_auth
    join public.profiles as caller_profile on caller_profile.id = caller_auth.id
    where caller_auth.id = caller_id
      and caller_auth.email_confirmed_at is not null
      and caller_profile.onboarding_completed_at is not null
      and caller_profile.username is not null
      and caller_profile.display_name is not null
  ) then
    raise exception using errcode = '42501', message = 'verified profile required';
  end if;
  return caller_id;
end;
$$;

create function private.canonical_template_name(raw_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.regexp_replace(raw_name, '^[[:space:]]+|[[:space:]]+$', '', 'g');
$$;

create function private.canonical_category_name(raw_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.regexp_replace(
    pg_catalog.regexp_replace(raw_name, '^[[:space:]]+|[[:space:]]+$', '', 'g'),
    '[[:space:]]+', ' ', 'g'
  );
$$;

create function private.normalized_template_search(raw_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.lower(
    pg_catalog.regexp_replace(
      pg_catalog.regexp_replace(raw_name, '^[[:space:]]+|[[:space:]]+$', '', 'g'),
      '[[:space:]]+', ' ', 'g'
    )
  );
$$;

create function private.lock_template_owner(caller_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('private-templates:' || caller_id::text, 0)
  );
end;
$$;

create function private.require_owned_template_category(
  target_category_id uuid,
  caller_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if target_category_id is not null and not exists (
    select 1
    from public.template_categories as category_record
    where category_record.id = target_category_id
      and category_record.owner_id = caller_id
  ) then
    raise exception using errcode = 'P0002', message = 'template category unavailable';
  end if;
end;
$$;

create function private.lock_owned_template(
  target_template_id uuid,
  caller_id uuid
)
returns public.templates
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  template_record public.templates%rowtype;
begin
  select candidate.* into template_record
  from public.templates as candidate
  where candidate.id = target_template_id
    and candidate.owner_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'template unavailable';
  end if;
  return template_record;
end;
$$;

alter function private.require_verified_template_caller() owner to postgres;
alter function private.canonical_template_name(text) owner to postgres;
alter function private.canonical_category_name(text) owner to postgres;
alter function private.normalized_template_search(text) owner to postgres;
alter function private.lock_template_owner(uuid) owner to postgres;
alter function private.require_owned_template_category(uuid, uuid) owner to postgres;
alter function private.lock_owned_template(uuid, uuid) owner to postgres;

revoke all on function private.require_verified_template_caller()
from public, anon, authenticated, service_role;
revoke all on function private.canonical_template_name(text)
from public, anon, authenticated, service_role;
revoke all on function private.canonical_category_name(text)
from public, anon, authenticated, service_role;
revoke all on function private.normalized_template_search(text)
from public, anon, authenticated, service_role;
revoke all on function private.lock_template_owner(uuid)
from public, anon, authenticated, service_role;
revoke all on function private.require_owned_template_category(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function private.lock_owned_template(uuid, uuid)
from public, anon, authenticated, service_role;

create function public.list_template_categories()
returns table (
  category_id uuid,
  name text,
  version bigint,
  template_count bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
begin
  return query
  select
    category_record.id,
    category_record.name,
    category_record.version,
    pg_catalog.count(template_record.id)::bigint,
    category_record.created_at,
    category_record.updated_at
  from public.template_categories as category_record
  left join public.templates as template_record
    on template_record.owner_id = category_record.owner_id
   and template_record.category_id = category_record.id
  where category_record.owner_id = caller_id
  group by category_record.id
  order by category_record.normalized_name, category_record.id;
end;
$$;

create function public.list_private_templates(
  search_query text default null,
  category_filter uuid default null,
  uncategorized_only boolean default false,
  sort_mode text default 'recent'
)
returns table (
  template_id uuid,
  category_id uuid,
  category_name text,
  name text,
  version bigint,
  item_count bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  normalized_search text := private.normalized_template_search(search_query);
begin
  if sort_mode not in ('recent', 'alpha', 'newest')
    or coalesce(uncategorized_only, false) and category_filter is not null
  then
    raise exception using errcode = '22023', message = 'invalid template query';
  end if;
  if normalized_search = '' then normalized_search := null; end if;

  return query
  select
    template_record.id,
    template_record.category_id,
    category_record.name,
    template_record.name,
    template_record.version,
    pg_catalog.count(item_record.id)::bigint,
    template_record.created_at,
    template_record.updated_at
  from public.templates as template_record
  left join public.template_categories as category_record
    on category_record.owner_id = template_record.owner_id
   and category_record.id = template_record.category_id
  left join public.template_items as item_record
    on item_record.template_id = template_record.id
  where template_record.owner_id = caller_id
    and (category_filter is null or template_record.category_id = category_filter)
    and (not coalesce(uncategorized_only, false) or template_record.category_id is null)
    and (
      normalized_search is null
      or pg_catalog.strpos(
        private.normalized_template_search(template_record.name), normalized_search
      ) > 0
      or exists (
        select 1
        from public.template_items as searched_item
        where searched_item.template_id = template_record.id
          and pg_catalog.strpos(
            private.normalized_template_search(searched_item.name), normalized_search
          ) > 0
      )
    )
  group by template_record.id, category_record.name
  order by
    case when sort_mode = 'recent' then template_record.updated_at end desc,
    case when sort_mode = 'alpha' then private.normalized_template_search(template_record.name) end asc,
    case when sort_mode = 'newest' then template_record.created_at end desc,
    template_record.id;
end;
$$;

create function public.get_private_template(target_template_id uuid)
returns table (
  template_id uuid,
  category_id uuid,
  category_name text,
  name text,
  version bigint,
  item_count bigint,
  remaining_capacity integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
begin
  return query
  select
    template_record.id,
    template_record.category_id,
    category_record.name,
    template_record.name,
    template_record.version,
    pg_catalog.count(item_record.id)::bigint,
    greatest(200 - pg_catalog.count(item_record.id), 0)::integer,
    template_record.created_at,
    template_record.updated_at
  from public.templates as template_record
  left join public.template_categories as category_record
    on category_record.owner_id = template_record.owner_id
   and category_record.id = template_record.category_id
  left join public.template_items as item_record
    on item_record.template_id = template_record.id
  where template_record.id = target_template_id
    and template_record.owner_id = caller_id
  group by template_record.id, category_record.name;
end;
$$;

create function public.list_private_template_items(target_template_id uuid)
returns table (
  item_id uuid,
  name text,
  quantity_thousandths bigint,
  "position" integer,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
begin
  return query
  select
    item_record.id,
    item_record.name,
    item_record.quantity_thousandths,
    item_record.position,
    item_record.version,
    item_record.created_at,
    item_record.updated_at
  from public.template_items as item_record
  join public.templates as template_record on template_record.id = item_record.template_id
  where template_record.id = target_template_id
    and template_record.owner_id = caller_id
  order by item_record.position, item_record.id;
end;
$$;

create function public.create_template_category(
  new_name text,
  creation_request_id uuid
)
returns table (
  category_id uuid,
  name text,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  canonical_name text := private.canonical_category_name(new_name);
  category_record public.template_categories%rowtype;
  mutation_time timestamptz;
begin
  if creation_request_id is null or canonical_name is null
    or pg_catalog.char_length(canonical_name) < 1
  then
    raise exception using errcode = '22023', message = 'invalid template category';
  end if;

  perform private.lock_template_owner(caller_id);
  select existing.* into category_record
  from public.template_categories as existing
  where existing.owner_id = caller_id
    and existing.creation_request_id = create_template_category.creation_request_id
  for update;
  if found then
    if category_record.name <> canonical_name then
      raise exception using
        errcode = '23505',
        message = 'template category creation request conflict',
        constraint = 'template_categories_owner_request_key';
    end if;
    return query select category_record.id, category_record.name,
      category_record.version, category_record.created_at, category_record.updated_at;
    return;
  end if;

  if (
    select pg_catalog.count(*)
    from public.template_categories as current_category
    where current_category.owner_id = caller_id
  ) >= 25 then
    raise exception using errcode = '54000', message = 'template category capacity reached';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.template_categories (
    owner_id, name, normalized_name, creation_request_id, created_at, updated_at
  ) values (
    caller_id, canonical_name, pg_catalog.lower(canonical_name),
    create_template_category.creation_request_id, mutation_time, mutation_time
  ) returning * into category_record;

  return query select category_record.id, category_record.name,
    category_record.version, category_record.created_at, category_record.updated_at;
end;
$$;

create function public.rename_template_category(
  target_category_id uuid,
  new_name text,
  expected_category_version bigint
)
returns table (
  category_id uuid,
  name text,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  canonical_name text := private.canonical_category_name(new_name);
  category_record public.template_categories%rowtype;
  mutation_time timestamptz;
begin
  if target_category_id is null or expected_category_version is null
    or expected_category_version < 1 or canonical_name is null
    or pg_catalog.char_length(canonical_name) < 1
  then
    raise exception using errcode = '22023', message = 'invalid template category rename';
  end if;

  select current_category.* into category_record
  from public.template_categories as current_category
  where current_category.id = target_category_id
    and current_category.owner_id = caller_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'template category unavailable';
  end if;
  if category_record.name = canonical_name
    and expected_category_version in (category_record.version, category_record.version - 1)
  then
    return query select category_record.id, category_record.name,
      category_record.version, category_record.created_at, category_record.updated_at;
    return;
  end if;
  if category_record.version <> expected_category_version then
    raise exception using errcode = '40001', message = 'template category changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  update public.template_categories as changed_category
  set name = canonical_name,
      normalized_name = pg_catalog.lower(canonical_name),
      version = changed_category.version + 1,
      updated_at = mutation_time
  where changed_category.id = category_record.id
  returning * into category_record;

  return query select category_record.id, category_record.name,
    category_record.version, category_record.created_at, category_record.updated_at;
end;
$$;

create function public.delete_template_category(
  target_category_id uuid,
  expected_category_version bigint
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  category_record public.template_categories%rowtype;
  affected_count bigint;
  mutation_time timestamptz;
begin
  if target_category_id is null or expected_category_version is null
    or expected_category_version < 1
  then
    raise exception using errcode = '22023', message = 'invalid template category deletion';
  end if;

  select current_category.* into category_record
  from public.template_categories as current_category
  where current_category.id = target_category_id
    and current_category.owner_id = caller_id
  for update;
  if not found then
    return 0;
  end if;
  if category_record.version <> expected_category_version then
    raise exception using errcode = '40001', message = 'template category changed';
  end if;

  perform 1
  from public.templates as affected_template
  where affected_template.owner_id = caller_id
    and affected_template.category_id = target_category_id
  order by affected_template.id
  for update;

  mutation_time := pg_catalog.clock_timestamp();
  update public.templates as affected_template
  set category_id = null,
      version = affected_template.version + 1,
      updated_at = mutation_time
  where affected_template.owner_id = caller_id
    and affected_template.category_id = target_category_id;
  get diagnostics affected_count = row_count;

  delete from public.template_categories as deleted_category
  where deleted_category.id = category_record.id;
  return affected_count;
end;
$$;

create function public.create_private_template(
  new_name text,
  target_category_id uuid,
  creation_request_id uuid
)
returns table (
  template_id uuid,
  category_id uuid,
  name text,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  canonical_name text := private.canonical_template_name(new_name);
  template_record public.templates%rowtype;
  mutation_time timestamptz;
begin
  if creation_request_id is null or canonical_name is null
    or pg_catalog.char_length(canonical_name) < 1
  then
    raise exception using errcode = '22023', message = 'invalid template';
  end if;

  perform private.lock_template_owner(caller_id);
  perform private.require_owned_template_category(target_category_id, caller_id);

  select existing.* into template_record
  from public.templates as existing
  where existing.owner_id = caller_id
    and existing.creation_request_id = create_private_template.creation_request_id
  for update;
  if found then
    if template_record.name <> canonical_name
      or template_record.category_id is distinct from target_category_id
    then
      raise exception using
        errcode = '23505',
        message = 'template creation request conflict',
        constraint = 'templates_owner_request_key';
    end if;
    return query select template_record.id, template_record.category_id,
      template_record.name, template_record.version,
      template_record.created_at, template_record.updated_at;
    return;
  end if;

  if (
    select pg_catalog.count(*)
    from public.templates as current_template
    where current_template.owner_id = caller_id
  ) >= 100 then
    raise exception using errcode = '54000', message = 'template capacity reached';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.templates (
    owner_id, category_id, name, creation_request_id, created_at, updated_at
  ) values (
    caller_id, target_category_id, canonical_name,
    create_private_template.creation_request_id, mutation_time, mutation_time
  ) returning * into template_record;

  return query select template_record.id, template_record.category_id,
    template_record.name, template_record.version,
    template_record.created_at, template_record.updated_at;
end;
$$;

create function public.update_private_template(
  target_template_id uuid,
  new_name text,
  target_category_id uuid,
  expected_template_version bigint
)
returns table (
  template_id uuid,
  category_id uuid,
  name text,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  canonical_name text := private.canonical_template_name(new_name);
  template_record public.templates%rowtype;
  mutation_time timestamptz;
begin
  if target_template_id is null or expected_template_version is null
    or expected_template_version < 1 or canonical_name is null
    or pg_catalog.char_length(canonical_name) < 1
  then
    raise exception using errcode = '22023', message = 'invalid template update';
  end if;

  template_record := private.lock_owned_template(target_template_id, caller_id);
  perform private.require_owned_template_category(target_category_id, caller_id);
  if template_record.name = canonical_name
    and template_record.category_id is not distinct from target_category_id
    and expected_template_version in (template_record.version, template_record.version - 1)
  then
    return query select template_record.id, template_record.category_id,
      template_record.name, template_record.version,
      template_record.created_at, template_record.updated_at;
    return;
  end if;
  if template_record.version <> expected_template_version then
    raise exception using errcode = '40001', message = 'template changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  update public.templates as changed_template
  set name = canonical_name,
      category_id = target_category_id,
      version = changed_template.version + 1,
      updated_at = mutation_time
  where changed_template.id = template_record.id
  returning * into template_record;

  return query select template_record.id, template_record.category_id,
    template_record.name, template_record.version,
    template_record.created_at, template_record.updated_at;
end;
$$;

create function public.delete_private_template(
  target_template_id uuid,
  expected_template_version bigint
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  template_record public.templates%rowtype;
begin
  if target_template_id is null or expected_template_version is null
    or expected_template_version < 1
  then
    raise exception using errcode = '22023', message = 'invalid template deletion';
  end if;
  select current_template.* into template_record
  from public.templates as current_template
  where current_template.id = target_template_id
    and current_template.owner_id = caller_id
  for update;
  if not found then return false; end if;
  if template_record.version <> expected_template_version then
    raise exception using errcode = '40001', message = 'template changed';
  end if;
  delete from public.templates as deleted_template
  where deleted_template.id = template_record.id;
  return true;
end;
$$;

create function public.create_private_template_item(
  target_template_id uuid,
  new_name text,
  creation_request_id uuid,
  expected_template_version bigint,
  new_quantity_thousandths bigint default 1000
)
returns table (
  item_id uuid,
  template_version bigint,
  name text,
  quantity_thousandths bigint,
  "position" integer,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  canonical_name text := private.canonical_template_name(new_name);
  template_record public.templates%rowtype;
  item_record public.template_items%rowtype;
  next_position integer;
  mutation_time timestamptz;
begin
  if target_template_id is null or creation_request_id is null
    or expected_template_version is null or expected_template_version < 1
    or canonical_name is null or pg_catalog.char_length(canonical_name) not between 1 and 120
    or new_quantity_thousandths is null
    or new_quantity_thousandths not between 1 and 999999999
  then
    raise exception using errcode = '22023', message = 'invalid template item creation';
  end if;

  template_record := private.lock_owned_template(target_template_id, caller_id);
  select existing.* into item_record
  from public.template_items as existing
  where existing.template_id = target_template_id
    and existing.creation_request_id = create_private_template_item.creation_request_id
  for update;
  if found then
    if item_record.name <> canonical_name
      or item_record.quantity_thousandths <> new_quantity_thousandths
    then
      raise exception using
        errcode = '23505',
        message = 'template item creation request conflict',
        constraint = 'template_items_template_request_key';
    end if;
    if expected_template_version not in (template_record.version, template_record.version - 1) then
      raise exception using errcode = '40001', message = 'template changed';
    end if;
    return query select item_record.id, template_record.version, item_record.name,
      item_record.quantity_thousandths, item_record.position, item_record.version,
      item_record.created_at, item_record.updated_at;
    return;
  end if;

  if template_record.version <> expected_template_version then
    raise exception using errcode = '40001', message = 'template changed';
  end if;
  if (
    select pg_catalog.count(*)
    from public.template_items as current_item
    where current_item.template_id = target_template_id
  ) >= 200 then
    raise exception using errcode = '54000', message = 'template item capacity reached';
  end if;

  select coalesce(pg_catalog.max(current_item.position), 0) + 1
  into next_position
  from public.template_items as current_item
  where current_item.template_id = target_template_id;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.template_items (
    template_id, name, quantity_thousandths, position,
    creation_request_id, created_at, updated_at
  ) values (
    target_template_id, canonical_name, new_quantity_thousandths, next_position,
    create_private_template_item.creation_request_id, mutation_time, mutation_time
  ) returning * into item_record;

  update public.templates as changed_template
  set version = changed_template.version + 1,
      updated_at = mutation_time
  where changed_template.id = template_record.id
  returning * into template_record;

  return query select item_record.id, template_record.version, item_record.name,
    item_record.quantity_thousandths, item_record.position, item_record.version,
    item_record.created_at, item_record.updated_at;
end;
$$;

create function public.update_private_template_item(
  target_template_id uuid,
  target_item_id uuid,
  new_name text,
  new_quantity_thousandths bigint,
  expected_template_version bigint,
  expected_item_version bigint
)
returns table (
  item_id uuid,
  template_version bigint,
  name text,
  quantity_thousandths bigint,
  "position" integer,
  version bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  canonical_name text := private.canonical_template_name(new_name);
  template_record public.templates%rowtype;
  item_record public.template_items%rowtype;
  mutation_time timestamptz;
begin
  if target_template_id is null or target_item_id is null
    or expected_template_version is null or expected_template_version < 1
    or expected_item_version is null or expected_item_version < 1
    or canonical_name is null or pg_catalog.char_length(canonical_name) not between 1 and 120
    or new_quantity_thousandths is null
    or new_quantity_thousandths not between 1 and 999999999
  then
    raise exception using errcode = '22023', message = 'invalid template item update';
  end if;

  template_record := private.lock_owned_template(target_template_id, caller_id);
  select current_item.* into item_record
  from public.template_items as current_item
  where current_item.id = target_item_id
    and current_item.template_id = target_template_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'template item unavailable';
  end if;

  if item_record.name = canonical_name
    and item_record.quantity_thousandths = new_quantity_thousandths
    and expected_template_version in (template_record.version, template_record.version - 1)
    and expected_item_version in (item_record.version, item_record.version - 1)
  then
    return query select item_record.id, template_record.version, item_record.name,
      item_record.quantity_thousandths, item_record.position, item_record.version,
      item_record.created_at, item_record.updated_at;
    return;
  end if;
  if template_record.version <> expected_template_version
    or item_record.version <> expected_item_version
  then
    raise exception using errcode = '40001', message = 'template changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  update public.template_items as changed_item
  set name = canonical_name,
      quantity_thousandths = new_quantity_thousandths,
      version = changed_item.version + 1,
      updated_at = mutation_time
  where changed_item.id = item_record.id
  returning * into item_record;

  update public.templates as changed_template
  set version = changed_template.version + 1,
      updated_at = mutation_time
  where changed_template.id = template_record.id
  returning * into template_record;

  return query select item_record.id, template_record.version, item_record.name,
    item_record.quantity_thousandths, item_record.position, item_record.version,
    item_record.created_at, item_record.updated_at;
end;
$$;

create function public.delete_private_template_item(
  target_template_id uuid,
  target_item_id uuid,
  expected_template_version bigint,
  expected_item_version bigint
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  template_record public.templates%rowtype;
  item_record public.template_items%rowtype;
  mutation_time timestamptz;
begin
  if target_template_id is null or target_item_id is null
    or expected_template_version is null or expected_template_version < 1
    or expected_item_version is null or expected_item_version < 1
  then
    raise exception using errcode = '22023', message = 'invalid template item deletion';
  end if;

  template_record := private.lock_owned_template(target_template_id, caller_id);
  select current_item.* into item_record
  from public.template_items as current_item
  where current_item.id = target_item_id
    and current_item.template_id = target_template_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'template item unavailable';
  end if;
  if template_record.version <> expected_template_version
    or item_record.version <> expected_item_version
  then
    raise exception using errcode = '40001', message = 'template changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  delete from public.template_items as deleted_item
  where deleted_item.id = item_record.id;
  update public.templates as changed_template
  set version = changed_template.version + 1,
      updated_at = mutation_time
  where changed_template.id = template_record.id
  returning * into template_record;
  return template_record.version;
end;
$$;

create function public.reorder_private_template_items(
  target_template_id uuid,
  ordered_item_ids uuid[],
  expected_template_version bigint
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  template_record public.templates%rowtype;
  current_item_ids uuid[];
  item_count integer;
  mutation_time timestamptz;
begin
  if target_template_id is null or ordered_item_ids is null
    or expected_template_version is null or expected_template_version < 1
    or pg_catalog.array_position(ordered_item_ids, null::uuid) is not null
    or exists (
      select submitted.item_id
      from pg_catalog.unnest(ordered_item_ids) as submitted(item_id)
      group by submitted.item_id
      having pg_catalog.count(*) > 1
    )
  then
    raise exception using errcode = '22023', message = 'invalid template item order';
  end if;

  template_record := private.lock_owned_template(target_template_id, caller_id);
  perform 1
  from public.template_items as lock_item
  where lock_item.template_id = target_template_id
  order by lock_item.id
  for update;
  select
    coalesce(
      pg_catalog.array_agg(item_record.id order by item_record.position),
      '{}'::uuid[]
    ),
    pg_catalog.count(*)::integer
  into current_item_ids, item_count
  from public.template_items as item_record
  where item_record.template_id = target_template_id;

  if pg_catalog.cardinality(ordered_item_ids) <> item_count
    or exists (
      select 1
      from pg_catalog.unnest(ordered_item_ids) as submitted(item_id)
      where not exists (
        select 1
        from public.template_items as current_item
        where current_item.template_id = target_template_id
          and current_item.id = submitted.item_id
      )
    )
  then
    raise exception using errcode = '22023', message = 'invalid template item order';
  end if;

  if current_item_ids = ordered_item_ids
    and expected_template_version in (template_record.version, template_record.version - 1)
  then
    return template_record.version;
  end if;
  if template_record.version <> expected_template_version then
    raise exception using errcode = '40001', message = 'template changed';
  end if;
  if item_count = 0 then return template_record.version; end if;

  update public.template_items as changed_item
  set position = changed_item.position + item_count
  where changed_item.template_id = target_template_id;
  update public.template_items as changed_item
  set position = submitted.ordinality::integer
  from pg_catalog.unnest(ordered_item_ids) with ordinality
    as submitted(item_id, ordinality)
  where changed_item.template_id = target_template_id
    and changed_item.id = submitted.item_id;

  mutation_time := pg_catalog.clock_timestamp();
  update public.templates as changed_template
  set version = changed_template.version + 1,
      updated_at = mutation_time
  where changed_template.id = template_record.id
  returning * into template_record;
  return template_record.version;
end;
$$;

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
  if (
    select pg_catalog.count(*)
    from public.active_list_items as current_item
    where current_item.list_id = target_list_id
  ) >= 200 then
    raise exception using errcode = '54000', message = 'list item capacity reached';
  end if;
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

create function public.save_active_list_as_template(
  source_list_id uuid,
  selected_item_ids uuid[],
  new_template_name text,
  target_category_id uuid,
  creation_request_id uuid,
  expected_list_version bigint
)
returns table (
  template_id uuid,
  category_id uuid,
  name text,
  version bigint,
  item_count integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  canonical_name text := private.canonical_template_name(new_template_name);
  list_record public.active_lists%rowtype;
  template_record public.templates%rowtype;
  selected_count integer := pg_catalog.cardinality(selected_item_ids);
  mutation_time timestamptz;
begin
  if source_list_id is null or selected_item_ids is null
    or selected_count not between 1 and 200
    or creation_request_id is null
    or expected_list_version is null or expected_list_version < 1
    or canonical_name is null or pg_catalog.char_length(canonical_name) < 1
    or pg_catalog.array_position(selected_item_ids, null::uuid) is not null
    or exists (
      select submitted.item_id
      from pg_catalog.unnest(selected_item_ids) as submitted(item_id)
      group by submitted.item_id
      having pg_catalog.count(*) > 1
    )
  then
    raise exception using errcode = '22023', message = 'invalid list template snapshot';
  end if;

  perform private.lock_template_owner(caller_id);
  perform private.require_owned_template_category(target_category_id, caller_id);
  select current_list.* into list_record
  from public.active_lists as current_list
  where current_list.id = source_list_id
  for update;
  if not found or not private.active_list_caller_is_member(source_list_id, caller_id) then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  if list_record.version <> expected_list_version then
    raise exception using errcode = '40001', message = 'list changed';
  end if;

  perform 1
  from public.active_list_items as lock_item
  where lock_item.list_id = source_list_id
    and lock_item.id = any(selected_item_ids)
  order by lock_item.id
  for update;
  if (
    select pg_catalog.count(*)
    from public.active_list_items as selected_item
    where selected_item.list_id = source_list_id
      and selected_item.id = any(selected_item_ids)
  ) <> selected_count then
    raise exception using errcode = '22023', message = 'invalid list template selection';
  end if;

  select existing.* into template_record
  from public.templates as existing
  where existing.owner_id = caller_id
    and existing.creation_request_id = save_active_list_as_template.creation_request_id
  for update;
  if found then
    if template_record.name <> canonical_name
      or template_record.category_id is distinct from target_category_id
      or exists (
        select 1
        from (
          select source_item.name, source_item.quantity_thousandths,
            pg_catalog.row_number() over (
              order by source_item.position, source_item.id
            ) as ordinal
          from public.active_list_items as source_item
          where source_item.list_id = source_list_id
            and source_item.id = any(selected_item_ids)
        ) as source_snapshot
        full join (
          select copied_item.name, copied_item.quantity_thousandths,
            pg_catalog.row_number() over (
              order by copied_item.position, copied_item.id
            ) as ordinal
          from public.template_items as copied_item
          where copied_item.template_id = template_record.id
        ) as copied_snapshot using (ordinal)
        where source_snapshot.name is distinct from copied_snapshot.name
          or source_snapshot.quantity_thousandths
            is distinct from copied_snapshot.quantity_thousandths
      )
    then
      raise exception using
        errcode = '23505',
        message = 'template creation request conflict',
        constraint = 'templates_owner_request_key';
    end if;
    return query select template_record.id, template_record.category_id,
      template_record.name, template_record.version,
      (select pg_catalog.count(*)::integer from public.template_items as existing_item
       where existing_item.template_id = template_record.id),
      template_record.created_at, template_record.updated_at;
    return;
  end if;

  if (
    select pg_catalog.count(*)
    from public.templates as current_template
    where current_template.owner_id = caller_id
  ) >= 100 then
    raise exception using errcode = '54000', message = 'template capacity reached';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.templates (
    owner_id, category_id, name, creation_request_id, created_at, updated_at
  ) values (
    caller_id, target_category_id, canonical_name,
    save_active_list_as_template.creation_request_id, mutation_time, mutation_time
  ) returning * into template_record;

  insert into public.template_items (
    template_id, name, quantity_thousandths, position,
    creation_request_id, created_at, updated_at
  )
  select
    template_record.id,
    source_item.name,
    source_item.quantity_thousandths,
    pg_catalog.row_number() over (order by source_item.position, source_item.id)::integer,
    pg_catalog.gen_random_uuid(),
    mutation_time,
    mutation_time
  from public.active_list_items as source_item
  where source_item.list_id = source_list_id
    and source_item.id = any(selected_item_ids)
  order by source_item.position, source_item.id;

  return query select template_record.id, template_record.category_id,
    template_record.name, template_record.version, selected_count,
    template_record.created_at, template_record.updated_at;
end;
$$;

create function public.create_active_list_from_template(
  source_template_id uuid,
  selected_item_ids uuid[],
  new_list_title text,
  list_creation_request_id uuid,
  item_creation_request_ids uuid[],
  expected_template_version bigint
)
returns table (
  list_id uuid,
  title text,
  version bigint,
  item_count integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  canonical_title text := pg_catalog.regexp_replace(new_list_title, '^[[:space:]]+|[[:space:]]+$', '', 'g');
  template_record public.templates%rowtype;
  list_record public.active_lists%rowtype;
  selected_count integer := pg_catalog.cardinality(selected_item_ids);
  mutation_time timestamptz;
begin
  if source_template_id is null or selected_item_ids is null
    or selected_count not between 1 and 200
    or item_creation_request_ids is null
    or pg_catalog.cardinality(item_creation_request_ids) <> selected_count
    or list_creation_request_id is null
    or expected_template_version is null or expected_template_version < 1
    or canonical_title is null or pg_catalog.char_length(canonical_title) not between 1 and 80
    or pg_catalog.array_position(selected_item_ids, null::uuid) is not null
    or pg_catalog.array_position(item_creation_request_ids, null::uuid) is not null
    or exists (
      select submitted.item_id
      from pg_catalog.unnest(selected_item_ids) as submitted(item_id)
      group by submitted.item_id having pg_catalog.count(*) > 1
    )
    or exists (
      select submitted.request_id
      from pg_catalog.unnest(item_creation_request_ids) as submitted(request_id)
      group by submitted.request_id having pg_catalog.count(*) > 1
    )
  then
    raise exception using errcode = '22023', message = 'invalid template list creation';
  end if;

  template_record := private.lock_owned_template(source_template_id, caller_id);
  if template_record.version <> expected_template_version then
    raise exception using errcode = '40001', message = 'template changed';
  end if;
  perform 1
  from public.template_items as lock_item
  where lock_item.template_id = source_template_id
    and lock_item.id = any(selected_item_ids)
  order by lock_item.id
  for update;
  if (
    select pg_catalog.count(*)
    from public.template_items as selected_item
    where selected_item.template_id = source_template_id
      and selected_item.id = any(selected_item_ids)
  ) <> selected_count then
    raise exception using errcode = '22023', message = 'invalid template selection';
  end if;

  select existing.* into list_record
  from public.active_lists as existing
  where existing.owner_id = caller_id
    and existing.creation_request_id = list_creation_request_id
  for update;
  if found then
    if list_record.title <> canonical_title
      or exists (
        select 1
        from pg_catalog.unnest(selected_item_ids) with ordinality
          as selected(item_id, ordinality)
        join pg_catalog.unnest(item_creation_request_ids) with ordinality
          as requested(request_id, ordinality)
          using (ordinality)
        join public.template_items as source_item
          on source_item.template_id = source_template_id
         and source_item.id = selected.item_id
        left join public.active_list_items as copied_item
          on copied_item.list_id = list_record.id
         and copied_item.creation_request_id = requested.request_id
        where copied_item.id is null
          or copied_item.name <> source_item.name
          or copied_item.quantity_thousandths <> source_item.quantity_thousandths
          or copied_item.unit_code is not null
      )
    then
      raise exception using
        errcode = '23505',
        message = 'list creation request conflict',
        constraint = 'active_lists_owner_creation_request_key';
    end if;
    if (
      select pg_catalog.count(*)
      from public.active_list_items as existing_item
      where existing_item.list_id = list_record.id
        and existing_item.creation_request_id = any(item_creation_request_ids)
    ) <> selected_count then
      raise exception using errcode = '23505', message = 'list copy request conflict';
    end if;
    return query select list_record.id, list_record.title, list_record.version,
      selected_count, list_record.created_at, list_record.updated_at;
    return;
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.active_lists (
    owner_id, title, creation_request_id, created_at, updated_at
  ) values (
    caller_id, canonical_title, list_creation_request_id, mutation_time, mutation_time
  ) returning * into list_record;

  insert into public.active_list_items (
    list_id, name, quantity_thousandths, unit_code, position,
    creation_request_id, created_at, updated_at
  )
  select
    list_record.id,
    source_item.name,
    source_item.quantity_thousandths,
    null,
    pg_catalog.row_number() over (
      order by source_item.position, source_item.id
    )::integer,
    requested.request_id,
    mutation_time,
    mutation_time
  from pg_catalog.unnest(selected_item_ids) with ordinality
    as selected(item_id, ordinality)
  join pg_catalog.unnest(item_creation_request_ids) with ordinality
    as requested(request_id, ordinality)
    using (ordinality)
  join public.template_items as source_item
    on source_item.template_id = source_template_id
   and source_item.id = selected.item_id
  order by source_item.position, source_item.id;

  return query select list_record.id, list_record.title, list_record.version,
    selected_count, list_record.created_at, list_record.updated_at;
end;
$$;

create function public.import_private_template_items(
  source_template_id uuid,
  selected_item_ids uuid[],
  target_list_id uuid,
  item_creation_request_ids uuid[],
  expected_template_version bigint,
  expected_list_version bigint
)
returns table (
  list_version bigint,
  imported_count integer,
  remaining_capacity integer
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  template_record public.templates%rowtype;
  list_record public.active_lists%rowtype;
  selected_count integer := pg_catalog.cardinality(selected_item_ids);
  current_count integer;
  existing_request_count integer;
  next_position integer;
  mutation_time timestamptz;
begin
  if source_template_id is null or target_list_id is null
    or selected_item_ids is null or selected_count not between 1 and 200
    or item_creation_request_ids is null
    or pg_catalog.cardinality(item_creation_request_ids) <> selected_count
    or expected_template_version is null or expected_template_version < 1
    or expected_list_version is null or expected_list_version < 1
    or pg_catalog.array_position(selected_item_ids, null::uuid) is not null
    or pg_catalog.array_position(item_creation_request_ids, null::uuid) is not null
    or exists (
      select submitted.item_id
      from pg_catalog.unnest(selected_item_ids) as submitted(item_id)
      group by submitted.item_id having pg_catalog.count(*) > 1
    )
    or exists (
      select submitted.request_id
      from pg_catalog.unnest(item_creation_request_ids) as submitted(request_id)
      group by submitted.request_id having pg_catalog.count(*) > 1
    )
  then
    raise exception using errcode = '22023', message = 'invalid template import';
  end if;

  list_record := private.lock_mutable_active_list(target_list_id, caller_id);
  template_record := private.lock_owned_template(source_template_id, caller_id);
  if template_record.version <> expected_template_version then
    raise exception using errcode = '40001', message = 'template changed';
  end if;

  perform 1
  from public.template_items as lock_item
  where lock_item.template_id = source_template_id
    and lock_item.id = any(selected_item_ids)
  order by lock_item.id
  for update;
  if (
    select pg_catalog.count(*)
    from public.template_items as selected_item
    where selected_item.template_id = source_template_id
      and selected_item.id = any(selected_item_ids)
  ) <> selected_count then
    raise exception using errcode = '22023', message = 'invalid template selection';
  end if;

  select pg_catalog.count(*)::integer,
    coalesce(pg_catalog.max(current_item.position), 0) + 1
  into current_count, next_position
  from public.active_list_items as current_item
  where current_item.list_id = target_list_id;
  select pg_catalog.count(*)::integer into existing_request_count
  from public.active_list_items as existing_item
  where existing_item.list_id = target_list_id
    and existing_item.creation_request_id = any(item_creation_request_ids);

  if existing_request_count = selected_count then
    if list_record.version not in (expected_list_version, expected_list_version + 1)
      or exists (
        select 1
        from pg_catalog.unnest(selected_item_ids) with ordinality
          as selected(item_id, ordinality)
        join pg_catalog.unnest(item_creation_request_ids) with ordinality
          as requested(request_id, ordinality)
          using (ordinality)
        join public.template_items as source_item
          on source_item.template_id = source_template_id
         and source_item.id = selected.item_id
        left join public.active_list_items as copied_item
          on copied_item.list_id = target_list_id
         and copied_item.creation_request_id = requested.request_id
        where copied_item.id is null
          or copied_item.name <> source_item.name
          or copied_item.quantity_thousandths <> source_item.quantity_thousandths
          or copied_item.unit_code is not null
      )
    then
      raise exception using errcode = '23505', message = 'list import request conflict';
    end if;
    return query select list_record.version, selected_count,
      greatest(200 - current_count, 0);
    return;
  elsif existing_request_count <> 0 then
    raise exception using errcode = '23505', message = 'partial list import request conflict';
  end if;

  if list_record.version <> expected_list_version then
    raise exception using errcode = '40001', message = 'list changed';
  end if;
  if current_count >= 200 or selected_count > 200 - current_count then
    raise exception using errcode = '54000', message = 'list item capacity reached';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.active_list_items (
    list_id, name, quantity_thousandths, unit_code, position,
    creation_request_id, created_at, updated_at
  )
  select
    target_list_id,
    source_item.name,
    source_item.quantity_thousandths,
    null,
    (
      next_position + pg_catalog.row_number() over (
        order by source_item.position, source_item.id
      ) - 1
    )::integer,
    requested.request_id,
    mutation_time,
    mutation_time
  from pg_catalog.unnest(selected_item_ids) with ordinality
    as selected(item_id, ordinality)
  join pg_catalog.unnest(item_creation_request_ids) with ordinality
    as requested(request_id, ordinality)
    using (ordinality)
  join public.template_items as source_item
    on source_item.template_id = source_template_id
   and source_item.id = selected.item_id
  order by source_item.position, source_item.id;

  update public.active_lists as changed_list
  set version = changed_list.version + 1,
      updated_at = mutation_time
  where changed_list.id = list_record.id
  returning * into list_record;

  return query select list_record.version, selected_count,
    200 - current_count - selected_count;
end;
$$;

alter function public.export_own_account_data()
rename to export_own_account_data_v3_base;
alter function public.export_own_account_data_v3_base()
set schema private;
revoke all on function private.export_own_account_data_v3_base()
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
  category_export jsonb := '[]'::jsonb;
  template_export jsonb := '[]'::jsonb;
begin
  base_export := private.export_own_account_data_v3_base();
  caller_id := (select auth.uid());

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'category_id', category_record.id,
        'name', category_record.name,
        'version', category_record.version,
        'created_at', category_record.created_at,
        'updated_at', category_record.updated_at
      ) order by category_record.normalized_name, category_record.id
    ),
    '[]'::jsonb
  ) into category_export
  from public.template_categories as category_record
  where category_record.owner_id = caller_id;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'template_id', template_record.id,
        'category_id', template_record.category_id,
        'name', template_record.name,
        'version', template_record.version,
        'created_at', template_record.created_at,
        'updated_at', template_record.updated_at,
        'items', (
          select coalesce(
            pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'item_id', item_record.id,
                'name', item_record.name,
                'quantity_thousandths', item_record.quantity_thousandths,
                'position', item_record.position,
                'version', item_record.version,
                'created_at', item_record.created_at,
                'updated_at', item_record.updated_at
              ) order by item_record.position, item_record.id
            ),
            '[]'::jsonb
          )
          from public.template_items as item_record
          where item_record.template_id = template_record.id
        )
      ) order by template_record.updated_at desc, template_record.id
    ),
    '[]'::jsonb
  ) into template_export
  from public.templates as template_record
  where template_record.owner_id = caller_id;

  return base_export || pg_catalog.jsonb_build_object(
    'schema_version', 4,
    'template_categories', category_export,
    'templates', template_export
  );
end;
$$;

create function private.broadcast_private_template_invalidation()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  recipient_id uuid;
begin
  recipient_id := case when tg_op = 'DELETE' then old.owner_id else new.owner_id end;
  perform private.send_account_invalidations(array[recipient_id]);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

alter function private.broadcast_private_template_invalidation() owner to postgres;
revoke all on function private.broadcast_private_template_invalidation()
from public, anon, authenticated, service_role;

create trigger template_categories_broadcast_invalidation
after insert or update or delete on public.template_categories
for each row execute function private.broadcast_private_template_invalidation();

create trigger templates_broadcast_invalidation
after insert or update or delete on public.templates
for each row execute function private.broadcast_private_template_invalidation();

alter function public.list_template_categories() owner to postgres;
alter function public.list_private_templates(text, uuid, boolean, text) owner to postgres;
alter function public.get_private_template(uuid) owner to postgres;
alter function public.list_private_template_items(uuid) owner to postgres;
alter function public.create_template_category(text, uuid) owner to postgres;
alter function public.rename_template_category(uuid, text, bigint) owner to postgres;
alter function public.delete_template_category(uuid, bigint) owner to postgres;
alter function public.create_private_template(text, uuid, uuid) owner to postgres;
alter function public.update_private_template(uuid, text, uuid, bigint) owner to postgres;
alter function public.delete_private_template(uuid, bigint) owner to postgres;
alter function public.create_private_template_item(uuid, text, uuid, bigint, bigint) owner to postgres;
alter function public.update_private_template_item(uuid, uuid, text, bigint, bigint, bigint) owner to postgres;
alter function public.delete_private_template_item(uuid, uuid, bigint, bigint) owner to postgres;
alter function public.reorder_private_template_items(uuid, uuid[], bigint) owner to postgres;
alter function public.create_active_list_item(uuid, text, uuid, bigint, bigint, text) owner to postgres;
alter function public.save_active_list_as_template(uuid, uuid[], text, uuid, uuid, bigint) owner to postgres;
alter function public.create_active_list_from_template(uuid, uuid[], text, uuid, uuid[], bigint) owner to postgres;
alter function public.import_private_template_items(uuid, uuid[], uuid, uuid[], bigint, bigint) owner to postgres;
alter function private.export_own_account_data_v3_base() owner to postgres;
alter function public.export_own_account_data() owner to postgres;

revoke all on function public.list_template_categories()
from public, anon, authenticated, service_role;
revoke all on function public.list_private_templates(text, uuid, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_private_template(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.list_private_template_items(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.create_template_category(text, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.rename_template_category(uuid, text, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.delete_template_category(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.create_private_template(text, uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.update_private_template(uuid, text, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.delete_private_template(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.create_private_template_item(uuid, text, uuid, bigint, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.update_private_template_item(uuid, uuid, text, bigint, bigint, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.delete_private_template_item(uuid, uuid, bigint, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.reorder_private_template_items(uuid, uuid[], bigint)
from public, anon, authenticated, service_role;
revoke all on function public.create_active_list_item(uuid, text, uuid, bigint, bigint, text)
from public, anon, authenticated, service_role;
revoke all on function public.save_active_list_as_template(uuid, uuid[], text, uuid, uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.create_active_list_from_template(uuid, uuid[], text, uuid, uuid[], bigint)
from public, anon, authenticated, service_role;
revoke all on function public.import_private_template_items(uuid, uuid[], uuid, uuid[], bigint, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data()
from public, anon, authenticated, service_role;

grant execute on function public.list_template_categories() to authenticated;
grant execute on function public.list_private_templates(text, uuid, boolean, text) to authenticated;
grant execute on function public.get_private_template(uuid) to authenticated;
grant execute on function public.list_private_template_items(uuid) to authenticated;
grant execute on function public.create_template_category(text, uuid) to authenticated;
grant execute on function public.rename_template_category(uuid, text, bigint) to authenticated;
grant execute on function public.delete_template_category(uuid, bigint) to authenticated;
grant execute on function public.create_private_template(text, uuid, uuid) to authenticated;
grant execute on function public.update_private_template(uuid, text, uuid, bigint) to authenticated;
grant execute on function public.delete_private_template(uuid, bigint) to authenticated;
grant execute on function public.create_private_template_item(uuid, text, uuid, bigint, bigint) to authenticated;
grant execute on function public.update_private_template_item(uuid, uuid, text, bigint, bigint, bigint) to authenticated;
grant execute on function public.delete_private_template_item(uuid, uuid, bigint, bigint) to authenticated;
grant execute on function public.reorder_private_template_items(uuid, uuid[], bigint) to authenticated;
grant execute on function public.create_active_list_item(uuid, text, uuid, bigint, bigint, text) to authenticated;
grant execute on function public.save_active_list_as_template(uuid, uuid[], text, uuid, uuid, bigint) to authenticated;
grant execute on function public.create_active_list_from_template(uuid, uuid[], text, uuid, uuid[], bigint) to authenticated;
grant execute on function public.import_private_template_items(uuid, uuid[], uuid, uuid[], bigint, bigint) to authenticated;
grant execute on function public.export_own_account_data() to authenticated;

comment on table public.template_categories is
  'RPC-only private template categories owned by one completed profile.';
comment on table public.templates is
  'RPC-only private reusable templates with optional owner-scoped category placement.';
comment on table public.template_items is
  'RPC-only ordered private template items containing only name and exact quantity.';
comment on function public.list_template_categories() is
  'Returns every caller-owned category, including empty categories, with template counts.';
comment on function public.list_private_templates(text, uuid, boolean, text) is
  'Returns at most the caller-owned 100-template summary projection with search, category filter, and sort.';
comment on function public.get_private_template(uuid) is
  'Returns one caller-owned template summary and authoritative remaining item capacity.';
comment on function public.list_private_template_items(uuid) is
  'Returns caller-owned template items in authoritative order.';
comment on function public.create_template_category(text, uuid) is
  'Creates one normalized caller-owned category under the serialized 25-category quota.';
comment on function public.rename_template_category(uuid, text, bigint) is
  'Version-checks a caller-owned normalized category rename.';
comment on function public.delete_template_category(uuid, bigint) is
  'Atomically moves affected templates to Uncategorized before deleting the category.';
comment on function public.create_private_template(text, uuid, uuid) is
  'Creates one blank caller-owned template under the serialized 100-template quota.';
comment on function public.update_private_template(uuid, text, uuid, bigint) is
  'Version-checks caller-owned template rename and recategorization.';
comment on function public.delete_private_template(uuid, bigint) is
  'Permanently deletes one exact caller-owned template without affecting lists.';
comment on function public.create_private_template_item(uuid, text, uuid, bigint, bigint) is
  'Adds one exact caller-owned template item under the transactional 200-item capacity.';
comment on function public.update_private_template_item(uuid, uuid, text, bigint, bigint, bigint) is
  'Version-checks caller-owned template item name and quantity changes.';
comment on function public.delete_private_template_item(uuid, uuid, bigint, bigint) is
  'Version-checks permanent item deletion and immediately frees one template capacity place.';
comment on function public.reorder_private_template_items(uuid, uuid[], bigint) is
  'Atomically versions one exact caller-owned template item order.';
comment on function public.create_active_list_item(uuid, text, uuid, bigint, bigint, text) is
  'Adds one owner-or-member item while enforcing the non-destructive 200-current-item list limit.';
comment on function public.save_active_list_as_template(uuid, uuid[], text, uuid, uuid, bigint) is
  'Atomically snapshots 1-200 selected accessible list items into one independent private template.';
comment on function public.create_active_list_from_template(uuid, uuid[], text, uuid, uuid[], bigint) is
  'Atomically creates one caller-owned active list from 1-200 selected private template items.';
comment on function public.import_private_template_items(uuid, uuid[], uuid, uuid[], bigint, bigint) is
  'Atomically imports selected private template items under active-list access, version, and remaining capacity.';
comment on function private.export_own_account_data_v3_base() is
  'Internal frozen schema-version-3 allowlist used only to compose version 4.';
comment on function public.export_own_account_data() is
  'Returns schema-version-4 own data including caller-owned categories, templates, and ordered template items.';
comment on function private.broadcast_private_template_invalidation() is
  'Sends only the existing private account invalidation after category or template writes.';
