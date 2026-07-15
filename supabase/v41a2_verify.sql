-- V4.1A.2 read-only verification. This file must never mutate database state.
with
functions as (
  select p.oid,p.proname,p.pronargs,p.prosecdef,
    lower(pg_catalog.pg_get_functiondef(p.oid)) definition,
    pg_catalog.regexp_replace(lower(pg_catalog.pg_get_functiondef(p.oid)),'[[:space:]]','','g') compact,
    exists(select 1 from unnest(p.proconfig) setting
      where pg_catalog.regexp_replace(setting,'[[:space:]]','','g') in ('search_path=','search_path=""')) empty_search_path
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'get_professional_active_client_count_v41a2','assert_professional_client_capacity_v41a2',
    'enforce_professional_client_limit_v41a2','get_my_professional_client_capacity',
    'get_my_commercial_account_context','create_trainer_student_invitation',
    'accept_trainer_student_invitation','sync_legacy_trainer_relationship_v41a'
  )
),
counter as (select * from functions where proname='get_professional_active_client_count_v41a2'),
capacity_assertion as (select * from functions where proname='assert_professional_client_capacity_v41a2'),
trigger_function as (select * from functions where proname='enforce_professional_client_limit_v41a2'),
capacity_rpc as (select * from functions where proname='get_my_professional_client_capacity'),
commercial_context as (select * from functions where proname='get_my_commercial_account_context'),
protection_trigger as (
  select lower(pg_catalog.pg_get_triggerdef(t.oid)) definition
  from pg_catalog.pg_trigger t
  where t.tgrelid='public.professional_student_relationships'::regclass
    and t.tgname='enforce_professional_client_limit_v41a2' and not t.tgisinternal
),
checks as (
  select '01_count_function_exists' check_name,to_regprocedure('public.get_professional_active_client_count_v41a2(uuid,text,uuid)') is not null passed,'internal distinct-client counter exists' details
  union all select '02_count_distinct_students',exists(select 1 from counter where compact like '%count(distinctrelationship.student_user_id)%'),'counter uses distinct students'
  union all select '03_active_status_only',exists(select 1 from counter where compact like '%relationship.status=''active''%'),'counter includes active status only'
  union all select '04_professional_types_separated',exists(select 1 from counter where compact like '%relationship.professional_type=target_professional_type%'),'counter filters professional type'
  union all select '05_capacity_assertion_exists',to_regprocedure('public.assert_professional_client_capacity_v41a2(uuid,text,uuid,uuid)') is not null,'capacity assertion exists'
  union all select '06_missing_account_blocked',exists(select 1 from capacity_assertion where definition like '%professional_account_required%'),'missing commercial account is blocked'
  union all select '07_primary_type_checked',exists(select 1 from capacity_assertion where compact like '%primary_account_type<>target_professional_type%' and definition like '%professional_account_type_mismatch%'),'primary type must match professional type'
  union all select '08_matching_active_plan_checked',exists(select 1 from capacity_assertion where compact like '%plan.code=account_record.plan_code%' and compact like '%plan.account_type=target_professional_type%' and compact like '%plan.is_active=true%'),'matching active catalog plan is required'
  union all select '09_subscription_status_checked',exists(select 1 from capacity_assertion where compact like '%subscription_statusnotin(''active'',''trialing'')%' and definition like '%professional_subscription_inactive%'),'only active or trialing may activate'
  union all select '10_limit_read_from_catalog',exists(select 1 from capacity_assertion where definition like '%plan.active_client_limit%'),'limit comes from catalog'
  union all select '11_commercial_row_locked',exists(select 1 from capacity_assertion where compact like '%frompublic.user_commercial_accountsaccount%' and compact like '%forupdate%'),'commercial row is locked before count'
  union all select '12_duplicate_student_not_recounted',exists(select 1 from capacity_assertion where compact like '%relationship.student_user_id=target_student_id%' and definition like '%then return%'),'already active student consumes no extra slot'
  union all select '13_trigger_exists',exists(select 1 from protection_trigger),'protection trigger exists'
  union all select '14_trigger_is_before',exists(select 1 from protection_trigger where definition like '%before insert%'),'trigger runs before mutation'
  union all select '15_trigger_handles_insert',exists(select 1 from protection_trigger where definition like '%before insert%'),'trigger handles INSERT'
  union all select '16_trigger_handles_required_updates',exists(select 1 from protection_trigger where definition like '%update of%' and definition like '%status%' and definition like '%professional_user_id%' and definition like '%professional_type%' and definition like '%student_user_id%'),'trigger covers activation identity columns'
  union all select '17_irrelevant_updates_not_blocked',exists(select 1 from trigger_function where compact like '%new.status=''active''and(%' and compact like '%old.statusisdistinctfrom''active''%' and compact like '%old.student_user_idisdistinctfromnew.student_user_id%'),'trigger validates only new activation or identity change'
  union all select '18_trigger_search_path_empty',exists(select 1 from trigger_function where empty_search_path),'trigger function has empty search_path'
  union all select '19_trigger_not_frontend_executable',not pg_catalog.has_function_privilege('anon','public.enforce_professional_client_limit_v41a2()','EXECUTE') and not pg_catalog.has_function_privilege('authenticated','public.enforce_professional_client_limit_v41a2()','EXECUTE'),'trigger function has no frontend EXECUTE'
  union all select '20_capacity_rpc_exists',to_regprocedure('public.get_my_professional_client_capacity()') is not null,'own capacity RPC exists'
  union all select '21_capacity_rpc_uses_auth_uid',exists(select 1 from capacity_rpc where definition like '%auth.uid()%'),'capacity RPC uses auth.uid()'
  union all select '22_capacity_rpc_has_no_user_argument',exists(select 1 from capacity_rpc where pronargs=0),'capacity RPC accepts no user id'
  union all select '23_capacity_rpc_authenticated_only',pg_catalog.has_function_privilege('authenticated','public.get_my_professional_client_capacity()','EXECUTE') and not pg_catalog.has_function_privilege('anon','public.get_my_professional_client_capacity()','EXECUTE'),'capacity RPC is authenticated-only'
  union all select '24_anon_cannot_execute_capacity',not pg_catalog.has_function_privilege('anon','public.get_my_professional_client_capacity()','EXECUTE'),'anon cannot read capacity'
  union all select '25_commercial_context_extended',exists(select 1 from commercial_context where definition like '%activeclientcount%' and definition like '%remainingslots%' and definition like '%limitreached%' and definition like '%canactivatenewclient%'),'commercial context includes capacity'
  union all select '26_free_plan_limits_preserved',exists(select 1 from public.account_plan_catalog where code='trainer_free' and account_type='trainer' and active_client_limit=5 and is_free) and exists(select 1 from public.account_plan_catalog where code='nutritionist_free' and account_type='nutritionist' and active_client_limit=5 and is_free),'free professional limits remain five'
  union all select '27_no_relationship_deletion',not exists(select 1 from functions where proname like '%v41a2%' and compact like '%deletefrompublic.professional_student_relationships%'),'V4.1A.2 functions delete no relationships'
  union all select '28_no_existing_status_rewrite',not exists(select 1 from functions where proname like '%v41a2%' and compact like '%updatepublic.professional_student_relationshipssetstatus=%'),'V4.1A.2 functions rewrite no existing status'
  union all select '29_no_counter_table',not exists(select 1 from information_schema.tables where table_schema='public' and table_name like '%client%count%'),'no duplicated counter table exists'
  union all select '30_no_paid_plan_created',(select count(*)=3 and bool_and(is_free) from public.account_plan_catalog),'catalog still contains only free plans'
  union all select '31_no_billing_rule_created',not exists(select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like '%v41a2%' and p.proname similar to '%(payment|checkout|billing|price|upgrade)%'),'no billing function was created'
  union all select '32_no_direct_relationship_writes',not pg_catalog.has_table_privilege('authenticated','public.professional_student_relationships','INSERT') and not pg_catalog.has_table_privilege('authenticated','public.professional_student_relationships','UPDATE') and not pg_catalog.has_table_privilege('authenticated','public.professional_student_relationships','DELETE'),'no direct relationship write was opened'
  union all select '33_legacy_flow_exists',to_regclass('public.trainer_student_relationships') is not null and to_regprocedure('public.accept_trainer_student_invitation(text)') is not null,'legacy trainer flow remains'
  union all select '34_legacy_sync_trigger_exists',exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.trainer_student_relationships'::regclass and tgname='sync_legacy_trainer_relationship_v41a' and not tgisinternal),'legacy synchronization trigger remains'
  union all select '35_organizations_unchanged',not exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.organizations'::regclass and tgname like '%v41a2%'),'no V4.1A.2 organization trigger exists'
  union all select '36_no_fake_users',not exists(select 1 from functions where proname like '%v41a2%' and (compact like '%insertintoauth.users%' or compact like '%insertintopublic.profiles%')),'V4.1A.2 functions create no users or profiles'
  union all select '37_all_new_functions_empty_search_path',(select count(*)=5 and bool_and(empty_search_path) from functions where proname in ('get_professional_active_client_count_v41a2','assert_professional_client_capacity_v41a2','enforce_professional_client_limit_v41a2','get_my_professional_client_capacity','get_my_commercial_account_context')),'all new or replaced functions have empty search_path'
  union all select '38_internal_helpers_not_executable',not pg_catalog.has_function_privilege('authenticated','public.get_professional_active_client_count_v41a2(uuid,text,uuid)','EXECUTE') and not pg_catalog.has_function_privilege('authenticated','public.assert_professional_client_capacity_v41a2(uuid,text,uuid,uuid)','EXECUTE') and not pg_catalog.has_function_privilege('anon','public.get_professional_active_client_count_v41a2(uuid,text,uuid)','EXECUTE'),'internal helpers are not frontend-executable'
  union all select '39_limit_not_hardcoded_in_enforcement',exists(select 1 from capacity_assertion where definition like '%active_client_limit%' and compact not like '%>=5%' and compact not like '%>5%'),'enforcement contains no hardcoded five'
  union all select '40_pending_invitation_creation_unblocked',exists(select 1 from functions where proname='create_trainer_student_invitation' and definition not like '%assert_professional_client_capacity_v41a2%'),'pending invitation creation does not consume capacity'
  union all select '41_legacy_acceptance_reaches_final_trigger',exists(select 1 from functions where proname='sync_legacy_trainer_relationship_v41a' and compact like '%insertintopublic.professional_student_relationships%'),'legacy acceptance synchronizes through protected table'
  union all select '42_limit_error_is_controlled',exists(select 1 from capacity_assertion where definition like '%professional_client_limit_reached%'),'limit uses controlled error code'
)
select check_name,passed,details,
  count(*) over() total_checks,
  count(*) filter(where passed) over() passed_checks,
  count(*) filter(where not passed) over() failed_checks,
  bool_and(passed) over() all_passed
from checks order by check_name;
