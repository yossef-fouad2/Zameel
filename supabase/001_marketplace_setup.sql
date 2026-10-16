-- Zameel marketplace foundation, v1. Run this WHOLE file in Supabase SQL Editor
-- as the database administrator, before using the profile-backed Flutter client.
-- This is a FRESH SETUP, not a migration of dbSchema (that draft is incomplete).
-- It is one transaction: incompatible existing objects cause a safe refusal.
-- Re-running this installer deliberately refuses without changing data. Do not
-- drop existing objects to make it pass. Review/migrate an existing project first.
-- Only the explicit administrator backfill below is designed for idempotent reruns.
-- After an error, issue ROLLBACK; before other SQL in the same editor session.
--
-- Dashboard/run order:
-- 1. Review this file, run it in a fresh Supabase project, then run 002 verification
--    in a disposable development project. Never use a service-role key in Flutter.
-- 2. Auth: enable the intended email signup/confirmation and recovery flows and
--    review redirect URLs/templates in the Dashboard. New email signups MUST send
--    raw_user_meta_data {"role":"student", "name":"Display name"}; use the
--    role "landlord" instead when that is the user's initial selected role.
--    Missing/invalid roles fail signup closed. OAuth/invite/anonymous users need
--    a separately reviewed initial-role flow; this script does not guess roles.
-- 3. Existing Auth users are NOT automatically assigned a role from mutable
--    metadata. After reviewing their identities and intended roles, run e.g.:
--      select zameel_private.backfill_profile('<reviewed-auth-user-uuid>', 'student');
--    Replace the placeholder yourself; do NOT run it as written. It inserts only
--    missing profiles and never changes an existing profile, including its role.
--    Preview missing profiles as administrator with:
--      select u.id, u.email from auth.users u
--      left join public.profiles p on p.id = u.id where p.id is null;
-- 4. Keep zameel_private OUT of the API's exposed schemas. No keys are configured
--    by this SQL. Do not add broad grants/policies to the application tables.
-- 5. Storage: listing-photos is PRIVATE, JPEG/PNG/WebP only, at most 10 MiB.
--    Upload (upsert: false) to <listing_uuid>/<new_photo_uuid>.jpg|jpeg|png|webp,
--    then insert listing_photos metadata. Never write storage.objects directly;
--    use the Storage API. Delete metadata BEFORE deleting its object. Replacement
--    means a NEW object/path, not an overwrite or move. Do not make the bucket public.
--    Use authorized downloads or short-lived signed URLs, not getPublicUrl().
--    Already-issued signed URLs/cached downloads outlive an unpublish until expiry.
--
-- API contract:
-- * profiles: self SELECT; UPDATE full_name, phone, avatar_url, preferred_language
--   only. No client INSERT/DELETE, role/id edits, or metadata-based authorization.
--   A landlord role is a persisted self-selected role, NOT identity/ownership vetting.
-- * listings: omit server-owned id, landlord_id, status, occupied_beds and timestamps
--   on writes. Specify monthly_rent, currency (uppercase three-letter code) and
--   pricing_unit explicitly. status is the ONLY publication source; available_beds
--   is generated, and occupied_beds changes only through booking RPCs.
--   Publish/archive with set_listing_status(p_listing_id, p_status). No client deletes.
-- * submit_booking(p_listing_id, p_request_id, p_message): a caller-generated UUID request
--   id must be retained across retries. Replays require the SAME listing/message.
--   A new attempt after a terminal status needs a new request_id. A pending request
--   DOES NOT reserve capacity. One pending/accepted request per student per listing.
-- * accept_booking/reject_booking(p_listing_id, p_booking_id): owning landlord only.
--   cancel_booking(p_listing_id, p_booking_id): requesting student only; accepted
--   cancellation ends that resident link and releases exactly one occupied bed.
--   Terminal same-action replays are no-ops; conflicting transitions are rejected.
--   PostgREST RPC JSON keys must use the declared p_* parameter names.
-- * All booking writes lock the listing FIRST, then the exact matching booking.
--   Room/property prices are valid listing data, but submit/accept explicitly fail
--   with pricing_unit_not_supported until a room/property accommodation-unit model
--   exists. We NEVER silently convert a room/property booking into one bed.
-- * A request snapshots the quoted monthly price/currency/unit and capacity. Price
--   edits do not rewrite that snapshot; changing unit with active requests is denied.
--   Archiving does not cancel requests/residents; it blocks new submissions/accepts.
-- * Occupancy covers accepted app bookings only, not imported/external tenants.
--   Different listings are independent; cross-property moves are not modeled.
-- * Raw lifestyle answers are optional and self-only, including after acceptance.
--   habit and preference answers are distinct. No scores/weights are invented.
--   Landlords can see their booking/resident rows, NOT other people's profiles.
--   Contact disclosure/compatibility aggregates need a separate consent-aware API.
-- * Account/listing deletion with booking history is intentionally restricted;
--   implement reviewed retention/anonymization and check-out rules before enabling it.
-- * Database administrators and Supabase's internal privileged services remain a
--   trust boundary; RLS cannot constrain a database owner/BYPASSRLS administrator.

