begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select no_plan();

select extensions.dblink_connect(
  'note_race_setup',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=note_race_setup'
);
select extensions.dblink_connect(
  'note_race_hold',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=note_race_hold'
);
select extensions.dblink_connect(
  'note_race_first',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=note_race_first'
);
select extensions.dblink_connect(
  'note_race_second',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=note_race_second'
);

select extensions.dblink_exec(
  'note_race_setup',
  $remote$
    delete from public.active_lists
    where id::text like 'c2000000-0000-4000-8000-%';
    delete from auth.users
    where id in (
      'c1000000-0000-4000-8000-000000000001',
      'c1000000-0000-4000-8000-000000000002',
      'c1000000-0000-4000-8000-000000000003',
      'c1000000-0000-4000-8000-000000000004',
      'c1000000-0000-4000-8000-000000000005',
      'c1000000-0000-4000-8000-000000000006',
      'c1000000-0000-4000-8000-000000000007',
      'c1000000-0000-4000-8000-000000000008',
      'c1000000-0000-4000-8000-000000000009',
      'c1000000-0000-4000-8000-00000000000a',
      'c1000000-0000-4000-8000-00000000000b'
    )
  $remote$
);
select extensions.dblink_exec(
  'note_race_setup',
  $remote$
    delete from private.deleted_username_reservations
    where canonical_username in (
      'noteraceowner',
      'noteracemember',
      'noteracesecond',
      'raceblockone',
      'raceblocktwo',
      'racedeleteone',
      'racedeletetwo',
      'raceexpense',
      'racemulti',
      'raceusername',
      'raceretry'
    )
  $remote$
);
select extensions.dblink_exec(
  'note_race_setup',
  $remote$
    insert into auth.users (
      id,
      email,
      email_confirmed_at,
      created_at,
      updated_at
    )
    values
      (
        'c1000000-0000-4000-8000-000000000001',
        'note-race-owner@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-000000000002',
        'note-race-member@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-000000000003',
        'note-race-second@example.test',
        now(),
        now(),
        now()
      );

    update public.profiles
    set username = case id
          when 'c1000000-0000-4000-8000-000000000001'
            then 'noteraceowner'
          when 'c1000000-0000-4000-8000-000000000002'
            then 'noteracemember'
          else 'noteracesecond'
        end,
        display_name = 'Note race'
    where id in (
      'c1000000-0000-4000-8000-000000000001',
      'c1000000-0000-4000-8000-000000000002',
      'c1000000-0000-4000-8000-000000000003'
    );

    insert into public.active_lists (
      id,
      owner_id,
      title,
      creation_request_id
    )
    values
      (
        'c2000000-0000-4000-8000-000000000001',
        'c1000000-0000-4000-8000-000000000001',
        'Two note writers',
        'c3000000-0000-4000-8000-000000000001'
      ),
      (
        'c2000000-0000-4000-8000-000000000002',
        'c1000000-0000-4000-8000-000000000001',
        'Note then remove',
        'c3000000-0000-4000-8000-000000000002'
      ),
      (
        'c2000000-0000-4000-8000-000000000003',
        'c1000000-0000-4000-8000-000000000001',
        'Remove then note',
        'c3000000-0000-4000-8000-000000000003'
      );

    insert into public.active_list_participants (
      list_id,
      participant_profile_id,
      state
    )
    values
      (
        'c2000000-0000-4000-8000-000000000002',
        'c1000000-0000-4000-8000-000000000002',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-000000000003',
        'c1000000-0000-4000-8000-000000000003',
        'member'
      );
  $remote$
);

-- Seed the identities needed by the profile-first races before the baseline
-- list races. The later extended fixture block fills the remaining deletion
-- cases and uses conflict-safe inserts for these already exercised rows.
select extensions.dblink_exec(
  'note_race_setup',
  $remote$
    insert into auth.users (
      id,
      email,
      email_confirmed_at,
      created_at,
      updated_at
    )
    values
      (
        'c1000000-0000-4000-8000-000000000004',
        'note-race-block-one@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-000000000005',
        'note-race-block-two@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-00000000000a',
        'note-race-username@example.test',
        now(),
        now(),
        now()
      )
    on conflict (id) do nothing;

    update public.profiles
    set username = case id
          when 'c1000000-0000-4000-8000-000000000004'
            then 'raceblockone'
          when 'c1000000-0000-4000-8000-000000000005'
            then 'raceblocktwo'
          else 'raceusername'
        end,
        display_name = 'Extended note race'
    where id in (
      'c1000000-0000-4000-8000-000000000004',
      'c1000000-0000-4000-8000-000000000005',
      'c1000000-0000-4000-8000-00000000000a'
    );

    insert into public.active_lists (
      id,
      owner_id,
      title,
      creation_request_id
    )
    values
      (
        'c2000000-0000-4000-8000-000000000004',
        'c1000000-0000-4000-8000-000000000001',
        'Note then block',
        'c3000000-0000-4000-8000-000000000004'
      ),
      (
        'c2000000-0000-4000-8000-000000000005',
        'c1000000-0000-4000-8000-000000000001',
        'Block then note',
        'c3000000-0000-4000-8000-000000000005'
      ),
      (
        'c2000000-0000-4000-8000-000000000009',
        'c1000000-0000-4000-8000-000000000001',
        'Note versus username',
        'c3000000-0000-4000-8000-000000000009'
      )
    on conflict (id) do nothing;

    insert into public.active_list_participants (
      list_id,
      participant_profile_id,
      state
    )
    values
      (
        'c2000000-0000-4000-8000-000000000004',
        'c1000000-0000-4000-8000-000000000004',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-000000000005',
        'c1000000-0000-4000-8000-000000000005',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-000000000009',
        'c1000000-0000-4000-8000-00000000000a',
        'member'
      )
    on conflict (list_id, participant_profile_id) do nothing;
  $remote$
);

select extensions.dblink_exec(
  'note_race_first',
  $remote$
    create or replace function pg_temp.attempt_note(
      target_list_id uuid,
      target_text text,
      target_ids uuid[],
      expected_version bigint
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform public.update_active_list_general_note(
        target_list_id,
        target_text,
        target_ids,
        expected_version
      );
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$
  $remote$
);
select extensions.dblink_exec(
  'note_race_second',
  $remote$
    create or replace function pg_temp.attempt_block(
      target_profile_id uuid
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform public.block_profile(target_profile_id);
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_username(
      target_profile_id uuid,
      target_username text
    )
    returns text
    language plpgsql
    as $function$
    begin
      update public.profiles
      set username = target_username
      where id = target_profile_id;
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

create temporary table note_race_results (
  label text primary key,
  result text
) on commit drop;

-- Note owns both profile locks before it waits on the list. A simultaneous
-- block therefore waits on the profile phase, rather than taking child locks
-- or forming a profile/list cycle.
truncate note_race_results;
select extensions.dblink_exec('note_race_hold', 'begin');
select extensions.dblink_exec(
  'note_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'c2000000-0000-4000-8000-000000000004'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local statement_timeout = ''10s'''
);
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'note_race_first',
    $remote$
      select pg_temp.attempt_note(
        'c2000000-0000-4000-8000-000000000004',
        'Block after @raceblockone',
        array['c1000000-0000-4000-8000-000000000004'::uuid],
        1
      )
    $remote$
  ),
  1,
  'note-before-block mutation starts asynchronously'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'note_race_first'
      and wait_event_type = 'Lock'
  ),
  'note-before-block proves it owns profile locks and waits on the parent list'
);

