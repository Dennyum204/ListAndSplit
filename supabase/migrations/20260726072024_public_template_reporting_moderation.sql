begin;

create table private.public_template_moderators (
  moderator_id uuid primary key,
  granted_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint public_template_moderators_user_fkey
    foreign key (moderator_id)
    references auth.users(id)
    on delete cascade
);

create table private.public_template_moderator_access_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  moderator_id uuid,
  access_action text not null,
  operator_label text not null,
  request_id uuid not null unique,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint public_template_moderator_access_events_user_fkey
    foreign key (moderator_id)
    references auth.users(id)
    on delete set null,
  constraint public_template_moderator_access_events_action_check
    check (access_action in ('grant', 'revoke')),
  constraint public_template_moderator_access_events_operator_check
    check (
      operator_label =
        pg_catalog.btrim(operator_label)
      and pg_catalog.char_length(operator_label) between 1 and 120
    )
);

create table private.public_template_report_groups (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  template_id uuid not null,
  template_owner_id uuid,
  reported_revision bigint not null,
  content_fingerprint bytea not null,
  reported_snapshot jsonb not null,
  status text not null default 'open',
  version bigint not null default 1,
  first_reported_at timestamptz not null default pg_catalog.clock_timestamp(),
  closed_at timestamptz,
  source_changed_at timestamptz,
  source_unpublished_at timestamptz,
  source_deleted_at timestamptz,
  source_moderated_at timestamptz,
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint public_template_report_groups_owner_fkey
    foreign key (template_owner_id)
    references auth.users(id)
    on delete set null,
  constraint public_template_report_groups_revision_check
    check (reported_revision > 0),
  constraint public_template_report_groups_fingerprint_check
    check (pg_catalog.octet_length(content_fingerprint) = 32),
  constraint public_template_report_groups_snapshot_check
    check (
      pg_catalog.jsonb_typeof(reported_snapshot) = 'object'
      and reported_snapshot ? 'name'
      and reported_snapshot ? 'items'
      and pg_catalog.jsonb_typeof(reported_snapshot -> 'name') = 'string'
      and pg_catalog.jsonb_typeof(reported_snapshot -> 'items') = 'array'
    ),
  constraint public_template_report_groups_status_check
    check (
      status in ('open', 'dismissed', 'taken_down', 'content_deleted')
    ),
  constraint public_template_report_groups_version_check
    check (version > 0),
  constraint public_template_report_groups_lifecycle_check
    check (
      (status = 'open' and closed_at is null)
      or (status <> 'open' and closed_at is not null)
    ),
  constraint public_template_report_groups_time_check
    check (
      updated_at >= first_reported_at
      and (closed_at is null or closed_at >= first_reported_at)
      and (source_changed_at is null or source_changed_at >= first_reported_at)
      and (
        source_unpublished_at is null
        or source_unpublished_at >= first_reported_at
      )
      and (source_deleted_at is null or source_deleted_at >= first_reported_at)
      and (
        source_moderated_at is null
        or source_moderated_at >= first_reported_at
      )
    )
);

create table private.public_template_reports (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  group_id uuid not null,
  template_id uuid not null,
  reported_revision bigint not null,
  reporter_id uuid,
  reason_code text not null,
  explanation text,
  content_fingerprint bytea not null,
  status text not null default 'open',
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  closed_at timestamptz,
  constraint public_template_reports_group_fkey
    foreign key (group_id)
    references private.public_template_report_groups(id)
    on delete cascade,
  constraint public_template_reports_reporter_fkey
    foreign key (reporter_id)
    references auth.users(id)
    on delete set null,
  constraint public_template_reports_revision_check
    check (reported_revision > 0),
  constraint public_template_reports_reason_check
    check (
      reason_code in (
        'spam_scam_deceptive',
        'hate_harassment_bullying',
        'sexual_content',
        'violence_dangerous',
        'illegal_regulated',
        'personal_confidential_information',
        'copyright_trademark',
        'other'
      )
    ),
  constraint public_template_reports_explanation_check
    check (
      explanation is null
      or (
        explanation = pg_catalog.btrim(explanation)
        and pg_catalog.char_length(explanation) between 1 and 500
      )
    ),
  constraint public_template_reports_required_explanation_check
    check (
      reason_code not in ('copyright_trademark', 'other')
      or explanation is not null
    ),
  constraint public_template_reports_fingerprint_check
    check (pg_catalog.octet_length(content_fingerprint) = 32),
  constraint public_template_reports_status_check
    check (
      status in ('open', 'dismissed', 'taken_down', 'content_deleted')
    ),
  constraint public_template_reports_lifecycle_check
    check (
      (status = 'open' and closed_at is null)
      or (status <> 'open' and closed_at is not null)
    ),
  constraint public_template_reports_time_check
    check (closed_at is null or closed_at >= created_at)
);

create table private.public_template_moderation_restrictions (
  template_id uuid primary key,
  template_owner_id uuid,
  template_name text not null,
  reason_code text not null,
  active boolean not null,
  version bigint not null default 1,
  imposed_at timestamptz not null,
  restored_at timestamptz,
  source_deleted_at timestamptz,
  updated_at timestamptz not null,
  constraint public_template_moderation_restrictions_owner_fkey
    foreign key (template_owner_id)
    references auth.users(id)
    on delete set null,
  constraint public_template_moderation_restrictions_name_check
    check (
      template_name = pg_catalog.btrim(template_name)
      and pg_catalog.char_length(template_name) between 1 and 120
    ),
  constraint public_template_moderation_restrictions_reason_check
    check (
      reason_code in (
        'spam_scam_deceptive',
        'hate_harassment_bullying',
        'sexual_content',
        'violence_dangerous',
        'illegal_regulated',
        'personal_confidential_information',
        'copyright_trademark',
        'other'
      )
    ),
  constraint public_template_moderation_restrictions_version_check
    check (version > 0),
  constraint public_template_moderation_restrictions_lifecycle_check
    check (
      (
        active
        and restored_at is null
        and source_deleted_at is null
      )
      or (
        not active
        and (restored_at is not null or source_deleted_at is not null)
      )
    ),
  constraint public_template_moderation_restrictions_time_check
    check (
      updated_at >= imposed_at
      and (restored_at is null or restored_at >= imposed_at)
      and (source_deleted_at is null or source_deleted_at >= imposed_at)
    )
);

create table private.public_template_moderation_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  template_id uuid not null,
  group_id uuid,
  moderator_id uuid,
  action text not null,
  general_reason_code text,
  private_note text,
  request_id uuid unique,
  request_fingerprint bytea,
  result_group_version bigint,
  result_restriction_version bigint,
  result_template_version bigint,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint public_template_moderation_events_moderator_fkey
    foreign key (moderator_id)
    references auth.users(id)
    on delete set null,
  constraint public_template_moderation_events_action_check
    check (action in ('dismiss', 'take_down', 'restore', 'content_deleted')),
  constraint public_template_moderation_events_reason_check
    check (
      (
        action in ('take_down', 'restore')
        and general_reason_code in (
          'spam_scam_deceptive',
          'hate_harassment_bullying',
          'sexual_content',
          'violence_dangerous',
          'illegal_regulated',
          'personal_confidential_information',
          'copyright_trademark',
          'other'
        )
      )
      or (
        action in ('dismiss', 'content_deleted')
        and general_reason_code is null
      )
    ),
  constraint public_template_moderation_events_note_check
    check (
      (
        action <> 'content_deleted'
        and private_note = pg_catalog.btrim(private_note)
        and pg_catalog.char_length(private_note) between 1 and 1000
      )
      or (action = 'content_deleted' and private_note is null)
    ),
  constraint public_template_moderation_events_request_check
    check (
      (
        action <> 'content_deleted'
        and request_id is not null
        and pg_catalog.octet_length(request_fingerprint) = 32
        and moderator_id is not null
      )
      or (
        action = 'content_deleted'
        and request_id is null
        and request_fingerprint is null
        and moderator_id is null
      )
    ),
  constraint public_template_moderation_events_result_check
    check (
      (action = 'dismiss' and result_group_version is not null)
      or (
        action = 'take_down'
        and result_group_version is not null
        and result_restriction_version is not null
        and result_template_version is not null
      )
      or (
        action = 'restore'
        and result_group_version is null
        and result_restriction_version is not null
        and result_template_version is not null
      )
      or (
        action = 'content_deleted'
        and result_group_version is null
        and result_restriction_version is null
        and result_template_version is null
      )
    )
);

