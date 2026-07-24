begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function(
  'public',
  'create_active_list_expense_v2',
  array['uuid','text','bigint','uuid','uuid[]','bigint[]','uuid','bigint'],
  'versioned expense creation RPC exists'
);
select has_function(
  'public',
  'update_active_list_expense_v2',
  array['uuid','uuid','text','bigint','uuid','uuid[]','bigint[]','bigint','bigint'],
  'versioned expense update RPC exists'
);
select ok(
  (
    select pg_catalog.bool_and(
      function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
      and pg_catalog.obj_description(function_record.oid, 'pg_proc') is not null
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.create_active_list_expense_v2(uuid,text,bigint,uuid,uuid[],bigint[],uuid,bigint)'::regprocedure,
      'public.update_active_list_expense_v2(uuid,uuid,text,bigint,uuid,uuid[],bigint[],bigint,bigint)'::regprocedure
    )
  ),
  'v2 expense RPCs are commented postgres-owned hardened definer boundaries'
);
select ok(
  (
    select pg_catalog.bool_and(
      has_function_privilege('authenticated', function_record.oid, 'EXECUTE')
      and not has_function_privilege('anon', function_record.oid, 'EXECUTE')
      and not has_function_privilege('service_role', function_record.oid, 'EXECUTE')
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.create_active_list_expense_v2(uuid,text,bigint,uuid,uuid[],bigint[],uuid,bigint)'::regprocedure,
      'public.update_active_list_expense_v2(uuid,uuid,text,bigint,uuid,uuid[],bigint[],bigint,bigint)'::regprocedure
    )
  ),
  'only authenticated receives the exact v2 expense RPC grants'
);
select ok(
  (
    select
      function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
      and pg_catalog.obj_description(function_record.oid, 'pg_proc') is not null
      and not has_function_privilege(
        'anon',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'authenticated',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'service_role',
        function_record.oid,
        'EXECUTE'
      )
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'private.active_list_expense_has_canonical_equal_shares(uuid,uuid,bigint)'::regprocedure
  ),
  'private canonical-equal helper is a commented owner-only hardened boundary'
);
select columns_are(
  'public',
  'active_list_expenses',
  array[
    'id',
    'list_id',
    'description',
    'amount_minor',
    'payer_participant_id',
    'creator_participant_id',
    'last_editor_participant_id',
    'version',
    'creation_request_id',
    'created_at',
    'updated_at'
  ],
  'custom allocation adds no expense column or persisted mode'
);
select columns_are(
  'public',
  'active_list_expense_shares',
  array['list_id','expense_id','participant_id','amount_minor'],
  'explicit share rows remain the complete durable allocation'
);

set local role anon;
select throws_like(
  $$select public.create_active_list_expense_v2(
    gen_random_uuid(),
    'Denied',
    1,
    gen_random_uuid(),
    array[gen_random_uuid()],
    array[1::bigint],
    gen_random_uuid(),
    1
  )$$,
  '%permission denied%function%',
  'anonymous callers cannot execute custom expense creation'
);
reset role;

set local role authenticated;
select throws_ok(
  $$select public.create_active_list_expense_v2(
    gen_random_uuid(),
    'No session',
    1,
    gen_random_uuid(),
    array[gen_random_uuid()],
    array[1::bigint],
    gen_random_uuid(),
    1
  )$$,
  '42501',
  'verified profile required',
  'authenticated database role without a verified user session is rejected'
);
reset role;

insert into auth.users(id, email, email_confirmed_at, created_at, updated_at) values
  (
    '91000000-0000-4000-8000-000000000001',
    'custom-owner@example.test',
    now(),
    now(),
    now()
  ),
  (
    '91000000-0000-4000-8000-000000000002',
    'custom-member@example.test',
    now(),
    now(),
    now()
  ),
  (
    '91000000-0000-4000-8000-000000000003',
    'custom-history@example.test',
    now(),
    now(),
    now()
  ),
  (
    '91000000-0000-4000-8000-000000000004',
    'custom-stranger@example.test',
    now(),
    now(),
    now()
  );

update public.profiles
set username = case id
      when '91000000-0000-4000-8000-000000000001'
        then 'custom_owner'
      when '91000000-0000-4000-8000-000000000002'
        then 'custom_member'
      when '91000000-0000-4000-8000-000000000003'
        then 'custom_history'
      else 'custom_stranger'
    end,
    display_name = case id
      when '91000000-0000-4000-8000-000000000001'
        then 'Custom Owner'
      when '91000000-0000-4000-8000-000000000002'
        then 'Custom Member'
      when '91000000-0000-4000-8000-000000000003'
        then 'Custom History'
      else 'Custom Stranger'
    end
