begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table(
  'private',
  'public_template_moderators',
  'the private moderator allowlist exists'
);
select has_table(
  'private',
  'public_template_report_groups',
  'private report groups exist'
);
select has_table(
  'private',
  'public_template_reports',
  'private individual reports exist'
);
select has_table(
  'private',
  'public_template_moderation_restrictions',
  'private template restrictions exist'
);
select has_table(
  'private',
  'public_template_moderation_events',
  'append-only moderation events exist'
);
select has_table(
  'private',
  'public_template_moderation_tombstones',
  'nonidentifying retention tombstones exist'
);
select has_index(
  'private',
  'public_template_moderator_access_events',
  'public_template_moderator_access_events_moderator_idx',
  'moderator access audit identity cleanup has a covering index'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as table_record
    where table_record.oid in (
      'private.public_template_moderators'::regclass,
      'private.public_template_moderator_access_events'::regclass,
      'private.public_template_report_groups'::regclass,
      'private.public_template_reports'::regclass,
      'private.public_template_moderation_restrictions'::regclass,
      'private.public_template_moderation_events'::regclass,
      'private.public_template_moderation_tombstones'::regclass
    )
      and table_record.relrowsecurity
      and table_record.relforcerowsecurity
  ),
  7::bigint,
  'every moderation table enables and forces RLS'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies as policy_record
    where policy_record.schemaname = 'private'
      and policy_record.tablename in (
        'public_template_moderators',
        'public_template_moderator_access_events',
        'public_template_report_groups',
        'public_template_reports',
        'public_template_moderation_restrictions',
        'public_template_moderation_events',
        'public_template_moderation_tombstones'
      )
      and policy_record.cmd = 'ALL'
      and policy_record.roles = array['anon','authenticated']::name[]
      and policy_record.qual = 'false'
      and policy_record.with_check = 'false'
  ),
  7::bigint,
  'every moderation table explicitly rejects all direct client operations'
);

