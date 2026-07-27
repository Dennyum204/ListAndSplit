begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select no_plan();

select extensions.dblink_connect(
  'template_send_race_setup',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=template_send_race_setup'
);
select extensions.dblink_connect(
  'template_send_race_first',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=template_send_race_first'
);
select extensions.dblink_connect(
  'template_send_race_second',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=template_send_race_second'
);

select extensions.dblink_exec(
  'template_send_race_setup',
  $remote$
    delete from auth.users
    where id in (
      'f1000000-0000-4000-8000-000000000001',
      'f1000000-0000-4000-8000-000000000002',
      'f1000000-0000-4000-8000-000000000003'
    );

    delete from private.deleted_username_reservations
    where canonical_username in (
      'sendracesource',
      'sendracequota',
      'sendracereplay'
    );

    insert into auth.users (
      id,
      email,
      email_confirmed_at,
      created_at,
      updated_at
    )
    values
      (
        'f1000000-0000-4000-8000-000000000001',
        'send-race-source@example.test',
        now(),
        now(),
        now()
      ),
      (
        'f1000000-0000-4000-8000-000000000002',
        'send-race-quota@example.test',
        now(),
        now(),
        now()
      ),
      (
        'f1000000-0000-4000-8000-000000000003',
        'send-race-replay@example.test',
        now(),
        now(),
        now()
      );

    update public.profiles
    set username = case id
          when 'f1000000-0000-4000-8000-000000000001'
            then 'sendracesource'
          when 'f1000000-0000-4000-8000-000000000002'
            then 'sendracequota'
          else 'sendracereplay'
        end,
        display_name = 'Template send race'
    where id in (
      'f1000000-0000-4000-8000-000000000001',
      'f1000000-0000-4000-8000-000000000002',
      'f1000000-0000-4000-8000-000000000003'
    );

    insert into public.user_relationships (
      profile_low_id,
      profile_high_id,
      state,
      requester_id
    )
    values
      (
        'f1000000-0000-4000-8000-000000000001',
        'f1000000-0000-4000-8000-000000000002',
        'friends',
        'f1000000-0000-4000-8000-000000000001'
      ),
      (
        'f1000000-0000-4000-8000-000000000001',
        'f1000000-0000-4000-8000-000000000003',
        'friends',
        'f1000000-0000-4000-8000-000000000001'
      );

    insert into public.templates (
      id,
      owner_id,
      name,
      creation_request_id
    )
    values
      (
        'f2000000-0000-4000-8000-000000000001',
        'f1000000-0000-4000-8000-000000000001',
        'Quota source one',
        'f3000000-0000-4000-8000-000000000001'
      ),
      (
        'f2000000-0000-4000-8000-000000000002',
        'f1000000-0000-4000-8000-000000000001',
        'Quota source two',
        'f3000000-0000-4000-8000-000000000002'
      ),
      (
        'f2000000-0000-4000-8000-000000000003',
        'f1000000-0000-4000-8000-000000000001',
        'Replay source',
        'f3000000-0000-4000-8000-000000000003'
      ),
      (
        'f2000000-0000-4000-8000-000000000004',
        'f1000000-0000-4000-8000-000000000001',
        'Deletion race source',
        'f3000000-0000-4000-8000-000000000004'
      );

    insert into public.templates (
      owner_id,
      name,
      creation_request_id
    )
    select
      'f1000000-0000-4000-8000-000000000002',
      'Existing quota template ' || fixture_number,
      gen_random_uuid()
    from generate_series(1, 99) as fixture(fixture_number);

    insert into public.template_sends (
      id,
      sender_id,
      recipient_id,
      source_template_id,
      snapshot_name,
      snapshot_item_count,
      state,
      version
    )
    values
      (
        'f4000000-0000-4000-8000-000000000001',
        'f1000000-0000-4000-8000-000000000001',
        'f1000000-0000-4000-8000-000000000002',
        'f2000000-0000-4000-8000-000000000001',
        'Quota source one',
        1,
        'pending',
        1
      ),
      (
        'f4000000-0000-4000-8000-000000000002',
        'f1000000-0000-4000-8000-000000000001',
        'f1000000-0000-4000-8000-000000000002',
        'f2000000-0000-4000-8000-000000000002',
        'Quota source two',
        1,
        'pending',
        1
      ),
      (
        'f4000000-0000-4000-8000-000000000003',
        'f1000000-0000-4000-8000-000000000001',
        'f1000000-0000-4000-8000-000000000003',
        'f2000000-0000-4000-8000-000000000003',
        'Replay source',
        1,
        'pending',
        1
      ),
      (
        'f4000000-0000-4000-8000-000000000004',
        'f1000000-0000-4000-8000-000000000001',
        'f1000000-0000-4000-8000-000000000003',
        'f2000000-0000-4000-8000-000000000004',
        'Deletion race source',
        1,
        'pending',
        1
      );

    insert into public.template_send_items (
      template_send_id,
      name,
      quantity_thousandths,
      position
    )
    select
      send_id,
      'Race item',
      1000,
      1
    from unnest(
      array[
        'f4000000-0000-4000-8000-000000000001'::uuid,
        'f4000000-0000-4000-8000-000000000002'::uuid,
        'f4000000-0000-4000-8000-000000000003'::uuid,
        'f4000000-0000-4000-8000-000000000004'::uuid
      ]
    ) as fixture(send_id);
  $remote$
);