where id::text like '91000000-0000-4000-8000-00000000000_';

insert into public.active_lists(id, owner_id, title, creation_request_id) values
  (
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000001',
    'Custom shares',
    '92000000-0000-4000-8000-000000000011'
  ),
  (
    '92000000-0000-4000-8000-000000000002',
    '91000000-0000-4000-8000-000000000004',
    'Other ledger',
    '92000000-0000-4000-8000-000000000012'
  ),
  (
    '92000000-0000-4000-8000-000000000003',
    '91000000-0000-4000-8000-000000000001',
    'Block ledger',
    '92000000-0000-4000-8000-000000000013'
  ),
  (
    '92000000-0000-4000-8000-000000000004',
    '91000000-0000-4000-8000-000000000001',
    'Wide historical ledger',
    '92000000-0000-4000-8000-000000000014'
  );

insert into public.active_list_participants(
  list_id,
  participant_profile_id,
  state
) values
  (
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000002',
    'member'
  ),
  (
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000003',
    'member'
  ),
  (
    '92000000-0000-4000-8000-000000000003',
    '91000000-0000-4000-8000-000000000002',
    'member'
  );

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.enable_active_list_split(
    '92000000-0000-4000-8000-000000000001',
    'CHF',
    1
  )$$,
  'owner enables the main CHF Split fixture'
);
select lives_ok(
  $$select public.enable_active_list_split(
    '92000000-0000-4000-8000-000000000003',
    'CHF',
    1
  )$$,
  'owner enables the block-separation fixture'
);
select lives_ok(
  $$select public.enable_active_list_split(
    '92000000-0000-4000-8000-000000000004',
    'CHF',
    1
  )$$,
  'owner enables the retained wide-history fixture'
);
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000004';
select lives_ok(
  $$select public.enable_active_list_split(
    '92000000-0000-4000-8000-000000000002',
    'EUR',
    1
  )$$,
  'other owner enables the cross-list and integer-boundary fixture'
);
reset role;

create temporary table custom_share_test_values(
  label text primary key,
  value_id uuid,
  version bigint,
  message_count bigint
) on commit drop;
grant select, insert, update on custom_share_test_values to authenticated;

create function pg_temp.custom_share_split_version(target_list_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select settings_record.version
  from public.active_list_split_settings as settings_record
  where settings_record.list_id = target_list_id;
$$;
create function pg_temp.custom_share_expense_version(target_expense_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select expense_record.version
  from public.active_list_expenses as expense_record
  where expense_record.id = target_expense_id;
$$;
create function pg_temp.custom_share_participant_ids(target_list_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.array_agg(
    split_participant.id
    order by split_participant.id
  )
  from public.active_list_split_participants as split_participant
  where split_participant.list_id = target_list_id;
$$;
grant execute on function
  pg_temp.custom_share_split_version(uuid),
  pg_temp.custom_share_expense_version(uuid),
  pg_temp.custom_share_participant_ids(uuid)
to authenticated;

insert into custom_share_test_values(label, value_id)
select
  case split_participant.profile_id
    when '91000000-0000-4000-8000-000000000001'
      then 'owner-participant'
    when '91000000-0000-4000-8000-000000000002'
      then 'member-participant'
    else 'history-participant'
  end,
  split_participant.id
from public.active_list_split_participants as split_participant
where split_participant.list_id = '92000000-0000-4000-8000-000000000001';

insert into custom_share_test_values(label, value_id)
select 'other-participant', split_participant.id
from public.active_list_split_participants as split_participant
where split_participant.list_id = '92000000-0000-4000-8000-000000000002';

insert into custom_share_test_values(label, value_id)
select 'block-member-participant', split_participant.id
from public.active_list_split_participants as split_participant
where split_participant.list_id = '92000000-0000-4000-8000-000000000003'
  and split_participant.profile_id =
    '91000000-0000-4000-8000-000000000002';

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000004';
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Unrelated',
    1,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[(select value_id from custom_share_test_values
      where label = 'owner-participant')],
    array[1::bigint],
    '93000000-0000-4000-8000-000000000090',
    1
  )$$,
  'P0002',
  'list unavailable',
  'unrelated caller cannot create a custom expense'
);
reset role;

delete from realtime.messages;

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select ok(
  public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    '  Custom dinner  ',
    3000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'member-participant'),
      (select value_id from custom_share_test_values
        where label = 'history-participant'),
      (select value_id from custom_share_test_values
        where label = 'owner-participant')
    ],
    array[1000::bigint, 500::bigint, 1500::bigint],
    '93000000-0000-4000-8000-000000000001',
    1
  ) @> '{"settings":{"version":2}}'::jsonb,
  'owner creates CHF 30.00 with exact CHF 15/10/5 custom shares'
);
reset role;

