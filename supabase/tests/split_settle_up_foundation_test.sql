begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table(
  'public',
  'active_list_settlements',
  'immutable settlement table exists'
);
select has_table(
  'public',
  'active_list_settlement_reversals',
  'append-only settlement reversal table exists'
);
select columns_are(
  'public',
  'active_list_settlements',
  array[
    'id',
    'list_id',
    'payer_participant_id',
    'recipient_participant_id',
    'recorded_by_participant_id',
    'amount_minor',
    'note',
    'creation_request_id',
    'created_at'
  ],
  'settlements contain only the reviewed immutable fields'
);
select columns_are(
  'public',
  'active_list_settlement_reversals',
  array[
    'list_id',
    'settlement_id',
    'reversed_by_participant_id',
    'reason',
    'reversal_request_id',
    'created_at'
  ],
  'reversals contain only the reviewed append-only correction fields'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as table_record
    where table_record.oid in (
      'public.active_list_settlements'::regclass,
      'public.active_list_settlement_reversals'::regclass
    )
      and table_record.relrowsecurity
      and table_record.relforcerowsecurity
  ),
  2::bigint,
  'both settlement tables enable and force RLS'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'active_list_settlements',
        'active_list_settlement_reversals'
      )
      and cmd = 'ALL'
      and roles = array['anon', 'authenticated']::name[]
      and qual = 'false'
      and with_check = 'false'
  ),
  2::bigint,
  'both settlement tables explicitly reject every direct client operation'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.active_list_settlements',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.active_list_settlements',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.active_list_settlements',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'anon',
    'public.active_list_settlement_reversals',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.active_list_settlement_reversals',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.active_list_settlement_reversals',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'no API role has direct settlement-table CRUD'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint
    where conrelid in (
      'public.active_list_settlements'::regclass,
      'public.active_list_settlement_reversals'::regclass
    )
      and conname in (
        'active_list_settlements_payer_fkey',
        'active_list_settlements_recipient_fkey',
        'active_list_settlements_recorder_fkey',
        'active_list_settlement_reversals_settlement_fkey',
        'active_list_settlement_reversals_actor_fkey'
      )
      and condeferrable
      and condeferred
  ),
  5::bigint,
  'all settlement same-list foreign keys are initially deferred'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'active_list_settlements_history_idx'
      and indexdef like '%(list_id, created_at DESC, id DESC)%'
  )
  and exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'active_list_settlements_payer_idx'
  )
  and exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'active_list_settlements_recipient_idx'
  )
  and exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'active_list_settlements_recorder_idx'
  )
  and exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and indexname = 'active_list_settlement_reversals_actor_idx'
  ),
  'history and every participant foreign-key path have supporting indexes'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc
    where proname in (
      'list_active_list_settlements',
      'record_active_list_settlement',
      'reverse_active_list_settlement'
    )
      and pronamespace = 'public'::regnamespace
  ),
  3::bigint,
  'the settlement API exposes exactly one signature for each reviewed RPC'
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
      'public.list_active_list_settlements(uuid,integer,timestamptz,uuid)'::regprocedure,
      'public.record_active_list_settlement(uuid,uuid,uuid,bigint,text,uuid,bigint)'::regprocedure,
      'public.reverse_active_list_settlement(uuid,uuid,text,uuid,bigint)'::regprocedure
    )
  ),
  'public settlement RPCs are commented postgres-owned hardened definer boundaries'
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
      'public.list_active_list_settlements(uuid,integer,timestamptz,uuid)'::regprocedure,
      'public.record_active_list_settlement(uuid,uuid,uuid,bigint,text,uuid,bigint)'::regprocedure,
      'public.reverse_active_list_settlement(uuid,uuid,text,uuid,bigint)'::regprocedure
    )
  ),
  'only authenticated receives each exact settlement RPC grant'
);

set local role anon;
select throws_like(
  $$select * from public.active_list_settlements$$,
  '%permission denied%',
  'anonymous direct settlement SELECT is denied'
);
select throws_like(
  $$select public.list_active_list_settlements(gen_random_uuid(), 20, null, null)$$,
  '%permission denied%function%',
  'anonymous settlement history RPC is denied'
);
reset role;
set local role authenticated;
select throws_like(
  $$insert into public.active_list_settlements(
      list_id,payer_participant_id,recipient_participant_id,
      recorded_by_participant_id,amount_minor,creation_request_id
    ) values(
      gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),
      gen_random_uuid(),1,gen_random_uuid()
    )$$,
  '%permission denied%',
  'authenticated direct settlement INSERT is denied'
);
select throws_like(
  $$delete from public.active_list_settlement_reversals$$,
  '%permission denied%',
  'authenticated direct reversal DELETE is denied'
);
reset role;

