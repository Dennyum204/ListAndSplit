begin;

create table public.active_list_settlements (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  list_id uuid not null,
  payer_participant_id uuid not null,
  recipient_participant_id uuid not null,
  recorded_by_participant_id uuid not null,
  amount_minor bigint not null,
  note text,
  creation_request_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint active_list_settlements_settings_fkey foreign key (list_id)
    references public.active_list_split_settings(list_id) on delete cascade,
  constraint active_list_settlements_list_id_key unique (list_id, id),
  constraint active_list_settlements_list_request_key unique (
    list_id,
    creation_request_id
  ),
  constraint active_list_settlements_payer_fkey foreign key (
    list_id,
    payer_participant_id
  ) references public.active_list_split_participants(list_id, id)
    deferrable initially deferred,
  constraint active_list_settlements_recipient_fkey foreign key (
    list_id,
    recipient_participant_id
  ) references public.active_list_split_participants(list_id, id)
    deferrable initially deferred,
  constraint active_list_settlements_recorder_fkey foreign key (
    list_id,
    recorded_by_participant_id
  ) references public.active_list_split_participants(list_id, id)
    deferrable initially deferred,
  constraint active_list_settlements_distinct_participants_check check (
    payer_participant_id <> recipient_participant_id
  ),
  constraint active_list_settlements_amount_check check (amount_minor > 0),
  constraint active_list_settlements_note_check check (
    note is null
    or (
      note = pg_catalog.regexp_replace(
        note,
        '^[[:space:]]+|[[:space:]]+$',
        '',
        'g'
      )
      and pg_catalog.char_length(note) between 1 and 120
    )
  )
);

create table public.active_list_settlement_reversals (
  list_id uuid not null,
  settlement_id uuid not null,
  reversed_by_participant_id uuid not null,
  reason text not null,
  reversal_request_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint active_list_settlement_reversals_pkey primary key (
    list_id,
    settlement_id
  ),
  constraint active_list_settlement_reversals_list_request_key unique (
    list_id,
    reversal_request_id
  ),
  constraint active_list_settlement_reversals_settlement_fkey foreign key (
    list_id,
    settlement_id
  ) references public.active_list_settlements(list_id, id) on delete cascade
    deferrable initially deferred,
  constraint active_list_settlement_reversals_actor_fkey foreign key (
    list_id,
    reversed_by_participant_id
  ) references public.active_list_split_participants(list_id, id)
    deferrable initially deferred,
  constraint active_list_settlement_reversals_reason_check check (
    reason = pg_catalog.regexp_replace(
      reason,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    )
    and pg_catalog.char_length(reason) between 1 and 120
  )
);

alter table public.active_list_settlements owner to postgres;
alter table public.active_list_settlement_reversals owner to postgres;

create index active_list_settlements_history_idx
  on public.active_list_settlements(list_id, created_at desc, id desc);
create index active_list_settlements_payer_idx
  on public.active_list_settlements(list_id, payer_participant_id);
create index active_list_settlements_recipient_idx
  on public.active_list_settlements(list_id, recipient_participant_id);
create index active_list_settlements_recorder_idx
  on public.active_list_settlements(list_id, recorded_by_participant_id);
create index active_list_settlement_reversals_actor_idx
  on public.active_list_settlement_reversals(
    list_id,
    reversed_by_participant_id
  );

alter table public.active_list_settlements enable row level security;
alter table public.active_list_settlements force row level security;
alter table public.active_list_settlement_reversals enable row level security;
alter table public.active_list_settlement_reversals force row level security;

revoke all on table public.active_list_settlements
from public, anon, authenticated, service_role;
revoke all on table public.active_list_settlement_reversals
from public, anon, authenticated, service_role;

create policy "active_list_settlements_reject_direct_client_access"
on public.active_list_settlements
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "active_list_settlement_reversals_reject_direct_client_access"
on public.active_list_settlement_reversals
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create function private.reject_active_list_settlement_update()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'settlement history is immutable';
end;
$$;

