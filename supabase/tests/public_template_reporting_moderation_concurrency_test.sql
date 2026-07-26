begin;

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select no_plan();

select extensions.dblink_connect(
  'moderation_race_setup',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=moderation_race_setup'
);
select extensions.dblink_connect(
  'moderation_race_first',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=moderation_race_first'
);
select extensions.dblink_connect(
  'moderation_race_second',
  'host=host.docker.internal port=54322 dbname=postgres user=postgres password=postgres application_name=moderation_race_second'
);

select extensions.dblink_exec(
  'moderation_race_setup',
  $remote$
    delete from public.user_notifications
    where public_template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_moderation_events
    where template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_reports
    where template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_report_groups
    where template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_moderation_restrictions
    where template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_moderator_access_events
    where request_id = 'f5000000-0000-4000-8000-000000000001';
    delete from auth.users
    where id in (
      'f1000000-0000-4000-8000-000000000001',
      'f1000000-0000-4000-8000-000000000002',
      'f1000000-0000-4000-8000-000000000003'
    );
    delete from private.deleted_username_reservations
    where canonical_username in (
      'moderationraceowner',
      'moderationracereporter',
      'moderationracereviewer'
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
        'moderation-race-owner@example.test',
        now(),
        now(),
        now()
      ),
      (
        'f1000000-0000-4000-8000-000000000002',
        'moderation-race-reporter@example.test',
        now(),
        now(),
        now()
      ),
      (
        'f1000000-0000-4000-8000-000000000003',
        'moderation-race-reviewer@example.test',
        now(),
        now(),
        now()
      );

    update public.profiles
    set username = case id
          when 'f1000000-0000-4000-8000-000000000001'
            then 'moderationraceowner'
          when 'f1000000-0000-4000-8000-000000000002'
            then 'moderationracereporter'
          else 'moderationracereviewer'
        end,
        display_name = 'Moderation race',
        onboarding_completed_at = now()
    where id in (
      'f1000000-0000-4000-8000-000000000001',
      'f1000000-0000-4000-8000-000000000002',
      'f1000000-0000-4000-8000-000000000003'
    );

    insert into public.templates (
      id,
      owner_id,
      name,
      version,
      creation_request_id,
      published_at
    )
    values (
      'f2000000-0000-4000-8000-000000000001',
      'f1000000-0000-4000-8000-000000000001',
      'Concurrent report source',
      1,
      'f3000000-0000-4000-8000-000000000001',
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
    values (
      'f4000000-0000-4000-8000-000000000001',
      'f2000000-0000-4000-8000-000000000001',
      'Water',
      1500,
      1,
      'f4000000-0000-4000-8000-000000000002'
    );

    select private.grant_public_template_moderator(
      'f1000000-0000-4000-8000-000000000003',
      'local-concurrency-test',
      'f5000000-0000-4000-8000-000000000001'
    );

    delete from realtime.messages
    where topic like 'account:f1000000-0000-4000-8000-%';
  $remote$
);

create temporary table moderation_race_results (
  label text primary key,
  result text not null
) on commit drop;

-- The first report completes but holds the template advisory lock until its
-- transaction commits. The concurrent identical retry must then converge.
select extensions.dblink_exec('moderation_race_first', 'begin');
select extensions.dblink_exec(
  'moderation_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'moderation_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'moderation_race_first',
    $remote$
      select report_id::text
      from public.report_public_template(
        'f2000000-0000-4000-8000-000000000001',
        1,
        'spam_scam_deceptive',
        null
      )
    $remote$
  ),
  1,
  'first report starts asynchronously'
);
select pg_catalog.pg_sleep(0.1);

select extensions.dblink_exec('moderation_race_second', 'begin');
select extensions.dblink_exec(
  'moderation_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'moderation_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000002'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'moderation_race_second',
    $remote$
      select report_id::text
      from public.report_public_template(
        'f2000000-0000-4000-8000-000000000001',
        1,
        'spam_scam_deceptive',
        null
      )
    $remote$
  ),
  1,
  'concurrent identical report retry starts'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('moderation_race_second') = 1,
  'concurrent report retry waits on the template moderation lock'
);

insert into moderation_race_results
select 'report-first', result
from extensions.dblink_get_result('moderation_race_first')
  as remote_result(result text);
select *
from extensions.dblink_get_result('moderation_race_first')
  as drained(status text);
select extensions.dblink_exec('moderation_race_first', 'commit');
insert into moderation_race_results
select 'report-second', result
from extensions.dblink_get_result('moderation_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('moderation_race_second')
  as drained(status text);
select extensions.dblink_exec('moderation_race_second', 'commit');

select is(
  (
    select pg_catalog.count(distinct result)
    from moderation_race_results
    where label like 'report-%'
  ),
  1::bigint,
  'concurrent identical reports return one immutable report identity'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_reports
    where template_id = 'f2000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'concurrent duplicate reporting stores exactly one individual report'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_report_groups
    where template_id = 'f2000000-0000-4000-8000-000000000001'
      and status = 'open'
  ),
  1::bigint,
  'concurrent duplicate reporting stores exactly one open group'
);

