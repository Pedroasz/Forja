begin;

set local search_path = public, extensions;
select no_plan();

-- All fixture values are synthetic. This RED suite must fail because the A.2D
-- tables and routines do not exist yet, never because bootstrap or Docker fails.

create or replace function pg_temp.safe_exec_v43a2d(target_sql text)
returns boolean
language plpgsql
set search_path = ''
as $function$
begin
  execute target_sql;
  return true;
exception when others then
  return false;
end;
$function$;

create or replace function pg_temp.safe_count_v43a2d(target_sql text)
returns bigint
language plpgsql
set search_path = ''
as $function$
declare
  result_count bigint;
begin
  execute target_sql into result_count;
  return result_count;
exception when others then
  return -1;
end;
$function$;

create or replace function pg_temp.safe_json_v43a2d(target_sql text)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  result_value jsonb;
begin
  execute target_sql into result_value;
  return coalesce(result_value, 'null'::jsonb);
exception when others then
  return jsonb_build_object('_errorState', sqlstate, '_errorMessage', sqlerrm);
end;
$function$;

create or replace function pg_temp.safe_text_v43a2d(target_sql text)
returns text
language plpgsql
set search_path = ''
as $function$
declare
  result_value text;
begin
  execute target_sql into result_value;
  return result_value;
exception when others then
  return '__error__:' || sqlstate;
end;
$function$;

grant execute on function pg_temp.safe_exec_v43a2d(text) to authenticated, anon;
grant execute on function pg_temp.safe_count_v43a2d(text) to authenticated, anon;
grant execute on function pg_temp.safe_json_v43a2d(text) to authenticated, anon;
grant execute on function pg_temp.safe_text_v43a2d(text) to authenticated, anon;

-- Versioned registry and relational observation model.
select has_table('public', 'consultation_measurement_definitions', 'versioned standard measurement definitions exist');
select has_table('public', 'consultation_measurement_sessions', 'measurement sessions preserve protocol context');
select has_table('public', 'consultation_measurements', 'standard and custom measurements are distinct observations');
select has_table('public', 'consultation_measurement_readings', 'raw repeated readings are relational');
select has_table('public', 'consultation_device_observations', 'manual device observations are separate from measurements and formulas');

select has_function(
  'public', 'save_my_consultation_measurement_v43',
  array['uuid','text','bigint','bigint','uuid','jsonb'],
  'measurement writes require consultation, lease, revision, correlation and bounded payload only'
);
select has_function(
  'public', 'save_my_consultation_device_observation_v43',
  array['uuid','text','bigint','bigint','uuid','jsonb'],
  'device observation writes reuse the A.2C authority contract'
);
select has_function(
  'private', 'reduce_consultation_measurement_v43',
  array['numeric[]','text','smallint'],
  'mean and median reducer is versioned server behavior'
);
select has_function(
  'private', 'normalize_consultation_measurement_unit_v43',
  array['numeric','text','text','smallint'],
  'unit normalization uses a curated deterministic server allowlist'
);
select has_function(
  'private', 'consultation_measurements_are_comparable_v43',
  array['uuid','uuid'],
  'standard comparison is protocol, definition and unit aware'
);
select has_function(
  'private', 'consultation_device_observations_are_comparable_v43',
  array['uuid','uuid'],
  'device comparison rejects unlike device or mode provenance'
);

select ok(
  (
    select count(*) = 5
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'consultation_measurement_definitions',
        'consultation_measurement_sessions',
        'consultation_measurements',
        'consultation_measurement_readings',
        'consultation_device_observations'
      ])
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'all A.2D tables enable and force RLS'
);

select ok(
  (
    select count(*) = 5
       and not bool_or(
         pg_catalog.has_table_privilege('authenticated', relation.oid, 'SELECT')
         or pg_catalog.has_table_privilege('authenticated', relation.oid, 'INSERT')
         or pg_catalog.has_table_privilege('authenticated', relation.oid, 'UPDATE')
         or pg_catalog.has_table_privilege('authenticated', relation.oid, 'DELETE')
         or pg_catalog.has_table_privilege('anon', relation.oid, 'SELECT')
         or pg_catalog.has_table_privilege('anon', relation.oid, 'INSERT')
         or pg_catalog.has_table_privilege('anon', relation.oid, 'UPDATE')
         or pg_catalog.has_table_privilege('anon', relation.oid, 'DELETE')
       )
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'consultation_measurement_definitions',
        'consultation_measurement_sessions',
        'consultation_measurements',
        'consultation_measurement_readings',
        'consultation_device_observations'
      ])
  ),
  'browser roles have no direct measurement table privileges'
);

