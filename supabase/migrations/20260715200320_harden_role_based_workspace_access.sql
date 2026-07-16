begin;

-- The baseline was captured without the explicit ACL revocations present in the
-- approved historical scripts. Reassert least privilege for the role/workspace
-- tables without changing their schema or their authenticated read contracts.
revoke all privileges on table
  public.account_plan_catalog,
  public.organization_members,
  public.organizations,
  public.platform_user_roles,
  public.professional_nutrition_templates,
  public.professional_student_relationships,
  public.professional_workout_templates,
  public.student_nutrition_assignments,
  public.student_workout_assignments,
  public.trainer_student_invitations,
  public.trainer_student_relationships,
  public.user_account_modes,
  public.user_commercial_accounts,
  public.user_identity_details,
  public.user_legal_acceptances,
  public.user_notifications
from public, anon, authenticated;

grant select on table
  public.account_plan_catalog,
  public.organization_members,
  public.organizations,
  public.platform_user_roles,
  public.professional_nutrition_templates,
  public.professional_student_relationships,
  public.professional_workout_templates,
  public.student_nutrition_assignments,
  public.student_workout_assignments,
  public.trainer_student_relationships,
  public.user_account_modes,
  public.user_commercial_accounts,
  public.user_identity_details,
  public.user_legal_acceptances,
  public.user_notifications
to authenticated;

-- Future objects must opt in to Data API access explicitly.
-- PUBLIC receives EXECUTE on new routines from PostgreSQL's global defaults,
-- which cannot be removed by a per-schema REVOKE alone.
alter default privileges for role postgres
  revoke all privileges on routines from public;
alter default privileges for role postgres in schema public
  revoke all privileges on tables from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on routines from public, anon, authenticated;

-- Internal helpers and trigger functions remain unavailable to frontend roles.
revoke all on function
  public.normalize_invitation_code(text),
  public.default_professional_scopes(text),
  public.sync_legacy_trainer_relationship_v41a(),
  public.validate_user_identity_birth_date_v41a1(),
  public.get_current_access_context_v41a(),
  public.get_professional_active_client_count_v41a2(uuid, text, uuid),
  public.assert_professional_client_capacity_v41a2(uuid, text, uuid, uuid),
  public.enforce_professional_client_limit_v41a2(),
  public.validate_workout_plan_payload_v41b(jsonb),
  public.assert_my_trainer_identity_v41b(),
  public.assert_my_trainer_write_access_v41b(),
  public.protect_workout_assignment_snapshot_v41b(),
  public.notification_iso_date_is_valid_v41c(text),
  public.notification_metadata_is_safe_v41c(jsonb),
  public.create_user_notification_v41c(uuid, uuid, text, text, text, text, uuid, text, jsonb),
  public.notify_relationship_status_v41c(),
  public.notify_workout_assignment_v41c(),
  public.nutrition_text_is_safe_v41c(text, integer),
  public.nutrition_unit_is_supported_v41c(text),
  public.validate_nutrition_plan_payload_v41c(jsonb),
  public.assert_my_nutritionist_identity_v41c(),
  public.assert_my_nutritionist_write_access_v41c(),
  public.protect_nutrition_assignment_snapshot_v41c(),
  public.notify_nutrition_assignment_v41c(),
  public.get_my_professional_monitoring_entitlement_v41d(uuid, text, text[]),
  public.assert_professional_monitoring_page_v41d(date, date, integer, date, uuid),
  public.default_professional_relationship_scopes_v41e1(text),
  public.apply_default_professional_relationship_scopes_v41e1()
from public, anon, authenticated;

