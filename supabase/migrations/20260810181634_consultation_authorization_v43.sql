begin;

-- Add the two consultation capabilities without changing any existing choice.
create or replace function public.default_professional_relationship_scopes_v41e1(
  target_professional_type text
)
returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  if target_professional_type = 'trainer' then
    return pg_catalog.jsonb_build_object(
      'manage_workout_plan', true,
      'view_workout_executions', true,
      'view_evolution', true,
      'manage_nutrition_plan', false,
      'view_nutrition_logs', false,
      'manage_consultations', false,
      'view_shared_consultation_history', false
    );
  end if;

  if target_professional_type = 'nutritionist' then
    return pg_catalog.jsonb_build_object(
      'manage_workout_plan', false,
      'view_workout_executions', false,
      'view_evolution', true,
      'manage_nutrition_plan', true,
      'view_nutrition_logs', true,
      'manage_consultations', false,
      'view_shared_consultation_history', false
    );
  end if;

  raise exception 'invalid_professional_type' using errcode = '22023';
end;
$$;

create or replace function public.apply_default_professional_relationship_scopes_v41e1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.scopes := public.default_professional_relationship_scopes_v41e1(
    new.professional_type
  ) || coalesce(new.scopes, '{}'::jsonb);
  return new;
end;
$$;

alter table public.professional_student_relationships
  drop constraint professional_student_relationships_scopes_check;

alter table public.professional_student_relationships
  alter column scopes set default '{
    "manage_workout_plan": false,
    "view_workout_executions": false,
    "manage_nutrition_plan": false,
    "view_nutrition_logs": false,
    "view_evolution": false,
    "manage_consultations": false,
    "view_shared_consultation_history": false
  }'::jsonb;

update public.professional_student_relationships
set scopes = pg_catalog.jsonb_build_object(
  'manage_consultations', false,
  'view_shared_consultation_history', false
) || scopes;

alter table public.professional_student_relationships
  add constraint professional_student_relationships_scopes_check
  check (
    pg_catalog.jsonb_typeof(scopes) = 'object'
    and scopes ?& array[
      'manage_workout_plan',
      'view_workout_executions',
      'manage_nutrition_plan',
      'view_nutrition_logs',
      'view_evolution',
      'manage_consultations',
      'view_shared_consultation_history'
    ]
    and pg_catalog.jsonb_typeof(scopes -> 'manage_workout_plan') = 'boolean'
    and pg_catalog.jsonb_typeof(scopes -> 'view_workout_executions') = 'boolean'
    and pg_catalog.jsonb_typeof(scopes -> 'manage_nutrition_plan') = 'boolean'
    and pg_catalog.jsonb_typeof(scopes -> 'view_nutrition_logs') = 'boolean'
    and pg_catalog.jsonb_typeof(scopes -> 'view_evolution') = 'boolean'
    and pg_catalog.jsonb_typeof(scopes -> 'manage_consultations') = 'boolean'
    and pg_catalog.jsonb_typeof(scopes -> 'view_shared_consultation_history') = 'boolean'
    and (
      scopes
      - 'manage_workout_plan'
      - 'view_workout_executions'
      - 'manage_nutrition_plan'
      - 'view_nutrition_logs'
      - 'view_evolution'
      - 'manage_consultations'
      - 'view_shared_consultation_history'
    ) = '{}'::jsonb
    and (
      professional_type <> 'trainer'
      or (
        scopes -> 'manage_nutrition_plan' = 'false'::jsonb
        and scopes -> 'view_nutrition_logs' = 'false'::jsonb
      )
    )
    and (
      professional_type <> 'nutritionist'
      or (
        scopes -> 'manage_workout_plan' = 'false'::jsonb
        and scopes -> 'view_workout_executions' = 'false'::jsonb
      )
    )
  );

