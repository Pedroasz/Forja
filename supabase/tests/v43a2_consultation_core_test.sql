begin;

set local search_path = public, extensions;
select no_plan();

select has_table('public', 'consultation_subjects', 'consultation subjects exist');
select has_table('public', 'professional_consultations', 'professional consultations exist');
select has_table('public', 'consultation_items', 'consultation items exist');
select has_table('public', 'consultation_final_snapshots', 'final snapshots exist');
select has_table('public', 'consultation_addenda', 'consultation addenda exist');
select has_table('public', 'consultation_discard_tombstones', 'discard tombstones exist');
select has_table('public', 'consultation_events', 'consultation events exist');

select has_column(
  'public',
  'professional_consultations',
  'consultation_kind',
  'consultation kind is relational'
);
select has_column(
  'public',
  'professional_consultations',
  'schedule_revision',
  'schedule revision is relational'
);
select has_column(
  'public',
  'consultation_final_snapshots',
  'canonical_bytes',
  'final snapshots preserve canonical bytes'
);
select has_column(
  'public',
  'consultation_final_snapshots',
  'payload_sha256',
  'final snapshots preserve SHA-256'
);

select ok(
  (
    select count(*) = 7
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'consultation_subjects',
        'professional_consultations',
        'consultation_items',
        'consultation_final_snapshots',
        'consultation_addenda',
        'consultation_discard_tombstones',
        'consultation_events'
      ])
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  'all seven A.2A tables enable and force RLS'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_policy policy
    join pg_catalog.pg_class relation on relation.oid = policy.polrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any(array[
        'consultation_subjects',
        'professional_consultations',
        'consultation_items',
        'consultation_final_snapshots',
        'consultation_addenda',
        'consultation_discard_tombstones',
        'consultation_events'
      ])
  ),
  'A.2A creates no authenticated content policies'
);

select ok(
  not has_table_privilege(role_name, format('public.%I', table_name), privilege_name)
  and not has_table_privilege('anon', format('public.%I', table_name), privilege_name),
  format('%s has no %s privilege for browser roles', table_name, privilege_name)
)
from unnest(array[
  'consultation_subjects',
  'professional_consultations',
  'consultation_items',
  'consultation_final_snapshots',
  'consultation_addenda',
  'consultation_discard_tombstones',
  'consultation_events'
]) as tables(table_name)
cross join (values ('authenticated')) as roles(role_name)
cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as privileges(privilege_name);

select has_function(
  'public',
  'resolve_account_consultation_subject_v43',
  array['uuid'],
  'account subject resolver exists with relationship-only signature'
);
select ok(
  (
    select procedure.prosecdef
      and procedure.proconfig @> array['search_path=""']
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'resolve_account_consultation_subject_v43'
      and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = 'target_relationship_id uuid'
  ),
  'resolver is SECURITY DEFINER with empty search_path'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.resolve_account_consultation_subject_v43(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.resolve_account_consultation_subject_v43(uuid)',
    'EXECUTE'
  ),
  'resolver execute is granted only to authenticated browser role'
);

select ok(
  (
    select count(*) = 0
    from information_schema.table_constraints constraint_info
    where constraint_info.table_schema = 'public'
      and constraint_info.table_name in (
        'consultation_discard_tombstones',
        'consultation_events'
      )
      and constraint_info.constraint_type = 'FOREIGN KEY'
  ),
  'tombstones and events contain copied identifiers without foreign keys'
);
select ok(
  not exists (
    select 1
    from information_schema.columns column_info
    where column_info.table_schema = 'public'
      and column_info.table_name in (
        'consultation_discard_tombstones',
        'consultation_events'
      )
      and (
        column_info.data_type in ('json', 'jsonb')
        or column_info.column_name ~ '(payload|content|body|details|filename)'
      )
  ),
  'tombstones and events have no content-bearing columns'
);

