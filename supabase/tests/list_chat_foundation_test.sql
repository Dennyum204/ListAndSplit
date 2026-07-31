begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_sequence(
  'private',
  'active_list_chat_message_position_seq',
  'Chat has one private durable position sequence'
);
select has_table(
  'public',
  'active_list_chat_messages',
  'Chat messages table exists'
);
select has_table(
  'public',
  'active_list_chat_states',
  'Chat state table exists'
);
select has_table(
  'private',
  'active_list_chat_send_requests',
  'Chat send request ledger exists'
);

select ok(
  (
    select message_table.relrowsecurity
      and message_table.relforcerowsecurity
      and state_table.relrowsecurity
      and state_table.relforcerowsecurity
      and request_table.relrowsecurity
      and request_table.relforcerowsecurity
    from pg_catalog.pg_class as message_table
    join pg_catalog.pg_namespace as message_schema
      on message_schema.oid = message_table.relnamespace
    join pg_catalog.pg_class as state_table
      on state_table.relname = 'active_list_chat_states'
    join pg_catalog.pg_namespace as state_schema
      on state_schema.oid = state_table.relnamespace
     and state_schema.nspname = 'public'
    join pg_catalog.pg_class as request_table
      on request_table.relname = 'active_list_chat_send_requests'
    join pg_catalog.pg_namespace as request_schema
      on request_schema.oid = request_table.relnamespace
     and request_schema.nspname = 'private'
    where message_schema.nspname = 'public'
      and message_table.relname = 'active_list_chat_messages'
  ),
  'all Chat tables enable and force RLS'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies
    where (
      schemaname = 'public'
      and tablename in (
        'active_list_chat_messages',
        'active_list_chat_states'
      )
    ) or (
      schemaname = 'private'
      and tablename = 'active_list_chat_send_requests'
    )
      and cmd = 'ALL'
      and roles = array['anon', 'authenticated']::name[]
      and qual = 'false'
      and with_check = 'false'
  ),
  3::bigint,
  'each Chat table has one explicit all-operation client rejection policy'
);
select ok(
  not pg_catalog.has_table_privilege(
    'anon',
    'public.active_list_chat_messages',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'public.active_list_chat_messages',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'service_role',
    'public.active_list_chat_messages',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'public.active_list_chat_states',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not pg_catalog.has_table_privilege(
    'authenticated',
    'private.active_list_chat_send_requests',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'no API role has direct Chat table access'
);
select ok(
  not pg_catalog.has_sequence_privilege(
    'anon',
    'private.active_list_chat_message_position_seq',
    'USAGE,SELECT,UPDATE'
  )
  and not pg_catalog.has_sequence_privilege(
    'authenticated',
    'private.active_list_chat_message_position_seq',
    'USAGE,SELECT,UPDATE'
  )
  and not pg_catalog.has_sequence_privilege(
    'service_role',
    'private.active_list_chat_message_position_seq',
    'USAGE,SELECT,UPDATE'
  ),
  'no API role can inspect or allocate Chat positions'
);
select ok(
  (
    select not sequence_record.seqcycle
      and sequence_record.seqmin = 1
      and sequence_record.seqincrement = 1
    from pg_catalog.pg_sequence as sequence_record
    where sequence_record.seqrelid =
      'private.active_list_chat_message_position_seq'::regclass
  ),
  'message positions use a positive noncycling bigint sequence'
);

select ok(
  (
    select pg_catalog.bool_and(
      function_record.proowner = 'postgres'::regrole
      and function_record.prosecdef
      and function_record.proconfig @> array['search_path=""']
      and pg_catalog.has_function_privilege(
        'authenticated',
        function_record.oid,
        'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'anon',
        function_record.oid,
        'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'service_role',
        function_record.oid,
        'EXECUTE'
      )
    )
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.list_active_list_chat_messages(uuid,integer,bigint)'::regprocedure,
      'public.send_active_list_chat_message(uuid,text,uuid)'::regprocedure,
      'public.delete_active_list_chat_message(uuid,uuid)'::regprocedure,
      'public.mark_active_list_chat_read(uuid,uuid)'::regprocedure,
      'public.get_active_list_chat_unread_count(uuid)'::regprocedure,
      'public.export_own_account_data_v12()'::regprocedure
    )
  ),
  'all exact client Chat RPCs are hardened postgres-owned authenticated-only definers'
);
select ok(
  (
    select function_record.proowner = 'postgres'::regrole
      and function_record.prosecdef
      and function_record.proconfig @> array['search_path=""']
      and pg_catalog.has_function_privilege(
        'postgres',
        function_record.oid,
        'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'public',
        function_record.oid,
        'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'anon',
        function_record.oid,
        'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'authenticated',
        function_record.oid,
        'EXECUTE'
      )
      and not pg_catalog.has_function_privilege(
        'service_role',
        function_record.oid,
        'EXECUTE'
      )
    from pg_catalog.pg_proc as function_record
    where function_record.oid =
      'private.maintain_active_list_chat_retention(timestamptz,integer)'::regprocedure
  ),
  'retention is a hardened postgres-only boundary'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and (
        tablename like 'active_list_chat%'
        or tablename = 'active_list_chat_send_requests'
      )
  ),
  'Chat tables are absent from the Realtime publication'
);
select is(
  (
    select pg_catalog.count(*)
    from cron.job
    where jobname = 'list-chat-retention-daily'
  ),
  1::bigint,
  'the later additive operational migration owns Chat retention scheduling'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'private.send_account_invalidations(uuid[])'::regprocedure
  ) like '%''invalidate''%'
  and pg_catalog.pg_get_functiondef(
    'private.send_account_invalidations(uuid[])'::regprocedure
  ) not like '%chat_invalidate%',
  'the established global invalidation helper is unchanged'
);
select ok(
  pg_catalog.pg_get_functiondef(
    'private.send_chat_account_invalidations(uuid[])'::regprocedure
  ) like '%jsonb_build_object(''v'', 1)%'
  and pg_catalog.pg_get_functiondef(
    'private.send_chat_account_invalidations(uuid[])'::regprocedure
  ) like '%''chat_invalidate''%'
  and pg_catalog.pg_get_functiondef(
    'private.send_chat_account_invalidations(uuid[])'::regprocedure
  ) like '%''account:'' || recipient_id::text%'
  and pg_catalog.pg_get_functiondef(
    'private.send_chat_account_invalidations(uuid[])'::regprocedure
  ) not like '%message_position%'
  and pg_catalog.pg_get_functiondef(
    'private.send_chat_account_invalidations(uuid[])'::regprocedure
  ) not like '%target_list_id%',
  'Chat invalidation fixes the opaque event, payload, and private account topic'
);

create temporary table chat_test_results (
  label text primary key,
  value jsonb not null
) on commit drop;
grant select, insert, update on chat_test_results to authenticated;