-- Repeat the same pattern for a payload-bound takedown request. The retry
-- must return the committed event instead of duplicating the decision or
-- owner notification.
select extensions.dblink_exec('moderation_race_first', 'begin');
select extensions.dblink_exec(
  'moderation_race_first',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'moderation_race_first',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000003'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'moderation_race_first',
    $remote$
      select result ->> 'event_id'
      from (
        select public.moderate_public_template_report_group(
          (
            public.list_public_template_moderation_queue(
              'open',
              20,
              null,
              null
            ) -> 'cases' -> 0 ->> 'group_id'
          )::uuid,
          'take_down',
          1,
          1,
          'spam_scam_deceptive',
          'Confirmed by the local concurrency test.',
          'f6000000-0000-4000-8000-000000000001'
        ) as result
      ) as decision
    $remote$
  ),
  1,
  'first takedown starts asynchronously'
);
select pg_catalog.pg_sleep(0.1);

select extensions.dblink_exec('moderation_race_second', 'begin');
select extensions.dblink_exec(
  'moderation_race_second',
  'set local role authenticated'
);
select extensions.dblink_exec(
  'moderation_race_second',
  $remote$
    set local "request.jwt.claim.sub" =
      'f1000000-0000-4000-8000-000000000003'
  $remote$
);
select is(
  extensions.dblink_send_query(
    'moderation_race_second',
    $remote$
      select result ->> 'event_id'
      from (
        select public.moderate_public_template_report_group(
          (
            public.list_public_template_moderation_queue(
              'open',
              20,
              null,
              null
            ) -> 'cases' -> 0 ->> 'group_id'
          )::uuid,
          'take_down',
          1,
          1,
          'spam_scam_deceptive',
          'Confirmed by the local concurrency test.',
          'f6000000-0000-4000-8000-000000000001'
        ) as result
      ) as decision
    $remote$
  ),
  1,
  'concurrent identical takedown retry starts'
);
select pg_catalog.pg_sleep(0.2);
select ok(
  extensions.dblink_is_busy('moderation_race_second') = 1,
  'concurrent takedown retry waits on the template moderation lock'
);

insert into moderation_race_results
select 'takedown-first', result
from extensions.dblink_get_result('moderation_race_first')
  as remote_result(result text);
select *
from extensions.dblink_get_result('moderation_race_first')
  as drained(status text);
select extensions.dblink_exec('moderation_race_first', 'commit');
insert into moderation_race_results
select 'takedown-second', result
from extensions.dblink_get_result('moderation_race_second')
  as remote_result(result text);
select *
from extensions.dblink_get_result('moderation_race_second')
  as drained(status text);
select extensions.dblink_exec('moderation_race_second', 'commit');

select is(
  (
    select pg_catalog.count(distinct result)
    from moderation_race_results
    where label like 'takedown-%'
  ),
  1::bigint,
  'concurrent identical takedowns return one immutable event identity'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_moderation_events
    where request_id = 'f6000000-0000-4000-8000-000000000001'
      and action = 'take_down'
  ),
  1::bigint,
  'concurrent identical takedowns append exactly one decision event'
);
select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where public_template_id =
      'f2000000-0000-4000-8000-000000000001'
      and notification_type = 'public_template_taken_down'
  ),
  1::bigint,
  'concurrent identical takedowns create exactly one owner notification'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_moderation_restrictions
    where template_id = 'f2000000-0000-4000-8000-000000000001'
      and active
  ),
  1::bigint,
  'concurrent identical takedowns create one active restriction'
);

select extensions.dblink_exec(
  'moderation_race_setup',
  $remote$
    delete from public.user_notifications
    where public_template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_moderation_events
    where template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_reports
    where template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_report_groups
    where template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_moderation_restrictions
    where template_id = 'f2000000-0000-4000-8000-000000000001';
    delete from private.public_template_moderator_access_events
    where request_id = 'f5000000-0000-4000-8000-000000000001';
    delete from auth.users
    where id in (
      'f1000000-0000-4000-8000-000000000001',
      'f1000000-0000-4000-8000-000000000002',
      'f1000000-0000-4000-8000-000000000003'
    );
    delete from private.deleted_username_reservations
    where canonical_username in (
      'moderationraceowner',
      'moderationracereporter',
      'moderationracereviewer'
    );
    delete from realtime.messages
    where topic like 'account:f1000000-0000-4000-8000-%';
  $remote$
);

select ok(
  not exists (
    select 1
    from auth.users
    where id::text like 'f1000000-0000-4000-8000-%'
  )
  and not exists (
    select 1
    from private.public_template_report_groups
    where template_id = 'f2000000-0000-4000-8000-000000000001'
  )
  and not exists (
    select 1
    from private.public_template_moderation_events
    where template_id = 'f2000000-0000-4000-8000-000000000001'
  ),
  'real-session moderation race fixtures are cleaned up'
);

select extensions.dblink_disconnect('moderation_race_first');
select extensions.dblink_disconnect('moderation_race_second');
select extensions.dblink_disconnect('moderation_race_setup');

select * from finish();
rollback;
