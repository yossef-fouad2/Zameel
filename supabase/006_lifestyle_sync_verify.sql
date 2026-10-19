-- Rollback-only SQL Editor verification AFTER 005, as administrator in a QUIET,
-- DISPOSABLE DEVELOPMENT database. Run the WHOLE file; NEVER replace ROLLBACK
-- with COMMIT. On assertion failure issue ROLLBACK before other SQL. Random Auth
-- fixtures and claim GUCs below are administrator-only test impersonation, not a
-- client authorization API. Do not use production or external Auth/database hooks
-- whose side effects are not undone by rollback. No extensions are required.
-- Run original 002 BEFORE 005: its direct-answer-write tests intentionally use
-- the old grant contract. This file tests the new RPC-only write contract.
--
-- This checks existing post-install rows are covered by state and untouched by
-- the tests. To verify the migration itself, in an isolated database capture
-- profiles/answers BEFORE 005, including both smoking kinds and null intensity;
-- apply 005 and compare every old column, then assert only answer owners have
-- revision 1 with false flags/null times. Run 005 twice to check its no-op, and
-- try a rolled-back definition/ACL change followed by 005 to check safe refusal.
-- A post-install verifier alone cannot reconstruct a pre-migration snapshot.
--
-- Real two-connection race check (not simulated by this single transaction):
-- Use a committed disposable student with no answers/state. A: BEGIN, SET LOCAL
-- ROLE authenticated, set its claims as below, save expected 0, keep A open.
-- B: same student/expected 0 with different answers; it must wait. COMMIT A; B
-- must fail 40001 / lifestyle_conflict. ROLLBACK B. Verify exactly A's revision 1
-- snapshot. Repeat with an existing revision and with A rolling back (B then
-- succeeds). A different student's save must not wait on A's state lock. Clean
-- up the disposable account as administrator. These setup/commit steps belong
-- ONLY in a separate isolated race harness, never in this rollback-only file.
-- This does not test hosted PostgREST/JWT validation, the Flutter sync/cache flow,
-- or a concurrent migration. Record those separately from passing SQL assertions.

begin;
set local search_path = pg_catalog;
set local timezone = 'UTC';

create temporary table lifestyle_test_ids (key text primary key, id uuid not null);
create temporary table lifestyle_test_results (name text not null);
create temporary table lifestyle_test_snapshots (key text primary key, value jsonb not null);
grant select, insert, update on pg_temp.lifestyle_test_ids, pg_temp.lifestyle_test_results,
  pg_temp.lifestyle_test_snapshots to anon, authenticated;

create function pg_temp.l_id(p_key text)
returns uuid language sql stable security invoker set search_path = '' as $test$
  select id from pg_temp.lifestyle_test_ids where key = p_key;
$test$;
create function pg_temp.l_actor(p_key text)
returns void language plpgsql security invoker set search_path = '' as $test$
declare
  v_id uuid := pg_temp.l_id(p_key);
  v_role text := case when p_key is null then 'anon' else 'authenticated' end;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_id::text, ''), true);
  perform pg_catalog.set_config('request.jwt.claim.role', v_role, true);
  perform pg_catalog.set_config('request.jwt.claims',
    pg_catalog.jsonb_build_object('sub', v_id, 'role', v_role)::text, true);
end;
$test$;
create function pg_temp.l_assert(p_name text, p_ok boolean)
returns void language plpgsql security invoker set search_path = '' as $test$
begin
  if p_ok is distinct from true then raise exception 'FAIL: %', p_name; end if;
  insert into pg_temp.lifestyle_test_results values (p_name);
end;
$test$;
create function pg_temp.l_error(p_name text, p_sql text, p_state text, p_message text default null)
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
      insert into pg_temp.lifestyle_test_results values (p_name);
      return;
    end if;
    raise exception 'FAIL: %; expected % / %, got % / %', p_name, p_state, p_message, v_state, v_message;
  end;
  raise exception 'FAIL: %; statement succeeded, expected %', p_name, p_state;
end;
$test$;
create function pg_temp.l_snapshot(
  p_name text, p_snapshot jsonb, p_revision bigint, p_answers jsonb,
  p_complete boolean default false, p_skipped boolean default false
) returns void language plpgsql security invoker set search_path = '' as $test$
declare
  v_answers jsonb;
