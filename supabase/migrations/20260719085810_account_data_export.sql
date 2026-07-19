create function public.export_own_account_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  caller_auth jsonb;
  caller_profile jsonb;
  outgoing_blocks jsonb := '[]'::jsonb;
  active_relationships jsonb := '[]'::jsonb;
  visible_notifications jsonb := '[]'::jsonb;
begin
  begin
    caller_id := (select auth.uid());
  exception
    when others then
      raise exception using
        errcode = '42501',
        message = 'verified account required';
  end;

  if caller_id is null
    or (
      select pg_catalog.count(*)
      from auth.users as caller
      where caller.id = caller_id
        and caller.email is not null
        and caller.email_confirmed_at is not null
    ) <> 1
  then
    raise exception using
      errcode = '42501',
      message = 'verified account required';
  end if;

  if (
    select pg_catalog.count(*)
    from public.profiles as profile_record
    where profile_record.id = caller_id
  ) <> 1
  then
    raise exception using
      errcode = '42501',
      message = 'verified account required';
  end if;

  select pg_catalog.jsonb_build_object(
    'id', caller.id,
    'email', caller.email,
    'email_confirmed_at', caller.email_confirmed_at,
    'created_at', caller.created_at,
    'updated_at', caller.updated_at,
    'last_sign_in_at', caller.last_sign_in_at
  )
  into strict caller_auth
  from auth.users as caller
  where caller.id = caller_id;

  select pg_catalog.jsonb_build_object(
    'id', profile_record.id,
    'username', profile_record.username,
    'display_name', profile_record.display_name,
    'created_at', profile_record.created_at,
    'updated_at', profile_record.updated_at,
    'onboarding_completed_at', profile_record.onboarding_completed_at
  )
  into strict caller_profile
  from public.profiles as profile_record
  where profile_record.id = caller_id;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'profile_id', blocked_profile.id,
        'username', blocked_profile.username,
        'display_name', blocked_profile.display_name,
        'created_at', block_record.created_at
      )
      order by block_record.created_at, blocked_profile.id
    ),
    '[]'::jsonb
  )
  into outgoing_blocks
  from public.user_blocks as block_record
  join public.profiles as blocked_profile
    on blocked_profile.id = block_record.blocked_id
    and blocked_profile.onboarding_completed_at is not null
  where block_record.blocker_id = caller_id;

  if (caller_profile ->> 'onboarding_completed_at') is not null then
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'profile_id', relationship.profile_id,
          'username', relationship.username,
          'display_name', relationship.display_name,
          'status', relationship.relationship_status,
          'version', relationship.version,
          'state_changed_at', relationship.state_changed_at
        )
        order by
          relationship.state_changed_at desc,
          relationship.username,
          relationship.profile_id
      ),
      '[]'::jsonb
    )
    into active_relationships
    from public.list_active_relationships() as relationship;

    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', notification_record.id,
          'type', notification_record.notification_type,
          'created_at', notification_record.created_at,
          'is_read', notification_record.read_at is not null,
          'read_at', notification_record.read_at,
          'expires_at', notification_record.expires_at,
          'actor_profile_id', actor_profile.id,
          'actor_username', actor_profile.username,
          'actor_display_name', actor_profile.display_name,
          'action_status', case
            when relationship_record.state = 'pending'
              and relationship_record.version =
                notification_record.relationship_version
              and relationship_record.requester_id =
                notification_record.actor_id
              and notification_record.recipient_id = caller_id
              then 'actionable'
            when relationship_record.state = 'friends' then 'friends'
            else 'unavailable'
          end,
          'expected_relationship_version', case
            when relationship_record.state = 'pending'
              and relationship_record.version =
                notification_record.relationship_version
              and relationship_record.requester_id =
                notification_record.actor_id
              and notification_record.recipient_id = caller_id
              then notification_record.relationship_version
            else null::bigint
          end
        )
        order by notification_record.created_at desc, notification_record.id desc
      ),
      '[]'::jsonb
    )
    into visible_notifications
    from public.user_notifications as notification_record
    join public.profiles as actor_profile
      on actor_profile.id = notification_record.actor_id
      and actor_profile.onboarding_completed_at is not null
    join public.user_relationships as relationship_record
      on relationship_record.profile_low_id =
        notification_record.relationship_low_id
      and relationship_record.profile_high_id =
        notification_record.relationship_high_id
    where notification_record.recipient_id = caller_id
      and notification_record.suppressed_at is null
      and notification_record.expires_at > pg_catalog.now()
      and not exists (
        select 1
        from public.user_blocks as pair_block
        where (
          pair_block.blocker_id = notification_record.actor_id
          and pair_block.blocked_id = notification_record.recipient_id
        )
        or (
          pair_block.blocker_id = notification_record.recipient_id
          and pair_block.blocked_id = notification_record.actor_id
        )
      );
  end if;

  return pg_catalog.jsonb_build_object(
    'product', 'list_and_split',
    'schema_version', 1,
    'exported_at', pg_catalog.statement_timestamp(),
    'auth_identity', caller_auth,
    'profile', caller_profile,
    'outgoing_blocks', outgoing_blocks,
    'active_relationships', active_relationships,
    'visible_notifications', visible_notifications
  );
end;
$$;

alter function public.export_own_account_data()
owner to postgres;

revoke all on function public.export_own_account_data()
from public, anon, authenticated, service_role;

grant execute on function public.export_own_account_data()
to authenticated;

comment on function public.export_own_account_data() is
  'Returns the verified caller''s versioned allowlisted account-data export without retaining or mutating data.';