insert into auth.users(id, email, email_confirmed_at, created_at, updated_at) values
  (
    '81000000-0000-4000-8000-000000000001',
    'settle-owner@example.test',
    now(),
    now(),
    now()
  ),
  (
    '81000000-0000-4000-8000-000000000002',
    'settle-member@example.test',
    now(),
    now(),
    now()
  ),
  (
    '81000000-0000-4000-8000-000000000003',
    'settle-history@example.test',
    now(),
    now(),
    now()
  ),
  (
    '81000000-0000-4000-8000-000000000004',
    'settle-stranger@example.test',
    now(),
    now(),
    now()
  );
update public.profiles
set username = case id
      when '81000000-0000-4000-8000-000000000001' then 'settle_owner'
      when '81000000-0000-4000-8000-000000000002' then 'settle_member'
      when '81000000-0000-4000-8000-000000000003' then 'settle_history'
      else 'settle_stranger'
    end,
    display_name = case id
      when '81000000-0000-4000-8000-000000000001' then 'Settle Owner'
      when '81000000-0000-4000-8000-000000000002' then 'Settle Member'
      when '81000000-0000-4000-8000-000000000003' then 'Settle History'
      else 'Settle Stranger'
    end
where id::text like '81000000-0000-4000-8000-00000000000_';

insert into public.active_lists(id, owner_id, title, creation_request_id) values
  (
    '82000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    'Settle ledger',
    '82000000-0000-4000-8000-000000000011'
  ),
  (
    '82000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000001',
    'Disabled Split',
    '82000000-0000-4000-8000-000000000012'
  ),
  (
    '82000000-0000-4000-8000-000000000003',
    '81000000-0000-4000-8000-000000000001',
    'Suggestion example',
    '82000000-0000-4000-8000-000000000013'
  );
insert into public.active_list_participants(
  list_id,
  participant_profile_id,
  state
) values
  (
    '82000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000002',
    'member'
  ),
  (
    '82000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000003',
    'member'
  ),
  (
    '82000000-0000-4000-8000-000000000003',
    '81000000-0000-4000-8000-000000000002',
    'member'
  ),
  (
    '82000000-0000-4000-8000-000000000003',
    '81000000-0000-4000-8000-000000000003',
    'member'
  ),
  (
    '82000000-0000-4000-8000-000000000003',
    '81000000-0000-4000-8000-000000000004',
    'member'
  );

create temporary table settle_test_values (
  label text primary key,
  value_id uuid,
  version bigint
) on commit drop;
grant select, insert, update on settle_test_values to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select is(
  public.list_active_list_settlements(
    '82000000-0000-4000-8000-000000000002',
    20,
    null,
    null
  ),
  pg_catalog.jsonb_build_object(
    'list_id',
    '82000000-0000-4000-8000-000000000002'::uuid,
    'currency_code',
    null,
    'entries',
    '[]'::jsonb,
    'next_cursor',
    null
  ),
  'authorized disabled Split returns an empty history page with null currency'
);
select throws_ok(
  $$select public.list_active_list_settlements(
    '82000000-0000-4000-8000-000000000002', 0, null, null
  )$$,
  '22023',
  'invalid settlement page',
  'history page size is bounded below'
);
select throws_ok(
  $$select public.list_active_list_settlements(
    '82000000-0000-4000-8000-000000000002', 51, null, null
  )$$,
  '22023',
  'invalid settlement page',
  'history page size is bounded above'
);
select throws_ok(
  $$select public.list_active_list_settlements(
    '82000000-0000-4000-8000-000000000002', 20, now(), null
  )$$,
  '22023',
  'invalid settlement page',
  'partial history cursor is rejected'
);
select ok(
  public.enable_active_list_split(
    '82000000-0000-4000-8000-000000000001',
    'CHF',
    1
  ) @> '{"settings":{"currency_code":"CHF","version":1},"suggestions":[]}'::jsonb,
  'owner enables CHF Split with no initial settlement suggestions'
);
reset role;

insert into settle_test_values(label, value_id)
select case split_participant.profile_id
    when '81000000-0000-4000-8000-000000000001'
      then 'owner-participant'
    when '81000000-0000-4000-8000-000000000002'
      then 'member-participant'
    else 'history-participant'
  end,
  split_participant.id