insert into custom_share_test_values(label, value_id, version)
select 'custom-expense', expense_record.id, expense_record.version
from public.active_list_expenses as expense_record
where expense_record.list_id = '92000000-0000-4000-8000-000000000001'
  and expense_record.creation_request_id =
    '93000000-0000-4000-8000-000000000001';

select ok(
  (
    select
      pg_catalog.count(*) = 3
      and pg_catalog.sum(share_record.amount_minor) = 3000
      and pg_catalog.bool_and(
        share_record.amount_minor = case split_participant.profile_id
          when '91000000-0000-4000-8000-000000000001' then 1500
          when '91000000-0000-4000-8000-000000000002' then 1000
          else 500
        end
      )
    from public.active_list_expense_shares as share_record
    join public.active_list_split_participants as split_participant
      on split_participant.list_id = share_record.list_id
     and split_participant.id = share_record.participant_id
    where share_record.expense_id = (
      select value_id
      from custom_share_test_values
      where label = 'custom-expense'
    )
  ),
  'custom share rows preserve the submitted participant-to-amount pairs'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select ok(
  (
    select
      pg_catalog.bool_and(
        (participant.document ->> 'balance_minor')::bigint =
          case participant.document ->> 'profile_id'
            when '91000000-0000-4000-8000-000000000001' then 1500
            when '91000000-0000-4000-8000-000000000002' then -1000
            else -500
          end
      )
    from pg_catalog.jsonb_array_elements(
      public.get_active_list_split(
        '92000000-0000-4000-8000-000000000001'
      ) -> 'participants'
    ) as participant(document)
  ),
  'custom shares drive exact owner +1500, member -1000, history -500 balances'
);
select ok(
  (
    select
      pg_catalog.count(*) = 2
      and pg_catalog.sum(
        (suggestion.document ->> 'amount_minor')::bigint
      ) = 1500
      and pg_catalog.bool_and(
        suggestion.document ->> 'recipient_participant_id' = (
          select value_id::text
          from custom_share_test_values
          where label = 'owner-participant'
        )
      )
    from pg_catalog.jsonb_array_elements(
      public.get_active_list_split(
        '92000000-0000-4000-8000-000000000001'
      ) -> 'suggestions'
    ) as suggestion(document)
  ),
  'custom balances feed the existing deterministic settlement suggestions'
);

select is(
  (
    public.create_active_list_expense_v2(
      '92000000-0000-4000-8000-000000000001',
      'Custom dinner',
      3000,
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      array[
        (select value_id from custom_share_test_values
          where label = 'owner-participant'),
        (select value_id from custom_share_test_values
          where label = 'history-participant'),
        (select value_id from custom_share_test_values
          where label = 'member-participant')
      ],
      array[1500::bigint, 500::bigint, 1000::bigint],
      '93000000-0000-4000-8000-000000000001',
      1
    ) #>> '{settings,version}'
  )::bigint,
  2::bigint,
  'same creation request and normalized logical pairs replay safely'
);
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Custom dinner',
    3000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'history-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    array[1499::bigint, 500::bigint, 1001::bigint],
    '93000000-0000-4000-8000-000000000001',
    2
  )$$,
  '23505',
  'expense creation request conflict',
  'creation request reuse with a different normalized allocation conflicts'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '92000000-0000-4000-8000-000000000001',
    'Custom dinner',
    3000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'history-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    '93000000-0000-4000-8000-000000000001',
    2
  )$$,
  '23505',
  'expense creation request conflict',
  'legacy creation replay cannot falsely match a noncanonical custom allocation'
);
select lives_ok(
  $$select public.record_active_list_settlement(
    '92000000-0000-4000-8000-000000000001',
    (select value_id from custom_share_test_values
      where label = 'member-participant'),
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    500,
    'Partial custom balance settlement',
    '93000000-0000-4000-8000-000000000009',
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    )
  )$$,
  'existing settlement recording accepts balances derived from custom shares'
);
select ok(
  public.list_active_list_settlements(
    '92000000-0000-4000-8000-000000000001',
    20,
    null,
    null
  ) @> pg_catalog.jsonb_build_object(
    'entries',
    pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'payer_participant_id',
          (select value_id from custom_share_test_values
            where label = 'member-participant'),
        'recipient_participant_id',
          (select value_id from custom_share_test_values
            where label = 'owner-participant'),
        'amount_minor',
          500
      )
    )
  ),
  'custom-share settlement remains understandable in paginated history'
);
reset role;

