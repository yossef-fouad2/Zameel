-- Rollback-only verification AFTER 007 AND 009, as administrator in a QUIET, ISOLATED
-- DEVELOPMENT database. Run the WHOLE file; NEVER replace ROLLBACK with COMMIT.
-- After any failure issue ROLLBACK before more SQL. Do not use production or
-- external Auth/database hooks whose side effects cannot be rolled back.
-- Claims/roles and random Auth/listing/catalogue fixtures are test impersonation,
-- not a client authorization API. No provider, Storage API or hosted Auth calls.
-- This expects the original 16 catalogue rows before administrator maintenance.
-- Run original 004 BEFORE 007: it publishes an address-only fixture that the new
-- pin constraint intentionally rejects. Original 002 also belongs before 005.
--
-- The publication CHECK is temporarily removed/reinstated inside this transaction
-- solely to model a grandfathered address-only publication. Its exclusive lock
-- prevents concurrent use of that temporary state; ROLLBACK restores everything.
-- Existing rows are snapshotted and checked unchanged before the final rollback.
--
-- Separately test migration behavior in an isolated harness: capture existing
-- listings/profiles/lifestyle/Storage/bookings before 007 (including address-only
-- published rows); apply 007 and compare. Run 007 twice, and after rolled-back
-- unknown object/policy/grant changes to check refusal. A post-install verifier
-- cannot reconstruct pre-install data or invoke 007's COMMIT safely inside itself.
--
-- Real two-connection race check: keep a writer transaction open after its call;
-- a second writer for the same listing must wait (or hit its bounded lock timeout),
-- then retain the first current row/timestamp. Pin/catalogue edits must serialize
-- with those locks; a response using old snapshots after an edit must fail PT409.
-- This single-session verifier checks replay/obsolete completions, not scheduling
-- across two connections. Hosted JWT/PostgREST, provider coverage and actual
-- pedestrian entrances remain separate deployment acceptance checks.

begin;
-- SET ROLE alone does not apply the per-request GUCs loaded by PostgREST.
set local extra_float_digits = 1;
set local search_path = pg_catalog;
set local timezone = 'UTC';

create temporary table ud_ids (key text primary key, id uuid not null);
create temporary table ud_results (name text not null);
create temporary table ud_snapshots (key text primary key, value jsonb not null);
create temporary table ud_existing (relation regclass not null, value jsonb not null);
create temporary table ud_expected (id uuid primary key, distance_m double precision not null);
grant select, insert, update on pg_temp.ud_ids, pg_temp.ud_results, pg_temp.ud_snapshots,
  pg_temp.ud_expected to anon, authenticated, service_role;

create function pg_temp.ud_id(p_key text)
returns uuid language sql stable security invoker set search_path = '' as $test$
  select id from pg_temp.ud_ids where key = p_key;
$test$;
create function pg_temp.ud_actor(p_key text)
returns void language plpgsql security invoker set search_path = '' as $test$
declare
  v_id uuid := pg_temp.ud_id(p_key);
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', current_user::text, true);
  perform pg_catalog.set_config('request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', v_id, 'role', current_user)::text, true);
end;
$test$;
create function pg_temp.ud_assert(p_name text, p_ok boolean)
returns void language plpgsql security invoker set search_path = '' as $test$
begin
  if p_ok is distinct from true then raise exception 'FAIL: %', p_name; end if;
  insert into pg_temp.ud_results values (p_name);
end;
$test$;
create function pg_temp.ud_error(p_name text, p_sql text, p_state text, p_message text default null)
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
      insert into pg_temp.ud_results values (p_name);
      return;
    end if;
    raise exception 'FAIL: %; expected % / %, got % / %', p_name, p_state, p_message, v_state, v_message;
  end;
  raise exception 'FAIL: %; statement succeeded, expected %', p_name, p_state;
end;
$test$;
create function pg_temp.ud_route(
  p_university_id integer default 2147483647, p_status text default 'ready',
  p_distance double precision default 1234.56789
) returns jsonb language sql immutable security invoker set search_path = '' as $test$
  select pg_catalog.jsonb_build_object(
    'university_id', p_university_id, 'university_latitude', 30.0276, 'university_longitude', 31.21014,
    'status', p_status, 'distance_m', p_distance,
    'matched_source_latitude', 30.0276, 'matched_source_longitude', 31.21014,
    'matched_target_latitude', 30.0276, 'matched_target_longitude', 31.21014);
$test$;
revoke all on function pg_temp.ud_id(text), pg_temp.ud_actor(text), pg_temp.ud_assert(text,boolean),
  pg_temp.ud_error(text,text,text,text), pg_temp.ud_route(integer,text,double precision) from public;
grant execute on function pg_temp.ud_id(text), pg_temp.ud_actor(text), pg_temp.ud_assert(text,boolean),
  pg_temp.ud_error(text,text,text,text), pg_temp.ud_route(integer,text,double precision)
  to anon, authenticated, service_role;