from public.active_list_split_participants as split_participant
where split_participant.list_id = '82000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000004';
select throws_ok(
  $$select public.list_active_list_settlements(
    '82000000-0000-4000-8000-000000000001', 20, null, null
  )$$,
  'P0002',
  'list unavailable',
  'unrelated caller cannot read settlement history'
);
select throws_ok(
  $$select public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='member-participant'),
    (select value_id from settle_test_values where label='owner-participant'),
    1,null,'83000000-0000-4000-8000-000000000099',1
  )$$,
  'P0002',
  'list unavailable',
  'unrelated caller cannot record a settlement'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select ok(
  public.create_active_list_expense(
    '82000000-0000-4000-8000-000000000001',
    'Shared lodging',
    6000,
    (select value_id from settle_test_values where label='owner-participant'),
    array[
      (select value_id from settle_test_values where label='member-participant'),
      (select value_id from settle_test_values where label='history-participant')
    ],
    '83000000-0000-4000-8000-000000000001',
    1
  ) @> '{"settings":{"version":2}}'::jsonb,
  'expense establishes one creditor and two equal debtors'
);
select ok(
  (
    select
      pg_catalog.jsonb_array_length(projection -> 'suggestions') = 2
      and (projection #>> '{suggestions,0,amount_minor}')::bigint = 3000
      and (projection #>> '{suggestions,1,amount_minor}')::bigint = 3000
      and (projection #>> '{suggestions,0,recipient_participant_id}')::uuid =
        (select value_id from settle_test_values where label='owner-participant')
      and (projection #>> '{suggestions,1,recipient_participant_id}')::uuid =
        (select value_id from settle_test_values where label='owner-participant')
      and (projection #>> '{suggestions,0,payer_participant_id}')::uuid <
        (projection #>> '{suggestions,1,payer_participant_id}')::uuid
    from (
      select public.get_active_list_split(
        '82000000-0000-4000-8000-000000000001'
      ) as projection
    ) as current_split
  ),
  'suggestions deterministically order equal debtors by immutable participant UUID'
);
reset role;

delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.enable_active_list_split(
    '82000000-0000-4000-8000-000000000003','EUR',1
  )$$,
  'owner enables the independent multi-creditor suggestion fixture'
);
reset role;
insert into settle_test_values(label, value_id)
select case split_participant.profile_id
    when '81000000-0000-4000-8000-000000000001'
      then 'algorithm-owner'
    when '81000000-0000-4000-8000-000000000002'
      then 'algorithm-member'
    when '81000000-0000-4000-8000-000000000003'
      then 'algorithm-history'
    else 'algorithm-stranger'
  end,
  split_participant.id
from public.active_list_split_participants as split_participant
where split_participant.list_id = '82000000-0000-4000-8000-000000000003';
set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.create_active_list_expense(
    '82000000-0000-4000-8000-000000000003','Owner creditor',6000,
    (select value_id from settle_test_values where label='algorithm-owner'),
    array[(select value_id from settle_test_values where label='algorithm-history')],
    '84000000-0000-4000-8000-000000000001',1
  )$$,
  'multi-creditor fixture gives the owner a EUR 60.00 credit'
);
select lives_ok(
  $$select public.create_active_list_expense(
    '82000000-0000-4000-8000-000000000003','Member credit one',1000,
    (select value_id from settle_test_values where label='algorithm-member'),
    array[(select value_id from settle_test_values where label='algorithm-history')],
    '84000000-0000-4000-8000-000000000002',2
  )$$,
  'multi-creditor fixture adds EUR 10.00 to the larger debtor'
);
select ok(
  (
    public.create_active_list_expense(
      '82000000-0000-4000-8000-000000000003',
      'Member credit two',
      3000,
      (select value_id from settle_test_values where label='algorithm-member'),
      array[
        (select value_id from settle_test_values where label='algorithm-stranger')
      ],
      '84000000-0000-4000-8000-000000000003',
      3
    ) -> 'suggestions'
  ) = pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      'payer_participant_id',
      (select value_id from settle_test_values where label='algorithm-history'),
      'recipient_participant_id',
      (select value_id from settle_test_values where label='algorithm-owner'),
      'amount_minor',
      6000
    ),
    pg_catalog.jsonb_build_object(
      'payer_participant_id',
      (select value_id from settle_test_values where label='algorithm-history'),
      'recipient_participant_id',
      (select value_id from settle_test_values where label='algorithm-member'),
      'amount_minor',
      1000
    ),
    pg_catalog.jsonb_build_object(
      'payer_participant_id',
      (select value_id from settle_test_values where label='algorithm-stranger'),
      'recipient_participant_id',
      (select value_id from settle_test_values where label='algorithm-member'),
      'amount_minor',
      3000
    )
  ),
  'largest-balance-first matching produces the exact deterministic three-payment contract'
);
reset role;

delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000002';
select ok(
  public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='member-participant'),
    (select value_id from settle_test_values where label='owner-participant'),
    1000,
    '  Partial cash  ',
    '83000000-0000-4000-8000-000000000002',
    2
  ) @> '{"settings":{"version":3}}'::jsonb,
  'current member records a partial integer-minor-unit settlement'
);
reset role;
select ok(
  (
    select pg_catalog.count(*)
    from realtime.messages
    where topic in (
      'account:81000000-0000-4000-8000-000000000001',
      'account:81000000-0000-4000-8000-000000000002',
      'account:81000000-0000-4000-8000-000000000003'
    )
  ) = 3
  and not exists (
    select 1
    from realtime.messages
    where payload - 'id' <> '{"v":1}'::jsonb
      or event <> 'invalidate'
      or not private
  ),
  'one settlement version fans out only opaque invalidations to current accepted accounts'
);
insert into settle_test_values(label, value_id)
select 'member-settlement', settlement_record.id
from public.active_list_settlements as settlement_record
where settlement_record.creation_request_id =
  '83000000-0000-4000-8000-000000000002';