create table private.public_template_moderation_tombstones (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  retention_month date not null,
  report_count integer not null,
  dismissed_count integer not null,
  takedown_count integer not null,
  restore_count integer not null,
  content_deleted_count integer not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint public_template_moderation_tombstones_month_check
    check (retention_month = pg_catalog.date_trunc('month', retention_month)::date),
  constraint public_template_moderation_tombstones_count_check
    check (
      report_count > 0
      and dismissed_count >= 0
      and takedown_count >= 0
      and restore_count >= 0
      and content_deleted_count >= 0
    )
);

create index public_template_moderator_access_events_moderator_idx
on private.public_template_moderator_access_events (moderator_id)
where moderator_id is not null;

create unique index public_template_report_groups_open_key
on private.public_template_report_groups (
  template_id,
  reported_revision,
  content_fingerprint
)
where status = 'open';

create index public_template_report_groups_open_queue_idx
on private.public_template_report_groups (first_reported_at, id)
where status = 'open';

create index public_template_report_groups_closed_queue_idx
on private.public_template_report_groups (closed_at desc, id desc)
where status <> 'open';

create index public_template_report_groups_owner_idx
on private.public_template_report_groups (template_owner_id)
where template_owner_id is not null;

create unique index public_template_reports_reporter_revision_key
on private.public_template_reports (
  reporter_id,
  template_id,
  reported_revision
)
where reporter_id is not null;

create index public_template_reports_group_created_idx
on private.public_template_reports (group_id, created_at, id);

create index public_template_reports_reporter_template_idx
on private.public_template_reports (reporter_id, template_id)
where reporter_id is not null;

create index public_template_moderation_restrictions_owner_idx
on private.public_template_moderation_restrictions (template_owner_id)
where template_owner_id is not null;

create index public_template_moderation_events_template_created_idx
on private.public_template_moderation_events (template_id, created_at, id);

create index public_template_moderation_events_group_idx
on private.public_template_moderation_events (group_id)
where group_id is not null;

create index public_template_moderation_events_moderator_idx
on private.public_template_moderation_events (moderator_id)
where moderator_id is not null;

alter table private.public_template_moderators owner to postgres;
alter table private.public_template_moderator_access_events owner to postgres;
alter table private.public_template_report_groups owner to postgres;
alter table private.public_template_reports owner to postgres;
alter table private.public_template_moderation_restrictions owner to postgres;
alter table private.public_template_moderation_events owner to postgres;
alter table private.public_template_moderation_tombstones owner to postgres;

alter table private.public_template_moderators enable row level security;
alter table private.public_template_moderators force row level security;
alter table private.public_template_moderator_access_events enable row level security;
alter table private.public_template_moderator_access_events force row level security;
alter table private.public_template_report_groups enable row level security;
alter table private.public_template_report_groups force row level security;
alter table private.public_template_reports enable row level security;
alter table private.public_template_reports force row level security;
alter table private.public_template_moderation_restrictions enable row level security;
alter table private.public_template_moderation_restrictions force row level security;
alter table private.public_template_moderation_events enable row level security;
alter table private.public_template_moderation_events force row level security;
alter table private.public_template_moderation_tombstones enable row level security;
alter table private.public_template_moderation_tombstones force row level security;

revoke all on table private.public_template_moderators
from public, anon, authenticated, service_role;
revoke all on table private.public_template_moderator_access_events
from public, anon, authenticated, service_role;
revoke all on table private.public_template_report_groups
from public, anon, authenticated, service_role;
revoke all on table private.public_template_reports
from public, anon, authenticated, service_role;
revoke all on table private.public_template_moderation_restrictions
from public, anon, authenticated, service_role;
revoke all on table private.public_template_moderation_events
from public, anon, authenticated, service_role;
revoke all on table private.public_template_moderation_tombstones
from public, anon, authenticated, service_role;

create policy "public_template_moderators_reject_direct_client_access"
on private.public_template_moderators
as restrictive for all to anon, authenticated
using (false) with check (false);

create policy "moderator_access_events_reject_direct_client_access"
on private.public_template_moderator_access_events
as restrictive for all to anon, authenticated
using (false) with check (false);

create policy "public_template_report_groups_reject_direct_client_access"
on private.public_template_report_groups
as restrictive for all to anon, authenticated
using (false) with check (false);

create policy "public_template_reports_reject_direct_client_access"
on private.public_template_reports
as restrictive for all to anon, authenticated
using (false) with check (false);

create policy "template_moderation_restrictions_reject_direct_client_access"
on private.public_template_moderation_restrictions
as restrictive for all to anon, authenticated
using (false) with check (false);

create policy "public_template_moderation_events_reject_direct_client_access"
on private.public_template_moderation_events
as restrictive for all to anon, authenticated
using (false) with check (false);

create policy "moderation_tombstones_reject_direct_client_access"
on private.public_template_moderation_tombstones
as restrictive for all to anon, authenticated
using (false) with check (false);

create function private.is_supported_public_template_report_reason(
  candidate text
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select candidate in (
    'spam_scam_deceptive',
    'hate_harassment_bullying',
    'sexual_content',
    'violence_dangerous',
    'illegal_regulated',
    'personal_confidential_information',
    'copyright_trademark',
    'other'
  );
$$;

create function private.lock_public_template_moderation_scope(
  target_template_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'public-template-moderation:' || target_template_id::text,
      0
    )
  );
end;
$$;