select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local statement_timeout = ''10s'''
);
select extensions.dblink_exec(
  'note_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'note_race_second',
    $remote$
      select pg_temp.attempt_block(
        'c1000000-0000-4000-8000-000000000004'
      )
    $remote$
  ),
  1,
  'block queues behind the note profile phase'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and extensions.dblink_is_busy('note_race_second') = 1
  and (
    select pg_catalog.count(*) = 2
    from pg_catalog.pg_stat_activity
    where application_name in ('note_race_first', 'note_race_second')
      and wait_event_type = 'Lock'
  ),
  'note-before-block proves both sessions are bounded on ordered locks'
);

select extensions.dblink_exec('note_race_hold', 'commit');
insert into note_race_results
select 'note-first', result
from extensions.dblink_get_result('note_race_first')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_first')
      as drained(status text)
  ),
  0::bigint,
  'note-before-block result queue is fully drained'
);
select extensions.dblink_exec('note_race_first', 'commit');
insert into note_race_results
select 'block-second', result
from extensions.dblink_get_result('note_race_second')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'block-after-note result queue is fully drained'
);
select extensions.dblink_exec('note_race_second', 'commit');
select is(
  (
    select pg_catalog.array_agg(result order by label)
    from note_race_results
  ),
  array['ok', 'ok']::text[],
  'note-before-block serializes both operations without a deadlock'
);
select ok(
  (
    select version = 3
      and general_note_version = 3
      and general_note_text = 'Block after @raceblockone'
    from public.active_lists
    where id = 'c2000000-0000-4000-8000-000000000004'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'c2000000-0000-4000-8000-000000000004'
  )
  and (
    select state = 'removed'
    from public.active_list_participants
    where list_id = 'c2000000-0000-4000-8000-000000000004'
      and participant_profile_id =
        'c1000000-0000-4000-8000-000000000004'
  ),
  'block-after-note preserves literal text, removes resolution, and bumps the parent once per operation'
);

-- Reverse acquisition order: the completed block transaction retains its
-- profile/list locks while the note preflights the still-visible membership.
-- Once the block commits, the queued note must revalidate and reject atomically.
truncate note_race_results;
select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local statement_timeout = ''10s'''
);
select extensions.dblink_exec(
  'note_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'note_race_second',
    $remote$
      select pg_temp.attempt_block(
        'c1000000-0000-4000-8000-000000000005'
      )
    $remote$
  ),
  1,
  'block-before-note starts asynchronously'
);
insert into note_race_results
select 'block-first', result
from extensions.dblink_get_result('note_race_second')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'block-before-note result queue is fully drained while locks remain held'
);

select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local statement_timeout = ''10s'''
);
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'note_race_first',
    $remote$
      select pg_temp.attempt_note(
        'c2000000-0000-4000-8000-000000000005',
        'Forbidden @raceblocktwo',
        array['c1000000-0000-4000-8000-000000000005'::uuid],
        1
      )
    $remote$
  ),
  1,
  'note queues behind the uncommitted block'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'note_race_first'
      and wait_event_type = 'Lock'
  ),
  'block-before-note proves the note waits on the ordered profile phase'
);
select extensions.dblink_exec('note_race_second', 'commit');
insert into note_race_results
select 'note-second', result
from extensions.dblink_get_result('note_race_first')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_first')
      as drained(status text)
  ),
  0::bigint,
  'note-after-block result queue is fully drained'
);
select extensions.dblink_exec('note_race_first', 'commit');
select is(
  (
    select pg_catalog.array_agg(result order by label)
    from note_race_results
  ),
  array['ok', '22023']::text[],
  'block-before-note succeeds and authoritative mention validation rejects the queued note'
);
select ok(
  (
    select version = 2
      and general_note_version = 1
      and general_note_text is null
    from public.active_lists
    where id = 'c2000000-0000-4000-8000-000000000005'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'c2000000-0000-4000-8000-000000000005'
  )
  and (
    select state = 'removed'
    from public.active_list_participants
    where list_id = 'c2000000-0000-4000-8000-000000000005'
      and participant_profile_id =
        'c1000000-0000-4000-8000-000000000005'
  ),
  'block-before-note leaves no partial note, link, notification, or version mutation'
);

-- A note locks the completed mention target before the parent list. The target
-- profile's forbidden username change therefore waits on that profile row,
-- then raises the established 22023 after the note commits.
truncate note_race_results;
select extensions.dblink_exec('note_race_hold', 'begin');
select extensions.dblink_exec(
  'note_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'c2000000-0000-4000-8000-000000000009'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local statement_timeout = ''10s'''
);
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select extensions.dblink_send_query(
  'note_race_first',
  $remote$
    select pg_temp.attempt_note(
      'c2000000-0000-4000-8000-000000000009',
      'Immutable @raceusername',
      array['c1000000-0000-4000-8000-00000000000a'::uuid],
      1
    )
  $remote$
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'note_race_first'
      and wait_event_type = 'Lock'
  ),
  'note-versus-username proves the note prelocked the target before waiting on the list'
);