select ok(
  (
    select settlement_record.note = 'Partial cash'
      and settlement_record.amount_minor = 1000
      and settlement_record.recorded_by_participant_id = (
        select value_id
        from settle_test_values
        where label = 'member-participant'
      )
    from public.active_list_settlements as settlement_record
    where settlement_record.id = (
      select value_id
      from settle_test_values
      where label = 'member-settlement'
    )
  ),
  'server trims the note and attributes the immutable row to the verified caller'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000002';
select ok(
  (
    select
      (owner_document ->> 'paid_minor')::bigint = 6000
      and (owner_document ->> 'owed_minor')::bigint = 0
      and (owner_document ->> 'settlement_paid_minor')::bigint = 0
      and (owner_document ->> 'settlement_received_minor')::bigint = 1000
      and (owner_document ->> 'balance_minor')::bigint = 5000
      and (member_document ->> 'settlement_paid_minor')::bigint = 1000
      and (member_document ->> 'settlement_received_minor')::bigint = 0
      and (member_document ->> 'balance_minor')::bigint = -2000
    from (
      select public.get_active_list_split(
        '82000000-0000-4000-8000-000000000001'
      ) as projection
    ) as split_state
    cross join lateral (
      select participant.document as owner_document
      from pg_catalog.jsonb_array_elements(
        split_state.projection -> 'participants'
      ) as participant(document)
      where participant.document ->> 'id' = (
        select value_id::text
        from settle_test_values
        where label = 'owner-participant'
      )
    ) as owner_state
    cross join lateral (
      select participant.document as member_document
      from pg_catalog.jsonb_array_elements(
        split_state.projection -> 'participants'
      ) as participant(document)
      where participant.document ->> 'id' = (
        select value_id::text
        from settle_test_values
        where label = 'member-participant'
      )
    ) as member_state
  ),
  'recording recalculates exact expense and settlement totals without redefining expense fields'
);
select is(
  (
    select pg_catalog.sum((participant.document ->> 'balance_minor')::bigint)
    from pg_catalog.jsonb_array_elements(
      public.get_active_list_split(
        '82000000-0000-4000-8000-000000000001'
      ) -> 'participants'
    ) as participant(document)
  ),
  0::numeric,
  'settlement-adjusted participant balances remain exactly zero-sum'
);
select is(
  (
    public.record_active_list_settlement(
      '82000000-0000-4000-8000-000000000001',
      (select value_id from settle_test_values where label='member-participant'),
      (select value_id from settle_test_values where label='owner-participant'),
      1000,
      'Partial cash',
      '83000000-0000-4000-8000-000000000002',
      2
    ) #>> '{settings,version}'
  )::bigint,
  3::bigint,
  'identical retry at the prior version returns the committed result'
);
select throws_ok(
  $$select public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='member-participant'),
    (select value_id from settle_test_values where label='owner-participant'),
    999,'Partial cash','83000000-0000-4000-8000-000000000002',3
  )$$,
  '23505',
  'settlement request conflict',
  'request UUID reuse with a different payload is rejected'
);
select throws_ok(
  $$select public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='member-participant'),
    (select value_id from settle_test_values where label='owner-participant'),
    2001,null,'83000000-0000-4000-8000-000000000003',3
  )$$,
  '22023',
  'settlement exceeds outstanding balance',
  'a settlement cannot cross the current debtor or creditor balance'
);
select throws_ok(
  $$select public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='owner-participant'),
    (select value_id from settle_test_values where label='member-participant'),
    1,null,'83000000-0000-4000-8000-000000000004',3
  )$$,
  '22023',
  'settlement exceeds outstanding balance',
  'positive-to-negative direction is rejected'
);
select throws_ok(
  $$select public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='member-participant'),
    (select value_id from settle_test_values where label='owner-participant'),
    1,repeat('n',121),'83000000-0000-4000-8000-000000000013',3
  )$$,
  '22023',
  'invalid settlement',
  'settlement notes longer than 120 canonical characters are rejected'
);
reset role;

