begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select no_plan();

-- Scalar state, RPC-only link table, indexes, and hardened boundaries.
select columns_are(
  'public',
  'active_list_note_mentions',
  array['list_id', 'mentioned_profile_id', 'resolved_at'],
  'General Note mentions store only stable current profile links'
);

select ok(
  (
    select table_record.relrowsecurity
      and table_record.relforcerowsecurity
    from pg_catalog.pg_class as table_record
    where table_record.oid =
      'public.active_list_note_mentions'::regclass
  ),
  'General Note mentions enable and force RLS'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'active_list_note_mentions'
      and policyname =
        'active_list_note_mentions_reject_direct_client_access'
      and permissive = 'RESTRICTIVE'
      and cmd = 'ALL'
      and roles = array['anon', 'authenticated']::name[]
      and qual = 'false'
      and with_check = 'false'
  ),
  1::bigint,
  'one restrictive policy rejects every direct anonymous/authenticated operation'
);

select ok(
  not has_table_privilege(
    'anon',
    'public.active_list_note_mentions',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.active_list_note_mentions',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.active_list_note_mentions',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'no Data API role has direct mention-table CRUD privileges'
);

select is(
  (
    select pg_catalog.array_agg(indexname order by indexname)
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'active_list_note_mentions'
  ),
  array[
    'active_list_note_mentions_pkey',
    'active_list_note_mentions_profile_list_idx'
  ]::name[],
  'mention identity and reverse lifecycle cleanup indexes are exact'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'active_lists'
      and column_name = 'general_note_text'
      and is_nullable = 'YES'
  )
  and exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'active_lists'
      and column_name = 'general_note_version'
      and is_nullable = 'NO'
      and column_default = '1'
  )
  and exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'active_lists'
      and column_name = 'general_note_updated_at'
      and is_nullable = 'YES'
  ),
  'active lists own optional scalar General Note state with version one default'
);

select ok(
  (
    select pg_catalog.array_agg(
      constraint_record.conname
      order by constraint_record.conname
    )
    from pg_catalog.pg_constraint as constraint_record
    where constraint_record.conname in (
      'active_lists_general_note_text_check',
      'active_lists_general_note_time_check',
      'active_lists_general_note_version_check',
      'active_list_note_mentions_pkey',
      'active_list_note_mentions_list_fkey',
      'active_list_note_mentions_profile_fkey'
    )
  ) = array[
    'active_list_note_mentions_list_fkey',
    'active_list_note_mentions_pkey',
    'active_list_note_mentions_profile_fkey',
    'active_lists_general_note_text_check',
    'active_lists_general_note_time_check',
    'active_lists_general_note_version_check'
  ]::name[]
  and (
    select pg_catalog.bool_and(
      constraint_record.confdeltype = 'c'
    )
    from pg_catalog.pg_constraint as constraint_record
    where constraint_record.conname in (
      'active_list_note_mentions_list_fkey',
      'active_list_note_mentions_profile_fkey'
    )
  ),
  'scalar note checks and stable-link primary/cascading foreign-key constraints are installed'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.get_active_list_general_note(uuid)'::regprocedure,
      'public.update_active_list_general_note(uuid,text,uuid[],bigint)'::regprocedure,
      'public.list_notifications_v3(integer,timestamptz,uuid)'::regprocedure,
      'public.get_unread_notification_count_v3()'::regprocedure,
      'public.export_own_account_data_v8()'::regprocedure
    )
      and function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
  ),
  5::bigint,
  'all five public additive RPCs are postgres-owned hardened definer boundaries'
);

select ok(
  (
    select pg_catalog.bool_and(
      has_function_privilege(
        'authenticated',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        function_record.oid,
        'EXECUTE'
      )
      and not has_function_privilege(
        'service_role',
        function_record.oid,
        'EXECUTE'
      )
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.get_active_list_general_note(uuid)'::regprocedure,
      'public.update_active_list_general_note(uuid,text,uuid[],bigint)'::regprocedure,
      'public.list_notifications_v3(integer,timestamptz,uuid)'::regprocedure,
      'public.get_unread_notification_count_v3()'::regprocedure,
      'public.export_own_account_data_v8()'::regprocedure
    )
  ),
  'only authenticated receives additive public RPC execution'
);

select ok(
  (
    select pg_catalog.bool_and(
      not has_function_privilege('anon', oid, 'EXECUTE')
      and not has_function_privilege('authenticated', oid, 'EXECUTE')
      and not has_function_privilege('service_role', oid, 'EXECUTE')
    )
    from pg_catalog.pg_proc
    where oid in (
      'private.normalize_active_list_general_note(text)'::regprocedure,
      'private.active_list_note_contains_username(text,text)'::regprocedure,
      'private.enforce_active_list_note_mention_eligibility()'::regprocedure,
      'private.build_active_list_note_mentions(uuid)'::regprocedure,
      'private.cleanup_active_list_profile_links(uuid,uuid,timestamptz)'::regprocedure,
      'private.cleanup_active_list_dependents_before_profile_delete()'::regprocedure,
      'private.build_active_list_general_note_export(uuid)'::regprocedure
    )
  ),
  'private note and lifecycle helpers have no Data API execution'
);

