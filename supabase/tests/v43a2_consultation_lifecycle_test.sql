begin;

set local search_path = public, extensions;
select no_plan();

-- Lock-order contract for every writer: relationship -> consultation -> lease.
-- The separate-session matrix in scripts/test-consultation-lifecycle.mjs proves:
-- editor A vs editor B save race; save vs explicit takeover; save vs discard;
-- heartbeat vs takeover; relationship revocation vs save; finalization vs save.

select has_table('public', 'consultation_edit_leases', 'server-owned consultation leases exist');
select has_table('public', 'consultation_save_receipts', 'content-free autosave idempotency receipts exist');

select has_function('public', 'get_consultation_lifecycle_constants_v43', array[]::text[], 'editing constants are executable');
select has_function('public', 'create_my_consultation_v43', array['uuid','text','uuid','timestamp with time zone','text','smallint'], 'creation derives all actor and subject identity');
select has_function('public', 'reschedule_my_consultation_v43', array['uuid','integer','timestamp with time zone','text','smallint'], 'reschedule uses optimistic schedule revision');
select has_function('public', 'acquire_my_consultation_lease_v43', array['uuid','text','text'], 'lease acquisition is purpose bounded');
select has_function('public', 'heartbeat_my_consultation_lease_v43', array['uuid','text','bigint'], 'heartbeat requires token and version');
select has_function('public', 'takeover_my_consultation_lease_v43', array['uuid','text','text','bigint'], 'takeover is explicit and revision aware');
select has_function('public', 'start_my_consultation_v43', array['uuid','text','bigint','bigint'], 'start is lease and revision protected');
select has_function('public', 'autosave_my_consultation_v43', array['uuid','text','bigint','bigint','uuid','jsonb'], 'autosave has no caller-supplied actor identity');
select has_function('public', 'pause_my_consultation_v43', array['uuid','text','bigint','bigint'], 'pause is protected');
select has_function('public', 'resume_my_consultation_v43', array['uuid','text','bigint'], 'resume issues a fresh edit lease');
select has_function('public', 'cancel_my_consultation_v43', array['uuid','text','bigint','bigint','text'], 'draft cancellation is protected');
select has_function('public', 'cancel_my_finalized_consultation_v43', array['uuid','text'], 'finalized cancellation is a bounded author action');
select has_function('public', 'mark_my_consultation_no_show_v43', array['uuid','text','bigint','bigint'], 'no-show uses database authority');
select has_function('public', 'archive_my_consultation_v43', array['uuid','bigint'], 'archive is an explicit lifecycle action');
select has_function('public', 'discard_my_consultation_v43', array['uuid','text','bigint','bigint','text'], 'normal discard is lease protected');
select has_function('public', 'cleanup_my_revoked_consultation_v43', array['uuid','bigint'], 'revoked-link cleanup is single purpose');
select has_function('public', 'finalize_my_consultation_v43', array['uuid','text','bigint','bigint'], 'finalization is lease and revision protected');

select is(
  public.get_consultation_lifecycle_constants_v43(),
  '{"autosaveDebounceMs":1200,"leaseHeartbeatSeconds":20,"leaseExpirySeconds":60,"deviceLabelMaxCodePoints":80}'::jsonb,
  'AUTOSAVE_DEBOUNCE_MS=1200, LEASE_HEARTBEAT_SECONDS=20 and LEASE_EXPIRY_SECONDS=60 are exact contracts'
);

select ok(
  (
    select count(*) = 2
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array['consultation_edit_leases','consultation_save_receipts'])
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'lease and receipt tables enable and force RLS'
);

select ok(
  not exists (
    select 1
    from unnest(array['consultation_edit_leases','consultation_save_receipts']) target(table_name)
    cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) privilege(privilege_name)
    where pg_catalog.has_table_privilege('authenticated', 'public.' || target.table_name, privilege.privilege_name)
       or pg_catalog.has_table_privilege('anon', 'public.' || target.table_name, privilege.privilege_name)
  ),
  'browser roles have no direct lease or receipt table privilege'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname like '%consultation%v43'
      and procedure.proname = any(array[
        'get_consultation_lifecycle_constants_v43','create_my_consultation_v43','reschedule_my_consultation_v43',
        'acquire_my_consultation_lease_v43','heartbeat_my_consultation_lease_v43','takeover_my_consultation_lease_v43',
        'start_my_consultation_v43','autosave_my_consultation_v43','pause_my_consultation_v43',
        'resume_my_consultation_v43','cancel_my_consultation_v43','cancel_my_finalized_consultation_v43',
        'mark_my_consultation_no_show_v43','archive_my_consultation_v43','discard_my_consultation_v43',
        'cleanup_my_revoked_consultation_v43','finalize_my_consultation_v43'
      ])
      and (
        not procedure.prosecdef
        or not exists (
          select 1 from unnest(coalesce(procedure.proconfig, array[]::text[])) config(setting)
          where pg_catalog.replace(config.setting, '"', '') = 'search_path='
        )
        or pg_catalog.has_function_privilege('anon', procedure.oid, 'EXECUTE')
      )
  ),
  'every public lifecycle RPC is a locked-down definer unavailable to anon'
);

