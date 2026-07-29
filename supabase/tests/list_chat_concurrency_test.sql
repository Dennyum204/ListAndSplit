begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select no_plan();

select extensions.dblink_connect(
  'chat_race_setup',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=chat_race_setup'
);
select extensions.dblink_connect(
  'chat_race_first',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=chat_race_first'
);
select extensions.dblink_connect(
  'chat_race_second',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=chat_race_second'
);
select extensions.dblink_connect(
  'chat_race_hold',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=chat_race_hold'
);

select extensions.dblink_exec(
  'chat_race_setup',
  $remote$
    delete from public.active_lists
    where id::text like 'd2000000-0000-4000-8000-%';

    delete from auth.users
    where id::text like 'd1000000-0000-4000-8000-%';

    delete from private.deleted_username_reservations
    where canonical_username ~ '^chatrace[0-9]{2}$';

    delete from realtime.messages
    where topic like 'account:d1000000-0000-4000-8000-%';
  $remote$
);

select extensions.dblink_exec(
  'chat_race_setup',
  $remote$
    insert into auth.users (
      id,
      email,
      email_confirmed_at,
      created_at,
      updated_at
    )
    select
      (
        'd1000000-0000-4000-8000-'
        || pg_catalog.lpad(identity_number::text, 12, '0')
      )::uuid,
      'chat-race-' || identity_number::text || '@example.test',
      pg_catalog.now(),
      pg_catalog.now(),
      pg_catalog.now()
    from pg_catalog.generate_series(1, 25) as identities(identity_number);

    update public.profiles
    set username = 'chatrace' || pg_catalog.right('0' || (
          pg_catalog.right(id::text, 2)::integer
        )::text, 2),
        display_name = 'Chat race ' || pg_catalog.right(id::text, 2)
    where id::text like 'd1000000-0000-4000-8000-%';

    insert into public.active_lists (
      id,
      owner_id,
      title,
      status,
      creation_request_id,
      archived_at
    )
    select
      (
        'd2000000-0000-4000-8000-'
        || pg_catalog.lpad(list_number::text, 12, '0')
      )::uuid,
      'd1000000-0000-4000-8000-000000000001'::uuid,
      'Chat race ' || list_number::text,
      case when list_number in (20, 21) then 'archived' else 'active' end,
      (
        'd3000000-0000-4000-8000-'
        || pg_catalog.lpad(list_number::text, 12, '0')
      )::uuid,
      case
        when list_number in (20, 21) then pg_catalog.now()
        else null
      end
    from pg_catalog.generate_series(1, 24) as lists(list_number);

    insert into public.active_list_participants (
      list_id,
      participant_profile_id,
      state
    )
    select
      (
        'd2000000-0000-4000-8000-'
        || pg_catalog.lpad(list_number::text, 12, '0')
      )::uuid,
      (
        'd1000000-0000-4000-8000-'
        || pg_catalog.lpad(
          (
            case
              when list_number in (22, 23) then 23
              when list_number = 24 then 25
              else list_number + 1
            end
          )::text,
          12,
          '0'
        )
      )::uuid,
      'member'
    from pg_catalog.generate_series(1, 24) as lists(list_number);

    insert into public.user_relationships (
      profile_low_id,
      profile_high_id,
      state,
      requester_id
    )
    select
      'd1000000-0000-4000-8000-000000000001'::uuid,
      (
        'd1000000-0000-4000-8000-'
        || pg_catalog.lpad(member_number::text, 12, '0')
      )::uuid,
      'friends',
      'd1000000-0000-4000-8000-000000000001'::uuid
    from pg_catalog.generate_series(6, 9) as members(member_number);

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
        'd5000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000015',
        pg_catalog.nextval(
          'private.active_list_chat_message_position_seq'::pg_catalog.regclass
        ),
        'd1000000-0000-4000-8000-000000000001',
        'mark first baseline',
        pg_catalog.clock_timestamp()
      ),
      (
        'd5000000-0000-4000-8000-000000000002',
        'd2000000-0000-4000-8000-000000000024',
        pg_catalog.nextval(
          'private.active_list_chat_message_position_seq'::pg_catalog.regclass
        ),
        'd1000000-0000-4000-8000-000000000001',
        'send first baseline',
        pg_catalog.clock_timestamp()
      );

    insert into public.active_list_chat_messages (
      list_id,
      message_position,
      sender_profile_id,
      body,
      created_at
    )
    select
      'd2000000-0000-4000-8000-000000000019',
      pg_catalog.nextval(
        'private.active_list_chat_message_position_seq'::pg_catalog.regclass
      ),
      'd1000000-0000-4000-8000-000000000020',
      'rate seed ' || seed_number::text,
      pg_catalog.clock_timestamp()
    from pg_catalog.generate_series(1, 19) as seeds(seed_number);
  $remote$
);