begin
  select coalesce(pg_catalog.jsonb_agg(a.value order by a.value ->> 'option_type', a.value ->> 'answer_kind'), '[]'::jsonb)
  into v_answers from pg_catalog.jsonb_array_elements(p_answers) a;
  perform pg_temp.l_assert(p_name || ': exact canonical keys, values and answer order',
    p_snapshot - array['completed_at', 'skipped_at'] = pg_catalog.jsonb_build_object(
      'user_id', auth.uid(), 'revision', p_revision, 'is_complete', p_complete,
      'is_skipped', p_skipped, 'answers', v_answers)
    and p_snapshot ?& array['completed_at', 'skipped_at']);
  perform pg_temp.l_assert(p_name || ': server status timestamps',
    case when p_complete then
      pg_catalog.jsonb_typeof(p_snapshot -> 'completed_at') = 'string'
      and (p_snapshot ->> 'completed_at')::timestamptz between pg_catalog.transaction_timestamp() and pg_catalog.clock_timestamp()
    else p_snapshot -> 'completed_at' = 'null'::jsonb end
    and case when p_skipped then
      pg_catalog.jsonb_typeof(p_snapshot -> 'skipped_at') = 'string'
      and (p_snapshot ->> 'skipped_at')::timestamptz between pg_catalog.transaction_timestamp() and pg_catalog.clock_timestamp()
    else p_snapshot -> 'skipped_at' = 'null'::jsonb end);
  perform pg_temp.l_assert(p_name || ': response equals subsequent get',
    p_snapshot = public.get_lifestyle_preferences(auth.uid()));
end;
$test$;

select pg_temp.l_assert('answer and private state RLS enabled',
  (select count(*) = 2 and bool_and(relrowsecurity) from pg_catalog.pg_class
   where oid in ('public.lifestyle_preferences'::regclass, 'zameel_private.lifestyle_sync_state'::regclass)));
select pg_temp.l_assert('only own-student SELECT policies remain',
  (select count(*) = 2 and bool_and(polcmd = 'r' and polpermissive
    and polroles = array[(select oid from pg_catalog.pg_roles where rolname = 'authenticated')]
    and polwithcheck is null
    and pg_catalog.regexp_replace(pg_catalog.pg_get_expr(polqual, polrelid), '\s', '', 'g') =
      '((user_id=(SELECTauth.uid()ASuid))AND((SELECTzameel_private.current_profile_role()AScurrent_profile_role)=''student''::text))')
   from pg_catalog.pg_policy where polrelid in
     ('public.lifestyle_preferences'::regclass, 'zameel_private.lifestyle_sync_state'::regclass)));
select pg_temp.l_assert('no table or column write privileges, including old 001 column grants',
  not exists (select 1 from pg_catalog.pg_class c
    cross join (values ('anon'), ('authenticated'), ('service_role')) as roles(name)
    where c.oid in ('public.lifestyle_preferences'::regclass, 'zameel_private.lifestyle_sync_state'::regclass)
      and (pg_catalog.has_table_privilege(roles.name, c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or (roles.name <> 'authenticated' and pg_catalog.has_table_privilege(roles.name, c.oid, 'SELECT'))
        or exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = c.oid
          and a.attnum > 0 and not a.attisdropped and (
            pg_catalog.has_column_privilege(roles.name, c.oid, a.attnum, 'INSERT,UPDATE,REFERENCES')
            or (roles.name <> 'authenticated' and pg_catalog.has_column_privilege(roles.name, c.oid, a.attnum, 'SELECT'))))))
  and pg_catalog.has_table_privilege('authenticated', 'public.lifestyle_preferences', 'SELECT')
  and pg_catalog.has_table_privilege('authenticated', 'zameel_private.lifestyle_sync_state', 'SELECT'));
select pg_temp.l_assert('exact RPC signatures, definer guard, empty search_path and volatility',
  (select count(*) = 2 and bool_and(prosecdef and prorettype = 'jsonb'::regtype
    and proconfig @> array['search_path=""']
    and ((oid = 'public.get_lifestyle_preferences(uuid)'::regprocedure and provolatile = 's'
      and proargnames = array['p_user_id'])
      or (oid = 'public.save_lifestyle_preferences(uuid,bigint,jsonb,boolean,boolean)'::regprocedure and provolatile = 'v'
        and proargnames = array['p_user_id', 'p_expected_revision', 'p_answers', 'p_is_complete', 'p_is_skipped'])))
   from pg_catalog.pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('get_lifestyle_preferences', 'save_lifestyle_preferences')));
