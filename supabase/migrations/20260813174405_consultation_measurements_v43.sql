begin;

create table public.consultation_measurement_definitions (
  id uuid default gen_random_uuid() not null,
  definition_key text not null,
  definition_version integer not null,
  display_name text not null,
  canonical_unit text not null,
  accepted_input_units text[] not null,
  anatomical_point text not null,
  position text not null,
  instructions text not null,
  protocol_id text not null,
  protocol_version text not null,
  allowed_readings_min smallint not null,
  allowed_readings_max smallint not null,
  reducer text not null,
  formula_eligible boolean default false not null,
  valid_range jsonb default '{}'::jsonb not null,
  warning_rule jsonb default '{}'::jsonb not null,
  source_reference text not null,
  is_active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  constraint consultation_measurement_definitions_pkey primary key (id),
  constraint consultation_measurement_definitions_key_version_key
    unique (definition_key, definition_version),
  constraint consultation_measurement_definitions_key_check
    check (
      char_length(definition_key) between 1 and 160
      and definition_key ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
    ),
  constraint consultation_measurement_definitions_version_check
    check (definition_version >= 1),
  constraint consultation_measurement_definitions_display_name_check
    check (
      char_length(btrim(display_name)) between 1 and 160
      and display_name !~ '[[:cntrl:]]'
    ),
  constraint consultation_measurement_definitions_canonical_unit_check
    check (canonical_unit in ('mm', 'cm', 'm', 'g', 'kg', '%')),
  constraint consultation_measurement_definitions_input_units_check
    check (
      cardinality(accepted_input_units) between 1 and 8
      and canonical_unit = any(accepted_input_units)
      and accepted_input_units <@ array['mm','cm','m','g','kg','%']::text[]
    ),
  constraint consultation_measurement_definitions_anatomical_point_check
    check (
      char_length(btrim(anatomical_point)) between 1 and 240
      and anatomical_point !~ '[[:cntrl:]]'
    ),
  constraint consultation_measurement_definitions_position_check
    check (
      char_length(btrim(position)) between 1 and 120
      and position !~ '[[:cntrl:]]'
    ),
  constraint consultation_measurement_definitions_instructions_check
    check (
      char_length(btrim(instructions)) between 1 and 2000
      and instructions !~ '[[:cntrl:]]'
    ),
  constraint consultation_measurement_definitions_protocol_check
    check (
      char_length(protocol_id) between 1 and 160
      and protocol_id ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
      and char_length(protocol_version) between 1 and 80
      and protocol_version !~ '[[:cntrl:]]'
    ),
  constraint consultation_measurement_definitions_reading_count_check
    check (
      allowed_readings_min between 1 and 3
      and allowed_readings_max between allowed_readings_min and 3
    ),
  constraint consultation_measurement_definitions_reducer_check
    check (reducer in ('mean', 'median')),
  constraint consultation_measurement_definitions_rules_check
    check (
      jsonb_typeof(valid_range) = 'object'
      and jsonb_typeof(warning_rule) = 'object'
      and pg_column_size(valid_range) <= 2048
      and pg_column_size(warning_rule) <= 2048
    ),
  constraint consultation_measurement_definitions_source_check
    check (
      char_length(btrim(source_reference)) between 1 and 500
      and source_reference !~ '[[:cntrl:]]'
    )
);

