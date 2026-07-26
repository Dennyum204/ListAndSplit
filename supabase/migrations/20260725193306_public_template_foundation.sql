alter table public.templates
add column published_at timestamptz;

alter table public.templates
add constraint templates_public_name_check check (
  published_at is null
  or (
    name = pg_catalog.regexp_replace(
      name,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    )
    and pg_catalog.char_length(name) between 1 and 120
  )
);

create index templates_owner_public_keyset_idx
on public.templates (owner_id, published_at desc, id desc)
where published_at is not null;

create table private.public_template_copy_requests (
  owner_id uuid not null,
  request_id uuid not null,
  request_fingerprint bytea not null,
  copied_template_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint public_template_copy_requests_pkey
    primary key (owner_id, request_id),
  constraint public_template_copy_requests_owner_fkey
    foreign key (owner_id)
    references public.profiles(id)
    on delete cascade,
  constraint public_template_copy_requests_destination_fkey
    foreign key (owner_id, copied_template_id)
    references public.templates(owner_id, id)
    on delete cascade,
  constraint public_template_copy_requests_fingerprint_check
    check (pg_catalog.octet_length(request_fingerprint) = 32)
);

create index public_template_copy_requests_destination_idx
on private.public_template_copy_requests (owner_id, copied_template_id);

alter table private.public_template_copy_requests owner to postgres;
alter table private.public_template_copy_requests enable row level security;
alter table private.public_template_copy_requests force row level security;

revoke all on table private.public_template_copy_requests
from public, anon, authenticated, service_role;

create policy "public_template_copy_requests_reject_direct_client_access"
on private.public_template_copy_requests
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create function private.public_template_copy_fingerprint(
  source_template_id uuid,
  expected_source_version bigint
)
returns bytea
language sql
immutable
security invoker
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(
      'list-and-split:public-template-copy:v1:'
      || source_template_id::text
      || ':'
      || expected_source_version::text,
      'UTF8'
    ),
    'sha256'
  );
$$;