select pg_temp.l_assert('RPC execute restricted to authenticated, never PUBLIC/anon/service_role',
  not exists (select 1 from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    where p.oid in ('public.get_lifestyle_preferences(uuid)'::regprocedure,
      'public.save_lifestyle_preferences(uuid,bigint,jsonb,boolean,boolean)'::regprocedure)
      and a.grantee = 0 and a.privilege_type = 'EXECUTE')
  and (select bool_and(pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
    and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE'))
   from pg_catalog.pg_proc p where p.oid in ('public.get_lifestyle_preferences(uuid)'::regprocedure,
     'public.save_lifestyle_preferences(uuid,bigint,jsonb,boolean,boolean)'::regprocedure)));
select pg_temp.l_assert('existing answer owners have positive revision state',
  not exists (select 1 from public.lifestyle_preferences a
    left join zameel_private.lifestyle_sync_state s on s.user_id = a.user_id
    where s.user_id is null or s.revision < 1));

-- Preserve a quiet development database's pre-existing rows, including IDs and
-- timestamps. Only random fixtures below may differ before the final rollback.
create temporary table lifestyle_existing_rows as
  select 'profile'::text as kind, p.id, to_jsonb(p) as value from public.profiles p
  union all select 'answer', a.id, to_jsonb(a) from public.lifestyle_preferences a
  union all select 'state', s.user_id, to_jsonb(s) from zameel_private.lifestyle_sync_state s;

insert into pg_temp.lifestyle_test_ids select key, gen_random_uuid()
from unnest(array['owner', 'other', 'landlord', 'missing', 'delete_me']) key;
insert into auth.users(id, email, raw_user_meta_data)
select id, 'lifestyle-test+' || id::text || '@example.invalid', jsonb_build_object(
  'role', case when key = 'landlord' then 'landlord' else 'student' end, 'name', 'Lifestyle test ' || key)
from pg_temp.lifestyle_test_ids;
delete from public.profiles where id = pg_temp.l_id('missing');
-- Mutable metadata is deliberately false in both directions; DB roles prevail.
update auth.users set raw_user_meta_data = '{"role":"student"}' where id = pg_temp.l_id('landlord');
update auth.users set raw_user_meta_data = '{"role":"landlord"}' where id = pg_temp.l_id('owner');
insert into pg_temp.lifestyle_test_snapshots
select 'profile_before', to_jsonb(p) from public.profiles p where id = pg_temp.l_id('owner');

set local role anon;
select pg_temp.l_actor(null);
select pg_temp.l_error('anonymous get denied', $$select public.get_lifestyle_preferences(pg_temp.l_id('owner'))$$, '42501');
select pg_temp.l_error('anonymous save denied',
  $$select public.save_lifestyle_preferences(pg_temp.l_id('owner'),0,'[]',false,false)$$, '42501');
select pg_temp.l_error('anonymous answers denied', $$select * from public.lifestyle_preferences$$, '42501');
select pg_temp.l_error('anonymous metadata denied', $$select * from zameel_private.lifestyle_sync_state$$, '42501');
select pg_temp.l_error('anonymous profiles still denied', $$select * from public.profiles$$, '42501');

set local role authenticated;
select pg_temp.l_actor(null);
select pg_temp.l_error('missing auth uid get denied',
  $$select public.get_lifestyle_preferences(pg_temp.l_id('owner'))$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_error('missing auth uid save denied',
  $$select public.save_lifestyle_preferences(pg_temp.l_id('owner'),0,'[]',false,false)$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_actor('landlord');
select pg_temp.l_error('landlord get denied despite forged student metadata',
  $$select public.get_lifestyle_preferences(pg_temp.l_id('landlord'))$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_error('landlord save denied despite forged student metadata',
  $$select public.save_lifestyle_preferences(pg_temp.l_id('landlord'),0,'[]',false,true)$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_actor('missing');
select pg_temp.l_error('missing DB profile get denied',
  $$select public.get_lifestyle_preferences(pg_temp.l_id('missing'))$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_error('missing DB profile save denied',
  $$select public.save_lifestyle_preferences(pg_temp.l_id('missing'),0,'[]',false,false)$$, '42501', 'lifestyle_not_authorized');

select pg_temp.l_actor('owner');
select pg_temp.l_error('null requested identity get denied', $$select public.get_lifestyle_preferences(null)$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_error('null requested identity save denied',
  $$select public.save_lifestyle_preferences(null,0,'[]',false,false)$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_error('other account get denied',
  $$select public.get_lifestyle_preferences(pg_temp.l_id('other'))$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_error('other account save denied',
  $$select public.save_lifestyle_preferences(pg_temp.l_id('other'),0,'[]',false,false)$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_snapshot('absent state', public.get_lifestyle_preferences(pg_temp.l_id('owner')), 0, '[]');
select pg_temp.l_assert('reading absent state performs no insert',
  not exists (select 1 from zameel_private.lifestyle_sync_state)
  and not exists (select 1 from public.lifestyle_preferences));
select pg_temp.l_error('table CHECK failure rolls back initial state insertion',
  $$select public.save_lifestyle_preferences(pg_temp.l_id('owner'),0,
    '[{"option_type":"smoking","answer_kind":"habit","value":"smokeFree","intensity":null}]',false,false)$$,
  '23514', 'lifestyle_invalid_answer');
select pg_temp.l_assert('failed first save leaves no state or answers',
  not exists (select 1 from zameel_private.lifestyle_sync_state)
  and public.get_lifestyle_preferences(pg_temp.l_id('owner')) -> 'revision' = '0'::jsonb);
select pg_temp.l_snapshot('first empty draft',
  public.save_lifestyle_preferences(pg_temp.l_id('owner'), 0, '[]', false, false), 1, '[]');

insert into pg_temp.lifestyle_test_snapshots values
  ('partial', '[{"option_type":"smoking","answer_kind":"preference","value":"smokeFree","intensity":5},
    {"option_type":"sleep_schedule","answer_kind":"habit","value":"nightOwl","intensity":null},
    {"option_type":"smoking","answer_kind":"habit","value":"occasionally","intensity":1}]'),
  ('complete', '[{"option_type":"study_atmosphere","answer_kind":"preference","value":"ambient","intensity":2},
    {"option_type":"sleep_schedule","answer_kind":"habit","value":"average","intensity":null},
    {"option_type":"room_sharing","answer_kind":"preference","value":"doubleRoom","intensity":3},
    {"option_type":"guest_preference","answer_kind":"preference","value":"occasional","intensity":4},
    {"option_type":"dish_policy","answer_kind":"preference","value":"sameDay","intensity":5}]');
select pg_temp.l_snapshot('partial draft with both smoking kinds',
  public.save_lifestyle_preferences(pg_temp.l_id('owner'), 1, value, false, false), 2, value)
from pg_temp.lifestyle_test_snapshots where key = 'partial';
select pg_temp.l_assert('both smoking rows and distinct nullable intensity persist',
  (select count(*) = 3 from public.lifestyle_preferences)
  and (select intensity = 1 from public.lifestyle_preferences where option_type = 'smoking' and answer_kind = 'habit')
  and (select intensity = 5 from public.lifestyle_preferences where option_type = 'smoking' and answer_kind = 'preference')
  and (select intensity is null from public.lifestyle_preferences where option_type = 'sleep_schedule'));
select pg_temp.l_snapshot('complete without optional smoking',
  public.save_lifestyle_preferences(pg_temp.l_id('owner'), 2, value, true, false), 3, value, true)
from pg_temp.lifestyle_test_snapshots where key = 'complete';
insert into pg_temp.lifestyle_test_snapshots values ('completed', public.get_lifestyle_preferences(pg_temp.l_id('owner')));
select pg_temp.l_snapshot('unchanged complete still advances revision',
  public.save_lifestyle_preferences(pg_temp.l_id('owner'), 3, value, true, false), 4, value, true)
from pg_temp.lifestyle_test_snapshots where key = 'complete';
select pg_temp.l_assert('completion time retained while remaining complete',
  public.get_lifestyle_preferences(pg_temp.l_id('owner')) -> 'completed_at' =
    (select value -> 'completed_at' from pg_temp.lifestyle_test_snapshots where key = 'completed'));
select pg_temp.l_snapshot('partial skip clears completion',
  public.save_lifestyle_preferences(pg_temp.l_id('owner'), 4, value, false, true), 5, value, false, true)
from pg_temp.lifestyle_test_snapshots where key = 'partial';
select pg_temp.l_snapshot('empty skip replaces all answers',
  public.save_lifestyle_preferences(pg_temp.l_id('owner'), 5, '[]', false, true), 6, '[]', false, true);
select pg_temp.l_snapshot('clear retains revision tombstone and removes status times',
  public.save_lifestyle_preferences(pg_temp.l_id('owner'), 6, '[]', false, false), 7, '[]');
select pg_temp.l_assert('clear deletes answers but not state',
  not exists (select 1 from public.lifestyle_preferences)
  and (select count(*) = 1 and bool_and(revision = 7) from zameel_private.lifestyle_sync_state));
select pg_temp.l_error('old revision zero cannot resurrect cleared answers',
  $$select public.save_lifestyle_preferences(pg_temp.l_id('owner'),0,
    (select value from pg_temp.lifestyle_test_snapshots where key='partial'),false,false)$$,
  '40001', 'lifestyle_conflict');
select pg_temp.l_error('future revision is also a conflict',
  $$select public.save_lifestyle_preferences(pg_temp.l_id('owner'),8,'[]',false,false)$$,
  '40001', 'lifestyle_conflict');

-- Exercise EVERY supported value in BOTH allowed kinds for non-smoking options,
-- and every nullable intensity. This also tests the maximum twelve-row snapshot.
do $all_values$
declare
  v_choice integer;
  v_intensity integer;
  v_answers jsonb;
  v_revision bigint := 7;
  v_result jsonb;
begin
  for v_choice in 1..3 loop
    foreach v_intensity in array array[null::integer, 1, 2, 3, 4, 5] loop
      select jsonb_agg(jsonb_build_object('option_type', choices.option_type,
        'answer_kind', kinds.answer_kind, 'value', choices.names[v_choice], 'intensity', v_intensity)
        order by choices.option_type desc, kinds.answer_kind desc)
      into v_answers
      from (values
        ('smoking', 'habit', array['nonSmoker', 'smoker', 'occasionally']),
        ('smoking', 'preference', array['noPreference', 'smokeFree', 'comfortableWithSmoking']),
        ('sleep_schedule', null, array['earlyBird', 'average', 'nightOwl']),
        ('study_atmosphere', null, array['librarySilence', 'ambient', 'social']),
        ('dish_policy', null, array['immediate', 'sameDay', 'weekend']),
        ('guest_preference', null, array['occasional', 'anytime', 'none']),
        ('room_sharing', null, array['privateRoom', 'doubleRoom', 'tripleRoom'])
      ) as choices(option_type, smoking_kind, names)
      cross join (values ('habit'), ('preference')) as kinds(answer_kind)
      where choices.smoking_kind is null or choices.smoking_kind = kinds.answer_kind;
      v_result := public.save_lifestyle_preferences(pg_temp.l_id('owner'), v_revision, v_answers, true, false);
      v_revision := v_revision + 1;
      perform pg_temp.l_snapshot('all values ' || v_choice || ', intensity ' || coalesce(v_intensity::text, 'null'),
        v_result, v_revision, v_answers, true);
      perform pg_temp.l_assert('full twelve-row snapshot persists', (select count(*) = 12 from public.lifestyle_preferences));
    end loop;
  end loop;
end;
$all_values$;
insert into pg_temp.lifestyle_test_snapshots values ('before_invalid', public.get_lifestyle_preferences(pg_temp.l_id('owner')));

-- Each invalid call runs inside l_error's subtransaction. Verify the complete
-- previous snapshot survives, including CHECK errors after DELETE/INSERT begins.
do $validation$
declare
  v_case record;
  v_before jsonb := public.get_lifestyle_preferences(pg_temp.l_id('owner'));
  v_revision bigint := (v_before ->> 'revision')::bigint;
begin
  for v_case in select * from (values
    ('SQL null answers', null::jsonb, '22023'),
    ('JSON null answers', 'null'::jsonb, '22023'),
    ('object instead of array', '{}'::jsonb, '22023'),
    ('scalar array member', '[1]'::jsonb, '22023'),
    ('null array member', '[null]'::jsonb, '22023'),
    ('missing keys', '[{}]'::jsonb, '22023'),
    ('missing intensity key', '[{"option_type":"smoking","answer_kind":"habit","value":"smoker"}]'::jsonb, '22023'),
    ('unknown/server key', '[{"option_type":"smoking","answer_kind":"habit","value":"smoker","intensity":null,"user_id":"forged"}]'::jsonb, '22023'),
    ('null option', '[{"option_type":null,"answer_kind":"habit","value":"smoker","intensity":null}]'::jsonb, '22023'),
    ('numeric kind', '[{"option_type":"smoking","answer_kind":1,"value":"smoker","intensity":null}]'::jsonb, '22023'),
    ('boolean value', '[{"option_type":"smoking","answer_kind":"habit","value":true,"intensity":null}]'::jsonb, '22023'),
    ('string intensity', '[{"option_type":"smoking","answer_kind":"habit","value":"smoker","intensity":"3"}]'::jsonb, '22023'),
    ('boolean intensity', '[{"option_type":"smoking","answer_kind":"habit","value":"smoker","intensity":true}]'::jsonb, '22023'),
    ('fractional intensity', '[{"option_type":"smoking","answer_kind":"habit","value":"smoker","intensity":1.5}]'::jsonb, '22023'),
    ('overflow intensity', '[{"option_type":"smoking","answer_kind":"habit","value":"smoker","intensity":2147483648}]'::jsonb, '22023'),
    ('unknown option', '[{"option_type":"unknown","answer_kind":"habit","value":"smoker","intensity":null}]'::jsonb, '23514'),
    ('unknown kind', '[{"option_type":"smoking","answer_kind":"unknown","value":"smoker","intensity":null}]'::jsonb, '23514'),
    ('wrong smoking kind value', '[{"option_type":"smoking","answer_kind":"preference","value":"smoker","intensity":null}]'::jsonb, '23514'),
    ('unknown value', '[{"option_type":"sleep_schedule","answer_kind":"habit","value":"flexible","intensity":null}]'::jsonb, '23514'),
    ('zero intensity', '[{"option_type":"smoking","answer_kind":"habit","value":"smoker","intensity":0}]'::jsonb, '23514'),
    ('excess intensity', '[{"option_type":"smoking","answer_kind":"habit","value":"smoker","intensity":6}]'::jsonb, '23514'),
    ('negative intensity', '[{"option_type":"smoking","answer_kind":"habit","value":"smoker","intensity":-1}]'::jsonb, '23514')
  ) as cases(name, answers, code) loop
    perform pg_temp.l_error(v_case.name, format(
      'select public.save_lifestyle_preferences(%L::uuid,%s,%L::jsonb,false,false)',
      pg_temp.l_id('owner'), v_revision, v_case.answers), v_case.code);
    perform pg_temp.l_assert(v_case.name || ': entire snapshot rolled back',
      public.get_lifestyle_preferences(pg_temp.l_id('owner')) = v_before);
  end loop;
  perform pg_temp.l_error('duplicate natural key', format(
    'select public.save_lifestyle_preferences(%L::uuid,%s,%L::jsonb,false,false)',
    pg_temp.l_id('owner'), v_revision,
    jsonb_build_array(v_before -> 'answers' -> 0, v_before -> 'answers' -> 0)), '22023', 'lifestyle_duplicate_answer');
  perform pg_temp.l_error('thirteen rows rejected before replacement', format(
    'select public.save_lifestyle_preferences(%L::uuid,%s,%L::jsonb,false,false)',
    pg_temp.l_id('owner'), v_revision,
    (v_before -> 'answers') || jsonb_build_array(v_before -> 'answers' -> 0)), '22023', 'lifestyle_invalid_input');
  for v_case in select value ->> 'option_type' as option_type
    from jsonb_array_elements((select value from pg_temp.lifestyle_test_snapshots where key = 'complete')) loop
    perform pg_temp.l_error('completion requires ' || v_case.option_type, format(
      'select public.save_lifestyle_preferences(%L::uuid,%s,%L::jsonb,true,false)',
      pg_temp.l_id('owner'), v_revision,
      (select jsonb_agg(value) from jsonb_array_elements(
        (select value from pg_temp.lifestyle_test_snapshots where key = 'complete'))
       where value ->> 'option_type' <> v_case.option_type)), '22023', 'lifestyle_incomplete');
  end loop;
  -- Five rows of the wrong kind are not the five displayed canonical answers.
  perform pg_temp.l_error('completion requires canonical kinds', format(
    'select public.save_lifestyle_preferences(%L::uuid,%s,%L::jsonb,true,false)',
    pg_temp.l_id('owner'), v_revision,
    (select jsonb_agg(value || jsonb_build_object('answer_kind', case
       when value ->> 'answer_kind' = 'habit' then 'preference' else 'habit' end))
     from jsonb_array_elements((select value from pg_temp.lifestyle_test_snapshots where key = 'complete')))),
    '22023', 'lifestyle_incomplete');
  perform pg_temp.l_error('empty completion rejected', format(
    'select public.save_lifestyle_preferences(%L::uuid,%s,''[]'',true,false)',
    pg_temp.l_id('owner'), v_revision), '22023', 'lifestyle_incomplete');
  for v_case in select * from (values
    ('missing expected revision', 'null', 'false', 'false'),
    ('negative expected revision', '-1', 'false', 'false'),
    ('missing complete flag', v_revision::text, 'null', 'false'),
    ('missing skipped flag', v_revision::text, 'false', 'null'),
    ('complete and skipped together', v_revision::text, 'true', 'true')
  ) as cases(name, revision, complete, skipped) loop
    perform pg_temp.l_error(v_case.name, format(
      'select public.save_lifestyle_preferences(%L::uuid,%s,''[]'',%s,%s)',
      pg_temp.l_id('owner'), v_case.revision, v_case.complete, v_case.skipped), '22023', 'lifestyle_invalid_input');
  end loop;
  perform pg_temp.l_error('stale existing revision', format(
    'select public.save_lifestyle_preferences(%L::uuid,%s,''[]'',false,false)',
    pg_temp.l_id('owner'), v_revision - 1), '40001', 'lifestyle_conflict');
  perform pg_temp.l_assert('all invalid/CAS calls preserve answers, flags, revision and times',
    public.get_lifestyle_preferences(pg_temp.l_id('owner')) = v_before);
end;
$validation$;

select pg_temp.l_error('direct answer insert denied',
  $$insert into public.lifestyle_preferences(option_type,answer_kind,value,intensity) values('smoking','habit','smoker',3)$$, '42501');
select pg_temp.l_error('direct answer update denied', $$update public.lifestyle_preferences set value='smoker',intensity=1$$, '42501');
select pg_temp.l_error('direct answer delete denied', $$delete from public.lifestyle_preferences$$, '42501');
select pg_temp.l_error('direct state insert denied',
  $$insert into zameel_private.lifestyle_sync_state(user_id) values(pg_temp.l_id('owner'))$$, '42501');
select pg_temp.l_error('direct state revision/flag/time update denied',
  $$update zameel_private.lifestyle_sync_state set revision=0,is_complete=false,completed_at=null$$, '42501');
select pg_temp.l_error('direct tombstone deletion denied', $$delete from zameel_private.lifestyle_sync_state$$, '42501');
select pg_temp.l_assert('all lifestyle operations leave entire profile and edit token unchanged',
  (select to_jsonb(p) = (select value from pg_temp.lifestyle_test_snapshots where key = 'profile_before')
   from public.profiles p where id = pg_temp.l_id('owner')));

select pg_temp.l_actor('other');
select pg_temp.l_assert('another student sees no owner answers or metadata',
  not exists (select 1 from public.lifestyle_preferences where user_id = pg_temp.l_id('owner'))
  and not exists (select 1 from zameel_private.lifestyle_sync_state where user_id = pg_temp.l_id('owner')));
select pg_temp.l_error('other student cannot read saved owner via RPC',
  $$select public.get_lifestyle_preferences(pg_temp.l_id('owner'))$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_error('other student cannot replace saved owner via RPC',
  $$select public.save_lifestyle_preferences(pg_temp.l_id('owner'),25,'[]',false,false)$$, '42501', 'lifestyle_not_authorized');
select pg_temp.l_snapshot('other account has independent revision zero', public.get_lifestyle_preferences(pg_temp.l_id('other')), 0, '[]');
select pg_temp.l_snapshot('other account independently skips',
  public.save_lifestyle_preferences(pg_temp.l_id('other'), 0, '[]', false, true), 1, '[]', false, true);
select pg_temp.l_actor('landlord');
select pg_temp.l_assert('landlord cannot read any lifestyle answers or state',
  not exists (select 1 from public.lifestyle_preferences)
  and not exists (select 1 from zameel_private.lifestyle_sync_state));

-- Profile policy/grant behavior from 003 remains independent of sync.
select pg_temp.l_actor('owner');
select pg_temp.l_assert('profile read remains self-only',
  (select count(*) = 1 and bool_and(id = pg_temp.l_id('owner')) from public.profiles));
select pg_temp.l_assert('profile column whitelist unchanged',
  not pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'INSERT,UPDATE,DELETE')
  and not exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = 'public.profiles'::regclass
    and a.attnum > 0 and not a.attisdropped
    and pg_catalog.has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE')
      is distinct from (a.attname in ('full_name', 'phone', 'preferred_language', 'avatar_path'))));
select pg_temp.l_assert('only the two original self profile policies remain',
  (select count(*) = 2 and bool_and(polname in ('profiles_self_read', 'profiles_self_edit'))
   from pg_catalog.pg_policy where polrelid = 'public.profiles'::regclass));
select pg_temp.l_error('profile role escalation still denied', $$update public.profiles set role='landlord'$$, '42501');
select pg_temp.l_error('profile edit token remains server owned', $$update public.profiles set updated_at=now()$$, '42501');
select pg_temp.l_error('profile legacy URL write still denied', $$update public.profiles set avatar_url=null$$, '42501');
with changed as (
  update public.profiles set full_name = 'Unauthorized' where id = pg_temp.l_id('other') returning id
) select pg_temp.l_assert('cross-account profile edits still affect zero rows', (select count(*) = 0 from changed));
update public.profiles set full_name = 'Lifestyle SQL profile edit', phone = '+12345', preferred_language = 'ar'
where id = pg_temp.l_id('owner');
select pg_temp.l_assert('authorized profile edit still advances its own token',
  (select full_name = 'Lifestyle SQL profile edit' and phone = '+12345' and preferred_language = 'ar'
    and updated_at > (select (value ->> 'updated_at')::timestamptz from pg_temp.lifestyle_test_snapshots where key = 'profile_before')
   from public.profiles where id = pg_temp.l_id('owner')));
select pg_temp.l_assert('profile edit does not change lifestyle revision/snapshot',
  public.get_lifestyle_preferences(pg_temp.l_id('owner')) =
    (select value from pg_temp.lifestyle_test_snapshots where key = 'before_invalid'));

select pg_temp.l_actor('delete_me');
select pg_temp.l_snapshot('account deletion fixture',
  public.save_lifestyle_preferences(pg_temp.l_id('delete_me'), 0, value, false, false), 1, value)
from pg_temp.lifestyle_test_snapshots where key = 'partial';
reset role;
delete from auth.users where id = pg_temp.l_id('delete_me');
select pg_temp.l_assert('account deletion cascades profile, answers and state despite denied client deletes',
  not exists (select 1 from public.profiles where id = pg_temp.l_id('delete_me'))
  and not exists (select 1 from public.lifestyle_preferences where user_id = pg_temp.l_id('delete_me'))
  and not exists (select 1 from zameel_private.lifestyle_sync_state where user_id = pg_temp.l_id('delete_me')));
select pg_temp.l_assert('pre-existing profiles, answers and states preserved exactly',
  not exists (
    with current_rows as (
      select 'profile'::text as kind, p.id, to_jsonb(p) as value from public.profiles p
      where p.id not in (select id from pg_temp.lifestyle_test_ids)
      union all select 'answer', a.id, to_jsonb(a) from public.lifestyle_preferences a
      where a.user_id not in (select id from pg_temp.lifestyle_test_ids)
      union all select 'state', s.user_id, to_jsonb(s) from zameel_private.lifestyle_sync_state s
      where s.user_id not in (select id from pg_temp.lifestyle_test_ids)
    )
    select 1 from pg_temp.lifestyle_existing_rows old full join current_rows now using (kind, id)
    where old.value is distinct from now.value
  ));

select count(*)::text || ' lifestyle sync assertions passed; all fixtures will now roll back.' as result
from pg_temp.lifestyle_test_results;
select count(*) as preexisting_answer_rows_checked from pg_temp.lifestyle_existing_rows where kind = 'answer';
rollback;