do $$
declare
  connection_name text;
begin
  foreach connection_name in array array[
    'chat_race_setup',
    'chat_race_first',
    'chat_race_second'
  ]
  loop
    perform extensions.dblink_exec(
      connection_name,
      $remote$
        create or replace function pg_temp.attempt_chat(
          action_name text,
          actor_id uuid,
          target_list_id uuid,
          target_id uuid default null,
          message_body text default null,
          send_request_id uuid default null,
          archive_value boolean default null,
          expected_version bigint default 1
        )
        returns text
        language plpgsql
        as $function$
        declare
          result_value jsonb;
        begin
          if action_name = 'account-delete' then
            delete from auth.users where id = actor_id;
            if not found then
              return 'P0002:account unavailable';
            end if;
            return 'ok';
          end if;

          perform pg_catalog.set_config(
            'request.jwt.claim.sub',
            actor_id::text,
            true
          );
          execute 'set local role authenticated';

          if action_name = 'send' then
            result_value := public.send_active_list_chat_message(
              target_list_id,
              message_body,
              send_request_id
            );
            return 'ok:' || (result_value->>'id');
          elsif action_name = 'remove' then
            perform public.remove_active_list_member(
              target_list_id,
              target_id,
              expected_version
            );
          elsif action_name = 'leave' then
            perform public.leave_active_list(
              target_list_id,
              expected_version
            );
          elsif action_name = 'block' then
            perform public.block_profile(target_id);
          elsif action_name = 'archive' then
            perform 1
            from public.set_active_list_archived(
              target_list_id,
              archive_value,
              expected_version
            );
          elsif action_name = 'delete-list' then
            perform public.delete_active_list(
              target_list_id,
              expected_version
            );
          elsif action_name = 'mark' then
            result_value := public.mark_active_list_chat_read(
              target_list_id,
              target_id
            );
            return 'ok:' || coalesce(result_value->>'changed', 'false');
          else
            raise exception using
              errcode = '22023',
              message = 'unknown race action';
          end if;

          return 'ok';
        exception
          when others then
            return sqlstate || ':' || sqlerrm;
        end;
        $function$;
      $remote$
    );
  end loop;
end;
$$;

create temporary table chat_race_results (
  label text primary key,
  value jsonb not null
) on commit drop;

create or replace function pg_temp.run_chat_race(
  first_query text,
  second_query text
)
returns jsonb
language plpgsql
as $$
declare
  first_result text;
  second_result text;
  second_waited boolean;
begin
  perform extensions.dblink_exec('chat_race_first', 'begin');
  select remote_result.result
  into first_result
  from extensions.dblink(
    'chat_race_first',
    first_query
  ) as remote_result(result text);

  perform extensions.dblink_exec('chat_race_second', 'begin');
  perform extensions.dblink_send_query(
    'chat_race_second',
    second_query
  );
  perform pg_catalog.pg_sleep(0.15);
  second_waited :=
    extensions.dblink_is_busy('chat_race_second') = 1;

  perform extensions.dblink_exec('chat_race_first', 'commit');
  select remote_result.result
  into second_result
  from extensions.dblink_get_result(
    'chat_race_second'
  ) as remote_result(result text);
  perform 1
  from extensions.dblink_get_result(
    'chat_race_second'
  ) as drained_result(result text);
  perform extensions.dblink_exec('chat_race_second', 'commit');

  return pg_catalog.jsonb_build_object(
    'first',
    first_result,
    'second',
    second_result,
    'second_waited',
    second_waited
  );