select ok(
  not has_table_privilege(
    'anon',
    'private.public_template_reports',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.public_template_reports',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'private.public_template_reports',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.public_template_moderators',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'API roles have no direct evidence or allowlist privileges'
);

select is(
  (
    select pg_catalog.count(*)
    from (
      values
        ('spam_scam_deceptive'),
        ('hate_harassment_bullying'),
        ('sexual_content'),
        ('violence_dangerous'),
        ('illegal_regulated'),
        ('personal_confidential_information'),
        ('copyright_trademark'),
        ('other')
    ) as supported_reason(reason_code)
    where private.is_supported_public_template_report_reason(
      supported_reason.reason_code
    )
  ),
  8::bigint,
  'all eight stable report reason codes are accepted server-side'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.is_public_template_moderator()'::regprocedure,
      'public.report_public_template(uuid,bigint,text,text)'::regprocedure,
      'public.list_private_templates_v3(text,uuid,boolean,text)'::regprocedure,
      'public.get_private_template_v3(uuid)'::regprocedure,
      'public.list_public_template_moderation_queue(text,integer,timestamptz,uuid)'::regprocedure,
      'public.get_public_template_moderation_case(uuid)'::regprocedure,
      'public.moderate_public_template_report_group(uuid,text,bigint,bigint,text,text,uuid)'::regprocedure,
      'public.restore_public_template_moderation(uuid,bigint,bigint,text,uuid)'::regprocedure,
      'public.list_notifications_v4(integer,timestamptz,uuid)'::regprocedure,
      'public.get_unread_notification_count_v4()'::regprocedure,
      'public.export_own_account_data_v10()'::regprocedure
    )
      and function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
  ),
  11::bigint,
  'all client moderation boundaries are postgres-owned hardened definers'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.report_public_template(uuid,bigint,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.list_public_template_moderation_queue(text,integer,timestamptz,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.report_public_template(uuid,bigint,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_public_template_moderation_case(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.grant_public_template_moderator(uuid,text,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'private.maintain_public_template_moderation_retention(timestamptz)',
    'EXECUTE'
  ),
  'authenticated receives only app RPCs while administrative functions stay postgres-only'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_publication_tables as published_table
    where published_table.schemaname = 'private'
      and published_table.tablename like 'public_template_%'
  ),
  0::bigint,
  'no moderation table is exposed through Postgres Changes'
);

set local role anon;
select throws_like(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000001',
      1,
      'spam_scam_deceptive',
      null
    )$$,
  '%permission denied%function%report_public_template%',
  'anonymous report execution is denied'
);
select throws_like(
  $$select * from private.public_template_reports$$,
  '%permission denied%',
  'anonymous evidence reads are denied'
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
    'e1000000-0000-4000-8000-000000000001',
    'moderation-owner@example.test',
    now(),
    now(),
    now()
  ),
  (
    'e1000000-0000-4000-8000-000000000002',
    'moderation-reporter@example.test',
    now(),
    now(),
    now()
  ),
  (
    'e1000000-0000-4000-8000-000000000003',
    'moderation-other@example.test',
    now(),
    now(),
    now()
  ),
  (
    'e1000000-0000-4000-8000-000000000004',
    'moderation-moderator@example.test',
    now(),
    now(),
    now()
  ),
  (
    'e1000000-0000-4000-8000-000000000005',
    'moderation-revoked@example.test',
    now(),
    now(),
    now()
  ),
  (
    'e1000000-0000-4000-8000-000000000006',
    'moderation-blocked@example.test',
    now(),
    now(),
    now()
  );

update public.profiles
set username = case id
      when 'e1000000-0000-4000-8000-000000000001' then 'mod_owner'
      when 'e1000000-0000-4000-8000-000000000002' then 'mod_reporter'
      when 'e1000000-0000-4000-8000-000000000003' then 'mod_other'
      when 'e1000000-0000-4000-8000-000000000004' then 'mod_moderator'
      when 'e1000000-0000-4000-8000-000000000005' then 'mod_revoked'
      when 'e1000000-0000-4000-8000-000000000006' then 'mod_blocked'
    end,
    display_name = case id
      when 'e1000000-0000-4000-8000-000000000001' then 'Moderation Owner'
      when 'e1000000-0000-4000-8000-000000000002' then 'Moderation Reporter'
      when 'e1000000-0000-4000-8000-000000000003' then 'Moderation Other'
      when 'e1000000-0000-4000-8000-000000000004' then 'Moderation Moderator'
      when 'e1000000-0000-4000-8000-000000000005' then 'Moderation Revoked'
      when 'e1000000-0000-4000-8000-000000000006' then 'Moderation Blocked'
    end;

insert into public.template_categories (
  id,
  owner_id,
  name,
  normalized_name,
  creation_request_id
)
values (
  'e3000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000001',
  'Private secret category',
  'private secret category',
  'e3100000-0000-4000-8000-000000000001'
);

insert into public.templates (
  id,
  owner_id,
  category_id,
  name,
  version,
  creation_request_id,
  published_at
)
values
  (
    'e2000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001',
    'e3000000-0000-4000-8000-000000000001',
    'Reported trip kit',
    5,
    'e2100000-0000-4000-8000-000000000001',
    now()
  ),
  (
    'e2000000-0000-4000-8000-000000000002',
    'e1000000-0000-4000-8000-000000000001',
    null,
    'Other public kit',
    2,
    'e2100000-0000-4000-8000-000000000002',
    now()
  ),
  (
    'e2000000-0000-4000-8000-000000000003',
    'e1000000-0000-4000-8000-000000000001',
    null,
    'Private kit',
    1,
    'e2100000-0000-4000-8000-000000000003',
    null
  ),
  (
    'e2000000-0000-4000-8000-000000000004',
    'e1000000-0000-4000-8000-000000000001',
    null,
    'Delete after report',
    3,
    'e2100000-0000-4000-8000-000000000004',
    now()
  ),
  (
    'e2000000-0000-4000-8000-000000000005',
    'e1000000-0000-4000-8000-000000000001',
    null,
    'Dismiss then report',
    4,
    'e2100000-0000-4000-8000-000000000005',
    now()
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
    'Water',
    1500,
    1,
    'e4100000-0000-4000-8000-000000000001'
  ),
  (
    'e4000000-0000-4000-8000-000000000002',
    'e2000000-0000-4000-8000-000000000001',
    'Water',
    2000,
    2,
    'e4100000-0000-4000-8000-000000000002'
  );

insert into public.user_blocks (blocker_id, blocked_id)
values (
  'e1000000-0000-4000-8000-000000000006',
  'e1000000-0000-4000-8000-000000000001'
);

select lives_ok(
  $$select private.grant_public_template_moderator(
      'e1000000-0000-4000-8000-000000000004',
      'local-pgtap',
      'e5000000-0000-4000-8000-000000000001'
    )$$,
  'postgres can grant one verified Auth UUID through the protected helper'
);
select lives_ok(
  $$select private.grant_public_template_moderator(
      'e1000000-0000-4000-8000-000000000004',
      'local-pgtap',
      'e5000000-0000-4000-8000-000000000001'
    )$$,
  'an identical moderator grant request is idempotent'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_moderator_access_events
    where moderator_id = 'e1000000-0000-4000-8000-000000000004'
      and access_action = 'grant'
  ),
  1::bigint,
  'the moderator grant is audited exactly once'
);