begin;
set local search_path = pg_catalog;
select pg_catalog.pg_advisory_xact_lock(20261016, 120026);

do $preflight$
begin
  if pg_catalog.to_regclass('auth.users') is null
     or pg_catalog.to_regprocedure('auth.uid()') is null
     or pg_catalog.to_regclass('storage.buckets') is null
     or pg_catalog.to_regclass('storage.objects') is null
     or pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()') is null then
    raise exception 'supabase_required: Auth, Storage and PostgreSQL 13+ must already exist';
  end if;
  if (select count(*) from pg_catalog.pg_roles
      where rolname in ('anon', 'authenticated', 'service_role')) <> 3 then
    raise exception 'supabase_required: expected Supabase API roles';
  end if;
  if pg_catalog.to_regnamespace('zameel_private') is not null
     or exists (
       select 1 from pg_catalog.pg_class c
       join pg_catalog.pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = any (array[
         'profiles', 'listings', 'listing_photos', 'amenities', 'listing_amenities',
         'house_rules', 'listing_house_rules', 'lifestyle_preferences', 'bookings',
         'listing_residents'
       ])
     ) or exists (
       select 1 from pg_catalog.pg_type t
       join pg_catalog.pg_namespace n on n.oid = t.typnamespace
       where n.nspname = 'public' and t.typname = any (array[
         'user_role', 'pricing_unit', 'booking_status', 'amenity_category',
         'preference_option_type', 'listing_status'
       ])
     ) or exists (
       select 1 from pg_catalog.pg_proc p
       join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = any (array[
         'handle_new_user', 'reserve_bed', 'submit_booking', 'accept_booking',
         'reject_booking', 'cancel_booking', 'set_listing_status'
       ])
     ) then
    raise exception 'fresh_setup_only: existing marketplace objects or a prior installation found; no changes made. Use a reviewed migration, or the explicit backfill for missing profiles';
  end if;
  if exists (select 1 from pg_catalog.pg_trigger
             where tgrelid = 'auth.users'::pg_catalog.regclass and not tgisinternal) then
    raise exception 'fresh_setup_only: review existing auth.users triggers before installing; none were removed';
  end if;
  if exists (select 1 from storage.buckets where id = 'listing-photos')
     or exists (select 1 from pg_catalog.pg_policy
                where polrelid = 'storage.objects'::pg_catalog.regclass) then
    raise exception 'fresh_setup_only: existing photo bucket or Storage object policies need review; none were overwritten';
  end if;
  if exists (select 1 from pg_catalog.pg_class
             where oid in ('storage.objects'::pg_catalog.regclass,
                           'storage.buckets'::pg_catalog.regclass)
               and not relrowsecurity) then
    raise exception 'storage_rls_required: restore the managed Storage RLS configuration before installing';
  end if;
end;
$preflight$;

create schema zameel_private;
revoke all on schema zameel_private from public, anon, authenticated, service_role;
grant usage on schema zameel_private to anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('student', 'landlord')),
  full_name text check (full_name is null or
    (char_length(btrim(full_name)) > 0 and char_length(full_name) <= 200)),
  phone text check (phone is null or char_length(phone) <= 40),
  avatar_url text check (avatar_url is null or char_length(avatar_url) <= 2048),
  preferred_language text not null default 'en'
    check (preferred_language in ('en', 'ar')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  landlord_id uuid not null default auth.uid()
    references public.profiles(id) on delete restrict,
  title text not null check (char_length(btrim(title)) between 1 and 200),
  description text check (description is null or char_length(description) <= 10000),
  address text check (address is null or char_length(btrim(address)) between 1 and 500),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  monthly_rent numeric(12,2) not null check (monthly_rent >= 0 and monthly_rent < 10000000000),
  pricing_unit text not null check (pricing_unit in ('per_bed', 'per_room', 'per_property')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  total_bed_capacity integer not null check (total_bed_capacity > 0),
  occupied_beds integer not null default 0,
  available_beds integer generated always as (total_bed_capacity - occupied_beds) stored,
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint listings_occupancy_bounds check (occupied_beds between 0 and total_bed_capacity),
  constraint listings_coordinate_pair check ((latitude is null) = (longitude is null)),
  constraint listings_published_location check (
    status <> 'published' or address is not null or latitude is not null
  )
);
create index listings_landlord_idx on public.listings(landlord_id);
create index listings_discovery_idx on public.listings(currency, pricing_unit, monthly_rent)
  where status = 'published';
-- Plain bounded coordinates suffice for the MVP; no PostGIS dependency or fake
-- distance sorting. Add a reviewed spatial index only with a real nearby query.
create index listings_coordinates_idx on public.listings(latitude, longitude)
  where status = 'published';

create table public.listing_photos (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  storage_path text not null unique,
  display_order integer not null default 0 check (display_order >= 0),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  constraint listing_photos_path check (
    split_part(storage_path, '/', 1) = listing_id::text and
    storage_path ~ '^[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](jpg|jpeg|png|webp)$'
  )
);
create index listing_photos_order_idx on public.listing_photos(listing_id, display_order);
create unique index listing_photos_one_primary_idx on public.listing_photos(listing_id)
  where is_primary;

create table public.amenities (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  name text not null check (char_length(btrim(name)) between 1 and 100),
  icon_name text,
  category text not null check (category in ('basic', 'comfort', 'luxury', 'outdoor'))
);
create table public.house_rules (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z][a-z0-9_]*$'),
  label text not null check (char_length(btrim(label)) between 1 and 100),
  description text
);
create table public.listing_amenities (
  listing_id uuid not null references public.listings(id) on delete cascade,
  amenity_id uuid not null references public.amenities(id) on delete restrict,
  primary key (listing_id, amenity_id)
);
create index listing_amenities_amenity_idx on public.listing_amenities(amenity_id);
create table public.listing_house_rules (
  listing_id uuid not null references public.listings(id) on delete cascade,
  rule_id uuid not null references public.house_rules(id) on delete restrict,
  primary key (listing_id, rule_id)
);
create index listing_house_rules_rule_idx on public.listing_house_rules(rule_id);

