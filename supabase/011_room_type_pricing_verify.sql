-- Rollback-only verification AFTER 010, as administrator in a QUIET, DISPOSABLE
-- DEVELOPMENT database. Run the WHOLE file; NEVER replace ROLLBACK with COMMIT.
-- After a failure issue ROLLBACK before further SQL. Do not use production or a
-- database with external Auth/DB hooks: their side effects may not roll back.
-- All writes target random fixture identities/listings or a new test university.
-- No real user rows, credentials, email, Storage objects or provider calls are used.
-- Claim GUCs/SET ROLE below are administrator-only test impersonation, not APIs.
-- No pgTAP/extensions required. This does not test hosted JWT/PostgREST behavior.
--
-- Separately, an isolated migration harness should snapshot generic listings and
-- legacy pending/accepted bookings BEFORE 010, compare after, verify refusal of
-- drift/reruns, and confirm the 007/009 fingerprint and v1 function are unchanged.
-- Do not invoke a committing migration inside this rollback-only verifier.
--
-- Native two-connection race checks (disposable fixtures only):
-- 1. Create one double room and one triple room, accept one double request, then
--    create two more pending double requests. A: BEGIN, impersonate the owner,
--    accept the first, keep open. B: accept the second; it must wait on the listing.
--    COMMIT A; B must fail room_type_full even while the triple room has free beds.
-- 2. Race submit against disabling its type, and enabling options against a legacy
--    submit. If submit wins, the edit must fail room_options_have_active_bookings;
--    if edit wins, submit must validate the new selection/shape, never guess a type.
-- 3. Race count reduction/conversion against accept/cancel. Counts cannot fall
--    below occupied capacity; no accepted booking can be left unassigned.
-- 4. Race duplicate submit, same-action accept/cancel and conflicting decisions.
--    Repeat with cancellation BEGIN before acceptance, but acceptance called first.
--    Each accepted booking owns exactly one resident link and one typed/aggregate
--    bed; pending owns none. Same-action replay changes no counters or timestamps.
-- Single-session/embedded PostgreSQL cannot establish two-connection scheduling.
-- Use the API's normal READ COMMITTED isolation for these manual race checks.

begin;
set local search_path = pg_catalog;
set local extra_float_digits = 1;
set local timezone = 'UTC';

do $preflight$
begin
  if pg_catalog.to_regprocedure('public.submit_booking(uuid,uuid,text,text)') is null
     or pg_catalog.to_regprocedure('public.submit_booking(uuid,uuid,text)') is not null
     or pg_catalog.to_regprocedure('public.search_listings_by_university_v2(integer,double precision,uuid,integer)') is null then
    raise exception 'room_verifier_requires_010: install the complete room-pricing migration first';
  end if;
end;
$preflight$;

create temporary table rp_ids (key text primary key, id uuid not null);
create temporary table rp_results (name text not null);
create temporary table rp_snapshots (key text primary key, value jsonb not null);
create temporary table rp_university (id integer primary key);
grant select, insert, update on pg_temp.rp_ids, pg_temp.rp_results, pg_temp.rp_snapshots
  to anon, authenticated, service_role;
grant select on pg_temp.rp_university to anon, authenticated, service_role;

create function pg_temp.rp_id(p_key text)
returns uuid language sql stable security invoker set search_path = '' as $test$
  select id from pg_temp.rp_ids where key = p_key;
$test$;
create function pg_temp.rp_actor(p_key text)
returns void language plpgsql security invoker set search_path = '' as $test$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub',coalesce(pg_temp.rp_id(p_key)::text,''),true);
  perform pg_catalog.set_config('request.jwt.claim.role',current_user::text,true);
  perform pg_catalog.set_config('request.jwt.claims',pg_catalog.jsonb_build_object(
    'sub',pg_temp.rp_id(p_key),'role',current_user)::text,true);
end;
$test$;
create function pg_temp.rp_assert(p_name text, p_ok boolean)
returns void language plpgsql security invoker set search_path = '' as $test$
begin
  if p_ok is distinct from true then raise exception 'FAIL: %', p_name; end if;
  insert into pg_temp.rp_results values (p_name);
end;
$test$;
create function pg_temp.rp_error(p_name text, p_sql text, p_state text, p_message text default null)
returns void language plpgsql security invoker set search_path = '' as $test$
declare
  v_state text;
  v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_state = p_state and (p_message is null or v_message = p_message) then
      insert into pg_temp.rp_results values (p_name);
      return;
    end if;
    raise exception 'FAIL: %; expected % / %, got % / %', p_name,p_state,p_message,v_state,v_message;
  end;
  raise exception 'FAIL: %; statement succeeded, expected %', p_name,p_state;
end;
$test$;
revoke all on function pg_temp.rp_id(text), pg_temp.rp_actor(text), pg_temp.rp_assert(text,boolean),
  pg_temp.rp_error(text,text,text,text) from public;
grant execute on function pg_temp.rp_id(text), pg_temp.rp_actor(text), pg_temp.rp_assert(text,boolean),
  pg_temp.rp_error(text,text,text,text) to anon, authenticated, service_role;

select pg_temp.rp_assert('six exact room column types, defaults and nullability',
  (select count(*) = 6 and bool_and(
    case when a.attname like '%monthly_rent' then a.atttypid = 'numeric'::regtype
      and a.atttypmod = 786438 and not a.attnotnull and d.adbin is null
    else a.atttypid = 'integer'::regtype and a.attnotnull and pg_catalog.pg_get_expr(d.adbin,d.adrelid) = '0' end
    and a.attgenerated = '' and a.attidentity = '')
   from pg_catalog.pg_attribute a left join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = 'public.listings'::regclass and a.attname in
     ('double_room_count','double_room_monthly_rent','double_room_occupied_beds',
      'triple_room_count','triple_room_monthly_rent','triple_room_occupied_beds')));