create table public.consultation_measurement_sessions (
  id uuid default gen_random_uuid() not null,
  consultation_id uuid not null,
  observed_at timestamp with time zone not null,
  operator_user_id uuid not null,
  protocol_id text not null,
  protocol_version text not null,
  conditions jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint consultation_measurement_sessions_pkey primary key (id),
  constraint consultation_measurement_sessions_consultation_id_fkey
    foreign key (consultation_id)
    references public.professional_consultations(id)
    on update restrict
    on delete cascade,
  constraint consultation_measurement_sessions_operator_user_id_fkey
    foreign key (operator_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_measurement_sessions_protocol_check
    check (
      char_length(protocol_id) between 1 and 160
      and protocol_id ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
      and char_length(protocol_version) between 1 and 80
      and protocol_version !~ '[[:cntrl:]]'
    ),
  constraint consultation_measurement_sessions_conditions_check
    check (
      jsonb_typeof(conditions) = 'object'
      and pg_column_size(conditions) <= 8192
    )
);

create table public.consultation_measurements (
  id uuid not null,
  consultation_id uuid not null,
  session_id uuid not null,
  definition_id uuid,
  measurement_kind text not null,
  definition_key text,
  definition_version integer,
  custom_label text,
  canonical_unit text not null,
  protocol_id text not null,
  protocol_version text not null,
  observation_status text not null,
  reducer text not null,
  formula_eligible boolean default false not null,
  calculation_eligible boolean default false not null,
  aggregate_value numeric,
  aggregate_display_value numeric,
  display_scale smallint default 2 not null,
  warning_code text,
  warning_accepted boolean default false not null,
  warning_justification text,
  correction_count integer default 0 not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint consultation_measurements_pkey primary key (id),
  constraint consultation_measurements_consultation_id_fkey
    foreign key (consultation_id)
    references public.professional_consultations(id)
    on update restrict
    on delete cascade,
  constraint consultation_measurements_session_id_fkey
    foreign key (session_id)
    references public.consultation_measurement_sessions(id)
    on update restrict
    on delete cascade,
  constraint consultation_measurements_definition_id_fkey
    foreign key (definition_id)
    references public.consultation_measurement_definitions(id)
    on update restrict
    on delete restrict,
  constraint consultation_measurements_kind_check
    check (measurement_kind in ('standard', 'custom')),
  constraint consultation_measurements_definition_shape_check
    check (
      (
        measurement_kind = 'standard'
        and definition_id is not null
        and definition_key is not null
        and definition_version is not null
        and custom_label is null
      )
      or (
        measurement_kind = 'custom'
        and definition_id is null
        and definition_key is null
        and definition_version is null
        and custom_label is not null
        and formula_eligible = false
        and calculation_eligible = false
      )
    ),
  constraint consultation_measurements_custom_label_check
    check (
      custom_label is null
      or (
        char_length(btrim(custom_label)) between 1 and 160
        and custom_label !~ '[[:cntrl:]]'
      )
    ),
  constraint consultation_measurements_unit_check
    check (canonical_unit in ('mm', 'cm', 'm', 'g', 'kg', '%')),
  constraint consultation_measurements_protocol_check
    check (
      char_length(protocol_id) between 1 and 160
      and protocol_id ~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
      and char_length(protocol_version) between 1 and 80
      and protocol_version !~ '[[:cntrl:]]'
    ),
  constraint consultation_measurements_status_check
    check (
      observation_status in (
        'not_attempted', 'client_declined', 'could_not_obtain',
        'instrument_limit', 'recorded', 'invalid'
      )
    ),
  constraint consultation_measurements_reducer_check
    check (reducer in ('mean', 'median')),
  constraint consultation_measurements_aggregate_shape_check
    check (
      (
        observation_status = 'recorded'
        and aggregate_value is not null
        and aggregate_display_value is not null
      )
      or (
        observation_status <> 'recorded'
        and aggregate_value is null
        and aggregate_display_value is null
        and calculation_eligible = false
      )
    ),
  constraint consultation_measurements_scale_check
    check (display_scale between 0 and 12),
  constraint consultation_measurements_warning_check
    check (
      (warning_code is null and not warning_accepted and warning_justification is null)
      or (
        warning_code is not null
        and char_length(warning_code) between 1 and 80
        and warning_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'
        and (
          (not warning_accepted and warning_justification is null)
          or (
            warning_accepted
            and char_length(btrim(warning_justification)) between 1 and 1000
            and warning_justification !~ '[[:cntrl:]]'
          )
        )
      )
    ),
  constraint consultation_measurements_correction_count_check
    check (correction_count >= 0)
);

create table public.consultation_measurement_readings (
  id uuid default gen_random_uuid() not null,
  measurement_id uuid not null,
  ordinal smallint not null,
  raw_value numeric not null,
  raw_unit text not null,
  normalized_value numeric not null,
  canonical_unit text not null,
  created_at timestamp with time zone default now() not null,
  constraint consultation_measurement_readings_pkey primary key (id),
  constraint consultation_measurement_readings_measurement_ordinal_key
    unique (measurement_id, ordinal),
  constraint consultation_measurement_readings_measurement_id_fkey
    foreign key (measurement_id)
    references public.consultation_measurements(id)
    on update restrict
    on delete cascade,
  constraint consultation_measurement_readings_ordinal_check
    check (ordinal between 1 and 3),
  constraint consultation_measurement_readings_unit_check
    check (
      raw_unit in ('mm', 'cm', 'm', 'g', 'kg', '%')
      and canonical_unit in ('mm', 'cm', 'm', 'g', 'kg', '%')
    ),
  constraint consultation_measurement_readings_numeric_bounds_check
    check (
      raw_value between -1000000000000::numeric and 1000000000000::numeric
      and normalized_value between -1000000000000::numeric and 1000000000000::numeric
    )
);

create table public.consultation_device_observations (
  id uuid not null,
  consultation_id uuid not null,
  observed_at timestamp with time zone not null,
  operator_user_id uuid not null,
  manufacturer text not null,
  model text not null,
  mode text not null,
  frequency text,
  electrode_layout text,
  device_settings jsonb default '{}'::jsonb not null,
  contemporaneous_mass_value numeric,
  contemporaneous_mass_unit text,
  conditions jsonb default '{}'::jsonb not null,
  original_metrics jsonb not null,
  result_kind text default 'external_device_estimate' not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint consultation_device_observations_pkey primary key (id),
  constraint consultation_device_observations_consultation_id_fkey
    foreign key (consultation_id)
    references public.professional_consultations(id)
    on update restrict
    on delete cascade,
  constraint consultation_device_observations_operator_user_id_fkey
    foreign key (operator_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_device_observations_device_text_check
    check (
      char_length(btrim(manufacturer)) between 1 and 160
      and manufacturer !~ '[[:cntrl:]]'
      and char_length(btrim(model)) between 1 and 160
      and model !~ '[[:cntrl:]]'
      and char_length(btrim(mode)) between 1 and 120
      and mode !~ '[[:cntrl:]]'
      and (frequency is null or (
        char_length(btrim(frequency)) between 1 and 80
        and frequency !~ '[[:cntrl:]]'
      ))
      and (electrode_layout is null or (
        char_length(btrim(electrode_layout)) between 1 and 240
        and electrode_layout !~ '[[:cntrl:]]'
      ))
    ),
  constraint consultation_device_observations_json_check
    check (
      jsonb_typeof(device_settings) = 'object'
      and jsonb_typeof(conditions) = 'object'
      and jsonb_typeof(original_metrics) = 'array'
      and jsonb_array_length(original_metrics) between 1 and 50
      and pg_column_size(device_settings) <= 8192
      and pg_column_size(conditions) <= 8192
      and pg_column_size(original_metrics) <= 32768
    ),
  constraint consultation_device_observations_mass_check
    check (
      (contemporaneous_mass_value is null and contemporaneous_mass_unit is null)
      or (
        contemporaneous_mass_value between 0::numeric and 1000::numeric
        and contemporaneous_mass_unit in ('g', 'kg')
      )
    ),
  constraint consultation_device_observations_result_kind_check
    check (result_kind = 'external_device_estimate')
);

create index consultation_measurement_definitions_active_key_idx
  on public.consultation_measurement_definitions
  (definition_key, definition_version desc)
  where is_active;
create index consultation_measurement_sessions_consultation_observed_idx
  on public.consultation_measurement_sessions (consultation_id, observed_at, id);
create index consultation_measurements_consultation_definition_idx
  on public.consultation_measurements
  (consultation_id, definition_key, definition_version)
  where measurement_kind = 'standard';
create index consultation_measurements_session_idx
  on public.consultation_measurements (session_id, id);
create index consultation_measurement_readings_measurement_idx
  on public.consultation_measurement_readings (measurement_id, ordinal);
create index consultation_device_observations_consultation_observed_idx
  on public.consultation_device_observations (consultation_id, observed_at, id);

create or replace function private.consultation_decimal_text_v43(
  target_value numeric
)
returns text
language plpgsql
immutable
strict
security definer
set search_path = ''
as $$
declare
  result_text text;
begin
  if target_value::text in ('NaN', 'Infinity', '-Infinity') then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end if;

  result_text := target_value::text;
  if pg_catalog.position('.' in result_text) > 0 then
    result_text := pg_catalog.regexp_replace(result_text, '0+$', '');
    result_text := pg_catalog.regexp_replace(result_text, '\.$', '');
  end if;
  if result_text in ('-0', '') then
    return '0';
  end if;
  return result_text;
end;
$$;

create or replace function private.reject_consultation_measurement_definition_mutation_v43()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'consultation_measurement_definitions_are_append_only'
    using errcode = '55000';
end;
$$;

create or replace function private.protect_finalized_consultation_measurements_v43()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_consultation_id uuid;
  target_consultation_id uuid;
begin
  if tg_table_name = 'consultation_measurement_sessions' then
    if tg_op <> 'INSERT' then source_consultation_id := old.consultation_id; end if;
    if tg_op <> 'DELETE' then target_consultation_id := new.consultation_id; end if;
  elsif tg_table_name = 'consultation_measurements' then
    if tg_op <> 'INSERT' then source_consultation_id := old.consultation_id; end if;
    if tg_op <> 'DELETE' then target_consultation_id := new.consultation_id; end if;
  elsif tg_table_name = 'consultation_measurement_readings' then
    if tg_op <> 'INSERT' then
      select measurement.consultation_id
      into source_consultation_id
      from public.consultation_measurements measurement
      where measurement.id = old.measurement_id;
    end if;
    if tg_op <> 'DELETE' then
      select measurement.consultation_id
      into target_consultation_id
      from public.consultation_measurements measurement
      where measurement.id = new.measurement_id;
    end if;
  elsif tg_table_name = 'consultation_device_observations' then
    if tg_op <> 'INSERT' then source_consultation_id := old.consultation_id; end if;
    if tg_op <> 'DELETE' then target_consultation_id := new.consultation_id; end if;
  end if;

  if exists (
    select 1
    from public.professional_consultations consultation
    where consultation.id in (source_consultation_id, target_consultation_id)
      and (
        consultation.status = 'finalized'
        or exists (
          select 1
          from public.consultation_final_snapshots snapshot
          where snapshot.consultation_id = consultation.id
        )
      )
  ) then
    raise exception 'finalized_consultation_measurements_are_immutable'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
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

  if exists (
    select 1
    from public.consultation_measurements measurement
    where measurement.consultation_id = consultation_record.id
      and measurement.warning_code is not null
      and (
        not measurement.warning_accepted
        or measurement.warning_justification is null
      )
  ) then
    raise exception 'consultation_measurement_justification_required'
      using errcode = '55000';
  end if;

  select pg_catalog.jsonb_build_object(
    'items',
    coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'itemKey', item.item_key,
            'itemKind', item.item_kind,
            'schemaVersion', item.schema_version,
            'value', item.value_payload
          ) order by item.item_key
        )
        from public.consultation_items item
        where item.consultation_id = consultation_record.id
      ),
      '[]'::jsonb
    ),
    'measurements',
    coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_strip_nulls(
            pg_catalog.jsonb_build_object(
              'measurementId', measurement.id,
              'measurementKind', measurement.measurement_kind,
              'definitionKey', measurement.definition_key,
              'definitionVersion', measurement.definition_version,
              'customLabel', measurement.custom_label,
              'canonicalUnit', measurement.canonical_unit,
              'protocolId', measurement.protocol_id,
              'protocolVersion', measurement.protocol_version,
              'observationStatus', measurement.observation_status,
              'reducer', measurement.reducer,
              'formulaEligible', measurement.formula_eligible,
              'calculationEligible', measurement.calculation_eligible,
              'aggregateValue', case when measurement.aggregate_value is null then null
                else private.consultation_decimal_text_v43(measurement.aggregate_value) end,
              'displayValue', case when measurement.aggregate_display_value is null then null
                else private.consultation_decimal_text_v43(measurement.aggregate_display_value) end,
              'warningCode', measurement.warning_code,
              'warningAccepted', case when measurement.warning_code is null then null
                else measurement.warning_accepted end,
              'warningJustification', measurement.warning_justification,
              'session', pg_catalog.jsonb_build_object(
                'observedAt', pg_catalog.to_char(
                  session.observed_at at time zone 'UTC',
                  'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
                ),
                'operatorUserId', session.operator_user_id,
                'conditions', session.conditions
              ),
              'readings', coalesce(
                (
                  select pg_catalog.jsonb_agg(
                    pg_catalog.jsonb_build_object(
                      'ordinal', reading.ordinal,
                      'rawValue', private.consultation_decimal_text_v43(reading.raw_value),
                      'rawUnit', reading.raw_unit,
                      'normalizedValue', private.consultation_decimal_text_v43(reading.normalized_value),
                      'canonicalUnit', reading.canonical_unit
                    ) order by reading.ordinal
                  )
                  from public.consultation_measurement_readings reading
                  where reading.measurement_id = measurement.id
                ),
                '[]'::jsonb
              )
            )
          ) order by session.observed_at, measurement.id
        )
        from public.consultation_measurements measurement
        join public.consultation_measurement_sessions session
          on session.id = measurement.session_id
        where measurement.consultation_id = consultation_record.id
      ),
      '[]'::jsonb
    ),
    'deviceObservations',
    coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_strip_nulls(
            pg_catalog.jsonb_build_object(
              'observationId', observation.id,
              'observedAt', pg_catalog.to_char(
                observation.observed_at at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
              ),
              'operatorUserId', observation.operator_user_id,
              'manufacturer', observation.manufacturer,
              'model', observation.model,
              'mode', observation.mode,
              'frequency', observation.frequency,
              'electrodeLayout', observation.electrode_layout,
              'deviceSettings', observation.device_settings,
              'contemporaneousMass', case
                when observation.contemporaneous_mass_value is null then null
                else pg_catalog.jsonb_build_object(
                  'value', private.consultation_decimal_text_v43(
                    observation.contemporaneous_mass_value
                  ),
                  'unit', observation.contemporaneous_mass_unit
                )
              end,
              'conditions', observation.conditions,
              'originalMetrics', observation.original_metrics,
              'resultKind', observation.result_kind
            )
          ) order by observation.observed_at, observation.id
        )
        from public.consultation_device_observations observation
        where observation.consultation_id = consultation_record.id
      ),
      '[]'::jsonb
    )
  )
  into snapshot_payload;

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

