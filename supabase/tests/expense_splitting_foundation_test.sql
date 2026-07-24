begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','active_list_split_settings','Split settings table exists');
select has_table('public','active_list_split_participants','Split participants table exists');
select has_table('public','active_list_expenses','Split expenses table exists');
select has_table('public','active_list_expense_shares','Split shares table exists');

select columns_are(
  'public','active_list_split_settings',
  array['list_id','currency_code','version','created_at','updated_at'],
  'settings expose only the reviewed columns'
);
select columns_are(
  'public','active_list_split_participants',
  array['id','list_id','profile_id','username_snapshot','display_name_snapshot','created_at','updated_at'],
  'financial participants retain no deletion timestamp or hidden identity field'
);
select columns_are(
  'public','active_list_expenses',
  array['id','list_id','description','amount_minor','payer_participant_id','creator_participant_id','last_editor_participant_id','version','creation_request_id','created_at','updated_at'],
  'expenses expose only the reviewed physical columns'
);
select columns_are(
  'public','active_list_expense_shares',
  array['list_id','expense_id','participant_id','amount_minor'],
  'shares expose only same-list allocation columns'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as table_record
    where table_record.oid in (
      'public.active_list_split_settings'::regclass,
      'public.active_list_split_participants'::regclass,
      'public.active_list_expenses'::regclass,
      'public.active_list_expense_shares'::regclass
    ) and table_record.relrowsecurity and table_record.relforcerowsecurity
  ),
  4::bigint,
  'all Split tables enable and force RLS'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname='public'
      and tablename in (
        'active_list_split_settings','active_list_split_participants',
        'active_list_expenses','active_list_expense_shares'
      )
      and cmd='ALL'
      and roles=array['anon','authenticated']::name[]
      and qual='false'
      and with_check='false'
  ),
  4::bigint,
  'each Split table explicitly rejects every direct client operation'
);
select ok(
  not has_table_privilege('anon','public.active_list_split_settings','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.active_list_split_settings','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','public.active_list_split_settings','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon','public.active_list_split_participants','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.active_list_split_participants','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','public.active_list_split_participants','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon','public.active_list_expenses','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.active_list_expenses','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','public.active_list_expenses','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon','public.active_list_expense_shares','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.active_list_expense_shares','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','public.active_list_expense_shares','SELECT,INSERT,UPDATE,DELETE'),
  'all API roles lack direct Split table CRUD'
);

select ok(
  (
    select pg_catalog.bool_and(
      function_record.prosecdef
      and function_record.proowner='postgres'::regrole
      and function_record.proconfig=array['search_path=""']
      and pg_catalog.obj_description(function_record.oid,'pg_proc') is not null
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.get_active_list_split(uuid)'::regprocedure,
      'public.enable_active_list_split(uuid,text,bigint)'::regprocedure,
      'public.change_active_list_split_currency(uuid,text,bigint)'::regprocedure,
      'public.create_active_list_expense(uuid,text,bigint,uuid,uuid[],uuid,bigint)'::regprocedure,
      'public.update_active_list_expense(uuid,uuid,text,bigint,uuid,uuid[],bigint,bigint)'::regprocedure,
      'public.delete_active_list_expense(uuid,uuid,bigint,bigint)'::regprocedure,
      'public.export_own_account_data()'::regprocedure
    )
  ),
  'all public Split/export RPCs are commented postgres-owned hardened definer boundaries'
);
select ok(
  (
    select pg_catalog.bool_and(
      has_function_privilege('authenticated',function_record.oid,'EXECUTE')
      and not has_function_privilege('anon',function_record.oid,'EXECUTE')
      and not has_function_privilege('service_role',function_record.oid,'EXECUTE')
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.get_active_list_split(uuid)'::regprocedure,
      'public.enable_active_list_split(uuid,text,bigint)'::regprocedure,
      'public.change_active_list_split_currency(uuid,text,bigint)'::regprocedure,
      'public.create_active_list_expense(uuid,text,bigint,uuid,uuid[],uuid,bigint)'::regprocedure,
      'public.update_active_list_expense(uuid,uuid,text,bigint,uuid,uuid[],bigint,bigint)'::regprocedure,
      'public.delete_active_list_expense(uuid,uuid,bigint,bigint)'::regprocedure
    )
  ),
  'only authenticated receives each exact Split RPC grant'
);
select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
    where schemaname='public' and indexname='active_list_split_participants_profile_idx'
      and indexdef like '%(profile_id, list_id)%WHERE (profile_id IS NOT NULL)%'
  ),
  'profile-leading partial index supports account-deletion anonymization'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint
    where conrelid in (
      'public.active_list_expenses'::regclass,
      'public.active_list_expense_shares'::regclass
    )
      and conname in (
        'active_list_expenses_payer_fkey','active_list_expenses_creator_fkey',
        'active_list_expenses_last_editor_fkey','active_list_expense_shares_expense_fkey',
        'active_list_expense_shares_participant_fkey'
      )
      and condeferrable and condeferred
  ),
  5::bigint,
  'all same-list financial foreign keys are initially deferred'
);