-- Public RPCs keep exactly the authenticated-only execution contract established
-- by the approved historical migrations.
revoke all on function
  public.is_organization_member(uuid, uuid),
  public.has_organization_role(uuid, text[], uuid),
  public.has_active_trainer_student_relationship(uuid, uuid, text),
  public.has_active_professional_relationship(uuid, uuid, text, text, uuid),
  public.get_current_access_context(),
  public.get_my_account_modes(),
  public.set_my_account_modes(text[]),
  public.create_trainer_student_invitation(),
  public.preview_trainer_invitation(text),
  public.accept_trainer_student_invitation(text),
  public.cancel_trainer_invitation(uuid),
  public.list_my_trainer_invitations(),
  public.list_my_trainer_student_connections(),
  public.get_my_commercial_account_context(),
  public.get_my_account_registration_context(),
  public.complete_my_initial_account_setup(text, text, text, date, text, text),
  public.set_my_personal_use_enabled(boolean),
  public.get_my_professional_client_capacity(),
  public.create_my_workout_template(text, text, jsonb, uuid),
  public.update_my_workout_template(uuid, text, text, jsonb),
  public.archive_my_workout_template(uuid),
  public.list_my_workout_templates(),
  public.list_my_manageable_workout_students(),
  public.assign_workout_template_to_student(uuid, uuid, date),
  public.revoke_my_student_workout_assignment(uuid),
  public.list_my_assigned_workout_plans(),
  public.list_my_notifications(integer, timestamptz),
  public.get_my_unread_notification_count(),
  public.mark_my_notification_read(uuid),
  public.mark_all_my_notifications_read(),
  public.create_my_nutrition_template(text, text, jsonb, uuid),
  public.update_my_nutrition_template(uuid, text, text, jsonb),
  public.archive_my_nutrition_template(uuid),
  public.list_my_nutrition_templates(),
  public.list_my_manageable_nutrition_students(),
  public.assign_nutrition_template_to_student(uuid, uuid, date, date),
  public.revoke_my_student_nutrition_assignment(uuid),
  public.list_my_assigned_nutrition_plans(date),
  public.list_my_student_workout_executions(uuid, date, date, integer, date, uuid),
  public.list_my_student_nutrition_logs(uuid, date, date, integer, date, uuid),
  public.list_my_student_evolution(uuid, date, date, integer, date, uuid)
from public, anon, authenticated;

grant execute on function
  public.is_organization_member(uuid, uuid),
  public.has_organization_role(uuid, text[], uuid),
  public.has_active_trainer_student_relationship(uuid, uuid, text),
  public.has_active_professional_relationship(uuid, uuid, text, text, uuid),
  public.get_current_access_context(),
  public.get_my_account_modes(),
  public.set_my_account_modes(text[]),
  public.create_trainer_student_invitation(),
  public.preview_trainer_invitation(text),
  public.accept_trainer_student_invitation(text),
  public.cancel_trainer_invitation(uuid),
  public.list_my_trainer_invitations(),
  public.list_my_trainer_student_connections(),
  public.get_my_commercial_account_context(),
  public.get_my_account_registration_context(),
  public.complete_my_initial_account_setup(text, text, text, date, text, text),
  public.set_my_personal_use_enabled(boolean),
  public.get_my_professional_client_capacity(),
  public.create_my_workout_template(text, text, jsonb, uuid),
  public.update_my_workout_template(uuid, text, text, jsonb),
  public.archive_my_workout_template(uuid),
  public.list_my_workout_templates(),
  public.list_my_manageable_workout_students(),
  public.assign_workout_template_to_student(uuid, uuid, date),
  public.revoke_my_student_workout_assignment(uuid),
  public.list_my_assigned_workout_plans(),
  public.list_my_notifications(integer, timestamptz),
  public.get_my_unread_notification_count(),
  public.mark_my_notification_read(uuid),
  public.mark_all_my_notifications_read(),
  public.create_my_nutrition_template(text, text, jsonb, uuid),
  public.update_my_nutrition_template(uuid, text, text, jsonb),
  public.archive_my_nutrition_template(uuid),
  public.list_my_nutrition_templates(),
  public.list_my_manageable_nutrition_students(),
  public.assign_nutrition_template_to_student(uuid, uuid, date, date),
  public.revoke_my_student_nutrition_assignment(uuid),
  public.list_my_assigned_nutrition_plans(date),
  public.list_my_student_workout_executions(uuid, date, date, integer, date, uuid),
  public.list_my_student_nutrition_logs(uuid, date, date, integer, date, uuid),
  public.list_my_student_evolution(uuid, date, date, integer, date, uuid)
to authenticated;

drop policy if exists student_workout_assignments_select_participant_v41b
  on public.student_workout_assignments;

create policy student_workout_assignments_select_participant_v41b
on public.student_workout_assignments
for select
to authenticated
using (
  exists (
    select 1
    from public.professional_student_relationships relationship
    where relationship.id = student_workout_assignments.relationship_id
      and (
        relationship.student_user_id = (select auth.uid())
        or (
          relationship.professional_user_id = (select auth.uid())
          and relationship.professional_type = 'trainer'
          and relationship.status = 'active'
          and relationship.scopes @> '{"manage_workout_plan": true}'::jsonb
          and (
            relationship.organization_id is null
            or exists (
              select 1
              from public.organizations organization
              join public.organization_members membership
                on membership.organization_id = organization.id
               and membership.user_id = relationship.professional_user_id
               and membership.status = 'active'
               and membership.role in ('owner', 'admin', 'trainer')
              where organization.id = relationship.organization_id
                and organization.status = 'active'
            )
          )
        )
      )
  )
);

