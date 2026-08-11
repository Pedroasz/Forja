begin;

create table public.consultation_edit_leases (
  consultation_id uuid not null,
  holder_user_id uuid not null,
  token_verifier bytea not null,
  lease_version bigint default 1 not null,
  purpose text not null,
  device_label text not null,
  acquired_at timestamp with time zone default now() not null,
  heartbeat_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone not null,
  invalidated_at timestamp with time zone,
  invalidation_reason text,
  takeover_count bigint default 0 not null,
  constraint consultation_edit_leases_pkey primary key (consultation_id),
  constraint consultation_edit_leases_consultation_id_fkey
    foreign key (consultation_id)
    references public.professional_consultations(id)
    on update restrict
    on delete cascade,
  constraint consultation_edit_leases_holder_user_id_fkey
    foreign key (holder_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_edit_leases_token_length_check
    check (octet_length(token_verifier) = 32),
  constraint consultation_edit_leases_version_check
    check (lease_version >= 1 and takeover_count >= 0),
  constraint consultation_edit_leases_purpose_check
    check (purpose in ('edit', 'discard', 'cleanup')),
  constraint consultation_edit_leases_device_label_check
    check (
      char_length(device_label) between 1 and 80
      and device_label !~ '[[:cntrl:]]'
    ),
  constraint consultation_edit_leases_time_check
    check (expires_at > heartbeat_at),
  constraint consultation_edit_leases_invalidation_check
    check (
      (invalidated_at is null and invalidation_reason is null)
      or (invalidated_at is not null and invalidation_reason is not null)
    )
);

create table public.consultation_save_receipts (
  author_user_id uuid not null,
  consultation_id uuid not null,
  correlation_id uuid not null,
  resulting_revision bigint not null,
  created_at timestamp with time zone default now() not null,
  constraint consultation_save_receipts_pkey
    primary key (author_user_id, consultation_id, correlation_id),
  constraint consultation_save_receipts_author_user_id_fkey
    foreign key (author_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_save_receipts_consultation_id_fkey
    foreign key (consultation_id)
    references public.professional_consultations(id)
    on update restrict
    on delete cascade,
  constraint consultation_save_receipts_revision_check
    check (resulting_revision >= 0)
);

create table private.consultation_transition_context_v43 (
  backend_pid integer not null,
  transaction_id bigint not null,
  consultation_id uuid not null,
  target_status text not null,
  constraint consultation_transition_context_v43_pkey
    primary key (backend_pid, transaction_id, consultation_id, target_status)
);

create index consultation_edit_leases_holder_expiry_idx
  on public.consultation_edit_leases (holder_user_id, expires_at);
create index consultation_save_receipts_consultation_created_idx
  on public.consultation_save_receipts (consultation_id, created_at);

create or replace function private.normalize_consultation_device_label_v43(
  target_device_label text
)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  normalized_label text;
begin
  normalized_label := pg_catalog.regexp_replace(
    coalesce(target_device_label, ''),
    '[[:cntrl:]]+',
    ' ',
    'g'
  );
  normalized_label := pg_catalog.regexp_replace(
    pg_catalog.btrim(normalized_label),
    '[[:space:]]+',
    ' ',
    'g'
  );
  normalized_label := pg_catalog.left(normalized_label, 80);

  if normalized_label = '' then
    normalized_label := 'Unknown device';
  end if;

  return normalized_label;
end;
$$;

create or replace function private.consultation_lease_verifier_v43(
  target_consultation_id uuid,
  target_lease_version bigint,
  target_raw_token text
)
returns bytea
language sql
immutable
strict
security definer
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(
      'forja.consultation.lease.v43:'
      || target_consultation_id::text || ':'
      || target_lease_version::text || ':'
      || target_raw_token,
      'UTF8'
    ),
    'sha256'
  );
$$;

create or replace function private.consultation_jsonb_depth_bounded_v43(
  target_value jsonb,
  current_depth integer
)
returns integer
language plpgsql
immutable
strict
security definer
set search_path = ''
as $$
declare
  child_depth integer;
begin
  if current_depth >= 17 then
    return 17;
  end if;

  if pg_catalog.jsonb_typeof(target_value) = 'object' then
    select coalesce(
      max(private.consultation_jsonb_depth_bounded_v43(entry.value, current_depth + 1)),
      current_depth + 1
    )
    into child_depth
    from pg_catalog.jsonb_each(target_value) entry;
    return child_depth;
  end if;

  if pg_catalog.jsonb_typeof(target_value) = 'array' then
    select coalesce(
      max(private.consultation_jsonb_depth_bounded_v43(entry.value, current_depth + 1)),
      current_depth + 1
    )
    into child_depth
    from pg_catalog.jsonb_array_elements(target_value) entry(value);
    return child_depth;
  end if;

  return current_depth;
end;
$$;

create or replace function private.consultation_jsonb_depth_v43(
  target_value jsonb
)
returns integer
language sql
immutable
strict
security definer
set search_path = ''
as $$
  select private.consultation_jsonb_depth_bounded_v43(target_value, 0);
$$;

create or replace function private.lock_consultation_authority_rows_v43(
  target_relationship public.professional_student_relationships
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  account_record public.user_commercial_accounts;
begin
  -- Deterministic shared authority order after the relationship SHARE lock and
  -- before the consultation UPDATE lock: commercial account -> plan -> account
  -- mode -> subject identity -> organization -> membership. SHARE conflicts
  -- with authority revocation updates without serializing independent writers.
  select account.*
  into account_record
  from public.user_commercial_accounts account
  where account.user_id = target_relationship.professional_user_id
  for share;

  if found and account_record.plan_code is not null then
    perform 1
    from public.account_plan_catalog plan
    where plan.code = account_record.plan_code
      and plan.account_type = account_record.primary_account_type
    for share;
  end if;

  perform 1
  from public.user_account_modes account_mode
  where account_mode.user_id = target_relationship.professional_user_id
  order by account_mode.id
  for share;

  perform 1
  from public.user_identity_details identity
  where identity.user_id = target_relationship.student_user_id
  for share;

  if target_relationship.organization_id is not null then
    perform 1
    from public.organizations organization
    where organization.id = target_relationship.organization_id
    for share;

    perform 1
    from public.organization_members membership
    where membership.organization_id = target_relationship.organization_id
      and membership.user_id = target_relationship.professional_user_id
    order by membership.id
    for share;
  end if;
end;
$$;

create or replace function private.assert_consultation_relationship_subject_binding_v43()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  relationship_record public.professional_student_relationships;
  binding_valid boolean;
begin
  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = new.relationship_id;

  perform 1
  from public.consultation_subjects subject
  join public.professional_student_relationships relationship
    on subject.account_user_id = relationship.student_user_id
  where subject.id = new.subject_id
    and relationship.id = new.relationship_id;

  if not found then
    raise exception 'consultation_relationship_subject_mismatch'
      using errcode = '23514';
  end if;

  select true
  into binding_valid
  from public.professional_student_relationships relationship
  cross join lateral (
    select
      new.author_user_id,
      new.professional_type,
      new.organization_id
  ) consultation
  where relationship.id = new.relationship_id
    and relationship.professional_user_id = consultation.author_user_id
    and relationship.professional_type = consultation.professional_type
    and relationship.organization_id is not distinct from consultation.organization_id;

  if not coalesce(binding_valid, false) then
    if relationship_record.professional_user_id is distinct from new.author_user_id then
      raise exception 'consultation_relationship_author_mismatch'
        using errcode = '23514';
    end if;

    if relationship_record.professional_type is distinct from new.professional_type then
      raise exception 'consultation_relationship_professional_type_mismatch'
        using errcode = '23514';
    end if;

    if relationship_record.organization_id is distinct from new.organization_id then
      raise exception 'consultation_relationship_organization_mismatch'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create or replace function private.allow_consultation_transition_v43(
  target_consultation_id uuid,
  target_status text
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.consultation_transition_context_v43 (
    backend_pid,
    transaction_id,
    consultation_id,
    target_status
  ) values (
    pg_catalog.pg_backend_pid(),
    pg_catalog.txid_current(),
    target_consultation_id,
    target_status
  )
  on conflict do nothing;
$$;

create or replace function private.protect_finalized_consultation_provenance_v43()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  transition_allowed boolean := false;
begin
  if tg_op = 'UPDATE' then
    delete from private.consultation_transition_context_v43 transition
    where transition.backend_pid = pg_catalog.pg_backend_pid()
      and transition.transaction_id = pg_catalog.txid_current()
      and transition.consultation_id = old.id
      and transition.target_status = new.status
    returning true into transition_allowed;
  end if;

  if (
      old.status = 'finalized'
      or exists (
        select 1
        from public.consultation_final_snapshots snapshot
        where snapshot.consultation_id = old.id
      )
    )
    and not coalesce(transition_allowed, false)
  then
    raise exception 'finalized_consultation_provenance_is_immutable'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create or replace function private.assert_locked_consultation_write_entitlement_v43(
  target_consultation_id uuid,
  target_required_scope text default 'manage_consultations'
)
returns public.professional_consultations
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  discovered_relationship_id uuid;
  relationship_record public.professional_student_relationships;
  consultation_record public.professional_consultations;
  subject_account_user_id uuid;
begin
  if caller_user_id is null then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  select consultation.relationship_id
  into discovered_relationship_id
  from public.professional_consultations consultation
  where consultation.id = target_consultation_id;

  if discovered_relationship_id is null then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = discovered_relationship_id
  for share;

  perform private.lock_consultation_authority_rows_v43(relationship_record);

  select consultation.*
  into consultation_record
  from public.professional_consultations consultation
  where consultation.id = target_consultation_id
    and consultation.relationship_id = relationship_record.id
  for update;

  if not found
     or consultation_record.author_user_id <> caller_user_id
     or relationship_record.professional_user_id <> consultation_record.author_user_id then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  select subject.account_user_id
  into subject_account_user_id
  from public.consultation_subjects subject
  where subject.id = consultation_record.subject_id;

  if subject_account_user_id is distinct from relationship_record.student_user_id
     or relationship_record.professional_type is distinct from consultation_record.professional_type
     or relationship_record.organization_id is distinct from consultation_record.organization_id then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  if relationship_record.status <> 'active'
     or (
       target_required_scope = 'manage_consultations'
       and not coalesce(
         (relationship_record.scopes ->> 'manage_consultations')::boolean,
         false
       )
     ) then
    if relationship_record.status <> 'active'
       or exists (
         select 1
         from public.consultation_events event
         where event.consultation_id = consultation_record.id
           and event.reason_category = 'relationship_revoked'
       ) then
      raise exception 'consultation_relationship_revoked'
        using errcode = '42501';
    end if;
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  perform private.assert_consultation_relationship_entitlement_v43(
    relationship_record.id,
    caller_user_id,
    target_required_scope
  );

  return consultation_record;
end;
$$;

create or replace function private.assert_consultation_lease_v43(
  target_consultation_id uuid,
  target_raw_token text,
  target_lease_version bigint,
  target_expected_purpose text default null
)
returns public.consultation_edit_leases
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  lease_record public.consultation_edit_leases;
begin
  select lease.*
  into lease_record
  from public.consultation_edit_leases lease
  where lease.consultation_id = target_consultation_id
  for update;

  if not found then
    raise exception 'consultation_stale_lease' using errcode = '55000';
  end if;

  if target_lease_version < lease_record.lease_version then
    raise exception 'consultation_lease_taken_over' using errcode = '55000';
  end if;

  if target_raw_token is null
     or target_raw_token !~ '^[0-9a-fA-F]{64}$' then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  if target_lease_version <> lease_record.lease_version
     or lease_record.token_verifier <> private.consultation_lease_verifier_v43(
       target_consultation_id,
       target_lease_version,
       target_raw_token
     ) then
    raise exception 'consultation_stale_lease' using errcode = '55000';
  end if;

  if target_expected_purpose is not null
     and lease_record.purpose <> target_expected_purpose then
    raise exception 'consultation_stale_lease' using errcode = '55000';
  end if;

  if lease_record.invalidated_at is not null then
    if lease_record.invalidation_reason = 'relationship_revoked' then
      raise exception 'consultation_relationship_revoked' using errcode = '42501';
    elsif lease_record.invalidation_reason = 'lease_takeover' then
      raise exception 'consultation_lease_taken_over' using errcode = '55000';
    end if;
    raise exception 'consultation_stale_lease' using errcode = '55000';
  end if;

  if lease_record.expires_at <= pg_catalog.statement_timestamp() then
    raise exception 'consultation_expired_lease' using errcode = '55000';
  end if;

  return lease_record;
end;
$$;

create or replace function private.issue_consultation_lease_v43(
  target_consultation public.professional_consultations,
  target_device_label text,
  target_purpose text,
  target_takeover boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  lease_record public.consultation_edit_leases;
  lease_found boolean := false;
  next_version bigint;
  raw_token text;
  issued_at timestamp with time zone := pg_catalog.statement_timestamp();
begin
  if target_purpose not in ('edit', 'discard', 'cleanup') then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  if (target_purpose = 'edit' and target_consultation.status not in ('scheduled', 'in_progress'))
     or (target_purpose = 'discard' and target_consultation.status <> 'paused')
     or (target_purpose = 'cleanup' and target_consultation.status <> 'cancelled') then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;

  select lease.*
  into lease_record
  from public.consultation_edit_leases lease
  where lease.consultation_id = target_consultation.id
  for update;

  lease_found := found;

  if target_takeover and not lease_found then
    raise exception 'consultation_stale_lease' using errcode = '55000';
  end if;

  if target_takeover and lease_record.invalidated_at is not null then
    raise exception 'consultation_stale_lease' using errcode = '55000';
  end if;

  if target_takeover and lease_record.expires_at <= issued_at then
    raise exception 'consultation_expired_lease' using errcode = '55000';
  end if;

  if lease_found
     and not target_takeover
     and lease_record.invalidated_at is null
     and lease_record.expires_at > issued_at then
    raise exception 'consultation_stale_lease' using errcode = '55000';
  end if;

  next_version := coalesce(lease_record.lease_version, 0) + 1;
  raw_token := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.consultation_edit_leases (
    consultation_id,
    holder_user_id,
    token_verifier,
    lease_version,
    purpose,
    device_label,
    acquired_at,
    heartbeat_at,
    expires_at,
    invalidated_at,
    invalidation_reason,
    takeover_count
  ) values (
    target_consultation.id,
    caller_user_id,
    private.consultation_lease_verifier_v43(
      target_consultation.id,
      next_version,
      raw_token
    ),
    next_version,
    target_purpose,
    private.normalize_consultation_device_label_v43(target_device_label),
    issued_at,
    issued_at,
    issued_at + interval '60 seconds',
    null,
    null,
    case when target_takeover then coalesce(lease_record.takeover_count, 0) + 1
         else coalesce(lease_record.takeover_count, 0) end
  )
  on conflict (consultation_id) do update
  set holder_user_id = excluded.holder_user_id,
      token_verifier = excluded.token_verifier,
      lease_version = excluded.lease_version,
      purpose = excluded.purpose,
      device_label = excluded.device_label,
      acquired_at = excluded.acquired_at,
      heartbeat_at = excluded.heartbeat_at,
      expires_at = excluded.expires_at,
      invalidated_at = null,
      invalidation_reason = null,
      takeover_count = excluded.takeover_count;

  return pg_catalog.jsonb_build_object(
    'consultationId', target_consultation.id,
    'leaseToken', raw_token,
    'leaseVersion', next_version,
    'purpose', target_purpose,
    'heartbeatAt', issued_at,
    'expiresAt', issued_at + interval '60 seconds'
  );
end;
$$;

create or replace function public.get_consultation_lifecycle_constants_v43()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'autosaveDebounceMs', 1200,
    'leaseHeartbeatSeconds', 20,
    'leaseExpirySeconds', 60,
    'deviceLabelMaxCodePoints', 80
  );
$$;

create or replace function public.create_my_consultation_v43(
  target_relationship_id uuid,
  target_consultation_kind text,
  target_predecessor_consultation_id uuid,
  target_scheduled_start_at timestamp with time zone,
  target_scheduled_time_zone text,
  target_scheduled_utc_offset_minutes smallint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  relationship_record public.professional_student_relationships;
  resolved_subject_id uuid;
  created_consultation_id uuid;
begin
  if caller_user_id is null then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = target_relationship_id
  for update;

  if not found or relationship_record.professional_user_id <> caller_user_id then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  perform private.lock_consultation_authority_rows_v43(relationship_record);

  perform private.assert_consultation_relationship_entitlement_v43(
    relationship_record.id,
    caller_user_id,
    'manage_consultations'
  );

  if target_consultation_kind not in ('initial', 'reassessment')
     or ((target_scheduled_start_at is null)::integer
       + (target_scheduled_time_zone is null)::integer
       + (target_scheduled_utc_offset_minutes is null)::integer) not in (0, 3) then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  insert into public.consultation_subjects (
    subject_kind,
    account_user_id,
    created_by_user_id
  ) values (
    'account',
    relationship_record.student_user_id,
    caller_user_id
  )
  on conflict (account_user_id) do update
  set updated_at = public.consultation_subjects.updated_at
  returning id into resolved_subject_id;

  insert into public.professional_consultations (
    subject_id,
    author_user_id,
    relationship_id,
    professional_type,
    organization_id,
    consultation_kind,
    predecessor_consultation_id,
    status,
    scheduled_start_at,
    scheduled_time_zone,
    scheduled_utc_offset_minutes,
    schedule_revision
  ) values (
    resolved_subject_id,
    caller_user_id,
    relationship_record.id,
    relationship_record.professional_type,
    relationship_record.organization_id,
    target_consultation_kind,
    target_predecessor_consultation_id,
    'scheduled',
    target_scheduled_start_at,
    target_scheduled_time_zone,
    target_scheduled_utc_offset_minutes,
    case when target_scheduled_start_at is null then 0 else 1 end
  ) returning id into created_consultation_id;

  insert into public.consultation_events (
    consultation_id,
    subject_id,
    actor_user_id,
    relationship_id,
    event_type
  ) values (
    created_consultation_id,
    resolved_subject_id,
    caller_user_id,
    relationship_record.id,
    'created'
  );

  return created_consultation_id;
end;
$$;

create or replace function public.reschedule_my_consultation_v43(
  target_consultation_id uuid,
  target_expected_schedule_revision integer,
  target_scheduled_start_at timestamp with time zone,
  target_scheduled_time_zone text,
  target_scheduled_utc_offset_minutes smallint
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
  next_revision integer;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );

  if consultation_record.status <> 'scheduled'
     or target_scheduled_start_at is null
     or target_scheduled_time_zone is null
     or target_scheduled_utc_offset_minutes is null then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;

  if consultation_record.schedule_revision <> target_expected_schedule_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  next_revision := consultation_record.schedule_revision + 1;
  update public.professional_consultations consultation
  set scheduled_start_at = target_scheduled_start_at,
      scheduled_time_zone = target_scheduled_time_zone,
      scheduled_utc_offset_minutes = target_scheduled_utc_offset_minutes,
      schedule_revision = next_revision,
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'rescheduled'
  );

  return next_revision;
end;
$$;

create or replace function public.acquire_my_consultation_lease_v43(
  target_consultation_id uuid,
  target_device_label text,
  target_purpose text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  if target_purpose = 'cleanup' then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );
  return private.issue_consultation_lease_v43(
    consultation_record,
    target_device_label,
    target_purpose,
    false
  );
end;
$$;

create or replace function public.heartbeat_my_consultation_lease_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
  lease_record public.consultation_edit_leases;
  heartbeat_time timestamp with time zone := pg_catalog.statement_timestamp();
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );
  lease_record := private.assert_consultation_lease_v43(
    target_consultation_id,
    target_lease_token,
    target_lease_version,
    null
  );

  update public.consultation_edit_leases lease
  set heartbeat_at = heartbeat_time,
      expires_at = heartbeat_time + interval '60 seconds'
  where lease.consultation_id = consultation_record.id;

  return pg_catalog.jsonb_build_object(
    'consultationId', consultation_record.id,
    'leaseVersion', lease_record.lease_version,
    'heartbeatAt', heartbeat_time,
    'expiresAt', heartbeat_time + interval '60 seconds'
  );
end;
$$;

create or replace function public.takeover_my_consultation_lease_v43(
  target_consultation_id uuid,
  target_device_label text,
  target_purpose text,
  target_expected_draft_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
  lease_payload jsonb;
begin
  if target_purpose = 'cleanup' then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );

  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  lease_payload := private.issue_consultation_lease_v43(
    consultation_record,
    target_device_label,
    target_purpose,
    true
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'lease_takeover'
  );

  return lease_payload;
end;
$$;

create or replace function private.invalidate_consultation_lease_v43(
  target_consultation_id uuid,
  target_reason text
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.consultation_edit_leases lease
  set invalidated_at = pg_catalog.statement_timestamp(),
      invalidation_reason = target_reason,
      expires_at = greatest(
        lease.expires_at,
        lease.heartbeat_at + interval '1 microsecond'
      )
  where lease.consultation_id = target_consultation_id
    and lease.invalidated_at is null;
$$;

create or replace function public.start_my_consultation_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );
  perform private.assert_consultation_lease_v43(
    target_consultation_id,
    target_lease_token,
    target_lease_version,
    'edit'
  );

  if consultation_record.status <> 'scheduled' then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  update public.professional_consultations consultation
  set status = 'in_progress',
      started_at = coalesce(consultation.started_at, pg_catalog.statement_timestamp()),
      paused_at = null,
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'started'
  );

  return consultation_record.draft_revision;
end;
$$;

create or replace function public.autosave_my_consultation_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint,
  target_correlation_id uuid,
  target_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  consultation_record public.professional_consultations;
  receipt_record public.consultation_save_receipts;
  patch_item jsonb;
  patch_item_key text;
  patch_item_kind text;
  current_value jsonb;
  current_exists boolean;
  next_revision bigint;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );
  perform private.assert_consultation_lease_v43(
    target_consultation_id,
    target_lease_token,
    target_lease_version,
    'edit'
  );

  if consultation_record.status not in ('scheduled', 'in_progress') then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;

  select receipt.*
  into receipt_record
  from public.consultation_save_receipts receipt
  where receipt.author_user_id = caller_user_id
    and receipt.consultation_id = consultation_record.id
    and receipt.correlation_id = target_correlation_id;

  if found then
    return pg_catalog.jsonb_build_object(
      'consultationId', consultation_record.id,
      'draftRevision', receipt_record.resulting_revision,
      'idempotent', true
    );
  end if;

  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  if target_correlation_id is null
     or target_patch is null
     or pg_catalog.jsonb_typeof(target_patch) <> 'array'
     or pg_catalog.jsonb_array_length(target_patch) > 100
     or pg_catalog.pg_column_size(target_patch) > 65536 then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  for patch_item in
    select patch_entry.value
    from pg_catalog.jsonb_array_elements(target_patch) patch_entry(value)
  loop
    patch_item_key := patch_item ->> 'itemKey';
    patch_item_kind := patch_item ->> 'itemKind';

    if pg_catalog.jsonb_typeof(patch_item) <> 'object'
       or patch_item_key is null
       or length(patch_item_key) not between 1 and 160
       or patch_item_key !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
       or patch_item_kind not in ('text','number','boolean','date','selection','structured')
       or not (patch_item ? 'value')
       or pg_catalog.jsonb_typeof(patch_item -> 'value') <> 'object'
       or pg_catalog.pg_column_size(patch_item -> 'value') > 16384
       or private.consultation_jsonb_depth_v43(patch_item -> 'value') > 16 then
      raise exception 'consultation_validation_failed' using errcode = '22023';
    end if;

    select item.value_payload, true
    into current_value, current_exists
    from public.consultation_items item
    where item.consultation_id = consultation_record.id
      and item.item_key = patch_item_key;

    if patch_item ? 'expectedOriginalValue'
       and (
         not coalesce(current_exists, false)
         or current_value is distinct from patch_item -> 'expectedOriginalValue'
       ) then
      raise exception 'consultation_stale_revision' using errcode = '55000';
    end if;

    current_value := null;
    current_exists := false;
  end loop;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(target_patch) patch_entry(value)
    group by patch_entry.value ->> 'itemKey'
    having count(*) > 1
  ) then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  for patch_item in
    select patch_entry.value
    from pg_catalog.jsonb_array_elements(target_patch) patch_entry(value)
  loop
    insert into public.consultation_items (
      consultation_id,
      item_key,
      item_kind,
      schema_version,
      value_payload
    ) values (
      consultation_record.id,
      patch_item ->> 'itemKey',
      patch_item ->> 'itemKind',
      1,
      patch_item -> 'value'
    )
    on conflict (consultation_id, item_key) do update
    set item_kind = excluded.item_kind,
        value_payload = excluded.value_payload,
        updated_at = pg_catalog.statement_timestamp();
  end loop;

  next_revision := consultation_record.draft_revision + 1;
  update public.professional_consultations consultation
  set draft_revision = next_revision,
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  insert into public.consultation_save_receipts (
    author_user_id,
    consultation_id,
    correlation_id,
    resulting_revision
  ) values (
    caller_user_id,
    consultation_record.id,
    target_correlation_id,
    next_revision
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    caller_user_id,
    consultation_record.relationship_id,
    'autosaved'
  );

  return pg_catalog.jsonb_build_object(
    'consultationId', consultation_record.id,
    'draftRevision', next_revision,
    'idempotent', false
  );
