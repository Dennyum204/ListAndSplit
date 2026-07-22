begin;

create table public.active_list_split_settings (
  list_id uuid primary key,
  currency_code text not null,
  version bigint not null default 1,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint active_list_split_settings_list_fkey foreign key (list_id)
    references public.active_lists(id) on delete cascade,
  constraint active_list_split_settings_currency_check check (
    currency_code in ('CHF', 'EUR')
  ),
  constraint active_list_split_settings_version_check check (version > 0),
  constraint active_list_split_settings_time_check check (updated_at >= created_at)
);

create table public.active_list_split_participants (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  list_id uuid not null,
  profile_id uuid,
  username_snapshot text,
  display_name_snapshot text,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint active_list_split_participants_settings_fkey foreign key (list_id)
    references public.active_list_split_settings(list_id) on delete cascade,
  constraint active_list_split_participants_profile_fkey foreign key (profile_id)
    references public.profiles(id) on delete set null,
  constraint active_list_split_participants_list_id_key unique (list_id, id),
  constraint active_list_split_participants_identity_state_check check (
    (
      profile_id is not null
      and username_snapshot is not null
      and display_name_snapshot is not null
    )
    or (
      profile_id is null
      and username_snapshot is null
      and display_name_snapshot is null
    )
  ),
  constraint active_list_split_participants_snapshot_check check (
    username_snapshot is null
    or (
      pg_catalog.char_length(username_snapshot) between 3 and 24
      and pg_catalog.char_length(display_name_snapshot) between 1 and 50
    )
  ),
  constraint active_list_split_participants_time_check check (
    updated_at >= created_at
  )
);

create unique index active_list_split_participants_live_profile_key
  on public.active_list_split_participants(list_id, profile_id)
  where profile_id is not null;
create index active_list_split_participants_profile_idx
  on public.active_list_split_participants(profile_id, list_id)
  where profile_id is not null;

create table public.active_list_expenses (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  list_id uuid not null,
  description text not null,
  amount_minor bigint not null,
  payer_participant_id uuid not null,
  creator_participant_id uuid not null,
  last_editor_participant_id uuid not null,
  version bigint not null default 1,
  creation_request_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint active_list_expenses_settings_fkey foreign key (list_id)
    references public.active_list_split_settings(list_id) on delete cascade,
  constraint active_list_expenses_list_id_key unique (list_id, id),
  constraint active_list_expenses_list_request_key unique (
    list_id,
    creation_request_id
  ),
  constraint active_list_expenses_payer_fkey foreign key (
    list_id,
    payer_participant_id
  ) references public.active_list_split_participants(list_id, id)
    deferrable initially deferred,
  constraint active_list_expenses_creator_fkey foreign key (
    list_id,
    creator_participant_id
  ) references public.active_list_split_participants(list_id, id)
    deferrable initially deferred,
  constraint active_list_expenses_last_editor_fkey foreign key (
    list_id,
    last_editor_participant_id
  ) references public.active_list_split_participants(list_id, id)
    deferrable initially deferred,
  constraint active_list_expenses_description_check check (
    description = pg_catalog.regexp_replace(
      description,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    )
    and pg_catalog.char_length(description) between 1 and 120
  ),
  constraint active_list_expenses_amount_check check (
    amount_minor between 1 and 999999999
  ),
  constraint active_list_expenses_version_check check (version > 0),
  constraint active_list_expenses_time_check check (updated_at >= created_at)
);

create table public.active_list_expense_shares (
  list_id uuid not null,
  expense_id uuid not null,
  participant_id uuid not null,
  amount_minor bigint not null,
  constraint active_list_expense_shares_pkey primary key (
    list_id,
    expense_id,
    participant_id
  ),
  constraint active_list_expense_shares_expense_fkey foreign key (
    list_id,
    expense_id
  ) references public.active_list_expenses(list_id, id) on delete cascade
    deferrable initially deferred,
  constraint active_list_expense_shares_participant_fkey foreign key (
    list_id,
    participant_id
  ) references public.active_list_split_participants(list_id, id)
    deferrable initially deferred,
  constraint active_list_expense_shares_amount_check check (amount_minor >= 0)
);

alter table public.active_list_split_settings owner to postgres;
alter table public.active_list_split_participants owner to postgres;
alter table public.active_list_expenses owner to postgres;
alter table public.active_list_expense_shares owner to postgres;

create index active_list_expenses_history_idx
  on public.active_list_expenses(list_id, created_at desc, id desc);
create index active_list_expenses_payer_idx
  on public.active_list_expenses(list_id, payer_participant_id);
create index active_list_expenses_creator_idx
  on public.active_list_expenses(list_id, creator_participant_id);
create index active_list_expenses_last_editor_idx
  on public.active_list_expenses(list_id, last_editor_participant_id);
create index active_list_expense_shares_participant_idx
  on public.active_list_expense_shares(list_id, participant_id, expense_id);

alter table public.active_list_split_settings enable row level security;
alter table public.active_list_split_settings force row level security;
alter table public.active_list_split_participants enable row level security;
alter table public.active_list_split_participants force row level security;
alter table public.active_list_expenses enable row level security;
alter table public.active_list_expenses force row level security;
alter table public.active_list_expense_shares enable row level security;
alter table public.active_list_expense_shares force row level security;