select ok(
  (
    select count(*) = 2
       and bool_and(
         procedure.prosecdef
         and not pg_catalog.has_function_privilege('anon', procedure.oid, 'EXECUTE')
         and exists (
           select 1
           from unnest(coalesce(procedure.proconfig, array[]::text[])) setting(value)
           where replace(setting.value, '"', '') = 'search_path='
         )
       )
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = any(array[
        'save_my_consultation_measurement_v43',
        'save_my_consultation_device_observation_v43'
      ])
  ),
  'measurement RPCs are locked-down definers and caller identity derives from auth.uid()'
);

select ok(
  pg_temp.safe_count_v43a2d($sql$
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'consultation_measurement_definitions'
      and column_name = any(array[
        'definition_key','definition_version','display_name','canonical_unit',
        'accepted_input_units','anatomical_point','position','instructions',
        'protocol_id','protocol_version','allowed_readings_min',
        'allowed_readings_max','reducer','formula_eligible','warning_rule'
      ])
  $sql$) = 15,
  'standard definition records unit, anatomy, position, instructions and protocol/version provenance'
);

select ok(
  pg_temp.safe_exec_v43a2d($sql$
    insert into public.consultation_measurement_definitions (
      id, definition_key, definition_version, display_name, canonical_unit,
      accepted_input_units, anatomical_point, position, instructions,
      protocol_id, protocol_version, allowed_readings_min, allowed_readings_max,
      reducer, formula_eligible, valid_range, warning_rule, source_reference, is_active
    ) values
      (
        '47100000-0000-0000-0000-000000000001', 'synthetic.waist', 1,
        'Synthetic waist', 'cm', array['cm','mm'], 'synthetic midpoint',
        'standing', 'Synthetic instruction only', 'forja.synthetic.waist', '1.0.0',
        1, 3, 'mean', true, '{"min":"1","max":"300"}',
        '{"maxSpread":"5"}', 'synthetic://waist/v1', true
      ),
      (
        '47100000-0000-0000-0000-000000000002', 'synthetic.skinfold', 1,
        'Synthetic skinfold', 'mm', array['mm'], 'synthetic point',
        'standing', 'Synthetic median instruction', 'forja.synthetic.skinfold', '1.0.0',
        1, 3, 'median', true, '{"min":"0.1","max":"100"}',
        '{"maxSpread":"10"}', 'synthetic://skinfold/v1', true
      )
  $sql$),
  'synthetic versioned definition fixtures satisfy the registry contract'
);

-- A.2C-compatible synthetic actors and authority. No production data is read.
insert into auth.users (id, aud, role, email, created_at, updated_at)
values
  ('47000000-0000-0000-0000-000000000001','authenticated','authenticated','a2d-author@example.test',now(),now()),
  ('47000000-0000-0000-0000-000000000002','authenticated','authenticated','a2d-other-professional@example.test',now(),now()),
  ('47000000-0000-0000-0000-000000000004','authenticated','authenticated','a2d-org-admin@example.test',now(),now()),
  ('47000000-0000-0000-0000-000000000101','authenticated','authenticated','a2d-client@example.test',now(),now()),
  ('47000000-0000-0000-0000-000000000103','authenticated','authenticated','a2d-unrelated@example.test',now(),now());

insert into public.account_plan_catalog (code, account_type, display_name, active_client_limit, is_free, is_active)
values ('trainer_ci_v43a2d','trainer','Trainer CI V43A2D',30,true,true);

insert into public.user_commercial_accounts
  (user_id, primary_account_type, plan_code, subscription_status, personal_use_enabled)
values
  ('47000000-0000-0000-0000-000000000001','trainer','trainer_ci_v43a2d','active',true),
  ('47000000-0000-0000-0000-000000000002','trainer','trainer_ci_v43a2d','active',true);

insert into public.user_account_modes (user_id, mode)
values
  ('47000000-0000-0000-0000-000000000001','trainer'),
  ('47000000-0000-0000-0000-000000000002','trainer');

insert into public.user_identity_details (user_id, birth_date, age_status, age_verified_at)
values ('47000000-0000-0000-0000-000000000101',date '1990-01-01','adult',now());

insert into public.organizations (id, name, slug, organization_type, owner_user_id, status)
values ('47200000-0000-0000-0000-000000000001','A2D Synthetic','a2d-synthetic','academy','47000000-0000-0000-0000-000000000004','active');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('47200000-0000-0000-0000-000000000001','47000000-0000-0000-0000-000000000004','owner','active'),
  ('47200000-0000-0000-0000-000000000001','47000000-0000-0000-0000-000000000001','trainer','active'),
  ('47200000-0000-0000-0000-000000000001','47000000-0000-0000-0000-000000000002','trainer','active');

insert into public.professional_student_relationships
  (id, professional_user_id, student_user_id, professional_type, organization_id, status, scopes)
