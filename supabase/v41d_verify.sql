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
    pg_catalog.regexp_replace(pg_catalog.lower(pg_catalog.pg_get_functiondef(procedure.oid)), '[[:space:]]', '', 'g') as compact,
    exists (
      select 1 from pg_catalog.unnest(procedure.proconfig) setting
      where pg_catalog.regexp_replace(setting, '[[:space:]]', '', 'g') in ('search_path=', 'search_path=""')
    ) as empty_search_path,
    exists (
      select 1
      from pg_catalog.aclexplode(coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))) acl
      where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
    ) as public_execute
  from pg_catalog.pg_proc procedure
  join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname in (
      'get_my_professional_monitoring_entitlement_v41d',
      'assert_professional_monitoring_page_v41d',
      'list_my_student_workout_executions',
      'list_my_student_nutrition_logs',
      'list_my_student_evolution'
    )
),
entitlement_helper as (
  select * from functions where proname = 'get_my_professional_monitoring_entitlement_v41d'
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
  where proname in ('list_my_student_workout_executions', 'list_my_student_nutrition_logs', 'list_my_student_evolution')
),
source_tables as (
  select class.oid, class.relname, class.relrowsecurity
  from pg_catalog.pg_class class
  join pg_catalog.pg_namespace namespace on namespace.oid = class.relnamespace
  where namespace.nspname = 'public'
    and class.relname in ('workouts', 'meals', 'evolution')
),
source_policies as (
  select
    policy.polrelid,
    policy.polcmd,
    policy.polroles,
    pg_catalog.regexp_replace(
      pg_catalog.lower(coalesce(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid), '')),
      '[[:space:]]', '', 'g'
    ) as compact_using
  from pg_catalog.pg_policy policy
  join source_tables source on source.oid = policy.polrelid
),
index_shapes as (
  select
    index_record.indrelid,
    index_record.indisunique,
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
  where index_record.indisvalid and index_record.indpred is null
),
checks as (
  select '01_workout_rpc_signature' as test_name, 'CRITICAL' as severity,
    pg_catalog.to_regprocedure('public.list_my_student_workout_executions(uuid,date,date,integer,date,uuid)') is not null as passed,
    'workout RPC has the reduced relationship-only signature' as details
  union all select '02_nutrition_rpc_signature', 'CRITICAL',
    pg_catalog.to_regprocedure('public.list_my_student_nutrition_logs(uuid,date,date,integer,date,uuid)') is not null,
    'nutrition RPC has the reduced relationship-only signature'
  union all select '03_evolution_rpc_signature', 'CRITICAL',
    pg_catalog.to_regprocedure('public.list_my_student_evolution(uuid,date,date,integer,date,uuid)') is not null,
    'evolution RPC has the reduced relationship-only signature'
  union all select '04_entitlement_helper_exists', 'CRITICAL',
    pg_catalog.to_regprocedure('public.get_my_professional_monitoring_entitlement_v41d(uuid,text,text[])') is not null,
    'V4.1D read entitlement helper exists'
  union all select '05_page_helper_exists', 'CRITICAL',
    pg_catalog.to_regprocedure('public.assert_professional_monitoring_page_v41d(date,date,integer,date,uuid)') is not null,
    'page validator exists'
  union all select '06_exact_v41d_function_set', 'CRITICAL',
    (select count(*) = 5 from functions),
    'five expected V4.1D functions exist without overload drift'
  union all select '07_old_workout_overload_absent', 'CRITICAL',
    pg_catalog.to_regprocedure('public.list_my_student_workout_executions(uuid,uuid,uuid,date,date,integer,date,uuid)') is null,
    'old workout overload was removed'
  union all select '08_old_nutrition_overload_absent', 'CRITICAL',
    pg_catalog.to_regprocedure('public.list_my_student_nutrition_logs(uuid,uuid,uuid,date,date,integer,date,uuid)') is null,
    'old nutrition overload was removed'
  union all select '09_old_evolution_overload_absent', 'CRITICAL',
    pg_catalog.to_regprocedure('public.list_my_student_evolution(uuid,uuid,text,uuid,date,date,integer,date,uuid)') is null,
    'old evolution overload was removed'
  union all select '10_old_access_helper_absent', 'CRITICAL',
    pg_catalog.to_regprocedure('public.assert_professional_student_read_access_v41d(uuid,uuid,text,text,uuid)') is null,
    'old caller-supplied access helper was removed'
  union all select '11_public_rpcs_security_definer', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(prosecdef and provolatile = 's' and empty_search_path) from public_rpcs), false),
    'public read RPCs are stable SECURITY DEFINER with empty search_path'
  union all select '12_entitlement_helper_protected', 'CRITICAL',
    coalesce((select bool_and(prosecdef and provolatile = 's' and empty_search_path
      and not public_execute
      and not pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')) from entitlement_helper), false),
    'entitlement helper is protected SECURITY DEFINER'
  union all select '13_page_helper_protected', 'CRITICAL',
    coalesce((select bool_and(not prosecdef and provolatile = 'i' and empty_search_path
      and not public_execute
      and not pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')) from page_helper), false),
    'page helper is protected immutable SECURITY INVOKER'
  union all select '14_authenticated_public_rpc_execute', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')) from public_rpcs), false),
    'authenticated can execute each public RPC'
  union all select '15_anon_no_rpc_execute', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(not pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')) from public_rpcs), false),
    'anon cannot execute a monitoring RPC'
  union all select '16_public_no_rpc_execute', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(not public_execute) from public_rpcs), false),
    'PUBLIC cannot execute a monitoring RPC'
  union all select '17_public_arguments_exact', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(proargnames = array[
      'target_relationship_id', 'target_start_date', 'target_end_date',
      'target_limit', 'target_cursor_date', 'target_cursor_id'
    ]::text[]) from public_rpcs), false),
    'every public RPC accepts only relationship, period, limit and cursor'
  union all select '18_removed_public_parameters_absent', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(not (coalesce(proargnames, array[]::text[]) && array[
      'professional_user_id', 'student_user_id', 'target_student_user_id',
      'organization_id', 'target_organization_id', 'professional_type', 'target_professional_type'
    ]::text[])) from public_rpcs), false),
    'public RPCs accept no professional, student, organization or type parameter'
  union all select '19_limit_required_cursor_optional', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(pronargdefaults = 2) from public_rpcs), false),
    'limit is required and only the cursor fields have defaults'
  union all select '20_entitlement_validates_session', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%auth.uid()isnull%' and compact like '%session_required%'),
    'entitlement requires an authenticated session'
  union all select '21_entitlement_owns_relationship', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%relationship.id=target_relationship_id%'
      and compact like '%relationship.professional_user_id=auth.uid()%'),
    'entitlement binds the relationship to auth.uid()'
  union all select '22_entitlement_derives_relationship_context', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%relationship.student_user_id,relationship.professional_type,relationship.organization_id%'
      and compact like '%derived_student_user_id,derived_professional_type,derived_organization_id%'),
    'student, type and organization are derived internally'
  union all select '23_entitlement_requires_active_relationship', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%relationship.status=''active''%'),
    'entitlement requires an active relationship'
  union all select '24_entitlement_requires_exact_scope', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%relationship.scopes@>pg_catalog.jsonb_build_object(target_required_scope,true)%'),
    'entitlement requires the exact boolean scope'
  union all select '25_entitlement_allowlists_domains', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%view_workout_executions%array[''trainer'']%'
      and compact like '%view_nutrition_logs%array[''nutritionist'']%'
      and compact like '%view_evolution%array[''trainer'',''nutritionist'']%'),
    'helper allowlists the three approved monitoring domains'
  union all select '26_entitlement_commercial_type', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%account.primary_account_type=derived_professional_type%'),
    'commercial account type must match the derived relationship type'
  union all select '27_entitlement_active_plan', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%plan.code=account.plan_code%'
      and compact like '%plan.account_type=account.primary_account_type%'
      and compact like '%account_plan_is_activeisnottrue%'),
    'existing commercial plan must be active'
  union all select '28_entitlement_subscription', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%account_subscription_statusnotin(''active'',''trialing'')%'),
    'subscription must be active or trialing'
  union all select '29_entitlement_account_mode', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%public.user_account_modes%account_mode.mode=derived_professional_type%'),
    'professional account mode must match the derived type'
  union all select '30_entitlement_independent_relationship', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%ifderived_organization_idisnotnullthen%'),
    'independent relationships do not require organization membership'
  union all select '31_entitlement_active_membership', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%public.organization_members%membership.status=''active''%'
      and compact like '%membership.organization_id=derived_organization_id%'),
    'organization relationships require active membership'
  union all select '32_entitlement_trainer_membership_roles', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%derived_professional_type=''trainer''%membership.rolein(''owner'',''admin'',''trainer'')%'),
    'trainer organization roles are owner, admin or trainer'
  union all select '33_entitlement_nutritionist_membership_roles', 'CRITICAL',
    exists(select 1 from entitlement_helper where compact like '%derived_professional_type=''nutritionist''%membership.rolein(''owner'',''admin'',''nutritionist'')%'),
    'nutritionist organization roles are owner, admin or nutritionist'
  union all select '34_workout_entitlement_call', 'CRITICAL',
    exists(select 1 from workout_rpc where compact like '%public.get_my_professional_monitoring_entitlement_v41d(target_relationship_id,''view_workout_executions'',array[''trainer'']::text[])%'),
    'workout RPC requires trainer workout-execution entitlement'
  union all select '35_nutrition_entitlement_call', 'CRITICAL',
    exists(select 1 from nutrition_rpc where compact like '%public.get_my_professional_monitoring_entitlement_v41d(target_relationship_id,''view_nutrition_logs'',array[''nutritionist'']::text[])%'),
    'nutrition RPC requires nutritionist log entitlement'
  union all select '36_evolution_entitlement_call', 'CRITICAL',
    exists(select 1 from evolution_rpc where compact like '%public.get_my_professional_monitoring_entitlement_v41d(target_relationship_id,''view_evolution'',array[''trainer'',''nutritionist'']::text[])%'),
    'evolution RPC permits trainer or nutritionist with view_evolution'
  union all select '37_all_rpcs_use_derived_student', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(compact like '%derived_student_user_id%') from public_rpcs), false),
    'all source queries use the internally derived student id'
  union all select '38_all_rpcs_call_page_guard', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(compact like '%public.assert_professional_monitoring_page_v41d(%') from public_rpcs), false),
    'all public RPCs call the central page validator'
  union all select '39_page_dates_required', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_start_dateisnullortarget_end_dateisnull%'),
    'date boundaries are mandatory'
  union all select '40_page_date_order', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_start_date>target_end_date%'),
    'invalid date order is rejected'
  union all select '41_page_max_366_days', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_end_date-target_start_date>365%'),
    'inclusive date range is limited to 366 days'
  union all select '42_page_limit_bounds', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_limit<1%' and compact like '%target_limit>100%'),
    'limit is constrained to one through one hundred'
  union all select '43_page_cursor_pair', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%(target_cursor_dateisnull)<>(target_cursor_idisnull)%'),
    'cursor date and id must be supplied together'
  union all select '44_page_cursor_range', 'CRITICAL',
    exists(select 1 from page_helper where compact like '%target_cursor_date<target_start_dateortarget_cursor_date>target_end_date%'),
    'cursor must remain inside the requested period'
  union all select '45_rpcs_bounded', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(compact like '%limit(target_limit+1)%' and compact like '%limittarget_limit%') from public_rpcs), false),
    'all source reads are bounded to limit plus one'
  union all select '46_rpcs_composite_cursor', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(compact like '%target_cursor_dateisnull%target_cursor_id%') from public_rpcs), false),
    'all RPCs use a stable date/id cursor'
  union all select '47_workout_order', 'CRITICAL',
    exists(select 1 from workout_rpc where compact like '%orderbyworkout.workout_datedesc,workout.iddesc%'),
    'workouts are deterministically ordered'
  union all select '48_nutrition_order', 'CRITICAL',
    exists(select 1 from nutrition_rpc where compact like '%orderbymeal.meal_datedesc,meal.iddesc%'),
    'nutrition logs are deterministically ordered'
  union all select '49_evolution_order', 'CRITICAL',
    exists(select 1 from evolution_rpc where compact like '%orderbyevolution.record_datedesc,evolution.iddesc%'),
    'evolution records are deterministically ordered'
  union all select '50_source_date_filters', 'CRITICAL',
    exists(select 1 from workout_rpc where compact like '%workout.workout_date>=target_start_date%workout.workout_date<=target_end_date%')
      and exists(select 1 from nutrition_rpc where compact like '%meal.meal_date>=target_start_date%meal.meal_date<=target_end_date%')
      and exists(select 1 from evolution_rpc where compact like '%evolution.record_date>=target_start_date%evolution.record_date<=target_end_date%'),
    'every source query is constrained by both period boundaries'
  union all select '51_minimal_projections', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(compact not like '%select*frompublic.%'
      and compact not like '%email%' and compact not like '%phone%' and compact not like '%token%') from public_rpcs), false),
    'RPCs do not return broad source rows or identity secrets'
  union all select '52_public_rpcs_no_write', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(definition !~ '\m(insert|update|delete|truncate|merge|alter|drop)\M') from public_rpcs), false),
    'public RPCs contain no writes'
  union all select '53_public_rpcs_no_dynamic_sql', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(definition !~ '\mexecute\M') from public_rpcs), false),
    'public RPCs contain no dynamic SQL'
  union all select '54_source_tables_exist', 'CRITICAL',
    (select count(*) = 3 from source_tables),
    'all three student-data source tables exist'
  union all select '55_source_tables_rls', 'CRITICAL',
    coalesce((select count(*) = 3 and bool_and(relrowsecurity) from source_tables), false),
    'RLS remains enabled on all student-data tables'
  union all select '56_anon_source_access_effective_rls', 'CRITICAL',
    not exists (
      select 1 from source_policies policy
      where policy.polcmd in ('r', '*')
        and (0::oid = any(policy.polroles) or (select oid from pg_catalog.pg_roles where rolname = 'anon') = any(policy.polroles))
        and (policy.compact_using in ('true', '(true)') or policy.compact_using not like '%auth.uid()%')
    ),
    'anon SELECT/ALL policies remain tied to auth.uid() rather than grants alone'
  union all select '57_source_policies_owner_limited', 'CRITICAL',
    not exists (
      select 1 from source_policies policy
      where policy.polcmd in ('r', '*')
        and (
          0::oid = any(policy.polroles)
          or (select oid from pg_catalog.pg_roles where rolname = 'anon') = any(policy.polroles)
          or (select oid from pg_catalog.pg_roles where rolname = 'authenticated') = any(policy.polroles)
        )
        and (policy.compact_using in ('true', '(true)')
          or policy.compact_using not like '%auth.uid()%'
          or policy.compact_using not like '%user_id%')
    ),
    'applicable source policies remain owner-limited by user_id and auth.uid()'
  union all select '58_authenticated_no_bypassrls', 'CRITICAL',
    coalesce((select not rolbypassrls and not rolsuper from pg_catalog.pg_roles where rolname = 'authenticated'), false),
    'authenticated is neither superuser nor BYPASSRLS'
  union all select '59_no_v41d_source_policy', 'CRITICAL',
    not exists (
      select 1 from pg_catalog.pg_policy policy
      join source_tables source on source.oid = policy.polrelid
      where policy.polname like '%v41d%'
    ),
    'V4.1D creates no direct professional source-table policy'
  union all select '60_workout_cursor_index', 'CRITICAL',
    exists(select 1 from index_shapes where indrelid = 'public.workouts'::regclass
      and key_columns = array['user_id', 'workout_date', 'id']::text[]),
    'workouts has an index for user/date/id cursor ordering'
  union all select '61_meals_unique_user_date', 'CRITICAL',
    exists(select 1 from index_shapes where indrelid = 'public.meals'::regclass
      and indisunique and key_columns = array['user_id', 'meal_date']::text[]),
    'meals reuses its unique user/date index'
  union all select '62_evolution_unique_user_date', 'CRITICAL',
    exists(select 1 from index_shapes where indrelid = 'public.evolution'::regclass
      and indisunique and key_columns = array['user_id', 'record_date']::text[]),
    'evolution reuses its unique user/date index'
  union all select '63_no_v41d_meals_index', 'CRITICAL',
    pg_catalog.to_regclass('public.meals_user_date_id_v41d_idx') is null,
    'no redundant V4.1D meals index exists'
  union all select '64_no_v41d_evolution_index', 'CRITICAL',
    pg_catalog.to_regclass('public.evolution_user_date_id_v41d_idx') is null,
    'no redundant V4.1D evolution index exists'
  union all select '65_relationship_scope_consistency', 'CRITICAL',
    not exists (
      select 1 from public.professional_student_relationships relationship
      where relationship.status = 'active' and (
        pg_catalog.jsonb_typeof(relationship.scopes) <> 'object'
        or (relationship.professional_type = 'trainer' and relationship.scopes @> '{"view_nutrition_logs": true}'::jsonb)
        or (relationship.professional_type = 'nutritionist' and relationship.scopes @> '{"view_workout_executions": true}'::jsonb)
      )
    ),
    'active relationships contain no cross-domain scope inconsistency'
  union all select '66_workout_keys_complete', 'WARNING',
    not exists(select 1 from public.workouts where user_id is null or workout_date is null or id is null),
    'existing workout rows have complete pagination keys'
  union all select '67_nutrition_keys_complete', 'WARNING',
    not exists(select 1 from public.meals where user_id is null or meal_date is null or id is null),
    'existing meal rows have complete pagination keys'
  union all select '68_evolution_keys_complete', 'WARNING',
    not exists(select 1 from public.evolution where user_id is null or record_date is null or id is null),
    'existing evolution rows have complete pagination keys'
  union all select '69_source_user_ids_not_null', 'CRITICAL',
    not exists (
      select 1
      from pg_catalog.pg_attribute attribute
      join source_tables source on source.oid = attribute.attrelid
      where attribute.attname = 'user_id'
        and attribute.attnum > 0
        and not attribute.attisdropped
        and not attribute.attnotnull
    ),
    'all source user_id columns are declared NOT NULL for RLS ownership'
),
base_checks as (
  select
    row_number() over (order by test_name)::integer as test_number,
    test_name as check_name,
    case
      when test_name < '20_' then 'RPC contract and grants'
      when test_name < '39_' then 'Authorization'
      when test_name < '54_' then 'Pagination and RPC safety'
      when test_name < '66_' then 'RLS and schema safety'
      else 'Data quality'
    end as category,
    severity,
    coalesce(passed, false) as passed,
    details
  from checks
),
test_inventory as (
  select
    count(*)::integer as total_tests,
    count(*) filter (where severity = 'CRITICAL')::integer as critical_tests,
    count(*) filter (where severity = 'WARNING')::integer as warning_tests,
    count(distinct check_name)::integer as unique_check_names
  from base_checks
),
structural_check as (
  select
    total_tests = 69
      and critical_tests = 66
      and warning_tests = 3
      and unique_check_names = 69 as passed,
    format(
      'structural inventory: total=%s/69, critical=%s/66, warning=%s/3, unique=%s/69',
      total_tests,
      critical_tests,
      warning_tests,
      unique_check_names
    ) as details
  from test_inventory
),
all_checks as (
  select
    check_row.test_number,
    check_row.check_name,
    check_row.category,
    check_row.severity,
    check_row.passed and structural_check.passed as passed,
    case when check_row.passed and structural_check.passed then 'true' else 'false' end as found_value,
    'true'::text as expected_value,
    check_row.details
      || case when structural_check.passed then '' else ' | ' || structural_check.details end as details
  from base_checks check_row
  cross join structural_check
),
summary as (
  select
    count(*)::integer as total_tests,
    count(*) filter (where severity = 'CRITICAL')::integer as critical_tests,
    count(*) filter (where severity = 'WARNING')::integer as warning_tests,
    count(*) filter (where not passed and severity = 'CRITICAL')::integer as critical_failures,
    count(*) filter (where not passed and severity = 'WARNING')::integer as triggered_warnings
  from all_checks
)
select
  all_checks.check_name,
  all_checks.category,
  all_checks.severity,
  case
    when all_checks.passed then 'PASS'
    when all_checks.severity = 'WARNING' then 'WARN'
    else 'FAIL'
  end as result,
  all_checks.found_value,
  all_checks.expected_value,
  all_checks.details,
  summary.total_tests,
  summary.critical_tests,
  summary.warning_tests,
  summary.critical_failures,
  summary.triggered_warnings,
  case
    when summary.critical_failures > 0 then 'FAIL'
    when summary.triggered_warnings > 0 then 'WARN'
    else 'PASS'
  end as overall_result
from all_checks
cross join summary
order by all_checks.test_number;
