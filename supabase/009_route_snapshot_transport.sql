-- Route snapshot transport, additive upgrade AFTER 007, as administrator.
-- Run the WHOLE file. After an error issue ROLLBACK before more SQL.
-- No coordinates, catalogue/cache rows, grants or ownership are changed.
-- Role defaults preserve float8 round trips through JSON; PT409 makes permanent
-- stale snapshots an HTTP conflict, not an old PostgREST serialization retry.
-- An intact v1 fingerprint is required. Fresh PT409 installs and reruns are safe.
-- PostgREST must load role settings (db-config) and listen on the pgrst channel;
-- notifications refresh config/schema after commit, without cancelling backends.

begin;
set local search_path = pg_catalog;
set local lock_timeout = '2s';
select pg_catalog.pg_advisory_xact_lock(20261016, 120026);

do $migration$
declare
  v_listings regclass := pg_catalog.to_regclass('public.listings');
  v_universities regclass := pg_catalog.to_regclass('public.universities');
  v_routes regclass := pg_catalog.to_regclass('public.listing_university_routes');
  v_writer regprocedure := pg_catalog.to_regprocedure('public.write_listing_university_routes(uuid,uuid,double precision,double precision,text,jsonb)');
  v_marker text;
  v_signature text;
  v_definition text;
  v_owner oid;
  v_acl aclitem[];
  v_old_error constant text := 'errcode = ''40001'', message = ''route_snapshot_stale''';
  v_new_error constant text := 'errcode = ''PT409'', message = ''route_snapshot_stale''';
  v_old_count integer;
  v_new_count integer;
begin
  if v_listings is null or v_universities is null or v_routes is null or v_writer is null then
    raise exception 'route_snapshot_transport_requires_007: install university discovery first';
  end if;
  if (select count(*) from pg_catalog.pg_roles
      where rolname in ('anon', 'authenticated', 'service_role')) <> 3 then
    raise exception 'route_snapshot_transport_missing_roles: expected anon, authenticated and service_role';
  end if;
  v_marker := pg_catalog.obj_description(v_universities, 'pg_class');
  if v_marker is null or v_marker not like 'zameel_university_discovery_v1:%' then
    raise exception 'route_snapshot_transport_requires_007: missing completed discovery v1 fingerprint';
  end if;

  -- Use EXACTLY 007's v1 owned-object set and serialization, before and after.
  -- In particular, pin CHECK validation is allowed; no table data is hashed.
  for v_pass in 1..2 loop
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

    if v_pass = 1 then
      if v_marker is distinct from 'zameel_university_discovery_v1:' || v_signature then
        raise exception 'route_snapshot_transport_definition_drift: review changed discovery objects; nothing was overwritten';
      end if;
      select pg_catalog.pg_get_functiondef(p.oid), p.proowner, p.proacl
        into v_definition, v_owner, v_acl
      from pg_catalog.pg_proc p where p.oid = v_writer and p.prosecdef
        and p.proconfig @> array['search_path=""', 'lock_timeout=2s'];
      if not found then
        raise exception 'route_snapshot_transport_incompatible_writer: expected SECURITY DEFINER, empty search_path and lock_timeout=2s';
      end if;
      v_old_count := (pg_catalog.length(v_definition)
        - pg_catalog.length(pg_catalog.replace(v_definition, v_old_error, ''))) / pg_catalog.length(v_old_error);
      v_new_count := (pg_catalog.length(v_definition)
        - pg_catalog.length(pg_catalog.replace(v_definition, v_new_error, ''))) / pg_catalog.length(v_new_error);
      if v_old_count = 2 and v_new_count = 0 then
        -- CREATE OR REPLACE from the installed definition retains its signature,
        -- security/configuration, owner and ACL; only these two SQLSTATEs differ.
        v_definition := pg_catalog.replace(v_definition, v_old_error, v_new_error);
        execute v_definition;
      elsif v_old_count <> 0 or v_new_count <> 2 then
        raise exception 'route_snapshot_transport_incompatible_writer: expected exactly two legacy or two PT409 stale-snapshot errors';
      end if;

      alter role anon set extra_float_digits = 1;
      alter role authenticated set extra_float_digits = 1;
      alter role service_role set extra_float_digits = 1;
    else
      if not exists (select 1 from pg_catalog.pg_proc p where p.oid = v_writer
          and pg_catalog.pg_get_functiondef(p.oid) = v_definition
          and p.proowner = v_owner and p.proacl is not distinct from v_acl) then
        raise exception 'route_snapshot_transport_writer_changed: writer definition, owner or grants were not preserved';
      end if;
      -- The object set/schema is still v1. Update only its checked definition hash.
      if v_marker is distinct from 'zameel_university_discovery_v1:' || v_signature then
        execute pg_catalog.format('comment on table public.universities is %L',
          'zameel_university_discovery_v1:' || v_signature);
      end if;
    end if;
  end loop;
end;
$migration$;

notify pgrst, 'reload config';
notify pgrst, 'reload schema';
commit;
