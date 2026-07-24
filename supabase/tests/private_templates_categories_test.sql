begin;

create extension if not exists pgtap with schema extensions;

select no_plan();

select has_table('public', 'template_categories', 'template categories table exists');
select has_table('public', 'templates', 'templates table exists');
select has_table('public', 'template_items', 'template items table exists');

select columns_are(
  'public', 'template_categories',
  array['id','owner_id','name','normalized_name','version','creation_request_id','created_at','updated_at'],
  'template categories expose only reviewed physical columns'
);
select columns_are(
  'public', 'templates',
  array['id','owner_id','category_id','name','version','creation_request_id','created_at','updated_at'],
  'templates expose only reviewed physical columns'
);
select columns_are(
  'public', 'template_items',
  array['id','template_id','name','quantity_thousandths','position','version','creation_request_id','created_at','updated_at'],
  'template items contain no completion, unit, actor, membership, or source link'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as table_class
    where table_class.oid in (
      'public.template_categories'::regclass,
      'public.templates'::regclass,
      'public.template_items'::regclass
    )
      and table_class.relrowsecurity
      and table_class.relforcerowsecurity
  ),
  3::bigint,
  'all private template tables enable and force RLS'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in ('template_categories','templates','template_items')
      and cmd = 'ALL'
      and roles = array['anon','authenticated']::name[]
      and qual = 'false'
      and with_check = 'false'
  ),
  3::bigint,
  'all private template tables explicitly reject every direct client operation'
);

select ok(
  not has_table_privilege('anon','public.template_categories','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.template_categories','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','public.template_categories','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon','public.templates','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.templates','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','public.templates','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('anon','public.template_items','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated','public.template_items','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','public.template_items','SELECT,INSERT,UPDATE,DELETE'),
  'Data API roles have no direct private template CRUD privileges'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.list_template_categories()'::regprocedure,
      'public.list_private_templates(text,uuid,boolean,text)'::regprocedure,
      'public.get_private_template(uuid)'::regprocedure,
      'public.list_private_template_items(uuid)'::regprocedure,
      'public.create_template_category(text,uuid)'::regprocedure,
      'public.rename_template_category(uuid,text,bigint)'::regprocedure,
      'public.delete_template_category(uuid,bigint)'::regprocedure,
      'public.create_private_template(text,uuid,uuid)'::regprocedure,
      'public.update_private_template(uuid,text,uuid,bigint)'::regprocedure,
      'public.delete_private_template(uuid,bigint)'::regprocedure,
      'public.create_private_template_item(uuid,text,uuid,bigint,bigint)'::regprocedure,
      'public.update_private_template_item(uuid,uuid,text,bigint,bigint,bigint)'::regprocedure,
      'public.delete_private_template_item(uuid,uuid,bigint,bigint)'::regprocedure,
      'public.reorder_private_template_items(uuid,uuid[],bigint)'::regprocedure,
      'public.save_active_list_as_template(uuid,uuid[],text,uuid,uuid,bigint)'::regprocedure,
      'public.create_active_list_from_template(uuid,uuid[],text,uuid,uuid[],bigint)'::regprocedure,
      'public.import_private_template_items(uuid,uuid[],uuid,uuid[],bigint,bigint)'::regprocedure,
      'public.export_own_account_data()'::regprocedure
    )
      and function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
  ),
  18::bigint,
  'every public template/export function is postgres-owned, definer-rights, and pins an empty search path'
);

select ok(
  has_function_privilege('authenticated','public.list_template_categories()','EXECUTE')
  and has_function_privilege('authenticated','public.import_private_template_items(uuid,uuid[],uuid,uuid[],bigint,bigint)','EXECUTE')
  and not has_function_privilege('anon','public.list_template_categories()','EXECUTE')
  and not has_function_privilege('service_role','public.list_template_categories()','EXECUTE')
  and not has_function_privilege('anon','public.import_private_template_items(uuid,uuid[],uuid,uuid[],bigint,bigint)','EXECUTE')
  and not has_function_privilege('service_role','public.import_private_template_items(uuid,uuid[],uuid,uuid[],bigint,bigint)','EXECUTE'),
  'only authenticated receives the exact template RPC grants'
);

