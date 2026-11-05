-- Optional double/triple rooms, additive upgrade AFTER 001, 007 and 009.
-- Run the WHOLE file as the original installation owner, then run 011 only in a
-- disposable development database, BEFORE releasing the updated client.
-- One transaction; after any error issue ROLLBACK before more SQL in that session.
-- This migration deliberately REFUSES reruns or incompatible/pre-existing objects.
-- Do not drop objects to make it pass. Future changes need a reviewed migration.
-- No users, bookings, prices or occupancy are backfilled/reassigned/cancelled.
-- Existing generic listings retain their price, capacity and occupied-bed count.
--
-- Each type has one PER-BED monthly rate, never a price per physical bed/room.
-- Count 0 requires NULL rent; count > 0 enables a type, including a zero price.
-- Options require per_bed. Capacity = double_count*2 + triple_count*3 (int bounded),
-- summary rent = cheapest enabled rate, occupied_beds = sum of type occupancy.
-- Clients may INSERT/UPDATE only the four new count/rent fields, not counters.
-- Enabling options with active unassigned requests, removing an actively selected
-- type or shrinking below its occupancy fails 22023/room_options_have_active_bookings.
-- Price changes remain allowed. No generic capacity is mixed into enabled options.
--
-- submit_booking(p_listing_id uuid, p_request_id uuid, p_message text DEFAULT NULL,
--                p_room_type text DEFAULT NULL) returns public.bookings.
-- room_type is NULL (generic) or exactly 'double'/'triple', immutable on the request.
-- A typed listing requires an enabled, non-full selection. The server snapshots
-- its CURRENT rate; aggregate snapshot capacity fields keep their original meaning.
-- Replays match listing, normalized message AND room type before current availability
-- checks, including after removal/unpublication. Quotes are never repriced.
-- accept/reject/cancel signatures are unchanged; pending requests reserve nothing.
-- All writes retain listing-first locking and participant/database-role checks.
--
-- v1 search and the EXACT 007/009 discovery fingerprint remain unchanged. v2 adds
-- six flat listing fields after the existing result fields, with identical filters,
-- unrounded global (distance_m,id) ordering, cursors, defaults and limits under RLS.
-- Do NOT rerun 007: its preflight requires the old exact listing column allowlist.
-- Keep zameel_private outside exposed API schemas. No hosted deployment is implied.

begin;
set local search_path = pg_catalog;
set local lock_timeout = '2s';
select pg_catalog.pg_advisory_xact_lock(20261016, 120026);

do $preflight$
declare
  v_listings regclass := pg_catalog.to_regclass('public.listings');
  v_bookings regclass := pg_catalog.to_regclass('public.bookings');
  v_residents regclass := pg_catalog.to_regclass('public.listing_residents');
  v_universities regclass := pg_catalog.to_regclass('public.universities');
  v_routes regclass := pg_catalog.to_regclass('public.listing_university_routes');
  v_owner oid;
  v_expected record;
  v_function record;
  v_signature text;
  v_owner_predicate text := '((landlord_id=(SELECTauth.uid()ASuid))AND((SELECTzameel_private.current_profile_role()AScurrent_profile_role)=''landlord''::text))';
