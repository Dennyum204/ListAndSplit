-- Application stale versions are HTTP conflicts, not database serialization failures.
-- PostgREST 14 retries 40001; preserve all guards/leases and the existing grants.
create or replace function public.begin_profile_avatar_operation(
  target_profile uuid, request_id uuid, fingerprint text, expected_version bigint
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  avatar private.profile_avatars%rowtype;
  token uuid := gen_random_uuid();
  completed boolean;
begin
  if target_profile is null or request_id is null or fingerprint is null
    or length(fingerprint) not between 1 and 80 then
    raise exception using errcode = '22023', message = 'invalid avatar operation';
  end if;
  perform 1 from public.profiles p join auth.users u on u.id = p.id
    where p.id = target_profile and u.email_confirmed_at is not null for update of p;
  if not found then
    raise exception using errcode = '42501', message = 'verified account required';
  end if;
  insert into private.profile_avatars(profile_id) values(target_profile) on conflict do nothing;
  select * into avatar from private.profile_avatars where profile_id = target_profile for update;
  if avatar.lease_until > clock_timestamp() then
    raise exception using errcode = '55P03', message = 'avatar operation in progress';
  end if;
  completed := coalesce(avatar.last_request = request_id, false);
  if completed and avatar.last_fingerprint <> fingerprint then
    raise exception using errcode = '22023', message = 'conflicting avatar request';
  end if;
  if not completed and expected_version is not null and avatar.version <> expected_version then
    raise exception using errcode = 'PT409', message = 'avatar changed';
  end if;
  update private.profile_avatars set lease = token, lease_until = clock_timestamp() + interval '15 minutes'
    where profile_id = target_profile;
  return jsonb_build_object('lease', token, 'version', avatar.version,
    'current_file', avatar.current_file, 'completed', completed,
    'files', coalesce((select jsonb_agg(id order by id) from private.profile_avatar_files
      where profile_id = target_profile), '[]'::jsonb));
end;
$$;
