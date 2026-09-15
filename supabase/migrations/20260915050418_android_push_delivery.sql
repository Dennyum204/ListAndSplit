begin;

-- Operational delivery state only. No historical backfill and no HTTP in
-- business transactions. All client access is through exact authenticated RPCs.
create table private.push_devices (
  id uuid primary key default gen_random_uuid(),
  installation_hash bytea not null unique,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid not null references auth.sessions(id) on delete cascade,
  binding_id uuid not null,
  token text not null unique check (char_length(token) between 20 and 4096),
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
create index push_devices_profile on private.push_devices(profile_id);
create index push_devices_session on private.push_devices(session_id);
create table private.push_deliveries (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references private.push_devices(id) on delete cascade,
  binding_id uuid not null,
  notification_id uuid references public.user_notifications(id) on delete cascade,
  message_id uuid references public.active_list_chat_messages(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  status text not null default 'pending' check(status in ('pending','sent','discarded','failed')),
  attempts integer not null default 0 check(attempts between 0 and 4),
  next_attempt_at timestamptz not null default now(),
  lease_id uuid,
  lease_until timestamptz,
  check ((notification_id is null) <> (message_id is null)),
  unique(device_id, notification_id),
  unique(device_id, message_id)
);
create index push_deliveries_due on private.push_deliveries(next_attempt_at) where status = 'pending';
create index push_deliveries_notification on private.push_deliveries(notification_id);
create index push_deliveries_message on private.push_deliveries(message_id);
create index push_deliveries_expiry on private.push_deliveries(expires_at);
alter table private.push_devices enable row level security;
alter table private.push_devices force row level security;
alter table private.push_deliveries enable row level security;
alter table private.push_deliveries force row level security;
create policy push_devices_reject on private.push_devices as restrictive for all to public using(false) with check(false);
create policy push_deliveries_reject on private.push_deliveries as restrictive for all to public using(false) with check(false);
revoke all on private.push_devices, private.push_deliveries from public, anon, authenticated, service_role;

create function public.register_push_device(
  installation_key uuid, binding_id uuid, device_token text,
  expected_account_id uuid, enable_delivery boolean default true
) returns void language plpgsql security definer set search_path = '' as $$
declare
  caller uuid := private.require_verified_friendship_caller();
  current_session uuid := (auth.jwt()->>'session_id')::uuid;
  installation bytea;
  existing private.push_devices;
begin
  if expected_account_id is distinct from caller or installation_key is null
    or binding_id is null or enable_delivery is null then
    raise exception using errcode = '22023', message = 'invalid device registration';
  end if;
  if not exists(select 1 from auth.sessions s where s.id = current_session and s.user_id = caller) then
    raise exception using errcode = '42501', message = 'session unavailable';
  end if;
  installation := extensions.digest(installation_key::text, 'sha256');
  -- Serialize the per-account device cap before taking installation/child locks.
  perform private.lock_active_list_item_assignee_profiles(array[caller]);
  -- The random installation capability is never returned or included in a push.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(installation_key::text, 711));
  select d.* into existing from private.push_devices d where d.installation_hash = installation for update;
  if not enable_delivery then
    delete from private.push_devices d where d.installation_hash = installation and d.profile_id = caller;
    return;
  end if;
  if device_token is null or char_length(device_token) not between 20 and 4096
    or device_token ~ '[[:space:][:cntrl:]]' then
    raise exception using errcode = '22023', message = 'invalid device token';
  end if;
  if (existing.id is null or existing.profile_id <> caller) and
    (select count(*) from private.push_devices d where d.profile_id = caller) >= 10 then
    raise exception using errcode = '54000', message = 'device limit reached';
  end if;
  if existing.id is not null and (existing.binding_id <> register_push_device.binding_id
      or existing.profile_id <> caller or existing.session_id <> current_session) then
    delete from private.push_deliveries where device_id = existing.id;
  end if;
  insert into private.push_devices(installation_hash, profile_id, session_id, binding_id, token)
  values(installation, caller, current_session, register_push_device.binding_id, device_token)
  on conflict(installation_hash) do update set profile_id = excluded.profile_id,
    session_id = excluded.session_id, binding_id = excluded.binding_id,
    token = excluded.token, enabled = true, updated_at = now();
exception when unique_violation then
  raise exception using errcode = 'PT409', message = 'device binding conflict';
end;
$$;

create function private.push_notification_visible(n public.user_notifications, recipient uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select n.recipient_id = recipient and n.suppressed_at is null and n.read_at is null
    and n.expires_at > now() and n.actor_id is distinct from recipient
    and (n.actor_id is null or not exists(select 1 from public.user_blocks b
      where (b.blocker_id = recipient and b.blocked_id = n.actor_id)
         or (b.blocker_id = n.actor_id and b.blocked_id = recipient)))
    and case n.notification_type
      when 'friend_request' then exists(select 1 from public.user_relationships r
        where r.profile_low_id = n.relationship_low_id and r.profile_high_id = n.relationship_high_id
          and r.state = 'pending' and r.version = n.relationship_version and r.requester_id = n.actor_id)
      when 'list_invitation' then exists(select 1 from public.active_list_participants p
        join public.active_lists l on l.id = p.list_id
        where p.list_id = n.active_list_id and p.participant_profile_id = recipient
          and p.state = 'pending' and p.version = n.access_version and l.status = 'active')
      when 'list_ownership_transferred' then exists(select 1 from public.active_lists l
        where l.id = n.active_list_id and l.owner_id = recipient)
      when 'list_item_assigned' then private.active_list_caller_is_member(n.active_list_id, recipient)
        and exists(select 1 from public.active_list_items i where i.id = n.active_list_item_id)
      when 'list_note_mentioned' then private.active_list_caller_is_member(n.active_list_id, recipient)
        and private.active_list_caller_is_member(n.active_list_id, n.actor_id)
      when 'template_send_received' then exists(select 1 from public.template_sends s
        where s.id = n.template_send_id and s.recipient_id = recipient and s.state = 'pending'
          and s.version = n.template_send_version and s.suppressed_at is null
          and private.template_send_pair_is_eligible(s.sender_id, recipient))
      when 'public_template_taken_down' then true
      when 'public_template_restored' then true
      else false end;
$$;

-- Rotation is a narrow capability, minted only by authenticated registration.
-- It needs all three unexposed values, a live original Auth session and a live
-- registration. It cannot enroll a device, change an account/binding or renew
-- expiry. This lets Android refresh FCM while the Flutter engine is stopped.
create function public.rotate_push_token(installation_key uuid, expected_binding_id uuid,
  previous_token text, replacement_token text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare updated uuid;
begin
  if installation_key is null or expected_binding_id is null or previous_token is null
    or replacement_token is null or char_length(replacement_token) not between 20 and 4096
    or char_length(previous_token) not between 20 and 4096
    or replacement_token ~ '[[:space:][:cntrl:]]' then return false; end if;
  update private.push_devices d set token = replacement_token
    where d.installation_hash = extensions.digest(installation_key::text,'sha256')
      and d.binding_id = expected_binding_id and d.token = previous_token and d.enabled
      and d.updated_at > now() - interval '30 days'
      and exists(select 1 from auth.sessions s where s.id = d.session_id and s.user_id = d.profile_id
        and (s.not_after is null or s.not_after > now())) returning d.id into updated;
  return updated is not null;
exception when unique_violation then return false;
end;
$$;

create function private.push_delivery_visible(delivery private.push_deliveries)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from private.push_devices d
    join auth.sessions s on s.id = d.session_id and s.user_id = d.profile_id
    join public.profiles p on p.id = d.profile_id and p.onboarding_completed_at is not null
    where d.id = delivery.device_id and d.binding_id = delivery.binding_id and d.enabled
      and d.updated_at > now() - interval '30 days' and delivery.expires_at > now()
      and (exists(select 1 from public.user_notifications n
          where n.id = delivery.notification_id and private.push_notification_visible(n, d.profile_id))
        or exists(select 1 from public.active_list_chat_messages m
          join public.active_list_chat_states cs on cs.list_id = m.list_id and cs.profile_id = d.profile_id
          join public.active_lists l on l.id = m.list_id and l.status = 'active'
          where m.id = delivery.message_id and m.deleted_at is null
            and m.sender_profile_id <> d.profile_id
            and m.message_position > greatest(cs.visible_after_message_position, cs.last_read_message_position)
            and private.active_list_caller_is_member(m.list_id, d.profile_id)
            and private.active_list_caller_is_member(m.list_id, m.sender_profile_id)
            and not exists(select 1 from public.user_blocks b
              where (b.blocker_id = d.profile_id and b.blocked_id = m.sender_profile_id)
                 or (b.blocker_id = m.sender_profile_id and b.blocked_id = d.profile_id)))));
$$;

create function private.enqueue_push_delivery() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- A bounded overflow may lose a push hint; never the business action or bell.
  if (select count(*) from private.push_deliveries) >= 10000 then return new; end if;
  if tg_table_name = 'user_notifications' then
    insert into private.push_deliveries(device_id, binding_id, notification_id)
    select d.id, d.binding_id, new.id from private.push_devices d
    where d.profile_id = new.recipient_id and d.enabled and d.updated_at > now() - interval '30 days'
      and private.push_notification_visible(new, d.profile_id)
    on conflict do nothing;
  else
    insert into private.push_deliveries(device_id, binding_id, message_id)
    select d.id, d.binding_id, new.id from private.push_devices d
    join public.active_list_chat_states cs on cs.profile_id = d.profile_id and cs.list_id = new.list_id
    where d.profile_id <> new.sender_profile_id and d.enabled and d.updated_at > now() - interval '30 days'
      and new.message_position > greatest(cs.visible_after_message_position, cs.last_read_message_position)
      and private.active_list_caller_is_member(new.list_id, d.profile_id)
    on conflict do nothing;
  end if;
  return new;
exception when others then
  -- No content, tokens or identities in diagnostics. The subtransaction rolls
  -- back only delivery work. Dispatch/registration failures never abort a send.
  raise log 'push enqueue failed (SQLSTATE %)', sqlstate;
  return new;
end;
$$;
create trigger enqueue_notification_push after insert on public.user_notifications
  for each row execute function private.enqueue_push_delivery();
create trigger enqueue_chat_push after insert on public.active_list_chat_messages
  for each row execute function private.enqueue_push_delivery();

create function public.claim_push_deliveries(batch_size integer default 20)
returns table(delivery_id uuid, delivery_lease uuid)
language plpgsql security definer set search_path = '' as $$
begin
  if batch_size is null or batch_size not between 1 and 20 then
    raise exception using errcode = '22023', message = 'invalid push batch';
  end if;
  -- Exact bounded operational cleanup, never application content.
  delete from private.push_deliveries where id in
    (select id from private.push_deliveries where expires_at <= now() order by expires_at limit 5000);
  delete from private.push_devices where id in
    (select id from private.push_devices where updated_at < now() - interval '30 days' limit 100);
  return query with due as (
    select p.id from private.push_deliveries p where p.status = 'pending' and p.attempts < 4
      and p.expires_at > now() and p.next_attempt_at <= now()
      and (p.lease_until is null or p.lease_until <= now())
    order by p.next_attempt_at, p.id for update skip locked limit batch_size
  ) update private.push_deliveries p set attempts = attempts + 1,
      lease_id = gen_random_uuid(), lease_until = now() + interval '2 minutes'
    from due where p.id = due.id returning p.id, p.lease_id;
end;
$$;

create function public.prepare_push_delivery(target_delivery_id uuid, delivery_lease uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p private.push_deliveries; d private.push_devices; list_id uuid;
begin
  select * into p from private.push_deliveries where id = target_delivery_id for update;
  if not found or p.status <> 'pending' or p.lease_id is distinct from delivery_lease
      or p.lease_until <= now() then return null; end if;
  if not private.push_delivery_visible(p) then
    update private.push_deliveries set status = 'discarded', lease_id = null, lease_until = null where id = p.id;
    return null;
  end if;
  select * into d from private.push_devices where id = p.device_id;
  if p.message_id is not null then
    select m.list_id into list_id from public.active_list_chat_messages m where m.id = p.message_id;
  end if;
  return jsonb_build_object('delivery_id',p.id,'binding_id',d.binding_id,'recipient_id',d.profile_id,
    'token',d.token,'kind',case when p.message_id is null then 'notification' else 'chat' end,
    'list_id',list_id,'expires_at',p.expires_at);
end;
$$;

create function public.finish_push_delivery(target_delivery_id uuid, delivery_lease uuid,
  outcome text, token_hash text default null, retry_after_seconds integer default 60)
returns void language plpgsql security definer set search_path = '' as $$
declare p private.push_deliveries;
begin
  if outcome is null or outcome not in ('sent','retry','invalid','discarded')
    or retry_after_seconds is null or retry_after_seconds not between 60 and 900 then
    raise exception using errcode = '22023', message = 'invalid push result';
  end if;
  select * into p from private.push_deliveries where id = target_delivery_id for update;
  if not found or p.status <> 'pending' or p.lease_id is distinct from delivery_lease
      or p.lease_until <= now() then return; end if;
  if outcome = 'invalid' then
    update private.push_devices d set enabled = false where d.id = p.device_id
      and d.binding_id = p.binding_id and encode(extensions.digest(d.token,'sha256'),'hex') = token_hash;
  end if;
  update private.push_deliveries set status = case
      when outcome = 'sent' then 'sent' when outcome = 'retry' and p.attempts < 4 then 'pending'
      when outcome = 'retry' then 'failed' else 'discarded' end,
    next_attempt_at = now() + make_interval(secs => greatest(retry_after_seconds, 60 * (2 ^ (p.attempts - 1))::integer)),
    lease_id = null, lease_until = null where id = p.id;
end;
$$;

create function public.resolve_push_destination(target_delivery_id uuid, expected_binding_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare caller uuid := private.require_verified_friendship_caller(); p private.push_deliveries; list_id uuid;
begin
  select q.* into p from private.push_deliveries q join private.push_devices d on d.id = q.device_id
    where q.id = target_delivery_id and d.profile_id = caller and d.binding_id = expected_binding_id
      and q.binding_id = d.binding_id;
  if not found then return null; end if;
  -- A read hint can already have cleared unread state. Opening the destination
  -- still independently rechecks access; expired/deleted delivery goes nowhere.
  if p.expires_at <= now() then return null; end if;
  if p.message_id is not null then
    select m.list_id into list_id from public.active_list_chat_messages m
      join public.active_list_chat_states cs on cs.list_id = m.list_id and cs.profile_id = caller
      where m.id = p.message_id and m.deleted_at is null and m.message_position > cs.visible_after_message_position
        and private.active_list_caller_is_member(m.list_id, caller);
    if list_id is null then return null; end if;
    return jsonb_build_object('kind','chat','list_id',list_id);
  end if;
  if not exists(select 1 from public.user_notifications n where n.id = p.notification_id
      and n.recipient_id = caller and n.suppressed_at is null) then return null; end if;
  return jsonb_build_object('kind','notification');
end;
$$;

-- Public RPCs remain closed by default; the worker alone receives delivery data.
revoke all on function public.register_push_device(uuid,uuid,text,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.register_push_device(uuid,uuid,text,uuid,boolean) to authenticated;
revoke all on function public.rotate_push_token(uuid,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.rotate_push_token(uuid,uuid,text,text) to anon,authenticated;
revoke all on function public.resolve_push_destination(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.resolve_push_destination(uuid,uuid) to authenticated;
revoke all on function public.claim_push_deliveries(integer) from public,anon,authenticated,service_role;
revoke all on function public.prepare_push_delivery(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.finish_push_delivery(uuid,uuid,text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.claim_push_deliveries(integer) to service_role;
grant execute on function public.prepare_push_delivery(uuid,uuid) to service_role;
grant execute on function public.finish_push_delivery(uuid,uuid,text,text,integer) to service_role;
revoke all on function private.push_notification_visible(public.user_notifications,uuid) from public,anon,authenticated,service_role;
revoke all on function private.push_delivery_visible(private.push_deliveries) from public,anon,authenticated,service_role;
revoke all on function private.enqueue_push_delivery() from public,anon,authenticated,service_role;

-- Dormant until rollout supplies the two exact Vault settings. The minute tick
-- checks for due work before making one external request, outside business work.
create extension if not exists pg_net with schema extensions;
create function private.dispatch_push_tick() returns void
language plpgsql security definer set search_path = '' as $$
declare endpoint text; worker_key text;
begin
  select decrypted_secret into endpoint from vault.decrypted_secrets where name = 'list_split_push_url';
  select decrypted_secret into worker_key from vault.decrypted_secrets where name = 'list_split_push_worker_key';
  if endpoint is distinct from 'https://lzwsgxziqxpxwyalkfuy.supabase.co/functions/v1/push-dispatch'
    or worker_key is null or length(worker_key) < 32 then return; end if;
  if not exists(select 1 from private.push_deliveries where status = 'pending'
      and attempts < 4 and next_attempt_at <= now() and expires_at > now()
      and (lease_until is null or lease_until <= now())) then return; end if;
  perform net.http_post(url := endpoint,
    headers := jsonb_build_object('Content-Type','application/json','x-push-worker-key',worker_key),
    body := '{}'::jsonb, timeout_milliseconds := 55000);
end;
$$;
revoke all on function private.dispatch_push_tick() from public,anon,authenticated,service_role;
-- Cleanup runs even when there are no enabled devices or delivery credentials.
create function private.maintain_push_retention() returns void
language sql security definer set search_path = '' as $$
  delete from private.push_deliveries where id in
    (select id from private.push_deliveries where expires_at <= now() order by expires_at limit 5000);
  delete from private.push_devices where id in
    (select id from private.push_devices where updated_at < now() - interval '30 days' limit 100);
$$;
revoke all on function private.maintain_push_retention() from public,anon,authenticated,service_role;
select cron.schedule('list-and-split-push-minute','* * * * *',
  'select private.maintain_push_retention(); select private.dispatch_push_tick();');

commit;