begin
  if v_listings is null or v_bookings is null or v_residents is null
     or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regprocedure('auth.uid()') is null
     or pg_catalog.to_regnamespace('zameel_private') is null then
    raise exception 'room_pricing_requires_001: install the marketplace foundation first';
  end if;
  if v_universities is null or v_routes is null
     or pg_catalog.to_regprocedure('public.search_listings_by_university(integer,double precision,uuid,integer)') is null
     or pg_catalog.to_regprocedure('public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)') is null then
    raise exception 'room_pricing_requires_007_009: install discovery and route transport first';
  end if;
  if (select count(*) from pg_catalog.pg_roles where rolname in ('anon','authenticated','service_role')
      and coalesce(rolconfig @> array['extra_float_digits=1'], false)) <> 3
     or pg_catalog.strpos(pg_catalog.pg_get_functiondef(
       'public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)'::regprocedure),
       'errcode = ''PT409'', message = ''route_snapshot_stale''') = 0 then
    raise exception 'room_pricing_requires_009: expected lossless API transport and PT409 stale snapshots';
  end if;
  if exists (select 1 from pg_catalog.pg_attribute where attnum > 0 and not attisdropped and (
       (attrelid = v_listings and attname in ('double_room_count','double_room_monthly_rent','double_room_occupied_beds',
         'triple_room_count','triple_room_monthly_rent','triple_room_occupied_beds'))
       or (attrelid = v_bookings and attname = 'room_type')))
     or exists (select 1 from pg_catalog.pg_proc where
       (pronamespace = 'public'::regnamespace and proname = 'search_listings_by_university_v2')
       or (pronamespace = 'zameel_private'::regnamespace
         and proname in ('guard_listing_room_options','guard_booking_room_type')))
     or (select count(*) from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace
       and proname = 'submit_booking') <> 1
     or pg_catalog.to_regprocedure('public.submit_booking(uuid,uuid,text)') is null then
    raise exception 'room_pricing_existing_objects: 010 is not rerunnable; review existing room columns/routines, nothing was overwritten';
  end if;

  -- Lock schema changes before checking the objects that this transaction extends.
  -- Booking operations already take the listing row first; no data is changed here.
  lock table public.listings, public.bookings, public.listing_residents in access exclusive mode;
  select relowner into v_owner from pg_catalog.pg_class where oid = v_listings;
  if v_owner <> current_user::regrole::oid or exists (select 1 from pg_catalog.pg_class
      where oid in (v_listings,v_bookings,v_residents,'public.profiles'::regclass)
        and (relkind <> 'r' or not relrowsecurity or relforcerowsecurity or relowner <> v_owner))
     or exists (select 1 from pg_catalog.pg_roles where rolname in ('anon','authenticated')
       and (rolsuper or rolbypassrls)) then
    raise exception 'room_pricing_incompatible_foundation: expected original owner, ordinary tables and enabled RLS';
  end if;
  if exists (select 1 from (values ('anon'),('authenticated'),('service_role')) r(name)
      where pg_catalog.has_column_privilege(r.name,'public.profiles','id','INSERT,UPDATE,REFERENCES')
         or pg_catalog.has_column_privilege(r.name,'public.profiles','role','INSERT,UPDATE,REFERENCES')
         or pg_catalog.has_table_privilege(r.name,'public.profiles','DELETE,TRUNCATE,TRIGGER')) then
    raise exception 'room_pricing_profile_role_grants: persisted profile identity and role must remain server-owned';
  end if;

  -- Check the exact column types/nullability, without assuming new columns can be
  -- grafted onto a different listing/booking schema. Only generated availability is allowed.
  for v_expected in select * from (values
    (v_listings, 'id:uuid:1,landlord_id:uuid:1,title:text:1,description:text:0,address:text:0,latitude:double precision:0,longitude:double precision:0,monthly_rent:numeric(12,2):1,pricing_unit:text:1,currency:text:1,total_bed_capacity:integer:1,occupied_beds:integer:1,available_beds:integer:0,status:text:1,created_at:timestamp with time zone:1,updated_at:timestamp with time zone:1'),
    (v_bookings, 'id:uuid:1,listing_id:uuid:1,student_id:uuid:1,request_id:uuid:1,status:text:1,message:text:0,snapshot_monthly_rent:numeric(12,2):1,snapshot_currency:text:1,snapshot_pricing_unit:text:1,snapshot_occupied_beds:integer:1,snapshot_total_beds:integer:1,requested_at:timestamp with time zone:1,responded_at:timestamp with time zone:0,cancelled_at:timestamp with time zone:0,created_at:timestamp with time zone:1,updated_at:timestamp with time zone:1'),
    (v_residents, 'id:uuid:1,booking_id:uuid:1,listing_id:uuid:1,user_id:uuid:1,joined_at:timestamp with time zone:1,left_at:timestamp with time zone:0')
  ) as expected(relation, shape) loop
    if (select pg_catalog.string_agg(a.attname || ':' || pg_catalog.format_type(a.atttypid,a.atttypmod)
        || ':' || a.attnotnull::integer::text, ',' order by a.attnum)
        from pg_catalog.pg_attribute a where a.attrelid = v_expected.relation and a.attnum > 0 and not a.attisdropped)
        is distinct from v_expected.shape
       or exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = v_expected.relation
         and a.attnum > 0 and not a.attisdropped and (a.attidentity <> ''
           or a.attgenerated <> case when a.attrelid = v_listings and a.attname = 'available_beds' then 's' else '' end)) then
      raise exception 'room_pricing_incompatible_columns: %', v_expected.relation;
    end if;
  end loop;
  for v_expected in select * from (values
    (v_listings,'id','gen_random_uuid()'), (v_listings,'landlord_id','auth.uid()'),
    (v_listings,'status','''draft''::text'), (v_listings,'occupied_beds','0'),
    (v_listings,'available_beds','(total_bed_capacity-occupied_beds)'),
    (v_bookings,'id','gen_random_uuid()'), (v_bookings,'status','''pending''::text'),
    (v_residents,'joined_at','clock_timestamp()')
  ) as expected(relation, name, expression) loop
    if (select pg_catalog.regexp_replace(pg_catalog.pg_get_expr(d.adbin,d.adrelid),'\s','','g')
        from pg_catalog.pg_attribute a join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
        where a.attrelid = v_expected.relation and a.attname = v_expected.name) is distinct from v_expected.expression then
      raise exception 'room_pricing_incompatible_default: %.%', v_expected.relation, v_expected.name;
    end if;
  end loop;

  -- Core capacity, quote, status and identity constraints must not have drifted.
  for v_expected in select * from (values
    (v_listings,'listings_pkey','PRIMARYKEY(id)'),
    (v_listings,'listings_occupancy_bounds','CHECK(((occupied_beds>=0)AND(occupied_beds<=total_bed_capacity)))'),
    (v_listings,'listings_total_bed_capacity_check','CHECK((total_bed_capacity>0))'),
    (v_listings,'listings_monthly_rent_check','CHECK(((monthly_rent>=(0)::numeric)AND(monthly_rent<(''10000000000''::bigint)::numeric)))'),
    (v_listings,'listings_pricing_unit_check','CHECK((pricing_unit=ANY(ARRAY[''per_bed''::text,''per_room''::text,''per_property''::text])))'),
    (v_listings,'listings_status_check','CHECK((status=ANY(ARRAY[''draft''::text,''published''::text,''archived''::text])))'),
    (v_listings,'listings_landlord_id_fkey','FOREIGNKEY(landlord_id)REFERENCESpublic.profiles(id)ONDELETERESTRICT'),
    (v_bookings,'bookings_pkey','PRIMARYKEY(id)'),
    (v_bookings,'bookings_student_id_request_id_key','UNIQUE(student_id,request_id)'),
    (v_bookings,'bookings_id_listing_id_student_id_key','UNIQUE(id,listing_id,student_id)'),
    (v_bookings,'bookings_listing_id_fkey','FOREIGNKEY(listing_id)REFERENCESpublic.listings(id)ONDELETERESTRICT'),
    (v_bookings,'bookings_student_id_fkey','FOREIGNKEY(student_id)REFERENCESpublic.profiles(id)ONDELETERESTRICT'),
    (v_bookings,'bookings_snapshot_pricing_unit_check','CHECK((snapshot_pricing_unit=''per_bed''::text))'),
    (v_bookings,'bookings_snapshot_bounds','CHECK(((snapshot_occupied_beds>=0)AND(snapshot_occupied_beds<=snapshot_total_beds)))'),
    (v_bookings,'bookings_snapshot_total_beds_check','CHECK((snapshot_total_beds>0))'),
    (v_bookings,'bookings_snapshot_monthly_rent_check','CHECK(((snapshot_monthly_rent>=(0)::numeric)AND(snapshot_monthly_rent<(''10000000000''::bigint)::numeric)))'),
    (v_bookings,'bookings_status_check','CHECK((status=ANY(ARRAY[''pending''::text,''accepted''::text,''rejected''::text,''cancelled''::text])))'),
    (v_bookings,'bookings_status_times','CHECK((((status=''pending''::text)AND(responded_atISNULL)AND(cancelled_atISNULL))OR((status=ANY(ARRAY[''accepted''::text,''rejected''::text]))AND(responded_atISNOTNULL)AND(cancelled_atISNULL))OR((status=''cancelled''::text)AND(cancelled_atISNOTNULL))))'),
    (v_residents,'listing_residents_booking_id_key','UNIQUE(booking_id)'),
    (v_residents,'listing_residents_booking_id_listing_id_user_id_fkey','FOREIGNKEY(booking_id,listing_id,user_id)REFERENCESpublic.bookings(id,listing_id,student_id)ONDELETERESTRICT')
  ) as expected(relation, name, definition) loop
    if not exists (select 1 from pg_catalog.pg_constraint c where c.conrelid = v_expected.relation
        and c.conname = v_expected.name and c.convalidated and not c.condeferrable
        and pg_catalog.regexp_replace(pg_catalog.pg_get_constraintdef(c.oid),'\s','','g') = v_expected.definition) then
      raise exception 'room_pricing_incompatible_constraint: %', v_expected.name;
    end if;
  end loop;
  if not exists (select 1 from pg_catalog.pg_index i where i.indrelid = v_bookings
      and i.indisunique and i.indisvalid and i.indisready
      and pg_catalog.pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX bookings_one_active_per_listing_idx ON public.bookings USING btree (listing_id, student_id) WHERE (status = ANY (ARRAY[''pending''::text, ''accepted''::text]))')
     or not exists (select 1 from pg_catalog.pg_index i where i.indrelid = v_residents
      and i.indisunique and i.indisvalid and i.indisready
      and pg_catalog.pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX listing_residents_one_current_idx ON public.listing_residents USING btree (listing_id, user_id) WHERE (left_at IS NULL)') then
    raise exception 'room_pricing_incompatible_booking_indexes: active request/resident uniqueness is required';
  end if;

  -- Preserve the existing RLS, rather than broadening policies to make this work.
  if (select count(*) from pg_catalog.pg_policy where polrelid in (v_listings,v_bookings,v_residents)) <> 6
     or exists (select 1 from pg_catalog.pg_policy p where p.polrelid in (v_listings,v_bookings,v_residents) and (
       p.polpermissive and (
         (p.polrelid = v_listings and p.polname = 'listings_published_read' and p.polcmd = 'r' and p.polwithcheck is null
           and p.polroles @> array['anon'::regrole::oid,'authenticated'::regrole::oid] and pg_catalog.array_length(p.polroles,1) = 2
           and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'\s','','g') = '(status=''published''::text)')
         or (p.polroles = array['authenticated'::regrole::oid] and (
           (p.polrelid = v_listings and p.polname in ('listings_owner_read','listings_owner_edit')
             and p.polcmd = case when p.polname = 'listings_owner_read' then 'r'::"char" else 'w'::"char" end
             and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'\s','','g') = v_owner_predicate
             and ((p.polname = 'listings_owner_read' and p.polwithcheck is null) or
               (p.polname = 'listings_owner_edit' and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'\s','','g') = v_owner_predicate)))
           or (p.polrelid = v_listings and p.polname = 'listings_owner_insert' and p.polcmd = 'a' and p.polqual is null
             and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'\s','','g') =
               '((landlord_id=(SELECTauth.uid()ASuid))AND(status=''draft''::text)AND(occupied_beds=0)AND((SELECTzameel_private.current_profile_role()AScurrent_profile_role)=''landlord''::text))')
           or (p.polcmd = 'r' and p.polwithcheck is null and (
             (p.polrelid = v_bookings and p.polname = 'bookings_participants_read'
               and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'\s','','g') =
                 '(((student_id=(SELECTauth.uid()ASuid))AND((SELECTzameel_private.current_profile_role()AScurrent_profile_role)=''student''::text))ORzameel_private.owns_listing(listing_id))')
             or (p.polrelid = v_residents and p.polname = 'residents_participants_read'
               and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'\s','','g') =
                 '(((user_id=(SELECTauth.uid()ASuid))AND((SELECTzameel_private.current_profile_role()AScurrent_profile_role)=''student''::text))ORzameel_private.owns_listing(listing_id))')))
         ))
       )) is distinct from true) then
    raise exception 'room_pricing_incompatible_policies: expected original owner/participant RLS';
  end if;
  if exists (select 1 from pg_catalog.pg_class c cross join (values ('anon'),('authenticated'),('service_role')) r(name)
      where c.oid in (v_listings,v_bookings,v_residents) and (
        pg_catalog.has_table_privilege(r.name,c.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or pg_catalog.has_table_privilege(r.name,c.oid,'SELECT') is distinct from
          (r.name = 'authenticated' or (r.name = 'anon' and c.oid = v_listings))
        or exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped and (
          pg_catalog.has_column_privilege(r.name,c.oid,a.attnum,'INSERT') is distinct from
            (r.name = 'authenticated' and c.oid = v_listings and a.attname in
              ('title','description','address','latitude','longitude','monthly_rent','pricing_unit','currency','total_bed_capacity'))
          or pg_catalog.has_column_privilege(r.name,c.oid,a.attnum,'UPDATE') is distinct from
            (r.name = 'authenticated' and c.oid = v_listings and a.attname in
              ('title','description','address','latitude','longitude','monthly_rent','pricing_unit','currency','total_bed_capacity'))
          or pg_catalog.has_column_privilege(r.name,c.oid,a.attnum,'REFERENCES')
          or (r.name = 'service_role' and pg_catalog.has_column_privilege(r.name,c.oid,a.attnum,'SELECT')))))) then
    raise exception 'room_pricing_incompatible_grants: expected existing column allowlist and protected booking/counter writes';
  end if;
  if exists (select 1 from pg_catalog.pg_class c
      cross join lateral pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
      where c.oid in (v_listings,v_bookings,v_residents) and a.grantee <> v_owner
        and (a.grantee not in ('anon'::regrole::oid,'authenticated'::regrole::oid)
          or a.privilege_type <> 'SELECT' or a.is_grantable))
     or exists (select 1 from pg_catalog.pg_attribute c cross join lateral pg_catalog.aclexplode(c.attacl) a
      where c.attrelid in (v_listings,v_bookings,v_residents) and c.attnum > 0 and not c.attisdropped
        and a.grantee <> v_owner and (a.grantee <> 'authenticated'::regrole::oid
          or a.privilege_type not in ('INSERT','UPDATE') or a.is_grantable)) then
    raise exception 'room_pricing_incompatible_grants: unexpected grantee or grant option on extended tables';
  end if;

  -- These are the exact 001 bodies, normalizing CRLF to LF only. Do not strip
  -- whitespace inside SQL literals or overwrite custom authorization/locking.
  -- These prerequisite hashes are NOT replacements for the v1 discovery marker.
  for v_expected in select * from (values
    ('public.submit_booking(uuid,uuid,text)','34de37d28291b7e852eb201c35c99165',true,'v',1,'public.bookings','p_listing_id,p_request_id,p_message',true),
    ('public.accept_booking(uuid,uuid)','eacc56f3706a9c4917ff890fb3025e1f',true,'v',0,'public.bookings','p_listing_id,p_booking_id',true),
    ('public.reject_booking(uuid,uuid)','32e30357903d177da8a2e2f80d4e31ec',true,'v',0,'public.bookings','p_listing_id,p_booking_id',true),
    ('public.cancel_booking(uuid,uuid)','9428ac25ac3e073998616b9688a30651',true,'v',0,'public.bookings','p_listing_id,p_booking_id',true),
    ('public.set_listing_status(uuid,text)','5a97366acd987687b797f8c3a3799c57',true,'v',0,'public.listings','p_listing_id,p_status',true),
    ('zameel_private.transition_booking(uuid,uuid,text)','0da095e9dc476ca945c986597d2646fe',false,'v',0,'public.bookings','p_listing_id,p_booking_id,p_action',false),
    ('zameel_private.guard_listing_unit()','3d897dc85c2cc77a1f934e3fd1153f4e',true,'v',0,'trigger',null,false),
    ('zameel_private.touch_updated_at()','a0f1070a3d9a9591442754edcc1d19a3',false,'v',0,'trigger',null,false),
    ('zameel_private.current_profile_role()','dc5f4a6b28b85d2fa5058ae9a6238041',true,'s',0,'text',null,true),
    ('zameel_private.owns_listing(uuid)','84f68e6be2fdc41ad3ad812c05832cf9',true,'s',0,'boolean','p_listing_id',true)
  ) as expected(signature, body_hash, definer, volatility, defaults, result_type, arguments, client_execute) loop
    select * into v_function from pg_catalog.pg_proc where oid = pg_catalog.to_regprocedure(v_expected.signature);
    if not found then raise exception 'room_pricing_missing_routine: %', v_expected.signature; end if;
    if pg_catalog.md5(pg_catalog.replace(v_function.prosrc,E'\r\n',E'\n')) <> v_expected.body_hash
       or v_function.proowner <> v_owner or v_function.prosecdef <> v_expected.definer
       or v_function.provolatile::text <> v_expected.volatility or v_function.proretset or v_function.proisstrict
       or v_function.prokind <> 'f' or v_function.proleakproof or v_function.proparallel <> 'u'
       or v_function.prolang <> (select oid from pg_catalog.pg_language where lanname =
         case when v_function.proname in ('accept_booking','reject_booking','cancel_booking','current_profile_role','owns_listing')
           then 'sql' else 'plpgsql' end)
       or v_function.proconfig is distinct from array['search_path=""']
       or v_function.pronargdefaults <> v_expected.defaults
       or pg_catalog.pg_get_expr(v_function.proargdefaults,0) is distinct from
         (case when v_expected.defaults = 1 then 'NULL::text' else null end)
       or v_function.prorettype <> v_expected.result_type::regtype
       or pg_catalog.array_to_string(v_function.proargnames,',') is distinct from v_expected.arguments
       or pg_catalog.has_function_privilege('authenticated',v_function.oid,'EXECUTE') <> v_expected.client_execute
       or pg_catalog.has_function_privilege('anon',v_function.oid,'EXECUTE')
       or pg_catalog.has_function_privilege('service_role',v_function.oid,'EXECUTE')
       or exists (select 1 from pg_catalog.aclexplode(coalesce(v_function.proacl,pg_catalog.acldefault('f',v_function.proowner))) a
         where a.grantee <> v_owner and (a.grantee <> 'authenticated'::regrole::oid or not v_expected.client_execute or a.is_grantable))
       or exists (select 1 from pg_catalog.pg_proc p where p.pronamespace = v_function.pronamespace
         and p.proname = v_function.proname and p.oid <> v_function.oid) then
      raise exception 'room_pricing_routine_drift: %', v_expected.signature;
    end if;
  end loop;
  if (select count(*) from pg_catalog.pg_trigger where tgrelid in (v_listings,v_bookings,v_residents) and not tgisinternal) <> 3
     or exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid in (v_listings,v_bookings,v_residents)
       and not t.tgisinternal and (t.tgtype = 19 and t.tgenabled = 'O' and t.tgqual is null and t.tgnargs = 0 and (
         (t.tgrelid = v_listings and t.tgname = 'listings_guard_unit'
           and t.tgfoid = 'zameel_private.guard_listing_unit()'::regprocedure and t.tgattr::text = '9')
         or (t.tgfoid = 'zameel_private.touch_updated_at()'::regprocedure and t.tgattr::text = '' and
           ((t.tgrelid = v_listings and t.tgname = 'listings_touch_updated_at')
            or (t.tgrelid = v_bookings and t.tgname = 'bookings_touch_updated_at'))))) is distinct from true)
     or exists (select 1 from pg_catalog.pg_rewrite where ev_class in (v_listings,v_bookings,v_residents)) then
    raise exception 'room_pricing_trigger_drift: expected only original listing/unit and timestamp guards';
  end if;

  -- EXACT 007/009 owned-object set/serialization, checked but NEVER rewritten.
  select pg_catalog.md5(pg_catalog.string_agg(definition,E'\n' order by definition)) into v_signature
  from (
    select 'table:' || c.oid::regclass::text || ':' || c.relkind::text || ':' || c.relowner::text || ':' ||
      c.relrowsecurity::text || ':' || c.relforcerowsecurity::text || ':' || coalesce(c.relacl::text,'') as definition
    from pg_catalog.pg_class c where c.oid in (v_universities,v_routes)
    union all
    select 'column:' || a.attrelid::regclass::text || ':' || a.attname || ':' || a.attnum::text || ':' ||
      a.atttypid::text || ':' || a.atttypmod::text || ':' || a.attnotnull::text || ':' ||
      a.attidentity::text || ':' || a.attgenerated::text || ':' || coalesce(a.attacl::text,'') || ':' ||
      coalesce(pg_catalog.pg_get_expr(d.adbin,d.adrelid),'')
    from pg_catalog.pg_attribute a left join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid in (v_universities,v_routes) and a.attnum > 0 and not a.attisdropped
    union all
    select 'constraint:' || c.conrelid::regclass::text || ':' || c.conname || ':' ||
      case when c.conrelid = v_listings then pg_catalog.replace(pg_catalog.pg_get_constraintdef(c.oid),' NOT VALID','')
        else pg_catalog.pg_get_constraintdef(c.oid) || ':' || c.convalidated::text end
    from pg_catalog.pg_constraint c where c.conrelid in (v_universities,v_routes)
      or (c.conrelid = v_listings and c.conname = 'listings_published_pin')
    union all
    select 'index:' || pg_catalog.pg_get_indexdef(i.indexrelid) || ':' || i.indisvalid::text || ':' || i.indisready::text
    from pg_catalog.pg_index i where i.indrelid in (v_universities,v_routes)
    union all
    select 'trigger:' || pg_catalog.pg_get_triggerdef(t.oid) || ':' || t.tgenabled::text
    from pg_catalog.pg_trigger t where t.tgrelid in (v_universities,v_routes) and not t.tgisinternal
    union all
    select 'rule:' || pg_catalog.pg_get_ruledef(r.oid) from pg_catalog.pg_rewrite r where r.ev_class in (v_universities,v_routes)
    union all
    select 'policy:' || p.polrelid::regclass::text || ':' || p.polname || ':' || p.polcmd::text || ':' ||
      p.polpermissive::text || ':' || p.polroles::text || ':' ||
      coalesce(pg_catalog.pg_get_expr(p.polqual,p.polrelid),'') || ':' || coalesce(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid),'')
    from pg_catalog.pg_policy p where p.polrelid in (v_universities,v_routes)
    union all
    select 'function:' || pg_catalog.pg_get_functiondef(p.oid) || ':' || p.proowner::text || ':' || coalesce(p.proacl::text,'')
    from pg_catalog.pg_proc p where
      (p.pronamespace = 'public'::regnamespace and p.proname in ('search_listings_by_university','write_listing_university_routes'))
      or (p.pronamespace = 'zameel_private'::regnamespace and p.proname = 'route_great_circle_m')
  ) as owned;
  if pg_catalog.obj_description(v_universities,'pg_class') is distinct from 'zameel_university_discovery_v1:' || v_signature then
    raise exception 'room_pricing_discovery_drift: original 007/009 fingerprint does not match; nothing was overwritten';
  end if;