select ok(
  (
    select pg_catalog.bool_and(
      pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'update public.active_list_participants'
      ) > 0
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'private.cleanup_active_list_profile_links'
      ) > pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'update public.active_list_participants'
      )
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'private.suppress_active_list_profile_link_notifications'
      ) > pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'private.cleanup_active_list_profile_links'
      )
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'update public.active_lists'
      ) > pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'private.suppress_active_list_profile_link_notifications'
      )
      and pg_catalog.pg_get_functiondef(function_record.oid)
        not like '%private.cleanup_active_list_item_assignments_for_profile%'
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.remove_active_list_member(uuid,uuid,bigint)'::regprocedure,
      'public.leave_active_list(uuid,bigint)'::regprocedure,
      'public.block_profile(uuid)'::regprocedure
    )
  ),
  'remove, leave, and block persist access-before-links-before-suppression with one final parent update'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_trigger
    where not tgisinternal
      and tgname in (
        'profiles_anonymize_split_participants_before_delete',
        'profiles_cleanup_item_assignments_before_delete'
      )
  )
  and exists (
    select 1
    from pg_catalog.pg_trigger
    where not tgisinternal
      and tgname =
        'profiles_cleanup_active_list_dependents_before_delete'
      and tgfoid =
        'private.cleanup_active_list_dependents_before_profile_delete()'
          ::regprocedure
  ),
  'one parent-first profile-delete coordinator supersedes both child-first triggers'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_trigger
    where not tgisinternal
      and tgrelid = 'public.profiles'::regclass
      and tgname = 'profiles_broadcast_invalidation_before_delete'
  )
  and (
    select pg_catalog.strpos(
      pg_catalog.pg_get_functiondef(function_record.oid),
      'into invalidation_recipient_ids'
    ) > 0
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'private.cleanup_active_list_profile_links'
      ) > pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'into invalidation_recipient_ids'
      )
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'update public.active_list_split_participants'
      ) > pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'private.cleanup_active_list_profile_links'
      )
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'private.suppress_active_list_profile_link_notifications'
      ) > pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'update public.active_list_split_participants'
      )
      and pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'private.send_account_invalidations'
      ) > pg_catalog.strpos(
        pg_catalog.pg_get_functiondef(function_record.oid),
        'private.suppress_active_list_profile_link_notifications'
      )
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'private.cleanup_active_list_dependents_before_profile_delete()'
        ::regprocedure
  ),
  'one coordinator captures recipients before child cleanup and sends one final invalidation set'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger
    where tgrelid = 'public.active_list_participants'::regclass
      and tgname in (
        'active_list_participants_sync_split_identity',
        'active_list_participants_broadcast_invalidation'
      )
      and tgdeferrable
      and not tginitdeferred
  ),
  2::bigint,
  'existing participant Split and Broadcast triggers are initially immediate but deferrable for ordered lifecycle RPCs'
);

select ok(
  private.active_list_note_contains_username(
    E'Hello,\n@FERNANDO!',
    'fernando'
  )
  and private.active_list_note_contains_username(
    '(@fernando)',
    'fernando'
  )
  and not private.active_list_note_contains_username(
    'name@fernando',
    'fernando'
  )
  and not private.active_list_note_contains_username(
    '@@fernando',
    'fernando'
  )
  and not private.active_list_note_contains_username(
    '@fernando@example',
    'fernando'
  )
  and not private.active_list_note_contains_username(
    '@fernando_extra',
    'fernando'
  )
  and not private.active_list_note_contains_username(
    '@NÖTEMEMBER',
    'notemember'
  ),
  'full-token matching uses ASCII-only folding and rejects email, doubled-at, partial, and non-ASCII-confusable tokens'
);

select is(
  private.normalize_active_list_general_note(
    E'\u00a0 First\r\nSecond\rThird \u3000'
  ),
  E'First\nSecond\nThird',
  'normalization matches Flutter Unicode trim and CRLF/CR conversion'
);

-- Verified identities and one authoritative shared-list fixture.
insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('b1000000-0000-4000-8000-000000000001', 'note-owner@example.test', now(), now(), now()),
  ('b1000000-0000-4000-8000-000000000002', 'note-member@example.test', now(), now(), now()),
  ('b1000000-0000-4000-8000-000000000003', 'note-second@example.test', now(), now(), now()),
  ('b1000000-0000-4000-8000-000000000004', 'note-pending@example.test', now(), now(), now()),
  ('b1000000-0000-4000-8000-000000000005', 'note-removed@example.test', now(), now(), now()),
  ('b1000000-0000-4000-8000-000000000006', 'note-stranger@example.test', now(), now(), now()),
  ('b1000000-0000-4000-8000-000000000007', 'note-incomplete@example.test', now(), now(), now()),
  ('b1000000-0000-4000-8000-000000000008', 'note-delete@example.test', now(), now(), now()),
  ('b1000000-0000-4000-8000-000000000009', 'note-reserved@example.test', now(), now(), now());

update public.profiles
set username = case id
      when 'b1000000-0000-4000-8000-000000000001' then 'noteowner'
      when 'b1000000-0000-4000-8000-000000000002' then 'notemember'
      when 'b1000000-0000-4000-8000-000000000003' then 'notesecond'
      when 'b1000000-0000-4000-8000-000000000004' then 'notepending'
      when 'b1000000-0000-4000-8000-000000000005' then 'noteremoved'
      when 'b1000000-0000-4000-8000-000000000006' then 'notestranger'
      when 'b1000000-0000-4000-8000-000000000008' then 'notedelete'
      when 'b1000000-0000-4000-8000-000000000009' then 'notereserved'
    end,
    display_name = 'Note ' || right(id::text, 2)