insert into custom_share_test_values(label, version, message_count) values (
  'rejected-create-state',
  (
    select settings_record.version
    from public.active_list_split_settings as settings_record
    where settings_record.list_id = '92000000-0000-4000-8000-000000000001'
  ),
  (select pg_catalog.count(*) from realtime.messages)
);

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Underallocated',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    array[500::bigint, 499::bigint],
    '93000000-0000-4000-8000-000000000010',
    (select version from custom_share_test_values
      where label = 'rejected-create-state')
  )$$,
  '22023',
  'invalid expense creation',
  'underallocated custom creation is rejected'
);
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Overallocated',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    array[500::bigint, 501::bigint],
    '93000000-0000-4000-8000-000000000011',
    (select version from custom_share_test_values
      where label = 'rejected-create-state')
  )$$,
  '22023',
  'invalid expense creation',
  'overallocated custom creation is rejected'
);
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Zero share',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    array[1000::bigint, 0::bigint],
    '93000000-0000-4000-8000-000000000012',
    (select version from custom_share_test_values
      where label = 'rejected-create-state')
  )$$,
  '22023',
  'invalid expense creation',
  'custom RPC requires positive submitted shares so zero is omitted by the client'
);
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Mismatched arrays',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    array[1000::bigint],
    '93000000-0000-4000-8000-000000000013',
    (select version from custom_share_test_values
      where label = 'rejected-create-state')
  )$$,
  '22023',
  'invalid expense creation',
  'custom participant and amount cardinalities must match'
);
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Duplicate beneficiary',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'member-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    array[500::bigint, 500::bigint],
    '93000000-0000-4000-8000-000000000014',
    (select version from custom_share_test_values
      where label = 'rejected-create-state')
  )$$,
  '22023',
  'invalid expense creation',
  'duplicate custom beneficiaries are rejected'
);
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Cross-list beneficiary',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[(select value_id from custom_share_test_values
      where label = 'other-participant')],
    array[1000::bigint],
    '93000000-0000-4000-8000-000000000015',
    (select version from custom_share_test_values
      where label = 'rejected-create-state')
  )$$,
  '22023',
  'expense participant unavailable',
  'cross-list custom beneficiary is rejected'
);
reset role;

select ok(
  (
    select settings_record.version
    from public.active_list_split_settings as settings_record
    where settings_record.list_id = '92000000-0000-4000-8000-000000000001'
  ) = (
    select version
    from custom_share_test_values
    where label = 'rejected-create-state'
  )
  and not exists (
    select 1
    from public.active_list_expenses as expense_record
    where expense_record.creation_request_id in (
      '93000000-0000-4000-8000-000000000010',
      '93000000-0000-4000-8000-000000000011',
      '93000000-0000-4000-8000-000000000012',
      '93000000-0000-4000-8000-000000000013',
      '93000000-0000-4000-8000-000000000014',
      '93000000-0000-4000-8000-000000000015'
    )
  )
  and (select pg_catalog.count(*) from realtime.messages) = (
    select message_count
    from custom_share_test_values
    where label = 'rejected-create-state'
  ),
  'rejected custom creates add no row, version increment, or invalidation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000002';
select lives_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Member custom expense',
    1000,
    (select value_id from custom_share_test_values
      where label = 'member-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    array[400::bigint, 600::bigint],
    '93000000-0000-4000-8000-000000000016',
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    )
  )$$,
  'current accepted member may create an exact custom expense'
);
reset role;
select is(
  (
    select expense_record.creator_participant_id
    from public.active_list_expenses as expense_record
    where expense_record.creation_request_id =
      '93000000-0000-4000-8000-000000000016'
  ),
  (
    select value_id
    from custom_share_test_values
    where label = 'member-participant'
  ),
  'custom expense preserves member recorder attribution'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.update_active_list_expense(
    '92000000-0000-4000-8000-000000000001',
    (select value_id from custom_share_test_values
      where label = 'custom-expense'),
    'Custom dinner',
    3000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant'),
      (select value_id from custom_share_test_values
        where label = 'history-participant')
    ],
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    ),
    1
  )$$,
  '55000',
  'custom expense requires updated client',
  'legacy update refuses a noncanonical custom expense before its no-op path'
);
select is(
  (
    public.update_active_list_expense_v2(
      '92000000-0000-4000-8000-000000000001',
      (select value_id from custom_share_test_values
        where label = 'custom-expense'),
      'Custom dinner',
      3000,
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      array[
        (select value_id from custom_share_test_values
          where label = 'history-participant'),
        (select value_id from custom_share_test_values
          where label = 'owner-participant'),
        (select value_id from custom_share_test_values
          where label = 'member-participant')
      ],
      array[500::bigint, 1500::bigint, 1000::bigint],
      pg_temp.custom_share_split_version(
        '92000000-0000-4000-8000-000000000001'
      ),
      1
    ) #>> '{settings,version}'
  )::bigint,
  pg_temp.custom_share_split_version(
    '92000000-0000-4000-8000-000000000001'
  ),
  'v2 update with the identical normalized custom payload is a no-op retry'
);
reset role;