values
  ('47100000-0000-0000-0000-000000000101','47000000-0000-0000-0000-000000000001','47000000-0000-0000-0000-000000000101','trainer','47200000-0000-0000-0000-000000000001','active','{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}'),
  ('47100000-0000-0000-0000-000000000102','47000000-0000-0000-0000-000000000002','47000000-0000-0000-0000-000000000101','trainer','47200000-0000-0000-0000-000000000001','active','{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}');

insert into public.consultation_subjects
  (id, subject_kind, account_user_id, created_by_user_id)
values
  ('47200000-0000-0000-0000-000000000101','account','47000000-0000-0000-0000-000000000101','47000000-0000-0000-0000-000000000001');

insert into public.professional_consultations
  (id, subject_id, author_user_id, relationship_id, professional_type, organization_id, consultation_kind, status, started_at)
select fixture.id, '47200000-0000-0000-0000-000000000101',
       '47000000-0000-0000-0000-000000000001',
       '47100000-0000-0000-0000-000000000101', 'trainer',
       '47200000-0000-0000-0000-000000000001', 'initial', 'in_progress', now()
from (values
  ('47300000-0000-0000-0000-000000000001'::uuid),
  ('47300000-0000-0000-0000-000000000002'::uuid),
  ('47300000-0000-0000-0000-000000000003'::uuid),
  ('47300000-0000-0000-0000-000000000004'::uuid),
  ('47300000-0000-0000-0000-000000000005'::uuid),
  ('47300000-0000-0000-0000-000000000006'::uuid),
  ('47300000-0000-0000-0000-000000000007'::uuid),
  ('47300000-0000-0000-0000-000000000008'::uuid),
  ('47300000-0000-0000-0000-000000000009'::uuid),
  ('47300000-0000-0000-0000-000000000010'::uuid),
  ('47300000-0000-0000-0000-000000000011'::uuid),
  ('47300000-0000-0000-0000-000000000012'::uuid)
) fixture(id);

create temporary table a2d_context (
  context_key text primary key,
  consultation_id uuid not null,
  lease_payload jsonb not null
) on commit drop;
grant select, insert, update, delete on table a2d_context to authenticated, anon;

set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
insert into a2d_context (context_key, consultation_id, lease_payload)
select fixture.context_key, fixture.consultation_id,
       public.acquire_my_consultation_lease_v43(fixture.consultation_id, 'A2D synthetic ' || fixture.context_key, 'edit')
from (values
  ('one','47300000-0000-0000-0000-000000000001'::uuid),
  ('three','47300000-0000-0000-0000-000000000002'::uuid),
  ('mean','47300000-0000-0000-0000-000000000003'::uuid),
  ('median','47300000-0000-0000-0000-000000000004'::uuid),
  ('invalid','47300000-0000-0000-0000-000000000005'::uuid),
  ('outlier','47300000-0000-0000-0000-000000000006'::uuid),
  ('nonrecorded','47300000-0000-0000-0000-000000000007'::uuid),
  ('custom-a','47300000-0000-0000-0000-000000000008'::uuid),
  ('custom-b','47300000-0000-0000-0000-000000000009'::uuid),
  ('snapshot','47300000-0000-0000-0000-000000000010'::uuid),
  ('device-a','47300000-0000-0000-0000-000000000011'::uuid),
  ('device-b','47300000-0000-0000-0000-000000000012'::uuid)
) fixture(context_key, consultation_id);
reset role;

create temporary table a2d_results (
  result_key text primary key,
  payload jsonb not null
) on commit drop;
grant select, insert, update, delete on table a2d_results to authenticated, anon;

-- Deterministic reducers and unit conversion preserve unrounded evidence.
select is(
  pg_temp.safe_json_v43a2d($sql$
    select private.reduce_consultation_measurement_v43(array[80.1,80.2,80.3]::numeric[],'mean',2::smallint)
  $sql$),
  '{"unroundedValue":"80.2","displayValue":"80.2"}'::jsonb,
  'deterministic mean preserves reproducible decimal output'
);
select is(
  pg_temp.safe_json_v43a2d($sql$
    select private.reduce_consultation_measurement_v43(array[3.1,1.1,2.1]::numeric[],'median',2::smallint)
  $sql$),
  '{"unroundedValue":"2.1","displayValue":"2.1"}'::jsonb,
  'deterministic median is independent of reading order'
);
select is(
  pg_temp.safe_json_v43a2d($sql$
    select private.reduce_consultation_measurement_v43(array[1.005]::numeric[],'mean',2::smallint)
  $sql$),
  '{"unroundedValue":"1.005","displayValue":"1.01"}'::jsonb,
  'deterministic decimal rounding stores unrounded and display values separately'
);
select is(
  pg_temp.safe_json_v43a2d($sql$
    select private.normalize_consultation_measurement_unit_v43(80.5,'mm','cm',3::smallint)
  $sql$),
  '{"canonicalValue":"8.05","canonicalUnit":"cm"}'::jsonb,
  'explicit unit conversion to the canonical unit is deterministic'
);