-- The access context carries organization state so the frontend can fail closed
-- instead of deriving a manager workspace from membership state alone.
create or replace function public.get_current_access_context()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select public.get_current_access_context_v41a() || jsonb_build_object(
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organization_id', membership.organization_id,
        'role', membership.role,
        'status', membership.status,
        'organizationStatus', organization.status,
        'joined_at', membership.joined_at
      ) order by membership.created_at)
      from public.organization_members membership
      join public.organizations organization on organization.id = membership.organization_id
      where membership.user_id = auth.uid()
    ), '[]'::jsonb),
    'commercialAccount', jsonb_build_object(
      'primaryAccountType', commercial->'primaryAccountType',
      'planCode', commercial->'planCode',
      'subscriptionStatus', commercial->'subscriptionStatus',
      'activeClientLimit', commercial->'activeClientLimit',
      'personalUseEnabled', commercial->'personalUseEnabled',
      'requiresAccountTypeSelection', commercial->'requiresAccountTypeSelection'
    ),
    'registration', jsonb_build_object(
      'profileCompleted', registration->'profileCompleted',
      'ageVerified', to_jsonb((registration->>'ageStatus') = 'adult'),
      'legalAcceptancesCurrent', to_jsonb((registration->>'termsAccepted')::boolean and (registration->>'privacyAccepted')::boolean)
    )
  )
  from (select public.get_my_commercial_account_context() commercial, public.get_my_account_registration_context() registration) context;
$function$;