where id in (
  'b1000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000002',
  'b1000000-0000-4000-8000-000000000003',
  'b1000000-0000-4000-8000-000000000004',
  'b1000000-0000-4000-8000-000000000005',
  'b1000000-0000-4000-8000-000000000006',
  'b1000000-0000-4000-8000-000000000008',
  'b1000000-0000-4000-8000-000000000009'
);

update public.profiles
set username = 'noteincomplete'
where id = 'b1000000-0000-4000-8000-000000000007';

insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id,
  created_at,
  updated_at
)
values (
  'b2000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000001',
  'General Note list',
  'b3000000-0000-4000-8000-000000000001',
  '2026-07-25 00:00:00+00',
  '2026-07-25 00:00:00+00'
);

insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state,
  version
)
values
  ('b2000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002', 'member', 1),
  ('b2000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000003', 'member', 1),
  ('b2000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000004', 'pending', 1),
  ('b2000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000005', 'removed', 2);

insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values (
  'b2000000-0000-4000-8000-000000000009',
  'b1000000-0000-4000-8000-000000000001',
  'General Note normalization',
  'b3000000-0000-4000-8000-000000000009'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000009',
    E' \r\n\t ',
    '{}'::uuid[],
    1
  )$$,
  'whitespace-only note normalizes to the existing null no-op'
);
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000009',
    E'  line one\r\nline two  ',
    '{}'::uuid[],
    1
  )$$,
  'trimmed multiline note is stored after newline normalization'
);
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000009',
    null,
    '{}'::uuid[],
    2
  )$$,
  'explicit null clears a populated General Note'
);
reset role;

select ok(
  (
    select general_note_text is null
      and general_note_version = 3
      and general_note_updated_at is null
      and version = 3
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000009'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-000000000009'
  ),
  'empty/null semantics clear scalar and link state without retaining a timestamp'
);

set local role anon;
select throws_like(
  $$select * from public.active_list_note_mentions$$,
  '%permission denied%',
  'anonymous direct mention SELECT is denied'
);
select throws_like(
  $$select * from public.get_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001'
  )$$,
  '%permission denied%',
  'anonymous note RPC execution is denied'
);
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select throws_like(
  $$select * from public.get_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001'
  )$$,
  '%verified profile required%',
  'authenticated role without a verified session is denied'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select throws_like(
  $$insert into public.active_list_note_mentions (
    list_id,
    mentioned_profile_id
  ) values (
    'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000001'
  )$$,
  '%permission denied%',
  'authenticated direct mention INSERT is denied'
);
select throws_like(
  $$update public.active_list_note_mentions
    set resolved_at = pg_catalog.clock_timestamp()$$,
  '%permission denied%',
  'authenticated direct mention UPDATE is denied'
);
select throws_like(
  $$delete from public.active_list_note_mentions$$,
  '%permission denied%',
  'authenticated direct mention DELETE is denied'
);
reset role;

delete from realtime.messages;
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    E'\u00a0 Hello,\r\n@NOTEMEMBER and @noteowner! \u3000',
    array[
      'b1000000-0000-4000-8000-000000000002'::uuid,
      'b1000000-0000-4000-8000-000000000001'::uuid,
      'b1000000-0000-4000-8000-000000000002'::uuid
    ],
    1
  )$$,
  'owner atomically writes normalized note text and a deduplicated mention set'
);
reset role;

select ok(
  (
    select general_note_text =
        E'Hello,\n@NOTEMEMBER and @noteowner!'
      and general_note_version = 2
      and version = 2
      and general_note_updated_at is not null
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 2
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-000000000001'
  ),
  'one real write advances note/list once and stores two stable links'
);

select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and active_list_id =
        'b2000000-0000-4000-8000-000000000001'
      and recipient_id =
        'b1000000-0000-4000-8000-000000000002'
      and actor_id =
        'b1000000-0000-4000-8000-000000000001'
      and general_note_version = 2
  ),
  1::bigint,
  'one add-only mention notification is created for the other newly resolved profile'
);

select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and recipient_id =
        'b1000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'self-mention resolves without a persistent notification'
);

