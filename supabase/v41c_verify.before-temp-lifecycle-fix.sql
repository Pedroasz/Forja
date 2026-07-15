-- V4.1C read-only verification. Run after v41c_notifications.sql and v41c_nutrition_plan_assignments.sql.
begin;

create temporary table v41c_verify_results
on commit drop
as
with
functions as (
  select p.oid,p.proname,p.proowner,p.proacl,p.prosecdef,
    lower(pg_get_function_arguments(p.oid)) arguments,
    lower(pg_get_functiondef(p.oid)) definition,
    regexp_replace(lower(pg_get_functiondef(p.oid)),'[[:space:]]','','g') compact,
    exists(select 1 from unnest(p.proconfig) setting where regexp_replace(setting,'[[:space:]]','','g') in ('search_path=','search_path=""')) empty_search_path
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
    'notification_iso_date_is_valid_v41c','notification_metadata_is_safe_v41c','create_user_notification_v41c','notify_relationship_status_v41c','notify_workout_assignment_v41c',
    'list_my_notifications','get_my_unread_notification_count','mark_my_notification_read','mark_all_my_notifications_read',
    'nutrition_text_is_safe_v41c','nutrition_unit_is_supported_v41c','validate_nutrition_plan_payload_v41c','assert_my_nutritionist_identity_v41c','assert_my_nutritionist_write_access_v41c',
    'protect_nutrition_assignment_snapshot_v41c','notify_nutrition_assignment_v41c','create_my_nutrition_template','update_my_nutrition_template',
    'archive_my_nutrition_template','list_my_nutrition_templates','list_my_manageable_nutrition_students','assign_nutrition_template_to_student',
    'revoke_my_student_nutrition_assignment','list_my_assigned_nutrition_plans'
  )
),
  notification_helper as (select * from functions where proname='create_user_notification_v41c'),
  notification_metadata_helper as (select * from functions where proname='notification_metadata_is_safe_v41c'),
relationship_trigger_function as (select * from functions where proname='notify_relationship_status_v41c'),
workout_trigger_function as (select * from functions where proname='notify_workout_assignment_v41c'),
notification_list_rpc as (select * from functions where proname='list_my_notifications'),
  nutrition_validator as (select * from functions where proname='validate_nutrition_plan_payload_v41c'),
  nutrition_unit_helper as (select * from functions where proname='nutrition_unit_is_supported_v41c'),
  nutrition_create as (select * from functions where proname='create_my_nutrition_template'),
  nutrition_update as (select * from functions where proname='update_my_nutrition_template'),
nutrition_identity as (select * from functions where proname='assert_my_nutritionist_identity_v41c'),
nutrition_write as (select * from functions where proname='assert_my_nutritionist_write_access_v41c'),
nutrition_snapshot as (select * from functions where proname='protect_nutrition_assignment_snapshot_v41c'),
nutrition_assign as (select * from functions where proname='assign_nutrition_template_to_student'),
nutrition_student_list as (select * from functions where proname='list_my_assigned_nutrition_plans'),
nutrition_manageable_list as (select * from functions where proname='list_my_manageable_nutrition_students'),
nutrition_notification_trigger as (select * from functions where proname='notify_nutrition_assignment_v41c'),
notification_public_rpcs as (select * from functions where proname in ('list_my_notifications','get_my_unread_notification_count','mark_my_notification_read','mark_all_my_notifications_read')),
nutrition_public_rpcs as (select * from functions where proname in ('create_my_nutrition_template','update_my_nutrition_template','archive_my_nutrition_template','list_my_nutrition_templates','list_my_manageable_nutrition_students','assign_nutrition_template_to_student','revoke_my_student_nutrition_assignment','list_my_assigned_nutrition_plans')),
notification_constraints as (select conname,lower(pg_get_constraintdef(oid)) definition,regexp_replace(lower(pg_get_constraintdef(oid)),'[[:space:]]','','g') compact from pg_constraint where conrelid=to_regclass('public.user_notifications')),
template_constraints as (select conname,contype,convalidated,lower(pg_get_constraintdef(oid)) definition,regexp_replace(lower(pg_get_constraintdef(oid)),'[[:space:]]','','g') compact from pg_constraint where conrelid=to_regclass('public.professional_nutrition_templates')),
assignment_constraints as (select conname,contype,convalidated,lower(pg_get_constraintdef(oid)) definition,regexp_replace(lower(pg_get_constraintdef(oid)),'[[:space:]]','','g') compact from pg_constraint where conrelid=to_regclass('public.student_nutrition_assignments')),
policies as (select tablename,policyname,cmd,roles,permissive,lower(coalesce(qual,'')) expression,lower(coalesce(with_check,'')) with_check from pg_policies where schemaname='public' and tablename in ('user_notifications','professional_nutrition_templates','student_nutrition_assignments')),
triggers as (select t.tgname,t.tgrelid::regclass::text table_name,lower(pg_get_triggerdef(t.oid)) definition from pg_trigger t where not t.tgisinternal and t.tgname like '%v41c'),
nutrition_indexes as (
  select relation.relname table_name,index_relation.relname index_name,index_definition.indisunique,index_definition.indisvalid,index_definition.indisready,
    regexp_replace(lower(pg_get_indexdef(index_definition.indexrelid)),'[[:space:]]','','g') definition
  from pg_index index_definition
  join pg_class relation on relation.oid=index_definition.indrelid
  join pg_namespace namespace on namespace.oid=relation.relnamespace
  join pg_class index_relation on index_relation.oid=index_definition.indexrelid
  where namespace.nspname='public' and relation.relname in ('professional_nutrition_templates','student_nutrition_assignments')
),
  valid_payload as (select '{"schemaVersion":1,"title":"Plano alimentar","notes":"","dailyTargets":{"calories":null,"proteinGrams":null,"carbohydrateGrams":null,"fatGrams":null,"waterMl":null},"meals":[{"code":"M1","name":"Cafe da manha","time":"07:00","notes":"","items":[{"foodId":null,"name":"Aveia","quantity":40,"unit":"g","notes":"","sortOrder":0}]}]}'::jsonb value),
  validator_cases as (select public.validate_nutrition_plan_payload_v41c(value) accepts_valid,not public.validate_nutrition_plan_payload_v41c(jsonb_set(value,'{schemaVersion}','2'::jsonb)) rejects_v2,not public.validate_nutrition_plan_payload_v41c(jsonb_set(value,'{schemaVersion}','1.5'::jsonb)) rejects_decimal from valid_payload),
  nutrition_optional_cases as (
    select
      public.validate_nutrition_plan_payload_v41c(value-'dailyTargets') daily_targets_omitted,
      public.validate_nutrition_plan_payload_v41c(jsonb_set(value,'{dailyTargets}','null'::jsonb)) daily_targets_null,
      public.validate_nutrition_plan_payload_v41c(jsonb_set(value,'{dailyTargets}','{"proteinGrams":120}'::jsonb)) daily_targets_partial,
      not public.validate_nutrition_plan_payload_v41c(jsonb_set(value,'{dailyTargets}','{"sodium":1}'::jsonb)) daily_targets_unknown_blocked,
      not public.validate_nutrition_plan_payload_v41c(jsonb_set(value,'{dailyTargets}','{"proteinGrams":-1}'::jsonb)) daily_targets_negative_blocked,
      not public.validate_nutrition_plan_payload_v41c(jsonb_set(value,'{meals,0,items}','[]'::jsonb)) empty_meal_blocked,
      public.validate_nutrition_plan_payload_v41c(value) one_item_valid,
      public.validate_nutrition_plan_payload_v41c(jsonb_set(value,'{meals,0,items}',(select jsonb_agg(jsonb_set(value->'meals'->0->'items'->0,'{sortOrder}',to_jsonb(item_number-1))) from generate_series(1,30) as series(item_number)))) thirty_items_valid,
      not public.validate_nutrition_plan_payload_v41c(jsonb_set(value,'{meals,0,items}',(select jsonb_agg(jsonb_set(value->'meals'->0->'items'->0,'{sortOrder}',to_jsonb(item_number-1))) from generate_series(1,31) as series(item_number)))) thirty_one_items_blocked
    from valid_payload
  ),
