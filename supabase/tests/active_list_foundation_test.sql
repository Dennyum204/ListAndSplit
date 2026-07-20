begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_table('public', 'active_lists', 'active lists table exists');
select has_table(
  'public',
  'active_list_items',
  'active list items table exists'
);

select columns_are(
  'public',
  'active_lists',
  array[
    'id',
    'owner_id',
    'title',
    'status',
    'version',
    'creation_request_id',
    'created_at',
    'updated_at',
    'archived_at'
  ],
  'active lists have only the reviewed columns'
);

select columns_are(
  'public',
  'active_list_items',
  array[
    'id',
    'list_id',
    'name',
    'quantity_thousandths',
    'unit_code',
    'position',
    'version',
    'creation_request_id',
    'completed_at',
    'completed_by',
    'created_at',
    'updated_at'
  ],
  'active list items have only the reviewed columns'
);

select ok(
  (
    select list_class.relrowsecurity and list_class.relforcerowsecurity
    from pg_catalog.pg_class as list_class
    where list_class.oid = 'public.active_lists'::regclass
  )
  and (
    select item_class.relrowsecurity and item_class.relforcerowsecurity
    from pg_catalog.pg_class as item_class
    where item_class.oid = 'public.active_list_items'::regclass
  ),
  'both list tables enable and force RLS'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in ('active_lists', 'active_list_items')
      and policyname in (
        'active_lists_reject_direct_client_access',
        'active_list_items_reject_direct_client_access'
      )
      and cmd = 'ALL'
      and roles = array['anon', 'authenticated']::name[]
      and qual = 'false'
      and with_check = 'false'
  ),
  2::bigint,
  'both tables explicitly reject all direct anon and authenticated operations'
);

select ok(
  not has_table_privilege(
    'anon',
    'public.active_lists',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.active_lists',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.active_lists',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'anon',
    'public.active_list_items',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.active_list_items',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.active_list_items',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'Data API roles have no direct list or item CRUD privileges'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint
    where conrelid in (
      'public.active_lists'::regclass,
      'public.active_list_items'::regclass
    )
      and conname in (
        'active_lists_owner_fkey',
        'active_lists_title_check',
        'active_lists_status_check',
        'active_lists_positive_version_check',
        'active_lists_archive_state_check',
        'active_lists_owner_creation_request_key',
        'active_list_items_list_fkey',
        'active_list_items_completed_by_fkey',
        'active_list_items_name_check',
        'active_list_items_quantity_check',
        'active_list_items_unit_check',
        'active_list_items_position_check',
        'active_list_items_positive_version_check',
        'active_list_items_completion_check',
        'active_list_items_list_creation_request_key',
        'active_list_items_list_position_key'
      )
  ),
  16::bigint,
  'all reviewed list and item constraints exist'
);

select ok(
  (
    select confdeltype = 'c'
    from pg_catalog.pg_constraint
    where conname = 'active_lists_owner_fkey'
  )
  and (
    select confdeltype = 'c'
    from pg_catalog.pg_constraint
    where conname = 'active_list_items_list_fkey'
  )
  and (
    select confdeltype = 'n'
    from pg_catalog.pg_constraint
    where conname = 'active_list_items_completed_by_fkey'
  ),
  'owner and list cascade while a deleted completion actor is set null'
);