-- Synthetic actors. All ordinary fixtures roll back with this file.
insert into auth.users (id, aud, role, email, created_at, updated_at)
values
  ('46000000-0000-0000-0000-000000000001','authenticated','authenticated','a2c-author@example.test',now(),now()),
  ('46000000-0000-0000-0000-000000000002','authenticated','authenticated','a2c-other-author@example.test',now(),now()),
  ('46000000-0000-0000-0000-000000000003','authenticated','authenticated','a2c-expired@example.test',now(),now()),
  ('46000000-0000-0000-0000-000000000004','authenticated','authenticated','a2c-org-admin@example.test',now(),now()),
  ('46000000-0000-0000-0000-000000000005','authenticated','authenticated','a2c-suspended-member@example.test',now(),now()),
  ('46000000-0000-0000-0000-000000000006','authenticated','authenticated','a2c-suspended-org@example.test',now(),now()),
  ('46000000-0000-0000-0000-000000000101','authenticated','authenticated','a2c-client@example.test',now(),now()),
  ('46000000-0000-0000-0000-000000000102','authenticated','authenticated','a2c-client-two@example.test',now(),now()),
  ('46000000-0000-0000-0000-000000000103','authenticated','authenticated','a2c-unrelated@example.test',now(),now());

insert into public.account_plan_catalog (code, account_type, display_name, active_client_limit, is_free, is_active)
values ('trainer_ci_v43a2c','trainer','Trainer CI V43A2C',30,true,true);

insert into public.user_commercial_accounts
  (user_id, primary_account_type, plan_code, subscription_status, personal_use_enabled)
values
  ('46000000-0000-0000-0000-000000000001','trainer','trainer_ci_v43a2c','active',true),
  ('46000000-0000-0000-0000-000000000002','trainer','trainer_ci_v43a2c','active',true),
  ('46000000-0000-0000-0000-000000000003','trainer','trainer_ci_v43a2c','past_due',true),
  ('46000000-0000-0000-0000-000000000005','trainer','trainer_ci_v43a2c','active',true),
  ('46000000-0000-0000-0000-000000000006','trainer','trainer_ci_v43a2c','active',true);

insert into public.user_account_modes (user_id, mode)
values
  ('46000000-0000-0000-0000-000000000001','trainer'),
  ('46000000-0000-0000-0000-000000000002','trainer'),
  ('46000000-0000-0000-0000-000000000003','trainer'),
  ('46000000-0000-0000-0000-000000000005','trainer'),
  ('46000000-0000-0000-0000-000000000006','trainer');

insert into public.user_identity_details (user_id, birth_date, age_status, age_verified_at)
values
  ('46000000-0000-0000-0000-000000000101',date '1990-01-01','adult',now()),
  ('46000000-0000-0000-0000-000000000102',date '1991-02-02','adult',now());

insert into public.organizations (id, name, slug, organization_type, owner_user_id, status)
values
  ('46200000-0000-0000-0000-000000000001','A2C Active','a2c-active','academy','46000000-0000-0000-0000-000000000004','active'),
  ('46200000-0000-0000-0000-000000000002','A2C Suspended','a2c-suspended','academy','46000000-0000-0000-0000-000000000004','suspended');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('46200000-0000-0000-0000-000000000001','46000000-0000-0000-0000-000000000004','owner','active'),
  ('46200000-0000-0000-0000-000000000001','46000000-0000-0000-0000-000000000001','trainer','active'),
  ('46200000-0000-0000-0000-000000000001','46000000-0000-0000-0000-000000000005','trainer','suspended'),
  ('46200000-0000-0000-0000-000000000002','46000000-0000-0000-0000-000000000006','trainer','active');

insert into public.professional_student_relationships
  (id, professional_user_id, student_user_id, professional_type, organization_id, status, scopes)
values
  ('46100000-0000-0000-0000-000000000001','46000000-0000-0000-0000-000000000001','46000000-0000-0000-0000-000000000101','trainer',null,'active','{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}'),
  ('46100000-0000-0000-0000-000000000002','46000000-0000-0000-0000-000000000002','46000000-0000-0000-0000-000000000101','trainer',null,'active','{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}'),
  ('46100000-0000-0000-0000-000000000003','46000000-0000-0000-0000-000000000001','46000000-0000-0000-0000-000000000102','trainer','46200000-0000-0000-0000-000000000001','active','{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}'),
  ('46100000-0000-0000-0000-000000000004','46000000-0000-0000-0000-000000000003','46000000-0000-0000-0000-000000000101','trainer',null,'active','{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}'),
  ('46100000-0000-0000-0000-000000000005','46000000-0000-0000-0000-000000000005','46000000-0000-0000-0000-000000000101','trainer','46200000-0000-0000-0000-000000000001','active','{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}'),
  ('46100000-0000-0000-0000-000000000006','46000000-0000-0000-0000-000000000006','46000000-0000-0000-0000-000000000101','trainer','46200000-0000-0000-0000-000000000002','active','{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}');

create temporary table a2c_results (
  result_key text primary key,
  consultation_id uuid,
  payload jsonb
) on commit drop;
grant select, insert, update, delete on table a2c_results to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
insert into a2c_results (result_key, consultation_id)
select 'created', public.create_my_consultation_v43(
  '46100000-0000-0000-0000-000000000001','initial',null,
  now() - interval '2 hours','UTC',0
);
insert into a2c_results (result_key, consultation_id)
select 'org-created', public.create_my_consultation_v43(
  '46100000-0000-0000-0000-000000000003','initial',null,null,null,null
);
reset role;