create function public.list_private_templates_v2(
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
  is_public boolean,
  published_at timestamptz,
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
    raise exception using
      errcode = '22023',
      message = 'invalid template query';
  end if;

  if normalized_search = '' then
    normalized_search := null;
  end if;

  return query
  select
    template_record.id,
    template_record.category_id,
    category_record.name,
    template_record.name,
    template_record.version,
    pg_catalog.count(item_record.id)::bigint,
    template_record.published_at is not null,
    template_record.published_at,
    template_record.created_at,
    template_record.updated_at
  from public.templates as template_record
  left join public.template_categories as category_record
    on category_record.owner_id = template_record.owner_id
   and category_record.id = template_record.category_id
  left join public.template_items as item_record
    on item_record.template_id = template_record.id
  where template_record.owner_id = caller_id
    and (
      category_filter is null
      or template_record.category_id = category_filter
    )
    and (
      not coalesce(uncategorized_only, false)
      or template_record.category_id is null
    )
    and (
      normalized_search is null
      or pg_catalog.strpos(
        private.normalized_template_search(template_record.name),
        normalized_search
      ) > 0
      or exists (
        select 1
        from public.template_items as searched_item
        where searched_item.template_id = template_record.id
          and pg_catalog.strpos(
            private.normalized_template_search(searched_item.name),
            normalized_search
          ) > 0
      )
    )
  group by template_record.id, category_record.name
  order by
    case
      when sort_mode = 'recent' then template_record.updated_at
    end desc,
    case
      when sort_mode = 'alpha'
        then private.normalized_template_search(template_record.name)
    end asc,
    case
      when sort_mode = 'newest' then template_record.created_at
    end desc,
    template_record.id;
end;
$$;

create function public.get_private_template_v2(
  target_template_id uuid
)
returns table (
  template_id uuid,
  category_id uuid,
  category_name text,
  name text,
  version bigint,
  item_count bigint,
  remaining_capacity integer,
  is_public boolean,
  published_at timestamptz,
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
    greatest(
      200::bigint - pg_catalog.count(item_record.id),
      0::bigint
    )::integer,
    template_record.published_at is not null,
    template_record.published_at,
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

create function public.set_template_publication(
  target_template_id uuid,
  desired_public boolean,
  expected_template_version bigint
)
returns table (
  template_id uuid,
  version bigint,
  is_public boolean,
  published_at timestamptz,
  updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  template_record public.templates%rowtype;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if target_template_id is null
    or desired_public is null
    or expected_template_version is null
    or expected_template_version < 1
  then
    raise exception using
      errcode = '22023',
      message = 'invalid template publication';
  end if;

  template_record := private.lock_owned_template(
    target_template_id,
    caller_id
  );

  if (template_record.published_at is not null) = desired_public then
    return query
    select
      template_record.id,
      template_record.version,
      template_record.published_at is not null,
      template_record.published_at,
      template_record.updated_at;
    return;
  end if;

  if template_record.version <> expected_template_version then
    raise exception using
      errcode = '40001',
      message = 'template changed';
  end if;

  if desired_public
    and pg_catalog.char_length(template_record.name) not between 1 and 120
  then
    raise exception using
      errcode = '22023',
      message = 'invalid public template name';
  end if;

  update public.templates as changed_template
  set published_at = case
        when desired_public then mutation_time
        else null
      end,
      version = changed_template.version + 1,
      updated_at = mutation_time
  where changed_template.id = template_record.id
  returning changed_template.*
  into template_record;

  return query
  select
    template_record.id,
    template_record.version,
    template_record.published_at is not null,
    template_record.published_at,
    template_record.updated_at;
end;
$$;

create function public.list_public_profile_templates(
  target_profile_id uuid,
  requested_page_size integer default 20,
  cursor_published_at timestamptz default null,
  cursor_template_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  profile_document jsonb;
  template_documents jsonb;
  next_cursor jsonb;
begin
  if target_profile_id is null
    or requested_page_size is null
    or requested_page_size not between 1 and 50
    or (
      (cursor_published_at is null)
      <> (cursor_template_id is null)
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid public template query';
  end if;

  select pg_catalog.jsonb_build_object(
    'profile_id', target_profile.id,
    'username', target_profile.username,
    'display_name', target_profile.display_name
  )
  into profile_document
  from public.profiles as target_profile
  where target_profile.id = target_profile_id
    and target_profile.onboarding_completed_at is not null
    and target_profile.username is not null
    and target_profile.display_name is not null
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = target_profile.id
      ) or (
        pair_block.blocker_id = target_profile.id
        and pair_block.blocked_id = caller_id
      )
    );

  if profile_document is null then
    return null;
  end if;

  with candidates as materialized (
    select
      template_record.id,
      template_record.name,
      template_record.version,
      template_record.published_at,
      (
        select pg_catalog.count(*)::bigint
        from public.template_items as item_record
        where item_record.template_id = template_record.id
      ) as item_count
    from public.templates as template_record
    where template_record.owner_id = target_profile_id
      and template_record.published_at is not null
      and (
        cursor_published_at is null
        or (
          template_record.published_at,
          template_record.id
        ) < (
          cursor_published_at,
          cursor_template_id
        )
      )
    order by template_record.published_at desc, template_record.id desc
    limit requested_page_size + 1
  ),
  page_rows as (
    select candidate.*
    from candidates as candidate
    order by candidate.published_at desc, candidate.id desc
    limit requested_page_size
  )
  select
    coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'template_id', page_row.id,
            'name', page_row.name,
            'version', page_row.version,
            'item_count', page_row.item_count,
            'published_at', page_row.published_at
          )
          order by page_row.published_at desc, page_row.id desc
        )
        from page_rows as page_row
      ),
      '[]'::jsonb
    ),
    case
      when (
        select pg_catalog.count(*) > requested_page_size
        from candidates
      ) then pg_catalog.jsonb_build_object(
        'published_at',
        (
          select page_row.published_at
          from page_rows as page_row
          order by page_row.published_at desc, page_row.id desc
          offset requested_page_size - 1
          limit 1
        ),
        'template_id',
        (
          select page_row.id
          from page_rows as page_row
          order by page_row.published_at desc, page_row.id desc
          offset requested_page_size - 1
          limit 1
        )
      )
      else null
    end
  into template_documents, next_cursor;

  return pg_catalog.jsonb_build_object(
    'profile', profile_document,
    'templates', template_documents,
    'next_cursor', next_cursor
  );