create trigger active_list_settlements_reject_update
before update on public.active_list_settlements
for each row execute function private.reject_active_list_settlement_update();

create trigger active_list_settlement_reversals_reject_update
before update on public.active_list_settlement_reversals
for each row execute function private.reject_active_list_settlement_update();

create function private.active_list_split_participant_totals(target_list_id uuid)
returns table (
  participant_id uuid,
  expense_paid_minor bigint,
  expense_owed_minor bigint,
  settlement_paid_minor bigint,
  settlement_received_minor bigint,
  balance_minor bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    split_participant.id,
    coalesce(expense_paid.amount_minor, 0)::bigint,
    coalesce(expense_owed.amount_minor, 0)::bigint,
    coalesce(settlement_paid.amount_minor, 0)::bigint,
    coalesce(settlement_received.amount_minor, 0)::bigint,
    (
      coalesce(expense_paid.amount_minor, 0)
      - coalesce(expense_owed.amount_minor, 0)
      + coalesce(settlement_paid.amount_minor, 0)
      - coalesce(settlement_received.amount_minor, 0)
    )::bigint
  from public.active_list_split_participants as split_participant
  left join (
    select
      expense_record.list_id,
      expense_record.payer_participant_id as participant_id,
      pg_catalog.sum(expense_record.amount_minor) as amount_minor
    from public.active_list_expenses as expense_record
    where expense_record.list_id = target_list_id
    group by expense_record.list_id, expense_record.payer_participant_id
  ) as expense_paid
    on expense_paid.list_id = split_participant.list_id
   and expense_paid.participant_id = split_participant.id
  left join (
    select
      share_record.list_id,
      share_record.participant_id,
      pg_catalog.sum(share_record.amount_minor) as amount_minor
    from public.active_list_expense_shares as share_record
    where share_record.list_id = target_list_id
    group by share_record.list_id, share_record.participant_id
  ) as expense_owed
    on expense_owed.list_id = split_participant.list_id
   and expense_owed.participant_id = split_participant.id
  left join (
    select
      settlement_record.list_id,
      settlement_record.payer_participant_id as participant_id,
      pg_catalog.sum(settlement_record.amount_minor) as amount_minor
    from public.active_list_settlements as settlement_record
    where settlement_record.list_id = target_list_id
      and not exists (
        select 1
        from public.active_list_settlement_reversals as reversal_record
        where reversal_record.list_id = settlement_record.list_id
          and reversal_record.settlement_id = settlement_record.id
      )
    group by settlement_record.list_id, settlement_record.payer_participant_id
  ) as settlement_paid
    on settlement_paid.list_id = split_participant.list_id
   and settlement_paid.participant_id = split_participant.id
  left join (
    select
      settlement_record.list_id,
      settlement_record.recipient_participant_id as participant_id,
      pg_catalog.sum(settlement_record.amount_minor) as amount_minor
    from public.active_list_settlements as settlement_record
    where settlement_record.list_id = target_list_id
      and not exists (
        select 1
        from public.active_list_settlement_reversals as reversal_record
        where reversal_record.list_id = settlement_record.list_id
          and reversal_record.settlement_id = settlement_record.id
      )
    group by settlement_record.list_id, settlement_record.recipient_participant_id
  ) as settlement_received
    on settlement_received.list_id = split_participant.list_id
   and settlement_received.participant_id = split_participant.id
  where split_participant.list_id = target_list_id;
$$;

create function private.build_active_list_split_suggestions(target_list_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  debtor_ids uuid[] := '{}'::uuid[];
  debtor_amounts bigint[] := '{}'::bigint[];
  creditor_ids uuid[] := '{}'::uuid[];
  creditor_amounts bigint[] := '{}'::bigint[];
  debtor_index integer := 1;
  creditor_index integer := 1;
  payment_amount bigint;
  suggestions jsonb := '[]'::jsonb;
begin
  select
    coalesce(
      pg_catalog.array_agg(
        totals.participant_id
        order by totals.balance_minor asc, totals.participant_id
      ),
      '{}'::uuid[]
    ),
    coalesce(
      pg_catalog.array_agg(
        -totals.balance_minor
        order by totals.balance_minor asc, totals.participant_id
      ),
      '{}'::bigint[]
    )
  into debtor_ids, debtor_amounts
  from private.active_list_split_participant_totals(target_list_id) as totals
  where totals.balance_minor < 0;

  select
    coalesce(
      pg_catalog.array_agg(
        totals.participant_id
        order by totals.balance_minor desc, totals.participant_id
      ),
      '{}'::uuid[]
    ),
    coalesce(
      pg_catalog.array_agg(
        totals.balance_minor
        order by totals.balance_minor desc, totals.participant_id
      ),
      '{}'::bigint[]
    )
  into creditor_ids, creditor_amounts
  from private.active_list_split_participant_totals(target_list_id) as totals
  where totals.balance_minor > 0;

  while debtor_index <= pg_catalog.cardinality(debtor_ids)
    and creditor_index <= pg_catalog.cardinality(creditor_ids)
  loop
    payment_amount := least(
      debtor_amounts[debtor_index],
      creditor_amounts[creditor_index]
    );
    suggestions := suggestions || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'payer_participant_id', debtor_ids[debtor_index],
        'recipient_participant_id', creditor_ids[creditor_index],
        'amount_minor', payment_amount
      )
    );
    debtor_amounts[debtor_index] :=
      debtor_amounts[debtor_index] - payment_amount;
    creditor_amounts[creditor_index] :=
      creditor_amounts[creditor_index] - payment_amount;
    if debtor_amounts[debtor_index] = 0 then
      debtor_index := debtor_index + 1;
    end if;
    if creditor_amounts[creditor_index] = 0 then
      creditor_index := creditor_index + 1;
    end if;
  end loop;
  return suggestions;