create or replace function public.save_my_consultation_device_observation_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint,
  target_correlation_id uuid,
  target_payload jsonb
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
  observation_id uuid;
  parsed_observed_at timestamp with time zone;
  parsed_manufacturer text;
  parsed_model text;
  parsed_mode text;
  parsed_frequency text;
  parsed_electrode_layout text;
  parsed_device_settings jsonb;
  parsed_conditions jsonb;
  parsed_metrics jsonb;
  parsed_mass_value numeric;
  parsed_mass_unit text;
  metric jsonb;
  metric_value text;
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
     or target_payload is null
     or pg_catalog.jsonb_typeof(target_payload) <> 'object'
     or pg_catalog.pg_column_size(target_payload) > 65536
     or private.consultation_jsonb_depth_v43(target_payload) > 16 then
    raise exception 'consultation_device_observation_validation_failed'
      using errcode = '22023';
  end if;

  begin
    observation_id := (target_payload ->> 'observationId')::uuid;
  exception when others then
    raise exception 'consultation_device_observation_validation_failed'
      using errcode = '22023';
  end;

  if target_payload ->> 'observedAt' !~
       '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$' then
    raise exception 'consultation_device_observation_validation_failed'
      using errcode = '22023';
  end if;

  parsed_observed_at := (target_payload ->> 'observedAt')::timestamp with time zone;
  parsed_manufacturer := nullif(btrim(target_payload ->> 'manufacturer'), '');
  parsed_model := nullif(btrim(target_payload ->> 'model'), '');
  parsed_mode := nullif(btrim(target_payload ->> 'mode'), '');
  parsed_frequency := nullif(btrim(target_payload ->> 'frequency'), '');
  parsed_electrode_layout := nullif(btrim(target_payload ->> 'electrodeLayout'), '');
  parsed_device_settings := coalesce(target_payload -> 'deviceSettings', '{}'::jsonb);
  parsed_conditions := coalesce(target_payload -> 'conditions', '{}'::jsonb);
  parsed_metrics := target_payload -> 'metrics';

  if observation_id is null
     or parsed_manufacturer is null
     or char_length(parsed_manufacturer) > 160
     or parsed_manufacturer ~ '[[:cntrl:]]'
     or parsed_model is null
     or char_length(parsed_model) > 160
     or parsed_model ~ '[[:cntrl:]]'
     or parsed_mode is null
     or char_length(parsed_mode) > 120
     or parsed_mode ~ '[[:cntrl:]]'
     or (parsed_frequency is not null and (
       char_length(parsed_frequency) > 80 or parsed_frequency ~ '[[:cntrl:]]'
     ))
     or (parsed_electrode_layout is not null and (
       char_length(parsed_electrode_layout) > 240
       or parsed_electrode_layout ~ '[[:cntrl:]]'
     ))
     or pg_catalog.jsonb_typeof(parsed_device_settings) <> 'object'
     or pg_catalog.jsonb_typeof(parsed_conditions) <> 'object'
     or pg_catalog.jsonb_typeof(parsed_metrics) <> 'array'
     or pg_catalog.jsonb_array_length(parsed_metrics) not between 1 and 50
     or pg_catalog.pg_column_size(parsed_device_settings) > 8192
     or pg_catalog.pg_column_size(parsed_conditions) > 8192
     or pg_catalog.pg_column_size(parsed_metrics) > 32768
     or private.consultation_jsonb_depth_v43(parsed_device_settings) > 8
     or private.consultation_jsonb_depth_v43(parsed_conditions) > 8
     or private.consultation_jsonb_depth_v43(parsed_metrics) > 8 then
    raise exception 'consultation_device_observation_validation_failed'
      using errcode = '22023';
  end if;

  perform private.validate_canonical_json_v1_payload(parsed_device_settings);
  perform private.validate_canonical_json_v1_payload(parsed_conditions);

  for metric in
    select entry.value
    from pg_catalog.jsonb_array_elements(parsed_metrics) entry(value)
  loop
    metric_value := metric ->> 'value';
    if pg_catalog.jsonb_typeof(metric) <> 'object'
       or metric ->> 'key' is null
       or char_length(metric ->> 'key') not between 1 and 120
       or metric ->> 'key' !~ '^[a-z0-9]+(?:[._-][a-z0-9]+)*$'
       or metric_value is null
       or char_length(metric_value) > 40
       or metric_value !~ '^-?(0|[1-9][0-9]*)(\.[0-9]{1,12})?$'
       or metric ->> 'unit' is null
       or char_length(metric ->> 'unit') not between 1 and 32
       or metric ->> 'unit' not in (
         '%', 'g', 'kg', 'mm', 'cm', 'm', 'ohm', 'kOhm', 'L', 'kcal', 'years'
       ) then
      raise exception 'consultation_device_observation_validation_failed'
        using errcode = '22023';
    end if;
  end loop;
  perform private.validate_canonical_json_v1_payload(parsed_metrics);

  if target_payload ? 'contemporaneousMass' then
    metric_value := target_payload #>> '{contemporaneousMass,value}';
    parsed_mass_unit := target_payload #>> '{contemporaneousMass,unit}';
    if metric_value is null
       or metric_value !~ '^(0|[1-9][0-9]*)(\.[0-9]{1,12})?$'
       or parsed_mass_unit not in ('g', 'kg') then
      raise exception 'consultation_device_observation_validation_failed'
        using errcode = '22023';
    end if;
    parsed_mass_value := metric_value::numeric;
    if parsed_mass_value <= 0 or parsed_mass_value > 1000 then
      raise exception 'consultation_device_observation_validation_failed'
        using errcode = '22023';
    end if;
  end if;

  if exists (
    select 1
    from public.consultation_device_observations observation
    where observation.id = observation_id
  ) then
    raise exception 'consultation_device_observation_correction_required'
      using errcode = '22023';
  end if;

  insert into public.consultation_device_observations (
    id, consultation_id, observed_at, operator_user_id,
    manufacturer, model, mode, frequency, electrode_layout,
    device_settings, contemporaneous_mass_value,
    contemporaneous_mass_unit, conditions, original_metrics
  ) values (
    observation_id, consultation_record.id, parsed_observed_at, caller_user_id,
    parsed_manufacturer, parsed_model, parsed_mode, parsed_frequency,
    parsed_electrode_layout, parsed_device_settings, parsed_mass_value,
    parsed_mass_unit, parsed_conditions, parsed_metrics
  );

  next_revision := consultation_record.draft_revision + 1;
  update public.professional_consultations consultation
  set draft_revision = next_revision,
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  insert into public.consultation_save_receipts (
    author_user_id, consultation_id, correlation_id, resulting_revision
  ) values (
    caller_user_id, consultation_record.id, target_correlation_id, next_revision
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    caller_user_id,
    consultation_record.relationship_id,
    'device_observation_saved'
  );

  return pg_catalog.jsonb_build_object(
    'consultationId', consultation_record.id,
    'observationId', observation_id,
    'draftRevision', next_revision,
    'resultKind', 'external_device_estimate',
    'idempotent', false
  );