revoke all on table public.active_list_split_settings
from public, anon, authenticated, service_role;
revoke all on table public.active_list_split_participants
from public, anon, authenticated, service_role;
revoke all on table public.active_list_expenses
from public, anon, authenticated, service_role;
revoke all on table public.active_list_expense_shares
from public, anon, authenticated, service_role;

create policy "active_list_split_settings_reject_direct_client_access"
on public.active_list_split_settings
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "active_list_split_participants_reject_direct_client_access"
on public.active_list_split_participants
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "active_list_expenses_reject_direct_client_access"
on public.active_list_expenses
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "active_list_expense_shares_reject_direct_client_access"
on public.active_list_expense_shares
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create function private.upsert_active_list_split_participants(target_list_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.active_list_split_settings as settings_record
    where settings_record.list_id = target_list_id
  ) then
    return;
  end if;

  insert into public.active_list_split_participants (
    list_id,
    profile_id,
    username_snapshot,
    display_name_snapshot,
    created_at,
    updated_at
  )
  select
    target_list_id,
    current_profile.id,
    current_profile.username,
    current_profile.display_name,
    pg_catalog.clock_timestamp(),
    pg_catalog.clock_timestamp()
  from (
    select list_record.owner_id as profile_id
    from public.active_lists as list_record
    where list_record.id = target_list_id
    union
    select access_record.participant_profile_id
    from public.active_list_participants as access_record
    where access_record.list_id = target_list_id
      and access_record.state = 'member'
  ) as current_participant
  join public.profiles as current_profile
    on current_profile.id = current_participant.profile_id
   and current_profile.onboarding_completed_at is not null
   and current_profile.username is not null
   and current_profile.display_name is not null
  on conflict (list_id, profile_id) where profile_id is not null
  do update set
    username_snapshot = excluded.username_snapshot,
    display_name_snapshot = excluded.display_name_snapshot,
    updated_at = pg_catalog.clock_timestamp();
end;
$$;

create function private.active_list_split_participant_is_current(
  target_list_id uuid,
  target_participant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.active_list_split_participants as split_participant
    join public.profiles as profile_record
      on profile_record.id = split_participant.profile_id
    join public.active_lists as list_record
      on list_record.id = split_participant.list_id
    where split_participant.list_id = target_list_id
      and split_participant.id = target_participant_id
      and (
        list_record.owner_id = split_participant.profile_id
        or exists (
          select 1
          from public.active_list_participants as access_record
          where access_record.list_id = target_list_id
            and access_record.participant_profile_id = split_participant.profile_id
            and access_record.state = 'member'
        )
      )
  );
$$;

create function private.sync_active_list_split_participant()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  target_list_id uuid := case when tg_op = 'DELETE' then old.list_id else new.list_id end;
  affects_current boolean :=
    (tg_op <> 'INSERT' and old.state in ('member', 'owner'))
    or (tg_op <> 'DELETE' and new.state in ('member', 'owner'));
begin
  if affects_current then
    perform private.upsert_active_list_split_participants(target_list_id);
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create function private.anonymize_active_list_split_participants()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  mutation_time timestamptz := pg_catalog.clock_timestamp();
begin
  update public.active_list_split_participants as split_participant
  set profile_id = null,
      username_snapshot = null,
      display_name_snapshot = null,
      updated_at = mutation_time
  where split_participant.profile_id = old.id;
  return old;
end;
$$;

create function private.sync_active_list_split_profile_snapshot()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if new.username is not null
    and new.display_name is not null
    and (
      old.username is distinct from new.username
      or old.display_name is distinct from new.display_name
    )
  then
    update public.active_list_split_participants as split_participant
    set username_snapshot = new.username,
        display_name_snapshot = new.display_name,
        updated_at = pg_catalog.clock_timestamp()
    where split_participant.profile_id = new.id;
  end if;
  return new;
end;
$$;

create function private.check_active_list_expense_share_total()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  target_list_id uuid;
  target_expense_id uuid;
  expense_amount bigint;
  share_count bigint;
  share_total numeric;
