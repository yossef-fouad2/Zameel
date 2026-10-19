-- Run WHOLE file after 001, 002 and 003 in a DISPOSABLE DEVELOPMENT project.
-- Administrator-only verification: random Auth fixtures, DB-only Storage rows,
-- API-role impersonation and assertions, followed by ROLLBACK. Never COMMIT this.
-- If a check fails, issue ROLLBACK. Do not use production or external database/Auth
-- hooks whose side effects cannot be rolled back. No real image bytes are uploaded.
-- Storage deletion GUC below is test-only; production files MUST use Storage APIs.
-- This verifies database policy, not PNG decoding/dimensions, HTTP uploads/signing,
-- JWT validation, signed-URL expiry or the client's cache. Exercise those in-app.
--
-- Manual concurrent verification, separate development connections:
-- 1. Two profile UPDATEs with the same original updated_at: hold the first open;
--    second waits, then returns zero rows after first commits. No lost update.
-- 2. Hold an avatar attachment UPDATE open; deleting that object as the same user
--    must wait and then delete zero rows after attachment commits.
-- 3. Hold orphan deletion open; a profile UPDATE referencing it must wait and fail
--    avatar_object_not_found after deletion commits. Neither direction may leave
--    a committed dangling reference. Different profiles do not share a lock.
-- Use authenticated claims only in this admin test context, never as a client API.

begin;
set local search_path = pg_catalog;
set local storage.allow_delete_query = 'true';

create temporary table avatar_test_ids (key text primary key, id uuid not null);
create temporary table avatar_test_versions (key text primary key, stamp timestamptz not null);
create temporary table avatar_test_results (name text not null);
grant select, insert on pg_temp.avatar_test_ids, pg_temp.avatar_test_versions,
  pg_temp.avatar_test_results to anon, authenticated;

create function pg_temp.a_id(p_key text)
returns uuid language sql stable security invoker set search_path = '' as $test$
  select id from pg_temp.avatar_test_ids where key = p_key;
$test$;
create function pg_temp.a_path(p_user text, p_nonce text)
returns text language sql stable security invoker set search_path = '' as $test$
  select pg_temp.a_id(p_user)::text || '/' || pg_catalog.replace(pg_temp.a_id(p_nonce)::text, '-', '') || '.png';
$test$;
create function pg_temp.a_actor(p_key text)
returns void language plpgsql security invoker set search_path = '' as $test$
declare
  v_id uuid := pg_temp.a_id(p_key);
  v_role text := case when p_key is null then 'anon' else 'authenticated' end;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claims', pg_catalog.jsonb_build_object('sub',v_id,'role',v_role)::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', v_role, true);
end;
$test$;
create function pg_temp.a_assert(p_name text, p_ok boolean)
returns void language plpgsql security invoker set search_path = '' as $test$
begin
  if p_ok is distinct from true then raise exception 'FAIL: %', p_name; end if;
  insert into pg_temp.avatar_test_results values (p_name);
end;
$test$;
create function pg_temp.a_error(p_name text, p_sql text, p_state text, p_message text default null)
returns void language plpgsql security invoker set search_path = '' as $test$
declare
  v_state text;
  v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_state = p_state and (p_message is null or pg_catalog.strpos(v_message,p_message) > 0) then
      insert into pg_temp.avatar_test_results values (p_name);
      return;
    end if;
    raise exception 'FAIL: %; expected % / %, got % / %', p_name,p_state,p_message,v_state,v_message;
  end;
  raise exception 'FAIL: %; statement succeeded, expected %', p_name,p_state;
end;
$test$;

select pg_temp.a_assert('avatar_path is nullable text, no automatic URL migration',
  exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles'
    and column_name='avatar_path' and data_type='text' and is_nullable='YES' and column_default is null));