select ok(
  (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:b1000000-0000-4000-8000-000000000001'
      and event = 'invalidate'
      and extension = 'broadcast'
      and payload - 'id' = '{"v":1}'::jsonb
      and private
  )
  and (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:b1000000-0000-4000-8000-000000000002'
      and event = 'invalidate'
      and extension = 'broadcast'
      and payload - 'id' = '{"v":1}'::jsonb
      and private
  )
  and (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:b1000000-0000-4000-8000-000000000003'
      and event = 'invalidate'
      and extension = 'broadcast'
      and payload - 'id' = '{"v":1}'::jsonb
      and private
  ),
  'note mutation reuses opaque private account invalidation for all current participants'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000002';
select ok(
  (
    select general_note_text =
        E'Hello,\n@NOTEMEMBER and @noteowner!'
      and general_note_version = 2
      and list_version = 2
      and pg_catalog.jsonb_array_length(mentions) = 2
      and mentions #>> '{0,username}' = 'notemember'
      and mentions #>> '{1,username}' = 'noteowner'
    from public.get_active_list_general_note(
      'b2000000-0000-4000-8000-000000000001'
    )
  ),
  'accepted member reads normalized note and deterministic live mention projection'
);
select is(
  (
    select pg_catalog.count(*)
    from public.list_notifications(20, null, null)
    where notification_type = 'list_note_mentioned'
  ),
  0::bigint,
  'notification v1 hides General Note mentions'
);
select is(
  (
    select pg_catalog.count(*)
    from public.list_notifications_v2(20, null, null)
    where notification_type = 'list_note_mentioned'
  ),
  0::bigint,
  'notification v2 hides General Note mentions'
);
select ok(
  (
    select general_note_version = 2
      and active_list_id =
        'b2000000-0000-4000-8000-000000000001'
      and active_list_title = 'General Note list'
      and action_status = 'unavailable'
      and active_list_item_id is null
      and assignment_item_version is null
    from public.list_notifications_v3(20, null, null)
    where notification_type = 'list_note_mentioned'
  ),
  'notification v3 exposes only live actor/list identity plus note version'
);
select is(
  public.get_unread_notification_count(),
  0::bigint,
  'v1 unread count hides note mentions'
);
select is(
  public.get_unread_notification_count_v2(),
  0::bigint,
  'v2 unread count hides note mentions'
);
select is(
  public.get_unread_notification_count_v3(),
  1::bigint,
  'v3 unread count includes the visible note mention'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000004';
select throws_ok(
  $$select * from public.get_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001'
  )$$,
  'P0002',
  'list unavailable',
  'pending participant cannot read the General Note'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000005';
select throws_ok(
  $$select * from public.get_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001'
  )$$,
  'P0002',
  'list unavailable',
  'removed historical participant cannot read the General Note'
);
reset role;

insert into public.user_blocks (blocker_id, blocked_id)
values (
  'b1000000-0000-4000-8000-000000000003',
  'b1000000-0000-4000-8000-000000000001'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select * from public.get_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001'
  )$$,
  'P0002',
  'list unavailable',
  'blocked accepted participant cannot read the General Note'
);
reset role;
delete from public.user_blocks
where blocker_id = 'b1000000-0000-4000-8000-000000000003'
  and blocked_id = 'b1000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000006';
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    'forged',
    '{}'::uuid[],
    2
  )$$,
  'P0002',
  'list unavailable',
  'unrelated user cannot discover or mutate the General Note'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    '@notemember',
    array['b1000000-0000-4000-8000-000000000002'::uuid],
    2
  )$$,
  'P0002',
  'list unavailable',
  'inaccessible list with an otherwise valid target returns generic unavailability'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    '@missing',
    array['b1ffffff-ffff-4fff-8fff-ffffffffffff'::uuid],
    2
  )$$,
  'P0002',
  'list unavailable',
  'inaccessible list with a nonexistent forged target is indistinguishable'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    '@noteincomplete',
    array['b1000000-0000-4000-8000-000000000007'::uuid],
    2
  )$$,
  'P0002',
  'list unavailable',
  'inaccessible list with an incomplete forged target is indistinguishable'
);
reset role;

select pg_catalog.set_config(
  'note.realtime_before_retry',
  (select pg_catalog.count(*)::text from realtime.messages),
  true
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    E'Hello,\n@NOTEMEMBER and @noteowner!',
    array[
      'b1000000-0000-4000-8000-000000000001'::uuid,
      'b1000000-0000-4000-8000-000000000002'::uuid
    ],
    1
  )$$,
  'payload-equivalent completed retry accepts prior version and canonical order'
);
reset role;

select ok(
  (
    select version = 2 and general_note_version = 2
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and active_list_id =
        'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) =
      pg_catalog.current_setting('note.realtime_before_retry')::bigint
    from realtime.messages
  ),
  'equivalent retry creates no extra version, notification, or invalidation'
);

select pg_catalog.set_config(
  'note.realtime_before_stale_failure',
  (select pg_catalog.count(*)::text from realtime.messages),
  true
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    'different',
    '{}'::uuid[],
    1
  )$$,
  '40001',
  'list changed',
  'payload-different stale write uses established serialization failure'
);
reset role;

select ok(
  (
    select version = 2 and general_note_version = 2
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 2
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) =
      pg_catalog.current_setting(
        'note.realtime_before_stale_failure'
      )::bigint
    from realtime.messages
  ),
  'stale rejection is atomic and emits no invalidation'
);

-- Every target and token boundary is validated server-side.
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    'name@notemember',
    array['b1000000-0000-4000-8000-000000000002'::uuid],
    2
  )$$,
  '22023',
  'invalid note mentions',
  'email-like prefix cannot satisfy a resolved mention'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    '@notemember@example',
    array['b1000000-0000-4000-8000-000000000002'::uuid],
    2
  )$$,
  '22023',
  'invalid note mentions',
  'email-like suffix cannot satisfy a resolved mention'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    '@notemember_extra',
    array['b1000000-0000-4000-8000-000000000002'::uuid],
    2
  )$$,
  '22023',
  'invalid note mentions',
  'partial username token cannot satisfy a resolved mention'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    '@notepending',
    array['b1000000-0000-4000-8000-000000000004'::uuid],
    2
  )$$,
  '22023',
  'invalid note mentions',
  'pending participant cannot resolve'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    '@noteremoved',
    array['b1000000-0000-4000-8000-000000000005'::uuid],
    2
  )$$,
  '22023',
  'invalid note mentions',
  'removed historical participant cannot resolve'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    '@notestranger',
    array['b1000000-0000-4000-8000-000000000006'::uuid],
    2
  )$$,
  '22023',
  'invalid note mentions',
  'cross-list or unrelated profile cannot resolve'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    '@noteincomplete',
    array['b1000000-0000-4000-8000-000000000007'::uuid],
    2
  )$$,
  '22023',
  'invalid note mentions',
  'incomplete onboarding candidate cannot resolve'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    repeat('x', 2001),
    '{}'::uuid[],
    2
  )$$,
  '22023',
  'invalid general note',
  '2,001 code points are rejected'
);
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    repeat('😀', 2000),
    '{}'::uuid[],
    2
  )$$,
  'exactly 2,000 Unicode code points are accepted'
);
reset role;