end;
$$;

create or replace function public.pause_my_consultation_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );
  perform private.assert_consultation_lease_v43(
    target_consultation_id,
    target_lease_token,
    target_lease_version,
    'edit'
  );

  if consultation_record.status <> 'in_progress' then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  update public.professional_consultations consultation
  set status = 'paused',
      paused_at = pg_catalog.statement_timestamp(),
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  perform private.invalidate_consultation_lease_v43(
    consultation_record.id,
    'paused'
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'paused'
  );

  return consultation_record.draft_revision;
end;
$$;

create or replace function public.resume_my_consultation_v43(
  target_consultation_id uuid,
  target_device_label text,
  target_expected_draft_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
  lease_payload jsonb;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );

  if consultation_record.status <> 'paused' then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  update public.professional_consultations consultation
  set status = 'in_progress',
      paused_at = null,
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  consultation_record.status := 'in_progress';
  lease_payload := private.issue_consultation_lease_v43(
    consultation_record,
    target_device_label,
    'edit',
    false
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'resumed'
  );

  return lease_payload;
end;
$$;

create or replace function public.cancel_my_consultation_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint,
  target_reason_category text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );
  perform private.assert_consultation_lease_v43(
    target_consultation_id,
    target_lease_token,
    target_lease_version,
    case when consultation_record.status = 'paused' then 'discard' else 'edit' end
  );

  if consultation_record.status not in ('scheduled', 'in_progress', 'paused') then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;
  if target_reason_category <> 'author_cancelled' then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  update public.professional_consultations consultation
  set status = 'cancelled',
      cancelled_at = pg_catalog.statement_timestamp(),
      paused_at = null,
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  perform private.invalidate_consultation_lease_v43(
    consultation_record.id,
    'cancelled'
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id,
    event_type, reason_category
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'cancelled',
    target_reason_category
  );

  return consultation_record.draft_revision;
