begin;

set local search_path = public, extensions;
select no_plan();

create or replace function pg_temp.safe_exec_v43a2(target_sql text)
returns boolean
language plpgsql
set search_path = ''
as $function$
begin
  execute target_sql;
  return true;
exception when others then
  return false;
end;
$function$;

create or replace function pg_temp.safe_count_v43a2(target_sql text)
returns bigint
language plpgsql
set search_path = ''
as $function$
declare
  result_count bigint;
begin
  execute target_sql into result_count;
  return result_count;
exception when others then
  return -1;
end;
$function$;

create or replace function pg_temp.safe_json_v43a2(target_sql text)
returns jsonb
language plpgsql
set search_path = ''
as $function$
declare
  result_value jsonb;
begin
  execute target_sql into result_value;
  return coalesce(result_value, 'null'::jsonb);
exception when others then
  return '[]'::jsonb;
end;
$function$;

-- Schema, ACL and immutable-history contract.
select has_table(
  'public',
  'consultation_authorization_text_versions',
  'server-owned authorization text versions exist'
);
select has_table(
  'public',
  'consultation_authorization_requests',
  'consultation authorization requests exist'
);
select has_table(
  'public',
  'consultation_authorization_events',
  'consultation authorization audit events exist'
);
select has_table(
  'public',
  'consultation_sharing_consents',
  'shared-history consent events exist'
);

select has_function(
  'public',
  'request_my_consultation_authorization_v43',
  array['uuid', 'text'],
  'professional request RPC accepts relationship and text version only'
);
select has_function(
  'public',
  'decide_my_consultation_authorization_v43',
  array['uuid', 'uuid', 'text', 'text'],
  'client decision RPC accepts no caller identity'
);
select has_function(
  'public',
  'revoke_my_consultation_authorization_v43',
  array['uuid', 'text'],
  'client revocation RPC accepts no caller identity'
);
select has_function(
  'public',
  'set_my_shared_consultation_history_consent_v43',
  array['uuid', 'text', 'boolean'],
  'shared-history consent RPC accepts no caller identity'
);
select has_function(
  'public',
  'list_my_manageable_consultation_subjects_v43',
  array['integer', 'uuid'],
  'manageable-subject selector is bounded'
);
select has_function(
  'public',
  'get_my_consultation_v43',
  array['uuid'],
  'author consultation projection is bounded to one consultation'
);
select has_function(
  'public',
  'list_shared_consultation_history_v43',
  array['uuid', 'integer'],
  'shared common-history projection is relationship-bound and bounded'
);

select ok(
  (
    select count(*) = 4
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'consultation_authorization_text_versions',
        'consultation_authorization_requests',
        'consultation_authorization_events',
        'consultation_sharing_consents'
      ])
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'all A.2B authorization tables enable and force RLS'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = any(array[
        'request_my_consultation_authorization_v43',
        'decide_my_consultation_authorization_v43',
        'revoke_my_consultation_authorization_v43',
        'set_my_shared_consultation_history_consent_v43',
        'list_my_manageable_consultation_subjects_v43',
        'get_my_consultation_v43',
        'list_shared_consultation_history_v43'
      ])
      and (
        not procedure.prosecdef
        or not exists (
          select 1
          from unnest(coalesce(procedure.proconfig, array[]::text[])) config(setting)
          where pg_catalog.replace(config.setting, '"', '') = 'search_path='
        )
      )
  )
  and (
    select count(*) = 7
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = any(array[
        'request_my_consultation_authorization_v43',
        'decide_my_consultation_authorization_v43',
        'revoke_my_consultation_authorization_v43',
        'set_my_shared_consultation_history_consent_v43',
        'list_my_manageable_consultation_subjects_v43',
        'get_my_consultation_v43',
        'list_shared_consultation_history_v43'
      ])
  ),
  'all public A.2B RPCs are SECURITY DEFINER with empty search_path'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    cross join lateral unnest(
      coalesce(procedure.proargnames, array[]::text[])
    ) argument(argument_name)
    where namespace.nspname = 'public'
      and procedure.proname = any(array[
        'request_my_consultation_authorization_v43',
        'decide_my_consultation_authorization_v43',
        'revoke_my_consultation_authorization_v43',
        'set_my_shared_consultation_history_consent_v43',
        'list_my_manageable_consultation_subjects_v43',
        'get_my_consultation_v43',
        'list_shared_consultation_history_v43'
      ])
      and argument.argument_name ~ '(professional|student|client|author)_user_id'
  ),
  'public RPC signatures expose no caller-supplied actor identity'
);