set local role anon;
select throws_like(
  $$select * from public.template_categories$$,
  '%permission denied%template_categories%',
  'anonymous direct category reads are denied'
);
select throws_like(
  $$select * from public.list_template_categories()$$,
  '%permission denied%function%list_template_categories%',
  'anonymous template RPC execution is denied'
);
reset role;

insert into auth.users (id,email,email_confirmed_at,created_at,updated_at)
values
  ('61000000-0000-4000-8000-000000000001','template-owner@example.test',now(),now(),now()),
  ('61000000-0000-4000-8000-000000000002','template-member@example.test',now(),now(),now()),
  ('61000000-0000-4000-8000-000000000003','template-other@example.test',now(),now(),now()),
  ('61000000-0000-4000-8000-000000000004','template-incomplete@example.test',now(),now(),now());

update public.profiles
set username = case id
      when '61000000-0000-4000-8000-000000000001' then 'template_owner'
      when '61000000-0000-4000-8000-000000000002' then 'template_member'
      when '61000000-0000-4000-8000-000000000003' then 'template_other'
    end,
    display_name = case id
      when '61000000-0000-4000-8000-000000000001' then 'Template Owner'
      when '61000000-0000-4000-8000-000000000002' then 'Template Member'
      when '61000000-0000-4000-8000-000000000003' then 'Template Other'
    end
where id <> '61000000-0000-4000-8000-000000000004';

create temporary table template_test_values (
  label text primary key,
  value_id uuid,
  secondary_id uuid,
  version bigint
) on commit drop;
grant select, insert, update on template_test_values to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" = '';
select throws_ok(
  $$select * from public.list_template_categories()$$,
  '42501','verified profile required',
  'authenticated without identity is denied'
);
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000004';
select throws_ok(
  $$select * from public.create_private_template('No',null,'62000000-0000-4000-8000-000000000001')$$,
  '42501','verified profile required',
  'incomplete onboarding is denied'
);

set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
insert into template_test_values(label,value_id,version)
select 'category', created.category_id, created.version
from public.create_template_category(
  '  Home   Supplies  ',
  '62000000-0000-4000-8000-000000000002'
) as created;

select ok(
  exists (
    select 1 from public.list_template_categories()
    where category_id = (select value_id from template_test_values where label='category')
      and name = 'Home Supplies' and version = 1 and template_count = 0
  ),
  'category normalization preserves one canonical display name and empty categories remain visible'
);

select is(
  (
    select version from public.rename_template_category(
      (select value_id from template_test_values where label='category'),
      ' Household Supplies ',
      1
    )
  ),
  2::bigint,
  'category rename normalizes display text and increments once'
);
update template_test_values set version=2 where label='category';

select throws_like(
  $$select * from public.create_template_category('household supplies','62000000-0000-4000-8000-000000000003')$$,
  '%template_categories_owner_name_key%',
  'normalized category names are unique per owner'
);

set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000003';
select lives_ok(
  $$select * from public.create_template_category(' HOUSEHOLD supplies ','62000000-0000-4000-8000-000000000004')$$,
  'different owners may use the same normalized category name'
);

set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
insert into template_test_values(label,value_id,version)
select 'template', created.template_id, created.version
from public.create_private_template(
  '  Weekly Basket  ',
  (select value_id from template_test_values where label='category'),
  '62000000-0000-4000-8000-000000000005'
) as created;

select lives_ok(
  $$select * from public.create_private_template('Weekly Basket',null,'62000000-0000-4000-8000-000000000006')$$,
  'duplicate template names and blank templates are allowed'
);

select is(
  (
    select pg_catalog.count(*)
    from public.list_private_templates('weekly',null,false,'alpha')
  ),
  2::bigint,
  'search and A-Z sorting return duplicate matching template names'
);

with created as (
  select * from public.create_private_template_item(
    (select value_id from template_test_values where label='template'),
    '  Milk  ',
    '62000000-0000-4000-8000-000000000007',
    1,
    1500
  )
)
insert into template_test_values(label,value_id,secondary_id,version)
select 'template-item-one', created.item_id,
  (select value_id from template_test_values where label='template'),
  created.version
