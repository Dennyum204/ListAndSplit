begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table(
  'public',
  'template_sends',
  'template-send parent records exist'
);
select has_table(
  'public',
  'template_send_items',
  'immutable template-send snapshot items exist'
);
select has_table(
  'private',
  'template_send_requests',
  'the private mutation retry ledger exists'
);
select columns_are(
  'public',
  'template_send_items',
  array[
    'id',
    'template_send_id',
    'name',
    'quantity_thousandths',
    'position',
    'created_at'
  ],
  'snapshot items contain only the reviewed immutable fields'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_class as table_record
    where table_record.oid in (
      'public.template_sends'::regclass,
      'public.template_send_items'::regclass,
      'private.template_send_requests'::regclass
    )
      and table_record.relrowsecurity
      and table_record.relforcerowsecurity
  ),
  3::bigint,
  'all template-send tables enable and force RLS'
);
select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies as policy_record
    where (
      policy_record.schemaname,
      policy_record.tablename
    ) in (
      ('public', 'template_sends'),
      ('public', 'template_send_items'),
      ('private', 'template_send_requests')
    )
      and policy_record.cmd = 'ALL'
      and policy_record.roles = array['anon','authenticated']::name[]
      and policy_record.qual = 'false'
      and policy_record.with_check = 'false'
  ),
  3::bigint,
  'all template-send tables explicitly reject direct clients'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.template_sends',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.template_sends',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.template_send_items',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.template_send_requests',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'API roles have no direct template-send table access'
);
select has_index(
  'public',
  'template_sends',
  'template_sends_one_pending_key',
  'one pending send is enforced for each sender/source/recipient'
);
select is(
  (
    select pg_catalog.pg_get_expr(
      index_record.indpred,
      index_record.indrelid
    )
    from pg_catalog.pg_index as index_record
    where index_record.indexrelid =
      'public.template_sends_one_pending_key'::regclass
  ),
  '(state = ''pending''::text)',
  'the duplicate-send constraint applies only while pending'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as function_record
    where function_record.oid in (
      'public.list_eligible_template_send_recipients(uuid,integer,text,uuid)'::regprocedure,
      'public.send_template_to_friend(uuid,uuid,bigint,uuid)'::regprocedure,
      'public.list_received_template_sends(text,integer,timestamptz,uuid)'::regprocedure,
      'public.list_sent_template_sends(text,integer,timestamptz,uuid)'::regprocedure,
      'public.get_received_template_send(uuid)'::regprocedure,
      'public.accept_template_send(uuid,bigint,uuid)'::regprocedure,
      'public.decline_template_send(uuid,bigint,uuid)'::regprocedure,
      'public.revoke_template_send(uuid,bigint,uuid)'::regprocedure,
      'public.list_notifications_v5(integer,timestamptz,uuid)'::regprocedure,
      'public.get_unread_notification_count_v5()'::regprocedure,
      'public.export_own_account_data_v11()'::regprocedure
    )
      and function_record.prosecdef
      and function_record.proowner = 'postgres'::regrole
      and function_record.proconfig = array['search_path=""']
  ),
  11::bigint,
  'all public template-send RPCs are hardened postgres-owned definers'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.send_template_to_friend(uuid,uuid,bigint,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.export_own_account_data_v11()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.send_template_to_friend(uuid,uuid,bigint,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.accept_template_send(uuid,bigint,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.maintain_template_send_retention(timestamptz)',
    'EXECUTE'
  ),
  'only authenticated receives the exact public RPC grants'
);

set local role anon;
select throws_like(
  $$select * from public.template_sends$$,
  '%permission denied%',
  'anonymous direct parent reads are denied'
);
select throws_like(
  $$select * from public.send_template_to_friend(
      'e2000000-0000-4000-8000-000000000001',
      'e1000000-0000-4000-8000-000000000002',
      1,
      'e5000000-0000-4000-8000-000000000001'
    )$$,
  '%permission denied%function%send_template_to_friend%',
  'anonymous send RPC execution is denied'
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
    'send-owner@example.test',
    now(),
    now(),
    now()
  ),
  (
    'e1000000-0000-4000-8000-000000000002',
    'send-friend@example.test',
    now(),
    now(),
    now()
  ),
  (
    'e1000000-0000-4000-8000-000000000003',
    'send-second@example.test',
    now(),
    now(),
    now()
  ),
  (
    'e1000000-0000-4000-8000-000000000004',
    'send-nonfriend@example.test',
    now(),
    now(),
    now()
  ),
  (
    'e1000000-0000-4000-8000-000000000005',
    'send-quota@example.test',
    now(),
    now(),
    now()
  );

update public.profiles
set username = case id
      when 'e1000000-0000-4000-8000-000000000001' then 'send_owner'
      when 'e1000000-0000-4000-8000-000000000002' then 'send_friend'
      when 'e1000000-0000-4000-8000-000000000003' then 'send_second'
      when 'e1000000-0000-4000-8000-000000000004' then 'send_nonfriend'
      when 'e1000000-0000-4000-8000-000000000005' then 'send_quota'
    end,
    display_name = case id
      when 'e1000000-0000-4000-8000-000000000001' then 'Send Owner'
      when 'e1000000-0000-4000-8000-000000000002' then 'Send Friend'
      when 'e1000000-0000-4000-8000-000000000003' then 'Send Second'
      when 'e1000000-0000-4000-8000-000000000004' then 'Send Nonfriend'
      when 'e1000000-0000-4000-8000-000000000005' then 'Send Quota'
    end;

insert into public.user_relationships (
  profile_low_id,
  profile_high_id,
  state,
  requester_id
)
values
  (
    'e1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000002',
    'friends',
    'e1000000-0000-4000-8000-000000000001'
  ),
  (
    'e1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000003',
    'friends',
    'e1000000-0000-4000-8000-000000000001'
  ),
  (
    'e1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000005',
    'friends',
    'e1000000-0000-4000-8000-000000000001'
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
    'Private trip',
    1,
    'e3000000-0000-4000-8000-000000000001',
    null
  ),
  (
    'e2000000-0000-4000-8000-000000000002',
    'e1000000-0000-4000-8000-000000000001',
    'Blank public trip',
    1,
    'e3000000-0000-4000-8000-000000000002',
    now()
  ),
  (
    'e2000000-0000-4000-8000-000000000003',
    'e1000000-0000-4000-8000-000000000001',
    'Exact capacity',
    1,
    'e3000000-0000-4000-8000-000000000003',
    null
  ),
  (
    'e2000000-0000-4000-8000-000000000004',
    'e1000000-0000-4000-8000-000000000001',
    'Moderated source',
    1,
    'e3000000-0000-4000-8000-000000000004',
    null
  ),
  (
    'e2000000-0000-4000-8000-000000000005',
    'e1000000-0000-4000-8000-000000000001',
    'Delete source',
    1,
    'e3000000-0000-4000-8000-000000000005',
    null
  ),
  (
    'e2000000-0000-4000-8000-000000000006',
    'e1000000-0000-4000-8000-000000000001',
    'Later moderated source',
    1,
    'e3000000-0000-4000-8000-000000000006',
    null
  ),
  (
    'e2000000-0000-4000-8000-000000000007',
    'e1000000-0000-4000-8000-000000000001',
    'Legacy oversized source',
    1,
    'e3000000-0000-4000-8000-000000000007',
    null
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
    'e6000000-0000-4000-8000-000000000001'
  ),
  (
    'e4000000-0000-4000-8000-000000000002',
    'e2000000-0000-4000-8000-000000000001',
    'Water',
    2000,
    2,
    'e6000000-0000-4000-8000-000000000002'
  );

insert into public.template_items (
  template_id,
  name,
  quantity_thousandths,
  position,
  creation_request_id
)
select
  'e2000000-0000-4000-8000-000000000003',
  'Capacity item ' || item_number,
  1000 + item_number,
  item_number,
  pg_catalog.gen_random_uuid()
from pg_catalog.generate_series(1, 200) as item(item_number);

insert into public.template_items (
  template_id,
  name,
  quantity_thousandths,
  position,
  creation_request_id
)
select
  'e2000000-0000-4000-8000-000000000007',
  'Legacy item ' || item_number,
  1000,
  item_number,
  pg_catalog.gen_random_uuid()
from pg_catalog.generate_series(1, 201) as item(item_number);

insert into private.public_template_moderation_restrictions (
  template_id,
  template_owner_id,
  template_name,
  reason_code,
  active,
  version,
  imposed_at,
  updated_at
)
values (
  'e2000000-0000-4000-8000-000000000004',
  'e1000000-0000-4000-8000-000000000001',
  'Moderated source',
  'other',
  true,
  1,
  now(),
  now()
);

create temporary table template_send_values (
  label text primary key,
  value_uuid uuid,
  value_uuid_2 uuid,
  value_bigint bigint,
  value_text text,
  value_json jsonb
) on commit drop;
grant select, insert, update, delete on template_send_values
to authenticated;

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';

select is(
  (
    select pg_catalog.count(*)
    from public.list_eligible_template_send_recipients(
      'e2000000-0000-4000-8000-000000000001',
      20,
      null,
      null
    )
  ),
  3::bigint,
  'eligible recipients contain current unblocked friends only'
);
select throws_ok(
  $$select * from public.list_eligible_template_send_recipients(
      'e2000000-0000-4000-8000-000000000004',
      20,
      null,
      null
    )$$,
  'P0002',
  'template unavailable',
  'actively moderated sources are unavailable for recipient discovery'
);
select throws_ok(
  $$select * from public.send_template_to_friend(
      'e2000000-0000-4000-8000-000000000001',
      'e1000000-0000-4000-8000-000000000004',
      1,
      'e5000000-0000-4000-8000-000000000001'
    )$$,
  '42501',
  'friendship required',
  'sending to a nonfriend is rejected'
);
select throws_ok(
  $$select * from public.send_template_to_friend(
      'e2000000-0000-4000-8000-000000000004',
      'e1000000-0000-4000-8000-000000000002',
      1,
      'e5000000-0000-4000-8000-000000000002'
    )$$,
  '42501',
  'template unavailable',
  'actively moderated sources cannot be sent'
);

insert into template_send_values (
  label,
  value_uuid,
  value_bigint,
  value_text
)
select
  'private-send',
  result.template_send_id,
  result.version,
  result.state
from public.send_template_to_friend(
  'e2000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000002',
  1,
  'e5000000-0000-4000-8000-000000000003'
) as result;

select is(
  (select value_text from template_send_values where label = 'private-send'),
  'pending',
  'private owned templates can be sent'
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.template_send_items as snapshot_item
    where snapshot_item.template_send_id = (
      select value_uuid
      from template_send_values
      where label = 'private-send'
    )
  ),
  2::bigint,
  'duplicate-name source items each occupy a snapshot position'
);
select results_eq(
  $$
    select snapshot_item.name, snapshot_item.quantity_thousandths
    from public.template_send_items as snapshot_item
    where snapshot_item.template_send_id = (
      select value_uuid
      from template_send_values
      where label = 'private-send'
    )
    order by snapshot_item.position
  $$,
  $$
    values ('Water'::text, 1500::bigint), ('Water'::text, 2000::bigint)
  $$,
  'the snapshot preserves only ordered names and exact quantities'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
select is(
  (
    select replay.template_send_id
    from public.send_template_to_friend(
      'e2000000-0000-4000-8000-000000000001',
      'e1000000-0000-4000-8000-000000000002',
      1,
      'e5000000-0000-4000-8000-000000000003'
    ) as replay
  ),
  (
    select value_uuid
    from template_send_values
    where label = 'private-send'
  ),
  'a lost send response replays the same invitation'
);
select throws_ok(
  $$select * from public.send_template_to_friend(
      'e2000000-0000-4000-8000-000000000002',
      'e1000000-0000-4000-8000-000000000002',
      1,
      'e5000000-0000-4000-8000-000000000003'
    )$$,
  '23505',
  'template send request identity conflict',
  'request UUID reuse with another payload is rejected'
);
select throws_ok(
  $$select * from public.send_template_to_friend(
      'e2000000-0000-4000-8000-000000000001',
      'e1000000-0000-4000-8000-000000000002',
      1,
      'e5000000-0000-4000-8000-000000000004'
    )$$,
  '23505',
  'pending template send already exists',
  'a second request cannot create a duplicate pending invitation'
);

insert into template_send_values (
  label,
  value_uuid,
  value_bigint,
  value_text
)
select
  'blank-send',
  result.template_send_id,
  result.version,
  result.state
from public.send_template_to_friend(
  'e2000000-0000-4000-8000-000000000002',
  'e1000000-0000-4000-8000-000000000003',
  1,
  'e5000000-0000-4000-8000-000000000005'
) as result;
reset role;
select is(
  (
    select snapshot_item_count
    from public.template_sends
    where id = (
      select value_uuid
      from template_send_values
      where label = 'blank-send'
    )
  ),
  0,
  'blank public templates are valid immutable offers'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
insert into template_send_values (
  label,
  value_uuid,
  value_bigint
)
select
  'capacity-send',
  result.template_send_id,
  result.version
from public.send_template_to_friend(
  'e2000000-0000-4000-8000-000000000003',
  'e1000000-0000-4000-8000-000000000003',
  1,
  'e5000000-0000-4000-8000-000000000006'
) as result;
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.template_send_items as snapshot_item
    where snapshot_item.template_send_id = (
      select value_uuid
      from template_send_values
      where label = 'capacity-send'
    )
  ),
  200::bigint,
  'exactly 200 source items are snapshotted'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select * from public.send_template_to_friend(
      'e2000000-0000-4000-8000-000000000007',
      'e1000000-0000-4000-8000-000000000002',
      1,
      'e5000000-0000-4000-8000-000000000014'
    )$$,
  '54000',
  'template exceeds send capacity',
  'legacy sources above 200 items are rejected without modification'
);
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.template_items
    where template_id = 'e2000000-0000-4000-8000-000000000007'
  ),
  201::bigint,
  'rejected legacy oversized sources remain untouched'
);