insert into custom_share_test_values(label, version, message_count) values (
  'before-custom-update',
  (
    select settings_record.version
    from public.active_list_split_settings as settings_record
    where settings_record.list_id = '92000000-0000-4000-8000-000000000001'
  ),
  (select pg_catalog.count(*) from realtime.messages)
);
update custom_share_test_values
set value_id = (
  select expense_record.id
  from public.active_list_expenses as expense_record
  where expense_record.creation_request_id =
    '93000000-0000-4000-8000-000000000001'
)
where label = 'before-custom-update';

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select is(
  (
    public.update_active_list_expense_v2(
      '92000000-0000-4000-8000-000000000001',
      (select value_id from custom_share_test_values
        where label = 'before-custom-update'),
      'Custom dinner adjusted',
      3000,
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      array[
        (select value_id from custom_share_test_values
          where label = 'owner-participant'),
        (select value_id from custom_share_test_values
          where label = 'member-participant'),
        (select value_id from custom_share_test_values
          where label = 'history-participant')
      ],
      array[1400::bigint, 1100::bigint, 500::bigint],
      (select version from custom_share_test_values
        where label = 'before-custom-update'),
      1
    ) #>> '{settings,version}'
  )::bigint,
  (
    select version + 1
    from custom_share_test_values
    where label = 'before-custom-update'
  ),
  'custom update atomically replaces exact shares and advances both versions'
);
select is(
  (
    public.update_active_list_expense_v2(
      '92000000-0000-4000-8000-000000000001',
      (select value_id from custom_share_test_values
        where label = 'before-custom-update'),
      'Custom dinner adjusted',
      3000,
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      array[
        (select value_id from custom_share_test_values
          where label = 'history-participant'),
        (select value_id from custom_share_test_values
          where label = 'member-participant'),
        (select value_id from custom_share_test_values
          where label = 'owner-participant')
      ],
      array[500::bigint, 1100::bigint, 1400::bigint],
      (select version from custom_share_test_values
        where label = 'before-custom-update'),
      1
    ) #>> '{settings,version}'
  )::bigint,
  (
    select version + 1
    from custom_share_test_values
    where label = 'before-custom-update'
  ),
  'lost-response update retry matches full normalized pairs at prior versions'
);
select throws_ok(
  $$select public.update_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    (select value_id from custom_share_test_values
      where label = 'before-custom-update'),
    'Concurrent loser',
    3000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant'),
      (select value_id from custom_share_test_values
        where label = 'history-participant')
    ],
    array[1300::bigint, 1200::bigint, 500::bigint],
    (select version from custom_share_test_values
      where label = 'before-custom-update'),
    1
  )$$,
  '40001',
  'expense changed',
  'serialized concurrent custom update with stale versions loses safely'
);
reset role;