from created;

update template_test_values
set version = 2
where label = 'template';

with created as (
  select * from public.create_private_template_item(
    (select value_id from template_test_values where label='template'),
    'Milk',
    '62000000-0000-4000-8000-000000000008',
    2,
    1000
  )
)
insert into template_test_values(label,value_id,secondary_id,version)
select 'template-item-two', created.item_id,
  (select value_id from template_test_values where label='template'),
  created.version
from created;
update template_test_values set version=3 where label='template';

select ok(
  (
    select pg_catalog.count(*) = 2
      and pg_catalog.min(name) = 'Milk'
      and pg_catalog.sum(quantity_thousandths) = 2500
    from public.list_private_template_items(
      (select value_id from template_test_values where label='template')
    )
  ),
  'template item names trim, duplicate names remain separate, and exact quantities are retained'
);

select is(
  public.reorder_private_template_items(
    (select value_id from template_test_values where label='template'),
    array[
      (select value_id from template_test_values where label='template-item-two'),
      (select value_id from template_test_values where label='template-item-one')
    ],
    3
  ),
  4::bigint,
  'template reorder advances the parent version exactly once'
);
update template_test_values set version=4 where label='template';

select ok(
  (
    select pg_catalog.array_agg(item_id order by position) = array[
      (select value_id from template_test_values where label='template-item-two'),
      (select value_id from template_test_values where label='template-item-one')
    ]
    from public.list_private_template_items(
      (select value_id from template_test_values where label='template')
    )
  ),
  'template reorder writes authoritative contiguous order'
);

reset role;

insert into public.template_categories(
  owner_id,name,normalized_name,creation_request_id
)
select
  '61000000-0000-4000-8000-000000000001',
  'Quota ' || series.value,
  pg_catalog.lower('Quota ' || series.value),
  ('63000000-0000-4000-8000-' || pg_catalog.lpad(series.value::text,12,'0'))::uuid
from pg_catalog.generate_series(1,24) as series(value);

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.create_template_category('Over quota','63000000-0000-4000-8000-000000000025')$$,
  '54000','template category capacity reached',
  'the twenty-sixth category is rejected under the serialized quota'
);

reset role;
insert into public.templates(owner_id,name,creation_request_id)
select
  '61000000-0000-4000-8000-000000000001',
  'Quota template ' || series.value,
  ('64000000-0000-4000-8000-' || pg_catalog.lpad(series.value::text,12,'0'))::uuid
from pg_catalog.generate_series(1,98) as series(value);

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.create_private_template('Over quota',null,'64000000-0000-4000-8000-000000000099')$$,
  '54000','template capacity reached',
  'the one-hundred-first template is rejected under the serialized quota'
);

reset role;
delete from public.templates
where owner_id = '61000000-0000-4000-8000-000000000001'
  and name like 'Quota template %';

insert into public.template_items(
  template_id,name,quantity_thousandths,position,creation_request_id
)
select
  (select value_id from template_test_values where label='template'),
  'Capacity item ' || series.value,
  1000,
  series.value + 2,
  ('65000000-0000-4000-8000-' || pg_catalog.lpad(series.value::text,12,'0'))::uuid
from pg_catalog.generate_series(1,197) as series(value);

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select is(
  (
    select template_version
    from public.create_private_template_item(
      (select value_id from template_test_values where label='template'),
      'Two hundred',
      '65000000-0000-4000-8000-000000000198',
      4,
      1000
    )
  ),
  5::bigint,
  'the two-hundredth template item succeeds'
);
update template_test_values set version=5 where label='template';

select throws_ok(
  format(
    $$select * from public.create_private_template_item(%L,'Too many','65000000-0000-4000-8000-000000000199',5,1000)$$,
    (select value_id from template_test_values where label='template')
  ),
  '54000','template item capacity reached',
  'the two-hundred-first template item fails'
);

select lives_ok(
  format(
    $$select * from public.update_private_template_item(%L,%L,'Edited at capacity',1000,5,1)$$,
    (select value_id from template_test_values where label='template'),
    (select value_id from template_test_values where label='template-item-one')
  ),
  'existing template items remain editable at capacity'
);
update template_test_values set version=6 where label='template';