create temporary table moderation_values (
  label text primary key,
  value_uuid uuid,
  value_uuid_two uuid,
  value_bigint bigint,
  value_bigint_two bigint,
  value_json jsonb
) on commit drop;
grant select, insert, update, delete on moderation_values to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000002';

select is(
  public.is_public_template_moderator(),
  false,
  'an ordinary authenticated caller is not a moderator'
);
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000003',
      1,
      'spam_scam_deceptive',
      null
    )$$,
  'P0002',
  'template unavailable',
  'a private template cannot be reported'
);
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000001',
      4,
      'spam_scam_deceptive',
      null
    )$$,
  '40001',
  'template changed',
  'a stale public revision cannot be reported'
);
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000099',
      1,
      'spam_scam_deceptive',
      null
    )$$,
  'P0002',
  'template unavailable',
  'a missing or deleted template cannot be reported'
);
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000001',
      5,
      'copyright_trademark',
      '   '
    )$$,
  '22023',
  'invalid public template report',
  'copyright reports require a nonempty explanation'
);
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000001',
      5,
      'other',
      repeat('x', 501)
    )$$,
  '22023',
  'invalid public template report',
  'report explanations are bounded at 500 characters'
);
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000001',
      5,
      'unsupported',
      null
    )$$,
  '22023',
  'invalid public template report',
  'unknown reason codes are rejected'
);

insert into moderation_values (
  label,
  value_uuid,
  value_uuid_two,
  value_bigint
)
select
  'primary-report',
  report_result.report_id,
  report_result.report_group_id,
  report_result.reported_revision
from public.report_public_template(
  'e2000000-0000-4000-8000-000000000001',
  5,
  'other',
  '  Explain this exact issue.  '
) as report_result;

select is(
  (
    select value_bigint
    from moderation_values
    where label = 'primary-report'
  ),
  5::bigint,
  'the report records the server-authoritative public revision'
);

select is(
  (
    select report_result.report_id
    from public.report_public_template(
      'e2000000-0000-4000-8000-000000000001',
      5,
      'other',
      'Explain this exact issue.'
    ) as report_result
  ),
  (
    select value_uuid
    from moderation_values
    where label = 'primary-report'
  ),
  'an identical report retry returns the original report'
);
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000001',
      5,
      'spam_scam_deceptive',
      null
    )$$,
  '23505',
  'public template report conflict',
  'the same reporter cannot change the payload for a reported revision'
);

select is(
  (
    public.list_public_profile_templates(
      'e1000000-0000-4000-8000-000000000001',
      20,
      null,
      null
    ) -> 'templates'
  ) @> '[{"template_id":"e2000000-0000-4000-8000-000000000001"}]'::jsonb,
  false,
  'the reported template disappears from the reporter public profile'
);
select is(
  (
    public.list_public_profile_templates(
      'e1000000-0000-4000-8000-000000000001',
      20,
      null,
      null
    ) -> 'templates'
  ) @> '[{"template_id":"e2000000-0000-4000-8000-000000000002"}]'::jsonb,
  true,
  'other public templates from the same owner remain visible'
);
select is(
  public.get_public_template(
    'e1000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001'
  ),
  null::jsonb,
  'reported detail is generically unavailable to only the reporter'
);
select throws_ok(
  $$select * from public.copy_public_template(
      'e2000000-0000-4000-8000-000000000001',
      5,
      'e5000000-0000-4000-8000-000000000010'
    )$$,
  'P0002',
  'template unavailable',
  'the reporter cannot copy the reported source'
);