select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local statement_timeout = ''10s'''
);
select extensions.dblink_exec(
  'note_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-00000000000a'
  $remote$
);
select extensions.dblink_send_query(
  'note_race_second',
  $remote$
    select pg_temp.attempt_username(
      'c1000000-0000-4000-8000-00000000000a',
      'changedusername'
    )
  $remote$
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and extensions.dblink_is_busy('note_race_second') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'note_race_second'
      and wait_event_type = 'Lock'
  ),
  'forbidden username write waits on the note-owned profile without a cycle'
);
select extensions.dblink_exec('note_race_hold', 'commit');
insert into note_race_results
select 'note', result
from extensions.dblink_get_result('note_race_first')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_first')
      as drained(status text)
  ),
  0::bigint,
  'note-versus-username note result queue is fully drained'
);
select extensions.dblink_exec('note_race_first', 'commit');
insert into note_race_results
select 'username', result
from extensions.dblink_get_result('note_race_second')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'note-versus-username profile result queue is fully drained'
);
select extensions.dblink_exec('note_race_second', 'commit');
select is(
  (
    select pg_catalog.array_agg(result order by label)
    from note_race_results
  ),
  array['ok', '22023']::text[],
  'note succeeds and the completed username change retains the established 22023'
);
select ok(
  (
    select username = 'raceusername'
    from public.profiles
    where id = 'c1000000-0000-4000-8000-00000000000a'
  )
  and (
    select version = 2
      and general_note_version = 2
      and general_note_text = 'Immutable @raceusername'
    from public.active_lists
    where id = 'c2000000-0000-4000-8000-000000000009'
  )
  and exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'c2000000-0000-4000-8000-000000000009'
      and mentioned_profile_id =
        'c1000000-0000-4000-8000-00000000000a'
  ),
  'forbidden username race leaves the stable-ID mention and canonical username intact'
);

select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-00000000000a'
  $remote$
);
select is(
  (
    select result
    from extensions.dblink(
      'note_race_second',
      $remote$
        select pg_temp.attempt_username(
          'c1000000-0000-4000-8000-00000000000a',
          '  RACEUSERNAME  '
        )
      $remote$
    ) as retry_result(result text)
  ),
  'ok',
  'same-canonical completed username retry remains accepted'
);
select extensions.dblink_exec('note_race_second', 'commit');

select extensions.dblink_exec(
  'note_race_first',
  $remote$
    create or replace function pg_temp.attempt_note(
      target_list_id uuid,
      target_text text,
      target_ids uuid[],
      expected_version bigint
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform public.update_active_list_general_note(
        target_list_id,
        target_text,
        target_ids,
        expected_version
      );
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$
  $remote$
);
select extensions.dblink_exec(
  'note_race_second',
  $remote$
    create or replace function pg_temp.attempt_note(
      target_list_id uuid,
      target_text text,
      target_ids uuid[],
      expected_version bigint
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform public.update_active_list_general_note(
        target_list_id,
        target_text,
        target_ids,
        expected_version
      );
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_remove(
      target_list_id uuid,
      target_profile_id uuid,
      expected_version bigint
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform public.remove_active_list_member(
        target_list_id,
        target_profile_id,
        expected_version
      );
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$
  $remote$
);

select extensions.dblink_exec(
  'note_race_first',
  $remote$
    create or replace function pg_temp.attempt_expense(
      target_list_id uuid,
      target_payer_id uuid,
      target_beneficiary_ids uuid[],
      target_request_id uuid,
      expected_version bigint
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform public.create_active_list_expense_v2(
        target_list_id,
        'Concurrent expense',
        1200,
        target_payer_id,
        target_beneficiary_ids,
        null::bigint[],
        target_request_id,
        expected_version
      );
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$
  $remote$
);

select extensions.dblink_exec(
  'note_race_second',
  $remote$
    create or replace function pg_temp.attempt_block(
      target_profile_id uuid
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform public.block_profile(target_profile_id);
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_username(
      target_profile_id uuid,
      target_username text
    )
    returns text
    language plpgsql
    as $function$
    begin
      update public.profiles
      set username = target_username
      where id = target_profile_id;
      if not found then
        return 'missing';
      end if;
      return 'ok';
    exception
      when others then
        return sqlstate;
    end;
    $function$;

    create or replace function pg_temp.attempt_auth_delete(
      target_profile_id uuid
    )
    returns text
    language plpgsql
    as $function$
    begin
      delete from auth.users
      where id = target_profile_id;
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

-- Both same-version writers reach the same held parent lock. Releasing it
-- deterministically permits one write and forces the other through 40001.
select extensions.dblink_exec('note_race_hold', 'begin');
select extensions.dblink_exec(
  'note_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'c2000000-0000-4000-8000-000000000001'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'note_race_first',
    $remote$
      select pg_temp.attempt_note(
        'c2000000-0000-4000-8000-000000000001',
        'First writer',
        '{}'::uuid[],
        1
      )
    $remote$
  ),
  1,
  'first same-version note writer starts asynchronously'
);
select pg_catalog.pg_sleep(0.1);
select is(
  extensions.dblink_send_query(
    'note_race_second',
    $remote$
      select pg_temp.attempt_note(
        'c2000000-0000-4000-8000-000000000001',
        'Second writer',
        '{}'::uuid[],
        1
      )
    $remote$
  ),
  1,
  'second same-version note writer starts asynchronously'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and extensions.dblink_is_busy('note_race_second') = 1
  and (
    select pg_catalog.count(*) = 2
    from pg_catalog.pg_stat_activity
    where application_name in ('note_race_first', 'note_race_second')
      and wait_event_type = 'Lock'
  ),
  'both note writers prove they reached the shared parent lock'
);
select extensions.dblink_exec('note_race_hold', 'commit');

truncate note_race_results;
insert into note_race_results
select 'first', result
from extensions.dblink_get_result('note_race_first')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_first')
      as drained(status text)
  ),
  0::bigint,
  'first same-version writer result queue is fully drained'
);
select extensions.dblink_exec('note_race_first', 'commit');
insert into note_race_results
select 'second', result
from extensions.dblink_get_result('note_race_second')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'second same-version writer result queue is fully drained'
);
select extensions.dblink_exec('note_race_second', 'commit');
select is(
  (
    select pg_catalog.array_agg(result order by result)
    from note_race_results
  ),
  array['40001', 'ok']::text[],
  'exactly one same-version note writer succeeds and one returns 40001'
);
select ok(
  (
    select version = 2
      and general_note_version = 2
      and general_note_text in ('First writer', 'Second writer')
    from public.active_lists
    where id = 'c2000000-0000-4000-8000-000000000001'
  ),
  'simultaneous writes produce one complete scalar mutation and one parent bump'
);

-- Note queues first, then removal. Both serialize successfully; cleanup
-- preserves the literal text while removing the newly committed link.
truncate note_race_results;
select extensions.dblink_exec('note_race_hold', 'begin');
select extensions.dblink_exec(
  'note_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'c2000000-0000-4000-8000-000000000002'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select extensions.dblink_send_query(
  'note_race_first',
  $remote$
    select pg_temp.attempt_note(
      'c2000000-0000-4000-8000-000000000002',
      'Keep @noteracemember',
      array['c1000000-0000-4000-8000-000000000002'::uuid],
      1
    )
  $remote$
);
select pg_catalog.pg_sleep(0.1);
select extensions.dblink_send_query(
  'note_race_second',
  $remote$
    select pg_temp.attempt_remove(
      'c2000000-0000-4000-8000-000000000002',
      'c1000000-0000-4000-8000-000000000002',
      1
    )
  $remote$
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and extensions.dblink_is_busy('note_race_second') = 1,
  'note-first and removal both wait behind the held parent without a cycle'
);
select extensions.dblink_exec('note_race_hold', 'commit');
insert into note_race_results
select 'note-first', result
from extensions.dblink_get_result('note_race_first')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_first')
      as drained(status text)
  ),
  0::bigint,
  'note-first result queue is fully drained'
);
select extensions.dblink_exec('note_race_first', 'commit');
insert into note_race_results
select 'remove-second', result
from extensions.dblink_get_result('note_race_second')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'remove-second result queue is fully drained'
);
select extensions.dblink_exec('note_race_second', 'commit');
select is(
  (
    select pg_catalog.array_agg(result order by label)
    from note_race_results
  ),
  array['ok', 'ok']::text[],
  'note-first and subsequent removal both complete'
);
select ok(
  (
    select version = 3
      and general_note_version = 3
      and general_note_text = 'Keep @noteracemember'
    from public.active_lists
    where id = 'c2000000-0000-4000-8000-000000000002'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'c2000000-0000-4000-8000-000000000002'
  )
  and (
    select state = 'removed'
    from public.active_list_participants
    where list_id = 'c2000000-0000-4000-8000-000000000002'
      and participant_profile_id =
        'c1000000-0000-4000-8000-000000000002'
  ),
  'note-first race preserves text, removes resolution, and applies one bump per serialized operation'
);

-- Removal queues first. The later note preflights while access still exists,
-- then revalidates after the lock and rejects atomically.
truncate note_race_results;
select extensions.dblink_exec('note_race_hold', 'begin');
select extensions.dblink_exec(
  'note_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'c2000000-0000-4000-8000-000000000003'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select extensions.dblink_send_query(
  'note_race_second',
  $remote$
    select pg_temp.attempt_remove(
      'c2000000-0000-4000-8000-000000000003',
      'c1000000-0000-4000-8000-000000000003',
      1
    )
  $remote$
);
select pg_catalog.pg_sleep(0.1);
select extensions.dblink_send_query(
  'note_race_first',
  $remote$
    select pg_temp.attempt_note(
      'c2000000-0000-4000-8000-000000000003',
      'Late @noteracesecond',
      array['c1000000-0000-4000-8000-000000000003'::uuid],
      1
    )
  $remote$
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and extensions.dblink_is_busy('note_race_second') = 1,
  'removal-first and note both prove bounded parent-lock waits'
);
select extensions.dblink_exec('note_race_hold', 'commit');
insert into note_race_results
select 'remove-first', result
from extensions.dblink_get_result('note_race_second')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'remove-first result queue is fully drained'
);
select extensions.dblink_exec('note_race_second', 'commit');
insert into note_race_results
select 'note-second', result
from extensions.dblink_get_result('note_race_first')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_first')
      as drained(status text)
  ),
  0::bigint,
  'note-second result queue is fully drained'
);
select extensions.dblink_exec('note_race_first', 'commit');
select is(
  (
    select pg_catalog.array_agg(result order by label)
    from note_race_results
  ),
  array['22023', 'ok']::text[],
  'removal-first succeeds and queued stale mention revalidation rejects'
);
select ok(
  (
    select version = 2
      and general_note_version = 1
      and general_note_text is null
    from public.active_lists
    where id = 'c2000000-0000-4000-8000-000000000003'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'c2000000-0000-4000-8000-000000000003'
  )
  and (
    select state = 'removed'
    from public.active_list_participants
    where list_id = 'c2000000-0000-4000-8000-000000000003'
      and participant_profile_id =
        'c1000000-0000-4000-8000-000000000003'
  ),
  'removal-first race applies only the one membership parent bump and no partial note state'
);

-- Additional autonomous fixtures exercise block, immutable-username,
-- account-deletion, expense-deletion, exact-retry, and reverse-order cleanup.
select extensions.dblink_exec(
  'note_race_setup',
  $remote$
    insert into auth.users (
      id,
      email,
      email_confirmed_at,
      created_at,
      updated_at
    )
    values
      (
        'c1000000-0000-4000-8000-000000000004',
        'note-race-block-one@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-000000000005',
        'note-race-block-two@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-000000000006',
        'note-race-delete-one@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-000000000007',
        'note-race-delete-two@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-000000000008',
        'note-race-expense@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-000000000009',
        'note-race-multi@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-00000000000a',
        'note-race-username@example.test',
        now(),
        now(),
        now()
      ),
      (
        'c1000000-0000-4000-8000-00000000000b',
        'note-race-retry@example.test',
        now(),
        now(),
        now()
      )
    on conflict (id) do nothing;

    update public.profiles
    set username = case id
          when 'c1000000-0000-4000-8000-000000000004'
            then 'raceblockone'
          when 'c1000000-0000-4000-8000-000000000005'
            then 'raceblocktwo'
          when 'c1000000-0000-4000-8000-000000000006'
            then 'racedeleteone'
          when 'c1000000-0000-4000-8000-000000000007'
            then 'racedeletetwo'
          when 'c1000000-0000-4000-8000-000000000008'
            then 'raceexpense'
          when 'c1000000-0000-4000-8000-000000000009'
            then 'racemulti'
          when 'c1000000-0000-4000-8000-00000000000a'
            then 'raceusername'
          else 'raceretry'
        end,
        display_name = 'Extended note race'
    where id in (
      'c1000000-0000-4000-8000-000000000004',
      'c1000000-0000-4000-8000-000000000005',
      'c1000000-0000-4000-8000-000000000006',
      'c1000000-0000-4000-8000-000000000007',
      'c1000000-0000-4000-8000-000000000008',
      'c1000000-0000-4000-8000-000000000009',
      'c1000000-0000-4000-8000-00000000000a',
      'c1000000-0000-4000-8000-00000000000b'
    );

    insert into public.active_lists (
      id,
      owner_id,
      title,
      creation_request_id
    )
    values
      (
        'c2000000-0000-4000-8000-000000000004',
        'c1000000-0000-4000-8000-000000000001',
        'Note then block',
        'c3000000-0000-4000-8000-000000000004'
      ),
      (
        'c2000000-0000-4000-8000-000000000005',
        'c1000000-0000-4000-8000-000000000001',
        'Block then note',
        'c3000000-0000-4000-8000-000000000005'
      ),
      (
        'c2000000-0000-4000-8000-000000000006',
        'c1000000-0000-4000-8000-000000000001',
        'Note then account delete',
        'c3000000-0000-4000-8000-000000000006'
      ),
      (
        'c2000000-0000-4000-8000-000000000007',
        'c1000000-0000-4000-8000-000000000001',
        'Account delete then note',
        'c3000000-0000-4000-8000-000000000007'
      ),
      (
        'c2000000-0000-4000-8000-000000000008',
        'c1000000-0000-4000-8000-000000000001',
        'Expense then account delete',
        'c3000000-0000-4000-8000-000000000008'
      ),
      (
        'c2000000-0000-4000-8000-000000000009',
        'c1000000-0000-4000-8000-000000000001',
        'Note versus username',
        'c3000000-0000-4000-8000-000000000009'
      ),
      (
        'c2000000-0000-4000-8000-00000000000a',
        'c1000000-0000-4000-8000-000000000001',
        'Exact completed retry',
        'c3000000-0000-4000-8000-00000000000a'
      )
    on conflict (id) do nothing;

    insert into public.active_list_participants (
      list_id,
      participant_profile_id,
      state
    )
    values
      (
        'c2000000-0000-4000-8000-000000000004',
        'c1000000-0000-4000-8000-000000000004',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-000000000005',
        'c1000000-0000-4000-8000-000000000005',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-000000000006',
        'c1000000-0000-4000-8000-000000000006',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-000000000007',
        'c1000000-0000-4000-8000-000000000007',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-000000000008',
        'c1000000-0000-4000-8000-000000000008',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-000000000009',
        'c1000000-0000-4000-8000-00000000000a',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-00000000000a',
        'c1000000-0000-4000-8000-00000000000b',
        'member'
      )
    on conflict (list_id, participant_profile_id) do nothing;

    update public.active_lists
    set general_note_text = case id
          when 'c2000000-0000-4000-8000-000000000006'
            then 'Initial @racedeleteone'
          else 'Initial @racedeletetwo'
        end,
        general_note_version = 2,
        general_note_updated_at = pg_catalog.clock_timestamp(),
        version = 2,
        updated_at = pg_catalog.clock_timestamp()
    where id in (
      'c2000000-0000-4000-8000-000000000006',
      'c2000000-0000-4000-8000-000000000007'
    );

    insert into public.active_list_note_mentions (
      list_id,
      mentioned_profile_id
    )
    values
      (
        'c2000000-0000-4000-8000-000000000006',
        'c1000000-0000-4000-8000-000000000006'
      ),
      (
        'c2000000-0000-4000-8000-000000000007',
        'c1000000-0000-4000-8000-000000000007'
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
    values
      (
        'c4000000-0000-4000-8000-000000000006',
        'c2000000-0000-4000-8000-000000000006',
        'Delete race one',
        1,
        'c5000000-0000-4000-8000-000000000006',
        now(),
        'c1000000-0000-4000-8000-000000000006'
      ),
      (
        'c4000000-0000-4000-8000-000000000007',
        'c2000000-0000-4000-8000-000000000007',
        'Delete race two',
        1,
        'c5000000-0000-4000-8000-000000000007',
        now(),
        'c1000000-0000-4000-8000-000000000007'
      );

    insert into public.active_list_item_assignments (
      list_id,
      item_id,
      assignee_profile_id
    )
    values
      (
        'c2000000-0000-4000-8000-000000000006',
        'c4000000-0000-4000-8000-000000000006',
        'c1000000-0000-4000-8000-000000000006'
      ),
      (
        'c2000000-0000-4000-8000-000000000007',
        'c4000000-0000-4000-8000-000000000007',
        'c1000000-0000-4000-8000-000000000007'
      );

    insert into public.active_list_split_settings (
      list_id,
      currency_code
    )
    values
      ('c2000000-0000-4000-8000-000000000006', 'CHF'),
      ('c2000000-0000-4000-8000-000000000007', 'CHF'),
      ('c2000000-0000-4000-8000-000000000008', 'CHF');

    insert into public.active_list_split_participants (
      id,
      list_id,
      profile_id,
      username_snapshot,
      display_name_snapshot
    )
    values
      (
        'c6000000-0000-4000-8000-000000000061',
        'c2000000-0000-4000-8000-000000000006',
        'c1000000-0000-4000-8000-000000000001',
        'noteraceowner',
        'Note race'
      ),
      (
        'c6000000-0000-4000-8000-000000000062',
        'c2000000-0000-4000-8000-000000000006',
        'c1000000-0000-4000-8000-000000000006',
        'racedeleteone',
        'Extended note race'
      ),
      (
        'c6000000-0000-4000-8000-000000000071',
        'c2000000-0000-4000-8000-000000000007',
        'c1000000-0000-4000-8000-000000000001',
        'noteraceowner',
        'Note race'
      ),
      (
        'c6000000-0000-4000-8000-000000000072',
        'c2000000-0000-4000-8000-000000000007',
        'c1000000-0000-4000-8000-000000000007',
        'racedeletetwo',
        'Extended note race'
      ),
      (
        'c6000000-0000-4000-8000-000000000081',
        'c2000000-0000-4000-8000-000000000008',
        'c1000000-0000-4000-8000-000000000001',
        'noteraceowner',
        'Note race'
      ),
      (
        'c6000000-0000-4000-8000-000000000082',
        'c2000000-0000-4000-8000-000000000008',
        'c1000000-0000-4000-8000-000000000008',
        'raceexpense',
        'Extended note race'
      );

    insert into public.active_list_expenses (
      id,
      list_id,
      description,
      amount_minor,
      payer_participant_id,
      creator_participant_id,
      last_editor_participant_id,
      creation_request_id
    )
    values
      (
        'c7000000-0000-4000-8000-000000000061',
        'c2000000-0000-4000-8000-000000000006',
        'Preserved history one',
        1000,
        'c6000000-0000-4000-8000-000000000062',
        'c6000000-0000-4000-8000-000000000061',
        'c6000000-0000-4000-8000-000000000061',
        'c8000000-0000-4000-8000-000000000061'
      ),
      (
        'c7000000-0000-4000-8000-000000000071',
        'c2000000-0000-4000-8000-000000000007',
        'Preserved history two',
        1000,
        'c6000000-0000-4000-8000-000000000072',
        'c6000000-0000-4000-8000-000000000071',
        'c6000000-0000-4000-8000-000000000071',
        'c8000000-0000-4000-8000-000000000071'
      );

    insert into public.active_list_expense_shares (
      list_id,
      expense_id,
      participant_id,
      amount_minor
    )
    values
      (
        'c2000000-0000-4000-8000-000000000006',
        'c7000000-0000-4000-8000-000000000061',
        'c6000000-0000-4000-8000-000000000062',
        1000
      ),
      (
        'c2000000-0000-4000-8000-000000000007',
        'c7000000-0000-4000-8000-000000000071',
        'c6000000-0000-4000-8000-000000000072',
        1000
      );

    -- Insert the multi-list fixtures in descending UUID order. The deletion
    -- coordinator must still acquire their parent and child locks ascending.
    insert into public.active_lists (
      id,
      owner_id,
      title,
      creation_request_id,
      general_note_text,
      general_note_version,
      general_note_updated_at,
      version,
      updated_at
    )
    values
      (
        'c2000000-0000-4000-8000-00000000000d',
        'c1000000-0000-4000-8000-000000000001',
        'Reverse cleanup high',
        'c3000000-0000-4000-8000-00000000000d',
        'Keep literal @racemulti high',
        2,
        pg_catalog.clock_timestamp(),
        2,
        pg_catalog.clock_timestamp()
      ),
      (
        'c2000000-0000-4000-8000-00000000000b',
        'c1000000-0000-4000-8000-000000000001',
        'Reverse cleanup low',
        'c3000000-0000-4000-8000-00000000000b',
        'Keep literal @racemulti low',
        2,
        pg_catalog.clock_timestamp(),
        2,
        pg_catalog.clock_timestamp()
      );

    insert into public.active_list_participants (
      list_id,
      participant_profile_id,
      state
    )
    values
      (
        'c2000000-0000-4000-8000-00000000000d',
        'c1000000-0000-4000-8000-000000000009',
        'member'
      ),
      (
        'c2000000-0000-4000-8000-00000000000b',
        'c1000000-0000-4000-8000-000000000009',
        'member'
      );

    insert into public.active_list_note_mentions (
      list_id,
      mentioned_profile_id
    )
    values
      (
        'c2000000-0000-4000-8000-00000000000d',
        'c1000000-0000-4000-8000-000000000009'
      ),
      (
        'c2000000-0000-4000-8000-00000000000b',
        'c1000000-0000-4000-8000-000000000009'
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
    values
      (
        'c4000000-0000-4000-8000-00000000000d',
        'c2000000-0000-4000-8000-00000000000d',
        'Reverse high',
        1,
        'c5000000-0000-4000-8000-00000000000d',
        now(),
        'c1000000-0000-4000-8000-000000000009'
      ),
      (
        'c4000000-0000-4000-8000-00000000000b',
        'c2000000-0000-4000-8000-00000000000b',
        'Reverse low',
        1,
        'c5000000-0000-4000-8000-00000000000b',
        now(),
        'c1000000-0000-4000-8000-000000000009'
      );

    insert into public.active_list_item_assignments (
      list_id,
      item_id,
      assignee_profile_id
    )
    values
      (
        'c2000000-0000-4000-8000-00000000000d',
        'c4000000-0000-4000-8000-00000000000d',
        'c1000000-0000-4000-8000-000000000009'
      ),
      (
        'c2000000-0000-4000-8000-00000000000b',
        'c4000000-0000-4000-8000-00000000000b',
        'c1000000-0000-4000-8000-000000000009'
      );

    insert into public.active_list_split_settings (
      list_id,
      currency_code
    )
    values
      ('c2000000-0000-4000-8000-00000000000d', 'EUR'),
      ('c2000000-0000-4000-8000-00000000000b', 'EUR');

    insert into public.active_list_split_participants (
      id,
      list_id,
      profile_id,
      username_snapshot,
      display_name_snapshot
    )
    values
      (
        'c6000000-0000-4000-8000-0000000000d1',
        'c2000000-0000-4000-8000-00000000000d',
        'c1000000-0000-4000-8000-000000000001',
        'noteraceowner',
        'Note race'
      ),
      (
        'c6000000-0000-4000-8000-0000000000d2',
        'c2000000-0000-4000-8000-00000000000d',
        'c1000000-0000-4000-8000-000000000009',
        'racemulti',
        'Extended note race'
      ),
      (
        'c6000000-0000-4000-8000-0000000000b1',
        'c2000000-0000-4000-8000-00000000000b',
        'c1000000-0000-4000-8000-000000000001',
        'noteraceowner',
        'Note race'
      ),
      (
        'c6000000-0000-4000-8000-0000000000b2',
        'c2000000-0000-4000-8000-00000000000b',
        'c1000000-0000-4000-8000-000000000009',
        'racemulti',
        'Extended note race'
      );

    insert into public.active_list_expenses (
      id,
      list_id,
      description,
      amount_minor,
      payer_participant_id,
      creator_participant_id,
      last_editor_participant_id,
      creation_request_id
    )
    values
      (
        'c7000000-0000-4000-8000-0000000000d1',
        'c2000000-0000-4000-8000-00000000000d',
        'Reverse high history',
        500,
        'c6000000-0000-4000-8000-0000000000d2',
        'c6000000-0000-4000-8000-0000000000d1',
        'c6000000-0000-4000-8000-0000000000d1',
        'c8000000-0000-4000-8000-0000000000d1'
      ),
      (
        'c7000000-0000-4000-8000-0000000000b1',
        'c2000000-0000-4000-8000-00000000000b',
        'Reverse low history',
        500,
        'c6000000-0000-4000-8000-0000000000b2',
        'c6000000-0000-4000-8000-0000000000b1',
        'c6000000-0000-4000-8000-0000000000b1',
        'c8000000-0000-4000-8000-0000000000b1'
      );

    insert into public.active_list_expense_shares (
      list_id,
      expense_id,
      participant_id,
      amount_minor
    )
    values
      (
        'c2000000-0000-4000-8000-00000000000d',
        'c7000000-0000-4000-8000-0000000000d1',
        'c6000000-0000-4000-8000-0000000000d2',
        500
      ),
      (
        'c2000000-0000-4000-8000-00000000000b',
        'c7000000-0000-4000-8000-0000000000b1',
        'c6000000-0000-4000-8000-0000000000b2',
        500
      );
  $remote$
);

-- Note first, Auth-root deletion second. The note owns the target profile and
-- waits on the parent; deletion must wait at the profile phase. After the note
-- commits, one parent-first cleanup removes assignment/mention identity,
-- clears completed_by, anonymizes Split identity, and preserves history.
truncate note_race_results;
select extensions.dblink_exec('note_race_hold', 'begin');
select extensions.dblink_exec(
  'note_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'c2000000-0000-4000-8000-000000000006'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local statement_timeout = ''10s'''
);
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'note_race_first',
    $remote$
      select pg_temp.attempt_note(
        'c2000000-0000-4000-8000-000000000006',
        'Updated @racedeleteone',
        array['c1000000-0000-4000-8000-000000000006'::uuid],
        2
      )
    $remote$
  ),
  1,
  'note-before-account-delete starts asynchronously'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'note_race_first'
      and wait_event_type = 'Lock'
  ),
  'note-before-account-delete proves profile-first then parent-list waiting'
);

