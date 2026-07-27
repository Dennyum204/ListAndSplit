begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_function(
  'public',
  'list_friend_public_template_feed',
  array['integer', 'timestamp with time zone', 'uuid'],
  'the exact friends public-template feed RPC exists'
);
select is(
  (
    select function_record.prorettype = 'jsonb'::regtype
      and function_record.provolatile = 's'
      and function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'public.list_friend_public_template_feed(integer,timestamptz,uuid)'::regprocedure
  ),
  true,
  'the feed is a postgres-owned stable hardened definer returning JSONB'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.list_friend_public_template_feed(integer,timestamptz,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.list_friend_public_template_feed(integer,timestamptz,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.list_friend_public_template_feed(integer,timestamptz,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'public',
    'public.list_friend_public_template_feed(integer,timestamptz,uuid)',
    'EXECUTE'
  ),
  'only authenticated has the exact feed execution grant'
);
select is(
  obj_description(
    'public.list_friend_public_template_feed(integer,timestamptz,uuid)'::regprocedure,
    'pg_proc'
  ),
  'Current-friends-only bounded public-template page with block, report, and moderation filtering.',
  'the RPC has its durable catalog contract'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as relation_record
    join pg_catalog.pg_namespace as namespace_record
      on namespace_record.oid = relation_record.relnamespace
    where relation_record.relkind in ('r', 'p')
      and (
        relation_record.relname like '%friend%template%feed%'
        or relation_record.relname like '%template%feed%'
      )
  ),
  0::bigint,
  'the read-through feed creates no stored feed table'
);
select is(
  (
    select pg_catalog.count(*)
    from cron.job
    where jobname like '%feed%'
  ),
  0::bigint,
  'the feed adds no Cron job'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_publication_tables as published_table
    where published_table.tablename like '%feed%'
  ),
  0::bigint,
  'the feed adds no Realtime publication'
);
select is(
  to_regclass('public.templates_public_keyset_idx'),
  null::regclass,
  'no speculative global public-template index is installed'
);
select has_index(
  'public',
  'templates',
  'templates_owner_public_keyset_idx',
  'the owner-first public-template index remains available'
);

set local role anon;
select throws_like(
  $$select public.list_friend_public_template_feed(20, null, null)$$,
  '%permission denied%function%list_friend_public_template_feed%',
  'anonymous clients cannot execute the feed'
);
reset role;