select pg_temp.ud_assert('exact original 16 supplied university records, including precision and cities',
  (select count(*) = 16 from public.universities) and not exists (
    select 1 from (values
      (1, 'Cairo University', 'Giza', 30.0276, 31.21014),
      (2, 'Ain Shams University', 'Abbassia, Cairo', 30.077022, 31.285017),
      (3, 'Al-Azhar University', 'Nasr City, Cairo', 30.0583, 31.3126),
      (4, 'Alexandria University', 'Alexandria', 31.20194, 29.90528),
      (5, 'Assiut University', 'Assiut', 27.187778, 31.170278),
      (6, 'Tanta University', 'Tanta', 30.7922, 30.9992),
      (7, 'Benha University', 'Benha', 30.471111, 31.181667),
      (8, 'Suez Canal University', 'Ismailia', 30.622778, 32.275),
      (9, 'Fayoum University', 'Fayoum', 29.3211, 30.8356),
      (10, 'Beni-Suef University', 'Beni Suef', 29.081389, 31.100556),
      (11, 'Aswan University', 'Aswan', 23.9989, 32.8599),
      (12, 'October 6 University', '6th of October City', 29.976167, 30.948528),
      (13, 'German University in Cairo (GUC)', 'New Cairo', 29.988, 31.442),
      (14, 'The American University in Cairo (AUC)', 'New Cairo', 30.019944, 31.500344),
      (15, 'British University in Egypt (BUE)', 'El Shorouk City', 30.117778, 31.606389),
      (16, 'Arab Open University (AOU) - Egypt', 'El-Shorouk City, Cairo Governorate', 30.1297, 31.615)
    ) as expected(id, name, city, latitude, longitude)
    left join public.universities u using (id)
    where u.id is null or u.name <> expected.name or u.city <> expected.city or not u.is_active
      or u.latitude <> expected.latitude::double precision or u.longitude <> expected.longitude::double precision
  ));
select pg_temp.ud_assert('new tables have RLS and only SELECT policies',
  (select count(*) = 2 and bool_and(relkind = 'r' and relrowsecurity)
   from pg_catalog.pg_class where oid in ('public.universities'::regclass, 'public.listing_university_routes'::regclass))
  and (select count(*) = 2 and bool_and(polcmd = 'r') from pg_catalog.pg_policy
    where polrelid in ('public.universities'::regclass, 'public.listing_university_routes'::regclass)));
select pg_temp.ud_assert('no direct catalogue/cache writes or service-role reads, including column grants',
  not exists (select 1 from pg_catalog.pg_class c
    cross join (values ('anon'), ('authenticated'), ('service_role')) as roles(name)
    where c.oid in ('public.universities'::regclass, 'public.listing_university_routes'::regclass)
      and (pg_catalog.has_table_privilege(roles.name, c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or (roles.name = 'service_role' and pg_catalog.has_table_privilege(roles.name, c.oid, 'SELECT'))
        or exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = c.oid
          and a.attnum > 0 and not a.attisdropped
          and (pg_catalog.has_column_privilege(roles.name, c.oid, a.attnum, 'INSERT,UPDATE,REFERENCES')
            or (roles.name = 'service_role' and pg_catalog.has_column_privilege(roles.name, c.oid, a.attnum, 'SELECT')))))));
select pg_temp.ud_assert('service-role existing table denial preserved',
  not exists (select 1 from pg_catalog.pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relname in (
      'profiles', 'listings', 'listing_photos', 'amenities', 'house_rules', 'listing_amenities',
      'listing_house_rules', 'lifestyle_preferences', 'bookings', 'listing_residents')
      and (pg_catalog.has_table_privilege('service_role', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = c.oid
          and a.attnum > 0 and not a.attisdropped
          and pg_catalog.has_column_privilege('service_role', c.oid, a.attnum, 'SELECT,INSERT,UPDATE,REFERENCES')))));
select pg_temp.ud_assert('new routines pin an empty search_path and revoke PUBLIC',
  (select count(*) = 3 and bool_and(coalesce(p.proconfig @> array['search_path=""'], false))
   from pg_catalog.pg_proc p where p.oid in (
     'public.search_listings_by_university(integer,double precision,uuid,integer)'::regprocedure,
     'public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)'::regprocedure,
     'zameel_private.route_great_circle_m(double precision,double precision,double precision,double precision)'::regprocedure))
  and not exists (select 1 from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    where p.oid in (
      'public.search_listings_by_university(integer,double precision,uuid,integer)'::regprocedure,
      'public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)'::regprocedure,
      'zameel_private.route_great_circle_m(double precision,double precision,double precision,double precision)'::regprocedure)
      and a.grantee = 0));
select pg_temp.ud_assert('search is SECURITY INVOKER/STABLE with exact named arguments and default page size',
  (select not prosecdef and provolatile = 's' and proretset
    and proargnames[1:4] = array['p_university_id','p_after_distance_m','p_after_listing_id','p_limit']
    and pronargdefaults = 3
    from pg_catalog.pg_proc where oid = 'public.search_listings_by_university(integer,double precision,uuid,integer)'::regprocedure)
  and pg_catalog.has_function_privilege('anon', 'public.search_listings_by_university(integer,double precision,uuid,integer)', 'EXECUTE')
  and pg_catalog.has_function_privilege('authenticated', 'public.search_listings_by_university(integer,double precision,uuid,integer)', 'EXECUTE'));