select is(
  (
    select pg_catalog.array_agg(indexname order by indexname)
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename in ('active_lists', 'active_list_items')
      and indexname in (
        'active_lists_owner_status_updated_idx',
        'active_lists_owner_archived_idx',
        'active_list_items_completed_by_idx',
        'active_lists_owner_creation_request_key',
        'active_list_items_list_creation_request_key',
        'active_list_items_list_position_key'
      )
  ),
  array[
    'active_list_items_completed_by_idx',
    'active_list_items_list_creation_request_key',
    'active_list_items_list_position_key',
    'active_lists_owner_archived_idx',
    'active_lists_owner_creation_request_key',
    'active_lists_owner_status_updated_idx'
  ]::name[],
  'the aggregate has the exact relationship and query indexes under test'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc
    where oid in (
      'public.list_active_lists(text,integer,timestamptz,uuid)'::regprocedure,
      'public.get_active_list(uuid)'::regprocedure,
      'public.list_active_list_items(uuid)'::regprocedure,
      'public.create_active_list(text,uuid)'::regprocedure,
      'public.rename_active_list(uuid,text,bigint)'::regprocedure,
      'public.set_active_list_archived(uuid,boolean,bigint)'::regprocedure,
      'public.delete_active_list(uuid,bigint)'::regprocedure,
      'public.create_active_list_item(uuid,text,uuid,bigint,bigint,text)'::regprocedure,
      'public.update_active_list_item(uuid,uuid,text,bigint,text,bigint,bigint)'::regprocedure,
      'public.set_active_list_item_completed(uuid,uuid,boolean,bigint,bigint)'::regprocedure,
      'public.delete_active_list_item(uuid,uuid,bigint,bigint)'::regprocedure,
      'public.reorder_active_list_items(uuid,uuid[],bigint)'::regprocedure
    )
      and prosecdef
      and proconfig @> array['search_path=""']
      and proowner = 'postgres'::regrole
  ),
  12::bigint,
  'all twelve public list RPCs are postgres-owned hardened definer boundaries'
);

select ok(
  (
    select pg_catalog.bool_and(
      has_function_privilege('authenticated', procedure_oid, 'EXECUTE')
      and not has_function_privilege('anon', procedure_oid, 'EXECUTE')
      and not has_function_privilege('service_role', procedure_oid, 'EXECUTE')
    )
    from pg_catalog.unnest(array[
      'public.list_active_lists(text,integer,timestamptz,uuid)'::regprocedure,
      'public.get_active_list(uuid)'::regprocedure,
      'public.list_active_list_items(uuid)'::regprocedure,
      'public.create_active_list(text,uuid)'::regprocedure,
      'public.rename_active_list(uuid,text,bigint)'::regprocedure,
      'public.set_active_list_archived(uuid,boolean,bigint)'::regprocedure,
      'public.delete_active_list(uuid,bigint)'::regprocedure,
      'public.create_active_list_item(uuid,text,uuid,bigint,bigint,text)'::regprocedure,
      'public.update_active_list_item(uuid,uuid,text,bigint,text,bigint,bigint)'::regprocedure,
      'public.set_active_list_item_completed(uuid,uuid,boolean,bigint,bigint)'::regprocedure,
      'public.delete_active_list_item(uuid,uuid,bigint,bigint)'::regprocedure,
      'public.reorder_active_list_items(uuid,uuid[],bigint)'::regprocedure
    ]) as procedures(procedure_oid)
  ),
  'only authenticated can execute each exact list RPC signature'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc as procedure_record
    cross join lateral pg_catalog.aclexplode(procedure_record.proacl)
      as privilege_record
    where procedure_record.oid in (
      'public.list_active_lists(text,integer,timestamptz,uuid)'::regprocedure,
      'public.get_active_list(uuid)'::regprocedure,
      'public.list_active_list_items(uuid)'::regprocedure,
      'public.create_active_list(text,uuid)'::regprocedure,
      'public.rename_active_list(uuid,text,bigint)'::regprocedure,
      'public.set_active_list_archived(uuid,boolean,bigint)'::regprocedure,
      'public.delete_active_list(uuid,bigint)'::regprocedure,
      'public.create_active_list_item(uuid,text,uuid,bigint,bigint,text)'::regprocedure,
      'public.update_active_list_item(uuid,uuid,text,bigint,text,bigint,bigint)'::regprocedure,
      'public.set_active_list_item_completed(uuid,uuid,boolean,bigint,bigint)'::regprocedure,
      'public.delete_active_list_item(uuid,uuid,bigint,bigint)'::regprocedure,
      'public.reorder_active_list_items(uuid,uuid[],bigint)'::regprocedure
    )
      and privilege_record.grantee = 0
      and privilege_record.privilege_type = 'EXECUTE'
  ),
  'PUBLIC execution is revoked from every list RPC'
);

set local role anon;

