begin;

create extension if not exists pgtap with schema extensions;

select plan(53);

select has_table(
  'public',
  'profiles',
  'profiles is an application table in the public schema'
);

select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
  ),
  6::bigint,
  'profiles has only the required six columns'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'email'
  ),
  'profiles never copies the private auth email address'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.profiles'::regclass
  ),
  'profiles has RLS enabled'
);

select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
  ),
  2::bigint,
  'profiles has exactly the own-read and own-update policies'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'profiles_select_own'
      and cmd = 'SELECT'
      and roles = '{authenticated}'::name[]
      and qual is not null
  ),
  'the select policy is scoped to authenticated owners'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'profiles_update_own'
      and cmd = 'UPDATE'
      and roles = '{authenticated}'::name[]
      and qual is not null
      and with_check is not null
  ),
  'the update policy has authenticated USING and WITH CHECK boundaries'
);

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'id', 'SELECT')
  and has_column_privilege('authenticated', 'public.profiles', 'username', 'SELECT')
  and has_column_privilege('authenticated', 'public.profiles', 'display_name', 'SELECT')
  and has_column_privilege(
    'authenticated',
    'public.profiles',
    'onboarding_completed_at',
    'SELECT'
  ),
  'authenticated can select the four client-facing profile columns'
);

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'created_at', 'SELECT')
  and not has_column_privilege('authenticated', 'public.profiles', 'updated_at', 'SELECT'),
  'authenticated cannot select database-internal audit timestamps'
);

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'username', 'UPDATE')
  and has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE'),
  'authenticated can update only the two approved profile inputs'
);

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'id', 'UPDATE')
  and not has_column_privilege(
    'authenticated',
    'public.profiles',
    'onboarding_completed_at',
    'UPDATE'
  )
  and not has_column_privilege('authenticated', 'public.profiles', 'created_at', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.profiles', 'updated_at', 'UPDATE'),
  'authenticated cannot update identity or database-managed state'
);

select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'INSERT')
  and not has_table_privilege('authenticated', 'public.profiles', 'DELETE'),
  'authenticated has no direct insert or delete privilege'
);

select ok(
  not has_table_privilege('anon', 'public.profiles', 'SELECT')
  and not has_table_privilege('anon', 'public.profiles', 'INSERT')
  and not has_table_privilege('anon', 'public.profiles', 'UPDATE')
  and not has_table_privilege('anon', 'public.profiles', 'DELETE'),
  'anon has no profile table privileges'
);

select ok(
  not has_table_privilege('service_role', 'public.profiles', 'SELECT')
  and not has_table_privilege('service_role', 'public.profiles', 'INSERT')
  and not has_table_privilege('service_role', 'public.profiles', 'UPDATE')
  and not has_table_privilege('service_role', 'public.profiles', 'DELETE'),
  'the service role receives no unnecessary Data API table grant'
);

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE')
  and not has_schema_privilege('authenticated', 'private', 'USAGE')
  and not has_schema_privilege('service_role', 'private', 'USAGE'),
  'the internal schema is unavailable to Data API roles'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'private.handle_new_auth_user()'::regprocedure
  ),
  'the auth boundary handler is security definer'
);

select ok(
  not (
    select prosecdef
    from pg_proc
    where oid = 'private.prepare_profile_write()'::regprocedure
  ),
  'the profile write trigger uses invoker rights'
);

select ok(
  (
    select proconfig @> array['search_path=""']
    from pg_proc
    where oid = 'private.handle_new_auth_user()'::regprocedure
  )
  and (
    select proconfig @> array['search_path=""']
    from pg_proc
    where oid = 'private.prepare_profile_write()'::regprocedure
  ),
  'both trigger functions pin an empty search path'
);

select ok(
  not has_function_privilege('anon', 'private.handle_new_auth_user()', 'EXECUTE')
  and not has_function_privilege(
    'authenticated',
    'private.handle_new_auth_user()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'private.handle_new_auth_user()',
    'EXECUTE'
  ),
  'Data API roles cannot execute the definer function'
);