set local role anon;
select throws_like($$select * from public.active_list_expenses$$,'%permission denied%','anon direct expense SELECT denied');
select throws_like($$select public.get_active_list_split(gen_random_uuid())$$,'%permission denied%function%','anon Split RPC denied');
reset role;
set local role authenticated;
select throws_like($$select * from public.active_list_expenses$$,'%permission denied%','authenticated direct expense SELECT denied');
select throws_like(
  $$insert into public.active_list_expense_shares values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),1)$$,
  '%permission denied%',
  'authenticated direct share INSERT denied'
);
reset role;

insert into auth.users(id,email,email_confirmed_at,created_at,updated_at) values
  ('71000000-0000-4000-8000-000000000001','split-owner@example.test',now(),now(),now()),
  ('71000000-0000-4000-8000-000000000002','split-member@example.test',now(),now(),now()),
  ('71000000-0000-4000-8000-000000000003','split-history@example.test',now(),now(),now()),
  ('71000000-0000-4000-8000-000000000004','split-stranger@example.test',now(),now(),now()),
  ('71000000-0000-4000-8000-000000000005','split-pending@example.test',now(),now(),now());
update public.profiles set
  username=case id
    when '71000000-0000-4000-8000-000000000001' then 'split_owner'
    when '71000000-0000-4000-8000-000000000002' then 'split_member'
    when '71000000-0000-4000-8000-000000000003' then 'split_history'
    when '71000000-0000-4000-8000-000000000004' then 'split_stranger'
    else 'split_pending'
  end,
  display_name=case id
    when '71000000-0000-4000-8000-000000000001' then 'Split Owner'
    when '71000000-0000-4000-8000-000000000002' then 'Split Member'
    when '71000000-0000-4000-8000-000000000003' then 'Split History'
    when '71000000-0000-4000-8000-000000000004' then 'Split Stranger'
    else 'Split Pending'
  end
where id::text like '71000000-0000-4000-8000-00000000000_';

insert into public.active_lists(id,owner_id,title,creation_request_id) values
  ('72000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','Split trip','72000000-0000-4000-8000-000000000011'),
  ('72000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000004','Private other','72000000-0000-4000-8000-000000000012'),
  ('72000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000001','Capacity ledger','72000000-0000-4000-8000-000000000013'),
  ('72000000-0000-4000-8000-000000000004','71000000-0000-4000-8000-000000000001','Wide history ledger','72000000-0000-4000-8000-000000000014');
insert into public.active_list_participants(list_id,participant_profile_id,state) values
  ('72000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002','member'),
  ('72000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000003','member'),
  ('72000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000005','pending');

create temporary table split_test_values(
  label text primary key,
  value_id uuid,
  version bigint
) on commit drop;
grant select,insert,update on split_test_values to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select ok(
  public.get_active_list_split('72000000-0000-4000-8000-000000000001') @>
    '{"enabled":false,"writable":false,"settings":null,"participants":[],"expenses":[]}'::jsonb,
  'accessible disabled Split returns the exact empty setup state'
);
select throws_ok(
  $$select public.enable_active_list_split('72000000-0000-4000-8000-000000000001','USD',1)$$,
  '22023','invalid split setup','unsupported currency is rejected'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.enable_active_list_split('72000000-0000-4000-8000-000000000001','CHF',1)$$,
  'P0002','list unavailable','accepted member cannot enable Split'
);
reset role;

delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select ok(
  public.enable_active_list_split('72000000-0000-4000-8000-000000000001','CHF',1) @>
    '{"enabled":true,"writable":true,"settings":{"currency_code":"CHF","version":1}}'::jsonb,
  'owner enables CHF Split on an active list'
);
select is(
  pg_catalog.jsonb_array_length(public.get_active_list_split('72000000-0000-4000-8000-000000000001')->'participants'),
  3,
  'enable materializes exactly the owner and two accepted members'
);
select is(
  (public.enable_active_list_split('72000000-0000-4000-8000-000000000001','CHF',1)#>>'{settings,version}')::bigint,
  1::bigint,
  'completed enable retry is an idempotent version no-op'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.active_list_split_participants where list_id='72000000-0000-4000-8000-000000000001'),
  3::bigint,
  'pending and unrelated profiles receive no financial identity'
);
select ok(
  not exists(
    select 1 from public.active_list_split_participants
    where list_id='72000000-0000-4000-8000-000000000001' and id=profile_id
  ),
  'financial participant IDs are independent random identities'
);

insert into split_test_values(label,value_id)
select case profile_id
    when '71000000-0000-4000-8000-000000000001' then 'owner-participant'
    when '71000000-0000-4000-8000-000000000002' then 'member-participant'
    else 'history-participant'
  end,
  id
