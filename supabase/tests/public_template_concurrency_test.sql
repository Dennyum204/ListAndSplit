begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select no_plan();

select extensions.dblink_connect(
  'public_template_race_setup',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=public_template_race_setup'
);
select extensions.dblink_connect(
  'public_template_race_first',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=public_template_race_first'
);
select extensions.dblink_connect(
  'public_template_race_second',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=public_template_race_second'
);

select extensions.dblink_exec(
  'public_template_race_setup',
  $remote$
    delete from auth.users
    where id in (
      'e1000000-0000-4000-8000-000000000001',
      'e1000000-0000-4000-8000-000000000002',
      'e1000000-0000-4000-8000-000000000003',
      'e1000000-0000-4000-8000-000000000004'
    );

    delete from private.deleted_username_reservations
    where canonical_username in (
      'publicracesource',
      'publicracecopier',
      'publicracesourcegone',
      'publicracequota'
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
        'e1000000-0000-4000-8000-000000000001',
        'public-race-source@example.test',
        now(),
        now(),
        now()
      ),
      (
        'e1000000-0000-4000-8000-000000000002',
        'public-race-copier@example.test',
        now(),
        now(),
        now()
      ),
      (
        'e1000000-0000-4000-8000-000000000003',
        'public-race-source-gone@example.test',
        now(),
        now(),
        now()
      ),
      (
        'e1000000-0000-4000-8000-000000000004',
        'public-race-quota@example.test',
        now(),
        now(),
        now()
      );

    update public.profiles
    set username = case id
          when 'e1000000-0000-4000-8000-000000000001'
            then 'publicracesource'
          when 'e1000000-0000-4000-8000-000000000002'
            then 'publicracecopier'
          when 'e1000000-0000-4000-8000-000000000003'
            then 'publicracesourcegone'
          else 'publicracequota'
        end,
        display_name = 'Public template race'
    where id in (
      'e1000000-0000-4000-8000-000000000001',
      'e1000000-0000-4000-8000-000000000002',
      'e1000000-0000-4000-8000-000000000003',
      'e1000000-0000-4000-8000-000000000004'
    );

    insert into public.templates (
      id,
      owner_id,
      name,
      version,
      creation_request_id,
      published_at
    )
    values
      (
        'e2000000-0000-4000-8000-000000000001',
        'e1000000-0000-4000-8000-000000000001',
        'Duplicate source',
        1,
        'e3000000-0000-4000-8000-000000000001',
        clock_timestamp()
      ),
      (
        'e2000000-0000-4000-8000-000000000002',
        'e1000000-0000-4000-8000-000000000001',
        'Edit source',
        1,
        'e3000000-0000-4000-8000-000000000002',
        clock_timestamp()
      ),
      (
        'e2000000-0000-4000-8000-000000000003',
        'e1000000-0000-4000-8000-000000000001',
        'Unpublish source',
        1,
        'e3000000-0000-4000-8000-000000000003',
        clock_timestamp()
      ),
      (
        'e2000000-0000-4000-8000-000000000004',
        'e1000000-0000-4000-8000-000000000001',
        'Delete source',
        1,
        'e3000000-0000-4000-8000-000000000004',
        clock_timestamp()
      ),
      (
        'e2000000-0000-4000-8000-000000000005',
        'e1000000-0000-4000-8000-000000000001',
        'Caller block source',
        1,
        'e3000000-0000-4000-8000-000000000005',
        clock_timestamp()
      ),
      (
        'e2000000-0000-4000-8000-000000000006',
        'e1000000-0000-4000-8000-000000000001',
        'Owner block source',
        1,
        'e3000000-0000-4000-8000-000000000006',
        clock_timestamp()
      ),
      (
        'e2000000-0000-4000-8000-000000000007',
        'e1000000-0000-4000-8000-000000000003',
        'Deleted account source',
        1,
        'e3000000-0000-4000-8000-000000000007',
        clock_timestamp()
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
        'e4000000-0000-4000-8000-000000000001',
        'e2000000-0000-4000-8000-000000000001',
        'First duplicate',
        1000,
        1,
        'e5000000-0000-4000-8000-000000000001'
      ),
      (
        'e4000000-0000-4000-8000-000000000002',
        'e2000000-0000-4000-8000-000000000001',
        'First duplicate',
        2500,
        2,
        'e5000000-0000-4000-8000-000000000002'
      );

    insert into public.templates (
      owner_id,
      name,
      creation_request_id
    )
    select
      'e1000000-0000-4000-8000-000000000004',
      'Quota fixture ' || fixture_number,
      gen_random_uuid()
    from generate_series(1, 99) as fixture_number;

    delete from realtime.messages
    where topic like 'account:e1000000-0000-4000-8000-%';
  $remote$
);