select ok(
  (
    select expense_record.description = 'Custom dinner adjusted'
      and expense_record.version = 2
    from public.active_list_expenses as expense_record
    where expense_record.id = (
      select value_id
      from custom_share_test_values
      where label = 'before-custom-update'
    )
  )
  and (select pg_catalog.count(*) from realtime.messages) = (
    select message_count + 3
    from custom_share_test_values
    where label = 'before-custom-update'
  ),
  'one successful update emits one bounded invalidation per current account; retries and stale failures emit none'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Payer excluded',
    2000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'member-participant'),
      (select value_id from custom_share_test_values
        where label = 'history-participant')
    ],
    array[1000::bigint, 1000::bigint],
    '93000000-0000-4000-8000-000000000002',
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    )
  )$$,
  'payer exclusion remains valid for exact custom shares'
);
select lives_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Canonical custom',
    3001,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    pg_temp.custom_share_participant_ids(
      '92000000-0000-4000-8000-000000000001'
    ),
    array[1001::bigint, 1000::bigint, 1000::bigint],
    '93000000-0000-4000-8000-000000000003',
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    )
  )$$,
  'custom values identical to canonical UUID-ordered Equal are accepted'
);
select lives_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Canonical custom',
    3001,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    pg_temp.custom_share_participant_ids(
      '92000000-0000-4000-8000-000000000001'
    ),
    null,
    '93000000-0000-4000-8000-000000000003',
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    ) - 1
  )$$,
  'canonical custom creation replays as Equal because no mode is persisted'
);
select lives_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Historical exclusion fixture',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    array[600::bigint, 400::bigint],
    '93000000-0000-4000-8000-000000000004',
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    )
  )$$,
  'fixture omits the participant who will become historical'
);
reset role;

insert into custom_share_test_values(label, value_id, version)
select
  'historical-exclusion-expense',
  expense_record.id,
  expense_record.version
from public.active_list_expenses as expense_record
where expense_record.creation_request_id =
  '93000000-0000-4000-8000-000000000004';

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.update_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    (select value_id from custom_share_test_values
      where label = 'historical-exclusion-expense'),
    'Historical exclusion equal',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    null,
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    ),
    1
  )$$,
  'Custom to Equal update asks the server to recompute canonical shares'
);
reset role;

select ok(
  private.active_list_expense_has_canonical_equal_shares(
    '92000000-0000-4000-8000-000000000001',
    (select value_id from custom_share_test_values
      where label = 'historical-exclusion-expense'),
    1000
  )
  and (
    select pg_catalog.min(share_record.amount_minor) = 500
      and pg_catalog.max(share_record.amount_minor) = 500
    from public.active_list_expense_shares as share_record
    where share_record.expense_id = (
      select value_id
      from custom_share_test_values
      where label = 'historical-exclusion-expense'
    )
  ),
  'server-derived Equal conversion stores the canonical UUID-ordered allocation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.update_active_list_expense(
    '92000000-0000-4000-8000-000000000001',
    (select value_id from custom_share_test_values
      where label = 'historical-exclusion-expense'),
    'Historical exclusion equal',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant')
    ],
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    ),
    2
  )$$,
  'legacy clients continue replaying canonical equal expenses'
);
reset role;

update public.active_list_participants
set state = 'removed',
    version = version + 1,
    state_changed_at = pg_catalog.clock_timestamp()
where list_id = '92000000-0000-4000-8000-000000000001'
  and participant_profile_id =
    '91000000-0000-4000-8000-000000000003';

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.update_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    (select value_id from custom_share_test_values
      where label = 'custom-expense'),
    'Historical amount adjusted',
    3000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant'),
      (select value_id from custom_share_test_values
        where label = 'history-participant')
    ],
    array[1300::bigint, 1100::bigint, 600::bigint],
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    ),
    2
  )$$,
  'already-attached historical beneficiary may remain and be adjusted'
);
select throws_ok(
  $$select public.update_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    (select value_id from custom_share_test_values
      where label = 'historical-exclusion-expense'),
    'Illicit historical addition',
    1000,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant'),
      (select value_id from custom_share_test_values
        where label = 'history-participant')
    ],
    array[400::bigint, 300::bigint, 300::bigint],
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    ),
    2
  )$$,
  '22023',
  'expense participant unavailable',
  'historical beneficiary not previously attached cannot be added'
);
select throws_ok(
  $$select public.update_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    (select value_id from custom_share_test_values
      where label = 'custom-expense'),
    'Illicit historical payer',
    3000,
    (select value_id from custom_share_test_values
      where label = 'history-participant'),
    array[
      (select value_id from custom_share_test_values
        where label = 'owner-participant'),
      (select value_id from custom_share_test_values
        where label = 'member-participant'),
      (select value_id from custom_share_test_values
        where label = 'history-participant')
    ],
    array[1300::bigint, 1100::bigint, 600::bigint],
    pg_temp.custom_share_split_version(
      '92000000-0000-4000-8000-000000000001'
    ),
    3
  )$$,
  '22023',
  'expense participant unavailable',
  'attached historical beneficiary cannot switch into a new payer role'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000004';