from public.active_list_split_participants
where list_id='72000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000005';
select throws_ok(
  $$select public.get_active_list_split('72000000-0000-4000-8000-000000000001')$$,
  'P0002','list unavailable','pending participant cannot read Split'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Pending',1,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000090',1)$$,
  'P0002','list unavailable','pending participant cannot create an expense'
);
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000004';
select throws_ok(
  $$select public.get_active_list_split('72000000-0000-4000-8000-000000000001')$$,
  'P0002','list unavailable','unrelated caller cannot read Split'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Unrelated',1,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000091',1)$$,
  'P0002','list unavailable','unrelated caller cannot create an expense'
);
select lives_ok(
  $$select public.enable_active_list_split(
    '72000000-0000-4000-8000-000000000002','CHF',1)$$,
  'unrelated-list owner enables only their own Split fixture'
);
reset role;
insert into split_test_values(label,value_id)
select 'other-list-participant',id
from public.active_list_split_participants
where list_id='72000000-0000-4000-8000-000000000002';

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.change_active_list_split_currency(
    '72000000-0000-4000-8000-000000000001','EUR',1)$$,
  'P0002','list unavailable','accepted member cannot change Split currency'
);
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.enable_active_list_split(
    '72000000-0000-4000-8000-000000000001','EUR',1)$$,
  '22023','split is already enabled','enabled Split cannot be silently reconfigured by setup retry'
);

select is(
  (public.change_active_list_split_currency('72000000-0000-4000-8000-000000000001','EUR',1)#>>'{settings,version}')::bigint,
  2::bigint,
  'owner changes currency exactly once before expenses exist'
);
select is(
  (public.change_active_list_split_currency('72000000-0000-4000-8000-000000000001','EUR',1)#>>'{settings,version}')::bigint,
  2::bigint,
  'currency change retry at the prior version is a no-op'
);

select ok(
  public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','  Lodging  ',6000,
    (select value_id from split_test_values where label='owner-participant'),
    array[
      (select value_id from split_test_values where label='member-participant'),
      (select value_id from split_test_values where label='owner-participant')
    ],
    '73000000-0000-4000-8000-000000000001',2
  ) @> '{"settings":{"version":3}}'::jsonb,
  'owner creates Example A atomically with trimmed description'
);
reset role;
insert into split_test_values(label,value_id,version)
select 'expense-a',id,version
from public.active_list_expenses
where list_id='72000000-0000-4000-8000-000000000001'
  and creation_request_id='73000000-0000-4000-8000-000000000001';
select ok(
  (
    select pg_catalog.count(*)=2 and pg_catalog.min(amount_minor)=3000
      and pg_catalog.max(amount_minor)=3000 and pg_catalog.sum(amount_minor)=6000
    from public.active_list_expense_shares
    where expense_id=(select value_id from split_test_values where label='expense-a')
  ),
  'Example A stores two exact CHF 30.00 shares summing to CHF 60.00'
);
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select ok(
  (
    select (owner_participant->>'balance_minor')::bigint=3000
      and (member_participant->>'balance_minor')::bigint=-3000
    from (select public.get_active_list_split('72000000-0000-4000-8000-000000000001') as projection) as split_state
    cross join lateral (
      select value as owner_participant
      from pg_catalog.jsonb_array_elements(split_state.projection->'participants')
      where value->>'profile_id'='71000000-0000-4000-8000-000000000001'
    ) as owner_row
    cross join lateral (
      select value as member_participant
      from pg_catalog.jsonb_array_elements(split_state.projection->'participants')
      where value->>'profile_id'='71000000-0000-4000-8000-000000000002'
    ) as member_row
  ),
  'Example A derives Fernando-like +CHF30 and Susana-like -CHF30 balances'
);

select is(
  pg_catalog.jsonb_array_length(
    public.create_active_list_expense(
      '72000000-0000-4000-8000-000000000001','Lodging',6000,
      (select value_id from split_test_values where label='owner-participant'),
      array[(select value_id from split_test_values where label='owner-participant'),(select value_id from split_test_values where label='member-participant')],
      '73000000-0000-4000-8000-000000000001',2
    )->'expenses'
  ),
  1,
  'matching lost-response creation retry creates no duplicate expense'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Different',6000,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000001',2)$$,
  '23505','expense creation request conflict','payload-conflicting request ID is rejected'
);

set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000002';
select ok(
  public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Taxi',2000,
    (select value_id from split_test_values where label='member-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000002',3
  ) @> '{"settings":{"version":4}}'::jsonb,
  'accepted member creates Example B with payer excluded from beneficiaries'
);
select ok(
  (
    select (owner_participant->>'balance_minor')::bigint=1000
      and (member_participant->>'balance_minor')::bigint=-1000
    from (select public.get_active_list_split('72000000-0000-4000-8000-000000000001') as projection) as split_state
    cross join lateral (
      select value as owner_participant from pg_catalog.jsonb_array_elements(split_state.projection->'participants')
      where value->>'profile_id'='71000000-0000-4000-8000-000000000001'
    ) as owner_row
    cross join lateral (
      select value as member_participant from pg_catalog.jsonb_array_elements(split_state.projection->'participants')
      where value->>'profile_id'='71000000-0000-4000-8000-000000000002'
    ) as member_row
  ),
  'combined examples derive +CHF10 and -CHF10 exactly'
);