end;
$$;

create function public.get_public_template(
  target_profile_id uuid,
  target_template_id uuid
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
  if target_profile_id is null or target_template_id is null then
    raise exception using
      errcode = '22023',
      message = 'invalid public template query';
  end if;

  select pg_catalog.jsonb_build_object(
    'profile',
    pg_catalog.jsonb_build_object(
      'profile_id', owner_profile.id,
      'username', owner_profile.username,
      'display_name', owner_profile.display_name
    ),
    'template',
    pg_catalog.jsonb_build_object(
      'template_id', template_record.id,
      'name', template_record.name,
      'version', template_record.version,
      'item_count',
      (
        select pg_catalog.count(*)::bigint
        from public.template_items as counted_item
        where counted_item.template_id = template_record.id
      ),
      'published_at', template_record.published_at,
      'items',
      coalesce(
        (
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'name', item_record.name,
              'quantity_thousandths', item_record.quantity_thousandths,
              'position', item_record.position
            )
            order by item_record.position, item_record.id
          )
          from public.template_items as item_record
          where item_record.template_id = template_record.id
        ),
        '[]'::jsonb
      )
    )
  )
  into result_document
  from public.templates as template_record
  join public.profiles as owner_profile
    on owner_profile.id = template_record.owner_id
  where template_record.id = target_template_id
    and template_record.owner_id = target_profile_id
    and template_record.published_at is not null
    and owner_profile.onboarding_completed_at is not null
    and owner_profile.username is not null
    and owner_profile.display_name is not null
    and not exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = owner_profile.id
      ) or (
        pair_block.blocker_id = owner_profile.id
        and pair_block.blocked_id = caller_id
      )
    );

  return result_document;
end;
$$;