data_metrics as (
  select
    (select count(*) from public.professional_nutrition_templates template where not public.validate_nutrition_plan_payload_v41c(template.plan_data)) invalid_template_payloads,
    (select count(*) from public.student_nutrition_assignments assignment where not public.validate_nutrition_plan_payload_v41c(assignment.plan_data_snapshot)) invalid_assignment_payloads,
    (select count(*) from (select relationship_id from public.student_nutrition_assignments where status='active' group by relationship_id having count(*)>1) duplicate_rows) multiple_active_relationships,
    (select count(*) from (select relationship_id,assignment_version from public.student_nutrition_assignments group by relationship_id,assignment_version having count(*)>1) duplicate_rows) duplicate_assignment_versions,
    (select count(*) from public.student_nutrition_assignments assignment
      left join public.professional_student_relationships relationship on relationship.id=assignment.relationship_id
      left join public.professional_nutrition_templates template on template.id=assignment.template_id
      where assignment.status='active' and (
        relationship.id is null or relationship.professional_type<>'nutritionist' or relationship.status<>'active'
        or (relationship.scopes @> '{"manage_nutrition_plan": true}'::jsonb) is not true
        or relationship.professional_user_id is null or relationship.student_user_id is null
        or (template.id is not null and template.owner_user_id<>relationship.professional_user_id)
      )) invalid_active_relationships,
    (select count(*) from public.student_nutrition_assignments assignment
      join public.professional_student_relationships relationship on relationship.id=assignment.relationship_id
      where relationship.status<>'active') historical_assignments_on_inactive_relationships,
    (select count(*) from public.student_nutrition_assignments assignment
      join public.professional_student_relationships relationship on relationship.id=assignment.relationship_id
      left join public.professional_nutrition_templates template on template.id=assignment.template_id
      where (template.id is not null and template.organization_id is distinct from relationship.organization_id)
        or (to_jsonb(assignment)?'organization_id' and to_jsonb(assignment)->>'organization_id' is distinct from relationship.organization_id::text)) organization_mismatches,
    (select count(*) from public.student_nutrition_assignments assignment where
      (assignment.effective_until is not null and assignment.effective_from is not null and assignment.effective_until<assignment.effective_from)
      or (assignment.status='active' and assignment.effective_until is not null and assignment.effective_until<current_date)
      or (assignment.status='superseded' and assignment.superseded_at is null)
      or (assignment.status='revoked' and assignment.revoked_at is null)
      or assignment.superseded_at<assignment.created_at or assignment.revoked_at<assignment.created_at) inconsistent_assignment_dates,
    (select count(*) from public.user_notifications notification where notification.dedupe_key is not null and (notification.dedupe_key<>btrim(notification.dedupe_key) or char_length(btrim(notification.dedupe_key)) not between 1 and 200)) invalid_dedupe_keys,
    (select count(*) from (select recipient_user_id,btrim(dedupe_key) normalized_key from public.user_notifications where dedupe_key is not null group by recipient_user_id,btrim(dedupe_key) having count(*)>1) duplicate_rows) duplicate_dedupe_keys,
    (select count(*) from public.user_notifications notification where jsonb_typeof(notification.metadata->'effectiveFrom')='string' and not public.notification_iso_date_is_valid_v41c(notification.metadata->>'effectiveFrom')) invalid_metadata_dates,
    (select count(*) from public.user_notifications notification where notification.recipient_user_id is null) notifications_without_user,
    (select count(*) from public.user_notifications notification where notification.notification_type not in (
      'relationship_activated','relationship_revoked','workout_plan_assigned','workout_plan_updated','workout_plan_revoked',
      'nutrition_plan_assigned','nutrition_plan_updated','nutrition_plan_revoked','system')) invalid_notification_types,
    (select count(*) from public.user_notifications notification where notification.expires_at is not null and notification.expires_at<=now()) expired_notifications
),
checks as (
  select '01_user_notifications_exists' check_name,to_regclass('public.user_notifications') is not null passed,'user_notifications exists' details
  union all select '02_notifications_rls_enabled',coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.user_notifications')),false),'notification RLS is enabled'
  union all select '03_notification_recipient_required',exists(select 1 from information_schema.columns where table_schema='public' and table_name='user_notifications' and column_name='recipient_user_id' and is_nullable='NO'),'recipient is required'
  union all select '04_notification_types_validated',exists(select 1 from notification_constraints where conname='user_notifications_type_check' and definition like '%relationship_activated%' and definition like '%nutrition_plan_revoked%'),'notification types are constrained'
  union all select '05_notification_metadata_object',exists(select 1 from notification_constraints where conname='user_notifications_metadata_object_check' and compact like '%jsonb_typeof(metadata)=''object''%'),'metadata must be a JSON object'
  union all select '06_notification_dedupe_partial',exists(select 1 from pg_indexes where schemaname='public' and tablename='user_notifications' and indexname='user_notifications_recipient_dedupe_idx' and indexdef ilike '%unique%' and indexdef ilike '%where (dedupe_key is not null)%'),'recipient dedupe is partial and unique'
  union all select '07_notification_indexes_exist',(select count(*)>=3 from pg_indexes where schemaname='public' and tablename='user_notifications' and indexname like 'user_notifications_%_idx'),'notification read and unread indexes exist'
  union all select '08_authenticated_reads_own_notifications',has_table_privilege('authenticated','public.user_notifications','SELECT') and exists(select 1 from policies where tablename='user_notifications' and expression like '%recipient_user_id = auth.uid()%'),'authenticated reads only own notifications'
  union all select '09_no_direct_notification_writes',not has_table_privilege('authenticated','public.user_notifications','INSERT') and not has_table_privilege('authenticated','public.user_notifications','UPDATE') and not has_table_privilege('authenticated','public.user_notifications','DELETE'),'authenticated has no direct notification writes'
  union all select '10_anon_no_notification_access',not has_table_privilege('anon','public.user_notifications','SELECT') and not has_table_privilege('anon','public.user_notifications','INSERT') and not has_table_privilege('anon','public.user_notifications','UPDATE') and not has_table_privilege('anon','public.user_notifications','DELETE'),'anon has no notification access'
  union all select '11_notification_helper_exists',to_regprocedure('public.create_user_notification_v41c(uuid,uuid,text,text,text,text,uuid,text,jsonb)') is not null,'internal notification helper exists'
  union all select '12_notification_helper_internal',not has_function_privilege('authenticated','public.create_user_notification_v41c(uuid,uuid,text,text,text,text,uuid,text,jsonb)','EXECUTE') and not has_function_privilege('anon','public.create_user_notification_v41c(uuid,uuid,text,text,text,text,uuid,text,jsonb)','EXECUTE'),'notification helper is not frontend executable'
  union all select '13_notification_helper_validates_recipient',exists(select 1 from notification_helper where compact like '%target_recipient_user_idisnull%' and compact like '%notification_recipient_required%'),'helper validates recipient'
  union all select '14_notification_helper_deduplicates',exists(select 1 from notification_helper where compact like '%onconflict(recipient_user_id,dedupe_key)%' and compact like '%donothing%'),'helper applies deterministic dedupe'
  union all select '15_relationship_notification_trigger',exists(select 1 from triggers where table_name like '%professional_student_relationships' and tgname='notify_relationship_status_v41c'),'relationship notification trigger exists'
  union all select '16_relationship_activation_notifies',exists(select 1 from relationship_trigger_function where compact like '%relationship_activated%' and compact like '%new.status=''active''%'),'relationship activation notifies both parties'
  union all select '17_relationship_revocation_notifies',exists(select 1 from relationship_trigger_function where compact like '%relationship_revoked%' and compact like '%old.status=''active''andnew.status=''revoked''%'),'relationship revocation notifies both parties'
  union all select '18_relationship_irrelevant_update_ignored',exists(select 1 from triggers where tgname='notify_relationship_status_v41c' and definition like '%update of status%') and exists(select 1 from relationship_trigger_function where compact like '%elsifold.status=''active''andnew.status=''revoked''then%' and compact like '%elsereturnnew;%'),'irrelevant relationship updates are ignored'
  union all select '19_workout_notification_trigger',exists(select 1 from triggers where table_name like '%student_workout_assignments' and tgname='notify_workout_assignment_status_v41c'),'workout notification trigger exists'
  union all select '20_workout_first_assignment_notifies',exists(select 1 from workout_trigger_function where compact like '%assignment_version=1%' and compact like '%workout_plan_assigned%'),'first workout assignment notifies'
  union all select '21_workout_new_version_notifies',exists(select 1 from workout_trigger_function where compact like '%workout_plan_updated%'),'new workout version notifies'
  union all select '22_workout_revocation_notifies',exists(select 1 from workout_trigger_function where compact like '%workout_plan_revoked%' and compact like '%old.status=''active''andnew.status=''revoked''%'),'workout revocation notifies'
  union all select '23_nutrition_notification_trigger',exists(select 1 from triggers where table_name like '%student_nutrition_assignments' and tgname='notify_nutrition_assignment_status_v41c'),'nutrition notification trigger exists'
  union all select '24_nutrition_first_assignment_notifies',exists(select 1 from nutrition_notification_trigger where compact like '%assignment_version=1%' and compact like '%nutrition_plan_assigned%'),'first nutrition assignment notifies'
  union all select '25_nutrition_new_version_notifies',exists(select 1 from nutrition_notification_trigger where compact like '%nutrition_plan_updated%'),'new nutrition version notifies'
  union all select '26_nutrition_revocation_notifies',exists(select 1 from nutrition_notification_trigger where compact like '%nutrition_plan_revoked%' and compact like '%old.status=''active''andnew.status=''revoked''%'),'nutrition revocation notifies'
  union all select '27_notification_list_rpc_exists',to_regprocedure('public.list_my_notifications(integer,timestamptz)') is not null,'notification list RPC exists'
  union all select '28_notification_list_uses_auth_uid',exists(select 1 from notification_list_rpc where compact like '%recipient_user_id=auth.uid()%'),'notification list derives recipient from auth.uid()'
  union all select '29_unread_count_rpc_exists',to_regprocedure('public.get_my_unread_notification_count()') is not null,'unread count RPC exists'
  union all select '30_mark_read_rpc_exists',to_regprocedure('public.mark_my_notification_read(uuid)') is not null,'mark read RPC exists'
  union all select '31_mark_all_rpc_exists',to_regprocedure('public.mark_all_my_notifications_read()') is not null,'mark all read RPC exists'
  union all select '32_notification_rpcs_authenticated_only',(select count(*)=4 and bool_and(prosecdef and empty_search_path and has_function_privilege('authenticated',oid,'EXECUTE') and not has_function_privilege('anon',oid,'EXECUTE')) from notification_public_rpcs),'four notification RPCs are authenticated-only security definers with empty search_path'
  union all select '33_notification_rpcs_no_recipient_argument',not exists(select 1 from notification_public_rpcs where arguments like '%recipient%'),'public notification RPCs accept no recipient id'
  union all select '34_nutrition_templates_exists',to_regclass('public.professional_nutrition_templates') is not null,'nutrition templates table exists'
  union all select '35_nutrition_templates_rls',coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.professional_nutrition_templates')),false),'nutrition template RLS is enabled'
  union all select '36_nutrition_template_owner_required',exists(select 1 from information_schema.columns where table_schema='public' and table_name='professional_nutrition_templates' and column_name='owner_user_id' and is_nullable='NO'),'nutrition template owner is required'
  union all select '37_nutrition_schema_version_one',(select accepts_valid and rejects_v2 and rejects_decimal from validator_cases) and exists(select 1 from template_constraints where conname='professional_nutrition_templates_schema_version_check' and compact like '%schema_version=1%'),'nutrition schemaVersion is exactly one'
  union all select '38_nutrition_schema_matches_json',exists(select 1 from template_constraints where conname='professional_nutrition_templates_schema_version_check' and compact like '%plan_data->>''schemaversion''%'),'template schema matches JSON'
  union all select '39_nutrition_validator_exists',to_regprocedure('public.validate_nutrition_plan_payload_v41c(jsonb)') is not null and exists(select 1 from nutrition_validator where compact like '%meal_countnotbetween1and12%' and compact like '%item_countnotbetween1and30%'),'nutrition validator exists and bounds meals/items'
  union all select '40_no_direct_nutrition_template_writes',not has_table_privilege('authenticated','public.professional_nutrition_templates','INSERT') and not has_table_privilege('authenticated','public.professional_nutrition_templates','UPDATE') and not has_table_privilege('authenticated','public.professional_nutrition_templates','DELETE'),'no direct nutrition template writes'
  union all select '41_nutrition_assignments_exists',to_regclass('public.student_nutrition_assignments') is not null,'nutrition assignments table exists'
  union all select '42_nutrition_assignments_rls',coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.student_nutrition_assignments')),false),'nutrition assignment RLS is enabled'
  union all select '43_nutrition_versions_snapshots_validated',exists(select 1 from assignment_constraints where definition like '%assignment_version >= 1%') and exists(select 1 from assignment_constraints where definition like '%validate_nutrition_plan_payload_v41c%'),'versions and snapshots are validated'
  union all select '44_one_active_nutrition_assignment',exists(select 1 from pg_indexes where schemaname='public' and tablename='student_nutrition_assignments' and indexname='student_nutrition_assignments_one_active_idx' and indexdef ilike '%unique%' and indexdef ilike '%status = ''active''%'),'one active nutrition assignment per relationship'
  union all select '45_nutrition_snapshots_immutable',exists(select 1 from nutrition_snapshot where compact like '%old.plan_data_snapshotisdistinctfromnew.plan_data_snapshot%' and compact like '%old.assigned_atisdistinctfromnew.assigned_at%'),'nutrition snapshots are immutable'
  union all select '46_nutrition_status_timestamps_consistent',exists(select 1 from assignment_constraints where conname='student_nutrition_assignments_status_timestamps_check' and compact like '%status=''active''%superseded_atisnull%revoked_atisnull%' and compact like '%status=''superseded''%superseded_atisnotnull%' and compact like '%status=''revoked''%revoked_atisnotnull%'),'nutrition status timestamps are consistent'
  union all select '47_nutrition_effective_dates_validated',exists(select 1 from assignment_constraints where conname='student_nutrition_assignments_effective_dates_check' and compact like '%effective_until>=effective_from%'),'nutrition validity dates are ordered'
  union all select '48_patient_reads_own_nutrition_relationship',exists(select 1 from policies where tablename='student_nutrition_assignments' and expression like '%student_user_id = auth.uid()%'),'patient reads own relationship'
  union all select '49_nutritionist_reads_authorized_relationship',exists(select 1 from policies where tablename='student_nutrition_assignments' and expression like '%professional_user_id = auth.uid()%' and expression like '%professional_type = ''nutritionist''%' and expression like '%manage_nutrition_plan%'),'nutritionist read requires own active scoped relationship'
  union all select '50_organization_alone_no_nutrition_access',not exists(select 1 from policies where tablename='student_nutrition_assignments' and expression like '%organization_id%' and expression not like '%professional_user_id%' and expression not like '%student_user_id%'),'organization alone grants no nutrition access'
  union all select '51_nutrition_identity_helper_exists',to_regprocedure('public.assert_my_nutritionist_identity_v41c()') is not null and exists(select 1 from nutrition_identity where compact like '%primary_account_type=''nutritionist''%' and compact like '%mode=''nutritionist''%'),'nutritionist identity helper exists'
  union all select '52_nutrition_write_requires_active_plan',exists(select 1 from nutrition_write where compact like '%assert_my_nutritionist_identity_v41c()%' and compact like '%is_activeisnottrue%'),'nutrition write requires active plan'
  union all select '53_nutrition_write_requires_subscription',exists(select 1 from nutrition_write where compact like '%subscription_statusisnull%' and compact like '%subscription_statusnotin(''active'',''trialing'')%'),'nutrition write requires active or trialing subscription'
  union all select '54_nutrition_internal_helpers_protected',not has_function_privilege('authenticated','public.nutrition_text_is_safe_v41c(text,integer)','EXECUTE') and not has_function_privilege('authenticated','public.nutrition_unit_is_supported_v41c(text)','EXECUTE') and not has_function_privilege('authenticated','public.validate_nutrition_plan_payload_v41c(jsonb)','EXECUTE') and not has_function_privilege('authenticated','public.assert_my_nutritionist_identity_v41c()','EXECUTE') and not has_function_privilege('authenticated','public.assert_my_nutritionist_write_access_v41c()','EXECUTE') and not has_function_privilege('authenticated','public.protect_nutrition_assignment_snapshot_v41c()','EXECUTE') and not has_function_privilege('authenticated','public.notify_nutrition_assignment_v41c()','EXECUTE'),'nutrition internal helpers are protected'
  union all select '55_create_nutrition_rpc',to_regprocedure('public.create_my_nutrition_template(text,text,jsonb,uuid)') is not null,'create nutrition template RPC exists'
  union all select '56_update_nutrition_rpc',to_regprocedure('public.update_my_nutrition_template(uuid,text,text,jsonb)') is not null,'update nutrition template RPC exists'
  union all select '57_archive_nutrition_rpc',to_regprocedure('public.archive_my_nutrition_template(uuid)') is not null,'archive nutrition template RPC exists'
  union all select '58_list_nutrition_templates_rpc',to_regprocedure('public.list_my_nutrition_templates()') is not null,'list nutrition templates RPC exists'
  union all select '59_list_nutrition_patients_rpc',to_regprocedure('public.list_my_manageable_nutrition_students()') is not null,'list manageable patients RPC exists'
  union all select '60_assign_nutrition_rpc',to_regprocedure('public.assign_nutrition_template_to_student(uuid,uuid,date,date)') is not null,'assign nutrition template RPC exists'
  union all select '61_assign_requires_nutritionist',exists(select 1 from nutrition_assign where compact like '%professional_user_id=auth.uid()%' and compact like '%professional_type=''nutritionist''%'),'assignment requires owning nutritionist'
  union all select '62_assign_requires_active_relationship',exists(select 1 from nutrition_assign where compact like '%relationship_record.status<>''active''%'),'assignment requires active relationship'
  union all select '63_assign_requires_nutrition_scope',exists(select 1 from nutrition_assign where compact like '%manage_nutrition_plan%' and compact like '%nutrition_scope_required%'),'assignment requires nutrition scope'
  union all select '64_assign_uses_locks',exists(select 1 from nutrition_assign where compact like '%forupdate%' and compact like '%forshare%'),'assignment locks relationship and template'
  union all select '65_assign_creates_version',exists(select 1 from nutrition_assign where compact like '%max(assignment_version)%' and compact like '%next_version%'),'assignment creates next version'
  union all select '66_assign_supersedes_previous',exists(select 1 from nutrition_assign where compact like '%status=''superseded''%' and compact like '%superseded_at=now()%'),'assignment supersedes prior active version'
  union all select '67_revoke_nutrition_rpc',to_regprocedure('public.revoke_my_student_nutrition_assignment(uuid)') is not null,'revoke nutrition assignment RPC exists'
  union all select '68_student_nutrition_list_rpc',to_regprocedure('public.list_my_assigned_nutrition_plans(date)') is not null,'student nutrition list RPC requires a local civil date'
  union all select '69_is_current_respects_status',exists(select 1 from nutrition_student_list where compact like '%''iscurrent''%' and compact like '%assignment.status=''active''%' and compact like '%relationship.status=''active''%' and compact like '%professional_type=''nutritionist''%' and compact like '%manage_nutrition_plan%'),'isCurrent requires active scoped nutrition relationship'
  union all select '70_is_current_respects_validity',exists(select 1 from nutrition_student_list where compact like '%effective_fromisnullorassignment.effective_from<=target_local_date%' and compact like '%effective_untilisnullorassignment.effective_until>=target_local_date%'),'isCurrent respects the supplied local civil date'
  union all select '71_trainer_has_no_nutrition_authority',exists(select 1 from nutrition_identity where compact like '%primary_account_type=''nutritionist''%') and exists(select 1 from nutrition_assign where compact like '%professional_user_id=auth.uid()%' and compact like '%professional_type=''nutritionist''%' and compact like '%membership.rolein(''owner'',''admin'',''nutritionist'')%') and not exists(select 1 from nutrition_assign where arguments like '%professional_user_id%'),'nutrition authority is structurally limited to the authenticated nutritionist'
  union all select '72_no_patient_diary_read_created',not exists(select 1 from functions where proname like '%nutrition%' and (compact like '%frompublic.meals%' or compact like '%frompublic.hydration%' or compact like '%frompublic.evolution%')),'V4.1C creates no patient diary reader'
  union all select '73_personal_diary_unchanged',not exists(select 1 from functions where proname like '%nutrition%' and (compact like '%updatepublic.meals%' or compact like '%insertintopublic.meals%' or compact like '%deletefrompublic.meals%')),'personal diary is untouched'
  union all select '74_hydration_unchanged',not exists(select 1 from functions where proname like '%nutrition%' and (compact like '%updatepublic.hydration%' or compact like '%insertintopublic.hydration%' or compact like '%deletefrompublic.hydration%')),'hydration is untouched'
  union all select '75_no_fake_user_created',not exists(select 1 from functions where proname like '%v41c%' and (compact like '%insertintoauth.users%' or compact like '%insertintopublic.profiles%')),'no user or profile is created'
  union all select '76_nutrition_templates_use_authenticated_owner',exists(select 1 from functions where proname='create_my_nutrition_template' and compact like '%insertintopublic.professional_nutrition_templates%' and compact like '%values(auth.uid()%'),'template creation derives owner from auth.uid()'
  union all select '77_no_billing_created',not exists(select 1 from functions where proname like '%v41c%' and proname similar to '%(payment|checkout|billing|price|upgrade)%'),'V4.1C creates no billing flow'
  union all select '78_all_notification_internals_protected',(select count(*)=5 and bool_and(empty_search_path and not has_function_privilege('authenticated',oid,'EXECUTE') and not has_function_privilege('anon',oid,'EXECUTE')) from functions where proname in ('notification_iso_date_is_valid_v41c','notification_metadata_is_safe_v41c','create_user_notification_v41c','notify_relationship_status_v41c','notify_workout_assignment_v41c')),'all notification internals use empty search_path and are not frontend executable'
  union all select '79_nutrition_rpcs_authenticated_only',(select count(*)=8 and bool_and(prosecdef and empty_search_path and has_function_privilege('authenticated',oid,'EXECUTE') and not has_function_privilege('anon',oid,'EXECUTE')) from nutrition_public_rpcs),'eight nutrition RPCs are authenticated-only security definers with empty search_path'
  union all select '80_anon_no_nutrition_access',not has_table_privilege('anon','public.professional_nutrition_templates','SELECT') and not has_table_privilege('anon','public.student_nutrition_assignments','SELECT'),'anon has no nutrition table access'
  union all select '81_no_direct_nutrition_assignment_writes',not has_table_privilege('authenticated','public.student_nutrition_assignments','INSERT') and not has_table_privilege('authenticated','public.student_nutrition_assignments','UPDATE') and not has_table_privilege('authenticated','public.student_nutrition_assignments','DELETE'),'authenticated has no direct nutrition assignment writes'
  union all select '82_notification_metadata_safe_constraint',exists(select 1 from notification_constraints where conname='user_notifications_metadata_safe_check' and compact like '%notification_metadata_is_safe_v41c(metadata)%'),'metadata safety is enforced by the table constraint'
  union all select '83_notification_metadata_size_constraint',exists(select 1 from notification_constraints where conname='user_notifications_metadata_safe_check' and compact like '%octet_length((metadata)::text)<=8192%'),'metadata serialized size is limited to 8192 bytes'
  union all select '84_notification_metadata_helper_bounded',exists(select 1 from notification_metadata_helper where (compact like '%octet_length(target_value::text)<=8192%' or compact like '%octet_length((target_value)::text)<=8192%') and compact like '%jsonb_each(casewhenjsonb_typeof(target_value)=''object''thentarget_valueelse''{}''::jsonbend)%' and compact not like '%withrecursive%' and compact not like '%jsonb_array_elements%'),'metadata helper limits size and validates only flat object entries'
  union all select '85_relationship_trigger_explicit_tg_op',exists(select 1 from relationship_trigger_function where compact like '%iftg_op=''insert''then%' and compact like '%elsiftg_op=''update''then%' and compact like '%elsereturncoalesce(new,old)%'),'relationship trigger handles TG_OP explicitly'
  union all select '86_workout_trigger_explicit_tg_op',exists(select 1 from workout_trigger_function where compact like '%iftg_op=''insert''then%' and compact like '%elsiftg_op=''update''then%' and compact like '%elsereturncoalesce(new,old)%'),'workout trigger handles TG_OP explicitly'
  union all select '87_nutrition_trigger_explicit_tg_op',exists(select 1 from nutrition_notification_trigger where compact like '%iftg_op=''insert''then%' and compact like '%elsiftg_op=''update''then%' and compact like '%elsereturncoalesce(new,old)%'),'nutrition trigger handles TG_OP explicitly'
  union all select '88_insert_branches_do_not_read_old',exists(select 1 from relationship_trigger_function where split_part(compact,'elsiftg_op=''update''then',1) not like '%old.%') and exists(select 1 from workout_trigger_function where split_part(compact,'elsiftg_op=''update''then',1) not like '%old.%') and exists(select 1 from nutrition_notification_trigger where split_part(compact,'elsiftg_op=''update''then',1) not like '%old.%'),'INSERT branches do not access OLD'
  union all select '89_relationship_real_transitions_only',exists(select 1 from relationship_trigger_function where compact like '%old.statusisdistinctfromnew.statusandnew.status=''active''%' and compact like '%old.status=''active''andnew.status=''revoked''%'),'relationship notifications require real activation or revocation transitions'
  union all select '90_relationship_insert_update_triggers',(select count(*)=2 from triggers where table_name like '%professional_student_relationships' and tgname in ('notify_relationship_insert_v41c','notify_relationship_status_v41c')),'relationship has separate INSERT and UPDATE triggers'
  union all select '91_workout_insert_update_triggers',(select count(*)=2 from triggers where table_name like '%student_workout_assignments' and tgname in ('notify_workout_assignment_insert_v41c','notify_workout_assignment_status_v41c')),'workout assignment has separate INSERT and UPDATE triggers'
  union all select '92_nutrition_insert_update_triggers',(select count(*)=2 from triggers where table_name like '%student_nutrition_assignments' and tgname in ('notify_nutrition_assignment_insert_v41c','notify_nutrition_assignment_status_v41c')),'nutrition assignment has separate INSERT and UPDATE triggers'
  union all select '93_workout_superseded_not_revoked',exists(select 1 from workout_trigger_function where compact like '%old.status=''active''andnew.status=''revoked''%' and compact not like '%new.status=''superseded''%'),'workout superseded transition does not emit revocation'
  union all select '94_nutrition_superseded_not_revoked',exists(select 1 from nutrition_notification_trigger where compact like '%old.status=''active''andnew.status=''revoked''%' and compact not like '%new.status=''superseded''%'),'nutrition superseded transition does not emit revocation'
  union all select '95_daily_targets_omitted_valid',(select daily_targets_omitted from nutrition_optional_cases),'dailyTargets may be omitted'
  union all select '96_daily_targets_null_valid',(select daily_targets_null from nutrition_optional_cases),'dailyTargets may be null'
  union all select '97_daily_targets_partial_valid',(select daily_targets_partial from nutrition_optional_cases),'dailyTargets may be partial'
  union all select '98_daily_targets_unknown_blocked',(select daily_targets_unknown_blocked from nutrition_optional_cases),'unknown daily target is rejected'
  union all select '99_daily_targets_negative_blocked',(select daily_targets_negative_blocked from nutrition_optional_cases),'negative daily target is rejected'
  union all select '100_empty_meal_blocked',(select empty_meal_blocked from nutrition_optional_cases),'published meal cannot be empty'
  union all select '101_one_item_meal_valid',(select one_item_valid from nutrition_optional_cases),'meal with one item is valid'
  union all select '102_thirty_item_limit',(select thirty_items_valid and thirty_one_items_blocked from nutrition_optional_cases),'thirty meal items are accepted and thirty-one are rejected'
  union all select '103_nutrition_unit_helper_exists',to_regprocedure('public.nutrition_unit_is_supported_v41c(text)') is not null and exists(select 1 from nutrition_unit_helper where empty_search_path),'central nutrition unit helper exists with empty search_path'
  union all select '104_expected_canonical_units_supported',public.nutrition_unit_is_supported_v41c('g') and public.nutrition_unit_is_supported_v41c('kg') and public.nutrition_unit_is_supported_v41c('ml') and public.nutrition_unit_is_supported_v41c('l') and public.nutrition_unit_is_supported_v41c('unidade') and public.nutrition_unit_is_supported_v41c('porcao') and public.nutrition_unit_is_supported_v41c('colher') and public.nutrition_unit_is_supported_v41c('xicara') and public.nutrition_unit_is_supported_v41c('fatia'),'the expected versioned SQL contract supports every canonical unit'
  union all select '105_unit_aliases_and_unknown',public.nutrition_unit_is_supported_v41c(' porção ') and public.nutrition_unit_is_supported_v41c('XÍCARA') and not public.nutrition_unit_is_supported_v41c('balde'),'spacing, case and aliases normalize while unknown units are rejected'
  union all select '106_template_title_safe_constraint',exists(select 1 from template_constraints where conname='professional_nutrition_templates_title_check' and compact like '%nutrition_text_is_safe_v41c(title,120)%'),'template title safety is constrained'
  union all select '107_template_description_safe_constraint',exists(select 1 from template_constraints where conname='professional_nutrition_templates_description_check' and compact like '%nutrition_text_is_safe_v41c(description,2000)%'),'template description safety is constrained'
  union all select '108_snapshot_text_constraints',exists(select 1 from assignment_constraints where conname='student_nutrition_assignments_title_check' and compact like '%nutrition_text_is_safe_v41c(title_snapshot,120)%') and exists(select 1 from assignment_constraints where conname='student_nutrition_assignments_description_check' and compact like '%nutrition_text_is_safe_v41c(description_snapshot,2000)%'),'title and description snapshots are protected'
  union all select '109_template_rpcs_normalize_and_validate_text',exists(select 1 from nutrition_create where compact like '%regexp_replace(btrim(coalesce(target_title%[[:space:]]+%' and compact like '%nutrition_text_is_safe_v41c(normalized_title,120)%' and compact like '%nutrition_text_is_safe_v41c(normalized_description,2000)%') and exists(select 1 from nutrition_update where compact like '%nutrition_text_is_safe_v41c(normalized_title,120)%' and compact like '%nutrition_text_is_safe_v41c(normalized_description,2000)%'),'create and update normalize and validate title and description'
  union all select '110_patient_rpc_requires_local_date',to_regprocedure('public.list_my_assigned_nutrition_plans(date)') is not null and exists(select 1 from nutrition_student_list where arguments like '%target_local_date date%'),'patient RPC requires target_local_date'
  union all select '111_legacy_patient_rpc_absent',to_regprocedure('public.list_my_assigned_nutrition_plans()') is null,'legacy no-argument patient RPC is absent'
  union all select '112_local_date_range_validated',exists(select 1 from nutrition_student_list where compact like '%target_local_dateisnull%' and compact like '%target_local_date<current_date-1%' and compact like '%target_local_date>current_date+1%' and compact like '%invalid_local_date%'),'local date is required and limited to server date plus or minus one day'
  union all select '113_is_current_uses_target_local_date',exists(select 1 from nutrition_student_list where compact like '%effective_from<=target_local_date%' and compact like '%effective_until>=target_local_date%' and compact not like '%effective_from<=current_date%' and compact not like '%effective_until>=current_date%'),'isCurrent uses target_local_date, not current_date'
  union all select '114_all_internal_helpers_no_frontend_execute',not exists(select 1 from functions function_record cross join lateral aclexplode(coalesce(function_record.proacl,acldefault('f',function_record.proowner))) privilege where function_record.proname in ('notification_iso_date_is_valid_v41c','notification_metadata_is_safe_v41c','create_user_notification_v41c','notify_relationship_status_v41c','notify_workout_assignment_v41c','nutrition_text_is_safe_v41c','nutrition_unit_is_supported_v41c','validate_nutrition_plan_payload_v41c','assert_my_nutritionist_identity_v41c','assert_my_nutritionist_write_access_v41c','protect_nutrition_assignment_snapshot_v41c','notify_nutrition_assignment_v41c') and privilege.privilege_type='EXECUTE' and (privilege.grantee='0'::oid or privilege.grantee in (coalesce(to_regrole('anon')::oid,'0'::oid),coalesce(to_regrole('authenticated')::oid,'0'::oid)))),'internal helpers are not executable by public, anon or authenticated'
  union all select '115_anon_no_nutrition_privileges',not has_table_privilege('anon','public.professional_nutrition_templates','SELECT,INSERT,UPDATE,DELETE') and not has_table_privilege('anon','public.student_nutrition_assignments','SELECT,INSERT,UPDATE,DELETE'),'anon has no nutrition table privileges'
  union all select '116_nutrition_rls_preserved',coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.professional_nutrition_templates')),false) and coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.student_nutrition_assignments')),false),'RLS remains enabled on both nutrition tables'
  union all select '117_no_nutrition_diary_reader',not exists(select 1 from functions where proname like '%nutrition%' and compact like any(array['%frompublic.meals%','%frompublic.diario%','%frompublic.food_logs%'])),'nutrition functions do not read personal diary data'
  union all select '118_no_nutrition_hydration_access',not exists(select 1 from functions where proname like '%nutrition%' and compact like '%public.hydration%'),'nutrition functions do not access hydration'
  union all select '119_nutrition_authority_structural',exists(select 1 from nutrition_identity where compact like '%primary_account_type=''nutritionist''%') and exists(select 1 from nutrition_assign where compact like '%professional_user_id=auth.uid()%' and compact like '%professional_type=''nutritionist''%' and compact like '%membership.rolein(''owner'',''admin'',''nutritionist'')%' and compact not like '%membership.role=''trainer''%' and compact not like '%membership.role=''student''%' and compact not like '%membership.rolein(''trainer''%' and compact not like '%membership.rolein(''student''%') and not exists(select 1 from nutrition_public_rpcs where arguments like '%professional_user_id%'),'nutrition authority requires nutritionist identity, owned relationship, allowed organization role, and no arbitrary professional id'
  union all select '120_metadata_values_and_keys_restricted',exists(select 1 from notification_metadata_helper where compact like '%notin(''professionaltype'',''version'',''effectivefrom'',''severity'',''action'',''route'',''code'')%' and compact like '%@[[:alnum:].-]+[.]%'),'metadata uses an exact key allowlist and rejects email-like values'
  union all select '121_metadata_rejects_containers',not public.notification_metadata_is_safe_v41c('{"action":[]}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"action":{"code":"nested"}}'::jsonb),'metadata rejects arrays and nested objects'
  union all select '122_metadata_professional_type_typed',public.notification_metadata_is_safe_v41c('{"professionalType":"trainer"}'::jsonb) and public.notification_metadata_is_safe_v41c('{"professionalType":"nutritionist"}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"professionalType":"doctor"}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"professionalType":true}'::jsonb),'professionalType accepts only trainer or nutritionist strings'
  union all select '123_metadata_version_typed',public.notification_metadata_is_safe_v41c('{"version":1}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"version":0}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"version":1.5}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"version":"1"}'::jsonb),'version is a positive bounded integer'
  union all select '124_metadata_effective_from_typed',public.notification_metadata_is_safe_v41c('{"effectiveFrom":"2026-07-15"}'::jsonb) and public.notification_metadata_is_safe_v41c('{"effectiveFrom":null}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"effectiveFrom":"15/07/2026"}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"effectiveFrom":"2026-13-15"}'::jsonb),'effectiveFrom accepts YYYY-MM-DD or null'
  union all select '125_metadata_route_internal_only',public.notification_metadata_is_safe_v41c('{"route":"treino"}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"route":"https://example.com"}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"route":"javascript:alert(1)"}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"route":"treino?email=user@example.com"}'::jsonb),'route accepts only known internal Forja destinations'
  union all select '126_metadata_action_code_limits',public.notification_metadata_is_safe_v41c('{"action":"open_plan","code":"plan.updated"}'::jsonb) and not public.notification_metadata_is_safe_v41c(jsonb_build_object('action',repeat('a',81))) and not public.notification_metadata_is_safe_v41c(jsonb_build_object('code',repeat('a',81))),'action and code are typed and limited to 80 characters'
  union all select '127_metadata_unknown_key_blocked',not public.notification_metadata_is_safe_v41c('{"patientName":"Pessoa"}'::jsonb),'unknown metadata keys are rejected'
  union all select '128_metadata_sensitive_values_blocked',not public.notification_metadata_is_safe_v41c('{"action":"email user@example.com"}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"action":"ligar 11999999999"}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"code":"12345678901"}'::jsonb),'email and phone or CPF-like sequences remain blocked'
  union all select '129_trigger_metadata_remains_valid',public.notification_metadata_is_safe_v41c('{"professionalType":"trainer"}'::jsonb) and public.notification_metadata_is_safe_v41c('{"professionalType":"nutritionist"}'::jsonb) and public.notification_metadata_is_safe_v41c('{"version":1}'::jsonb) and public.notification_metadata_is_safe_v41c('{"version":2,"effectiveFrom":"2026-07-15"}'::jsonb),'all flat metadata currently emitted by triggers remains valid'
  union all select '130_metadata_helper_has_no_recursion',exists(select 1 from notification_metadata_helper where definition not like '%with recursive%' and definition not like '%jsonb_array_elements%' and definition not like '%depth%'),'metadata helper has no recursive traversal'
  union all select '131_notification_actor_validated',exists(select 1 from notification_helper where compact like '%target_actor_user_idisnotnullandnotexists(select1fromauth.users%' and compact like '%notification_actor_not_found%') and exists(select 1 from notification_list_rpc where compact not like '%actor_user_id%'),'non-null actor must exist and public notification RPC does not return actor_user_id'
  union all select '132_manageable_plan_validity_returned',exists(select 1 from nutrition_manageable_list where compact like '%''currentassignmentstatus'',assignment.status%' and compact like '%''effectivefrom'',assignment.effective_from%' and compact like '%''effectiveuntil'',assignment.effective_until%'),'manageable patient list returns active assignment status and validity dates'
  union all select '133_manageable_plan_uses_active_only',exists(select 1 from nutrition_manageable_list where compact like '%leftjoinpublic.student_nutrition_assignmentsassignmentonassignment.relationship_id=relationship.idandassignment.status=''active''%' and compact not like '%status=''superseded''%'),'manageable patient list never substitutes a superseded assignment for the current one'
  union all select '134_manageable_plan_absence_safe',exists(select 1 from nutrition_manageable_list where compact like '%leftjoinpublic.student_nutrition_assignments%' and compact like '%''currentassignmentid'',assignment.id%' and compact not like '%coalesce(assignment.id%'),'missing active assignment leaves assignment fields null'
  union all select '135_metadata_action_html_blocked',not public.notification_metadata_is_safe_v41c('{"action":"<strong>abrir</strong>"}'::jsonb) and not public.notification_metadata_is_safe_v41c('{"action":"<script"}'::jsonb),'action rejects HTML markup indicators'
  union all select '136_metadata_real_iso_dates',public.notification_iso_date_is_valid_v41c('2026-02-28') and not public.notification_iso_date_is_valid_v41c('2026-02-31') and not public.notification_iso_date_is_valid_v41c('2026-13-01'),'effectiveFrom validation rejects impossible calendar dates'
  union all select '137_dedupe_constraint_normalized',exists(select 1 from notification_constraints where conname='user_notifications_dedupe_key_check' and compact like '%dedupe_key=btrim(dedupe_key)%' and (compact like '%char_length(btrim(dedupe_key))between1and200%' or (compact like '%char_length(btrim(dedupe_key))>=1%' and compact like '%char_length(btrim(dedupe_key))<=200%'))),'dedupe_key is stored trimmed and bounded'
  union all select '138_dedupe_helper_normalizes',exists(select 1 from notification_helper where compact like '%normalized_dedupe_key%' and compact like '%btrim(target_dedupe_key)%' and compact like '%dedupe_key=normalized_dedupe_key%'),'notification helper normalizes dedupe_key before insert and lookup'
  union all select '139_expired_notifications_filtered',exists(select 1 from notification_list_rpc where compact like '%expires_atisnullornotification.expires_at>now()%') and exists(select 1 from policies where tablename='user_notifications' and expression like '%expires_at%now()%'),'RPC and direct SELECT policy exclude expired notifications'
  union all select '140_notification_limit_rejects_null',exists(select 1 from notification_list_rpc where compact like '%target_limitisnullortarget_limitnotbetween1and100%'),'notification list rejects NULL and out-of-range limits'
  union all select '141_template_payload_constraint_validated',exists(select 1 from template_constraints where conname='professional_nutrition_templates_plan_check' and contype='c' and convalidated and compact like '%validate_nutrition_plan_payload_v41c(plan_data)%'),'template payload constraint exists and is validated'
  union all select '142_assignment_payload_constraint_validated',exists(select 1 from assignment_constraints where conname='student_nutrition_assignments_plan_check' and contype='c' and convalidated and compact like '%validate_nutrition_plan_payload_v41c(plan_data_snapshot)%'),'assignment payload constraint exists and is validated'
  union all select '143_active_assignment_index_ready',exists(select 1 from nutrition_indexes where table_name='student_nutrition_assignments' and index_name='student_nutrition_assignments_one_active_idx' and indisunique and indisvalid and indisready and definition like '%where(status=''active''%'),'one-active partial unique index is valid and ready'
  union all select '144_relationship_version_unique_validated',exists(select 1 from assignment_constraints where conname='student_nutrition_assignments_relationship_version_key' and contype='u' and convalidated and compact like '%unique(relationship_id,assignment_version)%'),'relationship/version uniqueness is validated'
  union all select '145_no_fragile_scope_boolean_casts',not exists(select 1 from functions where compact like '%manage_nutrition_plan%::boolean%') and not exists(select 1 from policies where expression like '%manage_nutrition_plan%::boolean%'),'authorization uses typed JSONB containment without text-to-boolean casts'
  union all select '146_exact_nutrition_select_policies',(select count(*)=2 and bool_and(cmd='SELECT' and roles='{authenticated}'::name[] and permissive='PERMISSIVE' and with_check='') from policies where tablename in ('professional_nutrition_templates','student_nutrition_assignments')),'nutrition tables expose exactly the two authenticated ownership/relationship SELECT policies'
  union all select '147_notification_select_policy_expiry',(select count(*)=1 and bool_and(cmd='SELECT' and roles='{authenticated}'::name[] and expression like '%recipient_user_id = auth.uid()%' and expression like '%expires_at%') from policies where tablename='user_notifications'),'notification table has one authenticated own-and-unexpired SELECT policy'
),
integrity_checks as (
  select '148_data_template_payloads_valid' check_name,invalid_template_payloads=0 passed,'DATA' category,'CRITICAL' severity,invalid_template_payloads::text found_value,'0' expected_value,'stored template payloads accepted by validator' details from data_metrics
  union all select '149_data_assignment_payloads_valid',invalid_assignment_payloads=0,'DATA','CRITICAL',invalid_assignment_payloads::text,'0','stored assignment snapshots accepted by validator' from data_metrics
  union all select '150_data_one_active_per_relationship',multiple_active_relationships=0,'DATA','CRITICAL',multiple_active_relationships::text,'0','relationships with more than one active assignment' from data_metrics
  union all select '151_data_versions_unique',duplicate_assignment_versions=0,'DATA','CRITICAL',duplicate_assignment_versions::text,'0','duplicated relationship and version combinations' from data_metrics
  union all select '152_data_active_relationships_compatible',invalid_active_relationships=0,'DATA','CRITICAL',invalid_active_relationships::text,'0','active assignments require an active scoped nutritionist relationship and compatible owner' from data_metrics
  union all select '153_data_organizations_compatible',organization_mismatches=0,'DATA','CRITICAL',organization_mismatches::text,'0','template, relationship and optional assignment organization must agree' from data_metrics
  union all select '154_data_assignment_dates_consistent',inconsistent_assignment_dates=0,'DATA','CRITICAL',inconsistent_assignment_dates::text,'0','effective and status timestamps must be coherent' from data_metrics
  union all select '155_data_dedupe_keys_valid',invalid_dedupe_keys=0,'DATA','CRITICAL',invalid_dedupe_keys::text,'0','dedupe keys must be trimmed, non-empty and bounded' from data_metrics
  union all select '156_data_dedupe_unique',duplicate_dedupe_keys=0,'DATA','CRITICAL',duplicate_dedupe_keys::text,'0','normalized recipient and dedupe key combinations must be unique' from data_metrics
  union all select '157_data_metadata_dates_valid',invalid_metadata_dates=0,'DATA','CRITICAL',invalid_metadata_dates::text,'0','metadata effectiveFrom values must be real ISO dates' from data_metrics
  union all select '158_data_notifications_have_user',notifications_without_user=0,'DATA','CRITICAL',notifications_without_user::text,'0','notifications require a recipient user' from data_metrics
  union all select '159_data_notification_types_valid',invalid_notification_types=0,'DATA','CRITICAL',invalid_notification_types::text,'0','notification types must belong to the allowlist' from data_metrics
),
warning_checks as (
  select '160_inactive_relationship_history' check_name,historical_assignments_on_inactive_relationships=0 passed,'DATA' category,'WARNING' severity,historical_assignments_on_inactive_relationships::text found_value,'0 preferred' expected_value,'historical assignments linked to inactive relationships are retained but should be reviewed' details from data_metrics
  union all select '161_expired_notifications_retained',expired_notifications=0,'DATA','WARNING',expired_notifications::text,'0 preferred','expired notifications are retained for history but excluded from reads' from data_metrics
),
all_checks as (
  select check_name,passed,'STRUCTURE'::text category,'CRITICAL'::text severity,passed::text found_value,'true'::text expected_value,details from checks
  union all select check_name,passed,category,severity,found_value,expected_value,details from integrity_checks
  union all select check_name,passed,category,severity,found_value,expected_value,details from warning_checks
)
select
  check_name,
  passed,
  category,
  severity,
  found_value,
  expected_value,
  details
