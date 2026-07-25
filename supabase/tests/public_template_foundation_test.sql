begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_column(
  'public',
  'templates',
  'published_at',
  'templates have nullable publication state'
);
select col_is_null(
  'public',
  'templates',
  'published_at',
  'publication is private by default'
);
select has_check(
  'public',
  'templates',
  'templates have a public-name database constraint'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint as constraint_record
    where constraint_record.conrelid = 'public.templates'::regclass
      and constraint_record.conname = 'templates_public_name_check'
      and constraint_record.contype = 'c'
  ),
  1::bigint,
  'the conditional public-name constraint has the reviewed identity'
);
select has_index(
  'public',
  'templates',
  'templates_owner_public_keyset_idx',
  'public profile listing has its partial keyset index'
);
select is(
  (
    select pg_catalog.pg_get_expr(index_record.indpred, index_record.indrelid)
    from pg_catalog.pg_index as index_record
    where index_record.indexrelid =
      'public.templates_owner_public_keyset_idx'::regclass
  ),
  '(published_at IS NOT NULL)',
  'the public keyset index contains only published templates'
);

select has_table(
  'private',
  'public_template_copy_requests',
  'the private public-copy retry ledger exists'
);
select columns_are(
  'private',
  'public_template_copy_requests',
  array[
    'owner_id',
    'request_id',
    'request_fingerprint',
    'copied_template_id',
    'created_at'
  ],
  'the copy ledger stores only the reviewed server fields'
);
select is(
  (
    select table_record.relrowsecurity and table_record.relforcerowsecurity
    from pg_catalog.pg_class as table_record
    where table_record.oid =
      'private.public_template_copy_requests'::regclass
  ),
  true,
  'the copy ledger enables and forces RLS'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'private'
      and tablename = 'public_template_copy_requests'
      and cmd = 'ALL'
      and roles = array['anon','authenticated']::name[]
      and qual = 'false'
      and with_check = 'false'
  ),
  1::bigint,
  'the copy ledger explicitly rejects all direct client operations'
);
select ok(
  not has_table_privilege(
    'anon',
    'private.public_template_copy_requests',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.public_template_copy_requests',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'private.public_template_copy_requests',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'no API role has direct copy-ledger privileges'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_constraint as constraint_record
    where constraint_record.conrelid =
      'private.public_template_copy_requests'::regclass
      and constraint_record.contype = 'f'
      and constraint_record.confdeltype = 'c'
  ),
  2::bigint,
  'copy ledger owner and destination references cascade'
);
select has_index(
  'private',
  'public_template_copy_requests',
  'public_template_copy_requests_destination_idx',
  'copy ledger destination cascades have a covering index'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.list_private_templates_v2(text,uuid,boolean,text)'::regprocedure,
      'public.get_private_template_v2(uuid)'::regprocedure,
      'public.set_template_publication(uuid,boolean,bigint)'::regprocedure,
      'public.list_public_profile_templates(uuid,integer,timestamptz,uuid)'::regprocedure,
      'public.get_public_template(uuid,uuid)'::regprocedure,
      'public.copy_public_template(uuid,bigint,uuid)'::regprocedure,
      'public.export_own_account_data_v9()'::regprocedure
    )
      and function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
  ),
  7::bigint,
  'all new public client RPCs are postgres-owned hardened definer boundaries'
);
select is(
  (
    select not function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'private.public_template_copy_fingerprint(uuid,bigint)'::regprocedure
  ),
  true,
  'the private fingerprint helper is invoker-rights and pins an empty search path'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.list_public_profile_templates(uuid,integer,timestamptz,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_public_template(uuid,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.copy_public_template(uuid,bigint,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.set_template_publication(uuid,boolean,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.export_own_account_data_v9()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.list_public_profile_templates(uuid,integer,timestamptz,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.copy_public_template(uuid,bigint,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.public_template_copy_fingerprint(uuid,bigint)',
    'EXECUTE'
  ),
  'only authenticated receives exact public-template RPC execution'
);

set local role anon;
select throws_like(
  $$select public.list_public_profile_templates(
      'd1000000-0000-4000-8000-000000000001',
      20,
      null,
      null
    )$$,
  '%permission denied%function%list_public_profile_templates%',
  'anonymous public-profile execution is denied'
);
select throws_like(
  $$select * from private.public_template_copy_requests$$,
  '%permission denied%',
  'anonymous direct copy-ledger reads are denied'
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
  (
    'd1000000-0000-4000-8000-000000000001',
    'public-owner@example.test',
    now(),
    now(),
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000002',
    'public-friend@example.test',
    now(),
    now(),
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000003',
    'public-nonfriend@example.test',
    now(),
    now(),
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000004',
    'public-incomplete@example.test',
    now(),
    now(),
    now()
  ),
  (
    'd1000000-0000-4000-8000-000000000005',
    'public-quota@example.test',
    now(),
    now(),
    now()
  );

update public.profiles
set username = case id
      when 'd1000000-0000-4000-8000-000000000001' then 'public_owner'
      when 'd1000000-0000-4000-8000-000000000002' then 'public_friend'
      when 'd1000000-0000-4000-8000-000000000003' then 'public_nonfriend'
      when 'd1000000-0000-4000-8000-000000000005' then 'public_quota'
    end,
    display_name = case id
      when 'd1000000-0000-4000-8000-000000000001' then 'Public Owner'
      when 'd1000000-0000-4000-8000-000000000002' then 'Public Friend'
      when 'd1000000-0000-4000-8000-000000000003' then 'Public Nonfriend'
      when 'd1000000-0000-4000-8000-000000000005' then 'Public Quota'
    end
where id <> 'd1000000-0000-4000-8000-000000000004';

insert into public.user_relationships (
  profile_low_id,
  profile_high_id,
  state,
  requester_id
)
values (
  'd1000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000002',
  'friends',
  'd1000000-0000-4000-8000-000000000001'
);

insert into public.templates (
  id,
  owner_id,
  name,
  creation_request_id
)
values
  (
    'd2000000-0000-4000-8000-000000000001',
    'd1000000-0000-4000-8000-000000000001',
    'Public kit',
    'd3000000-0000-4000-8000-000000000001'
  ),
  (
    'd2000000-0000-4000-8000-000000000002',
    'd1000000-0000-4000-8000-000000000001',
    'Empty public kit',
    'd3000000-0000-4000-8000-000000000002'
  ),
  (
    'd2000000-0000-4000-8000-000000000003',
    'd1000000-0000-4000-8000-000000000001',
    'Private kit',
    'd3000000-0000-4000-8000-000000000003'
  ),
  (
    'd2000000-0000-4000-8000-000000000004',
    'd1000000-0000-4000-8000-000000000001',
    repeat('x', 120),
    'd3000000-0000-4000-8000-000000000004'
  ),
  (
    'd2000000-0000-4000-8000-000000000005',
    'd1000000-0000-4000-8000-000000000001',
    repeat('y', 121),
    'd3000000-0000-4000-8000-000000000005'
  );

insert into public.template_items (
  id,
  template_id,
  name,
  quantity_thousandths,
  position,
  creation_request_id
)
values
  (
    'd4000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000001',
    'Water',
    1500,
    1,
    'd5000000-0000-4000-8000-000000000001'
  ),
  (
    'd4000000-0000-4000-8000-000000000002',
    'd2000000-0000-4000-8000-000000000001',
    'Water',
    2000,
    2,
    'd5000000-0000-4000-8000-000000000002'
  );

select is(
  (
    select pg_catalog.count(*)
    from public.templates
    where owner_id = 'd1000000-0000-4000-8000-000000000001'
      and published_at is not null
  ),
  0::bigint,
  'existing and new fixture templates remain private by default'
);

create temporary table public_template_values (
  label text primary key,
  value_uuid uuid,
  value_bigint bigint,
  value_time timestamptz,
  value_json jsonb
) on commit drop;
grant select, insert, update, delete on public_template_values
to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000004';
select throws_ok(
  $$select public.list_public_profile_templates(
      'd1000000-0000-4000-8000-000000000001',
      20,
      null,
      null
    )$$,
  '42501',
  'verified profile required',
  'incomplete callers cannot read public profiles'
);

set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000001';
insert into public_template_values (
  label,
  value_uuid,
  value_bigint,
  value_time
)
select
  'source-published',
  publication.template_id,
  publication.version,
  publication.published_at
from public.set_template_publication(
  'd2000000-0000-4000-8000-000000000001',
  true,
  1
) as publication;

select is(
  (
    select value_bigint
    from public_template_values
    where label = 'source-published'
  ),
  2::bigint,
  'first publication advances the template version once'
);
select ok(
  (
    select value_time is not null
    from public_template_values
    where label = 'source-published'
  ),
  'first publication returns a server timestamp'
);

select is(
  (
    select publication.version
    from public.set_template_publication(
      'd2000000-0000-4000-8000-000000000001',
      true,
      1
    ) as publication
  ),
  2::bigint,
  'a lost-response publication retry is an achieved-state no-op'
);
select is(
  (
    select publication.published_at
    from public.set_template_publication(
      'd2000000-0000-4000-8000-000000000001',
      true,
      1
    ) as publication
  ),
  (
    select value_time
    from public_template_values
    where label = 'source-published'
  ),
  'the achieved-state retry preserves publication time'
);

select * from public.update_private_template(
  'd2000000-0000-4000-8000-000000000001',
  'Public kit edited',
  null,
  2
);

select throws_ok(
  $$select * from public.set_template_publication(
      'd2000000-0000-4000-8000-000000000001',
      false,
      2
    )$$,
  '40001',
  'template changed',
  'a stale real unpublication transition is rejected'
);

select is(
  (
    select publication.version
    from public.set_template_publication(
      'd2000000-0000-4000-8000-000000000001',
      false,
      3
    ) as publication
  ),
  4::bigint,
  'unpublication advances the version once'
);
select is(
  (
    select publication.version
    from public.set_template_publication(
      'd2000000-0000-4000-8000-000000000001',
      false,
      3
    ) as publication
  ),
  4::bigint,
  'a repeated unpublication is an achieved-state no-op'
);

update public_template_values
set value_bigint = publication.version,
    value_time = publication.published_at
from public.set_template_publication(
  'd2000000-0000-4000-8000-000000000001',
  true,
  4
) as publication
where label = 'source-published';

select is(
  (
    select value_bigint
    from public_template_values
    where label = 'source-published'
  ),
  5::bigint,
  'republication advances the version once'
);

select * from public.set_template_publication(
  'd2000000-0000-4000-8000-000000000002',
  true,
  1
);
select * from public.set_template_publication(
  'd2000000-0000-4000-8000-000000000004',
  true,
  1
);
select throws_ok(
  $$select * from public.set_template_publication(
      'd2000000-0000-4000-8000-000000000005',
      true,
      1
    )$$,
  '22023',
  'invalid public template name',
  'a 121-code-point private legacy name cannot be published'
);
select throws_like(
  $$select * from public.update_private_template(
      'd2000000-0000-4000-8000-000000000004',
      repeat('z', 121),
      null,
      2
    )$$,
  '%templates_public_name_check%',
  'editing a public template enforces the public-name constraint'
);

select ok(
  exists (
    select 1
    from public.list_private_templates_v2(null, null, false, 'recent')
    where template_id = 'd2000000-0000-4000-8000-000000000001'
      and is_public
      and published_at is not null
  )
  and exists (
    select 1
    from public.list_private_templates_v2(null, null, false, 'recent')
    where template_id = 'd2000000-0000-4000-8000-000000000003'
      and not is_public
      and published_at is null
  ),
  'v2 owner listing exposes exact publication state for public and private rows'
);
select ok(
  exists (
    select 1
    from public.get_private_template_v2(
      'd2000000-0000-4000-8000-000000000001'
    )
    where is_public and published_at is not null and item_count = 2
  ),
  'v2 owner detail exposes publication state without changing item reads'
);

select throws_ok(
  $$select public.list_public_profile_templates(
      'd1000000-0000-4000-8000-000000000001',
      0,
      null,
      null
    )$$,
  '22023',
  'invalid public template query',
  'public page size is bounded below'
);
select throws_ok(
  $$select public.list_public_profile_templates(
      'd1000000-0000-4000-8000-000000000001',
      51,
      null,
      null
    )$$,
  '22023',
  'invalid public template query',
  'public page size is bounded above'
);
select throws_ok(
  $$select public.list_public_profile_templates(
      'd1000000-0000-4000-8000-000000000001',
      20,
      now(),
      null
    )$$,
  '22023',
  'invalid public template query',
  'public cursors are both null or both present'
);

set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000002';
insert into public_template_values(label, value_json)
values (
  'friend-page',
  public.list_public_profile_templates(
    'd1000000-0000-4000-8000-000000000001',
    1,
    null,
    null
  )
);
set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000003';
insert into public_template_values(label, value_json)
values (
  'nonfriend-page',
  public.list_public_profile_templates(
    'd1000000-0000-4000-8000-000000000001',
    1,
    null,
    null
  )
);

select is(
  (
    select value_json
    from public_template_values
    where label = 'friend-page'
  ),
  (
    select value_json
    from public_template_values
    where label = 'nonfriend-page'
  ),
  'friends and nonfriends receive identical public-profile output'
);
select is(
  (
    select pg_catalog.array_agg(key_name order by key_name)
    from pg_catalog.jsonb_object_keys(
      (
        select value_json
        from public_template_values
        where label = 'friend-page'
      )
    ) as key_name
  ),
  array['next_cursor','profile','templates']::text[],
  'public profile output has the exact top-level allowlist'
);
select is(
  (
    select pg_catalog.array_agg(key_name order by key_name)
    from pg_catalog.jsonb_object_keys(
      (
        select value_json -> 'profile'
        from public_template_values
        where label = 'friend-page'
      )
    ) as key_name
  ),
  array['display_name','profile_id','username']::text[],
  'public profile identity has the exact minimal allowlist'
);
select is(
  (
    select pg_catalog.array_agg(key_name order by key_name)
    from pg_catalog.jsonb_object_keys(
      (
        select value_json -> 'templates' -> 0
        from public_template_values
        where label = 'friend-page'
      )
    ) as key_name
  ),
  array[
    'item_count',
    'name',
    'published_at',
    'template_id',
    'version'
  ]::text[],
  'public template cards expose no category, count aggregate, or private field'
);
select ok(
  (
    select value_json -> 'next_cursor' is not null
    from public_template_values
    where label = 'friend-page'
  ),
  'one-extra-row paging returns a continuation cursor'
);

set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000002';
insert into public_template_values(label, value_json)
select
  'second-page',
  public.list_public_profile_templates(
    'd1000000-0000-4000-8000-000000000001',
    1,
    (
      select (value_json -> 'next_cursor' ->> 'published_at')::timestamptz
      from public_template_values
      where label = 'friend-page'
    ),
    (
      select (value_json -> 'next_cursor' ->> 'template_id')::uuid
      from public_template_values
      where label = 'friend-page'
    )
  );
select isnt(
  (
    select value_json -> 'templates' -> 0 ->> 'template_id'
    from public_template_values
    where label = 'friend-page'
  ),
  (
    select value_json -> 'templates' -> 0 ->> 'template_id'
    from public_template_values
    where label = 'second-page'
  ),
  'exclusive keyset paging does not repeat the prior template'
);

insert into public_template_values(label, value_json)
values (
  'detail',
  public.get_public_template(
    'd1000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000001'
  )
);
select is(
  (
    select pg_catalog.array_agg(key_name order by key_name)
    from pg_catalog.jsonb_object_keys(
      (
        select value_json -> 'template' -> 'items' -> 0
        from public_template_values
        where label = 'detail'
      )
    ) as key_name
  ),
  array['name','position','quantity_thousandths']::text[],
  'public detail items omit source item IDs and internal fields'
);
select is(
  (
    select value_json -> 'template' ->> 'item_count'
    from public_template_values
    where label = 'detail'
  ),
  '2',
  'public detail includes duplicate-name rows as separate ordered positions'
);
select is(
  public.get_public_template(
    'd1000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000003'
  ),
  null::jsonb,
  'private direct-ID detail is indistinguishable from missing'
);
select is(
  public.get_public_template(
    'd1000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000099'
  ),
  null::jsonb,
  'missing direct-ID detail is unavailable'
);
select is(
  public.list_public_profile_templates(
    'd1000000-0000-4000-8000-000000000004',
    20,
    null,
    null
  ),
  null::jsonb,
  'incomplete target profiles are unavailable'
);
reset role;

insert into public.user_blocks(blocker_id, blocked_id)
values (
  'd1000000-0000-4000-8000-000000000002',
  'd1000000-0000-4000-8000-000000000001'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000002';
select is(
  public.list_public_profile_templates(
    'd1000000-0000-4000-8000-000000000001',
    20,
    null,
    null
  ),
  null::jsonb,
  'caller-to-owner blocking suppresses the public profile'
);
select is(
  public.get_public_template(
    'd1000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000001'
  ),
  null::jsonb,
  'caller-to-owner blocking suppresses direct detail'
);
select throws_ok(
  $$select * from public.copy_public_template(
      'd2000000-0000-4000-8000-000000000001',
      5,
      'd6000000-0000-4000-8000-000000000001'
    )$$,
  'P0002',
  'template unavailable',
  'caller-to-owner blocking suppresses copy'
);
reset role;
delete from public.user_blocks
where blocker_id = 'd1000000-0000-4000-8000-000000000002'
  and blocked_id = 'd1000000-0000-4000-8000-000000000001';

insert into public.user_blocks(blocker_id, blocked_id)
values (
  'd1000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000002'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000002';
select is(
  public.list_public_profile_templates(
    'd1000000-0000-4000-8000-000000000001',
    20,
    null,
    null
  ),
  null::jsonb,
  'owner-to-caller blocking suppresses the public profile'
);
reset role;
delete from public.user_blocks
where blocker_id = 'd1000000-0000-4000-8000-000000000001'
  and blocked_id = 'd1000000-0000-4000-8000-000000000002';

delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000002';
insert into public_template_values(label, value_uuid, value_bigint)
select
  'copied',
  copied.template_id,
  copied.version
from public.copy_public_template(
  'd2000000-0000-4000-8000-000000000001',
  5,
  'd6000000-0000-4000-8000-000000000002'
) as copied;
reset role;

select ok(
  exists (
    select 1
    from public.templates as copied_template
    where copied_template.id = (
      select value_uuid
      from public_template_values
      where label = 'copied'
    )
      and copied_template.owner_id =
        'd1000000-0000-4000-8000-000000000002'
      and copied_template.category_id is null
      and copied_template.published_at is null
      and copied_template.name = 'Public kit edited'
  ),
  'copy is caller-owned, private, Uncategorized, and preserves the name'
);
select is(
  (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_array(
        copied_item.name,
        copied_item.quantity_thousandths,
        copied_item.position
      )
      order by copied_item.position
    )
    from public.template_items as copied_item
    where copied_item.template_id = (
      select value_uuid
      from public_template_values
      where label = 'copied'
    )
  ),
  '[["Water", 1500, 1], ["Water", 2000, 2]]'::jsonb,
  'copy preserves exact ordered names and quantities without merging duplicates'
);
select ok(
  not exists (
    select 1
    from public.template_items as copied_item
    where copied_item.template_id = (
      select value_uuid
      from public_template_values
      where label = 'copied'
    )
      and copied_item.id in (
        'd4000000-0000-4000-8000-000000000001',
        'd4000000-0000-4000-8000-000000000002'
      )
  ),
  'every copied item has a new identity'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_copy_requests
    where owner_id = 'd1000000-0000-4000-8000-000000000002'
      and request_id = 'd6000000-0000-4000-8000-000000000002'
      and pg_catalog.octet_length(request_fingerprint) = 32
  ),
  1::bigint,
  'copy records one 32-byte fingerprint-bound ledger entry'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000002';
select is(
  (
    select copied.template_id
    from public.copy_public_template(
      'd2000000-0000-4000-8000-000000000001',
      5,
      'd6000000-0000-4000-8000-000000000002'
    ) as copied
  ),
  (
    select value_uuid
    from public_template_values
    where label = 'copied'
  ),
  'an identical completed retry returns the same destination'
);
select throws_ok(
  $$select * from public.copy_public_template(
      'd2000000-0000-4000-8000-000000000002',
      2,
      'd6000000-0000-4000-8000-000000000002'
    )$$,
  '23505',
  'public template copy request conflict',
  'request UUID reuse with another source/version fingerprint is rejected'
);
select throws_ok(
  $$select * from public.copy_public_template(
      'd2000000-0000-4000-8000-000000000001',
      4,
      'd6000000-0000-4000-8000-000000000003'
    )$$,
  '40001',
  'template changed',
  'stale public source versions write no copy'
);
select throws_ok(
  $$select * from public.copy_public_template(
      'd2000000-0000-4000-8000-000000000003',
      1,
      'd6000000-0000-4000-8000-000000000004'
    )$$,
  'P0002',
  'template unavailable',
  'private sources cannot be copied'
);
reset role;

select ok(
  (
    select pg_catalog.count(*)
    from realtime.messages as message
    where message.topic =
      'account:d1000000-0000-4000-8000-000000000002'
      and message.extension = 'broadcast'
      and message.event = 'invalidate'
      and message.private
      and message.payload - 'id' = '{"v":1}'::jsonb
  ) >= 1
  and not exists (
    select 1
    from realtime.messages as message
    where message.topic =
      'account:d1000000-0000-4000-8000-000000000003'
  ),
  'copy reuses opaque copier-only invalidation and no public fanout'
);
select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where recipient_id = 'd1000000-0000-4000-8000-000000000002'
  ),
  0::bigint,
  'public template copy creates no persistent notification'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000001';
insert into public_template_values(label, value_uuid)
select
  'self-copy',
  copied.template_id
from public.copy_public_template(
  'd2000000-0000-4000-8000-000000000002',
  2,
  'd6000000-0000-4000-8000-000000000005'
) as copied;
select ok(
  (
    select value_uuid
    from public_template_values
    where label = 'self-copy'
  ) is not null,
  'source owners may save their own public template as an independent copy'
);

insert into public_template_values(label, value_json)
values ('export-v9', public.export_own_account_data_v9());
select is(
  (
    select (value_json ->> 'schema_version')::integer
    from public_template_values
    where label = 'export-v9'
  ),
  9,
  'current account export is schema version 9'
);
select ok(
  (
    select pg_catalog.bool_and(
      template_document ? 'is_public'
      and template_document ? 'published_at'
    )
    from public_template_values as exported,
    lateral pg_catalog.jsonb_array_elements(
      exported.value_json -> 'templates'
    ) as template_document
    where exported.label = 'export-v9'
  ),
  'every v9 caller-owned template has exactly the publication extension'
);
select ok(
  not ((
    public.export_own_account_data_v8() -> 'templates' -> 0
  ) ? 'is_public')
  and not ((
    public.export_own_account_data_v8() -> 'templates' -> 0
  ) ? 'published_at'),
  'legacy export v8 template shapes remain unchanged'
);
select ok(
  pg_catalog.strpos(
    (
      select value_json::text
      from public_template_values
      where label = 'export-v9'
    ),
    'd6000000-0000-4000-8000-000000000005'
  ) = 0,
  'export omits copy request UUIDs and the private ledger'
);
reset role;

insert into public.templates (
  owner_id,
  name,
  creation_request_id
)
select
  'd1000000-0000-4000-8000-000000000005',
  'Quota template ' || sequence_value,
  pg_catalog.gen_random_uuid()
from pg_catalog.generate_series(1, 100) as sequence_value;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000005';
select throws_ok(
  $$select * from public.copy_public_template(
      'd2000000-0000-4000-8000-000000000001',
      5,
      'd6000000-0000-4000-8000-000000000006'
    )$$,
  '54000',
  'template capacity reached',
  'destination quota exhaustion creates no partial copy'
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_copy_requests
    where owner_id = 'd1000000-0000-4000-8000-000000000005'
  ),
  0::bigint,
  'quota failure creates no retry-ledger row'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'd1000000-0000-4000-8000-000000000001';
select * from public.delete_private_template(
  'd2000000-0000-4000-8000-000000000001',
  5
);
reset role;
select ok(
  exists (
    select 1
    from public.templates
    where id = (
      select value_uuid
      from public_template_values
      where label = 'copied'
    )
  )
  and exists (
    select 1
    from private.public_template_copy_requests
    where owner_id = 'd1000000-0000-4000-8000-000000000002'
      and request_id = 'd6000000-0000-4000-8000-000000000002'
  ),
  'source deletion leaves completed independent copies and their retry result'
);

select * from finish();
rollback;