end;
$$;

create or replace function private.build_active_list_split_projection(
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
  suggestion_json jsonb := '[]'::jsonb;
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
          'paid_minor', participant_record.expense_paid_minor,
          'owed_minor', participant_record.expense_owed_minor,
          'settlement_paid_minor', participant_record.settlement_paid_minor,
          'settlement_received_minor', participant_record.settlement_received_minor,
          'balance_minor', participant_record.balance_minor
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
        totals.expense_paid_minor,
        totals.expense_owed_minor,
        totals.settlement_paid_minor,
        totals.settlement_received_minor,
        totals.balance_minor
      from public.active_list_split_participants as split_participant
      join private.active_list_split_participant_totals(target_list_id) as totals
        on totals.participant_id = split_participant.id
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
          or exists (
            select 1
            from public.active_list_settlements as relevant_settlement
            where relevant_settlement.list_id = target_list_id
              and split_participant.id in (
                relevant_settlement.payer_participant_id,
                relevant_settlement.recipient_participant_id,
                relevant_settlement.recorded_by_participant_id
              )
          )
          or exists (
            select 1
            from public.active_list_settlement_reversals as relevant_reversal
            where relevant_reversal.list_id = target_list_id
              and relevant_reversal.reversed_by_participant_id =
                split_participant.id
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
            select pg_catalog.jsonb_agg(
              share_record.participant_id order by share_record.participant_id
            )
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

    suggestion_json :=
      private.build_active_list_split_suggestions(target_list_id);
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
    'expenses', expense_json,
    'suggestions', suggestion_json
  );
end;
$$;

create or replace function public.change_active_list_split_currency(
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
  ) or exists (
    select 1
    from public.active_list_settlements as settlement_record
    where settlement_record.list_id = target_list_id
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

create function public.list_active_list_settlements(
  target_list_id uuid,
  page_size integer,
  cursor_created_at timestamptz default null,
  cursor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_active_list_caller();
  list_record public.active_lists%rowtype;
  currency_code text;
  caller_participant_id uuid;
  entries jsonb := '[]'::jsonb;
  has_more boolean := false;
  next_created_at timestamptz;
  next_id uuid;
begin
  if target_list_id is null
    or page_size is null
    or page_size not between 1 and 50
    or (cursor_created_at is null) <> (cursor_id is null)
  then
    raise exception using errcode = '22023', message = 'invalid settlement page';
  end if;
  if not private.active_list_caller_is_member(target_list_id, caller_id) then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  select current_list.* into list_record
  from public.active_lists as current_list
  where current_list.id = target_list_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'list unavailable';
  end if;
  select settings_record.currency_code into currency_code
  from public.active_list_split_settings as settings_record
  where settings_record.list_id = target_list_id;
  if not found then
    return pg_catalog.jsonb_build_object(
      'list_id', target_list_id,
      'currency_code', null,
      'entries', '[]'::jsonb,
      'next_cursor', null
    );
  end if;
  select split_participant.id into caller_participant_id
  from public.active_list_split_participants as split_participant
  where split_participant.list_id = target_list_id
    and split_participant.profile_id = caller_id;

  with candidates as (
    select
      settlement_record.id,
      settlement_record.created_at,
      pg_catalog.jsonb_build_object(
        'id', settlement_record.id,
        'payer_participant_id', settlement_record.payer_participant_id,
        'recipient_participant_id', settlement_record.recipient_participant_id,
        'recorded_by_participant_id', settlement_record.recorded_by_participant_id,
        'amount_minor', settlement_record.amount_minor,
        'note', settlement_record.note,
        'created_at', settlement_record.created_at,
        'can_reverse',
          reversal_record.settlement_id is null
          and list_record.status = 'active'
          and (
            list_record.owner_id = caller_id
            or settlement_record.recorded_by_participant_id =
              caller_participant_id
          ),
        'reversal', case
          when reversal_record.settlement_id is null then null
          else pg_catalog.jsonb_build_object(
            'reversed_by_participant_id',
              reversal_record.reversed_by_participant_id,
            'reason', reversal_record.reason,
            'created_at', reversal_record.created_at
          )
        end
      ) as document
    from public.active_list_settlements as settlement_record
    left join public.active_list_settlement_reversals as reversal_record
      on reversal_record.list_id = settlement_record.list_id
     and reversal_record.settlement_id = settlement_record.id
    where settlement_record.list_id = target_list_id
      and (
        cursor_created_at is null
        or (settlement_record.created_at, settlement_record.id)
          < (cursor_created_at, cursor_id)
      )
    order by settlement_record.created_at desc, settlement_record.id desc
    limit page_size + 1
  ),
  numbered as (
    select
      candidate.*,
      pg_catalog.row_number() over (
        order by candidate.created_at desc, candidate.id desc
      ) as ordinal
    from candidates as candidate
  )
  select
    coalesce(
      pg_catalog.jsonb_agg(
        numbered.document
        order by numbered.created_at desc, numbered.id desc
      ) filter (where numbered.ordinal <= page_size),
      '[]'::jsonb
    ),
    pg_catalog.count(*) > page_size,
    (
      pg_catalog.array_agg(numbered.created_at)
        filter (where numbered.ordinal = page_size)
    )[1],
    (
      pg_catalog.array_agg(numbered.id)
        filter (where numbered.ordinal = page_size)
    )[1]
  into entries, has_more, next_created_at, next_id
  from numbered;

  return pg_catalog.jsonb_build_object(
    'list_id', target_list_id,
    'currency_code', currency_code,
    'entries', entries,
    'next_cursor', case when has_more then pg_catalog.jsonb_build_object(
      'created_at', next_created_at,
      'id', next_id
    ) else null end
  );
end;
$$;

create function public.record_active_list_settlement(
  target_list_id uuid,
  payer_participant_id uuid,
  recipient_participant_id uuid,
  new_amount_minor bigint,
  new_note text,
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
  canonical_note text := nullif(
    pg_catalog.regexp_replace(
      new_note,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    ),
    ''
  );
  settings_record public.active_list_split_settings%rowtype;
  settlement_record public.active_list_settlements%rowtype;
  caller_participant_id uuid;
  payer_balance bigint;
  recipient_balance bigint;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or payer_participant_id is null
    or recipient_participant_id is null
    or payer_participant_id = recipient_participant_id
    or new_amount_minor is null
    or new_amount_minor < 1
    or creation_request_id is null
    or expected_split_version is null
    or expected_split_version < 1
    or (
      canonical_note is not null
      and pg_catalog.char_length(canonical_note) > 120
    )
  then
    raise exception using errcode = '22023', message = 'invalid settlement';
  end if;

  perform private.lock_mutable_active_list(target_list_id, caller_id);
  select current_settings.* into settings_record
  from public.active_list_split_settings as current_settings
  where current_settings.list_id = target_list_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'split unavailable';
  end if;
  select split_participant.id into caller_participant_id
  from public.active_list_split_participants as split_participant
  where split_participant.list_id = target_list_id
    and split_participant.profile_id = caller_id;
  if not found then
    perform private.upsert_active_list_split_participants(target_list_id);
    select split_participant.id into caller_participant_id
    from public.active_list_split_participants as split_participant
    where split_participant.list_id = target_list_id
      and split_participant.profile_id = caller_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'split unavailable';
    end if;
  end if;

  select existing_settlement.* into settlement_record
  from public.active_list_settlements as existing_settlement
  where existing_settlement.list_id = target_list_id
    and existing_settlement.creation_request_id =
      record_active_list_settlement.creation_request_id
  for update;
  if found then
    if settlement_record.payer_participant_id <> payer_participant_id
      or settlement_record.recipient_participant_id <> recipient_participant_id
      or settlement_record.amount_minor <> new_amount_minor
      or settlement_record.note is distinct from canonical_note
      or settlement_record.recorded_by_participant_id <> caller_participant_id
    then
      raise exception using
        errcode = '23505',
        message = 'settlement request conflict',
        constraint = 'active_list_settlements_list_request_key';
    end if;
    if expected_split_version not in (
      settings_record.version,
      settings_record.version - 1
    ) then
      raise exception using errcode = '40001', message = 'split changed';
    end if;
    return private.build_active_list_split_projection(target_list_id, caller_id);
  end if;

  if settings_record.version <> expected_split_version then
    raise exception using errcode = '40001', message = 'split changed';
  end if;
  if (
    select pg_catalog.count(*)
    from public.active_list_split_participants as endpoint
    where endpoint.list_id = target_list_id
      and endpoint.id in (payer_participant_id, recipient_participant_id)
  ) <> 2 then
    raise exception using
      errcode = '22023',
      message = 'settlement participant unavailable';
  end if;

  perform 1
  from public.active_list_split_participants as lock_participant
  where lock_participant.list_id = target_list_id
    and lock_participant.id in (payer_participant_id, recipient_participant_id)
  order by lock_participant.id
  for update;

  select totals.balance_minor into payer_balance
  from private.active_list_split_participant_totals(target_list_id) as totals
  where totals.participant_id = payer_participant_id;
  select totals.balance_minor into recipient_balance
  from private.active_list_split_participant_totals(target_list_id) as totals
  where totals.participant_id = recipient_participant_id;
  if payer_balance >= 0
    or recipient_balance <= 0
    or new_amount_minor > least(-payer_balance, recipient_balance)
  then
    raise exception using
      errcode = '22023',
      message = 'settlement exceeds outstanding balance';
  end if;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.active_list_settlements (
    list_id,
    payer_participant_id,
    recipient_participant_id,
    recorded_by_participant_id,
    amount_minor,
    note,
    creation_request_id,
    created_at
  ) values (
    target_list_id,
    payer_participant_id,
    recipient_participant_id,
    caller_participant_id,
    new_amount_minor,
    canonical_note,
    record_active_list_settlement.creation_request_id,
    mutation_time
  );
  update public.active_list_split_settings as changed_settings
  set version = changed_settings.version + 1,
      updated_at = mutation_time
  where changed_settings.list_id = target_list_id;
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

create function public.reverse_active_list_settlement(
  target_list_id uuid,
  target_settlement_id uuid,
  reversal_reason text,
  reversal_request_id uuid,
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
  canonical_reason text := pg_catalog.regexp_replace(
    reversal_reason,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  list_record public.active_lists%rowtype;
  settings_record public.active_list_split_settings%rowtype;
  settlement_record public.active_list_settlements%rowtype;
  reversal_record public.active_list_settlement_reversals%rowtype;
  caller_participant_id uuid;
  mutation_time timestamptz;
begin
  if target_list_id is null
    or target_settlement_id is null
    or canonical_reason is null
    or pg_catalog.char_length(canonical_reason) not between 1 and 120
    or reversal_request_id is null
    or expected_split_version is null
    or expected_split_version < 1
  then
    raise exception using errcode = '22023', message = 'invalid settlement reversal';
  end if;

  list_record := private.lock_mutable_active_list(target_list_id, caller_id);
  select current_settings.* into settings_record
  from public.active_list_split_settings as current_settings
  where current_settings.list_id = target_list_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'split unavailable';
  end if;
  select split_participant.id into caller_participant_id
  from public.active_list_split_participants as split_participant
  where split_participant.list_id = target_list_id
    and split_participant.profile_id = caller_id;
  if not found then
    perform private.upsert_active_list_split_participants(target_list_id);
    select split_participant.id into caller_participant_id
    from public.active_list_split_participants as split_participant
    where split_participant.list_id = target_list_id
      and split_participant.profile_id = caller_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'split unavailable';
    end if;
  end if;

  select existing_reversal.* into reversal_record
  from public.active_list_settlement_reversals as existing_reversal
  where existing_reversal.list_id = target_list_id
    and existing_reversal.reversal_request_id =
      reverse_active_list_settlement.reversal_request_id
  for update;
  if found then
    if reversal_record.settlement_id <> target_settlement_id
      or reversal_record.reason <> canonical_reason
      or reversal_record.reversed_by_participant_id <> caller_participant_id
    then
      raise exception using
        errcode = '23505',
        message = 'settlement reversal request conflict',
        constraint = 'active_list_settlement_reversals_list_request_key';
    end if;
    if expected_split_version not in (
      settings_record.version,
      settings_record.version - 1
    ) then
      raise exception using errcode = '40001', message = 'split changed';
    end if;
    return private.build_active_list_split_projection(target_list_id, caller_id);
  end if;

  if settings_record.version <> expected_split_version then
    raise exception using errcode = '40001', message = 'split changed';
  end if;
  select current_settlement.* into settlement_record
  from public.active_list_settlements as current_settlement
  where current_settlement.list_id = target_list_id
    and current_settlement.id = target_settlement_id
  for update;
  if not found then
    raise exception using errcode = '40001', message = 'settlement changed';
  end if;
  if exists (
    select 1
    from public.active_list_settlement_reversals as current_reversal
    where current_reversal.list_id = target_list_id
      and current_reversal.settlement_id = target_settlement_id
  ) then
    raise exception using errcode = '40001', message = 'settlement changed';
  end if;
  if list_record.owner_id <> caller_id
    and settlement_record.recorded_by_participant_id <> caller_participant_id
  then
    raise exception using errcode = '40001', message = 'settlement changed';
  end if;

  perform 1
  from public.active_list_split_participants as lock_participant
  where lock_participant.list_id = target_list_id
    and lock_participant.id in (
      settlement_record.payer_participant_id,
      settlement_record.recipient_participant_id,
      settlement_record.recorded_by_participant_id,
      caller_participant_id
    )
  order by lock_participant.id
  for update;

  mutation_time := pg_catalog.clock_timestamp();
  insert into public.active_list_settlement_reversals (
    list_id,
    settlement_id,
    reversed_by_participant_id,
    reason,
    reversal_request_id,
    created_at
  ) values (
    target_list_id,
    target_settlement_id,
    caller_participant_id,
    canonical_reason,
    reverse_active_list_settlement.reversal_request_id,
    mutation_time
  );
  update public.active_list_split_settings as changed_settings
  set version = changed_settings.version + 1,
      updated_at = mutation_time
  where changed_settings.list_id = target_list_id;
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

alter function public.export_own_account_data()
rename to export_own_account_data_v5_base;
alter function public.export_own_account_data_v5_base()
set schema private;
revoke all on function private.export_own_account_data_v5_base()
from public, anon, authenticated, service_role;

create function private.build_active_list_split_export_v6(target_list_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  base_split jsonb;
  settlement_json jsonb;
begin
  base_split := private.build_active_list_split_export(target_list_id);
  if base_split is null then
    return null;
  end if;
  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', settlement_record.id,
        'payer_participant_id', settlement_record.payer_participant_id,
        'recipient_participant_id', settlement_record.recipient_participant_id,
        'recorded_by_participant_id', settlement_record.recorded_by_participant_id,
        'amount_minor', settlement_record.amount_minor,
        'note', settlement_record.note,
        'created_at', settlement_record.created_at,
        'reversal', case
          when reversal_record.settlement_id is null then null
          else pg_catalog.jsonb_build_object(
            'reversed_by_participant_id',
              reversal_record.reversed_by_participant_id,
            'reason', reversal_record.reason,
            'created_at', reversal_record.created_at
          )
        end
      ) order by settlement_record.created_at desc, settlement_record.id desc
    ),
    '[]'::jsonb
  ) into settlement_json
  from public.active_list_settlements as settlement_record
  left join public.active_list_settlement_reversals as reversal_record
    on reversal_record.list_id = settlement_record.list_id
   and reversal_record.settlement_id = settlement_record.id
  where settlement_record.list_id = target_list_id;

  return base_split || pg_catalog.jsonb_build_object(
    'settlements',
    settlement_json
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
  base_export := private.export_own_account_data_v5_base();
  select coalesce(
    pg_catalog.jsonb_agg(
      owned_list.document || pg_catalog.jsonb_build_object(
        'split', private.build_active_list_split_export_v6(
          (owned_list.document ->> 'id')::uuid
        )
      ) order by owned_list.ordinality
    ),
    '[]'::jsonb
  ) into enriched_lists
  from pg_catalog.jsonb_array_elements(base_export -> 'active_lists')
    with ordinality as owned_list(document, ordinality);

  return pg_catalog.jsonb_set(
    pg_catalog.jsonb_set(base_export, '{schema_version}', '6'::jsonb),
    '{active_lists}',
    enriched_lists
  );
end;
$$;

alter function private.reject_active_list_settlement_update() owner to postgres;
alter function private.active_list_split_participant_totals(uuid) owner to postgres;
alter function private.build_active_list_split_suggestions(uuid) owner to postgres;
alter function private.build_active_list_split_projection(uuid, uuid) owner to postgres;
alter function public.change_active_list_split_currency(uuid, text, bigint)
owner to postgres;
alter function public.list_active_list_settlements(uuid, integer, timestamptz, uuid)
owner to postgres;
alter function public.record_active_list_settlement(
  uuid,
  uuid,
  uuid,
  bigint,
  text,
  uuid,
  bigint
) owner to postgres;
alter function public.reverse_active_list_settlement(
  uuid,
  uuid,
  text,
  uuid,
  bigint
) owner to postgres;
alter function private.export_own_account_data_v5_base() owner to postgres;
alter function private.build_active_list_split_export_v6(uuid) owner to postgres;
alter function public.export_own_account_data() owner to postgres;

revoke all on function private.reject_active_list_settlement_update()
from public, anon, authenticated, service_role;
revoke all on function private.active_list_split_participant_totals(uuid)
from public, anon, authenticated, service_role;
revoke all on function private.build_active_list_split_suggestions(uuid)
from public, anon, authenticated, service_role;
revoke all on function private.build_active_list_split_projection(uuid, uuid)
from public, anon, authenticated, service_role;
revoke all on function public.change_active_list_split_currency(uuid, text, bigint)
from public, anon, authenticated, service_role;
revoke all on function public.list_active_list_settlements(
  uuid,
  integer,
  timestamptz,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function public.record_active_list_settlement(
  uuid,
  uuid,
  uuid,
  bigint,
  text,
  uuid,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.reverse_active_list_settlement(
  uuid,
  uuid,
  text,
  uuid,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function private.export_own_account_data_v5_base()
from public, anon, authenticated, service_role;
revoke all on function private.build_active_list_split_export_v6(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.export_own_account_data()
from public, anon, authenticated, service_role;

grant execute on function public.change_active_list_split_currency(uuid, text, bigint)
to authenticated;
grant execute on function public.list_active_list_settlements(
  uuid,
  integer,
  timestamptz,
  uuid
) to authenticated;
grant execute on function public.record_active_list_settlement(
  uuid,
  uuid,
  uuid,
  bigint,
  text,
  uuid,
  bigint
) to authenticated;
grant execute on function public.reverse_active_list_settlement(
  uuid,
  uuid,
  text,
  uuid,
  bigint
) to authenticated;
grant execute on function public.export_own_account_data() to authenticated;

comment on table public.active_list_settlements is
  'RPC-only immutable integer-minor-unit settlement history for one enabled list Split ledger.';
comment on table public.active_list_settlement_reversals is
  'RPC-only append-only one-time corrections that preserve the original settlement history.';
comment on function private.reject_active_list_settlement_update() is
  'Rejects in-place changes to immutable settlement and reversal history.';
comment on function private.active_list_split_participant_totals(uuid) is
  'Calculates exact expense and unreversed-settlement totals for every persistent Split identity.';
comment on function private.build_active_list_split_suggestions(uuid) is
  'Builds deterministic largest-balance-first debtor-to-creditor suggestions with UUID tie-breaks.';
comment on function private.build_active_list_split_projection(uuid, uuid) is
  'Builds exact Split settings, settlement-adjusted participant balances, expenses, shares, and deterministic suggestions.';
comment on function public.change_active_list_split_currency(uuid, text, bigint) is
  'Version-checks an owner-only currency change while the Split ledger has no expense or settlement history.';
comment on function public.list_active_list_settlements(
  uuid,
  integer,
  timestamptz,
  uuid
) is
  'Returns bounded keyset-paginated immutable settlement history with server-derived reversal authority.';
comment on function public.record_active_list_settlement(
  uuid,
  uuid,
  uuid,
  bigint,
  text,
  uuid,
  bigint
) is
  'Retry-safely records one full or partial current-balance settlement between persistent Split identities.';
comment on function public.reverse_active_list_settlement(
  uuid,
  uuid,
  text,
  uuid,
  bigint
) is
  'Retry-safely appends one authorized reversal while preserving immutable financial history.';
comment on function private.export_own_account_data_v5_base() is
  'Internal frozen schema-version-5 allowlist used only to compose version 6.';
comment on function private.build_active_list_split_export_v6(uuid) is
  'Builds one allowlisted owned-list Split export with immutable settlement and nested reversal history.';
comment on function public.export_own_account_data() is
  'Returns schema-version-6 own data with Split settlement history only in fully exported caller-owned lists.';

commit;