begin
  if tg_table_name = 'active_list_expenses' then
    if tg_op = 'DELETE' then
      target_list_id := old.list_id;
      target_expense_id := old.id;
    else
      target_list_id := new.list_id;
      target_expense_id := new.id;
    end if;
  else
    if tg_op = 'DELETE' then
      target_list_id := old.list_id;
      target_expense_id := old.expense_id;
    else
      target_list_id := new.list_id;
      target_expense_id := new.expense_id;
    end if;
  end if;

  select expense_record.amount_minor
  into expense_amount
  from public.active_list_expenses as expense_record
  where expense_record.list_id = target_list_id
    and expense_record.id = target_expense_id;

  if found then
    select pg_catalog.count(*), coalesce(pg_catalog.sum(share_record.amount_minor), 0)
    into share_count, share_total
    from public.active_list_expense_shares as share_record
    where share_record.list_id = target_list_id
      and share_record.expense_id = target_expense_id;

    if share_count < 1 or share_total <> expense_amount then
      raise exception using
        errcode = '23514',
        message = 'expense shares must exactly equal the expense amount';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    if tg_table_name = 'active_list_expenses' then
      if old.list_id is distinct from new.list_id or old.id is distinct from new.id then
        target_list_id := old.list_id;
        target_expense_id := old.id;
      else
        return null;
      end if;
    else
      if old.list_id is distinct from new.list_id
        or old.expense_id is distinct from new.expense_id
      then
        target_list_id := old.list_id;
        target_expense_id := old.expense_id;
      else
        return null;
      end if;
    end if;

    select expense_record.amount_minor
    into expense_amount
    from public.active_list_expenses as expense_record
    where expense_record.list_id = target_list_id
      and expense_record.id = target_expense_id;
    if found and (
      select pg_catalog.count(*) < 1
        or coalesce(pg_catalog.sum(share_record.amount_minor), 0) <> expense_amount
      from public.active_list_expense_shares as share_record
      where share_record.list_id = target_list_id
        and share_record.expense_id = target_expense_id
    ) then
      raise exception using
        errcode = '23514',
        message = 'expense shares must exactly equal the expense amount';
    end if;
  end if;

  return null;
end;
$$;

create constraint trigger active_list_expenses_share_total_check
after insert or update of amount_minor on public.active_list_expenses
deferrable initially deferred
for each row execute function private.check_active_list_expense_share_total();

create constraint trigger active_list_expense_shares_total_check
after insert or update or delete on public.active_list_expense_shares
deferrable initially deferred
for each row execute function private.check_active_list_expense_share_total();

create trigger active_list_participants_sync_split_identity
after insert or update or delete on public.active_list_participants
for each row execute function private.sync_active_list_split_participant();

create trigger profiles_anonymize_split_participants_before_delete
before delete on public.profiles
for each row execute function private.anonymize_active_list_split_participants();

create trigger profiles_sync_split_participant_snapshot
after update of username, display_name on public.profiles
for each row execute function private.sync_active_list_split_profile_snapshot();

create function private.build_active_list_split_projection(
  target_list_id uuid,
  caller_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  list_record public.active_lists%rowtype;
  settings_record public.active_list_split_settings%rowtype;
  settings_json jsonb := null;
  participant_json jsonb := '[]'::jsonb;
  expense_json jsonb := '[]'::jsonb;
begin
  select current_list.* into list_record
  from public.active_lists as current_list
  where current_list.id = target_list_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;

  select current_settings.* into settings_record
  from public.active_list_split_settings as current_settings
  where current_settings.list_id = target_list_id;

  if found then
    settings_json := pg_catalog.jsonb_build_object(
      'currency_code', settings_record.currency_code,
      'version', settings_record.version,
      'created_at', settings_record.created_at,
      'updated_at', settings_record.updated_at
    );

    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', participant_record.id,
          'profile_id', participant_record.profile_id,
          'username', case
            when participant_record.is_current then live_profile.username
            else participant_record.username_snapshot
          end,
          'display_name', case
            when participant_record.is_current then live_profile.display_name
            else participant_record.display_name_snapshot
          end,
          'is_anonymized', participant_record.profile_id is null,
          'is_current', participant_record.is_current,
          'paid_minor', participant_record.paid_minor,
          'owed_minor', participant_record.owed_minor,
          'balance_minor', participant_record.paid_minor - participant_record.owed_minor
        ) order by participant_record.id
      ),
      '[]'::jsonb
    ) into participant_json
    from (
      select
        split_participant.*,
        private.active_list_split_participant_is_current(
          target_list_id,
          split_participant.id
        ) as is_current,
        coalesce((
          select pg_catalog.sum(expense_record.amount_minor)
          from public.active_list_expenses as expense_record
          where expense_record.list_id = target_list_id
            and expense_record.payer_participant_id = split_participant.id
        ), 0)::bigint as paid_minor,
        coalesce((
          select pg_catalog.sum(share_record.amount_minor)
          from public.active_list_expense_shares as share_record
          where share_record.list_id = target_list_id
            and share_record.participant_id = split_participant.id
        ), 0)::bigint as owed_minor
      from public.active_list_split_participants as split_participant
      where split_participant.list_id = target_list_id
        and (
          private.active_list_split_participant_is_current(
            target_list_id,
            split_participant.id
          )
          or exists (
            select 1
            from public.active_list_expenses as relevant_expense
            where relevant_expense.list_id = target_list_id
              and relevant_expense.payer_participant_id = split_participant.id
          )
          or exists (
            select 1
            from public.active_list_expenses as relevant_expense
            where relevant_expense.list_id = target_list_id
              and relevant_expense.creator_participant_id = split_participant.id
          )
          or exists (
            select 1
            from public.active_list_expenses as relevant_expense
            where relevant_expense.list_id = target_list_id
              and relevant_expense.last_editor_participant_id = split_participant.id
          )
          or exists (
            select 1
            from public.active_list_expense_shares as relevant_share
            where relevant_share.list_id = target_list_id
              and relevant_share.participant_id = split_participant.id
          )
        )
    ) as participant_record
    left join public.profiles as live_profile
      on live_profile.id = participant_record.profile_id;

    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', expense_record.id,
          'description', expense_record.description,
          'amount_minor', expense_record.amount_minor,
          'payer_participant_id', expense_record.payer_participant_id,
          'creator_participant_id', expense_record.creator_participant_id,
          'last_editor_participant_id', expense_record.last_editor_participant_id,
          'version', expense_record.version,
          'created_at', expense_record.created_at,
          'updated_at', expense_record.updated_at,
          'beneficiary_participant_ids', coalesce((
            select pg_catalog.jsonb_agg(share_record.participant_id order by share_record.participant_id)
            from public.active_list_expense_shares as share_record
            where share_record.list_id = target_list_id
              and share_record.expense_id = expense_record.id
          ), '[]'::jsonb),
          'shares', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'participant_id', share_record.participant_id,
                'amount_minor', share_record.amount_minor
              ) order by share_record.participant_id
            )
            from public.active_list_expense_shares as share_record
            where share_record.list_id = target_list_id
              and share_record.expense_id = expense_record.id
          ), '[]'::jsonb)
        ) order by expense_record.created_at desc, expense_record.id desc
      ),
      '[]'::jsonb
    ) into expense_json
    from public.active_list_expenses as expense_record
    where expense_record.list_id = target_list_id;
  end if;

  return pg_catalog.jsonb_build_object(
    'list_id', list_record.id,
    'list_title', list_record.title,
    'list_status', list_record.status,
    'list_version', list_record.version,
    'is_owner', list_record.owner_id = caller_id,
    'enabled', settings_json is not null,
    'writable', settings_json is not null and list_record.status = 'active',
    'settings', settings_json,
    'participants', participant_json,
    'expenses', expense_json
  );