select ok(
  not exists (
    select 1
    from unnest(array[
      'consultation_subjects',
      'professional_consultations',
      'consultation_items',
      'consultation_authorization_text_versions',
      'consultation_authorization_requests',
      'consultation_authorization_events',
      'consultation_sharing_consents'
    ]) tables(table_name)
    cross join unnest(array['INSERT', 'UPDATE', 'DELETE']) privileges(privilege_name)
    where case
      when pg_catalog.to_regclass('public.' || tables.table_name) is null then true
      else pg_catalog.has_table_privilege(
        'authenticated',
        'public.' || tables.table_name,
        privileges.privilege_name
      ) or pg_catalog.has_table_privilege(
        'anon',
        'public.' || tables.table_name,
        privileges.privilege_name
      )
    end
  ),
  'browser roles have no direct mutation privilege on consultation state'
);

-- Synthetic actors and tenants. All rows roll back with this pgTAP file.
insert into auth.users (id, aud, role, email, created_at, updated_at)
values
  ('44000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'v43a2-trainer@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'v43a2-nutritionist@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'v43a2-other-trainer@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'v43a2-org-admin@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'v43a2-expired@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'v43a2-wrong-type@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000007', 'authenticated', 'authenticated', 'v43a2-suspended-member@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000008', 'authenticated', 'authenticated', 'v43a2-unrelated@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000009', 'authenticated', 'authenticated', 'v43a2-suspended-org-prof@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'v43a2-client@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'v43a2-other-client@example.test', now(), now()),
  ('44000000-0000-0000-0000-000000000103', 'authenticated', 'authenticated', 'v43a2-minor@example.test', now(), now());

insert into public.account_plan_catalog (
  code,
  account_type,
  display_name,
  active_client_limit,
  is_free,
  is_active
)
values
  ('trainer_ci_v43a2', 'trainer', 'Trainer CI V43A2', 20, true, true),
  ('nutrition_ci_v43a2', 'nutritionist', 'Nutrition CI V43A2', 20, true, true);

insert into public.user_commercial_accounts (
  user_id,
  primary_account_type,
  plan_code,
  subscription_status,
  personal_use_enabled
)
values
  ('44000000-0000-0000-0000-000000000001', 'trainer', 'trainer_ci_v43a2', 'active', true),
  ('44000000-0000-0000-0000-000000000002', 'nutritionist', 'nutrition_ci_v43a2', 'trialing', true),
  ('44000000-0000-0000-0000-000000000003', 'trainer', 'trainer_ci_v43a2', 'active', true),
  ('44000000-0000-0000-0000-000000000005', 'trainer', 'trainer_ci_v43a2', 'past_due', true),
  ('44000000-0000-0000-0000-000000000006', 'nutritionist', 'nutrition_ci_v43a2', 'active', true),
  ('44000000-0000-0000-0000-000000000007', 'trainer', 'trainer_ci_v43a2', 'active', true),
  ('44000000-0000-0000-0000-000000000009', 'trainer', 'trainer_ci_v43a2', 'active', true);

insert into public.user_account_modes (user_id, mode)
values
  ('44000000-0000-0000-0000-000000000001', 'trainer'),
  ('44000000-0000-0000-0000-000000000002', 'nutritionist'),
  ('44000000-0000-0000-0000-000000000003', 'trainer'),
  ('44000000-0000-0000-0000-000000000005', 'trainer'),
  ('44000000-0000-0000-0000-000000000006', 'nutritionist'),
  ('44000000-0000-0000-0000-000000000007', 'trainer'),
  ('44000000-0000-0000-0000-000000000009', 'trainer');