create function pg_temp.chat_broadcast_count(target_profile_id uuid)
returns bigint
language sql
stable
set search_path = ''
as $$
  select pg_catalog.count(*)
  from realtime.messages as message_record
  where message_record.topic = 'account:' || target_profile_id::text
    and message_record.extension = 'broadcast'
    and message_record.event = 'chat_invalidate'
    and message_record.private
    and message_record.payload - 'id' = '{"v":1}'::jsonb
$$;

create function pg_temp.global_broadcast_count(target_profile_id uuid)
returns bigint
language sql
stable
set search_path = ''
as $$
  select pg_catalog.count(*)
  from realtime.messages as message_record
  where message_record.topic = 'account:' || target_profile_id::text
    and message_record.extension = 'broadcast'
    and message_record.event = 'invalidate'
    and message_record.private
    and message_record.payload - 'id' = '{"v":1}'::jsonb
$$;

create function pg_temp.clear_broadcasts()
returns void
language sql
volatile
set search_path = ''
as $$ delete from realtime.messages $$;

insert into auth.users (
  id,
  email,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('a1000000-0000-4000-8000-000000000001', 'chat-owner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000002', 'chat-member@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000003', 'chat-joiner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000004', 'chat-outsider@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000005', 'chat-block-owner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000006', 'chat-block-member@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000007', 'chat-leave-owner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000008', 'chat-leave-member@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-000000000009', 'chat-delete-owner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-00000000000a', 'chat-delete-member@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-00000000000b', 'chat-cascade-owner@example.test', now(), now(), now()),
  ('a1000000-0000-4000-8000-00000000000c', 'chat-state-fixture@example.test', now(), now(), now());

update public.profiles
set username = 'chat' || right(replace(id::text, '-', ''), 4),
    display_name = 'Chat ' || right(id::text, 2)
where id::text like 'a1000000-0000-4000-8000-%';

insert into public.user_relationships (
  profile_low_id,
  profile_high_id,
  state,
  requester_id
)
values
  ('a1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002', 'friends', 'a1000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000003', 'friends', 'a1000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-000000000006', 'friends', 'a1000000-0000-4000-8000-000000000005'),
  ('a1000000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-000000000008', 'friends', 'a1000000-0000-4000-8000-000000000007'),
  ('a1000000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-00000000000a', 'friends', 'a1000000-0000-4000-8000-000000000009');

insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'Main Chat', 'a3000000-0000-4000-8000-000000000001'),
  ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001', 'Join Chat', 'a3000000-0000-4000-8000-000000000002'),
  ('a2000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000004', 'Foreign Chat', 'a3000000-0000-4000-8000-000000000003'),
  ('a2000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000005', 'Block Chat', 'a3000000-0000-4000-8000-000000000004'),
  ('a2000000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-000000000007', 'Leave Chat', 'a3000000-0000-4000-8000-000000000005'),
  ('a2000000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-000000000009', 'Delete Member Chat', 'a3000000-0000-4000-8000-000000000006'),
  ('a2000000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-00000000000b', 'Cascade Chat', 'a3000000-0000-4000-8000-000000000007'),
  ('a2000000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-000000000001', 'Rate Chat', 'a3000000-0000-4000-8000-000000000008'),
  ('a2000000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-000000000001', 'Page Chat', 'a3000000-0000-4000-8000-000000000009'),
  ('a2000000-0000-4000-8000-00000000000a', 'a1000000-0000-4000-8000-000000000001', 'Unread Chat', 'a3000000-0000-4000-8000-00000000000a'),
  ('a2000000-0000-4000-8000-00000000000b', 'a1000000-0000-4000-8000-000000000001', 'Retention Chat', 'a3000000-0000-4000-8000-00000000000b');

insert into public.active_list_participants (
  list_id,
  participant_profile_id,
  state
)
values
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002', 'member'),
  ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000003', 'pending'),
  ('a2000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000006', 'member'),
  ('a2000000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-000000000008', 'member'),
  ('a2000000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-00000000000a', 'member'),
  ('a2000000-0000-4000-8000-00000000000a', 'a1000000-0000-4000-8000-000000000002', 'member');

select pg_temp.clear_broadcasts();

select is(
  (
    select pg_catalog.count(*)
    from public.active_list_chat_states
    where (
      list_id = 'a2000000-0000-4000-8000-000000000001'
      and profile_id in (
        'a1000000-0000-4000-8000-000000000001',
        'a1000000-0000-4000-8000-000000000002'
      )
    ) or (
      list_id = 'a2000000-0000-4000-8000-000000000002'
      and profile_id = 'a1000000-0000-4000-8000-000000000003'
    )
  ),
  2::bigint,
  'owners and accepted members get boundary-zero state while pending users do not'
);
select is(
  (
    select pg_catalog.count(*)
    from public.active_list_chat_states
    where visible_after_message_position <> 0
      or last_read_message_position <> 0
  ),
  0::bigint,
  'migration/new-list state starts at zero before any Chat history exists'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'normalized',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    U&'\00A0 Hello\000D\000A\0009world \D83D\DE00 \00A0',
    'a4000000-0000-4000-8000-000000000001'
  )
);
reset role;

insert into chat_test_results(label, value)
values (
  'initial-send-observation',
  pg_catalog.jsonb_build_object(
    'owner_chat_count',
    pg_temp.chat_broadcast_count(
      'a1000000-0000-4000-8000-000000000001'
    ),
    'member_chat_count',
    pg_temp.chat_broadcast_count(
      'a1000000-0000-4000-8000-000000000002'
    ),
    'foreign_chat_count',
    pg_temp.chat_broadcast_count(
      'a1000000-0000-4000-8000-000000000004'
    ),
    'global_count',
    pg_temp.global_broadcast_count(
      'a1000000-0000-4000-8000-000000000001'
    ),
    'payloads_are_opaque',
    (
      select pg_catalog.bool_and(
        message_record.payload - 'id' = '{"v":1}'::jsonb
        and message_record.event = 'chat_invalidate'
        and message_record.topic in (
          'account:a1000000-0000-4000-8000-000000000001',
          'account:a1000000-0000-4000-8000-000000000002'
        )
      )
      from realtime.messages as message_record
    ),
    'global_event_count',
    (
      select pg_catalog.count(*)
      from realtime.messages
      where event = 'invalidate'
    ),
    'list_version',
    (
      select version
      from public.active_lists
      where id = 'a2000000-0000-4000-8000-000000000001'
    ),
    'notification_count',
    (
      select pg_catalog.count(*)
      from public.user_notifications
      where active_list_id = 'a2000000-0000-4000-8000-000000000001'
    )
  )
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'two-thousand',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    repeat(U&'\00E9', 2000),
    'a4000000-0000-4000-8000-000000000005'
  )
);
reset role;