select extensions.dblink_exec(
  'public_template_race_first',
  $remote$
    create or replace function pg_temp.attempt_copy(
      source_id uuid,
      source_version bigint,
      copy_request_id uuid
    )
    returns text
    language plpgsql
    as $function$
    declare
      destination_id uuid;
    begin
      select copied.template_id
      into destination_id
      from public.copy_public_template(
        source_id,
        source_version,
        copy_request_id
      ) as copied;
      return 'ok:' || destination_id::text;
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_update(
      source_id uuid,
      source_name text,
      source_version bigint
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform *
      from public.update_private_template(
        source_id,
        source_name,
        null,
        source_version
      );
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_publication(
      source_id uuid,
      desired_public boolean,
      source_version bigint
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform *
      from public.set_template_publication(
        source_id,
        desired_public,
        source_version
      );
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_delete_template(
      source_id uuid,
      source_version bigint
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform public.delete_private_template(source_id, source_version);
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_block(target_id uuid)
    returns text
    language plpgsql
    as $function$
    begin
      perform public.block_profile(target_id);
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_auth_delete(target_id uuid)
    returns text
    language plpgsql
    as $function$
    begin
      delete from auth.users where id = target_id;
      if not found then
        return 'missing';
      end if;
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$
  $remote$
);

select extensions.dblink_exec(
  'public_template_race_second',
  $remote$
    create or replace function pg_temp.attempt_copy(
      source_id uuid,
      source_version bigint,
      copy_request_id uuid
    )
    returns text
    language plpgsql
    as $function$
    declare
      destination_id uuid;
    begin
      select copied.template_id
      into destination_id
      from public.copy_public_template(
        source_id,
        source_version,
        copy_request_id
      ) as copied;
      return 'ok:' || destination_id::text;
    exception
      when others then
        return sqlstate;
    end;
    $function$
  $remote$
);

create temporary table public_template_race_results (
  label text primary key,
  result text not null
) on commit drop;

-- Two in-flight copies with the same caller/request are serialized by the
-- destination-owner lock and converge on the same completed ledger result.
select extensions.dblink_exec('public_template_race_first', 'begin');
select extensions.dblink_exec(
  'public_template_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_first',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000001',
        1,
        'e6000000-0000-4000-8000-000000000001'
      )
    $remote$
  ),
  1,
  'first identical copy starts asynchronously'
);
select pg_catalog.pg_sleep(0.1);

select extensions.dblink_exec('public_template_race_second', 'begin');
select extensions.dblink_exec(
  'public_template_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_second',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000001',
        1,
        'e6000000-0000-4000-8000-000000000001'
      )
    $remote$
  ),
  1,
  'second identical copy starts while the first result is uncommitted'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('public_template_race_second') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'public_template_race_second'
      and wait_event_type = 'Lock'
  ),
  'duplicate copy retry waits on the deterministic destination-owner lock'
);

insert into public_template_race_results
select 'duplicate-first', result
from extensions.dblink_get_result('public_template_race_first')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_first')
  as drained(status text);
select extensions.dblink_exec('public_template_race_first', 'commit');
insert into public_template_race_results
select 'duplicate-second', result
from extensions.dblink_get_result('public_template_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_second')
  as drained(status text);
select extensions.dblink_exec('public_template_race_second', 'commit');