select is(
  public.delete_private_template_item(
    (select value_id from template_test_values where label='template'),
    (select value_id from template_test_values where label='template-item-two'),
    6,
    1
  ),
  7::bigint,
  'deleting a template item succeeds at capacity and advances once'
);
update template_test_values set version=7 where label='template';
select lives_ok(
  format(
    $$select * from public.create_private_template_item(%L,'Freed slot','65000000-0000-4000-8000-000000000200',7,1000)$$,
    (select value_id from template_test_values where label='template')
  ),
  'deleting a template item immediately frees one slot'
);

select is(
  public.delete_template_category(
    (select value_id from template_test_values where label='category'),
    2
  ),
  1::bigint,
  'category deletion atomically finds its one placed template'
);
select ok(
  exists (
    select 1
    from public.list_private_templates(null,null,true,'recent')
    where template_id = (select value_id from template_test_values where label='template')
      and category_id is null
  ),
  'category deletion preserves the template and moves it to Uncategorized'
);

reset role;

insert into public.active_lists(id,owner_id,title,creation_request_id)
values (
  '66000000-0000-4000-8000-000000000001',
  '61000000-0000-4000-8000-000000000001',
  'Capacity list',
  '66000000-0000-4000-8000-000000000002'
);
insert into public.active_list_items(
  list_id,name,quantity_thousandths,position,creation_request_id,completed_at,completed_by
)
select
  '66000000-0000-4000-8000-000000000001',
  'List capacity ' || series.value,
  1000,
  series.value,
  ('67000000-0000-4000-8000-' || pg_catalog.lpad(series.value::text,12,'0'))::uuid,
  case when series.value = 1 then now() else null end,
  case when series.value = 1 then '61000000-0000-4000-8000-000000000001'::uuid else null end
from pg_catalog.generate_series(1,199) as series(value);

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select is(
  (
    select list_version from public.create_active_list_item(
      '66000000-0000-4000-8000-000000000001','Two hundred',
      '67000000-0000-4000-8000-000000000200',1
    )
  ),
  2::bigint,
  'the two-hundredth ordinary list item succeeds while completed rows count'
);
select throws_ok(
  $$select * from public.create_active_list_item('66000000-0000-4000-8000-000000000001','Too many','67000000-0000-4000-8000-000000000201',2)$$,
  '54000','list item capacity reached',
  'the two-hundred-first ordinary list item fails'
);
select is(
  (
    select pg_catalog.count(*) from public.list_active_list_items('66000000-0000-4000-8000-000000000001')
  ),
  200::bigint,
  'stale/concurrent additions cannot exceed the two-hundred-row list limit'
);

select is(
  public.delete_active_list_item(
    '66000000-0000-4000-8000-000000000001',
    (select item_id from public.list_active_list_items('66000000-0000-4000-8000-000000000001') where position=200),
    2,
    1
  ),
  3::bigint,
  'deleting an ordinary item frees capacity and increments the list once'
);
select lives_ok(
  $$select * from public.create_active_list_item('66000000-0000-4000-8000-000000000001','Freed slot','67000000-0000-4000-8000-000000000202',3)$$,
  'ordinary creation can reuse the freed list slot'
);

reset role;
insert into public.active_lists(id,owner_id,title,version,creation_request_id)
values (
  '66000000-0000-4000-8000-000000000010',
  '61000000-0000-4000-8000-000000000001',
  'Legacy over capacity',
  1,
  '66000000-0000-4000-8000-000000000011'
);
insert into public.active_list_items(list_id,name,position,creation_request_id)
select
  '66000000-0000-4000-8000-000000000010',
  'Legacy ' || series.value,
  series.value,
  ('68000000-0000-4000-8000-' || pg_catalog.lpad(series.value::text,12,'0'))::uuid