select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local statement_timeout = ''10s'''
);
select is(
  extensions.dblink_send_query(
    'note_race_second',
    $remote$
      select pg_temp.attempt_auth_delete(
        'c1000000-0000-4000-8000-000000000006'
      )
    $remote$
  ),
  1,
  'Auth-root deletion queues behind the note-owned profile'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and extensions.dblink_is_busy('note_race_second') = 1
  and (
    select pg_catalog.count(*) = 2
    from pg_catalog.pg_stat_activity
    where application_name in ('note_race_first', 'note_race_second')
      and wait_event_type = 'Lock'
  ),
  'note-before-delete proves both sessions wait on bounded ordered locks'
);
select extensions.dblink_exec('note_race_hold', 'commit');
insert into note_race_results
select 'note-first', result
from extensions.dblink_get_result('note_race_first')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_first')
      as drained(status text)
  ),
  0::bigint,
  'note-before-delete note queue is fully drained'
);
select extensions.dblink_exec('note_race_first', 'commit');
insert into note_race_results
select 'delete-second', result
from extensions.dblink_get_result('note_race_second')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'note-before-delete deletion queue is fully drained'
);
select extensions.dblink_exec('note_race_second', 'commit');
select is(
  (
    select pg_catalog.array_agg(result order by label)
    from note_race_results
  ),
  array['ok', 'ok']::text[],
  'note-first and Auth-root deletion both complete without a deadlock'
);
select ok(
  not exists (
    select 1
    from public.profiles
    where id = 'c1000000-0000-4000-8000-000000000006'
  )
  and (
    select version = 4
      and general_note_version = 4
      and general_note_text = 'Updated @racedeleteone'
    from public.active_lists
    where id = 'c2000000-0000-4000-8000-000000000006'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'c2000000-0000-4000-8000-000000000006'
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'c2000000-0000-4000-8000-000000000006'
  )
  and (
    select completed_by is null and version = 2
    from public.active_list_items
    where id = 'c4000000-0000-4000-8000-000000000006'
  )
  and (
    select profile_id is null
      and username_snapshot is null
      and display_name_snapshot is null
    from public.active_list_split_participants
    where id = 'c6000000-0000-4000-8000-000000000062'
  )
  and exists (
    select 1
    from public.active_list_expenses
    where id = 'c7000000-0000-4000-8000-000000000061'
  ),
  'note-first deletion performs one parent bump and preserves completed and Split history'
);

-- Reverse order: Auth-root deletion completes its statement while retaining
-- profile/list/child locks. A note that preflighted the old mention waits on
-- the profile, then observes cleanup and returns 40001 with no partial write.
truncate note_race_results;
select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local statement_timeout = ''10s'''
);
select is(
  extensions.dblink_send_query(
    'note_race_second',
    $remote$
      select pg_temp.attempt_auth_delete(
        'c1000000-0000-4000-8000-000000000007'
      )
    $remote$
  ),
  1,
  'account-delete-before-note starts asynchronously'
);
insert into note_race_results
select 'delete-first', result
from extensions.dblink_get_result('note_race_second')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'delete-before-note result is drained while coordinator locks remain held'
);