select ok(
  exists (
    select 1
    from a2c_results result
    join public.professional_consultations consultation on consultation.id = result.consultation_id
    join public.consultation_subjects subject on subject.id = consultation.subject_id
    join public.professional_student_relationships relationship on relationship.id = consultation.relationship_id
    where result.result_key = 'created'
      and subject.account_user_id = relationship.student_user_id
      and consultation.author_user_id = relationship.professional_user_id
      and consultation.professional_type = relationship.professional_type
      and consultation.organization_id is not distinct from relationship.organization_id
  ),
  'consultation_subjects.account_user_id matches source relationship student_user_id on creation'
);

select is(
  (select schedule_revision from public.professional_consultations where id = (select consultation_id from a2c_results where result_key='created')),
  1,
  'valid schedule metadata starts at schedule_revision 1'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select lives_ok(
  format(
    $$select public.reschedule_my_consultation_v43('%s',1,now() + interval '1 day','UTC',0)$$,
    (select consultation_id from a2c_results where result_key='created')
  ),
  'reschedule succeeds at the current schedule revision'
);
select throws_ok(
  format(
    $$select public.reschedule_my_consultation_v43('%s',1,now() + interval '2 days','UTC',0)$$,
    (select consultation_id from a2c_results where result_key='created')
  ),
  '55000','consultation_stale_revision','stale schedule revision is rejected'
);
reset role;

select is(
  (select schedule_revision from public.professional_consultations where id = (select consultation_id from a2c_results where result_key='created')),
  2,
  'schedule_revision increments monotonically and preserves instant/zone/offset consistency'
);

-- Seed exact-provenance lifecycle fixtures. The new binding trigger must accept these.
insert into public.professional_consultations
  (id,subject_id,author_user_id,relationship_id,professional_type,consultation_kind,status,scheduled_start_at,scheduled_time_zone,scheduled_utc_offset_minutes,schedule_revision,finalized_at)
select fixture.id, subject.id, '46000000-0000-0000-0000-000000000001', '46100000-0000-0000-0000-000000000001', 'trainer', 'initial', fixture.status,
       fixture.scheduled_start_at, fixture.zone, fixture.offset_minutes, fixture.schedule_revision,
       case when fixture.status = 'finalized' then now() else null end
from public.consultation_subjects subject
cross join (values
  ('46300000-0000-0000-0000-000000000001'::uuid,'scheduled'::text,null::timestamptz,null::text,null::smallint,0),
  ('46300000-0000-0000-0000-000000000002'::uuid,'scheduled',now()-interval '1 hour','UTC',0::smallint,1),
  ('46300000-0000-0000-0000-000000000003'::uuid,'scheduled',now()+interval '1 hour','UTC',0::smallint,1),
  ('46300000-0000-0000-0000-000000000004'::uuid,'in_progress',null,null,null,0),
  ('46300000-0000-0000-0000-000000000005'::uuid,'in_progress',null,null,null,0),
  ('46300000-0000-0000-0000-000000000006'::uuid,'in_progress',null,null,null,0),
  ('46300000-0000-0000-0000-000000000007'::uuid,'paused',null,null,null,0),
  ('46300000-0000-0000-0000-000000000008'::uuid,'paused',null,null,null,0),
  ('46300000-0000-0000-0000-000000000009'::uuid,'finalized',null,null,null,0),
  ('46300000-0000-0000-0000-000000000010'::uuid,'finalized',null,null,null,0),
  ('46300000-0000-0000-0000-000000000011'::uuid,'cancelled',null,null,null,0),
  ('46300000-0000-0000-0000-000000000012'::uuid,'no_show',now()-interval '1 day','UTC',0::smallint,1),
  ('46300000-0000-0000-0000-000000000013'::uuid,'archived',null,null,null,0)
) fixture(id,status,scheduled_start_at,zone,offset_minutes,schedule_revision)
where subject.account_user_id = '46000000-0000-0000-0000-000000000101';

insert into public.consultation_final_snapshots
  (consultation_id,finalized_by_user_id,schema_version,canonical_payload)
values
  ('46300000-0000-0000-0000-000000000009','46000000-0000-0000-0000-000000000001',1,'{"items":[]}'),
  ('46300000-0000-0000-0000-000000000010','46000000-0000-0000-0000-000000000001',1,'{"items":[]}');

-- Acquire exact leases for all editable fixtures and retain raw tokens only in pg_temp.
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
insert into a2c_results(result_key,consultation_id,payload)
select 'lease-' || right(consultation.id::text,3), consultation.id,
       public.acquire_my_consultation_lease_v43(consultation.id,'  Device <script>\u0007 ' || repeat('x',100),'edit')
from public.professional_consultations consultation
where consultation.id = any(array[
  '46300000-0000-0000-0000-000000000001'::uuid,
  '46300000-0000-0000-0000-000000000002'::uuid,
  '46300000-0000-0000-0000-000000000003'::uuid,
  '46300000-0000-0000-0000-000000000004'::uuid,
  '46300000-0000-0000-0000-000000000005'::uuid,
  '46300000-0000-0000-0000-000000000006'::uuid
])
order by consultation.id;
reset role;

select ok(
  not exists (
    select 1 from public.consultation_edit_leases lease
    join a2c_results result on result.consultation_id = lease.consultation_id
    where pg_catalog.encode(lease.token_verifier,'hex') = result.payload->>'leaseToken'
       or lease.token_verifier = pg_catalog.convert_to(result.payload->>'leaseToken','UTF8')
  ),
  'raw lease token is NEVER stored and verifier cannot recover the raw token'
);

select ok(
  (select count(*) = count(distinct consultation_id) from public.consultation_edit_leases),
  'one active lease row exists per consultation'
);

select ok(
  not exists (
    select 1 from public.consultation_edit_leases
    where char_length(device_label) > 80
       or device_label ~ '[[:cntrl:]]'
  ),
  'device labels are plain text with at most 80 Unicode code points'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select throws_ok(
  $$select public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000001','second editor','edit')$$,
  '55000','consultation_stale_lease','a second editor cannot silently acquire an active lease'
);
select throws_ok(
  $$select public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000001','invalid purpose','publish')$$,
  '22023','consultation_validation_failed','lease purpose remains bounded to edit or discard'
);
insert into a2c_results(result_key,consultation_id,payload)
select 'takeover', '46300000-0000-0000-0000-000000000001',
  public.takeover_my_consultation_lease_v43('46300000-0000-0000-0000-000000000001','explicit takeover','edit',0);
select throws_ok(
  format(
    $$select public.heartbeat_my_consultation_lease_v43('46300000-0000-0000-0000-000000000001','%s',%s)$$,
    (select payload->>'leaseToken' from a2c_results where result_key='lease-001'),
    (select payload->>'leaseVersion' from a2c_results where result_key='lease-001')
  ),
  '55000','consultation_lease_taken_over','takeover invalidates previous heartbeat immediately'
);
reset role;

select ok(
  (select (payload->>'leaseVersion')::bigint from a2c_results where result_key='takeover')
    > (select (payload->>'leaseVersion')::bigint from a2c_results where result_key='lease-001'),
  'explicit takeover increments lease version'
);
select is(
  (select count(*) from public.consultation_events where consultation_id='46300000-0000-0000-0000-000000000001' and event_type='lease_takeover'),
  1::bigint,
  'takeover is audited without token or content'
);

-- Heartbeat uses database time and extends exactly the 60-second expiry contract.
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select lives_ok(
  format(
    $$select public.heartbeat_my_consultation_lease_v43('46300000-0000-0000-0000-000000000001','%s',%s)$$,
    (select payload->>'leaseToken' from a2c_results where result_key='takeover'),
    (select payload->>'leaseVersion' from a2c_results where result_key='takeover')
  ),
  'valid heartbeat refreshes the lease'
);
reset role;
select ok(
  exists (
    select 1 from public.consultation_edit_leases
    where consultation_id='46300000-0000-0000-0000-000000000001'
      and heartbeat_at between statement_timestamp()-interval '2 seconds' and statement_timestamp()+interval '2 seconds'
      and expires_at = heartbeat_at + interval '60 seconds'
  ),
  'heartbeat and expiry use database time'
);

-- Lifecycle matrix: scheduled -> in_progress/cancelled/no_show.
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select lives_ok(format(
  $$select public.start_my_consultation_v43('46300000-0000-0000-0000-000000000001','%s',%s,0)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='takeover'),
  (select payload->>'leaseVersion' from a2c_results where result_key='takeover')
), 'scheduled -> in_progress is allowed');
select lives_ok(format(
  $$select public.cancel_my_consultation_v43('46300000-0000-0000-0000-000000000002','%s',%s,0,'author_cancelled')$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-002'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-002')
), 'scheduled -> cancelled is allowed');
select throws_ok(format(
  $$select public.mark_my_consultation_no_show_v43('46300000-0000-0000-0000-000000000002','%s',%s,0)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-002'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-002')
), '55000','consultation_invalid_lifecycle_state','cancelled cannot be repurposed as no_show');
reset role;