update public.profiles
set display_name = 'Renamed Chat Owner'
where id = 'a1000000-0000-4000-8000-000000000001';
select pg_temp.clear_broadcasts();

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
insert into chat_test_results(label, value)
values (
  'member-message',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    'member body',
    'a4000000-0000-4000-8000-000000000010'
  )
);
insert into chat_test_results(label, value)
values (
  'member-history',
  public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-000000000001',
    50,
    null
  )
);
reset role;

select is(
  (
    select history_message->>'sender_display_name'
    from chat_test_results as result_record
    cross join lateral pg_catalog.jsonb_array_elements(
      result_record.value->'messages'
    ) as history_message
    where result_record.label = 'member-history'
      and history_message->>'id' = (
        select value->>'id'
        from chat_test_results
        where label = 'normalized'
      )
  ),
  'Renamed Chat Owner',
  'history resolves a sender current display name without a stored snapshot'
);
select ok(
  not (
    select value->'messages'->0
    from chat_test_results
    where label = 'member-history'
  ) ? 'sender_profile_id'
  and not (
    select value->'messages'->0
    from chat_test_results
    where label = 'member-history'
  ) ? 'list_id'
  and (
    select pg_catalog.count(*)
    from pg_catalog.jsonb_object_keys(
      (
        select value->'messages'->0
        from chat_test_results
        where label = 'member-history'
      )
    )
  ) = 9,
  'message history uses the exact minimal DTO allowlist'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
insert into chat_test_results(label, value)
values (
  'sender-tombstone',
  public.delete_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    (
      select (value->>'id')::uuid
      from chat_test_results
      where label = 'member-message'
    )
  )
);
reset role;
select ok(
  (
    select value->'body' = 'null'::jsonb
      and value->>'deletion_kind' = 'sender'
      and value->>'deleted_at' is not null
      and value->>'sender_username' = 'chat0002'
    from chat_test_results
    where label = 'sender-tombstone'
  ),
  'sender tombstone clears only the body and retains current sender resolution and order'
);
select ok(
  pg_temp.chat_broadcast_count(
    'a1000000-0000-4000-8000-000000000001'
  ) = 1
  and pg_temp.chat_broadcast_count(
    'a1000000-0000-4000-8000-000000000002'
  ) = 1
  and pg_temp.global_broadcast_count(
    'a1000000-0000-4000-8000-000000000001'
  ) = 0,
  'sender tombstone emits one Chat-only invalidation to both current accounts'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'owner-tombstone',
  public.delete_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    (
      select (value->>'id')::uuid
      from chat_test_results
      where label = 'two-thousand'
    )
  )
);
reset role;
select is(
  (
    select value->>'deletion_kind'
    from chat_test_results
    where label = 'owner-tombstone'
  ),
  'sender',
  'an owner deleting their own message is represented as a sender tombstone'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'owner-deletes-member',
  public.delete_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    (
      select (value->>'id')::uuid
      from chat_test_results
      where label = 'member-message'
    )
  )
)
on conflict (label) do update set value = excluded.value;
reset role;
select is(
  (
    select value->>'deletion_kind'
    from chat_test_results
    where label = 'owner-deletes-member'
  ),
  'sender',
  'a repeated owner delete preserves the existing sender tombstone'
);
select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
select public.delete_active_list_chat_message(
  'a2000000-0000-4000-8000-000000000001',
  (
    select (value->>'id')::uuid
    from chat_test_results
    where label = 'member-message'
  )
);
reset role;
select is(
  (select pg_catalog.count(*) from realtime.messages),
  0::bigint,
  'repeated tombstone is a no-op with no duplicate invalidation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
select throws_ok(
  format(
    $$select public.delete_active_list_chat_message(
      'a2000000-0000-4000-8000-000000000001',
      %L
    )$$,
    (
      select value->>'id'
      from chat_test_results
      where label = 'normalized'
    )
  ),
  'P0002',
  'list unavailable',
  'ordinary member cannot tombstone another sender retained message'
);
reset role;

select throws_ok(
  format(
    $$update public.active_list_chat_messages
      set body = 'rewritten'
      where id = %L$$,
    (
      select value->>'id'
      from chat_test_results
      where label = 'normalized'
    )
  ),
  '55000',
  'chat message is immutable',
  'defensive trigger rejects body editing'
);
select throws_ok(
  format(
    $$update public.active_list_chat_messages
      set message_position = message_position + 1
      where id = %L$$,
    (
      select value->>'id'
      from chat_test_results
      where label = 'normalized'
    )
  ),
  '55000',
  'chat message is immutable',
  'defensive trigger rejects position changes'
);
select throws_ok(
  format(
    $$update public.active_list_chat_messages
      set body = 'restored',
          deleted_at = null,
          deletion_kind = null
      where id = %L$$,
    (
      select value->>'id'
      from chat_test_results
      where label = 'member-message'
    )
  ),
  '55000',
  'chat message is immutable',
  'one-way tombstones cannot be restored'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'pre-join',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000002',
    'before first join',
    'a4000000-0000-4000-8000-000000000020'
  )
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000003';
select public.accept_active_list_invitation(
  'a2000000-0000-4000-8000-000000000002',
  1
);
insert into chat_test_results(label, value)
values (
  'first-join-history',
  public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-000000000002',
    20,
    null
  )
);
reset role;
select is(
  (
    select visible_after_message_position
    from public.active_list_chat_states
    where list_id = 'a2000000-0000-4000-8000-000000000002'
      and profile_id = 'a1000000-0000-4000-8000-000000000003'
  ),
  (
    select (value->>'message_position')::bigint
    from chat_test_results
    where label = 'pre-join'
  ),
  'first acceptance stores the latest locked list position as its visibility boundary'
);
select is(
  pg_catalog.jsonb_array_length(
    (
      select value->'messages'
      from chat_test_results
      where label = 'first-join-history'
    )
  ),
  0,
  'newly accepted participant cannot see pre-join history'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000003';
insert into chat_test_results(label, value)
values (
  'joiner-first-window-message',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000002',
    'first membership window',
    'a4000000-0000-4000-8000-000000000021'
  )
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
select public.remove_active_list_member(
  'a2000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000003',
  2
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.active_list_chat_states
    where list_id = 'a2000000-0000-4000-8000-000000000002'
      and profile_id = 'a1000000-0000-4000-8000-000000000003'
  ),
  0::bigint,
  'member removal deletes private Chat state in the lifecycle transaction'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
select public.invite_active_list_member(
  'a2000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000003',
  3
);
insert into chat_test_results(label, value)
values (
  'between-memberships',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000002',
    'between membership windows',
    'a4000000-0000-4000-8000-000000000022'
  )
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000003';
select public.accept_active_list_invitation(
  'a2000000-0000-4000-8000-000000000002',
  4
);
insert into chat_test_results(label, value)
values (
  'rejoin-history',
  public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-000000000002',
    20,
    null
  )
);
select throws_ok(
  $$select public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000002',
    'first membership window',
    'a4000000-0000-4000-8000-000000000021'
  )$$,
  'P0002',
  'list unavailable',
  'prior-window idempotent replay cannot expose content or create a duplicate'
);
reset role;
select is(
  pg_catalog.jsonb_array_length(
    (
      select value->'messages'
      from chat_test_results
      where label = 'rejoin-history'
    )
  ),
  0,
  'reacceptance starts a fresh empty visibility and unread window'
);
select is(
  (
    select pg_catalog.count(*)
    from public.active_list_chat_messages
    where list_id = 'a2000000-0000-4000-8000-000000000002'
      and body = 'first membership window'
  ),
  1::bigint,
  'prior-window replay creates no duplicate message'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000006';
insert into chat_test_results(label, value)
values (
  'block-member-message',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000004',
    'retained after block',
    'a4000000-0000-4000-8000-000000000030'
  )
);
reset role;
select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000005';
select public.block_profile(
  'a1000000-0000-4000-8000-000000000006'
);
reset role;
select ok(
  not exists (
    select 1
    from public.active_list_chat_states
    where list_id = 'a2000000-0000-4000-8000-000000000004'
      and profile_id = 'a1000000-0000-4000-8000-000000000006'
  )
  and exists (
    select 1
    from public.active_list_chat_messages
    where id = (
      select (value->>'id')::uuid
      from chat_test_results
      where label = 'block-member-message'
    )
  ),
  'block lifecycle revokes state immediately while retaining message history'
);
select ok(
  pg_temp.global_broadcast_count(
    'a1000000-0000-4000-8000-000000000005'
  ) >= 1
  and pg_temp.global_broadcast_count(
    'a1000000-0000-4000-8000-000000000006'
  ) >= 1
  and (
    select pg_catalog.count(*)
    from realtime.messages
    where event = 'chat_invalidate'
  ) = 0,
  'block keeps the established global lifecycle invalidation and emits no Chat event'
);
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000006';
select throws_ok(
  $$select public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-000000000004',
    20,
    null
  )$$,
  'P0002',
  'list unavailable',
  'block-removed member immediately loses Chat read access'
);
reset role;

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000008';
insert into chat_test_results(label, value)
values (
  'leaver-message',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000005',
    'retained after leave',
    'a4000000-0000-4000-8000-000000000031'
  )
);
select public.leave_active_list(
  'a2000000-0000-4000-8000-000000000005',
  1
);
reset role;
select ok(
  not exists (
    select 1
    from public.active_list_chat_states
    where list_id = 'a2000000-0000-4000-8000-000000000005'
      and profile_id = 'a1000000-0000-4000-8000-000000000008'
  )
  and exists (
    select 1
    from public.active_list_chat_messages
    where id = (
      select (value->>'id')::uuid
      from chat_test_results
      where label = 'leaver-message'
    )
  ),
  'departure removes Chat state while retaining authored history'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
insert into chat_test_results(label, value)
values (
  'owner-target-message',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    'owner may remove this',
    'a4000000-0000-4000-8000-000000000032'
  )
);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'true-owner-tombstone',
  public.delete_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    (
      select (value->>'id')::uuid
      from chat_test_results
      where label = 'owner-target-message'
    )
  )
);
reset role;
select ok(
  (
    select value->>'deletion_kind' = 'owner'
      and value->'body' = 'null'::jsonb
      and value->>'sender_username' = 'chat0002'
    from chat_test_results
    where label = 'true-owner-tombstone'
  ),
  'current owner can apply a distinct owner tombstone to another sender message'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values
  (
    'unread-owner-one',
    public.send_active_list_chat_message(
      'a2000000-0000-4000-8000-00000000000a',
      'unread one',
      'a4000000-0000-4000-8000-000000000040'
    )
  ),
  (
    'unread-owner-two',
    public.send_active_list_chat_message(
      'a2000000-0000-4000-8000-00000000000a',
      'unread two',
      'a4000000-0000-4000-8000-000000000041'
    )
  );
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
insert into chat_test_results(label, value)
values
  (
    'unread-member-own',
    public.send_active_list_chat_message(
      'a2000000-0000-4000-8000-00000000000a',
      'my own message',
      'a4000000-0000-4000-8000-000000000042'
    )
  ),
  (
    'unread-before-read',
    public.get_active_list_chat_unread_count(
      'a2000000-0000-4000-8000-00000000000a'
    )
  );
reset role;
select ok(
  (
    select (value->>'count')::integer = 2
      and not (value->>'is_capped')::boolean
    from chat_test_results
    where label = 'unread-before-read'
  ),
  'unread excludes the caller own message and counts visible active messages from another sender'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
select public.delete_active_list_chat_message(
  'a2000000-0000-4000-8000-00000000000a',
  (
    select (value->>'id')::uuid
    from chat_test_results
    where label = 'unread-owner-one'
  )
);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
insert into chat_test_results(label, value)
values (
  'unread-after-tombstone',
  public.get_active_list_chat_unread_count(
    'a2000000-0000-4000-8000-00000000000a'
  )
);
reset role;
select is(
  (
    select (value->>'count')::integer
    from chat_test_results
    where label = 'unread-after-tombstone'
  ),
  1,
  'tombstones are excluded from unread'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
insert into chat_test_results(label, value)
values (
  'mark-read',
  public.mark_active_list_chat_read(
    'a2000000-0000-4000-8000-00000000000a',
    (
      select (value->>'id')::uuid
      from chat_test_results
      where label = 'unread-owner-two'
    )
  )
);
reset role;
select ok(
  (
    select (value->>'changed')::boolean
      and (value->>'last_read_message_position')::bigint = (
        select (value->>'message_position')::bigint
        from chat_test_results
        where label = 'unread-owner-two'
      )
    from chat_test_results
    where label = 'mark-read'
  )
  and pg_temp.chat_broadcast_count(
    'a1000000-0000-4000-8000-000000000002'
  ) = 1
  and pg_temp.chat_broadcast_count(
    'a1000000-0000-4000-8000-000000000001'
  ) = 0,
  'mark-read advances monotonically and invalidates only the caller account'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'unread-after-cursor',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-00000000000a',
    'after read cursor',
    'a4000000-0000-4000-8000-000000000043'
  )
);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
insert into chat_test_results(label, value)
values (
  'older-read-noop',
  public.mark_active_list_chat_read(
    'a2000000-0000-4000-8000-00000000000a',
    (
      select (value->>'id')::uuid
      from chat_test_results
      where label = 'unread-owner-one'
    )
  )
);
insert into chat_test_results(label, value)
values (
  'unread-newer-remains',
  public.get_active_list_chat_unread_count(
    'a2000000-0000-4000-8000-00000000000a'
  )
);
select throws_ok(
  format(
    $$select public.mark_active_list_chat_read(
      'a2000000-0000-4000-8000-00000000000a',
      %L
    )$$,
    (
      select value->>'id'
      from chat_test_results
      where label = 'normalized'
    )
  ),
  'P0002',
  'list unavailable',
  'foreign-list cursor is rejected without exposing the message'
);
reset role;
select ok(
  not (
    select (value->>'changed')::boolean
    from chat_test_results
    where label = 'older-read-noop'
  )
  and (
    select (value->>'count')::integer = 1
    from chat_test_results
    where label = 'unread-newer-remains'
  ),
  'older cursor does not consume a concurrently newer message'
);

insert into public.active_list_chat_messages (
  list_id,
  message_position,
  sender_profile_id,
  body,
  created_at
)
select
  'a2000000-0000-4000-8000-00000000000a',
  pg_catalog.nextval(
    'private.active_list_chat_message_position_seq'::regclass
  ),
  'a1000000-0000-4000-8000-000000000001',
  'capped unread ' || generated.position::text,
  pg_catalog.clock_timestamp()
from pg_catalog.generate_series(1, 100) as generated(position);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
insert into chat_test_results(label, value)
values (
  'unread-capped',
  public.get_active_list_chat_unread_count(
    'a2000000-0000-4000-8000-00000000000a'
  )
);
reset role;
select ok(
  (
    select (value->>'count')::integer = 100
      and (value->>'is_capped')::boolean
    from chat_test_results
    where label = 'unread-capped'
  ),
  'unread stops at 100 and reports the 99+ cap'
);

insert into public.active_list_chat_messages (
  list_id,
  message_position,
  sender_profile_id,
  body,
  created_at
)
select
  'a2000000-0000-4000-8000-000000000009',
  pg_catalog.nextval(
    'private.active_list_chat_message_position_seq'::regclass
  ),
  'a1000000-0000-4000-8000-000000000001',
  'page message ' || generated.position::text,
  pg_catalog.clock_timestamp()
from pg_catalog.generate_series(1, 55) as generated(position);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'page-one',
  public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-000000000009',
    50,
    null
  )
);
insert into chat_test_results(label, value)
values (
  'page-two',
  public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-000000000009',
    50,
    (
      select (value->>'next_before_message_position')::bigint
      from chat_test_results
      where label = 'page-one'
    )
  )
);
reset role;
select ok(
  pg_catalog.jsonb_array_length(
    (select value->'messages' from chat_test_results where label = 'page-one')
  ) = 50
  and (
    select (value->>'has_more')::boolean
    from chat_test_results
    where label = 'page-one'
  )
  and pg_catalog.jsonb_array_length(
    (select value->'messages' from chat_test_results where label = 'page-two')
  ) = 5
  and not (
    select (value->>'has_more')::boolean
    from chat_test_results
    where label = 'page-two'
  ),
  'history uses bounded maximum-50 keyset pages with explicit continuation'
);
select is(
  (
    select pg_catalog.count(*)
    from (
      select page_message->>'id' as message_id
      from chat_test_results as result_record
      cross join lateral pg_catalog.jsonb_array_elements(
        result_record.value->'messages'
      ) as page_message
      where result_record.label in ('page-one', 'page-two')
      group by page_message->>'id'
      having pg_catalog.count(*) > 1
    ) as duplicate
  ),
  0::bigint,
  'keyset pages have no duplicates'
);
select ok(
  (
    select pg_catalog.bool_and(
      current_message.position > next_message.position
    )
    from (
      select
        (page_message->>'message_position')::bigint as position,
        pg_catalog.row_number() over () as ordinal
      from chat_test_results as result_record
      cross join lateral pg_catalog.jsonb_array_elements(
        result_record.value->'messages'
      ) as page_message
      where result_record.label = 'page-one'
    ) as current_message
    join (
      select
        (page_message->>'message_position')::bigint as position,
        pg_catalog.row_number() over () as ordinal
      from chat_test_results as result_record
      cross join lateral pg_catalog.jsonb_array_elements(
        result_record.value->'messages'
      ) as page_message
      where result_record.label = 'page-one'
    ) as next_message
      on next_message.ordinal = current_message.ordinal + 1
  ),
  'history is strictly ordered by immutable message_position descending'
);