set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Remainder',101,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='member-participant'),(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000003',4)$$,
  'non-even minor-unit expense succeeds'
);
reset role;
insert into split_test_values(label,value_id,version)
select 'remainder-expense',id,version
from public.active_list_expenses
where creation_request_id='73000000-0000-4000-8000-000000000003';
select ok(
  (
    select pg_catalog.array_agg(amount_minor order by participant_id)=array[51::bigint,50::bigint]
      and pg_catalog.sum(amount_minor)=101
    from public.active_list_expense_shares
    where expense_id=(
      select id from public.active_list_expenses
      where creation_request_id='73000000-0000-4000-8000-000000000003'
    )
  ),
  'ascending immutable participant ID receives the deterministic remainder'
);
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select is(
  (
    select pg_catalog.sum((participant->>'balance_minor')::bigint)
    from pg_catalog.jsonb_array_elements(
      public.get_active_list_split('72000000-0000-4000-8000-000000000001')->'participants'
    ) as participant
  ),
  0::numeric,
  'all derived list balances sum exactly to zero'
);

reset role;
insert into split_test_values(label,version) values
  ('invalid-failure-realtime',(select pg_catalog.count(*) from realtime.messages));
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.change_active_list_split_currency('72000000-0000-4000-8000-000000000001','CHF',5)$$,
  '22023','split currency is locked','currency cannot change after the first expense'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Zero',0,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000004',5)$$,
  '22023','invalid expense creation','zero amount is rejected'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','None',1,
    (select value_id from split_test_values where label='owner-participant'),'{}'::uuid[],
    '73000000-0000-4000-8000-000000000005',5)$$,
  '22023','invalid expense creation','zero beneficiaries are rejected'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001',pg_catalog.repeat('x',121),1,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000092',5)$$,
  '22023','invalid expense creation','description over one hundred twenty characters is rejected'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Excessive',1000000000,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000093',5)$$,
  '22023','invalid expense creation','amount above the documented minor-unit maximum is rejected'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Cross list',1,
    (select value_id from split_test_values where label='other-list-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000006',5)$$,
  '22023','expense participant unavailable','cross-list financial participant ID is rejected'
);

