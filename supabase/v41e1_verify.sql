with function_info as (
  select
    procedure.oid,
    procedure.prosecdef,
    procedure.proconfig,
    procedure.proacl,
    procedure.proowner,
    pg_catalog.pg_get_functiondef(procedure.oid) as definition,
    pg_catalog.pg_get_function_identity_arguments(procedure.oid) as identity_arguments,
    pg_catalog.pg_get_userbyid(procedure.proowner) as owner_name
  from pg_catalog.pg_proc procedure
  join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'set_my_professional_relationship_scopes'
), normalized_function as (
  select
    *,
    pg_catalog.lower(pg_catalog.regexp_replace(definition, '\\s+', '', 'g')) as compact_definition
  from function_info
), relation_info as (
  select
    pg_catalog.to_regclass('public.professional_student_relationships') as professional_relationships,
    pg_catalog.to_regclass('public.trainer_student_relationships') as legacy_relationships
), all_checks as (
  select '01_rpc_exists_with_exact_signature'::text as check_name, 'CRITICAL'::text as severity,
    exists(select 1 from normalized_function where identity_arguments = 'target_relationship_id uuid, target_scopes jsonb') as passed,
    'student scope RPC exists with only relationship and scopes parameters'::text as details
  union all select '02_rpc_uses_security_definer', 'CRITICAL',
    exists(select 1 from normalized_function where prosecdef),
    'RPC uses SECURITY DEFINER for the guarded update'
  union all select '03_rpc_uses_empty_search_path', 'CRITICAL',
    exists(select 1 from normalized_function where 'search_path=' = any(coalesce(proconfig, array[]::text[]))),
    'RPC has an empty search_path'
  union all select '04_public_and_anon_cannot_execute', 'CRITICAL',
    exists(select 1 from normalized_function function where not exists (
      select 1 from pg_catalog.aclexplode(coalesce(function.proacl, pg_catalog.acldefault('f', function.proowner))) privilege
      where privilege.grantee = 0 and privilege.privilege_type = 'EXECUTE'
    ) and not pg_catalog.has_function_privilege('anon', function.oid, 'EXECUTE')),
    'PUBLIC and anon cannot execute the RPC'
  union all select '05_authenticated_can_execute', 'CRITICAL',
    exists(select 1 from normalized_function function where pg_catalog.has_function_privilege('authenticated', function.oid, 'EXECUTE')),
    'authenticated can execute the RPC'
  union all select '06_requires_authenticated_student', 'CRITICAL',
    exists(select 1 from normalized_function where compact_definition like '%auth.uid()isnull%' and compact_definition like '%relationship.student_user_id=auth.uid()%'),
    'only the authenticated student can change a relationship'
  union all select '07_requires_active_relationship', 'CRITICAL',
    exists(select 1 from normalized_function where compact_definition like '%relationship_record.status<>''active''%'),
    'inactive relationships are rejected'
  union all select '08_rejects_unknown_scope_keys', 'CRITICAL',
    exists(select 1 from normalized_function where compact_definition like '%relationship_scope_unknown_key%' and compact_definition like '%jsonb_each(target_scopes)%'),
    'scope payload keys are allowlisted'
  union all select '09_rejects_non_boolean_values', 'CRITICAL',
    exists(select 1 from normalized_function where compact_definition like '%relationship_scope_value_must_be_boolean%' and compact_definition like '%jsonb_typeof(requested_value)<>''boolean''%'),
    'all accepted scope values are booleans'
  union all select '10_trainer_scopes_are_isolated', 'CRITICAL',
    exists(select 1 from normalized_function where compact_definition like '%relationship_scope_not_allowed_for_trainer%' and compact_definition like '%''manage_nutrition_plan'',false%' and compact_definition like '%''view_nutrition_logs'',false%'),
    'trainer relationships cannot receive nutrition scopes'
  union all select '11_nutritionist_scopes_are_isolated', 'CRITICAL',
    exists(select 1 from normalized_function where compact_definition like '%relationship_scope_not_allowed_for_nutritionist%' and compact_definition like '%''manage_workout_plan'',false%' and compact_definition like '%''view_workout_executions'',false%'),
    'nutritionist relationships cannot receive workout scopes'
  union all select '12_no_user_id_parameters', 'CRITICAL',
    exists(select 1 from normalized_function where identity_arguments = 'target_relationship_id uuid, target_scopes jsonb'),
    'RPC does not accept professional or student user IDs'
  union all select '13_legacy_trainer_mapping_present', 'CRITICAL',
    exists(select 1 from normalized_function where compact_definition like '%trainer_student_relationships%' and compact_definition like '%''assign_workouts'',normalized_scopes->''manage_workout_plan''%' and compact_definition like '%''view_executions'',normalized_scopes->''view_workout_executions''%' and compact_definition like '%''view_nutrition'',false%'),
    'legacy trainer permissions are mapped before the existing synchronizer runs'
  union all select '14_direct_scope_fallback_present', 'CRITICAL',
    exists(select 1 from normalized_function where compact_definition like '%updatepublic.professional_student_relationshipssetscopes=normalized_scopes%'),
    'non-legacy relationships update their own scopes directly'
  union all select '15_authenticated_has_no_direct_relationship_update', 'CRITICAL',
    (select professional_relationships is not null and not pg_catalog.has_table_privilege('authenticated', professional_relationships, 'UPDATE') from relation_info),
    'authenticated has no direct UPDATE on professional relationships'
  union all select '16_legacy_authenticated_has_no_direct_update', 'CRITICAL',
    (select legacy_relationships is null or not pg_catalog.has_table_privilege('authenticated', legacy_relationships, 'UPDATE') from relation_info),
    'authenticated has no direct UPDATE on legacy trainer relationships'
  union all select '17_no_v41e1_helper_is_frontend_callable', 'CRITICAL',
    not exists(
      select 1
      from pg_catalog.pg_proc procedure
      join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
      where namespace.nspname = 'public'
        and procedure.proname like '%v41e1%'
        and procedure.proname <> 'set_my_professional_relationship_scopes'
        and pg_catalog.has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
    ),
    'no V4.1E1 helper is executable by authenticated users'
), summarized as (
  select
    check_name,
    severity,
    case when passed then 'PASS' else 'FAIL' end as result,
    details,
    count(*) over () as total_tests,
    count(*) filter (where severity = 'CRITICAL') over () as critical_tests,
    count(*) filter (where severity = 'WARNING') over () as warning_tests,
    count(*) filter (where severity = 'CRITICAL' and not passed) over () as critical_failures,
    count(*) filter (where severity = 'WARNING' and not passed) over () as triggered_warnings
  from all_checks
)
select
  check_name,
  severity,
  result,
  details,
  total_tests,
  critical_tests,
  warning_tests,
  critical_failures,
  triggered_warnings,
  case when critical_failures > 0 then 'FAIL' when triggered_warnings > 0 then 'WARN' else 'PASS' end as overall_result
from summarized
order by check_name;