insert into public.active_list_chat_messages (
  list_id,
  message_position,
  sender_profile_id,
  body,
  created_at
)
values (
  'a2000000-0000-4000-8000-000000000008',
  pg_catalog.nextval(
    'private.active_list_chat_message_position_seq'::regclass
  ),
  'a1000000-0000-4000-8000-000000000001',
  'outside rolling window',
  pg_catalog.clock_timestamp() - interval '61 seconds'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
do $$
declare
  send_index integer;
begin
  for send_index in 1..20
  loop
    perform public.send_active_list_chat_message(
      'a2000000-0000-4000-8000-000000000008',
      'rate message ' || send_index::text,
      pg_catalog.gen_random_uuid()
    );
  end loop;
end;
$$;
select throws_ok(
  $$select public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000008',
    'rate overflow',
    'a4000000-0000-4000-8000-000000000050'
  )$$,
  'P0001',
  'chat rate limit reached',
  'the twenty-first successful send in the rolling minute is rejected'
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.active_list_chat_messages
    where list_id = 'a2000000-0000-4000-8000-000000000008'
  ),
  21::bigint,
  'the older-than-60-second row does not consume one of twenty current slots'
);
select is(
  (
    select pg_catalog.count(*)
    from private.active_list_chat_send_requests
    where list_id = 'a2000000-0000-4000-8000-000000000008'
  ),
  20::bigint,
  'rejected rate overflow creates no request ledger row'
);

