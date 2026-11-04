-- University walking discovery, additive upgrade of the marketplace foundation.
-- Run the WHOLE file as administrator, then 008 in an isolated development DB.
-- Existing installs run only missing upgrades; NEVER rerun fresh-only 001.
-- Original verifier order: 001,002,003,004,005,006,007,008. In particular 004's
-- address-only publication fixture predates the pin rule: run 004 BEFORE 007.
-- One transaction. After an error issue ROLLBACK before more SQL in that session.
-- An unchanged rerun is a checked no-op; unknown/drifted objects are refused.
-- Catalogue rows may be maintained by an administrator; reruns never reseed them.
-- Keep zameel_private outside the API's exposed schemas.
--
-- Public catalogue: the 16 supplied reference pins, not verified campus gates.
-- Cache: exact endpoint snapshots + geoapify-walk-short-metric-snap100-v1.
-- Only current, accessible-listing/active-university rows are readable. Draft
-- results remain owner-only. No client may write catalogue or cache rows.
-- Published pins are exact/public, matching the existing listing read contract.
-- The NOT VALID pin CHECK preserves legacy address-only publications, but new
-- publications/updates require a pin. Repair those rows before an administrator
-- runs ALTER TABLE public.listings VALIDATE CONSTRAINT listings_published_pin.
-- Validation is deliberately allowed by the rerun fingerprint below.
--
-- search_listings_by_university(integer,double precision,uuid,integer): flat
-- 001 listing columns + distance_m + university_id, published/current/ready only,
-- <=10000m inclusive, unrounded (distance_m,id) keyset; default 20, cap 50.
-- A null/nonpositive limit, inactive/unknown university, or invalid paired cursor
-- raises 22023. Do not round distance_m before returning it as a page cursor.
--
-- Server-only write_listing_university_routes(uuid,uuid,float8,float8,text,jsonb)
-- takes listing ID, verified landlord ID, original listing pin, routing version,
-- and 1..16 route objects with EXACT keys:
-- university_id, university_latitude, university_longitude, status, distance_m,
-- matched_source_latitude, matched_source_longitude, matched_target_latitude,
-- matched_target_longitude. Every nullable key must still be present.
-- Returns the number of inserted/replaced STALE rows. A concurrent current row
-- wins unchanged (including its timestamp); no bulk delete or pending state.
-- 40001/route_snapshot_stale rejects obsolete completions atomically.
-- 42501/route_write_not_authorized rejects a changed owner/persisted role.
-- Only service_role can execute it, with NO grants on any existing tables.

-- Apply 009 after this installer for lossless Data API coordinate transport.
begin;
set local search_path = pg_catalog;
select pg_catalog.pg_advisory_xact_lock(20261016, 120026);

do $migration$
declare
  v_listings regclass := pg_catalog.to_regclass('public.listings');
  v_universities regclass := pg_catalog.to_regclass('public.universities');
  v_routes regclass := pg_catalog.to_regclass('public.listing_university_routes');
  v_existing boolean := v_universities is not null;
  v_marker text;
  v_signature text;
  v_owner_predicate text := '((landlord_id=(SELECTauth.uid()ASuid))AND((SELECTzameel_private.current_profile_role()AScurrent_profile_role)=''landlord''::text))';
