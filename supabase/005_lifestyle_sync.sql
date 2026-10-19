-- Milestone 4.5: atomic cloud lifestyle sync, additive upgrade of 001.
-- Development run order: 001, 002, 003, 004, 005, then 006. On an existing
-- installation run only the missing migrations. NEVER rerun fresh-only 001.
-- IMPORTANT changed privilege contract: authenticated clients can still SELECT
-- their own student answers, but can no longer INSERT/UPDATE/DELETE them directly
-- (including via the old column grants). Every client write MUST use the save
-- RPC below so answers and metadata share one revision/CAS boundary. 002 tests
-- the intentionally different original direct-write contract; run it BEFORE 005.
-- No shipped cloud-write client is being kept compatible with that old contract.
--
-- Run this WHOLE file as administrator. One transaction; after an error issue
-- ROLLBACK before further SQL. A completed, unchanged installation is a checked
-- no-op on rerun; unknown/changed objects are refused, never overwritten.
-- Existing profiles, answer IDs/values/intensities/timestamps, and profile edit
-- timestamps are untouched. Only users with existing answers get revision 1;
-- no completion/skip history is inferred. Keep zameel_private outside API schemas.
--
-- RPC contract (authenticated, auth.uid() = p_user_id, DB profile role student):
-- * get_lifestyle_preferences(p_user_id uuid) -> JSON object with EXACTLY:
--   user_id, revision, is_complete, is_skipped, completed_at, skipped_at, answers.
--   answers is sorted by option_type, answer_kind and contains EXACTLY those two
--   string keys, value (string), and intensity (integer or JSON null) per row.
--   Missing state reads revision 0, false flags, null times; reading never writes.
-- * save_lifestyle_preferences(p_user_id uuid, p_expected_revision bigint,
--   p_answers jsonb, p_is_complete boolean, p_is_skipped boolean) -> same JSON.
--   p_answers is a FULL replacement array of <=12 unique option/kind objects,
--   each with all four keys above. All existing CHECK-supported answers remain
--   valid, including simultaneous smoking habit/preference and null intensities.
--   The five displayed canonical rows are required only when completing; smoking
--   is optional. Skip accepts partial/empty answers; neither flag is draft/clear.
--   Completion and skip are mutually exclusive. Timestamps are server-generated
--   on entering a mode, retained while staying in it, and cleared on leaving it.
-- * Every successful save advances revision, even an empty/unchanged snapshot.
--   Clearing retains a tombstone state: an old revision 0 cannot resurrect data.
--   Conflict: SQLSTATE 40001 / lifestyle_conflict. Invalid input: 22023 or 23514.
--   Authorization: 42501. Never drop the expected revision to force a retry.
-- Database owners/internal privileged services remain a trust boundary. No
-- profile policy, Storage policy, privileged client, or account-delete API is added.

begin;
set local search_path = pg_catalog;
select pg_catalog.pg_advisory_xact_lock(20261016, 120026);

do $migration$
declare
  v_answers regclass := pg_catalog.to_regclass('public.lifestyle_preferences');
  v_state regclass := pg_catalog.to_regclass('zameel_private.lifestyle_sync_state');
  v_existing boolean := v_state is not null;
  v_marker text;
  v_signature text;
  v_owner_predicate text := '((user_id=(SELECTauth.uid()ASuid))AND((SELECTzameel_private.current_profile_role()AScurrent_profile_role)=''student''::text))';