create or replace function public.assign_workout_template_to_student(
  target_template_id uuid,
  target_relationship_id uuid,
  target_effective_from date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  relationship_record public.professional_student_relationships;
  template_record public.professional_workout_templates;
  new_assignment public.student_workout_assignments;
  next_version integer;
begin
  perform public.assert_my_trainer_write_access_v41b();
  select * into relationship_record
  from public.professional_student_relationships
  where id = target_relationship_id
    and professional_user_id = auth.uid()
    and professional_type = 'trainer'
  for update;
  if not found then
    raise exception 'workout_relationship_not_found' using errcode = 'P0001';
  end if;
  if relationship_record.status <> 'active' then
    raise exception 'workout_relationship_inactive' using errcode = 'P0001';
  end if;
  if coalesce((relationship_record.scopes ->> 'manage_workout_plan')::boolean, false) is not true then
    raise exception 'workout_scope_required' using errcode = '42501';
  end if;

  if relationship_record.organization_id is not null then
    perform 1
    from public.organization_members membership
    join public.organizations organization
      on organization.id = membership.organization_id
    where membership.organization_id = relationship_record.organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin', 'trainer')
      and organization.status = 'active'
    for share of membership, organization;
    if not found then
      raise exception 'workout_organization_membership_required' using errcode = '42501';
    end if;
  end if;

  select * into template_record
  from public.professional_workout_templates
  where id = target_template_id
    and owner_user_id = auth.uid()
  for update;
  if not found then
    raise exception 'workout_template_not_found' using errcode = 'P0001';
  end if;
  if template_record.status <> 'active' then
    raise exception 'workout_template_archived' using errcode = 'P0001';
  end if;
  if template_record.organization_id is not null
     and template_record.organization_id is distinct from relationship_record.organization_id then
    raise exception 'workout_organization_mismatch' using errcode = '42501';
  end if;
  if template_record.organization_id is not null then
    perform 1
    from public.organization_members membership
    where membership.organization_id = template_record.organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin', 'trainer')
    for share;
    if not found then
      raise exception 'workout_organization_mismatch' using errcode = '42501';
    end if;
  end if;
  if not public.validate_workout_plan_payload_v41b(template_record.plan_data) then
    raise exception 'invalid_workout_plan_payload' using errcode = '22023';
  end if;
  select coalesce(max(assignment_version), 0) + 1 into next_version
  from public.student_workout_assignments
  where relationship_id = relationship_record.id;
  update public.student_workout_assignments
  set status = 'superseded', superseded_at = now(), updated_at = now()
  where relationship_id = relationship_record.id
    and status = 'active';
  insert into public.student_workout_assignments (
    relationship_id,
    template_id,
    assignment_version,
    title_snapshot,
    description_snapshot,
    plan_data_snapshot,
    schema_version,
    effective_from
  ) values (
    relationship_record.id,
    template_record.id,
    next_version,
    template_record.title,
    template_record.description,
    template_record.plan_data,
    template_record.schema_version,
    target_effective_from
  )
  returning * into new_assignment;
  return jsonb_build_object(
    'assignmentId', new_assignment.id,
    'relationshipId', new_assignment.relationship_id,
    'templateId', new_assignment.template_id,
    'assignmentVersion', new_assignment.assignment_version,
    'title', new_assignment.title_snapshot,
    'status', new_assignment.status,
    'assignedAt', new_assignment.assigned_at,
    'effectiveFrom', new_assignment.effective_from
  );
end;
$function$;

create or replace function public.assign_nutrition_template_to_student(
  target_template_id uuid,
  target_relationship_id uuid,
  target_effective_from date default null,
  target_effective_until date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  relationship_record public.professional_student_relationships;
  template_record public.professional_nutrition_templates;
  new_assignment public.student_nutrition_assignments;
  next_version integer;
begin
  perform public.assert_my_nutritionist_write_access_v41c();
  if target_effective_until is not null
     and target_effective_from is not null
     and target_effective_until < target_effective_from then
    raise exception 'invalid_nutrition_effective_dates' using errcode = '22023';
  end if;
  select * into relationship_record
  from public.professional_student_relationships
  where id = target_relationship_id
    and professional_user_id = auth.uid()
    and professional_type = 'nutritionist'
  for update;
  if not found then
    raise exception 'nutrition_relationship_not_found' using errcode = 'P0001';
  end if;
  if relationship_record.status <> 'active' then
    raise exception 'nutrition_relationship_inactive' using errcode = 'P0001';
  end if;
  if (relationship_record.scopes @> '{"manage_nutrition_plan": true}'::jsonb) is not true then
    raise exception 'nutrition_scope_required' using errcode = '42501';
  end if;

  if relationship_record.organization_id is not null then
    perform 1
    from public.organization_members membership
    join public.organizations organization
      on organization.id = membership.organization_id
    where membership.organization_id = relationship_record.organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin', 'nutritionist')
      and organization.status = 'active'
    for share of membership, organization;
    if not found then
      raise exception 'nutrition_organization_membership_required' using errcode = '42501';
    end if;
  end if;

  select * into template_record
  from public.professional_nutrition_templates
  where id = target_template_id
    and owner_user_id = auth.uid()
  for share;
  if not found then
    raise exception 'nutrition_template_not_found' using errcode = 'P0001';
  end if;
  if template_record.status <> 'active' then
    raise exception 'nutrition_template_archived' using errcode = 'P0001';
  end if;
  if template_record.organization_id is not null
     and template_record.organization_id is distinct from relationship_record.organization_id then
    raise exception 'nutrition_organization_mismatch' using errcode = '42501';
  end if;
  if template_record.organization_id is not null then
    perform 1
    from public.organization_members membership
    where membership.organization_id = template_record.organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.role in ('owner', 'admin', 'nutritionist')
    for share;
    if not found then
      raise exception 'nutrition_organization_mismatch' using errcode = '42501';
    end if;
  end if;
  if not public.validate_nutrition_plan_payload_v41c(template_record.plan_data) then
    raise exception 'invalid_nutrition_plan_payload' using errcode = '22023';
  end if;
  select coalesce(max(assignment_version), 0) + 1 into next_version
  from public.student_nutrition_assignments
  where relationship_id = relationship_record.id;
  update public.student_nutrition_assignments
  set status = 'superseded', superseded_at = now(), updated_at = now()
  where relationship_id = relationship_record.id
    and status = 'active';
  insert into public.student_nutrition_assignments (
    relationship_id,
    template_id,
    assignment_version,
    title_snapshot,
    description_snapshot,
    plan_data_snapshot,
    schema_version,
    effective_from,
    effective_until
  ) values (
    relationship_record.id,
    template_record.id,
    next_version,
    template_record.title,
    template_record.description,
    template_record.plan_data,
    template_record.schema_version,
    target_effective_from,
    target_effective_until
  )
  returning * into new_assignment;
  return jsonb_build_object(
    'assignmentId', new_assignment.id,
    'relationshipId', new_assignment.relationship_id,
    'templateId', new_assignment.template_id,
    'assignmentVersion', new_assignment.assignment_version,
    'title', new_assignment.title_snapshot,
    'assignmentStatus', new_assignment.status,
    'assignedAt', new_assignment.assigned_at,
    'effectiveFrom', new_assignment.effective_from,
    'effectiveUntil', new_assignment.effective_until
  );
end;
$function$;

create or replace function public.get_my_professional_monitoring_entitlement_v41d(
  target_relationship_id uuid,
  target_required_scope text,
  target_allowed_professional_types text[]
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  derived_student_user_id uuid;
  derived_professional_type text;
  derived_organization_id uuid;
  account_subscription_status text;
  account_plan_is_active boolean;
begin
  if auth.uid() is null then
    raise exception 'session_required' using errcode = '42501';
  end if;
  if target_relationship_id is null then
    raise exception 'relationship_required' using errcode = '22023';
  end if;

  if not (
    (target_required_scope = 'view_workout_executions'
      and target_allowed_professional_types = array['trainer']::text[])
    or (target_required_scope = 'view_nutrition_logs'
      and target_allowed_professional_types = array['nutritionist']::text[])
    or (target_required_scope = 'view_evolution'
      and target_allowed_professional_types = array['trainer', 'nutritionist']::text[])
  ) then
    raise exception 'invalid_professional_monitoring_scope' using errcode = '22023';
  end if;

  select
    relationship.student_user_id,
    relationship.professional_type,
    relationship.organization_id
  into
    derived_student_user_id,
    derived_professional_type,
    derived_organization_id
  from public.professional_student_relationships relationship
  where relationship.id = target_relationship_id
    and relationship.professional_user_id = auth.uid()
    and relationship.professional_type = any(target_allowed_professional_types)
    and relationship.status = 'active'
    and relationship.scopes @> pg_catalog.jsonb_build_object(target_required_scope, true);

  if not found then
    raise exception 'professional_student_read_forbidden' using errcode = '42501';
  end if;

  select account.subscription_status, plan.is_active
  into account_subscription_status, account_plan_is_active
  from public.user_commercial_accounts account
  join public.account_plan_catalog plan
    on plan.code = account.plan_code
   and plan.account_type = account.primary_account_type
  where account.user_id = auth.uid()
    and account.primary_account_type = derived_professional_type;

  if not found or account_plan_is_active is not true then
    raise exception 'professional_monitoring_plan_unavailable' using errcode = '42501';
  end if;
  if account_subscription_status is null
     or account_subscription_status not in ('active', 'trialing') then
    raise exception 'professional_monitoring_subscription_inactive' using errcode = '42501';
  end if;

  perform 1
  from public.user_account_modes account_mode
  where account_mode.user_id = auth.uid()
    and account_mode.mode = derived_professional_type;
  if not found then
    raise exception 'professional_monitoring_mode_required' using errcode = '42501';
  end if;

  if derived_organization_id is not null then
    perform 1
    from public.organization_members membership
    join public.organizations organization
      on organization.id = membership.organization_id
    where membership.organization_id = derived_organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and organization.status = 'active'
      and (
        (derived_professional_type = 'trainer'
          and membership.role in ('owner', 'admin', 'trainer'))
        or (derived_professional_type = 'nutritionist'
          and membership.role in ('owner', 'admin', 'nutritionist'))
      );
    if not found then
      raise exception 'professional_monitoring_organization_membership_required' using errcode = '42501';
    end if;
  end if;

  return derived_student_user_id;
end;
$function$;

-- Assignment readers expose authorization independently from the effective
-- date, allowing a future assignment to become read-only while offline. An
-- organization-bound prescription is eligible only while both the
-- organization and the professional membership remain active.
create or replace function public.list_my_assigned_workout_plans()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'assignmentId', assignment.id, 'relationshipId', assignment.relationship_id,
    'trainerDisplayName', coalesce(nullif(profile.display_name, ''), nullif(profile.full_name, ''), 'Treinador'),
    'organizationName', organization.name, 'organizationStatus', organization.status,
    'title', assignment.title_snapshot, 'description', assignment.description_snapshot,
    'planData', assignment.plan_data_snapshot, 'schemaVersion', assignment.schema_version,
    'assignmentVersion', assignment.assignment_version, 'status', assignment.status,
    'relationshipStatus', relationship.status, 'professionalType', relationship.professional_type,
    'canManageWorkoutPlan', (
      assignment.status = 'active'
      and relationship.status = 'active'
      and relationship.professional_type = 'trainer'
      and coalesce((relationship.scopes->>'manage_workout_plan')::boolean, false)
      and (
        relationship.organization_id is null
        or (
          organization.status = 'active'
          and exists (
            select 1 from public.organization_members membership
            where membership.organization_id = relationship.organization_id
              and membership.user_id = relationship.professional_user_id
              and membership.status = 'active'
              and membership.role in ('owner', 'admin', 'trainer')
          )
        )
      )
    ),
    'canStart', (
      assignment.status = 'active'
      and relationship.status = 'active'
      and relationship.professional_type = 'trainer'
      and coalesce((relationship.scopes->>'manage_workout_plan')::boolean, false)
      and (assignment.effective_from is null or assignment.effective_from <= current_date)
      and (
        relationship.organization_id is null
        or (
          organization.status = 'active'
          and exists (
            select 1 from public.organization_members membership
            where membership.organization_id = relationship.organization_id
              and membership.user_id = relationship.professional_user_id
              and membership.status = 'active'
              and membership.role in ('owner', 'admin', 'trainer')
          )
        )
      )
    ),
    'assignedAt', assignment.assigned_at, 'effectiveFrom', assignment.effective_from
  ) order by case assignment.status when 'active' then 0 else 1 end, assignment.assignment_version desc)
  from public.student_workout_assignments assignment
  join public.professional_student_relationships relationship on relationship.id = assignment.relationship_id
  left join public.profiles profile on profile.user_id = relationship.professional_user_id
  left join public.organizations organization on organization.id = relationship.organization_id
  where relationship.student_user_id = auth.uid()), '[]'::jsonb);