begin
  if v_listings is null or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regprocedure('auth.uid()') is null
     or pg_catalog.to_regprocedure('zameel_private.current_profile_role()') is null
     or pg_catalog.to_regprocedure('public.set_listing_status(uuid,text)') is null then
    raise exception 'discovery_requires_001: install the marketplace foundation first';
  end if;
  if (select count(*) from pg_catalog.pg_roles
      where rolname in ('anon', 'authenticated', 'service_role')) <> 3
     or exists (select 1 from pg_catalog.pg_class
       where oid in (v_listings, 'public.profiles'::regclass)
         and (relkind <> 'r' or not relrowsecurity)) then
    raise exception 'discovery_incompatible_foundation: expected marketplace roles, tables and RLS';
  end if;
  if (select count(*) from pg_catalog.pg_attribute
      where attrelid = v_listings and attnum > 0 and not attisdropped) <> 16
     or (select count(*) from pg_catalog.pg_attribute
       where attrelid = v_listings and attnum > 0 and not attisdropped and (
         (attname in ('id', 'landlord_id') and atttypid = 'uuid'::regtype and attnotnull) or
         (attname in ('title', 'pricing_unit', 'currency', 'status') and atttypid = 'text'::regtype and attnotnull) or
         (attname in ('description', 'address') and atttypid = 'text'::regtype and not attnotnull) or
         (attname in ('latitude', 'longitude') and atttypid = 'double precision'::regtype and not attnotnull) or
         (attname = 'monthly_rent' and atttypid = 'numeric'::regtype and atttypmod = 786438 and attnotnull) or
         (attname in ('total_bed_capacity', 'occupied_beds') and atttypid = 'integer'::regtype and attnotnull) or
         (attname = 'available_beds' and atttypid = 'integer'::regtype and attgenerated = 's') or
         (attname in ('created_at', 'updated_at') and atttypid = 'timestamptz'::regtype and attnotnull)
       )) <> 16
     or (select count(*) from pg_catalog.pg_constraint where conrelid = v_listings
       and contype = 'c' and convalidated and conname in (
         'listings_coordinate_pair', 'listings_latitude_check', 'listings_longitude_check',
         'listings_published_location', 'listings_occupancy_bounds')) <> 5 then
    raise exception 'discovery_incompatible_listings: expected the 001 listing column and coordinate contract';
  end if;
  -- Do not hide an unexpected access model behind another permissive policy.
  if (select count(*) from pg_catalog.pg_policy where polrelid = v_listings) <> 4
     or exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_listings and (
       p.polpermissive and (
         (p.polname = 'listings_published_read' and p.polcmd = 'r' and p.polwithcheck is null
           and p.polroles @> array[(select oid from pg_catalog.pg_roles where rolname = 'anon'),
                                  (select oid from pg_catalog.pg_roles where rolname = 'authenticated')]
           and pg_catalog.array_length(p.polroles, 1) = 2
           and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '\s', '', 'g') = '(status=''published''::text)')
         or (p.polroles = array[(select oid from pg_catalog.pg_roles where rolname = 'authenticated')]
           and ((p.polname = 'listings_owner_read' and p.polcmd = 'r' and p.polwithcheck is null
               and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '\s', '', 'g') = v_owner_predicate)
             or (p.polname = 'listings_owner_edit' and p.polcmd = 'w'
               and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '\s', '', 'g') = v_owner_predicate
               and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), '\s', '', 'g') = v_owner_predicate)
             or (p.polname = 'listings_owner_insert' and p.polcmd = 'a' and p.polqual is null
               and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), '\s', '', 'g') =
                 '((landlord_id=(SELECTauth.uid()ASuid))AND(status=''draft''::text)AND(occupied_beds=0)AND((SELECTzameel_private.current_profile_role()AScurrent_profile_role)=''landlord''::text))')))
       )) is distinct from true) then
    raise exception 'discovery_incompatible_listing_policies: expected published reads and landlord-owned writes';
  end if;
  if not pg_catalog.has_table_privilege('anon', v_listings, 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', v_listings, 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', v_listings, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or pg_catalog.has_table_privilege('anon', v_listings, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or exists (select 1 from pg_catalog.pg_class c
       where c.oid in (v_listings, 'public.profiles'::regclass)
         and (pg_catalog.has_table_privilege('service_role', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
           or exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = c.oid
             and a.attnum > 0 and not a.attisdropped
             and pg_catalog.has_column_privilege('service_role', c.oid, a.attnum, 'SELECT,INSERT,UPDATE,REFERENCES'))))
     or exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = v_listings
       and a.attnum > 0 and not a.attisdropped and (
         pg_catalog.has_column_privilege('authenticated', v_listings, a.attnum, 'INSERT')
           is distinct from (a.attname in ('title', 'description', 'address', 'latitude', 'longitude',
             'monthly_rent', 'pricing_unit', 'currency', 'total_bed_capacity'))
         or pg_catalog.has_column_privilege('authenticated', v_listings, a.attnum, 'UPDATE')
           is distinct from (a.attname in ('title', 'description', 'address', 'latitude', 'longitude',
             'monthly_rent', 'pricing_unit', 'currency', 'total_bed_capacity'))
         or pg_catalog.has_column_privilege('authenticated', v_listings, a.attnum, 'REFERENCES')
         or pg_catalog.has_column_privilege('anon', v_listings, a.attnum, 'INSERT,UPDATE,REFERENCES'))) then
    raise exception 'discovery_incompatible_listing_grants: expected the existing column allowlist and no service-role table access';
  end if;

  if v_existing then
    v_marker := pg_catalog.obj_description(v_universities, 'pg_class');
    if v_marker is null or v_marker not like 'zameel_university_discovery_v1:%' then
      raise exception 'discovery_existing_objects: catalogue is not this completed migration';
    end if;
  elsif v_routes is not null
     or pg_catalog.to_regtype('public.universities') is not null
     or pg_catalog.to_regtype('public.listing_university_routes') is not null
     or exists (select 1 from pg_catalog.pg_class where relnamespace = 'public'::regnamespace
       and relname in ('universities_pkey', 'listing_university_routes_pkey', 'listing_university_routes_discovery_idx'))
     or exists (select 1 from pg_catalog.pg_proc where
       (pronamespace = 'public'::regnamespace and proname in ('search_listings_by_university', 'write_listing_university_routes'))
       or (pronamespace = 'zameel_private'::regnamespace and proname = 'route_great_circle_m'))
     or exists (select 1 from pg_catalog.pg_constraint
       where conrelid = v_listings and conname = 'listings_published_pin') then
    raise exception 'discovery_existing_objects: review pre-existing discovery objects; nothing was overwritten';
  end if;

  if not v_existing then
    create table public.universities (
      id integer primary key check (id > 0),
      name text not null check (char_length(btrim(name)) between 1 and 200),
      city text not null check (char_length(btrim(city)) between 1 and 200),
      latitude double precision not null check (latitude between -90 and 90),
      longitude double precision not null check (longitude between -180 and 180),
      is_active boolean not null default true
    );
    create table public.listing_university_routes (
      listing_id uuid not null references public.listings(id) on delete cascade,
      university_id integer not null references public.universities(id) on delete cascade,
      status text not null check (status in ('ready', 'unroutable', 'needs_pin_review')),
      distance_m double precision,
      calculated_at timestamptz not null default clock_timestamp() check (isfinite(calculated_at)),
      listing_latitude double precision not null check (listing_latitude between -90 and 90),
      listing_longitude double precision not null check (listing_longitude between -180 and 180),
      university_latitude double precision not null check (university_latitude between -90 and 90),
      university_longitude double precision not null check (university_longitude between -180 and 180),
      routing_version text not null check (char_length(btrim(routing_version)) between 1 and 100),
      matched_source_latitude double precision check (matched_source_latitude between -90 and 90),
      matched_source_longitude double precision check (matched_source_longitude between -180 and 180),
      matched_target_latitude double precision check (matched_target_latitude between -90 and 90),
      matched_target_longitude double precision check (matched_target_longitude between -180 and 180),
      primary key (listing_id, university_id),
      constraint listing_routes_outcome check (
        (status = 'ready' and distance_m is not null and distance_m >= 0
          and distance_m < 'Infinity'::double precision
          and matched_source_latitude is not null and matched_target_latitude is not null)
        or (status in ('unroutable', 'needs_pin_review') and distance_m is null)
      ),
      constraint listing_routes_matched_pairs check (
        (matched_source_latitude is null) = (matched_source_longitude is null)
        and (matched_target_latitude is null) = (matched_target_longitude is null)
      )
    );
    create index listing_university_routes_discovery_idx
      on public.listing_university_routes(university_id, distance_m, listing_id)
      where status = 'ready' and distance_m <= 10000;

    alter table public.listings add constraint listings_published_pin check (
      status <> 'published' or (latitude is not null and longitude is not null)
    ) not valid;

    create function zameel_private.route_great_circle_m(
      p_lat1 double precision, p_lon1 double precision,
      p_lat2 double precision, p_lon2 double precision
    ) returns double precision language sql immutable strict security invoker set search_path = '' as $function$
      select 12742017.6 * pg_catalog.asin(pg_catalog.sqrt(least(1.0, greatest(0.0,
        pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_lat2 - p_lat1) / 2), 2)
        + pg_catalog.cos(pg_catalog.radians(p_lat1)) * pg_catalog.cos(pg_catalog.radians(p_lat2))
        * pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_lon2 - p_lon1) / 2), 2)
      ))));
    $function$;

    alter table public.universities enable row level security;
    alter table public.listing_university_routes enable row level security;
    create policy universities_active_read on public.universities
      for select to anon, authenticated using (is_active);
    create policy listing_routes_current_read on public.listing_university_routes
      for select to anon, authenticated using (
        routing_version = 'geoapify-walk-short-metric-snap100-v1' and exists (
          select 1 from public.listings l
          join public.universities u on u.id = listing_university_routes.university_id
          where l.id = listing_university_routes.listing_id and u.is_active
            and l.latitude = listing_university_routes.listing_latitude
            and l.longitude = listing_university_routes.listing_longitude
            and u.latitude = listing_university_routes.university_latitude
            and u.longitude = listing_university_routes.university_longitude
        )
      );
    revoke all on table public.universities, public.listing_university_routes
      from public, anon, authenticated, service_role;
    grant select on table public.universities, public.listing_university_routes to anon, authenticated;

    create function public.write_listing_university_routes(
      p_listing_id uuid, p_landlord_id uuid,
      p_listing_latitude double precision, p_listing_longitude double precision,
      p_routing_version text, p_routes jsonb
    ) returns integer language plpgsql volatile security definer
      set search_path = '' set lock_timeout = '2s' as $function$
    declare
      v_listing public.listings;
      v_university public.universities;
      v_route jsonb;
      v_row public.listing_university_routes;
      v_key text;
      v_number numeric;
      v_source_snap double precision;
      v_target_snap double precision;
      v_count integer := 0;
      v_changed integer;
    begin
      if p_listing_id is null or p_landlord_id is null
         or p_listing_latitude is null or p_listing_latitude not between -90 and 90
         or p_listing_longitude is null or p_listing_longitude not between -180 and 180
         or p_routing_version is distinct from 'geoapify-walk-short-metric-snap100-v1'
         or pg_catalog.jsonb_typeof(p_routes) is distinct from 'array' then
        raise exception using errcode = '22023', message = 'route_invalid_input';
      end if;
      if pg_catalog.jsonb_array_length(p_routes) not between 1 and 16 then
        raise exception using errcode = '22023', message = 'route_invalid_input';
      end if;
      -- Match the existing booking/status lock order: listing first. Hold the pin
      -- and catalogue rows through commit so edits cannot race a successful write.
      select * into v_listing from public.listings where id = p_listing_id for update;
      if not found or v_listing.landlord_id is distinct from p_landlord_id then
        raise exception using errcode = '42501', message = 'route_write_not_authorized';
      end if;
      perform 1 from public.profiles where id = p_landlord_id and role = 'landlord' for share;
      if not found then
        raise exception using errcode = '42501', message = 'route_write_not_authorized';
      end if;
      if v_listing.latitude is distinct from p_listing_latitude
         or v_listing.longitude is distinct from p_listing_longitude then
        -- Application conflicts must not trigger PostgREST's serialization retries.
        raise exception using errcode = 'PT409', message = 'route_snapshot_stale';
      end if;

      for v_route in select value from pg_catalog.jsonb_array_elements(p_routes) loop
        if pg_catalog.jsonb_typeof(v_route) is distinct from 'object' then
          raise exception using errcode = '22023', message = 'route_invalid_input';
        end if;
        if not (v_route ?& array['university_id', 'university_latitude', 'university_longitude',
            'status', 'distance_m', 'matched_source_latitude', 'matched_source_longitude',
            'matched_target_latitude', 'matched_target_longitude'])
           or v_route - array['university_id', 'university_latitude', 'university_longitude',
            'status', 'distance_m', 'matched_source_latitude', 'matched_source_longitude',
            'matched_target_latitude', 'matched_target_longitude'] <> '{}'::jsonb
           or pg_catalog.jsonb_typeof(v_route -> 'status') is distinct from 'string' then
          raise exception using errcode = '22023', message = 'route_invalid_input';
        end if;
        foreach v_key in array array['university_id', 'university_latitude', 'university_longitude',
          'distance_m', 'matched_source_latitude', 'matched_source_longitude',
          'matched_target_latitude', 'matched_target_longitude'] loop
          if pg_catalog.jsonb_typeof(v_route -> v_key) not in ('number', 'null')
             or (v_key in ('university_id', 'university_latitude', 'university_longitude')
               and v_route -> v_key = 'null'::jsonb) then
            raise exception using errcode = '22023', message = 'route_invalid_input';
          end if;
        end loop;
        v_number := (v_route ->> 'university_id')::numeric;
        if v_number <> pg_catalog.trunc(v_number) or v_number not between 1 and 2147483647 then
          raise exception using errcode = '22023', message = 'route_invalid_input';
        end if;
      end loop;
      if exists (select 1 from pg_catalog.jsonb_array_elements(p_routes) r
        group by (r.value ->> 'university_id')::numeric having count(*) > 1) then
        raise exception using errcode = '22023', message = 'route_invalid_input';
      end if;

      for v_route in select value from pg_catalog.jsonb_array_elements(p_routes)
        order by (value ->> 'university_id')::numeric loop
        select * into v_row from pg_catalog.jsonb_populate_record(null::public.listing_university_routes, v_route);
        select * into v_university from public.universities where id = v_row.university_id for share;
        if not found or not v_university.is_active
           or v_university.latitude is distinct from v_row.university_latitude
           or v_university.longitude is distinct from v_row.university_longitude then
          raise exception using errcode = 'PT409', message = 'route_snapshot_stale';
        end if;
        if v_row.status not in ('ready', 'unroutable', 'needs_pin_review')
           or (v_row.matched_source_latitude is null) <> (v_row.matched_source_longitude is null)
           or (v_row.matched_target_latitude is null) <> (v_row.matched_target_longitude is null)
           or v_row.matched_source_latitude not between -90 and 90
           or v_row.matched_source_longitude not between -180 and 180
           or v_row.matched_target_latitude not between -90 and 90
           or v_row.matched_target_longitude not between -180 and 180 then
          raise exception using errcode = '22023', message = 'route_invalid_input';
        end if;
        v_source_snap := zameel_private.route_great_circle_m(p_listing_latitude, p_listing_longitude,
          v_row.matched_source_latitude, v_row.matched_source_longitude);
        v_target_snap := zameel_private.route_great_circle_m(v_university.latitude, v_university.longitude,
          v_row.matched_target_latitude, v_row.matched_target_longitude);
        if (v_row.status = 'ready' and (v_row.distance_m is null
              or not (v_row.distance_m >= 0 and v_row.distance_m < 'Infinity'::double precision)
              or v_source_snap is null or v_target_snap is null or v_source_snap > 100 or v_target_snap > 100))
           or (v_row.status <> 'ready' and v_row.distance_m is not null)
           or (v_row.status = 'needs_pin_review' and not (coalesce(v_source_snap > 100, false) or coalesce(v_target_snap > 100, false)))
           or (v_row.status = 'unroutable' and (v_source_snap > 100 or v_target_snap > 100)) then
          raise exception using errcode = '22023', message = 'route_invalid_input';
        end if;
        insert into public.listing_university_routes as old (
          listing_id, university_id, status, distance_m, calculated_at,
          listing_latitude, listing_longitude, university_latitude, university_longitude,
          routing_version, matched_source_latitude, matched_source_longitude,
          matched_target_latitude, matched_target_longitude
        ) values (
          p_listing_id, v_university.id, v_row.status, v_row.distance_m, pg_catalog.clock_timestamp(),
          p_listing_latitude, p_listing_longitude, v_university.latitude, v_university.longitude,
          p_routing_version, v_row.matched_source_latitude, v_row.matched_source_longitude,
          v_row.matched_target_latitude, v_row.matched_target_longitude
        ) on conflict (listing_id, university_id) do update set
          status = excluded.status, distance_m = excluded.distance_m, calculated_at = excluded.calculated_at,
          listing_latitude = excluded.listing_latitude, listing_longitude = excluded.listing_longitude,
          university_latitude = excluded.university_latitude, university_longitude = excluded.university_longitude,
          routing_version = excluded.routing_version,
          matched_source_latitude = excluded.matched_source_latitude,
          matched_source_longitude = excluded.matched_source_longitude,
          matched_target_latitude = excluded.matched_target_latitude,
          matched_target_longitude = excluded.matched_target_longitude
        where old.listing_latitude is distinct from excluded.listing_latitude
          or old.listing_longitude is distinct from excluded.listing_longitude
          or old.university_latitude is distinct from excluded.university_latitude
          or old.university_longitude is distinct from excluded.university_longitude
          or old.routing_version is distinct from excluded.routing_version;
        get diagnostics v_changed = row_count;
        v_count := v_count + v_changed;
      end loop;
      return v_count;
    exception
      when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
        raise exception using errcode = '22023', message = 'route_invalid_input';
    end;
    $function$;

    create function public.search_listings_by_university(
      p_university_id integer, p_after_distance_m double precision default null,
      p_after_listing_id uuid default null, p_limit integer default 20
    ) returns table (
      id uuid, landlord_id uuid, title text, description text, address text,
      latitude double precision, longitude double precision, monthly_rent numeric,
      pricing_unit text, currency text, total_bed_capacity integer, occupied_beds integer,
      available_beds integer, status text, created_at timestamptz, updated_at timestamptz,
      distance_m double precision, university_id integer
    ) language plpgsql stable security invoker set search_path = '' as $function$
    begin
      if p_university_id is null or p_university_id <= 0 or not exists (
        select 1 from public.universities u where u.id = p_university_id and u.is_active
      ) then
        raise exception using errcode = '22023', message = 'university_unavailable';
      end if;
      if p_limit is null or p_limit <= 0 then
        raise exception using errcode = '22023', message = 'invalid_search_limit';
      end if;
      if (p_after_distance_m is null) <> (p_after_listing_id is null)
         or p_after_distance_m not between 0 and 10000 then
        raise exception using errcode = '22023', message = 'invalid_search_cursor';
      end if;
      return query
      select l.id, l.landlord_id, l.title, l.description, l.address,
        l.latitude, l.longitude, l.monthly_rent, l.pricing_unit, l.currency,
        l.total_bed_capacity, l.occupied_beds, l.available_beds, l.status,
        l.created_at, l.updated_at, r.distance_m, r.university_id
      from public.listing_university_routes r
      join public.listings l on l.id = r.listing_id
      join public.universities u on u.id = r.university_id
      where r.university_id = p_university_id and u.is_active and l.status = 'published'
        and r.status = 'ready' and r.distance_m <= 10000
        and r.routing_version = 'geoapify-walk-short-metric-snap100-v1'
        and r.listing_latitude = l.latitude and r.listing_longitude = l.longitude
        and r.university_latitude = u.latitude and r.university_longitude = u.longitude
        and (p_after_distance_m is null or (r.distance_m, l.id) > (p_after_distance_m, p_after_listing_id))
      order by r.distance_m, l.id limit least(p_limit, 50);
    end;
    $function$;

    revoke all on function zameel_private.route_great_circle_m(double precision,double precision,double precision,double precision),
      public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb),
      public.search_listings_by_university(integer,double precision,uuid,integer)
      from public, anon, authenticated, service_role;
    grant execute on function public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)
      to service_role;
    grant execute on function public.search_listings_by_university(integer,double precision,uuid,integer)
      to anon, authenticated;

    insert into public.universities(id, name, city, latitude, longitude) values
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
      (16, 'Arab Open University (AOU) - Egypt', 'El-Shorouk City, Cairo Governorate', 30.1297, 31.615);
    v_universities := 'public.universities'::regclass;
    v_routes := 'public.listing_university_routes'::regclass;
  end if;

  -- Definitions and ACLs, never catalogue/cache/user rows. All objects on the new
  -- tables are included so an unknown policy, trigger, column or grant is drift.
  select pg_catalog.md5(pg_catalog.string_agg(definition, E'\n' order by definition)) into v_signature
  from (
    select 'table:' || c.oid::regclass::text || ':' || c.relkind::text || ':' || c.relowner::text || ':' ||
      c.relrowsecurity::text || ':' || c.relforcerowsecurity::text || ':' || coalesce(c.relacl::text, '') as definition
    from pg_catalog.pg_class c where c.oid in (v_universities, v_routes)
    union all
    select 'column:' || a.attrelid::regclass::text || ':' || a.attname || ':' || a.attnum::text || ':' ||
      a.atttypid::text || ':' || a.atttypmod::text || ':' || a.attnotnull::text || ':' ||
      a.attidentity::text || ':' || a.attgenerated::text || ':' || coalesce(a.attacl::text, '') || ':' ||
      coalesce(pg_catalog.pg_get_expr(d.adbin, d.adrelid), '')
    from pg_catalog.pg_attribute a left join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid in (v_universities, v_routes) and a.attnum > 0 and not a.attisdropped
    union all
    select 'constraint:' || c.conrelid::regclass::text || ':' || c.conname || ':' ||
      case when c.conrelid = v_listings then pg_catalog.replace(pg_catalog.pg_get_constraintdef(c.oid), ' NOT VALID', '')
        else pg_catalog.pg_get_constraintdef(c.oid) || ':' || c.convalidated::text end
    from pg_catalog.pg_constraint c where c.conrelid in (v_universities, v_routes)
      or (c.conrelid = v_listings and c.conname = 'listings_published_pin')
    union all
    select 'index:' || pg_catalog.pg_get_indexdef(i.indexrelid) || ':' || i.indisvalid::text || ':' || i.indisready::text
    from pg_catalog.pg_index i where i.indrelid in (v_universities, v_routes)
    union all
    select 'trigger:' || pg_catalog.pg_get_triggerdef(t.oid) || ':' || t.tgenabled::text
    from pg_catalog.pg_trigger t where t.tgrelid in (v_universities, v_routes) and not t.tgisinternal
    union all
    select 'rule:' || pg_catalog.pg_get_ruledef(r.oid)
    from pg_catalog.pg_rewrite r where r.ev_class in (v_universities, v_routes)
    union all
    select 'policy:' || p.polrelid::regclass::text || ':' || p.polname || ':' || p.polcmd::text || ':' ||
      p.polpermissive::text || ':' || p.polroles::text || ':' ||
      coalesce(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '') || ':' ||
      coalesce(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), '')
    from pg_catalog.pg_policy p where p.polrelid in (v_universities, v_routes)
    union all
    select 'function:' || pg_catalog.pg_get_functiondef(p.oid) || ':' || p.proowner::text || ':' || coalesce(p.proacl::text, '')
    from pg_catalog.pg_proc p where
      (p.pronamespace = 'public'::regnamespace and p.proname in ('search_listings_by_university', 'write_listing_university_routes'))
      or (p.pronamespace = 'zameel_private'::regnamespace and p.proname = 'route_great_circle_m')
  ) as owned;
  if v_existing then
    if v_marker is distinct from 'zameel_university_discovery_v1:' || v_signature then
      raise exception 'discovery_definition_drift: review a new migration instead of overwriting changed discovery objects';
    end if;
    raise notice 'University discovery v1 already installed and unchanged; no rows or definitions changed.';
  else
    execute pg_catalog.format('comment on table public.universities is %L',
      'zameel_university_discovery_v1:' || v_signature);
    raise notice 'University discovery installed; existing listings, profiles, lifestyle, Storage and bookings preserved.';
  end if;
end;
$migration$;

notify pgrst, 'reload schema';
commit;