reset role;
select is(
  (
    select reported_snapshot
    from private.public_template_report_groups
    where id = (
      select value_uuid_two
      from moderation_values
      where label = 'primary-report'
    )
  ),
  jsonb_build_object(
    'name',
    'Reported trip kit',
    'items',
    jsonb_build_array(
      jsonb_build_object('name', 'Water', 'quantity_thousandths', 1500),
      jsonb_build_object('name', 'Water', 'quantity_thousandths', 2000)
    )
  ),
  'the immutable snapshot contains only ordered public name and quantities'
);
select is(
  (
    select explanation
    from private.public_template_reports
    where id = (
      select value_uuid
      from moderation_values
      where label = 'primary-report'
    )
  ),
  'Explain this exact issue.',
  'the server trims report explanation whitespace'
);
select is(
  (
    select pg_catalog.octet_length(content_fingerprint)
    from private.public_template_reports
    where id = (
      select value_uuid
      from moderation_values
      where label = 'primary-report'
    )
  ),
  32,
  'the server creates a deterministic SHA-256 evidence fingerprint'
);
select is(
  (
    select reported_snapshot ? 'category_id'
      or reported_snapshot::text like '%Private secret category%'
    from private.public_template_report_groups
    where id = (
      select value_uuid_two
      from moderation_values
      where label = 'primary-report'
    )
  ),
  false,
  'the report snapshot excludes the private category'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000003';
select ok(
  public.get_public_template(
    'e1000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000001'
  ) is not null,
  'another caller retains public access after someone reports'
);
select is(
  (
    select report_result.report_group_id
    from public.report_public_template(
      'e2000000-0000-4000-8000-000000000001',
      5,
      'spam_scam_deceptive',
      null
    ) as report_result
  ),
  (
    select value_uuid_two
    from moderation_values
    where label = 'primary-report'
  ),
  'same-revision evidence groups without losing individual reports'
);

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000001',
      5,
      'spam_scam_deceptive',
      null
    )$$,
  'P0002',
  'template unavailable',
  'an owner cannot report their own template'
);

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000006';
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000002',
      2,
      'spam_scam_deceptive',
      null
    )$$,
  'P0002',
  'template unavailable',
  'a blocked caller cannot report inaccessible content'
);

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000004';
select is(
  public.is_public_template_moderator(),
  true,
  'the protected self-check recognizes the exact allowlisted UUID'
);
insert into moderation_values (label, value_json)
values (
  'open-queue',
  public.list_public_template_moderation_queue(
    'open',
    20,
    null,
    null
  )
);
select is(
  (
    select value_json -> 'cases' -> 0 ->> 'template_name'
    from moderation_values
    where label = 'open-queue'
  ),
  'Reported trip kit',
  'the open queue exposes the oldest grouped report'
);
select is(
  (
    select (value_json -> 'cases' -> 0 ->> 'report_count')::bigint
    from moderation_values
    where label = 'open-queue'
  ),
  2::bigint,
  'the queue reports the retained individual report count'
);

insert into moderation_values (label, value_json)
select
  'primary-case',
  public.get_public_template_moderation_case(value_uuid_two)
from moderation_values
where label = 'primary-report';

select is(
  (
    select pg_catalog.jsonb_array_length(
      value_json -> 'reports'
    )
    from moderation_values
    where label = 'primary-case'
  ),
  2,
  'moderator detail returns each individual report'
);
select is(
  (
    select value_json::text like '%Private secret category%'
      or value_json::text like '%@example.test%'
    from moderation_values
    where label = 'primary-case'
  ),
  false,
  'moderator detail excludes private category and email data'
);

select throws_ok(
  $$select public.moderate_public_template_report_group(
      (
        select value_uuid_two
        from moderation_values
        where label = 'primary-report'
      ),
      'dismiss',
      1,
      null,
      null,
      '   ',
      'e5000000-0000-4000-8000-000000000020'
    )$$,
  '22023',
  'invalid moderation action',
  'moderator notes are required'
);