insert into public.user_identity_details (
  user_id,
  birth_date,
  age_status,
  age_verified_at
)
values
  ('44000000-0000-0000-0000-000000000101', date '1990-01-01', 'adult', now()),
  ('44000000-0000-0000-0000-000000000102', date '1988-02-02', 'adult', now()),
  ('44000000-0000-0000-0000-000000000103', current_date - interval '16 years', 'minor', null);

insert into public.organizations (
  id,
  name,
  slug,
  organization_type,
  owner_user_id,
  status
)
values
  ('44200000-0000-0000-0000-000000000001', 'Forja A2B Active', 'forja-a2b-active', 'academy', '44000000-0000-0000-0000-000000000004', 'active'),
  ('44200000-0000-0000-0000-000000000002', 'Forja A2B Suspended', 'forja-a2b-suspended', 'academy', '44000000-0000-0000-0000-000000000004', 'suspended');

insert into public.organization_members (organization_id, user_id, role, status)
values
  ('44200000-0000-0000-0000-000000000001', '44000000-0000-0000-0000-000000000004', 'owner', 'active'),
  ('44200000-0000-0000-0000-000000000001', '44000000-0000-0000-0000-000000000001', 'trainer', 'active'),
  ('44200000-0000-0000-0000-000000000001', '44000000-0000-0000-0000-000000000003', 'trainer', 'active'),
  ('44200000-0000-0000-0000-000000000001', '44000000-0000-0000-0000-000000000007', 'trainer', 'suspended'),
  ('44200000-0000-0000-0000-000000000002', '44000000-0000-0000-0000-000000000009', 'trainer', 'active');

insert into public.professional_student_relationships (
  id,
  professional_user_id,
  student_user_id,
  professional_type,
  organization_id,
  status,
  scopes
)
values
  (
    '44100000-0000-0000-0000-000000000001',
    '44000000-0000-0000-0000-000000000001',
    '44000000-0000-0000-0000-000000000101',
    'trainer',
    null,
    'active',
    '{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":false}'
  ),
  (
    '44100000-0000-0000-0000-000000000002',
    '44000000-0000-0000-0000-000000000002',
    '44000000-0000-0000-0000-000000000101',
    'nutritionist',
    null,
    'active',
    '{"manage_workout_plan":false,"view_workout_executions":false,"manage_nutrition_plan":true,"view_nutrition_logs":true,"view_evolution":true}'
  ),
  (
    '44100000-0000-0000-0000-000000000003',
    '44000000-0000-0000-0000-000000000003',
    '44000000-0000-0000-0000-000000000101',
    'trainer',
    '44200000-0000-0000-0000-000000000001',
    'active',
    '{"manage_workout_plan":true,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true}'
  ),
  (
    '44100000-0000-0000-0000-000000000007',
    '44000000-0000-0000-0000-000000000007',
    '44000000-0000-0000-0000-000000000101',
    'trainer',
    '44200000-0000-0000-0000-000000000001',
    'active',
    '{"manage_workout_plan":true,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true}'
  ),
  (
    '44100000-0000-0000-0000-000000000008',
    '44000000-0000-0000-0000-000000000001',
    '44000000-0000-0000-0000-000000000103',
    'trainer',
    null,
    'active',
    '{"manage_workout_plan":true,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true}'
  ),
  (
    '44100000-0000-0000-0000-000000000009',
    '44000000-0000-0000-0000-000000000009',
    '44000000-0000-0000-0000-000000000101',
    'trainer',
    '44200000-0000-0000-0000-000000000002',
    'active',
    '{"manage_workout_plan":true,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true}'
  );

-- These fixtures intentionally model invalid commercial/type states and bypass
-- only the pre-existing active-client-limit trigger. The A.2B authorization
-- routines must still reject them.
alter table public.professional_student_relationships
  disable trigger enforce_professional_client_limit_v41a2;
insert into public.professional_student_relationships (
  id,
  professional_user_id,
  student_user_id,
  professional_type,
  status,
  scopes
)
values
  (
    '44100000-0000-0000-0000-000000000005',
    '44000000-0000-0000-0000-000000000005',
    '44000000-0000-0000-0000-000000000101',
    'trainer',
    'active',
    '{"manage_workout_plan":true,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true}'
  ),
  (
    '44100000-0000-0000-0000-000000000006',
    '44000000-0000-0000-0000-000000000006',
    '44000000-0000-0000-0000-000000000101',
    'trainer',
    'active',
    '{"manage_workout_plan":true,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true}'
  );