begin
  if v_answers is null or pg_catalog.to_regclass('public.profiles') is null
     or pg_catalog.to_regprocedure('auth.uid()') is null
     or pg_catalog.to_regprocedure('zameel_private.current_profile_role()') is null
     or pg_catalog.to_regprocedure('zameel_private.touch_updated_at()') is null then
    raise exception 'lifestyle_requires_001: install the marketplace foundation first';
  end if;
  if (select count(*) from pg_catalog.pg_roles
      where rolname in ('anon', 'authenticated', 'service_role')) <> 3
     or exists (select 1 from pg_catalog.pg_class
       where oid in (v_answers, 'public.profiles'::regclass)
         and (relkind <> 'r' or not relrowsecurity)) then
    raise exception 'lifestyle_incompatible_foundation: expected marketplace roles, tables and RLS';
  end if;
  if (select count(*) from pg_catalog.pg_attribute where attrelid = v_answers
      and attnum > 0 and not attisdropped) <> 8
     or (select count(*) from pg_catalog.pg_attribute where attrelid = v_answers
       and attnum > 0 and not attisdropped and (
         (attname in ('id', 'user_id') and atttypid = 'uuid'::regtype and attnotnull) or
         (attname in ('option_type', 'answer_kind', 'value') and atttypid = 'text'::regtype and attnotnull) or
         (attname = 'intensity' and atttypid = 'integer'::regtype and not attnotnull) or
         (attname in ('created_at', 'updated_at') and atttypid = 'timestamptz'::regtype and attnotnull)
       )) <> 8
     or not exists (select 1 from pg_catalog.pg_constraint where conrelid = v_answers
       and contype = 'u' and pg_catalog.pg_get_constraintdef(oid) = 'UNIQUE (user_id, option_type, answer_kind)')
     or not exists (select 1 from pg_catalog.pg_constraint where conrelid = v_answers
       and contype = 'f' and confrelid = 'public.profiles'::regclass and confdeltype = 'c'
       and pg_catalog.pg_get_constraintdef(oid) = 'FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE')
     or (select count(*) from pg_catalog.pg_constraint where conrelid = v_answers
       and contype = 'c' and convalidated and conname in (
         'lifestyle_preferences_option_type_check', 'lifestyle_preferences_answer_kind_check',
         'lifestyle_preferences_intensity_check', 'lifestyle_preferences_value')) <> 4 then
    raise exception 'lifestyle_incompatible_answers: expected the normalized 001 answer contract';
  end if;
  if (select count(*) from pg_catalog.pg_trigger where tgrelid = v_answers and not tgisinternal) <> 1
     or not exists (select 1 from pg_catalog.pg_trigger where tgrelid = v_answers
       and tgname = 'preferences_touch_updated_at' and tgtype = 19 and tgenabled = 'O'
       and tgfoid = 'zameel_private.touch_updated_at()'::regprocedure) then
    raise exception 'lifestyle_incompatible_triggers: review changed answer triggers';
  end if;

  if v_existing then
    v_marker := pg_catalog.obj_description(v_state, 'pg_class');
    if v_marker is null or v_marker not like 'zameel_lifestyle_sync_v1:%' then
      raise exception 'lifestyle_existing_objects: state is not this completed migration';
    end if;
  elsif exists (select 1 from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace
                and proname in ('get_lifestyle_preferences', 'save_lifestyle_preferences'))
     or pg_catalog.to_regtype('zameel_private.lifestyle_sync_state') is not null then
    raise exception 'lifestyle_existing_objects: review pre-existing sync objects; nothing was overwritten';
  end if;

  -- Refuse unexpected policies/grants rather than silently replacing someone's
  -- authorization model. Only the three known 001 write policies are retired.
  if (select count(*) from pg_catalog.pg_policy where polrelid = v_answers)
       <> (case when v_existing then 1 else 4 end)
     or exists (select 1 from pg_catalog.pg_policy p where p.polrelid = v_answers and (
       p.polpermissive
       and p.polroles = array[(select oid from pg_catalog.pg_roles where rolname = 'authenticated')]
       and (
         (p.polname = 'preferences_self_read' and p.polcmd = 'r' and p.polwithcheck is null
           and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '\s', '', 'g') = v_owner_predicate)
         or (not v_existing and p.polname = 'preferences_self_insert' and p.polcmd = 'a' and p.polqual is null
           and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), '\s', '', 'g') = v_owner_predicate)
         or (not v_existing and p.polname = 'preferences_self_edit' and p.polcmd = 'w'
           and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '\s', '', 'g') = v_owner_predicate
           and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), '\s', '', 'g') = v_owner_predicate)
         or (not v_existing and p.polname = 'preferences_self_delete' and p.polcmd = 'd' and p.polwithcheck is null
           and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '\s', '', 'g') = v_owner_predicate)
       )) is distinct from true) then
    raise exception 'lifestyle_incompatible_policies: expected own-student answer policies';
  end if;
  if not pg_catalog.has_table_privilege('authenticated', v_answers, 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', v_answers, 'DELETE') is distinct from (not v_existing)
     or pg_catalog.has_table_privilege('authenticated', v_answers, 'INSERT,UPDATE,TRUNCATE,REFERENCES,TRIGGER')
     or pg_catalog.has_table_privilege('anon', v_answers, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or pg_catalog.has_table_privilege('service_role', v_answers, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     or exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = v_answers
       and a.attnum > 0 and not a.attisdropped and (
         pg_catalog.has_column_privilege('authenticated', v_answers, a.attnum, 'INSERT')
           is distinct from (not v_existing and a.attname in ('option_type', 'answer_kind', 'value', 'intensity'))
         or pg_catalog.has_column_privilege('authenticated', v_answers, a.attnum, 'UPDATE')
           is distinct from (not v_existing and a.attname in ('value', 'intensity'))
         or pg_catalog.has_column_privilege('authenticated', v_answers, a.attnum, 'REFERENCES')
         or pg_catalog.has_column_privilege('anon', v_answers, a.attnum, 'SELECT,INSERT,UPDATE,REFERENCES')
         or pg_catalog.has_column_privilege('service_role', v_answers, a.attnum, 'SELECT,INSERT,UPDATE,REFERENCES')
       )) then
    raise exception 'lifestyle_incompatible_grants: expected the known answer privilege contract';
  end if;

  if not v_existing then
    -- Drain any old direct writes before backfill, and block them until the new
    -- grants commit. Reads remain available; no existing answer row is rewritten.
    lock table public.lifestyle_preferences in share row exclusive mode;
    create table zameel_private.lifestyle_sync_state (
      user_id uuid primary key references public.profiles(id) on delete cascade,
      revision bigint not null default 0 check (revision >= 0),
      is_complete boolean not null default false,
      is_skipped boolean not null default false,
      completed_at timestamptz,
      skipped_at timestamptz,
      constraint lifestyle_sync_status_times check (
        not (is_complete and is_skipped)
        and is_complete = (completed_at is not null)
        and is_skipped = (skipped_at is not null)
      )
    );
    alter table zameel_private.lifestyle_sync_state enable row level security;
    create policy lifestyle_state_self_read on zameel_private.lifestyle_sync_state
      for select to authenticated using (
        user_id = (select auth.uid()) and (select zameel_private.current_profile_role()) = 'student'
      );
    revoke all on table zameel_private.lifestyle_sync_state from public, anon, authenticated, service_role;
    grant select on zameel_private.lifestyle_sync_state to authenticated;

    insert into zameel_private.lifestyle_sync_state(user_id, revision)
    select distinct user_id, 1 from public.lifestyle_preferences;

    create function public.get_lifestyle_preferences(p_user_id uuid)
    returns jsonb language plpgsql stable security definer set search_path = '' as $function$
    declare
      v_uid uuid := auth.uid();
      v_result jsonb;
    begin
      if v_uid is null or p_user_id is distinct from v_uid
         or zameel_private.current_profile_role() is distinct from 'student' then
        raise exception using errcode = '42501', message = 'lifestyle_not_authorized';
      end if;
      -- One SQL statement/snapshot for state AND answers. The existing natural
      -- key and CHECKs bound this indexed user_id read to at most twelve answers.
      select pg_catalog.jsonb_build_object(
        'user_id', p_user_id,
        'revision', coalesce(s.revision, 0::bigint),
        'is_complete', coalesce(s.is_complete, false),
        'is_skipped', coalesce(s.is_skipped, false),
        'completed_at', s.completed_at,
        'skipped_at', s.skipped_at,
        'answers', coalesce((
          select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'option_type', a.option_type, 'answer_kind', a.answer_kind,
            'value', a.value, 'intensity', a.intensity
          ) order by a.option_type, a.answer_kind)
          from public.lifestyle_preferences a where a.user_id = p_user_id
        ), '[]'::jsonb)
      ) into v_result
      from (values (p_user_id)) as requested(user_id)
      left join zameel_private.lifestyle_sync_state s on s.user_id = requested.user_id;
      return v_result;
    end;
    $function$;

    create function public.save_lifestyle_preferences(
      p_user_id uuid, p_expected_revision bigint, p_answers jsonb,
      p_is_complete boolean, p_is_skipped boolean
    ) returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
    declare
      v_uid uuid := auth.uid();
      v_answer jsonb;
      v_intensity numeric;
      v_state zameel_private.lifestyle_sync_state;
      v_now timestamptz;
      v_result jsonb;
    begin
      if v_uid is null or p_user_id is distinct from v_uid
         or zameel_private.current_profile_role() is distinct from 'student' then
        raise exception using errcode = '42501', message = 'lifestyle_not_authorized';
      end if;
      if p_expected_revision is null or p_expected_revision < 0
         or p_is_complete is null or p_is_skipped is null
         or (p_is_complete and p_is_skipped)
         or pg_catalog.jsonb_typeof(p_answers) is distinct from 'array' then
        raise exception using errcode = '22023', message = 'lifestyle_invalid_input';
      end if;
      if pg_catalog.jsonb_array_length(p_answers) > 12 then
        raise exception using errcode = '22023', message = 'lifestyle_invalid_input';
      end if;
      for v_answer in select value from pg_catalog.jsonb_array_elements(p_answers) loop
        if pg_catalog.jsonb_typeof(v_answer) is distinct from 'object' then
          raise exception using errcode = '22023', message = 'lifestyle_invalid_input';
        end if;
        if not (v_answer ?& array['option_type', 'answer_kind', 'value', 'intensity'])
           or v_answer - array['option_type', 'answer_kind', 'value', 'intensity'] <> '{}'::jsonb
           or pg_catalog.jsonb_typeof(v_answer -> 'option_type') is distinct from 'string'
           or pg_catalog.jsonb_typeof(v_answer -> 'answer_kind') is distinct from 'string'
           or pg_catalog.jsonb_typeof(v_answer -> 'value') is distinct from 'string'
           or pg_catalog.jsonb_typeof(v_answer -> 'intensity') not in ('number', 'null') then
          raise exception using errcode = '22023', message = 'lifestyle_invalid_input';
        end if;
        if v_answer -> 'intensity' <> 'null'::jsonb then
          v_intensity := (v_answer ->> 'intensity')::numeric;
          -- Validate lossless integer conversion before casting. The table CHECK,
          -- not a second value/intensity allowlist here, remains authoritative.
          if v_intensity <> pg_catalog.trunc(v_intensity)
             or v_intensity not between -2147483648 and 2147483647 then
            raise exception using errcode = '22023', message = 'lifestyle_invalid_input';
          end if;
        end if;
      end loop;
      if exists (select 1 from pg_catalog.jsonb_array_elements(p_answers) a
        group by a.value ->> 'option_type', a.value ->> 'answer_kind' having count(*) > 1) then
        raise exception using errcode = '22023', message = 'lifestyle_duplicate_answer';
      end if;
      if p_is_complete and exists (
        select 1 from (values
          ('sleep_schedule', 'habit'), ('study_atmosphere', 'preference'),
          ('dish_policy', 'preference'), ('guest_preference', 'preference'),
          ('room_sharing', 'preference')
        ) as required(option_type, answer_kind)
        where not exists (select 1 from pg_catalog.jsonb_array_elements(p_answers) a
          where a.value ->> 'option_type' = required.option_type
            and a.value ->> 'answer_kind' = required.answer_kind)
      ) then
        raise exception using errcode = '22023', message = 'lifestyle_incomplete';
      end if;

      -- ON CONFLICT waits for an uncommitted first insert. At READ COMMITTED the
      -- following lock sees its committed revision, so two expected-0 saves can
      -- never both succeed. Existing state uses the same per-user row lock.
      insert into zameel_private.lifestyle_sync_state(user_id) values (p_user_id)
      on conflict (user_id) do nothing;
      select * into v_state from zameel_private.lifestyle_sync_state
      where user_id = p_user_id for update;
      if v_state.revision is distinct from p_expected_revision then
        raise exception using errcode = '40001', message = 'lifestyle_conflict';
      end if;
      if v_state.revision = 9223372036854775807 then
        raise exception using errcode = '22023', message = 'lifestyle_invalid_revision';
      end if;

      delete from public.lifestyle_preferences where user_id = p_user_id;
      insert into public.lifestyle_preferences(user_id, option_type, answer_kind, value, intensity)
      select p_user_id, a.value ->> 'option_type', a.value ->> 'answer_kind',
        a.value ->> 'value', ((a.value ->> 'intensity')::numeric)::integer
      from pg_catalog.jsonb_array_elements(p_answers) a;

      v_now := pg_catalog.clock_timestamp();
      update zameel_private.lifestyle_sync_state set
        revision = v_state.revision + 1,
        is_complete = p_is_complete, is_skipped = p_is_skipped,
        completed_at = case when p_is_complete then coalesce(v_state.completed_at, v_now) end,
        skipped_at = case when p_is_skipped then coalesce(v_state.skipped_at, v_now) end
      where user_id = p_user_id;

      -- This subsequent SQL statement gets a fresh snapshot of our own writes;
      -- the state lock remains held through the response and transaction commit.
      select public.get_lifestyle_preferences(p_user_id) into v_result;
      return v_result;
    exception
      when check_violation then
        raise exception using errcode = '23514', message = 'lifestyle_invalid_answer';
      when serialization_failure then
        raise exception using errcode = '40001', message = 'lifestyle_conflict';
    end;
    $function$;

    drop policy preferences_self_insert on public.lifestyle_preferences;
    drop policy preferences_self_edit on public.lifestyle_preferences;
    drop policy preferences_self_delete on public.lifestyle_preferences;
    -- Table-level REVOKE alone does NOT revoke the column grants made in 001.
    revoke all on table public.lifestyle_preferences from public, anon, authenticated, service_role;
    revoke insert (option_type, answer_kind, value, intensity), update (value, intensity)
      on public.lifestyle_preferences from public, anon, authenticated, service_role;
    grant select on public.lifestyle_preferences to authenticated;
    revoke all on function public.get_lifestyle_preferences(uuid),
      public.save_lifestyle_preferences(uuid, bigint, jsonb, boolean, boolean)
      from public, anon, authenticated, service_role;
    grant execute on function public.get_lifestyle_preferences(uuid),
      public.save_lifestyle_preferences(uuid, bigint, jsonb, boolean, boolean) to authenticated;
    v_state := 'zameel_private.lifestyle_sync_state'::regclass;
  end if;

  -- Definitions/ACLs only, never user data. Include answer constraints and all
  -- policies so a later rerun cannot conceal a reopened direct-write path.
  select pg_catalog.md5(pg_catalog.string_agg(definition, E'\n' order by definition)) into v_signature
  from (
    select 'table:' || c.oid::regclass::text || ':' || c.relkind::text || ':' || c.relowner::text || ':' ||
      c.relrowsecurity::text || ':' || c.relforcerowsecurity::text || ':' || coalesce(c.relacl::text, '') as definition
    from pg_catalog.pg_class c where c.oid in (v_answers, v_state)
    union all
    select 'column:' || a.attrelid::regclass::text || ':' || a.attname || ':' || a.attnum::text || ':' ||
      a.atttypid::text || ':' || a.atttypmod::text || ':' || a.attnotnull::text || ':' ||
      a.attidentity::text || ':' || a.attgenerated::text || ':' || coalesce(a.attacl::text, '') || ':' ||
      coalesce(pg_catalog.pg_get_expr(d.adbin, d.adrelid), '')
    from pg_catalog.pg_attribute a left join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid in (v_answers, v_state) and a.attnum > 0 and not a.attisdropped
    union all
    select 'constraint:' || c.conrelid::regclass::text || ':' || c.conname || ':' ||
      pg_catalog.pg_get_constraintdef(c.oid) || ':' || c.convalidated::text
    from pg_catalog.pg_constraint c where c.conrelid in (v_answers, v_state)
    union all
    select 'index:' || pg_catalog.pg_get_indexdef(i.indexrelid) || ':' || i.indisvalid::text || ':' || i.indisready::text
    from pg_catalog.pg_index i where i.indrelid in (v_answers, v_state)
    union all
    select 'trigger:' || pg_catalog.pg_get_triggerdef(t.oid) || ':' || t.tgenabled::text
    from pg_catalog.pg_trigger t where t.tgrelid in (v_answers, v_state) and not t.tgisinternal
    union all
    select 'policy:' || p.polrelid::regclass::text || ':' || p.polname || ':' || p.polcmd::text || ':' ||
      p.polpermissive::text || ':' || p.polroles::text || ':' ||
      coalesce(pg_catalog.pg_get_expr(p.polqual, p.polrelid), '') || ':' ||
      coalesce(pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid), '')
    from pg_catalog.pg_policy p where p.polrelid in (v_answers, v_state)
    union all
    select 'function:' || pg_catalog.pg_get_functiondef(p.oid) || ':' || p.proowner::text || ':' || coalesce(p.proacl::text, '')
    from pg_catalog.pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('get_lifestyle_preferences', 'save_lifestyle_preferences')
  ) as owned;
  if v_existing then
    if v_marker is distinct from 'zameel_lifestyle_sync_v1:' || v_signature then
      raise exception 'lifestyle_definition_drift: review a new migration instead of overwriting changed sync objects';
    end if;
    raise notice 'Lifestyle sync v1 already installed and unchanged; no data or definitions changed.';
  else
    execute pg_catalog.format('comment on table zameel_private.lifestyle_sync_state is %L',
      'zameel_lifestyle_sync_v1:' || v_signature);
    raise notice 'Lifestyle sync installed; existing answers preserved, completion/skip not inferred.';
  end if;
end;
$migration$;

notify pgrst, 'reload schema';
commit;
