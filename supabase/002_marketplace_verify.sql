-- Optional SQL Editor verification, AFTER 001_marketplace_setup.sql.
-- Run this WHOLE file as the administrator in a DISPOSABLE DEVELOPMENT project.
-- It creates random test identities and DB-only Storage metadata, impersonates
-- API roles, checks failures, and ALWAYS ROLLS BACK. No email or object bytes are
-- created. Do not run against production or a project with external Auth/database
-- hooks: an external side effect is not necessarily undone by a SQL rollback.
-- If an assertion fails, run ROLLBACK; and investigate; never replace it with COMMIT.
-- No pgTAP/extensions are required. Passing SQL checks does not test Auth emails,
-- HTTP JWT verification, Storage MIME/size enforcement, actual uploads or caching.
-- The claim GUCs here are administrator-only test impersonation, not client APIs.
--
-- Manual multi-connection check (use a disposable project, not production):
-- Create a published, one-bed per_bed listing and two pending student requests.
-- Connection A: BEGIN; SET LOCAL ROLE authenticated; set the owning landlord's
-- JWT claims as below; call accept_booking(listing_id, first_booking_id); keep open.
-- Connection B: same landlord context; call accept_booking(listing_id, second_id).
-- B must wait for A's listing lock. COMMIT A; B must fail listing_full. ROLLBACK B.
-- Repeat with concurrent accept/cancel, capacity reduction, and duplicate submits.
-- Also BEGIN the cancellation transaction BEFORE the acceptance transaction but
-- call accept first: cancellation must still succeed after waiting on that lock.
-- Confirm occupied_beds = accepted bookings = current resident rows, never > total.
-- In the actual app also verify confirmation/signup OTP, recovery OTP and redirects,
-- denial of another user's draft photo, upload with upsert:false, denied overwrites,
-- and private bucket downloads/signing after publication/unpublication. Issued
-- signed URLs remain usable until expiry; keep lifetimes short.

begin;
set local search_path = pg_catalog;
-- Recent Storage versions guard SQL deletion. This test-only setting mimics the
-- Storage service's deletion context for rolled-back metadata, NOT a client flow.
set local storage.allow_delete_query = 'true';

create temporary table verify_ids (key text primary key, id uuid not null);
create temporary table verify_results (name text not null);
grant select, insert, update on pg_temp.verify_ids to anon, authenticated;
grant select, insert on pg_temp.verify_results to anon, authenticated;

create function pg_temp.test_id(p_key text)
returns uuid language sql stable security invoker set search_path = '' as $test$
  select id from pg_temp.verify_ids where key = p_key;
$test$;
create function pg_temp.test_path(p_listing_key text, p_photo_key text)
returns text language sql stable security invoker set search_path = '' as $test$
  select pg_temp.test_id(p_listing_key)::text || '/' || pg_temp.test_id(p_photo_key)::text || '.jpg';
$test$;
create function pg_temp.test_actor(p_key text)
returns void language plpgsql security invoker set search_path = '' as $test$
declare
  v_id uuid := pg_temp.test_id(p_key);
  v_role text := case when p_key is null then 'anon' else 'authenticated' end;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', v_role, true);
  perform pg_catalog.set_config('request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', v_id, 'role', v_role)::text, true);
end;
$test$;
create function pg_temp.assert_ok(p_name text, p_condition boolean)
returns void language plpgsql security invoker set search_path = '' as $test$
begin
  if p_condition is distinct from true then
    raise exception 'FAIL: %', p_name;
  end if;
  insert into pg_temp.verify_results(name) values (p_name);
end;
$test$;
create function pg_temp.expect_error(p_name text, p_sql text, p_state text, p_message text default null)
returns void language plpgsql security invoker set search_path = '' as $test$
declare
  v_state text;
  v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_state = p_state and (p_message is null or pg_catalog.strpos(v_message, p_message) > 0) then
      insert into pg_temp.verify_results(name) values (p_name);
      return;
    end if;
    raise exception 'FAIL: %; expected % / %, got % / %', p_name, p_state, p_message, v_state, v_message;
  end;
  raise exception 'FAIL: %; expected error %, statement succeeded', p_name, p_state;
end;
$test$;

-- Catalog checks catch accidental blanket grants as well as missing RLS.
select pg_temp.assert_ok('RLS on all ten application tables',
  (select count(*) = 10 and bool_and(c.relrowsecurity)
   from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname in (
     'profiles', 'listings', 'listing_photos', 'amenities', 'house_rules',
     'listing_amenities', 'listing_house_rules', 'lifestyle_preferences', 'bookings', 'listing_residents'
   )));
select pg_temp.assert_ok('single publication source and no unsafe reserve_bed RPC',
  not exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'listings' and column_name = 'is_published')
  and pg_catalog.to_regprocedure('public.reserve_bed(uuid,uuid)') is null);