insert into chat_test_results(label, value)
select
  'rate-tombstone-target',
  pg_catalog.jsonb_build_object('id', id)
from public.active_list_chat_messages
where list_id = 'a2000000-0000-4000-8000-000000000008'
  and created_at > pg_catalog.clock_timestamp() - interval '60 seconds'
order by message_position
limit 1;

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
select public.delete_active_list_chat_message(
  'a2000000-0000-4000-8000-000000000008',
  (
    select (value->>'id')::uuid
    from chat_test_results
    where label = 'rate-tombstone-target'
  )
);
select throws_ok(
  $$select public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000008',
    'tombstone still counts',
    'a4000000-0000-4000-8000-000000000051'
  )$$,
  'P0001',
  'chat rate limit reached',
  'tombstoned message continues to count in its original rate window'
);
reset role;

create temporary table chat_state_before_transfer
on commit drop
as
select
  profile_id,
  visible_after_message_position,
  last_read_message_position,
  updated_at
from public.active_list_chat_states
where list_id = 'a2000000-0000-4000-8000-000000000001'
  and profile_id in (
    'a1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000002'
  );

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
select * from public.transfer_active_list_ownership(
  'a2000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000002',
  1,
  1
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.active_list_chat_states as current_state
    join chat_state_before_transfer as prior_state
      on prior_state.profile_id = current_state.profile_id
     and prior_state.visible_after_message_position =
       current_state.visible_after_message_position
     and prior_state.last_read_message_position =
       current_state.last_read_message_position
     and prior_state.updated_at = current_state.updated_at
    where current_state.list_id =
      'a2000000-0000-4000-8000-000000000001'
  ),
  2::bigint,
  'ownership transfer preserves both users Chat visibility and unread state exactly'
);
select ok(
  pg_temp.global_broadcast_count(
    'a1000000-0000-4000-8000-000000000001'
  ) >= 1
  and pg_temp.global_broadcast_count(
    'a1000000-0000-4000-8000-000000000002'
  ) >= 1
  and (
    select pg_catalog.count(*)
    from realtime.messages
    where event = 'chat_invalidate'
  ) = 0,
  'ownership transfer retains only the existing global lifecycle invalidation'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
select * from public.set_active_list_archived(
  'a2000000-0000-4000-8000-000000000001',
  true,
  2
);
reset role;
select ok(
  pg_temp.global_broadcast_count(
    'a1000000-0000-4000-8000-000000000001'
  ) >= 1
  and (
    select pg_catalog.count(*)
    from realtime.messages
    where event = 'chat_invalidate'
  ) = 0,
  'archive remains a global lifecycle invalidation only'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'archived-history',
  public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-000000000001',
    20,
    null
  )
);
select throws_ok(
  $$select public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    'archived send',
    'a4000000-0000-4000-8000-000000000060'
  )$$,
  '55000',
  'archived list is read only',
  'archived Chat rejects send'
);
select throws_ok(
  format(
    $$select public.delete_active_list_chat_message(
      'a2000000-0000-4000-8000-000000000001',
      %L
    )$$,
    (
      select value->>'id'
      from chat_test_results
      where label = 'normalized'
    )
  ),
  '55000',
  'archived list is read only',
  'archived Chat rejects tombstone'
);
insert into chat_test_results(label, value)
values (
  'archived-mark-read',
  public.mark_active_list_chat_read(
    'a2000000-0000-4000-8000-000000000001',
    (
      select (value->>'id')::uuid
      from chat_test_results
      where label = 'normalized'
    )
  )
);
reset role;
select ok(
  pg_catalog.jsonb_array_length(
    (
      select value->'messages'
      from chat_test_results
      where label = 'archived-history'
    )
  ) > 0
  and (
    select value ? 'changed'
    from chat_test_results
    where label = 'archived-mark-read'
  ),
  'archived Chat remains readable and mark-read remains available'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000002';
select * from public.set_active_list_archived(
  'a2000000-0000-4000-8000-000000000001',
  false,
  3
);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'restored-send',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    'restored Chat writes again',
    'a4000000-0000-4000-8000-000000000061'
  )
);
reset role;
select is(
  (
    select value->>'body'
    from chat_test_results
    where label = 'restored-send'
  ),
  'restored Chat writes again',
  'restore makes retained Chat writable again'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-00000000000b';
insert into chat_test_results(label, value)
values (
  'cascade-message',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000007',
    'cascade with list',
    'a4000000-0000-4000-8000-000000000062'
  )
);
select public.delete_active_list(
  'a2000000-0000-4000-8000-000000000007',
  1
);
reset role;
select ok(
  not exists (
    select 1
    from public.active_list_chat_messages
    where list_id = 'a2000000-0000-4000-8000-000000000007'
  )
  and not exists (
    select 1
    from public.active_list_chat_states
    where list_id = 'a2000000-0000-4000-8000-000000000007'
  )
  and not exists (
    select 1
    from private.active_list_chat_send_requests
    where list_id = 'a2000000-0000-4000-8000-000000000007'
  ),
  'permanent list deletion cascades every Chat row'
);
select ok(
  pg_temp.global_broadcast_count(
    'a1000000-0000-4000-8000-00000000000b'
  ) >= 1
  and (
    select pg_catalog.count(*)
    from realtime.messages
    where event = 'chat_invalidate'
  ) >= 1,
  'send emitted Chat invalidation and later list deletion preserved the global lifecycle path'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-00000000000a';
insert into chat_test_results(label, value)
values
  (
    'account-active-message',
    public.send_active_list_chat_message(
      'a2000000-0000-4000-8000-000000000006',
      'account active body',
      'a4000000-0000-4000-8000-000000000070'
    )
  ),
  (
    'account-deleted-message',
    public.send_active_list_chat_message(
      'a2000000-0000-4000-8000-000000000006',
      'account prior tombstone',
      'a4000000-0000-4000-8000-000000000071'
    )
  );
select public.delete_active_list_chat_message(
  'a2000000-0000-4000-8000-000000000006',
  (
    select (value->>'id')::uuid
    from chat_test_results
    where label = 'account-deleted-message'
  )
);
reset role;
select pg_temp.clear_broadcasts();
delete from auth.users
where id = 'a1000000-0000-4000-8000-00000000000a';

select is(
  (
    select pg_catalog.count(*)
    from public.active_list_chat_messages
    where id in (
      (
        select (value->>'id')::uuid
        from chat_test_results
        where label = 'account-active-message'
      ),
      (
        select (value->>'id')::uuid
        from chat_test_results
        where label = 'account-deleted-message'
      )
    )
      and sender_profile_id is null
      and body is null
      and deletion_kind = 'account'
      and deleted_at is not null
  ),
  2::bigint,
  'account deletion converts active and already tombstoned retained messages to account tombstones'
);
select ok(
  not exists (
    select 1
    from public.active_list_chat_states
    where profile_id = 'a1000000-0000-4000-8000-00000000000a'
  )
  and not exists (
    select 1
    from private.active_list_chat_send_requests
    where actor_id = 'a1000000-0000-4000-8000-00000000000a'
  ),
  'account deletion removes that profile Chat state and request ledger rows'
);
select ok(
  pg_temp.global_broadcast_count(
    'a1000000-0000-4000-8000-000000000009'
  ) >= 1
  and (
    select pg_catalog.count(*)
    from realtime.messages
    where event = 'chat_invalidate'
  ) = 0,
  'account deletion uses the existing global lifecycle invalidation rather than a Chat event'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000009';
insert into chat_test_results(label, value)
values (
  'account-tombstone-history',
  public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-000000000006',
    20,
    null
  )
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from chat_test_results as result_record
    cross join lateral pg_catalog.jsonb_array_elements(
      result_record.value->'messages'
    ) as message_projection
    where result_record.label = 'account-tombstone-history'
      and message_projection->>'deletion_kind' = 'account'
      and message_projection->'sender_username' = 'null'::jsonb
      and message_projection->'sender_display_name' = 'null'::jsonb
      and not (message_projection->>'is_mine')::boolean
  ),
  2::bigint,
  'account tombstone history exposes no sender identity or body'
);