create function private.require_public_template_moderator()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
begin
  if not exists (
    select 1
    from private.public_template_moderators as moderator
    where moderator.moderator_id = caller_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'moderator access required';
  end if;
  return caller_id;
end;
$$;

create function private.grant_public_template_moderator(
  target_user_id uuid,
  operator_label text,
  request_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  canonical_operator text := pg_catalog.btrim(operator_label);
  existing_event private.public_template_moderator_access_events%rowtype;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if target_user_id is null
    or request_id is null
    or canonical_operator is null
    or pg_catalog.char_length(canonical_operator) not between 1 and 120
  then
    raise exception using
      errcode = '22023',
      message = 'invalid moderator grant';
  end if;

  select access_event.*
  into existing_event
  from private.public_template_moderator_access_events as access_event
  where access_event.request_id =
    grant_public_template_moderator.request_id;

  if found then
    if existing_event.access_action <> 'grant'
      or existing_event.moderator_id is distinct from target_user_id
      or existing_event.operator_label <> canonical_operator
    then
      raise exception using
        errcode = '23505',
        message = 'moderator access request conflict',
        constraint =
          'public_template_moderator_access_events_request_id_key';
    end if;
    return;
  end if;

  if not exists (
    select 1
    from auth.users as target_auth
    join public.profiles as target_profile
      on target_profile.id = target_auth.id
    where target_auth.id = target_user_id
      and target_auth.email_confirmed_at is not null
      and target_profile.onboarding_completed_at is not null
      and target_profile.username is not null
      and target_profile.display_name is not null
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'moderator target unavailable';
  end if;

  insert into private.public_template_moderators (
    moderator_id,
    granted_at
  )
  values (target_user_id, mutation_time)
  on conflict (moderator_id) do nothing;

  insert into private.public_template_moderator_access_events (
    moderator_id,
    access_action,
    operator_label,
    request_id,
    created_at
  )
  values (
    target_user_id,
    'grant',
    canonical_operator,
    request_id,
    mutation_time
  );

  perform private.send_account_invalidations(array[target_user_id]);
end;
$$;

create function private.revoke_public_template_moderator(
  target_user_id uuid,
  operator_label text,
  request_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  canonical_operator text := pg_catalog.btrim(operator_label);
  existing_event private.public_template_moderator_access_events%rowtype;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if target_user_id is null
    or request_id is null
    or canonical_operator is null
    or pg_catalog.char_length(canonical_operator) not between 1 and 120
  then
    raise exception using
      errcode = '22023',
      message = 'invalid moderator revocation';
  end if;

  select access_event.*
  into existing_event
  from private.public_template_moderator_access_events as access_event
  where access_event.request_id =
    revoke_public_template_moderator.request_id;

  if found then
    if existing_event.access_action <> 'revoke'
      or existing_event.moderator_id is distinct from target_user_id
      or existing_event.operator_label <> canonical_operator
    then
      raise exception using
        errcode = '23505',
        message = 'moderator access request conflict',
        constraint =
          'public_template_moderator_access_events_request_id_key';
    end if;
    return;
  end if;

  delete from private.public_template_moderators as moderator
  where moderator.moderator_id = target_user_id;

  insert into private.public_template_moderator_access_events (
    moderator_id,
    access_action,
    operator_label,
    request_id,
    created_at
  )
  values (
    target_user_id,
    'revoke',
    canonical_operator,
    request_id,
    mutation_time
  );

  if exists (
    select 1 from auth.users as target_auth
    where target_auth.id = target_user_id
  ) then
    perform private.send_account_invalidations(array[target_user_id]);
  end if;
end;
$$;

create function private.public_template_report_fingerprint(
  target_template_id uuid,
  reported_revision bigint,
  reported_snapshot jsonb
)
returns bytea
language sql
immutable
security invoker
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(
      'list-and-split:public-template-report:v1:'
      || target_template_id::text
      || ':'
      || reported_revision::text
      || ':'
      || reported_snapshot::text,
      'UTF8'
    ),
    'sha256'
  );
$$;

create function private.public_template_moderation_action_fingerprint(
  action text,
  target_id uuid,
  expected_primary_version bigint,
  expected_template_version bigint,
  reason_code text,
  private_note text
)
returns bytea
language sql
immutable
security invoker
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(
      'list-and-split:public-template-moderation-action:v1:'
      || coalesce(action, '')
      || ':'
      || coalesce(target_id::text, '')
      || ':'
      || coalesce(expected_primary_version::text, '')
      || ':'
      || coalesce(expected_template_version::text, '')
      || ':'
      || coalesce(reason_code, '')
      || ':'
      || coalesce(private_note, ''),
      'UTF8'
    ),
    'sha256'
  );
$$;

create function public.is_public_template_moderator()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null then
    return false;
  end if;

  return exists (
    select 1
    from auth.users as caller_auth
    join public.profiles as caller_profile
      on caller_profile.id = caller_auth.id
    join private.public_template_moderators as moderator
      on moderator.moderator_id = caller_auth.id
    where caller_auth.id = caller_id
      and caller_auth.email_confirmed_at is not null
      and caller_profile.onboarding_completed_at is not null
      and caller_profile.username is not null
      and caller_profile.display_name is not null
  );
end;
$$;

create function public.report_public_template(
  target_template_id uuid,
  expected_public_revision bigint,
  reason_code text,
  explanation text default null
)
returns table (
  report_id uuid,
  report_group_id uuid,
  reported_revision bigint,
  created_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  canonical_explanation text := nullif(pg_catalog.btrim(explanation), '');
  template_record public.templates%rowtype;
  existing_report private.public_template_reports%rowtype;
  group_record private.public_template_report_groups%rowtype;
  snapshot_document jsonb;
  fingerprint bytea;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if target_template_id is null
    or expected_public_revision is null
    or expected_public_revision < 1
    or not private.is_supported_public_template_report_reason(reason_code)
    or (
      canonical_explanation is not null
      and pg_catalog.char_length(canonical_explanation) > 500
    )
    or (
      reason_code in ('copyright_trademark', 'other')
      and canonical_explanation is null
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid public template report';
  end if;

  perform private.lock_public_template_moderation_scope(target_template_id);

  select source_template.*
  into template_record
  from public.templates as source_template
  where source_template.id = target_template_id
  for share;

  if not found
    or template_record.owner_id = caller_id
    or template_record.published_at is null
    or exists (
      select 1
      from private.public_template_moderation_restrictions as restriction
      where restriction.template_id = target_template_id
        and restriction.active
    )
    or exists (
      select 1
      from public.user_blocks as pair_block
      where (
        pair_block.blocker_id = caller_id
        and pair_block.blocked_id = template_record.owner_id
      ) or (
        pair_block.blocker_id = template_record.owner_id
        and pair_block.blocked_id = caller_id
      )
    )
  then
    raise exception using
      errcode = 'P0002',
      message = 'template unavailable';
  end if;

  if template_record.version <> expected_public_revision then
    raise exception using
      errcode = '40001',
      message = 'template changed';
  end if;

  perform 1
  from public.template_items as source_item
  where source_item.template_id = template_record.id
  order by source_item.id
  for share;

  snapshot_document := pg_catalog.jsonb_build_object(
    'name',
    template_record.name,
    'items',
    coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'name', source_item.name,
            'quantity_thousandths', source_item.quantity_thousandths
          )
          order by source_item.position, source_item.id
        )
        from public.template_items as source_item
        where source_item.template_id = template_record.id
      ),
      '[]'::jsonb
    )
  );

  fingerprint := private.public_template_report_fingerprint(
    template_record.id,
    template_record.version,
    snapshot_document
  );

  select submitted_report.*
  into existing_report
  from private.public_template_reports as submitted_report
  where submitted_report.reporter_id = caller_id
    and submitted_report.template_id = template_record.id
    and submitted_report.reported_revision = template_record.version;

  if found then
    if existing_report.reason_code <> reason_code
      or existing_report.explanation is distinct from canonical_explanation
      or existing_report.content_fingerprint <> fingerprint
    then
      raise exception using
        errcode = '23505',
        message = 'public template report conflict',
        constraint = 'public_template_reports_reporter_revision_key';
    end if;

    return query
    select
      existing_report.id,
      existing_report.group_id,
      existing_report.reported_revision,
      existing_report.created_at;
    return;
  end if;

  select open_group.*
  into group_record
  from private.public_template_report_groups as open_group
  where open_group.template_id = template_record.id
    and open_group.reported_revision = template_record.version
    and open_group.content_fingerprint = fingerprint
    and open_group.status = 'open'
  for update;

  if not found then
    insert into private.public_template_report_groups (
      template_id,
      template_owner_id,
      reported_revision,
      content_fingerprint,
      reported_snapshot,
      status,
      version,
      first_reported_at,
      updated_at
    )
    values (
      template_record.id,
      template_record.owner_id,
      template_record.version,
      fingerprint,
      snapshot_document,
      'open',
      1,
      mutation_time,
      mutation_time
    )
    returning *
    into group_record;
  end if;

  insert into private.public_template_reports (
    group_id,
    template_id,
    reported_revision,
    reporter_id,
    reason_code,
    explanation,
    content_fingerprint,
    status,
    created_at
  )
  values (
    group_record.id,
    template_record.id,
    template_record.version,
    caller_id,
    reason_code,
    canonical_explanation,
    fingerprint,
    'open',
    mutation_time
  )
  returning *
  into existing_report;

  perform private.send_account_invalidations(
    array(
      select distinct recipient_id
      from (
        select caller_id as recipient_id
        union all
        select moderator.moderator_id
        from private.public_template_moderators as moderator
      ) as recipients
      where recipient_id is not null
    )
  );

  return query
  select
    existing_report.id,
    existing_report.group_id,
    existing_report.reported_revision,
    existing_report.created_at;
end;
$$;