from all_checks;

select
  case
    when severity = 'WARNING' and passed is not true then 'WARN'
    when passed is true then 'PASS'
    else 'FAIL'
  end as result,
  check_name,
  category,
  severity,
  passed,
  found_value,
  expected_value,
  details,
  count(*) over () as total_checks,
  count(*) filter (where passed is true) over () as passed_checks,
  count(*) filter (where passed is not true) over () as failed_checks,
  count(*) filter (where severity = 'WARNING' and passed is not true) over () as warning_checks,
  case
    when bool_or(severity = 'CRITICAL' and passed is not true) over () then 'FAIL'
    when bool_or(severity = 'WARNING' and passed is not true) over () then 'WARN'
    else 'PASS'
  end as overall_result
from pg_temp.v41c_verify_results
order by check_name;

do $v41c_verify$
declare
  total_check_count integer;
  critical_check_count integer;
  critical_failure_count integer;
  critical_failure_details text;
begin
  select count(*)
  into total_check_count
  from pg_temp.v41c_verify_results;

  if total_check_count = 0 then
    raise exception 'V4.1C VERIFY FAILED: no verification results were produced'
      using errcode = 'P0001';
  end if;

  select count(*)
  into critical_check_count
  from pg_temp.v41c_verify_results
  where severity = 'CRITICAL';

  if critical_check_count = 0 then
    raise exception 'V4.1C VERIFY FAILED: no critical verification results were produced'
      using errcode = 'P0001';
  end if;

  select
    count(*),
    string_agg(
      check_name || ' [found=' || coalesce(found_value, 'null') ||
      ', expected=' || coalesce(expected_value, 'null') || ']',
      '; ' order by check_name
    )
  into critical_failure_count, critical_failure_details
  from pg_temp.v41c_verify_results
  where severity = 'CRITICAL'
    and passed is not true;

  if critical_failure_count > 0 then
    raise exception 'V4.1C VERIFY FAILED: % critical check(s) failed', critical_failure_count
      using
        errcode = 'P0001',
        detail = critical_failure_details,
        hint = 'Review every failed critical check before considering V4.1C published.';
  end if;
end;
$v41c_verify$;

commit;