select pg_temp.ud_assert('only service_role can execute the narrow SECURITY DEFINER cache writer',
  (select prosecdef and provolatile = 'v' and not proretset
      and prorettype = 'integer'::regtype and pronargdefaults = 0
      and proargnames = array['p_listing_id','p_landlord_id','p_listing_latitude',
        'p_listing_longitude','p_routing_version','p_routes']
      and proconfig @> array['lock_timeout=2s']
    from pg_catalog.pg_proc
   where oid = 'public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)'::regprocedure)
  and pg_catalog.has_function_privilege('service_role', 'public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('anon', 'public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)', 'EXECUTE')
  and not pg_catalog.has_function_privilege('authenticated', 'public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)', 'EXECUTE'));

select pg_temp.ud_assert('009 preserves full float precision for every Data API role',
  (select count(*) = 3 and bool_and(coalesce(rolconfig @> array['extra_float_digits=1'], false))
   from pg_catalog.pg_roles where rolname in ('anon','authenticated','service_role')));
select pg_temp.ud_assert('API JSON round-trips preserve exact pins and distance cursors',
  (select bool_and(v = (pg_catalog.to_jsonb(v)::text)::double precision)
   from unnest(array[30.123456789012345,31.234567890123457,1234.5678901234567]::double precision[]) as sample(v)));
select pg_temp.ud_assert('university-distance-id index supports keyset discovery',
  exists (select 1 from pg_catalog.pg_index i
    where i.indexrelid = 'public.listing_university_routes_discovery_idx'::regclass
      and i.indisvalid and i.indisready and pg_catalog.pg_get_indexdef(i.indexrelid) like
        '%(university_id, distance_m, listing_id)%'));

do $snapshot_existing$
declare
  v_table regclass;
begin
  for v_table in select c.oid from pg_catalog.pg_class c
    where (c.relnamespace = 'public'::regnamespace and c.relname in (
      'profiles', 'listings', 'listing_photos', 'amenities', 'house_rules', 'listing_amenities',
      'listing_house_rules', 'lifestyle_preferences', 'bookings', 'listing_residents',
      'universities', 'listing_university_routes'))
      or (c.relnamespace = 'zameel_private'::regnamespace and c.relname = 'lifestyle_sync_state')
      or (c.relnamespace = 'storage'::regnamespace and c.relname in ('objects', 'buckets')) loop
    execute pg_catalog.format('insert into pg_temp.ud_existing select %L::regclass, to_jsonb(t) from %s t', v_table, v_table);
  end loop;
end;
$snapshot_existing$;

insert into pg_temp.ud_ids select key, gen_random_uuid()
from unnest(array['owner', 'other', 'student', 'missing_profile', 'draft', 'archived', 'no_pin',
  'legacy', 'walk_near', 'walk_far', 'tie_a', 'tie_b', 'boundary', 'over', 'zero', 'full',
  'unroutable', 'review', 'stale_listing', 'stale_university', 'old_version', 'write_target', 'write_atomic']) key;
insert into pg_temp.ud_ids select 'page_' || n, gen_random_uuid() from generate_series(1, 60) n;
insert into auth.users(id, email, raw_user_meta_data)
select id, 'university-sql+' || id::text || '@example.invalid', jsonb_build_object(
  'role', case when key in ('owner','other') then 'landlord' else 'student' end, 'name', 'SQL discovery ' || key)
from pg_temp.ud_ids where key in ('owner','other','student','missing_profile');
delete from public.profiles where id = pg_temp.ud_id('missing_profile');
update auth.users set raw_user_meta_data = '{"role":"landlord"}' where id = pg_temp.ud_id('student');
update auth.users set raw_user_meta_data = '{"role":"student"}' where id = pg_temp.ud_id('owner');

-- Isolate search pages from any pre-existing real listings. These two temporary
-- catalogue fixtures COPY a supplied reference pin and never survive rollback.
insert into public.universities(id, name, city, latitude, longitude)
select n, 'Rollback-only verification reference', city, latitude, longitude
from public.universities cross join (values (2147483646), (2147483647)) as fixtures(n) where id = 1;
alter table public.listings drop constraint listings_published_pin;
insert into public.listings(id, landlord_id, title, description, address, latitude, longitude,
  monthly_rent, pricing_unit, currency, total_bed_capacity, occupied_beds, status)
select i.id, pg_temp.ud_id('owner'), 'SQL discovery ' || i.key, 'Rollback-only fixture', 'SQL fixture address',
  case when i.key in ('no_pin','legacy') then null else 30.0276 end,
  case when i.key in ('no_pin','legacy') then null
    when i.key = 'walk_near' then 31.21514 when i.key = 'walk_far' then 31.21114 else 31.21014 end,
  3500.25, 'per_bed', 'EGP', 2, case when i.key = 'full' then 2 else 0 end,
  case when i.key in ('draft','no_pin','write_atomic') then 'draft'
    when i.key = 'archived' then 'archived' else 'published' end
from pg_temp.ud_ids i where i.key not in ('owner','other','student','missing_profile');
alter table public.listings add constraint listings_published_pin check (
  status <> 'published' or (latitude is not null and longitude is not null)
) not valid;

insert into public.listing_university_routes(
  listing_id, university_id, status, distance_m, listing_latitude, listing_longitude,
  university_latitude, university_longitude, routing_version,
  matched_source_latitude, matched_source_longitude, matched_target_latitude, matched_target_longitude)