reset role;
select ok(
  (select version from public.active_list_split_settings
   where list_id='72000000-0000-4000-8000-000000000001')=5
  and (select pg_catalog.count(*) from public.active_list_expenses
       where list_id='72000000-0000-4000-8000-000000000001')=3
  and (select pg_catalog.count(*) from realtime.messages)=
      (select version from split_test_values where label='invalid-failure-realtime'),
  'invalid create/currency requests leave expenses, aggregate version, and invalidations unchanged'
);
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000003';
select is(
  (public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Historical payer',100,
    (select value_id from split_test_values where label='history-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000007',5)#>>'{settings,version}')::bigint,
  6::bigint,
  'accepted member creates an expense where their identity is payer-only'
);
select is(
  (public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Historical beneficiary',100,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='history-participant')],
    '73000000-0000-4000-8000-000000000008',6)#>>'{settings,version}')::bigint,
  7::bigint,
  'accepted member creates an expense where their identity is beneficiary-only'
);
reset role;
insert into split_test_values(label,value_id,version)
select
  case creation_request_id
    when '73000000-0000-4000-8000-000000000007' then 'historical-payer-expense'
    else 'historical-beneficiary-expense'
  end,
  id,
  version
from public.active_list_expenses
where creation_request_id in (
  '73000000-0000-4000-8000-000000000007',
  '73000000-0000-4000-8000-000000000008'
);
update public.active_list_participants set state='removed',version=version+1,state_changed_at=now()
where list_id='72000000-0000-4000-8000-000000000001'
  and participant_profile_id='71000000-0000-4000-8000-000000000003';
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select public.get_active_list_split('72000000-0000-4000-8000-000000000001')$$,
  'P0002','list unavailable','removed participant cannot read Split'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Removed caller',1,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000009',7)$$,
  'P0002','list unavailable','removed participant cannot create an expense'
);
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Removed',1,
    (select value_id from split_test_values where label='history-participant'),
    array[(select value_id from split_test_values where label='history-participant')],
    '73000000-0000-4000-8000-000000000010',7)$$,
  '22023','expense participant unavailable','removed identity cannot enter a new expense'
);
select is(
  (public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000001',
    (select value_id from split_test_values where label='historical-payer-expense'),
    'Historical payer adjusted',120,
    (select value_id from split_test_values where label='history-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],7,1)
    #>>'{settings,version}')::bigint,
  8::bigint,
  'removed existing payer may remain payer on an edit'
);
reset role;

select is(
  (select amount_minor from public.active_list_expense_shares
   where expense_id=(select value_id from split_test_values where label='historical-payer-expense')),
  120::bigint,
  'successful update atomically recalculates the stored equal share'
);
insert into split_test_values(label,version)
values ('payer-role-failure-realtime',(select pg_catalog.count(*) from realtime.messages));
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000001',
    (select value_id from split_test_values where label='historical-payer-expense'),
    'Invalid role expansion',120,
    (select value_id from split_test_values where label='history-participant'),
    array[
      (select value_id from split_test_values where label='owner-participant'),
      (select value_id from split_test_values where label='history-participant')
    ],8,2)$$,
  '22023','expense participant unavailable',
  'removed payer cannot be newly added as a beneficiary'
);
reset role;
select ok(
  (select version from public.active_list_split_settings
   where list_id='72000000-0000-4000-8000-000000000001')=8
  and (select version from public.active_list_expenses
       where id=(select value_id from split_test_values where label='historical-payer-expense'))=2
  and (select pg_catalog.count(*) from realtime.messages)=
      (select version from split_test_values where label='payer-role-failure-realtime'),
  'failed historical role expansion changes no rows, versions, or invalidations'
);

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select is(
  (public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000001',
    (select value_id from split_test_values where label='historical-payer-expense'),
    'Historical payer removed',120,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],8,2)
    #>>'{settings,version}')::bigint,
  9::bigint,
  'editing may remove a historical payer without deleting its identity'
);
select is(
  (public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000001',
    (select value_id from split_test_values where label='historical-beneficiary-expense'),
    'Historical beneficiary adjusted',130,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='history-participant')],9,1)
    #>>'{settings,version}')::bigint,
  10::bigint,
  'removed existing beneficiary may remain beneficiary on an edit'
);
reset role;
insert into split_test_values(label,version)
values ('beneficiary-role-failure-realtime',(select pg_catalog.count(*) from realtime.messages));
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000001',
    (select value_id from split_test_values where label='historical-beneficiary-expense'),
    'Invalid payer switch',130,
    (select value_id from split_test_values where label='history-participant'),
    array[(select value_id from split_test_values where label='history-participant')],10,2)$$,
  '22023','expense participant unavailable',
  'removed beneficiary cannot switch into the payer role'
);
reset role;
select ok(
  (select version from public.active_list_split_settings
   where list_id='72000000-0000-4000-8000-000000000001')=10
  and (select version from public.active_list_expenses
       where id=(select value_id from split_test_values where label='historical-beneficiary-expense'))=2
  and (select pg_catalog.count(*) from realtime.messages)=
      (select version from split_test_values where label='beneficiary-role-failure-realtime'),
  'failed historical role switch changes no rows, versions, or invalidations'
);

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select is(
  (public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000001',
    (select value_id from split_test_values where label='historical-beneficiary-expense'),
    'Historical beneficiary removed',130,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],10,2)
    #>>'{settings,version}')::bigint,
  11::bigint,
  'editing may remove a historical beneficiary without deleting its identity'
);
select ok(
  exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      public.get_active_list_split('72000000-0000-4000-8000-000000000001')->'participants'
    ) as participant(document)
    where participant.document->>'id'=
      (select value_id::text from split_test_values where label='history-participant')
      and not (participant.document->>'is_current')::boolean
  ),
  'creator-only removed identity remains in the projection for exposed actor IDs'
);
select is(
  (public.delete_active_list_expense(
    '72000000-0000-4000-8000-000000000001',
    (select value_id from split_test_values where label='remainder-expense'),11,1)
    #>>'{settings,version}')::bigint,
  12::bigint,
  'successful expense deletion recalculates the aggregate and increments once'
);
select ok(
  pg_catalog.jsonb_array_length(
    public.get_active_list_split('72000000-0000-4000-8000-000000000001')->'expenses'
  )=4
  and (
    select pg_catalog.sum((participant->>'balance_minor')::bigint)
    from pg_catalog.jsonb_array_elements(
      public.get_active_list_split('72000000-0000-4000-8000-000000000001')->'participants'
    ) as participant
  )=0,
  'successful deletion removes exactly one expense and preserves zero-sum balances'
);
reset role;

update public.profiles set display_name='Latest Historical Name'
where id='71000000-0000-4000-8000-000000000003';
select is(
  (select display_name_snapshot from public.active_list_split_participants
   where list_id='72000000-0000-4000-8000-000000000001'
     and profile_id='71000000-0000-4000-8000-000000000003'),
  'Latest Historical Name',
  'profile display-name changes refresh the live financial snapshot'
);
update public.active_list_participants set state='member',version=version+1,state_changed_at=now()
where list_id='72000000-0000-4000-8000-000000000001'
  and participant_profile_id='71000000-0000-4000-8000-000000000003';
select is(
  (select id from public.active_list_split_participants
   where list_id='72000000-0000-4000-8000-000000000001'
     and profile_id='71000000-0000-4000-8000-000000000003'),
  (select value_id from split_test_values where label='history-participant'),
  'reaccepting the same account reuses its persistent financial identity'
);

delete from auth.users where id='71000000-0000-4000-8000-000000000003';
select ok(
  exists(
    select 1 from public.active_list_split_participants
    where id=(select value_id from split_test_values where label='history-participant')
      and profile_id is null and username_snapshot is null and display_name_snapshot is null
  ),
  'member account deletion anonymizes profile link and both snapshots without deleting identity'
);

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select ok(
  exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      public.get_active_list_split('72000000-0000-4000-8000-000000000001')->'participants'
    ) as participant(document)
    where participant.document->>'id'=
      (select value_id::text from split_test_values where label='history-participant')
      and (participant.document->>'is_anonymized')::boolean
      and participant.document->'profile_id'='null'::jsonb
      and participant.document->'username'='null'::jsonb
      and participant.document->'display_name'='null'::jsonb
  ),
  'account deletion keeps actor-only arithmetic identity while clearing every identity snapshot'
);
select ok(
  public.export_own_account_data()->>'schema_version'='6'
  and exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      public.export_own_account_data()->'active_lists'
    ) as exported_list(document)
    where exported_list.document->>'id'='72000000-0000-4000-8000-000000000001'
      and exported_list.document #> '{split,settings}' is not null
  ),
  'schema-version-six owner export nests Split in fully exported owned lists'
);
select ok(
  exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      public.export_own_account_data()->'active_lists'
    ) as exported_list(document)
    where exported_list.document->>'id'='72000000-0000-4000-8000-000000000001'
      and (
        select pg_catalog.array_agg(key order by key)
        from pg_catalog.jsonb_object_keys(exported_list.document->'split') as key
      ) = array['expenses','participants','settings','settlements']
      and not exists (
        select 1
        from pg_catalog.jsonb_array_elements(
          exported_list.document #> '{split,participants}'
        ) as participant(document)
        where (
          select pg_catalog.array_agg(key order by key)
          from pg_catalog.jsonb_object_keys(participant.document) as key
        ) <> array['display_name','id','is_anonymized','is_current','profile_id','username']
      )
      and exported_list.document #> '{split,settlements}' = '[]'::jsonb
      and not exists (
        select 1
        from pg_catalog.jsonb_array_elements(
          exported_list.document #> '{split,expenses}'
        ) as expense(document)
        where (
          select pg_catalog.array_agg(key order by key)
          from pg_catalog.jsonb_object_keys(expense.document) as key
        ) <> array[
          'amount_minor','beneficiary_participant_ids','created_at','creator_participant_id',
          'description','id','last_editor_participant_id','payer_participant_id','shares',
          'updated_at','version'
        ]
          or exists (
            select 1
            from pg_catalog.jsonb_array_elements(expense.document->'shares') as share(document)
            where (
              select pg_catalog.array_agg(key order by key)
              from pg_catalog.jsonb_object_keys(share.document) as key
            ) <> array['amount_minor','participant_id']
          )
      )
  ),
  'export uses the documented Split allowlists and excludes derived balances and request IDs'
);
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000002';
select ok(
  not (public.export_own_account_data()->'active_lists' @> '[{"id":"72000000-0000-4000-8000-000000000001"}]'::jsonb),
  'accepted member export does not leak another owner list or Split contents'
);
reset role;