select is(
  (
    select pg_catalog.count(*)
    from public.user_notifications as notification_record
    where notification_record.template_send_id = (
      select value_uuid
      from template_send_values
      where label = 'private-send'
    )
      and notification_record.notification_type =
        'template_send_received'
  ),
  1::bigint,
  'a send creates exactly one recipient notification'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000002';
select is(
  (
    select pg_catalog.count(*)
    from public.list_notifications_v5(20, null, null)
    where notification_type = 'template_send_received'
  ),
  1::bigint,
  'notification v5 returns the new recipient notification'
);
select is(
  (
    select action_status
    from public.list_notifications_v5(20, null, null)
    where notification_type = 'template_send_received'
  ),
  'actionable',
  'notification v5 binds actionability to the exact send version'
);
select is(
  (
    select pg_catalog.count(*)
    from public.list_notifications(20, null, null)
    where notification_type = 'template_send_received'
  ) + (
    select pg_catalog.count(*)
    from public.list_notifications_v2(20, null, null)
    where notification_type = 'template_send_received'
  ) + (
    select pg_catalog.count(*)
    from public.list_notifications_v3(20, null, null)
    where notification_type = 'template_send_received'
  ) + (
    select pg_catalog.count(*)
    from public.list_notifications_v4(20, null, null)
    where notification_type = 'template_send_received'
  ),
  0::bigint,
  'notification RPCs v1-v4 remain unaware of template sends'
);
select is(
  public.get_unread_notification_count_v5()
    - public.get_unread_notification_count_v4(),
  1::bigint,
  'only notification count v5 includes the template offer'
);

insert into template_send_values (
  label,
  value_uuid,
  value_uuid_2,
  value_bigint,
  value_text
)
select
  'accepted',
  result.template_send_id,
  result.accepted_template_id,
  result.version,
  result.state
from public.accept_template_send(
  (
    select value_uuid
    from template_send_values
    where label = 'private-send'
  ),
  1,
  'e5000000-0000-4000-8000-000000000007'
) as result;

select is(
  (select value_text from template_send_values where label = 'accepted'),
  'accepted',
  'the recipient accepts a pending send'
);
reset role;
select ok(
  (
    select template_record.owner_id =
        'e1000000-0000-4000-8000-000000000002'
      and template_record.category_id is null
      and template_record.published_at is null
      and template_record.name = 'Private trip'
    from public.templates as template_record
    where template_record.id = (
      select value_uuid_2
      from template_send_values
      where label = 'accepted'
    )
  ),
  'acceptance creates one private Uncategorized recipient-owned copy'
);
select results_eq(
  $$
    select item_record.name, item_record.quantity_thousandths
    from public.template_items as item_record
    where item_record.template_id = (
      select value_uuid_2
      from template_send_values
      where label = 'accepted'
    )
    order by item_record.position
  $$,
  $$
    values ('Water'::text, 1500::bigint), ('Water'::text, 2000::bigint)
  $$,
  'the accepted copy is independent and exact'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000002';
select is(
  (
    select replay.accepted_template_id
    from public.accept_template_send(
      (
        select value_uuid
        from template_send_values
        where label = 'private-send'
      ),
      1,
      'e5000000-0000-4000-8000-000000000007'
    ) as replay
  ),
  (
    select value_uuid_2
    from template_send_values
    where label = 'accepted'
  ),
  'repeated Accept returns the same copy and creates no duplicate'
);

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
select ok(
  not (
    select to_jsonb(sent_projection) ? 'accepted_template_id'
    from public.list_sent_template_sends('history', 20, null, null)
      as sent_projection
    where sent_projection.template_send_id = (
      select value_uuid
      from template_send_values
      where label = 'accepted'
    )
  ),
  'the sender projection never exposes the recipient copy identifier'
);

insert into template_send_values (label, value_uuid, value_bigint)
select 'delete-send', result.template_send_id, result.version
from public.send_template_to_friend(
  'e2000000-0000-4000-8000-000000000005',
  'e1000000-0000-4000-8000-000000000002',
  1,
  'e5000000-0000-4000-8000-000000000008'
) as result;
select public.delete_private_template(
  'e2000000-0000-4000-8000-000000000005',
  1
);
reset role;
select ok(
  (
    select state = 'unavailable' and source_template_id is null
    from public.template_sends
    where id = (
      select value_uuid
      from template_send_values
      where label = 'delete-send'
    )
  ),
  'source deletion closes pending sends without deleting history'
);
select ok(
  exists (
    select 1
    from public.templates
    where id = (
      select value_uuid_2
      from template_send_values
      where label = 'accepted'
    )
  ),
  'source deletion does not affect a previously accepted copy'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
insert into template_send_values (label, value_uuid, value_bigint)
select 'decline-send', result.template_send_id, result.version
from public.send_template_to_friend(
  'e2000000-0000-4000-8000-000000000002',
  'e1000000-0000-4000-8000-000000000002',
  1,
  'e5000000-0000-4000-8000-000000000009'
) as result;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000002';
select is(
  (
    select result.state
    from public.decline_template_send(
      (
        select value_uuid
        from template_send_values
        where label = 'decline-send'
      ),
      1,
      'e5000000-0000-4000-8000-000000000010'
    ) as result
  ),
  'declined',
  'only the recipient can decline a pending invitation'
);

set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
insert into template_send_values (label, value_uuid, value_bigint)
select 'revoke-send', result.template_send_id, result.version
from public.send_template_to_friend(
  'e2000000-0000-4000-8000-000000000002',
  'e1000000-0000-4000-8000-000000000002',
  1,
  'e5000000-0000-4000-8000-000000000011'
) as result;
select is(
  (
    select result.state
    from public.revoke_template_send(
      (
        select value_uuid
        from template_send_values
        where label = 'revoke-send'
      ),
      1,
      'e5000000-0000-4000-8000-000000000012'
    ) as result
  ),
  'revoked',
  'only the sender can revoke a pending invitation'
);

insert into template_send_values (label, value_uuid, value_bigint)
select 'moderation-send', result.template_send_id, result.version
from public.send_template_to_friend(
  'e2000000-0000-4000-8000-000000000006',
  'e1000000-0000-4000-8000-000000000002',
  1,
  'e5000000-0000-4000-8000-000000000015'
) as result;
reset role;
insert into private.public_template_moderation_restrictions (
  template_id,
  template_owner_id,
  template_name,
  reason_code,
  active,
  version,
  imposed_at,
  updated_at
)
values (
  'e2000000-0000-4000-8000-000000000006',
  'e1000000-0000-4000-8000-000000000001',
  'Later moderated source',
  'other',
  true,
  1,
  now(),
  now()
);
select ok(
  (
    select state = 'unavailable' and suppressed_at is not null
    from public.template_sends
    where id = (
      select value_uuid
      from template_send_values
      where label = 'moderation-send'
    )
  ),
  'a new active moderation restriction closes and hides pending sends'
);
select ok(
  (
    select suppressed_at is not null
    from public.user_notifications
    where template_send_id = (
      select value_uuid
      from template_send_values
      where label = 'moderation-send'
    )
  ),
  'moderation also suppresses the recipient notification'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
insert into template_send_values (label, value_uuid, value_bigint)
select 'quota-send', result.template_send_id, result.version
from public.send_template_to_friend(
  'e2000000-0000-4000-8000-000000000002',
  'e1000000-0000-4000-8000-000000000005',
  1,
  'e5000000-0000-4000-8000-000000000016'
) as result;
reset role;
insert into public.templates (
  owner_id,
  name,
  creation_request_id
)
select
  'e1000000-0000-4000-8000-000000000005',
  'Quota template ' || template_number,
  pg_catalog.gen_random_uuid()
from pg_catalog.generate_series(1, 100)
  as fixture(template_number);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000005';
select throws_ok(
  format(
    'select * from public.accept_template_send(%L, 1, %L)',
    (
      select value_uuid
      from template_send_values
      where label = 'quota-send'
    ),
    'e5000000-0000-4000-8000-000000000017'
  ),
  '54000',
  'template capacity reached',
  'recipient capacity failure rejects acceptance atomically'
);
reset role;
select ok(
  (
    select state = 'pending'
      and version = 1
      and accepted_template_id is null
    from public.template_sends
    where id = (
      select value_uuid
      from template_send_values
      where label = 'quota-send'
    )
  )
  and (
    select pg_catalog.count(*) = 100
    from public.templates
    where owner_id = 'e1000000-0000-4000-8000-000000000005'
  ),
  'capacity failure leaves the invitation pending with no partial copy'
);
set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000005';
select public.block_profile(
  'e1000000-0000-4000-8000-000000000001'
);
reset role;
select ok(
  (
    select state = 'unavailable' and suppressed_at is not null
    from public.template_sends
    where id = (
      select value_uuid
      from template_send_values
      where label = 'quota-send'
    )
  ),
  'either-direction blocking closes and permanently hides pending sends'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
insert into template_send_values (label, value_uuid, value_bigint)
select 'friendship-loss-send', result.template_send_id, result.version
from public.send_template_to_friend(
  'e2000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000003',
  1,
  'e5000000-0000-4000-8000-000000000013'
) as result;
reset role;
update public.user_relationships
set state = 'ended',
    reopen_by_id = 'e1000000-0000-4000-8000-000000000001',
    version = version + 1,
    state_changed_at = now()
where profile_low_id = 'e1000000-0000-4000-8000-000000000001'
  and profile_high_id = 'e1000000-0000-4000-8000-000000000003';
select ok(
  (
    select state = 'unavailable' and suppressed_at is not null
    from public.template_sends
    where id = (
      select value_uuid
      from template_send_values
      where label = 'friendship-loss-send'
    )
  ),
  'friendship loss closes pending sends and permanently suppresses pair history'
);
update public.user_relationships
set state = 'friends',
    reopen_by_id = null,
    version = version + 1,
    state_changed_at = now()
where profile_low_id = 'e1000000-0000-4000-8000-000000000001'
  and profile_high_id = 'e1000000-0000-4000-8000-000000000003';
set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000003';
select is(
  (
    select pg_catalog.count(*)
    from public.list_received_template_sends('history', 50, null, null)
    where template_send_id = (
      select value_uuid
      from template_send_values
      where label = 'friendship-loss-send'
    )
  ),
  0::bigint,
  'refriending never restores hidden pair history'
);

reset role;

insert into public.template_sends (
  id,
  sender_id,
  recipient_id,
  source_template_id,
  snapshot_name,
  snapshot_item_count,
  state,
  version,
  state_changed_at,
  created_at,
  updated_at
)
values
  (
    'e7000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000002',
    null,
    'Old terminal',
    0,
    'declined',
    2,
    now() - interval '181 days',
    now() - interval '182 days',
    now() - interval '181 days'
  ),
  (
    'e7000000-0000-4000-8000-000000000002',
    'e1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000002',
    'e2000000-0000-4000-8000-000000000002',
    'Old pending',
    0,
    'pending',
    1,
    now() - interval '181 days',
    now() - interval '182 days',
    now() - interval '181 days'
  );
select is(
  private.maintain_template_send_retention(now()),
  1::bigint,
  'retention removes only terminal history older than 180 days'
);
select is(
  private.maintain_template_send_retention(now()),
  0::bigint,
  'template-send retention is idempotent'
);
select ok(
  exists (
    select 1
    from public.template_sends
    where id = 'e7000000-0000-4000-8000-000000000002'
      and state = 'pending'
  ),
  'pending invitations never expire through retention'
);
select is(
  (
    select pg_catalog.count(*)
    from cron.job
    where command like '%maintain_template_send_retention%'
  ),
  0::bigint,
  'template-send retention is intentionally unscheduled'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  'e1000000-0000-4000-8000-000000000001';
select is(
  (public.export_own_account_data_v11() ->> 'schema_version')::integer,
  11,
  'account export advances to schema v11'
);
select ok(
  public.export_own_account_data_v11() ? 'sent_template_offers'
  and public.export_own_account_data_v11() ?
    'received_template_offers',
  'export v11 adds both role-specific offer projections'
);
select ok(
  not (
    public.export_own_account_data_v11()
      -> 'sent_template_offers'
      -> 0
  ) ? 'accepted_template_id'
  and not (
    public.export_own_account_data_v11()
      -> 'sent_template_offers'
      -> 0
  ) ? 'source_template_id',
  'sender export contains no source or accepted-copy provenance'
);
select is(
  (public.export_own_account_data_v10() ->> 'schema_version')::integer,
  10,
  'export v10 remains unchanged and callable'
);
select is(
  (public.export_own_account_data() ->> 'schema_version')::integer,
  6,
  'the legacy v1-v6 export entrypoint remains unchanged and callable'
);
reset role;

delete from auth.users
where id = 'e1000000-0000-4000-8000-000000000001';
select is(
  (
    select pg_catalog.count(*)
    from public.template_sends
    where sender_id = 'e1000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'sender account deletion cascades its offer history'
);
select ok(
  exists (
    select 1
    from public.templates
    where id = (
      select value_uuid_2
      from template_send_values
      where label = 'accepted'
    )
      and owner_id = 'e1000000-0000-4000-8000-000000000002'
  ),
  'sender account deletion preserves the recipient-owned accepted copy'
);

select * from finish();
rollback;