select pg_temp.a_assert('profile update whitelist replaces legacy URL with path',
  pg_catalog.has_column_privilege('authenticated','public.profiles','avatar_path','UPDATE')
  and pg_catalog.has_column_privilege('authenticated','public.profiles','full_name','UPDATE')
  and pg_catalog.has_column_privilege('authenticated','public.profiles','phone','UPDATE')
  and pg_catalog.has_column_privilege('authenticated','public.profiles','preferred_language','UPDATE')
  and not pg_catalog.has_column_privilege('authenticated','public.profiles','avatar_url','UPDATE')
  and not pg_catalog.has_column_privilege('authenticated','public.profiles','role','UPDATE')
  and not pg_catalog.has_column_privilege('authenticated','public.profiles','id','UPDATE')
  and not pg_catalog.has_column_privilege('authenticated','public.profiles','updated_at','UPDATE')
  and not pg_catalog.has_table_privilege('authenticated','public.profiles','INSERT,UPDATE,DELETE'));
select pg_temp.a_assert('private PNG bucket is limited to 2 MiB',
  (select not public and file_size_limit=2097152 and allowed_mime_types=array['image/png']
   from storage.buckets where id='profile-avatars'));
select pg_temp.a_assert('profile and Storage RLS remain enabled',
  (select bool_and(relrowsecurity) from pg_catalog.pg_class where oid in
    ('public.profiles'::regclass,'storage.objects'::regclass,'storage.buckets'::regclass)));
select pg_temp.a_assert('profile visibility policies are not expanded',
  (select count(*)=2 and bool_and(polname in ('profiles_self_read','profiles_self_edit'))
   from pg_catalog.pg_policy where polrelid='public.profiles'::regclass));
select pg_temp.a_assert('validation trigger is not callable by API roles',
  not pg_catalog.has_function_privilege('authenticated','zameel_private.validate_profile_avatar()','EXECUTE')
  and not pg_catalog.has_function_privilege('anon','zameel_private.owns_profile_avatar(text)','EXECUTE')
  and not pg_catalog.has_function_privilege('service_role','zameel_private.can_delete_profile_avatar(text)','EXECUTE'));
select pg_temp.a_assert('avatar helpers pin search_path and deletion is volatile',
  (select count(*)=3 and bool_and(proconfig @> array['search_path=""'])
   from pg_catalog.pg_proc where pronamespace='zameel_private'::regnamespace
     and proname in ('owns_profile_avatar','can_delete_profile_avatar','validate_profile_avatar'))
  and (select provolatile='v' from pg_catalog.pg_proc where oid='zameel_private.can_delete_profile_avatar(text)'::regprocedure));

insert into pg_temp.avatar_test_ids select key,gen_random_uuid() from unnest(array[
  'owner','landlord','other_landlord','missing','current','next','orphan','foreign','unused','photo'
]) key;
insert into auth.users(id,email,raw_user_meta_data)
select id,'avatar-test+'||id::text||'@example.invalid',jsonb_build_object(
  'role',case when key like '%landlord' then 'landlord' else 'student' end,'name','Avatar test '||key)
from pg_temp.avatar_test_ids where key in ('owner','landlord','other_landlord','missing');
update public.profiles set avatar_url='https://example.invalid/legacy-avatar.png' where id=pg_temp.a_id('owner');
delete from public.profiles where id=pg_temp.a_id('missing');
-- Exact same path in another bucket must NOT count as an avatar object.
insert into storage.objects(bucket_id,name) values ('listing-photos',pg_temp.a_path('owner','unused'));

-- Prove the restrictive guards survive unrelated overly broad Storage policies.
-- These test policies and every fixture disappear at the final ROLLBACK.
create policy avatar_verification_broad_objects on storage.objects for all to anon,authenticated
  using (true) with check (true);
create policy avatar_verification_broad_buckets on storage.buckets for all to anon,authenticated
  using (true) with check (true);

set local role authenticated;
select pg_temp.a_actor('owner');
select pg_temp.a_assert('profile read remains self-only',
  (select count(*)=1 and bool_and(id=pg_temp.a_id('owner')) from public.profiles));