-- Align with lib/src/data/models/lifestyle_preferences.dart, NOT the draft enums.
-- Values below are the exact Dart enum.name strings. Field -> option_type mapping:
-- smokingPreference -> smoking; sleepSchedule -> sleep_schedule;
-- studyAtmosphere -> study_atmosphere; dishPolicy -> dish_policy;
-- guestPreference -> guest_preference; roomSharingPreference -> room_sharing.
-- A future sync must map a supplied sleepSchedule to habit, and supplied study,
-- dish, guest and room choices to preference. Additional habit/preference rows
-- require explicit answers, never an inferred conversion. Smoking's mixed enum
-- distinguishes habits (nonSmoker/smoker/occasionally) from desired conditions
-- (noPreference/smokeFree/comfortableWithSmoking). Null answers mean NO ROW;
-- noPreference is an explicit smoking answer, not a replacement for missing data.
-- Completion/skip metadata and cloud sync remain outside this SQL foundation.
create table public.lifestyle_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  option_type text not null check (option_type in (
    'smoking', 'sleep_schedule', 'study_atmosphere', 'dish_policy', 'guest_preference', 'room_sharing'
  )),
  answer_kind text not null check (answer_kind in ('habit', 'preference')),
  value text not null,
  intensity integer check (intensity between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, option_type, answer_kind),
  constraint lifestyle_preferences_value check (
    (option_type = 'smoking' and (
      (answer_kind = 'habit' and value in ('nonSmoker', 'smoker', 'occasionally')) or
      (answer_kind = 'preference' and value in ('noPreference', 'smokeFree', 'comfortableWithSmoking'))
    )) or
    (option_type = 'sleep_schedule' and value in ('earlyBird', 'average', 'nightOwl')) or
    (option_type = 'study_atmosphere' and value in ('librarySilence', 'ambient', 'social')) or
    (option_type = 'dish_policy' and value in ('immediate', 'sameDay', 'weekend')) or
    (option_type = 'guest_preference' and value in ('occasional', 'anytime', 'none')) or
    (option_type = 'room_sharing' and value in ('privateRoom', 'doubleRoom', 'tripleRoom'))
  )
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete restrict,
  student_id uuid not null references public.profiles(id) on delete restrict,
  request_id uuid not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  message text check (message is null or char_length(message) <= 2000),
  snapshot_monthly_rent numeric(12,2) not null
    check (snapshot_monthly_rent >= 0 and snapshot_monthly_rent < 10000000000),
  snapshot_currency text not null check (snapshot_currency ~ '^[A-Z]{3}$'),
  snapshot_pricing_unit text not null check (snapshot_pricing_unit = 'per_bed'),
  snapshot_occupied_beds integer not null,
  snapshot_total_beds integer not null check (snapshot_total_beds > 0),
  requested_at timestamptz not null default now(),
  responded_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, request_id),
  unique (id, listing_id, student_id),
  constraint bookings_snapshot_bounds check (
    snapshot_occupied_beds between 0 and snapshot_total_beds
  ),
  constraint bookings_status_times check (
    (status = 'pending' and responded_at is null and cancelled_at is null) or
    (status in ('accepted', 'rejected') and responded_at is not null and cancelled_at is null) or
    (status = 'cancelled' and cancelled_at is not null)
  )
);
create unique index bookings_one_active_per_listing_idx
  on public.bookings(listing_id, student_id) where status in ('pending', 'accepted');