select lives_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000002',
    'Bigint boundary',
    999999999,
    (select value_id from custom_share_test_values
      where label = 'other-participant'),
    array[(select value_id from custom_share_test_values
      where label = 'other-participant')],
    array[999999999::bigint],
    '93000000-0000-4000-8000-000000000020',
    1
  )$$,
  'maximum accepted amount remains exact in integer minor units'
);
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000002',
    'Beyond boundary',
    1000000000,
    (select value_id from custom_share_test_values
      where label = 'other-participant'),
    array[(select value_id from custom_share_test_values
      where label = 'other-participant')],
    array[1000000000::bigint],
    '93000000-0000-4000-8000-000000000021',
    2
  )$$,
  '22023',
  'invalid expense creation',
  'amount above the reviewed bigint product bound is rejected'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select ok(
  public.export_own_account_data() ->> 'schema_version' = '6'
  and (
    select pg_catalog.count(*) = 1
    from pg_catalog.jsonb_array_elements(
      public.export_own_account_data() -> 'active_lists'
    ) as exported_list(document)
    cross join lateral pg_catalog.jsonb_array_elements(
      exported_list.document #> '{split,expenses}'
    ) as exported_expense(document)
    where exported_list.document ->> 'id' =
      '92000000-0000-4000-8000-000000000001'
      and exported_expense.document ->> 'id' = (
        select value_id::text
        from custom_share_test_values
        where label = 'custom-expense'
      )
      and pg_catalog.jsonb_array_length(
        exported_expense.document -> 'shares'
      ) = 3
      and (
        select pg_catalog.sum(
          (exported_share.document ->> 'amount_minor')::bigint
        )
        from pg_catalog.jsonb_array_elements(
          exported_expense.document -> 'shares'
        ) as exported_share(document)
      ) = 3000
  ),
  'owner export v6 emits one custom expense with its exact shares once'
);
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000002';
select ok(
  not (
    public.export_own_account_data() -> 'active_lists'
    @> '[{"id":"92000000-0000-4000-8000-000000000001"}]'::jsonb
  ),
  'shared member export does not leak the owner custom expense or shares'
);
reset role;

update public.active_lists
set status = 'archived',
    archived_at = pg_catalog.clock_timestamp(),
    version = version + 1,
    updated_at = pg_catalog.clock_timestamp()
where id = '92000000-0000-4000-8000-000000000001';
insert into custom_share_test_values(label, version, message_count) values (
  'archive-failure-state',
  (
    select settings_record.version
    from public.active_list_split_settings as settings_record
    where settings_record.list_id = '92000000-0000-4000-8000-000000000001'
  ),
  (select pg_catalog.count(*) from realtime.messages)
);

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000001',
    'Archived',
    1,
    (select value_id from custom_share_test_values
      where label = 'owner-participant'),
    array[(select value_id from custom_share_test_values
      where label = 'owner-participant')],
    array[1::bigint],
    '93000000-0000-4000-8000-000000000030',
    (select version from custom_share_test_values
      where label = 'archive-failure-state')
  )$$,
  '55000',
  'archived list is read only',
  'archived list rejects custom expense creation'
);
reset role;

select ok(
  (
    select settings_record.version
    from public.active_list_split_settings as settings_record
    where settings_record.list_id = '92000000-0000-4000-8000-000000000001'
  ) = (
    select version
    from custom_share_test_values
    where label = 'archive-failure-state'
  )
  and not exists (
    select 1
    from public.active_list_expenses as expense_record
    where expense_record.creation_request_id =
      '93000000-0000-4000-8000-000000000030'
  )
  and (select pg_catalog.count(*) from realtime.messages) = (
    select message_count
    from custom_share_test_values
    where label = 'archive-failure-state'
  ),
  'archived rejection creates no data, Split version, or invalidation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.block_profile(
    '91000000-0000-4000-8000-000000000002'
  )$$,
  'owner blocks the member after all shared-main assertions'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.create_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000003',
    'Blocked',
    1,
    (select value_id from custom_share_test_values
      where label = 'block-member-participant'),
    array[(select value_id from custom_share_test_values
      where label = 'block-member-participant')],
    array[1::bigint],
    '93000000-0000-4000-8000-000000000031',
    1
  )$$,
  'P0002',
  'list unavailable',
  'block-aware membership separation prevents custom expense mutation'
);
reset role;

