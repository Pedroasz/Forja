begin;

drop table if exists pg_temp.v41d_verify_results;

create temporary table v41d_verify_results
on commit preserve rows
as
with
functions as (
  select
    procedure.oid,
    procedure.proname,
    procedure.prosecdef,
    procedure.provolatile,
    procedure.pronargdefaults,
    procedure.proargnames,
    pg_catalog.lower(pg_catalog.pg_get_function_identity_arguments(procedure.oid)) as identity_arguments,
    pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure.oid)) as definition,
    pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure.oid)),
      '[[:space:]]',
      '',
      'g'
    ) as compact,
    exists (
      select 1
      from pg_catalog.unnest(procedure.proconfig) setting
      where pg_catalog.regexp_replace(setting, '[[:space:]]', '', 'g') in ('search_path=', 'search_path=""')
    ) as empty_search_path,
    exists (
      select 1
      from pg_catalog.aclexplode(pg_catalog.coalesce(
        procedure.proacl,
        pg_catalog.acldefault('f', procedure.proowner)
      )) acl
      where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
    ) as public_execute
  from pg_catalog.pg_proc procedure
  join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname in (
      'assert_professional_student_read_access_v41d',
      'assert_professional_monitoring_page_v41d',
      'list_my_student_workout_executions',
      'list_my_student_nutrition_logs',
      'list_my_student_evolution'
    )
),
read_helper as (
  select * from functions where proname = 'assert_professional_student_read_access_v41d'
),
page_helper as (
  select * from functions where proname = 'assert_professional_monitoring_page_v41d'
),
workout_rpc as (
  select * from functions where proname = 'list_my_student_workout_executions'
),
nutrition_rpc as (
  select * from functions where proname = 'list_my_student_nutrition_logs'
),
evolution_rpc as (
  select * from functions where proname = 'list_my_student_evolution'
),
public_rpcs as (
  select * from functions
  where proname in (
    'list_my_student_workout_executions',
    'list_my_student_nutrition_logs',
    'list_my_student_evolution'
  )
),
source_tables as (
  select class.oid, namespace.nspname, class.relname, class.relrowsecurity
  from pg_catalog.pg_class class
  join pg_catalog.pg_namespace namespace on namespace.oid = class.relnamespace
  where namespace.nspname = 'public'
    and class.relname in ('professional_student_relationships', 'workouts', 'meals', 'evolution')
),
index_shapes as (
  select
    index_record.indrelid,
    (
      select pg_catalog.array_agg(attribute.attname::text order by key_column.ordinality)
      from pg_catalog.unnest(index_record.indkey::smallint[]) with ordinality key_column(attnum, ordinality)
      join pg_catalog.pg_attribute attribute
        on attribute.attrelid = index_record.indrelid
       and attribute.attnum = key_column.attnum
      where key_column.ordinality <= index_record.indnkeyatts
        and key_column.ordinality <= 3
    ) as key_columns
  from pg_catalog.pg_index index_record
  where index_record.indisvalid
    and index_record.indpred is null
),
checks as (
  select '01_workout_rpc_exists' as test_name, 'CRITICAL' as severity,
    pg_catalog.to_regprocedure('public.list_my_student_workout_executions(uuid,uuid,uuid,date,date,integer,date,uuid)') is not null as passed,
    'workout execution RPC exists with the approved signature' as details
  union all select '02_nutrition_rpc_exists', 'CRITICAL',
    pg_catalog.to_regprocedure('public.list_my_student_nutrition_logs(uuid,uuid,uuid,date,date,integer,date,uuid)') is not null,
    'nutrition log RPC exists with the approved signature'
  union all select '03_evolution_rpc_exists', 'CRITICAL',
    pg_catalog.to_regprocedure('public.list_my_student_evolution(uuid,uuid,text,uuid,date,date,integer,date,uuid)') is not null,
    'evolution RPC exists with the approved signature'
  union all select '04_read_helper_exists', 'CRITICAL',
    pg_catalog.to_regprocedure('public.assert_professional_student_read_access_v41d(uuid,uuid,text,text,uuid)') is not null,
    'central authorization helper exists'
  union all select '05_page_helper_exists', 'CRITICAL',
    pg_catalog.to_regprocedure('public.assert_professional_monitoring_page_v41d(date,date,integer,date,uuid)') is not null,
    'central pagination helper exists'
  union all select '06_exact_function_set', 'CRITICAL',
    (select count(*) = 5 from functions),
    'the five expected V4.1D functions are present without overload drift'
  union all select '07_public_rpcs_security_definer', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(prosecdef) from public_rpcs), false),
    'all public RPCs are SECURITY DEFINER'
  union all select '08_public_rpcs_stable', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(provolatile = 's') from public_rpcs), false),
    'all public RPCs are STABLE read functions'
  union all select '09_public_rpcs_empty_search_path', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(empty_search_path) from public_rpcs), false),
    'all public RPCs use an empty search_path'
  union all select '10_read_helper_security_definer', 'CRITICAL',
    coalesce((select bool_and(prosecdef and provolatile = 's' and empty_search_path) from read_helper), false),
    'authorization helper is stable SECURITY DEFINER with empty search_path'
  union all select '11_page_helper_invoker', 'CRITICAL',
    coalesce((select bool_and(not prosecdef and provolatile = 'i' and empty_search_path) from page_helper), false),
    'pure page validator is immutable SECURITY INVOKER with empty search_path'
  union all select '12_authenticated_rpc_execute', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')) from public_rpcs), false),
    'authenticated can execute only the public RPC surface'
  union all select '13_anon_no_rpc_execute', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(not pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')) from public_rpcs), false),
    'anon cannot execute any monitoring RPC'
  union all select '14_public_no_rpc_execute', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(not public_execute) from public_rpcs), false),
    'PUBLIC has no execute privilege on monitoring RPCs'
  union all select '15_helpers_not_frontend_executable', 'CRITICAL',
    coalesce((select count(*) = 2 and bool_and(
      not pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
      and not public_execute
    ) from functions where proname like 'assert_professional%'), false),
    'internal helpers are not executable by frontend roles'
  union all select '16_no_professional_id_parameter', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(
      not ('professional_user_id' = any(coalesce(proargnames, array[]::text[])))
      and identity_arguments not like '%professional_user_id%'
    ) from public_rpcs), false),
    'public RPCs never accept professional_user_id'
  union all select '17_relationship_id_parameter', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and('target_relationship_id' = any(proargnames)) from public_rpcs), false),
    'every public RPC requires relationship_id'
  union all select '18_student_id_parameter', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and('target_student_user_id' = any(proargnames)) from public_rpcs), false),
    'every public RPC binds the requested student'
  union all select '19_organization_parameter', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and('target_organization_id' = any(proargnames)) from public_rpcs), false),
    'every public RPC binds organization context'
  union all select '20_helper_validates_session', 'CRITICAL',
    exists(select 1 from read_helper where compact like '%auth.uid()isnull%' and compact like '%session_required%'),
    'authorization derives the professional from auth.uid()'
  union all select '21_helper_matches_relationship', 'CRITICAL',
    exists(select 1 from read_helper where compact like '%relationship.id=target_relationship_id%'),
    'authorization matches the supplied relationship id'
  union all select '22_helper_matches_professional', 'CRITICAL',
    exists(select 1 from read_helper where compact like '%relationship.professional_user_id=auth.uid()%'),
    'authorization requires the authenticated professional'
  union all select '23_helper_matches_student', 'CRITICAL',
    exists(select 1 from read_helper where compact like '%relationship.student_user_id=target_student_user_id%'),
    'authorization requires the relationship student'
  union all select '24_helper_matches_type', 'CRITICAL',
    exists(select 1 from read_helper where compact like '%relationship.professional_type=target_professional_type%'),
    'authorization requires the professional type'
  union all select '25_helper_matches_organization', 'CRITICAL',
    exists(select 1 from read_helper where compact like '%relationship.organization_idisnotdistinctfromtarget_organization_id%'),
    'authorization preserves null-safe organization context'
  union all select '26_helper_requires_active', 'CRITICAL',
    exists(select 1 from read_helper where compact like '%relationship.status=''active''%'),
    'authorization requires an active relationship'
  union all select '27_helper_requires_scope', 'CRITICAL',
    exists(select 1 from read_helper where compact like '%relationship.scopes@>pg_catalog.jsonb_build_object(target_required_scope,true)%'),
    'authorization requires the exact boolean scope'
  union all select '28_helper_blocks_cross_domain', 'CRITICAL',
    exists(select 1 from read_helper where compact like '%target_professional_type=''trainer''%view_workout_executions%view_evolution%'
      and compact like '%target_professional_type=''nutritionist''%view_nutrition_logs%view_evolution%'),
    'scope/type allowlist blocks cross-domain reads'
  union all select '29_workout_trainer_only', 'CRITICAL',
    exists(select 1 from workout_rpc where compact like '%''trainer''%''view_workout_executions''%'
      and compact not like '%''nutritionist''%'),
    'workout execution RPC is trainer-only'
  union all select '30_nutritionist_logs_only', 'CRITICAL',
    exists(select 1 from nutrition_rpc where compact like '%''nutritionist''%''view_nutrition_logs''%'
      and compact not like '%''trainer''%'),
    'nutrition log RPC is nutritionist-only'
  union all select '31_evolution_scope', 'CRITICAL',
    exists(select 1 from evolution_rpc where compact like '%target_professional_typenotin(''trainer'',''nutritionist'')%'
      and compact like '%''view_evolution''%'),
    'evolution RPC allows only trainer or nutritionist with view_evolution'
  union all select '32_page_dates_required', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_start_dateisnullortarget_end_dateisnull%'),
    'date boundaries are mandatory'
  union all select '33_page_date_order', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_start_date>target_end_date%'),
    'invalid date ordering is rejected'
  union all select '34_page_max_366_days', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_end_date-target_start_date>365%'),
    'inclusive periods are limited to 366 days'
  union all select '35_page_limit_lower_bound', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_limit<1%'),
    'limit lower bound is one'
  union all select '36_page_limit_upper_bound', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_limit>100%'),
    'limit upper bound is one hundred'
  union all select '37_page_cursor_pair', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%(target_cursor_dateisnull)<>(target_cursor_idisnull)%'),
    'cursor date and id must be supplied together'
  union all select '38_page_cursor_range', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_cursor_date<target_start_dateortarget_cursor_date>target_end_date%'),
    'cursor must remain inside the requested period'
  union all select '39_all_rpcs_call_authorization', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(compact like '%public.assert_professional_student_read_access_v41d(%') from public_rpcs), false),
    'all public RPCs invoke central authorization'
  union all select '40_all_rpcs_call_page_guard', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(compact like '%public.assert_professional_monitoring_page_v41d(%') from public_rpcs), false),
    'all public RPCs invoke central page validation'
  union all select '41_all_rpcs_bounded', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(compact like '%limit(target_limit+1)%' and compact like '%limittarget_limit%') from public_rpcs), false),
    'all source reads are bounded to limit plus one'
  union all select '42_all_rpcs_cursor_paginated', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(compact like '%target_cursor_dateisnull%target_cursor_id%') from public_rpcs), false),
    'all RPCs use a composite date/id cursor'
  union all select '43_workout_order_deterministic', 'CRITICAL',
    exists(select 1 from workout_rpc where compact like '%orderbyworkout.workout_datedesc,workout.iddesc%'),
    'workouts order deterministically by date and id'
  union all select '44_nutrition_order_deterministic', 'CRITICAL',
    exists(select 1 from nutrition_rpc where compact like '%orderbymeal.meal_datedesc,meal.iddesc%'),
    'nutrition logs order deterministically by date and id'
  union all select '45_evolution_order_deterministic', 'CRITICAL',
    exists(select 1 from evolution_rpc where compact like '%orderbyevolution.record_datedesc,evolution.iddesc%'),
    'evolution orders deterministically by date and id'
  union all select '46_workout_date_filter', 'CRITICAL',
    exists(select 1 from workout_rpc where compact like '%workout.workout_date>=target_start_date%'
      and compact like '%workout.workout_date<=target_end_date%'),
    'workout source is constrained by both dates'
  union all select '47_nutrition_date_filter', 'CRITICAL',
    exists(select 1 from nutrition_rpc where compact like '%meal.meal_date>=target_start_date%'
      and compact like '%meal.meal_date<=target_end_date%'),
    'nutrition source is constrained by both dates'
  union all select '48_evolution_date_filter', 'CRITICAL',
    exists(select 1 from evolution_rpc where compact like '%evolution.record_date>=target_start_date%'
      and compact like '%evolution.record_date<=target_end_date%'),
    'evolution source is constrained by both dates'
  union all select '49_workout_minimal_projection', 'CRITICAL',
    exists(select 1 from workout_rpc where compact not like '%select*frompublic.workouts%'
      and compact not like '%email%' and compact not like '%phone%' and compact not like '%token%'),
    'workout RPC projects only monitoring fields'
  union all select '50_nutrition_minimal_projection', 'CRITICAL',
    exists(select 1 from nutrition_rpc where compact not like '%select*frompublic.meals%'
      and compact not like '%email%' and compact not like '%phone%' and compact not like '%token%'),
    'nutrition RPC projects only monitoring fields'
  union all select '51_evolution_minimal_projection', 'CRITICAL',
    exists(select 1 from evolution_rpc where compact not like '%select*frompublic.evolution%'
      and compact not like '%email%' and compact not like '%phone%' and compact not like '%token%'),
    'evolution RPC projects only monitoring fields'
  union all select '52_public_rpcs_no_write', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(definition !~ '\m(insert|update|delete|truncate|merge|alter|drop)\M') from public_rpcs), false),
    'public RPC definitions contain no data or schema writes'
  union all select '53_public_rpcs_no_dynamic_sql', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(definition !~ '\mexecute\M') from public_rpcs), false),
    'public RPCs contain no dynamic SQL'
  union all select '54_source_tables_exist', 'CRITICAL',
    (select count(*) = 4 from source_tables),
    'all four authorization and data source tables exist'
  union all select '55_source_tables_rls', 'CRITICAL',
    coalesce((select count(*) = 4 and bool_and(relrowsecurity) from source_tables), false),
    'RLS remains enabled on every consulted table'
  union all select '56_anon_no_source_select', 'CRITICAL',
    not pg_catalog.has_table_privilege('anon', 'public.workouts', 'SELECT')
      and not pg_catalog.has_table_privilege('anon', 'public.meals', 'SELECT')
      and not pg_catalog.has_table_privilege('anon', 'public.evolution', 'SELECT'),
    'anon has no direct SELECT on student monitoring sources'
  union all select '57_authenticated_no_unmediated_source_select', 'CRITICAL',
    coalesce((select not rolbypassrls and not rolsuper from pg_catalog.pg_roles where rolname = 'authenticated'), false),
    'authenticated source access remains mediated by RLS'
  union all select '58_no_v41d_source_policy', 'CRITICAL',
    not exists (
      select 1
      from pg_catalog.pg_policy policy
      join pg_catalog.pg_class class on class.oid = policy.polrelid
      join pg_catalog.pg_namespace namespace on namespace.oid = class.relnamespace
      where namespace.nspname = 'public'
        and class.relname in ('workouts', 'meals', 'evolution')
        and policy.polname like '%v41d%'
    ),
    'V4.1D adds no direct table policy for professionals'
  union all select '59_workout_index_shape', 'CRITICAL',
    exists(select 1 from index_shapes where indrelid = 'public.workouts'::regclass
      and key_columns = array['user_id', 'workout_date', 'id']::text[]),
    'workout filtering and cursor ordering have an equivalent index'
  union all select '60_nutrition_index_shape', 'CRITICAL',
    exists(select 1 from index_shapes where indrelid = 'public.meals'::regclass
      and key_columns = array['user_id', 'meal_date', 'id']::text[]),
    'nutrition filtering and cursor ordering have an equivalent index'
  union all select '61_evolution_index_shape', 'CRITICAL',
    exists(select 1 from index_shapes where indrelid = 'public.evolution'::regclass
      and key_columns = array['user_id', 'record_date', 'id']::text[]),
    'evolution filtering and cursor ordering have an equivalent index'
  union all select '62_relationship_scope_consistency', 'CRITICAL',
    not exists (
      select 1
      from public.professional_student_relationships relationship
      where relationship.status = 'active'
        and (
          pg_catalog.jsonb_typeof(relationship.scopes) <> 'object'
          or (relationship.professional_type = 'trainer' and relationship.scopes @> '{"view_nutrition_logs": true}'::jsonb)
          or (relationship.professional_type = 'nutritionist' and relationship.scopes @> '{"view_workout_executions": true}'::jsonb)
        )
    ),
    'active relationships contain no cross-domain scope inconsistency'
  union all select '63_workout_source_keys_complete', 'WARNING',
    not exists(select 1 from public.workouts where user_id is null or workout_date is null or id is null),
    'existing workout rows have complete pagination keys'
  union all select '64_nutrition_source_keys_complete', 'WARNING',
    not exists(select 1 from public.meals where user_id is null or meal_date is null or id is null),
    'existing nutrition rows have complete pagination keys'
  union all select '65_evolution_source_keys_complete', 'WARNING',
    not exists(select 1 from public.evolution where user_id is null or record_date is null or id is null),
    'existing evolution rows have complete pagination keys'
  union all select '66_limit_argument_is_required', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(pronargdefaults = 2) from public_rpcs), false),
    'limit is mandatory; only the composite cursor fields have defaults'
)
select
  row_number() over (order by test_name)::integer as test_number,
  test_name,
  severity,
  coalesce(passed, false) as passed,
  details