select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local statement_timeout = ''10s'''
);
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'note_race_first',
    $remote$
      select pg_temp.attempt_note(
        'c2000000-0000-4000-8000-000000000007',
        'Forbidden @racedeletetwo',
        array['c1000000-0000-4000-8000-000000000007'::uuid],
        2
      )
    $remote$
  ),
  1,
  'note queues behind the uncommitted Auth-root deletion'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'note_race_first'
      and wait_event_type = 'Lock'
  ),
  'delete-before-note proves the note waits on the profile phase before revalidation'
);
select extensions.dblink_exec('note_race_second', 'commit');
insert into note_race_results
select 'note-second', result
from extensions.dblink_get_result('note_race_first')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_first')
      as drained(status text)
  ),
  0::bigint,
  'delete-before-note queued note result is fully drained'
);
select extensions.dblink_exec('note_race_first', 'commit');
select is(
  (
    select pg_catalog.array_agg(result order by label)
    from note_race_results
  ),
  array['ok', '40001']::text[],
  'delete-first succeeds and the stale queued note receives 40001'
);
select ok(
  (
    select version = 3
      and general_note_version = 3
      and general_note_text = 'Initial @racedeletetwo'
    from public.active_lists
    where id = 'c2000000-0000-4000-8000-000000000007'
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id = 'c2000000-0000-4000-8000-000000000007'
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id = 'c2000000-0000-4000-8000-000000000007'
  )
  and (
    select completed_by is null and version = 2
    from public.active_list_items
    where id = 'c4000000-0000-4000-8000-000000000007'
  )
  and (
    select profile_id is null
      and username_snapshot is null
      and display_name_snapshot is null
    from public.active_list_split_participants
    where id = 'c6000000-0000-4000-8000-000000000072'
  )
  and exists (
    select 1
    from public.active_list_expenses
    where id = 'c7000000-0000-4000-8000-000000000071'
  ),
  'delete-first preserves literal note and financial history with one cleanup parent bump'
);

-- Reproduce the former Split inversion directly: hold only the target Split
-- child, let expense mutation own the parent and wait on that child, then
-- start Auth-root deletion. Parent-first deletion must wait on the parent,
-- not retain a Split child lock that would close a cycle.
truncate note_race_results;
select extensions.dblink_exec('note_race_hold', 'begin');
select extensions.dblink_exec(
  'note_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_list_split_participants
      where id = 'c6000000-0000-4000-8000-000000000082'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local statement_timeout = ''10s'''
);
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'note_race_first',
    $remote$
      select pg_temp.attempt_expense(
        'c2000000-0000-4000-8000-000000000008',
        'c6000000-0000-4000-8000-000000000082',
        array['c6000000-0000-4000-8000-000000000082'::uuid],
        'c8000000-0000-4000-8000-000000000081',
        1
      )
    $remote$
  ),
  1,
  'expense mutation starts and owns its parent before Split children'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'note_race_first'
      and wait_event_type = 'Lock'
  ),
  'expense mutation proves it waits on the deliberately held Split child'
);