end;
$$;

create or replace function private.reduce_consultation_measurement_v43(
  target_values numeric[],
  target_reducer text,
  target_display_scale smallint
)
returns jsonb
language plpgsql
immutable
strict
security definer
set search_path = ''
as $$
declare
  value_count integer := cardinality(target_values);
  aggregate_value numeric;
begin
  if value_count not between 1 and 3
     or target_reducer not in ('mean', 'median')
     or target_display_scale not between 0 and 12
     or exists (
       select 1
       from unnest(target_values) reading(value)
       where reading.value is null
          or reading.value::text in ('NaN', 'Infinity', '-Infinity')
     ) then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end if;

  if target_reducer = 'mean' or value_count = 2 then
    select sum(reading.value) / value_count::numeric
    into aggregate_value
    from unnest(target_values) reading(value);
  else
    select reading.value
    into aggregate_value
    from unnest(target_values) reading(value)
    order by reading.value
    offset ((value_count - 1) / 2)
    limit 1;
  end if;

  return pg_catalog.jsonb_build_object(
    'unroundedValue', private.consultation_decimal_text_v43(aggregate_value),
    'displayValue', private.consultation_decimal_text_v43(
      pg_catalog.round(aggregate_value, target_display_scale)
    )
  );
end;
$$;

create or replace function private.normalize_consultation_measurement_unit_v43(
  target_value numeric,
  target_input_unit text,
  target_canonical_unit text,
  target_scale smallint
)
returns jsonb
language plpgsql
immutable
strict
security definer
set search_path = ''
as $$
declare
  normalized_value numeric;
