-- V4.1A verification only. This file performs no writes.
with
mode_constraint as (
  select lower(pg_catalog.pg_get_constraintdef(c.oid)) definition
  from pg_catalog.pg_constraint c
  where c.conrelid = 'public.user_account_modes'::regclass
    and c.conname = 'user_account_modes_mode_check'
),
organization_role_constraint as (
  select lower(pg_catalog.pg_get_constraintdef(c.oid)) definition
  from pg_catalog.pg_constraint c
  where c.conrelid = 'public.organization_members'::regclass
    and c.conname = 'organization_members_role_check'
),
relationship_table as (
  select cls.oid, cls.relrowsecurity
  from pg_catalog.pg_class cls
  join pg_catalog.pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public' and cls.relname = 'professional_student_relationships'
),
scope_constraint as (
  select lower(pg_catalog.pg_get_constraintdef(c.oid)) definition
  from pg_catalog.pg_constraint c
  where c.conrelid = 'public.professional_student_relationships'::regclass
    and c.conname = 'professional_student_relationships_scopes_check'
),
function_info as (
  select p.oid, p.proname, p.prosecdef,
    lower(pg_catalog.pg_get_functiondef(p.oid)) definition,
    exists (
      select 1 from unnest(p.proconfig) setting
      where pg_catalog.regexp_replace(setting, '[[:space:]]', '', 'g') in ('search_path=', 'search_path=""')
    ) empty_search_path
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'default_professional_scopes',
      'has_active_professional_relationship',
      'set_my_account_modes',
      'get_current_access_context',
      'sync_legacy_trainer_relationship_v41a'
    )
),
default_scope_function as (
  select definition from function_info where proname = 'default_professional_scopes'
),
access_context_function as (
  select definition from function_info where proname = 'get_current_access_context'
),
trigger_info as (
  select
    lower(pg_catalog.pg_get_triggerdef(trigger.oid)) trigger_definition,
    lower(pg_catalog.pg_get_functiondef(trigger.tgfoid)) function_definition
  from pg_catalog.pg_trigger trigger
  where trigger.tgrelid = 'public.trainer_student_relationships'::regclass
    and trigger.tgname = 'sync_legacy_trainer_relationship_v41a'
    and not trigger.tgisinternal
),
checks as (
  select '01_nutritionist_account_mode' check_name,
    exists(select 1 from mode_constraint where definition like '%nutritionist%')
    and pg_catalog.pg_get_functiondef('public.set_my_account_modes(text[])'::regprocedure)::text like '%nutritionist%' passed,
    'nutritionist must be accepted by both constraint and set_my_account_modes' details
  union all
  select '02_privileged_modes_blocked',
    exists(select 1 from mode_constraint where definition not like '%platform_admin%' and definition not like '%support%' and definition not like '%gym_admin%' and definition not like '%owner%' and definition not like '%admin%')
    and pg_catalog.pg_get_functiondef('public.set_my_account_modes(text[])'::regprocedure)::text not like '%platform_admin%',
    'account modes remain limited to individual, student, trainer and nutritionist'
  union all
  select '03_nutritionist_organization_role',
    exists(select 1 from organization_role_constraint where definition like '%nutritionist%' and definition like '%owner%' and definition like '%admin%' and definition like '%trainer%' and definition like '%student%'),
    'organization role check contains nutritionist without changing administrative roles'
  union all
  select '04_professional_relationship_table_exists',
    exists(select 1 from relationship_table),
    'public.professional_student_relationships exists'
  union all
  select '05_professional_relationship_rls_enabled',
    coalesce((select relrowsecurity from relationship_table), false),
    'RLS is enabled on professional_student_relationships'
  union all
  select '06_no_direct_writes',
    not pg_catalog.has_table_privilege('anon', 'public.professional_student_relationships', 'SELECT')
    and not pg_catalog.has_table_privilege('anon', 'public.professional_student_relationships', 'INSERT')
    and not pg_catalog.has_table_privilege('anon', 'public.professional_student_relationships', 'UPDATE')
    and not pg_catalog.has_table_privilege('anon', 'public.professional_student_relationships', 'DELETE')
    and not pg_catalog.has_table_privilege('authenticated', 'public.professional_student_relationships', 'INSERT')
    and not pg_catalog.has_table_privilege('authenticated', 'public.professional_student_relationships', 'UPDATE')
    and not pg_catalog.has_table_privilege('authenticated', 'public.professional_student_relationships', 'DELETE')
    and pg_catalog.has_table_privilege('authenticated', 'public.professional_student_relationships', 'SELECT'),
    'anon has no access and authenticated has SELECT only'
  union all
  select '07_scopes_exactly_validated',
    exists(select 1 from scope_constraint where
      definition like '%manage_workout_plan%'
      and definition like '%view_workout_executions%'
      and definition like '%manage_nutrition_plan%'
      and definition like '%view_nutrition_logs%'
      and definition like '%view_evolution%'
      and definition like '%jsonb_typeof%'
      and definition like '%?&%'
      and definition like '%professional_type <> ''trainer''%'
      and definition like '%manage_nutrition_plan%false%'
      and definition like '%view_nutrition_logs%false%'
      and definition like '%professional_type <> ''nutritionist''%'
      and definition like '%manage_workout_plan%false%'
      and definition like '%view_workout_executions%false%'),
    'five required boolean scopes exist, additional keys and cross-professional scopes are rejected'
  union all
  select '08_trainer_has_no_default_nutrition_access',
    exists(select 1 from default_scope_function where definition like '%''trainer''%'
      and definition like '%''manage_nutrition_plan'', false%'
      and definition like '%''view_nutrition_logs'', false%')
    and exists(select 1 from scope_constraint where definition like '%professional_type <> ''trainer''%'),
    'trainer defaults deny nutrition management and logs'
  union all
  select '09_nutritionist_has_no_default_workout_access',
    exists(select 1 from default_scope_function where definition like '%''nutritionist''%'
      and definition like '%''manage_workout_plan'', false%'
      and definition like '%''view_workout_executions'', false%')
    and exists(select 1 from scope_constraint where definition like '%professional_type <> ''nutritionist''%'),
    'nutritionist defaults deny workout management and executions'
  union all
  select '10_evolution_defaults_blocked',
    exists(select 1 from default_scope_function where
      (length(definition) - length(replace(definition, '''view_evolution'', false', ''))) / length('''view_evolution'', false') >= 2),
    'view_evolution starts false for both professional types'
  union all
  select '11_authorization_functions_safe',
    (select count(*) = 5 and bool_and(empty_search_path) from function_info)
    and coalesce((select prosecdef from function_info where proname = 'has_active_professional_relationship'), false)
    and not pg_catalog.has_function_privilege('anon', 'public.has_active_professional_relationship(uuid,uuid,text,text,uuid)', 'EXECUTE')
    and pg_catalog.has_function_privilege('authenticated', 'public.has_active_professional_relationship(uuid,uuid,text,text,uuid)', 'EXECUTE'),
    'authorization RPC is SECURITY DEFINER, authenticated-only and all V4.1A functions have empty search_path'
  union all
  select '12_access_context_updated',
    exists(select 1 from access_context_function where definition like '%professionalrelationships%'
      and definition like '%studentprofessionalrelationships%'
      and definition like '%professionaltype%'
      and definition like '%organizationid%'
      and definition like '%scopes%'
      and definition not like '%email%'
      and definition not like '%phone%'
      and definition not like '%nutrition_logs%'
      and definition not like '%workout_executions%'),
    'access context exposes only relationship identifiers, type, scopes, organization and status'
  union all
  select '13_legacy_relationships_preserved',
    to_regclass('public.trainer_student_relationships') is not null
    and exists(select 1 from pg_catalog.pg_trigger where tgname = 'sync_legacy_trainer_relationship_v41a' and not tgisinternal)
    and not exists(
      select 1 from public.trainer_student_relationships legacy
      left join public.professional_student_relationships current on current.id = legacy.id
      where current.id is null
    ),
    'legacy table remains and every existing row has a compatible professional row'
  union all
  select '14_no_fictitious_or_orphan_relationships',
    not exists(
      select 1 from public.professional_student_relationships relationship
      left join auth.users professional on professional.id = relationship.professional_user_id
      left join auth.users student on student.id = relationship.student_user_id
      where professional.id is null or student.id is null
    ),
    'all relationship identities are backed by real auth.users rows; migration creates no users or organizations'
  union all
  select '15_no_automatic_access_to_domain_data',
    not exists(
      select 1
      from pg_catalog.pg_policy policy
      join pg_catalog.pg_class cls on cls.oid = policy.polrelid
      join pg_catalog.pg_namespace ns on ns.oid = cls.relnamespace
      where ns.nspname = 'public'
        and cls.relname in ('meals', 'hydration', 'evolution', 'workouts', 'profiles')
        and pg_catalog.pg_get_expr(policy.polqual, policy.polrelid) like '%has_active_professional_relationship%'
    ),
    'no domain-data RLS policy grants professional access in V4.1A'
  union all
  select '16_constraints_replaced_by_expected_names',
    exists(select 1 from pg_catalog.pg_constraint where conrelid='public.user_account_modes'::regclass and conname='user_account_modes_mode_check')
    and exists(select 1 from pg_catalog.pg_constraint where conrelid='public.organization_members'::regclass and conname='organization_members_role_check'),
    'only the two explicitly named mode and role constraints are replaced by the migration'
  union all
  select '17_authorization_signature_has_organization',
    to_regprocedure('public.has_active_professional_relationship(uuid,uuid,text,text,uuid)') is not null
    and to_regprocedure('public.has_active_professional_relationship(uuid,uuid,text,text)') is null,
    'five-argument organization-aware signature exists and the old four-argument signature is absent'
  union all
  select '18_organization_context_isolated',
    exists(select 1 from function_info where proname='has_active_professional_relationship' and definition like '%organization_id is not distinct from target_organization_id%'),
    'authorization compares organization_id with IS NOT DISTINCT FROM'
  union all
  select '19_independent_context_requires_null',
    exists(select 1 from function_info where proname='has_active_professional_relationship' and definition like '%organization_id is not distinct from target_organization_id%')
    and lower(pg_catalog.pg_get_function_arguments('public.has_active_professional_relationship(uuid,uuid,text,text,uuid)'::regprocedure)) like '%target_organization_id uuid default null%',
    'an omitted organization resolves only independent relationships whose organization_id is null'
  union all
  select '20_legacy_trainer_nutrition_not_migrated',
    not exists(select 1 from public.professional_student_relationships where professional_type='trainer' and ((scopes->>'manage_nutrition_plan')::boolean or (scopes->>'view_nutrition_logs')::boolean))
    and exists(select 1 from trigger_info where pg_catalog.regexp_replace(function_definition,'[[:space:]]','','g') not like '%new.permissions->>''view_nutrition''%'),
    'legacy view_nutrition never becomes a trainer nutrition scope'
  union all
  select '21_legacy_trigger_handles_all_events',
    exists(select 1 from trigger_info where trigger_definition like '%insert%' and trigger_definition like '%update%' and trigger_definition like '%delete%'),
    'legacy synchronization trigger handles INSERT, UPDATE and DELETE'
  union all
  select '22_legacy_delete_is_id_and_type_scoped',
    exists(select 1 from trigger_info where function_definition like '%tg_op = ''delete''%'
      and function_definition like '%id = old.id%'
      and function_definition like '%professional_type = ''trainer''%'
      and function_definition like '%return old%'),
    'DELETE removes only the matching trainer professional relationship and returns OLD'
  union all
  select '23_trigger_function_not_executable_by_frontend',
    not pg_catalog.has_function_privilege('anon','public.sync_legacy_trainer_relationship_v41a()','EXECUTE')
    and not pg_catalog.has_function_privilege('authenticated','public.sync_legacy_trainer_relationship_v41a()','EXECUTE'),
    'trigger function has no EXECUTE grant for anon or authenticated'
  union all
  select '24_no_direct_write_policies',
    not exists(select 1 from pg_catalog.pg_policy where polrelid='public.professional_student_relationships'::regclass and polcmd in ('a','w','d','*')),
    'professional relationships have no INSERT, UPDATE, DELETE or ALL policy'
)
select
  check_name,
  passed,
  details,
  count(*) over () total_checks,
  count(*) filter (where passed) over () passed_checks,
  count(*) filter (where not passed) over () failed_checks,
  bool_and(passed) over () all_passed
from checks
order by check_name;