create function public.list_private_templates_v3(
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
  is_moderated boolean,
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
    coalesce(restriction.active, false),
    template_record.created_at,
    template_record.updated_at
  from public.templates as template_record
  left join public.template_categories as category_record
    on category_record.owner_id = template_record.owner_id
   and category_record.id = template_record.category_id
  left join public.template_items as item_record
    on item_record.template_id = template_record.id
  left join private.public_template_moderation_restrictions as restriction
    on restriction.template_id = template_record.id
   and restriction.active
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
  group by
    template_record.id,
    category_record.name,
    restriction.active
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

create function public.get_private_template_v3(
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
  is_moderated boolean,
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
    coalesce(restriction.active, false),
    template_record.created_at,
    template_record.updated_at
  from public.templates as template_record
  left join public.template_categories as category_record
    on category_record.owner_id = template_record.owner_id
   and category_record.id = template_record.category_id
  left join public.template_items as item_record
    on item_record.template_id = template_record.id
  left join private.public_template_moderation_restrictions as restriction
    on restriction.template_id = template_record.id
   and restriction.active
  where template_record.id = target_template_id
    and template_record.owner_id = caller_id
  group by
    template_record.id,
    category_record.name,
    restriction.active;
end;
$$;

create or replace function public.set_template_publication(
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

  perform private.lock_public_template_moderation_scope(target_template_id);
  template_record := private.lock_owned_template(
    target_template_id,
    caller_id
  );

  if desired_public and exists (
    select 1
    from private.public_template_moderation_restrictions as restriction
    where restriction.template_id = template_record.id
      and restriction.active
  ) then
    raise exception using
      errcode = '42501',
      message = 'template unavailable';
  end if;

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

create or replace function public.list_public_profile_templates(
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
      and not exists (
        select 1
        from private.public_template_moderation_restrictions as restriction
        where restriction.template_id = template_record.id
          and restriction.active
      )
      and not exists (
        select 1
        from private.public_template_reports as submitted_report
        where submitted_report.reporter_id = caller_id
          and submitted_report.template_id = template_record.id
      )
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

create or replace function public.get_public_template(
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
      from private.public_template_moderation_restrictions as restriction
      where restriction.template_id = template_record.id
        and restriction.active
    )
    and not exists (
      select 1
      from private.public_template_reports as submitted_report
      where submitted_report.reporter_id = caller_id
        and submitted_report.template_id = template_record.id
    )
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

alter function public.copy_public_template(uuid, bigint, uuid)
rename to copy_public_template_v1_unmoderated;
alter function public.copy_public_template_v1_unmoderated(uuid, bigint, uuid)
set schema private;

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

  perform private.lock_public_template_moderation_scope(source_template_id);

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

  if exists (
    select 1
    from private.public_template_moderation_restrictions as restriction
    where restriction.template_id = source_template_id
      and restriction.active
  ) or exists (
    select 1
    from private.public_template_reports as submitted_report
    where submitted_report.reporter_id = caller_id
      and submitted_report.template_id = source_template_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'template unavailable';
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
    or exists (
      select 1
      from private.public_template_moderation_restrictions as restriction
      where restriction.template_id = source_record.id
        and restriction.active
    )
    or exists (
      select 1
      from private.public_template_reports as submitted_report
      where submitted_report.reporter_id = caller_id
        and submitted_report.template_id = source_record.id
    )
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

drop function private.copy_public_template_v1_unmoderated(
  uuid,
  bigint,
  uuid
);

create function public.list_public_template_moderation_queue(
  queue_filter text default 'open',
  requested_page_size integer default 20,
  cursor_at timestamptz default null,
  cursor_group_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  case_documents jsonb;
  next_cursor jsonb;
begin
  perform private.require_public_template_moderator();

  if queue_filter not in ('open', 'taken_down', 'closed')
    or requested_page_size is null
    or requested_page_size not between 1 and 50
    or ((cursor_at is null) <> (cursor_group_id is null))
  then
    raise exception using
      errcode = '22023',
      message = 'invalid moderation queue query';
  end if;

  with eligible as materialized (
    select
      report_group.id,
      report_group.template_id,
      report_group.reported_revision,
      report_group.reported_snapshot ->> 'name' as template_name,
      report_group.status,
      report_group.version,
      report_group.first_reported_at,
      report_group.closed_at,
      report_group.source_changed_at is not null as source_changed,
      report_group.source_unpublished_at is not null as source_unpublished,
      report_group.source_deleted_at is not null as source_deleted,
      report_group.source_moderated_at is not null as source_moderated,
      pg_catalog.count(report_record.id)::bigint as report_count,
      coalesce(restriction.active, false) as is_restricted,
      case
        when coalesce(restriction.active, false) then restriction.version
        else null::bigint
      end as restriction_version,
      case
        when queue_filter = 'open'
          then report_group.first_reported_at
        else report_group.closed_at
      end as sort_at
    from private.public_template_report_groups as report_group
    join private.public_template_reports as report_record
      on report_record.group_id = report_group.id
    left join private.public_template_moderation_restrictions as restriction
      on restriction.template_id = report_group.template_id
    where (
      queue_filter = 'open'
      and report_group.status = 'open'
    ) or (
      queue_filter = 'taken_down'
      and report_group.status = 'taken_down'
      and coalesce(restriction.active, false)
    ) or (
      queue_filter = 'closed'
      and report_group.status <> 'open'
      and not (
        report_group.status = 'taken_down'
        and coalesce(restriction.active, false)
      )
    )
    group by report_group.id, restriction.active, restriction.version
  ),
  candidates as materialized (
    select eligible_case.*
    from eligible as eligible_case
    where cursor_at is null
      or (
        queue_filter = 'open'
        and (eligible_case.sort_at, eligible_case.id)
          > (cursor_at, cursor_group_id)
      )
      or (
        queue_filter <> 'open'
        and (eligible_case.sort_at, eligible_case.id)
          < (cursor_at, cursor_group_id)
      )
    order by
      case when queue_filter = 'open' then eligible_case.sort_at end asc,
      case when queue_filter = 'open' then eligible_case.id end asc,
      case when queue_filter <> 'open' then eligible_case.sort_at end desc,
      case when queue_filter <> 'open' then eligible_case.id end desc
    limit requested_page_size + 1
  ),
  page_rows as (
    select candidate.*
    from candidates as candidate
    order by
      case when queue_filter = 'open' then candidate.sort_at end asc,
      case when queue_filter = 'open' then candidate.id end asc,
      case when queue_filter <> 'open' then candidate.sort_at end desc,
      case when queue_filter <> 'open' then candidate.id end desc
    limit requested_page_size
  )
  select
    coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'group_id', page_row.id,
            'template_id', page_row.template_id,
            'template_name', page_row.template_name,
            'reported_revision', page_row.reported_revision,
            'report_count', page_row.report_count,
            'status', page_row.status,
            'version', page_row.version,
            'first_reported_at', page_row.first_reported_at,
            'closed_at', page_row.closed_at,
            'source_changed', page_row.source_changed,
            'source_unpublished', page_row.source_unpublished,
            'source_deleted', page_row.source_deleted,
            'source_moderated', page_row.source_moderated,
            'is_restricted', page_row.is_restricted,
            'restriction_version', page_row.restriction_version
          )
          order by
            case when queue_filter = 'open' then page_row.sort_at end asc,
            case when queue_filter = 'open' then page_row.id end asc,
            case when queue_filter <> 'open' then page_row.sort_at end desc,
            case when queue_filter <> 'open' then page_row.id end desc
        )
        from page_rows as page_row
      ),
      '[]'::jsonb
    ),
    case
      when (
        select pg_catalog.count(*) > requested_page_size
        from candidates
      ) then (
        select pg_catalog.jsonb_build_object(
          'at', last_row.sort_at,
          'group_id', last_row.id
        )
        from page_rows as last_row
        order by
          case when queue_filter = 'open' then last_row.sort_at end desc,
          case when queue_filter = 'open' then last_row.id end desc,
          case when queue_filter <> 'open' then last_row.sort_at end asc,
          case when queue_filter <> 'open' then last_row.id end asc
        limit 1
      )
      else null
    end
  into case_documents, next_cursor;

  return pg_catalog.jsonb_build_object(
    'filter', queue_filter,
    'cases', case_documents,
    'next_cursor', next_cursor
  );
end;
$$;

create function public.get_public_template_moderation_case(
  target_group_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result_document jsonb;
begin
  perform private.require_public_template_moderator();

  if target_group_id is null then
    raise exception using
      errcode = '22023',
      message = 'invalid moderation case query';
  end if;

  select pg_catalog.jsonb_build_object(
    'group',
    pg_catalog.jsonb_build_object(
      'group_id', report_group.id,
      'template_id', report_group.template_id,
      'reported_revision', report_group.reported_revision,
      'status', report_group.status,
      'version', report_group.version,
      'first_reported_at', report_group.first_reported_at,
      'closed_at', report_group.closed_at,
      'source_changed', report_group.source_changed_at is not null,
      'source_unpublished', report_group.source_unpublished_at is not null,
      'source_deleted', report_group.source_deleted_at is not null,
      'source_moderated', report_group.source_moderated_at is not null
    ),
    'reported_snapshot',
    report_group.reported_snapshot,
    'reports',
    (
      select coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'report_id', report_record.id,
            'reason_code', report_record.reason_code,
            'explanation', report_record.explanation,
            'created_at', report_record.created_at,
            'reporter',
            case
              when reporter_profile.id is null then null
              else pg_catalog.jsonb_build_object(
                'profile_id', reporter_profile.id,
                'username', reporter_profile.username,
                'display_name', reporter_profile.display_name
              )
            end
          )
          order by report_record.created_at, report_record.id
        ),
        '[]'::jsonb
      )
      from private.public_template_reports as report_record
      left join public.profiles as reporter_profile
        on reporter_profile.id = report_record.reporter_id
       and reporter_profile.onboarding_completed_at is not null
       and reporter_profile.username is not null
       and reporter_profile.display_name is not null
      where report_record.group_id = report_group.id
    ),
    'current_template',
    (
      select pg_catalog.jsonb_build_object(
        'template_id', current_template.id,
        'name', current_template.name,
        'version', current_template.version,
        'is_public', current_template.published_at is not null,
        'items',
        coalesce(
          (
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'name', current_item.name,
                'quantity_thousandths', current_item.quantity_thousandths
              )
              order by current_item.position, current_item.id
            )
            from public.template_items as current_item
            where current_item.template_id = current_template.id
          ),
          '[]'::jsonb
        )
      )
      from public.templates as current_template
      where current_template.id = report_group.template_id
    ),
    'restriction',
    (
      select pg_catalog.jsonb_build_object(
        'active', restriction.active,
        'version', restriction.version,
        'reason_code', restriction.reason_code,
        'imposed_at', restriction.imposed_at,
        'restored_at', restriction.restored_at,
        'source_deleted_at', restriction.source_deleted_at
      )
      from private.public_template_moderation_restrictions as restriction
      where restriction.template_id = report_group.template_id
    )
  )
  into result_document
  from private.public_template_report_groups as report_group
  where report_group.id = target_group_id;

  if result_document is null then
    raise exception using
      errcode = 'P0002',
      message = 'moderation case unavailable';
  end if;

  return result_document;
