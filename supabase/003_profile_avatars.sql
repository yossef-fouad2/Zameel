-- Profile editing/avatars, additive upgrade of 001_marketplace_setup.sql.
-- Run order in a disposable development project: 001, 002, 003, then 004.
-- On an existing 001 installation run only 003, then 004 in development. Do NOT
-- rerun the fresh-only 001 installer. Run this WHOLE file as SQL Editor admin.
-- One transaction; an error requires ROLLBACK before further SQL in that session.
-- A completed, unchanged 003 installation reruns as a checked no-op. Unknown or
-- changed avatar columns/buckets/policies/routines are refused, not overwritten.
-- Future changes need a new migration, not edits to an already-installed 003.
--
-- Client contract:
-- * profiles.avatar_path is nullable. Existing avatar_url values are retained;
--   this migration neither copies them into Storage nor overwrites profile data.
--   Client UPDATE columns: full_name, phone, preferred_language, avatar_path only.
--   Never send id/role/email/created_at/updated_at/avatar_url as update fields.
-- * Normalize gallery bytes to PNG, longest side <=512px and encoded size <=2 MiB.
--   uploadBinary to PRIVATE profile-avatars with contentType=image/png,
--   upsert:false, and a NEW <session-user-uuid>/<32 lowercase hex nonce>.png path.
--   Bucket MIME/size restrictions do not prove image contents/dimensions: client
--   decoding/resizing is still required. No server image processor is installed.
-- * Save with UPDATE ... WHERE id = auth.uid() AND updated_at = original_timestamp
--   RETURNING ... . Keep the full timestamp precision. Zero returned rows means
--   conflict/session change; refetch, do not silently retry without the predicate.
--   No new RPC is needed. Server updated_at advances on every successful update.
-- * Upload first, then save avatar_path. On conflict/failure the new upload may be
--   orphaned; delete it through the Storage API only after confirming it is unused.
--   Replacing/removing an avatar retires the old path; current references cannot
--   be deleted. Reuse no paths; overwrite/move/update is denied for this bucket.
-- * Storage read/sign/upload/delete is owner-only for students AND landlords.
--   Use authenticated downloads or short-lived signed URLs, never getPublicUrl().
--   Signed URLs are bearer capabilities until expiry; sign-out/replacement does
--   not revoke them or downloaded/cached bytes. Do not persist signed URLs.
-- * No automatic cleanup, profile enumeration or public avatar endpoint is added.
--   Never manipulate production storage.objects rows directly; use Storage APIs.
--   SQL verification uses rolled-back metadata only and cannot test actual bytes.
-- * Database owners/internal privileged services remain trusted. Existing 001
--   listing, booking, role and privacy rules are unchanged. zameel_private must
--   remain outside the API's exposed schemas.

begin;
set local search_path = pg_catalog;
select pg_catalog.pg_advisory_xact_lock(20261016, 120026);

do $migration$
declare
  v_profiles regclass := pg_catalog.to_regclass('public.profiles');
  v_existing boolean;
  v_marker text;
  v_signature text;
  v_allowed_columns text[];