select pg_temp.a_assert('legacy URL remains readable; new path starts null',
  (select avatar_url='https://example.invalid/legacy-avatar.png' and avatar_path is null from public.profiles));
insert into storage.objects(bucket_id,name) values
  ('profile-avatars',pg_temp.a_path('owner','current')),
  ('profile-avatars',pg_temp.a_path('owner','next')),
  ('profile-avatars',pg_temp.a_path('owner','orphan'));
select pg_temp.a_assert('student can read/sign their own uploaded objects',
  (select count(*)=3 from storage.objects where bucket_id='profile-avatars'));
select pg_temp.a_error('foreign upload prefix denied',
  $$insert into storage.objects(bucket_id,name) values('profile-avatars',pg_temp.a_path('landlord','foreign'))$$,'42501');
select pg_temp.a_error('uppercase nonce denied',
  $$insert into storage.objects(bucket_id,name) values('profile-avatars',pg_temp.a_id('owner')::text||'/'||repeat('A',32)||'.png')$$,'42501');
select pg_temp.a_error('non-PNG suffix denied',
  $$insert into storage.objects(bucket_id,name) values('profile-avatars',replace(pg_temp.a_path('owner','unused'),'.png','.jpg'))$$,'42501');
select pg_temp.a_error('hyphenated nonce denied',
  $$insert into storage.objects(bucket_id,name) values('profile-avatars',pg_temp.a_id('owner')::text||'/'||pg_temp.a_id('unused')::text||'.png')$$,'42501');
select pg_temp.a_error('extra directory denied',
  $$insert into storage.objects(bucket_id,name) values('profile-avatars',pg_temp.a_id('owner')::text||'/extra/'||repeat('a',32)||'.png')$$,'42501');
select pg_temp.a_error('object upsert/overwrite denied',
  $$insert into storage.objects(bucket_id,name) values('profile-avatars',pg_temp.a_path('owner','current'))
    on conflict(bucket_id,name) do update set metadata='{}'::jsonb$$,'42501');
with edited as (
  update storage.objects set name=pg_temp.a_path('owner','unused')
  where bucket_id='profile-avatars' and name=pg_temp.a_path('owner','current') returning id
) select pg_temp.a_assert('object rename denied', (select count(*)=0 from edited));

insert into pg_temp.avatar_test_versions select 'original',updated_at from public.profiles where id=pg_temp.a_id('owner');
with edited as (
  update public.profiles set full_name='Edited owner',phone='+12345',preferred_language='ar',
    avatar_path=pg_temp.a_path('owner','current')
  where id=pg_temp.a_id('owner') and updated_at=(select stamp from pg_temp.avatar_test_versions where key='original')
  returning updated_at
) select pg_temp.a_assert('own profile edit with exact timestamp succeeds',
  (select count(*)=1 and bool_and(updated_at>(select stamp from pg_temp.avatar_test_versions where key='original')) from edited));
insert into pg_temp.avatar_test_versions select 'saved',updated_at from public.profiles where id=pg_temp.a_id('owner');
select pg_temp.a_assert('profile fields saved without touching legacy URL',
  (select full_name='Edited owner' and phone='+12345' and preferred_language='ar'
    and avatar_path=pg_temp.a_path('owner','current') and avatar_url='https://example.invalid/legacy-avatar.png'
   from public.profiles));
select pg_temp.a_error('legacy avatar URL writes revoked', $$update public.profiles set avatar_url=null$$,'42501');
select pg_temp.a_error('role escalation denied', $$update public.profiles set role='landlord'$$,'42501');
select pg_temp.a_error('profile identity reassignment denied', $$update public.profiles set id=pg_temp.a_id('landlord')$$,'42501');
select pg_temp.a_error('created_at writes denied', $$update public.profiles set created_at=now()$$,'42501');
select pg_temp.a_error('updated_at writes denied', $$update public.profiles set updated_at=now()$$,'42501');
select pg_temp.a_error('Auth email is not a writable profile field',
  $$update auth.users set email='changed@example.invalid' where id=pg_temp.a_id('owner')$$,'42501');