exception
  when others then
    begin
      perform extensions.dblink_exec('chat_race_first', 'rollback');
    exception when others then null;
    end;
    begin
      if extensions.dblink_is_busy('chat_race_second') = 0 then
        perform extensions.dblink_exec('chat_race_second', 'rollback');
      end if;
    exception when others then null;
    end;
    raise;
end;
$$;

-- Send commits before owner removal.
insert into chat_race_results(label, value)
values (
  'send-before-remove',
  pg_temp.run_chat_race(
    $$select pg_temp.attempt_chat(
      'send',
      'd1000000-0000-4000-8000-000000000002',
      'd2000000-0000-4000-8000-000000000001',
      null,
      'send before remove',
      'd4000000-0000-4000-8000-000000000001'
    )$$,
    $$select pg_temp.attempt_chat(
      'remove',
      'd1000000-0000-4000-8000-000000000001',
      'd2000000-0000-4000-8000-000000000001',
      'd1000000-0000-4000-8000-000000000002'
    )$$
  )
);

-- Owner removal commits before the stale send.
insert into chat_race_results(label, value)
values (
  'remove-before-send',
  pg_temp.run_chat_race(
    $$select pg_temp.attempt_chat(
      'remove',
      'd1000000-0000-4000-8000-000000000001',
      'd2000000-0000-4000-8000-000000000002',
      'd1000000-0000-4000-8000-000000000003'
    )$$,
    $$select pg_temp.attempt_chat(
      'send',
      'd1000000-0000-4000-8000-000000000003',
      'd2000000-0000-4000-8000-000000000002',
      null,
      'rejected after remove',
      'd4000000-0000-4000-8000-000000000002'
    )$$
  )
);

-- Send and voluntary departure in both commit orders.
insert into chat_race_results(label, value)
values
  (
    'send-before-leave',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000004',
        'd2000000-0000-4000-8000-000000000003',
        null,
        'send before leave',
        'd4000000-0000-4000-8000-000000000003'
      )$$,
      $$select pg_temp.attempt_chat(
        'leave',
        'd1000000-0000-4000-8000-000000000004',
        'd2000000-0000-4000-8000-000000000003'
      )$$
    )
  ),
  (
    'leave-before-send',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'leave',
        'd1000000-0000-4000-8000-000000000005',
        'd2000000-0000-4000-8000-000000000004'
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000005',
        'd2000000-0000-4000-8000-000000000004',
        null,
        'rejected after leave',
        'd4000000-0000-4000-8000-000000000004'
      )$$
    )
  );

-- Member blocking the owner in both commit orders.
insert into chat_race_results(label, value)
values
  (
    'send-before-member-block',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000006',
        'd2000000-0000-4000-8000-000000000005',
        null,
        'send before member block',
        'd4000000-0000-4000-8000-000000000005'
      )$$,
      $$select pg_temp.attempt_chat(
        'block',
        'd1000000-0000-4000-8000-000000000006',
        'd2000000-0000-4000-8000-000000000005',
        'd1000000-0000-4000-8000-000000000001'
      )$$
    )
  ),
  (
    'member-block-before-send',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'block',
        'd1000000-0000-4000-8000-000000000007',
        'd2000000-0000-4000-8000-000000000006',
        'd1000000-0000-4000-8000-000000000001'
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000007',
        'd2000000-0000-4000-8000-000000000006',
        null,
        'rejected after member block',
        'd4000000-0000-4000-8000-000000000006'
      )$$
    )
  );