begin
  if v_profiles is null or pg_catalog.to_regnamespace('zameel_private') is null
     or pg_catalog.to_regprocedure('zameel_private.touch_updated_at()') is null
     or pg_catalog.to_regprocedure('zameel_private.current_profile_role()') is null
     or pg_catalog.to_regclass('storage.objects') is null
     or pg_catalog.to_regclass('storage.buckets') is null then
    raise exception 'avatars_require_001: install the marketplace foundation first';
  end if;
  if exists (select 1 from pg_catalog.pg_class
             where oid in (v_profiles, 'storage.objects'::regclass, 'storage.buckets'::regclass)
               and not relrowsecurity) then
    raise exception 'avatars_incompatible_rls: expected enabled profile and Storage RLS';
  end if;
  if (select count(*) from pg_catalog.pg_attribute where attrelid = v_profiles
      and attnum > 0 and not attisdropped and (
        (attname = 'id' and atttypid = 'uuid'::regtype and attnotnull) or
        (attname in ('role', 'preferred_language') and atttypid = 'text'::regtype and attnotnull) or
        (attname in ('full_name', 'phone', 'avatar_url') and atttypid = 'text'::regtype) or
        (attname in ('created_at', 'updated_at') and atttypid = 'timestamptz'::regtype and attnotnull)
      )) <> 8 then
    raise exception 'avatars_incompatible_profiles: expected the 001 profile contract';
  end if;
  -- Refuse changed profile visibility instead of adding another permissive policy.
  if (select count(*) from pg_catalog.pg_policy where polrelid = v_profiles) <> 2
     or exists (
       select 1 from pg_catalog.pg_policy p where p.polrelid = v_profiles and (
         p.polpermissive and p.polroles = array[(select oid from pg_catalog.pg_roles where rolname = 'authenticated')]
         and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '\s', '', 'g')
           = '(id=(SELECTauth.uid()ASuid))'
         and ((p.polname = 'profiles_self_read' and p.polcmd = 'r' and p.polwithcheck is null)
           or (p.polname = 'profiles_self_edit' and p.polcmd = 'w'
             and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), '\s', '', 'g')
               = '(id=(SELECTauth.uid()ASuid))'))
       ) is distinct from true
     ) then
    raise exception 'avatars_incompatible_profile_policies: retain the self-only 001 policies';
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger where tgrelid = v_profiles
      and tgname = 'profiles_touch_updated_at' and tgtype = 19 and tgenabled = 'O'
      and tgfoid = 'zameel_private.touch_updated_at()'::regprocedure) then
    raise exception 'avatars_incompatible_timestamp_trigger: expected the enabled 001 profile update trigger';
  end if;

  select exists (select 1 from pg_catalog.pg_attribute where attrelid = v_profiles
    and attname = 'avatar_path' and attnum > 0 and not attisdropped) into v_existing;
  v_allowed_columns := case when v_existing
    then array['full_name', 'phone', 'preferred_language', 'avatar_path']
    else array['full_name', 'phone', 'preferred_language', 'avatar_url'] end;
  if not pg_catalog.has_table_privilege('authenticated', v_profiles, 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', v_profiles, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or pg_catalog.has_table_privilege('anon', v_profiles, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or pg_catalog.has_table_privilege('service_role', v_profiles, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or exists (
       select 1 from pg_catalog.pg_attribute a where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
         and (pg_catalog.has_column_privilege('authenticated', v_profiles, a.attnum, 'UPDATE')
                is distinct from (a.attname = any(v_allowed_columns))
           or pg_catalog.has_column_privilege('authenticated', v_profiles, a.attnum, 'INSERT,REFERENCES')
           or pg_catalog.has_column_privilege('anon', v_profiles, a.attnum, 'SELECT,INSERT,UPDATE,REFERENCES')
           or pg_catalog.has_column_privilege('service_role', v_profiles, a.attnum, 'SELECT,INSERT,UPDATE,REFERENCES'))
     ) then
    raise exception 'avatars_incompatible_profile_grants: expected the exact client column whitelist';
  end if;

  if v_existing then
    select pg_catalog.col_description(v_profiles, attnum) into v_marker
    from pg_catalog.pg_attribute where attrelid = v_profiles and attname = 'avatar_path';
    if v_marker is null or v_marker not like 'zameel_profile_avatars_v1:%'
       or not exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = v_profiles
         and a.attname = 'avatar_path' and a.atttypid = 'text'::regtype and not a.attnotnull
         and a.atttypmod = -1 and a.attgenerated = '' and a.attidentity = ''
         and not exists (select 1 from pg_catalog.pg_attrdef d where d.adrelid = a.attrelid and d.adnum = a.attnum)) then
      raise exception 'avatars_incompatible_column: existing avatar_path is not this completed migration';
    end if;
  else
    if exists (select 1 from storage.buckets where id = 'profile-avatars' or name = 'profile-avatars')
       or exists (select 1 from pg_catalog.pg_proc where pronamespace = 'zameel_private'::regnamespace
         and proname in ('owns_profile_avatar', 'can_delete_profile_avatar', 'validate_profile_avatar'))
       or exists (select 1 from pg_catalog.pg_trigger where tgrelid = v_profiles and tgname = 'profiles_validate_avatar')
       or exists (select 1 from pg_catalog.pg_constraint where conrelid = v_profiles and conname = 'profiles_avatar_path_owner')
       or exists (select 1 from pg_catalog.pg_policy p
         where p.polrelid in ('storage.objects'::regclass, 'storage.buckets'::regclass)
           and (p.polname like 'zameel_avatar_%' or pg_catalog.strpos(
             coalesce(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '') ||
             coalesce(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), ''), 'profile-avatars') > 0)) then
      raise exception 'avatars_existing_objects: review pre-existing avatar bucket/policies/routines; nothing was overwritten';
    end if;

    alter table public.profiles add column avatar_path text;
    alter table public.profiles add constraint profiles_avatar_path_owner check (
      avatar_path is null or (char_length(avatar_path) = 73
        and avatar_path ~ ('^' || id::text || '/[0-9a-f]{32}[.]png$'))
    );

    create function zameel_private.owns_profile_avatar(p_name text)
    returns boolean language sql stable security invoker set search_path = '' as $function$
      select coalesce(pg_catalog.char_length(p_name) = 73
        and p_name ~ ('^' || (select auth.uid())::text || '/[0-9a-f]{32}[.]png$')
        and (select zameel_private.current_profile_role()) in ('student', 'landlord'), false);
    $function$;

    create function zameel_private.can_delete_profile_avatar(p_name text)
    returns boolean language plpgsql volatile security definer set search_path = '' as $function$
    declare
      v_current text;
    begin
      if not zameel_private.owns_profile_avatar(p_name) then
        return false;
      end if;
      -- Profile first, object second, matching profile UPDATE + validation. This
      -- VOLATILE row-locking check sees a concurrent save after waiting for it.
      select p.avatar_path into v_current from public.profiles p
      where p.id = (select auth.uid()) for update;
      return found and v_current is distinct from p_name;
    end;
    $function$;

    create function zameel_private.validate_profile_avatar()
    returns trigger language plpgsql security definer set search_path = '' as $function$
    begin
      if tg_op = 'UPDATE' then
        -- This trigger sorts AFTER profiles_touch_updated_at. Guarantee a new
        -- optimistic-lock token even within one microsecond or after clock skew.
        new.updated_at := greatest(new.updated_at, old.updated_at + interval '1 microsecond');
        if new.avatar_path is not distinct from old.avatar_path then
          return new;
        end if;
      end if;
      if new.avatar_path is null then
        return new;
      end if;
      if pg_catalog.char_length(new.avatar_path) <> 73
         or new.avatar_path !~ ('^' || new.id::text || '/[0-9a-f]{32}[.]png$') then
        raise exception using errcode = '22023', message = 'avatar_path_invalid';
      end if;
      -- The UPDATE already locks this profile. Hold the exact object through
      -- commit, so a successful reference never races authorized orphan deletion.
      perform 1 from storage.objects o
      where o.bucket_id = 'profile-avatars' and o.name = new.avatar_path for key share;
      if not found then
        raise exception using errcode = '23503', message = 'avatar_object_not_found';
      end if;
      return new;
    end;
    $function$;
    create trigger profiles_validate_avatar before insert or update on public.profiles
      for each row execute function zameel_private.validate_profile_avatar();

    insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
    values ('profile-avatars', 'profile-avatars', false, 2097152, array['image/png']);

    -- Preserve ALL 001 Storage policies. Restrictive guards protect this new
    -- bucket even if another bucket later receives a broad permissive policy.
    -- Permissive policies select the bucket; the restrictive predicate performs
    -- each ownership/reference check once, including the delete's profile lock.
    create policy zameel_avatar_bucket_guard on storage.buckets as restrictive for all to anon, authenticated
      using (id <> 'profile-avatars') with check (id <> 'profile-avatars');
    create policy zameel_avatar_anon_guard on storage.objects as restrictive for all to anon
      using (bucket_id <> 'profile-avatars') with check (bucket_id <> 'profile-avatars');
    create policy zameel_avatar_read on storage.objects for select to authenticated
      using (bucket_id = 'profile-avatars');
    create policy zameel_avatar_read_guard on storage.objects as restrictive for select to authenticated
      using (bucket_id <> 'profile-avatars' or zameel_private.owns_profile_avatar(name));
    create policy zameel_avatar_insert on storage.objects for insert to authenticated
      with check (bucket_id = 'profile-avatars');
    create policy zameel_avatar_insert_guard on storage.objects as restrictive for insert to authenticated
      with check (bucket_id <> 'profile-avatars' or zameel_private.owns_profile_avatar(name));
    create policy zameel_avatar_delete on storage.objects for delete to authenticated
      using (bucket_id = 'profile-avatars');
    create policy zameel_avatar_delete_guard on storage.objects as restrictive for delete to authenticated
      using (bucket_id <> 'profile-avatars' or zameel_private.can_delete_profile_avatar(name));
    create policy zameel_avatar_no_overwrite on storage.objects as restrictive for update to anon, authenticated
      using (bucket_id <> 'profile-avatars') with check (bucket_id <> 'profile-avatars');

    revoke update (avatar_url) on public.profiles from public, anon, authenticated, service_role;
    grant update (avatar_path) on public.profiles to authenticated;
    revoke all on function zameel_private.owns_profile_avatar(text),
      zameel_private.can_delete_profile_avatar(text), zameel_private.validate_profile_avatar()
      from public, anon, authenticated, service_role;
    grant execute on function zameel_private.owns_profile_avatar(text),
      zameel_private.can_delete_profile_avatar(text) to authenticated;
  end if;

  if not exists (select 1 from storage.buckets where id = 'profile-avatars' and name = 'profile-avatars'
      and public = false and file_size_limit = 2097152 and allowed_mime_types = array['image/png']) then
    raise exception 'avatars_incompatible_bucket: expected private PNG-only 2 MiB bucket';
  end if;
  -- Record only this migration's definitions, ACLs and bucket configuration, NOT
  -- user rows/object contents. A rerun checks the fingerprint without replacing
  -- policies, dropping objects, resetting timestamps, or deleting any user files.
  select pg_catalog.md5(pg_catalog.string_agg(definition, E'\n' order by definition)) into v_signature
  from (
    select 'column:' || a.atttypid::text || ':' || a.attnotnull::text || ':' || coalesce(a.attacl::text, '') as definition
    from pg_catalog.pg_attribute a where a.attrelid = v_profiles and a.attname = 'avatar_path'
    union all
    select 'constraint:' || pg_catalog.pg_get_constraintdef(c.oid) || ':' || c.convalidated::text
    from pg_catalog.pg_constraint c where c.conrelid = v_profiles and c.conname = 'profiles_avatar_path_owner'
    union all
    select 'trigger:' || pg_catalog.pg_get_triggerdef(t.oid) || ':' || t.tgenabled::text
    from pg_catalog.pg_trigger t where t.tgrelid = v_profiles and t.tgname = 'profiles_validate_avatar'
    union all
    select 'function:' || pg_catalog.pg_get_functiondef(p.oid) || ':' || p.proowner::text || ':' || coalesce(p.proacl::text, '')
    from pg_catalog.pg_proc p where p.pronamespace = 'zameel_private'::regnamespace
      and p.proname in ('owns_profile_avatar', 'can_delete_profile_avatar', 'validate_profile_avatar')
    union all
    select 'policy:' || p.polrelid::regclass::text || ':' || p.polname || ':' || p.polcmd::text || ':' ||
      p.polpermissive::text || ':' || p.polroles::text || ':' ||
      coalesce(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '') || ':' ||
      coalesce(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), '')
    from pg_catalog.pg_policy p where p.polrelid in ('storage.objects'::regclass, 'storage.buckets'::regclass)
      and p.polname like 'zameel_avatar_%'
  ) as owned;
  if v_existing then
    if v_marker is distinct from 'zameel_profile_avatars_v1:' || v_signature then
      raise exception 'avatars_definition_drift: existing avatar objects changed; review a new migration instead of overwriting';
    end if;
    raise notice 'Profile avatars v1 already installed and unchanged; no data or definitions changed.';
  else
    execute pg_catalog.format('comment on column public.profiles.avatar_path is %L',
      'zameel_profile_avatars_v1:' || v_signature);
    raise notice 'Profile avatars installed; legacy URLs and all existing profile values preserved.';
  end if;
end;
$migration$;

notify pgrst, 'reload schema';
commit;