select throws_like(
  $$select * from public.active_lists$$,
  '%permission denied%active_lists%',
  'anonymous direct list select is denied'
);
select throws_like(
  $$insert into public.active_lists (owner_id, title, creation_request_id) values ('11111111-1111-4111-8111-111111111111', 'No', '10000000-0000-4000-8000-000000000001')$$,
  '%permission denied%active_lists%',
  'anonymous direct list insert is denied'
);
select throws_like(
  $$update public.active_lists set title = 'No'$$,
  '%permission denied%active_lists%',
  'anonymous direct list update is denied'
);
select throws_like(
  $$delete from public.active_lists$$,
  '%permission denied%active_lists%',
  'anonymous direct list delete is denied'
);
select throws_like(
  $$select * from public.active_list_items$$,
  '%permission denied%active_list_items%',
  'anonymous direct item select is denied'
);
select throws_like(
  $$select * from public.list_active_lists('active')$$,
  '%permission denied%function%list_active_lists%',
  'anonymous list RPC execution is denied'
);

reset role;

insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('11111111-1111-4111-8111-111111111111', 'owner@example.test', now(), now(), now()),
  ('22222222-2222-4222-8222-222222222222', 'other@example.test', now(), now(), now()),
  ('33333333-3333-4333-8333-333333333333', 'unverified@example.test', null, now(), now()),
  ('44444444-4444-4444-8444-444444444444', 'incomplete@example.test', now(), now(), now()),
  ('55555555-5555-4555-8555-555555555555', 'actor@example.test', now(), now(), now());

update public.profiles
set username = case id
      when '11111111-1111-4111-8111-111111111111' then 'list_owner'
      when '22222222-2222-4222-8222-222222222222' then 'other_owner'
      when '33333333-3333-4333-8333-333333333333' then 'unverified_owner'
      when '55555555-5555-4555-8555-555555555555' then 'future_actor'
    end,
    display_name = case id
      when '11111111-1111-4111-8111-111111111111' then 'List Owner'
      when '22222222-2222-4222-8222-222222222222' then 'Other Owner'
      when '33333333-3333-4333-8333-333333333333' then 'Unverified Owner'
      when '55555555-5555-4555-8555-555555555555' then 'Future Actor'
    end
where id <> '44444444-4444-4444-8444-444444444444';

set local role authenticated;
set local "request.jwt.claim.sub" = '';

select throws_ok(
  $$select * from public.list_active_lists('active')$$,
  '42501',
  'verified profile required',
  'an authenticated role without identity is denied'
);

set local "request.jwt.claim.sub" = '33333333-3333-4333-8333-333333333333';

select throws_ok(
  $$select * from public.create_active_list('No', '10000000-0000-4000-8000-000000000001')$$,
  '42501',
  'verified profile required',
  'an unverified user is denied'
);

set local "request.jwt.claim.sub" = '44444444-4444-4444-8444-444444444444';

select throws_ok(
  $$select * from public.create_active_list('No', '10000000-0000-4000-8000-000000000002')$$,
  '42501',
  'verified profile required',
  'an incomplete profile is denied'
);

select throws_like(
  $$select * from public.active_lists$$,
  '%permission denied%active_lists%',
  'authenticated direct list select is denied'
);
select throws_like(
  $$insert into public.active_list_items (list_id, name, position, creation_request_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'No', 1, '10000000-0000-4000-8000-000000000003')$$,
  '%permission denied%active_list_items%',
  'authenticated direct item insert is denied'
);
select throws_like(
  $$update public.active_list_items set name = 'No'$$,
  '%permission denied%active_list_items%',
  'authenticated direct item update is denied'
);
select throws_like(
  $$delete from public.active_list_items$$,
  '%permission denied%active_list_items%',
  'authenticated direct item delete is denied'
);

reset role;
set local role service_role;

select throws_like(
  $$select * from public.active_lists$$,
  '%permission denied%active_lists%',
  'service role direct list access remains revoked'
);

reset role;

create temporary table active_list_test_values (
  label text primary key,
  list_id uuid,
  item_id uuid,
  list_version bigint,
  item_version bigint,
  created_at timestamptz,
  updated_at timestamptz
) on commit drop;