create index bookings_landlord_queue_idx on public.bookings(listing_id, status, requested_at);
create index bookings_student_history_idx on public.bookings(student_id, requested_at desc);

create table public.listing_residents (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique,
  listing_id uuid not null,
  user_id uuid not null,
  joined_at timestamptz not null default clock_timestamp(),
  left_at timestamptz check (left_at is null or left_at >= joined_at),
  -- A composite FK makes it impossible to attach a resident to a different
  -- listing/student than the accepted booking. left_at is the only current flag.
  foreign key (booking_id, listing_id, user_id)
    references public.bookings(id, listing_id, student_id) on delete restrict
);
create unique index listing_residents_one_current_idx
  on public.listing_residents(listing_id, user_id) where left_at is null;
create index listing_residents_member_idx on public.listing_residents(user_id, listing_id);

-- Trigger routines are not callable by API roles. Fixed empty search paths and
-- qualified relations prevent a caller-controlled schema from changing behavior.
create function zameel_private.touch_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $function$
begin
  new.updated_at := pg_catalog.clock_timestamp();
  return new;
end;
$function$;
create trigger profiles_touch_updated_at before update on public.profiles
  for each row execute function zameel_private.touch_updated_at();
create trigger listings_touch_updated_at before update on public.listings
  for each row execute function zameel_private.touch_updated_at();
create trigger preferences_touch_updated_at before update on public.lifestyle_preferences
  for each row execute function zameel_private.touch_updated_at();
create trigger bookings_touch_updated_at before update on public.bookings
  for each row execute function zameel_private.touch_updated_at();

create function zameel_private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $function$
declare
  v_role text := new.raw_user_meta_data ->> 'role';
begin
  if v_role is null or v_role not in ('student', 'landlord') then
    raise exception using errcode = '22023', message = 'signup_role_required',
      hint = 'Supply signup metadata role exactly student or landlord.';
  end if;
  insert into public.profiles(id, role, full_name)
  values (new.id, v_role, nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'name'), ''));
  return new;
end;
$function$;
create trigger zameel_auth_user_created after insert on auth.users
  for each row execute function zameel_private.handle_new_user();

create function zameel_private.backfill_profile(p_user_id uuid, p_role text)
returns public.profiles language plpgsql security invoker set search_path = '' as $function$
declare
  v_profile public.profiles;
begin
  if p_user_id is null or p_role is null or p_role not in ('student', 'landlord') then
    raise exception using errcode = '22023', message = 'explicit_backfill_id_and_role_required';
  end if;
  -- Do not even validate today's mutable name metadata for an existing profile.
  select * into v_profile from public.profiles where id = p_user_id;
  if found then
    return v_profile;
  end if;
  -- DO NOTHING is intentional, not an upsert that overwrites established roles.
  insert into public.profiles(id, role, full_name)
  select u.id, p_role, nullif(pg_catalog.btrim(u.raw_user_meta_data ->> 'name'), '')
  from auth.users u where u.id = p_user_id
  on conflict (id) do nothing;
  select * into v_profile from public.profiles where id = p_user_id;
  if not found then
    raise exception using errcode = '22023', message = 'backfill_auth_user_not_found';
  end if;
  return v_profile;
end;
$function$;

create function zameel_private.current_profile_role()
returns text language sql stable security definer set search_path = '' as $function$
  select p.role from public.profiles p where p.id = (select auth.uid());
$function$;
create function zameel_private.owns_listing(p_listing_id uuid)
returns boolean language sql stable security definer set search_path = '' as $function$
  select exists (
    select 1 from public.listings l join public.profiles p on p.id = l.landlord_id
    where l.id = p_listing_id and p.id = (select auth.uid()) and p.role = 'landlord'
  );
$function$;

create function zameel_private.guard_listing_unit()
returns trigger language plpgsql security definer set search_path = '' as $function$
begin
  -- The updating statement already holds this listing's row lock, the same lock
  -- used by submit/accept/cancel. Requests cannot race a unit/capacity edit.
  if new.pricing_unit is distinct from old.pricing_unit and exists (
    select 1 from public.bookings b where b.listing_id = old.id
      and b.status in ('pending', 'accepted')
  ) then
    raise exception using errcode = '22023', message = 'pricing_unit_has_active_bookings';
  end if;
  return new;
end;
$function$;
create trigger listings_guard_unit before update of pricing_unit on public.listings
  for each row execute function zameel_private.guard_listing_unit();

create function public.set_listing_status(p_listing_id uuid, p_status text)
returns public.listings language plpgsql security definer set search_path = '' as $function$
declare
  v_listing public.listings;
  v_uid uuid := auth.uid();