end;
$$;

create or replace function public.cancel_my_finalized_consultation_v43(
  target_consultation_id uuid,
  target_reason_category text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );

  if consultation_record.status <> 'finalized' then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if target_reason_category <> 'administrative_correction' then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  perform private.allow_consultation_transition_v43(
    consultation_record.id,
    'cancelled'
  );
  update public.professional_consultations consultation
  set status = 'cancelled',
      cancelled_at = pg_catalog.statement_timestamp(),
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id,
    event_type, reason_category
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'finalized_cancelled',
    target_reason_category
  );

  return true;
end;
$$;

create or replace function public.mark_my_consultation_no_show_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );

  if consultation_record.status <> 'scheduled'
     or consultation_record.scheduled_start_at is null
     or consultation_record.scheduled_start_at > pg_catalog.statement_timestamp() then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  perform private.assert_consultation_lease_v43(
    target_consultation_id,
    target_lease_token,
    target_lease_version,
    'edit'
  );
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  update public.professional_consultations consultation
  set status = 'no_show',
      no_show_at = pg_catalog.statement_timestamp(),
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  perform private.invalidate_consultation_lease_v43(
    consultation_record.id,
    'no_show'
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'no_show'
  );

  return consultation_record.draft_revision;
end;
$$;

create or replace function public.archive_my_consultation_v43(
  target_consultation_id uuid,
  target_expected_draft_revision bigint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );

  if consultation_record.status not in ('finalized', 'cancelled', 'no_show') then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  if consultation_record.status = 'finalized'
     or exists (
       select 1
       from public.consultation_final_snapshots snapshot
       where snapshot.consultation_id = consultation_record.id
     ) then
    perform private.allow_consultation_transition_v43(
      consultation_record.id,
      'archived'
    );
  end if;

  update public.professional_consultations consultation
  set status = 'archived',
      archived_at = pg_catalog.statement_timestamp(),
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'archived'
  );

  return true;