-- Valid one-reading, three-reading, mean and median writes.
set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
insert into a2d_results (result_key, payload)
select fixture.result_key, pg_temp.safe_json_v43a2d(format(
  'select public.save_my_consultation_measurement_v43(%L::uuid,%L,%s,%s,%L::uuid,%L::jsonb)',
  context.consultation_id,
  context.lease_payload->>'leaseToken',
  context.lease_payload->>'leaseVersion',
  fixture.expected_revision,
  fixture.correlation_id,
  fixture.payload::text
))
from a2d_context context
join (values
  ('one','one',0,'47400000-0000-0000-0000-000000000001'::uuid,
   '{"measurementId":"47500000-0000-0000-0000-000000000001","session":{"observedAt":"2026-08-12T12:00:00.000Z","protocolId":"forja.synthetic.waist","protocolVersion":"1.0.0","conditions":{"surface":"synthetic"}},"measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"80.1","unit":"cm"}]}'::jsonb),
  ('three','three',0,'47400000-0000-0000-0000-000000000002'::uuid,
   '{"measurementId":"47500000-0000-0000-0000-000000000002","session":{"observedAt":"2026-08-12T12:01:00.000Z","protocolId":"forja.synthetic.waist","protocolVersion":"1.0.0","conditions":{}},"measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"80.1","unit":"cm"},{"ordinal":2,"value":"80.2","unit":"cm"},{"ordinal":3,"value":"80.3","unit":"cm"}]}'::jsonb),
  ('mean','mean',0,'47400000-0000-0000-0000-000000000003'::uuid,
   '{"measurementId":"47500000-0000-0000-0000-000000000003","session":{"observedAt":"2026-08-12T12:02:00.000Z","protocolId":"forja.synthetic.waist","protocolVersion":"1.0.0","conditions":{}},"measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":3,"value":"80.3","unit":"cm"},{"ordinal":1,"value":"80.1","unit":"cm"},{"ordinal":2,"value":"80.2","unit":"cm"}]}'::jsonb),
  ('median','median',0,'47400000-0000-0000-0000-000000000004'::uuid,
   '{"measurementId":"47500000-0000-0000-0000-000000000004","session":{"observedAt":"2026-08-12T12:03:00.000Z","protocolId":"forja.synthetic.skinfold","protocolVersion":"1.0.0","conditions":{}},"measurementKind":"standard","definitionKey":"synthetic.skinfold","definitionVersion":1,"observationStatus":"recorded","inputUnit":"mm","reducer":"median","readings":[{"ordinal":1,"value":"3.1","unit":"mm"},{"ordinal":2,"value":"1.1","unit":"mm"},{"ordinal":3,"value":"2.1","unit":"mm"}]}'::jsonb)
) fixture(result_key, context_key, expected_revision, correlation_id, payload)
  on context.context_key = fixture.context_key;
reset role;

select ok(not (payload ? '_errorState'), 'one reading is valid') from a2d_results where result_key = 'one';
select ok(not (payload ? '_errorState'), 'three readings are valid') from a2d_results where result_key = 'three';
select is(payload->>'aggregateValue','80.2','deterministic mean is persisted from raw readings') from a2d_results where result_key = 'mean';
select is(payload->>'aggregateValue','2.1','deterministic median is persisted from raw readings') from a2d_results where result_key = 'median';
select is(
  pg_temp.safe_count_v43a2d($sql$
    select count(*) from public.consultation_measurement_readings
    where measurement_id = '47500000-0000-0000-0000-000000000002'
      and (ordinal, raw_value::text, raw_unit) in ((1,'80.1','cm'),(2,'80.2','cm'),(3,'80.3','cm'))
  $sql$),
  3::bigint,
  'raw readings remain preserved with unique ordinal and original unit'
);