insert into settle_test_values(label, version) values
  (
    'stale-record-version',
    (
      select version
      from public.active_list_split_settings
      where list_id = '82000000-0000-4000-8000-000000000001'
    )
  ),
  (
    'stale-record-rows',
    (
      select pg_catalog.count(*)
      from public.active_list_settlements
      where list_id = '82000000-0000-4000-8000-000000000001'
    )
  ),
  (
    'stale-record-messages',
    (select pg_catalog.count(*) from realtime.messages)
  );
set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='member-participant'),
    (select value_id from settle_test_values where label='owner-participant'),
    1,null,'83000000-0000-4000-8000-000000000014',2
  )$$,
  '40001',
  'split changed',
  'serialized concurrent settlement loser is rejected by stale aggregate version'
);
reset role;
select ok(
  (
    select version
    from public.active_list_split_settings
    where list_id = '82000000-0000-4000-8000-000000000001'
  ) = (
    select version from settle_test_values where label = 'stale-record-version'
  )
  and (
    select pg_catalog.count(*)
    from public.active_list_settlements
    where list_id = '82000000-0000-4000-8000-000000000001'
  ) = (
    select version from settle_test_values where label = 'stale-record-rows'
  )
  and (
    select pg_catalog.count(*) from realtime.messages
  ) = (
    select version from settle_test_values where label = 'stale-record-messages'
  ),
  'stale concurrent record creates no row, version, or Realtime invalidation'
);

update public.active_list_participants
set state = 'removed',
    version = version + 1,
    state_changed_at = now()
where list_id = '82000000-0000-4000-8000-000000000001'
  and participant_profile_id = '81000000-0000-4000-8000-000000000003';

savepoint member_historical_settlement_probe;
set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000002';
select ok(
  public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='history-participant'),
    (select value_id from settle_test_values where label='owner-participant'),
    1,
    '  ' || repeat('n', 120) || '  ',
    '83000000-0000-4000-8000-000000000015',
    3
  ) @> '{"settings":{"version":4}}'::jsonb,
  'current member may record a historical endpoint with an exact 120-character note'
);
reset role;
rollback to savepoint member_historical_settlement_probe;
release savepoint member_historical_settlement_probe;

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select ok(
  public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='history-participant'),
    (select value_id from settle_test_values where label='owner-participant'),
    500,
    null,
    '83000000-0000-4000-8000-000000000005',
    3
  ) @> '{"settings":{"version":4}}'::jsonb,
  'current owner may record a valid payment for a removed historical debtor'
);
reset role;
insert into settle_test_values(label, value_id)
select 'owner-settlement', settlement_record.id
from public.active_list_settlements as settlement_record
where settlement_record.creation_request_id =
  '83000000-0000-4000-8000-000000000005';
insert into settle_test_values(label, version) values
  (
    'stale-reverse-version',
    (
      select version
      from public.active_list_split_settings
      where list_id = '82000000-0000-4000-8000-000000000001'
    )
  ),
  (
    'stale-reverse-rows',
    (
      select pg_catalog.count(*)
      from public.active_list_settlement_reversals
      where list_id = '82000000-0000-4000-8000-000000000001'
    )
  ),
  (
    'stale-reverse-messages',
    (select pg_catalog.count(*) from realtime.messages)
  );