select ok(
  not has_function_privilege('anon', 'private.prepare_profile_write()', 'EXECUTE')
  and not has_function_privilege(
    'authenticated',
    'private.prepare_profile_write()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'private.prepare_profile_write()',
    'EXECUTE'
  ),
  'Data API roles cannot execute the profile trigger function'
);

insert into auth.users (id, email, created_at, updated_at)
values
  (
    '11111111-1111-4111-8111-111111111111',
    'one@example.test',
    now(),
    now()
  ),
  (
    '22222222-2222-4222-8222-222222222222',
    'two@example.test',
    now(),
    now()
  ),
  (
    '33333333-3333-4333-8333-333333333333',
    'three@example.test',
    now(),
    now()
  );

select is(
  (
    select count(*)
    from public.profiles
    where id in (
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      '33333333-3333-4333-8333-333333333333'
    )
  ),
  3::bigint,
  'the auth trigger creates one profile for every new auth user'
);

select ok(
  exists (
    select 1
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
      and username is null
      and display_name is null
      and onboarding_completed_at is null
      and created_at is not null
      and updated_at is not null
  ),
  'a new profile starts incomplete with database timestamps'
);

create trigger create_profile_after_auth_user_insert_retry_test
after insert on auth.users
for each row execute function private.handle_new_auth_user();

select lives_ok(
  $$
    insert into auth.users (id, email, created_at, updated_at)
    values (
      '44444444-4444-4444-8444-444444444444',
      'retry@example.test',
      now(),
      now()
    )
  $$,
  'profile creation is idempotent when the auth event is retried'
);

select is(
  (
    select count(*)
    from public.profiles
    where id = '44444444-4444-4444-8444-444444444444'
  ),
  1::bigint,
  'a retried auth event still creates exactly one profile'
);

drop trigger create_profile_after_auth_user_insert_retry_test on auth.users;

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$
    update public.profiles
    set username = E'\t  First_Name  \n'
    where id = '11111111-1111-4111-8111-111111111111'
  $$,
  'a username wrapped in POSIX whitespace is accepted for normalization'
);

reset role;