select ok(
  (
    select count(*) = 4
    from pg_catalog.pg_constraint constraint_info
    join pg_catalog.pg_class relation on relation.oid = constraint_info.conrelid
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and constraint_info.conname = any(array[
        'professional_consultations_subject_id_fkey',
        'professional_consultations_relationship_id_fkey',
        'consultation_final_snapshots_consultation_id_fkey',
        'consultation_addenda_consultation_id_fkey'
      ])
      and constraint_info.confdeltype in ('a', 'r')
  ),
  'finalized history foreign keys use NO ACTION or RESTRICT'
);
select ok(
  (
    select constraint_info.confdeltype = 'c'
    from pg_catalog.pg_constraint constraint_info
    where constraint_info.conname = 'consultation_items_consultation_id_fkey'
  ),
  'only draft consultation items cascade with their aggregate'
);

select ok(
  (
    select count(*) >= 14
    from pg_catalog.pg_indexes index_info
    where index_info.schemaname = 'public'
      and index_info.indexname = any(array[
        'consultation_subjects_account_user_id_key',
        'professional_consultations_author_status_idx',
        'professional_consultations_subject_status_idx',
        'professional_consultations_relationship_status_idx',
        'professional_consultations_organization_status_idx',
        'professional_consultations_predecessor_idx',
        'consultation_items_consultation_item_key_key',
        'consultation_items_consultation_idx',
        'consultation_final_snapshots_consultation_id_key',
        'consultation_addenda_consultation_created_idx',
        'consultation_addenda_final_snapshot_idx',
        'consultation_discard_tombstones_consultation_discarded_idx',
        'consultation_events_consultation_occurred_idx',
        'consultation_events_subject_occurred_idx'
      ])
  ),
  'foreign keys and intended lookup predicates have stable indexes'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  created_at,
  updated_at
)
values
  ('43000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'v43-professional@example.test', now(), now()),
  ('43000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'v43-adult@example.test', now(), now()),
  ('43000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'v43-minor@example.test', now(), now()),
  ('43000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'v43-other-professional@example.test', now(), now()),
  ('43000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'v43-other-adult@example.test', now(), now());

insert into public.user_identity_details (
  user_id,
  birth_date,
  age_status,
  age_verified_at
)
values
  ('43000000-0000-0000-0000-000000000002', date '1990-01-01', 'adult', now()),
  ('43000000-0000-0000-0000-000000000003', current_date - interval '16 years', 'minor', null),
  ('43000000-0000-0000-0000-000000000005', date '1985-01-01', 'adult', now());

alter table public.professional_student_relationships disable trigger user;
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
    '43100000-0000-0000-0000-000000000001',
    '43000000-0000-0000-0000-000000000001',
    '43000000-0000-0000-0000-000000000002',
    'trainer',
    'active',
    '{"manage_workout_plan":false,"view_workout_executions":false,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":false,"manage_consultations":false,"view_shared_consultation_history":false}'
  ),
  (
    '43100000-0000-0000-0000-000000000002',
    '43000000-0000-0000-0000-000000000001',
    '43000000-0000-0000-0000-000000000003',
    'trainer',
    'active',
    '{"manage_workout_plan":false,"view_workout_executions":false,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":false,"manage_consultations":false,"view_shared_consultation_history":false}'
  ),
  (
    '43100000-0000-0000-0000-000000000003',
    '43000000-0000-0000-0000-000000000004',
    '43000000-0000-0000-0000-000000000005',
    'nutritionist',
    'active',
    '{"manage_workout_plan":false,"view_workout_executions":false,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":false,"manage_consultations":false,"view_shared_consultation_history":false}'
  );
alter table public.professional_student_relationships enable trigger user;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '43000000-0000-0000-0000-000000000001',
  true
);
select lives_ok(
  $$select public.resolve_account_consultation_subject_v43(
    '43100000-0000-0000-0000-000000000001'
  )$$,
  'adult active relationship resolves an account subject'
);
select lives_ok(
  $$select public.resolve_account_consultation_subject_v43(
    '43100000-0000-0000-0000-000000000001'
  )$$,
  'subject resolution is idempotent'
);
select throws_ok(
  $$select public.resolve_account_consultation_subject_v43(
    '43100000-0000-0000-0000-000000000002'
  )$$,
  '42501',
  'consultation_subject_requires_adult_account',
  'minor account subject resolution is denied'
);
reset role;

select is(
  (
    select count(*)::integer
    from public.consultation_subjects
    where account_user_id = '43000000-0000-0000-0000-000000000002'
  ),
  1,
  'one stable subject exists for the adult account'
);
select is(
  (
    select subject_kind
    from public.consultation_subjects
    where account_user_id = '43000000-0000-0000-0000-000000000002'
  ),
  'account',
  'A.2A subjects are account-backed'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '43000000-0000-0000-0000-000000000004',
  true
);
select throws_ok(
  $$select public.resolve_account_consultation_subject_v43(
    '43100000-0000-0000-0000-000000000001'
  )$$,
  '42501',
  'consultation_relationship_not_authorized',
  'another professional cannot resolve a foreign relationship'
);
reset role;

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.resolve_account_consultation_subject_v43(
    '43100000-0000-0000-0000-000000000001'
  )$$,
  '42501',
  'authentication_required',
  'resolver rejects a missing authenticated caller'
);

select throws_ok(
  $$
    insert into public.consultation_subjects (
      subject_kind,
      account_user_id,
      created_by_user_id
    )
    values (
      'external',
      '43000000-0000-0000-0000-000000000003',
      '43000000-0000-0000-0000-000000000001'
    )
  $$,
  '23514',
  null,
  'external consultation subjects are impossible in A.2A'
);

insert into public.consultation_subjects (
  id,
  subject_kind,
  account_user_id,
  created_by_user_id
)
values (
  '43200000-0000-0000-0000-000000000005',
  'account',
  '43000000-0000-0000-0000-000000000005',
  '43000000-0000-0000-0000-000000000004'
);

insert into public.professional_consultations (
  id,
  subject_id,
  author_user_id,
  relationship_id,
  professional_type,
  consultation_kind,
  status,
  draft_revision,
  schema_version,
  finalized_at
)
values (
  '43300000-0000-0000-0000-000000000001',
  (
    select id
    from public.consultation_subjects
    where account_user_id = '43000000-0000-0000-0000-000000000002'
  ),
  '43000000-0000-0000-0000-000000000001',
  '43100000-0000-0000-0000-000000000001',
  'trainer',
  'initial',
  'in_progress',
  2,
  1,
  null
);

insert into public.consultation_items (
  id,
  consultation_id,
  item_key,
  item_kind,
  schema_version,
  value_payload
)
values (
  '43400000-0000-0000-0000-000000000001',
  '43300000-0000-0000-0000-000000000001',
  'common.goal',
  'text',
  1,
  '{"value":"synthetic"}'
);

update public.professional_consultations
set status = 'finalized',
    finalized_at = now()
where id = '43300000-0000-0000-0000-000000000001';

insert into public.professional_consultations (
  id,
  subject_id,
  author_user_id,
  relationship_id,
  professional_type,
  consultation_kind,
  status,
  scheduled_start_at,
  scheduled_time_zone,
  scheduled_utc_offset_minutes,
  schedule_revision
)
values (
  '43300000-0000-0000-0000-000000000002',
  (
    select id
    from public.consultation_subjects
    where account_user_id = '43000000-0000-0000-0000-000000000002'
  ),
  '43000000-0000-0000-0000-000000000001',
  '43100000-0000-0000-0000-000000000001',
  'trainer',
  'initial',
  'scheduled',
  timestamptz '2026-08-01 12:00:00+00',
  'America/Sao_Paulo',
  -180,
  1
);

select throws_ok(
  $$
    insert into public.professional_consultations (
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      status
    )
    values (
      (select id from public.consultation_subjects where account_user_id = '43000000-0000-0000-0000-000000000002'),
      '43000000-0000-0000-0000-000000000001',
      '43100000-0000-0000-0000-000000000001',
      'trainer',
      'follow_up',
      'scheduled'
    )
  $$,
  '23514',
  null,
  'unsupported consultation kind is rejected'
);
select throws_ok(
  $$
    insert into public.professional_consultations (
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      status
    )
    values (
      (select id from public.consultation_subjects where account_user_id = '43000000-0000-0000-0000-000000000002'),
      '43000000-0000-0000-0000-000000000001',
      '43100000-0000-0000-0000-000000000001',
      'trainer',
      'initial',
      'draft'
    )
  $$,
  '23514',
  null,
  'unsupported lifecycle status is rejected'
);
select throws_ok(
  $$
    insert into public.professional_consultations (
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      status,
      scheduled_start_at,
      schedule_revision
    )
    values (
      (select id from public.consultation_subjects where account_user_id = '43000000-0000-0000-0000-000000000002'),
      '43000000-0000-0000-0000-000000000001',
      '43100000-0000-0000-0000-000000000001',
      'trainer',
      'initial',
      'scheduled',
      now(),
      1
    )
  $$,
  '23514',
  null,
  'partial schedule metadata is rejected'
);
select throws_ok(
  $$
    insert into public.professional_consultations (
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      status,
      schedule_revision
    )
    values (
      (select id from public.consultation_subjects where account_user_id = '43000000-0000-0000-0000-000000000002'),
      '43000000-0000-0000-0000-000000000001',
      '43100000-0000-0000-0000-000000000001',
      'trainer',
      'initial',
      'scheduled',
      5
    )
  $$,
  '23514',
  null,
  'an initially unscheduled consultation starts at schedule revision zero'
);
select throws_ok(
  $$
    insert into public.professional_consultations (
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      status,
      scheduled_start_at,
      scheduled_time_zone,
      scheduled_utc_offset_minutes,
      schedule_revision
    )
    values (
      (select id from public.consultation_subjects where account_user_id = '43000000-0000-0000-0000-000000000002'),
      '43000000-0000-0000-0000-000000000001',
      '43100000-0000-0000-0000-000000000001',
      'trainer',
      'initial',
      'scheduled',
      now(),
      'Mars/Olympus',
      0,
      1
    )
  $$,
  '23514',
  null,
  'unknown IANA time zone is rejected'
);
select throws_ok(
  $$
    insert into public.professional_consultations (
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      status,
      scheduled_start_at,
      scheduled_time_zone,
      scheduled_utc_offset_minutes,
      schedule_revision
    )
    values (
      (select id from public.consultation_subjects where account_user_id = '43000000-0000-0000-0000-000000000002'),
      '43000000-0000-0000-0000-000000000001',
      '43100000-0000-0000-0000-000000000001',
      'trainer',
      'initial',
      'scheduled',
      timestamptz '2026-08-01 12:00:00+00',
      'America/Sao_Paulo',
      0,
      1
    )
  $$,
  '23514',
  null,
  'original offset must match the IANA zone at the scheduled instant'
);
select throws_ok(
  $$
    update public.professional_consultations
    set scheduled_start_at = scheduled_start_at + interval '1 hour'
    where id = '43300000-0000-0000-0000-000000000002'
  $$,
  '23514',
  null,
  'schedule metadata change requires the next revision'
);
select throws_ok(
  $$
    update public.professional_consultations
    set schedule_revision = schedule_revision + 1
    where id = '43300000-0000-0000-0000-000000000002'
  $$,
  '23514',
  null,
  'schedule revision cannot change without schedule metadata'
);

select throws_ok(
  $$
    insert into public.professional_consultations (
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      predecessor_consultation_id,
      status
    )
    values (
      (select id from public.consultation_subjects where account_user_id = '43000000-0000-0000-0000-000000000002'),
      '43000000-0000-0000-0000-000000000001',
      '43100000-0000-0000-0000-000000000001',
      'trainer',
      'initial',
      '43300000-0000-0000-0000-000000000001',
      'scheduled'
    )
  $$,
  '23514',
  null,
  'initial consultation cannot have a predecessor'
);
select throws_ok(
  $$
    insert into public.professional_consultations (
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      predecessor_consultation_id,
      status
    )
    values (
      '43200000-0000-0000-0000-000000000005',
      '43000000-0000-0000-0000-000000000004',
      '43100000-0000-0000-0000-000000000003',
      'nutritionist',
      'reassessment',
      '43300000-0000-0000-0000-000000000001',
      'scheduled'
    )
  $$,
  '23514',
  null,
  'reassessment predecessor must belong to the same subject'
);
select throws_ok(
  $$
    insert into public.professional_consultations (
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      predecessor_consultation_id,
      status
    )
    values (
      (select id from public.consultation_subjects where account_user_id = '43000000-0000-0000-0000-000000000002'),
      '43000000-0000-0000-0000-000000000001',
      '43100000-0000-0000-0000-000000000001',
      'trainer',
      'reassessment',
      '43300000-0000-0000-0000-000000000002',
      'scheduled'
    )
  $$,
  '23514',
  null,
  'reassessment predecessor must already be finalized'
);
select lives_ok(
  $$
    insert into public.professional_consultations (
      id,
      subject_id,
      author_user_id,
      relationship_id,
      professional_type,
      consultation_kind,
      predecessor_consultation_id,
      status
    )
    values (
      '43300000-0000-0000-0000-000000000003',
      (select id from public.consultation_subjects where account_user_id = '43000000-0000-0000-0000-000000000002'),
      '43000000-0000-0000-0000-000000000001',
      '43100000-0000-0000-0000-000000000001',
      'trainer',
      'reassessment',
      '43300000-0000-0000-0000-000000000001',
      'scheduled'
    )
  $$,
  'same-subject reassessment may reference a finalized predecessor'
);

insert into public.consultation_final_snapshots (
  id,
  consultation_id,
  finalized_by_user_id,
  schema_version,
  canonical_payload
)
values (
  '43500000-0000-0000-0000-000000000001',
  '43300000-0000-0000-0000-000000000001',
  '43000000-0000-0000-0000-000000000001',
  1,
  jsonb_build_object(
    'z', null,
    'array', jsonb_build_array(
      3,
      '1.23',
      jsonb_build_object(
        'b', true,
        'a', '2026-07-25T12:34:56.789Z'
      )
    ),
    'a', U&'e\0301'
  )
);

select is(
  (
    select pg_catalog.encode(canonical_bytes, 'hex')
    from public.consultation_final_snapshots
    where id = '43500000-0000-0000-0000-000000000001'
  ),
  '7b2261223a22c3a9222c226172726179223a5b332c22312e3233222c7b2261223a22323032362d30372d32355431323a33343a35362e3738395a222c2262223a747275657d5d2c227a223a6e756c6c7d',
  'canonical v1 bytes match the fixed UTF-8 known answer'
);
select is(
  (
    select pg_catalog.encode(payload_sha256, 'hex')
    from public.consultation_final_snapshots
    where id = '43500000-0000-0000-0000-000000000001'
  ),
  '39a84d4e728d4602667ff74764427ab3199f398431f3a4096a88d40194bb01d6',
  'canonical v1 SHA-256 matches the fixed known answer'
);
select is(
  (
    select canonicalization_version
    from public.consultation_final_snapshots
    where id = '43500000-0000-0000-0000-000000000001'
  ),
  'forja.canonical-json.v1',
  'snapshot records the canonicalization version'
);
select ok(
  (
    select payload_sha256 = extensions.digest(canonical_bytes, 'sha256')
    from public.consultation_final_snapshots
    where id = '43500000-0000-0000-0000-000000000001'
  ),
  'snapshot hash is computed from canonical bytes'
);
select throws_ok(
  $$
    select private.forja_canonical_json_v1_bytes(
      '{"at":"2026-07-25T12:34:56Z"}',
      'forja.canonical-json.v1'
    )
  $$,
  '22023',
  'canonical_json_timestamp_requires_milliseconds_utc',
  'timestamp-like strings require millisecond UTC RFC 3339'
);
select throws_ok(
  $$
    select private.forja_canonical_json_v1_bytes(
      '{"value":"1.230"}',
      'forja.canonical-json.v1'
    )
  $$,
  '22023',
  'canonical_json_decimal_not_minimal',
  'decimal strings reject insignificant trailing zeros'
);
select throws_ok(
  $$
    select private.forja_canonical_json_v1_bytes(
      '{"value":1.23}',
      'forja.canonical-json.v1'
    )
  $$,
  '22023',
  'canonical_json_decimal_must_be_string',
  'non-integer JSON numbers cannot represent measured decimals'
);

insert into public.consultation_addenda (
  id,
  consultation_id,
  final_snapshot_id,
  author_user_id,
  reason,
  schema_version,
  canonical_payload
)
values (
  '43600000-0000-0000-0000-000000000001',
  '43300000-0000-0000-0000-000000000001',
  '43500000-0000-0000-0000-000000000001',
  '43000000-0000-0000-0000-000000000001',
  'synthetic correction',
  1,
  '{"corrections":[]}'
);
insert into public.consultation_discard_tombstones (
  id,
  discarded_consultation_id,
  subject_id,
  author_user_id,
  relationship_id,
  discarded_by_user_id,
  reason_category
)
values (
  '43700000-0000-0000-0000-000000000001',
  '43300000-0000-0000-0000-000000000099',
  '43200000-0000-0000-0000-000000000099',
  '43000000-0000-0000-0000-000000000001',
  '43100000-0000-0000-0000-000000000001',
  '43000000-0000-0000-0000-000000000001',
  'author_discard'
);
insert into public.consultation_events (
  id,
  consultation_id,
  subject_id,
  actor_user_id,
  relationship_id,
  event_type,
  reason_category
)
values (
  '43800000-0000-0000-0000-000000000001',
  '43300000-0000-0000-0000-000000000099',
  '43200000-0000-0000-0000-000000000099',
  '43000000-0000-0000-0000-000000000001',
  '43100000-0000-0000-0000-000000000001',
  'discarded',
  'author_discard'
);

insert into public.professional_consultations (
  id,
  subject_id,
  author_user_id,
  relationship_id,
  professional_type,
  consultation_kind,
  status,
  finalized_at
)
select
  fixture.id,
  (
    select id
    from public.consultation_subjects
    where account_user_id = '43000000-0000-0000-0000-000000000002'
  ),
  '43000000-0000-0000-0000-000000000001',
  '43100000-0000-0000-0000-000000000001',
  'trainer',
  'initial',
  'finalized',
  now()
from (
  values
    ('43300000-0000-0000-0000-000000000005'::uuid),
    ('43300000-0000-0000-0000-000000000006'::uuid)
) as fixture(id);

set local role authenticated;
select throws_ok(
  $$update public.consultation_final_snapshots set schema_version = 2 where id = '43500000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated user cannot update a final snapshot'
);
select throws_ok(
  $$delete from public.consultation_final_snapshots where id = '43500000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated user cannot delete a final snapshot'
);
select throws_ok(
  $$update public.consultation_addenda set reason = 'changed' where id = '43600000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated user cannot update an addendum'
);
select throws_ok(
  $$delete from public.consultation_addenda where id = '43600000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated user cannot delete an addendum'
);
select throws_ok(
  $$update public.consultation_discard_tombstones set reason_category = 'relationship_revoked_cleanup' where id = '43700000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated user cannot update a discard tombstone'
);
select throws_ok(
  $$delete from public.consultation_discard_tombstones where id = '43700000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated user cannot delete a discard tombstone'
);
select throws_ok(
  $$update public.consultation_events set event_type = 'created' where id = '43800000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated user cannot update an event'
);
select throws_ok(
  $$delete from public.consultation_events where id = '43800000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'authenticated user cannot delete an event'
);
reset role;

select throws_ok(
  $$update public.consultation_final_snapshots set schema_version = 2 where id = '43500000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'table owner cannot update a final snapshot'
);
select throws_ok(
  $$delete from public.consultation_final_snapshots where id = '43500000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'table owner cannot delete a final snapshot'
);
select throws_ok(
  $$update public.consultation_addenda set reason = 'changed' where id = '43600000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'table owner cannot update an addendum'
);
select throws_ok(
  $$delete from public.consultation_addenda where id = '43600000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'table owner cannot delete an addendum'
);
select throws_ok(
  $$update public.consultation_discard_tombstones set reason_category = 'relationship_revoked_cleanup' where id = '43700000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'table owner cannot update a discard tombstone'
);
select throws_ok(
  $$delete from public.consultation_discard_tombstones where id = '43700000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'table owner cannot delete a discard tombstone'
);
select throws_ok(
  $$update public.consultation_events set event_type = 'created' where id = '43800000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'table owner cannot update an event'
);
select throws_ok(
  $$delete from public.consultation_events where id = '43800000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'table owner cannot delete an event'
);
savepoint owner_reparent_guard;
select throws_ok(
  $$update public.consultation_items set consultation_id = '43300000-0000-0000-0000-000000000002' where id = '43400000-0000-0000-0000-000000000001'$$,
  '55000',
  'finalized_consultation_items_are_immutable',
  'table owner cannot reparent an item away from finalized history'
);
rollback to savepoint owner_reparent_guard;
release savepoint owner_reparent_guard;
select throws_ok(
  $$update public.professional_consultations set status = 'cancelled' where id = '43300000-0000-0000-0000-000000000001'$$,
  '55000',
  'finalized_consultation_provenance_is_immutable',
  'table owner cannot rewrite finalized consultation lifecycle'
);
select throws_ok(
  $$delete from public.professional_consultations where id = '43300000-0000-0000-0000-000000000005'$$,
  '55000',
  'finalized_consultation_provenance_is_immutable',
  'table owner cannot delete a finalized consultation before snapshot insertion'
);

create role v43a2_maintenance_test nologin bypassrls;
grant v43a2_maintenance_test to postgres;
grant usage on schema public to v43a2_maintenance_test;
grant usage on schema extensions to v43a2_maintenance_test;
grant select, insert, update, delete on table
  public.consultation_final_snapshots,
  public.consultation_addenda,
  public.consultation_discard_tombstones,
  public.consultation_events,
  public.consultation_items,
  public.professional_consultations
to v43a2_maintenance_test;

set local role v43a2_maintenance_test;
select throws_ok(
  $$update public.consultation_final_snapshots set schema_version = 2 where id = '43500000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'maintenance role cannot update a final snapshot'
);
select throws_ok(
  $$delete from public.consultation_final_snapshots where id = '43500000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'maintenance role cannot delete a final snapshot'
);
select throws_ok(
  $$update public.consultation_addenda set reason = 'changed' where id = '43600000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'maintenance role cannot update an addendum'
);
select throws_ok(
  $$delete from public.consultation_addenda where id = '43600000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'maintenance role cannot delete an addendum'
);
select throws_ok(
  $$update public.consultation_discard_tombstones set reason_category = 'relationship_revoked_cleanup' where id = '43700000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'maintenance role cannot update a discard tombstone'
);
select throws_ok(
  $$delete from public.consultation_discard_tombstones where id = '43700000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'maintenance role cannot delete a discard tombstone'
);
select throws_ok(
  $$update public.consultation_events set event_type = 'created' where id = '43800000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'maintenance role cannot update an event'
);
select throws_ok(
  $$delete from public.consultation_events where id = '43800000-0000-0000-0000-000000000001'$$,
  '55000',
  'immutable_consultation_entity',
  'maintenance role cannot delete an event'
);
select throws_ok(
  $$update public.consultation_items set value_payload = '{"value":"changed"}' where id = '43400000-0000-0000-0000-000000000001'$$,
  '55000',
  'finalized_consultation_items_are_immutable',
  'maintenance role cannot update items after finalization'
);
savepoint maintenance_reparent_guard;
select throws_ok(
  $$update public.consultation_items set consultation_id = '43300000-0000-0000-0000-000000000002' where id = '43400000-0000-0000-0000-000000000001'$$,
  '55000',
  'finalized_consultation_items_are_immutable',
  'maintenance role cannot reparent an item away from finalized history'
);
rollback to savepoint maintenance_reparent_guard;
release savepoint maintenance_reparent_guard;
select throws_ok(
  $$update public.professional_consultations set subject_id = '43200000-0000-0000-0000-000000000005' where id = '43300000-0000-0000-0000-000000000001'$$,
  '55000',
  'finalized_consultation_provenance_is_immutable',
  'maintenance role cannot rewrite finalized consultation provenance'
);
select throws_ok(
  $$update public.professional_consultations set status = 'archived' where id = '43300000-0000-0000-0000-000000000001'$$,
  '55000',
  'finalized_consultation_provenance_is_immutable',
  'maintenance role cannot rewrite finalized consultation lifecycle'
);
select throws_ok(
  $$delete from public.professional_consultations where id = '43300000-0000-0000-0000-000000000006'$$,
  '55000',
  'finalized_consultation_provenance_is_immutable',
  'maintenance role cannot delete a finalized consultation before snapshot insertion'
);
reset role;

select throws_ok(
  $$delete from public.professional_consultations where id = '43300000-0000-0000-0000-000000000001'$$,
  '55000',
  'finalized_consultation_provenance_is_immutable',
  'database guard rejects finalized consultation deletion before the restrictive foreign key'
);
select throws_ok(
  $$
    delete from public.consultation_subjects
    where account_user_id = '43000000-0000-0000-0000-000000000002'
  $$,
  '23503',
  null,
  'consultation history restricts subject deletion'
);
select throws_ok(
  $$
    delete from public.professional_student_relationships
    where id = '43100000-0000-0000-0000-000000000001'
  $$,
  '23503',
  null,
  'consultation history restricts relationship deletion'
);

insert into public.professional_consultations (
  id,
  subject_id,
  author_user_id,
  relationship_id,
  professional_type,
  consultation_kind,
  status
)
values (
  '43300000-0000-0000-0000-000000000004',
  (
    select id
    from public.consultation_subjects
    where account_user_id = '43000000-0000-0000-0000-000000000002'
  ),
  '43000000-0000-0000-0000-000000000001',
  '43100000-0000-0000-0000-000000000001',
  'trainer',
  'initial',
  'scheduled'
);
insert into public.consultation_items (
  id,
  consultation_id,
  item_key,
  item_kind,
  schema_version,
  value_payload
)
values (
  '43400000-0000-0000-0000-000000000004',
  '43300000-0000-0000-0000-000000000004',
  'common.synthetic',
  'text',
  1,
  '{"value":"discardable"}'
);
delete from public.professional_consultations
where id = '43300000-0000-0000-0000-000000000004';
select is(
  (
    select count(*)::integer
    from public.consultation_items
    where id = '43400000-0000-0000-0000-000000000004'
  ),
  0,
  'enumerated draft items cascade when a draft aggregate is discarded'
);

create or replace function pg_temp.has_consultation_retention_job_v43()
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  found_job boolean := false;
begin
  if pg_catalog.to_regclass('cron.job') is null then
    return false;
  end if;

  execute $query$
    select exists (
      select 1
      from cron.job
      where command ~* '(consultation|v43).*(retention|cleanup|delete)'
    )
  $query$
  into found_job;

  return found_job;
end;
$$;

select ok(
  not pg_temp.has_consultation_retention_job_v43()
  and not exists (
    select 1
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public', 'private')
      and procedure.proname ~* 'consultation.*(retention|automatic_cleanup)'
  ),
  'A.2A creates no automatic time-based retention job'
);

select * from finish();
rollback;