alter table public.professional_student_relationships
  enable trigger enforce_professional_client_limit_v41a2;

insert into public.professional_student_relationships (
  id,
  professional_user_id,
  student_user_id,
  professional_type,
  organization_id,
  status
)
values (
  '44100000-0000-0000-0000-000000000004',
  '44000000-0000-0000-0000-000000000001',
  '44000000-0000-0000-0000-000000000102',
  'trainer',
  '44200000-0000-0000-0000-000000000001',
  'active'
);

select ok(
  pg_temp.safe_exec_v43a2($sql$
    insert into public.consultation_authorization_text_versions (
      purpose,
      version_identifier,
      status,
      effective_at
    ) values
      ('manage_consultations', 'consultation-auth-v1', 'effective', now()),
      ('shared_history', 'shared-history-v1', 'effective', now())
  $sql$),
  'synthetic effective authorization version identifiers can be configured'
);

-- Scope migration regression: explicit old choices survive and both new keys
-- are present with false defaults.
select is(
  (
    select relationship.scopes -> 'manage_consultations'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  'false'::jsonb,
  'existing relationship gains manage_consultations=false'
);
select is(
  (
    select relationship.scopes -> 'view_shared_consultation_history'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  'false'::jsonb,
  'existing relationship gains view_shared_consultation_history=false'
);
select is(
  (
    select relationship.scopes - 'manage_consultations' - 'view_shared_consultation_history'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  '{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":false}'::jsonb,
  'scope migration preserves explicit workout, nutrition and evolution choices'
);
select is(
  (
    select relationship.scopes -> 'manage_consultations'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000004'
  ),
  'false'::jsonb,
  'new relationship defaults manage_consultations to false'
);
select is(
  (
    select relationship.scopes -> 'view_shared_consultation_history'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000004'
  ),
  'false'::jsonb,
  'new relationship defaults shared history to false'
);

-- Professional request flow. A request never activates the scope.
set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    'consultation-auth-v1'
  )$$,
  'trainer may request access for the exact active relationship'
);
select lives_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    'consultation-auth-v1'
  )$$,
  'repeated identical request is idempotent'
);
reset role;

select is(
  pg_temp.safe_count_v43a2($sql$
    select count(*)
    from public.consultation_authorization_requests request
    where request.relationship_id = '44100000-0000-0000-0000-000000000001'
      and request.status = 'pending'
  $sql$),
  1::bigint,
  'one effective pending request exists per relationship'
);
select is(
  (
    select relationship.scopes -> 'manage_consultations'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  'false'::jsonb,
  'professional request does not activate consultation management'
);
select is(
  pg_temp.safe_count_v43a2($sql$
    select count(*)
    from public.consultation_authorization_events event
    where event.relationship_id = '44100000-0000-0000-0000-000000000001'
      and event.event_type = 'requested'
  $sql$),
  1::bigint,
  'idempotent request records one append-only request event'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000002', true);
select lives_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000002',
    'consultation-auth-v1'
  )$$,
  'nutritionist may request access for the exact active relationship'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'unrelated professional cannot request for another relationship'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000101', true);
select throws_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'client cannot impersonate the professional request actor'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000004', true);
select throws_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000003',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'organization owner without the exact professional relationship has no clinical authority'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000005', true);
select throws_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000005',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'expired subscription cannot create an authorization request'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000006', true);
select throws_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000006',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'wrong authoritative professional type is denied'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000007', true);
select throws_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000007',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'suspended organization membership is denied'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000009', true);
select throws_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000009',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'suspended organization is denied'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000008',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'minor client cannot be authorized for consultation management'
);
reset role;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'anonymous caller cannot execute professional authorization request'
);
reset role;

-- Only the exact client can decide, and unrelated scope keys are preserved.
set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.decide_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    (select request.id from public.consultation_authorization_requests request where request.relationship_id = '44100000-0000-0000-0000-000000000001' and request.status = 'pending'),
    'accept',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'professional cannot self-grant consultation management'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000102', true);