create table public.consultation_authorization_text_versions (
  id uuid default gen_random_uuid() not null,
  purpose text not null,
  version_identifier text not null,
  status text default 'effective' not null,
  effective_at timestamp with time zone not null,
  retired_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  constraint consultation_authorization_text_versions_pkey primary key (id),
  constraint consultation_authorization_text_versions_identity_key
    unique (purpose, version_identifier),
  constraint consultation_authorization_text_versions_purpose_check
    check (purpose in ('manage_consultations', 'shared_history')),
  constraint consultation_authorization_text_versions_status_check
    check (status in ('effective', 'retired')),
  constraint consultation_authorization_text_versions_lifecycle_check
    check (
      (status = 'effective' and retired_at is null)
      or (status = 'retired' and retired_at is not null)
    ),
  constraint consultation_authorization_text_versions_identifier_check
    check (
      length(version_identifier) between 1 and 120
      and version_identifier ~ '^[a-z0-9][a-z0-9._-]*$'
    )
);

create unique index consultation_authorization_text_versions_effective_key
on public.consultation_authorization_text_versions (purpose)
where status = 'effective';

create table public.consultation_authorization_requests (
  id uuid default gen_random_uuid() not null,
  relationship_id uuid not null,
  professional_user_id uuid not null,
  client_user_id uuid not null,
  authorization_purpose text
    generated always as ('manage_consultations'::text) stored,
  authorization_text_version text not null,
  status text default 'pending' not null,
  requested_at timestamp with time zone default now() not null,
  decided_at timestamp with time zone,
  decided_by_user_id uuid,
  invalidated_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  constraint consultation_authorization_requests_pkey primary key (id),
  constraint consultation_authorization_requests_relationship_id_fkey
    foreign key (relationship_id)
    references public.professional_student_relationships(id)
    on update restrict
    on delete restrict,
  constraint consultation_authorization_requests_professional_user_id_fkey
    foreign key (professional_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_authorization_requests_client_user_id_fkey
    foreign key (client_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_authorization_requests_decided_by_user_id_fkey
    foreign key (decided_by_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_authorization_requests_version_fkey
    foreign key (authorization_purpose, authorization_text_version)
    references public.consultation_authorization_text_versions(
      purpose,
      version_identifier
    ),
  constraint consultation_authorization_requests_status_check
    check (status in ('pending', 'accepted', 'declined', 'invalidated'))
);

create unique index consultation_authorization_requests_relationship_pending_key
on public.consultation_authorization_requests (relationship_id)
where status = 'pending';

create index consultation_authorization_requests_relationship_lookup_idx
on public.consultation_authorization_requests (
  relationship_id,
  status,
  requested_at desc
);

create table public.consultation_authorization_events (
  id uuid default gen_random_uuid() not null,
  event_sequence bigint generated always as identity not null,
  relationship_id uuid not null,
  request_id uuid,
  professional_user_id uuid not null,
  client_user_id uuid not null,
  actor_user_id uuid,
  event_type text not null,
  authorization_text_version text,
  occurred_at timestamp with time zone default now() not null,
  constraint consultation_authorization_events_pkey primary key (id),
  constraint consultation_authorization_events_sequence_key
    unique (event_sequence),
  constraint consultation_authorization_events_relationship_id_fkey
    foreign key (relationship_id)
    references public.professional_student_relationships(id)
    on update restrict
    on delete restrict,
  constraint consultation_authorization_events_request_id_fkey
    foreign key (request_id)
    references public.consultation_authorization_requests(id)
    on update restrict
    on delete restrict,
  constraint consultation_authorization_events_professional_user_id_fkey
    foreign key (professional_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_authorization_events_client_user_id_fkey
    foreign key (client_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_authorization_events_actor_user_id_fkey
    foreign key (actor_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_authorization_events_type_check
    check (
      event_type in (
        'requested',
        'accepted',
        'declined',
        'revoked',
        'relationship_invalidated'
      )
    )
);

create index consultation_authorization_events_relationship_lookup_idx
on public.consultation_authorization_events (
  relationship_id,
  event_sequence desc
);

create table public.consultation_sharing_consents (
  id uuid default gen_random_uuid() not null,
  event_sequence bigint generated always as identity not null,
  relationship_id uuid not null,
  professional_user_id uuid not null,
  client_user_id uuid not null,
  actor_user_id uuid,
  disclosure_purpose text
    generated always as ('shared_history'::text) stored,
  disclosure_text_version text not null,
  granted boolean not null,
  event_type text not null,
  occurred_at timestamp with time zone default now() not null,
  constraint consultation_sharing_consents_pkey primary key (id),
  constraint consultation_sharing_consents_sequence_key
    unique (event_sequence),
  constraint consultation_sharing_consents_relationship_id_fkey
    foreign key (relationship_id)
    references public.professional_student_relationships(id)
    on update restrict
    on delete restrict,
  constraint consultation_sharing_consents_professional_user_id_fkey
    foreign key (professional_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_sharing_consents_client_user_id_fkey
    foreign key (client_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_sharing_consents_actor_user_id_fkey
    foreign key (actor_user_id)
    references auth.users(id)
    on update restrict
    on delete restrict,
  constraint consultation_sharing_consents_version_fkey
    foreign key (disclosure_purpose, disclosure_text_version)
    references public.consultation_authorization_text_versions(
      purpose,
      version_identifier
    ),
  constraint consultation_sharing_consents_event_type_check
    check (event_type in ('granted', 'revoked', 'relationship_invalidated')),
  constraint consultation_sharing_consents_event_value_check
    check (
      (event_type = 'granted' and granted)
      or (event_type in ('revoked', 'relationship_invalidated') and not granted)
    )
);

create index consultation_sharing_consents_relationship_lookup_idx
on public.consultation_sharing_consents (
  relationship_id,
  event_sequence desc
);

create or replace function private.assert_effective_consultation_text_version_v43(
  target_purpose text,
  target_version_identifier text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if target_purpose not in ('manage_consultations', 'shared_history')
     or target_version_identifier is null then
    raise exception 'invalid_consultation_authorization_version'
      using errcode = '22023';
  end if;

  perform 1
  from public.consultation_authorization_text_versions version
  where version.purpose = target_purpose
    and version.version_identifier = target_version_identifier
    and version.status = 'effective'
    and version.effective_at <= now()
    and version.retired_at is null;

  if not found then
    raise exception 'consultation_authorization_version_not_effective'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function private.assert_consultation_relationship_entitlement_v43(
  target_relationship_id uuid,
  target_professional_user_id uuid,
  target_required_scope text default null
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  relationship_record public.professional_student_relationships;
begin
  if target_relationship_id is null or target_professional_user_id is null then
    raise exception 'consultation_relationship_not_authorized'
      using errcode = '42501';
  end if;

  if target_required_scope is not null
     and target_required_scope not in (
       'manage_consultations',
       'view_shared_consultation_history'
     ) then
    raise exception 'invalid_consultation_scope' using errcode = '22023';
  end if;

  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = target_relationship_id
    and relationship.professional_user_id = target_professional_user_id
    and relationship.professional_type in ('trainer', 'nutritionist')
    and relationship.status = 'active'
    and (
      target_required_scope is null
      or coalesce(
        (relationship.scopes ->> target_required_scope)::boolean,
        false
      )
    );

  if not found then
    raise exception 'consultation_relationship_not_authorized'
      using errcode = '42501';
  end if;

  perform 1
  from public.user_commercial_accounts account
  join public.account_plan_catalog plan
    on plan.code = account.plan_code
   and plan.account_type = account.primary_account_type
  join public.user_account_modes account_mode
    on account_mode.user_id = account.user_id
   and account_mode.mode = relationship_record.professional_type
  where account.user_id = relationship_record.professional_user_id
    and account.primary_account_type = relationship_record.professional_type
    and account.subscription_status in ('active', 'trialing')
    and plan.is_active;

  if not found then
    raise exception 'consultation_professional_entitlement_inactive'
      using errcode = '42501';
  end if;

  perform 1
  from public.user_identity_details identity
  where identity.user_id = relationship_record.student_user_id
    and identity.age_status = 'adult'
    and identity.age_verified_at is not null
    and identity.birth_date <= (current_date - interval '18 years')::date;

  if not found then
    raise exception 'consultation_subject_requires_adult_account'
      using errcode = '42501';
  end if;

  if relationship_record.organization_id is not null then
    perform 1
    from public.organization_members membership
    join public.organizations organization
      on organization.id = membership.organization_id
    where membership.organization_id = relationship_record.organization_id
      and membership.user_id = relationship_record.professional_user_id
      and membership.status = 'active'
      and organization.status = 'active'
      and (
        (
          relationship_record.professional_type = 'trainer'
          and membership.role in ('owner', 'admin', 'trainer')
        )
        or (
          relationship_record.professional_type = 'nutritionist'
          and membership.role in ('owner', 'admin', 'nutritionist')
        )
      );

    if not found then
      raise exception 'consultation_organization_entitlement_inactive'
        using errcode = '42501';
    end if;
  end if;

  return relationship_record.student_user_id;
end;
$$;

create or replace function private.has_current_shared_consultation_history_consent_v43(
  target_relationship_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select consent.granted
      and consent.disclosure_text_version = version.version_identifier
    from public.consultation_sharing_consents consent
    join public.consultation_authorization_text_versions version
      on version.purpose = 'shared_history'
     and version.status = 'effective'
     and version.effective_at <= now()
     and version.retired_at is null
    where consent.relationship_id = target_relationship_id
    order by consent.event_sequence desc
    limit 1
  ), false);
$$;

create or replace function private.is_approved_shared_consultation_item_v43(
  target_item_key text
)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select target_item_key in ('common.goal');
$$;

create or replace function private.reject_immutable_consultation_authorization_history_v43()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'immutable_consultation_authorization_history'
    using errcode = '55000';
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
        invalidated_at = now()
    where request.relationship_id = new.id
      and request.status = 'pending';

    if coalesce(
      (old.scopes ->> 'manage_consultations')::boolean,
      false
    ) then
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
        now()
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
          now()
        );
      end if;
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.request_my_consultation_authorization_v43(
  target_relationship_id uuid,
  target_authorization_text_version text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  relationship_record public.professional_student_relationships;
  pending_request public.consultation_authorization_requests;
  created_request_id uuid;
begin
  if caller_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  perform private.assert_consultation_relationship_entitlement_v43(
    target_relationship_id,
    caller_user_id,
    null
  );
  perform private.assert_effective_consultation_text_version_v43(
    'manage_consultations',
    target_authorization_text_version
  );

  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = target_relationship_id
    and relationship.professional_user_id = caller_user_id
  for update;

  select request.*
  into pending_request
  from public.consultation_authorization_requests request
  where request.relationship_id = target_relationship_id
    and request.status = 'pending'
  order by request.requested_at desc, request.id desc
  limit 1
  for update;

  if found then
    if pending_request.authorization_text_version
       = target_authorization_text_version then
      return pending_request.id;
    end if;

    update public.consultation_authorization_requests request
    set status = 'invalidated', invalidated_at = now()
    where request.id = pending_request.id;
  end if;

  insert into public.consultation_authorization_requests (
    relationship_id,
    professional_user_id,
    client_user_id,
    authorization_text_version
  ) values (
    relationship_record.id,
    relationship_record.professional_user_id,
    relationship_record.student_user_id,
    target_authorization_text_version
  )
  returning id into created_request_id;

  insert into public.consultation_authorization_events (
    relationship_id,
    request_id,
    professional_user_id,
    client_user_id,
    actor_user_id,
    event_type,
    authorization_text_version
  ) values (
    relationship_record.id,
    created_request_id,
    relationship_record.professional_user_id,
    relationship_record.student_user_id,
    caller_user_id,
    'requested',
    target_authorization_text_version
  );

  return created_request_id;
end;
$$;

create or replace function public.decide_my_consultation_authorization_v43(
  target_relationship_id uuid,
  target_request_id uuid,
  target_decision text,
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
  request_record public.consultation_authorization_requests;
begin
  if caller_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if target_decision not in ('accept', 'decline') then
    raise exception 'invalid_consultation_authorization_decision'
      using errcode = '22023';
  end if;

  select relationship.*
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = target_relationship_id
    and relationship.student_user_id = caller_user_id
    and relationship.status = 'active'
  for update;

  if not found then
    raise exception 'consultation_authorization_decision_forbidden'
      using errcode = '42501';
  end if;

  perform private.assert_consultation_relationship_entitlement_v43(
    relationship_record.id,
    relationship_record.professional_user_id,
    null
  );
  perform private.assert_effective_consultation_text_version_v43(
    'manage_consultations',
    target_authorization_text_version
  );

  select request.*
  into request_record
  from public.consultation_authorization_requests request
  where request.id = target_request_id
    and request.relationship_id = relationship_record.id
    and request.professional_user_id = relationship_record.professional_user_id
    and request.client_user_id = caller_user_id
    and request.authorization_text_version
      = target_authorization_text_version
    and request.status = 'pending'
  for update;

  if not found then
    raise exception 'consultation_authorization_request_not_pending'
      using errcode = '42501';
  end if;

  update public.consultation_authorization_requests request
  set status = case target_decision
        when 'accept' then 'accepted'
        else 'declined'
      end,
      decided_at = now(),
      decided_by_user_id = caller_user_id
  where request.id = request_record.id;

  update public.professional_student_relationships relationship
  set scopes = pg_catalog.jsonb_set(
        relationship.scopes,
        '{manage_consultations}',
        case target_decision
          when 'accept' then 'true'::jsonb
          else 'false'::jsonb
        end,
        true
      ),
      updated_at = now()
  where relationship.id = relationship_record.id;

  insert into public.consultation_authorization_events (
    relationship_id,
    request_id,
    professional_user_id,
    client_user_id,
    actor_user_id,
    event_type,
    authorization_text_version
  ) values (
    relationship_record.id,
    request_record.id,
    relationship_record.professional_user_id,
    caller_user_id,
    caller_user_id,
    case target_decision
      when 'accept' then 'accepted'
      else 'declined'
    end,
    target_authorization_text_version
  );

  return target_decision = 'accept';
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
  set status = 'invalidated', invalidated_at = now()
  where request.relationship_id = relationship_record.id
    and request.status = 'pending';

  update public.professional_student_relationships relationship
  set scopes = pg_catalog.jsonb_set(
        relationship.scopes,
        '{manage_consultations}',
        'false'::jsonb,
        true
      ),
      updated_at = now()
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

  return true;
end;
$$;

create or replace function public.set_my_shared_consultation_history_consent_v43(
  target_relationship_id uuid,
  target_disclosure_text_version text,
  target_granted boolean
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
    and (not target_granted or relationship.status = 'active')
  for update;

  if not found then
    raise exception 'consultation_sharing_consent_forbidden'
      using errcode = '42501';
  end if;

  if target_granted then
    perform private.assert_consultation_relationship_entitlement_v43(
      relationship_record.id,
      relationship_record.professional_user_id,
      null
    );
    perform private.assert_effective_consultation_text_version_v43(
      'shared_history',
      target_disclosure_text_version
    );
  else
    perform 1
    from public.consultation_authorization_text_versions version
    where version.purpose = 'shared_history'
      and version.version_identifier = target_disclosure_text_version;
    if not found then
      raise exception 'invalid_consultation_authorization_version'
        using errcode = '22023';
    end if;
  end if;

  insert into public.consultation_sharing_consents (
    relationship_id,
    professional_user_id,
    client_user_id,
    actor_user_id,
    disclosure_text_version,
    granted,
    event_type
  ) values (
    relationship_record.id,
    relationship_record.professional_user_id,
    caller_user_id,
    caller_user_id,
    target_disclosure_text_version,
    target_granted,
    case when target_granted then 'granted' else 'revoked' end
  );

  update public.professional_student_relationships relationship
  set scopes = pg_catalog.jsonb_set(
        relationship.scopes,
        '{view_shared_consultation_history}',
        pg_catalog.to_jsonb(target_granted),
        true
      ),
      updated_at = now()
  where relationship.id = relationship_record.id;

  return target_granted;
end;
$$;

create or replace function public.list_my_manageable_consultation_subjects_v43(
  target_limit integer default 50,
  target_after_relationship_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  bounded_limit integer;
begin
  if caller_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  bounded_limit := greatest(
    1,
    least(coalesce(target_limit, 50), 100)
  );

  return coalesce((
    select pg_catalog.jsonb_agg(result.payload order by result.relationship_id)
    from (
      select
        relationship.id as relationship_id,
        pg_catalog.jsonb_build_object(
          'relationshipId', relationship.id,
          'subjectId', subject.id,
          'clientUserId', relationship.student_user_id,
          'professionalType', relationship.professional_type,
          'organizationId', relationship.organization_id
        ) as payload
      from public.professional_student_relationships relationship
      join public.user_commercial_accounts account
        on account.user_id = relationship.professional_user_id
       and account.primary_account_type = relationship.professional_type
       and account.subscription_status in ('active', 'trialing')
      join public.account_plan_catalog plan
        on plan.code = account.plan_code
       and plan.account_type = account.primary_account_type
       and plan.is_active
      join public.user_account_modes account_mode
        on account_mode.user_id = relationship.professional_user_id
       and account_mode.mode = relationship.professional_type
      join public.user_identity_details identity
        on identity.user_id = relationship.student_user_id
       and identity.age_status = 'adult'
       and identity.age_verified_at is not null
       and identity.birth_date <= (current_date - interval '18 years')::date
      join public.consultation_subjects subject
        on subject.account_user_id = relationship.student_user_id
      left join public.organizations organization
        on organization.id = relationship.organization_id
      where relationship.professional_user_id = caller_user_id
        and relationship.professional_type in ('trainer', 'nutritionist')
        and relationship.status = 'active'
        and coalesce(
          (relationship.scopes ->> 'manage_consultations')::boolean,
          false
        )
        and (
          target_after_relationship_id is null
          or relationship.id > target_after_relationship_id
        )
        and (
          relationship.organization_id is null
          or (
            organization.status = 'active'
            and exists (
              select 1
              from public.organization_members membership
              where membership.organization_id = relationship.organization_id
                and membership.user_id = relationship.professional_user_id
                and membership.status = 'active'
                and (
                  (
                    relationship.professional_type = 'trainer'
                    and membership.role in ('owner', 'admin', 'trainer')
                  )
                  or (
                    relationship.professional_type = 'nutritionist'
                    and membership.role in ('owner', 'admin', 'nutritionist')
                  )
                )
            )
          )
        )
      order by relationship.id
      limit bounded_limit
    ) result
  ), '[]'::jsonb);
end;
$$;

create or replace function public.get_my_consultation_v43(
  target_consultation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  consultation_record public.professional_consultations;
begin
  if caller_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select consultation.*
  into consultation_record
  from public.professional_consultations consultation
  where consultation.id = target_consultation_id
    and consultation.author_user_id = caller_user_id;

  if not found then
    raise exception 'consultation_content_forbidden' using errcode = '42501';
  end if;

  perform private.assert_consultation_relationship_entitlement_v43(
    consultation_record.relationship_id,
    caller_user_id,
    'manage_consultations'
  );

  return pg_catalog.jsonb_build_object(
    'id', consultation_record.id,
    'subjectId', consultation_record.subject_id,
    'relationshipId', consultation_record.relationship_id,
    'professionalType', consultation_record.professional_type,
    'organizationId', consultation_record.organization_id,
    'consultationKind', consultation_record.consultation_kind,
    'status', consultation_record.status,
    'draftRevision', consultation_record.draft_revision,
    'schemaVersion', consultation_record.schema_version,
    'scheduledStartAt', consultation_record.scheduled_start_at,
    'startedAt', consultation_record.started_at,
    'finalizedAt', consultation_record.finalized_at,
    'items', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', item.id,
          'itemKey', item.item_key,
          'itemKind', item.item_kind,
          'schemaVersion', item.schema_version,
          'value', item.value_payload
        ) order by item.item_key
      )
      from public.consultation_items item
      where item.consultation_id = consultation_record.id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.list_shared_consultation_history_v43(
  target_relationship_id uuid,
  target_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_user_id uuid := auth.uid();
  client_user_id uuid;
  bounded_limit integer;
begin
  if caller_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  client_user_id := private.assert_consultation_relationship_entitlement_v43(
    target_relationship_id,
    caller_user_id,
    'view_shared_consultation_history'
  );

  if not private.has_current_shared_consultation_history_consent_v43(
    target_relationship_id
  ) then
    raise exception 'shared_consultation_history_consent_required'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.professional_consultations consultation
    join public.consultation_subjects subject
      on subject.id = consultation.subject_id
    join public.professional_student_relationships source_relationship
      on source_relationship.id = consultation.relationship_id
    left join public.organizations source_organization
      on source_organization.id = source_relationship.organization_id
    where subject.account_user_id = client_user_id
      and consultation.status = 'finalized'
      and (
        source_relationship.status <> 'active'
        or source_relationship.professional_user_id
          <> consultation.author_user_id
        or source_relationship.professional_type
          <> consultation.professional_type
        or source_relationship.organization_id
          is distinct from consultation.organization_id
        or (
          source_relationship.organization_id is not null
          and (
            source_organization.status <> 'active'
            or not exists (
              select 1
              from public.organization_members source_membership
              where source_membership.organization_id
                = source_relationship.organization_id
                and source_membership.user_id
                  = source_relationship.professional_user_id
                and source_membership.status = 'active'
                and (
                  (
                    source_relationship.professional_type = 'trainer'
                    and source_membership.role in ('owner', 'admin', 'trainer')
                  )
                  or (
                    source_relationship.professional_type = 'nutritionist'
                    and source_membership.role in (
                      'owner',
                      'admin',
                      'nutritionist'
                    )
                  )
                )
            )
          )
        )
      )
  ) then
    raise exception 'shared_consultation_history_source_inactive'
      using errcode = '42501';
  end if;

  bounded_limit := greatest(
    1,
    least(coalesce(target_limit, 50), 100)
  );

  return coalesce((
    select pg_catalog.jsonb_agg(result.payload order by result.finalized_at desc)
    from (
      select
        consultation.finalized_at,
        pg_catalog.jsonb_build_object(
          'consultationId', consultation.id,
          'finalizedAt', consultation.finalized_at,
          'professionalType', consultation.professional_type,
          'itemKey', snapshot_item.item ->> 'itemKey',
          'value', snapshot_item.item -> 'value'
        ) as payload
      from public.professional_consultations consultation
      join public.consultation_subjects subject
        on subject.id = consultation.subject_id
      join public.professional_student_relationships source_relationship
        on source_relationship.id = consultation.relationship_id
       and source_relationship.status = 'active'
       and source_relationship.professional_user_id
         = consultation.author_user_id
       and source_relationship.professional_type
         = consultation.professional_type
       and source_relationship.organization_id
         is not distinct from consultation.organization_id
      join public.consultation_final_snapshots snapshot
        on snapshot.consultation_id = consultation.id
      cross join lateral pg_catalog.jsonb_array_elements(
        snapshot.canonical_payload -> 'items'
      ) snapshot_item(item)
      left join public.organizations source_organization
        on source_organization.id = source_relationship.organization_id
      where subject.account_user_id = client_user_id
        and consultation.status = 'finalized'
        and private.is_approved_shared_consultation_item_v43(
          snapshot_item.item ->> 'itemKey'
        )
        and (
          source_relationship.organization_id is null
          or (
            source_organization.status = 'active'
            and exists (
              select 1
              from public.organization_members source_membership
              where source_membership.organization_id
                = source_relationship.organization_id
                and source_membership.user_id
                  = source_relationship.professional_user_id
                and source_membership.status = 'active'
                and (
                  (
                    source_relationship.professional_type = 'trainer'
                    and source_membership.role in ('owner', 'admin', 'trainer')
                  )
                  or (
                    source_relationship.professional_type = 'nutritionist'
                    and source_membership.role in (
                      'owner',
                      'admin',
                      'nutritionist'
                    )
                  )
                )
            )
          )
        )
      order by consultation.finalized_at desc, consultation.id, snapshot_item.item ->> 'itemKey'
      limit bounded_limit
    ) result
  ), '[]'::jsonb);
end;
$$;

create trigger reject_consultation_authorization_event_mutation_v43
before update or delete on public.consultation_authorization_events
for each row
execute function private.reject_immutable_consultation_authorization_history_v43();

create trigger reject_consultation_sharing_consent_mutation_v43
before update or delete on public.consultation_sharing_consents
for each row
execute function private.reject_immutable_consultation_authorization_history_v43();

create trigger protect_consultation_relationship_authorization_v43
before update of status on public.professional_student_relationships
for each row
execute function private.protect_consultation_relationship_authorization_v43();

alter table public.consultation_authorization_text_versions enable row level security;
alter table public.consultation_authorization_text_versions force row level security;
alter table public.consultation_authorization_requests enable row level security;
alter table public.consultation_authorization_requests force row level security;
alter table public.consultation_authorization_events enable row level security;
alter table public.consultation_authorization_events force row level security;
alter table public.consultation_sharing_consents enable row level security;
alter table public.consultation_sharing_consents force row level security;

revoke all privileges on table public.consultation_subjects
from public, anon, authenticated;
revoke all privileges on table public.professional_consultations
from public, anon, authenticated;
revoke all privileges on table public.consultation_items
from public, anon, authenticated;
revoke all privileges on table public.consultation_authorization_text_versions
from public, anon, authenticated;
revoke all privileges on table public.consultation_authorization_requests
from public, anon, authenticated;
revoke all privileges on table public.consultation_authorization_events
from public, anon, authenticated;
revoke all privileges on table public.consultation_sharing_consents
from public, anon, authenticated;

revoke all on function
  public.request_my_consultation_authorization_v43(uuid, text),
  public.decide_my_consultation_authorization_v43(uuid, uuid, text, text),
  public.revoke_my_consultation_authorization_v43(uuid, text),
  public.set_my_shared_consultation_history_consent_v43(uuid, text, boolean),
  public.list_my_manageable_consultation_subjects_v43(integer, uuid),
  public.get_my_consultation_v43(uuid),
  public.list_shared_consultation_history_v43(uuid, integer)
from public, anon, authenticated;

grant execute on function
  public.request_my_consultation_authorization_v43(uuid, text),
  public.decide_my_consultation_authorization_v43(uuid, uuid, text, text),
  public.revoke_my_consultation_authorization_v43(uuid, text),
  public.set_my_shared_consultation_history_consent_v43(uuid, text, boolean),
  public.list_my_manageable_consultation_subjects_v43(integer, uuid),
  public.get_my_consultation_v43(uuid),
  public.list_shared_consultation_history_v43(uuid, integer)
to authenticated;

revoke all on function
  public.default_professional_relationship_scopes_v41e1(text),
  public.apply_default_professional_relationship_scopes_v41e1()
from public, anon, authenticated;

revoke all privileges on all functions in schema private
from public, anon, authenticated;

commit;