select is(
  (
    select pg_catalog.count(distinct result)
    from public_template_race_results
    where label like 'duplicate-%'
      and result like 'ok:%'
  ),
  1::bigint,
  'concurrent identical submissions return one destination identity'
);
select is(
  (
    select pg_catalog.count(*)
    from public.templates
    where owner_id = 'e1000000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'concurrent identical submissions create exactly one template'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_copy_requests
    where owner_id = 'e1000000-0000-4000-8000-000000000002'
      and request_id = 'e6000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'concurrent identical submissions create exactly one ledger row'
);

-- An owner edit that commits while a copy waits makes the old source version
-- stale. The rejected copy leaves no destination or ledger residue.
select extensions.dblink_exec('public_template_race_first', 'begin');
select extensions.dblink_exec(
  'public_template_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  (
    select result
    from extensions.dblink(
      'public_template_race_first',
      $remote$
        select pg_temp.attempt_update(
          'e2000000-0000-4000-8000-000000000002',
          'Edited source',
          1
        )
      $remote$
    ) as update_result(result text)
  ),
  'ok',
  'source edit completes inside an open transaction'
);
select extensions.dblink_exec('public_template_race_second', 'begin');
select extensions.dblink_exec(
  'public_template_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_second',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000002',
        1,
        'e6000000-0000-4000-8000-000000000002'
      )
    $remote$
  ),
  1,
  'copy starts against an concurrently edited source'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('public_template_race_second') = 1,
  'copy waits for the source edit transaction'
);
select extensions.dblink_exec('public_template_race_first', 'commit');
insert into public_template_race_results
select 'edit-copy', result
from extensions.dblink_get_result('public_template_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_second')
  as drained(status text);
select extensions.dblink_exec('public_template_race_second', 'commit');
select is(
  (
    select result
    from public_template_race_results
    where label = 'edit-copy'
  ),
  '40001',
  'a copy losing the source-edit race is rejected as stale'
);

-- Unpublication and deletion similarly win at the authoritative source row.
select extensions.dblink_exec('public_template_race_first', 'begin');
select extensions.dblink_exec(
  'public_template_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  (
    select result
    from extensions.dblink(
      'public_template_race_first',
      $remote$
        select pg_temp.attempt_publication(
          'e2000000-0000-4000-8000-000000000003',
          false,
          1
        )
      $remote$
    ) as publication_result(result text)
  ),
  'ok',
  'unpublication completes inside an open transaction'
);
select extensions.dblink_exec('public_template_race_second', 'begin');
select extensions.dblink_exec(
  'public_template_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_second',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000003',
        1,
        'e6000000-0000-4000-8000-000000000003'
      )
    $remote$
  ),
  1,
  'copy starts against a concurrently unpublished source'
);
select pg_catalog.pg_sleep(0.2);
select extensions.dblink_exec('public_template_race_first', 'commit');
insert into public_template_race_results
select 'unpublish-copy', result
from extensions.dblink_get_result('public_template_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_second')
  as drained(status text);
select extensions.dblink_exec('public_template_race_second', 'commit');
select is(
  (
    select result
    from public_template_race_results
    where label = 'unpublish-copy'
  ),
  'P0002',
  'a copy losing the unpublication race is unavailable'
);

select extensions.dblink_exec('public_template_race_first', 'begin');
select extensions.dblink_exec(
  'public_template_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  (
    select result
    from extensions.dblink(
      'public_template_race_first',
      $remote$
        select pg_temp.attempt_delete_template(
          'e2000000-0000-4000-8000-000000000004',
          1
        )
      $remote$
    ) as deletion_result(result text)
  ),
  'ok',
  'source deletion completes inside an open transaction'
);
select extensions.dblink_exec('public_template_race_second', 'begin');
select extensions.dblink_exec(
  'public_template_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_second',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000004',
        1,
        'e6000000-0000-4000-8000-000000000004'
      )
    $remote$
  ),
  1,
  'copy starts against a concurrently deleted source'
);
select pg_catalog.pg_sleep(0.2);
select extensions.dblink_exec('public_template_race_first', 'commit');
insert into public_template_race_results
select 'delete-copy', result
from extensions.dblink_get_result('public_template_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_second')
  as drained(status text);
select extensions.dblink_exec('public_template_race_second', 'commit');
select is(
  (
    select result
    from public_template_race_results
    where label = 'delete-copy'
  ),
  'P0002',
  'a copy losing the source-deletion race is unavailable'
);