end;
$preflight$;

alter table public.listings
  add column double_room_count integer not null default 0,
  add column double_room_monthly_rent numeric(12,2),
  add column double_room_occupied_beds integer not null default 0,
  add column triple_room_count integer not null default 0,
  add column triple_room_monthly_rent numeric(12,2),
  add column triple_room_occupied_beds integer not null default 0,
  add constraint listings_double_room_option check (
    double_room_count >= 0 and ((double_room_count = 0) = (double_room_monthly_rent is null))
    and (double_room_monthly_rent is null or (double_room_monthly_rent >= 0 and double_room_monthly_rent < 10000000000))
    and double_room_occupied_beds::bigint between 0 and double_room_count::bigint * 2
  ),
  add constraint listings_triple_room_option check (
    triple_room_count >= 0 and ((triple_room_count = 0) = (triple_room_monthly_rent is null))
    and (triple_room_monthly_rent is null or (triple_room_monthly_rent >= 0 and triple_room_monthly_rent < 10000000000))
    and triple_room_occupied_beds::bigint between 0 and triple_room_count::bigint * 3
  ),
  add constraint listings_room_options_summary check (
    double_room_count::bigint * 2 + triple_room_count::bigint * 3 <= 2147483647
    and ((double_room_count = 0 and triple_room_count = 0) or (
      pricing_unit = 'per_bed'
      and total_bed_capacity::bigint = double_room_count::bigint * 2 + triple_room_count::bigint * 3
      and occupied_beds::bigint = double_room_occupied_beds::bigint + triple_room_occupied_beds::bigint
      and monthly_rent = least(double_room_monthly_rent,triple_room_monthly_rent)
    ))
  );