select ok(
  (
    select pg_catalog.char_length(general_note_text) = 2000
      and pg_catalog.octet_length(general_note_text) = 8000
      and version = 3
      and general_note_version = 3
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 0
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-000000000001'
  ),
  'Unicode length uses code points and text/link replacement is atomic'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    E'Again @notemember.\n@notemember',
    array['b1000000-0000-4000-8000-000000000002'::uuid],
    3
  )$$,
  'repeated token occurrences resolve one stable link'
);
reset role;

select ok(
  (
    select general_note_version = 4 and version = 4
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.count(*) = 2
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and active_list_id =
        'b2000000-0000-4000-8000-000000000001'
      and recipient_id =
        'b1000000-0000-4000-8000-000000000002'
  ),
  're-resolving in a later save creates one fresh version-bound notification'
);

-- Archived lists remain readable but immutable.
update public.active_lists
set status = 'archived',
    archived_at = pg_catalog.clock_timestamp()
where id = 'b2000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000002';
select lives_ok(
  $$select * from public.get_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001'
  )$$,
  'accepted member reads archived General Note'
);
select throws_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000001',
    'archived edit',
    '{}'::uuid[],
    4
  )$$,
  '55000',
  'archived list is read only',
  'archived General Note cannot be mutated'
);
reset role;

update public.active_lists
set status = 'active',
    archived_at = null
where id = 'b2000000-0000-4000-8000-000000000001';

-- Assignment plus mention cleanup performs one aggregate parent bump.
insert into public.active_list_items (
  id,
  list_id,
  name,
  quantity_thousandths,
  position,
  creation_request_id,
  completed_at,
  completed_by,
  created_at,
  updated_at
)
values (
  'b4000000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000001',
  'Cleanup item',
  1000,
  1,
  'b5000000-0000-4000-8000-000000000001',
  now(),
  'b1000000-0000-4000-8000-000000000002',
  now(),
  now()
);
insert into public.active_list_item_assignments (
  list_id,
  item_id,
  assignee_profile_id
)
values (
  'b2000000-0000-4000-8000-000000000001',
  'b4000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000002'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select is(
  public.remove_active_list_member(
    'b2000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000002',
    1
  ),
  2::bigint,
  'owner removes the mentioned and assigned member'
);
reset role;

select ok(
  (
    select version = 5
      and general_note_version = 5
      and general_note_text = E'Again @notemember.\n@notemember'
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000001'
  )
  and (
    select version = 2
    from public.active_list_items
    where id = 'b4000000-0000-4000-8000-000000000001'
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where assignee_profile_id =
      'b1000000-0000-4000-8000-000000000002'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where mentioned_profile_id =
      'b1000000-0000-4000-8000-000000000002'
  ),
  'combined cleanup preserves literal text, advances item/note, and bumps parent exactly once'
);

select ok(
  (
    select pg_catalog.bool_and(suppressed_at is not null)
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and active_list_id =
        'b2000000-0000-4000-8000-000000000001'
      and (
        recipient_id =
          'b1000000-0000-4000-8000-000000000002'
        or actor_id =
          'b1000000-0000-4000-8000-000000000002'
      )
  ),
  'access loss permanently stores suppression for note rows involving the departing profile'
);

update public.active_list_participants
set state = 'member',
    version = version + 1,
    state_changed_at = pg_catalog.clock_timestamp()
where list_id = 'b2000000-0000-4000-8000-000000000001'
  and participant_profile_id =
    'b1000000-0000-4000-8000-000000000002';

select ok(
  not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-000000000001'
      and mentioned_profile_id =
        'b1000000-0000-4000-8000-000000000002'
  )
  and (
    select pg_catalog.bool_and(suppressed_at is not null)
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and active_list_id =
        'b2000000-0000-4000-8000-000000000001'
  ),
  'reinvitation never restores a link or clears historical suppression'
);

select pg_catalog.set_config(
  'note.suppressed_notification_id',
  (
    select id::text
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and active_list_id =
        'b2000000-0000-4000-8000-000000000001'
    order by created_at
    limit 1
  ),
  true
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000002';
select public.mark_notifications_read(
  array[
    pg_catalog.current_setting(
      'note.suppressed_notification_id'
    )::uuid
  ]
);
select is(
  (
    select pg_catalog.count(*)
    from public.list_notifications_v3(50, null, null)
    where notification_type = 'list_note_mentioned'
  ),
  0::bigint,
  'suppressed note notifications remain absent from the v3 listing'
);
reset role;
select ok(
  (
    select pg_catalog.bool_and(read_at is null)
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and active_list_id =
        'b2000000-0000-4000-8000-000000000001'
  ),
  'mark-read hardening leaves permanently suppressed note IDs unread after access restoration'
);

-- Mark-read applies the full v3 privacy matrix, not only recipient ownership.
insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values (
  'b2000000-0000-4000-8000-00000000000f',
  'b1000000-0000-4000-8000-000000000001',
  'Mark read privacy',
  'b3000000-0000-4000-8000-00000000000f'
);
insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state
)
values
  (
    'b2000000-0000-4000-8000-00000000000f',
    'b1000000-0000-4000-8000-000000000002',
    'member'
  ),
  (
    'b2000000-0000-4000-8000-00000000000f',
    'b1000000-0000-4000-8000-000000000003',
    'member'
  );