select pg_temp.rp_assert('nullable text selection preserves null history',
  exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = 'public.bookings'::regclass
    and a.attname = 'room_type' and a.atttypid = 'text'::regtype and not a.attnotnull and not a.atthasdef));
select pg_temp.rp_assert('single unambiguous four-argument submission with two defaults',
  (select count(*) = 1 and bool_and(p.prosecdef and not p.proretset and p.provolatile = 'v'
    and p.prorettype = 'public.bookings'::regtype and p.pronargdefaults = 2
    and p.proargnames = array['p_listing_id','p_request_id','p_message','p_room_type']
    and p.proconfig = array['search_path=""']
    and pg_catalog.pg_get_expr(p.proargdefaults,0) = 'NULL::text, NULL::text')
   from pg_catalog.pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'submit_booking'));
select pg_temp.rp_assert('fixed-action wrappers retain their signatures and guarded execution',
  (select count(*) = 3 and bool_and(p.prosecdef and p.pronargdefaults = 0
    and p.proargnames = array['p_listing_id','p_booking_id'] and p.proconfig = array['search_path=""'])
   from pg_catalog.pg_proc p where p.oid in ('public.accept_booking(uuid,uuid)'::regprocedure,
     'public.reject_booking(uuid,uuid)'::regprocedure,'public.cancel_booking(uuid,uuid)'::regprocedure)));
select pg_temp.rp_assert('v2 is invoker stable and appends exactly six fields to v1',
  (select not p.prosecdef and p.provolatile = 's' and p.proretset and p.pronargdefaults = 3
    and p.proargnames[1:22] = old.proargnames and p.proallargtypes[1:22] = old.proallargtypes
    and p.proargnames[23:28] = array['double_room_count','double_room_monthly_rent','double_room_occupied_beds',
      'triple_room_count','triple_room_monthly_rent','triple_room_occupied_beds']
    and p.proconfig = array['search_path=""']
    and pg_catalog.pg_get_expr(p.proargdefaults,0) = pg_catalog.pg_get_expr(old.proargdefaults,0)
   from pg_catalog.pg_proc p cross join pg_catalog.pg_proc old
   where p.oid = 'public.search_listings_by_university_v2(integer,double precision,uuid,integer)'::regprocedure
     and old.oid = 'public.search_listings_by_university(integer,double precision,uuid,integer)'::regprocedure));
select pg_temp.rp_assert('listing, booking and resident RLS remain enabled with original policies',
  (select count(*) = 3 and bool_and(relrowsecurity) from pg_catalog.pg_class where oid in
    ('public.listings'::regclass,'public.bookings'::regclass,'public.listing_residents'::regclass))
  and (select count(*) = 6 from pg_catalog.pg_policy where polrelid in
    ('public.listings'::regclass,'public.bookings'::regclass,'public.listing_residents'::regclass)));