insert into public.active_lists (
  id,
  owner_id,
  title,
  creation_request_id
)
values (
  'a2000000-0000-4000-8000-00000000000c',
  'a1000000-0000-4000-8000-00000000000b',
  'Owner account cascade',
  'a3000000-0000-4000-8000-00000000000c'
);
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-00000000000b';
select public.send_active_list_chat_message(
  'a2000000-0000-4000-8000-00000000000c',
  'owned aggregate disappears',
  'a4000000-0000-4000-8000-000000000072'
);
reset role;
delete from auth.users
where id = 'a1000000-0000-4000-8000-00000000000b';
select ok(
  not exists (
    select 1
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-00000000000c'
  )
  and not exists (
    select 1
    from public.active_list_chat_messages
    where list_id = 'a2000000-0000-4000-8000-00000000000c'
  ),
  'owner account deletion continues to cascade the owned list and all Chat data'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000008';
insert into chat_test_results(label, value)
values
  (
    'export-v11-leaver',
    public.export_own_account_data_v11()
  ),
  (
    'export-v12-leaver',
    public.export_own_account_data_v12()
  );
reset role;
select ok(
  (
    select (value->>'schema_version')::integer = 11
      and not value ? 'authored_chat_messages'
    from chat_test_results
    where label = 'export-v11-leaver'
  ),
  'legacy export v11 remains byte-shape compatible and Chat-unaware'
);
select ok(
  (
    select (value->>'schema_version')::integer = 12
      and pg_catalog.jsonb_array_length(
        value->'authored_chat_messages'
      ) = 1
    from chat_test_results
    where label = 'export-v12-leaver'
  ),
  'export v12 adds the caller retained authored Chat collection'
);
select ok(
  (
    select authored_message->>'body' = 'retained after leave'
      and not (authored_message->>'conversation_available')::boolean
      and authored_message->'list_id' = 'null'::jsonb
      and authored_message->'list_title' = 'null'::jsonb
      and authored_message->'list_status' = 'null'::jsonb
      and not authored_message ? 'message_position'
      and not authored_message ? 'sender_profile_id'
      and not authored_message ? 'request_id'
    from chat_test_results as result_record
    cross join lateral pg_catalog.jsonb_array_elements(
      result_record.value->'authored_chat_messages'
    ) as authored_message
    where result_record.label = 'export-v12-leaver'
  ),
  'ended access exports own body with unavailable null conversation context and no internal identifiers'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'export-v12-active',
  public.export_own_account_data_v12()
);
reset role;
select ok(
  (
    select pg_catalog.bool_and(
      authored_message ? 'message_id'
      and authored_message ? 'body'
      and authored_message ? 'created_at'
      and authored_message ? 'deleted_at'
      and authored_message ? 'deletion_kind'
      and authored_message ? 'conversation_available'
      and authored_message ? 'list_id'
      and authored_message ? 'list_title'
      and authored_message ? 'list_status'
      and (
        not (authored_message->>'conversation_available')::boolean
        or (
          authored_message->'list_id' <> 'null'::jsonb
          and authored_message->'list_title' <> 'null'::jsonb
          and authored_message->>'list_status' in ('active', 'archived')
        )
      )
    )
    from chat_test_results as result_record
    cross join lateral pg_catalog.jsonb_array_elements(
      result_record.value->'authored_chat_messages'
    ) as authored_message
    where result_record.label = 'export-v12-active'
  ),
  'export v12 uses exact caller-authored rows and minimal current-or-unavailable context'
);
select ok(
  not (
    select value->'authored_chat_messages'
    from chat_test_results
    where label = 'export-v12-active'
  ) @> pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('body', 'retained after leave')
  ),
  'one account export never contains another user message body'
);

