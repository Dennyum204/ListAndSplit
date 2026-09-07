-- Derive current participant counts only after the existing list read boundary
-- has selected an authorized, bounded page. Reuse the participant projection so
-- pending/dormant access rows and the transfer-only owner row never add a person.
-- The wrappers need no direct table access or additional definer privileges.
create function public.list_active_lists_v2(
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
  archived_at timestamptz,
  is_owner boolean,
  owner_profile_id uuid,
  owner_username text,
  owner_display_name text,
  caller_access_version bigint,
  participant_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    list_projection.list_id,
    list_projection.title,
    list_projection.status,
    list_projection.version,
    list_projection.item_count,
    list_projection.completed_item_count,
    list_projection.created_at,
    list_projection.updated_at,
    list_projection.archived_at,
    list_projection.is_owner,
    list_projection.owner_profile_id,
    list_projection.owner_username,
    list_projection.owner_display_name,
    list_projection.caller_access_version,
    (
      select pg_catalog.count(*)
      from public.list_active_list_participants(list_projection.list_id)
    ) as participant_count
  from public.list_active_lists(
    requested_status, page_size, before_sort_at, before_list_id
  ) as list_projection
  order by
    case when requested_status = 'active'
      then list_projection.updated_at
      else list_projection.archived_at
    end desc,
    list_projection.list_id desc;
$$;

create function public.get_active_list_v2(target_list_id uuid)
returns table (
  list_id uuid,
  title text,
  status text,
  version bigint,
  item_count bigint,
  completed_item_count bigint,
  created_at timestamptz,
  updated_at timestamptz,
  archived_at timestamptz,
  is_owner boolean,
  owner_profile_id uuid,
  owner_username text,
  owner_display_name text,
  caller_access_version bigint,
  participant_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    list_projection.list_id,
    list_projection.title,
    list_projection.status,
    list_projection.version,
    list_projection.item_count,
    list_projection.completed_item_count,
    list_projection.created_at,
    list_projection.updated_at,
    list_projection.archived_at,
    list_projection.is_owner,
    list_projection.owner_profile_id,
    list_projection.owner_username,
    list_projection.owner_display_name,
    list_projection.caller_access_version,
    (
      select pg_catalog.count(*)
      from public.list_active_list_participants(list_projection.list_id)
    ) as participant_count
  from public.get_active_list(target_list_id) as list_projection;
$$;

alter function public.list_active_lists_v2(text, integer, timestamptz, uuid)
owner to postgres;
alter function public.get_active_list_v2(uuid) owner to postgres;

revoke all on function public.list_active_lists_v2(text, integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_active_list_v2(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.list_active_lists_v2(text, integer, timestamptz, uuid)
to authenticated;
grant execute on function public.get_active_list_v2(uuid) to authenticated;

comment on function public.list_active_lists_v2(text, integer, timestamptz, uuid) is
  'Legacy authorized keyset list page plus the current owner-and-accepted-member count; pending and dormant access are excluded.';
comment on function public.get_active_list_v2(uuid) is
  'Legacy authorized list detail summary plus the current owner-and-accepted-member count; no stored counter or additional identity fields.';