-- Structurally invalid sets are rejected atomically and never invent values.
set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,0,'47400000-0000-0000-0000-000000000010','{"measurementId":"47500000-0000-0000-0000-000000000010","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[]}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '22023', 'consultation_measurement_validation_failed', 'recorded status requires readings')
from a2d_context where context_key = 'invalid';
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,0,'47400000-0000-0000-0000-000000000011','{"measurementId":"47500000-0000-0000-0000-000000000011","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"1","unit":"cm"},{"ordinal":2,"value":"2","unit":"cm"},{"ordinal":3,"value":"3","unit":"cm"},{"ordinal":4,"value":"4","unit":"cm"}]}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '22023', 'consultation_measurement_validation_failed', 'four readings are rejected')
from a2d_context where context_key = 'invalid';
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,0,'47400000-0000-0000-0000-000000000012','{"measurementId":"47500000-0000-0000-0000-000000000012","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"1","unit":"cm"},{"ordinal":1,"value":"2","unit":"cm"}]}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '22023', 'consultation_measurement_validation_failed', 'duplicate reading ordinal is rejected')
from a2d_context where context_key = 'invalid';
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,0,'47400000-0000-0000-0000-000000000013','{"measurementId":"47500000-0000-0000-0000-000000000013","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"client_declined","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"80","unit":"cm"}]}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '22023', 'consultation_measurement_validation_failed', 'non-recorded status rejects readings')
from a2d_context where context_key = 'invalid';
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,0,'47400000-0000-0000-0000-000000000014','{"measurementId":"47500000-0000-0000-0000-000000000014","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"kg","reducer":"mean","readings":[{"ordinal":1,"value":"80","unit":"kg"}]}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '22023', 'consultation_measurement_incompatible_unit', 'incompatible units are rejected')
from a2d_context where context_key = 'invalid';
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,0,'47400000-0000-0000-0000-000000000015','{"measurementId":"47500000-0000-0000-0000-000000000015","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"NaN","unit":"cm"}]}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '22023', 'consultation_measurement_validation_failed', 'structurally malformed values are rejected')
from a2d_context where context_key = 'invalid';
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,0,'47400000-0000-0000-0000-000000000016','{"measurementId":"47500000-0000-0000-0000-000000000016","measurementKind":"custom","customLabel":"Synthetic custom","canonicalUnit":"cm","formulaEligible":true,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"1","unit":"cm"}]}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '22023', 'consultation_measurement_validation_failed', 'custom measurement cannot request formula eligibility')
from a2d_context where context_key = 'invalid';
reset role;

-- Non-recorded statuses may finalize but cannot carry or enable numeric evidence.
set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
insert into a2d_results (result_key, payload)
select 'absence-' || fixture.ordinal, pg_temp.safe_json_v43a2d(format(
  'select public.save_my_consultation_measurement_v43(%L::uuid,%L,%s,%s,%L::uuid,%L::jsonb)',
  context.consultation_id, context.lease_payload->>'leaseToken',
  context.lease_payload->>'leaseVersion', fixture.ordinal - 1,
  fixture.correlation_id, fixture.payload::text
))
from a2d_context context
cross join (values
  (1,'47400000-0000-0000-0000-000000000021'::uuid,'{"measurementId":"47500000-0000-0000-0000-000000000021","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"not_attempted","readings":[]}'::jsonb),
  (2,'47400000-0000-0000-0000-000000000022'::uuid,'{"measurementId":"47500000-0000-0000-0000-000000000022","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"client_declined","readings":[]}'::jsonb),
  (3,'47400000-0000-0000-0000-000000000023'::uuid,'{"measurementId":"47500000-0000-0000-0000-000000000023","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"could_not_obtain","readings":[]}'::jsonb),
  (4,'47400000-0000-0000-0000-000000000024'::uuid,'{"measurementId":"47500000-0000-0000-0000-000000000024","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"instrument_limit","readings":[]}'::jsonb),
  (5,'47400000-0000-0000-0000-000000000025'::uuid,'{"measurementId":"47500000-0000-0000-0000-000000000025","measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"invalid","readings":[]}'::jsonb)
) fixture(ordinal, correlation_id, payload)
where context.context_key = 'nonrecorded';
select lives_ok(format(
  $$select public.finalize_my_consultation_v43('%s','%s',%s,5)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), 'non-recorded observation statuses may exist in a finalized assessment')
from a2d_context where context_key = 'nonrecorded';
reset role;

select is(
  pg_temp.safe_count_v43a2d($sql$
    select count(*) from public.consultation_measurements
    where consultation_id = '47300000-0000-0000-0000-000000000007'
      and observation_status in ('not_attempted','client_declined','could_not_obtain','instrument_limit','invalid')
      and aggregate_value is null
      and calculation_eligible = false
  $sql$),
  5::bigint,
  'non-recorded statuses do not invent numeric values and dependent calculations remain ineligible'
);