update public.active_lists set status='archived',archived_at=now(),version=version+1,updated_at=now()
where id='72000000-0000-4000-8000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select ok(
  public.get_active_list_split('72000000-0000-4000-8000-000000000001') @>
    '{"list_status":"archived","enabled":true,"writable":false}'::jsonb,
  'archived list retains readable Split history and balances'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000001','Archived',1,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],
    '73000000-0000-4000-8000-000000000080',12)$$,
  '55000','archived list is read only','archived list rejects expense mutation'
);
reset role;

update public.active_lists set status='active',archived_at=null,version=version+1,updated_at=now()
where id='72000000-0000-4000-8000-000000000001';
insert into split_test_values(label,version) values
  ('stale-failure-realtime',(select pg_catalog.count(*) from realtime.messages)),
  ('stale-failure-expenses',(select pg_catalog.count(*) from public.active_list_expenses
    where list_id='72000000-0000-4000-8000-000000000001'));
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000001',
    (select value_id from split_test_values where label='expense-a'),'Stale edit',6001,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],11,1)$$,
  '40001','expense changed','stale concurrent expense edit is rejected without overwrite'
);
select throws_ok(
  $$select public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000001',gen_random_uuid(),'Gone',1,
    (select value_id from split_test_values where label='owner-participant'),
    array[(select value_id from split_test_values where label='owner-participant')],12,1)$$,
  '40001','expense changed','missing remote-edited expense is a stale conflict, not list unavailability'
);
select throws_ok(
  $$select public.delete_active_list_expense(
    '72000000-0000-4000-8000-000000000001',gen_random_uuid(),12,1)$$,
  '40001','expense changed','missing remote-deleted expense is a stale conflict'
);
reset role;
select ok(
  (select version from public.active_list_split_settings
   where list_id='72000000-0000-4000-8000-000000000001')=12
  and (select pg_catalog.count(*) from public.active_list_expenses
       where list_id='72000000-0000-4000-8000-000000000001')=
      (select version from split_test_values where label='stale-failure-expenses')
  and (select pg_catalog.count(*) from realtime.messages)=
      (select version from split_test_values where label='stale-failure-realtime'),
  'stale missing-expense failures change no rows, versions, or invalidations'
);