-- The previous statement must be denied once implementation exists; keep an explicit fresh past fixture for allowed no-show.
insert into public.professional_consultations
  (id,subject_id,author_user_id,relationship_id,professional_type,consultation_kind,status,scheduled_start_at,scheduled_time_zone,scheduled_utc_offset_minutes,schedule_revision)
select '46300000-0000-0000-0000-000000000014',id,'46000000-0000-0000-0000-000000000001','46100000-0000-0000-0000-000000000001','trainer','initial','scheduled',now()-interval '1 hour','UTC',0,1
from public.consultation_subjects where account_user_id='46000000-0000-0000-0000-000000000101';
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
insert into a2c_results(result_key,consultation_id,payload)
values ('lease-014','46300000-0000-0000-0000-000000000014',public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000014','no-show','edit'));
select lives_ok(format(
  $$select public.mark_my_consultation_no_show_v43('46300000-0000-0000-0000-000000000014','%s',%s,0)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-014'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-014')
), 'scheduled -> no_show is allowed after the database scheduled instant');
select throws_ok(format(
  $$select public.mark_my_consultation_no_show_v43('46300000-0000-0000-0000-000000000003','%s',%s,0)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-003'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-003')
), '55000','consultation_invalid_lifecycle_state','no_show is denied before persisted scheduled instant using database time');
reset role;