select is(
  (
    select username
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  'first_name',
  'a partial username is trimmed and normalized to lowercase'
);

select ok(
  (
    select onboarding_completed_at is null
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  'a username alone does not complete onboarding'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select lives_ok(
  $$
    update public.profiles
    set username = ' Corrected_Name '
    where id = '11111111-1111-4111-8111-111111111111'
  $$,
  'an incomplete profile can correct its username before completion'
);

reset role;

select is(
  (
    select username
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  'corrected_name',
  'the corrected pre-completion username is canonical'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-4222-8222-222222222222';

update public.profiles
set
  username = '  Alpha_User  ',
  display_name = '  Alice Example  '
where id = '22222222-2222-4222-8222-222222222222';

reset role;

select is(
  (
    select username
    from public.profiles
    where id = '22222222-2222-4222-8222-222222222222'
  ),
  'alpha_user',
  'completion stores the canonical username'
);

select is(
  (
    select display_name
    from public.profiles
    where id = '22222222-2222-4222-8222-222222222222'
  ),
  'Alice Example',
  'completion stores the trimmed display name'
);

select ok(
  (
    select onboarding_completed_at is not null
    from public.profiles
    where id = '22222222-2222-4222-8222-222222222222'
  ),
  'the database marks onboarding complete only after both fields are valid'
);

select ok(
  not exists (
    select 1
    from public.profiles
    where (onboarding_completed_at is not null)
      is distinct from (username is not null and display_name is not null)
  ),
  'the completion marker is equivalent to both onboarding fields being present'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '33333333-3333-4333-8333-333333333333';

select throws_like(
  $$
    update public.profiles
    set username = '1invalid'
    where id = '33333333-3333-4333-8333-333333333333'
  $$,
  '%profiles_username_format_check%',
  'a direct API update rejects an invalid username'
);

select throws_like(
  $$
    update public.profiles
    set display_name = '   '
    where id = '33333333-3333-4333-8333-333333333333'
  $$,
  '%profiles_display_name_format_check%',
  'a direct API update rejects an empty trimmed display name'
);

select throws_like(
  $$
    update public.profiles
    set display_name = E'\t\n\r'
    where id = '33333333-3333-4333-8333-333333333333'
  $$,
  '%profiles_display_name_format_check%',
  'a direct API update rejects a display name containing only POSIX whitespace'
);

reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-4111-8111-111111111111';

select throws_like(
  $$
    update public.profiles
    set username = ' ALPHA_USER '
    where id = '11111111-1111-4111-8111-111111111111'
  $$,
  '%profiles_username_key%',
  'canonical username uniqueness is case-insensitive'
);

update public.profiles
set display_name = '  First Person  '
where id = '11111111-1111-4111-8111-111111111111';

select throws_like(
  $$
    update public.profiles
    set username = 'different_name'
    where id = '11111111-1111-4111-8111-111111111111'
  $$,
  '%username cannot be changed after onboarding is complete%',
  'a direct API update cannot change a completed username'
);

select lives_ok(
  $$
    update public.profiles
    set username = '  CORRECTED_NAME  '
    where id = '11111111-1111-4111-8111-111111111111'
  $$,
  'a same-canonical username retry is idempotent'
);

select lives_ok(
  $$
    update public.profiles
    set display_name = '  Edited Person  '
    where id = '11111111-1111-4111-8111-111111111111'
  $$,
  'a completed profile can edit its display name'
);

select is(
  (
    select count(*)
    from public.profiles
  ),
  1::bigint,
  'RLS lets a user read only their own profile'
);

select is(
  (
    select count(*)
    from public.profiles
    where id = '22222222-2222-4222-8222-222222222222'
  ),
  0::bigint,
  'RLS hides another user profile'
);

update public.profiles
set display_name = 'Attacker edit'
where id = '22222222-2222-4222-8222-222222222222';

select throws_like(
  $$
    insert into public.profiles (id)
    values ('66666666-6666-4666-8666-666666666666')
  $$,
  '%permission denied%profiles%',
  'an authenticated client cannot insert a profile directly'
);

select throws_like(
  $$
    delete from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  $$,
  '%permission denied%profiles%',
  'an authenticated client cannot delete a profile directly'
);

select throws_like(
  $$
    update public.profiles
    set onboarding_completed_at = null
    where id = '11111111-1111-4111-8111-111111111111'
  $$,
  '%permission denied%profiles%',
  'an authenticated client cannot write the completion marker'
);

select throws_like(
  $$
    update public.profiles
    set id = '66666666-6666-4666-8666-666666666666'
    where id = '11111111-1111-4111-8111-111111111111'
  $$,
  '%permission denied%profiles%',
  'an authenticated client cannot rewrite profile identity'
);

reset role;

select is(
  (
    select display_name
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  'Edited Person',
  'display-name edits are trimmed and persisted'
);

select is(
  (
    select username
    from public.profiles
    where id = '11111111-1111-4111-8111-111111111111'
  ),
  'corrected_name',
  'the immutable username remains unchanged after rejected updates and retries'
);

select is(
  (
    select display_name
    from public.profiles
    where id = '22222222-2222-4222-8222-222222222222'
  ),
  'Alice Example',
  'a cross-user update is filtered without mutating the target'
);

set local role anon;

select throws_like(
  $$select id from public.profiles$$,
  '%permission denied%profiles%',
  'anonymous clients cannot read profiles'
);

select throws_like(
  $$
    update public.profiles
    set display_name = 'Anonymous edit'
  $$,
  '%permission denied%profiles%',
  'anonymous clients cannot update profiles'
);

reset role;

select throws_like(
  $$
    delete from auth.users
    where id = '44444444-4444-4444-8444-444444444444'
  $$,
  '%profiles_id_fkey%',
  'auth-user deletion is blocked until the open retention behavior is resolved'
);

select is(
  (
    select count(*)
    from public.profiles
    where id = '44444444-4444-4444-8444-444444444444'
  ),
  1::bigint,
  'a blocked auth-user deletion leaves the profile intact'
);

select * from finish();
rollback;