select l.id, 2147483647,
  case when i.key = 'unroutable' then 'unroutable' when i.key = 'review' then 'needs_pin_review' else 'ready' end,
  case when i.key in ('unroutable','review') then null when i.key = 'zero' then 0
    when i.key = 'walk_near' then 900.0000001 when i.key = 'walk_far' then 1400.0000001
    when i.key in ('tie_a','tie_b') then 1000.123456789
    when i.key = 'boundary' then 10000 when i.key = 'over' then 10000.0000001
    when i.key like 'page_%' then 2000 + substring(i.key from 6)::integer / 10.0 else 1500 end,
  l.latitude + case when i.key = 'stale_listing' then 0.01 else 0 end, l.longitude,
  30.0276 + case when i.key = 'stale_university' then 0.01 else 0 end, 31.21014,
  case when i.key = 'old_version' then 'old-routing-version' else 'geoapify-walk-short-metric-snap100-v1' end,
  l.latitude + case when i.key = 'review' then 0.01 else 0 end, l.longitude, 30.0276, 31.21014
from public.listings l join pg_temp.ud_ids i on i.id = l.id
where i.key not in ('no_pin','legacy','write_target','write_atomic');
insert into pg_temp.ud_expected
select r.listing_id, r.distance_m from public.listing_university_routes r
join public.listings l on l.id = r.listing_id join public.universities u on u.id = r.university_id
where u.id = 2147483647 and l.status = 'published' and r.status = 'ready' and r.distance_m <= 10000
  and r.listing_latitude = l.latitude and r.listing_longitude = l.longitude
  and r.university_latitude = u.latitude and r.university_longitude = u.longitude
  and r.routing_version = 'geoapify-walk-short-metric-snap100-v1';
select pg_temp.ud_assert('fixture walking order deliberately differs from straight-line order',
  zameel_private.route_great_circle_m(30.0276,31.21514,30.0276,31.21014)
    > zameel_private.route_great_circle_m(30.0276,31.21114,30.0276,31.21014)
  and (select distance_m from pg_temp.ud_expected where id = pg_temp.ud_id('walk_near'))
    < (select distance_m from pg_temp.ud_expected where id = pg_temp.ud_id('walk_far')));

set local role anon;
select pg_temp.ud_actor(null);
select pg_temp.ud_assert('anonymous catalogue reads include active supplied references',
  (select count(*) = 16 from public.universities where id between 1 and 16));
select pg_temp.ud_assert('anonymous published pins are exact and public, including full listings',
  (select latitude = 30.0276 and longitude = 31.21514 and landlord_id = pg_temp.ud_id('owner')
   from public.listings where id = pg_temp.ud_id('walk_near'))
  and exists (select 1 from public.listings where id = pg_temp.ud_id('full')));
select pg_temp.ud_assert('anonymous cannot read draft/archived listing or route rows',
  not exists (select 1 from public.listings where id in (pg_temp.ud_id('draft'),pg_temp.ud_id('archived')))
  and not exists (select 1 from public.listing_university_routes
    where listing_id in (pg_temp.ud_id('draft'),pg_temp.ud_id('archived'))));
select pg_temp.ud_assert('stale listing, stale university and old-version cache hidden in direct reads',
  not exists (select 1 from public.listing_university_routes where listing_id in (
    pg_temp.ud_id('stale_listing'),pg_temp.ud_id('stale_university'),pg_temp.ud_id('old_version'))));
select pg_temp.ud_error('anonymous cannot forge distances',
  $$insert into public.listing_university_routes(listing_id,university_id,status,distance_m)
    values(pg_temp.ud_id('walk_near'),1,'ready',0)$$, '42501');
select pg_temp.ud_error('anonymous cannot edit catalogue', $$update public.universities set latitude=0$$, '42501');
select pg_temp.ud_error('anonymous cannot call server writer',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(pg_temp.ud_route()))$$, '42501');
select pg_temp.ud_error('anonymous profile privacy preserved', $$select * from public.profiles$$, '42501');
select pg_temp.ud_assert('legacy address-only publication is retained but absent from walking discovery',
  exists (select 1 from public.listings where id = pg_temp.ud_id('legacy') and latitude is null and status = 'published')
  and not exists (select 1 from public.search_listings_by_university(2147483647) where id = pg_temp.ud_id('legacy')));

select pg_temp.ud_assert('default page size is 20 and explicit size is capped at 50',
  (select count(*) = 20 from public.search_listings_by_university(2147483647))
  and (select count(*) = 50 from public.search_listings_by_university(2147483647,null,null,500)));
select pg_temp.ud_assert('flat search contract returns all 001 listing columns plus distance/university',
  (select to_jsonb(s) ?& array['id','landlord_id','title','description','address','latitude','longitude',
      'monthly_rent','pricing_unit','currency','total_bed_capacity','occupied_beds','available_beds',
      'status','created_at','updated_at','distance_m','university_id']
    and to_jsonb(s) - array['id','landlord_id','title','description','address','latitude','longitude',
      'monthly_rent','pricing_unit','currency','total_bed_capacity','occupied_beds','available_beds',
      'status','created_at','updated_at','distance_m','university_id'] = '{}'::jsonb
    and s.currency = 'EGP' and s.monthly_rent = 3500.25 and s.status = 'published'
   from public.search_listings_by_university(2147483647,null,null,1) s));
do $ordered_pages$
declare
  v_row record;
  v_seen uuid[] := array[]::uuid[];
  v_after_distance double precision;
  v_after_id uuid;
  v_count integer;
  v_page integer := 0;