-- in_progress -> paused/finalized/cancelled; pause/finalization invalidate leases.
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select lives_ok(format(
  $$select public.pause_my_consultation_v43('46300000-0000-0000-0000-000000000004','%s',%s,0)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-004'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-004')
), 'in_progress -> paused is allowed and invalidates its lease');
insert into a2c_results(result_key,consultation_id,payload)
values ('resume-004','46300000-0000-0000-0000-000000000004',public.resume_my_consultation_v43('46300000-0000-0000-0000-000000000004','resume device',0));
select is((select status from public.professional_consultations where id='46300000-0000-0000-0000-000000000004'),'in_progress','paused -> in_progress is allowed with a fresh lease');
select lives_ok(format(
  $$select public.finalize_my_consultation_v43('46300000-0000-0000-0000-000000000005','%s',%s,0)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-005'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-005')
), 'in_progress -> finalized is allowed');
select lives_ok(format(
  $$select public.cancel_my_consultation_v43('46300000-0000-0000-0000-000000000006','%s',%s,0,'author_cancelled')$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-006'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-006')
), 'in_progress -> cancelled is allowed');
reset role;

select ok(
  exists (
    select 1 from public.consultation_final_snapshots snapshot
    join public.professional_consultations consultation on consultation.id=snapshot.consultation_id
    where consultation.id='46300000-0000-0000-0000-000000000005'
      and consultation.status='finalized'
      and snapshot.canonicalization_version='forja.canonical-json.v1'
      and octet_length(snapshot.payload_sha256)=32
      and snapshot.payload_sha256=extensions.digest(snapshot.canonical_bytes,'sha256')
  ),
  'finalization builds immutable canonical bytes and SHA-256 atomically'
);
select ok(
  not exists (select 1 from public.consultation_edit_leases where consultation_id='46300000-0000-0000-0000-000000000005' and invalidated_at is null),
  'finalization invalidates the active lease'
);

-- Finalized -> archived/cancelled, cancelled/no_show -> archived.
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select lives_ok($$select public.archive_my_consultation_v43('46300000-0000-0000-0000-000000000009',0)$$,'finalized -> archived is allowed through bounded RPC');
select lives_ok($$select public.cancel_my_finalized_consultation_v43('46300000-0000-0000-0000-000000000010','administrative_correction')$$,'finalized -> cancelled requires approved author reason');
select lives_ok($$select public.archive_my_consultation_v43('46300000-0000-0000-0000-000000000011',0)$$,'cancelled -> archived is allowed');
select lives_ok($$select public.archive_my_consultation_v43('46300000-0000-0000-0000-000000000012',0)$$,'no_show -> archived is allowed');
select throws_ok($$select public.archive_my_consultation_v43('46300000-0000-0000-0000-000000000013',0)$$,'55000','consultation_invalid_lifecycle_state','archived -> anything is denied');
select throws_ok($$select public.resume_my_consultation_v43('46300000-0000-0000-0000-000000000010','reopen',0)$$,'55000','consultation_invalid_lifecycle_state','finalized cannot return to in_progress or paused');
reset role;

-- Autosave optimistic concurrency, bounded patch and idempotency.
insert into public.professional_consultations
  (id,subject_id,author_user_id,relationship_id,professional_type,consultation_kind,status)
select fixture.id,id,'46000000-0000-0000-0000-000000000001','46100000-0000-0000-0000-000000000001','trainer','initial','scheduled'
from public.consultation_subjects
cross join (values
  ('46300000-0000-0000-0000-000000000020'::uuid),
  ('46300000-0000-0000-0000-000000000021'::uuid)
) fixture(id)
where account_user_id='46000000-0000-0000-0000-000000000101';
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
insert into a2c_results(result_key,consultation_id,payload)
values
  ('lease-020','46300000-0000-0000-0000-000000000020',public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000020','save A','edit')),
  ('lease-021','46300000-0000-0000-0000-000000000021',public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000021','save B','edit'));
insert into a2c_results(result_key,consultation_id,payload)
select 'save-020','46300000-0000-0000-0000-000000000020',public.autosave_my_consultation_v43(
  '46300000-0000-0000-0000-000000000020',
  (select payload->>'leaseToken' from a2c_results where result_key='lease-020'),
  (select (payload->>'leaseVersion')::bigint from a2c_results where result_key='lease-020'),
  0,'46400000-0000-0000-0000-000000000001',
  '[{"itemKey":"common.goal","itemKind":"text","value":{"text":"first"}}]'::jsonb
);
select is((select draft_revision from public.professional_consultations where id='46300000-0000-0000-0000-000000000020'),1::bigint,'correct revision saves exactly once and increments draft_revision');
select is(
  (public.autosave_my_consultation_v43(
    '46300000-0000-0000-0000-000000000020',
    (select payload->>'leaseToken' from a2c_results where result_key='lease-020'),
    (select (payload->>'leaseVersion')::bigint from a2c_results where result_key='lease-020'),
    0,'46400000-0000-0000-0000-000000000001',
    '[{"itemKey":"common.goal","itemKind":"text","value":{"text":"ignored duplicate"}}]'::jsonb
  )->>'idempotent')::boolean,true,'duplicate correlation ID is deduplicated without mutation');
select throws_ok(format(
  $$select public.autosave_my_consultation_v43('46300000-0000-0000-0000-000000000020','%s',%s,0,'46400000-0000-0000-0000-000000000002','[{"itemKey":"common.goal","itemKind":"text","value":{"text":"stale"}}]'::jsonb)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-020'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-020')
),'55000','consultation_stale_revision','stale revision returns stable conflict and cannot overwrite');
select throws_ok(format(
  $$select public.autosave_my_consultation_v43('46300000-0000-0000-0000-000000000020','%s',%s,1,'46400000-0000-0000-0000-000000000003','[{"itemKey":"common.goal","itemKind":"text","expectedOriginalValue":{"text":"wrong"},"value":{"text":"overwrite"}},{"itemKey":"common.second","itemKind":"text","value":{"text":"partial"}}]'::jsonb)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-020'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-020')
),'55000','consultation_stale_revision','expectedOriginalValue mismatch rejects the whole patch');
reset role;
select is((select value_payload from public.consultation_items where consultation_id='46300000-0000-0000-0000-000000000020' and item_key='common.goal'),'{"text":"first"}'::jsonb,'stale save never overwrites current content');
select is((select count(*) from public.consultation_items where consultation_id='46300000-0000-0000-0000-000000000020' and item_key='common.second'),0::bigint,'conflict causes no partial mutation');

