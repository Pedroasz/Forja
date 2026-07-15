-- V4.0B2 read-only verification. Run only after the migration.

-- 1. Expected: two tables.
select table_name from information_schema.tables where table_schema='public' and table_name in ('user_account_modes','trainer_student_invitations') order by table_name;

-- 2. Expected: all documented columns, with no plaintext invite_code column.
select table_name,column_name,data_type,is_nullable,column_default from information_schema.columns
where table_schema='public' and table_name in ('user_account_modes','trainer_student_invitations') order by table_name,ordinal_position;

-- 3. Expected: PK, FK, CHECK and UNIQUE constraints.
select conrelid::regclass as table_name,conname,contype,pg_get_constraintdef(oid) as definition from pg_constraint
where conrelid in ('public.user_account_modes'::regclass,'public.trainer_student_invitations'::regclass) order by conrelid::regclass::text,conname;

-- 4. Expected: user/mode and invitation lookup indexes, including unique hash.
select tablename,indexname,indexdef from pg_indexes where schemaname='public' and tablename in ('user_account_modes','trainer_student_invitations') order by tablename,indexname;

-- 5. Expected: RLS enabled on both tables.
select relname,relrowsecurity from pg_class where oid in ('public.user_account_modes'::regclass,'public.trainer_student_invitations'::regclass) order by relname;

-- 6. Expected: SELECT policies only, to authenticated.
select tablename,policyname,cmd,roles,qual,with_check from pg_policies where schemaname='public' and tablename in ('user_account_modes','trainer_student_invitations') order by tablename;

-- 7. Expected: zero rows; no anon/public policy.
select tablename,policyname,roles from pg_policies where schemaname='public' and tablename in ('user_account_modes','trainer_student_invitations') and (roles @> array['anon']::name[] or roles @> array['public']::name[]);

-- 8. Expected: zero rows; no direct table writes.
select grantee,table_name,privilege_type from information_schema.role_table_grants where table_schema='public' and table_name in ('user_account_modes','trainer_student_invitations') and grantee in ('anon','authenticated') and privilege_type in ('INSERT','UPDATE','DELETE');

-- 9. Expected: nine functions (normalizer, modes, invitation flows, list connections).
select p.proname,pg_get_function_identity_arguments(p.oid) as arguments,pg_get_function_result(p.oid) as result
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('normalize_invitation_code','get_my_account_modes','set_my_account_modes','create_trainer_student_invitation','preview_trainer_invitation','accept_trainer_student_invitation','cancel_trainer_invitation','list_my_trainer_invitations','list_my_trainer_student_connections') order by p.proname;

-- 10 and 11. Expected: the eight RPCs are SECURITY DEFINER; the internal normalizer is not. Every function has empty search_path.
select p.proname,p.prosecdef as security_definer,coalesce((select setting from unnest(p.proconfig) setting where setting like 'search_path=%' limit 1),'') as search_path_setting
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('normalize_invitation_code','get_my_account_modes','set_my_account_modes','create_trainer_student_invitation','preview_trainer_invitation','accept_trainer_student_invitation','cancel_trainer_invitation','list_my_trainer_invitations','list_my_trainer_student_connections') order by p.proname;

-- 12. Expected: anon false; authenticated true only for the eight frontend RPCs (normalizer remains internal).
select p.proname,has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('normalize_invitation_code','get_my_account_modes','set_my_account_modes','create_trainer_student_invitation','preview_trainer_invitation','accept_trainer_student_invitation','cancel_trainer_invitation','list_my_trainer_invitations','list_my_trainer_student_connections') order by p.proname;

-- 13. Expected: zero rows. No column stores the complete invitation code.
select column_name from information_schema.columns where table_schema='public' and table_name='trainer_student_invitations' and column_name in ('invite_code','code','full_code','normalized_code');

-- 14. Expected: invite_code_hash UNIQUE.
select conname,pg_get_constraintdef(oid) as definition from pg_constraint where conrelid='public.trainer_student_invitations'::regclass and contype='u' and pg_get_constraintdef(oid) like '%invite_code_hash%';