select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local statement_timeout = ''10s'''
);
select is(
  extensions.dblink_send_query(
    'note_race_second',
    $remote$
      select pg_temp.attempt_auth_delete(
        'c1000000-0000-4000-8000-000000000008'
      )
    $remote$
  ),
  1,
  'Auth-root deletion starts behind the expense-owned parent'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_first') = 1
  and extensions.dblink_is_busy('note_race_second') = 1
  and (
    select pg_catalog.count(*) = 2
    from pg_catalog.pg_stat_activity
    where application_name in ('note_race_first', 'note_race_second')
      and wait_event_type = 'Lock'
  ),
  'expense/delete barrier proves no child-first deletion lock closes the former cycle'
);
select extensions.dblink_exec('note_race_hold', 'commit');
insert into note_race_results
select 'expense-first', result
from extensions.dblink_get_result('note_race_first')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_first')
      as drained(status text)
  ),
  0::bigint,
  'expense/delete mutation result queue is fully drained'
);
select extensions.dblink_exec('note_race_first', 'commit');
insert into note_race_results
select 'delete-second', result
from extensions.dblink_get_result('note_race_second')
  as remote_result(result text);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'expense/delete account result queue is fully drained'
);
select extensions.dblink_exec('note_race_second', 'commit');
select is(
  (
    select pg_catalog.array_agg(result order by label)
    from note_race_results
  ),
  array['ok', 'ok']::text[],
  'expense and account deletion serialize without deadlock or timeout'
);
select ok(
  (
    select version = 2
    from public.active_list_split_settings
    where list_id = 'c2000000-0000-4000-8000-000000000008'
  )
  and (
    select profile_id is null
      and username_snapshot is null
      and display_name_snapshot is null
    from public.active_list_split_participants
    where id = 'c6000000-0000-4000-8000-000000000082'
  )
  and (
    select pg_catalog.count(*) = 1
    from public.active_list_expenses
    where list_id = 'c2000000-0000-4000-8000-000000000008'
      and creation_request_id =
        'c8000000-0000-4000-8000-000000000081'
  )
  and (
    select version = 2
    from public.active_lists
    where id = 'c2000000-0000-4000-8000-000000000008'
  ),
  'former inversion race preserves the expense and anonymizes only live financial identity'
);

-- An exact completed note retry accepts the immediately prior expected version
-- but must be a total side-effect no-op: scalar/link versions, timestamps,
-- notifications, suppression, and private Broadcast rows all stay identical.
select extensions.dblink_exec(
  'note_race_setup',
  $remote$
    delete from public.user_notifications
    where active_list_id = 'c2000000-0000-4000-8000-00000000000a';
    delete from realtime.messages
    where topic in (
      'account:c1000000-0000-4000-8000-000000000001',
      'account:c1000000-0000-4000-8000-00000000000b'
    )
  $remote$
);
select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  (
    select result
    from extensions.dblink(
      'note_race_first',
      $remote$
        select pg_temp.attempt_note(
          'c2000000-0000-4000-8000-00000000000a',
          'Retry @raceretry',
          array['c1000000-0000-4000-8000-00000000000b'::uuid],
          1
        )
      $remote$
    ) as first_result(result text)
  ),
  'ok',
  'initial note request completes before its exact retry'
);
select extensions.dblink_exec('note_race_first', 'commit');

create temporary table note_retry_snapshot on commit drop as
select
  list_record.version as list_version,
  list_record.general_note_version,
  list_record.general_note_updated_at,
  (
    select pg_catalog.count(*)
    from public.active_list_note_mentions as mention_record
    where mention_record.list_id = list_record.id
  ) as mention_count,
  (
    select pg_catalog.count(*)
    from public.user_notifications as notification_record
    where notification_record.active_list_id = list_record.id
      and notification_record.notification_type = 'list_note_mentioned'
  ) as notification_count,
  (
    select pg_catalog.count(*)
    from public.user_notifications as notification_record
    where notification_record.active_list_id = list_record.id
      and notification_record.notification_type = 'list_note_mentioned'
      and notification_record.suppressed_at is not null
  ) as suppression_count,
  (
    select pg_catalog.count(*)
    from realtime.messages as message_record
    where message_record.topic in (
      'account:c1000000-0000-4000-8000-000000000001',
      'account:c1000000-0000-4000-8000-00000000000b'
    )
  ) as broadcast_count
from public.active_lists as list_record
where list_record.id = 'c2000000-0000-4000-8000-00000000000a';

select ok(
  (
    select list_version = 2
      and general_note_version = 2
      and mention_count = 1
      and notification_count = 1
      and suppression_count = 0
      and broadcast_count > 0
    from note_retry_snapshot
  ),
  'initial completed request records one resolved mention and one unsuppressed notification'
);

select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'c1000000-0000-4000-8000-000000000001'
  $remote$
);
select is(
  (
    select result
    from extensions.dblink(
      'note_race_first',
      $remote$
        select pg_temp.attempt_note(
          'c2000000-0000-4000-8000-00000000000a',
          'Retry @raceretry',
          array['c1000000-0000-4000-8000-00000000000b'::uuid],
          1
        )
      $remote$
    ) as retry_result(result text)
  ),
  'ok',
  'payload-identical completed request accepts the prior expected version'
);
select extensions.dblink_exec('note_race_first', 'commit');
select ok(
  (
    select
      list_record.version = snapshot.list_version
      and list_record.general_note_version =
        snapshot.general_note_version
      and list_record.general_note_updated_at =
        snapshot.general_note_updated_at
      and (
        select pg_catalog.count(*)
        from public.active_list_note_mentions as mention_record
        where mention_record.list_id = list_record.id
      ) = snapshot.mention_count
      and (
        select pg_catalog.count(*)
        from public.user_notifications as notification_record
        where notification_record.active_list_id = list_record.id
          and notification_record.notification_type =
            'list_note_mentioned'
      ) = snapshot.notification_count
      and (
        select pg_catalog.count(*)
        from public.user_notifications as notification_record
        where notification_record.active_list_id = list_record.id
          and notification_record.notification_type =
            'list_note_mentioned'
          and notification_record.suppressed_at is not null
      ) = snapshot.suppression_count
      and (
        select pg_catalog.count(*)
        from realtime.messages as message_record
        where message_record.topic in (
          'account:c1000000-0000-4000-8000-000000000001',
          'account:c1000000-0000-4000-8000-00000000000b'
        )
      ) = snapshot.broadcast_count
    from public.active_lists as list_record
    cross join note_retry_snapshot as snapshot
    where list_record.id = 'c2000000-0000-4000-8000-00000000000a'
  ),
  'exact retry adds no version, timestamp, link, notification, suppression, or Broadcast side effect'
);

-- The affected lists were inserted high UUID first. Hold the low parent and
-- start deletion: an independent lock of the high parent must still succeed,
-- proving the coordinator is blocked at the lower UUID rather than having
-- acquired the higher parent first.
select extensions.dblink_exec(
  'note_race_first',
  $remote$
    create or replace function pg_temp.attempt_list_lock(
      target_list_id uuid
    )
    returns text
    language plpgsql
    as $function$
    begin
      perform 1
      from public.active_lists
      where id = target_list_id
      for update;
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
select extensions.dblink_exec('note_race_hold', 'begin');
select extensions.dblink_exec(
  'note_race_hold',
  $remote$
    do $block$
    begin
      perform 1
      from public.active_lists
      where id = 'c2000000-0000-4000-8000-00000000000b'
      for update;
    end
    $block$
  $remote$
);
select extensions.dblink_exec('note_race_second', 'begin');
select extensions.dblink_exec(
  'note_race_second',
  'set local statement_timeout = ''10s'''
);
select is(
  extensions.dblink_send_query(
    'note_race_second',
    $remote$
      select pg_temp.attempt_auth_delete(
        'c1000000-0000-4000-8000-000000000009'
      )
    $remote$
  ),
  1,
  'reverse-inserted multi-list account cleanup starts asynchronously'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('note_race_second') = 1
  and exists (
    select 1
    from pg_catalog.pg_stat_activity
    where application_name = 'note_race_second'
      and wait_event_type = 'Lock'
  ),
  'multi-list deletion proves it waits at the held lower parent UUID'
);
select extensions.dblink_exec('note_race_first', 'begin');
select extensions.dblink_exec(
  'note_race_first',
  'set local statement_timeout = ''2s'''
);
select is(
  (
    select result
    from extensions.dblink(
      'note_race_first',
      $remote$
        select pg_temp.attempt_list_lock(
          'c2000000-0000-4000-8000-00000000000d'
        )
      $remote$
    ) as lock_result(result text)
  ),
  'ok',
  'higher parent remains lockable while deletion waits on the lower UUID'
);
select extensions.dblink_exec('note_race_first', 'commit');
select extensions.dblink_exec('note_race_hold', 'commit');
select is(
  (
    select result
    from extensions.dblink_get_result('note_race_second')
      as delete_result(result text)
  ),
  'ok',
  'reverse-inserted multi-list cleanup completes after the ordered barrier releases'
);
select is(
  (
    select pg_catalog.count(*)
    from extensions.dblink_get_result('note_race_second')
      as drained(status text)
  ),
  0::bigint,
  'reverse-order multi-list cleanup result queue is fully drained'
);
select extensions.dblink_exec('note_race_second', 'commit');
select ok(
  not exists (
    select 1
    from public.profiles
    where id = 'c1000000-0000-4000-8000-000000000009'
  )
  and (
    select pg_catalog.count(*) = 2
      and pg_catalog.bool_and(
        list_record.version = 3
        and list_record.general_note_version = 3
        and list_record.general_note_text like 'Keep literal @racemulti%'
      )
    from public.active_lists as list_record
    where list_record.id in (
      'c2000000-0000-4000-8000-00000000000b',
      'c2000000-0000-4000-8000-00000000000d'
    )
  )
  and not exists (
    select 1
    from public.active_list_note_mentions
    where list_id in (
      'c2000000-0000-4000-8000-00000000000b',
      'c2000000-0000-4000-8000-00000000000d'
    )
  )
  and not exists (
    select 1
    from public.active_list_item_assignments
    where list_id in (
      'c2000000-0000-4000-8000-00000000000b',
      'c2000000-0000-4000-8000-00000000000d'
    )
  )
  and (
    select pg_catalog.count(*) = 2
      and pg_catalog.bool_and(
        item_record.completed_by is null
        and item_record.version = 2
      )
    from public.active_list_items as item_record
    where item_record.list_id in (
      'c2000000-0000-4000-8000-00000000000b',
      'c2000000-0000-4000-8000-00000000000d'
    )
  )
  and (
    select pg_catalog.count(*) = 2
      and pg_catalog.bool_and(
        split_participant.profile_id is null
        and split_participant.username_snapshot is null
        and split_participant.display_name_snapshot is null
      )
    from public.active_list_split_participants as split_participant
    where split_participant.id in (
      'c6000000-0000-4000-8000-0000000000b2',
      'c6000000-0000-4000-8000-0000000000d2'
    )
  )
  and (
    select pg_catalog.count(*) = 2
    from public.active_list_expenses as expense_record
    where expense_record.list_id in (
      'c2000000-0000-4000-8000-00000000000b',
      'c2000000-0000-4000-8000-00000000000d'
    )
  ),
  'reverse-UUID cleanup bumps each parent once, removes live links, and preserves both histories'
);