end;
$$;

create function public.get_active_list_split(target_list_id uuid)
returns jsonb
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
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

create function public.enable_active_list_split(
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

  select current_list.* into list_record
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

  select current_settings.* into settings_record
  from public.active_list_split_settings as current_settings
  where current_settings.list_id = target_list_id
  for update;
  if found then
    if settings_record.currency_code <> new_currency_code then
      raise exception using errcode = '22023', message = 'split is already enabled';
    end if;
    perform private.upsert_active_list_split_participants(target_list_id);
    return private.build_active_list_split_projection(target_list_id, caller_id);
  end if;

  insert into public.active_list_split_settings(list_id, currency_code)
  values (target_list_id, new_currency_code);
  perform private.upsert_active_list_split_participants(target_list_id);
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

create function public.change_active_list_split_currency(
  target_list_id uuid,
  new_currency_code text,
  expected_split_version bigint
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
  settings_record public.active_list_split_settings%rowtype;
begin
  if target_list_id is null
    or new_currency_code is null
    or new_currency_code not in ('CHF', 'EUR')
    or expected_split_version is null
    or expected_split_version < 1
  then
    raise exception using errcode = '22023', message = 'invalid split currency change';
  end if;

  select current_list.* into list_record
  from public.active_lists as current_list
  where current_list.id = target_list_id
  for update;
  if not found or list_record.owner_id <> caller_id then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  if list_record.status <> 'active' then
    raise exception using errcode = '55000', message = 'archived list is read only';
  end if;

  select current_settings.* into settings_record
  from public.active_list_split_settings as current_settings
  where current_settings.list_id = target_list_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'split unavailable';
  end if;
  if settings_record.currency_code = new_currency_code
    and expected_split_version in (settings_record.version, settings_record.version - 1)
  then
    return private.build_active_list_split_projection(target_list_id, caller_id);
  end if;
  if settings_record.version <> expected_split_version then
    raise exception using errcode = '40001', message = 'split changed';
  end if;
  if exists (
    select 1
    from public.active_list_expenses as expense_record
    where expense_record.list_id = target_list_id
  ) then
    raise exception using errcode = '22023', message = 'split currency is locked';
  end if;

  update public.active_list_split_settings as changed_settings
  set currency_code = new_currency_code,
      version = changed_settings.version + 1,
      updated_at = pg_catalog.clock_timestamp()
  where changed_settings.list_id = target_list_id;
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

create function public.create_active_list_expense(
  target_list_id uuid,
  new_description text,
  new_amount_minor bigint,
  payer_participant_id uuid,
  beneficiary_participant_ids uuid[],
  creation_request_id uuid,
  expected_split_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  canonical_description text := pg_catalog.regexp_replace(
    new_description,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  requested_payer_id uuid := payer_participant_id;
  requested_ids uuid[];
  selected_count integer := pg_catalog.cardinality(beneficiary_participant_ids);
  settings_record public.active_list_split_settings%rowtype;
  expense_record public.active_list_expenses%rowtype;
  caller_participant_id uuid;
  existing_ids uuid[];
  mutation_time timestamptz;
begin
  if target_list_id is null
    or creation_request_id is null
    or requested_payer_id is null
    or beneficiary_participant_ids is null
    or selected_count < 1
    or expected_split_version is null
    or expected_split_version < 1
    or canonical_description is null
    or pg_catalog.char_length(canonical_description) not between 1 and 120
    or new_amount_minor is null
    or new_amount_minor not between 1 and 999999999
    or pg_catalog.array_position(beneficiary_participant_ids, null::uuid) is not null
    or exists (
      select submitted.participant_id
      from pg_catalog.unnest(beneficiary_participant_ids) as submitted(participant_id)
      group by submitted.participant_id
      having pg_catalog.count(*) > 1
    )
  then
    raise exception using errcode = '22023', message = 'invalid expense creation';
  end if;
  select pg_catalog.array_agg(submitted.participant_id order by submitted.participant_id)
  into requested_ids
  from pg_catalog.unnest(beneficiary_participant_ids) as submitted(participant_id);

  perform private.lock_mutable_active_list(target_list_id, caller_id);
  select current_settings.* into settings_record
  from public.active_list_split_settings as current_settings
  where current_settings.list_id = target_list_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'split unavailable';
  end if;
  perform private.upsert_active_list_split_participants(target_list_id);
  select split_participant.id into caller_participant_id
  from public.active_list_split_participants as split_participant
  where split_participant.list_id = target_list_id
    and split_participant.profile_id = caller_id;

  select existing_expense.* into expense_record
  from public.active_list_expenses as existing_expense
  where existing_expense.list_id = target_list_id
    and existing_expense.creation_request_id = create_active_list_expense.creation_request_id
  for update;
  if found then
    select pg_catalog.array_agg(existing_share.participant_id order by existing_share.participant_id)
    into existing_ids
    from public.active_list_expense_shares as existing_share
    where existing_share.list_id = target_list_id
      and existing_share.expense_id = expense_record.id;
    if expense_record.description <> canonical_description
      or expense_record.amount_minor <> new_amount_minor
      or expense_record.payer_participant_id <> requested_payer_id
      or existing_ids is distinct from requested_ids
    then
      raise exception using
        errcode = '23505',
        message = 'expense creation request conflict',
        constraint = 'active_list_expenses_list_request_key';
    end if;
    if expected_split_version not in (settings_record.version, settings_record.version - 1)
    then
      raise exception using errcode = '40001', message = 'split changed';
    end if;
    return private.build_active_list_split_projection(target_list_id, caller_id);
  end if;

  if settings_record.version <> expected_split_version then
    raise exception using errcode = '40001', message = 'split changed';
  end if;
  if (
    select pg_catalog.count(*)
    from public.active_list_expenses as current_expense
    where current_expense.list_id = target_list_id
  ) >= 200 then
    raise exception using errcode = '54000', message = 'expense capacity reached';
  end if;
  if not private.active_list_split_participant_is_current(
    target_list_id,
    requested_payer_id
  ) or (
    select pg_catalog.count(*)
    from public.active_list_split_participants as selected_participant
    where selected_participant.list_id = target_list_id
      and selected_participant.id = any(requested_ids)
      and private.active_list_split_participant_is_current(
        target_list_id,
        selected_participant.id
      )
  ) <> selected_count then
    raise exception using errcode = '22023', message = 'expense participant unavailable';
  end if;

  perform 1
  from public.active_list_split_participants as lock_participant
  where lock_participant.list_id = target_list_id
    and lock_participant.id = any(requested_ids || requested_payer_id)
  order by lock_participant.id
  for update;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.active_list_expenses (
    list_id,
    description,
    amount_minor,
    payer_participant_id,
    creator_participant_id,
    last_editor_participant_id,
    creation_request_id,
    created_at,
    updated_at
  ) values (
    target_list_id,
    canonical_description,
    new_amount_minor,
    requested_payer_id,
    caller_participant_id,
    caller_participant_id,
    create_active_list_expense.creation_request_id,
    mutation_time,
    mutation_time
  ) returning * into expense_record;

  insert into public.active_list_expense_shares (
    list_id,
    expense_id,
    participant_id,
    amount_minor
  )
  select
    target_list_id,
    expense_record.id,
    allocated.participant_id,
    (new_amount_minor / selected_count)
      + case
          when allocated.ordinality <= new_amount_minor % selected_count then 1
          else 0
        end
  from pg_catalog.unnest(requested_ids) with ordinality
    as allocated(participant_id, ordinality);

  update public.active_list_split_settings as changed_settings
  set version = changed_settings.version + 1,
      updated_at = mutation_time
  where changed_settings.list_id = target_list_id;
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

create function public.update_active_list_expense(
  target_list_id uuid,
  target_expense_id uuid,
  new_description text,
  new_amount_minor bigint,
  payer_participant_id uuid,
  beneficiary_participant_ids uuid[],
  expected_split_version bigint,
  expected_expense_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  canonical_description text := pg_catalog.regexp_replace(
    new_description,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  requested_payer_id uuid := payer_participant_id;
  requested_ids uuid[];
  selected_count integer := pg_catalog.cardinality(beneficiary_participant_ids);
  settings_record public.active_list_split_settings%rowtype;
  expense_record public.active_list_expenses%rowtype;
  caller_participant_id uuid;
  existing_ids uuid[];
  mutation_time timestamptz;
begin
  if target_list_id is null
    or target_expense_id is null
    or requested_payer_id is null
    or beneficiary_participant_ids is null
    or selected_count < 1
    or expected_split_version is null
    or expected_split_version < 1
    or expected_expense_version is null
    or expected_expense_version < 1
    or canonical_description is null
    or pg_catalog.char_length(canonical_description) not between 1 and 120
    or new_amount_minor is null
    or new_amount_minor not between 1 and 999999999
    or pg_catalog.array_position(beneficiary_participant_ids, null::uuid) is not null
    or exists (
      select submitted.participant_id
      from pg_catalog.unnest(beneficiary_participant_ids) as submitted(participant_id)
      group by submitted.participant_id
      having pg_catalog.count(*) > 1
    )
  then
    raise exception using errcode = '22023', message = 'invalid expense update';
  end if;
  select pg_catalog.array_agg(submitted.participant_id order by submitted.participant_id)
  into requested_ids
  from pg_catalog.unnest(beneficiary_participant_ids) as submitted(participant_id);

  perform private.lock_mutable_active_list(target_list_id, caller_id);
  select current_settings.* into settings_record
  from public.active_list_split_settings as current_settings
  where current_settings.list_id = target_list_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'split unavailable';
  end if;
  perform private.upsert_active_list_split_participants(target_list_id);
  select split_participant.id into caller_participant_id
  from public.active_list_split_participants as split_participant
  where split_participant.list_id = target_list_id
    and split_participant.profile_id = caller_id;

  select current_expense.* into expense_record
  from public.active_list_expenses as current_expense
  where current_expense.list_id = target_list_id
    and current_expense.id = target_expense_id
  for update;
  if not found then
    raise exception using errcode = '40001', message = 'expense changed';
  end if;
  perform 1
  from public.active_list_expense_shares as lock_share
  where lock_share.list_id = target_list_id
    and lock_share.expense_id = target_expense_id
  order by lock_share.participant_id
  for update;
  select pg_catalog.array_agg(existing_share.participant_id order by existing_share.participant_id)
  into existing_ids
  from public.active_list_expense_shares as existing_share
  where existing_share.list_id = target_list_id
    and existing_share.expense_id = target_expense_id;

  if expense_record.description = canonical_description
    and expense_record.amount_minor = new_amount_minor
    and expense_record.payer_participant_id = requested_payer_id
    and existing_ids = requested_ids
    and expected_split_version in (settings_record.version, settings_record.version - 1)
    and expected_expense_version in (expense_record.version, expense_record.version - 1)
  then
    return private.build_active_list_split_projection(target_list_id, caller_id);
  end if;
  if settings_record.version <> expected_split_version
    or expense_record.version <> expected_expense_version
  then
    raise exception using errcode = '40001', message = 'expense changed';
  end if;
  if not (
    private.active_list_split_participant_is_current(target_list_id, requested_payer_id)
    or requested_payer_id = expense_record.payer_participant_id
  ) or exists (
    select 1
    from pg_catalog.unnest(requested_ids) as submitted(participant_id)
    where not private.active_list_split_participant_is_current(
      target_list_id,
      submitted.participant_id
    )
      and not submitted.participant_id = any(existing_ids)
  ) then
    raise exception using errcode = '22023', message = 'expense participant unavailable';
  end if;
  if (
    select pg_catalog.count(*)
    from public.active_list_split_participants as selected_participant
    where selected_participant.list_id = target_list_id
      and selected_participant.id = any(requested_ids || requested_payer_id)
  ) <> pg_catalog.cardinality(
    array(
      select distinct submitted.participant_id
      from pg_catalog.unnest(requested_ids || requested_payer_id)
        as submitted(participant_id)
    )
  ) then
    raise exception using errcode = '22023', message = 'expense participant unavailable';
  end if;

  perform 1
  from public.active_list_split_participants as lock_participant
  where lock_participant.list_id = target_list_id
    and lock_participant.id = any(requested_ids || requested_payer_id)
  order by lock_participant.id
  for update;

  mutation_time := pg_catalog.clock_timestamp();
  update public.active_list_expenses as changed_expense
  set description = canonical_description,
      amount_minor = new_amount_minor,
      payer_participant_id = requested_payer_id,
      last_editor_participant_id = caller_participant_id,
      version = changed_expense.version + 1,
      updated_at = mutation_time
  where changed_expense.list_id = target_list_id
    and changed_expense.id = target_expense_id
  returning * into expense_record;

  delete from public.active_list_expense_shares as old_share
  where old_share.list_id = target_list_id
    and old_share.expense_id = target_expense_id;
  insert into public.active_list_expense_shares (
    list_id,
    expense_id,
    participant_id,
    amount_minor
  )
  select
    target_list_id,
    target_expense_id,
    allocated.participant_id,
    (new_amount_minor / selected_count)
      + case
          when allocated.ordinality <= new_amount_minor % selected_count then 1
          else 0
        end
  from pg_catalog.unnest(requested_ids) with ordinality
    as allocated(participant_id, ordinality);

  update public.active_list_split_settings as changed_settings
  set version = changed_settings.version + 1,
      updated_at = mutation_time
  where changed_settings.list_id = target_list_id;
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

create function public.delete_active_list_expense(
  target_list_id uuid,
  target_expense_id uuid,
  expected_split_version bigint,
  expected_expense_version bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  settings_record public.active_list_split_settings%rowtype;
  expense_record public.active_list_expenses%rowtype;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or target_expense_id is null
    or expected_split_version is null
    or expected_split_version < 1
    or expected_expense_version is null
    or expected_expense_version < 1
  then
    raise exception using errcode = '22023', message = 'invalid expense deletion';
  end if;

  perform private.lock_mutable_active_list(target_list_id, caller_id);
  select current_settings.* into settings_record
  from public.active_list_split_settings as current_settings
  where current_settings.list_id = target_list_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'split unavailable';
  end if;
  select current_expense.* into expense_record
  from public.active_list_expenses as current_expense
  where current_expense.list_id = target_list_id
    and current_expense.id = target_expense_id
  for update;
  if not found then
    raise exception using errcode = '40001', message = 'expense changed';
  end if;
  if settings_record.version <> expected_split_version
    or expense_record.version <> expected_expense_version
  then
    raise exception using errcode = '40001', message = 'expense changed';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  delete from public.active_list_expenses as deleted_expense
  where deleted_expense.list_id = target_list_id
    and deleted_expense.id = target_expense_id;
  update public.active_list_split_settings as changed_settings
  set version = changed_settings.version + 1,
      updated_at = mutation_time
  where changed_settings.list_id = target_list_id;
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

create function private.broadcast_active_list_split_invalidation()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  target_list_id uuid := case when tg_op = 'DELETE' then old.list_id else new.list_id end;
  recipient_ids uuid[];
begin
  recipient_ids := array(
    select list_record.owner_id
    from public.active_lists as list_record
    where list_record.id = target_list_id
    union
    select access_record.participant_profile_id
    from public.active_list_participants as access_record
    where access_record.list_id = target_list_id
      and access_record.state = 'member'
  );
  perform private.send_account_invalidations(recipient_ids);
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger active_list_split_settings_broadcast_invalidation
after insert or update on public.active_list_split_settings
for each row execute function private.broadcast_active_list_split_invalidation();

alter function public.export_own_account_data()
rename to export_own_account_data_v4_base;
alter function public.export_own_account_data_v4_base()
set schema private;
revoke all on function private.export_own_account_data_v4_base()
from public, anon, authenticated, service_role;

create function private.build_active_list_split_export(target_list_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
  projection jsonb;
begin
  select list_record.owner_id into owner_id
  from public.active_lists as list_record
  where list_record.id = target_list_id;
  if not found or not exists (
    select 1
    from public.active_list_split_settings as settings_record
    where settings_record.list_id = target_list_id
  ) then
    return null;
  end if;
  projection := private.build_active_list_split_projection(target_list_id, owner_id);
  return pg_catalog.jsonb_build_object(
    'settings', projection -> 'settings',
    'participants', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', participant.document -> 'id',
          'profile_id', participant.document -> 'profile_id',
          'username', participant.document -> 'username',
          'display_name', participant.document -> 'display_name',
          'is_anonymized', participant.document -> 'is_anonymized',
          'is_current', participant.document -> 'is_current'
        ) order by participant.ordinality
      )
      from pg_catalog.jsonb_array_elements(projection -> 'participants')
        with ordinality as participant(document, ordinality)
    ), '[]'::jsonb),
    'expenses', projection -> 'expenses'
  );
end;
$$;

create function public.export_own_account_data()
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
  base_export := private.export_own_account_data_v4_base();
  select coalesce(
    pg_catalog.jsonb_agg(
      owned_list.document || pg_catalog.jsonb_build_object(
        'split', private.build_active_list_split_export(
          (owned_list.document ->> 'id')::uuid
        )
      ) order by owned_list.ordinality
    ),
    '[]'::jsonb
  ) into enriched_lists
  from pg_catalog.jsonb_array_elements(base_export -> 'active_lists')
    with ordinality as owned_list(document, ordinality);

  return pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(base_export, '{schema_version}', '5'::jsonb),
    '{active_lists}',
    enriched_lists
  );
end;
$$;

alter function private.upsert_active_list_split_participants(uuid) owner to postgres;
alter function private.active_list_split_participant_is_current(uuid, uuid) owner to postgres;
alter function private.sync_active_list_split_participant() owner to postgres;
alter function private.anonymize_active_list_split_participants() owner to postgres;
alter function private.sync_active_list_split_profile_snapshot() owner to postgres;
alter function private.check_active_list_expense_share_total() owner to postgres;
alter function private.build_active_list_split_projection(uuid, uuid) owner to postgres;
alter function private.broadcast_active_list_split_invalidation() owner to postgres;
alter function private.build_active_list_split_export(uuid) owner to postgres;
alter function private.export_own_account_data_v4_base() owner to postgres;
alter function public.get_active_list_split(uuid) owner to postgres;
alter function public.enable_active_list_split(uuid, text, bigint) owner to postgres;
alter function public.change_active_list_split_currency(uuid, text, bigint) owner to postgres;
alter function public.create_active_list_expense(uuid, text, bigint, uuid, uuid[], uuid, bigint)
owner to postgres;
alter function public.update_active_list_expense(uuid, uuid, text, bigint, uuid, uuid[], bigint, bigint)
owner to postgres;
alter function public.delete_active_list_expense(uuid, uuid, bigint, bigint)
owner to postgres;
alter function public.export_own_account_data() owner to postgres;

revoke all on function private.upsert_active_list_split_participants(uuid)
from public, anon, authenticated, service_role;
revoke all on function private.active_list_split_participant_is_current(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function private.sync_active_list_split_participant()
from public, anon, authenticated, service_role;
revoke all on function private.anonymize_active_list_split_participants()
from public, anon, authenticated, service_role;
revoke all on function private.sync_active_list_split_profile_snapshot()
from public, anon, authenticated, service_role;
revoke all on function private.check_active_list_expense_share_total()
from public, anon, authenticated, service_role;
revoke all on function private.build_active_list_split_projection(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function private.broadcast_active_list_split_invalidation()
from public, anon, authenticated, service_role;
revoke all on function private.build_active_list_split_export(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.get_active_list_split(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.enable_active_list_split(uuid, text, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.change_active_list_split_currency(uuid, text, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.create_active_list_expense(uuid, text, bigint, uuid, uuid[], uuid, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.update_active_list_expense(uuid, uuid, text, bigint, uuid, uuid[], bigint, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.delete_active_list_expense(uuid, uuid, bigint, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data()
from public, anon, authenticated, service_role;

grant execute on function public.get_active_list_split(uuid) to authenticated;
grant execute on function public.enable_active_list_split(uuid, text, bigint) to authenticated;
grant execute on function public.change_active_list_split_currency(uuid, text, bigint) to authenticated;
grant execute on function public.create_active_list_expense(uuid, text, bigint, uuid, uuid[], uuid, bigint)
to authenticated;
grant execute on function public.update_active_list_expense(uuid, uuid, text, bigint, uuid, uuid[], bigint, bigint)
to authenticated;
grant execute on function public.delete_active_list_expense(uuid, uuid, bigint, bigint)
to authenticated;
grant execute on function public.export_own_account_data() to authenticated;

comment on table public.active_list_split_settings is
  'RPC-only list Split settings and aggregate version rooted in one active list.';
comment on table public.active_list_split_participants is
  'Persistent list-scoped financial identities that survive membership removal and anonymize on account deletion.';
comment on table public.active_list_expenses is
  'RPC-only versioned integer-minor-unit expenses inside one enabled list Split ledger.';
comment on table public.active_list_expense_shares is
  'Explicit same-list integer equal-share allocations whose total equals their expense.';
comment on function private.upsert_active_list_split_participants(uuid) is
  'Creates or refreshes persistent Split identities for the current owner and accepted members.';
comment on function private.active_list_split_participant_is_current(uuid, uuid) is
  'Checks whether one persistent Split identity still maps to the current owner or an accepted member.';
comment on function private.sync_active_list_split_participant() is
  'Synchronizes live Split identity snapshots across retained participant-state transitions.';
comment on function private.anonymize_active_list_split_participants() is
  'Clears Split profile links and snapshots before profile deletion while preserving arithmetic.';
comment on function private.sync_active_list_split_profile_snapshot() is
  'Refreshes live Split snapshots after an allowlisted profile name changes.';
comment on function private.check_active_list_expense_share_total() is
  'Deferredly enforces at least one explicit share whose integer total equals the expense.';
comment on function private.build_active_list_split_projection(uuid, uuid) is
  'Builds the exact allowlisted Split settings, participant balances, expenses, and shares projection.';
comment on function private.broadcast_active_list_split_invalidation() is
  'Sends one opaque private invalidation to the owner and current accepted members after Split aggregate version changes.';
comment on function private.build_active_list_split_export(uuid) is
  'Builds one allowlisted owned-list Split export or null when Split is disabled.';
comment on function private.export_own_account_data_v4_base() is
  'Internal frozen schema-version-4 allowlist used only to compose version 5.';
comment on function public.get_active_list_split(uuid) is
  'Returns one accessible list Split with server-derived integer balances and exact shares.';
comment on function public.enable_active_list_split(uuid, text, bigint) is
  'Idempotently enables owner-only Split setup with an exact active-list version and CHF or EUR.';
comment on function public.change_active_list_split_currency(uuid, text, bigint) is
  'Version-checks an owner-only currency change while the Split ledger has no expenses.';
comment on function public.create_active_list_expense(uuid, text, bigint, uuid, uuid[], uuid, bigint) is
  'Retry-safely creates one bounded expense and deterministic equal shares for current eligible identities.';
comment on function public.update_active_list_expense(uuid, uuid, text, bigint, uuid, uuid[], bigint, bigint) is
  'Version-checks one atomic expense and equal-share replacement while preserving only attached historical roles.';
comment on function public.delete_active_list_expense(uuid, uuid, bigint, bigint) is
  'Version-checks permanent expense deletion and advances the Split aggregate exactly once.';
comment on function public.export_own_account_data() is
  'Returns schema-version-5 own data with Split nested only in fully exported caller-owned lists.';

commit;