insert into public.active_list_split_participants(
  id,
  list_id,
  profile_id,
  username_snapshot,
  display_name_snapshot
)
select
  (
    '99000000-0000-4000-8000-'
      || pg_catalog.lpad(series.value::text, 12, '0')
  )::uuid,
  '92000000-0000-4000-8000-000000000004',
  null,
  null,
  null
from pg_catalog.generate_series(1, 22) as series(value);

insert into custom_share_test_values(label, value_id)
select
  'wide-history-' || pg_catalog.lpad(series.value::text, 2, '0'),
  (
    '99000000-0000-4000-8000-'
      || pg_catalog.lpad(series.value::text, 12, '0')
  )::uuid
from pg_catalog.generate_series(1, 22) as series(value);
insert into custom_share_test_values(label, value_id)
select 'wide-owner-participant', split_participant.id
from public.active_list_split_participants as split_participant
where split_participant.list_id = '92000000-0000-4000-8000-000000000004'
  and split_participant.profile_id =
    '91000000-0000-4000-8000-000000000001';

insert into public.active_list_expenses(
  id,
  list_id,
  description,
  amount_minor,
  payer_participant_id,
  creator_participant_id,
  last_editor_participant_id,
  creation_request_id
) values (
  '99000000-0000-4000-8000-999999999999',
  '92000000-0000-4000-8000-000000000004',
  'Wide retained history',
  2200,
  (select value_id from custom_share_test_values
    where label = 'wide-owner-participant'),
  (select value_id from custom_share_test_values
    where label = 'wide-owner-participant'),
  (select value_id from custom_share_test_values
    where label = 'wide-owner-participant'),
  '93000000-0000-4000-8000-000000000040'
);
insert into public.active_list_expense_shares(
  list_id,
  expense_id,
  participant_id,
  amount_minor
)
select
  '92000000-0000-4000-8000-000000000004',
  '99000000-0000-4000-8000-999999999999',
  test_value.value_id,
  100
from custom_share_test_values as test_value
where test_value.label like 'wide-history-%';
set constraints all immediate;
set constraints all deferred;

set local role authenticated;
set local "request.jwt.claim.sub" = '91000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.update_active_list_expense_v2(
    '92000000-0000-4000-8000-000000000004',
    '99000000-0000-4000-8000-999999999999',
    'Wide retained history adjusted',
    2200,
    (select value_id from custom_share_test_values
      where label = 'wide-owner-participant'),
    array(
      select test_value.value_id
      from custom_share_test_values as test_value
      where test_value.label like 'wide-history-%'
      order by test_value.value_id
    ),
    array(
      select case numbered.ordinality
        when 1 then 101::bigint
        when 22 then 99::bigint
        else 100::bigint
      end
      from (
        select
          test_value.value_id,
          pg_catalog.row_number() over (
            order by test_value.value_id
          ) as ordinality
        from custom_share_test_values as test_value
        where test_value.label like 'wide-history-%'
      ) as numbered
      order by numbered.value_id
    ),
    1,
    1
  )$$,
  'v2 update preserves and adjusts more than 20 attached historical beneficiaries'
);
reset role;

select ok(
  (
    select
      pg_catalog.count(*) = 22
      and pg_catalog.sum(share_record.amount_minor) = 2200
      and pg_catalog.min(share_record.amount_minor) = 99
      and pg_catalog.max(share_record.amount_minor) = 101
    from public.active_list_expense_shares as share_record
    where share_record.expense_id =
      '99000000-0000-4000-8000-999999999999'
  )
  and (
    select expense_record.version = 2
    from public.active_list_expenses as expense_record
    where expense_record.id =
      '99000000-0000-4000-8000-999999999999'
  ),
  'wide retained history remains exact and non-destructive after custom update'
);

select ok(
  not exists (
    select 1
    from realtime.messages as message_record
    where message_record.event <> 'invalidate'
      or message_record.payload - 'id' <> '{"v":1}'::jsonb
      or not message_record.private
  ),
  'custom expense mutations preserve the opaque private invalidation contract'
);

select * from finish();
rollback;