insert into public.user_notifications (
  id,
  recipient_id,
  actor_id,
  notification_type,
  active_list_id,
  general_note_version,
  created_at,
  expires_at
)
values
  (
    'b7000000-0000-4000-8000-000000000001',
    'b1000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000001',
    'list_note_mentioned',
    'b2000000-0000-4000-8000-00000000000f',
    1,
    now(),
    now() + interval '180 days'
  ),
  (
    'b7000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000001',
    'list_note_mentioned',
    'b2000000-0000-4000-8000-00000000000f',
    2,
    now(),
    now() + interval '180 days'
  ),
  (
    'b7000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000001',
    'list_note_mentioned',
    'b2000000-0000-4000-8000-00000000000f',
    3,
    now() - interval '181 days',
    now() - interval '1 day'
  ),
  (
    'b7000000-0000-4000-8000-000000000004',
    'b1000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000002',
    'list_note_mentioned',
    'b2000000-0000-4000-8000-00000000000f',
    4,
    now(),
    now() + interval '180 days'
  );

update public.active_list_participants
set state = 'removed',
    version = version + 1,
    state_changed_at = pg_catalog.clock_timestamp()
where list_id = 'b2000000-0000-4000-8000-00000000000f'
  and participant_profile_id =
    'b1000000-0000-4000-8000-000000000002';

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000003';
select lives_ok(
  $$select public.mark_notifications_read(
    array[
      'b7000000-0000-4000-8000-000000000001'::uuid,
      'b7000000-0000-4000-8000-000000000002'::uuid,
      'b7000000-0000-4000-8000-000000000003'::uuid,
      'b7000000-0000-4000-8000-000000000004'::uuid
    ]
  )$$,
  'mixed visible, foreign, expired, and actor-inaccessible IDs are handled atomically'
);
reset role;
select ok(
  (
    select read_at is not null
    from public.user_notifications
    where id = 'b7000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.bool_and(read_at is null)
    from public.user_notifications
    where id in (
      'b7000000-0000-4000-8000-000000000002',
      'b7000000-0000-4000-8000-000000000003',
      'b7000000-0000-4000-8000-000000000004'
    )
  ),
  'mark-read changes only the current unexpired recipient row with current actor access'
);

insert into public.user_blocks (blocker_id, blocked_id)
values (
  'b1000000-0000-4000-8000-000000000001',
  'b1000000-0000-4000-8000-000000000003'
);
insert into public.user_notifications (
  id,
  recipient_id,
  actor_id,
  notification_type,
  active_list_id,
  general_note_version,
  created_at,
  expires_at
)
values (
  'b7000000-0000-4000-8000-000000000005',
  'b1000000-0000-4000-8000-000000000003',
  'b1000000-0000-4000-8000-000000000001',
  'list_note_mentioned',
  'b2000000-0000-4000-8000-00000000000f',
  5,
  now(),
  now() + interval '180 days'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000003';
select public.mark_notifications_read(
  array['b7000000-0000-4000-8000-000000000005'::uuid]
);
reset role;
select ok(
  (
    select read_at is null and suppressed_at is null
    from public.user_notifications
    where id = 'b7000000-0000-4000-8000-000000000005'
  ),
  'a newly inserted blocked-pair note notification cannot be marked read'
);

delete from public.active_lists
where id = 'b2000000-0000-4000-8000-00000000000f';
delete from public.user_blocks
where blocker_id = 'b1000000-0000-4000-8000-000000000001'
  and blocked_id = 'b1000000-0000-4000-8000-000000000003';
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000003';
select lives_ok(
  $$select public.mark_notifications_read(
    array['b7000000-0000-4000-8000-000000000005'::uuid]
  )$$,
  'deleted-context notification identifier is an idempotent no-op'
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where id = 'b7000000-0000-4000-8000-000000000005'
  ),
  0::bigint,
  'list deletion removes the referenced notification context before mark-read'
);

-- V8 owner-only note export and v1-v7 compatibility.
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select ok(
  (
    select exported ->> 'schema_version' = '8'
      and exported #>> '{active_lists,0,general_note,text}' =
        E'Again @notemember.\n@notemember'
      and exported #>> '{active_lists,0,general_note,version}' = '5'
      and pg_catalog.jsonb_array_length(
        exported #> '{active_lists,0,general_note,mentions}'
      ) = 0
    from (
      select public.export_own_account_data_v8() as exported
    ) as result
  ),
  'export v8 includes owned literal note plus only current resolved links'
);
select ok(
  public.export_own_account_data_v7() ->> 'schema_version' = '7'
  and public.export_own_account_data() ->> 'schema_version' = '6',
  'export versions 6 and 7 remain unchanged'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000002';
select ok(
  (
    select exported ->> 'schema_version' = '8'
      and exists (
        select 1
        from pg_catalog.jsonb_array_elements(
          exported -> 'shared_list_access'
        ) as shared_list(entry)
        where shared_list.entry ->> 'list_id' =
            'b2000000-0000-4000-8000-000000000001'
      )
      and (exported -> 'shared_list_access')::text
        !~ 'general_note|mention'
      and not (exported -> 'active_lists') @>
        pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object(
            'id',
            'b2000000-0000-4000-8000-000000000001'
          )
        )
    from (
      select public.export_own_account_data_v8() as exported
    ) as result
  ),
  'export v8 keeps another owner shared list metadata-only under P-039'
);
reset role;