select extensions.dblink_exec(
  'note_race_setup',
  $remote$
    delete from public.active_lists
    where id::text like 'c2000000-0000-4000-8000-%';
    delete from auth.users
    where id in (
      'c1000000-0000-4000-8000-000000000001',
      'c1000000-0000-4000-8000-000000000002',
      'c1000000-0000-4000-8000-000000000003',
      'c1000000-0000-4000-8000-000000000004',
      'c1000000-0000-4000-8000-000000000005',
      'c1000000-0000-4000-8000-000000000006',
      'c1000000-0000-4000-8000-000000000007',
      'c1000000-0000-4000-8000-000000000008',
      'c1000000-0000-4000-8000-000000000009',
      'c1000000-0000-4000-8000-00000000000a',
      'c1000000-0000-4000-8000-00000000000b'
    );
    delete from private.deleted_username_reservations
    where canonical_username in (
      'noteraceowner',
      'noteracemember',
      'noteracesecond',
      'raceblockone',
      'raceblocktwo',
      'racedeleteone',
      'racedeletetwo',
      'raceexpense',
      'racemulti',
      'raceusername',
      'raceretry'
    );
    delete from realtime.messages
    where topic like 'account:c1000000-0000-4000-8000-%'
  $remote$
);

select ok(
  not exists (
    select 1
    from auth.users
    where id::text like 'c1000000-0000-4000-8000-%'
  )
  and not exists (
    select 1
    from public.active_lists
    where id::text like 'c2000000-0000-4000-8000-%'
  )
  and not exists (
    select 1
    from private.deleted_username_reservations
    where canonical_username in (
      'noteraceowner',
      'noteracemember',
      'noteracesecond',
      'raceblockone',
      'raceblocktwo',
      'racedeleteone',
      'racedeletetwo',
      'raceexpense',
      'racemulti',
      'raceusername',
      'raceretry'
    )
  )
  and not exists (
    select 1
    from realtime.messages
    where topic like 'account:c1000000-0000-4000-8000-%'
  ),
  'all autonomous race fixtures, reservations, and Broadcast rows are removed'
);

select extensions.dblink_disconnect('note_race_setup');
select extensions.dblink_disconnect('note_race_hold');
select extensions.dblink_disconnect('note_race_first');
select extensions.dblink_disconnect('note_race_second');

select * from finish();
rollback;
