with function_info as (
  select
    procedure.oid,
    procedure.proname,
    procedure.prosecdef,
    procedure.proconfig,
    procedure.proacl,
    procedure.proowner,
    pg_catalog.pg_get_functiondef(procedure.oid) as definition,
    pg_catalog.pg_get_function_identity_arguments(procedure.oid) as identity_arguments
  from pg_catalog.pg_proc procedure
  join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
), normalized_functions as (
  select
    *,
    pg_catalog.lower(
      pg_catalog.regexp_replace(
        definition,
        '[[:space:]]+',
        '',
        'g'
      )
    ) as compact_definition
  from function_info
), canonical_scopes as (
  select
    pg_catalog.jsonb_build_object(
      'manage_workout_plan', true,
      'view_workout_executions', true,
      'view_evolution', true,
      'manage_nutrition_plan', false,
      'view_nutrition_logs', false
    ) as trainer_scopes,
    pg_catalog.jsonb_build_object(
      'manage_workout_plan', false,
      'view_workout_executions', false,
      'view_evolution', true,
      'manage_nutrition_plan', true,
      'view_nutrition_logs', true
    ) as nutritionist_scopes,
    pg_catalog.jsonb_build_object(
      'view_workouts', true,
      'assign_workouts', true,
      'view_executions', true,
      'view_evolution', true,
      'view_nutrition', false
    ) as trainer_permissions
), all_checks as (
  select '01_default_helper_returns_exact_trainer_scopes'::text as check_name, 'CRITICAL'::text as severity,
    exists(select 1 from normalized_functions where proname = 'default_professional_relationship_scopes_v41e1' and identity_arguments = 'target_professional_type text')
      and public.default_professional_relationship_scopes_v41e1('trainer') = (select trainer_scopes from canonical_scopes) as passed,
    'trainer helper result is the canonical automatic scope set'::text as details
  union all select '02_default_helper_returns_exact_nutritionist_scopes', 'CRITICAL',
    public.default_professional_relationship_scopes_v41e1('nutritionist') = (select nutritionist_scopes from canonical_scopes),
    'nutritionist helper result is the canonical automatic scope set'
  union all select '03_default_helper_is_internal', 'CRITICAL',
    exists(select 1 from normalized_functions function where function.proname = 'default_professional_relationship_scopes_v41e1'
      and not pg_catalog.has_function_privilege('public', function.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', function.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('authenticated', function.oid, 'EXECUTE')),
    'default helper is not executable by public, anon, or authenticated'
  union all select '04_before_trigger_normalizes_every_write', 'CRITICAL',
    exists(select 1 from pg_catalog.pg_trigger trigger join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace join normalized_functions function on function.oid = trigger.tgfoid
      where namespace.nspname = 'public' and relation.relname = 'professional_student_relationships'
        and trigger.tgname = 'apply_default_professional_relationship_scopes_v41e1' and not trigger.tgisinternal
        and (trigger.tgtype & 1) <> 0 and (trigger.tgtype & 2) <> 0 and (trigger.tgtype & 4) <> 0 and (trigger.tgtype & 16) <> 0
        and function.prosecdef
        and 'search_path=' = any(coalesce(function.proconfig, array[]::text[]))
        and not pg_catalog.has_function_privilege('public', function.oid, 'EXECUTE')
        and not pg_catalog.has_function_privilege('anon', function.oid, 'EXECUTE')
        and not pg_catalog.has_function_privilege('authenticated', function.oid, 'EXECUTE')
        and function.compact_definition like '%new.scopes:=public.default_professional_relationship_scopes_v41e1(new.professional_type)%'),
    'ROW BEFORE INSERT OR UPDATE trigger is internal, protected, and always replaces supplied scopes with defaults'
  union all select '05_invitation_grants_canonical_legacy_permissions', 'CRITICAL',
    exists(select 1 from normalized_functions where proname = 'accept_trainer_student_invitation'
      and compact_definition like '%''view_workouts'',true%' and compact_definition like '%''assign_workouts'',true%'
      and compact_definition like '%''view_executions'',true%' and compact_definition like '%''view_evolution'',true%'
      and compact_definition like '%''view_nutrition'',false%' and compact_definition like '%permissions=excluded.permissions%'),
    'accepted trainer invitation creates the canonical legacy permissions'
  union all select '06_active_trainers_have_only_canonical_scopes', 'CRITICAL',
    not exists(select 1 from public.professional_student_relationships relationship where relationship.status = 'active' and relationship.professional_type = 'trainer' and relationship.scopes is distinct from (select trainer_scopes from canonical_scopes)),
    'every active trainer relationship has only workout and evolution scopes'
  union all select '07_active_nutritionists_have_only_canonical_scopes', 'CRITICAL',
    not exists(select 1 from public.professional_student_relationships relationship where relationship.status = 'active' and relationship.professional_type = 'nutritionist' and relationship.scopes is distinct from (select nutritionist_scopes from canonical_scopes)),
    'every active nutritionist relationship has only nutrition and evolution scopes'
  union all select '08_manual_scope_rpc_is_absent', 'CRITICAL',
    not exists(select 1 from normalized_functions where proname = 'set_my_professional_relationship_scopes'),
    'no public RPC remains for students to edit relationship scopes'
  union all select '09_assignment_rpcs_require_active_relationship', 'CRITICAL',
    exists(select 1 from normalized_functions where proname = 'assign_workout_template_to_student' and compact_definition like '%relationship_record.status<>''active''%')
      and exists(select 1 from normalized_functions where proname = 'assign_nutrition_template_to_student' and compact_definition like '%relationship_record.status<>''active''%'),
    'both workout and nutrition assignment RPCs reject inactive relationships'
  union all select '10_v41d_monitoring_rpcs_require_active_relationship', 'CRITICAL',
    exists(select 1 from normalized_functions where proname = 'get_my_professional_monitoring_entitlement_v41d' and compact_definition like '%relationship.status=''active''%')
      and exists(select 1 from normalized_functions where proname = 'list_my_student_workout_executions' and compact_definition like '%public.get_my_professional_monitoring_entitlement_v41d(%')
      and exists(select 1 from normalized_functions where proname = 'list_my_student_nutrition_logs' and compact_definition like '%public.get_my_professional_monitoring_entitlement_v41d(%')
      and exists(select 1 from normalized_functions where proname = 'list_my_student_evolution' and compact_definition like '%public.get_my_professional_monitoring_entitlement_v41d(%'),
    'each V4.1D monitoring RPC uses the active-relationship entitlement guard'
  union all select '11_active_legacy_trainers_are_synchronized', 'CRITICAL',
    not exists(select 1 from public.trainer_student_relationships legacy join public.professional_student_relationships relationship on relationship.id = legacy.id
      where legacy.status = 'active' and (legacy.permissions is distinct from (select trainer_permissions from canonical_scopes) or relationship.status is distinct from 'active' or relationship.professional_type is distinct from 'trainer' or relationship.scopes is distinct from (select trainer_scopes from canonical_scopes))),
    'active legacy trainer rows and professional rows are synchronized to defaults'
  union all select '12_authenticated_has_no_direct_relationship_update', 'CRITICAL',
    not pg_catalog.has_table_privilege('authenticated', 'public.professional_student_relationships', 'UPDATE')
      and not pg_catalog.has_table_privilege('authenticated', 'public.trainer_student_relationships', 'UPDATE'),
    'authenticated has no direct UPDATE privilege on relationship tables'
), structural_validity as (
  select
    count(*) = 12
      and count(*) filter (where severity = 'CRITICAL') = 12
      and count(*) filter (where severity = 'WARNING') = 0
      and count(distinct check_name) = count(*)
      and bool_and(passed is not null) as passed
  from all_checks
), normalized_checks as (
  select
    check_name,
    severity,
    coalesce(all_checks.passed, false) and structural_validity.passed as passed,
    details
  from all_checks
  cross join structural_validity
), summarized as (
  select
    check_name,
    severity,
    case when coalesce(passed, false) then 'PASS' else 'FAIL' end as result,
    details,
    count(*) over () as total_tests,
    count(*) filter (where severity = 'CRITICAL') over () as critical_tests,
    count(*) filter (where severity = 'WARNING') over () as warning_tests,
    count(*) filter (where severity = 'CRITICAL' and not coalesce(passed, false)) over () as critical_failures,
    count(*) filter (where severity = 'WARNING' and not coalesce(passed, false)) over () as triggered_warnings
  from normalized_checks
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