begin
  if v_uid is null or zameel_private.current_profile_role() is distinct from 'landlord' then
    raise exception using errcode = '42501', message = 'landlord_role_required';
  end if;
  if p_status is null or p_status not in ('draft', 'published', 'archived') then
    raise exception using errcode = '22023', message = 'invalid_listing_status';
  end if;
  select * into v_listing from public.listings
  where id = p_listing_id and landlord_id = v_uid for update;
  if not found then
    raise exception using errcode = '42501', message = 'listing_not_accessible';
  end if;
  if v_listing.status = p_status then
    return v_listing;
  end if;
  update public.listings set status = p_status where id = v_listing.id returning * into v_listing;
  return v_listing;
end;
$function$;

create function public.submit_booking(p_listing_id uuid, p_request_id uuid, p_message text default null)
returns public.bookings language plpgsql security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_listing public.listings;
  v_booking public.bookings;
  v_message text := nullif(pg_catalog.btrim(p_message), '');
begin
  if v_uid is null or zameel_private.current_profile_role() is distinct from 'student' then
    raise exception using errcode = '42501', message = 'student_role_required';
  end if;
  if p_listing_id is null or p_request_id is null or pg_catalog.char_length(v_message) > 2000 then
    raise exception using errcode = '22023', message = 'invalid_booking_request';
  end if;
  -- A replay can still retrieve its own booking after the listing is archived.
  select * into v_listing from public.listings l
  where l.id = p_listing_id and (l.status = 'published' or exists (
    select 1 from public.bookings b where b.listing_id = l.id
      and b.student_id = v_uid and b.request_id = p_request_id
  )) for update;
  if not found then
    raise exception using errcode = '42501', message = 'listing_not_accessible';
  end if;
  select * into v_booking from public.bookings
  where listing_id = p_listing_id and student_id = v_uid and request_id = p_request_id
  for update;
  if found then
    if v_booking.message is distinct from v_message then
      raise exception using errcode = '22023', message = 'idempotency_key_payload_mismatch';
    end if;
    return v_booking;
  end if;
  if exists (select 1 from public.bookings where student_id = v_uid and request_id = p_request_id) then
    raise exception using errcode = '22023', message = 'idempotency_key_listing_mismatch';
  end if;
  if v_listing.pricing_unit <> 'per_bed' then
    raise exception using errcode = '22023', message = 'pricing_unit_not_supported',
      hint = 'MVP booking RPCs support per_bed only; room/property unit allocation is not modeled.';
  end if;
  if v_listing.status <> 'published' then
    raise exception using errcode = '22023', message = 'listing_not_published';
  end if;
  if v_listing.occupied_beds >= v_listing.total_bed_capacity then
    raise exception using errcode = '22023', message = 'listing_full';
  end if;
  if exists (select 1 from public.bookings where listing_id = p_listing_id
             and student_id = v_uid and status in ('pending', 'accepted')) then
    raise exception using errcode = '22023', message = 'active_booking_already_exists';
  end if;
  insert into public.bookings (
    listing_id, student_id, request_id, message, snapshot_monthly_rent,
    snapshot_currency, snapshot_pricing_unit, snapshot_occupied_beds, snapshot_total_beds
  ) values (
    v_listing.id, v_uid, p_request_id, v_message, v_listing.monthly_rent,
    v_listing.currency, v_listing.pricing_unit, v_listing.occupied_beds, v_listing.total_bed_capacity
  ) returning * into v_booking;
  return v_booking;
end;
$function$;

-- Only the three public fixed-action wrappers can invoke this routine. It is
-- SECURITY INVOKER; their trusted owner supplies privileges, never an API caller.
create function zameel_private.transition_booking(p_listing_id uuid, p_booking_id uuid, p_action text)
returns public.bookings language plpgsql security invoker set search_path = '' as $function$
declare
  v_uid uuid := auth.uid();
  v_role text := zameel_private.current_profile_role();
  v_listing public.listings;
  v_booking public.bookings;
  v_changed integer;