select throws_ok(
  $$select public.decide_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    (select request.id from public.consultation_authorization_requests request where request.relationship_id = '44100000-0000-0000-0000-000000000001' and request.status = 'pending'),
    'accept',
    'consultation-auth-v1'
  )$$,
  '42501',
  null,
  'client from another relationship cannot decide'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000101', true);
select lives_ok(
  $$select public.decide_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    (select request.id from public.consultation_authorization_requests request where request.relationship_id = '44100000-0000-0000-0000-000000000001' and request.status = 'pending'),
    'accept',
    'consultation-auth-v1'
  )$$,
  'exact client accepts the outstanding request'
);
select lives_ok(
  $$select public.decide_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000002',
    (select request.id from public.consultation_authorization_requests request where request.relationship_id = '44100000-0000-0000-0000-000000000002' and request.status = 'pending'),
    'decline',
    'consultation-auth-v1'
  )$$,
  'exact client may decline without activating management'
);
reset role;

select is(
  (
    select relationship.scopes -> 'manage_consultations'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  'true'::jsonb,
  'client acceptance atomically activates manage_consultations'
);
select is(
  (
    select relationship.scopes - 'manage_consultations' - 'view_shared_consultation_history'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  '{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":false}'::jsonb,
  'client acceptance preserves every unrelated scope'
);
select is(
  (
    select relationship.scopes -> 'manage_consultations'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000002'
  ),
  'false'::jsonb,
  'client decline keeps manage_consultations false'
);
select is(
  pg_temp.safe_count_v43a2($sql$
    select count(*)
    from public.consultation_authorization_events event
    where event.relationship_id = '44100000-0000-0000-0000-000000000001'
      and event.event_type = 'accepted'
      and event.actor_user_id = '44000000-0000-0000-0000-000000000101'
      and event.authorization_text_version = 'consultation-auth-v1'
  $sql$),
  1::bigint,
  'acceptance writes one versioned append-only audit event'
);

-- Build finalized synthetic content for author and common-history projections.
insert into public.consultation_subjects (
  id,
  subject_kind,
  account_user_id,
  created_by_user_id
)
values
  ('44400000-0000-0000-0000-000000000101', 'account', '44000000-0000-0000-0000-000000000101', '44000000-0000-0000-0000-000000000001'),
  ('44400000-0000-0000-0000-000000000102', 'account', '44000000-0000-0000-0000-000000000102', '44000000-0000-0000-0000-000000000001');

insert into public.professional_consultations (
  id,
  subject_id,
  author_user_id,
  relationship_id,
  professional_type,
  organization_id,
  consultation_kind,
  status
)
values
  ('44300000-0000-0000-0000-000000000001', '44400000-0000-0000-0000-000000000101', '44000000-0000-0000-0000-000000000001', '44100000-0000-0000-0000-000000000001', 'trainer', null, 'initial', 'in_progress'),
  ('44300000-0000-0000-0000-000000000004', '44400000-0000-0000-0000-000000000102', '44000000-0000-0000-0000-000000000001', '44100000-0000-0000-0000-000000000004', 'trainer', '44200000-0000-0000-0000-000000000001', 'initial', 'scheduled'),
  ('44300000-0000-0000-0000-000000000005', '44400000-0000-0000-0000-000000000101', '44000000-0000-0000-0000-000000000005', '44100000-0000-0000-0000-000000000005', 'trainer', null, 'initial', 'scheduled'),
  ('44300000-0000-0000-0000-000000000009', '44400000-0000-0000-0000-000000000101', '44000000-0000-0000-0000-000000000009', '44100000-0000-0000-0000-000000000009', 'trainer', '44200000-0000-0000-0000-000000000002', 'initial', 'scheduled');

insert into public.consultation_items (
  id,
  consultation_id,
  item_key,
  item_kind,
  schema_version,
  value_payload
)
values
  ('44500000-0000-0000-0000-000000000001', '44300000-0000-0000-0000-000000000001', 'common.goal', 'text', 1, '{"value":"synthetic common goal"}'),
  ('44500000-0000-0000-0000-000000000002', '44300000-0000-0000-0000-000000000001', 'trainer.private_note', 'text', 1, '{"value":"synthetic private note"}');

update public.professional_consultations
set status = 'finalized', finalized_at = now()
where id = '44300000-0000-0000-0000-000000000001';

insert into public.consultation_final_snapshots (
  consultation_id,
  finalized_by_user_id,
  schema_version,
  canonical_payload
)
values (
  '44300000-0000-0000-0000-000000000001',
  '44000000-0000-0000-0000-000000000001',
  1,
  '{"items":[{"itemKey":"common.goal","value":{"value":"synthetic common goal"}},{"itemKey":"trainer.private_note","value":{"value":"synthetic private note"}}]}'
);

-- Author-only bounded content read.
set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000001', true);
select is(
  pg_temp.safe_json_v43a2($sql$
    select public.get_my_consultation_v43('44300000-0000-0000-0000-000000000001')
  $sql$) ->> 'id',
  '44300000-0000-0000-0000-000000000001',
  'authorized trainer reads their consultation through the bounded RPC'
);
select ok(
  pg_catalog.jsonb_array_length(
    pg_temp.safe_json_v43a2($sql$
      select public.list_my_manageable_consultation_subjects_v43(50, null)
    $sql$)
  ) >= 1,
  'authorized trainer sees an exact manageable consultation subject'
);
select throws_ok(
  $$select public.get_my_consultation_v43('44300000-0000-0000-0000-000000000004')$$,
  '42501',
  null,
  'missing manage scope denies author consultation content'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.get_my_consultation_v43('44300000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'another linked professional cannot read author-private consultation content'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000101', true);
select throws_ok(
  $$select public.get_my_consultation_v43('44300000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'client cannot read draft or clinical core through author RPC'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000004', true);
select throws_ok(
  $$select public.get_my_consultation_v43('44300000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'organization owner receives no clinical content from administrative role'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000008', true);
select throws_ok(
  $$select public.get_my_consultation_v43('44300000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'unrelated authenticated user cannot read consultation content'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000005', true);
select throws_ok(
  $$select public.get_my_consultation_v43('44300000-0000-0000-0000-000000000005')$$,
  '42501',
  null,
  'expired write entitlement denies new clinical access'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000009', true);
select throws_ok(
  $$select public.get_my_consultation_v43('44300000-0000-0000-0000-000000000009')$$,
  '42501',
  null,
  'suspended organization denies clinical access'
);
reset role;

-- Shared history remains independent from manage_consultations.
set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.list_shared_consultation_history_v43(
    '44100000-0000-0000-0000-000000000001',
    50
  )$$,
  '42501',
  null,
  'manage_consultations alone never grants shared-history access'
);
select throws_ok(
  $$select public.set_my_shared_consultation_history_consent_v43(
    '44100000-0000-0000-0000-000000000001',
    'shared-history-v1',
    true
  )$$,
  '42501',
  null,
  'professional cannot self-grant shared-history consent'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000004', true);
select throws_ok(
  $$select public.set_my_shared_consultation_history_consent_v43(
    '44100000-0000-0000-0000-000000000003',
    'shared-history-v1',
    true
  )$$,
  '42501',
  null,
  'organization owner cannot grant shared-history consent'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000102', true);
select throws_ok(
  $$select public.set_my_shared_consultation_history_consent_v43(
    '44100000-0000-0000-0000-000000000002',
    'shared-history-v1',
    true
  )$$,
  '42501',
  null,
  'client from another relationship cannot grant consent'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000101', true);
select lives_ok(
  $$select public.set_my_shared_consultation_history_consent_v43(
    '44100000-0000-0000-0000-000000000002',
    'shared-history-v1',
    true
  )$$,
  'exact client grants current-version consent to nutritionist relationship'
);
select lives_ok(
  $$select public.set_my_shared_consultation_history_consent_v43(
    '44100000-0000-0000-0000-000000000003',
    'shared-history-v1',
    true
  )$$,
  'exact client grants current-version consent to organization relationship'
);
reset role;

select is(
  (
    select relationship.scopes -> 'view_shared_consultation_history'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000002'
  ),
  'true'::jsonb,
  'client grant atomically activates only shared-history scope'
);
select is(
  (
    select relationship.scopes -> 'manage_consultations'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000002'
  ),
  'false'::jsonb,
  'shared-history consent does not activate manage_consultations'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000002', true);
select is(
  pg_catalog.jsonb_array_length(
    pg_temp.safe_json_v43a2($sql$
      select public.list_shared_consultation_history_v43(
        '44100000-0000-0000-0000-000000000002',
        50
      )
    $sql$)
  ),
  1,
  'recipient with scope and current consent reads one common finalized item'
);
select is(
  pg_temp.safe_json_v43a2($sql$
    select public.list_shared_consultation_history_v43(
      '44100000-0000-0000-0000-000000000002',
      50
    )
  $sql$) -> 0 ->> 'itemKey',
  'common.goal',
  'common projection returns only an approved common item'
);
select unlike(
  pg_temp.safe_json_v43a2($sql$
    select public.list_shared_consultation_history_v43(
      '44100000-0000-0000-0000-000000000002',
      50
    )
  $sql$)::text,
  '%trainer.private_note%',
  'common projection excludes profession-private content'
);
reset role;

select ok(
  pg_temp.safe_exec_v43a2($sql$
    update public.consultation_authorization_text_versions
    set status = 'retired', retired_at = now()
    where purpose = 'shared_history'
      and version_identifier = 'shared-history-v1'
  $sql$)
  and pg_temp.safe_exec_v43a2($sql$
    insert into public.consultation_authorization_text_versions (
      purpose,
      version_identifier,
      status,
      effective_at
    ) values ('shared_history', 'shared-history-v2', 'effective', now())
  $sql$),
  'synthetic disclosure version can advance without legal text content'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.list_shared_consultation_history_v43(
    '44100000-0000-0000-0000-000000000002',
    50
  )$$,
  '42501',
  null,
  'stale disclosure consent denies immediately'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000101', true);
select lives_ok(
  $$select public.set_my_shared_consultation_history_consent_v43(
    '44100000-0000-0000-0000-000000000002',
    'shared-history-v2',
    true
  )$$,
  'client renews consent for the current disclosure version'
);
select lives_ok(
  $$select public.set_my_shared_consultation_history_consent_v43(
    '44100000-0000-0000-0000-000000000002',
    'shared-history-v2',
    false
  )$$,
  'client revokes shared-history consent at any time'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.list_shared_consultation_history_v43(
    '44100000-0000-0000-0000-000000000002',
    50
  )$$,
  '42501',
  null,
  'revoked shared-history consent denies immediately'
);
reset role;

select is(
  (
    select relationship.scopes -> 'view_shared_consultation_history'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000002'
  ),
  'false'::jsonb,
  'shared-history revocation changes only its scope to false'
);
select is(
  (
    select relationship.scopes -> 'manage_nutrition_plan'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000002'
  ),
  'true'::jsonb,
  'shared-history revocation preserves nutrition scope'
);

-- Organization and source/recipient link checks are independent.
set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000101', true);
select lives_ok(
  $$select public.set_my_shared_consultation_history_consent_v43(
    '44100000-0000-0000-0000-000000000003',
    'shared-history-v2',
    true
  )$$,
  'client renews organization-recipient consent for v2'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000003', true);
select lives_ok(
  $$select public.list_shared_consultation_history_v43(
    '44100000-0000-0000-0000-000000000003',
    50
  )$$,
  'active organization recipient reads authorized common history'
);
reset role;

update public.organizations
set status = 'suspended'
where id = '44200000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.list_shared_consultation_history_v43(
    '44100000-0000-0000-0000-000000000003',
    50
  )$$,
  '42501',
  null,
  'recipient organization suspension denies immediately'
);
reset role;
update public.organizations
set status = 'active'
where id = '44200000-0000-0000-0000-000000000001';

update public.professional_student_relationships
set status = 'revoked', revoked_at = now()
where id = '44100000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.list_shared_consultation_history_v43(
    '44100000-0000-0000-0000-000000000003',
    50
  )$$,
  '42501',
  null,
  'source-author relationship revocation suspends common history'
);
reset role;

select is(
  (
    select relationship.scopes -> 'manage_consultations'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  'false'::jsonb,
  'leaving active relationship state clears manage_consultations'
);

update public.professional_student_relationships
set status = 'active', revoked_at = null
where id = '44100000-0000-0000-0000-000000000001';
select is(
  (
    select relationship.scopes -> 'manage_consultations'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  'false'::jsonb,
  'relationship reactivation does not revive prior consultation authorization'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.get_my_consultation_v43('44300000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'reactivated author needs a brand-new request and client acceptance'
);
select lives_ok(
  $$select public.request_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    'consultation-auth-v1'
  )$$,
  'reactivated professional creates a fresh request'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000101', true);
select lives_ok(
  $$select public.decide_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    (select request.id from public.consultation_authorization_requests request where request.relationship_id = '44100000-0000-0000-0000-000000000001' and request.status = 'pending' order by request.requested_at desc limit 1),
    'accept',
    'consultation-auth-v1'
  )$$,
  'fresh client acceptance restores management after reactivation'
);
select lives_ok(
  $$select public.revoke_my_consultation_authorization_v43(
    '44100000-0000-0000-0000-000000000001',
    'consultation-auth-v1'
  )$$,
  'client may revoke consultation management at any time'
);
reset role;

select is(
  (
    select relationship.scopes -> 'manage_consultations'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  'false'::jsonb,
  'client revocation is immediately effective'
);
select is(
  (
    select relationship.scopes -> 'view_workout_executions'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000001'
  ),
  'true'::jsonb,
  'manage revocation preserves unrelated workout scope'
);

update public.professional_student_relationships
set status = 'revoked', revoked_at = now()
where id = '44100000-0000-0000-0000-000000000003';
select is(
  (
    select relationship.scopes -> 'view_shared_consultation_history'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000003'
  ),
  'false'::jsonb,
  'recipient relationship revocation clears shared-history scope'
);
update public.professional_student_relationships
set status = 'active', revoked_at = null
where id = '44100000-0000-0000-0000-000000000003';
select is(
  (
    select relationship.scopes -> 'view_shared_consultation_history'
    from public.professional_student_relationships relationship
    where relationship.id = '44100000-0000-0000-0000-000000000003'
  ),
  'false'::jsonb,
  'recipient relationship reactivation requires fresh shared-history consent'
);

-- Browser roles cannot mutate clinical or authorization history directly.
set local role authenticated;
select set_config('request.jwt.claim.sub', '44000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$insert into public.professional_consultations (
    subject_id,
    author_user_id,
    relationship_id,
    professional_type,
    consultation_kind,
    status
  ) values (
    '44400000-0000-0000-0000-000000000101',
    '44000000-0000-0000-0000-000000000001',
    '44100000-0000-0000-0000-000000000001',
    'trainer',
    'initial',
    'scheduled'
  )$$,
  '42501',
  null,
  'authenticated professional cannot insert consultation core directly'
);
select throws_ok(
  $$update public.consultation_items
    set value_payload = '{"value":"spoofed"}'
    where id = '44500000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated professional cannot update consultation items directly'
);
select throws_ok(
  $$delete from public.professional_consultations
    where id = '44300000-0000-0000-0000-000000000004'$$,
  '42501',
  null,
  'authenticated professional cannot delete consultation core directly'
);
select throws_ok(
  $$update public.consultation_authorization_events
    set event_type = 'accepted'
    where relationship_id = '44100000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated actor cannot rewrite authorization audit history'
);
select throws_ok(
  $$delete from public.consultation_sharing_consents
    where relationship_id = '44100000-0000-0000-0000-000000000002'$$,
  '42501',
  null,
  'authenticated actor cannot delete consent history'
);
reset role;

select throws_ok(
  $$update public.consultation_authorization_events
    set event_type = 'accepted'
    where relationship_id = '44100000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_authorization_history',
  'table owner cannot rewrite append-only authorization events'
);
select throws_ok(
  $$delete from public.consultation_sharing_consents
    where relationship_id = '44100000-0000-0000-0000-000000000002'$$,
  '55000',
  'immutable_consultation_authorization_history',
  'table owner cannot delete append-only shared-history consent'
);

select * from finish();
rollback;