insert into public.active_list_chat_messages (
  id,
  list_id,
  message_position,
  sender_profile_id,
  body,
  created_at
)
values
  (
    'a5000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-00000000000b',
    pg_catalog.nextval(
      'private.active_list_chat_message_position_seq'::regclass
    ),
    'a1000000-0000-4000-8000-000000000001',
    'oldest retention',
    '2025-01-01 00:00:00+00'
  ),
  (
    'a5000000-0000-4000-8000-000000000002',
    'a2000000-0000-4000-8000-00000000000b',
    pg_catalog.nextval(
      'private.active_list_chat_message_position_seq'::regclass
    ),
    'a1000000-0000-4000-8000-000000000001',
    'exact retention boundary',
    '2025-01-02 00:00:00+00'
  ),
  (
    'a5000000-0000-4000-8000-000000000003',
    'a2000000-0000-4000-8000-00000000000b',
    pg_catalog.nextval(
      'private.active_list_chat_message_position_seq'::regclass
    ),
    'a1000000-0000-4000-8000-000000000001',
    'not yet eligible',
    '2025-01-03 00:00:01+00'
  );
insert into private.active_list_chat_send_requests (
  actor_id,
  request_id,
  list_id,
  message_id,
  fingerprint,
  created_at
)
values (
  'a1000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000080',
  'a2000000-0000-4000-8000-00000000000b',
  'a5000000-0000-4000-8000-000000000001',
  private.active_list_chat_send_fingerprint(
    'a2000000-0000-4000-8000-00000000000b',
    'oldest retention'
  ),
  '2025-01-01 00:00:00+00'
);
update public.active_list_chat_states
set last_read_message_position = (
      select message_position
      from public.active_list_chat_messages
      where id = 'a5000000-0000-4000-8000-000000000002'
    ),
    updated_at = pg_catalog.clock_timestamp()
where list_id = 'a2000000-0000-4000-8000-00000000000b'
  and profile_id = 'a1000000-0000-4000-8000-000000000001';