begin
  if p_action is null or p_action not in ('accept', 'reject', 'cancel') then
    raise exception using errcode = '22023', message = 'invalid_booking_action';
  end if;
  if v_uid is null
     or (p_action in ('accept', 'reject') and v_role is distinct from 'landlord')
     or (p_action = 'cancel' and v_role is distinct from 'student') then
    raise exception using errcode = '42501', message = 'booking_action_not_authorized';
  end if;
  select * into v_listing from public.listings l where l.id = p_listing_id and (
    (p_action in ('accept', 'reject') and l.landlord_id = v_uid) or
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
  if (p_action in ('accept', 'reject') and v_booking.status <> 'pending')
     or (p_action = 'cancel' and v_booking.status not in ('pending', 'accepted')) then
    raise exception using errcode = '22023', message = 'booking_transition_not_allowed';
  end if;

  if p_action = 'accept' then
    if v_listing.pricing_unit <> 'per_bed' or v_booking.snapshot_pricing_unit <> 'per_bed' then
      raise exception using errcode = '22023', message = 'pricing_unit_not_supported';
    end if;
    if v_listing.status <> 'published' then
      raise exception using errcode = '22023', message = 'listing_not_published';
    end if;
    if v_listing.occupied_beds >= v_listing.total_bed_capacity then
      raise exception using errcode = '22023', message = 'listing_full';
    end if;
    update public.listings set occupied_beds = occupied_beds + 1 where id = v_listing.id;
    insert into public.listing_residents(booking_id, listing_id, user_id)
    values (v_booking.id, v_listing.id, v_booking.student_id);
    update public.bookings set status = 'accepted', responded_at = pg_catalog.clock_timestamp()
    where id = v_booking.id returning * into v_booking;
  elsif p_action = 'reject' then
    update public.bookings set status = 'rejected', responded_at = pg_catalog.clock_timestamp()
    where id = v_booking.id returning * into v_booking;
  else
    if v_booking.status = 'accepted' then
      -- now() is the transaction START: a cancellation transaction may have
      -- started before the acceptance it waited on. Timestamp the locked action.
      update public.listing_residents set left_at = pg_catalog.clock_timestamp()
      where booking_id = v_booking.id and listing_id = v_listing.id
        and user_id = v_booking.student_id and left_at is null;
      get diagnostics v_changed = row_count;
      if v_changed <> 1 or v_listing.occupied_beds <= 0 then
        raise exception using errcode = '23514', message = 'booking_occupancy_invariant_failed';
      end if;
      update public.listings set occupied_beds = occupied_beds - 1 where id = v_listing.id;
    end if;
    update public.bookings set status = 'cancelled', cancelled_at = pg_catalog.clock_timestamp()
    where id = v_booking.id returning * into v_booking;
  end if;
  return v_booking;
end;
$function$;

create function public.accept_booking(p_listing_id uuid, p_booking_id uuid)
returns public.bookings language sql security definer set search_path = '' as $function$
  select zameel_private.transition_booking(p_listing_id, p_booking_id, 'accept');
$function$;
create function public.reject_booking(p_listing_id uuid, p_booking_id uuid)
returns public.bookings language sql security definer set search_path = '' as $function$
  select zameel_private.transition_booking(p_listing_id, p_booking_id, 'reject');
$function$;
create function public.cancel_booking(p_listing_id uuid, p_booking_id uuid)
returns public.bookings language sql security definer set search_path = '' as $function$
  select zameel_private.transition_booking(p_listing_id, p_booking_id, 'cancel');
$function$;

-- RLS applies even when callers bypass the Flutter UI. Owners use database-backed
-- role checks, not a role supplied in a request or editable Auth user metadata.
alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.listing_photos enable row level security;
alter table public.amenities enable row level security;
alter table public.house_rules enable row level security;
alter table public.listing_amenities enable row level security;
alter table public.listing_house_rules enable row level security;
alter table public.lifestyle_preferences enable row level security;
alter table public.bookings enable row level security;
alter table public.listing_residents enable row level security;

create policy profiles_self_read on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profiles_self_edit on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy listings_published_read on public.listings for select to anon, authenticated
  using (status = 'published');
create policy listings_owner_read on public.listings for select to authenticated
  using (landlord_id = (select auth.uid()) and
    (select zameel_private.current_profile_role()) = 'landlord');
create policy listings_owner_insert on public.listings for insert to authenticated
  with check (landlord_id = (select auth.uid()) and status = 'draft' and occupied_beds = 0 and
    (select zameel_private.current_profile_role()) = 'landlord');
create policy listings_owner_edit on public.listings for update to authenticated
  using (landlord_id = (select auth.uid()) and
    (select zameel_private.current_profile_role()) = 'landlord')
  with check (landlord_id = (select auth.uid()) and
    (select zameel_private.current_profile_role()) = 'landlord');

create policy amenities_read on public.amenities for select to anon, authenticated using (true);
create policy house_rules_read on public.house_rules for select to anon, authenticated using (true);
create policy listing_amenities_published_read on public.listing_amenities for select to anon, authenticated
  using (exists (select 1 from public.listings l where l.id = listing_id and l.status = 'published'));
create policy listing_amenities_owner_read on public.listing_amenities for select to authenticated
  using (zameel_private.owns_listing(listing_id));
create policy listing_amenities_owner_insert on public.listing_amenities for insert to authenticated
  with check (zameel_private.owns_listing(listing_id));
create policy listing_amenities_owner_delete on public.listing_amenities for delete to authenticated
  using (zameel_private.owns_listing(listing_id));
create policy listing_rules_published_read on public.listing_house_rules for select to anon, authenticated
  using (exists (select 1 from public.listings l where l.id = listing_id and l.status = 'published'));
create policy listing_rules_owner_read on public.listing_house_rules for select to authenticated
  using (zameel_private.owns_listing(listing_id));
create policy listing_rules_owner_insert on public.listing_house_rules for insert to authenticated
  with check (zameel_private.owns_listing(listing_id));
create policy listing_rules_owner_delete on public.listing_house_rules for delete to authenticated
  using (zameel_private.owns_listing(listing_id));

create policy preferences_self_read on public.lifestyle_preferences for select to authenticated
  using (user_id = (select auth.uid()) and (select zameel_private.current_profile_role()) = 'student');
create policy preferences_self_insert on public.lifestyle_preferences for insert to authenticated
  with check (user_id = (select auth.uid()) and (select zameel_private.current_profile_role()) = 'student');
create policy preferences_self_edit on public.lifestyle_preferences for update to authenticated
  using (user_id = (select auth.uid()) and (select zameel_private.current_profile_role()) = 'student')
  with check (user_id = (select auth.uid()) and (select zameel_private.current_profile_role()) = 'student');
create policy preferences_self_delete on public.lifestyle_preferences for delete to authenticated
  using (user_id = (select auth.uid()) and (select zameel_private.current_profile_role()) = 'student');

create policy bookings_participants_read on public.bookings for select to authenticated
  using ((student_id = (select auth.uid()) and
          (select zameel_private.current_profile_role()) = 'student')
         or zameel_private.owns_listing(listing_id));
create policy residents_participants_read on public.listing_residents for select to authenticated
  using ((user_id = (select auth.uid()) and
          (select zameel_private.current_profile_role()) = 'student')
         or zameel_private.owns_listing(listing_id));

-- Storage helpers disclose only caller ownership or already-published metadata.
-- They never return profiles, arbitrary object metadata, or raw preferences.
create function zameel_private.owns_photo_path(p_name text)
returns boolean language sql stable security definer set search_path = '' as $function$
  select p_name ~ '^[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](jpg|jpeg|png|webp)$'
    and exists (
      select 1 from public.listings l join public.profiles p on p.id = l.landlord_id
      where l.id::text = pg_catalog.split_part(p_name, '/', 1)
        and p.id = (select auth.uid()) and p.role = 'landlord'
    );
$function$;
create function zameel_private.can_attach_photo(p_listing_id uuid, p_name text)
returns boolean language sql stable security definer set search_path = '' as $function$
  select pg_catalog.split_part(p_name, '/', 1) = p_listing_id::text
    and zameel_private.owns_photo_path(p_name)
    and exists (select 1 from storage.objects o where o.bucket_id = 'listing-photos' and o.name = p_name);
$function$;
create function zameel_private.can_read_photo(p_name text)
returns boolean language sql stable security definer set search_path = '' as $function$
  select zameel_private.owns_photo_path(p_name) or exists (
    select 1 from public.listing_photos f join public.listings l on l.id = f.listing_id
    where f.storage_path = p_name and l.status = 'published'
  );
$function$;
create function zameel_private.can_delete_photo(p_name text)
returns boolean language sql stable security definer set search_path = '' as $function$
  select zameel_private.owns_photo_path(p_name) and not exists (
    select 1 from public.listing_photos f where f.storage_path = p_name
  );
$function$;

create policy photos_published_read on public.listing_photos for select to anon, authenticated
  using (exists (select 1 from public.listings l where l.id = listing_id and l.status = 'published'));
create policy photos_owner_read on public.listing_photos for select to authenticated
  using (zameel_private.owns_listing(listing_id));
create policy photos_owner_insert on public.listing_photos for insert to authenticated
  with check (zameel_private.can_attach_photo(listing_id, storage_path));
create policy photos_owner_edit on public.listing_photos for update to authenticated
  using (zameel_private.owns_listing(listing_id))
  with check (zameel_private.can_attach_photo(listing_id, storage_path));
create policy photos_owner_delete on public.listing_photos for delete to authenticated
  using (zameel_private.owns_listing(listing_id));

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp']);

-- Supabase owns the Storage tables/grants: do not replace them or add FKs/triggers
-- to their internals. These restrictive guards ALSO prevent future broad
-- permissive Storage policies from opening this bucket to API callers.
create policy zameel_bucket_client_guard on storage.buckets as restrictive
  for all to anon, authenticated
  using (id <> 'listing-photos') with check (id <> 'listing-photos');
create policy zameel_objects_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'listing-photos' and zameel_private.can_read_photo(name));
create policy zameel_objects_read_guard on storage.objects as restrictive for select to anon, authenticated
  using (bucket_id <> 'listing-photos' or zameel_private.can_read_photo(name));