set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.reverse_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='owner-settlement'),
    'Stale correction',
    '83000000-0000-4000-8000-000000000016',
    3
  )$$,
  '40001',
  'split changed',
  'serialized concurrent reversal loser is rejected by stale aggregate version'
);
reset role;
select ok(
  (
    select version
    from public.active_list_split_settings
    where list_id = '82000000-0000-4000-8000-000000000001'
  ) = (
    select version from settle_test_values where label = 'stale-reverse-version'
  )
  and (
    select pg_catalog.count(*)
    from public.active_list_settlement_reversals
    where list_id = '82000000-0000-4000-8000-000000000001'
  ) = (
    select version from settle_test_values where label = 'stale-reverse-rows'
  )
  and (
    select pg_catalog.count(*) from realtime.messages
  ) = (
    select version from settle_test_values where label = 'stale-reverse-messages'
  ),
  'stale concurrent reversal creates no row, version, or Realtime invalidation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000002';
select ok(
  exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      public.list_active_list_settlements(
        '82000000-0000-4000-8000-000000000001',
        20,
        null,
        null
      ) -> 'entries'
    ) as history_entry(document)
    where history_entry.document ->> 'id' = (
      select value_id::text
      from settle_test_values
      where label = 'owner-settlement'
    )
      and not (history_entry.document ->> 'can_reverse')::boolean
  ),
  'non-recorder member sees owner-recorded history without reversal authority'
);
select throws_ok(
  $$select public.reverse_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='owner-settlement'),
    'Not mine',
    '83000000-0000-4000-8000-000000000006',
    4
  )$$,
  '40001',
  'settlement changed',
  'non-recorder member receives stale reconciliation rather than access loss'
);
reset role;
select ok(
  (
    select version
    from public.active_list_split_settings
    where list_id = '82000000-0000-4000-8000-000000000001'
  ) = (
    select version from settle_test_values where label = 'stale-reverse-version'
  )
  and (
    select pg_catalog.count(*)
    from public.active_list_settlement_reversals
    where list_id = '82000000-0000-4000-8000-000000000001'
  ) = (
    select version from settle_test_values where label = 'stale-reverse-rows'
  )
  and (
    select pg_catalog.count(*) from realtime.messages
  ) = (
    select version from settle_test_values where label = 'stale-reverse-messages'
  ),
  'reversal-authority denial adds no row, version, or Realtime invalidation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select ok(
  exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      public.list_active_list_settlements(
        '82000000-0000-4000-8000-000000000001',
        20,
        null,
        null
      ) -> 'entries'
    ) as history_entry(document)
    where history_entry.document ->> 'id' = (
      select value_id::text
      from settle_test_values
      where label = 'owner-settlement'
    )
      and (history_entry.document ->> 'can_reverse')::boolean
  ),
  'owner receives server-derived reversal authority for an unreversed payment'
);
select throws_ok(
  $$select public.reverse_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='owner-settlement'),
    repeat('r',121),
    '83000000-0000-4000-8000-000000000017',
    4
  )$$,
  '22023',
  'invalid settlement reversal',
  'reversal reasons longer than 120 canonical characters are rejected'
);
reset role;
delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select is(
  (
    public.reverse_active_list_settlement(
      '82000000-0000-4000-8000-000000000001',
      (select value_id from settle_test_values where label='owner-settlement'),
      '  ' || repeat('r', 120) || '  ',
      '83000000-0000-4000-8000-000000000007',
      4
    ) #>> '{settings,version}'
  )::bigint,
  5::bigint,
  'owner appends one full reversal without changing the original payment'
);
reset role;
select ok(
  (
    select pg_catalog.count(*)
    from realtime.messages
    where topic in (
      'account:81000000-0000-4000-8000-000000000001',
      'account:81000000-0000-4000-8000-000000000002'
    )
  ) = 2
  and not exists (
    select 1
    from realtime.messages
    where payload - 'id' <> '{"v":1}'::jsonb
      or event <> 'invalidate'
      or not private
  ),
  'one reversal version fans out only opaque invalidations to current accounts'
);
select ok(
  (
    select pg_catalog.char_length(reversal_record.reason) = 120
      and settlement_record.amount_minor = 500
    from public.active_list_settlements as settlement_record
    join public.active_list_settlement_reversals as reversal_record
      on reversal_record.list_id = settlement_record.list_id
     and reversal_record.settlement_id = settlement_record.id
    where settlement_record.id = (
      select value_id
      from settle_test_values
      where label = 'owner-settlement'
    )
  ),
  'reversal trims and accepts an exact 120-character reason without changing the payment'
);
set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select is(
  (
    public.reverse_active_list_settlement(
      '82000000-0000-4000-8000-000000000001',
      (select value_id from settle_test_values where label='owner-settlement'),
      repeat('r', 120),
      '83000000-0000-4000-8000-000000000007',
      4
    ) #>> '{settings,version}'
  )::bigint,
  5::bigint,
  'identical reversal retry at the prior version is idempotent'
);
select throws_ok(
  $$select public.reverse_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='owner-settlement'),
    'Different reason',
    '83000000-0000-4000-8000-000000000007',
    5
  )$$,
  '23505',
  'settlement reversal request conflict',
  'reversal request UUID reuse with a different payload is rejected'
);
select throws_ok(
  $$select public.reverse_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='owner-settlement'),
    'Second reversal',
    '83000000-0000-4000-8000-000000000008',
    5
  )$$,
  '40001',
  'settlement changed',
  'one settlement can be reversed only once'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000002';