set local role service_role;
select throws_like(
  $$select public.list_friend_public_template_feed(20, null, null)$$,
  '%permission denied%function%list_friend_public_template_feed%',
  'service-role API calls cannot execute the feed'
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
  ('f1000000-0000-4000-8000-000000000001', 'feed-caller@example.test', now(), now(), now()),
  ('f1000000-0000-4000-8000-000000000002', 'feed-friend-a@example.test', now(), now(), now()),
  ('f1000000-0000-4000-8000-000000000003', 'feed-friend-b@example.test', now(), now(), now()),
  ('f1000000-0000-4000-8000-000000000004', 'feed-nonfriend@example.test', now(), now(), now()),
  ('f1000000-0000-4000-8000-000000000005', 'feed-pending@example.test', now(), now(), now()),
  ('f1000000-0000-4000-8000-000000000006', 'feed-declined@example.test', now(), now(), now()),
  ('f1000000-0000-4000-8000-000000000007', 'feed-cancelled@example.test', now(), now(), now()),
  ('f1000000-0000-4000-8000-000000000008', 'feed-ended@example.test', now(), now(), now()),
  ('f1000000-0000-4000-8000-000000000009', 'feed-incomplete@example.test', now(), now(), now()),
  ('f1000000-0000-4000-8000-00000000000a', 'feed-unverified@example.test', null, now(), now());

update public.profiles
set username = case id
      when 'f1000000-0000-4000-8000-000000000001' then 'feed_caller'
      when 'f1000000-0000-4000-8000-000000000002' then 'feed_friend_a'
      when 'f1000000-0000-4000-8000-000000000003' then 'feed_friend_b'
      when 'f1000000-0000-4000-8000-000000000004' then 'feed_nonfriend'
      when 'f1000000-0000-4000-8000-000000000005' then 'feed_pending'
      when 'f1000000-0000-4000-8000-000000000006' then 'feed_declined'
      when 'f1000000-0000-4000-8000-000000000007' then 'feed_cancelled'
      when 'f1000000-0000-4000-8000-000000000008' then 'feed_ended'
      when 'f1000000-0000-4000-8000-00000000000a' then 'feed_unverified'
    end,
    display_name = case id
      when 'f1000000-0000-4000-8000-000000000001' then 'Feed Caller'
      when 'f1000000-0000-4000-8000-000000000002' then 'Feed Friend A'
      when 'f1000000-0000-4000-8000-000000000003' then 'Feed Friend B'
      when 'f1000000-0000-4000-8000-000000000004' then 'Feed Nonfriend'
      when 'f1000000-0000-4000-8000-000000000005' then 'Feed Pending'
      when 'f1000000-0000-4000-8000-000000000006' then 'Feed Declined'
      when 'f1000000-0000-4000-8000-000000000007' then 'Feed Cancelled'
      when 'f1000000-0000-4000-8000-000000000008' then 'Feed Ended'
      when 'f1000000-0000-4000-8000-00000000000a' then 'Feed Unverified'
    end
where id <> 'f1000000-0000-4000-8000-000000000009';

insert into public.user_relationships (
  profile_low_id,
  profile_high_id,
  state,
  requester_id,
  reopen_by_id
)
values
  ('f1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000002', 'friends', 'f1000000-0000-4000-8000-000000000001', null),
  ('f1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000003', 'friends', 'f1000000-0000-4000-8000-000000000003', null),
  ('f1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000005', 'pending', 'f1000000-0000-4000-8000-000000000005', null),
  ('f1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000006', 'declined', 'f1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000006'),
  ('f1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000007', 'cancelled', 'f1000000-0000-4000-8000-000000000007', null),
  ('f1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000008', 'ended', 'f1000000-0000-4000-8000-000000000008', 'f1000000-0000-4000-8000-000000000008'),
  ('f1000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000009', 'friends', 'f1000000-0000-4000-8000-000000000001', null);

insert into public.templates (
  id,
  owner_id,
  name,
  version,
  published_at,
  creation_request_id
)
values
  ('f2000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001', 'Own public', 1, '2026-07-02 12:00:00+00', 'f3000000-0000-4000-8000-000000000001'),
  ('f2000000-0000-4000-8000-000000000101', 'f1000000-0000-4000-8000-000000000002', 'Friend A same one', 1, '2026-07-01 12:00:00+00', 'f3000000-0000-4000-8000-000000000101'),
  ('f2000000-0000-4000-8000-000000000102', 'f1000000-0000-4000-8000-000000000002', 'Friend A same two', 1, '2026-07-01 12:00:00+00', 'f3000000-0000-4000-8000-000000000102'),
  ('f2000000-0000-4000-8000-000000000103', 'f1000000-0000-4000-8000-000000000002', 'Friend A blank', 1, '2026-06-01 12:00:00+00', 'f3000000-0000-4000-8000-000000000103'),
  ('f2000000-0000-4000-8000-000000000104', 'f1000000-0000-4000-8000-000000000002', 'Friend A old', 1, '2020-01-01 00:00:00+00', 'f3000000-0000-4000-8000-000000000104'),
  ('f2000000-0000-4000-8000-000000000105', 'f1000000-0000-4000-8000-000000000002', 'Friend A reported', 1, '2026-07-04 12:00:00+00', 'f3000000-0000-4000-8000-000000000105'),
  ('f2000000-0000-4000-8000-000000000106', 'f1000000-0000-4000-8000-000000000002', 'Friend A restricted', 1, '2026-07-03 12:00:00+00', 'f3000000-0000-4000-8000-000000000106'),
  ('f2000000-0000-4000-8000-000000000107', 'f1000000-0000-4000-8000-000000000002', 'Friend A private', 1, null, 'f3000000-0000-4000-8000-000000000107'),
  ('f2000000-0000-4000-8000-000000000201', 'f1000000-0000-4000-8000-000000000003', 'Friend B same', 1, '2026-07-01 12:00:00+00', 'f3000000-0000-4000-8000-000000000201'),
  ('f2000000-0000-4000-8000-000000000301', 'f1000000-0000-4000-8000-000000000004', 'Nonfriend public', 1, '2026-07-05 12:00:00+00', 'f3000000-0000-4000-8000-000000000301'),
  ('f2000000-0000-4000-8000-000000000501', 'f1000000-0000-4000-8000-000000000005', 'Pending public', 1, '2026-07-05 12:00:00+00', 'f3000000-0000-4000-8000-000000000501'),
  ('f2000000-0000-4000-8000-000000000601', 'f1000000-0000-4000-8000-000000000006', 'Declined public', 1, '2026-07-05 12:00:00+00', 'f3000000-0000-4000-8000-000000000601'),
  ('f2000000-0000-4000-8000-000000000701', 'f1000000-0000-4000-8000-000000000007', 'Cancelled public', 1, '2026-07-05 12:00:00+00', 'f3000000-0000-4000-8000-000000000701'),
  ('f2000000-0000-4000-8000-000000000801', 'f1000000-0000-4000-8000-000000000008', 'Ended public', 1, '2026-07-05 12:00:00+00', 'f3000000-0000-4000-8000-000000000801'),
  ('f2000000-0000-4000-8000-000000000901', 'f1000000-0000-4000-8000-000000000009', 'Incomplete owner public', 1, '2026-07-06 12:00:00+00', 'f3000000-0000-4000-8000-000000000901');

insert into public.template_items (
  id,
  template_id,
  name,
  quantity_thousandths,
  position,
  creation_request_id
)
values
  ('f4000000-0000-4000-8000-000000000101', 'f2000000-0000-4000-8000-000000000101', 'Water', 1000, 1, 'f5000000-0000-4000-8000-000000000101'),
  ('f4000000-0000-4000-8000-000000000102', 'f2000000-0000-4000-8000-000000000102', 'Hat', 1000, 1, 'f5000000-0000-4000-8000-000000000102'),
  ('f4000000-0000-4000-8000-000000000201', 'f2000000-0000-4000-8000-000000000201', 'Map', 1000, 1, 'f5000000-0000-4000-8000-000000000201');

insert into private.public_template_moderation_restrictions (
  template_id,
  template_owner_id,
  template_name,
  reason_code,
  active,
  imposed_at,
  updated_at
)
values (
  'f2000000-0000-4000-8000-000000000106',
  'f1000000-0000-4000-8000-000000000002',
  'Friend A restricted',
  'spam_scam_deceptive',
  true,
  now(),
  now()
);

create temporary table feed_documents (
  label text primary key,
  document jsonb not null
) on commit drop;
grant select, insert, update, delete on feed_documents to authenticated;

set local role authenticated;
select throws_ok(
  $$select public.list_friend_public_template_feed(20, null, null)$$,
  '42501',
  'verified profile required',
  'an authenticated role without an identity is denied'
);

set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000009';
select throws_ok(
  $$select public.list_friend_public_template_feed(20, null, null)$$,
  '42501',
  'verified profile required',
  'an incomplete caller is denied'
);

set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-00000000000a';
select throws_ok(
  $$select public.list_friend_public_template_feed(20, null, null)$$,
  '42501',
  'verified profile required',
  'an unverified caller is denied'
);

set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select public.report_public_template(
  'f2000000-0000-4000-8000-000000000105',
  1,
  'spam_scam_deceptive',
  null
);

insert into feed_documents (label, document)
values (
  'full',
  public.list_friend_public_template_feed(20, null, null)
);

select is(
  (
    select pg_catalog.array_agg(entry -> 'template' ->> 'template_id')
    from feed_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'entries'
    ) as entry
    where label = 'full'
  ),
  array[
    'f2000000-0000-4000-8000-000000000201',
    'f2000000-0000-4000-8000-000000000102',
    'f2000000-0000-4000-8000-000000000101',
    'f2000000-0000-4000-8000-000000000103',
    'f2000000-0000-4000-8000-000000000104'
  ]::text[],
  'only current friends appear in publication-time and UUID order with no age cutoff'
);
select is(
  (
    select document -> 'next_cursor'
    from feed_documents
    where label = 'full'
  ),
  'null'::jsonb,
  'a complete page has no cursor'
);
select is(
  (
    select pg_catalog.array_agg(root_key order by root_key)
    from feed_documents
    cross join lateral pg_catalog.jsonb_object_keys(document) as root_key
    where label = 'full'
  ),
  array['entries', 'next_cursor']::text[],
  'the feed root contains only entries and cursor'
);
select is(
  (
    select pg_catalog.array_agg(entry_key order by entry_key)
    from feed_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'entries'
    ) as entry
    cross join lateral pg_catalog.jsonb_object_keys(entry) as entry_key
    where label = 'full'
      and entry -> 'template' ->> 'template_id' =
        'f2000000-0000-4000-8000-000000000201'
  ),
  array['profile', 'template']::text[],
  'each entry exposes only profile and template objects'
);
select is(
  (
    select pg_catalog.array_agg(profile_key order by profile_key)
    from feed_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'entries'
    ) as entry
    cross join lateral pg_catalog.jsonb_object_keys(
      entry -> 'profile'
    ) as profile_key
    where label = 'full'
      and entry -> 'template' ->> 'template_id' =
        'f2000000-0000-4000-8000-000000000201'
  ),
  array['display_name', 'profile_id', 'username']::text[],
  'profile output is the exact approved identity allowlist'
);
select is(
  (
    select pg_catalog.array_agg(template_key order by template_key)
    from feed_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'entries'
    ) as entry
    cross join lateral pg_catalog.jsonb_object_keys(
      entry -> 'template'
    ) as template_key
    where label = 'full'
      and entry -> 'template' ->> 'template_id' =
        'f2000000-0000-4000-8000-000000000201'
  ),
  array[
    'item_count',
    'name',
    'published_at',
    'template_id',
    'version'
  ]::text[],
  'template output is the exact approved public summary allowlist'
);
select is(
  (
    select (entry -> 'template' ->> 'item_count')::bigint
    from feed_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'entries'
    ) as entry
    where label = 'full'
      and entry -> 'template' ->> 'template_id' =
        'f2000000-0000-4000-8000-000000000103'
  ),
  0::bigint,
  'a blank public friend template appears with item count zero'
);
select ok(
  not (
    select document::text
    from feed_documents
    where label = 'full'
  ) ~ '(Own public|Nonfriend public|Pending public|Declined public|Cancelled public|Ended public|Incomplete owner|reported|restricted|private)',
  'self, incomplete-owner, nonfriend, dormant, private, reported, and restricted content is absent'
);