-- Owner blocking the member in both commit orders.
insert into chat_race_results(label, value)
values
  (
    'send-before-owner-block',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000008',
        'd2000000-0000-4000-8000-000000000007',
        null,
        'send before owner block',
        'd4000000-0000-4000-8000-000000000007'
      )$$,
      $$select pg_temp.attempt_chat(
        'block',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000007',
        'd1000000-0000-4000-8000-000000000008'
      )$$
    )
  ),
  (
    'owner-block-before-send',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'block',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000008',
        'd1000000-0000-4000-8000-000000000009'
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000009',
        'd2000000-0000-4000-8000-000000000008',
        null,
        'rejected after owner block',
        'd4000000-0000-4000-8000-000000000008'
      )$$
    )
  );

-- Send and archive in both commit orders.
insert into chat_race_results(label, value)
values
  (
    'send-before-archive',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000010',
        'd2000000-0000-4000-8000-000000000009',
        null,
        'send before archive',
        'd4000000-0000-4000-8000-000000000009'
      )$$,
      $$select pg_temp.attempt_chat(
        'archive',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000009',
        null,
        null,
        null,
        true
      )$$
    )
  ),
  (
    'archive-before-send',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'archive',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000010',
        null,
        null,
        null,
        true
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000011',
        'd2000000-0000-4000-8000-000000000010',
        null,
        'rejected after archive',
        'd4000000-0000-4000-8000-000000000010'
      )$$
    )
  );

-- Send and permanent list deletion in both commit orders.
insert into chat_race_results(label, value)
values
  (
    'send-before-list-delete',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000012',
        'd2000000-0000-4000-8000-000000000011',
        null,
        'send before list delete',
        'd4000000-0000-4000-8000-000000000011'
      )$$,
      $$select pg_temp.attempt_chat(
        'delete-list',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000011'
      )$$
    )
  ),
  (
    'list-delete-before-send',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'delete-list',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000012'
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000013',
        'd2000000-0000-4000-8000-000000000012',
        null,
        'rejected after list delete',
        'd4000000-0000-4000-8000-000000000012'
      )$$
    )
  );

-- Send and sender account deletion in both commit orders.
insert into chat_race_results(label, value)
values
  (
    'send-before-account-delete',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000014',
        'd2000000-0000-4000-8000-000000000013',
        null,
        'send before account delete',
        'd4000000-0000-4000-8000-000000000013'
      )$$,
      $$select pg_temp.attempt_chat(
        'account-delete',
        'd1000000-0000-4000-8000-000000000014',
        'd2000000-0000-4000-8000-000000000013'
      )$$
    )
  ),
  (
    'account-delete-before-send',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'account-delete',
        'd1000000-0000-4000-8000-000000000015',
        'd2000000-0000-4000-8000-000000000014'
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000015',
        'd2000000-0000-4000-8000-000000000014',
        null,
        'rejected after account delete',
        'd4000000-0000-4000-8000-000000000014'
      )$$
    )
  );

-- Marking the old cursor and receiving a new message in both commit orders.
insert into chat_race_results(label, value)
values
  (
    'mark-before-incoming-send',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'mark',
        'd1000000-0000-4000-8000-000000000016',
        'd2000000-0000-4000-8000-000000000015',
        'd5000000-0000-4000-8000-000000000001'
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000015',
        null,
        'incoming after mark',
        'd4000000-0000-4000-8000-000000000015'
      )$$
    )
  ),
  (
    'incoming-send-before-mark',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000024',
        null,
        'incoming before mark',
        'd4000000-0000-4000-8000-000000000024'
      )$$,
      $$select pg_temp.attempt_chat(
        'mark',
        'd1000000-0000-4000-8000-000000000025',
        'd2000000-0000-4000-8000-000000000024',
        'd5000000-0000-4000-8000-000000000002'
      )$$
    )
  );