insert into moderation_values (label, value_json)
select
  'dismiss-result',
  public.moderate_public_template_report_group(
    value_uuid_two,
    'dismiss',
    1,
    null,
    null,
    'Reviewed against the policy.',
    'e5000000-0000-4000-8000-000000000021'
  )
from moderation_values
where label = 'primary-report';

select is(
  (
    select value_json ->> 'action'
    from moderation_values
    where label = 'dismiss-result'
  ),
  'dismiss',
  'dismiss closes only the selected group'
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where public_template_id =
      'e2000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'dismiss creates no owner or reporter notification'
);

select private.revoke_public_template_moderator(
  'e1000000-0000-4000-8000-000000000004',
  'local-pgtap',
  'e5000000-0000-4000-8000-000000000002'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_moderator_access_events
    where moderator_id = 'e1000000-0000-4000-8000-000000000004'
  ),
  2::bigint,
  'grant and revoke access changes are both audited'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000004';
select is(
  public.is_public_template_moderator(),
  false,
  'revocation immediately changes the self-check'
);
select throws_ok(
  $$select public.list_public_template_moderation_queue(
      'open',
      20,
      null,
      null
    )$$,
  '42501',
  'moderator access required',
  'revocation immediately blocks queue execution'
);

reset role;
select private.grant_public_template_moderator(
  'e1000000-0000-4000-8000-000000000004',
  'local-pgtap',
  'e5000000-0000-4000-8000-000000000003'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000002';
insert into moderation_values (
  label,
  value_uuid,
  value_uuid_two,
  value_bigint
)
select
  'delete-report',
  report_result.report_id,
  report_result.report_group_id,
  report_result.reported_revision
from public.report_public_template(
  'e2000000-0000-4000-8000-000000000004',
  3,
  'personal_confidential_information',
  null
) as report_result;

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
select public.delete_private_template(
  'e2000000-0000-4000-8000-000000000004',
  3
);

reset role;
select is(
  (
    select status
    from private.public_template_report_groups
    where id = (
      select value_uuid_two
      from moderation_values
      where label = 'delete-report'
    )
  ),
  'content_deleted',
  'source deletion closes open evidence as content deleted'
);
select ok(
  (
    select source_deleted_at is not null
    from private.public_template_report_groups
    where id = (
      select value_uuid_two
      from moderation_values
      where label = 'delete-report'
    )
  ),
  'source deletion preserves an explicit lifecycle timestamp'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000002';
insert into moderation_values (
  label,
  value_uuid,
  value_uuid_two,
  value_bigint
)
select
  'takedown-report',
  report_result.report_id,
  report_result.report_group_id,
  report_result.reported_revision
from public.report_public_template(
  'e2000000-0000-4000-8000-000000000005',
  4,
  'illegal_regulated',
  null
) as report_result;

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000004';
insert into moderation_values (label, value_json)
select
  'takedown-result',
  public.moderate_public_template_report_group(
    value_uuid_two,
    'take_down',
    1,
    4,
    'illegal_regulated',
    'Confirmed against the moderation policy.',
    'e5000000-0000-4000-8000-000000000030'
  )
from moderation_values
where label = 'takedown-report';

select is(
  (
    select value_json ->> 'action'
    from moderation_values
    where label = 'takedown-result'
  ),
  'take_down',
  'takedown records the reviewed action'
);
select is(
  (
    select (value_json ->> 'template_version')::bigint
    from moderation_values
    where label = 'takedown-result'
  ),
  5::bigint,
  'takedown advances the source version exactly once'
);
select is(
  (
    public.moderate_public_template_report_group(
      (
        select value_uuid_two
        from moderation_values
        where label = 'takedown-report'
      ),
      'take_down',
      1,
      4,
      'illegal_regulated',
      'Confirmed against the moderation policy.',
      'e5000000-0000-4000-8000-000000000030'
    ) ->> 'event_id'
  ),
  (
    select value_json ->> 'event_id'
    from moderation_values
    where label = 'takedown-result'
  ),
  'a lost-response takedown retry returns the original decision'
);

reset role;
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_moderation_events
    where template_id = 'e2000000-0000-4000-8000-000000000005'
      and action = 'take_down'
  ),
  1::bigint,
  'takedown retry creates one immutable decision'
);
select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where public_template_id =
      'e2000000-0000-4000-8000-000000000005'
      and notification_type = 'public_template_taken_down'
  ),
  1::bigint,
  'takedown creates exactly one owner notification'
);
select is(
  (
    select actor_id is null
      and public_template_name = 'Dismiss then report'
      and moderation_reason_code = 'illegal_regulated'
      and relationship_low_id is null
      and active_list_id is null
    from public.user_notifications
    where public_template_id =
      'e2000000-0000-4000-8000-000000000005'
      and notification_type = 'public_template_taken_down'
  ),
  true,
  'owner notification is system-authored and contains only safe moderation fields'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
select is(
  public.get_unread_notification_count_v3(),
  0::bigint,
  'a legacy v3 client does not count unsupported moderation notifications'
);
select is(
  public.get_unread_notification_count_v4(),
  1::bigint,
  'the v4 owner sees the takedown notification count'
);
select is(
  (
    select notification_type
    from public.list_notifications_v4(20, null, null)
    limit 1
  ),
  'public_template_taken_down',
  'notification v4 returns the owner-only moderation outcome'
);
select is(
  (
    select actor_profile_id is null
      and actor_username is null
      and actor_display_name is null
      and public_template_name = 'Dismiss then report'
    from public.list_notifications_v4(20, null, null)
    where notification_type = 'public_template_taken_down'
  ),
  true,
  'notification v4 exposes no reporter or moderator actor'
);
select throws_ok(
  $$select * from public.set_template_publication(
      'e2000000-0000-4000-8000-000000000005',
      true,
      5
    )$$,
  '42501',
  'template unavailable',
  'an active takedown prevents owner republishing'
);
select ok(
  (
    select is_moderated
    from public.get_private_template_v3(
      'e2000000-0000-4000-8000-000000000005'
    )
  ),
  'owner template v3 exposes a text-capable moderation state'
);

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000003';
select is(
  public.get_public_template(
    'e1000000-0000-4000-8000-000000000001',
    'e2000000-0000-4000-8000-000000000005'
  ),
  null::jsonb,
  'takedown makes public detail generically unavailable to others'
);
select throws_ok(
  $$select * from public.copy_public_template(
      'e2000000-0000-4000-8000-000000000005',
      5,
      'e5000000-0000-4000-8000-000000000031'
    )$$,
  'P0002',
  'template unavailable',
  'takedown prevents public copying'
);
select throws_ok(
  $$select public.report_public_template(
      'e2000000-0000-4000-8000-000000000005',
      5,
      'spam_scam_deceptive',
      null
    )$$,
  'P0002',
  'template unavailable',
  'moderated content cannot be newly reported'
);

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000004';
insert into moderation_values (label, value_json)
select
  'restore-result',
  public.restore_public_template_moderation(
    'e2000000-0000-4000-8000-000000000005',
    (value_json ->> 'restriction_version')::bigint,
    (value_json ->> 'template_version')::bigint,
    'Restriction reviewed and lifted.',
    'e5000000-0000-4000-8000-000000000032'
  )
from moderation_values
where label = 'takedown-result';

select is(
  (
    select value_json ->> 'action'
    from moderation_values
    where label = 'restore-result'
  ),
  'restore',
  'restore records an immutable decision'
);
select is(
  (
    public.restore_public_template_moderation(
      'e2000000-0000-4000-8000-000000000005',
      (
        select (value_json ->> 'restriction_version')::bigint
        from moderation_values
        where label = 'takedown-result'
      ),
      (
        select (value_json ->> 'template_version')::bigint
        from moderation_values
        where label = 'takedown-result'
      ),
      'Restriction reviewed and lifted.',
      'e5000000-0000-4000-8000-000000000032'
    ) ->> 'event_id'
  ),
  (
    select value_json ->> 'event_id'
    from moderation_values
    where label = 'restore-result'
  ),
  'a lost-response restoration retry returns the original decision'
);

reset role;
select is(
  (
    select published_at
    from public.templates
    where id = 'e2000000-0000-4000-8000-000000000005'
  ),
  null::timestamptz,
  'restoration never republishes automatically'
);
select is(
  (
    select active
    from private.public_template_moderation_restrictions
    where template_id = 'e2000000-0000-4000-8000-000000000005'
  ),
  false,
  'restoration deactivates the template restriction'
);
select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications
    where public_template_id =
      'e2000000-0000-4000-8000-000000000005'
      and notification_type = 'public_template_restored'
  ),
  1::bigint,
  'restoration creates exactly one owner notification'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