select throws_ok(
  $test$do $body$
  begin
    insert into public.active_list_expenses(
      id,list_id,description,amount_minor,payer_participant_id,
      creator_participant_id,last_editor_participant_id,creation_request_id
    ) values (
      '77000000-0000-4000-8000-000000000001',
      '72000000-0000-4000-8000-000000000001','Incomplete privileged write',4,
      (select value_id from split_test_values where label='owner-participant'),
      (select value_id from split_test_values where label='owner-participant'),
      (select value_id from split_test_values where label='owner-participant'),
      '77000000-0000-4000-8000-000000000011'
    );
    set constraints all immediate;
  end
  $body$$test$,
  '23514','expense shares must exactly equal the expense amount',
  'deferred integrity trigger rejects a privileged expense without shares'
);
select throws_ok(
  $test$do $body$
  begin
    insert into public.active_list_expenses(
      id,list_id,description,amount_minor,payer_participant_id,
      creator_participant_id,last_editor_participant_id,creation_request_id
    ) values (
      '77000000-0000-4000-8000-000000000002',
      '72000000-0000-4000-8000-000000000001','Wrong privileged sum',4,
      (select value_id from split_test_values where label='owner-participant'),
      (select value_id from split_test_values where label='owner-participant'),
      (select value_id from split_test_values where label='owner-participant'),
      '77000000-0000-4000-8000-000000000012'
    );
    insert into public.active_list_expense_shares(
      list_id,expense_id,participant_id,amount_minor
    ) values (
      '72000000-0000-4000-8000-000000000001',
      '77000000-0000-4000-8000-000000000002',
      (select value_id from split_test_values where label='owner-participant'),3
    );
    set constraints all immediate;
  end
  $body$$test$,
  '23514','expense shares must exactly equal the expense amount',
  'deferred integrity trigger rejects a privileged wrong-sum allocation'
);

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.enable_active_list_split(
    '72000000-0000-4000-8000-000000000004','CHF',1)$$,
  'wide historical-beneficiary fixture Split is enabled'
);
reset role;
insert into split_test_values(label,value_id)
select 'wide-owner-participant',id
from public.active_list_split_participants
where list_id='72000000-0000-4000-8000-000000000004';
insert into public.active_list_split_participants(id,list_id)
select
  ('78000000-0000-4000-8000-'||pg_catalog.lpad(series.value::text,12,'0'))::uuid,
  '72000000-0000-4000-8000-000000000004'
from pg_catalog.generate_series(1,22) as series(value);
insert into public.active_list_expenses(
  id,list_id,description,amount_minor,payer_participant_id,
  creator_participant_id,last_editor_participant_id,creation_request_id
) values (
  '78100000-0000-4000-8000-000000000001',
  '72000000-0000-4000-8000-000000000004',
  'Accumulated historical group',2100,
  (select value_id from split_test_values where label='wide-owner-participant'),
  (select value_id from split_test_values where label='wide-owner-participant'),
  (select value_id from split_test_values where label='wide-owner-participant'),
  '78200000-0000-4000-8000-000000000001'
);
insert into public.active_list_expense_shares(
  list_id,expense_id,participant_id,amount_minor
)
select
  '72000000-0000-4000-8000-000000000004',
  '78100000-0000-4000-8000-000000000001',
  ('78000000-0000-4000-8000-'||pg_catalog.lpad(series.value::text,12,'0'))::uuid,
  100
from pg_catalog.generate_series(1,21) as series(value);
set constraints all immediate;
set constraints all deferred;

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select is(
  (public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000004',
    '78100000-0000-4000-8000-000000000001',
    'Accumulated historical group plus owner',2200,
    (select value_id from split_test_values where label='wide-owner-participant'),
    array(
      select ('78000000-0000-4000-8000-'||pg_catalog.lpad(series.value::text,12,'0'))::uuid
      from pg_catalog.generate_series(1,21) as series(value)
    ) || array[(select value_id from split_test_values where label='wide-owner-participant')],
    1,1
  )#>>'{settings,version}')::bigint,
  2::bigint,
  'edit retains more than twenty historical beneficiaries and adds one current eligible identity'
);
reset role;
select ok(
  (
    select pg_catalog.count(*)=22
      and pg_catalog.min(amount_minor)=100
      and pg_catalog.max(amount_minor)=100
      and pg_catalog.sum(amount_minor)=2200
    from public.active_list_expense_shares
    where expense_id='78100000-0000-4000-8000-000000000001'
  ),
  'wide historical edit recalculates all twenty-two exact shares without loss or truncation'
);

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.update_active_list_expense(
    '72000000-0000-4000-8000-000000000004',
    '78100000-0000-4000-8000-000000000001',
    'Invalid historical expansion',2300,
    (select value_id from split_test_values where label='wide-owner-participant'),
    array(
      select ('78000000-0000-4000-8000-'||pg_catalog.lpad(series.value::text,12,'0'))::uuid
      from pg_catalog.generate_series(1,22) as series(value)
    ) || array[(select value_id from split_test_values where label='wide-owner-participant')],
    2,2
  )$$,
  '22023','expense participant unavailable',
  'edit cannot expand a removed historical identity into a new role'
);
reset role;
select ok(
  (select version from public.active_list_split_settings
   where list_id='72000000-0000-4000-8000-000000000004')=2
  and (select version from public.active_list_expenses
       where id='78100000-0000-4000-8000-000000000001')=2
  and (select pg_catalog.count(*) from public.active_list_expense_shares
       where expense_id='78100000-0000-4000-8000-000000000001')=22,
  'rejected historical role expansion leaves aggregate, expense, and shares unchanged'
);