select extensions.dblink_exec(
  'template_send_race_first',
  $remote$
    create or replace function pg_temp.attempt_accept(
      send_id uuid,
      send_version bigint,
      mutation_request_id uuid
    )
    returns text
    language plpgsql
    as $function$
    declare
      copy_id uuid;
    begin
      select result.accepted_template_id
      into copy_id
      from public.accept_template_send(
        send_id,
        send_version,
        mutation_request_id
      ) as result;
      return 'ok:' || copy_id::text;
    exception
      when others then return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_delete(
      template_id uuid,
      template_version bigint
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform public.delete_private_template(
        template_id,
        template_version
      );
      return 'ok';
    exception
      when others then return sqlstate;
    end;
    $function$;
  $remote$
);

select extensions.dblink_exec(
  'template_send_race_second',
  $remote$
    create or replace function pg_temp.attempt_accept(
      send_id uuid,
      send_version bigint,
      mutation_request_id uuid
    )
    returns text
    language plpgsql
    as $function$
    declare
      copy_id uuid;
    begin
      select result.accepted_template_id
      into copy_id
      from public.accept_template_send(
        send_id,
        send_version,
        mutation_request_id
      ) as result;
      return 'ok:' || copy_id::text;
    exception
      when others then return sqlstate;
    end;
    $function$;
  $remote$
);

create temporary table template_send_race_results (
  label text primary key,
  result text not null
) on commit drop;

-- Two different accepts serialize on the recipient template quota. Only one
-- may consume the final slot; the losing request remains pending.
select extensions.dblink_exec('template_send_race_first', 'begin');
select extensions.dblink_exec(
  'template_send_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'template_send_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'template_send_race_first',
    $remote$
      select pg_temp.attempt_accept(
        'f4000000-0000-4000-8000-000000000001',
        1,
        'f5000000-0000-4000-8000-000000000001'
      )
    $remote$
  ),
  1,
  'the first final-slot accept starts'
);
select pg_catalog.pg_sleep(0.1);

select extensions.dblink_exec('template_send_race_second', 'begin');
select extensions.dblink_exec(
  'template_send_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'template_send_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'template_send_race_second',
    $remote$
      select pg_temp.attempt_accept(
        'f4000000-0000-4000-8000-000000000002',
        1,
        'f5000000-0000-4000-8000-000000000002'
      )
    $remote$
  ),
  1,
  'the competing final-slot accept starts'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('template_send_race_second') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'template_send_race_second'
      and wait_event_type = 'Lock'
  ),
  'the competing accept waits on the recipient quota lock'
);

insert into template_send_race_results
select 'quota-first', result
from extensions.dblink_get_result('template_send_race_first')
  as remote_result(result text);
select *
from extensions.dblink_get_result('template_send_race_first')
  as drained(status text);
select extensions.dblink_exec('template_send_race_first', 'commit');
insert into template_send_race_results
select 'quota-second', result
from extensions.dblink_get_result('template_send_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('template_send_race_second')
  as drained(status text);
select extensions.dblink_exec('template_send_race_second', 'commit');

select ok(
  (
    select result
    from template_send_race_results
    where label = 'quota-first'
  ) like 'ok:%',
  'one concurrent accept consumes the final slot'
);
select is(
  (
    select result
    from template_send_race_results
    where label = 'quota-second'
  ),
  '54000',
  'the competing accept receives the capacity SQLSTATE'
);
select is(
  (
    select pg_catalog.count(*)
    from public.templates
    where owner_id = 'f1000000-0000-4000-8000-000000000002'
  ),
  100::bigint,
  'concurrent acceptance cannot exceed the 100-template quota'
);
select ok(
  (
    select state = 'accepted' and version = 2
    from public.template_sends
    where id = 'f4000000-0000-4000-8000-000000000001'
  )
  and (
    select state = 'pending'
      and version = 1
      and accepted_template_id is null
    from public.template_sends
    where id = 'f4000000-0000-4000-8000-000000000002'
  ),
  'the capacity loser has no partial state or version change'
);

-- Concurrent identical retries converge on one accepted copy.
select extensions.dblink_exec('template_send_race_first', 'begin');
select extensions.dblink_exec(
  'template_send_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'template_send_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000003'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'template_send_race_first',
    $remote$
      select pg_temp.attempt_accept(
        'f4000000-0000-4000-8000-000000000003',
        1,
        'f5000000-0000-4000-8000-000000000003'
      )
    $remote$
  ),
  1,
  'the first idempotent accept starts'
);
select pg_catalog.pg_sleep(0.1);

