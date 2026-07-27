create function public.list_friend_public_template_feed(
  requested_page_size integer default 20,
  cursor_published_at timestamptz default null,
  cursor_template_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := private.require_verified_template_caller();
  entry_documents jsonb;
  next_cursor jsonb;
begin
  if requested_page_size is null
    or requested_page_size not between 1 and 50
    or (
      (cursor_published_at is null)
      <> (cursor_template_id is null)
    )
  then
    raise exception using
      errcode = '22023',
      message = 'invalid public template query';
  end if;

  with friend_profiles as materialized (
    select
      friend_profile.id,
      friend_profile.username,
      friend_profile.display_name
    from public.user_relationships as relationship
    join public.profiles as friend_profile
      on friend_profile.id = case
        when relationship.profile_low_id = caller_id
          then relationship.profile_high_id
        else relationship.profile_low_id
      end
    where relationship.state = 'friends'
      and (
        relationship.profile_low_id = caller_id
        or relationship.profile_high_id = caller_id
      )
      and friend_profile.id <> caller_id
      and friend_profile.onboarding_completed_at is not null
      and friend_profile.username is not null
      and friend_profile.display_name is not null
      and not exists (
        select 1
        from public.user_blocks as pair_block
        where (
          pair_block.blocker_id = caller_id
          and pair_block.blocked_id = friend_profile.id
        ) or (
          pair_block.blocker_id = friend_profile.id
          and pair_block.blocked_id = caller_id
        )
      )
  ),
  candidates as materialized (
    select
      friend_profile.id as profile_id,
      friend_profile.username,
      friend_profile.display_name,
      candidate.template_id,
      candidate.template_name,
      candidate.template_version,
      candidate.published_at
    from friend_profiles as friend_profile
    cross join lateral (
      select
        template_record.id as template_id,
        template_record.name as template_name,
        template_record.version as template_version,
        template_record.published_at
      from public.templates as template_record
      where template_record.owner_id = friend_profile.id
        and template_record.published_at is not null
        and not exists (
          select 1
          from private.public_template_moderation_restrictions as restriction
          where restriction.template_id = template_record.id
            and restriction.active
        )
        and not exists (
          select 1
          from private.public_template_reports as submitted_report
          where submitted_report.reporter_id = caller_id
            and submitted_report.template_id = template_record.id
        )
        and (
          cursor_published_at is null
          or (
            template_record.published_at,
            template_record.id
          ) < (
            cursor_published_at,
            cursor_template_id
          )
        )
      order by template_record.published_at desc, template_record.id desc
      limit requested_page_size + 1
    ) as candidate
    order by candidate.published_at desc, candidate.template_id desc
    limit requested_page_size + 1
  ),
  page_rows as (
    select candidate.*
    from candidates as candidate
    order by candidate.published_at desc, candidate.template_id desc
    limit requested_page_size
  )
  select
    coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'profile',
            pg_catalog.jsonb_build_object(
              'profile_id', page_row.profile_id,
              'username', page_row.username,
              'display_name', page_row.display_name
            ),
            'template',
            pg_catalog.jsonb_build_object(
              'template_id', page_row.template_id,
              'name', page_row.template_name,
              'version', page_row.template_version,
              'item_count',
              (
                select pg_catalog.count(*)::bigint
                from public.template_items as item_record
                where item_record.template_id = page_row.template_id
              ),
              'published_at', page_row.published_at
            )
          )
          order by page_row.published_at desc, page_row.template_id desc
        )
        from page_rows as page_row
      ),
      '[]'::jsonb
    ),
    case
      when (
        select pg_catalog.count(*) > requested_page_size
        from candidates
      ) then pg_catalog.jsonb_build_object(
        'published_at',
        (
          select page_row.published_at
          from page_rows as page_row
          order by page_row.published_at desc, page_row.template_id desc
          offset requested_page_size - 1
          limit 1
        ),
        'template_id',
        (
          select page_row.template_id
          from page_rows as page_row
          order by page_row.published_at desc, page_row.template_id desc
          offset requested_page_size - 1
          limit 1
        )
      )
      else null
    end
  into entry_documents, next_cursor;

  return pg_catalog.jsonb_build_object(
    'entries', entry_documents,
    'next_cursor', next_cursor
  );
end;
$$;

alter function public.list_friend_public_template_feed(
  integer,
  timestamptz,
  uuid
) owner to postgres;

revoke all on function public.list_friend_public_template_feed(
  integer,
  timestamptz,
  uuid
) from public, anon, authenticated, service_role;

grant execute on function public.list_friend_public_template_feed(
  integer,
  timestamptz,
  uuid
) to authenticated;

comment on function public.list_friend_public_template_feed(
  integer,
  timestamptz,
  uuid
) is
  'Current-friends-only bounded public-template page with block, report, and moderation filtering.';