begin
  loop
    v_count := 0;
    v_page := v_page + 1;
    if v_page > 30 then raise exception 'FAIL: keyset pagination did not terminate'; end if;
    for v_row in select * from public.search_listings_by_university(2147483647,v_after_distance,v_after_id,7) loop
      perform pg_temp.ud_assert('keyset advances unrounded distance then UUID',
        v_after_distance is null or (v_row.distance_m,v_row.id) > (v_after_distance,v_after_id));
      v_seen := array_append(v_seen,v_row.id);
      v_after_distance := v_row.distance_m;
      v_after_id := v_row.id;
      v_count := v_count + 1;
    end loop;
    exit when v_count = 0;
  end loop;
  perform pg_temp.ud_assert('all pages equal globally sorted expected rows, no omissions or duplicates',
    v_seen = (select array_agg(id order by distance_m,id) from pg_temp.ud_expected));
  perform pg_temp.ud_assert('walking rank, not straight-line rank',
    array_position(v_seen,pg_temp.ud_id('walk_near')) < array_position(v_seen,pg_temp.ud_id('walk_far')));
  perform pg_temp.ud_assert('exact 10000m boundary and zero included; over/unreachable/review excluded',
    pg_temp.ud_id('boundary') = any(v_seen) and pg_temp.ud_id('zero') = any(v_seen)
    and not (pg_temp.ud_id('over') = any(v_seen)) and not (pg_temp.ud_id('unroutable') = any(v_seen))
    and not (pg_temp.ud_id('review') = any(v_seen)));
  perform pg_temp.ud_assert('no unrequested availability filter', pg_temp.ud_id('full') = any(v_seen));
end;
$ordered_pages$;
select pg_temp.ud_assert('ties use UUID and resume without rounding',
  (select array_agg(id order by distance_m,id) from public.search_listings_by_university(2147483647,900.0000001,pg_temp.ud_id('walk_near'),2))
    = (select array_agg(id order by id) from pg_temp.ud_ids where key in ('tie_a','tie_b')));

do $search_validation$
declare
  v_case record;
begin
  for v_case in select * from (values
    ('null university','null,null,null,20','university_unavailable'),
    ('zero university','0,null,null,20','university_unavailable'),
    ('unknown university','100,null,null,20','university_unavailable'),
    ('null limit','2147483647,null,null,null','invalid_search_limit'),
    ('zero limit','2147483647,null,null,0','invalid_search_limit'),
    ('negative limit','2147483647,null,null,-1','invalid_search_limit'),
    ('missing cursor id','2147483647,10,null,20','invalid_search_cursor'),
    ('missing cursor distance','2147483647,null,pg_temp.ud_id(''tie_a''),20','invalid_search_cursor'),
    ('negative cursor','2147483647,-1,pg_temp.ud_id(''tie_a''),20','invalid_search_cursor'),
    ('over-bound cursor','2147483647,10000.0001,pg_temp.ud_id(''tie_a''),20','invalid_search_cursor'),
    ('NaN cursor','2147483647,''NaN''::float8,pg_temp.ud_id(''tie_a''),20','invalid_search_cursor'),
    ('infinite cursor','2147483647,''Infinity''::float8,pg_temp.ud_id(''tie_a''),20','invalid_search_cursor')
  ) as cases(name,args,message) loop
    perform pg_temp.ud_error(v_case.name, 'select public.search_listings_by_university(' || v_case.args || ')', '22023', v_case.message);
  end loop;
end;
$search_validation$;

set local role authenticated;
select pg_temp.ud_actor('student');
select pg_temp.ud_assert('student can read published search but not private drafts',
  (select count(*) = 20 from public.search_listings_by_university(2147483647))
  and not exists (select 1 from public.listing_university_routes where listing_id = pg_temp.ud_id('draft')));
select pg_temp.ud_error('student cannot use server writer despite forged landlord metadata',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(pg_temp.ud_route()))$$, '42501');
select pg_temp.ud_error('student listing insert still denied by persisted role',
  $$insert into public.listings(title,monthly_rent,pricing_unit,currency,total_bed_capacity)
    values('Unauthorized',1000,'per_bed','EGP',2)$$, '42501');
select pg_temp.ud_error('student cache update denied', $$update public.listing_university_routes set distance_m=0$$, '42501');
select pg_temp.ud_error('student cache delete denied', $$delete from public.listing_university_routes$$, '42501');

select pg_temp.ud_actor('other');
with changed as (update public.listings set title='Unauthorized' where id=pg_temp.ud_id('draft') returning id)
select pg_temp.ud_assert('other landlord cannot edit private listing', (select count(*)=0 from changed));
with changed as (update public.listings set title='Unauthorized' where id=pg_temp.ud_id('walk_near') returning id)
select pg_temp.ud_assert('public visibility does not grant other landlord writes', (select count(*)=0 from changed));
select pg_temp.ud_error('other landlord cannot publish owner draft',
  $$select public.set_listing_status(pg_temp.ud_id('draft'),'published')$$, '42501');

select pg_temp.ud_actor('owner');
select pg_temp.ud_assert('owner sees current draft and archived route results despite false Auth metadata',
  (select count(*)=2 from public.listing_university_routes where listing_id in (pg_temp.ud_id('draft'),pg_temp.ud_id('archived'))));