-- Warning acceptance is explicit; raw values are never silently autocorrected.
set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
insert into a2d_results (result_key, payload)
select 'outlier', pg_temp.safe_json_v43a2d(format(
  'select public.save_my_consultation_measurement_v43(%L::uuid,%L,%s,0,%L::uuid,%L::jsonb)',
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion',
  '47400000-0000-0000-0000-000000000030',
  '{"measurementId":"47500000-0000-0000-0000-000000000030","session":{"observedAt":"2026-08-12T12:30:00.000Z","protocolId":"forja.synthetic.waist","protocolVersion":"1.0.0","conditions":{}},"measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"80","unit":"cm"},{"ordinal":2,"value":"81","unit":"cm"},{"ordinal":3,"value":"100","unit":"cm"}]}'
)) from a2d_context where context_key = 'outlier';
select throws_ok(format(
  $$select public.finalize_my_consultation_v43('%s','%s',%s,1)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '55000', 'consultation_measurement_justification_required', 'outlier finalization requires professional justification')
from a2d_context where context_key = 'outlier';
insert into a2d_results (result_key, payload)
select 'outlier-accepted', pg_temp.safe_json_v43a2d(format(
  'select public.save_my_consultation_measurement_v43(%L::uuid,%L,%s,1,%L::uuid,%L::jsonb)',
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion',
  '47400000-0000-0000-0000-000000000031',
  '{"measurementId":"47500000-0000-0000-0000-000000000030","session":{"observedAt":"2026-08-12T12:30:00.000Z","protocolId":"forja.synthetic.waist","protocolVersion":"1.0.0","conditions":{}},"measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"80","unit":"cm"},{"ordinal":2,"value":"81","unit":"cm"},{"ordinal":3,"value":"100","unit":"cm"}],"acceptWarning":true,"justification":"Synthetic protocol review accepted the retained outlier."}'
)) from a2d_context where context_key = 'outlier';
select lives_ok(format(
  $$select public.finalize_my_consultation_v43('%s','%s',%s,2)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), 'explicit bounded justification permits finalization without changing raw values')
from a2d_context where context_key = 'outlier';
reset role;

select is(
  pg_temp.safe_count_v43a2d($sql$
    select count(*) from public.consultation_measurement_readings
    where measurement_id = '47500000-0000-0000-0000-000000000030'
      and (ordinal, raw_value::text) in ((1,'80'),(2,'81'),(3,'100'))
  $sql$),
  3::bigint,
  'outlier warning does not autocorrect raw readings'
);

-- Raw replacement needs an explicit correction operation and content-free audit.
set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,1,'47400000-0000-0000-0000-000000000040','{"measurementId":"47500000-0000-0000-0000-000000000001","session":{"observedAt":"2026-08-12T12:00:00.000Z","protocolId":"forja.synthetic.waist","protocolVersion":"1.0.0","conditions":{}},"measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"81.1","unit":"cm"}]}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '22023', 'consultation_measurement_correction_required', 'silent raw-reading replacement is rejected')
from a2d_context where context_key = 'one';
select lives_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,1,'47400000-0000-0000-0000-000000000041','{"measurementId":"47500000-0000-0000-0000-000000000001","session":{"observedAt":"2026-08-12T12:00:00.000Z","protocolId":"forja.synthetic.waist","protocolVersion":"1.0.0","conditions":{}},"measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":1,"value":"81.1","unit":"cm"}],"correctionReason":"Synthetic transcription correction."}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), 'explicit correction may replace the draft raw set before finalization')
from a2d_context where context_key = 'one';
reset role;

select ok(
  pg_temp.safe_count_v43a2d($sql$
    select count(*) from public.consultation_events
    where consultation_id = '47300000-0000-0000-0000-000000000001'
      and event_type = 'measurement_corrected'
  $sql$) = 1,
  'raw-reading correction is audited without copying measurement values'
);

-- Custom observations remain distinct and formula-ineligible even with equal labels.
set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
insert into a2d_results (result_key, payload)
select context.context_key, pg_temp.safe_json_v43a2d(format(
  'select public.save_my_consultation_measurement_v43(%L::uuid,%L,%s,0,%L::uuid,%L::jsonb)',
  context.consultation_id, context.lease_payload->>'leaseToken', context.lease_payload->>'leaseVersion',
  case when context.context_key = 'custom-a' then '47400000-0000-0000-0000-000000000050' else '47400000-0000-0000-0000-000000000051' end,
  jsonb_build_object(
    'measurementId', case when context.context_key = 'custom-a' then '47500000-0000-0000-0000-000000000050' else '47500000-0000-0000-0000-000000000051' end,
    'session', jsonb_build_object('observedAt','2026-08-12T13:00:00.000Z','protocolId','custom.manual','protocolVersion','1','conditions',jsonb_build_object()),
    'measurementKind','custom','customLabel','Synthetic custom','canonicalUnit','cm',
    'observationStatus','recorded','inputUnit','cm','reducer','mean',
    'readings',jsonb_build_array(jsonb_build_object('ordinal',1,'value','10','unit','cm'))
  )::text
))
from a2d_context context where context.context_key in ('custom-a','custom-b');
reset role;

select is(
  pg_temp.safe_count_v43a2d($sql$
    select count(*) from public.consultation_measurements
    where id in ('47500000-0000-0000-0000-000000000050','47500000-0000-0000-0000-000000000051')
      and measurement_kind = 'custom'
      and definition_id is null
      and formula_eligible = false
  $sql$),
  2::bigint,
  'custom measurement remains formula-ineligible and separate from the standard registry'
);
select is(
  pg_temp.safe_text_v43a2d($sql$
    select private.consultation_measurements_are_comparable_v43(
      '47500000-0000-0000-0000-000000000050',
      '47500000-0000-0000-0000-000000000051'
    )::text
  $sql$),
  'false',
  'custom measurements are not compared by label alone'
);

-- A.2C actor, lease and optimistic-revision authority remains mandatory.
set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000101',true);
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,1,'47400000-0000-0000-0000-000000000060','{}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '42501', 'consultation_unauthorized', 'client cannot write measurements')
from a2d_context where context_key = 'three';
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000002',true);
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,1,'47400000-0000-0000-0000-000000000061','{}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '42501', 'consultation_unauthorized', 'other linked professional cannot write measurements')
from a2d_context where context_key = 'three';
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000004',true);
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,1,'47400000-0000-0000-0000-000000000062','{}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '42501', 'consultation_unauthorized', 'organization admin has no clinical authority')
from a2d_context where context_key = 'three';
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000103',true);
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,1,'47400000-0000-0000-0000-000000000063','{}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '42501', 'consultation_unauthorized', 'unrelated user cannot write measurements')
from a2d_context where context_key = 'three';
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,1,'47400000-0000-0000-0000-000000000064','{}'::jsonb)$$,
  consultation_id, repeat('0',64), lease_payload->>'leaseVersion'
), '55000', 'consultation_stale_lease', 'stale lease cannot write measurements')
from a2d_context where context_key = 'three';
select throws_ok(format(
  $$select public.save_my_consultation_measurement_v43('%s','%s',%s,0,'47400000-0000-0000-0000-000000000065','{}'::jsonb)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), '55000', 'consultation_stale_revision', 'stale revision cannot write measurements')