select pg_temp.assert_ok('profile column whitelist',
  pg_catalog.has_column_privilege('authenticated', 'public.profiles', 'full_name', 'UPDATE')
  and not pg_catalog.has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')
  and not pg_catalog.has_column_privilege('authenticated', 'public.profiles', 'id', 'UPDATE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'INSERT'));
select pg_temp.assert_ok('protected listing and booking writes have no client grant',
  not pg_catalog.has_column_privilege('authenticated', 'public.listings', 'landlord_id', 'UPDATE')
  and not pg_catalog.has_column_privilege('authenticated', 'public.listings', 'occupied_beds', 'UPDATE')
  and not pg_catalog.has_column_privilege('authenticated', 'public.listings', 'status', 'UPDATE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.bookings', 'INSERT,UPDATE,DELETE')
  and not pg_catalog.has_table_privilege('authenticated', 'public.listing_residents', 'INSERT,UPDATE,DELETE'));
select pg_temp.assert_ok('private routines are not client RPCs',
  not pg_catalog.has_function_privilege('authenticated', 'zameel_private.backfill_profile(uuid,text)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated', 'zameel_private.transition_booking(uuid,uuid,text)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated', 'zameel_private.handle_new_user()', 'EXECUTE')
  and not pg_catalog.has_function_privilege('anon', 'public.submit_booking(uuid,uuid,text)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('service_role', 'public.accept_booking(uuid,uuid)', 'EXECUTE'));
select pg_temp.assert_ok('all owned SECURITY DEFINER routines pin an empty search_path',
  not exists (
    select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where p.prosecdef and (n.nspname = 'zameel_private' or
      (n.nspname = 'public' and p.proname in (
        'submit_booking', 'accept_booking', 'reject_booking', 'cancel_booking', 'set_listing_status'
      ))) and not coalesce(p.proconfig @> array['search_path=""'], false)
  ));
select pg_temp.assert_ok('no PUBLIC execute on owned SECURITY DEFINER routines',
  not exists (
    select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace,
      lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    where p.prosecdef and (n.nspname = 'zameel_private' or
      (n.nspname = 'public' and p.proname in (
        'submit_booking', 'accept_booking', 'reject_booking', 'cancel_booking', 'set_listing_status'
      ))) and a.grantee = 0 and a.privilege_type = 'EXECUTE'
  ));
select pg_temp.assert_ok('photo bucket is private and constrained',
  (select not public and file_size_limit = 10485760
    and allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
   from storage.buckets where id = 'listing-photos'));

insert into pg_temp.verify_ids(key, id)
select key, gen_random_uuid() from unnest(array[
  'landlord_a', 'landlord_b', 'student_a', 'student_b', 'student_c', 'legacy',
  'request_a', 'request_b', 'request_c', 'request_d',
  'photo_public', 'photo_draft', 'photo_orphan', 'photo_new'
]) as key;
insert into auth.users(id, email, raw_user_meta_data)
select id, 'sql-test+' || id::text || '@example.invalid',
  jsonb_build_object('role', case when key like 'landlord%' then 'landlord' else 'student' end,
                    'name', 'SQL test ' || key)
from pg_temp.verify_ids where key in ('landlord_a', 'landlord_b', 'student_a', 'student_b', 'student_c', 'legacy');
select pg_temp.assert_ok('Auth INSERT creates profile with name and en default',
  (select role = 'student' and full_name = 'SQL test student_a' and preferred_language = 'en'
    and phone is null and avatar_url is null and created_at is not null and updated_at is not null
   from public.profiles where id = pg_temp.test_id('student_a')));
select pg_temp.expect_error('invalid signup role fails closed',
  $$insert into auth.users(id, raw_user_meta_data) values (gen_random_uuid(), '{"role":"admin"}')$$,
  '22023', 'signup_role_required');
select pg_temp.expect_error('missing signup role fails closed',
  $$insert into auth.users(id, raw_user_meta_data) values (gen_random_uuid(), '{}')$$,
  '22023', 'signup_role_required');
-- Simulate mutable Auth metadata and a legacy Auth user without a profile.
update auth.users set raw_user_meta_data = '{"role":"landlord","name":"Untrusted new name"}'
where id in (pg_temp.test_id('student_a'), pg_temp.test_id('legacy'));
select pg_temp.assert_ok('metadata UPDATE never changes profile role or name',
  (select role = 'student' and full_name = 'SQL test student_a'
   from public.profiles where id = pg_temp.test_id('student_a')));
delete from public.profiles where id = pg_temp.test_id('legacy');
select pg_temp.assert_ok('backfill uses explicit role instead of mutable metadata',
  (select role = 'student' from zameel_private.backfill_profile(pg_temp.test_id('legacy'), 'student')));
select pg_temp.assert_ok('backfill replay preserves existing role and profile',
  (select role = 'student' and full_name = 'Untrusted new name'
   from zameel_private.backfill_profile(pg_temp.test_id('legacy'), 'landlord')));
update auth.users set raw_user_meta_data = jsonb_build_object('role','landlord','name',repeat('x',201))
where id = pg_temp.test_id('legacy');
select pg_temp.assert_ok('backfill replay ignores now-invalid mutable name metadata',
  (select role = 'student' and full_name = 'Untrusted new name'
   from zameel_private.backfill_profile(pg_temp.test_id('legacy'), 'landlord')));
delete from public.profiles where id = pg_temp.test_id('student_c');

set local role authenticated;
select pg_temp.test_actor('student_c');
select pg_temp.assert_ok('missing profile has no fallback metadata-derived role',
  zameel_private.current_profile_role() is null and not exists (select 1 from public.profiles));
select pg_temp.expect_error('authenticated user without profile cannot submit',
  $$select public.submit_booking(null,pg_temp.test_id('request_d'))$$, '42501', 'student_role_required');
select pg_temp.expect_error('authenticated user without profile cannot publish',
  $$select public.set_listing_status(null,'published')$$, '42501', 'landlord_role_required');
select pg_temp.test_actor('landlord_a');
with added as (
  insert into public.listings(title, address, monthly_rent, pricing_unit, currency, total_bed_capacity)
  values ('SQL bed', 'Development fixture', 100, 'per_bed', 'USD', 1) returning id
) insert into pg_temp.verify_ids select 'listing_bed', id from added;
with added as (
  insert into public.listings(title, address, monthly_rent, pricing_unit, currency, total_bed_capacity)
  values ('SQL second', 'Development fixture', 120, 'per_bed', 'USD', 2) returning id
) insert into pg_temp.verify_ids select 'listing_second', id from added;
with added as (
  insert into public.listings(title, address, monthly_rent, pricing_unit, currency, total_bed_capacity)
  values ('SQL room', 'Development fixture', 300, 'per_room', 'USD', 2) returning id
) insert into pg_temp.verify_ids select 'listing_room', id from added;
with added as (
  insert into public.listings(title, address, monthly_rent, pricing_unit, currency, total_bed_capacity)
  values ('SQL property', 'Development fixture', 800, 'per_property', 'USD', 4) returning id
) insert into pg_temp.verify_ids select 'listing_property', id from added;
with added as (
  insert into public.listings(title, address, monthly_rent, pricing_unit, currency, total_bed_capacity)
  values ('SQL draft', 'Development fixture', 110, 'per_bed', 'USD', 1) returning id
) insert into pg_temp.verify_ids select 'listing_draft', id from added;
select public.set_listing_status(id, 'published') from pg_temp.verify_ids
where key in ('listing_bed', 'listing_second', 'listing_room', 'listing_property');
select pg_temp.assert_ok('listing insert defaults verified owner, draft, zero occupancy',
  (select landlord_id = pg_temp.test_id('landlord_a') and status = 'draft'
    and occupied_beds = 0 and available_beds = 1
   from public.listings where id = pg_temp.test_id('listing_draft')));
select pg_temp.expect_error('no direct listing status writes',
  $$update public.listings set status = 'published' where id = pg_temp.test_id('listing_draft')$$, '42501');
select pg_temp.expect_error('no direct occupancy writes',
  $$update public.listings set occupied_beds = 1 where id = pg_temp.test_id('listing_bed')$$, '42501');
select pg_temp.expect_error('no ownership reassignment',
  $$update public.listings set landlord_id = pg_temp.test_id('landlord_b') where id = pg_temp.test_id('listing_bed')$$, '42501');
select pg_temp.expect_error('no owner override on insert',
  $$insert into public.listings(landlord_id,title,monthly_rent,pricing_unit,currency,total_bed_capacity)
    values(pg_temp.test_id('landlord_b'),'Forged',1,'per_bed','USD',1)$$, '42501');
select pg_temp.expect_error('currency must be explicit',
  $$insert into public.listings(title,monthly_rent,pricing_unit,total_bed_capacity)
    values('Missing currency',1,'per_bed',1)$$, '23502');
select pg_temp.expect_error('no NaN rent',
  $$update public.listings set monthly_rent = 'NaN' where id = pg_temp.test_id('listing_bed')$$, '23514');
select pg_temp.expect_error('no incomplete coordinates',
  $$update public.listings set latitude = 30 where id = pg_temp.test_id('listing_bed')$$, '23514');
select pg_temp.expect_error('landlord cannot submit a student booking',
  $$select public.submit_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('request_a'))$$,
  '42501', 'student_role_required');
insert into public.listing_amenities(listing_id, amenity_id)
select pg_temp.test_id(k), a.id from unnest(array['listing_bed','listing_draft']) k,
  public.amenities a where a.code = 'wifi';
insert into public.listing_house_rules(listing_id, rule_id)
select pg_temp.test_id(k), r.id from unnest(array['listing_bed','listing_draft']) k,
  public.house_rules r where r.code = 'no_smoking';

-- DB-only object rows test policies, NOT real upload bytes or MIME validation.
insert into storage.objects(bucket_id, name) values
  ('listing-photos', pg_temp.test_path('listing_bed','photo_public')),
  ('listing-photos', pg_temp.test_path('listing_draft','photo_draft')),
  ('listing-photos', pg_temp.test_path('listing_bed','photo_orphan'));
insert into public.listing_photos(listing_id, storage_path, is_primary) values
  (pg_temp.test_id('listing_bed'), pg_temp.test_path('listing_bed','photo_public'), true),
  (pg_temp.test_id('listing_draft'), pg_temp.test_path('listing_draft','photo_draft'), true);
select pg_temp.expect_error('photo metadata requires an existing owned object',
  $$insert into public.listing_photos(listing_id,storage_path)
    values(pg_temp.test_id('listing_bed'),pg_temp.test_path('listing_bed','photo_new'))$$, '42501');
select pg_temp.expect_error('photo cannot link another listing path',
  $$insert into public.listing_photos(listing_id,storage_path)
    values(pg_temp.test_id('listing_second'),pg_temp.test_path('listing_bed','photo_orphan'))$$, '42501');
select pg_temp.expect_error('only one primary photo per listing',
  $$insert into public.listing_photos(listing_id,storage_path,is_primary)
    values(pg_temp.test_id('listing_bed'),pg_temp.test_path('listing_bed','photo_orphan'),true)$$, '23505');
with changed as (
  update storage.objects set name = pg_temp.test_path('listing_bed','photo_new')
  where name = pg_temp.test_path('listing_bed','photo_public') returning id
) select pg_temp.assert_ok('Storage overwrites/moves denied', (select count(*) = 0 from changed));
with removed as (
  delete from storage.objects where name = pg_temp.test_path('listing_bed','photo_public') returning id
) select pg_temp.assert_ok('linked Storage object cannot be deleted', (select count(*) = 0 from removed));

select pg_temp.test_actor('landlord_b');
with added as (
  insert into public.listings(title, address, monthly_rent, pricing_unit, currency, total_bed_capacity)
  values ('SQL other owner', 'Development fixture', 150, 'per_bed', 'USD', 1) returning id
) insert into pg_temp.verify_ids select 'listing_other', id from added;
with changed as (
  update public.listings set title = 'Unauthorized' where id = pg_temp.test_id('listing_bed') returning id
) select pg_temp.assert_ok('other landlord cannot edit listing', (select count(*) = 0 from changed));
select pg_temp.expect_error('other landlord cannot publish',
  $$select public.set_listing_status(pg_temp.test_id('listing_draft'),'published')$$, '42501');
select pg_temp.expect_error('other landlord cannot add amenities',
  $$insert into public.listing_amenities(listing_id,amenity_id)
    select pg_temp.test_id('listing_bed'),id from public.amenities where code='laundry'$$, '42501');
select pg_temp.expect_error('other landlord cannot upload to owner path',
  $$insert into storage.objects(bucket_id,name)
    values('listing-photos',pg_temp.test_path('listing_bed','photo_new'))$$, '42501');

select pg_temp.test_actor('student_a');
select pg_temp.assert_ok('profile read is self-only',
  (select count(*) = 1 and bool_and(id = pg_temp.test_id('student_a')) from public.profiles));
update public.profiles set full_name = 'Updated student', phone = '+12345', preferred_language = 'ar'
where id = pg_temp.test_id('student_a');
select pg_temp.assert_ok('authorized self profile edit succeeds',
  (select full_name = 'Updated student' and phone = '+12345' and preferred_language = 'ar'
   from public.profiles where id = pg_temp.test_id('student_a')));
select pg_temp.expect_error('client profile insert denied',
  $$insert into public.profiles(id,role) values(pg_temp.test_id('student_a'),'student')$$, '42501');
select pg_temp.expect_error('client role escalation denied',
  $$update public.profiles set role='landlord' where id=pg_temp.test_id('student_a')$$, '42501');
select pg_temp.expect_error('profile timestamp edit denied',
  $$update public.profiles set created_at=now() where id=pg_temp.test_id('student_a')$$, '42501');
select pg_temp.expect_error('unsupported profile language denied',
  $$update public.profiles set preferred_language='fr' where id=pg_temp.test_id('student_a')$$, '23514');
with changed as (
  update public.profiles set phone = 'Unauthorized' where id = pg_temp.test_id('student_b') returning id
) select pg_temp.assert_ok('cross-profile edit denied', (select count(*) = 0 from changed));
select pg_temp.expect_error('client backfill execution denied',
  $$select zameel_private.backfill_profile(pg_temp.test_id('student_a'),'landlord')$$, '42501');
select pg_temp.expect_error('client internal transition execution denied',
  $$select zameel_private.transition_booking(null,null,'accept')$$, '42501');
select pg_temp.expect_error('metadata role forgery does not grant listing writes',
  $$insert into public.listings(title,monthly_rent,pricing_unit,currency,total_bed_capacity)
    values('Forged landlord',1,'per_bed','USD',1)$$, '42501');
select pg_temp.expect_error('student cannot upload listing photos',
  $$insert into storage.objects(bucket_id,name)
    values('listing-photos',pg_temp.test_path('listing_bed','photo_new'))$$, '42501');
insert into public.lifestyle_preferences(option_type, answer_kind, value) values
  ('smoking', 'habit', 'nonSmoker'), ('smoking', 'preference', 'noPreference');
select pg_temp.assert_ok('habits and desired conditions stored separately',
  (select count(*) = 2 from public.lifestyle_preferences));
select pg_temp.assert_ok('unanswered questionnaire dimensions remain absent',
  not exists (select 1 from public.lifestyle_preferences where option_type <> 'smoking'));
insert into public.lifestyle_preferences(option_type, answer_kind, value) values
  ('sleep_schedule', 'habit', 'average'),
  ('study_atmosphere', 'preference', 'librarySilence'),
  ('dish_policy', 'preference', 'weekend'),
  ('guest_preference', 'preference', 'none'),
  ('room_sharing', 'preference', 'tripleRoom');
do $quiz_values$
declare
  v_answer record;
begin
  -- Exercise every actual Dart enum.name; no lossy draft-value mapping.
  for v_answer in select * from (values
    ('smoking', 'habit', 'nonSmoker'), ('smoking', 'habit', 'smoker'), ('smoking', 'habit', 'occasionally'),
    ('smoking', 'preference', 'noPreference'), ('smoking', 'preference', 'smokeFree'),
    ('smoking', 'preference', 'comfortableWithSmoking'),
    ('sleep_schedule', 'habit', 'earlyBird'), ('sleep_schedule', 'habit', 'average'), ('sleep_schedule', 'habit', 'nightOwl'),
    ('study_atmosphere', 'preference', 'librarySilence'), ('study_atmosphere', 'preference', 'ambient'),
    ('study_atmosphere', 'preference', 'social'),
    ('dish_policy', 'preference', 'immediate'), ('dish_policy', 'preference', 'sameDay'), ('dish_policy', 'preference', 'weekend'),
    ('guest_preference', 'preference', 'occasional'), ('guest_preference', 'preference', 'anytime'), ('guest_preference', 'preference', 'none'),
    ('room_sharing', 'preference', 'privateRoom'), ('room_sharing', 'preference', 'doubleRoom'), ('room_sharing', 'preference', 'tripleRoom')
  ) as answers(option_type, answer_kind, value) loop
    update public.lifestyle_preferences set value = v_answer.value
    where option_type = v_answer.option_type and answer_kind = v_answer.answer_kind;
    if not found then
      raise exception 'FAIL: missing questionnaire fixture % / %', v_answer.option_type, v_answer.answer_kind;
    end if;
  end loop;
end;
$quiz_values$;
select pg_temp.assert_ok('all Dart questionnaire enum names are accepted',
  (select count(*) = 7 from public.lifestyle_preferences));
select pg_temp.expect_error('desired smoke-free condition is not a smoking habit',
  $$update public.lifestyle_preferences set value='smokeFree' where option_type='smoking' and answer_kind='habit'$$, '23514');
select pg_temp.expect_error('draft flexible sleep value is not a current questionnaire answer',
  $$update public.lifestyle_preferences set value='flexible' where option_type='sleep_schedule'$$, '23514');
select pg_temp.expect_error('invalid preference option rejected',
  $$insert into public.lifestyle_preferences(option_type,answer_kind,value)
    values('sleep_schedule','habit','smoker')$$, '23514');
select pg_temp.expect_error('preference ownership cannot be supplied',
  $$insert into public.lifestyle_preferences(user_id,option_type,answer_kind,value)
    values(pg_temp.test_id('student_b'),'smoking','habit','smoker')$$, '42501');
insert into pg_temp.verify_ids
select 'booking_a', id from public.submit_booking(pg_temp.test_id('listing_bed'), pg_temp.test_id('request_a'), 'Hello');
select pg_temp.assert_ok('submission pending and snapshot explicit',
  (select status = 'pending' and snapshot_pricing_unit = 'per_bed'
    and snapshot_monthly_rent = 100 and snapshot_currency = 'USD'
   from public.bookings where id = pg_temp.test_id('booking_a')));
select pg_temp.assert_ok('same submit retry returns the same booking',
  (select id = pg_temp.test_id('booking_a')
   from public.submit_booking(pg_temp.test_id('listing_bed'), pg_temp.test_id('request_a'), 'Hello')));
select pg_temp.expect_error('changed retry payload rejected',
  $$select public.submit_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('request_a'),'Changed')$$,
  '22023', 'idempotency_key_payload_mismatch');
select pg_temp.expect_error('request key cannot move to another listing',
  $$select public.submit_booking(pg_temp.test_id('listing_second'),pg_temp.test_id('request_a'),'Hello')$$,
  '22023', 'idempotency_key_listing_mismatch');
select pg_temp.expect_error('duplicate active request rejected',
  $$select public.submit_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('request_c'))$$,
  '22023', 'active_booking_already_exists');
select pg_temp.expect_error('per_room bookings explicitly unsupported',
  $$select public.submit_booking(pg_temp.test_id('listing_room'),pg_temp.test_id('request_c'))$$,
  '22023', 'pricing_unit_not_supported');
select pg_temp.expect_error('per_property bookings explicitly unsupported',
  $$select public.submit_booking(pg_temp.test_id('listing_property'),pg_temp.test_id('request_c'))$$,
  '22023', 'pricing_unit_not_supported');
select pg_temp.expect_error('draft booking denied',
  $$select public.submit_booking(pg_temp.test_id('listing_draft'),pg_temp.test_id('request_c'))$$, '42501');
select pg_temp.expect_error('raw booking insertion denied',
  $$insert into public.bookings(listing_id,student_id,request_id)
    values(pg_temp.test_id('listing_bed'),pg_temp.test_id('student_a'),pg_temp.test_id('request_c'))$$, '42501');
select pg_temp.expect_error('raw booking status write denied',
  $$update public.bookings set status='accepted' where id=pg_temp.test_id('booking_a')$$, '42501');
select pg_temp.expect_error('raw resident creation denied',
  $$insert into public.listing_residents(booking_id,listing_id,user_id)
    values(pg_temp.test_id('booking_a'),pg_temp.test_id('listing_bed'),pg_temp.test_id('student_a'))$$, '42501');

select pg_temp.test_actor('student_b');
insert into pg_temp.verify_ids select 'booking_b', id
from public.submit_booking(pg_temp.test_id('listing_bed'), pg_temp.test_id('request_b'));
select pg_temp.assert_ok('second pending request does not reserve the last bed',
  (select occupied_beds = 0 and available_beds = 1
   from public.listings where id = pg_temp.test_id('listing_bed')));
select pg_temp.assert_ok('students cannot read each others bookings or preferences',
  not exists (select 1 from public.bookings where id = pg_temp.test_id('booking_a'))
  and not exists (select 1 from public.lifestyle_preferences where user_id = pg_temp.test_id('student_a')));
select pg_temp.expect_error('student cannot cancel another student request',
  $$select public.cancel_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_a'))$$, '42501');
select pg_temp.expect_error('student cannot accept a request',
  $$select public.accept_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_b'))$$, '42501');

select pg_temp.test_actor('landlord_b');
select pg_temp.expect_error('wrong landlord cannot accept booking',
  $$select public.accept_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_a'))$$, '42501');
select pg_temp.assert_ok('wrong landlord cannot read booking members',
  not exists (select 1 from public.bookings where id in (pg_temp.test_id('booking_a'),pg_temp.test_id('booking_b'))));
select pg_temp.test_actor('landlord_a');
select pg_temp.expect_error('booking must match exact listing even for its owner',
  $$select public.accept_booking(pg_temp.test_id('listing_second'),pg_temp.test_id('booking_a'))$$, '42501');
select pg_temp.expect_error('unit edit with active requests denied',
  $$update public.listings set pricing_unit='per_room' where id=pg_temp.test_id('listing_bed')$$,
  '22023', 'pricing_unit_has_active_bookings');
update public.listings set monthly_rent = 150 where id = pg_temp.test_id('listing_bed');
select pg_temp.assert_ok('price edits do not alter the requested price snapshot',
  (select snapshot_monthly_rent = 100 from public.bookings where id = pg_temp.test_id('booking_a')));
select public.set_listing_status(pg_temp.test_id('listing_bed'), 'archived');
select pg_temp.expect_error('archived listing cannot accept pending request',
  $$select public.accept_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_a'))$$,
  '22023', 'listing_not_published');
select pg_temp.test_actor('student_a');
select pg_temp.assert_ok('own submission retry works after archiving',
  (select id = pg_temp.test_id('booking_a')
   from public.submit_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('request_a'),'Hello')));
select pg_temp.assert_ok('archived listing and photos hidden from student',
  not exists (select 1 from public.listings where id=pg_temp.test_id('listing_bed'))
  and not exists (select 1 from public.listing_photos where listing_id=pg_temp.test_id('listing_bed'))
  and not exists (select 1 from storage.objects where name=pg_temp.test_path('listing_bed','photo_public')));
select pg_temp.test_actor('landlord_a');
select public.set_listing_status(pg_temp.test_id('listing_bed'), 'published');
select pg_temp.assert_ok('accept moves exactly one request to accepted',
  (select status = 'accepted' from public.accept_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_a'))));
select pg_temp.assert_ok('accept replay is idempotent',
  (select id = pg_temp.test_id('booking_a') and status='accepted'
   from public.accept_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_a'))));
select pg_temp.assert_ok('accept creates exactly one resident and consumes one bed',
  (select occupied_beds=1 and available_beds=0 from public.listings where id=pg_temp.test_id('listing_bed'))
  and (select count(*)=1 from public.listing_residents where booking_id=pg_temp.test_id('booking_a') and left_at is null));
select pg_temp.expect_error('second accept cannot overbook',
  $$select public.accept_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_b'))$$,
  '22023', 'listing_full');
select pg_temp.expect_error('accepted booking cannot be rejected',
  $$select public.reject_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_a'))$$,
  '22023', 'booking_transition_not_allowed');
select pg_temp.expect_error('cannot reduce capacity below occupancy',
  $$update public.listings set total_bed_capacity=0 where id=pg_temp.test_id('listing_bed')$$, '23514');
select pg_temp.assert_ok('landlord cannot read resident profiles or lifestyle answers',
  not exists (select 1 from public.profiles where id=pg_temp.test_id('student_a'))
  and not exists (select 1 from public.lifestyle_preferences where user_id=pg_temp.test_id('student_a')));
select pg_temp.test_actor('student_b');
select pg_temp.assert_ok('unrelated student cannot read current resident identity',
  not exists (select 1 from public.listing_residents where listing_id=pg_temp.test_id('listing_bed')));
select pg_temp.test_actor('student_a');
select pg_temp.assert_ok('member can read only their own resident row',
  (select count(*)=1 and bool_and(user_id=pg_temp.test_id('student_a')) from public.listing_residents));
select pg_temp.assert_ok('accepted student cancellation succeeds',
  (select status='cancelled' from public.cancel_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_a'))));
select pg_temp.assert_ok('cancel replay is idempotent',
  (select status='cancelled' from public.cancel_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_a'))));
select pg_temp.assert_ok('accepted cancellation releases exactly one bed and retains history',
  (select occupied_beds=0 and available_beds=1 from public.listings where id=pg_temp.test_id('listing_bed'))
  and (select count(*)=1 and bool_and(left_at is not null)
       from public.listing_residents where booking_id=pg_temp.test_id('booking_a')));
insert into pg_temp.verify_ids select 'booking_c', id
from public.submit_booking(pg_temp.test_id('listing_bed'), pg_temp.test_id('request_c'));
select pg_temp.assert_ok('new request allowed after prior cancellation',
  (select status='pending' from public.bookings where id=pg_temp.test_id('booking_c')));
select pg_temp.assert_ok('pending cancellation succeeds without resident',
  (select status='cancelled' and responded_at is null
   from public.cancel_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_c'))));
select pg_temp.assert_ok('submit retry after cancellation returns terminal result',
  (select id=pg_temp.test_id('booking_c') and status='cancelled'
   from public.submit_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('request_c'))));
select pg_temp.test_actor('landlord_a');
select pg_temp.expect_error('cancelled booking cannot be accepted',
  $$select public.accept_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_a'))$$,
  '22023', 'booking_transition_not_allowed');
select pg_temp.assert_ok('reject pending succeeds',
  (select status='rejected' from public.reject_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_b'))));
select pg_temp.assert_ok('reject replay is idempotent',
  (select status='rejected' from public.reject_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_b'))));
select pg_temp.test_actor('student_b');
select pg_temp.expect_error('rejected booking cannot be cancelled',
  $$select public.cancel_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('booking_b'))$$,
  '22023', 'booking_transition_not_allowed');

reset role;
select pg_temp.expect_error('resident FK enforces exact booking/listing/student identity',
  $$insert into public.listing_residents(booking_id,listing_id,user_id)
    values(pg_temp.test_id('booking_b'),pg_temp.test_id('listing_second'),pg_temp.test_id('student_a'))$$,
  '23503');
select pg_temp.assert_ok('occupancy equals accepted bookings and current residents',
  not exists (
    select 1 from public.listings l where l.id in (select id from pg_temp.verify_ids where key like 'listing_%')
      and (l.occupied_beds <> (select count(*) from public.bookings b where b.listing_id=l.id and b.status='accepted')
        or l.occupied_beds <> (select count(*) from public.listing_residents r where r.listing_id=l.id and r.left_at is null)
        or l.occupied_beds > l.total_bed_capacity)
  ));

-- Deliberately add overly broad policies inside this ROLLED-BACK transaction to
-- prove the bucket-scoped RESTRICTIVE guards still protect the photo bucket.
create policy verification_only_broad_objects on storage.objects for all to anon, authenticated
  using (true) with check (true);
create policy verification_only_broad_buckets on storage.buckets for all to anon, authenticated
  using (true) with check (true);
set local role anon;
select pg_temp.test_actor(null);
select pg_temp.assert_ok('anonymous reads only published fixture listings',
  (select count(*)=4 from public.listings where id in (select id from pg_temp.verify_ids where key like 'listing_%')));
select pg_temp.assert_ok('anonymous reads only published photo metadata',
  (select count(*)=1 from public.listing_photos
   where listing_id in (pg_temp.test_id('listing_bed'),pg_temp.test_id('listing_draft'))));
select pg_temp.assert_ok('anonymous cannot read draft or unlinked Storage objects',
  (select count(*)=1 from storage.objects where name in (
    pg_temp.test_path('listing_bed','photo_public'), pg_temp.test_path('listing_draft','photo_draft'),
    pg_temp.test_path('listing_bed','photo_orphan'))));
select pg_temp.assert_ok('dictionary links do not reveal draft listings',
  (select count(*)=1 from public.listing_amenities
   where listing_id in (pg_temp.test_id('listing_bed'),pg_temp.test_id('listing_draft')))
  and (select count(*)=1 from public.listing_house_rules
       where listing_id in (pg_temp.test_id('listing_bed'),pg_temp.test_id('listing_draft'))));
select pg_temp.expect_error('anonymous profile access denied', $$select * from public.profiles$$, '42501');
select pg_temp.expect_error('anonymous raw preferences access denied', $$select * from public.lifestyle_preferences$$, '42501');
select pg_temp.expect_error('anonymous bookings access denied', $$select * from public.bookings$$, '42501');
select pg_temp.expect_error('anonymous residents access denied', $$select * from public.listing_residents$$, '42501');
select pg_temp.expect_error('anonymous booking RPC denied',
  $$select public.submit_booking(pg_temp.test_id('listing_bed'),pg_temp.test_id('request_d'))$$, '42501');
select pg_temp.expect_error('broad Storage policy does not allow anonymous upload',
  $$insert into storage.objects(bucket_id,name)
    values('listing-photos',pg_temp.test_path('listing_bed','photo_new'))$$, '42501');
with removed as (
  delete from storage.objects where name=pg_temp.test_path('listing_bed','photo_public') returning id
) select pg_temp.assert_ok('broad Storage policy does not allow anonymous delete', (select count(*)=0 from removed));
with changed as (
  update storage.buckets set public=true where id='listing-photos' returning id
) select pg_temp.assert_ok('client cannot make photo bucket public', (select count(*)=0 from changed));

set local role authenticated;
select pg_temp.test_actor('landlord_b');
select pg_temp.expect_error('broad Storage policy does not allow cross-owner upload',
  $$insert into storage.objects(bucket_id,name)
    values('listing-photos',pg_temp.test_path('listing_bed','photo_new'))$$, '42501');
with removed as (
  delete from storage.objects where name=pg_temp.test_path('listing_bed','photo_public') returning id
) select pg_temp.assert_ok('broad Storage policy does not allow cross-owner deletion', (select count(*)=0 from removed));
select pg_temp.test_actor('landlord_a');
with changed as (
  update storage.objects set name=pg_temp.test_path('listing_bed','photo_new')
  where name=pg_temp.test_path('listing_bed','photo_public') returning id
) select pg_temp.assert_ok('broad Storage policy does not allow owner overwrite', (select count(*)=0 from changed));
with removed as (
  delete from storage.objects where name=pg_temp.test_path('listing_bed','photo_public') returning id
) select pg_temp.assert_ok('broad Storage policy does not bypass attached-photo protection', (select count(*)=0 from removed));
delete from public.listing_photos where storage_path=pg_temp.test_path('listing_bed','photo_public');
with removed as (
  delete from storage.objects where name=pg_temp.test_path('listing_bed','photo_public') returning id
) select pg_temp.assert_ok('owner can delete after unlinking photo metadata', (select count(*)=1 from removed));

reset role;
select count(*)::text || ' SQL assertions passed; all verification fixtures will now roll back.' as result
from pg_temp.verify_results;
rollback;