select pg_temp.ud_assert('owner discovery still excludes drafts and archives explicitly',
  not exists (select 1 from public.search_listings_by_university(2147483647,null,null,50)
    where id in (pg_temp.ud_id('draft'),pg_temp.ud_id('archived'))));
select pg_temp.ud_error('owning landlord cannot forge distance through RPC',
  $$select public.write_listing_university_routes(pg_temp.ud_id('draft'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(pg_temp.ud_route()))$$, '42501');
select pg_temp.ud_error('owning landlord cannot directly insert route results',
  $$insert into public.listing_university_routes(listing_id,university_id,status,distance_m)
    values(pg_temp.ud_id('draft'),1,'ready',0)$$, '42501');
select pg_temp.ud_error('catalogue INSERT denied', $$insert into public.universities values(100,'Forged','City',0,0,true)$$, '42501');
select pg_temp.ud_error('catalogue UPDATE denied', $$update public.universities set longitude=0$$, '42501');
select pg_temp.ud_error('catalogue DELETE denied', $$delete from public.universities$$, '42501');
select pg_temp.ud_error('server-owned publication status still protected', $$update public.listings set status='published'$$, '42501');
select pg_temp.ud_error('server-owned occupancy still protected', $$update public.listings set occupied_beds=0$$, '42501');
select pg_temp.ud_error('server-owned landlord id still protected', $$update public.listings set landlord_id=pg_temp.ud_id('other')$$, '42501');
select pg_temp.ud_error('server-owned updated_at still protected', $$update public.listings set updated_at=now()$$, '42501');
select pg_temp.ud_error('new publication requires a saved coordinate pair',
  $$select public.set_listing_status(pg_temp.ud_id('no_pin'),'published')$$, '23514');
select pg_temp.ud_error('legacy address-only row cannot be updated without repairing pin',
  $$update public.listings set title='Still no pin' where id=pg_temp.ud_id('legacy')$$, '23514');
select pg_temp.ud_assert('legacy row remains untouched after failed update',
  (select title='SQL discovery legacy' and status='published' and latitude is null from public.listings where id=pg_temp.ud_id('legacy')));
select public.set_listing_status(pg_temp.ud_id('legacy'),'draft');
select pg_temp.ud_error('unpublished legacy row cannot be newly published without pin',
  $$select public.set_listing_status(pg_temp.ud_id('legacy'),'published')$$, '23514');
update public.listings set latitude=30.0276,longitude=31.21014 where id=pg_temp.ud_id('legacy');
select public.set_listing_status(pg_temp.ud_id('legacy'),'published');
select pg_temp.ud_assert('publication can succeed with pin even without cached routes',
  (select status='published' from public.listings where id=pg_temp.ud_id('legacy'))
  and not exists (select 1 from public.listing_university_routes where listing_id=pg_temp.ud_id('legacy')));

set local role service_role;
select pg_temp.ud_actor(null);
select pg_temp.ud_error('service-role cannot read existing listings', $$select * from public.listings$$, '42501');
select pg_temp.ud_error('service-role cannot read existing profiles', $$select * from public.profiles$$, '42501');
select pg_temp.ud_error('service-role cannot directly read route cache', $$select * from public.listing_university_routes$$, '42501');
select pg_temp.ud_error('service-role cannot directly write route cache', $$delete from public.listing_university_routes$$, '42501');
select pg_temp.ud_assert('narrow writer stores multiple university associations atomically',
  public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(
      pg_temp.ud_route(),pg_temp.ud_route(2147483646)))=2);
set local role authenticated;
select pg_temp.ud_actor('owner');
insert into pg_temp.ud_snapshots select 'written_cache', jsonb_agg(to_jsonb(r) order by university_id)
from public.listing_university_routes r where listing_id=pg_temp.ud_id('write_target');
select pg_temp.ud_assert('written distance precision, exact snapshots, version and finite server timestamp',
  (select count(*)=2 and bool_and(distance_m=1234.56789 and listing_latitude=30.0276 and listing_longitude=31.21014
    and university_latitude=30.0276 and university_longitude=31.21014
    and routing_version='geoapify-walk-short-metric-snap100-v1' and isfinite(calculated_at)
    and calculated_at between transaction_timestamp() and clock_timestamp())
   from public.listing_university_routes where listing_id=pg_temp.ud_id('write_target')));
set local role service_role;
select pg_temp.ud_assert('duplicate completion cannot overwrite valid current outcomes or timestamps',
  public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(
      pg_temp.ud_route(2147483647,'unroutable',null),pg_temp.ud_route(2147483646,'ready',1)))=0);
select pg_temp.ud_error('writer rechecks owner, not a supplied claim',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('other'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(pg_temp.ud_route()))$$,
  '42501','route_write_not_authorized');
select pg_temp.ud_error('old listing snapshot completion fails closed',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0277,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(pg_temp.ud_route()))$$,
  'PT409','route_snapshot_stale');
select pg_temp.ud_error('one stale university invalidates whole batch',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_atomic'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(
      pg_temp.ud_route(2147483646),pg_temp.ud_route()||'{"university_latitude":30.1}'::jsonb))$$,
  'PT409','route_snapshot_stale');

do $writer_validation$
declare
  v_case record;