select is(
  (
    select publication.is_public
    from public.set_template_publication(
      'e2000000-0000-4000-8000-000000000005',
      true,
      6
    ) as publication
  ),
  true,
  'the owner may explicitly publish after restoration'
);

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000002';
select is(
  (
    public.export_own_account_data_v10()
      ->> 'schema_version'
  )::integer,
  10,
  'account export advances to schema version 10'
);
select is(
  (
    select pg_catalog.jsonb_object_keys(
      public.export_own_account_data_v10()
        -> 'submitted_public_template_reports' -> 0
    )
    order by 1
    limit 1
  ),
  'explanation',
  'submitted report export begins with an approved field'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.jsonb_object_keys(
      public.export_own_account_data_v10()
        -> 'submitted_public_template_reports' -> 0
    )
  ),
  3::bigint,
  'submitted report export contains exactly reason, explanation, and date'
);
select is(
  (
    public.export_own_account_data_v10()
      -> 'submitted_public_template_reports'
  )::text like '%fingerprint%'
    or (
      public.export_own_account_data_v10()
        -> 'submitted_public_template_reports'
    )::text like '%moderator%'
    or (
      public.export_own_account_data_v10()
        -> 'submitted_public_template_reports'
    )::text like '%snapshot%',
  false,
  'account export excludes internal fingerprints, snapshots, and moderation data'
);