alter table public.bookings add column room_type text
  constraint bookings_room_type_check check (room_type in ('double','triple'));

create function zameel_private.guard_listing_room_options()
returns trigger language plpgsql security definer set search_path = '' as $function$
declare
  v_capacity bigint := new.double_room_count::bigint * 2 + new.triple_room_count::bigint * 3;
begin
  -- UPDATE already holds the listing lock. The VOLATILE trigger sees bookings
  -- committed by the operation it waited on; every booking write locks this row.
  if tg_op = 'UPDATE' and (
      new.double_room_count is distinct from old.double_room_count
      or new.triple_room_count is distinct from old.triple_room_count
      or new.pricing_unit is distinct from old.pricing_unit) then
    if (new.double_room_count >= 0 and new.double_room_count::bigint * 2 < old.double_room_occupied_beds)
       or (new.triple_room_count >= 0 and new.triple_room_count::bigint * 3 < old.triple_room_occupied_beds)
       or exists (select 1 from public.bookings b where b.listing_id = old.id and b.status in ('pending','accepted') and (
         (b.room_type is null and (new.double_room_count > 0 or new.triple_room_count > 0))
         or (b.room_type = 'double' and (new.double_room_count = 0 or new.pricing_unit <> 'per_bed'))
         or (b.room_type = 'triple' and (new.triple_room_count = 0 or new.pricing_unit <> 'per_bed'))
       )) then
      raise exception using errcode = '22023', message = 'room_options_have_active_bookings';
    end if;
  end if;
  if new.double_room_count > 0 or new.triple_room_count > 0 then
    if v_capacity not between 1 and 2147483647 then
      raise exception using errcode = '23514', message = 'room_options_capacity_invalid';
    end if;
    new.total_bed_capacity := v_capacity::integer;
    new.monthly_rent := least(new.double_room_monthly_rent,new.triple_room_monthly_rent);
  end if;
  return new;