begin
  if target_value::text in ('NaN', 'Infinity', '-Infinity')
     or target_scale not between 0 and 12
     or target_input_unit not in ('mm', 'cm', 'm', 'g', 'kg', '%')
     or target_canonical_unit not in ('mm', 'cm', 'm', 'g', 'kg', '%') then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end if;

  normalized_value := case
    when target_input_unit = target_canonical_unit then target_value
    when target_input_unit = 'mm' and target_canonical_unit = 'cm' then target_value / 10::numeric
    when target_input_unit = 'cm' and target_canonical_unit = 'mm' then target_value * 10::numeric
    when target_input_unit = 'm' and target_canonical_unit = 'cm' then target_value * 100::numeric
    when target_input_unit = 'cm' and target_canonical_unit = 'm' then target_value / 100::numeric
    when target_input_unit = 'g' and target_canonical_unit = 'kg' then target_value / 1000::numeric
    when target_input_unit = 'kg' and target_canonical_unit = 'g' then target_value * 1000::numeric
    else null
  end;

  if normalized_value is null then
    raise exception 'consultation_measurement_incompatible_unit'
      using errcode = '22023';
  end if;

  normalized_value := pg_catalog.round(normalized_value, target_scale);
  return pg_catalog.jsonb_build_object(
    'canonicalValue', private.consultation_decimal_text_v43(normalized_value),
    'canonicalUnit', target_canonical_unit
  );
end;
$$;

create or replace function private.consultation_measurements_are_comparable_v43(
  source_measurement_id uuid,
  target_measurement_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select
        source.measurement_kind = 'standard'
        and target.measurement_kind = 'standard'
        and source.definition_id = target.definition_id
        and source.definition_key = target.definition_key
        and source.definition_version = target.definition_version
        and source.protocol_id = target.protocol_id
        and source.protocol_version = target.protocol_version
        and source.canonical_unit = target.canonical_unit
        and source.observation_status = 'recorded'
        and target.observation_status = 'recorded'
      from public.consultation_measurements source
      join public.consultation_measurements target
        on target.id = target_measurement_id
      where source.id = source_measurement_id
    ),
    false
  );
$$;

create or replace function private.consultation_device_observations_are_comparable_v43(
  source_observation_id uuid,
  target_observation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select
        source.manufacturer = target.manufacturer
        and source.model = target.model
        and source.mode = target.mode
        and source.frequency is not distinct from target.frequency
        and source.electrode_layout is not distinct from target.electrode_layout
      from public.consultation_device_observations source
      join public.consultation_device_observations target
        on target.id = target_observation_id
      where source.id = source_observation_id
    ),
    false
  );
$$;