begin
  for v_case in select * from (values
    ('SQL null',null::jsonb), ('object','{}'::jsonb), ('empty','[]'::jsonb),
    ('scalar member','[1]'::jsonb), ('missing keys','[{}]'::jsonb),
    ('unknown key',jsonb_build_array(pg_temp.ud_route()||'{"calculated_at":"2020-01-01"}'::jsonb)),
    ('missing nullable key',jsonb_build_array(pg_temp.ud_route()-'matched_target_latitude')),
    ('fractional university',jsonb_build_array(pg_temp.ud_route()||'{"university_id":1.5}'::jsonb)),
    ('overflow university',jsonb_build_array(pg_temp.ud_route()||'{"university_id":2147483648}'::jsonb)),
    ('negative distance',jsonb_build_array(pg_temp.ud_route()||'{"distance_m":-1}'::jsonb)),
    ('non-number distance',jsonb_build_array(pg_temp.ud_route()||'{"distance_m":"NaN"}'::jsonb)),
    ('infinite distance',jsonb_build_array(pg_temp.ud_route()||'{"distance_m":1e999}'::jsonb)),
    ('ready needs distance',jsonb_build_array(pg_temp.ud_route()||'{"distance_m":null}'::jsonb)),
    ('unknown status',jsonb_build_array(pg_temp.ud_route()||'{"status":"pending"}'::jsonb)),
    ('unreachable cannot have distance',jsonb_build_array(pg_temp.ud_route(2147483647,'unroutable',0))),
    ('ready needs both matched endpoints',jsonb_build_array(pg_temp.ud_route()||'{"matched_target_latitude":null,"matched_target_longitude":null}'::jsonb)),
    ('matched pair incomplete',jsonb_build_array(pg_temp.ud_route()||'{"matched_source_latitude":null}'::jsonb)),
    ('matched latitude bounded',jsonb_build_array(pg_temp.ud_route()||'{"matched_source_latitude":91}'::jsonb)),
    ('matched longitude bounded',jsonb_build_array(pg_temp.ud_route()||'{"matched_target_longitude":181}'::jsonb)),
    ('ready source snap too far',jsonb_build_array(pg_temp.ud_route()||'{"matched_source_latitude":30.03}'::jsonb)),
    ('ready target snap too far',jsonb_build_array(pg_temp.ud_route()||'{"matched_target_latitude":30.03}'::jsonb)),
    ('review must identify an excessive snap',jsonb_build_array(pg_temp.ud_route(2147483647,'needs_pin_review',null))),
    ('duplicate university',jsonb_build_array(pg_temp.ud_route(),pg_temp.ud_route())),
    ('oversized array',(select jsonb_agg(pg_temp.ud_route()) from generate_series(1,17)))
  ) as cases(name,body) loop
    perform pg_temp.ud_error('invalid writer input: '||v_case.name, format(
      'select public.write_listing_university_routes(%L,%L,30.0276,31.21014,%L,%L::jsonb)',
      pg_temp.ud_id('write_atomic'),pg_temp.ud_id('owner'),'geoapify-walk-short-metric-snap100-v1',v_case.body),
      '22023','route_invalid_input');
  end loop;
end;
$writer_validation$;
select pg_temp.ud_error('writer rejects obsolete routing version',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'old-version',jsonb_build_array(pg_temp.ud_route()))$$,'22023','route_invalid_input');
set local role authenticated;
select pg_temp.ud_actor('owner');
select pg_temp.ud_assert('replays/errors preserve every current cache field and timestamp',
  (select jsonb_agg(to_jsonb(r) order by university_id) from public.listing_university_routes r
    where listing_id=pg_temp.ud_id('write_target'))
  = (select value from pg_temp.ud_snapshots where key='written_cache'));
select pg_temp.ud_assert('failed batches and invalid payloads leave no partial rows',
  not exists (select 1 from public.listing_university_routes where listing_id=pg_temp.ud_id('write_atomic')));

set local role service_role;
select pg_temp.ud_assert('server caches genuine zero distance without converting absent routes to zero',
  public.write_listing_university_routes(pg_temp.ud_id('write_atomic'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(
      pg_temp.ud_route(2147483647,'ready',0),
      pg_temp.ud_route(2147483646,'unroutable',null)||'{"matched_source_latitude":null,"matched_source_longitude":null,"matched_target_latitude":null,"matched_target_longitude":null}'::jsonb))=2);
set local role authenticated;
select pg_temp.ud_actor('owner');
select pg_temp.ud_assert('unreachable cache is explicitly null and reusable, distinct from a real zero route',
  (select status='unroutable' and distance_m is null and matched_source_latitude is null
   from public.listing_university_routes where listing_id=pg_temp.ud_id('write_atomic') and university_id=2147483646)
  and (select status='ready' and distance_m=0 from public.listing_university_routes
   where listing_id=pg_temp.ud_id('write_atomic') and university_id=2147483647));
update public.listings set latitude=30.0277 where id=pg_temp.ud_id('write_atomic');
set local role service_role;
select pg_temp.ud_assert('server caches excessive snap as review and retains over-10km successful route',
  public.write_listing_university_routes(pg_temp.ud_id('write_atomic'),pg_temp.ud_id('owner'),
    30.0277,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(
      pg_temp.ud_route(2147483647,'needs_pin_review',null)||'{"matched_source_latitude":30.03}'::jsonb,
      pg_temp.ud_route(2147483646,'ready',10000.0000001)))=2);
set local role authenticated;
select pg_temp.ud_actor('owner');
select pg_temp.ud_assert('review has no distance, while over-limit result retains exact distance',
  (select status='needs_pin_review' and distance_m is null from public.listing_university_routes
   where listing_id=pg_temp.ud_id('write_atomic') and university_id=2147483647)
  and (select status='ready' and distance_m=10000.0000001 from public.listing_university_routes
   where listing_id=pg_temp.ud_id('write_atomic') and university_id=2147483646));

reset role;
update public.profiles set role='student' where id=pg_temp.ud_id('owner');
set local role service_role;
select pg_temp.ud_error('server writer rechecks persisted landlord role',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(pg_temp.ud_route()))$$,
  '42501','route_write_not_authorized');