end;
$function$;
-- Alphabetically BEFORE listings_guard_unit, including simultaneous conversion.
create trigger listings_guard_room_options before insert or update on public.listings
  for each row execute function zameel_private.guard_listing_room_options();

create function zameel_private.guard_booking_room_type()
returns trigger language plpgsql security invoker set search_path = '' as $function$
begin
  if new.room_type is distinct from old.room_type then
    raise exception using errcode = '23514', message = 'booking_room_type_immutable';
  end if;
  return new;
end;
$function$;
create trigger bookings_guard_room_type before update of room_type on public.bookings
  for each row execute function zameel_private.guard_booking_room_type();

-- No CASCADE: an unexpected dependent object refuses the entire transaction.
-- One routine with defaults keeps old 2/3-argument requests unambiguous in PostgREST.
drop function public.submit_booking(uuid,uuid,text);
create function public.submit_booking(
  p_listing_id uuid, p_request_id uuid, p_message text default null, p_room_type text default null
) returns public.bookings language plpgsql security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings;
  v_booking public.bookings;
  v_message text := nullif(pg_catalog.btrim(p_message),'');
  v_rent numeric(12,2);
begin
  if v_uid is null or zameel_private.current_profile_role() is distinct from 'student' then
    raise exception using errcode = '42501', message = 'student_role_required';
  end if;
  if p_listing_id is null or p_request_id is null or pg_catalog.char_length(v_message) > 2000 then
    raise exception using errcode = '22023', message = 'invalid_booking_request';
  end if;
  select * into v_listing from public.listings l
  where l.id = p_listing_id and (l.status = 'published' or exists (
    select 1 from public.bookings b where b.listing_id = l.id
      and b.student_id = v_uid and b.request_id = p_request_id
  )) for update;
  if not found then
    raise exception using errcode = '42501', message = 'listing_not_accessible';
  end if;
  select * into v_booking from public.bookings
  where listing_id = p_listing_id and student_id = v_uid and request_id = p_request_id for update;
  if found then
    if v_booking.message is distinct from v_message or v_booking.room_type is distinct from p_room_type then
      raise exception using errcode = '22023', message = 'idempotency_key_payload_mismatch';
    end if;
    return v_booking;
  end if;
  if exists (select 1 from public.bookings where student_id = v_uid and request_id = p_request_id) then
    raise exception using errcode = '22023', message = 'idempotency_key_listing_mismatch';
  end if;
  if v_listing.pricing_unit <> 'per_bed' then
    raise exception using errcode = '22023', message = 'pricing_unit_not_supported';
  end if;
  if v_listing.status <> 'published' then
    raise exception using errcode = '22023', message = 'listing_not_published';
  end if;
  v_rent := v_listing.monthly_rent;
  if v_listing.double_room_count > 0 or v_listing.triple_room_count > 0 then
    if p_room_type is null then
      raise exception using errcode = '22023', message = 'room_type_required';
    end if;
    if p_room_type = 'double' and v_listing.double_room_count > 0 then
      if v_listing.double_room_occupied_beds::bigint >= v_listing.double_room_count::bigint * 2 then
        raise exception using errcode = '22023', message = 'room_type_full';
      end if;
      v_rent := v_listing.double_room_monthly_rent;
    elsif p_room_type = 'triple' and v_listing.triple_room_count > 0 then
      if v_listing.triple_room_occupied_beds::bigint >= v_listing.triple_room_count::bigint * 3 then
        raise exception using errcode = '22023', message = 'room_type_full';
      end if;
      v_rent := v_listing.triple_room_monthly_rent;
    else
      raise exception using errcode = '22023', message = 'room_type_unavailable';
    end if;
  else
    if p_room_type is not null then
      raise exception using errcode = '22023', message = 'room_type_unavailable';
    end if;
    if v_listing.occupied_beds >= v_listing.total_bed_capacity then
      raise exception using errcode = '22023', message = 'listing_full';
    end if;
  end if;
  if exists (select 1 from public.bookings where listing_id = p_listing_id
      and student_id = v_uid and status in ('pending','accepted')) then
    raise exception using errcode = '22023', message = 'active_booking_already_exists';
  end if;
  insert into public.bookings (
    listing_id, student_id, request_id, message, room_type, snapshot_monthly_rent,
    snapshot_currency, snapshot_pricing_unit, snapshot_occupied_beds, snapshot_total_beds
  ) values (
    v_listing.id, v_uid, p_request_id, v_message, p_room_type, v_rent,
    v_listing.currency, v_listing.pricing_unit, v_listing.occupied_beds, v_listing.total_bed_capacity
  ) returning * into v_booking;
  return v_booking;
