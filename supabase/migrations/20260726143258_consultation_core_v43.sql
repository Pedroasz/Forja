begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter default privileges for role postgres in schema public
  revoke all privileges on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on routines from public, anon, authenticated;
alter default privileges for role postgres in schema private
  revoke all privileges on routines from public, anon, authenticated;

create table public.consultation_subjects (
  id uuid default gen_random_uuid() not null,
  subject_kind text default 'account' not null,
  account_user_id uuid not null,
  created_by_user_id uuid not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint consultation_subjects_pkey primary key (id),
  constraint consultation_subjects_account_user_id_key unique (account_user_id),
  constraint consultation_subjects_subject_kind_check
    check (subject_kind = 'account'),
  constraint consultation_subjects_account_required_check
    check (subject_kind = 'account' and account_user_id is not null),
  constraint consultation_subjects_account_user_id_fkey
    foreign key (account_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_subjects_created_by_user_id_fkey
    foreign key (created_by_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict
);

create table public.professional_consultations (
  id uuid default gen_random_uuid() not null,
  subject_id uuid not null,
  author_user_id uuid not null,
  relationship_id uuid not null,
  professional_type text not null,
  organization_id uuid,
  consultation_kind text not null,
  predecessor_consultation_id uuid,
  status text default 'scheduled' not null,
  draft_revision bigint default 0 not null,
  schema_version integer default 1 not null,
  scheduled_start_at timestamp with time zone,
  scheduled_time_zone text,
  scheduled_utc_offset_minutes smallint,
  schedule_revision integer default 0 not null,
  started_at timestamp with time zone,
  paused_at timestamp with time zone,
  finalized_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  no_show_at timestamp with time zone,
  archived_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint professional_consultations_pkey primary key (id),
  constraint professional_consultations_subject_id_fkey
    foreign key (subject_id)
    references public.consultation_subjects(id)
    on update restrict
    on delete restrict,
  constraint professional_consultations_author_user_id_fkey
    foreign key (author_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint professional_consultations_relationship_id_fkey
    foreign key (relationship_id)
    references public.professional_student_relationships(id)
    on update restrict
    on delete restrict,
  constraint professional_consultations_organization_id_fkey
    foreign key (organization_id)
    references public.organizations(id)
    on update restrict
    on delete restrict,
  constraint professional_consultations_predecessor_id_fkey
    foreign key (predecessor_consultation_id)
    references public.professional_consultations(id)
    on update restrict
    on delete restrict,
  constraint professional_consultations_professional_type_check
    check (professional_type in ('trainer', 'nutritionist')),
  constraint professional_consultations_kind_check
    check (consultation_kind in ('initial', 'reassessment')),
  constraint professional_consultations_status_check
    check (
      status in (
        'scheduled',
        'in_progress',
        'paused',
        'finalized',
        'cancelled',
        'no_show',
        'archived'
      )
    ),
  constraint professional_consultations_draft_revision_check
    check (draft_revision >= 0),
  constraint professional_consultations_schema_version_check
    check (schema_version >= 1),
  constraint professional_consultations_schedule_revision_check
    check (schedule_revision >= 0),
  constraint professional_consultations_schedule_all_or_none_check
    check (
      (
        scheduled_start_at is null
        and scheduled_time_zone is null
        and scheduled_utc_offset_minutes is null
        and schedule_revision = 0
      )
      or (
        scheduled_start_at is not null
        and scheduled_time_zone is not null
        and scheduled_utc_offset_minutes is not null
        and schedule_revision >= 1
      )
    ),
  constraint professional_consultations_schedule_zone_length_check
    check (
      scheduled_time_zone is null
      or length(scheduled_time_zone) between 1 and 80
    ),
  constraint professional_consultations_schedule_offset_check
    check (
      scheduled_utc_offset_minutes is null
      or scheduled_utc_offset_minutes between -840 and 840
    ),
  constraint professional_consultations_initial_predecessor_check
    check (
      consultation_kind = 'reassessment'
      or predecessor_consultation_id is null
    )
);

create table public.consultation_items (
  id uuid default gen_random_uuid() not null,
  consultation_id uuid not null,
  item_key text not null,
  item_kind text not null,
  schema_version integer default 1 not null,
  value_payload jsonb not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint consultation_items_pkey primary key (id),
  constraint consultation_items_consultation_item_key_key
    unique (consultation_id, item_key),
  constraint consultation_items_consultation_id_fkey
    foreign key (consultation_id)
    references public.professional_consultations(id)
    on update restrict
    on delete cascade,
  constraint consultation_items_item_key_check
    check (
      length(item_key) between 1 and 160
      and item_key ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    ),
  constraint consultation_items_item_kind_check
    check (
      item_kind in (
        'text',
        'number',
        'boolean',
        'date',
        'selection',
        'structured'
      )
    ),
  constraint consultation_items_schema_version_check
    check (schema_version >= 1),
  constraint consultation_items_value_object_check
    check (jsonb_typeof(value_payload) = 'object')
);

create table public.consultation_final_snapshots (
  id uuid default gen_random_uuid() not null,
  consultation_id uuid not null,
  finalized_by_user_id uuid not null,
  schema_version integer not null,
  canonicalization_version text
    default 'forja.canonical-json.v1'
    not null,
  canonical_payload jsonb not null,
  canonical_bytes bytea not null,
  payload_sha256 bytea not null,
  created_at timestamp with time zone default now() not null,
  constraint consultation_final_snapshots_pkey primary key (id),
  constraint consultation_final_snapshots_consultation_id_key
    unique (consultation_id),
  constraint consultation_final_snapshots_consultation_id_fkey
    foreign key (consultation_id)
    references public.professional_consultations(id)
    on update restrict
    on delete restrict,
  constraint consultation_final_snapshots_finalized_by_user_id_fkey
    foreign key (finalized_by_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_final_snapshots_schema_version_check
    check (schema_version >= 1),
  constraint consultation_final_snapshots_canonicalization_check
    check (canonicalization_version = 'forja.canonical-json.v1'),
  constraint consultation_final_snapshots_sha256_length_check
    check (octet_length(payload_sha256) = 32)
);

create table public.consultation_addenda (
  id uuid default gen_random_uuid() not null,
  consultation_id uuid not null,
  final_snapshot_id uuid not null,
  author_user_id uuid not null,
  reason text not null,
  schema_version integer not null,
  canonicalization_version text
    default 'forja.canonical-json.v1'
    not null,
  canonical_payload jsonb not null,
  canonical_bytes bytea not null,
  payload_sha256 bytea not null,
  created_at timestamp with time zone default now() not null,
  constraint consultation_addenda_pkey primary key (id),
  constraint consultation_addenda_consultation_id_fkey
    foreign key (consultation_id)
    references public.professional_consultations(id)
    on update restrict
    on delete restrict,
  constraint consultation_addenda_final_snapshot_id_fkey
    foreign key (final_snapshot_id)
    references public.consultation_final_snapshots(id)
    on update restrict
    on delete restrict,
  constraint consultation_addenda_author_user_id_fkey
    foreign key (author_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_addenda_reason_check
    check (length(btrim(reason)) between 1 and 1000),
  constraint consultation_addenda_schema_version_check
    check (schema_version >= 1),
  constraint consultation_addenda_canonicalization_check
    check (canonicalization_version = 'forja.canonical-json.v1'),
  constraint consultation_addenda_sha256_length_check
    check (octet_length(payload_sha256) = 32)
);

create table public.consultation_discard_tombstones (
  id uuid default gen_random_uuid() not null,
  discarded_consultation_id uuid not null,
  subject_id uuid not null,
  author_user_id uuid not null,
  relationship_id uuid not null,
  discarded_by_user_id uuid not null,
  reason_category text not null,
  discarded_at timestamp with time zone default now() not null,
  constraint consultation_discard_tombstones_pkey primary key (id),
  constraint consultation_discard_tombstones_reason_check
    check (
      reason_category in (
        'author_discard',
        'relationship_revoked_cleanup'
      )
    )
);

create table public.consultation_events (
  id uuid default gen_random_uuid() not null,
  consultation_id uuid not null,
  subject_id uuid not null,
  actor_user_id uuid,
  relationship_id uuid,
  event_type text not null,
  reason_category text,
  occurred_at timestamp with time zone default now() not null,
  constraint consultation_events_pkey primary key (id),
  constraint consultation_events_event_type_check
    check (
      length(event_type) between 1 and 80
      and event_type ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'
    ),
  constraint consultation_events_reason_check
    check (
      reason_category is null
      or (
        length(reason_category) between 1 and 80
        and reason_category ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'
      )
    )
);

create index consultation_subjects_created_by_idx
  on public.consultation_subjects (created_by_user_id);
create index professional_consultations_author_status_idx
  on public.professional_consultations (author_user_id, status, created_at desc);
create index professional_consultations_subject_status_idx
  on public.professional_consultations (subject_id, status, created_at desc);
create index professional_consultations_relationship_status_idx
  on public.professional_consultations (relationship_id, status, created_at desc);
create index professional_consultations_organization_status_idx
  on public.professional_consultations (organization_id, status, created_at desc)
  where organization_id is not null;
create index professional_consultations_predecessor_idx
  on public.professional_consultations (predecessor_consultation_id)
  where predecessor_consultation_id is not null;
create index consultation_items_consultation_idx
  on public.consultation_items (consultation_id, created_at);
create index consultation_final_snapshots_finalized_by_idx
  on public.consultation_final_snapshots (finalized_by_user_id);
create index consultation_addenda_consultation_created_idx
  on public.consultation_addenda (consultation_id, created_at);
create index consultation_addenda_final_snapshot_idx
  on public.consultation_addenda (final_snapshot_id);
create index consultation_addenda_author_created_idx
  on public.consultation_addenda (author_user_id, created_at);
create index consultation_discard_tombstones_consultation_discarded_idx
  on public.consultation_discard_tombstones (
    discarded_consultation_id,
    discarded_at
  );
create index consultation_discard_tombstones_subject_discarded_idx
  on public.consultation_discard_tombstones (subject_id, discarded_at);
create index consultation_discard_tombstones_author_discarded_idx
  on public.consultation_discard_tombstones (author_user_id, discarded_at);
create index consultation_discard_tombstones_relationship_discarded_idx
  on public.consultation_discard_tombstones (relationship_id, discarded_at);
create index consultation_events_consultation_occurred_idx
  on public.consultation_events (consultation_id, occurred_at);
create index consultation_events_subject_occurred_idx
  on public.consultation_events (subject_id, occurred_at);
create index consultation_events_actor_occurred_idx
  on public.consultation_events (actor_user_id, occurred_at)
  where actor_user_id is not null;
create index consultation_events_relationship_occurred_idx
  on public.consultation_events (relationship_id, occurred_at)
  where relationship_id is not null;

create or replace function private.forja_canonical_json_v1_text(
  target_value jsonb
)
returns text
language plpgsql
stable
strict
set search_path = ''
as $$
declare
  value_type text;
  canonical_text text;
  scalar_text text;
begin
  value_type := pg_catalog.jsonb_typeof(target_value);

  if value_type = 'null' then
    return 'null';
  end if;

  if value_type = 'boolean' then
    if target_value = 'true'::jsonb then
      return 'true';
    end if;
    return 'false';
  end if;

  if value_type = 'number' then
    return target_value #>> '{}';
  end if;

  if value_type = 'string' then
    scalar_text := target_value #>> '{}';
    return pg_catalog.to_json(
      normalize(scalar_text)
    )::text;
  end if;

  if value_type = 'array' then
    select
      '['
      || coalesce(
        pg_catalog.string_agg(
          private.forja_canonical_json_v1_text(element.value),
          ','
          order by element.ordinality
        ),
        ''
      )
      || ']'
    into canonical_text
    from pg_catalog.jsonb_array_elements(target_value)
      with ordinality as element(value, ordinality);

    return canonical_text;
  end if;

  if value_type = 'object' then
    if exists (
      select 1
      from pg_catalog.jsonb_each(target_value) entry
      group by normalize(entry.key)
      having count(*) > 1
    ) then
      raise exception 'canonical_json_normalized_key_collision'
        using errcode = '22023';
    end if;

    select
      '{'
      || coalesce(
        pg_catalog.string_agg(
          pg_catalog.to_json(
            normalize(entry.key)
          )::text
          || ':'
          || private.forja_canonical_json_v1_text(entry.value),
          ','
          order by normalize(entry.key) collate "C"
        ),
        ''
      )
      || '}'
    into canonical_text
    from pg_catalog.jsonb_each(target_value) entry;

    return canonical_text;
  end if;

  raise exception 'canonical_json_unsupported_type'
    using errcode = '22023';
end;
$$;

create or replace function private.validate_canonical_json_v1_payload(
  target_value jsonb
)
returns void
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  value_type text;
  scalar_text text;
  nested_value jsonb;
begin
  value_type := pg_catalog.jsonb_typeof(target_value);

  if value_type = 'number' then
    scalar_text := target_value #>> '{}';
    if scalar_text ~ '[.eE]' then
      raise exception 'canonical_json_decimal_must_be_string'
        using errcode = '22023';
    end if;
    return;
  end if;

  if value_type = 'string' then
    scalar_text := normalize(target_value #>> '{}');

    if scalar_text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
       and scalar_text !~
         '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$' then
      raise exception 'canonical_json_timestamp_requires_milliseconds_utc'
        using errcode = '22023';
    end if;

    if (
      scalar_text ~
        '^-?(0|[1-9][0-9]*)\.[0-9]+$'
      and scalar_text ~ '0$'
    )
    or scalar_text ~
      '^-?(0|[1-9][0-9]*)(\.[0-9]+)?[eE][+-]?[0-9]+$' then
      raise exception 'canonical_json_decimal_not_minimal'
        using errcode = '22023';
    end if;
    return;
  end if;

  if value_type = 'array' then
    for nested_value in
      select element.value
      from pg_catalog.jsonb_array_elements(target_value) element(value)
    loop
      perform private.validate_canonical_json_v1_payload(nested_value);
    end loop;
    return;
  end if;

  if value_type = 'object' then
    for nested_value in
      select entry.value
      from pg_catalog.jsonb_each(target_value) entry
    loop
      perform private.validate_canonical_json_v1_payload(nested_value);
    end loop;
    return;
  end if;
end;
$$;

create or replace function private.forja_canonical_json_v1_bytes(
  target_payload jsonb,
  target_version text default 'forja.canonical-json.v1'
)
returns bytea
language plpgsql
stable
strict
set search_path = ''
as $$
begin
  if target_version <> 'forja.canonical-json.v1' then
    raise exception 'unsupported_canonicalization_version'
      using errcode = '22023';
  end if;

  perform private.validate_canonical_json_v1_payload(target_payload);

  return pg_catalog.convert_to(
    private.forja_canonical_json_v1_text(target_payload),
    'UTF8'
  );
end;
$$;

create or replace function private.prepare_consultation_canonical_record_v43()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  consultation_record public.professional_consultations;
  snapshot_consultation_id uuid;
begin
  select consultation.*
  into consultation_record
  from public.professional_consultations consultation
  where consultation.id = new.consultation_id;

  if not found
     or consultation_record.status <> 'finalized'
     or consultation_record.finalized_at is null then
    raise exception 'consultation_must_be_finalized'
      using errcode = '23514';
  end if;

  if tg_table_name = 'consultation_final_snapshots' then
    if new.finalized_by_user_id <> consultation_record.author_user_id then
      raise exception 'snapshot_finalizer_must_be_author'
        using errcode = '23514';
    end if;
  elsif tg_table_name = 'consultation_addenda' then
    select snapshot.consultation_id
    into snapshot_consultation_id
    from public.consultation_final_snapshots snapshot
    where snapshot.id = new.final_snapshot_id;

    if snapshot_consultation_id is distinct from new.consultation_id
       or new.author_user_id <> consultation_record.author_user_id then
      raise exception 'addendum_history_mismatch'
        using errcode = '23514';
    end if;
  end if;

  new.canonicalization_version := 'forja.canonical-json.v1';
  new.canonical_bytes :=
    private.forja_canonical_json_v1_bytes(
      new.canonical_payload,
      new.canonicalization_version
    );
  new.payload_sha256 :=
    extensions.digest(new.canonical_bytes, 'sha256');

  return new;
end;
$$;

create or replace function private.reject_immutable_consultation_entity_v43()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'immutable_consultation_entity'
    using errcode = '55000';
end;
$$;

create or replace function private.protect_finalized_consultation_provenance_v43()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if
    old.status = 'finalized'
    or exists (
      select 1
      from public.consultation_final_snapshots snapshot
      where snapshot.consultation_id = old.id
    )
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

create or replace function private.protect_finalized_consultation_items_v43()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  source_consultation_id uuid;
  target_consultation_id uuid;
begin
  if tg_op <> 'INSERT' then
    source_consultation_id := old.consultation_id;
  end if;

  if tg_op <> 'DELETE' then
    target_consultation_id := new.consultation_id;
  end if;

  if exists (
    select 1
    from public.professional_consultations consultation
    where (
        consultation.id = source_consultation_id
        or consultation.id = target_consultation_id
      )
      and (
        consultation.status = 'finalized'
        or exists (
          select 1
          from public.consultation_final_snapshots snapshot
          where snapshot.consultation_id = consultation.id
        )
      )
  ) then
    raise exception 'finalized_consultation_items_are_immutable'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create or replace function private.enforce_consultation_schedule_revision_v43()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  schedule_changed boolean;
  expected_offset_minutes integer;
begin
  if new.scheduled_time_zone is not null
     and not exists (
       select 1
       from pg_catalog.pg_timezone_names timezone_info
       where timezone_info.name = new.scheduled_time_zone
     ) then
    raise exception 'invalid_consultation_time_zone'
      using errcode = '23514';
  end if;

  if new.scheduled_start_at is not null then
    expected_offset_minutes := pg_catalog.round(
      extract(
        epoch from (
          new.scheduled_start_at at time zone new.scheduled_time_zone
          - new.scheduled_start_at at time zone 'UTC'
        )
      ) / 60
    )::integer;

    if new.scheduled_utc_offset_minutes <> expected_offset_minutes then
      raise exception 'consultation_schedule_offset_mismatch'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' then
    if new.scheduled_start_at is not null
       and new.schedule_revision <> 1 then
      raise exception 'initial_schedule_revision_must_be_one'
        using errcode = '23514';
    end if;
    return new;
  end if;

  schedule_changed :=
    row(
      new.scheduled_start_at,
      new.scheduled_time_zone,
      new.scheduled_utc_offset_minutes
    )
    is distinct from
    row(
      old.scheduled_start_at,
      old.scheduled_time_zone,
      old.scheduled_utc_offset_minutes
    );

  if schedule_changed
     and new.schedule_revision <> old.schedule_revision + 1 then
    raise exception 'schedule_revision_must_increment'
      using errcode = '23514';
  end if;

  if not schedule_changed
     and new.schedule_revision <> old.schedule_revision then
    raise exception 'schedule_revision_without_schedule_change'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function private.validate_consultation_predecessor_v43()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  predecessor_record public.professional_consultations;
begin
  if new.predecessor_consultation_id is null then
    return new;
  end if;

  if new.consultation_kind <> 'reassessment'
     or new.predecessor_consultation_id = new.id then
    raise exception 'invalid_consultation_predecessor'
      using errcode = '23514';
  end if;

  select consultation.*
  into predecessor_record
  from public.professional_consultations consultation
  where consultation.id = new.predecessor_consultation_id;

  if not found
     or predecessor_record.subject_id <> new.subject_id
     or predecessor_record.status <> 'finalized' then
    raise exception 'invalid_consultation_predecessor'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function public.resolve_account_consultation_subject_v43(
  target_relationship_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid;
  relationship_record public.professional_student_relationships;
  resolved_subject_id uuid;
begin
  caller_user_id := auth.uid();

  if caller_user_id is null then
    raise exception 'authentication_required'
      using errcode = '42501';
  end if;

  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = target_relationship_id
    and relationship.professional_user_id = caller_user_id
    and relationship.status = 'active'
    and relationship.professional_type in ('trainer', 'nutritionist');

  if not found then
    raise exception 'consultation_relationship_not_authorized'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.user_identity_details identity
    where identity.user_id = relationship_record.student_user_id
      and identity.age_status = 'adult'
      and identity.birth_date
        <= (current_date - interval '18 years')::date
  ) then
    raise exception 'consultation_subject_requires_adult_account'
      using errcode = '42501';
  end if;

  insert into public.consultation_subjects (
    subject_kind,
    account_user_id,
    created_by_user_id
  )
  values (
    'account',
    relationship_record.student_user_id,
    caller_user_id
  )
  on conflict (account_user_id) do nothing
  returning id into resolved_subject_id;

  if resolved_subject_id is null then
    select subject.id
    into resolved_subject_id
    from public.consultation_subjects subject
    where subject.account_user_id = relationship_record.student_user_id;
  end if;

  return resolved_subject_id;
end;
$$;

create trigger prepare_consultation_final_snapshot_v43
before insert on public.consultation_final_snapshots
for each row
execute function private.prepare_consultation_canonical_record_v43();

create trigger prepare_consultation_addendum_v43
before insert on public.consultation_addenda
for each row
execute function private.prepare_consultation_canonical_record_v43();

create trigger reject_consultation_final_snapshot_mutation_v43
before update or delete on public.consultation_final_snapshots
for each row
execute function private.reject_immutable_consultation_entity_v43();

create trigger reject_consultation_addendum_mutation_v43
before update or delete on public.consultation_addenda
for each row
execute function private.reject_immutable_consultation_entity_v43();

create trigger reject_consultation_discard_tombstone_mutation_v43
before update or delete on public.consultation_discard_tombstones
for each row
execute function private.reject_immutable_consultation_entity_v43();

create trigger reject_consultation_event_mutation_v43
before update or delete on public.consultation_events
for each row
execute function private.reject_immutable_consultation_entity_v43();

create trigger protect_finalized_consultation_items_v43
before insert or update or delete on public.consultation_items
for each row
execute function private.protect_finalized_consultation_items_v43();

create trigger protect_finalized_consultation_provenance_v43
before update or delete on public.professional_consultations
for each row
execute function private.protect_finalized_consultation_provenance_v43();

create trigger enforce_consultation_schedule_revision_v43
before insert or update of
  scheduled_start_at,
  scheduled_time_zone,
  scheduled_utc_offset_minutes,
  schedule_revision
on public.professional_consultations
for each row
execute function private.enforce_consultation_schedule_revision_v43();

create constraint trigger validate_consultation_predecessor_v43
after insert or update of
  subject_id,
  consultation_kind,
  predecessor_consultation_id
on public.professional_consultations
deferrable initially immediate
for each row
execute function private.validate_consultation_predecessor_v43();

alter table public.consultation_subjects enable row level security;
alter table public.consultation_subjects force row level security;
alter table public.professional_consultations enable row level security;
alter table public.professional_consultations force row level security;
alter table public.consultation_items enable row level security;
alter table public.consultation_items force row level security;
alter table public.consultation_final_snapshots enable row level security;
alter table public.consultation_final_snapshots force row level security;
alter table public.consultation_addenda enable row level security;
alter table public.consultation_addenda force row level security;
alter table public.consultation_discard_tombstones enable row level security;
alter table public.consultation_discard_tombstones force row level security;
alter table public.consultation_events enable row level security;
alter table public.consultation_events force row level security;

revoke all on table public.consultation_subjects
  from public, anon, authenticated;
revoke all on table public.professional_consultations
  from public, anon, authenticated;
revoke all on table public.consultation_items
  from public, anon, authenticated;
revoke all on table public.consultation_final_snapshots
  from public, anon, authenticated;
revoke all on table public.consultation_addenda
  from public, anon, authenticated;
revoke all on table public.consultation_discard_tombstones
  from public, anon, authenticated;
revoke all on table public.consultation_events
  from public, anon, authenticated;

revoke all on function
  public.resolve_account_consultation_subject_v43(uuid)
  from public, anon, authenticated;
grant execute on function
  public.resolve_account_consultation_subject_v43(uuid)
  to authenticated;

revoke all privileges on all functions in schema private
  from public, anon, authenticated;

commit;