-- Live mention projection survives profile presentation changes and ownership.
insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values (
  'b2000000-0000-4000-8000-00000000000c',
  'b1000000-0000-4000-8000-000000000001',
  'Mention ownership lifecycle',
  'b3000000-0000-4000-8000-00000000000c'
);
insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state
)
values (
  'b2000000-0000-4000-8000-00000000000c',
  'b1000000-0000-4000-8000-000000000003',
  'member'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-00000000000c',
    'Ask @notesecond',
    array['b1000000-0000-4000-8000-000000000003'::uuid],
    1
  )$$,
  'owner resolves a mention for profile and ownership lifecycle checks'
);
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-00000000000c',
    'Changed text still asks @notesecond',
    array['b1000000-0000-4000-8000-000000000003'::uuid],
    2
  )$$,
  'unrelated text changes retain the existing resolved mention'
);
reset role;

select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and active_list_id =
        'b2000000-0000-4000-8000-00000000000c'
      and recipient_id =
        'b1000000-0000-4000-8000-000000000003'
  ),
  1::bigint,
  'retained mention creates no notification merely because note text changed'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000003';
update public.profiles
set display_name = '  Renamed Mention  '
where id = 'b1000000-0000-4000-8000-000000000003';
select lives_ok(
  $$update public.profiles
    set username = '  NOTESECOND  '
    where id = 'b1000000-0000-4000-8000-000000000003'$$,
  'same-canonical completed username retry remains idempotent'
);
select throws_like(
  $$update public.profiles
    set username = 'changed_note_username'
    where id = 'b1000000-0000-4000-8000-000000000003'$$,
  '%username cannot be changed after onboarding is complete%',
  'completed username mutation remains forbidden while mentioned'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select ok(
  (
    select mentions #>> '{0,username}' = 'notesecond'
      and mentions #>> '{0,display_name}' = 'Renamed Mention'
    from public.get_active_list_general_note(
      'b2000000-0000-4000-8000-00000000000c'
    )
  ),
  'stable profile link renders the current canonical username and display name'
);
select lives_ok(
  $$select * from public.transfer_active_list_ownership(
    'b2000000-0000-4000-8000-00000000000c',
    'b1000000-0000-4000-8000-000000000003',
    3,
    1
  )$$,
  'ownership transfer succeeds without rewriting General Note state'
);
reset role;

select ok(
  (
    select owner_id =
        'b1000000-0000-4000-8000-000000000003'
      and version = 4
      and general_note_version = 3
      and general_note_text = 'Changed text still asks @notesecond'
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-00000000000c'
  )
  and exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-00000000000c'
      and mentioned_profile_id =
        'b1000000-0000-4000-8000-000000000003'
  ),
  'ownership transfer preserves scalar note and stable resolved links'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000003';
select lives_ok(
  $$select public.delete_active_list(
    'b2000000-0000-4000-8000-00000000000c',
    4
  )$$,
  'new owner deletes the list through the established lifecycle RPC'
);
reset role;

select ok(
  not exists (
    select 1
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-00000000000c'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-00000000000c'
  ),
  'list deletion cascades the General Note mention context'
);

-- Voluntary leave uses the same one-bump combined cleanup contract.
insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values (
  'b2000000-0000-4000-8000-00000000000d',
  'b1000000-0000-4000-8000-000000000001',
  'Mention leave lifecycle',
  'b3000000-0000-4000-8000-00000000000d'
);
insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state
)
values (
  'b2000000-0000-4000-8000-00000000000d',
  'b1000000-0000-4000-8000-000000000002',
  'member'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-00000000000d',
    'Keep literal @notemember',
    array['b1000000-0000-4000-8000-000000000002'::uuid],
    1
  )$$,
  'owner resolves the voluntary-leave fixture mention'
);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000002';
select is(
  public.leave_active_list(
    'b2000000-0000-4000-8000-00000000000d',
    1
  ),
  2::bigint,
  'mentioned member voluntarily leaves'
);
reset role;
select ok(
  (
    select version = 3
      and general_note_version = 3
      and general_note_text = 'Keep literal @notemember'
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-00000000000d'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-00000000000d'
  )
  and (
    select state = 'left'
    from public.active_list_participants
    where list_id = 'b2000000-0000-4000-8000-00000000000d'
      and participant_profile_id =
        'b1000000-0000-4000-8000-000000000002'
  ),
  'voluntary leave preserves literal text, removes only the link, and bumps parent/note once'
);

-- Account deletion reserves the immutable username without reactivating links.
insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values (
  'b2000000-0000-4000-8000-00000000000e',
  'b1000000-0000-4000-8000-000000000001',
  'Mention username reservation',
  'b3000000-0000-4000-8000-00000000000e'
);
insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state
)
values (
  'b2000000-0000-4000-8000-00000000000e',
  'b1000000-0000-4000-8000-000000000009',
  'member'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-00000000000e',
    'Literal @notereserved remains',
    array['b1000000-0000-4000-8000-000000000009'::uuid],
    1
  )$$,
  'owner resolves the account-deletion reservation fixture'
);
reset role;