-- Correlation IDs are scoped to author + consultation and never grant authority.
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000002',true);
select throws_ok(
  $$select public.autosave_my_consultation_v43('46300000-0000-0000-0000-000000000020','not-a-token',1,1,'46400000-0000-0000-0000-000000000001','[]'::jsonb)$$,
  '42501','consultation_unauthorized','same correlation ID grants unrelated author no access'
);
reset role;

-- Expiry, wrong consultation, wrong token and lease version participate in writes.
update public.consultation_edit_leases
set heartbeat_at=now()-interval '61 seconds', expires_at=now()-interval '1 second'
where consultation_id='46300000-0000-0000-0000-000000000021';
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select throws_ok(format(
  $$select public.heartbeat_my_consultation_lease_v43('46300000-0000-0000-0000-000000000021','%s',%s)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-021'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-021')
),'55000','consultation_expired_lease','expiry occurs after 60 seconds without accepted heartbeat');
select throws_ok(format(
  $$select public.autosave_my_consultation_v43('46300000-0000-0000-0000-000000000021','%s',%s,0,'46400000-0000-0000-0000-000000000004','[]'::jsonb)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-021'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-021')
),'55000','consultation_expired_lease','expired lease cannot save');
select throws_ok(format(
  $$select public.autosave_my_consultation_v43('46300000-0000-0000-0000-000000000020','%s',%s,1,'46400000-0000-0000-0000-000000000005','[]'::jsonb)$$,
  (select payload->>'leaseToken' from a2c_results where result_key='lease-021'),
  (select payload->>'leaseVersion' from a2c_results where result_key='lease-021')
),'55000','consultation_stale_lease','token from consultation A cannot operate on consultation B');
reset role;

-- Actor and entitlement denials create neither lease nor misleading event.
insert into public.professional_consultations
  (id,subject_id,author_user_id,relationship_id,professional_type,organization_id,consultation_kind,status)
select fixture.id, subject.id, fixture.author_id, fixture.relationship_id, 'trainer', fixture.organization_id, 'initial', 'scheduled'
from (values
  ('46300000-0000-0000-0000-000000000030'::uuid,'46000000-0000-0000-0000-000000000003'::uuid,'46100000-0000-0000-0000-000000000004'::uuid,null::uuid),
  ('46300000-0000-0000-0000-000000000031'::uuid,'46000000-0000-0000-0000-000000000005'::uuid,'46100000-0000-0000-0000-000000000005'::uuid,'46200000-0000-0000-0000-000000000001'::uuid),
  ('46300000-0000-0000-0000-000000000032'::uuid,'46000000-0000-0000-0000-000000000006'::uuid,'46100000-0000-0000-0000-000000000006'::uuid,'46200000-0000-0000-0000-000000000002'::uuid)
) fixture(id,author_id,relationship_id,organization_id)
join public.consultation_subjects subject on subject.account_user_id='46000000-0000-0000-0000-000000000101';