select is(
  (
    public.reverse_active_list_settlement(
      '82000000-0000-4000-8000-000000000001',
      (select value_id from settle_test_values where label='member-settlement'),
      'Cash was returned',
      '83000000-0000-4000-8000-000000000009',
      5
    ) #>> '{settings,version}'
  )::bigint,
  6::bigint,
  'original recorder may reverse their own payment'
);
reset role;

select throws_ok(
  $$update public.active_list_settlements
    set note = 'Changed'
    where id = (
      select value_id from settle_test_values where label='member-settlement'
    )$$,
  '55000',
  'settlement history is immutable',
  'even privileged in-place settlement update is rejected'
);
select throws_ok(
  $$update public.active_list_settlement_reversals
    set reason = 'Changed'
    where settlement_id = (
      select value_id from settle_test_values where label='member-settlement'
    )$$,
  '55000',
  'settlement history is immutable',
  'even privileged in-place reversal update is rejected'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.change_active_list_split_currency(
    '82000000-0000-4000-8000-000000000001','EUR',6
  )$$,
  '22023',
  'split currency is locked',
  'any settlement history permanently locks list currency after reversal'
);
select ok(
  (
    select
      first_page ->> 'currency_code' = 'CHF'
      and pg_catalog.jsonb_array_length(first_page -> 'entries') = 1
      and first_page -> 'next_cursor' is not null
      and pg_catalog.jsonb_array_length(second_page -> 'entries') = 1
      and first_page #>> '{entries,0,id}' <>
        second_page #>> '{entries,0,id}'
      and second_page -> 'next_cursor' = 'null'::jsonb
    from (
      select public.list_active_list_settlements(
        '82000000-0000-4000-8000-000000000001',
        1,
        null,
        null
      ) as first_page
    ) as first_result
    cross join lateral (
      select public.list_active_list_settlements(
        '82000000-0000-4000-8000-000000000001',
        1,
        (first_result.first_page #>> '{next_cursor,created_at}')::timestamptz,
        (first_result.first_page #>> '{next_cursor,id}')::uuid
      ) as second_page
    ) as second_result
  ),
  'bounded keyset pagination returns stable non-overlapping history pages'
);
select ok(
  (
    select
      history_page #>> '{entries,0,id}' = (
        select value_id::text
        from settle_test_values
        where label = 'owner-settlement'
      )
      and history_page #>> '{entries,1,id}' = (
        select value_id::text
        from settle_test_values
        where label = 'member-settlement'
      )
      and not exists (
        select 1
        from pg_catalog.jsonb_array_elements(
          history_page -> 'entries'
        ) as history_entry(document)
        where (
          select pg_catalog.array_agg(key order by key)
          from pg_catalog.jsonb_object_keys(history_entry.document) as key
        ) <> array[
          'amount_minor',
          'can_reverse',
          'created_at',
          'id',
          'note',
          'payer_participant_id',
          'recipient_participant_id',
          'recorded_by_participant_id',
          'reversal'
        ]
      )
    from (
      select public.list_active_list_settlements(
        '82000000-0000-4000-8000-000000000001',
        20,
        null,
        null
      ) as history_page
    ) as current_history
  ),
  'history uses the exact allowlist and deterministic newest-first UUID order'
);
select ok(
  public.export_own_account_data() ->> 'schema_version' = '6'
  and exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      public.export_own_account_data() -> 'active_lists'
    ) as exported_list(document)
    where exported_list.document ->> 'id' =
      '82000000-0000-4000-8000-000000000001'
      and pg_catalog.jsonb_array_length(
        exported_list.document #> '{split,settlements}'
      ) = 2
      and exported_list.document #>> '{split,settlements,0,id}' = (
        select value_id::text
        from settle_test_values
        where label = 'owner-settlement'
      )
      and exported_list.document #>> '{split,settlements,1,id}' = (
        select value_id::text
        from settle_test_values
        where label = 'member-settlement'
      )
      and not exists (
        select 1
        from pg_catalog.jsonb_array_elements(
          exported_list.document #> '{split,settlements}'
        ) as exported_settlement(document)
        where (
          select pg_catalog.array_agg(key order by key)
          from pg_catalog.jsonb_object_keys(
            exported_settlement.document
          ) as key
        ) <> array[
          'amount_minor',
          'created_at',
          'id',
          'note',
          'payer_participant_id',
          'recipient_participant_id',
          'recorded_by_participant_id',
          'reversal'
        ]
          or exported_settlement.document ? 'creation_request_id'
          or exported_settlement.document ? 'can_reverse'
          or (
            exported_settlement.document -> 'reversal' <> 'null'::jsonb
            and (
              select pg_catalog.array_agg(key order by key)
              from pg_catalog.jsonb_object_keys(
                exported_settlement.document -> 'reversal'
              ) as key
            ) <> array[
              'created_at',
              'reason',
              'reversed_by_participant_id'
            ]
          )
      )
  ),
  'schema-version-six owner export allowlists nested settlement and reversal history'
);
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000002';
select ok(
  not (
    public.export_own_account_data() -> 'active_lists'
    @> '[{"id":"82000000-0000-4000-8000-000000000001"}]'::jsonb
  ),
  'member export does not leak another owner list settlement history'
);
reset role;