end;
$$;

create or replace function public.finalize_my_consultation_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
  snapshot_payload jsonb;
  created_snapshot_id uuid;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );
  perform private.assert_consultation_lease_v43(
    target_consultation_id,
    target_lease_token,
    target_lease_version,
    'edit'
  );

  if consultation_record.status <> 'in_progress' then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  select pg_catalog.jsonb_build_object(
    'items',
    coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'itemKey', item.item_key,
          'itemKind', item.item_kind,
          'schemaVersion', item.schema_version,
          'value', item.value_payload
        ) order by item.item_key
      ),
      '[]'::jsonb
    )
  )
  into snapshot_payload
  from public.consultation_items item
  where item.consultation_id = consultation_record.id;

  update public.professional_consultations consultation
  set status = 'finalized',
      finalized_at = pg_catalog.statement_timestamp(),
      paused_at = null,
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  insert into public.consultation_final_snapshots (
    consultation_id,
    finalized_by_user_id,
    schema_version,
    canonical_payload
  ) values (
    consultation_record.id,
    auth.uid(),
    consultation_record.schema_version,
    snapshot_payload
  ) returning id into created_snapshot_id;

  perform private.invalidate_consultation_lease_v43(
    consultation_record.id,
    'finalized'
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'finalized'
  );

  return created_snapshot_id;