-- 15. Expected: creation function contains interval '7 days'.
select position('7 days' in pg_get_functiondef(p.oid))>0 as seven_day_expiry from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='create_trainer_student_invitation';

-- 16. Expected: all five relationship permission defaults are false during acceptance.
with normalized_function as (
  select regexp_replace(lower(pg_get_functiondef(p.oid)), '[[:space:]]+', '', 'g') as definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='accept_trainer_student_invitation'
)
select position('''view_workouts'',false' in definition)>0 as workouts_false,
       position('''assign_workouts'',false' in definition)>0 as assign_false,
       position('''view_executions'',false' in definition)>0 as executions_false,
       position('''view_evolution'',false' in definition)>0 as evolution_false,
       position('''view_nutrition'',false' in definition)>0 as nutrition_false
from normalized_function;

-- 17. Expected: account mode CHECK contains only individual/student/trainer and no privileged role.
select conname,pg_get_constraintdef(oid) as definition from pg_constraint where conrelid='public.user_account_modes'::regclass and contype='c';

-- 18. Expected immediately after migration: both counts zero (no fictitious data).
select (select count(*) from public.user_account_modes) as account_modes_count,(select count(*) from public.trainer_student_invitations) as invitations_count;

-- 19. Expected: unchanged from before migration; V4.0B2 creates no organization.
select count(*) as organizations_count from public.organizations;

-- 20. Expected: unchanged from before migration; V4.0B2 creates no relationship.
select count(*) as relationships_count from public.trainer_student_relationships;

-- 21. Expected: authenticated can SELECT modes but cannot SELECT invitations directly; anon can SELECT neither.
select
  has_table_privilege('authenticated','public.user_account_modes','SELECT') as authenticated_modes_select,
  has_table_privilege('authenticated','public.trainer_student_invitations','SELECT') as authenticated_invitations_select,
  has_table_privilege('anon','public.user_account_modes','SELECT') as anon_modes_select,
  has_table_privilege('anon','public.trainer_student_invitations','SELECT') as anon_invitations_select;

-- 22. Expected: false. invite_code_hash is not selectable by the authenticated frontend.
select has_column_privilege('authenticated','public.trainer_student_invitations','invite_code_hash','SELECT') as authenticated_can_select_invite_hash;

-- 23. Expected: preserves_active_permissions = true and preserves_active_accepted_at = true.
select
  lower(pg_get_functiondef(p.oid)) ~ 'when[[:space:]]+public\.trainer_student_relationships\.status[[:space:]]*=[[:space:]]*''active''[[:space:]]+then[[:space:]]+public\.trainer_student_relationships\.permissions' as preserves_active_permissions,
  lower(pg_get_functiondef(p.oid)) ~ 'when[[:space:]]+public\.trainer_student_relationships\.status[[:space:]]*=[[:space:]]*''active''[[:space:]]+then[[:space:]]+public\.trainer_student_relationships\.accepted_at' as preserves_active_accepted_at
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='accept_trainer_student_invitation';

-- 24. Expected: trainer_mode_lock_precedes_limit_count = true.
select
  position('for update' in lower(pg_get_functiondef(p.oid)))>0
  and position('for update' in lower(pg_get_functiondef(p.oid))) < position('count(*)' in lower(pg_get_functiondef(p.oid)))
  as trainer_mode_lock_precedes_limit_count
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='create_trainer_student_invitation';

-- 25. Expected: derives_expired_status = true.
select
  lower(pg_get_functiondef(p.oid)) ~ 'status[[:space:]]*=[[:space:]]*''pending'''
  and lower(pg_get_functiondef(p.oid)) ~ 'expires_at[[:space:]]*<=[[:space:]]*now\(\)'
  and lower(pg_get_functiondef(p.oid)) ~ 'then[[:space:]]+''expired'''
  as derives_expired_status
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='list_my_trainer_invitations';

-- 26. Expected: expired_invitation_cannot_be_cancelled = true.
select lower(pg_get_functiondef(p.oid)) ~ 'expires_at[[:space:]]*>[[:space:]]*now\(\)' as expired_invitation_cannot_be_cancelled
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='cancel_trainer_invitation';

-- Consolidated result: one row per check plus overall totals.
with
expected_functions(name) as (values
  ('normalize_invitation_code'),('get_my_account_modes'),('set_my_account_modes'),
  ('create_trainer_student_invitation'),('preview_trainer_invitation'),
  ('accept_trainer_student_invitation'),('cancel_trainer_invitation'),
  ('list_my_trainer_invitations'),('list_my_trainer_student_connections')
),
function_info as (
  select p.oid,p.proname,p.prosecdef,p.proconfig,lower(pg_get_functiondef(p.oid)) as definition,
         exists(select 1 from unnest(p.proconfig) setting where regexp_replace(setting,'[[:space:]]','','g') in ('search_path=','search_path=""')) as empty_search_path
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (select name from expected_functions)
),
checks(check_name,passed,details) as (
  select '01_tables_exist',count(*)=2,format('%s of 2 tables found',count(*))
  from information_schema.tables where table_schema='public' and table_name in ('user_account_modes','trainer_student_invitations')
  union all
  select '02_columns_match',
    count(*) filter(where table_name='user_account_modes')=5 and count(*) filter(where table_name='trainer_student_invitations')=11
      and count(*) filter(where column_name in ('invite_code','code','full_code','normalized_code'))=0,
    format('modes=%s invitations=%s plaintext_code_columns=%s',count(*) filter(where table_name='user_account_modes'),count(*) filter(where table_name='trainer_student_invitations'),count(*) filter(where column_name in ('invite_code','code','full_code','normalized_code')))
  from information_schema.columns where table_schema='public' and table_name in ('user_account_modes','trainer_student_invitations')
  union all
  select '03_constraints_exist',count(*)>=9,format('%s constraints found',count(*)) from pg_constraint where conrelid in ('public.user_account_modes'::regclass,'public.trainer_student_invitations'::regclass)
  union all
  select '04_indexes_exist',count(*)>=7,format('%s indexes found',count(*)) from pg_indexes where schemaname='public' and tablename in ('user_account_modes','trainer_student_invitations')
  union all
  select '05_rls_enabled',count(*)=2 and bool_and(relrowsecurity),format('%s tables checked; all_enabled=%s',count(*),coalesce(bool_and(relrowsecurity),false)) from pg_class where oid in ('public.user_account_modes'::regclass,'public.trainer_student_invitations'::regclass)
  union all
  select '06_select_policies_only',count(*)=2 and bool_and(cmd='SELECT' and roles=array['authenticated']::name[]),format('%s policies; valid=%s',count(*),coalesce(bool_and(cmd='SELECT' and roles=array['authenticated']::name[]),false)) from pg_policies where schemaname='public' and tablename in ('user_account_modes','trainer_student_invitations')
  union all
  select '07_no_anon_policies',count(*)=0,format('%s anon/public policies found',count(*)) from pg_policies where schemaname='public' and tablename in ('user_account_modes','trainer_student_invitations') and (roles @> array['anon']::name[] or roles @> array['public']::name[])
  union all
  select '08_no_direct_writes',count(*)=0,format('%s direct write grants found',count(*)) from information_schema.role_table_grants where table_schema='public' and table_name in ('user_account_modes','trainer_student_invitations') and grantee in ('anon','authenticated') and privilege_type in ('INSERT','UPDATE','DELETE')
  union all
  select '09_functions_exist',count(*)=9,format('%s of 9 functions found',count(*)) from function_info
  union all
  select '10_security_definer_configuration',count(*)=9 and count(*) filter(where proname='normalize_invitation_code' and not prosecdef)=1 and count(*) filter(where proname<>'normalize_invitation_code' and prosecdef)=8,format('normalizer_invoker=%s security_definer_rpcs=%s',count(*) filter(where proname='normalize_invitation_code' and not prosecdef),count(*) filter(where proname<>'normalize_invitation_code' and prosecdef)) from function_info
  union all
  select '11_empty_search_path',count(*)=9 and bool_and(empty_search_path),format('%s functions; all_empty=%s',count(*),coalesce(bool_and(empty_search_path),false)) from function_info
  union all
  select '12_function_execute_grants',count(*)=9 and bool_and(not has_function_privilege('anon',oid,'EXECUTE')) and count(*) filter(where proname='normalize_invitation_code' and not has_function_privilege('authenticated',oid,'EXECUTE'))=1 and count(*) filter(where proname<>'normalize_invitation_code' and has_function_privilege('authenticated',oid,'EXECUTE'))=8,format('anon_execute=%s authenticated_rpcs=%s normalizer_authenticated=%s',count(*) filter(where has_function_privilege('anon',oid,'EXECUTE')),count(*) filter(where proname<>'normalize_invitation_code' and has_function_privilege('authenticated',oid,'EXECUTE')),count(*) filter(where proname='normalize_invitation_code' and has_function_privilege('authenticated',oid,'EXECUTE'))) from function_info
  union all
  select '13_no_plaintext_code_column',count(*)=0,format('%s plaintext code columns found',count(*)) from information_schema.columns where table_schema='public' and table_name='trainer_student_invitations' and column_name in ('invite_code','code','full_code','normalized_code')
  union all
  select '14_invite_hash_unique',count(*)=1,format('%s matching unique constraints',count(*)) from pg_constraint where conrelid='public.trainer_student_invitations'::regclass and contype='u' and pg_get_constraintdef(oid) like '%invite_code_hash%'
  union all
  select '15_seven_day_expiry',coalesce(bool_or(definition like '%7 days%'),false),format('configured=%s',coalesce(bool_or(definition like '%7 days%'),false)) from function_info where proname='create_trainer_student_invitation'
  union all
  select '16_permissions_default_false',coalesce(bool_or(regexp_replace(definition,'[[:space:]]+','','g') like '%''view_workouts'',false%' and regexp_replace(definition,'[[:space:]]+','','g') like '%''assign_workouts'',false%' and regexp_replace(definition,'[[:space:]]+','','g') like '%''view_executions'',false%' and regexp_replace(definition,'[[:space:]]+','','g') like '%''view_evolution'',false%' and regexp_replace(definition,'[[:space:]]+','','g') like '%''view_nutrition'',false%'),false),format('all_five_false=%s',coalesce(bool_or(regexp_replace(definition,'[[:space:]]+','','g') like '%''view_workouts'',false%' and regexp_replace(definition,'[[:space:]]+','','g') like '%''assign_workouts'',false%' and regexp_replace(definition,'[[:space:]]+','','g') like '%''view_executions'',false%' and regexp_replace(definition,'[[:space:]]+','','g') like '%''view_evolution'',false%' and regexp_replace(definition,'[[:space:]]+','','g') like '%''view_nutrition'',false%'),false)) from function_info where proname='accept_trainer_student_invitation'
  union all
  select '17_account_modes_restricted',count(*)=1 and bool_and(pg_get_constraintdef(oid) like '%individual%' and pg_get_constraintdef(oid) like '%student%' and pg_get_constraintdef(oid) like '%trainer%' and pg_get_constraintdef(oid) not similar to '%(owner|admin|support|platform_admin|gym_admin)%'),format('%s valid mode constraints',count(*)) from pg_constraint where conrelid='public.user_account_modes'::regclass and contype='c'
  union all
  select '18_no_fictitious_b2_data',(select count(*) from public.user_account_modes)=0 and (select count(*) from public.trainer_student_invitations)=0,format('account_modes=%s invitations=%s',(select count(*) from public.user_account_modes),(select count(*) from public.trainer_student_invitations))
  union all
  select '19_no_organizations_created',count(*)=0,format('organizations=%s',count(*)) from public.organizations
  union all
  select '20_no_relationships_created',count(*)=0,format('relationships=%s',count(*)) from public.trainer_student_relationships
  union all
  select '21_table_select_privileges',has_table_privilege('authenticated','public.user_account_modes','SELECT') and not has_table_privilege('authenticated','public.trainer_student_invitations','SELECT') and not has_table_privilege('anon','public.user_account_modes','SELECT') and not has_table_privilege('anon','public.trainer_student_invitations','SELECT'),format('auth_modes=%s auth_invites=%s anon_modes=%s anon_invites=%s',has_table_privilege('authenticated','public.user_account_modes','SELECT'),has_table_privilege('authenticated','public.trainer_student_invitations','SELECT'),has_table_privilege('anon','public.user_account_modes','SELECT'),has_table_privilege('anon','public.trainer_student_invitations','SELECT'))
  union all
  select '22_invite_hash_not_selectable',not has_column_privilege('authenticated','public.trainer_student_invitations','invite_code_hash','SELECT'),format('authenticated_hash_select=%s',has_column_privilege('authenticated','public.trainer_student_invitations','invite_code_hash','SELECT'))
  union all
  select '23_active_relationship_preserved',coalesce(bool_or(definition ~ 'when[[:space:]]+public\.trainer_student_relationships\.status[[:space:]]*=[[:space:]]*''active''[[:space:]]+then[[:space:]]+public\.trainer_student_relationships\.permissions' and definition ~ 'when[[:space:]]+public\.trainer_student_relationships\.status[[:space:]]*=[[:space:]]*''active''[[:space:]]+then[[:space:]]+public\.trainer_student_relationships\.accepted_at'),false),format('preserved=%s',coalesce(bool_or(definition ~ 'when[[:space:]]+public\.trainer_student_relationships\.status[[:space:]]*=[[:space:]]*''active''[[:space:]]+then[[:space:]]+public\.trainer_student_relationships\.permissions' and definition ~ 'when[[:space:]]+public\.trainer_student_relationships\.status[[:space:]]*=[[:space:]]*''active''[[:space:]]+then[[:space:]]+public\.trainer_student_relationships\.accepted_at'),false)) from function_info where proname='accept_trainer_student_invitation'
  union all
  select '24_trainer_lock_before_limit',coalesce(bool_or(position('for update' in definition)>0 and position('for update' in definition)<position('count(*)' in definition)),false),format('lock_precedes_count=%s',coalesce(bool_or(position('for update' in definition)>0 and position('for update' in definition)<position('count(*)' in definition)),false)) from function_info where proname='create_trainer_student_invitation'
  union all
  select '25_expired_status_derived',coalesce(bool_or(definition ~ 'status[[:space:]]*=[[:space:]]*''pending''' and definition ~ 'expires_at[[:space:]]*<=[[:space:]]*now\(\)' and definition ~ 'then[[:space:]]+''expired'''),false),format('derived=%s',coalesce(bool_or(definition ~ 'status[[:space:]]*=[[:space:]]*''pending''' and definition ~ 'expires_at[[:space:]]*<=[[:space:]]*now\(\)' and definition ~ 'then[[:space:]]+''expired'''),false)) from function_info where proname='list_my_trainer_invitations'
  union all
  select '26_expired_invite_not_cancellable',coalesce(bool_or(definition ~ 'expires_at[[:space:]]*>[[:space:]]*now\(\)'),false),format('guard_present=%s',coalesce(bool_or(definition ~ 'expires_at[[:space:]]*>[[:space:]]*now\(\)'),false)) from function_info where proname='cancel_trainer_invitation'
),
summary as (
  select count(*)::integer as total_checks,count(*) filter(where passed)::integer as passed_checks,count(*) filter(where not passed)::integer as failed_checks,bool_and(passed) as all_passed from checks
)
select checks.check_name,checks.passed,checks.details,summary.total_checks,summary.passed_checks,summary.failed_checks,summary.all_passed
from checks cross join summary
order by checks.check_name;