create policy zameel_objects_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'listing-photos' and zameel_private.owns_photo_path(name));
create policy zameel_objects_insert_guard on storage.objects as restrictive for insert to authenticated
  with check (bucket_id <> 'listing-photos' or zameel_private.owns_photo_path(name));
create policy zameel_objects_anon_no_insert on storage.objects as restrictive for insert to anon
  with check (bucket_id <> 'listing-photos');
create policy zameel_objects_delete on storage.objects for delete to authenticated
  using (bucket_id = 'listing-photos' and zameel_private.can_delete_photo(name));
create policy zameel_objects_delete_guard on storage.objects as restrictive for delete to authenticated
  using (bucket_id <> 'listing-photos' or zameel_private.can_delete_photo(name));
create policy zameel_objects_anon_no_delete on storage.objects as restrictive for delete to anon
  using (bucket_id <> 'listing-photos');
create policy zameel_objects_no_overwrite on storage.objects as restrictive for update to anon, authenticated
  using (bucket_id <> 'listing-photos') with check (bucket_id <> 'listing-photos');

-- Revoke Supabase/default PUBLIC grants explicitly before adding a column-level
-- allowlist. RLS alone does NOT stop a user changing their own role/owner/status.
revoke all on table public.profiles, public.listings, public.listing_photos,
  public.amenities, public.house_rules, public.listing_amenities, public.listing_house_rules,
  public.lifestyle_preferences, public.bookings, public.listing_residents
  from public, anon, authenticated, service_role;