grant select, insert, update on active_list_test_values to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

insert into active_list_test_values (
  label,
  list_id,
  list_version,
  created_at,
  updated_at
)
select
  'primary',
  created.list_id,
  created.version,
  created.created_at,
  created.updated_at
from public.create_active_list(
  '  Groceries  ',
  '10000000-0000-4000-8000-000000000011'
) as created;

select ok(
  (
    select detail.title = 'Groceries'
      and detail.status = 'active'
      and detail.version = 1
      and detail.item_count = 0
      and detail.completed_item_count = 0
    from public.get_active_list(
      (select list_id from active_list_test_values where label = 'primary')
    ) as detail
  ),
  'list creation trims the title and returns an active version-one empty list'
);

select is(
  (
    select pg_catalog.count(*)
    from public.create_active_list(
      'Groceries',
      '10000000-0000-4000-8000-000000000011'
    ) as retried
    where retried.version = 1
      and retried.created_at = (
        select created_at
        from active_list_test_values
        where label = 'primary'
      )
      and retried.updated_at = (
        select updated_at
        from active_list_test_values
        where label = 'primary'
      )
  ),
  1::bigint,
  'same-payload list creation retry returns the original row without changes'
);

select throws_ok(
  $$select * from public.create_active_list('Different', '10000000-0000-4000-8000-000000000011')$$,
  '23505',
  'list creation request conflict',
  'conflicting list creation idempotency payload is rejected'
);

insert into active_list_test_values (label, list_id, list_version)
select 'duplicate-title', created.list_id, created.version
from public.create_active_list(
  'Groceries',
  '10000000-0000-4000-8000-000000000012'
) as created;

select is(
  (
    select pg_catalog.count(*)
    from public.list_active_lists('active', 50)
    where title = 'Groceries'
  ),
  2::bigint,
  'duplicate list titles are allowed'
);

select throws_ok(
  $$select * from public.create_active_list('   ', '10000000-0000-4000-8000-000000000013')$$,
  '22023',
  'invalid list creation',
  'blank list titles are rejected'
);

select throws_ok(
  $$select * from public.create_active_list(repeat('x', 81), '10000000-0000-4000-8000-000000000014')$$,
  '22023',
  'invalid list creation',
  'overlong list titles are rejected'
);

insert into active_list_test_values (label, list_id, list_version)
select 'page-three', created.list_id, created.version
from public.create_active_list(
  'Third',
  '10000000-0000-4000-8000-000000000015'
) as created;

reset role;

update public.active_lists
set updated_at = '2026-01-01 00:00:00+00'::timestamptz
where owner_id = '11111111-1111-4111-8111-111111111111';

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select is(
  (select pg_catalog.count(*) from public.list_active_lists('active', 2)),
  2::bigint,
  'active list page size is enforced'
);

select is(
  (
    with first_page as (
      select * from public.list_active_lists('active', 2)
    ), cursor_row as (
      select *
      from first_page
      order by updated_at, list_id
      limit 1
    )
    select pg_catalog.count(*)
    from cursor_row
    cross join lateral public.list_active_lists(
      'active',
      2,
      cursor_row.updated_at,
      cursor_row.list_id
    ) as next_page
    where not exists (
      select 1
      from first_page
      where first_page.list_id = next_page.list_id
    )
  ),
  1::bigint,
  'active keyset pagination uses the deterministic ID tie breaker without overlap'
);

select throws_ok(
  $$select * from public.list_active_lists('active', 51)$$,
  '22023',
  'invalid list page size',
  'unbounded list page requests are rejected'
);

select throws_ok(
  $$select * from public.list_active_lists('other')$$,
  '22023',
  'invalid list status',
  'unknown list statuses are rejected'
);

with target as (
  select list_id
  from active_list_test_values
  where label = 'primary'
), renamed as (
  select rename_result.*
  from target
  cross join lateral public.rename_active_list(
    target.list_id,
    '  Weekly groceries ',
    1
  ) as rename_result
)
update active_list_test_values as saved
set list_version = renamed.version,
    updated_at = renamed.updated_at