from a2d_context where context_key = 'three';
reset role;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
select throws_ok(
  $$select public.save_my_consultation_measurement_v43('47300000-0000-0000-0000-000000000002',repeat('0',64),1,1,'47400000-0000-0000-0000-000000000066','{}'::jsonb)$$,
  '42501', null, 'anonymous cannot write measurements'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
select throws_ok(
  $$delete from public.consultation_measurements where false$$,
  '42501', null, 'authenticated actor cannot bypass RPC-only measurement writes'
);
reset role;

-- Device observations preserve original provenance and never enter formula data.
set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
insert into a2d_results (result_key, payload)
select context.context_key, pg_temp.safe_json_v43a2d(format(
  'select public.save_my_consultation_device_observation_v43(%L::uuid,%L,%s,0,%L::uuid,%L::jsonb)',
  context.consultation_id, context.lease_payload->>'leaseToken', context.lease_payload->>'leaseVersion',
  case when context.context_key = 'device-a' then '47400000-0000-0000-0000-000000000070' else '47400000-0000-0000-0000-000000000071' end,
  jsonb_build_object(
    'observationId',case when context.context_key = 'device-a' then '47500000-0000-0000-0000-000000000070' else '47500000-0000-0000-0000-000000000071' end,
    'observedAt','2026-08-12T14:00:00.000Z','manufacturer','Synthetic Devices',
    'model','Model X','mode',case when context.context_key = 'device-a' then 'foot_to_foot' else 'hand_to_foot' end,
    'frequency','50 kHz','electrodeLayout','synthetic layout','deviceSettings',jsonb_build_object('profile','synthetic'),
    'contemporaneousMass',jsonb_build_object('value','70.2','unit','kg'),
    'conditions',jsonb_build_object('hydration','not assessed'),
    'metrics',jsonb_build_array(jsonb_build_object('key','body_fat_percent','value','18.7','unit','%'))
  )::text
)) from a2d_context context where context.context_key in ('device-a','device-b');
reset role;

select is(
  pg_temp.safe_count_v43a2d($sql$
    select count(*) from public.consultation_device_observations
    where id in ('47500000-0000-0000-0000-000000000070','47500000-0000-0000-0000-000000000071')
      and result_kind = 'external_device_estimate'
      and original_metrics @> '[{"key":"body_fat_percent","value":"18.7","unit":"%"}]'::jsonb
  $sql$),
  2::bigint,
  'device observation preserves original metrics and units as external_device_estimate'
);
select is(
  pg_temp.safe_text_v43a2d($sql$
    select private.consultation_device_observations_are_comparable_v43(
      '47500000-0000-0000-0000-000000000070',
      '47500000-0000-0000-0000-000000000071'
    )::text
  $sql$),
  'false',
  'different device or mode is not silently comparable'
);

-- Final snapshot ordering and version provenance remain deterministic.
set local role authenticated;
select set_config('request.jwt.claim.sub','47000000-0000-0000-0000-000000000001',true);
insert into a2d_results (result_key, payload)
select 'snapshot-save', pg_temp.safe_json_v43a2d(format(
  'select public.save_my_consultation_measurement_v43(%L::uuid,%L,%s,0,%L::uuid,%L::jsonb)',
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion',
  '47400000-0000-0000-0000-000000000080',
  '{"measurementId":"47500000-0000-0000-0000-000000000080","session":{"observedAt":"2026-08-12T15:00:00.000Z","protocolId":"forja.synthetic.waist","protocolVersion":"1.0.0","conditions":{}},"measurementKind":"standard","definitionKey":"synthetic.waist","definitionVersion":1,"observationStatus":"recorded","inputUnit":"cm","reducer":"mean","readings":[{"ordinal":2,"value":"80.2","unit":"cm"},{"ordinal":1,"value":"80.1","unit":"cm"},{"ordinal":3,"value":"80.3","unit":"cm"}]}'
)) from a2d_context where context_key = 'snapshot';
select lives_ok(format(
  $$select public.finalize_my_consultation_v43('%s','%s',%s,1)$$,
  consultation_id, lease_payload->>'leaseToken', lease_payload->>'leaseVersion'
), 'measurement-bearing consultation finalizes through the existing atomic snapshot model')
from a2d_context where context_key = 'snapshot';
reset role;

select ok(
  pg_temp.safe_exec_v43a2d($sql$
    insert into public.consultation_measurement_definitions (
      id, definition_key, definition_version, display_name, canonical_unit,
      accepted_input_units, anatomical_point, position, instructions,
      protocol_id, protocol_version, allowed_readings_min, allowed_readings_max,
      reducer, formula_eligible, valid_range, warning_rule, source_reference, is_active
    ) values (
      '47100000-0000-0000-0000-000000000003','synthetic.waist',2,
      'Synthetic waist updated','cm',array['cm','mm'],'synthetic midpoint v2',
      'standing','Later synthetic instruction','forja.synthetic.waist','2.0.0',
      1,3,'median',true,'{"min":"1","max":"300"}','{"maxSpread":"4"}',
      'synthetic://waist/v2',true
    )
  $sql$),
  'later standard definition versions append without rewriting v1'
);

insert into a2d_results (result_key, payload)
values (
  'snapshot-payload',
  pg_temp.safe_json_v43a2d($sql$
    select canonical_payload from public.consultation_final_snapshots
    where consultation_id = '47300000-0000-0000-0000-000000000010'
  $sql$)
);

select ok(
  payload @> '{"measurements":[{"measurementId":"47500000-0000-0000-0000-000000000080","definitionKey":"synthetic.waist","definitionVersion":1,"protocolId":"forja.synthetic.waist","protocolVersion":"1.0.0","canonicalUnit":"cm","readings":[{"ordinal":1,"rawValue":"80.1","rawUnit":"cm"},{"ordinal":2,"rawValue":"80.2","rawUnit":"cm"},{"ordinal":3,"rawValue":"80.3","rawUnit":"cm"}]}]}'::jsonb,
  'snapshot preserves definition and protocol version with readings in deterministic ordinal order'
) from a2d_results where result_key = 'snapshot-payload';
select ok(
  (payload->>'canonicalizationVersion' = 'forja.canonical-json.v1')
  or exists (
    select 1 from public.consultation_final_snapshots snapshot
    where snapshot.consultation_id = '47300000-0000-0000-0000-000000000010'
      and snapshot.canonicalization_version = 'forja.canonical-json.v1'
  ),
  'measurement snapshot remains compatible with forja.canonical-json.v1'
) from a2d_results where result_key = 'snapshot-payload';
select ok(
  payload @> '{"measurements":[{"definitionVersion":1,"protocolVersion":"1.0.0"}]}'::jsonb,
  'later definition version does not rewrite finalized measurement provenance'
) from a2d_results where result_key = 'snapshot-payload';

select ok(
  pg_temp.safe_json_v43a2d($sql$
    select canonical_payload from public.consultation_final_snapshots
    where consultation_id = '47300000-0000-0000-0000-000000000007'
  $sql$) @> '{"measurements":[{"observationStatus":"client_declined","calculationEligible":false}]}'::jsonb,
  'non-recorded observation finalizes without invented numeric values'
);

-- Finalized measurement/readings cannot be rewritten by any caller.
select throws_ok(
  $$delete from public.consultation_measurements where consultation_id = '47300000-0000-0000-0000-000000000010'$$,
  '55000', 'finalized_consultation_measurements_are_immutable',
  'finalized measurement rows are immutable for the table owner'
);
select throws_ok(
  $$delete from public.consultation_measurement_readings where measurement_id = '47500000-0000-0000-0000-000000000080'$$,
  '55000', 'finalized_consultation_measurements_are_immutable',
  'finalized raw readings are immutable for the table owner'
);

select * from finish();
rollback;