grant select on public.profiles to authenticated;
grant update (full_name, phone, avatar_url, preferred_language) on public.profiles to authenticated;
grant select on public.listings, public.listing_photos, public.amenities, public.house_rules,
  public.listing_amenities, public.listing_house_rules to anon, authenticated;
grant insert (title, description, address, latitude, longitude, monthly_rent, pricing_unit, currency, total_bed_capacity)
  on public.listings to authenticated;
grant update (title, description, address, latitude, longitude, monthly_rent, pricing_unit, currency, total_bed_capacity)
  on public.listings to authenticated;
grant insert (listing_id, storage_path, display_order, is_primary) on public.listing_photos to authenticated;
grant update (storage_path, display_order, is_primary) on public.listing_photos to authenticated;
grant delete on public.listing_photos to authenticated;
grant insert (listing_id, amenity_id) on public.listing_amenities to authenticated;
grant insert (listing_id, rule_id) on public.listing_house_rules to authenticated;
grant delete on public.listing_amenities, public.listing_house_rules to authenticated;
grant select, delete on public.lifestyle_preferences to authenticated;
grant insert (option_type, answer_kind, value, intensity) on public.lifestyle_preferences to authenticated;
grant update (value, intensity) on public.lifestyle_preferences to authenticated;
grant select on public.bookings, public.listing_residents to authenticated;

revoke all on all functions in schema zameel_private from public, anon, authenticated, service_role;
grant execute on function zameel_private.current_profile_role(), zameel_private.owns_listing(uuid),
  zameel_private.owns_photo_path(text), zameel_private.can_attach_photo(uuid, text),
  zameel_private.can_delete_photo(text) to authenticated;
grant execute on function zameel_private.can_read_photo(text) to anon, authenticated;
revoke all on function public.set_listing_status(uuid, text), public.submit_booking(uuid, uuid, text),
  public.accept_booking(uuid, uuid), public.reject_booking(uuid, uuid), public.cancel_booking(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.set_listing_status(uuid, text), public.submit_booking(uuid, uuid, text),
  public.accept_booking(uuid, uuid), public.reject_booking(uuid, uuid), public.cancel_booking(uuid, uuid)
  to authenticated;

-- Dictionary metadata only. No listings, residents, users, occupancy or scores.
-- Stable codes can be localized by the client; these labels are fallback text.
insert into public.amenities(code, name, icon_name, category) values
  ('wifi', 'Wi-Fi', 'wifi', 'basic'),
  ('furnished', 'Furnished', 'chair', 'basic'),
  ('laundry', 'Laundry', 'local_laundry_service', 'comfort'),
  ('air_conditioning', 'Air conditioning', 'ac_unit', 'comfort'),
  ('parking', 'Parking', 'local_parking', 'outdoor');
insert into public.house_rules(code, label, description) values
  ('no_smoking', 'No smoking', 'Smoking is not permitted inside the property.'),
  ('no_pets', 'No pets', 'Pets are not permitted at the property.'),
  ('quiet_hours', 'Quiet hours', 'See the listing description for the stated quiet hours.');

do $backfill_notice$
declare
  v_missing bigint;
begin
  select count(*) into v_missing from auth.users u
  where not exists (select 1 from public.profiles p where p.id = u.id);
  raise notice 'Setup complete. % existing Auth users need explicit administrator profile backfill; none were auto-assigned.', v_missing;
end;
$backfill_notice$;
notify pgrst, 'reload schema';
commit;