create function public.copy_public_template(
  source_template_id uuid,
  expected_source_version bigint,
  request_id uuid
)
returns table (
  template_id uuid,
  category_id uuid,
  category_name text,
  name text,
  version bigint,
  item_count bigint,
  is_public boolean,
  published_at timestamptz,
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
  source_owner_id uuid;
  source_record public.templates%rowtype;
  destination_record public.templates%rowtype;
  request_record private.public_template_copy_requests%rowtype;
  fingerprint bytea;
  locked_profile_count integer;
  source_item_count integer;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if source_template_id is null
    or expected_source_version is null
    or expected_source_version < 1
    or request_id is null
  then
    raise exception using
      errcode = '22023',
      message = 'invalid public template copy';
  end if;

  fingerprint := private.public_template_copy_fingerprint(
    source_template_id,
    expected_source_version
  );

  select existing_request.*
  into request_record
  from private.public_template_copy_requests as existing_request
  where existing_request.owner_id = caller_id
    and existing_request.request_id = copy_public_template.request_id;

  if found then
    if request_record.request_fingerprint <> fingerprint then
      raise exception using
        errcode = '23505',
        message = 'public template copy request conflict',
        constraint = 'public_template_copy_requests_pkey';
    end if;

    select copied_template.*
    into destination_record
    from public.templates as copied_template
    where copied_template.owner_id = caller_id
      and copied_template.id = request_record.copied_template_id;

    if not found then
      raise exception using
        errcode = 'P0002',
        message = 'template unavailable';
    end if;

    return query
    select
      destination_record.id,
      destination_record.category_id,
      null::text,
      destination_record.name,
      destination_record.version,
      (
        select pg_catalog.count(*)::bigint
        from public.template_items as copied_item
        where copied_item.template_id = destination_record.id
      ),
      false,
      null::timestamptz,
      destination_record.created_at,
      destination_record.updated_at;
    return;
  end if;

  select source_template.owner_id
  into source_owner_id
  from public.templates as source_template
  where source_template.id = source_template_id;

  if source_owner_id is null then
    raise exception using
      errcode = 'P0002',
      message = 'template unavailable';
  end if;

  select pg_catalog.count(*)::integer
  into locked_profile_count
  from (
    select profile_record.id
    from public.profiles as profile_record
    where profile_record.id = any (
      array[caller_id, source_owner_id]::uuid[]
    )
    order by profile_record.id
    for key share
  ) as locked_profiles;

  if locked_profile_count <> (
    case
      when caller_id = source_owner_id then 1
      else 2
    end
  )
  then
    raise exception using
      errcode = 'P0002',
      message = 'template unavailable';
  end if;

  if caller_id <> source_owner_id then
    perform private.lock_relationship_pair(caller_id, source_owner_id);
  end if;

  if exists (
    select 1
    from public.profiles as profile_record
    where profile_record.id = any (
      array[caller_id, source_owner_id]::uuid[]
    )
      and (
        profile_record.onboarding_completed_at is null
        or profile_record.username is null
        or profile_record.display_name is null
      )
  ) or exists (
    select 1
    from public.user_blocks as pair_block
    where (
      pair_block.blocker_id = caller_id
      and pair_block.blocked_id = source_owner_id
    ) or (
      pair_block.blocker_id = source_owner_id
      and pair_block.blocked_id = caller_id
    )
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'template unavailable';
  end if;

  perform private.lock_template_owner(caller_id);

  select existing_request.*
  into request_record
  from private.public_template_copy_requests as existing_request
  where existing_request.owner_id = caller_id
    and existing_request.request_id = copy_public_template.request_id;

  if found then
    if request_record.request_fingerprint <> fingerprint then
      raise exception using
        errcode = '23505',
        message = 'public template copy request conflict',
        constraint = 'public_template_copy_requests_pkey';
    end if;

    select copied_template.*
    into destination_record
    from public.templates as copied_template
    where copied_template.owner_id = caller_id
      and copied_template.id = request_record.copied_template_id;

    return query
    select
      destination_record.id,
      destination_record.category_id,
      null::text,
      destination_record.name,
      destination_record.version,
      (
        select pg_catalog.count(*)::bigint
        from public.template_items as copied_item
        where copied_item.template_id = destination_record.id
      ),
      false,
      null::timestamptz,
      destination_record.created_at,
      destination_record.updated_at;
    return;
  end if;

  select source_template.*
  into source_record
  from public.templates as source_template
  where source_template.id = source_template_id
  for update;

  if not found
    or source_record.owner_id <> source_owner_id
    or source_record.published_at is null
  then
    raise exception using
      errcode = 'P0002',
      message = 'template unavailable';
  end if;

  if source_record.version <> expected_source_version then
    raise exception using
      errcode = '40001',
      message = 'template changed';
  end if;

  perform 1
  from public.template_items as source_item
  where source_item.template_id = source_record.id
  order by source_item.id
  for share;

  select pg_catalog.count(*)::integer
  into source_item_count
  from public.template_items as source_item
  where source_item.template_id = source_record.id;

  if source_item_count > 200 then
    raise exception using
      errcode = '54000',
      message = 'template item capacity reached';
  end if;

  if (
    select pg_catalog.count(*)
    from public.templates as owned_template
    where owned_template.owner_id = caller_id
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
    published_at,
    created_at,
    updated_at
  )
  values (
    caller_id,
    null,
    source_record.name,
    1,
    pg_catalog.gen_random_uuid(),
    null,
    mutation_time,
    mutation_time
  )
  returning *
  into destination_record;

  insert into public.template_items (
    id,
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
    pg_catalog.gen_random_uuid(),
    destination_record.id,
    source_item.name,
    source_item.quantity_thousandths,
    source_item.position,
    1,
    pg_catalog.gen_random_uuid(),
    mutation_time,
    mutation_time
  from public.template_items as source_item
  where source_item.template_id = source_record.id
  order by source_item.position, source_item.id;

  insert into private.public_template_copy_requests (
    owner_id,
    request_id,
    request_fingerprint,
    copied_template_id,
    created_at
  )
  values (
    caller_id,
    copy_public_template.request_id,
    fingerprint,
    destination_record.id,
    mutation_time
  );

  return query
  select
    destination_record.id,
    destination_record.category_id,
    null::text,
    destination_record.name,
    destination_record.version,
    source_item_count::bigint,
    false,
    null::timestamptz,
    destination_record.created_at,
    destination_record.updated_at;
end;
$$;

create function public.export_own_account_data_v9()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  base_export jsonb;
  enriched_templates jsonb;
begin
  base_export := public.export_own_account_data_v8();

  select coalesce(
    pg_catalog.jsonb_agg(
      owned_template.document
      || pg_catalog.jsonb_build_object(
        'is_public', template_record.published_at is not null,
        'published_at', template_record.published_at
      )
      order by owned_template.ordinality
    ),
    '[]'::jsonb
  )
  into enriched_templates
  from pg_catalog.jsonb_array_elements(base_export -> 'templates')
    with ordinality as owned_template(document, ordinality)
  left join public.templates as template_record
    on template_record.id = (owned_template.document ->> 'template_id')::uuid
   and template_record.owner_id = caller_id;

  return pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(base_export, '{schema_version}', '9'::jsonb),
    '{templates}',
    enriched_templates
  );
end;
$$;

alter function private.public_template_copy_fingerprint(uuid, bigint)
owner to postgres;
alter function public.list_private_templates_v2(text, uuid, boolean, text)
owner to postgres;
alter function public.get_private_template_v2(uuid)
owner to postgres;
alter function public.set_template_publication(uuid, boolean, bigint)
owner to postgres;
alter function public.list_public_profile_templates(
  uuid,
  integer,
  timestamptz,
  uuid
) owner to postgres;
alter function public.get_public_template(uuid, uuid)
owner to postgres;
alter function public.copy_public_template(uuid, bigint, uuid)
owner to postgres;
alter function public.export_own_account_data_v9()
owner to postgres;

revoke all on function private.public_template_copy_fingerprint(uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.list_private_templates_v2(
  text,
  uuid,
  boolean,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.get_private_template_v2(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.set_template_publication(uuid, boolean, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.list_public_profile_templates(
  uuid,
  integer,
  timestamptz,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function public.get_public_template(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.copy_public_template(uuid, bigint, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data_v9()
from public, anon, authenticated, service_role;

grant execute on function public.list_private_templates_v2(
  text,
  uuid,
  boolean,
  text
) to authenticated;
grant execute on function public.get_private_template_v2(uuid)
to authenticated;
grant execute on function public.set_template_publication(uuid, boolean, bigint)
to authenticated;
grant execute on function public.list_public_profile_templates(
  uuid,
  integer,
  timestamptz,
  uuid
) to authenticated;
grant execute on function public.get_public_template(uuid, uuid)
to authenticated;
grant execute on function public.copy_public_template(uuid, bigint, uuid)
to authenticated;
grant execute on function public.export_own_account_data_v9()
to authenticated;

comment on column public.templates.published_at is
  'Null for private templates; server-owned time of the current publication.';
comment on table private.public_template_copy_requests is
  'Server-only retry ledger with no raw public-template source identity.';
comment on function public.list_private_templates_v2(
  text,
  uuid,
  boolean,
  text
) is
  'Owner-only private template listing with publication state.';
comment on function public.get_private_template_v2(uuid) is
  'Owner-only private template detail with publication state.';
comment on function public.set_template_publication(uuid, boolean, bigint) is
  'Owner-only idempotent publication desired-state transition.';
comment on function public.list_public_profile_templates(
  uuid,
  integer,
  timestamptz,
  uuid
) is
  'Block-aware profile identity and bounded public-template keyset page.';
comment on function public.get_public_template(uuid, uuid) is
  'Block-aware public-template detail with no source item identities.';
comment on function public.copy_public_template(uuid, bigint, uuid) is
  'Atomic private Uncategorized deep copy with fingerprint-bound retry.';
comment on function public.export_own_account_data_v9() is
  'Account export v9 adds publication state only to caller-owned templates.';