end;
$function$;

create or replace function public.list_my_assigned_nutrition_plans(target_local_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode = '42501'; end if;
  if target_local_date is null or target_local_date < current_date - 1 or target_local_date > current_date + 1 then raise exception 'invalid_local_date' using errcode = '22023'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'assignmentId', assignment.id, 'relationshipId', assignment.relationship_id,
    'nutritionistDisplayName', coalesce(nullif(profile.display_name, ''), nullif(profile.full_name, ''), 'Nutricionista'),
    'organizationName', organization.name, 'organizationStatus', organization.status,
    'title', assignment.title_snapshot, 'description', assignment.description_snapshot,
    'planData', assignment.plan_data_snapshot, 'schemaVersion', assignment.schema_version,
    'assignmentVersion', assignment.assignment_version, 'assignmentStatus', assignment.status,
    'relationshipStatus', relationship.status, 'professionalType', relationship.professional_type,
    'canManageNutritionPlan', (
      assignment.status = 'active'
      and relationship.status = 'active'
      and relationship.professional_type = 'nutritionist'
      and relationship.scopes @> '{"manage_nutrition_plan": true}'::jsonb
      and (
        relationship.organization_id is null
        or (
          organization.status = 'active'
          and exists (
            select 1 from public.organization_members membership
            where membership.organization_id = relationship.organization_id
              and membership.user_id = relationship.professional_user_id
              and membership.status = 'active'
              and membership.role in ('owner', 'admin', 'nutritionist')
          )
        )
      )
    ),
    'isCurrent', (
      assignment.status = 'active'
      and relationship.status = 'active'
      and relationship.professional_type = 'nutritionist'
      and relationship.scopes @> '{"manage_nutrition_plan": true}'::jsonb
      and (assignment.effective_from is null or assignment.effective_from <= target_local_date)
      and (assignment.effective_until is null or assignment.effective_until >= target_local_date)
      and (
        relationship.organization_id is null
        or (
          organization.status = 'active'
          and exists (
            select 1 from public.organization_members membership
            where membership.organization_id = relationship.organization_id
              and membership.user_id = relationship.professional_user_id
              and membership.status = 'active'
              and membership.role in ('owner', 'admin', 'nutritionist')
          )
        )
      )
    ),
    'assignedAt', assignment.assigned_at, 'effectiveFrom', assignment.effective_from,
    'effectiveUntil', assignment.effective_until
  ) order by case assignment.status when 'active' then 0 else 1 end, assignment.assignment_version desc)
  from public.student_nutrition_assignments assignment
  join public.professional_student_relationships relationship on relationship.id = assignment.relationship_id
  left join public.profiles profile on profile.user_id = relationship.professional_user_id
  left join public.organizations organization on organization.id = relationship.organization_id
  where relationship.student_user_id = auth.uid()), '[]'::jsonb);