reset role;
delete from auth.users
where id = 'e1000000-0000-4000-8000-000000000003';
select is(
  (
    select reporter_id
    from private.public_template_reports
    where template_id = 'e2000000-0000-4000-8000-000000000001'
      and reason_code = 'spam_scam_deceptive'
  ),
  null::uuid,
  'account deletion immediately anonymizes a retained reporter identity'
);

update private.public_template_report_groups
set first_reported_at = now() - interval '30 months',
    closed_at = now() - interval '25 months',
    updated_at = now() - interval '25 months'
where id = (
  select value_uuid_two
  from moderation_values
  where label = 'primary-report'
);
update private.public_template_reports
set created_at = now() - interval '30 months',
    closed_at = now() - interval '25 months'
where group_id = (
  select value_uuid_two
  from moderation_values
  where label = 'primary-report'
);
update private.public_template_moderation_events
set created_at = now() - interval '25 months'
where group_id = (
  select value_uuid_two
  from moderation_values
  where label = 'primary-report'
);

select is(
  (
    select created_tombstones
    from private.maintain_public_template_moderation_retention(now())
  ),
  1,
  'retention purges one fully closed evidence scope after 24 months'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_report_groups
    where id = (
      select value_uuid_two
      from moderation_values
      where label = 'primary-report'
    )
  ),
  0::bigint,
  'retention removes identifying snapshots and fingerprints'
);
select is(
  (
    select pg_catalog.count(*)
    from private.public_template_moderation_tombstones
    where report_count = 2
  ),
  1::bigint,
  'retention leaves one aggregate tombstone with no source identity'
);
select is(
  (
    select created_tombstones
    from private.maintain_public_template_moderation_retention(now())
  ),
  0,
  'retention maintenance is idempotent'
);
select ok(
  exists (
    select 1
    from private.public_template_report_groups
    where status = 'content_deleted'
  ),
  'recent closed evidence is retained'
);
select ok(
  not exists (
    select 1
    from pg_catalog.pg_attribute as column_record
    where column_record.attrelid =
      'private.public_template_moderation_tombstones'::regclass
      and not column_record.attisdropped
      and column_record.attname in (
        'template_id',
        'reporter_id',
        'owner_id',
        'moderator_id',
        'snapshot',
        'fingerprint',
        'explanation',
        'private_note'
      )
  ),
  'retention tombstones contain no user or content identifier columns'
);

select * from finish();
rollback;