select pg_temp.a_error('client profile insertion still denied',
  $$insert into public.profiles(id,role) values(pg_temp.a_id('owner'),'student')$$,'42501');
select pg_temp.a_error('foreign avatar reference denied',
  $$update public.profiles set avatar_path=pg_temp.a_path('landlord','foreign')$$,'22023','avatar_path_invalid');
select pg_temp.a_error('same path in wrong bucket cannot be referenced',
  $$update public.profiles set avatar_path=pg_temp.a_path('owner','unused')$$,'23503','avatar_object_not_found');
with removed as (
  delete from storage.objects where bucket_id='profile-avatars' and name=pg_temp.a_path('owner','current') returning id
) select pg_temp.a_assert('currently referenced avatar cannot be deleted', (select count(*)=0 from removed));
with edited as (
  update public.profiles set full_name='Stale edit',avatar_path=pg_temp.a_path('owner','orphan')
  where id=pg_temp.a_id('owner') and updated_at=(select stamp from pg_temp.avatar_test_versions where key='original')
  returning id
) select pg_temp.a_assert('stale optimistic update returns zero rows', (select count(*)=0 from edited));
select pg_temp.a_assert('stale update preserves profile and timestamp',
  (select full_name='Edited owner' and avatar_path=pg_temp.a_path('owner','current')
    and updated_at=(select stamp from pg_temp.avatar_test_versions where key='saved') from public.profiles));
with removed as (
  delete from storage.objects where bucket_id='profile-avatars' and name=pg_temp.a_path('owner','orphan') returning id
) select pg_temp.a_assert('failed-save orphan can be cleaned up by owner', (select count(*)=1 from removed));

select pg_temp.a_actor('landlord');
insert into storage.objects(bucket_id,name) values ('profile-avatars',pg_temp.a_path('landlord','foreign'));
update public.profiles set avatar_path=pg_temp.a_path('landlord','foreign') where id=pg_temp.a_id('landlord');
select pg_temp.a_assert('landlord can also save an owned avatar',
  (select avatar_path=pg_temp.a_path('landlord','foreign') from public.profiles where id=pg_temp.a_id('landlord')));
select pg_temp.a_assert('other profiles and their avatar objects are not enumerable',
  not exists(select 1 from public.profiles where id=pg_temp.a_id('owner'))
  and not exists(select 1 from storage.objects where bucket_id='profile-avatars' and name=pg_temp.a_path('owner','current')));
with edited as (
  update public.profiles set full_name='Foreign edit' where id=pg_temp.a_id('owner') returning id
) select pg_temp.a_assert('other user profile edit affects zero rows', (select count(*)=0 from edited));
with removed as (
  delete from storage.objects where bucket_id='profile-avatars' and name=pg_temp.a_path('owner','current') returning id
) select pg_temp.a_assert('other user cannot delete an avatar', (select count(*)=0 from removed));

-- Listing photo behavior from 001 remains intact after adding the avatar guards.
with added as (
  insert into public.listings(title,address,monthly_rent,pricing_unit,currency,total_bed_capacity)
  values('Avatar SQL fixture','Development only',100,'per_bed','USD',1) returning id
) insert into pg_temp.avatar_test_ids select 'listing',id from added;
insert into storage.objects(bucket_id,name) values
  ('listing-photos',pg_temp.a_id('listing')::text||'/'||pg_temp.a_id('photo')::text||'.jpg');