-- Blocking in either direction serializes through the relationship pair before
-- the source snapshot is authorized.
select extensions.dblink_exec('public_template_race_first', 'begin');
select extensions.dblink_exec(
  'public_template_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  (
    select result
    from extensions.dblink(
      'public_template_race_first',
      $remote$
        select pg_temp.attempt_block(
          'e1000000-0000-4000-8000-000000000001'
        )
      $remote$
    ) as block_result(result text)
  ),
  'ok',
  'caller-to-owner block completes inside an open transaction'
);
select extensions.dblink_exec('public_template_race_second', 'begin');
select extensions.dblink_exec(
  'public_template_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_second',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000005',
        1,
        'e6000000-0000-4000-8000-000000000005'
      )
    $remote$
  ),
  1,
  'copy starts against a concurrent caller-to-owner block'
);
select pg_catalog.pg_sleep(0.2);
select extensions.dblink_exec('public_template_race_first', 'commit');
insert into public_template_race_results
select 'caller-block-copy', result
from extensions.dblink_get_result('public_template_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_second')
  as drained(status text);
select extensions.dblink_exec('public_template_race_second', 'commit');
select is(
  (
    select result
    from public_template_race_results
    where label = 'caller-block-copy'
  ),
  'P0002',
  'caller-to-owner blocking wins over copy without partial data'
);

select extensions.dblink_exec(
  'public_template_race_setup',
  $remote$
    delete from public.user_blocks
    where blocker_id = 'e1000000-0000-4000-8000-000000000002'
      and blocked_id = 'e1000000-0000-4000-8000-000000000001'
  $remote$
);

select extensions.dblink_exec('public_template_race_first', 'begin');
select extensions.dblink_exec(
  'public_template_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  (
    select result
    from extensions.dblink(
      'public_template_race_first',
      $remote$
        select pg_temp.attempt_block(
          'e1000000-0000-4000-8000-000000000002'
        )
      $remote$
    ) as block_result(result text)
  ),
  'ok',
  'owner-to-caller block completes inside an open transaction'
);
select extensions.dblink_exec('public_template_race_second', 'begin');
select extensions.dblink_exec(
  'public_template_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_second',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000006',
        1,
        'e6000000-0000-4000-8000-000000000006'
      )
    $remote$
  ),
  1,
  'copy starts against a concurrent owner-to-caller block'
);
select pg_catalog.pg_sleep(0.2);
select extensions.dblink_exec('public_template_race_first', 'commit');
insert into public_template_race_results
select 'owner-block-copy', result
from extensions.dblink_get_result('public_template_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_second')
  as drained(status text);
select extensions.dblink_exec('public_template_race_second', 'commit');
select is(
  (
    select result
    from public_template_race_results
    where label = 'owner-block-copy'
  ),
  'P0002',
  'owner-to-caller blocking wins over copy without partial data'
);

select extensions.dblink_exec(
  'public_template_race_setup',
  $remote$
    delete from public.user_blocks
    where blocker_id = 'e1000000-0000-4000-8000-000000000001'
      and blocked_id = 'e1000000-0000-4000-8000-000000000002'
  $remote$
);

-- Auth-root deletion owns the profile row before cascading. Copy waits for that
-- lifecycle boundary and fails generically once the source identity is gone.
select extensions.dblink_exec('public_template_race_first', 'begin');
select is(
  (
    select result
    from extensions.dblink(
      'public_template_race_first',
      $remote$
        select pg_temp.attempt_auth_delete(
          'e1000000-0000-4000-8000-000000000003'
        )
      $remote$
    ) as delete_result(result text)
  ),
  'ok',
  'source account deletion completes inside an open transaction'
);
select extensions.dblink_exec('public_template_race_second', 'begin');
select extensions.dblink_exec(
  'public_template_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_second',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000007',
        1,
        'e6000000-0000-4000-8000-000000000007'
      )
    $remote$
  ),
  1,
  'copy starts against concurrent source-account deletion'
);
select pg_catalog.pg_sleep(0.2);
select extensions.dblink_exec('public_template_race_first', 'commit');
insert into public_template_race_results
select 'account-delete-copy', result
from extensions.dblink_get_result('public_template_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_second')
  as drained(status text);
select extensions.dblink_exec('public_template_race_second', 'commit');
select is(
  (
    select result
    from public_template_race_results
    where label = 'account-delete-copy'
  ),
  'P0002',
  'source-account deletion wins over copy without leaking availability'
);

-- Two distinct requests race for the final destination quota slot. The owner
-- advisory lock admits one whole copy and rejects the other without overflow.
select extensions.dblink_exec('public_template_race_first', 'begin');
select extensions.dblink_exec(
  'public_template_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000004'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_first',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000001',
        1,
        'e6000000-0000-4000-8000-000000000008'
      )
    $remote$
  ),
  1,
  'first final-slot copy starts asynchronously'
);
select pg_catalog.pg_sleep(0.1);

