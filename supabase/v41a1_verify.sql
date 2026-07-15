-- V4.1A.1 read-only verification. Do not add write statements to this file.
with
tables as (
  select c.relname,c.relrowsecurity
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relname in ('account_plan_catalog','user_commercial_accounts','user_identity_details','user_legal_acceptances')
),
functions as (
  select p.oid,p.proname,p.prosecdef,lower(pg_catalog.pg_get_functiondef(p.oid)) definition,
    exists(
      select 1 from unnest(p.proconfig) setting
      where pg_catalog.regexp_replace(setting,'[[:space:]]','','g') in ('search_path=','search_path=""')
    ) empty_search_path
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname in (
      'complete_my_initial_account_setup','get_my_account_registration_context',
      'get_my_commercial_account_context','set_my_personal_use_enabled',
      'get_current_access_context','get_current_access_context_v41a',
      'validate_user_identity_birth_date_v41a1'
    )
),
setup as (
  select definition,pg_catalog.regexp_replace(definition,'[[:space:]]','','g') compact
  from functions where proname='complete_my_initial_account_setup'
),
policies as (
  select p.polname,p.polrelid,p.polcmd,p.polroles,
    pg_catalog.regexp_replace(lower(pg_catalog.pg_get_expr(p.polqual,p.polrelid)),'[[:space:]]','','g') qual
  from pg_catalog.pg_policy p
  where p.polrelid in (
    'public.user_commercial_accounts'::regclass,
    'public.user_identity_details'::regclass,
    'public.user_legal_acceptances'::regclass
  )
),
birth_trigger as (
  select lower(pg_catalog.pg_get_triggerdef(t.oid)) definition
  from pg_catalog.pg_trigger t
  where t.tgrelid='public.user_identity_details'::regclass
    and t.tgname='validate_user_identity_birth_date_v41a1'
    and not t.tgisinternal
),
checks as (
  select '01_plan_catalog_exists' check_name,to_regclass('public.account_plan_catalog') is not null passed,'account_plan_catalog exists' details
  union all select '02_plan_catalog_rls',coalesce((select relrowsecurity from tables where relname='account_plan_catalog'),false),'catalog RLS enabled'
  union all select '03_only_three_initial_plans',(select count(*)=3 and count(*) filter(where code in ('individual_free','trainer_free','nutritionist_free'))=3 from public.account_plan_catalog),'only expected free plans exist'
  union all select '04_trainer_limit_five',exists(select 1 from public.account_plan_catalog where code='trainer_free' and account_type='trainer' and active_client_limit=5 and is_free and is_active),'trainer_free limit is 5'
  union all select '05_nutritionist_limit_five',exists(select 1 from public.account_plan_catalog where code='nutritionist_free' and account_type='nutritionist' and active_client_limit=5 and is_free and is_active),'nutritionist_free limit is 5'
  union all select '06_individual_limit_null',exists(select 1 from public.account_plan_catalog where code='individual_free' and account_type='individual' and active_client_limit is null and is_free and is_active),'individual_free has null client limit'
  union all select '07_commercial_accounts_exists',to_regclass('public.user_commercial_accounts') is not null,'user_commercial_accounts exists'
  union all select '08_commercial_accounts_rls',coalesce((select relrowsecurity from tables where relname='user_commercial_accounts'),false),'commercial account RLS enabled'
  union all select '09_commercial_no_direct_writes',not pg_catalog.has_table_privilege('authenticated','public.user_commercial_accounts','INSERT') and not pg_catalog.has_table_privilege('authenticated','public.user_commercial_accounts','UPDATE') and not pg_catalog.has_table_privilege('authenticated','public.user_commercial_accounts','DELETE'),'authenticated has no commercial writes'
  union all select '10_commercial_no_anon_access',not pg_catalog.has_table_privilege('anon','public.user_commercial_accounts','SELECT') and not pg_catalog.has_table_privilege('anon','public.user_commercial_accounts','INSERT') and not pg_catalog.has_table_privilege('anon','public.user_commercial_accounts','UPDATE') and not pg_catalog.has_table_privilege('anon','public.user_commercial_accounts','DELETE'),'anon has no commercial access'
  union all select '11_identity_details_exists',to_regclass('public.user_identity_details') is not null,'identity table exists'
  union all select '12_identity_details_rls',coalesce((select relrowsecurity from tables where relname='user_identity_details'),false),'identity RLS enabled'
  union all select '13_identity_select_own_only',exists(select 1 from policies where polname='user_identity_details_select_own_v41a1' and polcmd='r' and cardinality(polroles)=1 and pg_catalog.to_regrole('authenticated')=any(polroles) and (qual like '%user_id=auth.uid()%' or qual like '%auth.uid()=user_id%')),'identity SELECT is own-row only'
  union all select '14_identity_no_direct_writes',not pg_catalog.has_table_privilege('authenticated','public.user_identity_details','INSERT') and not pg_catalog.has_table_privilege('authenticated','public.user_identity_details','UPDATE') and not pg_catalog.has_table_privilege('authenticated','public.user_identity_details','DELETE'),'identity writes blocked'
  union all select '15_legal_acceptances_exists',to_regclass('public.user_legal_acceptances') is not null,'legal acceptances table exists'
  union all select '16_legal_acceptances_rls',coalesce((select relrowsecurity from tables where relname='user_legal_acceptances'),false),'legal acceptance RLS enabled'
  union all select '17_legal_no_direct_writes',not pg_catalog.has_table_privilege('authenticated','public.user_legal_acceptances','INSERT') and not pg_catalog.has_table_privilege('authenticated','public.user_legal_acceptances','UPDATE') and not pg_catalog.has_table_privilege('authenticated','public.user_legal_acceptances','DELETE'),'legal writes blocked'
  union all select '18_privileged_primary_types_blocked',exists(select 1 from pg_catalog.pg_constraint where conrelid='public.user_commercial_accounts'::regclass and pg_catalog.pg_get_constraintdef(oid) like '%individual%' and pg_catalog.pg_get_constraintdef(oid) like '%trainer%' and pg_catalog.pg_get_constraintdef(oid) like '%nutritionist%' and pg_catalog.pg_get_constraintdef(oid) not like '%admin%' and pg_catalog.pg_get_constraintdef(oid) not like '%owner%'),'primary types exclude privileged roles'
  union all select '19_plan_matches_account_type',exists(select 1 from pg_catalog.pg_constraint where conrelid='public.user_commercial_accounts'::regclass and contype='f' and pg_catalog.pg_get_constraintdef(oid) like '%plan_code, primary_account_type%' and pg_catalog.pg_get_constraintdef(oid) like '%code, account_type%'),'composite FK binds plan and type'
  union all select '20_minor_setup_blocked',exists(select 1 from setup where definition like '%calculated_age < 18%' and definition like '%cadastro de menores%'),'server blocks age below 18'
  union all select '21_future_birth_blocked',exists(select 1 from setup where definition like '%target_birth_date > current_date%'),'server blocks future birth date'
  union all select '22_implausible_age_blocked',exists(select 1 from setup where definition like '%120 years%'),'server blocks age above 120'
  union all select '23_setup_rpc_exists',to_regprocedure('public.complete_my_initial_account_setup(text,text,text,date,text,text)') is not null,'typed setup RPC exists'
  union all select '24_setup_rpc_authenticated_only',not pg_catalog.has_function_privilege('anon','public.complete_my_initial_account_setup(text,text,text,date,text,text)','EXECUTE') and pg_catalog.has_function_privilege('authenticated','public.complete_my_initial_account_setup(text,text,text,date,text,text)','EXECUTE'),'setup RPC authenticated-only'
  union all select '25_plan_not_client_selectable',exists(select 1 from setup where definition like '%selected_plan_code := case%' and definition not like '%target_plan%'),'plan is selected server-side'
  union all select '26_setup_idempotent',exists(select 1 from setup where definition like '%on conflict%' and definition like '%existing_type is not null%'),'same setup can be safely repeated'
  union all select '27_direct_type_change_blocked',exists(select 1 from setup where definition like '%existing_type <> normalized_type%' and definition like '%raise exception%'),'direct primary type change blocked'
  union all select '28_legal_versions_checked',exists(select 1 from setup where definition like '%terms-2026-01%' and definition like '%privacy-2026-01%' and definition like '%aceites legais desatualizados%'),'explicit legal versions checked'
  union all select '29_registration_context_exists',to_regprocedure('public.get_my_account_registration_context()') is not null,'registration context RPC exists'
  union all select '30_commercial_context_exists',to_regprocedure('public.get_my_commercial_account_context()') is not null,'commercial context RPC exists'
  union all select '31_personal_use_rpc_exists',to_regprocedure('public.set_my_personal_use_enabled(boolean)') is not null,'personal use RPC exists'
  union all select '32_new_functions_empty_search_path',(select count(*)=6 and bool_and(empty_search_path) from functions where proname<>'get_current_access_context_v41a'),'all V4.1A.1 functions have empty search_path'
  union all select '33_existing_users_not_forced',not exists(select 1 from public.user_commercial_accounts where primary_account_type is not null and account_type_selected_at is null),'no selected type lacks explicit selection timestamp'
  union all select '34_profiles_preserved',to_regclass('public.profiles') is not null and not exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.profiles'::regclass and tgname like '%v41a1%'),'profiles have no V4.1A.1 mutation trigger'
  union all select '35_meals_unchanged',not exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.meals'::regclass and tgname like '%v41a1%'),'no V4.1A.1 meal trigger'
  union all select '36_workouts_unchanged',not exists(select 1 from pg_catalog.pg_trigger where tgrelid='public.workouts'::regclass and tgname like '%v41a1%'),'no V4.1A.1 workout trigger'
  union all select '37_no_relationship_created',not exists(select 1 from functions where definition like '%insert into public.professional_student_relationships%' or definition like '%insert into public.trainer_student_relationships%'),'registration RPCs create no relationships'
  union all select '38_no_paid_subscription',(select bool_and(is_free) and count(*)=3 from public.account_plan_catalog),'all catalog entries are free'
  union all select '39_no_cpf_columns',not exists(select 1 from information_schema.columns where table_schema='public' and table_name in ('user_identity_details','user_commercial_accounts','user_legal_acceptances') and column_name like '%cpf%'),'no CPF column exists'
  union all select '40_no_third_party_policies',not exists(select 1 from policies where polcmd<>'r' or cardinality(polroles)<>1 or pg_catalog.to_regrole('authenticated')<>all(polroles) or not (qual like '%user_id=auth.uid()%' or qual like '%auth.uid()=user_id%')),'private tables expose own rows only'
  union all select '41_setup_preserves_subscription_status',exists(select 1 from setup where compact not like '%subscription_status=%'),'idempotent setup does not reset subscription status'
  union all select '42_setup_preserves_personal_use',exists(select 1 from setup where compact not like '%personal_use_enabled=%'),'idempotent setup does not reset personal use'
  union all select '43_profile_identity_birth_consistency',exists(select 1 from setup where definition like '%existing_profile_birth_date%' and definition like '%existing_birth_date%' and definition like '%<> target_birth_date%'),'setup rejects divergent confirmed birth dates'
  union all select '44_profile_birth_not_overwritten',exists(select 1 from setup where compact like '%birth_date=coalesce(public.profiles.birth_date,excluded.birth_date)%'),'existing profile birth date is preserved'
  union all select '45_profile_birth_null_fill',exists(select 1 from setup where compact like '%birth_date=coalesce(public.profiles.birth_date,excluded.birth_date)%' and compact like '%target_birth_date%'),'null profile birth date can be filled'
  union all select '46_birth_trigger_exists',exists(select 1 from birth_trigger),'birth-date validation trigger exists'
  union all select '47_birth_trigger_insert_update',exists(select 1 from birth_trigger where definition like '%before insert or update of birth_date%'),'trigger handles INSERT and birth_date UPDATE'
  union all select '48_birth_trigger_not_frontend_executable',to_regprocedure('public.validate_user_identity_birth_date_v41a1()') is not null and not pg_catalog.has_function_privilege('anon','public.validate_user_identity_birth_date_v41a1()','EXECUTE') and not pg_catalog.has_function_privilege('authenticated','public.validate_user_identity_birth_date_v41a1()','EXECUTE'),'trigger function is not frontend-executable'
  union all select '49_base_access_context_exists',to_regprocedure('public.get_current_access_context_v41a()') is not null,'V4.1A base access context exists'
  union all select '50_current_context_calls_base',exists(select 1 from functions where proname='get_current_access_context' and definition like '%public.get_current_access_context_v41a()%'),'current access context delegates to its base'
  union all select '51_private_policies_exact',(select count(*)=3 and bool_and(polcmd='r' and cardinality(polroles)=1 and pg_catalog.to_regrole('authenticated')=any(polroles) and 0::oid<>all(polroles) and pg_catalog.to_regrole('anon')<>all(polroles) and (qual like '%user_id=auth.uid()%' or qual like '%auth.uid()=user_id%')) from policies where polname in ('user_commercial_accounts_select_own_v41a1','user_identity_details_select_own_v41a1','user_legal_acceptances_select_own_v41a1')),'three private policies are authenticated own-row SELECT only'
  union all select '52_anon_no_new_table_privileges',not exists(select 1 from unnest(array['account_plan_catalog','user_commercial_accounts','user_identity_details','user_legal_acceptances']) as names(table_name) where pg_catalog.has_table_privilege('anon','public.'||table_name,'SELECT') or pg_catalog.has_table_privilege('anon','public.'||table_name,'INSERT') or pg_catalog.has_table_privilege('anon','public.'||table_name,'UPDATE') or pg_catalog.has_table_privilege('anon','public.'||table_name,'DELETE') or pg_catalog.has_table_privilege('anon','public.'||table_name,'TRUNCATE') or pg_catalog.has_table_privilege('anon','public.'||table_name,'REFERENCES') or pg_catalog.has_table_privilege('anon','public.'||table_name,'TRIGGER')),'anon has no privileges on V4.1A.1 tables'
  union all select '53_authenticated_select_only',not exists(select 1 from unnest(array['account_plan_catalog','user_commercial_accounts','user_identity_details','user_legal_acceptances']) as names(table_name) where not pg_catalog.has_table_privilege('authenticated','public.'||table_name,'SELECT') or pg_catalog.has_table_privilege('authenticated','public.'||table_name,'INSERT') or pg_catalog.has_table_privilege('authenticated','public.'||table_name,'UPDATE') or pg_catalog.has_table_privilege('authenticated','public.'||table_name,'DELETE') or pg_catalog.has_table_privilege('authenticated','public.'||table_name,'TRUNCATE') or pg_catalog.has_table_privilege('authenticated','public.'||table_name,'REFERENCES') or pg_catalog.has_table_privilege('authenticated','public.'||table_name,'TRIGGER')),'authenticated has SELECT only on V4.1A.1 tables'
  union all select '54_no_temporal_birth_checks',not exists(select 1 from pg_catalog.pg_constraint where conrelid='public.user_identity_details'::regclass and conname in ('user_identity_details_birth_not_future','user_identity_details_age_plausible')),'CURRENT_DATE birth checks were removed'
)
select check_name,passed,details,count(*) over() total_checks,count(*) filter(where passed) over() passed_checks,count(*) filter(where not passed) over() failed_checks,bool_and(passed) over() all_passed
from checks order by check_name;