end;
$$;

create or replace function public.discard_my_consultation_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint,
  target_reason_category text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  consultation_record := private.assert_locked_consultation_write_entitlement_v43(
    target_consultation_id
  );
  perform private.assert_consultation_lease_v43(
    target_consultation_id,
    target_lease_token,
    target_lease_version,
    case when consultation_record.status = 'paused' then 'discard' else 'edit' end
  );

  if consultation_record.status not in ('scheduled', 'in_progress', 'paused')
     or exists (
       select 1 from public.consultation_final_snapshots snapshot
       where snapshot.consultation_id = consultation_record.id
     ) then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;
  if target_reason_category <> 'author_discard' then
    raise exception 'consultation_validation_failed' using errcode = '22023';
  end if;

  insert into public.consultation_discard_tombstones (
    discarded_consultation_id,
    subject_id,
    author_user_id,
    relationship_id,
    discarded_by_user_id,
    reason_category
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    consultation_record.author_user_id,
    consultation_record.relationship_id,
    auth.uid(),
    target_reason_category
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id,
    event_type, reason_category
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    auth.uid(),
    consultation_record.relationship_id,
    'discarded',
    target_reason_category
  );

  delete from public.professional_consultations consultation
  where consultation.id = consultation_record.id;

  return true;
end;
$$;