set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000003',true);
select throws_ok($$select public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000030','expired','edit')$$,'42501',null,'subscription/write entitlement is required');
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000005',true);
select throws_ok($$select public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000031','suspended member','edit')$$,'42501',null,'active organization membership is required');
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000006',true);
select throws_ok($$select public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000032','suspended org','edit')$$,'42501',null,'active organization state is required');
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000004',true);
select throws_ok($$select public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000031','org admin','edit')$$,'42501','consultation_unauthorized','organization admin role alone is never clinical authority');
reset role;
select is((select count(*) from public.consultation_edit_leases where consultation_id in ('46300000-0000-0000-0000-000000000030','46300000-0000-0000-0000-000000000031','46300000-0000-0000-0000-000000000032')),0::bigint,'denied acquisition creates no lease');
select is((select count(*) from public.consultation_events where consultation_id in ('46300000-0000-0000-0000-000000000030','46300000-0000-0000-0000-000000000031','46300000-0000-0000-0000-000000000032')),0::bigint,'denied acquisition creates no misleading audit event');

-- Relationship revocation atomically blocks authorization, invalidates leases and cancels active drafts.
insert into public.professional_consultations
  (id,subject_id,author_user_id,relationship_id,professional_type,organization_id,consultation_kind,status)
select fixture.id,subject.id,'46000000-0000-0000-0000-000000000001','46100000-0000-0000-0000-000000000003','trainer','46200000-0000-0000-0000-000000000001','initial',fixture.status
from public.consultation_subjects subject
cross join (values
  ('46300000-0000-0000-0000-000000000040'::uuid,'scheduled'::text),
  ('46300000-0000-0000-0000-000000000041'::uuid,'in_progress'::text),
  ('46300000-0000-0000-0000-000000000042'::uuid,'paused'::text)
) fixture(id,status)
where subject.account_user_id='46000000-0000-0000-0000-000000000102';
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
insert into a2c_results(result_key,consultation_id,payload)
values
  ('lease-040','46300000-0000-0000-0000-000000000040',public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000040','revoke scheduled','edit')),
  ('lease-041','46300000-0000-0000-0000-000000000041',public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000041','revoke progress','edit'));
reset role;
update public.professional_student_relationships set status='revoked' where id='46100000-0000-0000-0000-000000000003';
select is((select count(*) from public.professional_consultations where id in ('46300000-0000-0000-0000-000000000040','46300000-0000-0000-0000-000000000041','46300000-0000-0000-0000-000000000042') and status='cancelled'),3::bigint,'active -> revoked system-cancels every scheduled/in_progress/paused draft');
select is((select count(*) from public.consultation_events where consultation_id in ('46300000-0000-0000-0000-000000000040','46300000-0000-0000-0000-000000000041','46300000-0000-0000-0000-000000000042') and reason_category='relationship_revoked'),3::bigint,'revocation preserves content-free relationship_revoked audit metadata');
select ok(not exists(select 1 from public.consultation_edit_leases where consultation_id in ('46300000-0000-0000-0000-000000000040','46300000-0000-0000-0000-000000000041') and invalidated_at is null),'relationship revocation invalidates every active lease');
update public.professional_student_relationships set status='active' where id='46100000-0000-0000-0000-000000000003';
select is((select count(*) from public.professional_consultations where id in ('46300000-0000-0000-0000-000000000040','46300000-0000-0000-0000-000000000041','46300000-0000-0000-0000-000000000042') and status='cancelled'),3::bigint,'reactivation never reopens cancelled consultation');
select is((select (scopes->>'manage_consultations')::boolean from public.professional_student_relationships where id='46100000-0000-0000-0000-000000000003'),false,'reactivation does not restore old authorization');
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select throws_ok(format($$select public.heartbeat_my_consultation_lease_v43('46300000-0000-0000-0000-000000000040','%s',%s)$$,(select payload->>'leaseToken' from a2c_results where result_key='lease-040'),(select payload->>'leaseVersion' from a2c_results where result_key='lease-040')),'42501','consultation_relationship_revoked','old lease remains unusable after reactivation');
select throws_ok($$select public.resume_my_consultation_v43('46300000-0000-0000-0000-000000000042','reactivated',0)$$,'42501','consultation_relationship_revoked','reactivation cannot resume old cancelled draft');
reset role;

-- Revoked-link cleanup is the only post-revocation capability and preserves a content-free tombstone.
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select lives_ok($$select public.cleanup_my_revoked_consultation_v43('46300000-0000-0000-0000-000000000040',0)$$,'original author can cleanup already system-cancelled relationship_revoked draft');
select throws_ok($$select public.start_my_consultation_v43('46300000-0000-0000-0000-000000000041','not-a-token',1,0)$$,'42501','consultation_relationship_revoked','cleanup capability cannot restart or edit');
select throws_ok($$select public.finalize_my_consultation_v43('46300000-0000-0000-0000-000000000041','not-a-token',1,0)$$,'42501','consultation_relationship_revoked','cleanup capability cannot finalize');
reset role;
select ok(not exists(select 1 from public.professional_consultations where id='46300000-0000-0000-0000-000000000040'),'revoked cleanup deletes only eligible draft aggregate');
select ok(exists(select 1 from public.consultation_discard_tombstones where discarded_consultation_id='46300000-0000-0000-0000-000000000040' and reason_category='relationship_revoked_cleanup'),'revoked cleanup preserves approved opaque tombstone');

-- Normal discard requires valid current token/version/revision and never deletes finalized history.
insert into public.professional_consultations
  (id,subject_id,author_user_id,relationship_id,professional_type,consultation_kind,status)
select fixture.id,id,'46000000-0000-0000-0000-000000000001','46100000-0000-0000-0000-000000000001','trainer','initial',fixture.status
from public.consultation_subjects
cross join (values
  ('46300000-0000-0000-0000-000000000050'::uuid,'scheduled'::text),
  ('46300000-0000-0000-0000-000000000051'::uuid,'paused'::text)
) fixture(id,status)
where account_user_id='46000000-0000-0000-0000-000000000101';
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
insert into a2c_results(result_key,consultation_id,payload)
values ('lease-050','46300000-0000-0000-0000-000000000050',public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000050','discard active','edit'));
select throws_ok($$select public.discard_my_consultation_v43('46300000-0000-0000-0000-000000000050','wrong-token',1,0,'author_discard')$$,'55000','consultation_stale_lease','discard denies stale token');
select throws_ok(format($$select public.discard_my_consultation_v43('46300000-0000-0000-0000-000000000050','%s',%s,1,'author_discard')$$,(select payload->>'leaseToken' from a2c_results where result_key='lease-050'),(select payload->>'leaseVersion' from a2c_results where result_key='lease-050')),'55000','consultation_stale_revision','discard denies stale revision');
select lives_ok(format($$select public.discard_my_consultation_v43('46300000-0000-0000-0000-000000000050','%s',%s,0,'author_discard')$$,(select payload->>'leaseToken' from a2c_results where result_key='lease-050'),(select payload->>'leaseVersion' from a2c_results where result_key='lease-050')),'normal discard deletes an unpublished never-finalized draft exactly once');
insert into a2c_results(result_key,consultation_id,payload)
values ('lease-051','46300000-0000-0000-0000-000000000051',public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000051','paused discard','discard'));
select lives_ok(format($$select public.discard_my_consultation_v43('46300000-0000-0000-0000-000000000051','%s',%s,0,'author_discard')$$,(select payload->>'leaseToken' from a2c_results where result_key='lease-051'),(select payload->>'leaseVersion' from a2c_results where result_key='lease-051')),'paused discard first acquires an exclusive discard-capable lease');
select throws_ok($$select public.discard_my_consultation_v43('46300000-0000-0000-0000-000000000005','replayed',1,0,'author_discard')$$,'55000',null,'finalized consultation and replayed token cannot be discarded');
reset role;
select ok(exists(select 1 from public.consultation_final_snapshots where consultation_id='46300000-0000-0000-0000-000000000005'),'discard never deletes finalized history');

-- Direct provenance mismatch is blocked independently of browser/RPC authorization.
select throws_ok(
  $$insert into public.professional_consultations
    (subject_id,author_user_id,relationship_id,professional_type,consultation_kind,status)
    select id,'46000000-0000-0000-0000-000000000001','46100000-0000-0000-0000-000000000001','trainer','initial','scheduled'
    from public.consultation_subjects where account_user_id='46000000-0000-0000-0000-000000000102'$$,
  '23514','consultation_relationship_subject_mismatch',
  'writer paths reject consultation_subjects.account_user_id that differs from source relationship student_user_id'
);

-- Finalization failure is atomic: neither status nor partial snapshot survives.
insert into public.professional_consultations
  (id,subject_id,author_user_id,relationship_id,professional_type,consultation_kind,status)
select '46300000-0000-0000-0000-000000000060',id,'46000000-0000-0000-0000-000000000001','46100000-0000-0000-0000-000000000001','trainer','initial','in_progress'
from public.consultation_subjects where account_user_id='46000000-0000-0000-0000-000000000101';
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
insert into a2c_results(result_key,consultation_id,payload)
values ('lease-060','46300000-0000-0000-0000-000000000060',public.acquire_my_consultation_lease_v43('46300000-0000-0000-0000-000000000060','atomic finalization','edit'));
reset role;
create function pg_temp.reject_snapshot_for_atomic_test()
returns trigger language plpgsql set search_path='' as $$begin raise exception 'synthetic_snapshot_failure'; end$$;
create trigger reject_snapshot_for_atomic_test before insert on public.consultation_final_snapshots
for each row execute function pg_temp.reject_snapshot_for_atomic_test();
set local role authenticated;
select set_config('request.jwt.claim.sub','46000000-0000-0000-0000-000000000001',true);
select throws_ok(format($$select public.finalize_my_consultation_v43('46300000-0000-0000-0000-000000000060','%s',%s,0)$$,(select payload->>'leaseToken' from a2c_results where result_key='lease-060'),(select payload->>'leaseVersion' from a2c_results where result_key='lease-060')),'P0001','synthetic_snapshot_failure','failure while finalizing rolls back the full transaction');
reset role;
drop trigger reject_snapshot_for_atomic_test on public.consultation_final_snapshots;
select is((select status from public.professional_consultations where id='46300000-0000-0000-0000-000000000060'),'in_progress','failed finalization leaves lifecycle unchanged');
select is((select count(*) from public.consultation_final_snapshots where consultation_id='46300000-0000-0000-0000-000000000060'),0::bigint,'failed finalization leaves no partial snapshot');

-- Stable error vocabulary is bounded and content-free. These values must never contain tokens or field values.
select ok(
  not exists (
    select 1 from public.consultation_events event
    where event.event_type ~ '(token|payload|content|value)'
       or coalesce(event.reason_category,'') ~ '(token|payload|content|value)'
  ),
  'events remain bounded, content-free and non-secret'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid=relation.relnamespace
    where namespace.nspname in ('public','private')
      and relation.relname ~ '(cron|reminder|publication|attachment|offline)'
      and relation.relname like 'consultation_%'
  ),
  'A.2C adds no cron, reminders, publication, attachment or offline persistence'
);

select * from finish();
rollback;