from pg_catalog.generate_series(1,201) as series(value);

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select is(
  (select pg_catalog.count(*) from public.list_active_list_items('66000000-0000-4000-8000-000000000010')),
  201::bigint,
  'legacy over-capacity rows remain intact and readable'
);
select throws_ok(
  $$select * from public.create_active_list_item('66000000-0000-4000-8000-000000000010','Blocked','68000000-0000-4000-8000-000000000202',1)$$,
  '54000','list item capacity reached',
  'legacy over-capacity list blocks further additions without destructive migration behavior'
);
select lives_ok(
  $$select * from public.update_active_list_item('66000000-0000-4000-8000-000000000010',(select item_id from public.list_active_list_items('66000000-0000-4000-8000-000000000010') where position=1),'Still editable',1000,null,1,1)$$,
  'legacy over-capacity rows remain editable'
);

reset role;

insert into public.active_lists(id,owner_id,title,version,creation_request_id)
values (
  '69000000-0000-4000-8000-000000000001',
  '61000000-0000-4000-8000-000000000001',
  'Snapshot source',
  1,
  '69000000-0000-4000-8000-000000000002'
);
insert into public.active_list_items(id,list_id,name,quantity_thousandths,position,creation_request_id,completed_at,completed_by)
values
  ('69000000-0000-4000-8000-000000000011','69000000-0000-4000-8000-000000000001','Done',2000,1,'69000000-0000-4000-8000-000000000021',now(),'61000000-0000-4000-8000-000000000001'),
  ('69000000-0000-4000-8000-000000000012','69000000-0000-4000-8000-000000000001','Open',3000,2,'69000000-0000-4000-8000-000000000022',null,null);

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
insert into template_test_values(label,value_id,version)
select 'snapshot-template', saved.template_id, saved.version
from public.save_active_list_as_template(
  '69000000-0000-4000-8000-000000000001',
  array['69000000-0000-4000-8000-000000000011'::uuid,'69000000-0000-4000-8000-000000000012'::uuid],
  'Snapshot',null,'69000000-0000-4000-8000-000000000031',1
) as saved;

select ok(
  (
    select pg_catalog.array_agg(name order by position) = array['Done','Open']
      and pg_catalog.array_agg(quantity_thousandths order by position) = array[2000::bigint,3000::bigint]
    from public.list_private_template_items(
      (select value_id from template_test_values where label='snapshot-template')
    )
  ),
  'save-as-template copies selected completed and open names, quantities, and source order without completion state'
);

select throws_ok(
  $$select * from public.save_active_list_as_template('69000000-0000-4000-8000-000000000001','{}'::uuid[],'Empty',null,'69000000-0000-4000-8000-000000000032',1)$$,
  '22023','invalid list template snapshot',
  'save-as-template rejects zero selected items'
);

select throws_ok(
  $$select * from public.save_active_list_as_template('66000000-0000-4000-8000-000000000010',(select pg_catalog.array_agg(item_id order by position) from public.list_active_list_items('66000000-0000-4000-8000-000000000010')),'Too many',null,'69000000-0000-4000-8000-000000000033',2)$$,
  '22023','invalid list template snapshot',
  'save-as-template rejects more than two hundred selected items'
);

insert into template_test_values(label,value_id,version)
select 'copied-list', created.list_id, created.version
from public.create_active_list_from_template(
  (select value_id from template_test_values where label='snapshot-template'),
  array[
    (select item_id from public.list_private_template_items((select value_id from template_test_values where label='snapshot-template')) where position=2),
    (select item_id from public.list_private_template_items((select value_id from template_test_values where label='snapshot-template')) where position=1)
  ],
  'Created from template',
  '69000000-0000-4000-8000-000000000041',
  array['69000000-0000-4000-8000-000000000042'::uuid,'69000000-0000-4000-8000-000000000043'::uuid],
  1
) as created;

select ok(
  (
    select pg_catalog.array_agg(name order by position) = array['Done','Open']
      and pg_catalog.bool_and(completed_at is null and completed_by is null)
    from public.list_active_list_items(
      (select value_id from template_test_values where label='copied-list')
    )
  ),
  'create-from-template uses authoritative template order and creates independent uncompleted items'
);