from renamed
where saved.label = 'primary';

select ok(
  (
    select title = 'Weekly groceries' and version = 2
    from public.get_active_list(
      (select list_id from active_list_test_values where label = 'primary')
    )
  ),
  'rename trims the title and increments list version once'
);

select is(
  (
    select renamed.version
    from public.rename_active_list(
      (select list_id from active_list_test_values where label = 'primary'),
      'Weekly groceries',
      1
    ) as renamed
  ),
  2::bigint,
  'completed rename retry is a no-op at the immediately prior version'
);

select throws_ok(
  format(
    $$select * from public.rename_active_list(%L, 'Stale overwrite', 1)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '40001',
  'list changed',
  'stale rename cannot overwrite newer list state'
);

insert into active_list_test_values (
  label,
  list_id,
  item_id,
  list_version,
  item_version,
  created_at,
  updated_at
)
select
  'item-one',
  (select list_id from active_list_test_values where label = 'primary'),
  created.item_id,
  created.list_version,
  created.version,
  created.created_at,
  created.updated_at
from public.create_active_list_item(
  (select list_id from active_list_test_values where label = 'primary'),
  '  Milk  ',
  '20000000-0000-4000-8000-000000000001',
  2
) as created;

select ok(
  (
    select name = 'Milk'
      and quantity_thousandths = 1000
      and unit_code is null
      and "position" = 1
      and version = 1
      and list_version = 3
    from public.create_active_list_item(
      (select list_id from active_list_test_values where label = 'primary'),
      'Milk',
      '20000000-0000-4000-8000-000000000001',
      2
    )
  ),
  'item creation trims name, defaults to one, appends first, and retries safely'
);

select throws_ok(
  format(
    $$select * from public.create_active_list_item(%L, 'Changed', '20000000-0000-4000-8000-000000000001', 3)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '23505',
  'list item creation request conflict',
  'conflicting item creation idempotency payload is rejected'
);

insert into active_list_test_values (
  label,
  list_id,
  item_id,
  list_version,
  item_version
)
select
  'item-two',
  (select list_id from active_list_test_values where label = 'primary'),
  created.item_id,
  created.list_version,
  created.version
from public.create_active_list_item(
  (select list_id from active_list_test_values where label = 'primary'),
  'Milk',
  '20000000-0000-4000-8000-000000000002',
  3,
  1,
  'kg'
) as created;

select ok(
  (
    select name = 'Milk'
      and quantity_thousandths = 1
      and unit_code = 'kg'
      and "position" = 2
    from public.list_active_list_items(
      (select list_id from active_list_test_values where label = 'primary')
    )
    where item_id = (
      select item_id from active_list_test_values where label = 'item-two'
    )
  )
  and (
    select version = 4
    from public.get_active_list(
      (select list_id from active_list_test_values where label = 'primary')
    )
  ),
  'duplicate item names, minimum quantity, stable unit, and creation order work'
);

select throws_ok(
  format(
    $$select * from public.create_active_list_item(%L, 'Zero', '20000000-0000-4000-8000-000000000003', 4, 0, null)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '22023',
  'invalid list item creation',
  'zero quantity is rejected'
);

select throws_ok(
  format(
    $$select * from public.create_active_list_item(%L, 'Negative', '20000000-0000-4000-8000-000000000004', 4, -1, null)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '22023',
  'invalid list item creation',
  'negative quantity is rejected'
);

select throws_ok(
  format(
    $$select * from public.create_active_list_item(%L, 'Overflow', '20000000-0000-4000-8000-000000000005', 4, 1000000000, null)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '22023',
  'invalid list item creation',
  'overflow quantity is rejected'
);

select throws_ok(
  format(
    $$select * from public.create_active_list_item(%L, 'Unknown unit', '20000000-0000-4000-8000-000000000006', 4, 1000, 'each')$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '22023',
  'invalid list item creation',
  'unknown unit code is rejected'
);

select throws_ok(
  format(
    $$select * from public.create_active_list_item(%L, repeat('x', 121), '20000000-0000-4000-8000-000000000007', 4)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '22023',
  'invalid list item creation',
  'overlong item name is rejected'
);

with target as (
  select list_id, item_id
  from active_list_test_values
  where label = 'item-one'
), updated as (
  select update_result.*
  from target
  cross join lateral public.update_active_list_item(
    target.list_id,
    target.item_id,
    'Whole milk',
    1500,
    'bottle',
    4,
    1
  ) as update_result
)
update active_list_test_values as saved
set list_version = updated.list_version,
    item_version = updated.version,
    updated_at = updated.updated_at
from updated
where saved.label = 'item-one';

select ok(
  (
    select list_version = 5
      and version = 2
      and name = 'Whole milk'
      and quantity_thousandths = 1500
      and unit_code = 'bottle'
    from public.update_active_list_item(
      (select list_id from active_list_test_values where label = 'item-one'),
      (select item_id from active_list_test_values where label = 'item-one'),
      'Whole milk',
      1500,
      'bottle',
      4,
      1
    )
  ),
  'item edit increments list and item versions once and retries without change'
);

select throws_ok(
  format(
    $$select * from public.update_active_list_item(%L, %L, 'Stale', 1000, null, 4, 1)$$,
    (select list_id from active_list_test_values where label = 'item-one'),
    (select item_id from active_list_test_values where label = 'item-one')
  ),
  '40001',
  'list item changed',
  'stale item edits cannot overwrite current content'
);

select ok(
  (
    select list_version = 6
      and version = 3
      and completed_at is not null
      and completed_by = '11111111-1111-4111-8111-111111111111'::uuid
    from public.set_active_list_item_completed(
      (select list_id from active_list_test_values where label = 'item-one'),
      (select item_id from active_list_test_values where label = 'item-one'),
      true,
      5,
      2
    )
  ),
  'completion increments both versions with server-owned owner attribution'
);

select ok(
  (
    select list_version = 6 and version = 3
    from public.set_active_list_item_completed(
      (select list_id from active_list_test_values where label = 'item-one'),
      (select item_id from active_list_test_values where label = 'item-one'),
      true,
      5,
      2
    )
  ),
  'completed completion retry is a version/timestamp no-op'
);

select ok(
  (
    select list_version = 7
      and version = 4
      and completed_at is null
      and completed_by is null
    from public.set_active_list_item_completed(
      (select list_id from active_list_test_values where label = 'item-one'),
      (select item_id from active_list_test_values where label = 'item-one'),
      false,
      6,
      3
    )
  ),
  'reopening increments both versions and clears completion attribution'
);

select is(
  public.reorder_active_list_items(
    (select list_id from active_list_test_values where label = 'primary'),
    array[
      (select item_id from active_list_test_values where label = 'item-two'),
      (select item_id from active_list_test_values where label = 'item-one')
    ],
    7
  ),
  8::bigint,
  'valid reorder increments list version once'
);

select is(
  (
    select pg_catalog.array_agg(item_id order by "position")
    from public.list_active_list_items(
      (select list_id from active_list_test_values where label = 'primary')
    )
  ),
  array[
    (select item_id from active_list_test_values where label = 'item-two'),
    (select item_id from active_list_test_values where label = 'item-one')
  ]::uuid[],
  'reorder persists contiguous deterministic item order'
);

select is(
  public.reorder_active_list_items(
    (select list_id from active_list_test_values where label = 'primary'),
    array[
      (select item_id from active_list_test_values where label = 'item-two'),
      (select item_id from active_list_test_values where label = 'item-one')
    ],
    7
  ),
  8::bigint,
  'same reorder retry is a no-op at the immediately prior list version'
);

select throws_ok(
  format(
    $$select public.reorder_active_list_items(%L, array[%L::uuid, %L::uuid], 8)$$,
    (select list_id from active_list_test_values where label = 'primary'),
    (select item_id from active_list_test_values where label = 'item-one'),
    (select item_id from active_list_test_values where label = 'item-one')
  ),
  '22023',
  'invalid list item order',
  'duplicate reorder IDs are rejected'
);

select throws_ok(
  format(
    $$select public.reorder_active_list_items(%L, array[%L::uuid], 8)$$,
    (select list_id from active_list_test_values where label = 'primary'),
    (select item_id from active_list_test_values where label = 'item-one')
  ),
  '22023',
  'invalid list item order',
  'incomplete reorder ID sets are rejected'
);

select throws_ok(
  format(
    $$select public.reorder_active_list_items(%L, array[%L::uuid, 'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid], 8)$$,
    (select list_id from active_list_test_values where label = 'primary'),
    (select item_id from active_list_test_values where label = 'item-one')
  ),
  '22023',
  'invalid list item order',
  'foreign reorder IDs are rejected'
);

select throws_ok(
  format(
    $$select public.reorder_active_list_items(%L, array[%L::uuid, %L::uuid], 7)$$,
    (select list_id from active_list_test_values where label = 'primary'),
    (select item_id from active_list_test_values where label = 'item-one'),
    (select item_id from active_list_test_values where label = 'item-two')
  ),
  '40001',
  'list changed',
  'stale concurrent reorder cannot overwrite the committed order'
);

select ok(
  (
    select status = 'archived'
      and version = 9
      and archived_at is not null
    from public.set_active_list_archived(
      (select list_id from active_list_test_values where label = 'primary'),
      true,
      8
    )
  ),
  'archive records server time and increments list version'
);

select is(
  (
    select archived.version
    from public.set_active_list_archived(
      (select list_id from active_list_test_values where label = 'primary'),
      true,
      8
    ) as archived
  ),
  9::bigint,
  'archive retry is a no-op'
);

select ok(
  (
    select status = 'archived' and item_count = 2
    from public.get_active_list(
      (select list_id from active_list_test_values where label = 'primary')
    )
  )
  and (
    select pg_catalog.count(*) = 2
    from public.list_active_list_items(
      (select list_id from active_list_test_values where label = 'primary')
    )
  ),
  'archived list detail and items remain readable'
);

select throws_ok(
  format(
    $$select * from public.rename_active_list(%L, 'No', 9)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '55000',
  'archived list is read only',
  'archived list rename is rejected'
);
select throws_ok(
  format(
    $$select * from public.create_active_list_item(%L, 'No', '20000000-0000-4000-8000-000000000008', 9)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '55000',
  'archived list is read only',
  'archived item creation is rejected'
);
select throws_ok(
  format(
    $$select * from public.update_active_list_item(%L, %L, 'No', 1000, null, 9, 4)$$,
    (select list_id from active_list_test_values where label = 'primary'),
    (select item_id from active_list_test_values where label = 'item-one')
  ),
  '55000',
  'archived list is read only',
  'archived item edit is rejected'
);
select throws_ok(
  format(
    $$select * from public.set_active_list_item_completed(%L, %L, true, 9, 4)$$,
    (select list_id from active_list_test_values where label = 'primary'),
    (select item_id from active_list_test_values where label = 'item-one')
  ),
  '55000',
  'archived list is read only',
  'archived completion is rejected'
);
select throws_ok(
  format(
    $$select public.delete_active_list_item(%L, %L, 9, 4)$$,
    (select list_id from active_list_test_values where label = 'primary'),
    (select item_id from active_list_test_values where label = 'item-one')
  ),
  '55000',
  'archived list is read only',
  'archived item deletion is rejected'
);
select throws_ok(
  format(
    $$select public.reorder_active_list_items(%L, array[%L::uuid, %L::uuid], 9)$$,
    (select list_id from active_list_test_values where label = 'primary'),
    (select item_id from active_list_test_values where label = 'item-two'),
    (select item_id from active_list_test_values where label = 'item-one')
  ),
  '55000',
  'archived list is read only',
  'archived reorder is rejected'
);
select throws_ok(
  format(
    $$select public.delete_active_list(%L, 9)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '55000',
  'archived list is read only',
  'archived list deletion is rejected'
);

select ok(
  (
    select status = 'active'
      and version = 10
      and archived_at is null
    from public.set_active_list_archived(
      (select list_id from active_list_test_values where label = 'primary'),
      false,
      9
    )
  ),
  'restore returns the list to mutable active state'
);

select is(
  (
    select restored.version
    from public.set_active_list_archived(
      (select list_id from active_list_test_values where label = 'primary'),
      false,
      9
    ) as restored
  ),
  10::bigint,
  'restore retry is a no-op'
);

select is(
  public.delete_active_list_item(
    (select list_id from active_list_test_values where label = 'primary'),
    (select item_id from active_list_test_values where label = 'item-two'),
    10,
    1
  ),
  11::bigint,
  'item deletion increments list version'
);

select is(
  (
    select pg_catalog.count(*)
    from public.list_active_list_items(
      (select list_id from active_list_test_values where label = 'primary')
    )
  ),
  1::bigint,
  'item deletion removes only the requested item'
);

select throws_ok(
  format(
    $$select public.delete_active_list(%L, 10)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  '40001',
  'list changed',
  'stale list deletion is rejected'
);

select lives_ok(
  format(
    $$select public.delete_active_list(%L, 11)$$,
    (select list_id from active_list_test_values where label = 'primary')
  ),
  'exact-version list deletion succeeds'
);

reset role;

select ok(
  not exists (
    select 1
    from public.active_lists
    where id = (
      select list_id from active_list_test_values where label = 'primary'
    )
  )
  and not exists (
    select 1
    from public.active_list_items
    where id = (
      select item_id from active_list_test_values where label = 'item-one'
    )
  ),
  'permanent list deletion cascades its remaining item'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

insert into active_list_test_values (label, list_id, list_version)
select 'other-list', created.list_id, created.version
from public.create_active_list(
  'Other list',
  '10000000-0000-4000-8000-000000000021'
) as created;

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select throws_ok(
  format(
    $$select * from public.get_active_list(%L)$$,
    (select list_id from active_list_test_values where label = 'other-list')
  ),
  'P0002',
  'list unavailable',
  'cross-owner detail is privacy-safe unavailable'
);

select throws_ok(
  format(
    $$select * from public.rename_active_list(%L, 'No', 1)$$,
    (select list_id from active_list_test_values where label = 'other-list')
  ),
  'P0002',
  'list unavailable',
  'cross-owner mutation is privacy-safe unavailable'
);

reset role;

select is(
  (
    select pg_catalog.count(*)
    from public.active_lists
    where id = (
      select list_id from active_list_test_values where label = 'other-list'
    )
  ),
  1::bigint,
  'an unrelated owner list survives another owner aggregate deletion'
);

insert into public.active_list_items (
  list_id,
  name,
  quantity_thousandths,
  unit_code,
  position,
  creation_request_id
)
select
  other_list.list_id,
  'Unit ' || coalesce(unit_value.unit_code, 'none'),
  case when unit_value.ordinality = 1 then 999999999 else 1000 end,
  unit_value.unit_code,
  unit_value.ordinality,
  ('30000000-0000-4000-8000-' || pg_catalog.lpad(unit_value.ordinality::text, 12, '0'))::uuid
from active_list_test_values as other_list
cross join lateral pg_catalog.unnest(array[
  null,
  'piece',
  'kg',
  'g',
  'l',
  'ml',
  'pack',
  'box',
  'bottle',
  'can',
  'bag'
]::text[]) with ordinality as unit_value(unit_code, ordinality)
where other_list.label = 'other-list';

select is(
  (
    select pg_catalog.count(*)
    from public.active_list_items
    where list_id = (
      select list_id from active_list_test_values where label = 'other-list'
    )
  ),
  11::bigint,
  'null, every stable unit code, and maximum quantity satisfy constraints'
);

update public.active_list_items
set completed_at = pg_catalog.clock_timestamp(),
    completed_by = '55555555-5555-4555-8555-555555555555'
where list_id = (
    select list_id from active_list_test_values where label = 'other-list'
  )
  and position = 1;

delete from auth.users
where id = '55555555-5555-4555-8555-555555555555';

select ok(
  (
    select completed_at is not null and completed_by is null
    from public.active_list_items
    where list_id = (
        select list_id from active_list_test_values where label = 'other-list'
      )
      and position = 1
  ),
  'future completion actor deletion retains time and never deletes the item'
);

select * from finish();

rollback;