end;
$function$;

-- The unchanged fixed-action SECURITY DEFINER wrappers are the only API entry.
create or replace function zameel_private.transition_booking(p_listing_id uuid, p_booking_id uuid, p_action text)
returns public.bookings language plpgsql security invoker set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_role text := zameel_private.current_profile_role();
  v_listing public.listings;
  v_booking public.bookings;
  v_changed integer;
begin
  if p_action is null or p_action not in ('accept','reject','cancel') then
    raise exception using errcode = '22023', message = 'invalid_booking_action';
  end if;
  if v_uid is null
     or (p_action in ('accept','reject') and v_role is distinct from 'landlord')
     or (p_action = 'cancel' and v_role is distinct from 'student') then
    raise exception using errcode = '42501', message = 'booking_action_not_authorized';
  end if;
  select * into v_listing from public.listings l where l.id = p_listing_id and (
    (p_action in ('accept','reject') and l.landlord_id = v_uid) or
    (p_action = 'cancel' and exists (select 1 from public.bookings b
      where b.id = p_booking_id and b.listing_id = l.id and b.student_id = v_uid))
  ) for update;
  if not found then
    raise exception using errcode = '42501', message = 'booking_not_accessible';
  end if;
  select * into v_booking from public.bookings
  where id = p_booking_id and listing_id = v_listing.id for update;
  if not found or (p_action = 'cancel' and v_booking.student_id <> v_uid) then
    raise exception using errcode = '42501', message = 'booking_not_accessible';
  end if;
  if (p_action = 'accept' and v_booking.status = 'accepted')
     or (p_action = 'reject' and v_booking.status = 'rejected')
     or (p_action = 'cancel' and v_booking.status = 'cancelled') then
    return v_booking;
  end if;
  if (p_action in ('accept','reject') and v_booking.status <> 'pending')
     or (p_action = 'cancel' and v_booking.status not in ('pending','accepted')) then
    raise exception using errcode = '22023', message = 'booking_transition_not_allowed';
  end if;

  if p_action = 'accept' or (p_action = 'cancel' and v_booking.status = 'accepted') then
    if (v_listing.double_room_count > 0 or v_listing.triple_room_count > 0) and (
        v_booking.room_type is null or v_listing.occupied_beds::bigint <>
          v_listing.double_room_occupied_beds::bigint + v_listing.triple_room_occupied_beds::bigint) then
      raise exception using errcode = '23514', message = 'booking_occupancy_invariant_failed';
    end if;
  end if;
  if p_action = 'accept' then
    if v_listing.pricing_unit <> 'per_bed' or v_booking.snapshot_pricing_unit <> 'per_bed' then
      raise exception using errcode = '22023', message = 'pricing_unit_not_supported';
    end if;
    if v_listing.status <> 'published' then
      raise exception using errcode = '22023', message = 'listing_not_published';
    end if;
    if v_booking.room_type = 'double' then
      if v_listing.double_room_count = 0 then
        raise exception using errcode = '22023', message = 'room_type_unavailable';
      end if;
      if v_listing.double_room_occupied_beds::bigint >= v_listing.double_room_count::bigint * 2 then
        raise exception using errcode = '22023', message = 'room_type_full';
      end if;
    elsif v_booking.room_type = 'triple' then
      if v_listing.triple_room_count = 0 then
        raise exception using errcode = '22023', message = 'room_type_unavailable';
      end if;
      if v_listing.triple_room_occupied_beds::bigint >= v_listing.triple_room_count::bigint * 3 then
        raise exception using errcode = '22023', message = 'room_type_full';
      end if;
    elsif v_listing.occupied_beds >= v_listing.total_bed_capacity then
      raise exception using errcode = '22023', message = 'listing_full';
    end if;
    update public.listings set occupied_beds = occupied_beds + 1,
      double_room_occupied_beds = double_room_occupied_beds + case when v_booking.room_type = 'double' then 1 else 0 end,
      triple_room_occupied_beds = triple_room_occupied_beds + case when v_booking.room_type = 'triple' then 1 else 0 end
    where id = v_listing.id;
    insert into public.listing_residents(booking_id,listing_id,user_id)
    values (v_booking.id,v_listing.id,v_booking.student_id);
    update public.bookings set status = 'accepted', responded_at = pg_catalog.clock_timestamp()
    where id = v_booking.id returning * into v_booking;
  elsif p_action = 'reject' then
    update public.bookings set status = 'rejected', responded_at = pg_catalog.clock_timestamp()
    where id = v_booking.id returning * into v_booking;
  else
    if v_booking.status = 'accepted' then
      -- Timestamp the locked action, not the possibly earlier transaction start.
      update public.listing_residents set left_at = pg_catalog.clock_timestamp()
      where booking_id = v_booking.id and listing_id = v_listing.id
        and user_id = v_booking.student_id and left_at is null;
      get diagnostics v_changed = row_count;
      if v_changed <> 1 or v_listing.occupied_beds <= 0
         or (v_booking.room_type = 'double' and v_listing.double_room_occupied_beds <= 0)
         or (v_booking.room_type = 'triple' and v_listing.triple_room_occupied_beds <= 0) then
        raise exception using errcode = '23514', message = 'booking_occupancy_invariant_failed';
      end if;
      update public.listings set occupied_beds = occupied_beds - 1,
        double_room_occupied_beds = double_room_occupied_beds - case when v_booking.room_type = 'double' then 1 else 0 end,
        triple_room_occupied_beds = triple_room_occupied_beds - case when v_booking.room_type = 'triple' then 1 else 0 end
      where id = v_listing.id;
    end if;
    update public.bookings set status = 'cancelled', cancelled_at = pg_catalog.clock_timestamp()
    where id = v_booking.id returning * into v_booking;
  end if;
  return v_booking;