reset role;
insert into public.active_lists(id,owner_id,title,creation_request_id)
values (
  '6a000000-0000-4000-8000-000000000001',
  '61000000-0000-4000-8000-000000000001',
  'Import destination',
  '6a000000-0000-4000-8000-000000000002'
);
insert into public.active_list_items(list_id,name,position,creation_request_id)
select
  '6a000000-0000-4000-8000-000000000001',
  case when series.value=1 then 'done' else 'Existing ' || series.value end,
  series.value,
  ('6a100000-0000-4000-8000-' || pg_catalog.lpad(series.value::text,12,'0'))::uuid
from pg_catalog.generate_series(1,198) as series(value);
delete from realtime.messages;

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select ok(
  (
    select list_version=2 and imported_count=2 and remaining_capacity=0
    from public.import_private_template_items(
      (select value_id from template_test_values where label='snapshot-template'),
      (select pg_catalog.array_agg(item_id order by position desc) from public.list_private_template_items((select value_id from template_test_values where label='snapshot-template'))),
      '6a000000-0000-4000-8000-000000000001',
      array['6a200000-0000-4000-8000-000000000001'::uuid,'6a200000-0000-4000-8000-000000000002'::uuid],
      1,1
    )
  ),
  'exact remaining-capacity import succeeds atomically'
);
select ok(
  (
    select pg_catalog.array_agg(name order by position) filter (where position>198) = array['Done','Open']
    from public.list_active_list_items('6a000000-0000-4000-8000-000000000001')
  ),
  'import preserves authoritative template order even when selection IDs are reversed'
);

reset role;
delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.import_private_template_items((select value_id from template_test_values where label='snapshot-template'),array[(select item_id from public.list_private_template_items((select value_id from template_test_values where label='snapshot-template')) where position=1)],'6a000000-0000-4000-8000-000000000001',array['6a200000-0000-4000-8000-000000000003'::uuid],1,2)$$,
  '54000','list item capacity reached',
  'overflow import fails instead of partially reducing selection'
);
reset role;
select ok(
  (select pg_catalog.count(*)=200 from public.active_list_items where list_id='6a000000-0000-4000-8000-000000000001')
  and (select version=2 from public.active_lists where id='6a000000-0000-4000-8000-000000000001')
  and (select pg_catalog.count(*)=0 from realtime.messages),
  'overflow import creates no rows, version change, or Realtime invalidation'
);

insert into public.active_lists(id,owner_id,title,creation_request_id)
values (
  '6b000000-0000-4000-8000-000000000001',
  '61000000-0000-4000-8000-000000000001',
  'Concurrent import destination',
  '6b000000-0000-4000-8000-000000000002'
);
insert into public.active_list_items(list_id,name,position,creation_request_id)
select
  '6b000000-0000-4000-8000-000000000001',
  'Concurrent ' || series.value,
  series.value,
  ('6b100000-0000-4000-8000-' || pg_catalog.lpad(series.value::text,12,'0'))::uuid
from pg_catalog.generate_series(1,199) as series(value);

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.import_private_template_items((select value_id from template_test_values where label='snapshot-template'),array[(select item_id from public.list_private_template_items((select value_id from template_test_values where label='snapshot-template')) where position=1)],'6b000000-0000-4000-8000-000000000001',array['6b200000-0000-4000-8000-000000000001'::uuid],1,1)$$,
  'first exact-slot import succeeds'
);
select throws_ok(
  $$select * from public.import_private_template_items((select value_id from template_test_values where label='snapshot-template'),array[(select item_id from public.list_private_template_items((select value_id from template_test_values where label='snapshot-template')) where position=2)],'6b000000-0000-4000-8000-000000000001',array['6b200000-0000-4000-8000-000000000002'::uuid],1,1)$$,
  '40001','list changed',
  'a concurrent stale import cannot exceed remaining capacity'
);
select is(
  (select pg_catalog.count(*) from public.list_active_list_items('6b000000-0000-4000-8000-000000000001')),
  200::bigint,
  'serialized concurrent imports never exceed two hundred current items'
);