reset role;
update public.profiles set role='landlord' where id=pg_temp.ud_id('owner');

set local role authenticated;
select pg_temp.ud_actor('owner');
update public.listings set latitude=30.0277 where id=pg_temp.ud_id('write_target');
select pg_temp.ud_assert('pin edit immediately hides old cache from owner without deleting it',
  not exists (select 1 from public.listing_university_routes where listing_id=pg_temp.ud_id('write_target')));
set local role anon;
select pg_temp.ud_actor(null);
select pg_temp.ud_assert('pin edit immediately hides old cache from public table and search',
  not exists (select 1 from public.listing_university_routes where listing_id=pg_temp.ud_id('write_target'))
  and not exists (select 1 from public.search_listings_by_university(2147483647,null,null,50) where id=pg_temp.ud_id('write_target')));
set local role service_role;
select pg_temp.ud_error('late provider success cannot resurrect old listing coordinates',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0276,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(pg_temp.ud_route()))$$,
  'PT409','route_snapshot_stale');
select pg_temp.ud_assert('explicit refresh can replace stale inputs with new exact snapshots',
  public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0277,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(
      pg_temp.ud_route(),pg_temp.ud_route(2147483646)))=2);
set local role anon;
select pg_temp.ud_assert('new cache inputs restore direct-read and search visibility',
  (select count(*)=2 from public.listing_university_routes where listing_id=pg_temp.ud_id('write_target'))
  and exists (select 1 from public.search_listings_by_university(2147483647,null,null,50) where id=pg_temp.ud_id('write_target')));

reset role;
update public.universities set latitude=30.0278 where id=2147483647;
set local role anon;
select pg_temp.ud_assert('university pin edit hides all old endpoint snapshots immediately',
  not exists (select 1 from public.listing_university_routes where university_id=2147483647)
  and not exists (select 1 from public.search_listings_by_university(2147483647)));
set local role service_role;
select pg_temp.ud_error('late provider success cannot resurrect old university coordinates',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0277,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(pg_temp.ud_route()))$$,
  'PT409','route_snapshot_stale');
reset role;
update public.universities set latitude=30.0276,is_active=false where id=2147483647;
set local role anon;
select pg_temp.ud_assert('inactive catalogue entry and its routes are not exposed',
  not exists (select 1 from public.universities where id=2147483647)
  and not exists (select 1 from public.listing_university_routes where university_id=2147483647));
select pg_temp.ud_error('inactive university search is rejected',
  $$select public.search_listings_by_university(2147483647)$$,'22023','university_unavailable');
set local role service_role;
select pg_temp.ud_error('inactive target rejects backend completion',
  $$select public.write_listing_university_routes(pg_temp.ud_id('write_target'),pg_temp.ud_id('owner'),
    30.0277,31.21014,'geoapify-walk-short-metric-snap100-v1',jsonb_build_array(pg_temp.ud_route()))$$,
  'PT409','route_snapshot_stale');
reset role;
update public.universities set is_active=true where id=2147483647;
set local role authenticated;
select pg_temp.ud_actor('owner');
select public.set_listing_status(pg_temp.ud_id('write_target'),'archived');
select pg_temp.ud_assert('archiving preserves current cache for owner but not owner discovery',
  (select count(*)=2 from public.listing_university_routes where listing_id=pg_temp.ud_id('write_target'))
  and not exists (select 1 from public.search_listings_by_university(2147483647,null,null,50) where id=pg_temp.ud_id('write_target')));
set local role anon;
select pg_temp.ud_actor(null);
select pg_temp.ud_assert('archived listing and cache disappear from public',
  not exists (select 1 from public.listings where id=pg_temp.ud_id('write_target'))
  and not exists (select 1 from public.listing_university_routes where listing_id=pg_temp.ud_id('write_target')));

reset role;
do $preservation$
declare
  v_old record;
  v_count bigint;
begin
  for v_old in select * from pg_temp.ud_existing loop
    execute format('select count(*) from %s t where to_jsonb(t)=$1',v_old.relation)
      into v_count using v_old.value;
    if v_count <> 1 then raise exception 'FAIL: a pre-existing row changed in %',v_old.relation; end if;
  end loop;
  perform pg_temp.ud_assert('all pre-existing listings/profiles/lifestyle/Storage/bookings/catalogue/cache rows preserved exactly',true);
end;
$preservation$;

select count(*)::text || ' university discovery assertions passed; all fixtures will now roll back.' as result
from pg_temp.ud_results;
rollback;