delete from auth.users
where id = '81000000-0000-4000-8000-000000000003';
select ok(
  exists (
    select 1
    from public.active_list_split_participants as split_participant
    where split_participant.id = (
      select value_id
      from settle_test_values
      where label = 'history-participant'
    )
      and split_participant.profile_id is null
      and split_participant.username_snapshot is null
      and split_participant.display_name_snapshot is null
  )
  and exists (
    select 1
    from public.active_list_settlements as settlement_record
    where settlement_record.id = (
      select value_id
      from settle_test_values
      where label = 'owner-settlement'
    )
  ),
  'account deletion anonymizes the persistent endpoint without deleting financial history'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select is(
  (
    public.record_active_list_settlement(
      '82000000-0000-4000-8000-000000000001',
      (select value_id from settle_test_values where label='member-participant'),
      (select value_id from settle_test_values where label='owner-participant'),
      500,
      '  ' || repeat('n', 120) || '  ',
      '83000000-0000-4000-8000-000000000010',
      6
    ) #>> '{settings,version}'
  )::bigint,
  7::bigint,
  'a later valid payment still records after earlier one-time reversals'
);
reset role;
insert into settle_test_values(label, value_id)
select 'active-settlement', settlement_record.id
from public.active_list_settlements as settlement_record
where settlement_record.creation_request_id =
  '83000000-0000-4000-8000-000000000010';
select is(
  (
    select pg_catalog.char_length(settlement_record.note)
    from public.active_list_settlements as settlement_record
    where settlement_record.creation_request_id =
      '83000000-0000-4000-8000-000000000010'
  ),
  120,
  'an exact canonical 120-character settlement note is stored after trimming'
);

update public.active_lists
set status = 'archived',
    archived_at = now(),
    version = version + 1,
    updated_at = now()
where id = '82000000-0000-4000-8000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub" = '81000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.record_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='member-participant'),
    (select value_id from settle_test_values where label='owner-participant'),
    1,null,'83000000-0000-4000-8000-000000000011',7
  )$$,
  '55000',
  'archived list is read only',
  'archived list rejects settlement recording'
);
select throws_ok(
  $$select public.reverse_active_list_settlement(
    '82000000-0000-4000-8000-000000000001',
    (select value_id from settle_test_values where label='active-settlement'),
    'Archived correction',
    '83000000-0000-4000-8000-000000000012',
    7
  )$$,
  '55000',
  'archived list is read only',
  'archived list rejects settlement reversal'
);
select ok(
  not exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      public.list_active_list_settlements(
        '82000000-0000-4000-8000-000000000001',
        20,
        null,
        null
      ) -> 'entries'
    ) as history_entry(document)
    where (history_entry.document ->> 'can_reverse')::boolean
  ),
  'archived history remains readable but exposes no reversal action'
);
reset role;

select is(
  (
    select version
    from public.active_list_split_settings
    where list_id = '82000000-0000-4000-8000-000000000001'
  ),
  7::bigint,
  'failed, stale, denied, and archived requests never advance aggregate version'
);
select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
  ),
  0::bigint,
  'settlement operations create no persistent notification'
);
select ok(
  (
    select pg_catalog.count(*)
    from realtime.messages
    where topic in (
      'account:81000000-0000-4000-8000-000000000001',
      'account:81000000-0000-4000-8000-000000000002'
    )
  ) > 0
  and not exists (
    select 1
    from realtime.messages
    where payload - 'id' <> '{"v":1}'::jsonb
      or event <> 'invalidate'
      or not private
  ),
  'successful settlement aggregate versions use only opaque private invalidations'
);

delete from public.active_lists
where id = '82000000-0000-4000-8000-000000000001';
select ok(
  not exists (
    select 1
    from public.active_list_settlements
    where list_id = '82000000-0000-4000-8000-000000000001'
  )
  and not exists (
    select 1
    from public.active_list_settlement_reversals
    where list_id = '82000000-0000-4000-8000-000000000001'
  ),
  'list deletion cascades settlement and reversal history'
);

select * from finish();
rollback;