insert into public.listing_photos(listing_id,storage_path)
values(pg_temp.a_id('listing'),pg_temp.a_id('listing')::text||'/'||pg_temp.a_id('photo')::text||'.jpg');
select public.set_listing_status(pg_temp.a_id('listing'),'published');
with edited as (
  update storage.objects set metadata='{}'::jsonb where bucket_id='listing-photos'
    and name=pg_temp.a_id('listing')::text||'/'||pg_temp.a_id('photo')::text||'.jpg' returning id
) select pg_temp.a_assert('listing object overwrite remains denied', (select count(*)=0 from edited));
with removed as (
  delete from storage.objects where bucket_id='listing-photos'
    and name=pg_temp.a_id('listing')::text||'/'||pg_temp.a_id('photo')::text||'.jpg' returning id
) select pg_temp.a_assert('referenced listing photo deletion remains denied', (select count(*)=0 from removed));
select pg_temp.a_actor('other_landlord');
select pg_temp.a_error('foreign listing upload remains denied',
  $$insert into storage.objects(bucket_id,name)
    values('listing-photos',pg_temp.a_id('listing')::text||'/'||pg_temp.a_id('unused')::text||'.jpg')$$,'42501');
select pg_temp.a_actor('missing');
select pg_temp.a_error('authenticated user without a profile cannot upload avatar',
  $$insert into storage.objects(bucket_id,name) values('profile-avatars',pg_temp.a_path('missing','unused'))$$,'42501');

set local role anon;
select pg_temp.a_actor(null);
select pg_temp.a_assert('anonymous cannot read or sign ANY avatar',
  not exists(select 1 from storage.objects where bucket_id='profile-avatars'));
select pg_temp.a_error('anonymous profile access remains denied', $$select * from public.profiles$$,'42501');
select pg_temp.a_error('anonymous avatar upload denied despite broad policies',
  $$insert into storage.objects(bucket_id,name) values('profile-avatars',pg_temp.a_path('owner','unused'))$$,'42501');
with removed as (
  delete from storage.objects where bucket_id='profile-avatars' returning id
) select pg_temp.a_assert('anonymous avatar deletion denied', (select count(*)=0 from removed));
select pg_temp.a_assert('published listing photos still readable by anonymous users',
  exists(select 1 from storage.objects where bucket_id='listing-photos'
    and name=pg_temp.a_id('listing')::text||'/'||pg_temp.a_id('photo')::text||'.jpg'));
with edited as (
  update storage.buckets set public=true where id='profile-avatars' returning id
) select pg_temp.a_assert('avatar bucket cannot be made public by anonymous user', (select count(*)=0 from edited));

set local role authenticated;
select pg_temp.a_actor('owner');
with edited as (
  update storage.buckets set public=true where id='profile-avatars' returning id
) select pg_temp.a_assert('avatar bucket cannot be made public by owner', (select count(*)=0 from edited));
select pg_temp.a_error('existing foreign avatar cannot be attached to own profile',
  $$update public.profiles set avatar_path=pg_temp.a_path('landlord','foreign')
    where id=pg_temp.a_id('owner')$$,'22023','avatar_path_invalid');
with edited as (
  update public.profiles set avatar_path=pg_temp.a_path('owner','next')
  where id=pg_temp.a_id('owner') and updated_at=(select stamp from pg_temp.avatar_test_versions where key='saved') returning id
) select pg_temp.a_assert('fresh optimistic replacement succeeds', (select count(*)=1 from edited));
with removed as (
  delete from storage.objects where bucket_id='profile-avatars' and name=pg_temp.a_path('owner','current') returning id
) select pg_temp.a_assert('retired avatar deletion succeeds', (select count(*)=1 from removed));
with removed as (
  delete from storage.objects where bucket_id='profile-avatars' and name=pg_temp.a_path('owner','next') returning id
) select pg_temp.a_assert('replacement avatar is protected while referenced', (select count(*)=0 from removed));
update public.profiles set avatar_path=null where id=pg_temp.a_id('owner');
with removed as (
  delete from storage.objects where bucket_id='profile-avatars' and name=pg_temp.a_path('owner','next') returning id
) select pg_temp.a_assert('cleared avatar becomes deletable', (select count(*)=1 from removed));
select pg_temp.a_assert('legacy URL survives replacement and removal',
  (select avatar_path is null and avatar_url='https://example.invalid/legacy-avatar.png' from public.profiles));

reset role;
select count(*)::text || ' profile/avatar assertions passed; all fixtures will now roll back.' as result
from pg_temp.avatar_test_results;
rollback;