-- Identical and conflicting request UUID races.
insert into chat_race_results(label, value)
values
  (
    'identical-request',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000017',
        'd2000000-0000-4000-8000-000000000016',
        null,
        'same request',
        'd4000000-0000-4000-8000-000000000016'
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000017',
        'd2000000-0000-4000-8000-000000000016',
        null,
        'same request',
        'd4000000-0000-4000-8000-000000000016'
      )$$
    )
  ),
  (
    'conflicting-request',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000018',
        'd2000000-0000-4000-8000-000000000017',
        null,
        'first payload',
        'd4000000-0000-4000-8000-000000000017'
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000018',
        'd2000000-0000-4000-8000-000000000017',
        null,
        'second payload',
        'd4000000-0000-4000-8000-000000000017'
      )$$
    )
  );

-- Different request UUIDs serialize into distinct positions.
insert into chat_race_results(label, value)
values (
  'two-different-sends',
  pg_temp.run_chat_race(
    $$select pg_temp.attempt_chat(
      'send',
      'd1000000-0000-4000-8000-000000000019',
      'd2000000-0000-4000-8000-000000000018',
      null,
      'first different send',
      'd4000000-0000-4000-8000-000000000018'
    )$$,
    $$select pg_temp.attempt_chat(
      'send',
      'd1000000-0000-4000-8000-000000000019',
      'd2000000-0000-4000-8000-000000000018',
      null,
      'second different send',
      'd4000000-0000-4000-8000-000000000019'
    )$$
  )
);

-- Nineteen committed rows plus two concurrent sends must cap at twenty.
insert into chat_race_results(label, value)
values (
  'concurrent-rate-threshold',
  pg_temp.run_chat_race(
    $$select pg_temp.attempt_chat(
      'send',
      'd1000000-0000-4000-8000-000000000020',
      'd2000000-0000-4000-8000-000000000019',
      null,
      'twentieth send',
      'd4000000-0000-4000-8000-000000000020'
    )$$,
    $$select pg_temp.attempt_chat(
      'send',
      'd1000000-0000-4000-8000-000000000020',
      'd2000000-0000-4000-8000-000000000019',
      null,
      'twenty first send',
      'd4000000-0000-4000-8000-000000000021'
    )$$
  )
);

-- Restore before send succeeds; send against archived state before restore rejects.
insert into chat_race_results(label, value)
values
  (
    'restore-before-send',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'archive',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000020',
        null,
        null,
        null,
        false
      )$$,
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000021',
        'd2000000-0000-4000-8000-000000000020',
        null,
        'send after restore',
        'd4000000-0000-4000-8000-000000000022'
      )$$
    )
  ),
  (
    'send-before-restore',
    pg_temp.run_chat_race(
      $$select pg_temp.attempt_chat(
        'send',
        'd1000000-0000-4000-8000-000000000022',
        'd2000000-0000-4000-8000-000000000021',
        null,
        'rejected before restore',
        'd4000000-0000-4000-8000-000000000023'
      )$$,
      $$select pg_temp.attempt_chat(
        'archive',
        'd1000000-0000-4000-8000-000000000001',
        'd2000000-0000-4000-8000-000000000021',
        null,
        null,
        null,
        false
      )$$
    )
  );

-- Seed two authored rows and request ledgers for the ordered multi-list cleanup.
insert into chat_race_results(label, value)
select
  'multi-list-lower-seed',
  pg_catalog.jsonb_build_object('result', seeded_lower.result)
from extensions.dblink(
  'chat_race_setup',
  $$select pg_temp.attempt_chat(
    'send',
    'd1000000-0000-4000-8000-000000000023',
    'd2000000-0000-4000-8000-000000000022',
    null,
    'multi list lower',
    'd4000000-0000-4000-8000-000000000030'
  )$$
) as seeded_lower(result text);
insert into chat_race_results(label, value)
select
  'multi-list-upper-seed',
  pg_catalog.jsonb_build_object('result', seeded_upper.result)
from extensions.dblink(
  'chat_race_setup',
  $$select pg_temp.attempt_chat(
    'send',
    'd1000000-0000-4000-8000-000000000023',
    'd2000000-0000-4000-8000-000000000023',
    null,
    'multi list upper',
    'd4000000-0000-4000-8000-000000000031'
  )$$
) as seeded_upper(result text);