create or replace function public.save_my_consultation_measurement_v43(
  target_consultation_id uuid,
  target_lease_token text,
  target_lease_version bigint,
  target_expected_draft_revision bigint,
  target_correlation_id uuid,
  target_payload jsonb
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
  definition_record public.consultation_measurement_definitions;
  existing_measurement public.consultation_measurements;
  measurement_id uuid;
  session_id uuid;
  parsed_measurement_kind text;
  parsed_custom_label text;
  parsed_observation_status text;
  parsed_canonical_unit text;
  parsed_input_unit text;
  reducer_name text;
  parsed_protocol_id text;
  parsed_protocol_version text;
  parsed_observed_at timestamp with time zone;
  parsed_conditions jsonb;
  readings jsonb;
  reading jsonb;
  reading_ordinal smallint;
  reading_text text;
  reading_unit text;
  reading_value numeric;
  normalized_result jsonb;
  normalized_value numeric;
  normalized_values numeric[] := array[]::numeric[];
  normalized_readings jsonb := '[]'::jsonb;
  aggregate_result jsonb;
  parsed_aggregate_value numeric;
  parsed_aggregate_display_value numeric;
  parsed_display_scale smallint := 2;
  parsed_formula_eligible boolean := false;
  parsed_calculation_eligible boolean := false;
  parsed_warning_code text;
  parsed_warning_accepted boolean := false;
  parsed_warning_justification text;
  correction_reason text;
  raw_set_changed boolean := false;
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
     or target_payload is null
     or pg_catalog.jsonb_typeof(target_payload) <> 'object'
     or pg_catalog.pg_column_size(target_payload) > 65536
     or private.consultation_jsonb_depth_v43(target_payload) > 16 then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end if;

  begin
    measurement_id := (target_payload ->> 'measurementId')::uuid;
  exception when others then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end;

  parsed_measurement_kind := target_payload ->> 'measurementKind';
  parsed_observation_status := target_payload ->> 'observationStatus';
  correction_reason := nullif(btrim(target_payload ->> 'correctionReason'), '');
  parsed_warning_justification := nullif(btrim(target_payload ->> 'justification'), '');
  parsed_warning_accepted := coalesce((target_payload ->> 'acceptWarning')::boolean, false);
  readings := target_payload -> 'readings';

  if measurement_id is null
     or parsed_measurement_kind not in ('standard', 'custom')
     or parsed_observation_status not in (
       'not_attempted', 'client_declined', 'could_not_obtain',
       'instrument_limit', 'recorded', 'invalid'
     )
     or readings is null
     or pg_catalog.jsonb_typeof(readings) <> 'array'
     or pg_catalog.jsonb_array_length(readings) > 3 then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end if;

  if correction_reason is not null and (
       char_length(correction_reason) > 1000
       or correction_reason ~ '[[:cntrl:]]'
     ) then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end if;

  if parsed_warning_justification is not null and (
       char_length(parsed_warning_justification) > 1000
       or parsed_warning_justification ~ '[[:cntrl:]]'
     ) then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end if;

  if target_payload ? 'displayScale' then
    begin
      parsed_display_scale := (target_payload ->> 'displayScale')::smallint;
    exception when others then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end;
  end if;
  if parsed_display_scale not between 0 and 12 then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end if;

  if parsed_measurement_kind = 'standard' then
    begin
      select definition.*
      into definition_record
      from public.consultation_measurement_definitions definition
      where definition.definition_key = target_payload ->> 'definitionKey'
        and definition.definition_version = (target_payload ->> 'definitionVersion')::integer
        and definition.is_active;
    exception when others then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end;

    if not found then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;

    parsed_canonical_unit := definition_record.canonical_unit;
    reducer_name := coalesce(target_payload ->> 'reducer', definition_record.reducer);
    parsed_formula_eligible := definition_record.formula_eligible;
    parsed_protocol_id := coalesce(
      target_payload #>> '{session,protocolId}',
      definition_record.protocol_id
    );
    parsed_protocol_version := coalesce(
      target_payload #>> '{session,protocolVersion}',
      definition_record.protocol_version
    );

    if reducer_name <> definition_record.reducer
       or parsed_protocol_id <> definition_record.protocol_id
       or parsed_protocol_version <> definition_record.protocol_version then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;
  else
    if coalesce((target_payload ->> 'formulaEligible')::boolean, false) then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;

    parsed_custom_label := nullif(btrim(target_payload ->> 'customLabel'), '');
    parsed_canonical_unit := target_payload ->> 'canonicalUnit';
    reducer_name := target_payload ->> 'reducer';
    parsed_protocol_id := target_payload #>> '{session,protocolId}';
    parsed_protocol_version := target_payload #>> '{session,protocolVersion}';

    if parsed_custom_label is null
       or char_length(parsed_custom_label) > 160
       or parsed_custom_label ~ '[[:cntrl:]]'
       or parsed_canonical_unit not in ('mm', 'cm', 'm', 'g', 'kg', '%')
       or reducer_name not in ('mean', 'median')
       or parsed_protocol_id is null
       or parsed_protocol_version is null then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;
  end if;

  if target_payload #>> '{session,observedAt}' is not null then
    if target_payload #>> '{session,observedAt}' !~
         '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$' then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;
    parsed_observed_at := (target_payload #>> '{session,observedAt}')::timestamp with time zone;
  else
    parsed_observed_at := pg_catalog.statement_timestamp();
  end if;

  parsed_conditions := coalesce(target_payload #> '{session,conditions}', '{}'::jsonb);
  if pg_catalog.jsonb_typeof(parsed_conditions) <> 'object'
     or pg_catalog.pg_column_size(parsed_conditions) > 8192
     or private.consultation_jsonb_depth_v43(parsed_conditions) > 8 then
    raise exception 'consultation_measurement_validation_failed'
      using errcode = '22023';
  end if;
  perform private.validate_canonical_json_v1_payload(parsed_conditions);

  if parsed_observation_status = 'recorded' then
    if pg_catalog.jsonb_array_length(readings) not between
         coalesce(definition_record.allowed_readings_min, 1)
         and coalesce(definition_record.allowed_readings_max, 3) then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;

    parsed_input_unit := target_payload ->> 'inputUnit';
    if parsed_input_unit not in ('mm', 'cm', 'm', 'g', 'kg', '%') then
      raise exception 'consultation_measurement_incompatible_unit'
        using errcode = '22023';
    end if;
    if parsed_measurement_kind = 'standard'
       and not (parsed_input_unit = any(definition_record.accepted_input_units)) then
      raise exception 'consultation_measurement_incompatible_unit'
        using errcode = '22023';
    end if;

    if exists (
      select 1
      from pg_catalog.jsonb_array_elements(readings) entry(value)
      group by entry.value ->> 'ordinal'
      having count(*) > 1
    ) then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;

    for reading in
      select entry.value
      from pg_catalog.jsonb_array_elements(readings) entry(value)
      order by (entry.value ->> 'ordinal')::integer
    loop
      begin
        reading_ordinal := (reading ->> 'ordinal')::smallint;
      exception when others then
        raise exception 'consultation_measurement_validation_failed'
          using errcode = '22023';
      end;
      reading_text := reading ->> 'value';
      reading_unit := reading ->> 'unit';

      if pg_catalog.jsonb_typeof(reading) <> 'object'
         or reading_ordinal not between 1 and 3
         or reading_text is null
         or char_length(reading_text) > 40
         or reading_text !~ '^-?(0|[1-9][0-9]*)(\.[0-9]{1,12})?$'
         or reading_unit <> parsed_input_unit then
        raise exception 'consultation_measurement_validation_failed'
          using errcode = '22023';
      end if;
      if parsed_measurement_kind = 'standard'
         and not (reading_unit = any(definition_record.accepted_input_units)) then
        raise exception 'consultation_measurement_incompatible_unit'
          using errcode = '22023';
      end if;

      reading_value := reading_text::numeric;
      normalized_result := private.normalize_consultation_measurement_unit_v43(
        reading_value, reading_unit, parsed_canonical_unit, 12::smallint
      );
      normalized_value := (normalized_result ->> 'canonicalValue')::numeric;

      if parsed_measurement_kind = 'standard' and (
        (definition_record.valid_range ? 'min'
         and normalized_value < (definition_record.valid_range ->> 'min')::numeric)
        or (definition_record.valid_range ? 'max'
         and normalized_value > (definition_record.valid_range ->> 'max')::numeric)
      ) then
        raise exception 'consultation_measurement_validation_failed'
          using errcode = '22023';
      end if;

      normalized_values := pg_catalog.array_append(normalized_values, normalized_value);
      normalized_readings := normalized_readings || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'ordinal', reading_ordinal,
          'rawValue', private.consultation_decimal_text_v43(reading_value),
          'rawUnit', reading_unit,
          'normalizedValue', private.consultation_decimal_text_v43(normalized_value)
        )
      );
    end loop;

    aggregate_result := private.reduce_consultation_measurement_v43(
      normalized_values, reducer_name, parsed_display_scale
    );
    parsed_aggregate_value := (aggregate_result ->> 'unroundedValue')::numeric;
    parsed_aggregate_display_value := (aggregate_result ->> 'displayValue')::numeric;

    if parsed_measurement_kind = 'standard'
       and definition_record.warning_rule ? 'maxSpread'
       and (
         (select max(value) - min(value) from unnest(normalized_values) valueset(value))
         > (definition_record.warning_rule ->> 'maxSpread')::numeric
       ) then
      parsed_warning_code := 'reading_spread_outlier';
    end if;

    if parsed_warning_accepted and parsed_warning_code is null then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;
    if parsed_warning_accepted and parsed_warning_justification is null then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;

    parsed_calculation_eligible := parsed_formula_eligible
      and (parsed_warning_code is null or parsed_warning_accepted);
  else
    if pg_catalog.jsonb_array_length(readings) <> 0
       or target_payload ? 'inputUnit'
       or target_payload ? 'acceptWarning'
       or target_payload ? 'justification' then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;
    parsed_warning_accepted := false;
    parsed_warning_justification := null;
    parsed_calculation_eligible := false;
  end if;

  select measurement.*
  into existing_measurement
  from public.consultation_measurements measurement
  where measurement.id = measurement_id
  for update;

  if found and existing_measurement.consultation_id <> consultation_record.id then
    raise exception 'consultation_unauthorized' using errcode = '42501';
  end if;

  if found then
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'ordinal', stored.ordinal,
          'rawValue', private.consultation_decimal_text_v43(stored.raw_value),
          'rawUnit', stored.raw_unit,
          'normalizedValue', private.consultation_decimal_text_v43(stored.normalized_value)
        ) order by stored.ordinal
      ),
      '[]'::jsonb
    ) is distinct from normalized_readings
    into raw_set_changed
    from public.consultation_measurement_readings stored
    where stored.measurement_id = existing_measurement.id;

    if raw_set_changed and correction_reason is null then
      raise exception 'consultation_measurement_correction_required'
        using errcode = '22023';
    end if;

    if existing_measurement.measurement_kind <> parsed_measurement_kind
       or existing_measurement.definition_id is distinct from definition_record.id
       or existing_measurement.custom_label is distinct from parsed_custom_label then
      raise exception 'consultation_measurement_validation_failed'
        using errcode = '22023';
    end if;

    session_id := existing_measurement.session_id;
    update public.consultation_measurement_sessions session
    set observed_at = parsed_observed_at,
        operator_user_id = caller_user_id,
        protocol_id = parsed_protocol_id,
        protocol_version = parsed_protocol_version,
        conditions = parsed_conditions,
        updated_at = pg_catalog.statement_timestamp()
    where session.id = session_id;

    update public.consultation_measurements measurement
    set canonical_unit = parsed_canonical_unit,
        protocol_id = parsed_protocol_id,
        protocol_version = parsed_protocol_version,
        observation_status = parsed_observation_status,
        reducer = reducer_name,
        formula_eligible = parsed_formula_eligible,
        calculation_eligible = parsed_calculation_eligible,
        aggregate_value = parsed_aggregate_value,
        aggregate_display_value = parsed_aggregate_display_value,
        display_scale = parsed_display_scale,
        warning_code = parsed_warning_code,
        warning_accepted = parsed_warning_accepted,
        warning_justification = parsed_warning_justification,
        correction_count = measurement.correction_count + case when raw_set_changed then 1 else 0 end,
        updated_at = pg_catalog.statement_timestamp()
    where measurement.id = existing_measurement.id;

    delete from public.consultation_measurement_readings stored
    where stored.measurement_id = existing_measurement.id;
  else
    session_id := gen_random_uuid();
    insert into public.consultation_measurement_sessions (
      id, consultation_id, observed_at, operator_user_id,
      protocol_id, protocol_version, conditions
    ) values (
      session_id, consultation_record.id, parsed_observed_at, caller_user_id,
      parsed_protocol_id, parsed_protocol_version, parsed_conditions
    );

    insert into public.consultation_measurements (
      id, consultation_id, session_id, definition_id, measurement_kind,
      definition_key, definition_version, custom_label, canonical_unit,
      protocol_id, protocol_version, observation_status, reducer,
      formula_eligible, calculation_eligible, aggregate_value,
      aggregate_display_value, display_scale, warning_code,
      warning_accepted, warning_justification
    ) values (
      measurement_id, consultation_record.id, session_id, definition_record.id,
      parsed_measurement_kind, definition_record.definition_key,
      definition_record.definition_version, parsed_custom_label, parsed_canonical_unit,
      parsed_protocol_id, parsed_protocol_version, parsed_observation_status, reducer_name,
      parsed_formula_eligible, parsed_calculation_eligible, parsed_aggregate_value,
      parsed_aggregate_display_value, parsed_display_scale, parsed_warning_code,
      parsed_warning_accepted, parsed_warning_justification
    );
  end if;

  if parsed_observation_status = 'recorded' then
    for reading in
      select entry.value
      from pg_catalog.jsonb_array_elements(normalized_readings) entry(value)
      order by (entry.value ->> 'ordinal')::integer
    loop
      insert into public.consultation_measurement_readings (
        measurement_id, ordinal, raw_value, raw_unit,
        normalized_value, canonical_unit
      ) values (
        measurement_id,
        (reading ->> 'ordinal')::smallint,
        (reading ->> 'rawValue')::numeric,
        reading ->> 'rawUnit',
        (reading ->> 'normalizedValue')::numeric,
        parsed_canonical_unit
      );
    end loop;
  end if;

  next_revision := consultation_record.draft_revision + 1;
  update public.professional_consultations consultation
  set draft_revision = next_revision,
      updated_at = pg_catalog.statement_timestamp()
  where consultation.id = consultation_record.id;

  insert into public.consultation_save_receipts (
    author_user_id, consultation_id, correlation_id, resulting_revision
  ) values (
    caller_user_id, consultation_record.id, target_correlation_id, next_revision
  );

  insert into public.consultation_events (
    consultation_id, subject_id, actor_user_id, relationship_id, event_type
  ) values (
    consultation_record.id,
    consultation_record.subject_id,
    caller_user_id,
    consultation_record.relationship_id,
    case when raw_set_changed then 'measurement_corrected' else 'measurement_saved' end
  );

  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'consultationId', consultation_record.id,
    'measurementId', measurement_id,
    'draftRevision', next_revision,
    'aggregateValue', case when parsed_aggregate_value is null then null
      else private.consultation_decimal_text_v43(parsed_aggregate_value) end,
    'displayValue', case when parsed_aggregate_display_value is null then null
      else private.consultation_decimal_text_v43(parsed_aggregate_display_value) end,
    'warningCode', parsed_warning_code,
    'calculationEligible', parsed_calculation_eligible,
    'idempotent', false
  ));