set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.enable_active_list_split('72000000-0000-4000-8000-000000000003','CHF',1)$$,
  'capacity fixture Split is enabled'
);
reset role;
insert into split_test_values(label,value_id)
select 'capacity-participant',id
from public.active_list_split_participants
where list_id='72000000-0000-4000-8000-000000000003';
insert into public.active_list_expenses(
  id,list_id,description,amount_minor,payer_participant_id,
  creator_participant_id,last_editor_participant_id,creation_request_id
)
select
  ('74000000-0000-4000-8000-'||pg_catalog.lpad(series.value::text,12,'0'))::uuid,
  '72000000-0000-4000-8000-000000000003',
  'Capacity '||series.value,
  1,
  split_participant.id,
  split_participant.id,
  split_participant.id,
  ('75000000-0000-4000-8000-'||pg_catalog.lpad(series.value::text,12,'0'))::uuid
from pg_catalog.generate_series(1,199) as series(value)
cross join lateral (
  select id from public.active_list_split_participants
  where list_id='72000000-0000-4000-8000-000000000003'
) as split_participant;
insert into public.active_list_expense_shares(list_id,expense_id,participant_id,amount_minor)
select expense_record.list_id,expense_record.id,expense_record.payer_participant_id,1
from public.active_list_expenses as expense_record
where expense_record.list_id='72000000-0000-4000-8000-000000000003';
set constraints all immediate;
set constraints all deferred;
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select is(
  (public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000003','Two hundred',1,
    (select value_id from split_test_values where label='capacity-participant'),
    array[(select value_id from split_test_values where label='capacity-participant')],
    '76000000-0000-4000-8000-000000000000',1)#>>'{settings,version}')::bigint,
  2::bigint,
  'two-hundredth expense succeeds through the reviewed RPC'
);
reset role;
insert into split_test_values(label,version) values
  ('capacity-failure-realtime',(select pg_catalog.count(*) from realtime.messages));
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000003','Serialized concurrent loser',1,
    (select value_id from split_test_values where label='capacity-participant'),
    array[(select value_id from split_test_values where label='capacity-participant')],
    '76000000-0000-4000-8000-000000000003',1)$$,
  '40001','split changed','serialized concurrent create observes the aggregate version change'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000003','Two hundred one',1,
    (select value_id from split_test_values where label='capacity-participant'),
    array[(select value_id from split_test_values where label='capacity-participant')],
    '76000000-0000-4000-8000-000000000001',2)$$,
  '54000','expense capacity reached','two-hundred-first current expense is rejected'
);
reset role;
select ok(
  (select version from public.active_list_split_settings
   where list_id='72000000-0000-4000-8000-000000000003')=2
  and (select pg_catalog.count(*) from public.active_list_expenses
       where list_id='72000000-0000-4000-8000-000000000003')=200
  and (select pg_catalog.count(*) from realtime.messages)=
      (select version from split_test_values where label='capacity-failure-realtime'),
  'stale and over-capacity creates add no row, version increment, or invalidation'
);
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select is(
  (public.delete_active_list_expense(
    '72000000-0000-4000-8000-000000000003',
    '74000000-0000-4000-8000-000000000001',2,1)#>>'{settings,version}')::bigint,
  3::bigint,
  'deleting an expense frees one capacity slot'
);
select is(
  pg_catalog.jsonb_array_length(public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000003','Replacement two hundred',1,
    (select value_id from split_test_values where label='capacity-participant'),
    array[(select value_id from split_test_values where label='capacity-participant')],
    '76000000-0000-4000-8000-000000000002',3)->'expenses'),
  200,
  'the freed slot accepts one replacement without exceeding capacity'
);
reset role;

select is(
  (select pg_catalog.count(*) from public.user_notifications),
  0::bigint,
  'Split operations create no persistent notification or badge mutation'
);
select ok(
  (select pg_catalog.count(*) from realtime.messages where topic='account:71000000-0000-4000-8000-000000000001') > 0
  and not exists(
    select 1 from realtime.messages
    where payload - 'id' <> '{"v":1}'::jsonb or event <> 'invalidate' or not private
  ),
  'successful Split aggregate changes use only the existing opaque private invalidation contract'
);

delete from public.active_lists where id='72000000-0000-4000-8000-000000000003';
set local role authenticated;
set local "request.jwt.claim.sub"='71000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.get_active_list_split('72000000-0000-4000-8000-000000000003')$$,
  'P0002','list unavailable','stale read after list deletion is rejected safely'
);
select throws_ok(
  $$select public.create_active_list_expense(
    '72000000-0000-4000-8000-000000000003','Deleted list',1,
    (select value_id from split_test_values where label='capacity-participant'),
    array[(select value_id from split_test_values where label='capacity-participant')],
    '76000000-0000-4000-8000-000000000004',4)$$,
  'P0002','list unavailable','stale mutation after list deletion creates nothing'
);
reset role;
select ok(
  not exists(select 1 from public.active_list_split_settings where list_id='72000000-0000-4000-8000-000000000003')
  and not exists(select 1 from public.active_list_split_participants where list_id='72000000-0000-4000-8000-000000000003')
  and not exists(select 1 from public.active_list_expenses where list_id='72000000-0000-4000-8000-000000000003')
  and not exists(select 1 from public.active_list_expense_shares where list_id='72000000-0000-4000-8000-000000000003'),
  'list deletion cascades the complete settings-rooted Split aggregate'
);

select * from finish();
rollback;