select pg_temp.clear_broadcasts();
select is(
  private.maintain_active_list_chat_retention(
    '2026-01-02 00:00:00+00',
    1
  ),
  1::bigint,
  'retention deletes at most the requested deterministic oldest batch'
);
select ok(
  not exists (
    select 1
    from public.active_list_chat_messages
    where id = 'a5000000-0000-4000-8000-000000000001'
  )
  and not exists (
    select 1
    from private.active_list_chat_send_requests
    where message_id = 'a5000000-0000-4000-8000-000000000001'
  )
  and exists (
    select 1
    from public.active_list_chat_messages
    where id = 'a5000000-0000-4000-8000-000000000002'
  ),
  'retention cascades only the deleted message request ledger and leaves the next row'
);
select is(
  private.maintain_active_list_chat_retention(
    '2026-01-02 00:00:00+00',
    1
  ),
  1::bigint,
  'exactly 365-day-old message is eligible on the next bounded call'
);
select is(
  private.maintain_active_list_chat_retention(
    '2026-01-02 00:00:00+00',
    10
  ),
  0::bigint,
  'retention is idempotent and keeps not-yet-eligible messages'
);
select ok(
  (
    select last_read_message_position
    from public.active_list_chat_states
    where list_id = 'a2000000-0000-4000-8000-00000000000b'
      and profile_id = 'a1000000-0000-4000-8000-000000000001'
  ) > 0
  and pg_temp.chat_broadcast_count(
    'a1000000-0000-4000-8000-000000000001'
  ) = 2,
  'retention preserves numeric unread cursors and emits one content-free event per successful batch'
);
select ok(
  exists (
    select 1
    from public.active_list_chat_messages
    where id = 'a5000000-0000-4000-8000-000000000003'
  )
  and (
    select last_value
    from private.active_list_chat_message_position_seq
  ) > (
    select last_read_message_position
    from public.active_list_chat_states
    where list_id = 'a2000000-0000-4000-8000-00000000000b'
      and profile_id = 'a1000000-0000-4000-8000-000000000001'
  ),
  'global sequence remains ahead after retention and cannot depend on retained rows'
);

select is(
  (
    select version
    from public.active_lists
    where id = 'a2000000-0000-4000-8000-00000000000b'
  ),
  1::bigint,
  'retention changes no ordinary list version'
);
select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where notification_type like '%chat%'
  ),
  0::bigint,
  'Chat introduces no notification-centre type or row'
);

select is(
  (select value->>'body' from chat_test_results where label = 'normalized'),
  U&'Hello\000A\0009world \D83D\DE00',
  'send normalizes line endings and Unicode edge whitespace while preserving tab, LF, and emoji'
);
select ok(
  (
    select (value->>'message_position')::bigint > 0
      and value->>'sender_username' = 'chat0001'
      and value->>'sender_display_name' = 'Chat 01'
      and (value->>'is_mine')::boolean
    from chat_test_results
    where label = 'normalized'
  ),
  'message DTO exposes current names and caller-relative ownership without a profile ID'
);
select is(
  (
    select pg_catalog.count(*)
    from private.active_list_chat_send_requests
    where actor_id = 'a1000000-0000-4000-8000-000000000001'
      and request_id = 'a4000000-0000-4000-8000-000000000001'
      and pg_catalog.octet_length(fingerprint) = 32
  ),
  1::bigint,
  'successful send records one private 32-byte payload-bound request'
);
select ok(
  (
    select (value->>'owner_chat_count')::bigint = 1
      and (value->>'member_chat_count')::bigint = 1
      and (value->>'foreign_chat_count')::bigint = 0
      and (value->>'global_count')::bigint = 0
      and (value->>'payloads_are_opaque')::boolean
    from chat_test_results
    where label = 'initial-send-observation'
  ),
  'send invalidates exactly the final current participants with no content-bearing payload'
);
select is(
  (
    select (value->>'global_event_count')::bigint
    from chat_test_results
    where label = 'initial-send-observation'
  ),
  0::bigint,
  'ordinary Chat send emits no global invalidation'
);

select pg_temp.clear_broadcasts();
set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
insert into chat_test_results(label, value)
values (
  'replay',
  public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    U&'\00A0 Hello\000D\000A\0009world \D83D\DE00 \00A0',
    'a4000000-0000-4000-8000-000000000001'
  )
);
reset role;
select is(
  (select value->>'id' from chat_test_results where label = 'replay'),
  (select value->>'id' from chat_test_results where label = 'normalized'),
  'identical retry returns the original message'
);
select is(
  (select pg_catalog.count(*) from realtime.messages),
  0::bigint,
  'identical retry emits no duplicate invalidation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    'different payload',
    'a4000000-0000-4000-8000-000000000001'
  )$$,
  '23505',
  'chat send request conflict',
  'conflicting request UUID reuse fails safely'
);
select throws_ok(
  $$select public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    E' \r\n ',
    'a4000000-0000-4000-8000-000000000002'
  )$$,
  '22023',
  'invalid chat message',
  'empty normalized body is rejected'
);
select throws_ok(
  $$select public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    E'bad\007control',
    'a4000000-0000-4000-8000-000000000003'
  )$$,
  '22023',
  'invalid chat message',
  'disallowed control characters are rejected'
);
select throws_ok(
  $$select public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    repeat('x', 2001),
    'a4000000-0000-4000-8000-000000000004'
  )$$,
  '22023',
  'invalid chat message',
  '2,001 PostgreSQL characters are rejected'
);
reset role;
select is(
  pg_catalog.char_length(
    (select value->>'body' from chat_test_results where label = 'two-thousand')
  ),
  2000,
  'exactly 2,000 Unicode characters are accepted'
);

select is(
  (
    select (value->>'list_version')::bigint
    from chat_test_results
    where label = 'initial-send-observation'
  ),
  1::bigint,
  'Chat sends do not advance the active-list version'
);
select is(
  (
    select (value->>'notification_count')::bigint
    from chat_test_results
    where label = 'initial-send-observation'
  ),
  0::bigint,
  'Chat sends create no persistent notification row'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000004';
select throws_ok(
  $$select public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-000000000001',
    20,
    null
  )$$,
  'P0002',
  'list unavailable',
  'foreign completed caller cannot list Chat'
);
select throws_ok(
  $$select public.send_active_list_chat_message(
    'a2000000-0000-4000-8000-000000000001',
    'forged',
    'a4000000-0000-4000-8000-000000000006'
  )$$,
  'P0002',
  'list unavailable',
  'foreign completed caller cannot send Chat'
);
reset role;

insert into public.active_list_participants(
  list_id,
  participant_profile_id,
  state
)
values (
  'a2000000-0000-4000-8000-00000000000b',
  'a1000000-0000-4000-8000-000000000003',
  'pending'
)
on conflict (list_id, participant_profile_id) do update
set state = excluded.state;

set local role authenticated;
set local "request.jwt.claim.sub" = 'a1000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select public.list_active_list_chat_messages(
    'a2000000-0000-4000-8000-00000000000b',
    20,
    null
  )$$,
  'P0002',
  'list unavailable',
  'pending participant cannot read Chat'
);
reset role;

set local role authenticated;
select throws_like(
  $$select * from public.active_list_chat_messages$$,
  '%permission denied%',
  'authenticated direct message select is denied'
);
select throws_like(
  $$insert into public.active_list_chat_states(
      list_id, profile_id, visible_after_message_position,
      last_read_message_position
    ) values (
      'a2000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000004',
      0,
      0
    )$$,
  '%permission denied%',
  'authenticated cannot spoof Chat state'
);
select throws_like(
  $$select nextval('private.active_list_chat_message_position_seq')$$,
  '%permission denied%',
  'authenticated cannot allocate a Chat position'
);
reset role;

select * from finish();
rollback;
