begin;

create function private.active_list_expense_has_canonical_equal_shares(
  target_list_id uuid,
  target_expense_id uuid,
  target_amount_minor bigint
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    target_list_id is not null
    and target_expense_id is not null
    and target_amount_minor is not null
    and exists (
      select 1
      from public.active_list_expense_shares as present_share
      where present_share.list_id = target_list_id
        and present_share.expense_id = target_expense_id
    )
    and not exists (
      select 1
      from (
        select
          share_record.amount_minor,
          pg_catalog.row_number() over (
            order by share_record.participant_id
          ) as allocation_ordinality,
          pg_catalog.count(*) over () as allocation_count
        from public.active_list_expense_shares as share_record
        where share_record.list_id = target_list_id
          and share_record.expense_id = target_expense_id
      ) as allocated
      where allocated.amount_minor <> (
        target_amount_minor / allocated.allocation_count
      ) + case
        when allocated.allocation_ordinality
          <= target_amount_minor % allocated.allocation_count
        then 1
        else 0
      end
    );
$$;

create function public.create_active_list_expense_v2(
  target_list_id uuid,
  new_description text,
  new_amount_minor bigint,
  payer_participant_id uuid,
  beneficiary_participant_ids uuid[],
  beneficiary_amounts_minor bigint[],
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
  requested_amounts bigint[];
  selected_count integer := pg_catalog.cardinality(beneficiary_participant_ids);
  settings_record public.active_list_split_settings%rowtype;
  expense_record public.active_list_expenses%rowtype;
  caller_participant_id uuid;
  existing_ids uuid[];
  existing_amounts bigint[];
  mutation_time timestamptz;
begin
  if target_list_id is null
    or creation_request_id is null
    or requested_payer_id is null
    or beneficiary_participant_ids is null
    or selected_count is null
    or selected_count not between 1 and 20
    or expected_split_version is null
    or expected_split_version < 1
    or canonical_description is null
    or pg_catalog.char_length(canonical_description) not between 1 and 120
    or new_amount_minor is null
    or new_amount_minor not between 1 and 999999999
    or pg_catalog.array_position(
      beneficiary_participant_ids,
      null::uuid
    ) is not null
    or exists (
      select submitted.participant_id
      from pg_catalog.unnest(beneficiary_participant_ids)
        as submitted(participant_id)
      group by submitted.participant_id
      having pg_catalog.count(*) > 1
    )
    or (
      beneficiary_amounts_minor is not null
      and (
        pg_catalog.cardinality(beneficiary_amounts_minor) <> selected_count
        or pg_catalog.array_position(
          beneficiary_amounts_minor,
          null::bigint
        ) is not null
        or exists (
          select 1
          from pg_catalog.unnest(beneficiary_amounts_minor)
            as submitted(amount_minor)
          where submitted.amount_minor not between 1 and 999999999
        )
        or (
          select coalesce(
            pg_catalog.sum(submitted.amount_minor::numeric),
            0::numeric
          )
          from pg_catalog.unnest(beneficiary_amounts_minor)
            as submitted(amount_minor)
        ) <> new_amount_minor::numeric
      )
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid expense creation';
  end if;

  if beneficiary_amounts_minor is null then
    select pg_catalog.array_agg(
      submitted.participant_id
      order by submitted.participant_id
    )
    into requested_ids
    from pg_catalog.unnest(beneficiary_participant_ids)
      as submitted(participant_id);

    select pg_catalog.array_agg(
      (new_amount_minor / selected_count)
        + case
            when allocated.ordinality <= new_amount_minor % selected_count
            then 1
            else 0
          end
      order by allocated.ordinality
    )
    into requested_amounts
    from pg_catalog.unnest(requested_ids) with ordinality
      as allocated(participant_id, ordinality);
  else
    select
      pg_catalog.array_agg(
        submitted.participant_id
        order by submitted.participant_id
      ),
      pg_catalog.array_agg(
        submitted.amount_minor
        order by submitted.participant_id
      )
    into requested_ids, requested_amounts
    from rows from (
      pg_catalog.unnest(beneficiary_participant_ids),
      pg_catalog.unnest(beneficiary_amounts_minor)
    ) as submitted(participant_id, amount_minor);
  end if;

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
    and existing_expense.creation_request_id =
      create_active_list_expense_v2.creation_request_id
  for update;
  if found then
    select
      pg_catalog.array_agg(
        existing_share.participant_id
        order by existing_share.participant_id
      ),
      pg_catalog.array_agg(
        existing_share.amount_minor
        order by existing_share.participant_id
      )
    into existing_ids, existing_amounts
    from public.active_list_expense_shares as existing_share
    where existing_share.list_id = target_list_id
      and existing_share.expense_id = expense_record.id;

    if expense_record.description <> canonical_description
      or expense_record.amount_minor <> new_amount_minor
      or expense_record.payer_participant_id <> requested_payer_id
      or existing_ids is distinct from requested_ids
      or existing_amounts is distinct from requested_amounts
    then
      raise exception using
        errcode = '23505',
        message = 'expense creation request conflict',
        constraint = 'active_list_expenses_list_request_key';
    end if;
    if expected_split_version not in (
      settings_record.version,
      settings_record.version - 1
    ) then
      raise exception using errcode = '40001', message = 'split changed';
    end if;
    return private.build_active_list_split_projection(
      target_list_id,
      caller_id
    );
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
    raise exception using
      errcode = '22023',
      message = 'expense participant unavailable';
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
    create_active_list_expense_v2.creation_request_id,
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
    allocated.amount_minor
  from rows from (
    pg_catalog.unnest(requested_ids),
    pg_catalog.unnest(requested_amounts)
  ) as allocated(participant_id, amount_minor);

  update public.active_list_split_settings as changed_settings
  set version = changed_settings.version + 1,
      updated_at = mutation_time
  where changed_settings.list_id = target_list_id;
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

create function public.update_active_list_expense_v2(
  target_list_id uuid,
  target_expense_id uuid,
  new_description text,
  new_amount_minor bigint,
  payer_participant_id uuid,
  beneficiary_participant_ids uuid[],
  beneficiary_amounts_minor bigint[],
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
  requested_amounts bigint[];
  selected_count integer := pg_catalog.cardinality(beneficiary_participant_ids);
  settings_record public.active_list_split_settings%rowtype;
  expense_record public.active_list_expenses%rowtype;
  caller_participant_id uuid;
  existing_ids uuid[];
  existing_amounts bigint[];
  mutation_time timestamptz;
begin
  if target_list_id is null
    or target_expense_id is null
    or requested_payer_id is null
    or beneficiary_participant_ids is null
    or selected_count is null
    or selected_count < 1
    or expected_split_version is null
    or expected_split_version < 1
    or expected_expense_version is null
    or expected_expense_version < 1
    or canonical_description is null
    or pg_catalog.char_length(canonical_description) not between 1 and 120
    or new_amount_minor is null
    or new_amount_minor not between 1 and 999999999
    or pg_catalog.array_position(
      beneficiary_participant_ids,
      null::uuid
    ) is not null
    or exists (
      select submitted.participant_id
      from pg_catalog.unnest(beneficiary_participant_ids)
        as submitted(participant_id)
      group by submitted.participant_id
      having pg_catalog.count(*) > 1
    )
    or (
      beneficiary_amounts_minor is not null
      and (
        pg_catalog.cardinality(beneficiary_amounts_minor) <> selected_count
        or pg_catalog.array_position(
          beneficiary_amounts_minor,
          null::bigint
        ) is not null
        or exists (
          select 1
          from pg_catalog.unnest(beneficiary_amounts_minor)
            as submitted(amount_minor)
          where submitted.amount_minor not between 1 and 999999999
        )
        or (
          select coalesce(
            pg_catalog.sum(submitted.amount_minor::numeric),
            0::numeric
          )
          from pg_catalog.unnest(beneficiary_amounts_minor)
            as submitted(amount_minor)
        ) <> new_amount_minor::numeric
      )
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid expense update';
  end if;

  if beneficiary_amounts_minor is null then
    select pg_catalog.array_agg(
      submitted.participant_id
      order by submitted.participant_id
    )
    into requested_ids
    from pg_catalog.unnest(beneficiary_participant_ids)
      as submitted(participant_id);

    select pg_catalog.array_agg(
      (new_amount_minor / selected_count)
        + case
            when allocated.ordinality <= new_amount_minor % selected_count
            then 1
            else 0
          end
      order by allocated.ordinality
    )
    into requested_amounts
    from pg_catalog.unnest(requested_ids) with ordinality
      as allocated(participant_id, ordinality);
  else
    select
      pg_catalog.array_agg(
        submitted.participant_id
        order by submitted.participant_id
      ),
      pg_catalog.array_agg(
        submitted.amount_minor
        order by submitted.participant_id
      )
    into requested_ids, requested_amounts
    from rows from (
      pg_catalog.unnest(beneficiary_participant_ids),
      pg_catalog.unnest(beneficiary_amounts_minor)
    ) as submitted(participant_id, amount_minor);
  end if;

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
  select
    pg_catalog.array_agg(
      existing_share.participant_id
      order by existing_share.participant_id
    ),
    pg_catalog.array_agg(
      existing_share.amount_minor
      order by existing_share.participant_id
    )
  into existing_ids, existing_amounts
  from public.active_list_expense_shares as existing_share
  where existing_share.list_id = target_list_id
    and existing_share.expense_id = target_expense_id;

  if expense_record.description = canonical_description
    and expense_record.amount_minor = new_amount_minor
    and expense_record.payer_participant_id = requested_payer_id
    and existing_ids = requested_ids
    and existing_amounts = requested_amounts
    and expected_split_version in (
      settings_record.version,
      settings_record.version - 1
    )
    and expected_expense_version in (
      expense_record.version,
      expense_record.version - 1
    )
  then
    return private.build_active_list_split_projection(
      target_list_id,
      caller_id
    );
  end if;
  if settings_record.version <> expected_split_version
    or expense_record.version <> expected_expense_version
  then
    raise exception using errcode = '40001', message = 'expense changed';
  end if;
  if not (
    private.active_list_split_participant_is_current(
      target_list_id,
      requested_payer_id
    )
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
    raise exception using
      errcode = '22023',
      message = 'expense participant unavailable';
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
    raise exception using
      errcode = '22023',
      message = 'expense participant unavailable';
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
    allocated.amount_minor
  from rows from (
    pg_catalog.unnest(requested_ids),
    pg_catalog.unnest(requested_amounts)
  ) as allocated(participant_id, amount_minor);

  update public.active_list_split_settings as changed_settings
  set version = changed_settings.version + 1,
      updated_at = mutation_time
  where changed_settings.list_id = target_list_id;
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

create or replace function public.create_active_list_expense(
  target_list_id uuid,
  new_description text,
  new_amount_minor bigint,
  payer_participant_id uuid,
  beneficiary_participant_ids uuid[],
  creation_request_id uuid,
  expected_split_version bigint
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$
  select public.create_active_list_expense_v2(
    target_list_id,
    new_description,
    new_amount_minor,
    payer_participant_id,
    beneficiary_participant_ids,
    null::bigint[],
    creation_request_id,
    expected_split_version
  );
$$;

create or replace function public.update_active_list_expense(
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
  existing_amounts bigint[];
  requested_amounts bigint[];
  mutation_time timestamptz;
begin
  if target_list_id is null
    or target_expense_id is null
    or requested_payer_id is null
    or beneficiary_participant_ids is null
    or selected_count is null
    or selected_count < 1
    or expected_split_version is null
    or expected_split_version < 1
    or expected_expense_version is null
    or expected_expense_version < 1
    or canonical_description is null
    or pg_catalog.char_length(canonical_description) not between 1 and 120
    or new_amount_minor is null
    or new_amount_minor not between 1 and 999999999
    or pg_catalog.array_position(
      beneficiary_participant_ids,
      null::uuid
    ) is not null
    or exists (
      select submitted.participant_id
      from pg_catalog.unnest(beneficiary_participant_ids)
        as submitted(participant_id)
      group by submitted.participant_id
      having pg_catalog.count(*) > 1
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid expense update';
  end if;

  select pg_catalog.array_agg(
    submitted.participant_id
    order by submitted.participant_id
  )
  into requested_ids
  from pg_catalog.unnest(beneficiary_participant_ids)
    as submitted(participant_id);
  select pg_catalog.array_agg(
    (new_amount_minor / selected_count)
      + case
          when allocated.ordinality <= new_amount_minor % selected_count
          then 1
          else 0
        end
    order by allocated.ordinality
  )
  into requested_amounts
  from pg_catalog.unnest(requested_ids) with ordinality
    as allocated(participant_id, ordinality);

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
  select
    pg_catalog.array_agg(
      existing_share.participant_id
      order by existing_share.participant_id
    ),
    pg_catalog.array_agg(
      existing_share.amount_minor
      order by existing_share.participant_id
    )
  into existing_ids, existing_amounts
  from public.active_list_expense_shares as existing_share
  where existing_share.list_id = target_list_id
    and existing_share.expense_id = target_expense_id;

  if not private.active_list_expense_has_canonical_equal_shares(
    target_list_id,
    target_expense_id,
    expense_record.amount_minor
  ) then
    raise exception using
      errcode = '55000',
      message = 'custom expense requires updated client';
  end if;

  if expense_record.description = canonical_description
    and expense_record.amount_minor = new_amount_minor
    and expense_record.payer_participant_id = requested_payer_id
    and existing_ids = requested_ids
    and existing_amounts = requested_amounts
    and expected_split_version in (
      settings_record.version,
      settings_record.version - 1
    )
    and expected_expense_version in (
      expense_record.version,
      expense_record.version - 1
    )
  then
    return private.build_active_list_split_projection(
      target_list_id,
      caller_id
    );
  end if;
  if settings_record.version <> expected_split_version
    or expense_record.version <> expected_expense_version
  then
    raise exception using errcode = '40001', message = 'expense changed';
  end if;
  if not (
    private.active_list_split_participant_is_current(
      target_list_id,
      requested_payer_id
    )
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
    raise exception using
      errcode = '22023',
      message = 'expense participant unavailable';
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
    raise exception using
      errcode = '22023',
      message = 'expense participant unavailable';
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
    allocated.amount_minor
  from rows from (
    pg_catalog.unnest(requested_ids),
    pg_catalog.unnest(requested_amounts)
  ) as allocated(participant_id, amount_minor);

  update public.active_list_split_settings as changed_settings
  set version = changed_settings.version + 1,
      updated_at = mutation_time
  where changed_settings.list_id = target_list_id;
  return private.build_active_list_split_projection(target_list_id, caller_id);
end;
$$;

alter function private.active_list_expense_has_canonical_equal_shares(
  uuid,
  uuid,
  bigint
) owner to postgres;
alter function public.create_active_list_expense_v2(
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  bigint[],
  uuid,
  bigint
) owner to postgres;
alter function public.update_active_list_expense_v2(
  uuid,
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  bigint[],
  bigint,
  bigint
) owner to postgres;

revoke all on function private.active_list_expense_has_canonical_equal_shares(
  uuid,
  uuid,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.create_active_list_expense_v2(
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  bigint[],
  uuid,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.update_active_list_expense_v2(
  uuid,
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  bigint[],
  bigint,
  bigint
) from public, anon, authenticated, service_role;

grant execute on function public.create_active_list_expense_v2(
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  bigint[],
  uuid,
  bigint
) to authenticated;
grant execute on function public.update_active_list_expense_v2(
  uuid,
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  bigint[],
  bigint,
  bigint
) to authenticated;

comment on table public.active_list_expense_shares is
  'Explicit same-list integer expense allocations whose total equals their expense.';
comment on function private.active_list_expense_has_canonical_equal_shares(
  uuid,
  uuid,
  bigint
) is
  'Checks whether durable shares match the canonical UUID-ordered equal allocation.';
comment on function public.create_active_list_expense_v2(
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  bigint[],
  uuid,
  bigint
) is
  'Retry-safely creates an expense with server-derived equal or exact positive custom shares.';
comment on function public.update_active_list_expense_v2(
  uuid,
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  bigint[],
  bigint,
  bigint
) is
  'Version-checks an atomic equal or exact custom expense replacement with historical-role safety.';
comment on function public.create_active_list_expense(
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  uuid,
  bigint
) is
  'Legacy-compatible equal expense creation with complete durable allocation replay binding.';
comment on function public.update_active_list_expense(
  uuid,
  uuid,
  text,
  bigint,
  uuid,
  uuid[],
  bigint,
  bigint
) is
  'Legacy-compatible equal expense update that refuses to overwrite noncanonical custom shares.';

commit;