do $permissions$
declare
  v_role text;
  v_column text;
  v_signature text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    perform pg_temp.rp_assert(v_role || ' has no blanket listing/booking/resident write grant',
      not pg_catalog.has_table_privilege(v_role,'public.listings','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      and not pg_catalog.has_any_column_privilege(v_role,'public.bookings','INSERT,UPDATE,REFERENCES')
      and not pg_catalog.has_any_column_privilege(v_role,'public.listing_residents','INSERT,UPDATE,REFERENCES')
      and not pg_catalog.has_table_privilege(v_role,'public.bookings','DELETE,TRUNCATE,TRIGGER')
      and not pg_catalog.has_table_privilege(v_role,'public.listing_residents','DELETE,TRUNCATE,TRIGGER'));
    foreach v_column in array array['double_room_count','double_room_monthly_rent','triple_room_count','triple_room_monthly_rent'] loop
      perform pg_temp.rp_assert(v_role || ' editable column ' || v_column,
        pg_catalog.has_column_privilege(v_role,'public.listings',v_column,'INSERT') = (v_role = 'authenticated')
        and pg_catalog.has_column_privilege(v_role,'public.listings',v_column,'UPDATE') = (v_role = 'authenticated'));
    end loop;
    foreach v_column in array array['id','landlord_id','status','occupied_beds','available_beds',
      'double_room_occupied_beds','triple_room_occupied_beds','created_at','updated_at'] loop
      perform pg_temp.rp_assert(v_role || ' cannot write protected listing column ' || v_column,
        not pg_catalog.has_column_privilege(v_role,'public.listings',v_column,'INSERT,UPDATE,REFERENCES'));
    end loop;
    foreach v_signature in array array['zameel_private.guard_listing_room_options()',
      'zameel_private.guard_booking_room_type()','zameel_private.transition_booking(uuid,uuid,text)'] loop
      perform pg_temp.rp_assert(v_role || ' cannot invoke ' || v_signature,
        not pg_catalog.has_function_privilege(v_role,v_signature,'EXECUTE'));
    end loop;
    perform pg_temp.rp_assert(v_role || ' submit RPC permission',
      pg_catalog.has_function_privilege(v_role,'public.submit_booking(uuid,uuid,text,text)','EXECUTE') = (v_role = 'authenticated'));
    perform pg_temp.rp_assert(v_role || ' v2 search permission',
      pg_catalog.has_function_privilege(v_role,'public.search_listings_by_university_v2(integer,double precision,uuid,integer)','EXECUTE')
        = (v_role in ('anon','authenticated')));
  end loop;
end;
$permissions$;

insert into pg_temp.rp_ids select key,gen_random_uuid() from unnest(array[
  'owner','other_owner','student_a','student_b','student_c','student_d',
  'student_e','student_f','student_g','student_h','missing_profile',
  'request_a','request_b','request_c','request_d','request_e','request_f','request_g','request_h',
  'request_legacy','request_legacy_second','request_zero','request_unused'
]) key;
insert into auth.users(id,email,raw_user_meta_data)
select id,'room-sql+' || id::text || '@example.invalid',jsonb_build_object(
  'role',case when key in ('owner','other_owner') then 'landlord' else 'student' end,
  'name','Rollback-only room fixture ' || key)
from pg_temp.rp_ids where key in ('owner','other_owner','student_a','student_b','student_c',
  'student_d','student_e','student_f','student_g','student_h','missing_profile');
delete from public.profiles where id = pg_temp.rp_id('missing_profile');
insert into pg_temp.rp_university select n from generate_series(2147483647,2147483548,-1) n
where not exists (select 1 from public.universities u where u.id = n) order by n desc limit 1;
select pg_temp.rp_assert('allocated isolated test university without replacing catalogue data',
  (select count(*) = 1 from pg_temp.rp_university));
insert into public.universities(id,name,city,latitude,longitude)
select id,'Rollback-only room verifier','SQL fixture',30.0276,31.21014 from pg_temp.rp_university;

set local role authenticated;
select pg_temp.rp_actor('owner');
-- Deliberately omit generic rent/capacity: BEFORE INSERT derives both before NOT NULL checks.
with added as (
  insert into public.listings(title,latitude,longitude,pricing_unit,currency,
    double_room_count,double_room_monthly_rent,triple_room_count,triple_room_monthly_rent)
  values ('SQL rooms',30.0276,31.21014,'per_bed','EGP',1,300,1,200) returning id
) insert into pg_temp.rp_ids select 'typed',id from added;
with added as (
  insert into public.listings(title,latitude,longitude,monthly_rent,pricing_unit,currency,total_bed_capacity)
  values ('SQL generic',30.0276,31.21014,777,'per_bed','EGP',1) returning id
) insert into pg_temp.rp_ids select 'generic',id from added;
with added as (
  insert into public.listings(title,latitude,longitude,pricing_unit,currency,double_room_count,double_room_monthly_rent)
  values ('SQL free double',30.0276,31.21014,'per_bed','EGP',1,0) returning id
) insert into pg_temp.rp_ids select 'double_only',id from added;
with added as (
  insert into public.listings(title,latitude,longitude,pricing_unit,currency,triple_room_count,triple_room_monthly_rent)
  values ('SQL triple',30.0276,31.21014,'per_bed','EGP',2,123.45) returning id
) insert into pg_temp.rp_ids select 'triple_only',id from added;
with added as (
  insert into public.listings(title,latitude,longitude,pricing_unit,currency,double_room_count,double_room_monthly_rent)
  values ('SQL private room draft',30.0276,31.21014,'per_bed','EGP',1,100) returning id
) insert into pg_temp.rp_ids select 'draft',id from added;
select pg_temp.rp_assert('typed create derives minimum price and total capacity, counters remain zero',
  (select monthly_rent = 200 and total_bed_capacity = 5 and occupied_beds = 0 and available_beds = 5
    and double_room_occupied_beds = 0 and triple_room_occupied_beds = 0 and status = 'draft'
    and landlord_id = pg_temp.rp_id('owner') from public.listings where id = pg_temp.rp_id('typed')));
select pg_temp.rp_assert('generic defaults leave legacy price/capacity untouched',
  (select monthly_rent = 777 and total_bed_capacity = 1 and occupied_beds = 0
    and double_room_count = 0 and triple_room_count = 0
    and double_room_monthly_rent is null and triple_room_monthly_rent is null
    and double_room_occupied_beds = 0 and triple_room_occupied_beds = 0
   from public.listings where id = pg_temp.rp_id('generic')));
select pg_temp.rp_assert('zero rate is enabled and triple rooms multiply capacity by three',
  (select monthly_rent = 0 and total_bed_capacity = 2 from public.listings where id = pg_temp.rp_id('double_only'))
  and (select monthly_rent = 123.45 and total_bed_capacity = 6 from public.listings where id = pg_temp.rp_id('triple_only')));

do $invalid_options$
declare
  v_type text;
  v_case record;
begin
  foreach v_type in array array['double','triple'] loop
    for v_case in select * from (values
      ('_room_count = -1','23514'), ('_room_count = 0','23514'), ('_room_count = null','23502'),
      ('_room_monthly_rent = null','23514'), ('_room_monthly_rent = -0.01','23514'),
      ('_room_monthly_rent = ''NaN''','23514'), ('_room_monthly_rent = 10000000000','22003'),
      ('_room_count = 2147483647','23514')
    ) as cases(assignment,state) loop
      perform pg_temp.rp_error('reject ' || v_type || v_case.assignment,
        'update public.listings set ' || v_type || v_case.assignment || ' where id = pg_temp.rp_id(''typed'')',v_case.state);
    end loop;
    perform pg_temp.rp_error('protected ' || v_type || ' occupancy UPDATE',
      'update public.listings set ' || v_type || '_room_occupied_beds = 1 where id = pg_temp.rp_id(''typed'')','42501');
    perform pg_temp.rp_error('protected ' || v_type || ' occupancy INSERT',
      'insert into public.listings(title,pricing_unit,currency,' || v_type || '_room_count,' || v_type ||
      '_room_monthly_rent,' || v_type || '_room_occupied_beds) values(''Forged'',''per_bed'',''EGP'',1,100,1)','42501');
  end loop;
end;
$invalid_options$;
select pg_temp.rp_error('typed options cannot use per_room',
  $$update public.listings set pricing_unit = 'per_room' where id = pg_temp.rp_id('typed')$$,'23514');
select pg_temp.rp_error('typed options cannot use per_property',
  $$update public.listings set pricing_unit = 'per_property' where id = pg_temp.rp_id('typed')$$,'23514');
select pg_temp.rp_error('aggregate occupancy remains protected',
  $$update public.listings set occupied_beds = 1 where id = pg_temp.rp_id('typed')$$,'42501');
select pg_temp.rp_error('status remains protected',
  $$update public.listings set status = 'published' where id = pg_temp.rp_id('typed')$$,'42501');
select pg_temp.rp_error('ownership remains protected',
  $$update public.listings set landlord_id = pg_temp.rp_id('other_owner') where id = pg_temp.rp_id('typed')$$,'42501');
insert into pg_temp.rp_snapshots select 'typed_cas',to_jsonb(l) from public.listings l where id = pg_temp.rp_id('typed');
with changed as (
  update public.listings set double_room_count = 2,double_room_monthly_rent = 320,
    triple_room_count = 1,triple_room_monthly_rent = 180,monthly_rent = 999,total_bed_capacity = 999
  where id = pg_temp.rp_id('typed') and updated_at =
    (select (value ->> 'updated_at')::timestamptz from pg_temp.rp_snapshots where key = 'typed_cas') returning *
) select pg_temp.rp_assert('one atomic CAS edits both types and overrides mixed generic capacity/price',
  (select count(*) = 1 and bool_and(total_bed_capacity = 7 and monthly_rent = 180) from changed));
with changed as (
  update public.listings set double_room_count = 3 where id = pg_temp.rp_id('typed') and updated_at =
    (select (value ->> 'updated_at')::timestamptz from pg_temp.rp_snapshots where key = 'typed_cas') returning id
) select pg_temp.rp_assert('stale CAS cannot partially edit options',(select count(*) = 0 from changed));
update public.listings set double_room_count = 1 where id = pg_temp.rp_id('typed');
update public.listings set double_room_count = 1073741822,double_room_monthly_rent = 9999999999.99,
  triple_room_count = 1,triple_room_monthly_rent = 9999999999.99 where id = pg_temp.rp_id('draft');
select pg_temp.rp_assert('maximum valid aggregate capacity and two-decimal rate are accepted without overflow',
  (select total_bed_capacity = 2147483647 and available_beds = 2147483647 and monthly_rent = 9999999999.99
   from public.listings where id = pg_temp.rp_id('draft')));
update public.listings set double_room_count = 1,double_room_monthly_rent = 100,
  triple_room_count = 0,triple_room_monthly_rent = null where id = pg_temp.rp_id('draft');
select public.set_listing_status(id,'published') from pg_temp.rp_ids
where key in ('typed','generic','double_only','triple_only');

select pg_temp.rp_actor('other_owner');
with changed as (
  update public.listings set double_room_monthly_rent = 1 where id = pg_temp.rp_id('typed') returning id
) select pg_temp.rp_assert('unrelated landlord cannot edit published options',(select count(*) = 0 from changed));
select pg_temp.rp_assert('unrelated landlord cannot read private options',
  not exists (select 1 from public.listings where id = pg_temp.rp_id('draft')));
select pg_temp.rp_actor('student_a');
with changed as (
  update public.listings set triple_room_count = 3 where id = pg_temp.rp_id('typed') returning id
) select pg_temp.rp_assert('student cannot edit option counts',(select count(*) = 0 from changed));
select pg_temp.rp_error('student cannot create typed listing',
  $$insert into public.listings(title,pricing_unit,currency,double_room_count,double_room_monthly_rent)
    values ('Unauthorized','per_bed','EGP',1,100)$$,'42501');
select pg_temp.rp_actor('missing_profile');
select pg_temp.rp_error('missing profile cannot submit',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_unused'),null,'double')$$,
  '42501','student_role_required');

-- Only the new, isolated university is used, so real listings cannot affect pages.
reset role;
insert into public.listing_university_routes(listing_id,university_id,status,distance_m,
  listing_latitude,listing_longitude,university_latitude,university_longitude,routing_version,
  matched_source_latitude,matched_source_longitude,matched_target_latitude,matched_target_longitude)
select l.id,u.id,'ready',case when i.key = 'double_only' then 500 when i.key = 'generic' then 750
  when i.key = 'draft' then 100 else 1000.123456789 end,
  l.latitude,l.longitude,30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',
  l.latitude,l.longitude,30.0276,31.21014
from public.listings l join pg_temp.rp_ids i on i.id = l.id cross join pg_temp.rp_university u
where i.key in ('typed','generic','double_only','triple_only','draft');
select pg_temp.rp_error('database rejects aggregate/type occupancy mismatch even for administrator',
  $$update public.listings set occupied_beds = 1 where id = pg_temp.rp_id('typed')$$,'23514');
select pg_temp.rp_error('database rejects occupancy beyond type capacity',
  $$update public.listings set occupied_beds = 3,double_room_occupied_beds = 3 where id = pg_temp.rp_id('typed')$$,'23514');

set local role authenticated;
select pg_temp.rp_actor('student_a');
select pg_temp.rp_assert('v2 returns options in one flat row with the original discovery fields',
  (select double_room_count = 1 and double_room_monthly_rent = 320 and double_room_occupied_beds = 0
    and triple_room_count = 1 and triple_room_monthly_rent = 180 and triple_room_occupied_beds = 0
    and total_bed_capacity = 5 and monthly_rent = 180 and distance_m = 1000.123456789
   from public.search_listings_by_university_v2((select id from pg_temp.rp_university)) where id = pg_temp.rp_id('typed')));
select pg_temp.rp_assert('v2 preserves every v1 value and result, with no private listing leakage',
  (select count(*) = 4 from public.search_listings_by_university_v2((select id from pg_temp.rp_university)))
  and not exists (
    select to_jsonb(s) from public.search_listings_by_university((select id from pg_temp.rp_university)) s
    except
    select to_jsonb(s) - array['double_room_count','double_room_monthly_rent','double_room_occupied_beds',
      'triple_room_count','triple_room_monthly_rent','triple_room_occupied_beds']
    from public.search_listings_by_university_v2((select id from pg_temp.rp_university)) s));
do $pagination$
declare
  v_row record;
  v_distance double precision;
  v_id uuid;
  v_seen uuid[] := array[]::uuid[];
  v_count integer;
begin
  loop
    v_count := 0;
    for v_row in select * from public.search_listings_by_university_v2(
      (select id from pg_temp.rp_university),v_distance,v_id,2) loop
      perform pg_temp.rp_assert('page tuple strictly advances ' || (cardinality(v_seen) + 1),
        v_id is null or (v_row.distance_m,v_row.id) > (v_distance,v_id));
      v_distance := v_row.distance_m;
      v_id := v_row.id;
      v_seen := array_append(v_seen,v_id);
      v_count := v_count + 1;
    end loop;
    exit when v_count = 0;
  end loop;
  perform pg_temp.rp_assert('v2 keyset pages retain global v1 order across distance ties',
    v_seen = (select array_agg(s.id order by s.ordinality)
      from public.search_listings_by_university((select id from pg_temp.rp_university)) with ordinality s));
end;
$pagination$;
select pg_temp.rp_error('v2 retains limit validation',
  $$select * from public.search_listings_by_university_v2((select id from pg_temp.rp_university),null,null,0)$$,
  '22023','invalid_search_limit');
select pg_temp.rp_error('v2 retains cursor validation',
  $$select * from public.search_listings_by_university_v2((select id from pg_temp.rp_university),1,null)$$,
  '22023','invalid_search_cursor');
select pg_temp.rp_error('v2 retains university validation',
  $$select * from public.search_listings_by_university_v2(0)$$,'22023','university_unavailable');
set local role anon;
select pg_temp.rp_actor(null);
select pg_temp.rp_assert('anonymous discovery exposes only published options',
  (select count(*) = 4 from public.search_listings_by_university_v2((select id from pg_temp.rp_university))));
select pg_temp.rp_error('anonymous submission denied',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_unused'),null,'double')$$,'42501');
select pg_temp.rp_error('anonymous request history denied',$$select * from public.bookings$$,'42501');

set local role authenticated;
select pg_temp.rp_actor('student_a');
select pg_temp.rp_error('old null-selection client fails closed on typed listing',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_a'))$$,'22023','room_type_required');
do $invalid_selection$
declare v_type text;
begin
  foreach v_type in array array['twin','Double',' double ',''] loop
    perform pg_temp.rp_error('invalid selection ' || v_type,pg_catalog.format(
      'select public.submit_booking(pg_temp.rp_id(''typed''),pg_temp.rp_id(''request_a''),null,%L)',v_type),
      '22023','room_type_unavailable');
  end loop;
end;
$invalid_selection$;
select pg_temp.rp_error('disabled double selection rejected',
  $$select public.submit_booking(pg_temp.rp_id('triple_only'),pg_temp.rp_id('request_a'),null,'double')$$,
  '22023','room_type_unavailable');
select pg_temp.rp_error('disabled triple selection rejected',
  $$select public.submit_booking(pg_temp.rp_id('double_only'),pg_temp.rp_id('request_a'),null,'triple')$$,
  '22023','room_type_unavailable');
select pg_temp.rp_error('generic listing requires null selection',
  $$select public.submit_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('request_a'),null,'double')$$,
  '22023','room_type_unavailable');
select pg_temp.rp_error('draft submission remains inaccessible',
  $$select public.submit_booking(pg_temp.rp_id('draft'),pg_temp.rp_id('request_a'),null,'double')$$,'42501','listing_not_accessible');
select pg_temp.rp_error('message length validation retained',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_a'),repeat('x',2001),'double')$$,
  '22023','invalid_booking_request');
insert into pg_temp.rp_ids select 'booking_a',id
from public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_a'),' Hello ','double');
select pg_temp.rp_assert('request chooses double rate, not cheaper summary; snapshot capacities remain aggregate',
  (select room_type = 'double' and message = 'Hello' and snapshot_monthly_rent = 320 and snapshot_currency = 'EGP'
    and snapshot_pricing_unit = 'per_bed' and snapshot_total_beds = 5 and snapshot_occupied_beds = 0 and status = 'pending'
   from public.bookings where id = pg_temp.rp_id('booking_a')));
select pg_temp.rp_error('frozen request type cannot change on replay',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_a'),'Hello','triple')$$,
  '22023','idempotency_key_payload_mismatch');
select pg_temp.rp_error('frozen type cannot disappear on old-client replay',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_a'),'Hello')$$,
  '22023','idempotency_key_payload_mismatch');
select pg_temp.rp_error('frozen message cannot change on replay',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_a'),'Changed','double')$$,
  '22023','idempotency_key_payload_mismatch');
select pg_temp.rp_error('request id cannot move to a different listing',
  $$select public.submit_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('request_a'),'Hello','double')$$,
  '22023','idempotency_key_listing_mismatch');
select pg_temp.rp_error('active request uniqueness retained across type choices',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_unused'),null,'triple')$$,
  '22023','active_booking_already_exists');
select pg_temp.rp_error('client cannot change stored room selection',
  $$update public.bookings set room_type = 'triple' where id = pg_temp.rp_id('booking_a')$$,'42501');
select pg_temp.rp_error('client cannot rewrite quote',
  $$update public.bookings set snapshot_monthly_rent = 0 where id = pg_temp.rp_id('booking_a')$$,'42501');
select pg_temp.rp_error('client cannot write request status',
  $$update public.bookings set status = 'accepted' where id = pg_temp.rp_id('booking_a')$$,'42501');
select pg_temp.rp_error('client cannot insert request directly',
  $$insert into public.bookings(listing_id,student_id,request_id,room_type)
    values(pg_temp.rp_id('typed'),pg_temp.rp_id('student_a'),pg_temp.rp_id('request_unused'),'double')$$,'42501');

select pg_temp.rp_actor('owner');
select pg_temp.rp_error('landlord role cannot submit',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_unused'),null,'double')$$,
  '42501','student_role_required');
select pg_temp.rp_error('pending selected option cannot be disabled',
  $$update public.listings set double_room_count = 0,double_room_monthly_rent = null where id = pg_temp.rp_id('typed')$$,
  '22023','room_options_have_active_bookings');
select pg_temp.rp_error('pending options cannot convert to generic per_room',
  $$update public.listings set double_room_count = 0,double_room_monthly_rent = null,
    triple_room_count = 0,triple_room_monthly_rent = null,pricing_unit = 'per_room' where id = pg_temp.rp_id('typed')$$,
  '22023','room_options_have_active_bookings');
update public.listings set triple_room_count = 0,triple_room_monthly_rent = null where id = pg_temp.rp_id('typed');
select pg_temp.rp_assert('an unused type may be removed while another type has a pending request',
  (select total_bed_capacity = 2 and monthly_rent = 320 and double_room_count = 1 and triple_room_count = 0
   from public.listings where id = pg_temp.rp_id('typed'))
  and (select snapshot_total_beds = 5 from public.bookings where id = pg_temp.rp_id('booking_a')));
update public.listings set triple_room_count = 1,triple_room_monthly_rent = 180 where id = pg_temp.rp_id('typed');
update public.listings set double_room_monthly_rent = 450,triple_room_monthly_rent = 160 where id = pg_temp.rp_id('typed');
select pg_temp.rp_actor('student_a');
select pg_temp.rp_assert('same payload returns original quote after a future price edit',
  (select id = pg_temp.rp_id('booking_a') and snapshot_monthly_rent = 320 and room_type = 'double'
   from public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_a'),'Hello','double')));
do $more_pending$
declare v_key text;
begin
  foreach v_key in array array['b','c','d','e','f','g'] loop
    perform pg_temp.rp_actor('student_' || v_key);
    insert into pg_temp.rp_ids select 'booking_' || v_key,id from public.submit_booking(
      pg_temp.rp_id('typed'),pg_temp.rp_id('request_' || v_key),null,
      case when v_key in ('b','c') then 'double' else 'triple' end);
  end loop;
end;
$more_pending$;
select pg_temp.rp_actor('owner');
select pg_temp.rp_assert('new requests snapshot latest selected rates at submission, never client/summary prices',
  (select snapshot_monthly_rent = 450 from public.bookings where id = pg_temp.rp_id('booking_b'))
  and (select room_type = 'triple' and snapshot_monthly_rent = 160 from public.bookings where id = pg_temp.rp_id('booking_d')));
select pg_temp.rp_assert('overlapping pending requests reserve no aggregate or type capacity',
  (select occupied_beds = 0 and double_room_occupied_beds = 0 and triple_room_occupied_beds = 0
   from public.listings where id = pg_temp.rp_id('typed')));
select pg_temp.rp_actor('student_h');
select pg_temp.rp_assert('unrelated student cannot read requests or residents',
  not exists (select 1 from public.bookings where listing_id = pg_temp.rp_id('typed'))
  and not exists (select 1 from public.listing_residents where listing_id = pg_temp.rp_id('typed')));
select pg_temp.rp_error('unrelated student cannot cancel typed request',
  $$select public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_a'))$$,'42501','booking_not_accessible');
select pg_temp.rp_error('student cannot accept typed request',
  $$select public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_a'))$$,'42501','booking_action_not_authorized');
select pg_temp.rp_actor('other_owner');
select pg_temp.rp_assert('unrelated owner cannot read requests',
  not exists (select 1 from public.bookings where listing_id = pg_temp.rp_id('typed')));
select pg_temp.rp_error('unrelated owner cannot accept typed request',
  $$select public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_a'))$$,'42501','booking_not_accessible');

select pg_temp.rp_actor('owner');
select pg_temp.rp_error('request must match exact listing',
  $$select public.accept_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('booking_a'))$$,'42501','booking_not_accessible');
select public.set_listing_status(pg_temp.rp_id('typed'),'archived');
select pg_temp.rp_error('typed pending request cannot be accepted after unpublication',
  $$select public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_a'))$$,'22023','listing_not_published');
select pg_temp.rp_actor('student_a');
select pg_temp.rp_assert('typed pending submission replays its original quote while listing is hidden',
  (select id = pg_temp.rp_id('booking_a') and room_type = 'double' and snapshot_monthly_rent = 320 and status = 'pending'
   from public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_a'),'Hello','double'))
  and not exists (select 1 from public.listings where id = pg_temp.rp_id('typed')));
select pg_temp.rp_actor('owner');
select public.set_listing_status(pg_temp.rp_id('typed'),'published');
insert into pg_temp.rp_snapshots select 'accepted_a',to_jsonb(b)
from public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_a')) b;
select pg_temp.rp_assert('accept replay preserves entire request including timestamps',
  (select to_jsonb(b) = (select value from pg_temp.rp_snapshots where key = 'accepted_a')
   from public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_a')) b));
select public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_b'));
select pg_temp.rp_assert('accept increments only selected type and aggregate exactly once',
  (select occupied_beds = 2 and double_room_occupied_beds = 2 and triple_room_occupied_beds = 0 and available_beds = 3
   from public.listings where id = pg_temp.rp_id('typed'))
  and (select count(*) = 2 from public.listing_residents where listing_id = pg_temp.rp_id('typed') and left_at is null));
select pg_temp.rp_error('selected double full even though triple beds remain free',
  $$select public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_c'))$$,'22023','room_type_full');
select pg_temp.rp_error('accepted option cannot be removed',
  $$update public.listings set double_room_count = 0,double_room_monthly_rent = null where id = pg_temp.rp_id('typed')$$,
  '22023','room_options_have_active_bookings');
select pg_temp.rp_actor('student_h');
select pg_temp.rp_error('submission also respects selected double fullness',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_h'),null,'double')$$,'22023','room_type_full');
select pg_temp.rp_actor('owner');
update public.listings set double_room_count = 2 where id = pg_temp.rp_id('typed');
select public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_c'));
select pg_temp.rp_error('count cannot shrink below occupied type capacity',
  $$update public.listings set double_room_count = 1 where id = pg_temp.rp_id('typed')$$,
  '22023','room_options_have_active_bookings');
update public.listings set double_room_monthly_rent = 100 where id = pg_temp.rp_id('typed');
select pg_temp.rp_assert('price edits remain allowed with residents and do not reprice accepted quotes',
  (select monthly_rent = 100 from public.listings where id = pg_temp.rp_id('typed'))
  and (select snapshot_monthly_rent = 320 from public.bookings where id = pg_temp.rp_id('booking_a')));
select pg_temp.rp_actor('student_c');
select public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_c'));
select public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_c'));
select pg_temp.rp_actor('owner');
update public.listings set double_room_count = 1 where id = pg_temp.rp_id('typed');
select pg_temp.rp_assert('count may shrink to exactly occupied capacity after one release',
  (select total_bed_capacity = 5 and occupied_beds = 2 and double_room_occupied_beds = 2
   from public.listings where id = pg_temp.rp_id('typed')));
select pg_temp.rp_actor('student_a');
insert into pg_temp.rp_snapshots select 'cancelled_a',to_jsonb(b)
from public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_a')) b;
select pg_temp.rp_assert('cancel replay preserves quote/type/timestamps and only one bed is released',
  (select to_jsonb(b) = (select value from pg_temp.rp_snapshots where key = 'cancelled_a')
   from public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_a')) b)
  and (select occupied_beds = 1 and double_room_occupied_beds = 1 and triple_room_occupied_beds = 0
   from public.listings where id = pg_temp.rp_id('typed'))
  and (select left_at is not null and left_at >= joined_at from public.listing_residents where booking_id = pg_temp.rp_id('booking_a')));

select pg_temp.rp_actor('owner');
select public.accept_booking(pg_temp.rp_id('typed'),id) from pg_temp.rp_ids where key in ('booking_d','booking_e','booking_f');
select pg_temp.rp_assert('triple allocations consume their own capacity, leaving a double bed free',
  (select triple_room_occupied_beds = 3 and double_room_occupied_beds = 1 and occupied_beds = 4 and available_beds = 1
   from public.listings where id = pg_temp.rp_id('typed')));
select pg_temp.rp_error('selected triple full while double remains free',
  $$select public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_g'))$$,'22023','room_type_full');
select pg_temp.rp_error('cannot remove pending/accepted triple option',
  $$update public.listings set triple_room_count = 0,triple_room_monthly_rent = null where id = pg_temp.rp_id('typed')$$,
  '22023','room_options_have_active_bookings');
select pg_temp.rp_error('accepted request cannot be rejected',
  $$select public.reject_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_b'))$$,'22023','booking_transition_not_allowed');
select pg_temp.rp_assert('reject replay is a no-op and pending rejection consumes no bed',
  (select status = 'rejected' from public.reject_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_g')))
  and (select status = 'rejected' from public.reject_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_g'))));
select pg_temp.rp_actor('student_h');
select pg_temp.rp_error('new triple submission cannot use remaining double capacity',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_h'),null,'triple')$$,'22023','room_type_full');
insert into pg_temp.rp_ids select 'booking_h',id
from public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_h'),null,'double');
select public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_h'));
select public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_h'));
select pg_temp.rp_assert('pending cancellation/replay changes no occupied counter',
  (select occupied_beds = 4 and double_room_occupied_beds = 1 and triple_room_occupied_beds = 3
   from public.listings where id = pg_temp.rp_id('typed'))
  and not exists (select 1 from public.listing_residents where booking_id = pg_temp.rp_id('booking_h')));

-- Deliberately corrupt only a fixture resident inside an expected-error subtransaction;
-- its error rolls back BOTH the delete and attempted cancellation.
reset role;
select pg_temp.rp_actor('student_b');
select pg_temp.rp_error('cancellation refuses a missing resident link and rolls back all changes',
  $$do $broken$ begin
    delete from public.listing_residents where booking_id = pg_temp.rp_id('booking_b');
    perform public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_b'));
  end; $broken$;$$,'23514','booking_occupancy_invariant_failed');
select pg_temp.rp_error('stored type is immutable even in an administrative update',
  $$update public.bookings set room_type = 'triple' where id = pg_temp.rp_id('booking_a')$$,'23514','booking_room_type_immutable');
set local role authenticated;
do $release_typed$
declare v_key text;
begin
  foreach v_key in array array['b','d','e','f'] loop
    perform pg_temp.rp_actor('student_' || v_key);
    perform public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_' || v_key));
    perform public.cancel_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_' || v_key));
  end loop;
end;
$release_typed$;
select pg_temp.rp_actor('owner');
select pg_temp.rp_assert('all accepted cancellations release both type counters exactly once',
  (select occupied_beds = 0 and double_room_occupied_beds = 0 and triple_room_occupied_beds = 0
   from public.listings where id = pg_temp.rp_id('typed'))
  and not exists (select 1 from public.listing_residents where listing_id = pg_temp.rp_id('typed') and left_at is null));
select pg_temp.rp_error('terminal cancellation cannot be resurrected',
  $$select public.accept_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('booking_a'))$$,'22023','booking_transition_not_allowed');
update public.listings set double_room_count = 0,double_room_monthly_rent = null,
  triple_room_count = 0,triple_room_monthly_rent = null,pricing_unit = 'per_property',monthly_rent = 600,total_bed_capacity = 9
where id = pg_temp.rp_id('typed');
select pg_temp.rp_assert('terminal history allows disabling/converting options without rewriting quotes',
  (select monthly_rent = 600 and total_bed_capacity = 9 and pricing_unit = 'per_property'
   from public.listings where id = pg_temp.rp_id('typed'))
  and (select room_type = 'double' and snapshot_monthly_rent = 320 and snapshot_pricing_unit = 'per_bed'
   from public.bookings where id = pg_temp.rp_id('booking_a'))
  and (select room_type = 'triple' and snapshot_monthly_rent = 160 from public.bookings where id = pg_temp.rp_id('booking_d')));
select public.set_listing_status(pg_temp.rp_id('typed'),'archived');
select pg_temp.rp_actor('student_a');
select pg_temp.rp_assert('same frozen request replays after option removal and unpublication',
  (select id = pg_temp.rp_id('booking_a') and room_type = 'double' and snapshot_monthly_rent = 320 and status = 'cancelled'
   from public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_a'),'Hello','double')));
select pg_temp.rp_assert('left-joined history survives hidden listing without revealing it',
  (select l.id is null and b.room_type = 'double' and b.snapshot_monthly_rent = 320
   from public.bookings b left join public.listings l on l.id = b.listing_id where b.id = pg_temp.rp_id('booking_a')));
select pg_temp.rp_error('new request cannot access archived listing',
  $$select public.submit_booking(pg_temp.rp_id('typed'),pg_temp.rp_id('request_unused'),null,'double')$$,
  '42501','listing_not_accessible');

-- Generic/legacy path retains old calls, snapshots, errors and untyped counters.
insert into pg_temp.rp_ids select 'legacy_booking',id
from public.submit_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('request_legacy'),'Legacy');
select pg_temp.rp_assert('legacy three-argument call stores a null type and generic quote',
  (select room_type is null and snapshot_monthly_rent = 777 and snapshot_total_beds = 1
   from public.bookings where id = pg_temp.rp_id('legacy_booking')));
select pg_temp.rp_actor('owner');
select pg_temp.rp_error('active unassigned pending request blocks enabling room options',
  $$update public.listings set double_room_count = 1,double_room_monthly_rent = 100 where id = pg_temp.rp_id('generic')$$,
  '22023','room_options_have_active_bookings');
select public.accept_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('legacy_booking'));
select public.accept_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('legacy_booking'));
select pg_temp.rp_assert('legacy acceptance increments aggregate only once',
  (select occupied_beds = 1 and double_room_occupied_beds = 0 and triple_room_occupied_beds = 0
   from public.listings where id = pg_temp.rp_id('generic')));
select pg_temp.rp_error('active unassigned accepted request blocks enabling room options',
  $$update public.listings set triple_room_count = 1,triple_room_monthly_rent = 100 where id = pg_temp.rp_id('generic')$$,
  '22023','room_options_have_active_bookings');
select pg_temp.rp_error('legacy pricing-unit transition guard remains unchanged',
  $$update public.listings set pricing_unit = 'per_room' where id = pg_temp.rp_id('generic')$$,
  '22023','pricing_unit_has_active_bookings');
update public.listings set monthly_rent = 888 where id = pg_temp.rp_id('generic');
select pg_temp.rp_actor('student_b');
select pg_temp.rp_error('legacy full listing error remains unchanged',
  $$select public.submit_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('request_legacy_second'))$$,'22023','listing_full');
select pg_temp.rp_actor('owner');
select public.set_listing_status(pg_temp.rp_id('generic'),'archived');
select pg_temp.rp_actor('student_a');
select public.cancel_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('legacy_booking'));
select public.cancel_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('legacy_booking'));
select pg_temp.rp_assert('legacy cancellation works after archive and preserves original price',
  (select room_type is null and snapshot_monthly_rent = 777 and status = 'cancelled'
   from public.bookings where id = pg_temp.rp_id('legacy_booking'))
  and (select left_at is not null from public.listing_residents where booking_id = pg_temp.rp_id('legacy_booking')));
select pg_temp.rp_actor('owner');
select public.set_listing_status(pg_temp.rp_id('generic'),'published');
select pg_temp.rp_assert('legacy cancel replay did not underflow aggregate or type counters',
  (select occupied_beds = 0 and double_room_occupied_beds = 0 and triple_room_occupied_beds = 0
   from public.listings where id = pg_temp.rp_id('generic')));
select pg_temp.rp_actor('student_b');
insert into pg_temp.rp_ids select 'legacy_second',id
from public.submit_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('request_legacy_second'));
select pg_temp.rp_actor('owner');
select public.reject_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('legacy_second'));
select public.reject_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('legacy_second'));
update public.listings set double_room_count = 1,double_room_monthly_rent = 100 where id = pg_temp.rp_id('generic');
select pg_temp.rp_assert('options may be enabled after all legacy requests are terminal',
  (select total_bed_capacity = 2 and monthly_rent = 100 and occupied_beds = 0 and double_room_count = 1
   from public.listings where id = pg_temp.rp_id('generic')));
select pg_temp.rp_actor('student_a');
select pg_temp.rp_assert('legacy null replay survives later conversion to a typed listing',
  (select room_type is null and snapshot_monthly_rent = 777 and status = 'cancelled'
   from public.submit_booking(pg_temp.rp_id('generic'),pg_temp.rp_id('request_legacy'),'Legacy')));
select pg_temp.rp_actor('student_b');
insert into pg_temp.rp_ids select 'zero_booking',id from public.submit_booking(
  p_listing_id => pg_temp.rp_id('double_only'),p_request_id => pg_temp.rp_id('request_zero'),p_room_type => 'double');
select pg_temp.rp_assert('named type with omitted message snapshots enabled zero price',
  (select room_type = 'double' and message is null and snapshot_monthly_rent = 0
   from public.bookings where id = pg_temp.rp_id('zero_booking')));
select public.cancel_booking(pg_temp.rp_id('double_only'),pg_temp.rp_id('zero_booking'));

reset role;
select pg_temp.rp_assert('every fixture aggregate/type occupancy matches accepted requests and live resident links',
  not exists (select 1 from public.listings l join pg_temp.rp_ids i on i.id = l.id where
    l.occupied_beds <> (select count(*) from public.bookings b where b.listing_id = l.id and b.status = 'accepted')
    or l.occupied_beds <> (select count(*) from public.listing_residents r where r.listing_id = l.id and r.left_at is null)
    or l.double_room_occupied_beds <> (select count(*) from public.bookings b
      where b.listing_id = l.id and b.status = 'accepted' and b.room_type = 'double')
    or l.triple_room_occupied_beds <> (select count(*) from public.bookings b
      where b.listing_id = l.id and b.status = 'accepted' and b.room_type = 'triple')));
select count(*) as assertions_passed from pg_temp.rp_results;
rollback;