select extensions.dblink_exec('public_template_race_second', 'begin');
select extensions.dblink_exec(
  'public_template_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'public_template_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'e1000000-0000-4000-8000-000000000004'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'public_template_race_second',
    $remote$
      select pg_temp.attempt_copy(
        'e2000000-0000-4000-8000-000000000001',
        1,
        'e6000000-0000-4000-8000-000000000009'
      )
    $remote$
  ),
  1,
  'second final-slot copy races with the uncommitted first copy'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('public_template_race_second') = 1,
  'second final-slot copy waits on the destination quota lock'
);
insert into public_template_race_results
select 'quota-first', result
from extensions.dblink_get_result('public_template_race_first')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_first')
  as drained(status text);
select extensions.dblink_exec('public_template_race_first', 'commit');
insert into public_template_race_results
select 'quota-second', result
from extensions.dblink_get_result('public_template_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('public_template_race_second')
  as drained(status text);
select extensions.dblink_exec('public_template_race_second', 'commit');

select is(
  (
    select pg_catalog.count(*)
    from public_template_race_results
    where label like 'quota-%'
      and result like 'ok:%'
  ),
  1::bigint,
  'exactly one concurrent final-slot copy succeeds'
);
select is(
  (
    select pg_catalog.count(*)
    from public_template_race_results
    where label like 'quota-%'
      and result = '54000'
  ),
  1::bigint,
  'the other concurrent final-slot copy is rejected at quota'
);
select is(
  (
    select pg_catalog.count(*)
    from public.templates
    where owner_id = 'e1000000-0000-4000-8000-000000000004'
  ),
  100::bigint,
  'concurrent quota requests cannot create more than 100 templates'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_copy_requests
    where owner_id = 'e1000000-0000-4000-8000-000000000004'
      and request_id in (
        'e6000000-0000-4000-8000-000000000008',
        'e6000000-0000-4000-8000-000000000009'
      )
  ),
  1::bigint,
  'quota race commits exactly one retry-ledger row'
);

select is(
  (
    select pg_catalog.count(*)
    from private.public_template_copy_requests
    where owner_id = 'e1000000-0000-4000-8000-000000000002'
      and request_id in (
        'e6000000-0000-4000-8000-000000000002',
        'e6000000-0000-4000-8000-000000000003',
        'e6000000-0000-4000-8000-000000000004',
        'e6000000-0000-4000-8000-000000000005',
        'e6000000-0000-4000-8000-000000000006',
        'e6000000-0000-4000-8000-000000000007'
      )
  ),
  0::bigint,
  'all losing edit, publication, deletion, block, and lifecycle races leave no ledger rows'
);
select is(
  (
    select pg_catalog.count(*)
    from public.templates
    where owner_id = 'e1000000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'all rejected races leave the copier with only the original successful copy'
);

select extensions.dblink_exec(
  'public_template_race_setup',
  $remote$
    delete from auth.users
    where id in (
      'e1000000-0000-4000-8000-000000000001',
      'e1000000-0000-4000-8000-000000000002',
      'e1000000-0000-4000-8000-000000000003',
      'e1000000-0000-4000-8000-000000000004'
    );

    delete from private.deleted_username_reservations
    where canonical_username in (
      'publicracesource',
      'publicracecopier',
      'publicracesourcegone',
      'publicracequota'
    );

    delete from realtime.messages
    where topic like 'account:e1000000-0000-4000-8000-%';
  $remote$
);

select ok(
  not exists (
    select 1
    from auth.users
    where id::text like 'e1000000-0000-4000-8000-%'
  )
  and not exists (
    select 1
    from public.templates
    where owner_id::text like 'e1000000-0000-4000-8000-%'
  )
  and not exists (
    select 1
    from private.public_template_copy_requests
    where owner_id::text like 'e1000000-0000-4000-8000-%'
  ),
  'real-session public-template race fixtures are cleaned up'
);

select extensions.dblink_disconnect('public_template_race_first');
select extensions.dblink_disconnect('public_template_race_second');
select extensions.dblink_disconnect('public_template_race_setup');

select * from finish();
rollback;