insert into feed_documents (label, document)
values (
  'page-one',
  public.list_friend_public_template_feed(2, null, null)
);
insert into feed_documents (label, document)
select
  'page-two',
  public.list_friend_public_template_feed(
    2,
    (document #>> '{next_cursor,published_at}')::timestamptz,
    (document #>> '{next_cursor,template_id}')::uuid
  )
from feed_documents
where label = 'page-one';
insert into feed_documents (label, document)
select
  'page-three',
  public.list_friend_public_template_feed(
    2,
    (document #>> '{next_cursor,published_at}')::timestamptz,
    (document #>> '{next_cursor,template_id}')::uuid
  )
from feed_documents
where label = 'page-two';

select is(
  (
    select pg_catalog.count(distinct entry -> 'template' ->> 'template_id')
    from feed_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'entries'
    ) as entry
    where label in ('page-one', 'page-two', 'page-three')
  ),
  5::bigint,
  'static multipage traversal returns every eligible template without duplicates'
);
select is(
  (
    select pg_catalog.count(*)
    from feed_documents
    cross join lateral pg_catalog.jsonb_array_elements(
      document -> 'entries'
    ) as entry
    where label in ('page-one', 'page-two', 'page-three')
  ),
  5::bigint,
  'static multipage traversal has no gaps or repeated rows'
);
select ok(
  (select document -> 'next_cursor' <> 'null'::jsonb from feed_documents where label = 'page-one')
  and (select document -> 'next_cursor' <> 'null'::jsonb from feed_documents where label = 'page-two')
  and (select document -> 'next_cursor' = 'null'::jsonb from feed_documents where label = 'page-three'),
  'overfetch produces cursors only while another row exists'
);

select throws_ok(
  $$select public.list_friend_public_template_feed(0, null, null)$$,
  '22023',
  'invalid public template query',
  'page size zero is rejected'
);
select throws_ok(
  $$select public.list_friend_public_template_feed(51, null, null)$$,
  '22023',
  'invalid public template query',
  'page sizes above fifty are rejected'
);
select throws_ok(
  $$select public.list_friend_public_template_feed(
      20,
      '2026-07-01 12:00:00+00',
      null
    )$$,
  '22023',
  'invalid public template query',
  'a partial timestamp cursor is rejected'
);
select throws_ok(
  $$select public.list_friend_public_template_feed(
      20,
      null,
      'f2000000-0000-4000-8000-000000000101'
    )$$,
  '22023',
  'invalid public template query',
  'a partial UUID cursor is rejected'
);
select lives_ok(
  $$select public.list_friend_public_template_feed(1, null, null)$$,
  'the exact minimum page size is accepted'
);
select lives_ok(
  $$select public.list_friend_public_template_feed(50, null, null)$$,
  'the exact maximum page size is accepted'
);

reset role;

update public.templates
set name = 'Friend A edited',
    version = version + 1,
    updated_at = pg_catalog.clock_timestamp()
where id = 'f2000000-0000-4000-8000-000000000101';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select is(
  (
    select entry -> 'template' ->> 'published_at'
    from pg_catalog.jsonb_array_elements(
      public.list_friend_public_template_feed(20, null, null) -> 'entries'
    ) as entry
    where entry -> 'template' ->> 'template_id' =
      'f2000000-0000-4000-8000-000000000101'
  ),
  '2026-07-01T12:00:00+00:00',
  'an ordinary edit preserves publication time and feed position'
);

reset role;
update public.user_relationships
set state = 'ended',
    reopen_by_id = 'f1000000-0000-4000-8000-000000000001',
    version = version + 1,
    state_changed_at = now()
where profile_low_id = 'f1000000-0000-4000-8000-000000000001'
  and profile_high_id = 'f1000000-0000-4000-8000-000000000002';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select is(
  pg_catalog.jsonb_array_length(
    public.list_friend_public_template_feed(20, null, null) -> 'entries'
  ),
  1,
  'friendship loss removes that owner on the next authoritative read'
);

reset role;
update public.user_relationships
set state = 'friends',
    reopen_by_id = null,
    version = version + 1,
    state_changed_at = now()
where profile_low_id = 'f1000000-0000-4000-8000-000000000001'
  and profile_high_id = 'f1000000-0000-4000-8000-000000000002';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select is(
  pg_catalog.jsonb_array_length(
    public.list_friend_public_template_feed(20, null, null) -> 'entries'
  ),
  5,
  'refriending restores currently eligible public templates'
);

reset role;
insert into public.user_blocks (blocker_id, blocked_id)
values (
  'f1000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000002'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select is(
  pg_catalog.jsonb_array_length(
    public.list_friend_public_template_feed(20, null, null) -> 'entries'
  ),
  1,
  'an outgoing block removes the friend owner'
);

reset role;
delete from public.user_blocks;
update public.user_relationships
set state = 'friends',
    reopen_by_id = null,
    version = version + 1,
    state_changed_at = now()
where profile_low_id = 'f1000000-0000-4000-8000-000000000001'
  and profile_high_id = 'f1000000-0000-4000-8000-000000000002';
insert into public.user_blocks (blocker_id, blocked_id)
values (
  'f1000000-0000-4000-8000-000000000002',
  'f1000000-0000-4000-8000-000000000001'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select is(
  pg_catalog.jsonb_array_length(
    public.list_friend_public_template_feed(20, null, null) -> 'entries'
  ),
  1,
  'an incoming block removes the friend owner'
);

reset role;
delete from public.user_blocks;
update public.user_relationships
set state = 'friends',
    reopen_by_id = null,
    version = version + 1,
    state_changed_at = now()
where profile_low_id = 'f1000000-0000-4000-8000-000000000001'
  and profile_high_id = 'f1000000-0000-4000-8000-000000000002';

update public.templates
set published_at = null,
    version = version + 1,
    updated_at = pg_catalog.clock_timestamp()
where id = 'f2000000-0000-4000-8000-000000000103';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select is(
  pg_catalog.jsonb_array_length(
    public.list_friend_public_template_feed(20, null, null) -> 'entries'
  ),
  4,
  'unpublication removes the source on refresh'
);

reset role;
update public.templates
set published_at = pg_catalog.clock_timestamp(),
    version = version + 1,
    updated_at = pg_catalog.clock_timestamp()
where id = 'f2000000-0000-4000-8000-000000000103';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select is(
  (
    public.list_friend_public_template_feed(20, null, null)
      #>> '{entries,0,template,template_id}'
  ),
  'f2000000-0000-4000-8000-000000000103',
  'republication receives a new position at the front'
);

reset role;
delete from public.templates
where id = 'f2000000-0000-4000-8000-000000000104';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select is(
  pg_catalog.jsonb_array_length(
    public.list_friend_public_template_feed(20, null, null) -> 'entries'
  ),
  4,
  'source deletion removes the entry without a retained feed row'
);
select ok(
  public.list_public_profile_templates(
    'f1000000-0000-4000-8000-000000000002',
    20,
    null,
    null
  ) is not null
  and public.get_public_template(
    'f1000000-0000-4000-8000-000000000002',
    'f2000000-0000-4000-8000-000000000101'
  ) is not null,
  'existing public profile listing and detail remain compatible'
);
select is(
  (
    select pg_catalog.count(*)
    from public.copy_public_template(
      'f2000000-0000-4000-8000-000000000101',
      2,
      'f6000000-0000-4000-8000-000000000001'
    )
  ),
  1::bigint,
  'the existing public copy RPC remains compatible'
);
select is(
  public.export_own_account_data_v11() ->> 'schema_version',
  '11',
  'account export remains schema version eleven'
);
select is(
  public.get_unread_notification_count_v5(),
  0::bigint,
  'notification v5 remains unchanged and feed-silent'
);

reset role;
delete from auth.users
where id = 'f1000000-0000-4000-8000-000000000003';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'f1000000-0000-4000-8000-000000000001';
select ok(
  not (
    public.list_friend_public_template_feed(20, null, null)::text
      like '%f1000000-0000-4000-8000-000000000003%'
  ),
  'friend account deletion removes its owner and templates from the projection'
);

select * from finish();
rollback;