end;
$function$;

create function public.search_listings_by_university_v2(
  p_university_id integer, p_after_distance_m double precision default null,
  p_after_listing_id uuid default null, p_limit integer default 20
) returns table (
  id uuid, landlord_id uuid, title text, description text, address text,
  latitude double precision, longitude double precision, monthly_rent numeric,
  pricing_unit text, currency text, total_bed_capacity integer, occupied_beds integer,
  available_beds integer, status text, created_at timestamptz, updated_at timestamptz,
  distance_m double precision, university_id integer,
  double_room_count integer, double_room_monthly_rent numeric, double_room_occupied_beds integer,
  triple_room_count integer, triple_room_monthly_rent numeric, triple_room_occupied_beds integer
) language sql stable security invoker set search_path = '' as $function$
  select s.*, l.double_room_count, l.double_room_monthly_rent, l.double_room_occupied_beds,
    l.triple_room_count, l.triple_room_monthly_rent, l.triple_room_occupied_beds
  from public.search_listings_by_university(p_university_id,p_after_distance_m,p_after_listing_id,p_limit) s
  join public.listings l on l.id = s.id
  order by s.distance_m,s.id;
$function$;

grant insert (double_room_count,double_room_monthly_rent,triple_room_count,triple_room_monthly_rent),
  update (double_room_count,double_room_monthly_rent,triple_room_count,triple_room_monthly_rent)
  on public.listings to authenticated;
revoke all on function zameel_private.guard_listing_room_options(), zameel_private.guard_booking_room_type(),
  zameel_private.transition_booking(uuid,uuid,text), public.submit_booking(uuid,uuid,text,text),
  public.search_listings_by_university_v2(integer,double precision,uuid,integer)
  from public, anon, authenticated, service_role;
grant execute on function public.submit_booking(uuid,uuid,text,text) to authenticated;
grant execute on function public.search_listings_by_university_v2(integer,double precision,uuid,integer) to anon, authenticated;

select pg_catalog.pg_notify('pgrst','reload schema');
commit;
