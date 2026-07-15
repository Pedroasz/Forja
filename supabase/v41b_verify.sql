-- V4.1B read-only verification. This file never mutates database state.
with
functions as (
  select p.oid,p.proname,p.pronargs,p.prosecdef,p.proowner,p.proacl,
    lower(pg_get_function_arguments(p.oid)) arguments,
    lower(pg_get_functiondef(p.oid)) definition,
    regexp_replace(lower(pg_get_functiondef(p.oid)),'[[:space:]]','','g') compact,
    exists(select 1 from unnest(p.proconfig) setting where regexp_replace(setting,'[[:space:]]','','g') in ('search_path=','search_path=""')) empty_search_path
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'validate_workout_plan_payload_v41b','assert_my_trainer_identity_v41b','assert_my_trainer_write_access_v41b','protect_workout_assignment_snapshot_v41b',
    'create_my_workout_template','update_my_workout_template','archive_my_workout_template','list_my_workout_templates',
    'list_my_manageable_workout_students','assign_workout_template_to_student','revoke_my_student_workout_assignment','list_my_assigned_workout_plans'
  )
),
validator as (select * from functions where proname='validate_workout_plan_payload_v41b'),
identity_helper as (select * from functions where proname='assert_my_trainer_identity_v41b'),
write_helper as (select * from functions where proname='assert_my_trainer_write_access_v41b'),
snapshot_trigger as (select * from functions where proname='protect_workout_assignment_snapshot_v41b'),
create_rpc as (select * from functions where proname='create_my_workout_template'),
update_rpc as (select * from functions where proname='update_my_workout_template'),
archive_rpc as (select * from functions where proname='archive_my_workout_template'),
template_list_rpc as (select * from functions where proname='list_my_workout_templates'),
student_manage_list_rpc as (select * from functions where proname='list_my_manageable_workout_students'),
assign_rpc as (select * from functions where proname='assign_workout_template_to_student'),
revoke_rpc as (select * from functions where proname='revoke_my_student_workout_assignment'),
student_list_rpc as (select * from functions where proname='list_my_assigned_workout_plans'),
public_rpcs as (
  select * from functions where proname in (
    'create_my_workout_template','update_my_workout_template','archive_my_workout_template','list_my_workout_templates',
    'list_my_manageable_workout_students','assign_workout_template_to_student','revoke_my_student_workout_assignment','list_my_assigned_workout_plans'
  )
),
template_constraints as (
  select conname,lower(pg_get_constraintdef(oid)) definition,regexp_replace(lower(pg_get_constraintdef(oid)),'[[:space:]]','','g') compact
  from pg_constraint where conrelid=to_regclass('public.professional_workout_templates')
),
assignment_constraints as (
  select conname,lower(pg_get_constraintdef(oid)) definition,regexp_replace(lower(pg_get_constraintdef(oid)),'[[:space:]]','','g') compact
  from pg_constraint where conrelid=to_regclass('public.student_workout_assignments')
),
policies as (
  select tablename,policyname,lower(coalesce(qual,'')) expression from pg_policies
  where schemaname='public' and tablename in ('professional_workout_templates','student_workout_assignments')
),
valid_payload as (
  select '{"schemaVersion":1,"splitType":"A","days":[{"code":"A","name":"Treino A","exercises":[]}]}'::jsonb value
),
validator_cases as (
  select
    public.validate_workout_plan_payload_v41b(value) accepts_one,
    not public.validate_workout_plan_payload_v41b(jsonb_set(value,'{schemaVersion}','0'::jsonb)) rejects_zero,
    not public.validate_workout_plan_payload_v41b(jsonb_set(value,'{schemaVersion}','-1'::jsonb)) rejects_negative,
    not public.validate_workout_plan_payload_v41b(jsonb_set(value,'{schemaVersion}','1.5'::jsonb)) and not public.validate_workout_plan_payload_v41b(jsonb_set(value,'{schemaVersion}','1.0'::jsonb)) rejects_decimal,
    not public.validate_workout_plan_payload_v41b(jsonb_set(value,'{schemaVersion}','2'::jsonb)) rejects_two,
    not public.validate_workout_plan_payload_v41b(jsonb_set(value,'{schemaVersion}','"1"'::jsonb)) rejects_string,
    not public.validate_workout_plan_payload_v41b(jsonb_set(value,'{schemaVersion}','null'::jsonb)) rejects_null
  from valid_payload
),
checks as (
  select '01_templates_table_exists' check_name,to_regclass('public.professional_workout_templates') is not null passed,'professional workout templates exists' details
  union all select '02_templates_rls_enabled',coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.professional_workout_templates')),false),'template RLS is enabled'
  union all select '03_template_owner_required',exists(select 1 from information_schema.columns where table_schema='public' and table_name='professional_workout_templates' and column_name='owner_user_id' and is_nullable='NO'),'owner_user_id is required'
  union all select '04_template_status_validated',exists(select 1 from template_constraints where definition like '%status%' and definition like '%active%' and definition like '%archived%'),'template status is constrained'
  union all select '05_template_plan_validated',exists(select 1 from template_constraints where definition like '%validate_workout_plan_payload_v41b%'),'template plan_data uses validator'
  union all select '06_no_direct_template_writes',not has_table_privilege('authenticated','public.professional_workout_templates','INSERT') and not has_table_privilege('authenticated','public.professional_workout_templates','UPDATE') and not has_table_privilege('authenticated','public.professional_workout_templates','DELETE'),'authenticated has no direct template writes'
  union all select '07_anon_no_template_access',not has_table_privilege('anon','public.professional_workout_templates','SELECT') and not has_table_privilege('anon','public.professional_workout_templates','INSERT') and not has_table_privilege('anon','public.professional_workout_templates','UPDATE') and not has_table_privilege('anon','public.professional_workout_templates','DELETE'),'anon has no template access'
  union all select '08_assignments_table_exists',to_regclass('public.student_workout_assignments') is not null,'student workout assignments exists'
  union all select '09_assignments_rls_enabled',coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.student_workout_assignments')),false),'assignment RLS is enabled'
  union all select '10_relationship_required',exists(select 1 from information_schema.columns where table_schema='public' and table_name='student_workout_assignments' and column_name='relationship_id' and is_nullable='NO'),'relationship_id is required'
  union all select '11_assignment_versions_positive',exists(select 1 from assignment_constraints where definition like '%assignment_version >= 1%'),'assignment versions are positive'
  union all select '12_relationship_version_unique',exists(select 1 from assignment_constraints where definition like '%unique (relationship_id, assignment_version)%'),'relationship and version are unique'
  union all select '13_one_active_assignment',exists(select 1 from pg_indexes where schemaname='public' and tablename='student_workout_assignments' and indexdef ilike '%unique%' and indexdef ilike '%(relationship_id)%' and indexdef ilike '%where (status = ''active''%'),'only one active assignment per relationship'
  union all select '14_snapshots_required',(select count(*)=3 from information_schema.columns where table_schema='public' and table_name='student_workout_assignments' and column_name in ('title_snapshot','plan_data_snapshot','schema_version') and is_nullable='NO'),'required snapshot fields are non-null'
  union all select '15_assignment_status_validated',exists(select 1 from assignment_constraints where definition like '%active%' and definition like '%superseded%' and definition like '%revoked%'),'assignment status is constrained'
  union all select '16_no_direct_assignment_writes',not has_table_privilege('authenticated','public.student_workout_assignments','INSERT') and not has_table_privilege('authenticated','public.student_workout_assignments','UPDATE') and not has_table_privilege('authenticated','public.student_workout_assignments','DELETE'),'authenticated has no direct assignment writes'
  union all select '17_student_reads_own_relationship',exists(select 1 from policies where tablename='student_workout_assignments' and expression like '%student_user_id = auth.uid()%'),'student policy checks own relationship'
  union all select '18_trainer_reads_own_relationship',exists(select 1 from policies where tablename='student_workout_assignments' and expression like '%professional_user_id = auth.uid()%'),'trainer policy checks own relationship'
  union all select '19_organization_alone_not_authority',not exists(select 1 from policies where tablename='student_workout_assignments' and expression like '%organization_id%' and expression not like '%professional_user_id%' and expression not like '%student_user_id%'),'organization alone grants no assignment access'
  union all select '20_payload_validator_exists',to_regprocedure('public.validate_workout_plan_payload_v41b(jsonb)') is not null,'payload validator exists'
  union all select '21_schema_version_accepts_only_one',(select accepts_one and rejects_zero and rejects_negative and rejects_decimal and rejects_two and rejects_string and rejects_null from validator_cases),'validator accepts numeric 1 and rejects zero, negative, decimal, 2, string and null'
  union all select '22_template_schema_version_exact',exists(select 1 from template_constraints where conname='professional_workout_templates_schema_version_check' and compact like '%schema_version=1%' and compact like '%schema_version=((plan_data->>''schemaversion''::text))::integer%'),'template schema version is exactly one and matches JSON'
  union all select '23_assignment_schema_version_exact',exists(select 1 from assignment_constraints where conname='student_workout_assignments_schema_version_check' and compact like '%schema_version=1%' and compact like '%schema_version=((plan_data_snapshot->>''schemaversion''::text))::integer%'),'assignment schema version is exactly one and matches JSON snapshot'
  union all select '24_split_and_exercises_validated',exists(select 1 from validator where compact like '%splittype%' and compact like '%day_countnotbetween1and5%' and compact like '%exercise_count>50%'),'split, day and exercise payload are bounded'
  union all select '25_create_template_rpc_exists',to_regprocedure('public.create_my_workout_template(text,text,jsonb,uuid)') is not null,'create template RPC exists'
  union all select '26_update_template_rpc_exists',to_regprocedure('public.update_my_workout_template(uuid,text,text,jsonb)') is not null,'update template RPC exists'
  union all select '27_archive_template_rpc_exists',to_regprocedure('public.archive_my_workout_template(uuid)') is not null,'archive template RPC exists'
  union all select '28_list_templates_rpc_exists',to_regprocedure('public.list_my_workout_templates()') is not null,'list templates RPC exists'
  union all select '29_list_students_rpc_exists',to_regprocedure('public.list_my_manageable_workout_students()') is not null,'manageable students RPC exists'
  union all select '30_assign_rpc_exists',to_regprocedure('public.assign_workout_template_to_student(uuid,uuid,date)') is not null,'assignment RPC exists'
  union all select '31_assign_uses_auth_uid',exists(select 1 from assign_rpc where compact like '%professional_user_id=auth.uid()%'),'assignment derives trainer from auth.uid()'
  union all select '32_structural_trainer_authority',exists(select 1 from identity_helper where compact like '%primary_account_type=''trainer''%') and exists(select 1 from assign_rpc where compact like '%professional_type=''trainer''%' and compact like '%professional_user_id=auth.uid()%') and not exists(select 1 from public_rpcs where arguments like '%professional_user_id%'),'identity and assignment require the authenticated trainer; no RPC accepts arbitrary professional_user_id'
  union all select '33_assign_requires_active_relationship',exists(select 1 from assign_rpc where compact like '%relationship_record.status<>''active''%'),'assignment requires active relationship'
  union all select '34_assign_requires_manage_scope',exists(select 1 from assign_rpc where compact like '%manage_workout_plan%' and compact like '%workout_scope_required%'),'assignment requires manage_workout_plan'
  union all select '35_assign_validates_organization_match',exists(select 1 from assign_rpc where compact like '%template_record.organization_idisdistinctfromrelationship_record.organization_id%' and compact like '%workout_organization_mismatch%'),'assignment validates organization context'
  union all select '36_assign_locks_concurrency',exists(select 1 from assign_rpc where compact like '%forupdate%'),'assignment uses row locks'
  union all select '37_assign_creates_version',exists(select 1 from assign_rpc where compact like '%max(assignment_version)%' and compact like '%next_version%'),'assignment calculates next version'
  union all select '38_assign_supersedes_previous',exists(select 1 from assign_rpc where compact like '%status=''superseded''%' and compact like '%superseded_at=now()%' and compact like '%status=''active''%'),'previous active assignment is superseded with timestamp'
  union all select '39_revoke_rpc_exists',to_regprocedure('public.revoke_my_student_workout_assignment(uuid)') is not null,'revoke RPC exists'
  union all select '40_revoke_preserves_history',exists(select 1 from revoke_rpc where compact not like '%deletefrom%' and compact like '%status=''revoked''%' and compact like '%revoked_at=now()%' and compact like '%superseded_at=null%'),'revoke updates status and timestamps without delete'
  union all select '41_student_list_rpc_exists',to_regprocedure('public.list_my_assigned_workout_plans()') is not null,'student list RPC exists'
  union all select '42_student_list_uses_auth_uid',exists(select 1 from student_list_rpc where compact like '%student_user_id=auth.uid()%'),'student list derives current user'
  union all select '43_no_arbitrary_professional_authority',exists(select 1 from identity_helper where compact like '%primary_account_type=''trainer''%') and exists(select 1 from assign_rpc where compact like '%professional_type=''trainer''%' and compact like '%professional_user_id=auth.uid()%') and not exists(select 1 from public_rpcs where arguments like '%professional_user_id%'),'trainer identity, relationship type and ownership are structural; public RPCs accept no arbitrary professional id'
  union all select '44_student_no_write_rpc',not exists(select 1 from public_rpcs where proname not in ('list_my_manageable_workout_students','list_my_assigned_workout_plans') and compact like '%student_user_id=auth.uid()%'),'student receives no assignment writer'
  union all select '45_identity_helper_ignores_subscription',exists(select 1 from identity_helper where compact not like '%subscription_status%' and compact not like '%is_active%'),'identity helper does not require active subscription or plan'
  union all select '46_write_helper_requires_subscription',exists(select 1 from write_helper where
    compact like '%assert_my_trainer_identity_v41b()%' and
    compact like '%frompublic.user_commercial_accounts%' and compact like '%public.account_plan_catalog%' and
    (compact ~ '\.code[^=;]{0,30}=[^;]{0,30}\.plan_code' or compact ~ '\.plan_code[^=;]{0,30}=[^;]{0,30}\.code') and
    (compact ~ '\.account_type[^=;]{0,30}=[^;]{0,30}\.primary_account_type' or compact ~ '\.primary_account_type[^=;]{0,30}=[^;]{0,30}\.account_type') and
    compact like '%user_id=auth.uid()%' and compact like '%primary_account_type=''trainer''%' and
    compact like '%is_active%' and (compact ~ 'is_active[^;]{0,40}(isnottrue|<>true|=false)' or compact ~ '(ifnot|not\()[^;]{0,40}is_active' or compact ~ 'is_active[^;]{0,40}(=true|istrue)' or compact ~ 'coalesce\([^;]{0,40}is_active[^;]{0,40}false') and
    (compact like '%subscription_statusisnull%' or compact like '%coalesce(%subscription_status%') and
    (compact ~ 'subscription_status[^;]{0,120}''active''[^;]{0,60}''trialing''' or compact ~ 'subscription_status[^;]{0,120}''trialing''[^;]{0,60}''active''') and
    compact like '%trainer_plan_unavailable%' and compact like '%trainer_subscription_inactive%'
  ),'write helper structurally requires trainer identity, matching active plan and active or trialing subscription'
  union all select '47_template_list_uses_identity_only',exists(select 1 from template_list_rpc where compact like '%assert_my_trainer_identity_v41b()%' and compact not like '%assert_my_trainer_write_access_v41b()%'),'template reading remains available with inactive subscription'
  union all select '48_student_list_uses_identity_only',exists(select 1 from student_manage_list_rpc where compact like '%assert_my_trainer_identity_v41b()%' and compact not like '%assert_my_trainer_write_access_v41b()%'),'manageable-student reading remains available with inactive subscription'
  union all select '49_create_requires_write_access',exists(select 1 from create_rpc where compact like '%assert_my_trainer_write_access_v41b()%'),'create requires write access'
  union all select '50_update_requires_write_access',exists(select 1 from update_rpc where compact like '%assert_my_trainer_write_access_v41b()%'),'update requires write access'
  union all select '51_assign_requires_write_access',exists(select 1 from assign_rpc where compact like '%assert_my_trainer_write_access_v41b()%'),'assignment requires write access'
  union all select '52_archive_uses_identity_only',exists(select 1 from archive_rpc where compact like '%assert_my_trainer_identity_v41b()%' and compact not like '%assert_my_trainer_write_access_v41b()%'),'archive remains a reduction action'
  union all select '53_revoke_uses_identity_only',exists(select 1 from revoke_rpc where compact like '%assert_my_trainer_identity_v41b()%' and compact not like '%assert_my_trainer_write_access_v41b()%' and compact like '%professional_type=''trainer''%' and compact like '%professional_user_id=auth.uid()%'),'revoke remains available to the owning trainer with inactive subscription'
  union all select '54_create_org_roles_allowed',exists(select 1 from create_rpc where compact like '%membership.status=''active''%' and compact like '%membership.rolein(''owner'',''admin'',''trainer'')%'),'organization templates accept active owner, admin or trainer membership'
  union all select '55_create_org_roles_exclude_others',exists(select 1 from create_rpc where compact like '%membership.rolein(''owner'',''admin'',''trainer'')%') and not exists(select 1 from create_rpc where compact like '%membership.rolein(%nutritionist%' or compact like '%membership.rolein(%student%'),'nutritionist and student memberships are not accepted'
  union all select '56_assign_revalidates_org_membership',exists(select 1 from assign_rpc where compact like '%frompublic.organization_members%' and compact like '%membership.status=''active''%' and compact like '%membership.rolein(''owner'',''admin'',''trainer'')%' and compact like '%forshare%'),'assignment revalidates and locks active organization membership'
  union all select '57_student_rpc_relationship_status',exists(select 1 from student_list_rpc where compact like '%''relationshipstatus'',relationship.status%'),'student RPC returns relationshipStatus'
  union all select '58_student_rpc_can_start',exists(select 1 from student_list_rpc where compact like '%''canstart''%'),'student RPC returns canStart'
  union all select '59_can_start_requires_active_assignment',exists(select 1 from student_list_rpc where compact like '%assignment.status=''active''%'),'canStart requires active assignment'
  union all select '60_can_start_requires_active_relationship',exists(select 1 from student_list_rpc where compact like '%relationship.status=''active''%'),'canStart requires active relationship'
  union all select '61_can_start_requires_trainer_relationship',exists(select 1 from student_list_rpc where compact like '%relationship.professional_type=''trainer''%'),'canStart requires trainer relationship'
  union all select '62_can_start_requires_scope',exists(select 1 from student_list_rpc where compact like '%manage_workout_plan%' and compact like '%::boolean,false)%'),'canStart requires manage_workout_plan'
  union all select '63_can_start_respects_effective_from',exists(select 1 from student_list_rpc where compact like '%assignment.effective_fromisnullorassignment.effective_from<=current_date%'),'canStart permits null or reached civil effective date'
  union all select '64_status_timestamps_constraint_named',exists(select 1 from assignment_constraints where conname='student_workout_assignments_status_timestamps_check'),'stable status/timestamp constraint exists'
  union all select '65_active_timestamps_null',exists(select 1 from assignment_constraints where conname='student_workout_assignments_status_timestamps_check' and compact like '%status=''active''%superseded_atisnull%revoked_atisnull%'),'active status requires null terminal timestamps'
  union all select '66_superseded_timestamp_required',exists(select 1 from assignment_constraints where conname='student_workout_assignments_status_timestamps_check' and compact like '%status=''superseded''%superseded_atisnotnull%revoked_atisnull%'),'superseded status requires only superseded_at'
  union all select '67_revoked_timestamp_required',exists(select 1 from assignment_constraints where conname='student_workout_assignments_status_timestamps_check' and compact like '%status=''revoked''%revoked_atisnotnull%superseded_atisnull%'),'revoked status requires only revoked_at'
  union all select '68_terminal_status_cannot_reactivate',exists(select 1 from snapshot_trigger where compact like '%old.status<>''active''%' and compact like '%workout_assignment_status_immutable%'),'terminal assignments cannot return to active or change status timestamps'
  union all select '69_snapshots_immutable',to_regprocedure('public.protect_workout_assignment_snapshot_v41b()') is not null and exists(select 1 from snapshot_trigger where compact like '%old.plan_data_snapshotisdistinctfromnew.plan_data_snapshot%' and compact like '%old.assigned_atisdistinctfromnew.assigned_at%') and exists(select 1 from pg_trigger where tgrelid=to_regclass('public.student_workout_assignments') and tgname='protect_workout_assignment_snapshot_v41b' and not tgisinternal),'snapshot and assigned_at immutability trigger exists'
  union all select '70_internal_functions_not_executable',not has_function_privilege('authenticated','public.validate_workout_plan_payload_v41b(jsonb)','EXECUTE') and not has_function_privilege('authenticated','public.assert_my_trainer_identity_v41b()','EXECUTE') and not has_function_privilege('authenticated','public.assert_my_trainer_write_access_v41b()','EXECUTE') and not has_function_privilege('authenticated','public.protect_workout_assignment_snapshot_v41b()','EXECUTE'),'all internal functions are not frontend-executable'
  union all select '71_public_rpcs_authenticated_only',(select count(*)=8 and bool_and(has_function_privilege('authenticated',oid,'EXECUTE') and not has_function_privilege('anon',oid,'EXECUTE')) from public_rpcs),'eight frontend RPCs are authenticated-only'
  union all select '72_all_functions_empty_search_path',(select count(*)=12 and bool_and(empty_search_path) from functions),'all twelve V4.1B functions use empty search_path'
  union all select '73_template_owner_policy',exists(select 1 from policies where tablename='professional_workout_templates' and expression like '%owner_user_id = auth.uid()%'),'template owner policy uses auth.uid()'
  union all select '74_anon_no_assignment_access',not has_table_privilege('anon','public.student_workout_assignments','SELECT') and not has_table_privilege('anon','public.student_workout_assignments','INSERT') and not has_table_privilege('anon','public.student_workout_assignments','UPDATE') and not has_table_privilege('anon','public.student_workout_assignments','DELETE'),'anon has no assignment access'
  union all select '75_public_has_no_function_execute',not exists(select 1 from functions function_row cross join lateral aclexplode(coalesce(function_row.proacl,acldefault('f',function_row.proowner))) acl where acl.grantee=0 and acl.privilege_type='EXECUTE'),'PUBLIC has no EXECUTE on V4.1B functions'
  union all select '76_old_executions_unchanged',not exists(select 1 from information_schema.columns where table_schema='public' and table_name='workouts' and column_name like '%assignment%'),'existing workouts table was not altered'
  union all select '77_personal_workouts_unchanged',not exists(select 1 from functions where compact like '%updatepublic.workouts%' or compact like '%deletefrompublic.workouts%'),'personal workouts are untouched'
  union all select '78_no_relationship_created',not exists(select 1 from functions where compact like '%insertintopublic.professional_student_relationships%'),'no professional relationship is created'
  union all select '79_no_fake_user_created',not exists(select 1 from functions where compact like '%insertintoauth.users%' or compact like '%insertintopublic.profiles%'),'no user or profile is created'
  union all select '80_no_nutrition_or_billing_created',not exists(select 1 from functions where compact like '%nutrition_plan%' or proname similar to '%(payment|checkout|billing|price|upgrade)%'),'V4.1B creates no nutrition or billing flow'
  union all select '81_authenticated_select_only',has_table_privilege('authenticated','public.professional_workout_templates','SELECT') and has_table_privilege('authenticated','public.student_workout_assignments','SELECT'),'authenticated has SELECT on both V4.1B tables'
  union all select '82_no_direct_writes_for_frontend_roles',not exists(select 1 from information_schema.table_privileges where table_schema='public' and table_name in ('professional_workout_templates','student_workout_assignments') and grantee in ('PUBLIC','anon','authenticated') and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')),'PUBLIC, anon and authenticated have no direct writes on V4.1B tables'
  union all select '83_old_combined_helper_removed',to_regprocedure('public.assert_my_trainer_account_v41b()') is null,'obsolete combined identity and billing helper is absent'
)
select check_name,passed,details,
  count(*) over() total_checks,
  count(*) filter(where passed) over() passed_checks,
  count(*) filter(where not passed) over() failed_checks,
  bool_and(passed) over() all_passed
from checks order by check_name;