end;
$function$;

-- CREATE OR REPLACE preserves existing ACLs, but reassert the intended contract
-- after the definitions so this migration remains safe under future refactors.
revoke all on function
  public.get_my_professional_monitoring_entitlement_v41d(uuid, text, text[])
from public, anon, authenticated;

revoke all on function
  public.assign_workout_template_to_student(uuid, uuid, date),
  public.assign_nutrition_template_to_student(uuid, uuid, date, date),
  public.get_current_access_context(),
  public.list_my_assigned_workout_plans(),
  public.list_my_assigned_nutrition_plans(date)
from public, anon, authenticated;

grant execute on function
  public.assign_workout_template_to_student(uuid, uuid, date),
  public.assign_nutrition_template_to_student(uuid, uuid, date, date),
  public.get_current_access_context(),
  public.list_my_assigned_workout_plans(),
  public.list_my_assigned_nutrition_plans(date)
to authenticated;

-- Transactional catalog assertions: no persistent test objects are created.
do $v42a_assert$
declare
  sensitive_table text;
  definition text;
begin
  foreach sensitive_table in array array[
    'public.account_plan_catalog',
    'public.organization_members',
    'public.organizations',
    'public.platform_user_roles',
    'public.professional_nutrition_templates',
    'public.professional_student_relationships',
    'public.professional_workout_templates',
    'public.student_nutrition_assignments',
    'public.student_workout_assignments',
    'public.trainer_student_relationships',
    'public.user_account_modes',
    'public.user_commercial_accounts',
    'public.user_identity_details',
    'public.user_legal_acceptances',
    'public.user_notifications'
  ] loop
    if not pg_catalog.has_table_privilege('authenticated', sensitive_table, 'SELECT')
       or pg_catalog.has_table_privilege('authenticated', sensitive_table, 'INSERT')
       or pg_catalog.has_table_privilege('authenticated', sensitive_table, 'UPDATE')
       or pg_catalog.has_table_privilege('authenticated', sensitive_table, 'DELETE')
       or pg_catalog.has_table_privilege('anon', sensitive_table, 'SELECT,INSERT,UPDATE,DELETE') then
      raise exception 'V4.2A table ACL assertion failed for %', sensitive_table;
    end if;
  end loop;

  if pg_catalog.has_table_privilege(
    'authenticated',
    'public.trainer_student_invitations',
    'SELECT,INSERT,UPDATE,DELETE'
  ) or pg_catalog.has_table_privilege(
    'anon',
    'public.trainer_student_invitations',
    'SELECT,INSERT,UPDATE,DELETE'
  ) then
    raise exception 'V4.2A invitation table ACL assertion failed';
  end if;

  if pg_catalog.has_function_privilege(
      'authenticated',
      'public.create_user_notification_v41c(uuid,uuid,text,text,text,text,uuid,text,jsonb)',
      'EXECUTE'
    )
    or pg_catalog.has_function_privilege(
      'anon',
      'public.get_my_professional_monitoring_entitlement_v41d(uuid,text,text[])',
      'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated',
      'public.assign_workout_template_to_student(uuid,uuid,date)',
      'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated',
      'public.assign_nutrition_template_to_student(uuid,uuid,date,date)',
      'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated',
      'public.get_current_access_context()',
      'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated',
      'public.list_my_assigned_workout_plans()',
      'EXECUTE'
    )
    or not pg_catalog.has_function_privilege(
      'authenticated',
      'public.list_my_assigned_nutrition_plans(date)',
      'EXECUTE'
    ) then
    raise exception 'V4.2A function ACL assertion failed';
  end if;

  select pg_catalog.regexp_replace(pg_catalog.lower(policy.qual), '[[:space:]]+', '', 'g')
  into definition
  from pg_catalog.pg_policies policy
  where policy.schemaname = 'public'
    and policy.tablename = 'student_workout_assignments'
    and policy.policyname = 'student_workout_assignments_select_participant_v41b';

  if definition is null
     or definition not like '%relationship.student_user_id=%auth.uid()%'
     or definition not like '%relationship.professional_user_id=%auth.uid()%'
     or definition not like '%relationship.professional_type=''trainer''%'
     or definition not like '%relationship.status=''active''%'
     or definition not like '%manage_workout_plan%'
     or definition not like '%organization.status=''active''%'
     or definition not like '%membership.status=''active''%'
     or definition not like '%membership.rolein(''owner'',''admin'',''trainer'')%' then
    raise exception 'V4.2A workout assignment policy assertion failed';
  end if;

  select pg_catalog.regexp_replace(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      pg_catalog.to_regprocedure('public.get_current_access_context()')
    )),
    '[[:space:]]+',
    '',
    'g'
  ) into definition;
  if definition not like '%''organizationstatus'',organization.status%'
     or definition not like '%membership.user_id=auth.uid()%' then
    raise exception 'V4.2A access context organization assertion failed';
  end if;

  select pg_catalog.regexp_replace(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      pg_catalog.to_regprocedure('public.list_my_assigned_workout_plans()')
    )),
    '[[:space:]]+',
    '',
    'g'
  ) into definition;
  if definition not like '%''canmanageworkoutplan''%'
     or definition not like '%organization.status=''active''%'
     or definition not like '%membership.status=''active''%'
     or definition not like '%assignment.effective_from<=current_date%' then
    raise exception 'V4.2A workout reader eligibility assertion failed';
  end if;

  select pg_catalog.regexp_replace(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      pg_catalog.to_regprocedure('public.list_my_assigned_nutrition_plans(date)')
    )),
    '[[:space:]]+',
    '',
    'g'
  ) into definition;
  if definition not like '%''canmanagenutritionplan''%'
     or definition not like '%organization.status=''active''%'
     or definition not like '%membership.status=''active''%'
     or definition not like '%assignment.effective_from<=target_local_date%' then
    raise exception 'V4.2A nutrition reader eligibility assertion failed';
  end if;

  select pg_catalog.regexp_replace(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      pg_catalog.to_regprocedure(
        'public.assign_workout_template_to_student(uuid,uuid,date)'
      )
    )),
    '[[:space:]]+',
    '',
    'g'
  ) into definition;
  if definition not like '%relationship_record.organization_idisnotnull%'
     or definition not like '%membership.organization_id=relationship_record.organization_id%'
     or definition not like '%membership.status=''active''%'
     or definition not like '%membership.rolein(''owner'',''admin'',''trainer'')%'
     or definition not like '%organization.status=''active''%'
     or definition not like '%workout_organization_membership_required%' then
    raise exception 'V4.2A workout organization guard assertion failed';
  end if;

  select pg_catalog.regexp_replace(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      pg_catalog.to_regprocedure(
        'public.assign_nutrition_template_to_student(uuid,uuid,date,date)'
      )
    )),
    '[[:space:]]+',
    '',
    'g'
  ) into definition;
  if definition not like '%relationship_record.organization_idisnotnull%'
     or definition not like '%membership.organization_id=relationship_record.organization_id%'
     or definition not like '%membership.status=''active''%'
     or definition not like '%membership.rolein(''owner'',''admin'',''nutritionist'')%'
     or definition not like '%organization.status=''active''%'
     or definition not like '%nutrition_organization_membership_required%' then
    raise exception 'V4.2A nutrition organization guard assertion failed';
  end if;

  select pg_catalog.regexp_replace(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      pg_catalog.to_regprocedure(
        'public.get_my_professional_monitoring_entitlement_v41d(uuid,text,text[])'
      )
    )),
    '[[:space:]]+',
    '',
    'g'
  ) into definition;
  if definition not like '%membership.organization_id=derived_organization_id%'
     or definition not like '%membership.status=''active''%'
     or definition not like '%organization.status=''active''%'
     or definition not like '%professional_monitoring_organization_membership_required%' then
    raise exception 'V4.2A monitoring organization guard assertion failed';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_default_acl defaults
    left join pg_catalog.pg_namespace namespace
      on namespace.oid = defaults.defaclnamespace
    cross join lateral pg_catalog.aclexplode(defaults.defaclacl) privilege
    where pg_catalog.pg_get_userbyid(defaults.defaclrole) = 'postgres'
      and (
        defaults.defaclnamespace = 0
        or namespace.nspname = 'public'
      )
      and defaults.defaclobjtype in ('r', 'S', 'f')
      and (
        privilege.grantee = 0
        or privilege.grantee = pg_catalog.to_regrole('anon')
        or privilege.grantee = pg_catalog.to_regrole('authenticated')
      )
  ) then
    raise exception 'V4.2A default privilege assertion failed';
  end if;
end;
$v42a_assert$;

commit;