select extensions.dblink_exec('template_send_race_second', 'begin');
select extensions.dblink_exec(
  'template_send_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'template_send_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000003'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'template_send_race_second',
    $remote$
      select pg_temp.attempt_accept(
        'f4000000-0000-4000-8000-000000000003',
        1,
        'f5000000-0000-4000-8000-000000000003'
      )
    $remote$
  ),
  1,
  'the identical retry starts while the first is uncommitted'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('template_send_race_second') = 1,
  'the identical retry waits for the first request ledger result'
);
insert into template_send_race_results
select 'replay-first', result
from extensions.dblink_get_result('template_send_race_first')
  as remote_result(result text);
select *
from extensions.dblink_get_result('template_send_race_first')
  as drained(status text);
select extensions.dblink_exec('template_send_race_first', 'commit');
insert into template_send_race_results
select 'replay-second', result
from extensions.dblink_get_result('template_send_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('template_send_race_second')
  as drained(status text);
select extensions.dblink_exec('template_send_race_second', 'commit');
select is(
  (
    select pg_catalog.count(distinct result)
    from template_send_race_results
    where label like 'replay-%'
      and result like 'ok:%'
  ),
  1::bigint,
  'concurrent identical accepts return one destination identity'
);
select is(
  (
    select pg_catalog.count(*)
    from public.templates
    where owner_id = 'f1000000-0000-4000-8000-000000000003'
  ),
  1::bigint,
  'concurrent identical accepts create exactly one template'
);

-- A source deletion that wins the race closes the pending invitation before
-- acceptance and therefore creates no recipient copy.
select extensions.dblink_exec('template_send_race_first', 'begin');
select extensions.dblink_exec(
  'template_send_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'template_send_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'template_send_race_first',
    $remote$
      select pg_temp.attempt_delete(
        'f2000000-0000-4000-8000-000000000004',
        1
      )
    $remote$
  ),
  1,
  'source deletion starts first'
);
select pg_catalog.pg_sleep(0.1);

select extensions.dblink_exec('template_send_race_second', 'begin');
select extensions.dblink_exec(
  'template_send_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'template_send_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000003'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'template_send_race_second',
    $remote$
      select pg_temp.attempt_accept(
        'f4000000-0000-4000-8000-000000000004',
        1,
        'f5000000-0000-4000-8000-000000000004'
      )
    $remote$
  ),
  1,
  'acceptance starts while source deletion is uncommitted'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('template_send_race_second') = 1,
  'acceptance waits for source-deletion lifecycle closure'
);
insert into template_send_race_results
select 'delete-first', result
from extensions.dblink_get_result('template_send_race_first')
  as remote_result(result text);
select *
from extensions.dblink_get_result('template_send_race_first')
  as drained(status text);
select extensions.dblink_exec('template_send_race_first', 'commit');
insert into template_send_race_results
select 'delete-accept', result
from extensions.dblink_get_result('template_send_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('template_send_race_second')
  as drained(status text);
select extensions.dblink_exec('template_send_race_second', 'commit');
select is(
  (
    select result
    from template_send_race_results
    where label = 'delete-first'
  ),
  'ok',
  'source deletion commits successfully'
);
select is(
  (
    select result
    from template_send_race_results
    where label = 'delete-accept'
  ),
  '55000',
  'acceptance losing to source deletion is rejected'
);
select ok(
  (
    select state = 'unavailable'
      and version = 2
      and source_template_id is null
      and accepted_template_id is null
    from public.template_sends
    where id = 'f4000000-0000-4000-8000-000000000004'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.templates
    where owner_id = 'f1000000-0000-4000-8000-000000000003'
  ),
  'the deletion race leaves no partial copy or extra version change'
);

select extensions.dblink_exec(
  'template_send_race_setup',
  $remote$
    delete from auth.users
    where id in (
      'f1000000-0000-4000-8000-000000000001',
      'f1000000-0000-4000-8000-000000000002',
      'f1000000-0000-4000-8000-000000000003'
    );
    delete from private.deleted_username_reservations
    where canonical_username in (
      'sendracesource',
      'sendracequota',
      'sendracereplay'
    );
  $remote$
);

select extensions.dblink_disconnect('template_send_race_first');
select extensions.dblink_disconnect('template_send_race_second');
select extensions.dblink_disconnect('template_send_race_setup');

select * from finish();
rollback;