from checks;

-- Full report.
select
  test_number,
  test_name,
  severity,
  case when passed then 'PASS' when severity = 'WARNING' then 'WARN' else 'FAIL' end as result,
  details
from pg_temp.v41d_verify_results
order by test_number;

-- Summary with PASS, WARN or FAIL.
select
  count(*) as total_tests,
  count(*) filter (where severity = 'CRITICAL') as critical_tests,
  count(*) filter (where severity = 'WARNING') as warning_tests,
  count(*) filter (where not passed and severity = 'CRITICAL') as critical_failures,
  count(*) filter (where not passed and severity = 'WARNING') as warnings,
  case
    when count(*) filter (where not passed and severity = 'CRITICAL') > 0 then 'FAIL'
    when count(*) filter (where not passed and severity = 'WARNING') > 0 then 'WARN'
    else 'PASS'
  end as overall_result
from pg_temp.v41d_verify_results;

-- Final gate: warnings remain visible but do not block.
do $v41d_gate$
declare
  critical_failures integer;
  failed_tests text;
begin
  select
    count(*) filter (where not passed and severity = 'CRITICAL'),
    pg_catalog.string_agg(test_name, ', ' order by test_number) filter (where not passed and severity = 'CRITICAL')
  into critical_failures, failed_tests
  from pg_temp.v41d_verify_results;

  if critical_failures > 0 then
    raise exception 'V4.1D verification failed (% critical): %', critical_failures, failed_tests;
  end if;
end;
$v41d_gate$;

drop table if exists pg_temp.v41d_verify_results;

commit;