end;
$$;

alter table public.user_notifications
  drop constraint user_notifications_type_check,
  drop constraint user_notifications_reference_scope_check,
  drop constraint user_notifications_positive_version_check,
  alter column actor_id drop not null,
  add column public_template_id uuid,
  add column public_template_name text,
  add column moderation_reason_code text,
  add column moderation_event_id uuid;

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
      'list_note_mentioned',
      'public_template_taken_down',
      'public_template_restored'
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
      and actor_id is not null
    ) or (
      notification_type not in (
        'friend_request',
        'list_item_assigned',
        'list_note_mentioned',
        'public_template_taken_down',
        'public_template_restored'
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
      and actor_id is null
    )
  ),
  add constraint user_notifications_positive_version_check check (
    coalesce(
      relationship_version,
      access_version,
      assignment_item_version,
      general_note_version
    ) > 0
    or moderation_event_id is not null
  );

create unique index user_notifications_moderation_event_key
on public.user_notifications (
  recipient_id,
  notification_type,
  moderation_event_id
)
where notification_type in (
  'public_template_taken_down',
  'public_template_restored'
);

create index user_notifications_public_template_idx
on public.user_notifications (public_template_id)
where public_template_id is not null;

create function public.moderate_public_template_report_group(
  target_group_id uuid,
  moderation_action text,
  expected_group_version bigint,
  expected_template_version bigint,
  owner_reason_code text,
  private_note text,
  request_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_public_template_moderator();
  canonical_note text := pg_catalog.btrim(private_note);
  group_record private.public_template_report_groups%rowtype;
  template_record public.templates%rowtype;
  restriction_record private.public_template_moderation_restrictions%rowtype;
  existing_event private.public_template_moderation_events%rowtype;
  decision_event private.public_template_moderation_events%rowtype;
  fingerprint bytea;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
  selected_group_version bigint;
begin
  if target_group_id is null
    or moderation_action not in ('dismiss', 'take_down')
    or expected_group_version is null
    or expected_group_version < 1
    or request_id is null
    or canonical_note is null
    or pg_catalog.char_length(canonical_note) not between 1 and 1000
    or (
      moderation_action = 'dismiss'
      and (
        expected_template_version is not null
        or owner_reason_code is not null
      )
    )
    or (
      moderation_action = 'take_down'
      and (
        expected_template_version is null
        or expected_template_version < 1
        or not private.is_supported_public_template_report_reason(
          owner_reason_code
        )
      )
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid moderation action';
  end if;

  fingerprint := private.public_template_moderation_action_fingerprint(
    moderation_action,
    target_group_id,
    expected_group_version,
    expected_template_version,
    owner_reason_code,
    canonical_note
  );

  select moderation_event.*
  into existing_event
  from private.public_template_moderation_events as moderation_event
  where moderation_event.request_id =
    moderate_public_template_report_group.request_id;

  if found then
    if existing_event.moderator_id is distinct from caller_id
      or existing_event.action <> moderation_action
      or existing_event.request_fingerprint <> fingerprint
    then
      raise exception using
        errcode = '23505',
        message = 'moderation request conflict',
        constraint = 'public_template_moderation_events_request_id_key';
    end if;

    return pg_catalog.jsonb_build_object(
      'event_id', existing_event.id,
      'action', existing_event.action,
      'group_id', existing_event.group_id,
      'group_version', existing_event.result_group_version,
      'restriction_version', existing_event.result_restriction_version,
      'template_version', existing_event.result_template_version,
      'created_at', existing_event.created_at
    );
  end if;

  select report_group.*
  into group_record
  from private.public_template_report_groups as report_group
  where report_group.id = target_group_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'moderation case unavailable';
  end if;

  perform private.lock_public_template_moderation_scope(
    group_record.template_id
  );

  -- A concurrent identical request can commit while this caller waits on the
  -- template-scoped lock. Recheck the ledger inside the serialized section so
  -- the retry converges on the committed result instead of observing the now
  -- closed group as an unrelated unavailable case.
  select moderation_event.*
  into existing_event
  from private.public_template_moderation_events as moderation_event
  where moderation_event.request_id =
    moderate_public_template_report_group.request_id;

  if found then
    if existing_event.moderator_id is distinct from caller_id
      or existing_event.action <> moderation_action
      or existing_event.request_fingerprint <> fingerprint
    then
      raise exception using
        errcode = '23505',
        message = 'moderation request conflict',
        constraint = 'public_template_moderation_events_request_id_key';
    end if;

    return pg_catalog.jsonb_build_object(
      'event_id', existing_event.id,
      'action', existing_event.action,
      'group_id', existing_event.group_id,
      'group_version', existing_event.result_group_version,
      'restriction_version', existing_event.result_restriction_version,
      'template_version', existing_event.result_template_version,
      'created_at', existing_event.created_at
    );
  end if;

  select report_group.*
  into group_record
  from private.public_template_report_groups as report_group
  where report_group.id = target_group_id
  for update;

  if group_record.status <> 'open' then
    raise exception using
      errcode = 'P0002',
      message = 'moderation case unavailable';
  end if;

  if group_record.version <> expected_group_version then
    raise exception using
      errcode = '40001',
      message = 'moderation case changed';
  end if;

  if moderation_action = 'dismiss' then
    update private.public_template_report_groups as changed_group
    set status = 'dismissed',
        version = changed_group.version + 1,
        closed_at = mutation_time,
        updated_at = mutation_time
    where changed_group.id = group_record.id
    returning *
    into group_record;

    update private.public_template_reports as changed_report
    set status = 'dismissed',
        closed_at = mutation_time
    where changed_report.group_id = group_record.id
      and changed_report.status = 'open';

    insert into private.public_template_moderation_events (
      template_id,
      group_id,
      moderator_id,
      action,
      private_note,
      request_id,
      request_fingerprint,
      result_group_version,
      created_at
    )
    values (
      group_record.template_id,
      group_record.id,
      caller_id,
      'dismiss',
      canonical_note,
      request_id,
      fingerprint,
      group_record.version,
      mutation_time
    )
    returning *
    into decision_event;

    perform private.send_account_invalidations(
      array(
        select moderator.moderator_id
        from private.public_template_moderators as moderator
      )
    );
  else
    select source_template.*
    into template_record
    from public.templates as source_template
    where source_template.id = group_record.template_id
    for update;

    if not found then
      raise exception using
        errcode = 'P0002',
        message = 'moderation case unavailable';
    end if;

    if template_record.version <> expected_template_version then
      raise exception using
        errcode = '40001',
        message = 'template changed';
    end if;

    if exists (
      select 1
      from private.public_template_moderation_restrictions as restriction
      where restriction.template_id = template_record.id
        and restriction.active
    ) then
      raise exception using
        errcode = 'P0002',
        message = 'moderation case unavailable';
    end if;

    update public.templates as changed_template
    set published_at = null,
        version = changed_template.version + 1,
        updated_at = mutation_time
    where changed_template.id = template_record.id
    returning *
    into template_record;

    insert into private.public_template_moderation_restrictions (
      template_id,
      template_owner_id,
      template_name,
      reason_code,
      active,
      version,
      imposed_at,
      restored_at,
      source_deleted_at,
      updated_at
    )
    values (
      template_record.id,
      template_record.owner_id,
      template_record.name,
      owner_reason_code,
      true,
      1,
      mutation_time,
      null,
      null,
      mutation_time
    )
    on conflict (template_id) do update
      set template_owner_id = excluded.template_owner_id,
          template_name = excluded.template_name,
          reason_code = excluded.reason_code,
          active = true,
          version =
            private.public_template_moderation_restrictions.version + 1,
          imposed_at = excluded.imposed_at,
          restored_at = null,
          source_deleted_at = null,
          updated_at = excluded.updated_at
      where not private.public_template_moderation_restrictions.active
    returning *
    into restriction_record;

    if not found or not restriction_record.active then
      raise exception using
        errcode = 'P0002',
        message = 'moderation case unavailable';
    end if;

    update private.public_template_report_groups as changed_group
    set status = 'taken_down',
        version = changed_group.version + 1,
        closed_at = mutation_time,
        source_moderated_at = coalesce(
          changed_group.source_moderated_at,
          mutation_time
        ),
        source_unpublished_at = coalesce(
          changed_group.source_unpublished_at,
          mutation_time
        ),
        updated_at = mutation_time
    where changed_group.template_id = template_record.id
      and changed_group.status = 'open';

    select changed_group.version
    into selected_group_version
    from private.public_template_report_groups as changed_group
    where changed_group.id = group_record.id;

    update private.public_template_reports as changed_report
    set status = 'taken_down',
        closed_at = mutation_time
    where changed_report.template_id = template_record.id
      and changed_report.status = 'open';

    insert into private.public_template_moderation_events (
      template_id,
      group_id,
      moderator_id,
      action,
      general_reason_code,
      private_note,
      request_id,
      request_fingerprint,
      result_group_version,
      result_restriction_version,
      result_template_version,
      created_at
    )
    values (
      template_record.id,
      group_record.id,
      caller_id,
      'take_down',
      owner_reason_code,
      canonical_note,
      request_id,
      fingerprint,
      selected_group_version,
      restriction_record.version,
      template_record.version,
      mutation_time
    )
    returning *
    into decision_event;

    insert into public.user_notifications (
      recipient_id,
      actor_id,
      notification_type,
      public_template_id,
      public_template_name,
      moderation_reason_code,
      moderation_event_id,
      created_at,
      expires_at
    )
    values (
      template_record.owner_id,
      null,
      'public_template_taken_down',
      template_record.id,
      template_record.name,
      owner_reason_code,
      decision_event.id,
      mutation_time,
      mutation_time + interval '180 days'
    );

    perform private.send_account_invalidations(
      array(
        select distinct recipient_id
        from (
          select template_record.owner_id as recipient_id
          union all
          select moderator.moderator_id
          from private.public_template_moderators as moderator
        ) as recipients
        where recipient_id is not null
      )
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'event_id', decision_event.id,
    'action', decision_event.action,
    'group_id', decision_event.group_id,
    'group_version', decision_event.result_group_version,
    'restriction_version', decision_event.result_restriction_version,
    'template_version', decision_event.result_template_version,
    'created_at', decision_event.created_at
  );
end;
$$;

create function public.restore_public_template_moderation(
  target_template_id uuid,
  expected_restriction_version bigint,
  expected_template_version bigint,
  private_note text,
  request_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_public_template_moderator();
  canonical_note text := pg_catalog.btrim(private_note);
  restriction_record private.public_template_moderation_restrictions%rowtype;
  template_record public.templates%rowtype;
  existing_event private.public_template_moderation_events%rowtype;
  decision_event private.public_template_moderation_events%rowtype;
  fingerprint bytea;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  if target_template_id is null
    or expected_restriction_version is null
    or expected_restriction_version < 1
    or expected_template_version is null
    or expected_template_version < 1
    or request_id is null
    or canonical_note is null
    or pg_catalog.char_length(canonical_note) not between 1 and 1000
  then
    raise exception using
      errcode = '22023',
      message = 'invalid moderation restoration';
  end if;

  fingerprint := private.public_template_moderation_action_fingerprint(
    'restore',
    target_template_id,
    expected_restriction_version,
    expected_template_version,
    null,
    canonical_note
  );

  select moderation_event.*
  into existing_event
  from private.public_template_moderation_events as moderation_event
  where moderation_event.request_id =
    restore_public_template_moderation.request_id;

  if found then
    if existing_event.moderator_id is distinct from caller_id
      or existing_event.action <> 'restore'
      or existing_event.request_fingerprint <> fingerprint
    then
      raise exception using
        errcode = '23505',
        message = 'moderation request conflict',
        constraint = 'public_template_moderation_events_request_id_key';
    end if;

    return pg_catalog.jsonb_build_object(
      'event_id', existing_event.id,
      'action', existing_event.action,
      'group_id', existing_event.group_id,
      'group_version', existing_event.result_group_version,
      'restriction_version', existing_event.result_restriction_version,
      'template_version', existing_event.result_template_version,
      'created_at', existing_event.created_at
    );
  end if;

  perform private.lock_public_template_moderation_scope(target_template_id);

  -- Recheck after serialization for a request that committed while waiting.
  select moderation_event.*
  into existing_event
  from private.public_template_moderation_events as moderation_event
  where moderation_event.request_id =
    restore_public_template_moderation.request_id;

  if found then
    if existing_event.moderator_id is distinct from caller_id
      or existing_event.action <> 'restore'
      or existing_event.request_fingerprint <> fingerprint
    then
      raise exception using
        errcode = '23505',
        message = 'moderation request conflict',
        constraint = 'public_template_moderation_events_request_id_key';
    end if;

    return pg_catalog.jsonb_build_object(
      'event_id', existing_event.id,
      'action', existing_event.action,
      'group_id', existing_event.group_id,
      'group_version', existing_event.result_group_version,
      'restriction_version', existing_event.result_restriction_version,
      'template_version', existing_event.result_template_version,
      'created_at', existing_event.created_at
    );
  end if;

  select restriction.*
  into restriction_record
  from private.public_template_moderation_restrictions as restriction
  where restriction.template_id = target_template_id
  for update;

  if not found or not restriction_record.active then
    raise exception using
      errcode = 'P0002',
      message = 'moderation restriction unavailable';
  end if;

  if restriction_record.version <> expected_restriction_version then
    raise exception using
      errcode = '40001',
      message = 'moderation restriction changed';
  end if;

  select source_template.*
  into template_record
  from public.templates as source_template
  where source_template.id = target_template_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'moderation restriction unavailable';
  end if;

  if template_record.version <> expected_template_version then
    raise exception using
      errcode = '40001',
      message = 'template changed';
  end if;

  update public.templates as changed_template
  set version = changed_template.version + 1,
      updated_at = mutation_time
  where changed_template.id = template_record.id
  returning *
  into template_record;

  update private.public_template_moderation_restrictions as restriction
  set active = false,
      version = restriction.version + 1,
      restored_at = mutation_time,
      updated_at = mutation_time
  where restriction.template_id = template_record.id
  returning *
  into restriction_record;

  insert into private.public_template_moderation_events (
    template_id,
    moderator_id,
    action,
    general_reason_code,
    private_note,
    request_id,
    request_fingerprint,
    result_restriction_version,
    result_template_version,
    created_at
  )
  values (
    template_record.id,
    caller_id,
    'restore',
    restriction_record.reason_code,
    canonical_note,
    request_id,
    fingerprint,
    restriction_record.version,
    template_record.version,
    mutation_time
  )
  returning *
  into decision_event;

  insert into public.user_notifications (
    recipient_id,
    actor_id,
    notification_type,
    public_template_id,
    public_template_name,
    moderation_reason_code,
    moderation_event_id,
    created_at,
    expires_at
  )
  values (
    template_record.owner_id,
    null,
    'public_template_restored',
    template_record.id,
    template_record.name,
    restriction_record.reason_code,
    decision_event.id,
    mutation_time,
    mutation_time + interval '180 days'
  );

  perform private.send_account_invalidations(
    array(
      select distinct recipient_id
      from (
        select template_record.owner_id as recipient_id
        union all
        select moderator.moderator_id
        from private.public_template_moderators as moderator
      ) as recipients
      where recipient_id is not null
    )
  );

  return pg_catalog.jsonb_build_object(
    'event_id', decision_event.id,
    'action', decision_event.action,
    'group_id', decision_event.group_id,
    'group_version', decision_event.result_group_version,
    'restriction_version', decision_event.result_restriction_version,
    'template_version', decision_event.result_template_version,
    'created_at', decision_event.created_at
  );
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
      'list_note_mentioned',
      'public_template_taken_down',
      'public_template_restored'
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
    and notification_record.notification_type not in (
      'list_note_mentioned',
      'public_template_taken_down',
      'public_template_restored'
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

create or replace function public.get_unread_notification_count_v3()
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
    and notification_record.notification_type not in (
      'public_template_taken_down',
      'public_template_restored'
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

create function public.list_notifications_v4(
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
  moderation_reason_code text
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
    end,
    notification_record.public_template_id,
    notification_record.public_template_name,
    notification_record.moderation_reason_code
  from public.user_notifications as notification_record
  left join public.profiles as actor_profile
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
      notification_record.notification_type in (
        'public_template_taken_down',
        'public_template_restored'
      )
      or (
        actor_profile.id is not null
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
      )
    )
    and (
      before_created_at is null
      or (notification_record.created_at, notification_record.id)
        < (before_created_at, before_notification_id)
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

create function public.get_unread_notification_count_v4()
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
  left join public.profiles as actor_profile
    on actor_profile.id = notification_record.actor_id
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
      notification_record.expires_at > pg_catalog.now()
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
        actor_profile.id is not null
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
            notification_record.notification_type = 'list_item_assigned'
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
end;
$$;

create unique index public_template_moderation_events_content_deleted_key
on private.public_template_moderation_events (template_id, action)
where action = 'content_deleted';

create function private.reconcile_public_template_moderation_source()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  source_template_id uuid :=
    case when tg_op = 'DELETE' then old.id else new.id end;
  mutation_time timestamptz := pg_catalog.clock_timestamp();
  has_evidence boolean;
begin
  select exists (
    select 1
    from private.public_template_report_groups as report_group
    where report_group.template_id = source_template_id
  ) or exists (
    select 1
    from private.public_template_moderation_restrictions as restriction
    where restriction.template_id = source_template_id
  )
  into has_evidence;

  if not has_evidence then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'UPDATE' then
    update private.public_template_report_groups as report_group
    set source_changed_at = case
          when new.version <> report_group.reported_revision
            then coalesce(report_group.source_changed_at, mutation_time)
          else report_group.source_changed_at
        end,
        source_unpublished_at = case
          when old.published_at is not null and new.published_at is null
            then coalesce(
              report_group.source_unpublished_at,
              mutation_time
            )
          else report_group.source_unpublished_at
        end,
        updated_at = mutation_time
    where report_group.template_id = source_template_id
      and (
        new.version <> report_group.reported_revision
        or (
          old.published_at is not null
          and new.published_at is null
        )
      );
  else
    update private.public_template_report_groups as report_group
    set status = case
          when report_group.status = 'open'
            then 'content_deleted'
          else report_group.status
        end,
        version = case
          when report_group.status = 'open'
            then report_group.version + 1
          else report_group.version
        end,
        closed_at = case
          when report_group.status = 'open'
            then mutation_time
          else report_group.closed_at
        end,
        source_deleted_at = coalesce(
          report_group.source_deleted_at,
          mutation_time
        ),
        updated_at = mutation_time
    where report_group.template_id = source_template_id;

    update private.public_template_reports as report_record
    set status = 'content_deleted',
        closed_at = mutation_time
    where report_record.template_id = source_template_id
      and report_record.status = 'open';

    update private.public_template_moderation_restrictions as restriction
    set active = false,
        version = restriction.version + 1,
        source_deleted_at = mutation_time,
        updated_at = mutation_time
    where restriction.template_id = source_template_id
      and restriction.active;

    insert into private.public_template_moderation_events (
      template_id,
      action,
      created_at
    )
    values (
      source_template_id,
      'content_deleted',
      mutation_time
    )
    on conflict (template_id, action)
      where action = 'content_deleted'
      do nothing;
  end if;

  perform private.send_account_invalidations(
    array(
      select moderator.moderator_id
      from private.public_template_moderators as moderator
    )
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger templates_reconcile_public_moderation_source
after update or delete on public.templates
for each row
execute function private.reconcile_public_template_moderation_source();

create function private.maintain_public_template_moderation_retention(
  as_of timestamptz default pg_catalog.clock_timestamp()
)
returns table (
  purged_groups integer,
  purged_reports integer,
  purged_events integer,
  purged_restrictions integer,
  created_tombstones integer
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  cutoff_time timestamptz;
  candidate_template_ids uuid[];
begin
  if as_of is null then
    raise exception using
      errcode = '22023',
      message = 'invalid moderation retention time';
  end if;

  cutoff_time := as_of - interval '24 months';

  select pg_catalog.array_agg(candidate.template_id order by candidate.template_id)
  into candidate_template_ids
  from (
    select distinct report_group.template_id
    from private.public_template_report_groups as report_group
    where not exists (
      select 1
      from private.public_template_report_groups as open_group
      where open_group.template_id = report_group.template_id
        and open_group.status = 'open'
    )
      and not exists (
        select 1
        from private.public_template_report_groups as recent_group
        where recent_group.template_id = report_group.template_id
          and (
            recent_group.closed_at is null
            or recent_group.closed_at > cutoff_time
          )
      )
      and not exists (
        select 1
        from private.public_template_moderation_restrictions as restriction
        where restriction.template_id = report_group.template_id
          and (
            restriction.active
            or coalesce(
              restriction.restored_at,
              restriction.source_deleted_at,
              restriction.updated_at
            ) > cutoff_time
          )
      )
      and not exists (
        select 1
        from private.public_template_moderation_events as recent_event
        where recent_event.template_id = report_group.template_id
          and recent_event.created_at > cutoff_time
      )
  ) as candidate;

  if coalesce(pg_catalog.cardinality(candidate_template_ids), 0) = 0 then
    return query select 0, 0, 0, 0, 0;
    return;
  end if;

  insert into private.public_template_moderation_tombstones (
    retention_month,
    report_count,
    dismissed_count,
    takedown_count,
    restore_count,
    content_deleted_count
  )
  select
    pg_catalog.date_trunc('month', as_of)::date,
    (
      select pg_catalog.count(*)::integer
      from private.public_template_reports as report_record
      where report_record.template_id = candidate_template.template_id
    ),
    (
      select pg_catalog.count(*)::integer
      from private.public_template_moderation_events as moderation_event
      where moderation_event.template_id = candidate_template.template_id
        and moderation_event.action = 'dismiss'
    ),
    (
      select pg_catalog.count(*)::integer
      from private.public_template_moderation_events as moderation_event
      where moderation_event.template_id = candidate_template.template_id
        and moderation_event.action = 'take_down'
    ),
    (
      select pg_catalog.count(*)::integer
      from private.public_template_moderation_events as moderation_event
      where moderation_event.template_id = candidate_template.template_id
        and moderation_event.action = 'restore'
    ),
    (
      select pg_catalog.count(*)::integer
      from private.public_template_moderation_events as moderation_event
      where moderation_event.template_id = candidate_template.template_id
        and moderation_event.action = 'content_deleted'
    )
  from pg_catalog.unnest(candidate_template_ids)
    as candidate_template(template_id);
  get diagnostics created_tombstones = row_count;

  delete from private.public_template_reports as report_record
  where report_record.template_id = any(candidate_template_ids);
  get diagnostics purged_reports = row_count;

  delete from private.public_template_report_groups as report_group
  where report_group.template_id = any(candidate_template_ids);
  get diagnostics purged_groups = row_count;

  delete from private.public_template_moderation_events as moderation_event
  where moderation_event.template_id = any(candidate_template_ids);
  get diagnostics purged_events = row_count;

  delete from private.public_template_moderation_restrictions as restriction
  where restriction.template_id = any(candidate_template_ids)
    and not restriction.active;
  get diagnostics purged_restrictions = row_count;

  return next;
end;
$$;

create function public.export_own_account_data_v10()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  base_export jsonb;
  submitted_reports jsonb;
begin
  base_export := public.export_own_account_data_v9();

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'reason_code', submitted_report.reason_code,
        'explanation', submitted_report.explanation,
        'submitted_at', submitted_report.created_at
      )
      order by submitted_report.created_at, submitted_report.id
    ),
    '[]'::jsonb
  )
  into submitted_reports
  from private.public_template_reports as submitted_report
  where submitted_report.reporter_id = caller_id;

  return pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(base_export, '{schema_version}', '10'::jsonb),
    '{submitted_public_template_reports}',
    submitted_reports
  );
end;
$$;

alter function private.is_supported_public_template_report_reason(text)
owner to postgres;
alter function private.lock_public_template_moderation_scope(uuid)
owner to postgres;
alter function private.require_public_template_moderator()
owner to postgres;
alter function private.grant_public_template_moderator(uuid, text, uuid)
owner to postgres;
alter function private.revoke_public_template_moderator(uuid, text, uuid)
owner to postgres;
alter function private.public_template_report_fingerprint(uuid, bigint, jsonb)
owner to postgres;
alter function private.public_template_moderation_action_fingerprint(
  text,
  uuid,
  bigint,
  bigint,
  text,
  text
) owner to postgres;
alter function private.reconcile_public_template_moderation_source()
owner to postgres;
alter function private.maintain_public_template_moderation_retention(
  timestamptz
) owner to postgres;

alter function public.is_public_template_moderator()
owner to postgres;
alter function public.report_public_template(uuid, bigint, text, text)
owner to postgres;
alter function public.list_private_templates_v3(text, uuid, boolean, text)
owner to postgres;
alter function public.get_private_template_v3(uuid)
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
alter function public.list_public_template_moderation_queue(
  text,
  integer,
  timestamptz,
  uuid
) owner to postgres;
alter function public.get_public_template_moderation_case(uuid)
owner to postgres;
alter function public.moderate_public_template_report_group(
  uuid,
  text,
  bigint,
  bigint,
  text,
  text,
  uuid
) owner to postgres;
alter function public.restore_public_template_moderation(
  uuid,
  bigint,
  bigint,
  text,
  uuid
) owner to postgres;
alter function public.get_unread_notification_count()
owner to postgres;
alter function public.get_unread_notification_count_v2()
owner to postgres;
alter function public.get_unread_notification_count_v3()
owner to postgres;
alter function public.list_notifications_v4(integer, timestamptz, uuid)
owner to postgres;
alter function public.get_unread_notification_count_v4()
owner to postgres;
alter function public.mark_notifications_read(uuid[])
owner to postgres;
alter function public.export_own_account_data_v10()
owner to postgres;

revoke all on function
  private.is_supported_public_template_report_reason(text)
from public, anon, authenticated, service_role;
revoke all on function
  private.lock_public_template_moderation_scope(uuid)
from public, anon, authenticated, service_role;
revoke all on function private.require_public_template_moderator()
from public, anon, authenticated, service_role;
revoke all on function
  private.grant_public_template_moderator(uuid, text, uuid)
from public, anon, authenticated, service_role;
revoke all on function
  private.revoke_public_template_moderator(uuid, text, uuid)
from public, anon, authenticated, service_role;
revoke all on function
  private.public_template_report_fingerprint(uuid, bigint, jsonb)
from public, anon, authenticated, service_role;
revoke all on function
  private.public_template_moderation_action_fingerprint(
    text,
    uuid,
    bigint,
    bigint,
    text,
    text
  )
from public, anon, authenticated, service_role;
revoke all on function
  private.reconcile_public_template_moderation_source()
from public, anon, authenticated, service_role;
revoke all on function
  private.maintain_public_template_moderation_retention(timestamptz)
from public, anon, authenticated, service_role;

revoke all on function public.is_public_template_moderator()
from public, anon, authenticated, service_role;
revoke all on function
  public.report_public_template(uuid, bigint, text, text)
from public, anon, authenticated, service_role;
revoke all on function
  public.list_private_templates_v3(text, uuid, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function public.get_private_template_v3(uuid)
from public, anon, authenticated, service_role;
revoke all on function
  public.set_template_publication(uuid, boolean, bigint)
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
revoke all on function public.list_public_template_moderation_queue(
  text,
  integer,
  timestamptz,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function public.get_public_template_moderation_case(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.moderate_public_template_report_group(
  uuid,
  text,
  bigint,
  bigint,
  text,
  text,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function public.restore_public_template_moderation(
  uuid,
  bigint,
  bigint,
  text,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count()
from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count_v2()
from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count_v3()
from public, anon, authenticated, service_role;
revoke all on function
  public.list_notifications_v4(integer, timestamptz, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_unread_notification_count_v4()
from public, anon, authenticated, service_role;
revoke all on function public.mark_notifications_read(uuid[])
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data_v10()
from public, anon, authenticated, service_role;

grant execute on function public.is_public_template_moderator()
to authenticated;
grant execute on function
  public.report_public_template(uuid, bigint, text, text)
to authenticated;
grant execute on function
  public.list_private_templates_v3(text, uuid, boolean, text)
to authenticated;
grant execute on function public.get_private_template_v3(uuid)
to authenticated;
grant execute on function
  public.set_template_publication(uuid, boolean, bigint)
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
grant execute on function public.list_public_template_moderation_queue(
  text,
  integer,
  timestamptz,
  uuid
) to authenticated;
grant execute on function public.get_public_template_moderation_case(uuid)
to authenticated;
grant execute on function public.moderate_public_template_report_group(
  uuid,
  text,
  bigint,
  bigint,
  text,
  text,
  uuid
) to authenticated;
grant execute on function public.restore_public_template_moderation(
  uuid,
  bigint,
  bigint,
  text,
  uuid
) to authenticated;
grant execute on function public.get_unread_notification_count()
to authenticated;
grant execute on function public.get_unread_notification_count_v2()
to authenticated;
grant execute on function public.get_unread_notification_count_v3()
to authenticated;
grant execute on function
  public.list_notifications_v4(integer, timestamptz, uuid)
to authenticated;
grant execute on function public.get_unread_notification_count_v4()
to authenticated;
grant execute on function public.mark_notifications_read(uuid[])
to authenticated;
grant execute on function public.export_own_account_data_v10()
to authenticated;

comment on table private.public_template_moderators is
  'Empty-by-default immutable-Auth-UUID allowlist for the moderation queue.';
comment on table private.public_template_moderator_access_events is
  'Append-only audited administrative moderator grants and revocations.';
comment on table private.public_template_report_groups is
  'Private revision-and-fingerprint groups retaining immutable public snapshots.';
comment on table private.public_template_reports is
  'Every individual immutable public-template report and its retained lifecycle.';
comment on table private.public_template_moderation_restrictions is
  'Template-level mutable enforcement state; decisions remain append-only events.';
comment on table private.public_template_moderation_events is
  'Immutable dismiss, takedown, restore, and source-deletion evidence.';
comment on table private.public_template_moderation_tombstones is
  'Nonidentifying aggregate totals retained after detailed 24-month evidence purge.';
comment on function
  private.grant_public_template_moderator(uuid, text, uuid) is
  'Postgres-only idempotent allowlist grant with audited operator label.';
comment on function
  private.revoke_public_template_moderator(uuid, text, uuid) is
  'Postgres-only idempotent immediate allowlist revocation with audit.';
comment on function
  private.maintain_public_template_moderation_retention(timestamptz) is
  'Unscheduled postgres-only idempotent purge of fully closed evidence older than 24 months.';
comment on function public.is_public_template_moderator() is
  'Protected self-check; empty or revoked allowlist access returns false.';
comment on function
  public.report_public_template(uuid, bigint, text, text) is
  'Atomic stale-safe report capture, grouping, fingerprinting, and reporter hide.';
comment on function
  public.list_private_templates_v3(text, uuid, boolean, text) is
  'Owner-only template list v3 adds active moderation status while retaining v1-v2.';
comment on function public.get_private_template_v3(uuid) is
  'Owner-only template detail v3 adds active moderation status while retaining v1-v2.';
comment on function
  public.set_template_publication(uuid, boolean, bigint) is
  'Owner desired-state publication transition that rejects active moderation restrictions.';
comment on function public.list_public_profile_templates(
  uuid,
  integer,
  timestamptz,
  uuid
) is
  'Block-, report-, and moderation-aware bounded public profile template page.';
comment on function public.get_public_template(uuid, uuid) is
  'Generic-unavailable public detail with report and moderation hiding.';
comment on function public.copy_public_template(uuid, bigint, uuid) is
  'Atomic public copy preserving v1 shape while rejecting reports and restrictions.';
comment on function public.list_public_template_moderation_queue(
  text,
  integer,
  timestamptz,
  uuid
) is
  'Moderator-only bounded keyset queue for open, active-takedown, and closed cases.';
comment on function public.get_public_template_moderation_case(uuid) is
  'Moderator-only reported snapshot, current public fields, reporters, and enforcement state.';
comment on function public.moderate_public_template_report_group(
  uuid,
  text,
  bigint,
  bigint,
  text,
  text,
  uuid
) is
  'Moderator-only idempotent dismiss or atomic template-level takedown.';
comment on function public.restore_public_template_moderation(
  uuid,
  bigint,
  bigint,
  text,
  uuid
) is
  'Moderator-only idempotent restriction restoration that never republishes.';
comment on function
  public.list_notifications_v4(integer, timestamptz, uuid) is
  'Notification v4 adds system-authored owner-only moderation outcomes without private evidence.';
comment on function public.get_unread_notification_count_v4() is
  'Unread v4 count including owner-only moderation outcomes.';
comment on function public.export_own_account_data_v10() is
  'Export v10 adds only the caller submitted report reason, explanation, and date; v1-v9 remain.';

commit;