end;
$$;

create trigger reject_consultation_measurement_definition_mutation_v43
before update or delete on public.consultation_measurement_definitions
for each row
execute function private.reject_consultation_measurement_definition_mutation_v43();

create trigger protect_finalized_consultation_measurement_sessions_v43
before insert or update or delete on public.consultation_measurement_sessions
for each row
execute function private.protect_finalized_consultation_measurements_v43();

create trigger protect_finalized_consultation_measurements_v43
before insert or update or delete on public.consultation_measurements
for each row
execute function private.protect_finalized_consultation_measurements_v43();

create trigger protect_finalized_consultation_measurement_readings_v43
before insert or update or delete on public.consultation_measurement_readings
for each row
execute function private.protect_finalized_consultation_measurements_v43();

create trigger protect_finalized_consultation_device_observations_v43
before insert or update or delete on public.consultation_device_observations
for each row
execute function private.protect_finalized_consultation_measurements_v43();

alter table public.consultation_measurement_definitions enable row level security;
alter table public.consultation_measurement_definitions force row level security;
alter table public.consultation_measurement_sessions enable row level security;
alter table public.consultation_measurement_sessions force row level security;
alter table public.consultation_measurements enable row level security;
alter table public.consultation_measurements force row level security;
alter table public.consultation_measurement_readings enable row level security;
alter table public.consultation_measurement_readings force row level security;
alter table public.consultation_device_observations enable row level security;
alter table public.consultation_device_observations force row level security;

revoke all privileges on table public.consultation_measurement_definitions
  from public, anon, authenticated;
revoke all privileges on table public.consultation_measurement_sessions
  from public, anon, authenticated;
revoke all privileges on table public.consultation_measurements
  from public, anon, authenticated;
revoke all privileges on table public.consultation_measurement_readings
  from public, anon, authenticated;
revoke all privileges on table public.consultation_device_observations
  from public, anon, authenticated;

revoke all on function
  public.save_my_consultation_measurement_v43(uuid, text, bigint, bigint, uuid, jsonb),
  public.save_my_consultation_device_observation_v43(uuid, text, bigint, bigint, uuid, jsonb)
from public, anon, authenticated;

grant execute on function
  public.save_my_consultation_measurement_v43(uuid, text, bigint, bigint, uuid, jsonb),
  public.save_my_consultation_device_observation_v43(uuid, text, bigint, bigint, uuid, jsonb)
to authenticated;

revoke all privileges on all functions in schema private
  from public, anon, authenticated;

commit;