select extensions.dblink_exec('chat_race_hold', 'begin');
select extensions.dblink_exec(
  'chat_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'd2000000-0000-4000-8000-000000000022'
      for update;
    end;
    $block$;
  $remote$
);
select extensions.dblink_exec('chat_race_first', 'begin');
select extensions.dblink_send_query(
  'chat_race_first',
  $$select pg_temp.attempt_chat(
    'account-delete',
    'd1000000-0000-4000-8000-000000000023',
    'd2000000-0000-4000-8000-000000000022'
  )$$
);
select pg_catalog.pg_sleep(0.15);
select ok(
  extensions.dblink_is_busy('chat_race_first') = 1,
  'multi-list account cleanup waits at the lower ordered parent-list lock'
);
select extensions.dblink_exec('chat_race_hold', 'commit');
insert into chat_race_results(label, value)
select
  'multi-list-account-cleanup',
  pg_catalog.jsonb_build_object('result', remote_result.result)
from extensions.dblink_get_result(
  'chat_race_first'
) as remote_result(result text);
select *
from extensions.dblink_get_result(
  'chat_race_first'
) as drained_multi_list_result(result text);
select extensions.dblink_exec('chat_race_first', 'commit');

select ok(
  (
    select (value->>'first') like 'ok:%'
      and value->>'second' = 'ok'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'send-before-remove'
  )
  and exists (
    select 1
    from public.active_list_chat_messages
    where list_id = 'd2000000-0000-4000-8000-000000000001'
  )
  and not exists (
    select 1
    from public.active_list_chat_states
    where list_id = 'd2000000-0000-4000-8000-000000000001'
      and profile_id = 'd1000000-0000-4000-8000-000000000002'
  ),
  'send-before-remove commits one retained row before access cleanup'
);

select ok(
  (
    select value->>'first' = 'ok'
      and value->>'second' = 'P0002:list unavailable'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'remove-before-send'
  )
  and not exists (
    select 1
    from public.active_list_chat_messages
    where list_id = 'd2000000-0000-4000-8000-000000000002'
  )
  and not exists (
    select 1
    from private.active_list_chat_send_requests
    where list_id = 'd2000000-0000-4000-8000-000000000002'
  ),
  'remove-before-send rejects atomically after authoritative revalidation'
);

select ok(
  (
    select (value->>'first') like 'ok:%'
      and value->>'second' = 'ok'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'send-before-leave'
  )
  and (
    select value->>'first' = 'ok'
      and value->>'second' = 'P0002:list unavailable'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'leave-before-send'
  ),
  'send and departure serialize safely in both commit orders'
);

select ok(
  (
    select (value->>'first') like 'ok:%'
      and value->>'second' = 'ok'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'send-before-member-block'
  )
  and (
    select value->>'first' = 'ok'
      and value->>'second' = 'P0002:list unavailable'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'member-block-before-send'
  ),
  'member-to-owner block and send serialize safely in both commit orders'
);

select ok(
  (
    select (value->>'first') like 'ok:%'
      and value->>'second' = 'ok'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'send-before-owner-block'
  )
  and (
    select value->>'first' = 'ok'
      and value->>'second' = 'P0002:list unavailable'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'owner-block-before-send'
  ),
  'owner-to-member block and send serialize safely in both commit orders'
);

select ok(
  (
    select (value->>'first') like 'ok:%'
      and value->>'second' = 'ok'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'send-before-archive'
  )
  and (
    select value->>'first' = 'ok'
      and value->>'second' = '55000:archived list is read only'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'archive-before-send'
  ),
  'send and archive serialize safely in both commit orders'
);

select ok(
  (
    select (value->>'first') like 'ok:%'
      and value->>'second' = 'ok'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'send-before-list-delete'
  )
  and (
    select value->>'first' = 'ok'
      and value->>'second' = 'P0002:list unavailable'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'list-delete-before-send'
  )
  and not exists (
    select 1
    from public.active_lists
    where id in (
      'd2000000-0000-4000-8000-000000000011',
      'd2000000-0000-4000-8000-000000000012'
    )
  ),
  'send and permanent deletion serialize without orphaned Chat data'
);