select lives_ok(
  format(
    $$select * from public.create_active_list_from_template(
      %L,
      (select pg_catalog.array_agg(item_id order by position) from public.list_private_template_items(%L)),
      'Exact two hundred',
      '6d000000-0000-4000-8000-000000000001',
      (select pg_catalog.array_agg(
        ('6d100000-0000-4000-8000-' || pg_catalog.lpad(series.value::text,12,'0'))::uuid
        order by series.value
      ) from pg_catalog.generate_series(1,200) as series(value)),
      (select version from public.get_private_template(%L))
    )$$,
    (select value_id from template_test_values where label='template'),
    (select value_id from template_test_values where label='template'),
    (select value_id from template_test_values where label='template')
  ),
  'creating a new list from exactly two hundred template items succeeds'
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.active_lists as created_list
    join public.active_list_items as created_item on created_item.list_id=created_list.id
    where created_list.owner_id='61000000-0000-4000-8000-000000000001'
      and created_list.creation_request_id='6d000000-0000-4000-8000-000000000001'
  ),
  200::bigint,
  'create-from-template respects the two-hundred-item list capacity'
);

insert into public.active_lists(id,owner_id,title,creation_request_id)
values (
  '6e000000-0000-4000-8000-000000000001',
  '61000000-0000-4000-8000-000000000003',
  'Member destination',
  '6e000000-0000-4000-8000-000000000002'
);
insert into public.active_list_participants(
  list_id,participant_profile_id,state,version
) values (
  '6e000000-0000-4000-8000-000000000001',
  '61000000-0000-4000-8000-000000000001',
  'member',1
);

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.import_private_template_items(
    (select value_id from template_test_values where label='snapshot-template'),
    array[(select item_id from public.list_private_template_items((select value_id from template_test_values where label='snapshot-template')) where position=1)],
    '6e000000-0000-4000-8000-000000000001',
    array['6e100000-0000-4000-8000-000000000001'::uuid],1,1
  )$$,
  'an accepted member may import their private template into an active shared list'
);

reset role;
update public.active_lists
set status='archived',archived_at=now(),version=3,updated_at=now()
where id='6e000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.save_active_list_as_template(
    '6e000000-0000-4000-8000-000000000001',
    array[(select item_id from public.list_active_list_items('6e000000-0000-4000-8000-000000000001') where position=1)],
    'Archived member snapshot',null,'6e100000-0000-4000-8000-000000000002',3
  )$$,
  'an accepted member may save an archived list while access remains valid'
);

select ok(
  (
    select schema_version=6
      and pg_catalog.jsonb_array_length(template_categories) >= 1
      and pg_catalog.jsonb_array_length(templates) >= 1
    from pg_catalog.jsonb_to_record(public.export_own_account_data())
      as exported(schema_version integer,template_categories jsonb,templates jsonb)
  ),
  'account export schema version six includes private categories and templates'
);

set local "request.jwt.claim.sub" = '61000000-0000-4000-8000-000000000003';
select is(
  (
    select pg_catalog.count(*)
    from public.get_private_template(
      (select value_id from template_test_values where label='snapshot-template')
    )
  ),
  0::bigint,
  'cross-account template detail is unavailable'
);
select is(
  (
    select pg_catalog.count(*)
    from public.list_private_templates(null,null,false,'recent')
    where template_id = (select value_id from template_test_values where label='snapshot-template')
  ),
  0::bigint,
  'cross-account template listing reveals no rows'
);

reset role;

select is((select pg_catalog.count(*) from public.user_notifications),0::bigint,
  'private template and category operations create no persistent notifications');

delete from auth.users
where id='61000000-0000-4000-8000-000000000001';

select ok(
  not exists (select 1 from public.templates where owner_id='61000000-0000-4000-8000-000000000001')
  and not exists (select 1 from public.template_categories where owner_id='61000000-0000-4000-8000-000000000001')
  and exists (
    select 1 from public.active_lists as surviving_list
    join public.active_list_items as surviving_item on surviving_item.list_id=surviving_list.id
    where surviving_list.id='6e000000-0000-4000-8000-000000000001'
      and surviving_list.owner_id='61000000-0000-4000-8000-000000000003'
      and surviving_item.name='Done'
  ),
  'Auth-root deletion removes only private template data while independent imported list items survive'
);

select * from finish();
rollback;