delete from auth.users
where id = 'b1000000-0000-4000-8000-000000000009';
select ok(
  (
    select version = 3
      and general_note_version = 3
      and general_note_text = 'Literal @notereserved remains'
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-00000000000e'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-00000000000e'
  )
  and exists (
    select 1
    from private.deleted_username_reservations
    where canonical_username = 'notereserved'
  ),
  'account deletion preserves literal text, removes the stable link, bumps once, and reserves username'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000007';
select throws_like(
  $$update public.profiles
    set username = ' NOTERESERVED '
    where id = 'b1000000-0000-4000-8000-000000000007'$$,
  '%username unavailable%',
  'reserved completed username cannot be reused by an incomplete profile'
);
reset role;

delete from private.deleted_username_reservations
where canonical_username = 'notereserved';
set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000007';
select lives_ok(
  $$update public.profiles
    set username = ' NOTERESERVED ',
        display_name = 'Replacement profile'
    where id = 'b1000000-0000-4000-8000-000000000007'$$,
  'a deliberately released historical username may be reused by a new identity'
);
reset role;

select ok(
  not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-00000000000e'
  )
  and (
    select onboarding_completed_at is not null
      and username = 'notereserved'
    from public.profiles
    where id = 'b1000000-0000-4000-8000-000000000007'
  ),
  'successful later username reuse by another stable ID never reactivates the old link'
);

-- Blocking removes only the affected structured link and never unsuppresses it.
insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values (
  'b2000000-0000-4000-8000-000000000004',
  'b1000000-0000-4000-8000-000000000001',
  'Block cleanup',
  'b3000000-0000-4000-8000-000000000004'
);
insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state
)
values (
  'b2000000-0000-4000-8000-000000000004',
  'b1000000-0000-4000-8000-000000000003',
  'member'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select * from public.update_active_list_general_note(
    'b2000000-0000-4000-8000-000000000004',
    'Ask @notesecond',
    array['b1000000-0000-4000-8000-000000000003'::uuid],
    1
  )$$,
  'owner resolves the block-race fixture mention'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'b1000000-0000-4000-8000-000000000003';
select lives_ok(
  $$select public.block_profile(
    'b1000000-0000-4000-8000-000000000001'
  )$$,
  'mentioned member blocks the list owner'
);
select lives_ok(
  $$select public.unblock_profile(
    'b1000000-0000-4000-8000-000000000001'
  )$$,
  'unblocking succeeds without restoring list state'
);
reset role;

select ok(
  (
    select version = 3
      and general_note_version = 3
      and general_note_text = 'Ask @notesecond'
    from public.active_lists
    where id = 'b2000000-0000-4000-8000-000000000004'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'b2000000-0000-4000-8000-000000000004'
  )
  and (
    select suppressed_at is not null
    from public.user_notifications
    where notification_type = 'list_note_mentioned'
      and active_list_id =
        'b2000000-0000-4000-8000-000000000004'
  ),
  'block cleanup bumps parent/note once, preserves text, removes link, and suppression survives unblock'
);

-- Parent-first account deletion also reconciles completed_by-only and
-- historical Split-only surviving lists without artificial parent bumps.
insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values
  (
    'b2000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000001',
    'Completed by only',
    'b3000000-0000-4000-8000-000000000002'
  ),
  (
    'b2000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000001',
    'Historical Split only',
    'b3000000-0000-4000-8000-000000000003'
  );

insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state
)
values
  (
    'b2000000-0000-4000-8000-000000000002',
    'b1000000-0000-4000-8000-000000000003',
    'member'
  ),
  (
    'b2000000-0000-4000-8000-000000000003',
    'b1000000-0000-4000-8000-000000000003',
    'member'
  );

insert into public.active_list_items (
  id,
  list_id,
  name,
  position,
  creation_request_id,
  completed_at,
  completed_by
)
values (
  'b4000000-0000-4000-8000-000000000002',
  'b2000000-0000-4000-8000-000000000002',
  'Historical completion',
  1,
  'b5000000-0000-4000-8000-000000000002',
  now(),
  'b1000000-0000-4000-8000-000000000008'
);

insert into public.active_list_split_settings (
  list_id,
  currency_code
)
values (
  'b2000000-0000-4000-8000-000000000003',
  'CHF'
);

insert into public.active_list_split_participants (
  id,
  list_id,
  profile_id,
  username_snapshot,
  display_name_snapshot
)
values (
  'b6000000-0000-4000-8000-000000000001',
  'b2000000-0000-4000-8000-000000000003',
  'b1000000-0000-4000-8000-000000000008',
  'notedelete',
  'Note 08'
);

delete from realtime.messages;
delete from auth.users
where id = 'b1000000-0000-4000-8000-000000000008';

select ok(
  (
    select completed_by is null and version = 1
    from public.active_list_items
    where id = 'b4000000-0000-4000-8000-000000000002'
  )
  and (
    select profile_id is null
      and username_snapshot is null
      and display_name_snapshot is null
    from public.active_list_split_participants
    where id = 'b6000000-0000-4000-8000-000000000001'
  )
  and (
    select pg_catalog.bool_and(version = 1)
    from public.active_lists
    where id in (
      'b2000000-0000-4000-8000-000000000002',
      'b2000000-0000-4000-8000-000000000003'
    )
  ),
  'account deletion preserves both lists, nulls historical identities, and creates no parent/item version bump'
);

select ok(
  (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:b1000000-0000-4000-8000-000000000001'
      and event = 'invalidate'
      and extension = 'broadcast'
      and payload - 'id' = '{"v":1}'::jsonb
      and private
  )
  and (
    select pg_catalog.count(*) >= 1
    from realtime.messages
    where topic =
      'account:b1000000-0000-4000-8000-000000000003'
      and event = 'invalidate'
      and extension = 'broadcast'
      and payload - 'id' = '{"v":1}'::jsonb
      and private
  ),
  'completed_by-only and Split-only owners/current members receive transactional invalidations'
);

select * from finish();
rollback;