select ok(
  (
    select (value->>'first') like 'ok:%'
      and value->>'second' = 'ok'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'send-before-account-delete'
  )
  and exists (
    select 1
    from public.active_list_chat_messages
    where list_id = 'd2000000-0000-4000-8000-000000000013'
      and sender_profile_id is null
      and body is null
      and deletion_kind = 'account'
  )
  and (
    select value->>'first' = 'ok'
      and value->>'second' like 'P0002:%'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'account-delete-before-send'
  ),
  'send and sender-account deletion serialize into privacy-safe outcomes'
);

select ok(
  (
    select value->>'first' like 'ok:%'
      and value->>'second' like 'ok:%'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'mark-before-incoming-send'
  )
  and (
    select value->>'first' like 'ok:%'
      and value->>'second' like 'ok:%'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'incoming-send-before-mark'
  )
  and (
    select (public.get_active_list_chat_unread_count(
      'd2000000-0000-4000-8000-000000000015'
    )->>'count')::integer
    from (
      select pg_catalog.set_config(
        'request.jwt.claim.sub',
        'd1000000-0000-4000-8000-000000000016',
        true
      )
    ) as configured
  ) = 1,
  'mark-read versus incoming send preserves the concurrent newer unread row'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'd1000000-0000-4000-8000-000000000025';
select is(
  (
    public.get_active_list_chat_unread_count(
      'd2000000-0000-4000-8000-000000000024'
    )->>'count'
  )::integer,
  1,
  'send-before-mark through an older ID also leaves the newer row unread'
);
reset role;

select ok(
  (
    select value->>'first' = value->>'second'
      and value->>'first' like 'ok:%'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'identical-request'
  )
  and (
    select pg_catalog.count(*)
    from public.active_list_chat_messages
    where list_id = 'd2000000-0000-4000-8000-000000000016'
  ) = 1
  and (
    select pg_catalog.count(*)
    from private.active_list_chat_send_requests
    where list_id = 'd2000000-0000-4000-8000-000000000016'
  ) = 1,
  'concurrent identical requests converge on one message and one ledger row'
);

select ok(
  (
    select value->>'first' like 'ok:%'
      and value->>'second' = '23505:chat send request conflict'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'conflicting-request'
  )
  and (
    select pg_catalog.count(*)
    from public.active_list_chat_messages
    where list_id = 'd2000000-0000-4000-8000-000000000017'
  ) = 1
  and (
    select pg_catalog.count(*)
    from private.active_list_chat_send_requests
    where list_id = 'd2000000-0000-4000-8000-000000000017'
  ) = 1,
  'concurrent conflicting request reuse rejects without partial data'
);

select ok(
  (
    select value->>'first' like 'ok:%'
      and value->>'second' like 'ok:%'
      and value->>'first' <> value->>'second'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'two-different-sends'
  )
  and (
    select pg_catalog.count(distinct message_position)
    from public.active_list_chat_messages
    where list_id = 'd2000000-0000-4000-8000-000000000018'
  ) = 2,
  'two different concurrent sends commit as distinct ordered messages'
);

select ok(
  (
    select value->>'first' like 'ok:%'
      and value->>'second' = 'P0001:chat rate limit reached'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'concurrent-rate-threshold'
  )
  and (
    select pg_catalog.count(*)
    from public.active_list_chat_messages
    where list_id = 'd2000000-0000-4000-8000-000000000019'
  ) = 20
  and (
    select pg_catalog.count(*)
    from private.active_list_chat_send_requests
    where list_id = 'd2000000-0000-4000-8000-000000000019'
  ) = 1,
  'concurrent rate-limit threshold cannot exceed twenty successful sends'
);

select ok(
  (
    select value->>'first' = 'ok'
      and value->>'second' like 'ok:%'
      and (value->>'second_waited')::boolean
    from chat_race_results
    where label = 'restore-before-send'
  )
  and (
    select value->>'first' = '55000:archived list is read only'
      and value->>'second' = 'ok'
    from chat_race_results
    where label = 'send-before-restore'
  )
  and (
    select pg_catalog.count(*)
    from public.active_list_chat_messages
    where list_id = 'd2000000-0000-4000-8000-000000000021'
  ) = 0,
  'restore and send honor the committed archive state in both orders'
);

select ok(
  (
    select value->>'result' = 'ok'
    from chat_race_results
    where label = 'multi-list-account-cleanup'
  )
  and (
    select pg_catalog.count(*)
    from public.active_list_chat_messages
    where list_id in (
      'd2000000-0000-4000-8000-000000000022',
      'd2000000-0000-4000-8000-000000000023'
    )
      and sender_profile_id is null
      and body is null
      and deletion_kind = 'account'
  ) = 2
  and not exists (
    select 1
    from public.active_list_chat_states
    where profile_id = 'd1000000-0000-4000-8000-000000000023'
  )
  and not exists (
    select 1
    from private.active_list_chat_send_requests
    where actor_id = 'd1000000-0000-4000-8000-000000000023'
  ),
  'multi-list account cleanup locks parents in UUID order and removes private state'
);

select ok(
  not exists (
    select 1
    from private.active_list_chat_send_requests as request_record
    left join public.active_list_chat_messages as message_record
      on message_record.id = request_record.message_id
    where message_record.id is null
  )
  and not exists (
    select 1
    from public.active_list_chat_states as state_record
    left join public.active_lists as list_record
      on list_record.id = state_record.list_id
    left join public.profiles as profile_record
      on profile_record.id = state_record.profile_id
    where list_record.id is null or profile_record.id is null
  ),
  'all race outcomes preserve request and state referential integrity'
);

select is(
  (
    select pg_catalog.count(*)
    from public.active_lists
    where id::text like 'd2000000-0000-4000-8000-%'
      and version <> case
        when id in (
          'd2000000-0000-4000-8000-000000000001',
          'd2000000-0000-4000-8000-000000000002',
          'd2000000-0000-4000-8000-000000000003',
          'd2000000-0000-4000-8000-000000000004',
          'd2000000-0000-4000-8000-000000000005',
          'd2000000-0000-4000-8000-000000000006',
          'd2000000-0000-4000-8000-000000000007',
          'd2000000-0000-4000-8000-000000000008',
          'd2000000-0000-4000-8000-000000000009',
          'd2000000-0000-4000-8000-000000000010',
          'd2000000-0000-4000-8000-000000000013',
          'd2000000-0000-4000-8000-000000000014',
          'd2000000-0000-4000-8000-000000000020',
          'd2000000-0000-4000-8000-000000000021',
          'd2000000-0000-4000-8000-000000000022',
          'd2000000-0000-4000-8000-000000000023'
        ) then 2
        else 1
      end
  ),
  0::bigint,
  'Chat operations add no list-version bump beyond serialized lifecycle mutations'
);

select extensions.dblink_exec(
  'chat_race_setup',
  $remote$
    delete from public.active_lists
    where id::text like 'd2000000-0000-4000-8000-%';

    delete from auth.users
    where id::text like 'd1000000-0000-4000-8000-%';

    delete from private.deleted_username_reservations
    where canonical_username ~ '^chatrace[0-9]{2}$';

    delete from realtime.messages
    where topic like 'account:d1000000-0000-4000-8000-%';
  $remote$
);

select is(
  (
    select pg_catalog.count(*)
    from public.active_lists
    where id::text like 'd2000000-0000-4000-8000-%'
  ),
  0::bigint,
  'autonomous Chat race fixtures are removed'
);

select extensions.dblink_disconnect('chat_race_hold');
select extensions.dblink_disconnect('chat_race_first');
select extensions.dblink_disconnect('chat_race_second');
select extensions.dblink_disconnect('chat_race_setup');

select * from finish();
rollback;