create or replace function public.acquire_my_revoked_consultation_cleanup_lease_v43(
  target_consultation_id uuid,
  target_device_label text,
  target_expected_draft_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  discovered_relationship_id uuid;
  relationship_record public.professional_student_relationships;
  consultation_record public.professional_consultations;
begin
  if caller_user_id is null then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  select consultation.relationship_id
  into discovered_relationship_id
  from public.professional_consultations consultation
  where consultation.id = target_consultation_id;

  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = discovered_relationship_id
  for update;

  select consultation.*
  into consultation_record
  from public.professional_consultations consultation
  where consultation.id = target_consultation_id
    and consultation.relationship_id = relationship_record.id
  for update;

  if not found
     or consultation_record.author_user_id <> caller_user_id
     or relationship_record.professional_user_id <> consultation_record.author_user_id then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;
  if consultation_record.status <> 'cancelled'
     or exists (
       select 1 from public.consultation_final_snapshots snapshot
       where snapshot.consultation_id = consultation_record.id
     )
     or not exists (
       select 1 from public.consultation_events event
       where event.consultation_id = consultation_record.id
         and event.reason_category = 'relationship_revoked'
     ) then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  return private.issue_consultation_lease_v43(
    consultation_record,
    target_device_label,
    'cleanup',
    false
  );
end;
$$;

create or replace function public.cleanup_my_revoked_consultation_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  discovered_relationship_id uuid;
  relationship_record public.professional_student_relationships;
  consultation_record public.professional_consultations;
begin
  if caller_user_id is null then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  select consultation.relationship_id
  into discovered_relationship_id
  from public.professional_consultations consultation
  where consultation.id = target_consultation_id;

  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = discovered_relationship_id
  for update;

  select consultation.*
  into consultation_record
  from public.professional_consultations consultation
  where consultation.id = target_consultation_id
    and consultation.relationship_id = relationship_record.id
  for update;

  if not found
     or consultation_record.author_user_id <> caller_user_id
     or relationship_record.professional_user_id <> consultation_record.author_user_id then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;
  if consultation_record.status <> 'cancelled'
     or exists (
       select 1 from public.consultation_final_snapshots snapshot
       where snapshot.consultation_id = consultation_record.id
     )
     or not exists (
       select 1 from public.consultation_events event
       where event.consultation_id = consultation_record.id
         and event.reason_category = 'relationship_revoked'
     ) then
    raise exception 'consultation_invalid_lifecycle_state' using errcode = '55000';
  end if;
  if consultation_record.draft_revision <> target_expected_draft_revision then
    raise exception 'consultation_stale_revision' using errcode = '55000';
  end if;

  perform private.assert_consultation_lease_v43(
    consultation_record.id,
    target_lease_token,
    target_lease_version,
    'cleanup'
  );

  insert into public.consultation_discard_tombstones (
    discarded_consultation_id,
    subject_id,
    author_user_id,
    relationship_id,
    discarded_by_user_id,
    reason_category
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    consultation_record.author_user_id,
    consultation_record.relationship_id,
    caller_user_id,
    'relationship_revoked_cleanup'
  );

  delete from public.professional_consultations consultation
  where consultation.id = consultation_record.id;

  return true;
end;
$$;

create or replace function private.invalidate_consultations_for_revoked_relationship_v43(
  target_relationship_id uuid,
  target_actor_user_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  for consultation_record in
    select consultation.*
    from public.professional_consultations consultation
    where consultation.relationship_id = target_relationship_id
      and consultation.status in ('scheduled', 'in_progress', 'paused')
    order by consultation.id
    for update
  loop
    update public.professional_consultations consultation
    set status = 'cancelled',
        cancelled_at = pg_catalog.statement_timestamp(),
        paused_at = null,
        updated_at = pg_catalog.statement_timestamp()
    where consultation.id = consultation_record.id;

    perform private.invalidate_consultation_lease_v43(
      consultation_record.id,
      'relationship_revoked'
    );

    insert into public.consultation_events (
      consultation_id,
      subject_id,
      actor_user_id,
      relationship_id,
      event_type,
      reason_category
    ) values (
      consultation_record.id,
      consultation_record.subject_id,
      target_actor_user_id,
      consultation_record.relationship_id,
      'cancelled',
      'relationship_revoked'
    );
  end loop;
end;
$$;

create or replace function private.invalidate_consultation_leases_for_revoked_authorization_v43(
  target_relationship_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
begin
  -- The relationship row is already locked by the caller. Preserve the
  -- relationship -> consultation -> lease order without changing lifecycle.
  for consultation_record in
    select consultation.*
    from public.professional_consultations consultation
    where consultation.relationship_id = target_relationship_id
      and consultation.status in ('scheduled', 'in_progress', 'paused')
    order by consultation.id
    for update
  loop
    perform private.invalidate_consultation_lease_v43(
      consultation_record.id,
      'authorization_revoked'
    );
  end loop;
end;
$$;

create or replace function private.protect_consultation_relationship_authorization_v43()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  last_disclosure_version text;
begin
  if old.status = 'active' and new.status <> 'active' then
    -- The delegated helper locks and updates public.professional_consultations,
    -- then invalidates matching public.consultation_edit_leases with the
    -- content-free relationship_revoked reason atomically.
    new.scopes := pg_catalog.jsonb_set(
      pg_catalog.jsonb_set(
        new.scopes,
        '{manage_consultations}',
        'false'::jsonb,
        true
      ),
      '{view_shared_consultation_history}',
      'false'::jsonb,
      true
    );

    update public.consultation_authorization_requests request
    set status = 'invalidated',
        invalidated_at = pg_catalog.statement_timestamp()
    where request.relationship_id = new.id
      and request.status = 'pending';

    if coalesce((old.scopes ->> 'manage_consultations')::boolean, false) then
      insert into public.consultation_authorization_events (
        relationship_id,
        professional_user_id,
        client_user_id,
        actor_user_id,
        event_type,
        occurred_at
      ) values (
        old.id,
        old.professional_user_id,
        old.student_user_id,
        auth.uid(),
        'relationship_invalidated',
        pg_catalog.statement_timestamp()
      );
    end if;

    if coalesce(
      (old.scopes ->> 'view_shared_consultation_history')::boolean,
      false
    ) then
      select consent.disclosure_text_version
      into last_disclosure_version
      from public.consultation_sharing_consents consent
      where consent.relationship_id = old.id
      order by consent.event_sequence desc
      limit 1;

      if last_disclosure_version is not null then
        insert into public.consultation_sharing_consents (
          relationship_id,
          professional_user_id,
          client_user_id,
          actor_user_id,
          disclosure_text_version,
          granted,
          event_type,
          occurred_at
        ) values (
          old.id,
          old.professional_user_id,
          old.student_user_id,
          auth.uid(),
          last_disclosure_version,
          false,
          'relationship_invalidated',
          pg_catalog.statement_timestamp()
        );
      end if;
    end if;

    perform private.invalidate_consultations_for_revoked_relationship_v43(
      old.id,
      auth.uid()
    );
  end if;

  return new;
end;
$$;

create or replace function public.revoke_my_consultation_authorization_v43(
  target_relationship_id uuid,
  target_authorization_text_version text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  relationship_record public.professional_student_relationships;
begin
  if caller_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = target_relationship_id
    and relationship.student_user_id = caller_user_id
  for update;

  if not found then
    raise exception 'consultation_authorization_revocation_forbidden'
      using errcode = '42501';
  end if;

  perform 1
  from public.consultation_authorization_text_versions version
  where version.purpose = 'manage_consultations'
    and version.version_identifier = target_authorization_text_version;
  if not found then
    raise exception 'invalid_consultation_authorization_version'
      using errcode = '22023';
  end if;

  update public.consultation_authorization_requests request
  set status = 'invalidated',
      invalidated_at = pg_catalog.statement_timestamp()
  where request.relationship_id = relationship_record.id
    and request.status = 'pending';

  update public.professional_student_relationships relationship
  set scopes = pg_catalog.jsonb_set(
        relationship.scopes,
        '{manage_consultations}',
        'false'::jsonb,
        true
      ),
      updated_at = pg_catalog.statement_timestamp()
  where relationship.id = relationship_record.id;

  insert into public.consultation_authorization_events (
    relationship_id,
    professional_user_id,
    client_user_id,
    actor_user_id,
    event_type,
    authorization_text_version
  ) values (
    relationship_record.id,
    relationship_record.professional_user_id,
    caller_user_id,
    caller_user_id,
    'revoked',
    target_authorization_text_version
  );

  perform private.invalidate_consultation_leases_for_revoked_authorization_v43(
    relationship_record.id
  );

  return true;
end;
$$;

create trigger validate_consultation_relationship_subject_binding_v43
before insert or update of subject_id, author_user_id, relationship_id,
  professional_type, organization_id
on public.professional_consultations
for each row
execute function private.assert_consultation_relationship_subject_binding_v43();

alter table public.consultation_edit_leases enable row level security;
alter table public.consultation_edit_leases force row level security;
alter table public.consultation_save_receipts enable row level security;
alter table public.consultation_save_receipts force row level security;

revoke all privileges on table public.consultation_edit_leases
  from public, anon, authenticated;
revoke all privileges on table public.consultation_save_receipts
  from public, anon, authenticated;
revoke all privileges on table private.consultation_transition_context_v43
  from public, anon, authenticated;

revoke all on function
  public.get_consultation_lifecycle_constants_v43(),
  public.create_my_consultation_v43(uuid, text, uuid, timestamp with time zone, text, smallint),
  public.reschedule_my_consultation_v43(uuid, integer, timestamp with time zone, text, smallint),
  public.acquire_my_consultation_lease_v43(uuid, text, text),
  public.heartbeat_my_consultation_lease_v43(uuid, text, bigint),
  public.takeover_my_consultation_lease_v43(uuid, text, text, bigint),
  public.start_my_consultation_v43(uuid, text, bigint, bigint),
  public.autosave_my_consultation_v43(uuid, text, bigint, bigint, uuid, jsonb),
  public.pause_my_consultation_v43(uuid, text, bigint, bigint),
  public.resume_my_consultation_v43(uuid, text, bigint),
  public.cancel_my_consultation_v43(uuid, text, bigint, bigint, text),
  public.cancel_my_finalized_consultation_v43(uuid, text),
  public.mark_my_consultation_no_show_v43(uuid, text, bigint, bigint),
  public.archive_my_consultation_v43(uuid, bigint),
  public.discard_my_consultation_v43(uuid, text, bigint, bigint, text),
  public.acquire_my_revoked_consultation_cleanup_lease_v43(uuid, text, bigint),
  public.cleanup_my_revoked_consultation_v43(uuid, text, bigint, bigint),
  public.finalize_my_consultation_v43(uuid, text, bigint, bigint)
from public, anon, authenticated;

grant execute on function
  public.get_consultation_lifecycle_constants_v43(),
  public.create_my_consultation_v43(uuid, text, uuid, timestamp with time zone, text, smallint),
  public.reschedule_my_consultation_v43(uuid, integer, timestamp with time zone, text, smallint),
  public.acquire_my_consultation_lease_v43(uuid, text, text),
  public.heartbeat_my_consultation_lease_v43(uuid, text, bigint),
  public.takeover_my_consultation_lease_v43(uuid, text, text, bigint),
  public.start_my_consultation_v43(uuid, text, bigint, bigint),
  public.autosave_my_consultation_v43(uuid, text, bigint, bigint, uuid, jsonb),
  public.pause_my_consultation_v43(uuid, text, bigint, bigint),
  public.resume_my_consultation_v43(uuid, text, bigint),
  public.cancel_my_consultation_v43(uuid, text, bigint, bigint, text),
  public.cancel_my_finalized_consultation_v43(uuid, text),
  public.mark_my_consultation_no_show_v43(uuid, text, bigint, bigint),
  public.archive_my_consultation_v43(uuid, bigint),
  public.discard_my_consultation_v43(uuid, text, bigint, bigint, text),
  public.acquire_my_revoked_consultation_cleanup_lease_v43(uuid, text, bigint),
  public.cleanup_my_revoked_consultation_v43(uuid, text, bigint, bigint),
  public.finalize_my_consultation_v43(uuid, text, bigint, bigint)
to authenticated;

revoke all on function
  private.normalize_consultation_device_label_v43(text),
  private.consultation_lease_verifier_v43(uuid, bigint, text),
  private.consultation_jsonb_depth_bounded_v43(jsonb, integer),
  private.consultation_jsonb_depth_v43(jsonb),
  private.lock_consultation_authority_rows_v43(public.professional_student_relationships),
  private.assert_consultation_relationship_subject_binding_v43(),
  private.allow_consultation_transition_v43(uuid, text),
  private.assert_locked_consultation_write_entitlement_v43(uuid, text),
  private.assert_consultation_lease_v43(uuid, text, bigint, text),
  private.issue_consultation_lease_v43(public.professional_consultations, text, text, boolean),
  private.invalidate_consultation_lease_v43(uuid, text),
  private.invalidate_consultations_for_revoked_relationship_v43(uuid, uuid),
  private.invalidate_consultation_leases_for_revoked_authorization_v43(uuid)
from public, anon, authenticated;

commit;
