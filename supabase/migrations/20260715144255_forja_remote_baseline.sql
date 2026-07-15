SET check_function_bodies = false;
DROP EXTENSION pg_net;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, USAGE ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON ROUTINES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, USAGE ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON ROUTINES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, USAGE ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON ROUTINES TO service_role;
CREATE FUNCTION public.accept_trainer_student_invitation(invite_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_user_id uuid := auth.uid();
  normalized_code text;
  code_hash text;
  invitation record;
  relationship_id uuid;
  relationship_permissions jsonb;
  safe_permissions jsonb := pg_catalog.jsonb_build_object(
    'view_workouts', true,
    'assign_workouts', true,
    'view_executions', true,
    'view_evolution', true,
    'view_nutrition', false
  );
begin
  if current_user_id is null then
    raise exception 'Sessão indisponível.' using errcode = '42501';
  end if;

  normalized_code := public.normalize_invitation_code(invite_code);
  if pg_catalog.char_length(normalized_code) <> 25 then
    return pg_catalog.jsonb_build_object('accepted', false, 'message', 'Este código não é válido ou não está mais disponível.');
  end if;

  code_hash := pg_catalog.encode(extensions.digest(normalized_code, 'sha256'), 'hex');
  select * into invitation
  from public.trainer_student_invitations
  where invite_code_hash = code_hash
  for update;

  if not found or invitation.status <> 'pending' then
    return pg_catalog.jsonb_build_object('accepted', false, 'message', 'Este código não é válido ou não está mais disponível.');
  end if;
  if invitation.expires_at <= now() then
    update public.trainer_student_invitations
    set status = 'expired', updated_at = now()
    where id = invitation.id;
    return pg_catalog.jsonb_build_object('accepted', false, 'message', 'Este convite não está mais disponível.');
  end if;
  if invitation.trainer_user_id = current_user_id then
    return pg_catalog.jsonb_build_object('accepted', false, 'message', 'Você não pode aceitar um convite criado pela sua própria conta.');
  end if;

  insert into public.trainer_student_relationships (
    trainer_user_id, student_user_id, organization_id, status, permissions, requested_by, accepted_at
  ) values (
    invitation.trainer_user_id, current_user_id, null, 'active', safe_permissions, invitation.trainer_user_id, now()
  )
  on conflict (trainer_user_id, student_user_id) where organization_id is null
  do update set
    status = 'active',
    permissions = excluded.permissions,
    accepted_at = case
      when public.trainer_student_relationships.status = 'active' then public.trainer_student_relationships.accepted_at
      else excluded.accepted_at
    end,
    revoked_at = null,
    updated_at = now()
  returning id, permissions into relationship_id, relationship_permissions;

  insert into public.user_account_modes(user_id, mode)
  values (current_user_id, 'student')
  on conflict (user_id, mode) do update set updated_at = now();

  update public.trainer_student_invitations
  set status = 'accepted', accepted_by_user_id = current_user_id, accepted_at = now(), updated_at = now()
  where id = invitation.id;

  return pg_catalog.jsonb_build_object(
    'accepted', true,
    'relationship_id', relationship_id,
    'status', 'active',
    'permissions', relationship_permissions
  );
end;
$function$;
GRANT ALL ON FUNCTION public.accept_trainer_student_invitation(text) TO authenticated;
GRANT ALL ON FUNCTION public.accept_trainer_student_invitation(text) TO service_role;
CREATE FUNCTION public.apply_default_professional_relationship_scopes_v41e1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  new.scopes := public.default_professional_relationship_scopes_v41e1(new.professional_type);
  return new;
end;
$function$;
GRANT ALL ON FUNCTION public.apply_default_professional_relationship_scopes_v41e1() TO service_role;
CREATE FUNCTION public.archive_my_nutrition_template(target_template_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare template_record public.professional_nutrition_templates;
begin
  perform public.assert_my_nutritionist_identity_v41c();
  update public.professional_nutrition_templates set status='archived',updated_at=now() where id=target_template_id and owner_user_id=auth.uid() returning * into template_record;
  if not found then raise exception 'nutrition_template_not_found' using errcode='P0001'; end if;
  return jsonb_build_object('id',template_record.id,'status',template_record.status,'updatedAt',template_record.updated_at);
end; $function$;
GRANT ALL ON FUNCTION public.archive_my_nutrition_template(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.archive_my_nutrition_template(uuid) TO service_role;
CREATE FUNCTION public.archive_my_workout_template(target_template_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare template_record public.professional_workout_templates;
begin
  perform public.assert_my_trainer_identity_v41b();
  update public.professional_workout_templates set status='archived',updated_at=now() where id=target_template_id and owner_user_id=auth.uid() returning * into template_record;
  if not found then raise exception 'workout_template_not_found' using errcode='P0001'; end if;
  return jsonb_build_object('id',template_record.id,'status',template_record.status,'updatedAt',template_record.updated_at);
end;
$function$;
GRANT ALL ON FUNCTION public.archive_my_workout_template(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.archive_my_workout_template(uuid) TO service_role;
CREATE FUNCTION public.assert_my_nutritionist_identity_v41c()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  if not exists(select 1 from public.user_commercial_accounts account where account.user_id=auth.uid() and account.primary_account_type='nutritionist')
    or not exists(select 1 from public.user_account_modes mode where mode.user_id=auth.uid() and mode.mode='nutritionist') then raise exception 'nutritionist_account_required' using errcode='42501'; end if;
  if not exists(select 1 from public.user_commercial_accounts account join public.account_plan_catalog plan on plan.code=account.plan_code and plan.account_type=account.primary_account_type where account.user_id=auth.uid() and account.primary_account_type='nutritionist') then raise exception 'nutritionist_plan_unavailable' using errcode='42501'; end if;
end;
$function$;
GRANT ALL ON FUNCTION public.assert_my_nutritionist_identity_v41c() TO service_role;
CREATE FUNCTION public.assert_my_nutritionist_write_access_v41c()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare account_subscription_status text; account_plan_is_active boolean;
begin
  perform public.assert_my_nutritionist_identity_v41c();
  select account.subscription_status,plan.is_active into account_subscription_status,account_plan_is_active
  from public.user_commercial_accounts account join public.account_plan_catalog plan on plan.code=account.plan_code and plan.account_type=account.primary_account_type
  where account.user_id=auth.uid() and account.primary_account_type='nutritionist';
  if not found or account_plan_is_active is not true then raise exception 'nutritionist_plan_unavailable' using errcode='42501'; end if;
  if account_subscription_status is null or account_subscription_status not in ('active','trialing') then raise exception 'nutritionist_subscription_inactive' using errcode='42501'; end if;
end;
$function$;
GRANT ALL ON FUNCTION public.assert_my_nutritionist_write_access_v41c() TO service_role;
CREATE FUNCTION public.assert_my_trainer_identity_v41b()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  if not exists(select 1 from public.user_commercial_accounts account where account.user_id=auth.uid() and account.primary_account_type='trainer')
    or not exists(select 1 from public.user_account_modes mode where mode.user_id=auth.uid() and mode.mode='trainer') then
    raise exception 'trainer_account_required' using errcode='42501';
  end if;
  if not exists(select 1 from public.user_commercial_accounts account join public.account_plan_catalog plan on plan.code=account.plan_code and plan.account_type=account.primary_account_type where account.user_id=auth.uid() and account.primary_account_type='trainer') then raise exception 'trainer_plan_unavailable' using errcode='42501'; end if;
end;
$function$;
GRANT ALL ON FUNCTION public.assert_my_trainer_identity_v41b() TO service_role;
CREATE FUNCTION public.assert_my_trainer_write_access_v41b()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  account_subscription_status text;
  account_plan_is_active boolean;
begin
  perform public.assert_my_trainer_identity_v41b();
  select account.subscription_status,plan.is_active
  into account_subscription_status,account_plan_is_active
  from public.user_commercial_accounts account
  join public.account_plan_catalog plan on plan.code=account.plan_code and plan.account_type=account.primary_account_type
  where account.user_id=auth.uid() and account.primary_account_type='trainer';
  if not found or account_plan_is_active is not true then raise exception 'trainer_plan_unavailable' using errcode='42501'; end if;
  if account_subscription_status is null or account_subscription_status not in ('active','trialing') then raise exception 'trainer_subscription_inactive' using errcode='42501'; end if;
end;
$function$;
GRANT ALL ON FUNCTION public.assert_my_trainer_write_access_v41b() TO service_role;
CREATE FUNCTION public.assert_professional_client_capacity_v41a2(target_professional_id uuid, target_professional_type text, target_student_id uuid, relationship_id_to_exclude uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  account_record record;
  plan_record record;
  active_count bigint;
begin
  if target_professional_id is null or target_student_id is null
     or target_professional_id=target_student_id
     or target_professional_type not in ('trainer','nutritionist') then
    raise exception 'invalid_professional_capacity_parameters' using errcode='22023';
  end if;

  select account.primary_account_type,account.plan_code,account.subscription_status
    into account_record
  from public.user_commercial_accounts account
  where account.user_id=target_professional_id
  for update;
  if not found or account_record.primary_account_type is null or account_record.plan_code is null then
    raise exception 'professional_account_required' using errcode='P0001';
  end if;
  if account_record.primary_account_type<>target_professional_type then
    raise exception 'professional_account_type_mismatch' using errcode='P0001';
  end if;
  if account_record.subscription_status not in ('active','trialing') then
    raise exception 'professional_subscription_inactive' using errcode='P0001';
  end if;

  select plan.active_client_limit,plan.is_active
    into plan_record
  from public.account_plan_catalog plan
  where plan.code=account_record.plan_code
    and plan.account_type=target_professional_type
    and plan.is_active=true;
  if not found then
    raise exception 'professional_plan_unavailable' using errcode='P0001';
  end if;

  -- Another active organization relationship for this student already occupies the slot.
  if exists(
    select 1 from public.professional_student_relationships relationship
    where relationship.professional_user_id=target_professional_id
      and relationship.professional_type=target_professional_type
      and relationship.student_user_id=target_student_id
      and relationship.status='active'
      and (relationship_id_to_exclude is null or relationship.id<>relationship_id_to_exclude)
  ) then return; end if;

  if plan_record.active_client_limit is null then return; end if;
  active_count:=public.get_professional_active_client_count_v41a2(
    target_professional_id,target_professional_type,relationship_id_to_exclude
  );
  if active_count>=plan_record.active_client_limit then
    raise exception 'professional_client_limit_reached' using errcode='P0001';
  end if;
end;
$function$;
GRANT ALL ON FUNCTION public.assert_professional_client_capacity_v41a2(uuid, text, uuid, uuid) TO service_role;
CREATE FUNCTION public.assert_professional_monitoring_page_v41d(target_start_date date, target_end_date date, target_limit integer, target_cursor_date date, target_cursor_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  if target_start_date is null or target_end_date is null then
    raise exception 'monitoring_date_range_required' using errcode = '22023';
  end if;
  if target_start_date > target_end_date then
    raise exception 'invalid_monitoring_date_range' using errcode = '22023';
  end if;
  if target_end_date - target_start_date > 365 then
    raise exception 'monitoring_date_range_exceeds_366_days' using errcode = '22023';
  end if;
  if target_limit is null or target_limit < 1 or target_limit > 100 then
    raise exception 'monitoring_limit_must_be_between_1_and_100' using errcode = '22023';
  end if;
  if (target_cursor_date is null) <> (target_cursor_id is null) then
    raise exception 'monitoring_cursor_is_incomplete' using errcode = '22023';
  end if;
  if target_cursor_date is not null
     and (target_cursor_date < target_start_date or target_cursor_date > target_end_date) then
    raise exception 'monitoring_cursor_outside_date_range' using errcode = '22023';
  end if;
end;
$function$;
GRANT ALL ON FUNCTION public.assert_professional_monitoring_page_v41d(date, date, integer, date, uuid) TO service_role;
CREATE FUNCTION public.assign_nutrition_template_to_student(target_template_id uuid, target_relationship_id uuid, target_effective_from date DEFAULT NULL::date, target_effective_until date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare relationship_record public.professional_student_relationships; template_record public.professional_nutrition_templates; new_assignment public.student_nutrition_assignments; next_version integer;
begin
  perform public.assert_my_nutritionist_write_access_v41c();
  if target_effective_until is not null and target_effective_from is not null and target_effective_until<target_effective_from then raise exception 'invalid_nutrition_effective_dates' using errcode='22023'; end if;
  select * into relationship_record from public.professional_student_relationships where id=target_relationship_id and professional_user_id=auth.uid() and professional_type='nutritionist' for update;
  if not found then raise exception 'nutrition_relationship_not_found' using errcode='P0001'; end if;
  if relationship_record.status<>'active' then raise exception 'nutrition_relationship_inactive' using errcode='P0001'; end if;
  if (relationship_record.scopes @> '{"manage_nutrition_plan": true}'::jsonb) is not true then raise exception 'nutrition_scope_required' using errcode='42501'; end if;
  select * into template_record from public.professional_nutrition_templates where id=target_template_id and owner_user_id=auth.uid() for share;
  if not found then raise exception 'nutrition_template_not_found' using errcode='P0001'; end if;
  if template_record.status<>'active' then raise exception 'nutrition_template_archived' using errcode='P0001'; end if;
  if template_record.organization_id is not null and template_record.organization_id is distinct from relationship_record.organization_id then raise exception 'nutrition_organization_mismatch' using errcode='42501'; end if;
  if template_record.organization_id is not null then
    perform 1 from public.organization_members membership where membership.organization_id=template_record.organization_id and membership.user_id=auth.uid() and membership.status='active' and membership.role in ('owner','admin','nutritionist') for share;
    if not found then raise exception 'nutrition_organization_mismatch' using errcode='42501'; end if;
  end if;
  if not public.validate_nutrition_plan_payload_v41c(template_record.plan_data) then raise exception 'invalid_nutrition_plan_payload' using errcode='22023'; end if;
  select coalesce(max(assignment_version),0)+1 into next_version from public.student_nutrition_assignments where relationship_id=relationship_record.id;
  update public.student_nutrition_assignments set status='superseded',superseded_at=now(),updated_at=now() where relationship_id=relationship_record.id and status='active';
  insert into public.student_nutrition_assignments(relationship_id,template_id,assignment_version,title_snapshot,description_snapshot,plan_data_snapshot,schema_version,effective_from,effective_until)
  values(relationship_record.id,template_record.id,next_version,template_record.title,template_record.description,template_record.plan_data,template_record.schema_version,target_effective_from,target_effective_until) returning * into new_assignment;
  return jsonb_build_object('assignmentId',new_assignment.id,'relationshipId',new_assignment.relationship_id,'templateId',new_assignment.template_id,'assignmentVersion',new_assignment.assignment_version,'title',new_assignment.title_snapshot,'assignmentStatus',new_assignment.status,'assignedAt',new_assignment.assigned_at,'effectiveFrom',new_assignment.effective_from,'effectiveUntil',new_assignment.effective_until);
end; $function$;
GRANT ALL ON FUNCTION public.assign_nutrition_template_to_student(uuid, uuid, date, date) TO authenticated;
GRANT ALL ON FUNCTION public.assign_nutrition_template_to_student(uuid, uuid, date, date) TO service_role;
CREATE FUNCTION public.assign_workout_template_to_student(target_template_id uuid, target_relationship_id uuid, target_effective_from date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare relationship_record public.professional_student_relationships; template_record public.professional_workout_templates; new_assignment public.student_workout_assignments; next_version integer;
begin
  perform public.assert_my_trainer_write_access_v41b();
  select * into relationship_record from public.professional_student_relationships where id=target_relationship_id and professional_user_id=auth.uid() and professional_type='trainer' for update;
  if not found then raise exception 'workout_relationship_not_found' using errcode='P0001'; end if;
  if relationship_record.status<>'active' then raise exception 'workout_relationship_inactive' using errcode='P0001'; end if;
  if coalesce((relationship_record.scopes->>'manage_workout_plan')::boolean,false) is not true then raise exception 'workout_scope_required' using errcode='42501'; end if;
  select * into template_record from public.professional_workout_templates where id=target_template_id and owner_user_id=auth.uid() for update;
  if not found then raise exception 'workout_template_not_found' using errcode='P0001'; end if;
  if template_record.status<>'active' then raise exception 'workout_template_archived' using errcode='P0001'; end if;
  if template_record.organization_id is not null and template_record.organization_id is distinct from relationship_record.organization_id then raise exception 'workout_organization_mismatch' using errcode='42501'; end if;
  if template_record.organization_id is not null then
    perform 1 from public.organization_members membership
    where membership.organization_id=template_record.organization_id and membership.user_id=auth.uid()
      and membership.status='active' and membership.role in ('owner','admin','trainer')
    for share;
    if not found then raise exception 'workout_organization_mismatch' using errcode='42501'; end if;
  end if;
  if not public.validate_workout_plan_payload_v41b(template_record.plan_data) then raise exception 'invalid_workout_plan_payload' using errcode='22023'; end if;
  select coalesce(max(assignment_version),0)+1 into next_version from public.student_workout_assignments where relationship_id=relationship_record.id;
  update public.student_workout_assignments set status='superseded',superseded_at=now(),updated_at=now() where relationship_id=relationship_record.id and status='active';
  insert into public.student_workout_assignments(relationship_id,template_id,assignment_version,title_snapshot,description_snapshot,plan_data_snapshot,schema_version,effective_from)
  values(relationship_record.id,template_record.id,next_version,template_record.title,template_record.description,template_record.plan_data,template_record.schema_version,target_effective_from)
  returning * into new_assignment;
  return jsonb_build_object('assignmentId',new_assignment.id,'relationshipId',new_assignment.relationship_id,'templateId',new_assignment.template_id,'assignmentVersion',new_assignment.assignment_version,'title',new_assignment.title_snapshot,'status',new_assignment.status,'assignedAt',new_assignment.assigned_at,'effectiveFrom',new_assignment.effective_from);
end;
$function$;
GRANT ALL ON FUNCTION public.assign_workout_template_to_student(uuid, uuid, date) TO authenticated;
GRANT ALL ON FUNCTION public.assign_workout_template_to_student(uuid, uuid, date) TO service_role;
CREATE FUNCTION public.cancel_trainer_invitation(invitation_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'Sessão indisponível.' using errcode='42501'; end if;
  update public.trainer_student_invitations set status='cancelled',cancelled_at=now(),updated_at=now()
  where id=invitation_id and trainer_user_id=auth.uid() and status='pending' and expires_at>now();
  return found;
end;
$function$;
GRANT ALL ON FUNCTION public.cancel_trainer_invitation(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_trainer_invitation(uuid) TO service_role;
CREATE FUNCTION public.complete_my_initial_account_setup(target_account_type text, target_full_name text, target_display_name text, target_birth_date date, accepted_terms_version text, accepted_privacy_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_user_id uuid := auth.uid();
  normalized_type text := pg_catalog.lower(pg_catalog.btrim(coalesce(target_account_type, '')));
  normalized_full_name text := pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(target_full_name, '')), '[[:space:]]+', ' ', 'g');
  normalized_display_name text := pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(target_display_name, '')), '[[:space:]]+', ' ', 'g');
  calculated_age integer;
  selected_plan_code text;
  existing_type text;
  existing_birth_date date;
  existing_profile_birth_date date;
begin
  if current_user_id is null then raise exception 'Sessão indisponível.' using errcode='42501'; end if;
  if normalized_type not in ('individual','trainer','nutritionist') then raise exception 'Tipo principal inválido.' using errcode='22023'; end if;
  if char_length(normalized_full_name) not between 2 and 80 or normalized_full_name !~ '[[:alpha:]]' then raise exception 'Nome completo inválido.' using errcode='22023'; end if;
  if char_length(normalized_display_name) > 40 then raise exception 'Nome de exibição inválido.' using errcode='22023'; end if;
  if normalized_display_name = '' then normalized_display_name := split_part(normalized_full_name, ' ', 1); end if;
  if target_birth_date is null or target_birth_date > current_date then raise exception 'Data de nascimento inválida.' using errcode='22023'; end if;
  if target_birth_date < (current_date - interval '120 years')::date then raise exception 'Data de nascimento inválida.' using errcode='22023'; end if;
  calculated_age := extract(year from age(current_date, target_birth_date));
  if calculated_age < 18 then raise exception 'O cadastro de menores ainda não está disponível nesta versão do Forja.' using errcode='22023'; end if;
  if accepted_terms_version <> 'terms-2026-01' or accepted_privacy_version <> 'privacy-2026-01' then raise exception 'Aceites legais desatualizados.' using errcode='22023'; end if;
  selected_plan_code := case normalized_type when 'individual' then 'individual_free' when 'trainer' then 'trainer_free' when 'nutritionist' then 'nutritionist_free' end;

  insert into public.user_commercial_accounts(user_id) values(current_user_id) on conflict(user_id) do nothing;
  select primary_account_type into existing_type from public.user_commercial_accounts where user_id=current_user_id for update;
  select birth_date into existing_profile_birth_date from public.profiles where user_id=current_user_id for update;
  if existing_profile_birth_date is not null and existing_profile_birth_date <> target_birth_date then raise exception 'A data de nascimento ja foi confirmada.' using errcode='42501'; end if;
  if existing_type is not null and existing_type <> normalized_type then raise exception 'O tipo principal já foi definido e não pode ser trocado diretamente.' using errcode='42501'; end if;
  select birth_date into existing_birth_date from public.user_identity_details where user_id=current_user_id for update;
  if existing_birth_date is not null and existing_birth_date <> target_birth_date then raise exception 'A data de nascimento já foi confirmada.' using errcode='42501'; end if;

  insert into public.user_identity_details(user_id,birth_date,age_status,age_verified_at,country_code)
  values(current_user_id,target_birth_date,'adult',now(),'BR')
  on conflict(user_id) do update set birth_date=excluded.birth_date,age_status='adult',age_verified_at=coalesce(public.user_identity_details.age_verified_at,now()),updated_at=now();

  insert into public.profiles(user_id,full_name,display_name,birth_date,locale,updated_at)
  values(current_user_id,normalized_full_name,normalized_display_name,target_birth_date,'pt-BR',now())
  on conflict(user_id) do update set full_name=excluded.full_name,display_name=excluded.display_name,birth_date=coalesce(public.profiles.birth_date,excluded.birth_date),locale=coalesce(public.profiles.locale,'pt-BR'),updated_at=now();

  update public.user_commercial_accounts set primary_account_type=normalized_type,plan_code=selected_plan_code,account_type_selected_at=coalesce(account_type_selected_at,now()),updated_at=now() where user_id=current_user_id;

  insert into public.user_legal_acceptances(user_id,document_type,document_version)
  values(current_user_id,'terms',accepted_terms_version),(current_user_id,'privacy',accepted_privacy_version)
  on conflict(user_id,document_type,document_version) do nothing;

  insert into public.user_account_modes(user_id,mode) values(current_user_id,normalized_type)
  on conflict(user_id,mode) do update set updated_at=now();
  if normalized_type in ('trainer','nutritionist') then
    insert into public.user_account_modes(user_id,mode) values(current_user_id,'individual')
    on conflict(user_id,mode) do update set updated_at=now();
  end if;

  return public.get_my_account_registration_context();
end;
$function$;
GRANT ALL ON FUNCTION public.complete_my_initial_account_setup(text, text, text, date, text, text) TO authenticated;
GRANT ALL ON FUNCTION public.complete_my_initial_account_setup(text, text, text, date, text, text) TO service_role;
CREATE FUNCTION public.create_my_nutrition_template(target_title text, target_description text, target_plan_data jsonb, target_organization_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare template_record public.professional_nutrition_templates; normalized_title text; normalized_description text;
begin
  perform public.assert_my_nutritionist_write_access_v41c();
  normalized_title:=regexp_replace(btrim(coalesce(target_title,'')),'[[:space:]]+',' ','g');
  normalized_description:=nullif(regexp_replace(btrim(coalesce(target_description,'')),'[[:space:]]+',' ','g'),'');
  if char_length(normalized_title) not between 2 and 120 or not public.nutrition_text_is_safe_v41c(normalized_title,120)
    or (normalized_description is not null and not public.nutrition_text_is_safe_v41c(normalized_description,2000)) then raise exception 'invalid_nutrition_template_text' using errcode='22023'; end if;
  if not public.validate_nutrition_plan_payload_v41c(target_plan_data) then raise exception 'invalid_nutrition_plan_payload' using errcode='22023'; end if;
  if target_organization_id is not null and not exists(select 1 from public.organization_members membership where membership.organization_id=target_organization_id and membership.user_id=auth.uid() and membership.status='active' and membership.role in ('owner','admin','nutritionist')) then raise exception 'nutrition_organization_mismatch' using errcode='42501'; end if;
  insert into public.professional_nutrition_templates(owner_user_id,organization_id,title,description,plan_data,schema_version)
  values(auth.uid(),target_organization_id,normalized_title,normalized_description,target_plan_data,(target_plan_data->>'schemaVersion')::integer) returning * into template_record;
  return jsonb_build_object('id',template_record.id,'title',template_record.title,'description',template_record.description,'planData',template_record.plan_data,'schemaVersion',template_record.schema_version,'status',template_record.status,'organizationId',template_record.organization_id,'createdAt',template_record.created_at,'updatedAt',template_record.updated_at);
end; $function$;
GRANT ALL ON FUNCTION public.create_my_nutrition_template(text, text, jsonb, uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_my_nutrition_template(text, text, jsonb, uuid) TO service_role;
CREATE FUNCTION public.create_my_workout_template(target_title text, target_description text, target_plan_data jsonb, target_organization_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare template_record public.professional_workout_templates;
begin
  perform public.assert_my_trainer_write_access_v41b();
  if char_length(btrim(coalesce(target_title,''))) not between 2 and 120 or char_length(coalesce(target_description,''))>2000 then raise exception 'invalid_workout_template_text' using errcode='22023'; end if;
  if not public.validate_workout_plan_payload_v41b(target_plan_data) then raise exception 'invalid_workout_plan_payload' using errcode='22023'; end if;
  if target_organization_id is not null and not exists(select 1 from public.organization_members membership where membership.organization_id=target_organization_id and membership.user_id=auth.uid() and membership.status='active' and membership.role in ('owner','admin','trainer')) then raise exception 'workout_organization_mismatch' using errcode='42501'; end if;
  insert into public.professional_workout_templates(owner_user_id,organization_id,title,description,plan_data,schema_version)
  values(auth.uid(),target_organization_id,btrim(target_title),nullif(btrim(coalesce(target_description,'')),''),target_plan_data,(target_plan_data->>'schemaVersion')::integer)
  returning * into template_record;
  return jsonb_build_object('id',template_record.id,'title',template_record.title,'description',template_record.description,'planData',template_record.plan_data,'schemaVersion',template_record.schema_version,'status',template_record.status,'organizationId',template_record.organization_id,'createdAt',template_record.created_at,'updatedAt',template_record.updated_at);
end;
$function$;
GRANT ALL ON FUNCTION public.create_my_workout_template(text, text, jsonb, uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_my_workout_template(text, text, jsonb, uuid) TO service_role;
CREATE FUNCTION public.create_trainer_student_invitation()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_user_id uuid := auth.uid(); raw_token text; full_code text; normalized_code text;
  code_hash text; code_prefix text; invitation_id uuid; invitation_expires_at timestamptz;
begin
  if current_user_id is null then raise exception 'Sessão indisponível.' using errcode = '42501'; end if;
  perform 1 from public.user_account_modes
  where user_id=current_user_id and mode='trainer'
  for update;
  if not found then
    raise exception 'Ative o modo Treinador no seu perfil para gerar convites.' using errcode = '42501';
  end if;
  update public.trainer_student_invitations set status='expired', updated_at=now()
  where trainer_user_id=current_user_id and status='pending' and expires_at <= now();
  if (select count(*) from public.trainer_student_invitations where trainer_user_id=current_user_id and status='pending' and expires_at>now()) >= 20 then
    raise exception 'Você atingiu o limite de convites ativos.' using errcode = '54000';
  end if;
  loop
    raw_token := pg_catalog.upper(pg_catalog.encode(extensions.gen_random_bytes(10), 'hex'));
    full_code := 'FORJA-' || substring(raw_token,1,4) || '-' || substring(raw_token,5,4) || '-' || substring(raw_token,9,4) || '-' || substring(raw_token,13,4) || '-' || substring(raw_token,17,4);
    normalized_code := public.normalize_invitation_code(full_code);
    code_hash := pg_catalog.encode(extensions.digest(normalized_code, 'sha256'), 'hex');
    exit when not exists (select 1 from public.trainer_student_invitations where invite_code_hash=code_hash);
  end loop;
  code_prefix := 'FORJA-' || substring(raw_token,1,4);
  invitation_expires_at := now() + interval '7 days';
  insert into public.trainer_student_invitations (trainer_user_id,invite_code_hash,invite_code_prefix,expires_at)
  values (current_user_id,code_hash,code_prefix,invitation_expires_at) returning id into invitation_id;
  return jsonb_build_object('id',invitation_id,'invite_code',full_code,'invite_code_prefix',code_prefix,'expires_at',invitation_expires_at);
end;
$function$;
GRANT ALL ON FUNCTION public.create_trainer_student_invitation() TO authenticated;
GRANT ALL ON FUNCTION public.create_trainer_student_invitation() TO service_role;
CREATE FUNCTION public.create_user_notification_v41c(target_recipient_user_id uuid, target_actor_user_id uuid, target_notification_type text, target_title text, target_message text, target_entity_type text, target_entity_id uuid, target_dedupe_key text, target_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  notification_id uuid;
  safe_metadata jsonb:=coalesce(target_metadata,'{}'::jsonb);
  normalized_dedupe_key text;
begin
  if target_recipient_user_id is null then raise exception 'notification_recipient_required' using errcode='22023'; end if;
  if target_actor_user_id is not null and not exists(select 1 from auth.users actor where actor.id=target_actor_user_id) then raise exception 'notification_actor_not_found' using errcode='22023'; end if;
  if target_notification_type not in (
    'relationship_activated','relationship_revoked','workout_plan_assigned','workout_plan_updated','workout_plan_revoked',
    'nutrition_plan_assigned','nutrition_plan_updated','nutrition_plan_revoked','system'
  ) then raise exception 'invalid_notification_type' using errcode='22023'; end if;
  if target_entity_type is not null and target_entity_type not in ('relationship','workout_assignment','nutrition_assignment','system') then raise exception 'invalid_notification_entity' using errcode='22023'; end if;
  if char_length(btrim(coalesce(target_title,''))) not between 1 and 120 or char_length(btrim(coalesce(target_message,''))) not between 1 and 500 then raise exception 'invalid_notification_text' using errcode='22023'; end if;
  if target_dedupe_key is not null and char_length(btrim(target_dedupe_key)) not between 1 and 200 then raise exception 'invalid_notification_dedupe_key' using errcode='22023'; end if;
  normalized_dedupe_key:=case when target_dedupe_key is null then null else btrim(target_dedupe_key) end;
  if jsonb_typeof(safe_metadata)<>'object' or octet_length(safe_metadata::text)>8192 or not public.notification_metadata_is_safe_v41c(safe_metadata) then raise exception 'unsafe_notification_metadata' using errcode='22023'; end if;

  insert into public.user_notifications(recipient_user_id,actor_user_id,notification_type,title,message,entity_type,entity_id,dedupe_key,metadata)
  values(target_recipient_user_id,target_actor_user_id,target_notification_type,btrim(target_title),btrim(target_message),target_entity_type,target_entity_id,normalized_dedupe_key,safe_metadata)
  on conflict (recipient_user_id,dedupe_key) where dedupe_key is not null do nothing
  returning id into notification_id;

  if notification_id is null and normalized_dedupe_key is not null then
    select notification.id into notification_id from public.user_notifications notification
    where notification.recipient_user_id=target_recipient_user_id and notification.dedupe_key=normalized_dedupe_key;
  end if;
  return notification_id;
end;
$function$;
GRANT ALL ON FUNCTION public.create_user_notification_v41c(uuid, uuid, text, text, text, text, uuid, text, jsonb) TO service_role;
CREATE FUNCTION public.default_professional_relationship_scopes_v41e1(target_professional_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if target_professional_type = 'trainer' then
    return pg_catalog.jsonb_build_object(
      'manage_workout_plan', true,
      'view_workout_executions', true,
      'view_evolution', true,
      'manage_nutrition_plan', false,
      'view_nutrition_logs', false
    );
  end if;

  if target_professional_type = 'nutritionist' then
    return pg_catalog.jsonb_build_object(
      'manage_workout_plan', false,
      'view_workout_executions', false,
      'view_evolution', true,
      'manage_nutrition_plan', true,
      'view_nutrition_logs', true
    );
  end if;

  raise exception 'invalid_professional_type' using errcode = '22023';
end;
$function$;
GRANT ALL ON FUNCTION public.default_professional_relationship_scopes_v41e1(text) TO service_role;
CREATE FUNCTION public.default_professional_scopes(target_professional_type text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case target_professional_type
    when 'trainer' then jsonb_build_object(
      'manage_workout_plan', true,
      'view_workout_executions', true,
      'manage_nutrition_plan', false,
      'view_nutrition_logs', false,
      'view_evolution', false
    )
    when 'nutritionist' then jsonb_build_object(
      'manage_workout_plan', false,
      'view_workout_executions', false,
      'manage_nutrition_plan', true,
      'view_nutrition_logs', true,
      'view_evolution', false
    )
    else null
  end;
$function$;
GRANT ALL ON FUNCTION public.default_professional_scopes(text) TO service_role;
CREATE FUNCTION public.enforce_professional_client_limit_v41a2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status='active' and (
    tg_op='INSERT'
    or old.status is distinct from 'active'
    or old.professional_user_id is distinct from new.professional_user_id
    or old.professional_type is distinct from new.professional_type
    or old.student_user_id is distinct from new.student_user_id
  ) then
    perform public.assert_professional_client_capacity_v41a2(
      new.professional_user_id,
      new.professional_type,
      new.student_user_id,
      case when tg_op='UPDATE' then old.id else null end
    );
  end if;
  return new;
end;
$function$;
GRANT ALL ON FUNCTION public.enforce_professional_client_limit_v41a2() TO service_role;
CREATE FUNCTION public.get_current_access_context_v41a()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when auth.uid() is null then jsonb_build_object(
    'user_id', null,
    'platform_roles', '[]'::jsonb,
    'memberships', '[]'::jsonb,
    'trainer_relationships', '[]'::jsonb,
    'student_relationships', '[]'::jsonb,
    'professionalRelationships', '[]'::jsonb,
    'studentProfessionalRelationships', '[]'::jsonb
  ) else jsonb_build_object(
    'user_id', auth.uid(),
    'platform_roles', coalesce((
      select jsonb_agg(role_record.role order by role_record.role)
      from public.platform_user_roles role_record
      where role_record.user_id = auth.uid()
    ), '[]'::jsonb),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organization_id', membership.organization_id,
        'role', membership.role,
        'status', membership.status,
        'joined_at', membership.joined_at
      ) order by membership.created_at)
      from public.organization_members membership
      where membership.user_id = auth.uid()
    ), '[]'::jsonb),
    'trainer_relationships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', relationship.id,
        'student_user_id', relationship.student_user_id,
        'organization_id', relationship.organization_id,
        'status', relationship.status,
        'permissions', relationship.permissions
      ) order by relationship.created_at)
      from public.trainer_student_relationships relationship
      where relationship.trainer_user_id = auth.uid()
    ), '[]'::jsonb),
    'student_relationships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', relationship.id,
        'trainer_user_id', relationship.trainer_user_id,
        'organization_id', relationship.organization_id,
        'status', relationship.status,
        'permissions', relationship.permissions
      ) order by relationship.created_at)
      from public.trainer_student_relationships relationship
      where relationship.student_user_id = auth.uid()
    ), '[]'::jsonb),
    'professionalRelationships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', relationship.id,
        'studentUserId', relationship.student_user_id,
        'professionalType', relationship.professional_type,
        'scopes', relationship.scopes,
        'organizationId', relationship.organization_id,
        'status', relationship.status
      ) order by relationship.created_at)
      from public.professional_student_relationships relationship
      where relationship.professional_user_id = auth.uid()
    ), '[]'::jsonb),
    'studentProfessionalRelationships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', relationship.id,
        'professionalUserId', relationship.professional_user_id,
        'professionalType', relationship.professional_type,
        'scopes', relationship.scopes,
        'organizationId', relationship.organization_id,
        'status', relationship.status
      ) order by relationship.created_at)
      from public.professional_student_relationships relationship
      where relationship.student_user_id = auth.uid()
    ), '[]'::jsonb)
  ) end;
$function$;
GRANT ALL ON FUNCTION public.get_current_access_context_v41a() TO service_role;
CREATE FUNCTION public.get_current_access_context()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.get_current_access_context_v41a() || jsonb_build_object(
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
GRANT ALL ON FUNCTION public.get_current_access_context() TO authenticated;
GRANT ALL ON FUNCTION public.get_current_access_context() TO service_role;
CREATE FUNCTION public.get_my_account_modes()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when auth.uid() is null then array[]::text[] else coalesce(
    (select array_agg(account_mode.mode order by account_mode.mode)
     from public.user_account_modes account_mode
     where account_mode.user_id = auth.uid()),
    array[]::text[]
  ) end;
$function$;
GRANT ALL ON FUNCTION public.get_my_account_modes() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_account_modes() TO service_role;
CREATE FUNCTION public.get_my_account_registration_context()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when auth.uid() is null then jsonb_build_object(
    'profileCompleted', false, 'fullName', null, 'displayName', null,
    'ageStatus', 'unknown', 'identityCompleted', false,
    'termsAccepted', false, 'privacyAccepted', false,
    'currentTermsVersion', 'terms-2026-01', 'currentPrivacyVersion', 'privacy-2026-01',
    'primaryAccountType', null, 'planCode', null, 'planName', null,
    'subscriptionStatus', null, 'personalUseEnabled', true,
    'activeClientLimit', null, 'accountTypeSelectedAt', null,
    'requiresAccountTypeSelection', true, 'requiresIdentityCompletion', true,
    'requiresLegalAcceptance', true, 'availableAccountTypes', '[]'::jsonb
  ) else (
    select commercial || jsonb_build_object(
      'profileCompleted', nullif(btrim(profile.full_name), '') is not null,
      'fullName', nullif(btrim(profile.full_name), ''),
      'displayName', nullif(btrim(profile.display_name), ''),
      'ageStatus', coalesce(identity.age_status, 'unknown'),
      'identityCompleted', identity.age_status = 'adult',
      'termsAccepted', exists(select 1 from public.user_legal_acceptances acceptance where acceptance.user_id=auth.uid() and acceptance.document_type='terms' and acceptance.document_version='terms-2026-01'),
      'privacyAccepted', exists(select 1 from public.user_legal_acceptances acceptance where acceptance.user_id=auth.uid() and acceptance.document_type='privacy' and acceptance.document_version='privacy-2026-01'),
      'currentTermsVersion', 'terms-2026-01',
      'currentPrivacyVersion', 'privacy-2026-01',
      'requiresIdentityCompletion', coalesce(identity.age_status, 'unknown') <> 'adult',
      'requiresLegalAcceptance', not (
        exists(select 1 from public.user_legal_acceptances acceptance where acceptance.user_id=auth.uid() and acceptance.document_type='terms' and acceptance.document_version='terms-2026-01')
        and exists(select 1 from public.user_legal_acceptances acceptance where acceptance.user_id=auth.uid() and acceptance.document_type='privacy' and acceptance.document_version='privacy-2026-01')
      )
    )
    from (select public.get_my_commercial_account_context() commercial) context
    left join public.profiles profile on profile.user_id=auth.uid()
    left join public.user_identity_details identity on identity.user_id=auth.uid()
  ) end;
$function$;
GRANT ALL ON FUNCTION public.get_my_account_registration_context() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_account_registration_context() TO service_role;
CREATE FUNCTION public.get_my_commercial_account_context()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when auth.uid() is null then jsonb_build_object(
    'primaryAccountType',null,'planCode',null,'planName',null,
    'subscriptionStatus',null,'personalUseEnabled',true,
    'activeClientLimit',null,'activeClientCount',0,'remainingSlots',null,
    'limitReached',false,'canActivateNewClient',false,
    'accountTypeSelectedAt',null,'requiresAccountTypeSelection',true,
    'availableAccountTypes','[]'::jsonb
  ) else jsonb_build_object(
    'primaryAccountType',account.primary_account_type,
    'planCode',account.plan_code,
    'planName',plan.display_name,
    'subscriptionStatus',account.subscription_status,
    'personalUseEnabled',coalesce(account.personal_use_enabled,true),
    'activeClientLimit',capacity->'activeClientLimit',
    'activeClientCount',capacity->'activeClientCount',
    'remainingSlots',capacity->'remainingSlots',
    'limitReached',capacity->'limitReached',
    'canActivateNewClient',capacity->'canActivateNewClient',
    'accountTypeSelectedAt',account.account_type_selected_at,
    'requiresAccountTypeSelection',account.primary_account_type is null,
    'availableAccountTypes',coalesce((select jsonb_agg(jsonb_build_object(
      'accountType',catalog.account_type,'planCode',catalog.code,
      'planName',catalog.display_name,'activeClientLimit',catalog.active_client_limit
    ) order by catalog.code) from public.account_plan_catalog catalog
      where catalog.is_active and catalog.is_free),'[]'::jsonb)
    ) end
  from (
    select auth.uid() as user_id
  ) as current_user_context
  left join public.user_commercial_accounts account
    on account.user_id = current_user_context.user_id
  left join public.account_plan_catalog plan on plan.code=account.plan_code and plan.account_type=account.primary_account_type
  cross join lateral (
    select case
      when auth.uid() is null then '{}'::jsonb
      else public.get_my_professional_client_capacity()
    end capacity
  ) capacity_context;
$function$;
GRANT ALL ON FUNCTION public.get_my_commercial_account_context() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_commercial_account_context() TO service_role;
CREATE FUNCTION public.get_my_professional_client_capacity()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_user_id uuid:=auth.uid();
  account_record record;
  plan_record record;
  professional_type text;
  active_count bigint:=0;
  remaining_slots integer;
  limit_reached boolean:=false;
  requires_professional_account boolean:=true;
  can_activate boolean:=false;
begin
  if current_user_id is null then
    raise exception 'session_required' using errcode='42501';
  end if;
  select account.primary_account_type,account.plan_code,account.subscription_status
    into account_record
  from public.user_commercial_accounts account
  where account.user_id=current_user_id;
  if not found then
    return jsonb_build_object(
      'professionalType',null,'planCode',null,'planName',null,'subscriptionStatus',null,
      'activeClientLimit',null,'activeClientCount',0,'remainingSlots',null,
      'limitReached',false,'canActivateNewClient',false,'requiresProfessionalAccount',true
    );
  end if;

  if account_record.primary_account_type in ('trainer','nutritionist') then
    professional_type:=account_record.primary_account_type;
    requires_professional_account:=false;
    active_count:=public.get_professional_active_client_count_v41a2(current_user_id,professional_type);
  end if;
  select plan.display_name,plan.active_client_limit,plan.is_active
    into plan_record
  from public.account_plan_catalog plan
  where plan.code=account_record.plan_code
    and plan.account_type=account_record.primary_account_type;

  if plan_record.active_client_limit is not null then
    remaining_slots:=greatest(plan_record.active_client_limit-active_count::integer,0);
    limit_reached:=active_count>=plan_record.active_client_limit;
  end if;
  can_activate:=not requires_professional_account
    and coalesce(plan_record.is_active,false)
    and account_record.subscription_status in ('active','trialing')
    and not limit_reached;

  return jsonb_build_object(
    'professionalType',professional_type,
    'planCode',account_record.plan_code,
    'planName',plan_record.display_name,
    'subscriptionStatus',account_record.subscription_status,
    'activeClientLimit',plan_record.active_client_limit,
    'activeClientCount',active_count,
    'remainingSlots',remaining_slots,
    'limitReached',limit_reached,
    'canActivateNewClient',can_activate,
    'requiresProfessionalAccount',requires_professional_account
  );
end;
$function$;
GRANT ALL ON FUNCTION public.get_my_professional_client_capacity() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_professional_client_capacity() TO service_role;
CREATE FUNCTION public.get_my_professional_monitoring_entitlement_v41d(target_relationship_id uuid, target_required_scope text, target_allowed_professional_types text[])
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    (target_required_scope = 'view_workout_executions' and target_allowed_professional_types = array['trainer']::text[])
    or (target_required_scope = 'view_nutrition_logs' and target_allowed_professional_types = array['nutritionist']::text[])
    or (target_required_scope = 'view_evolution' and target_allowed_professional_types = array['trainer', 'nutritionist']::text[])
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
    where membership.organization_id = derived_organization_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and (
        (derived_professional_type = 'trainer' and membership.role in ('owner', 'admin', 'trainer'))
        or (derived_professional_type = 'nutritionist' and membership.role in ('owner', 'admin', 'nutritionist'))
      );
    if not found then
      raise exception 'professional_monitoring_organization_membership_required' using errcode = '42501';
    end if;
  end if;

  return derived_student_user_id;
end;
$function$;
GRANT ALL ON FUNCTION public.get_my_professional_monitoring_entitlement_v41d(uuid, text, text[]) TO service_role;
CREATE FUNCTION public.get_my_unread_notification_count()
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  return (select count(*)::integer from public.user_notifications notification where notification.recipient_user_id=auth.uid() and notification.read_at is null and (notification.expires_at is null or notification.expires_at>now()));
end;
$function$;
GRANT ALL ON FUNCTION public.get_my_unread_notification_count() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_unread_notification_count() TO service_role;
CREATE FUNCTION public.get_professional_active_client_count_v41a2(target_professional_id uuid, target_professional_type text, relationship_id_to_exclude uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare active_count bigint;
begin
  if target_professional_id is null or target_professional_type not in ('trainer','nutritionist') then
    raise exception 'invalid_professional_capacity_parameters' using errcode='22023';
  end if;
  select count(distinct relationship.student_user_id)
    into active_count
  from public.professional_student_relationships relationship
  where relationship.professional_user_id=target_professional_id
    and relationship.professional_type=target_professional_type
    and relationship.status='active'
    and (relationship_id_to_exclude is null or relationship.id<>relationship_id_to_exclude);
  return coalesce(active_count,0);
end;
$function$;
GRANT ALL ON FUNCTION public.get_professional_active_client_count_v41a2(uuid, text, uuid) TO service_role;
CREATE FUNCTION public.handle_new_user_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (user_id, email, name)
  values (
    new.id,
    new.email,
    coalesce(
      new.raw_user_meta_data ->> 'name',
      new.raw_user_meta_data ->> 'full_name'
    )
  )
  on conflict (user_id) do nothing;

  return new;
end;
$function$;
CREATE TRIGGER on_auth_user_created_create_profile AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();
GRANT ALL ON FUNCTION public.handle_new_user_profile() TO anon;
GRANT ALL ON FUNCTION public.handle_new_user_profile() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user_profile() TO service_role;
CREATE FUNCTION public.has_active_professional_relationship(professional_id uuid, student_id uuid, target_professional_type text, required_scope text DEFAULT NULL::text, target_organization_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select auth.uid() is not null
    and auth.uid() in (professional_id, student_id)
    and target_professional_type in ('trainer', 'nutritionist')
    and (
      required_scope is null
      or required_scope = any(array[
        'manage_workout_plan',
        'view_workout_executions',
        'manage_nutrition_plan',
        'view_nutrition_logs',
        'view_evolution'
      ]::text[])
    )
    and exists (
      select 1
      from public.professional_student_relationships relationship
      where relationship.professional_user_id = professional_id
        and relationship.student_user_id = student_id
        and relationship.professional_type = target_professional_type
        and relationship.organization_id is not distinct from target_organization_id
        and relationship.status = 'active'
        and (required_scope is null or relationship.scopes ->> required_scope = 'true')
    );
$function$;
GRANT ALL ON FUNCTION public.has_active_professional_relationship(uuid, uuid, text, text, uuid) TO authenticated;
GRANT ALL ON FUNCTION public.has_active_professional_relationship(uuid, uuid, text, text, uuid) TO service_role;
CREATE FUNCTION public.has_active_trainer_student_relationship(target_trainer_id uuid, target_student_id uuid, required_permission text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select auth.uid() is not null
    and auth.uid() in (target_trainer_id, target_student_id)
    and (required_permission is null or required_permission = any(array[
      'view_workouts', 'assign_workouts', 'view_executions', 'view_evolution', 'view_nutrition'
    ]::text[]))
    and exists (
      select 1 from public.trainer_student_relationships relationship
      where relationship.trainer_user_id = target_trainer_id
        and relationship.student_user_id = target_student_id
        and relationship.status = 'active'
        and (required_permission is null or relationship.permissions ->> required_permission = 'true')
    );
$function$;
GRANT ALL ON FUNCTION public.has_active_trainer_student_relationship(uuid, uuid, text) TO authenticated;
GRANT ALL ON FUNCTION public.has_active_trainer_student_relationship(uuid, uuid, text) TO service_role;
CREATE FUNCTION public.has_organization_role(target_organization_id uuid, allowed_roles text[], target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select auth.uid() is not null
    and target_user_id = auth.uid()
    and allowed_roles <@ array['owner', 'admin', 'trainer', 'nutritionist', 'student']::text[]
    and exists (
      select 1
      from public.organization_members membership
      where membership.organization_id = target_organization_id
        and membership.user_id = target_user_id
        and membership.status = 'active'
        and membership.role = any(allowed_roles)
    );
$function$;
GRANT ALL ON FUNCTION public.has_organization_role(uuid, text[], uuid) TO authenticated;
GRANT ALL ON FUNCTION public.has_organization_role(uuid, text[], uuid) TO service_role;
CREATE FUNCTION public.is_organization_member(target_organization_id uuid, target_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select auth.uid() is not null
    and target_user_id = auth.uid()
    and exists (
      select 1 from public.organization_members membership
      where membership.organization_id = target_organization_id
        and membership.user_id = target_user_id
        and membership.status in ('active', 'pending')
    );
$function$;
GRANT ALL ON FUNCTION public.is_organization_member(uuid, uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_organization_member(uuid, uuid) TO service_role;
CREATE FUNCTION public.list_my_assigned_nutrition_plans(target_local_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  if target_local_date is null or target_local_date<current_date-1 or target_local_date>current_date+1 then raise exception 'invalid_local_date' using errcode='22023'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'assignmentId',assignment.id,'relationshipId',assignment.relationship_id,
    'nutritionistDisplayName',coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Nutricionista'),
    'organizationName',organization.name,'title',assignment.title_snapshot,'description',assignment.description_snapshot,
    'planData',assignment.plan_data_snapshot,'schemaVersion',assignment.schema_version,'assignmentVersion',assignment.assignment_version,
    'assignmentStatus',assignment.status,'relationshipStatus',relationship.status,
    'professionalType',relationship.professional_type,
    'canManageNutritionPlan',coalesce(relationship.scopes @> '{"manage_nutrition_plan": true}'::jsonb,false),
    'isCurrent',(assignment.status='active' and relationship.status='active' and relationship.professional_type='nutritionist'
      and relationship.scopes @> '{"manage_nutrition_plan": true}'::jsonb
      and (assignment.effective_from is null or assignment.effective_from<=target_local_date)
      and (assignment.effective_until is null or assignment.effective_until>=target_local_date)),
    'assignedAt',assignment.assigned_at,'effectiveFrom',assignment.effective_from,'effectiveUntil',assignment.effective_until
  ) order by case assignment.status when 'active' then 0 else 1 end,assignment.assignment_version desc)
  from public.student_nutrition_assignments assignment
  join public.professional_student_relationships relationship on relationship.id=assignment.relationship_id
  left join public.profiles profile on profile.user_id=relationship.professional_user_id
  left join public.organizations organization on organization.id=relationship.organization_id
  where relationship.student_user_id=auth.uid()),'[]'::jsonb);
end; $function$;
GRANT ALL ON FUNCTION public.list_my_assigned_nutrition_plans(date) TO authenticated;
GRANT ALL ON FUNCTION public.list_my_assigned_nutrition_plans(date) TO service_role;
CREATE FUNCTION public.list_my_assigned_workout_plans()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'assignmentId',assignment.id,'relationshipId',assignment.relationship_id,
    'trainerDisplayName',coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Treinador'),
    'organizationName',organization.name,'title',assignment.title_snapshot,'description',assignment.description_snapshot,
    'planData',assignment.plan_data_snapshot,'schemaVersion',assignment.schema_version,'assignmentVersion',assignment.assignment_version,
    'status',assignment.status,'relationshipStatus',relationship.status,
    'canStart',(assignment.status='active' and relationship.status='active' and relationship.professional_type='trainer' and coalesce((relationship.scopes->>'manage_workout_plan')::boolean,false) and (assignment.effective_from is null or assignment.effective_from<=current_date)),
    'assignedAt',assignment.assigned_at,'effectiveFrom',assignment.effective_from
  ) order by case assignment.status when 'active' then 0 else 1 end,assignment.assignment_version desc)
  from public.student_workout_assignments assignment
  join public.professional_student_relationships relationship on relationship.id=assignment.relationship_id
  left join public.profiles profile on profile.user_id=relationship.professional_user_id
  left join public.organizations organization on organization.id=relationship.organization_id
  where relationship.student_user_id=auth.uid()),'[]'::jsonb);
end;
$function$;
GRANT ALL ON FUNCTION public.list_my_assigned_workout_plans() TO authenticated;
GRANT ALL ON FUNCTION public.list_my_assigned_workout_plans() TO service_role;
CREATE FUNCTION public.list_my_manageable_nutrition_students()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.assert_my_nutritionist_identity_v41c();
  return coalesce((select jsonb_agg(jsonb_build_object(
    'relationshipId',relationship.id,'patientDisplayName',coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Paciente'),
    'organizationId',relationship.organization_id,'organizationName',organization.name,'relationshipStatus',relationship.status,
    'canManageNutritionPlan',true,'currentAssignmentId',assignment.id,'currentAssignmentVersion',assignment.assignment_version,'currentAssignmentTitle',assignment.title_snapshot,
    'currentAssignmentStatus',assignment.status,'effectiveFrom',assignment.effective_from,'effectiveUntil',assignment.effective_until
  ) order by coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Paciente'))
  from public.professional_student_relationships relationship
  left join public.profiles profile on profile.user_id=relationship.student_user_id
  left join public.organizations organization on organization.id=relationship.organization_id
  left join public.student_nutrition_assignments assignment on assignment.relationship_id=relationship.id and assignment.status='active'
  where relationship.professional_user_id=auth.uid() and relationship.professional_type='nutritionist' and relationship.status='active' and relationship.scopes @> '{"manage_nutrition_plan": true}'::jsonb),'[]'::jsonb);
end; $function$;
GRANT ALL ON FUNCTION public.list_my_manageable_nutrition_students() TO authenticated;
GRANT ALL ON FUNCTION public.list_my_manageable_nutrition_students() TO service_role;
CREATE FUNCTION public.list_my_manageable_workout_students()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.assert_my_trainer_identity_v41b();
  return coalesce((select jsonb_agg(jsonb_build_object(
    'relationshipId',relationship.id,'studentDisplayName',coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Aluno'),
    'organizationId',relationship.organization_id,'organizationName',organization.name,'relationshipStatus',relationship.status,
    'canManageWorkoutPlan',true,'currentAssignmentId',assignment.id,'currentAssignmentVersion',assignment.assignment_version,'currentAssignmentTitle',assignment.title_snapshot
  ) order by coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Aluno'))
  from public.professional_student_relationships relationship
  left join public.profiles profile on profile.user_id=relationship.student_user_id
  left join public.organizations organization on organization.id=relationship.organization_id
  left join public.student_workout_assignments assignment on assignment.relationship_id=relationship.id and assignment.status='active'
  where relationship.professional_user_id=auth.uid() and relationship.professional_type='trainer' and relationship.status='active' and relationship.scopes->>'manage_workout_plan'='true'),'[]'::jsonb);
end;
$function$;
GRANT ALL ON FUNCTION public.list_my_manageable_workout_students() TO authenticated;
GRANT ALL ON FUNCTION public.list_my_manageable_workout_students() TO service_role;
CREATE FUNCTION public.list_my_notifications(target_limit integer DEFAULT 30, target_before timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  if target_limit is null or target_limit not between 1 and 100 then raise exception 'invalid_notification_limit' using errcode='22023'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',item.id,'notificationType',item.notification_type,'title',item.title,'message',item.message,
    'entityType',item.entity_type,'entityId',item.entity_id,'metadata',item.metadata,
    'readAt',item.read_at,'createdAt',item.created_at,'expiresAt',item.expires_at
  ) order by item.created_at desc) from (
    select notification.* from public.user_notifications notification
    where notification.recipient_user_id=auth.uid()
      and (notification.expires_at is null or notification.expires_at>now())
      and (target_before is null or notification.created_at<target_before)
    order by notification.created_at desc limit target_limit
  ) item),'[]'::jsonb);
end;
$function$;
GRANT ALL ON FUNCTION public.list_my_notifications(integer, timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.list_my_notifications(integer, timestamp with time zone) TO service_role;
CREATE FUNCTION public.list_my_nutrition_templates()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.assert_my_nutritionist_identity_v41c();
  return coalesce((select jsonb_agg(jsonb_build_object('id',template.id,'title',template.title,'description',template.description,'planData',template.plan_data,'schemaVersion',template.schema_version,'status',template.status,'organizationId',template.organization_id,'createdAt',template.created_at,'updatedAt',template.updated_at) order by template.updated_at desc) from public.professional_nutrition_templates template where template.owner_user_id=auth.uid()),'[]'::jsonb);
end; $function$;
GRANT ALL ON FUNCTION public.list_my_nutrition_templates() TO authenticated;
GRANT ALL ON FUNCTION public.list_my_nutrition_templates() TO service_role;
CREATE FUNCTION public.list_my_student_evolution(target_relationship_id uuid, target_start_date date, target_end_date date, target_limit integer, target_cursor_date date DEFAULT NULL::date, target_cursor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  derived_student_user_id uuid;
  response jsonb;
begin
  derived_student_user_id := public.get_my_professional_monitoring_entitlement_v41d(
    target_relationship_id,
    'view_evolution',
    array['trainer', 'nutritionist']::text[]
  );
  perform public.assert_professional_monitoring_page_v41d(
    target_start_date, target_end_date, target_limit, target_cursor_date, target_cursor_id
  );

  with candidates as (
    select evolution.id, evolution.record_date, evolution.weight, evolution.body_fat,
      evolution.waist, evolution.hip, evolution.chest, evolution.left_arm,
      evolution.right_arm, evolution.left_thigh, evolution.right_thigh, evolution.notes
    from public.evolution evolution
    where evolution.user_id = derived_student_user_id
      and evolution.record_date >= target_start_date
      and evolution.record_date <= target_end_date
      and (target_cursor_date is null or (evolution.record_date, evolution.id) < (target_cursor_date, target_cursor_id))
    order by evolution.record_date desc, evolution.id desc
    limit (target_limit + 1)
  ), visible as (
    select * from candidates order by record_date desc, id desc limit target_limit
  ), page_state as (
    select count(*) > target_limit as has_more from candidates
  ), last_visible as (
    select record_date, id from visible order by record_date asc, id asc limit 1
  )
  select pg_catalog.jsonb_build_object(
    'items', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', item.id, 'recordDate', item.record_date, 'weight', item.weight,
      'bodyFat', item.body_fat, 'waist', item.waist, 'hip', item.hip,
      'chest', item.chest, 'leftArm', item.left_arm, 'rightArm', item.right_arm,
      'leftThigh', item.left_thigh, 'rightThigh', item.right_thigh, 'notes', item.notes
    ) order by item.record_date desc, item.id desc) from visible item), '[]'::jsonb),
    'hasMore', (select has_more from page_state),
    'nextCursor', case when (select has_more from page_state) then (
      select pg_catalog.jsonb_build_object('date', cursor_row.record_date, 'id', cursor_row.id)
      from last_visible cursor_row
    ) else null end
  ) into response;

  return response;
end;
$function$;
GRANT ALL ON FUNCTION public.list_my_student_evolution(uuid, date, date, integer, date, uuid) TO authenticated;
GRANT ALL ON FUNCTION public.list_my_student_evolution(uuid, date, date, integer, date, uuid) TO service_role;
CREATE FUNCTION public.list_my_student_nutrition_logs(target_relationship_id uuid, target_start_date date, target_end_date date, target_limit integer, target_cursor_date date DEFAULT NULL::date, target_cursor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  derived_student_user_id uuid;
  response jsonb;
begin
  derived_student_user_id := public.get_my_professional_monitoring_entitlement_v41d(
    target_relationship_id,
    'view_nutrition_logs',
    array['nutritionist']::text[]
  );
  perform public.assert_professional_monitoring_page_v41d(
    target_start_date, target_end_date, target_limit, target_cursor_date, target_cursor_id
  );

  with candidates as (
    select meal.id, meal.meal_date, meal.items, meal.total_calories,
      meal.total_protein, meal.total_carbs, meal.total_fat
    from public.meals meal
    where meal.user_id = derived_student_user_id
      and meal.meal_date >= target_start_date
      and meal.meal_date <= target_end_date
      and (target_cursor_date is null or (meal.meal_date, meal.id) < (target_cursor_date, target_cursor_id))
    order by meal.meal_date desc, meal.id desc
    limit (target_limit + 1)
  ), visible as (
    select * from candidates order by meal_date desc, id desc limit target_limit
  ), page_state as (
    select count(*) > target_limit as has_more from candidates
  ), last_visible as (
    select meal_date, id from visible order by meal_date asc, id asc limit 1
  )
  select pg_catalog.jsonb_build_object(
    'items', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', item.id, 'mealDate', item.meal_date, 'items', item.items,
      'totalCalories', item.total_calories, 'totalProtein', item.total_protein,
      'totalCarbs', item.total_carbs, 'totalFat', item.total_fat
    ) order by item.meal_date desc, item.id desc) from visible item), '[]'::jsonb),
    'hasMore', (select has_more from page_state),
    'nextCursor', case when (select has_more from page_state) then (
      select pg_catalog.jsonb_build_object('date', cursor_row.meal_date, 'id', cursor_row.id)
      from last_visible cursor_row
    ) else null end
  ) into response;

  return response;
end;
$function$;
GRANT ALL ON FUNCTION public.list_my_student_nutrition_logs(uuid, date, date, integer, date, uuid) TO authenticated;
GRANT ALL ON FUNCTION public.list_my_student_nutrition_logs(uuid, date, date, integer, date, uuid) TO service_role;
CREATE FUNCTION public.list_my_student_workout_executions(target_relationship_id uuid, target_start_date date, target_end_date date, target_limit integer, target_cursor_date date DEFAULT NULL::date, target_cursor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  derived_student_user_id uuid;
  response jsonb;
begin
  derived_student_user_id := public.get_my_professional_monitoring_entitlement_v41d(
    target_relationship_id,
    'view_workout_executions',
    array['trainer']::text[]
  );
  perform public.assert_professional_monitoring_page_v41d(
    target_start_date, target_end_date, target_limit, target_cursor_date, target_cursor_id
  );

  with candidates as (
    select workout.id, workout.workout_date, workout.name, workout.exercises,
      workout.total_volume, workout.duration_minutes
    from public.workouts workout
    where workout.user_id = derived_student_user_id
      and workout.workout_date >= target_start_date
      and workout.workout_date <= target_end_date
      and (target_cursor_date is null or (workout.workout_date, workout.id) < (target_cursor_date, target_cursor_id))
    order by workout.workout_date desc, workout.id desc
    limit (target_limit + 1)
  ), visible as (
    select * from candidates order by workout_date desc, id desc limit target_limit
  ), page_state as (
    select count(*) > target_limit as has_more from candidates
  ), last_visible as (
    select workout_date, id from visible order by workout_date asc, id asc limit 1
  )
  select pg_catalog.jsonb_build_object(
    'items', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', item.id, 'workoutDate', item.workout_date, 'name', item.name,
      'exercises', item.exercises, 'totalVolume', item.total_volume,
      'durationMinutes', item.duration_minutes
    ) order by item.workout_date desc, item.id desc) from visible item), '[]'::jsonb),
    'hasMore', (select has_more from page_state),
    'nextCursor', case when (select has_more from page_state) then (
      select pg_catalog.jsonb_build_object('date', cursor_row.workout_date, 'id', cursor_row.id)
      from last_visible cursor_row
    ) else null end
  ) into response;

  return response;
end;
$function$;
GRANT ALL ON FUNCTION public.list_my_student_workout_executions(uuid, date, date, integer, date, uuid) TO authenticated;
GRANT ALL ON FUNCTION public.list_my_student_workout_executions(uuid, date, date, integer, date, uuid) TO service_role;
CREATE FUNCTION public.list_my_trainer_invitations()
 RETURNS TABLE(id uuid, invite_code_prefix text, status text, expires_at timestamp with time zone, created_at timestamp with time zone, accepted_at timestamp with time zone, cancelled_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select invitation.id,invitation.invite_code_prefix,
         case when invitation.status='pending' and invitation.expires_at<=now() then 'expired' else invitation.status end as status,
         invitation.expires_at,invitation.created_at,invitation.accepted_at,invitation.cancelled_at
  from public.trainer_student_invitations invitation where auth.uid() is not null and invitation.trainer_user_id=auth.uid() order by invitation.created_at desc;
$function$;
GRANT ALL ON FUNCTION public.list_my_trainer_invitations() TO authenticated;
GRANT ALL ON FUNCTION public.list_my_trainer_invitations() TO service_role;
CREATE FUNCTION public.list_my_trainer_student_connections()
 RETURNS TABLE(relationship_id uuid, role_in_relationship text, display_name text, status text, permissions jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select relationship.id,'trainer'::text,coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Usuário do Forja'),relationship.status,relationship.permissions
  from public.trainer_student_relationships relationship join public.profiles profile on profile.user_id=relationship.student_user_id
  where relationship.trainer_user_id=auth.uid()
  union all
  select relationship.id,'student'::text,coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Treinador do Forja'),relationship.status,relationship.permissions
  from public.trainer_student_relationships relationship join public.profiles profile on profile.user_id=relationship.trainer_user_id
  where relationship.student_user_id=auth.uid();
$function$;
GRANT ALL ON FUNCTION public.list_my_trainer_student_connections() TO authenticated;
GRANT ALL ON FUNCTION public.list_my_trainer_student_connections() TO service_role;
CREATE FUNCTION public.list_my_workout_templates()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.assert_my_trainer_identity_v41b();
  return coalesce((select jsonb_agg(jsonb_build_object('id',template.id,'title',template.title,'description',template.description,'planData',template.plan_data,'schemaVersion',template.schema_version,'status',template.status,'organizationId',template.organization_id,'createdAt',template.created_at,'updatedAt',template.updated_at) order by template.updated_at desc) from public.professional_workout_templates template where template.owner_user_id=auth.uid()),'[]'::jsonb);
end;
$function$;
GRANT ALL ON FUNCTION public.list_my_workout_templates() TO authenticated;
GRANT ALL ON FUNCTION public.list_my_workout_templates() TO service_role;
CREATE FUNCTION public.mark_all_my_notifications_read()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare affected integer;
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  update public.user_notifications notification set read_at=now()
  where notification.recipient_user_id=auth.uid() and notification.read_at is null and (notification.expires_at is null or notification.expires_at>now());
  get diagnostics affected=row_count;
  return affected;
end;
$function$;
GRANT ALL ON FUNCTION public.mark_all_my_notifications_read() TO authenticated;
GRANT ALL ON FUNCTION public.mark_all_my_notifications_read() TO service_role;
CREATE FUNCTION public.mark_my_notification_read(target_notification_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare notification_record public.user_notifications;
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  update public.user_notifications notification set read_at=coalesce(notification.read_at,now())
  where notification.id=target_notification_id and notification.recipient_user_id=auth.uid()
    and (notification.expires_at is null or notification.expires_at>now())
  returning notification.* into notification_record;
  if not found then raise exception 'notification_not_found' using errcode='P0001'; end if;
  return jsonb_build_object('id',notification_record.id,'readAt',notification_record.read_at);
end;
$function$;
GRANT ALL ON FUNCTION public.mark_my_notification_read(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.mark_my_notification_read(uuid) TO service_role;
CREATE FUNCTION public.normalize_invitation_code(input_code text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select pg_catalog.upper(
  pg_catalog.regexp_replace(
    coalesce(input_code, ''),
    '[^A-Za-z0-9]',
    '',
    'g'
  )
);
$function$;
GRANT ALL ON FUNCTION public.normalize_invitation_code(text) TO service_role;
CREATE FUNCTION public.notification_iso_date_is_valid_v41c(target_value text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare parsed_value date;
begin
  if target_value is null or target_value!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return false; end if;
  parsed_value:=target_value::date;
  return pg_catalog.to_char(parsed_value,'YYYY-MM-DD')=target_value;
exception when invalid_datetime_format or datetime_field_overflow then
  return false;
end;
$function$;
GRANT ALL ON FUNCTION public.notification_iso_date_is_valid_v41c(text) TO service_role;
CREATE FUNCTION public.notification_metadata_is_safe_v41c(target_value jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select target_value is not null
    and jsonb_typeof(target_value)='object'
    and octet_length(target_value::text)<=8192
    and not exists (
      select 1
      from jsonb_each(case when jsonb_typeof(target_value)='object' then target_value else '{}'::jsonb end) metadata_item
      where metadata_item.key not in ('professionalType','version','effectiveFrom','severity','action','route','code')
        or case metadata_item.key
          when 'professionalType' then
            jsonb_typeof(metadata_item.value)<>'string'
            or metadata_item.value#>>'{}' not in ('trainer','nutritionist')
          when 'version' then
            jsonb_typeof(metadata_item.value)<>'number'
            or metadata_item.value#>>'{}'!~'^[1-9][0-9]{0,9}$'
            or case
              when jsonb_typeof(metadata_item.value)='number' and metadata_item.value#>>'{}'~'^[1-9][0-9]{0,9}$'
                then (metadata_item.value#>>'{}')::numeric>2147483647
              else false
            end
          when 'effectiveFrom' then
            jsonb_typeof(metadata_item.value) not in ('string','null')
            or (jsonb_typeof(metadata_item.value)='string' and not public.notification_iso_date_is_valid_v41c(metadata_item.value#>>'{}'))
          when 'severity' then
            jsonb_typeof(metadata_item.value)<>'string'
            or metadata_item.value#>>'{}' not in ('info','success','warning','error')
          when 'action' then
            jsonb_typeof(metadata_item.value)<>'string'
            or char_length(metadata_item.value#>>'{}') not between 1 and 80
            or metadata_item.value#>>'{}'~*'[<>]|[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}'
            or regexp_replace(metadata_item.value#>>'{}','[^0-9]','','g')~'^[0-9]{10,14}$'
          when 'route' then
            jsonb_typeof(metadata_item.value)<>'string'
            or metadata_item.value#>>'{}' not in ('home','dieta','treino','evolucao','exportar','profile','connections')
          when 'code' then
            jsonb_typeof(metadata_item.value)<>'string'
            or char_length(metadata_item.value#>>'{}') not between 1 and 80
            or metadata_item.value#>>'{}'!~'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$'
            or metadata_item.value#>>'{}'~*'[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}'
            or regexp_replace(metadata_item.value#>>'{}','[^0-9]','','g')~'^[0-9]{10,14}$'
          else true
        end
    )
$function$;
GRANT ALL ON FUNCTION public.notification_metadata_is_safe_v41c(jsonb) TO service_role;
CREATE FUNCTION public.notify_nutrition_assignment_v41c()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare relationship_record public.professional_student_relationships; event_type text; start_suffix text;
begin
  if tg_op='INSERT' then
    if new.status<>'active' then return new; end if;
  elsif tg_op='UPDATE' then
    if not (old.status='active' and new.status='revoked') then return new; end if;
  else
    return coalesce(new,old);
  end if;
  select * into relationship_record from public.professional_student_relationships relationship where relationship.id=new.relationship_id;
  if not found then return new; end if;
  start_suffix:=case when new.effective_from is null then '' else ' - início em '||to_char(new.effective_from,'DD/MM/YYYY') end;
  if tg_op='INSERT' then
    event_type:=case when new.assignment_version=1 then 'nutrition_plan_assigned' else 'nutrition_plan_updated' end;
    perform public.create_user_notification_v41c(relationship_record.student_user_id,relationship_record.professional_user_id,event_type,
      case event_type when 'nutrition_plan_assigned' then 'Novo plano alimentar' else 'Plano alimentar atualizado' end,
      'Versão '||new.assignment_version||start_suffix,'nutrition_assignment',new.id,'nutrition:'||event_type||':'||new.id,
      jsonb_build_object('version',new.assignment_version,'effectiveFrom',new.effective_from));
  elsif tg_op='UPDATE' then
    perform public.create_user_notification_v41c(relationship_record.student_user_id,relationship_record.professional_user_id,'nutrition_plan_revoked','Plano alimentar revogado','O plano alimentar não está mais ativo.','nutrition_assignment',new.id,'nutrition:revoked:'||new.id,jsonb_build_object('version',new.assignment_version));
  end if;
  return new;
end; $function$;
GRANT ALL ON FUNCTION public.notify_nutrition_assignment_v41c() TO service_role;
CREATE FUNCTION public.notify_relationship_status_v41c()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor_id uuid; professional_label text; student_label text; event_kind text;
begin
  if tg_op='INSERT' then
    if new.status<>'active' then return new; end if;
    event_kind:='activation';
  elsif tg_op='UPDATE' then
    if old.status is distinct from new.status and new.status='active' then
      event_kind:='activation';
    elsif old.status='active' and new.status='revoked' then
      event_kind:='revocation';
    else
      return new;
    end if;
  else
    return coalesce(new,old);
  end if;
  actor_id:=case when auth.uid() in (new.professional_user_id,new.student_user_id) then auth.uid() else null end;
  professional_label:=case new.professional_type when 'nutritionist' then 'nutricionista' else 'treinador' end;
  student_label:=case new.professional_type when 'nutritionist' then 'paciente' else 'aluno' end;

  if event_kind='activation' then
    perform public.create_user_notification_v41c(new.professional_user_id,actor_id,'relationship_activated','Nova conexão profissional','Um '||student_label||' aceitou sua conexão.','relationship',new.id,'relationship:active:'||new.id||':'||new.updated_at||':'||new.professional_user_id,jsonb_build_object('professionalType',new.professional_type));
    perform public.create_user_notification_v41c(new.student_user_id,actor_id,'relationship_activated','Conexão profissional ativa','Sua conexão com o '||professional_label||' está ativa.','relationship',new.id,'relationship:active:'||new.id||':'||new.updated_at||':'||new.student_user_id,jsonb_build_object('professionalType',new.professional_type));
  elsif event_kind='revocation' then
    perform public.create_user_notification_v41c(new.professional_user_id,actor_id,'relationship_revoked','Conexão profissional encerrada','Uma conexão profissional não está mais ativa.','relationship',new.id,'relationship:revoked:'||new.id||':'||new.updated_at||':'||new.professional_user_id,jsonb_build_object('professionalType',new.professional_type));
    perform public.create_user_notification_v41c(new.student_user_id,actor_id,'relationship_revoked','Conexão profissional encerrada','Uma conexão profissional não está mais ativa.','relationship',new.id,'relationship:revoked:'||new.id||':'||new.updated_at||':'||new.student_user_id,jsonb_build_object('professionalType',new.professional_type));
  end if;
  return new;
end;
$function$;
GRANT ALL ON FUNCTION public.notify_relationship_status_v41c() TO service_role;
CREATE FUNCTION public.notify_workout_assignment_v41c()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare relationship_record public.professional_student_relationships; event_type text;
begin
  if tg_op='INSERT' then
    if new.status<>'active' then return new; end if;
  elsif tg_op='UPDATE' then
    if not (old.status='active' and new.status='revoked') then return new; end if;
  else
    return coalesce(new,old);
  end if;
  select * into relationship_record from public.professional_student_relationships relationship where relationship.id=new.relationship_id;
  if not found then return new; end if;
  if tg_op='INSERT' then
    event_type:=case when new.assignment_version=1 then 'workout_plan_assigned' else 'workout_plan_updated' end;
    perform public.create_user_notification_v41c(
      relationship_record.student_user_id,relationship_record.professional_user_id,event_type,
      case event_type when 'workout_plan_assigned' then 'Novo plano de treino' else 'Plano de treino atualizado' end,
      'Versão '||new.assignment_version||' disponível.',
      'workout_assignment',new.id,'workout:'||event_type||':'||new.id,
      jsonb_build_object('version',new.assignment_version)
    );
  elsif tg_op='UPDATE' then
    perform public.create_user_notification_v41c(relationship_record.student_user_id,relationship_record.professional_user_id,'workout_plan_revoked','Plano de treino revogado','O plano de treino não está mais ativo.','workout_assignment',new.id,'workout:revoked:'||new.id,jsonb_build_object('version',new.assignment_version));
  end if;
  return new;
end;
$function$;
GRANT ALL ON FUNCTION public.notify_workout_assignment_v41c() TO service_role;
CREATE FUNCTION public.nutrition_text_is_safe_v41c(target_value text, target_max_length integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select target_value is not null
    and char_length(target_value)<=target_max_length
    and target_value !~* '(<[^>]*>|javascript:|on[a-z]+[[:space:]]*=)'
$function$;
GRANT ALL ON FUNCTION public.nutrition_text_is_safe_v41c(text, integer) TO service_role;
CREATE FUNCTION public.nutrition_unit_is_supported_v41c(target_unit text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select translate(
    lower(regexp_replace(btrim(coalesce(target_unit,'')),'[[:space:]]+',' ','g')),
    'áàâãéèêíìîóòôõúùûç',
    'aaaaeeeiiioooouuuc'
  ) in (
    'g','grama','gramas','kg','quilograma','quilogramas',
    'ml','mililitro','mililitros','l','litro','litros',
    'unidade','unidades','porcao','porcoes','colher','colheres',
    'xicara','xicaras','fatia','fatias','scoop','scoops'
  )
$function$;
GRANT ALL ON FUNCTION public.nutrition_unit_is_supported_v41c(text) TO service_role;
CREATE FUNCTION public.preview_trainer_invitation(invite_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare current_user_id uuid:=auth.uid(); normalized_code text; code_hash text; invitation record; trainer_name text;
begin
  if current_user_id is null then raise exception 'Sessão indisponível.' using errcode='42501'; end if;
  normalized_code:=public.normalize_invitation_code(invite_code);
  if char_length(normalized_code)<>25 then return jsonb_build_object('valid',false,'message','Este código não é válido ou não está mais disponível.'); end if;
  code_hash:=pg_catalog.encode(extensions.digest(normalized_code,'sha256'),'hex');
  select * into invitation from public.trainer_student_invitations where invite_code_hash=code_hash;
  if not found or invitation.status<>'pending' then return jsonb_build_object('valid',false,'message','Este código não é válido ou não está mais disponível.'); end if;
  if invitation.expires_at<=now() then
    update public.trainer_student_invitations set status='expired',updated_at=now() where id=invitation.id;
    return jsonb_build_object('valid',false,'message','Este convite não está mais disponível.');
  end if;
  if invitation.trainer_user_id=current_user_id then return jsonb_build_object('valid',false,'message','Você não pode aceitar um convite criado pela sua própria conta.'); end if;
  select coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Treinador do Forja') into trainer_name
  from public.profiles profile where profile.user_id=invitation.trainer_user_id;
  return jsonb_build_object('valid',true,'trainer_display_name',coalesce(trainer_name,'Treinador do Forja'),'expires_at',invitation.expires_at,'invite_prefix',invitation.invite_code_prefix);
end;
$function$;
GRANT ALL ON FUNCTION public.preview_trainer_invitation(text) TO authenticated;
GRANT ALL ON FUNCTION public.preview_trainer_invitation(text) TO service_role;
CREATE FUNCTION public.protect_nutrition_assignment_snapshot_v41c()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.relationship_id is distinct from new.relationship_id or old.template_id is distinct from new.template_id
    or old.assignment_version is distinct from new.assignment_version or old.title_snapshot is distinct from new.title_snapshot
    or old.description_snapshot is distinct from new.description_snapshot or old.plan_data_snapshot is distinct from new.plan_data_snapshot
    or old.schema_version is distinct from new.schema_version or old.assigned_at is distinct from new.assigned_at
    or old.effective_from is distinct from new.effective_from or old.effective_until is distinct from new.effective_until then
    raise exception 'nutrition_assignment_snapshot_immutable' using errcode='42501';
  end if;
  if old.status<>'active' and (old.status is distinct from new.status or old.superseded_at is distinct from new.superseded_at or old.revoked_at is distinct from new.revoked_at) then raise exception 'nutrition_assignment_status_immutable' using errcode='42501'; end if;
  if old.status='active' and new.status not in ('active','superseded','revoked') then raise exception 'invalid_nutrition_assignment_status' using errcode='22023'; end if;
  return new;
end;
$function$;
GRANT ALL ON FUNCTION public.protect_nutrition_assignment_snapshot_v41c() TO service_role;
CREATE FUNCTION public.protect_workout_assignment_snapshot_v41b()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.relationship_id is distinct from new.relationship_id
    or old.template_id is distinct from new.template_id
    or old.assignment_version is distinct from new.assignment_version
    or old.title_snapshot is distinct from new.title_snapshot
    or old.description_snapshot is distinct from new.description_snapshot
    or old.plan_data_snapshot is distinct from new.plan_data_snapshot
    or old.schema_version is distinct from new.schema_version
    or old.assigned_at is distinct from new.assigned_at
    or old.effective_from is distinct from new.effective_from then
    raise exception 'workout_assignment_snapshot_immutable' using errcode='42501';
  end if;
  if old.status<>'active' and (old.status is distinct from new.status or old.superseded_at is distinct from new.superseded_at or old.revoked_at is distinct from new.revoked_at) then raise exception 'workout_assignment_status_immutable' using errcode='42501'; end if;
  if old.status='active' and new.status not in ('active','superseded','revoked') then raise exception 'invalid_workout_assignment_status' using errcode='22023'; end if;
  return new;
end;
$function$;
GRANT ALL ON FUNCTION public.protect_workout_assignment_snapshot_v41b() TO service_role;
CREATE FUNCTION public.revoke_my_student_nutrition_assignment(target_assignment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare assignment_record public.student_nutrition_assignments;
begin
  perform public.assert_my_nutritionist_identity_v41c();
  select assignment.* into assignment_record from public.student_nutrition_assignments assignment join public.professional_student_relationships relationship on relationship.id=assignment.relationship_id
  where assignment.id=target_assignment_id and relationship.professional_user_id=auth.uid() and relationship.professional_type='nutritionist' for update of assignment;
  if not found then raise exception 'nutrition_assignment_not_found' using errcode='P0001'; end if;
  if assignment_record.status<>'active' then raise exception 'nutrition_assignment_inactive' using errcode='P0001'; end if;
  update public.student_nutrition_assignments set status='revoked',revoked_at=now(),superseded_at=null,updated_at=now() where id=assignment_record.id returning * into assignment_record;
  return jsonb_build_object('assignmentId',assignment_record.id,'relationshipId',assignment_record.relationship_id,'assignmentVersion',assignment_record.assignment_version,'assignmentStatus',assignment_record.status,'revokedAt',assignment_record.revoked_at);
end; $function$;
GRANT ALL ON FUNCTION public.revoke_my_student_nutrition_assignment(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_my_student_nutrition_assignment(uuid) TO service_role;
CREATE FUNCTION public.revoke_my_student_workout_assignment(target_assignment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare assignment_record public.student_workout_assignments;
begin
  perform public.assert_my_trainer_identity_v41b();
  select assignment.* into assignment_record from public.student_workout_assignments assignment
  join public.professional_student_relationships relationship on relationship.id=assignment.relationship_id
  where assignment.id=target_assignment_id and relationship.professional_user_id=auth.uid() and relationship.professional_type='trainer' for update of assignment;
  if not found then raise exception 'workout_assignment_not_found' using errcode='P0001'; end if;
  if assignment_record.status<>'active' then raise exception 'workout_assignment_inactive' using errcode='P0001'; end if;
  update public.student_workout_assignments set status='revoked',revoked_at=now(),superseded_at=null,updated_at=now() where id=assignment_record.id returning * into assignment_record;
  return jsonb_build_object('assignmentId',assignment_record.id,'relationshipId',assignment_record.relationship_id,'assignmentVersion',assignment_record.assignment_version,'status',assignment_record.status,'revokedAt',assignment_record.revoked_at);
end;
$function$;
GRANT ALL ON FUNCTION public.revoke_my_student_workout_assignment(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_my_student_workout_assignment(uuid) TO service_role;
CREATE FUNCTION public.set_my_account_modes(requested_modes text[])
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_user_id uuid := auth.uid();
  normalized_modes text[];
begin
  if current_user_id is null then raise exception 'Sessão indisponível.' using errcode = '42501'; end if;
  select coalesce(array_agg(distinct pg_catalog.lower(pg_catalog.btrim(value)) order by pg_catalog.lower(pg_catalog.btrim(value))), array[]::text[])
    into normalized_modes
  from unnest(coalesce(requested_modes, array[]::text[])) as value
  where pg_catalog.btrim(value) <> '';
  if cardinality(normalized_modes) = 0 then raise exception 'Selecione pelo menos um modo de uso.' using errcode = '22023'; end if;
  if exists (select 1 from unnest(normalized_modes) mode where mode not in ('individual', 'student', 'trainer', 'nutritionist')) then
    raise exception 'Modo de uso inválido.' using errcode = '22023';
  end if;
  delete from public.user_account_modes where user_id = current_user_id and mode <> all(normalized_modes);
  insert into public.user_account_modes (user_id, mode)
  select current_user_id, mode from unnest(normalized_modes) mode
  on conflict (user_id, mode) do update set updated_at = now();
  return normalized_modes;
end;
$function$;
GRANT ALL ON FUNCTION public.set_my_account_modes(text[]) TO authenticated;
GRANT ALL ON FUNCTION public.set_my_account_modes(text[]) TO service_role;
CREATE FUNCTION public.set_my_personal_use_enabled(target_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'Sessão indisponível.' using errcode='42501'; end if;
  if target_enabled is null then raise exception 'Valor inválido.' using errcode='22023'; end if;
  insert into public.user_commercial_accounts(user_id,personal_use_enabled) values(auth.uid(),target_enabled)
  on conflict(user_id) do update set personal_use_enabled=excluded.personal_use_enabled,updated_at=now();
  if target_enabled then insert into public.user_account_modes(user_id,mode) values(auth.uid(),'individual') on conflict(user_id,mode) do update set updated_at=now(); end if;
  return public.get_my_commercial_account_context();
end;
$function$;
GRANT ALL ON FUNCTION public.set_my_personal_use_enabled(boolean) TO authenticated;
GRANT ALL ON FUNCTION public.set_my_personal_use_enabled(boolean) TO service_role;
CREATE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;
GRANT ALL ON FUNCTION public.set_updated_at() TO anon;
GRANT ALL ON FUNCTION public.set_updated_at() TO authenticated;
GRANT ALL ON FUNCTION public.set_updated_at() TO service_role;
CREATE FUNCTION public.sync_legacy_trainer_relationship_v41a()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare mapped_scopes jsonb;
begin
  if tg_op = 'DELETE' then
    delete from public.professional_student_relationships
    where id = old.id
      and professional_type = 'trainer';
    return old;
  end if;

  mapped_scopes := jsonb_build_object(
    'manage_workout_plan', coalesce((new.permissions ->> 'assign_workouts')::boolean, false),
    'view_workout_executions', coalesce((new.permissions ->> 'view_executions')::boolean, false),
    'manage_nutrition_plan', false,
    'view_nutrition_logs', false,
    'view_evolution', coalesce((new.permissions ->> 'view_evolution')::boolean, false)
  );

  insert into public.professional_student_relationships (
    id, professional_user_id, student_user_id, professional_type, organization_id,
    status, scopes, requested_by, accepted_at, revoked_at, created_at, updated_at
  ) values (
    new.id, new.trainer_user_id, new.student_user_id, 'trainer', new.organization_id,
    new.status, mapped_scopes, new.requested_by, new.accepted_at, new.revoked_at,
    new.created_at, new.updated_at
  )
  on conflict (id) do update set
    status = excluded.status,
    scopes = excluded.scopes,
    requested_by = excluded.requested_by,
    accepted_at = excluded.accepted_at,
    revoked_at = excluded.revoked_at,
    updated_at = excluded.updated_at;
  return new;
end;
$function$;
GRANT ALL ON FUNCTION public.sync_legacy_trainer_relationship_v41a() TO service_role;
CREATE FUNCTION public.update_my_nutrition_template(target_template_id uuid, target_title text, target_description text, target_plan_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare template_record public.professional_nutrition_templates; normalized_title text; normalized_description text;
begin
  perform public.assert_my_nutritionist_write_access_v41c();
  normalized_title:=regexp_replace(btrim(coalesce(target_title,'')),'[[:space:]]+',' ','g');
  normalized_description:=nullif(regexp_replace(btrim(coalesce(target_description,'')),'[[:space:]]+',' ','g'),'');
  if char_length(normalized_title) not between 2 and 120 or not public.nutrition_text_is_safe_v41c(normalized_title,120)
    or (normalized_description is not null and not public.nutrition_text_is_safe_v41c(normalized_description,2000)) then raise exception 'invalid_nutrition_template_text' using errcode='22023'; end if;
  if not public.validate_nutrition_plan_payload_v41c(target_plan_data) then raise exception 'invalid_nutrition_plan_payload' using errcode='22023'; end if;
  update public.professional_nutrition_templates set title=normalized_title,description=normalized_description,plan_data=target_plan_data,schema_version=(target_plan_data->>'schemaVersion')::integer,updated_at=now()
  where id=target_template_id and owner_user_id=auth.uid() and status='active' returning * into template_record;
  if not found then raise exception 'nutrition_template_not_found' using errcode='P0001'; end if;
  return jsonb_build_object('id',template_record.id,'title',template_record.title,'description',template_record.description,'planData',template_record.plan_data,'schemaVersion',template_record.schema_version,'status',template_record.status,'organizationId',template_record.organization_id,'updatedAt',template_record.updated_at);
end; $function$;
GRANT ALL ON FUNCTION public.update_my_nutrition_template(uuid, text, text, jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.update_my_nutrition_template(uuid, text, text, jsonb) TO service_role;
CREATE FUNCTION public.update_my_workout_template(target_template_id uuid, target_title text, target_description text, target_plan_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare template_record public.professional_workout_templates;
begin
  perform public.assert_my_trainer_write_access_v41b();
  if char_length(btrim(coalesce(target_title,''))) not between 2 and 120 or char_length(coalesce(target_description,''))>2000 then raise exception 'invalid_workout_template_text' using errcode='22023'; end if;
  if not public.validate_workout_plan_payload_v41b(target_plan_data) then raise exception 'invalid_workout_plan_payload' using errcode='22023'; end if;
  update public.professional_workout_templates set title=btrim(target_title),description=nullif(btrim(coalesce(target_description,'')),''),plan_data=target_plan_data,schema_version=(target_plan_data->>'schemaVersion')::integer,updated_at=now()
  where id=target_template_id and owner_user_id=auth.uid() and status='active' returning * into template_record;
  if not found then raise exception 'workout_template_not_found' using errcode='P0001'; end if;
  return jsonb_build_object('id',template_record.id,'title',template_record.title,'description',template_record.description,'planData',template_record.plan_data,'schemaVersion',template_record.schema_version,'status',template_record.status,'organizationId',template_record.organization_id,'updatedAt',template_record.updated_at);
end;
$function$;
GRANT ALL ON FUNCTION public.update_my_workout_template(uuid, text, text, jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.update_my_workout_template(uuid, text, text, jsonb) TO service_role;
CREATE FUNCTION public.validate_nutrition_plan_payload_v41c(plan_data jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  meal_item jsonb; food_item jsonb; target_key text; numeric_value numeric; meal_codes text[]:=array[]::text[];
  daily_targets jsonb; meal_count integer; item_count integer; maximum numeric;
begin
  if plan_data is null or jsonb_typeof(plan_data)<>'object' then return false; end if;
  if not (plan_data ?& array['schemaVersion','title','meals']) then return false; end if;
  if (plan_data-'schemaVersion'-'title'-'notes'-'dailyTargets'-'meals')<>'{}'::jsonb then return false; end if;
  if jsonb_typeof(plan_data->'schemaVersion')<>'number' or (plan_data->>'schemaVersion')!~'^[0-9]+$' or (plan_data->>'schemaVersion')::numeric<>1 then return false; end if;
  if jsonb_typeof(plan_data->'title')<>'string' or char_length(btrim(plan_data->>'title')) not between 1 and 120 or not public.nutrition_text_is_safe_v41c(plan_data->>'title',120) then return false; end if;
  if plan_data?'notes' and jsonb_typeof(plan_data->'notes') not in ('string','null') then return false; end if;
  if jsonb_typeof(plan_data->'notes')='string' and not public.nutrition_text_is_safe_v41c(plan_data->>'notes',2000) then return false; end if;

  if plan_data?'dailyTargets' then
    daily_targets:=plan_data->'dailyTargets';
    if jsonb_typeof(daily_targets)='object' then
      if (daily_targets-'calories'-'proteinGrams'-'carbohydrateGrams'-'fatGrams'-'waterMl')<>'{}'::jsonb then return false; end if;
      for target_key in select jsonb_object_keys(daily_targets) loop
        if jsonb_typeof(daily_targets->target_key) not in ('number','null') then return false; end if;
        if jsonb_typeof(daily_targets->target_key)='number' then
          numeric_value:=(daily_targets->>target_key)::numeric;
          maximum:=case target_key when 'calories' then 20000 when 'waterMl' then 20000 else 2000 end;
          if numeric_value<0 or numeric_value>maximum then return false; end if;
        end if;
      end loop;
    elsif jsonb_typeof(daily_targets)<>'null' then
      return false;
    end if;
  end if;

  if jsonb_typeof(plan_data->'meals')<>'array' then return false; end if;
  meal_count:=jsonb_array_length(plan_data->'meals');
  if meal_count not between 1 and 12 then return false; end if;
  for meal_item in select value from jsonb_array_elements(plan_data->'meals') loop
    if jsonb_typeof(meal_item)<>'object' or not (meal_item?&array['code','name','items']) or (meal_item-'code'-'name'-'time'-'notes'-'items')<>'{}'::jsonb then return false; end if;
    if jsonb_typeof(meal_item->'code')<>'string' or (meal_item->>'code')!~'^[A-Za-z0-9_-]{1,20}$' or meal_item->>'code'=any(meal_codes) then return false; end if;
    meal_codes:=array_append(meal_codes,meal_item->>'code');
    if jsonb_typeof(meal_item->'name')<>'string' or char_length(btrim(meal_item->>'name')) not between 1 and 80 or not public.nutrition_text_is_safe_v41c(meal_item->>'name',80) then return false; end if;
    if meal_item?'time' and jsonb_typeof(meal_item->'time') not in ('string','null') then return false; end if;
    if jsonb_typeof(meal_item->'time')='string' and (meal_item->>'time')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' then return false; end if;
    if meal_item?'notes' and jsonb_typeof(meal_item->'notes') not in ('string','null') then return false; end if;
    if jsonb_typeof(meal_item->'notes')='string' and not public.nutrition_text_is_safe_v41c(meal_item->>'notes',1000) then return false; end if;
    if jsonb_typeof(meal_item->'items')<>'array' then return false; end if;
    item_count:=jsonb_array_length(meal_item->'items');
    if item_count not between 1 and 30 then return false; end if;
    for food_item in select value from jsonb_array_elements(meal_item->'items') loop
      if jsonb_typeof(food_item)<>'object' or not (food_item?&array['name','quantity','unit','sortOrder']) or (food_item-'foodId'-'name'-'quantity'-'unit'-'notes'-'sortOrder')<>'{}'::jsonb then return false; end if;
      if food_item?'foodId' and jsonb_typeof(food_item->'foodId') not in ('string','null') then return false; end if;
      if jsonb_typeof(food_item->'foodId')='string' and char_length(food_item->>'foodId')>120 then return false; end if;
      if jsonb_typeof(food_item->'name')<>'string' or char_length(btrim(food_item->>'name')) not between 1 and 120 or not public.nutrition_text_is_safe_v41c(food_item->>'name',120) then return false; end if;
      if jsonb_typeof(food_item->'quantity')<>'number' or (food_item->>'quantity')::numeric<=0 or (food_item->>'quantity')::numeric>100000 then return false; end if;
      if jsonb_typeof(food_item->'unit')<>'string' or not public.nutrition_unit_is_supported_v41c(food_item->>'unit') then return false; end if;
      if food_item?'notes' and jsonb_typeof(food_item->'notes') not in ('string','null') then return false; end if;
      if jsonb_typeof(food_item->'notes')='string' and not public.nutrition_text_is_safe_v41c(food_item->>'notes',500) then return false; end if;
      if jsonb_typeof(food_item->'sortOrder')<>'number' then return false; end if;
      numeric_value:=(food_item->>'sortOrder')::numeric;
      if numeric_value<>trunc(numeric_value) or numeric_value<0 then return false; end if;
    end loop;
  end loop;
  return true;
exception when others then return false;
end;
$function$;
GRANT ALL ON FUNCTION public.validate_nutrition_plan_payload_v41c(jsonb) TO service_role;
CREATE FUNCTION public.validate_user_identity_birth_date_v41a1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.birth_date is null or new.birth_date > current_date then
    raise exception 'Data de nascimento invalida.' using errcode = '22023';
  end if;
  if new.birth_date < (current_date - interval '120 years')::date then
    raise exception 'Data de nascimento invalida.' using errcode = '22023';
  end if;
  return new;
end;
$function$;
GRANT ALL ON FUNCTION public.validate_user_identity_birth_date_v41a1() TO service_role;
CREATE FUNCTION public.validate_workout_plan_payload_v41b(plan_data jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  plan_schema_version numeric;
  split_type text;
  expected_days integer;
  day_item jsonb;
  exercise_item jsonb;
  day_codes text[] := array[]::text[];
  day_count integer;
  exercise_count integer;
  numeric_value numeric;
begin
  if plan_data is null or jsonb_typeof(plan_data) <> 'object' then return false; end if;
  if not (plan_data ?& array['schemaVersion','splitType','days']) then return false; end if;
  if (plan_data - 'schemaVersion' - 'splitType' - 'days') <> '{}'::jsonb then return false; end if;
  if jsonb_typeof(plan_data->'schemaVersion') <> 'number' or (plan_data->>'schemaVersion') !~ '^[0-9]+$' then return false; end if;
  plan_schema_version := (plan_data->>'schemaVersion')::numeric;
  if plan_schema_version <> 1 then return false; end if;
  if jsonb_typeof(plan_data->'splitType') <> 'string' then return false; end if;
  split_type := plan_data->>'splitType';
  expected_days := case split_type when 'A' then 1 when 'AB' then 2 when 'ABC' then 3 when 'ABCD' then 4 when 'ABCDE' then 5 else null end;
  if expected_days is null or jsonb_typeof(plan_data->'days') <> 'array' then return false; end if;
  day_count := jsonb_array_length(plan_data->'days');
  if day_count <> expected_days or day_count not between 1 and 5 then return false; end if;

  for day_item in select value from jsonb_array_elements(plan_data->'days') loop
    if jsonb_typeof(day_item) <> 'object' or (day_item - 'code' - 'name' - 'notes' - 'exercises') <> '{}'::jsonb then return false; end if;
    if not (day_item ?& array['code','name','exercises']) then return false; end if;
    if jsonb_typeof(day_item->'code') <> 'string' or day_item->>'code' not in ('A','B','C','D','E') then return false; end if;
    if day_item->>'code' = any(day_codes) then return false; end if;
    day_codes := array_append(day_codes,day_item->>'code');
    if jsonb_typeof(day_item->'name') <> 'string' or char_length(btrim(day_item->>'name')) not between 1 and 80 then return false; end if;
    if day_item ? 'notes' and jsonb_typeof(day_item->'notes') not in ('string','null') then return false; end if;
    if jsonb_typeof(day_item->'notes') = 'string' and char_length(day_item->>'notes') > 1000 then return false; end if;
    if jsonb_typeof(day_item->'exercises') <> 'array' then return false; end if;
    exercise_count := jsonb_array_length(day_item->'exercises');
    if exercise_count > 50 then return false; end if;

    for exercise_item in select value from jsonb_array_elements(day_item->'exercises') loop
      if jsonb_typeof(exercise_item) <> 'object' or (exercise_item - 'exerciseId' - 'name' - 'sets' - 'reps' - 'restSeconds' - 'load' - 'notes' - 'sortOrder') <> '{}'::jsonb then return false; end if;
      if not (exercise_item ?& array['name','sets','reps','restSeconds','load','sortOrder']) then return false; end if;
      if exercise_item ? 'exerciseId' and jsonb_typeof(exercise_item->'exerciseId') not in ('string','null') then return false; end if;
      if jsonb_typeof(exercise_item->'exerciseId') = 'string' and char_length(exercise_item->>'exerciseId') > 120 then return false; end if;
      if jsonb_typeof(exercise_item->'name') <> 'string' or char_length(btrim(exercise_item->>'name')) not between 1 and 120 then return false; end if;
      if jsonb_typeof(exercise_item->'sets') <> 'number' then return false; end if;
      numeric_value := (exercise_item->>'sets')::numeric;
      if numeric_value <> trunc(numeric_value) or numeric_value not between 1 and 20 then return false; end if;
      if jsonb_typeof(exercise_item->'reps') <> 'string' or char_length(btrim(exercise_item->>'reps')) not between 1 and 30 then return false; end if;
      if jsonb_typeof(exercise_item->'restSeconds') <> 'number' then return false; end if;
      numeric_value := (exercise_item->>'restSeconds')::numeric;
      if numeric_value <> trunc(numeric_value) or numeric_value not between 0 and 900 then return false; end if;
      if exercise_item ? 'load' and jsonb_typeof(exercise_item->'load') not in ('number','null') then return false; end if;
      if jsonb_typeof(exercise_item->'load') = 'number' and (exercise_item->>'load')::numeric < 0 then return false; end if;
      if exercise_item ? 'notes' and jsonb_typeof(exercise_item->'notes') not in ('string','null') then return false; end if;
      if jsonb_typeof(exercise_item->'notes') = 'string' and char_length(exercise_item->>'notes') > 1000 then return false; end if;
      if jsonb_typeof(exercise_item->'sortOrder') <> 'number' then return false; end if;
      numeric_value := (exercise_item->>'sortOrder')::numeric;
      if numeric_value <> trunc(numeric_value) or numeric_value < 0 then return false; end if;
    end loop;
  end loop;
  return true;
exception when others then
  return false;
end;
$function$;
GRANT ALL ON FUNCTION public.validate_workout_plan_payload_v41b(jsonb) TO service_role;
CREATE TABLE public.account_plan_catalog (code text NOT NULL, account_type text NOT NULL, display_name text NOT NULL, active_client_limit integer, is_free boolean DEFAULT false NOT NULL, is_active boolean DEFAULT true NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.account_plan_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_plan_catalog ADD CONSTRAINT account_plan_catalog_account_type_check CHECK (account_type = ANY (ARRAY['individual'::text, 'trainer'::text, 'nutritionist'::text]));
ALTER TABLE public.account_plan_catalog ADD CONSTRAINT account_plan_catalog_active_client_limit_check CHECK (active_client_limit IS NULL OR active_client_limit >= 0);
ALTER TABLE public.account_plan_catalog ADD CONSTRAINT account_plan_catalog_code_format_check CHECK (code ~ '^[a-z][a-z0-9_]{2,49}$'::text);
ALTER TABLE public.account_plan_catalog ADD CONSTRAINT account_plan_catalog_code_type_key UNIQUE (code, account_type);
ALTER TABLE public.account_plan_catalog ADD CONSTRAINT account_plan_catalog_display_name_check CHECK (char_length(btrim(display_name)) >= 3 AND char_length(btrim(display_name)) <= 80);
ALTER TABLE public.account_plan_catalog ADD CONSTRAINT account_plan_catalog_pkey PRIMARY KEY (code);
GRANT SELECT ON public.account_plan_catalog TO authenticated;
GRANT ALL ON public.account_plan_catalog TO service_role;
CREATE POLICY account_plan_catalog_select_active_v41a1 ON public.account_plan_catalog FOR SELECT TO authenticated USING ((is_active = true));
CREATE TABLE public.evolution (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, record_date date NOT NULL, weight numeric(5,2), body_fat numeric(5,2), waist numeric(5,2), hip numeric(5,2), chest numeric(5,2), left_arm numeric(5,2), right_arm numeric(5,2), left_thigh numeric(5,2), right_thigh numeric(5,2), notes text, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.evolution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evolution ADD CONSTRAINT evolution_pkey PRIMARY KEY (id);
ALTER TABLE public.evolution ADD CONSTRAINT evolution_user_date_unique UNIQUE (user_id, record_date);
ALTER TABLE public.evolution ADD CONSTRAINT evolution_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT ALL ON public.evolution TO anon;
GRANT ALL ON public.evolution TO authenticated;
GRANT ALL ON public.evolution TO service_role;
CREATE INDEX evolution_user_id_idx ON public.evolution (user_id);
CREATE INDEX evolution_record_date_idx ON public.evolution (record_date);
CREATE INDEX evolution_user_date_idx ON public.evolution (user_id, record_date);
CREATE TRIGGER set_evolution_updated_at BEFORE UPDATE ON public.evolution FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE POLICY evolution_delete_own ON public.evolution FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY evolution_insert_own ON public.evolution FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY evolution_select_own ON public.evolution FOR SELECT USING ((auth.uid() = user_id));
CREATE POLICY evolution_update_own ON public.evolution FOR UPDATE USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
CREATE TABLE public.hydration (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, hydration_date date NOT NULL, total_ml integer DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.hydration ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hydration ADD CONSTRAINT hydration_pkey PRIMARY KEY (id);
ALTER TABLE public.hydration ADD CONSTRAINT hydration_user_date_unique UNIQUE (user_id, hydration_date);
ALTER TABLE public.hydration ADD CONSTRAINT hydration_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT ALL ON public.hydration TO anon;
GRANT ALL ON public.hydration TO authenticated;
GRANT ALL ON public.hydration TO service_role;
CREATE INDEX hydration_hydration_date_idx ON public.hydration (hydration_date);
CREATE INDEX hydration_user_id_idx ON public.hydration (user_id);
CREATE INDEX hydration_user_date_idx ON public.hydration (user_id, hydration_date);
CREATE TRIGGER set_hydration_updated_at BEFORE UPDATE ON public.hydration FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE POLICY hydration_delete_own ON public.hydration FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY hydration_insert_own ON public.hydration FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY hydration_select_own ON public.hydration FOR SELECT USING ((auth.uid() = user_id));
CREATE POLICY hydration_update_own ON public.hydration FOR UPDATE USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
CREATE TABLE public.meals (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, meal_date date NOT NULL, items jsonb DEFAULT '[]'::jsonb NOT NULL, total_calories numeric(10,2) DEFAULT 0 NOT NULL, total_protein numeric(10,2) DEFAULT 0 NOT NULL, total_carbs numeric(10,2) DEFAULT 0 NOT NULL, total_fat numeric(10,2) DEFAULT 0 NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meals ADD CONSTRAINT meals_pkey PRIMARY KEY (id);
ALTER TABLE public.meals ADD CONSTRAINT meals_user_date_unique UNIQUE (user_id, meal_date);
ALTER TABLE public.meals ADD CONSTRAINT meals_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT ALL ON public.meals TO anon;
GRANT ALL ON public.meals TO authenticated;
GRANT ALL ON public.meals TO service_role;
CREATE INDEX meals_user_date_idx ON public.meals (user_id, meal_date);
CREATE INDEX meals_meal_date_idx ON public.meals (meal_date);
CREATE INDEX meals_user_id_idx ON public.meals (user_id);
CREATE TRIGGER set_meals_updated_at BEFORE UPDATE ON public.meals FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE POLICY meals_delete_own ON public.meals FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY meals_insert_own ON public.meals FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY meals_select_own ON public.meals FOR SELECT USING ((auth.uid() = user_id));
CREATE POLICY meals_update_own ON public.meals FOR UPDATE USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
CREATE TABLE public.organization_members (id uuid DEFAULT gen_random_uuid() NOT NULL, organization_id uuid NOT NULL, user_id uuid NOT NULL, role text NOT NULL, status text DEFAULT 'pending'::text NOT NULL, created_by uuid, joined_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ADD CONSTRAINT organization_members_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.organization_members ADD CONSTRAINT organization_members_organization_user_key UNIQUE (organization_id, user_id);
ALTER TABLE public.organization_members ADD CONSTRAINT organization_members_pkey PRIMARY KEY (id);
ALTER TABLE public.organization_members ADD CONSTRAINT organization_members_role_check CHECK (role = ANY (ARRAY['owner'::text, 'admin'::text, 'trainer'::text, 'nutritionist'::text, 'student'::text]));
ALTER TABLE public.organization_members ADD CONSTRAINT organization_members_status_check CHECK (status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'revoked'::text]));
ALTER TABLE public.organization_members ADD CONSTRAINT organization_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT SELECT ON public.organization_members TO authenticated;
GRANT ALL ON public.organization_members TO service_role;
CREATE INDEX organization_members_org_role_status_idx ON public.organization_members (organization_id, role, status);
CREATE INDEX organization_members_user_id_idx ON public.organization_members (user_id);
CREATE INDEX organization_members_organization_id_idx ON public.organization_members (organization_id);
CREATE POLICY organization_members_select_scoped_v40b1 ON public.organization_members FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.has_organization_role(organization_id, ARRAY['owner'::text, 'admin'::text], auth.uid())));
CREATE TABLE public.organizations (id uuid DEFAULT gen_random_uuid() NOT NULL, name text NOT NULL, slug text NOT NULL, organization_type text NOT NULL, owner_user_id uuid NOT NULL, status text DEFAULT 'active'::text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations ADD CONSTRAINT organizations_name_check CHECK (char_length(btrim(name)) >= 2 AND char_length(btrim(name)) <= 120);
ALTER TABLE public.organizations ADD CONSTRAINT organizations_organization_type_check CHECK (organization_type = ANY (ARRAY['academy'::text, 'team'::text]));
ALTER TABLE public.organizations ADD CONSTRAINT organizations_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
ALTER TABLE public.organizations ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);
ALTER TABLE public.organization_members ADD CONSTRAINT organization_members_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.organizations ADD CONSTRAINT organizations_slug_check CHECK (char_length(slug) >= 3 AND char_length(slug) <= 60 AND slug ~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])$'::text);
ALTER TABLE public.organizations ADD CONSTRAINT organizations_status_check CHECK (status = ANY (ARRAY['active'::text, 'suspended'::text, 'archived'::text]));
GRANT SELECT ON public.organizations TO authenticated;
GRANT ALL ON public.organizations TO service_role;
CREATE INDEX organizations_owner_user_id_idx ON public.organizations (owner_user_id);
CREATE UNIQUE INDEX organizations_slug_lower_key ON public.organizations (lower(slug));
CREATE POLICY organizations_select_related_v40b1 ON public.organizations FOR SELECT TO authenticated USING (((owner_user_id = auth.uid()) OR public.is_organization_member(id, auth.uid())));
CREATE TABLE public.platform_user_roles (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, role text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, created_by uuid);
ALTER TABLE public.platform_user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_user_roles ADD CONSTRAINT platform_user_roles_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.platform_user_roles ADD CONSTRAINT platform_user_roles_pkey PRIMARY KEY (id);
ALTER TABLE public.platform_user_roles ADD CONSTRAINT platform_user_roles_role_check CHECK (role = ANY (ARRAY['platform_admin'::text, 'support'::text]));
ALTER TABLE public.platform_user_roles ADD CONSTRAINT platform_user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.platform_user_roles ADD CONSTRAINT platform_user_roles_user_role_key UNIQUE (user_id, role);
GRANT SELECT ON public.platform_user_roles TO authenticated;
GRANT ALL ON public.platform_user_roles TO service_role;
CREATE INDEX platform_user_roles_user_id_idx ON public.platform_user_roles (user_id);
CREATE POLICY platform_user_roles_select_own_v40b1 ON public.platform_user_roles FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE TABLE public.professional_nutrition_templates (id uuid DEFAULT gen_random_uuid() NOT NULL, owner_user_id uuid NOT NULL, organization_id uuid, title text NOT NULL, description text, plan_data jsonb NOT NULL, schema_version integer DEFAULT 1 NOT NULL, status text DEFAULT 'active'::text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.professional_nutrition_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.professional_nutrition_templates ADD CONSTRAINT professional_nutrition_templates_description_check CHECK (description IS NULL OR public.nutrition_text_is_safe_v41c(description, 2000));
ALTER TABLE public.professional_nutrition_templates ADD CONSTRAINT professional_nutrition_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);
ALTER TABLE public.professional_nutrition_templates ADD CONSTRAINT professional_nutrition_templates_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.professional_nutrition_templates ADD CONSTRAINT professional_nutrition_templates_pkey PRIMARY KEY (id);
ALTER TABLE public.professional_nutrition_templates ADD CONSTRAINT professional_nutrition_templates_plan_check CHECK (public.validate_nutrition_plan_payload_v41c(plan_data));
ALTER TABLE public.professional_nutrition_templates ADD CONSTRAINT professional_nutrition_templates_schema_version_check CHECK (schema_version = 1 AND schema_version = ((plan_data ->> 'schemaVersion'::text)::integer));
ALTER TABLE public.professional_nutrition_templates ADD CONSTRAINT professional_nutrition_templates_status_check CHECK (status = ANY (ARRAY['active'::text, 'archived'::text]));
ALTER TABLE public.professional_nutrition_templates ADD CONSTRAINT professional_nutrition_templates_title_check CHECK (char_length(btrim(title)) >= 2 AND char_length(btrim(title)) <= 120 AND public.nutrition_text_is_safe_v41c(title, 120));
GRANT SELECT ON public.professional_nutrition_templates TO authenticated;
GRANT ALL ON public.professional_nutrition_templates TO service_role;
CREATE INDEX professional_nutrition_templates_owner_idx ON public.professional_nutrition_templates (owner_user_id, status, updated_at DESC);
CREATE POLICY professional_nutrition_templates_select_own_v41c ON public.professional_nutrition_templates FOR SELECT TO authenticated USING ((owner_user_id = auth.uid()));
CREATE TABLE public.professional_student_relationships (id uuid DEFAULT gen_random_uuid() NOT NULL, professional_user_id uuid NOT NULL, student_user_id uuid NOT NULL, professional_type text NOT NULL, organization_id uuid, status text DEFAULT 'pending'::text NOT NULL, scopes jsonb DEFAULT jsonb_build_object('manage_workout_plan', false, 'view_workout_executions', false, 'manage_nutrition_plan', false, 'view_nutrition_logs', false, 'view_evolution', false) NOT NULL, requested_by uuid, accepted_at timestamp with time zone, revoked_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.professional_student_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.professional_student_relationships ADD CONSTRAINT professional_student_relationships_distinct_users CHECK (professional_user_id <> student_user_id);
ALTER TABLE public.professional_student_relationships ADD CONSTRAINT professional_student_relationships_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.professional_student_relationships ADD CONSTRAINT professional_student_relationships_pkey PRIMARY KEY (id);
ALTER TABLE public.professional_student_relationships ADD CONSTRAINT professional_student_relationships_professional_user_id_fkey FOREIGN KEY (professional_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.professional_student_relationships ADD CONSTRAINT professional_student_relationships_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.professional_student_relationships ADD CONSTRAINT professional_student_relationships_scopes_check CHECK (jsonb_typeof(scopes) = 'object'::text AND scopes ?& ARRAY['manage_workout_plan'::text, 'view_workout_executions'::text, 'manage_nutrition_plan'::text, 'view_nutrition_logs'::text, 'view_evolution'::text] AND jsonb_typeof(scopes -> 'manage_workout_plan'::text) = 'boolean'::text AND jsonb_typeof(scopes -> 'view_workout_executions'::text) = 'boolean'::text AND jsonb_typeof(scopes -> 'manage_nutrition_plan'::text) = 'boolean'::text AND jsonb_typeof(scopes -> 'view_nutrition_logs'::text) = 'boolean'::text AND jsonb_typeof(scopes -> 'view_evolution'::text) = 'boolean'::text AND (scopes - 'manage_workout_plan'::text - 'view_workout_executions'::text - 'manage_nutrition_plan'::text - 'view_nutrition_logs'::text - 'view_evolution'::text) = '{}'::jsonb AND (professional_type <> 'trainer'::text OR (scopes -> 'manage_nutrition_plan'::text) = 'false'::jsonb AND (scopes -> 'view_nutrition_logs'::text) = 'false'::jsonb) AND (professional_type <> 'nutritionist'::text OR (scopes -> 'manage_workout_plan'::text) = 'false'::jsonb AND (scopes -> 'view_workout_executions'::text) = 'false'::jsonb));
ALTER TABLE public.professional_student_relationships ADD CONSTRAINT professional_student_relationships_status_check CHECK (status = ANY (ARRAY['pending'::text, 'active'::text, 'rejected'::text, 'revoked'::text]));
ALTER TABLE public.professional_student_relationships ADD CONSTRAINT professional_student_relationships_student_user_id_fkey FOREIGN KEY (student_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.professional_student_relationships ADD CONSTRAINT professional_student_relationships_type_check CHECK (professional_type = ANY (ARRAY['trainer'::text, 'nutritionist'::text]));
GRANT SELECT ON public.professional_student_relationships TO authenticated;
GRANT ALL ON public.professional_student_relationships TO service_role;
CREATE INDEX professional_student_relationships_organization_idx ON public.professional_student_relationships (organization_id, status);
CREATE INDEX professional_student_relationships_professional_idx ON public.professional_student_relationships (professional_user_id, professional_type, status);
CREATE UNIQUE INDEX professional_student_relationships_org_context_key ON public.professional_student_relationships (professional_user_id, student_user_id, professional_type, organization_id) WHERE organization_id IS NOT NULL;
CREATE UNIQUE INDEX professional_student_relationships_independent_context_key ON public.professional_student_relationships (professional_user_id, student_user_id, professional_type) WHERE organization_id IS NULL;
CREATE INDEX professional_student_relationships_student_idx ON public.professional_student_relationships (student_user_id, status);
CREATE TRIGGER apply_default_professional_relationship_scopes_v41e1 BEFORE INSERT OR UPDATE ON public.professional_student_relationships FOR EACH ROW EXECUTE FUNCTION public.apply_default_professional_relationship_scopes_v41e1();
CREATE TRIGGER enforce_professional_client_limit_v41a2 BEFORE INSERT OR UPDATE OF status, professional_user_id, professional_type, student_user_id ON public.professional_student_relationships FOR EACH ROW EXECUTE FUNCTION public.enforce_professional_client_limit_v41a2();
CREATE TRIGGER notify_relationship_insert_v41c AFTER INSERT ON public.professional_student_relationships FOR EACH ROW EXECUTE FUNCTION public.notify_relationship_status_v41c();
CREATE TRIGGER notify_relationship_status_v41c AFTER UPDATE OF status ON public.professional_student_relationships FOR EACH ROW EXECUTE FUNCTION public.notify_relationship_status_v41c();
CREATE POLICY professional_student_relationships_select_scoped_v41a ON public.professional_student_relationships FOR SELECT TO authenticated USING (((professional_user_id = auth.uid()) OR (student_user_id = auth.uid()) OR ((organization_id IS NOT NULL) AND public.has_organization_role(organization_id, ARRAY['owner'::text, 'admin'::text], auth.uid()))));
CREATE TABLE public.professional_workout_templates (id uuid DEFAULT gen_random_uuid() NOT NULL, owner_user_id uuid NOT NULL, organization_id uuid, title text NOT NULL, description text, plan_data jsonb NOT NULL, schema_version integer DEFAULT 1 NOT NULL, status text DEFAULT 'active'::text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.professional_workout_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.professional_workout_templates ADD CONSTRAINT professional_workout_templates_description_check CHECK (description IS NULL OR char_length(description) <= 2000);
ALTER TABLE public.professional_workout_templates ADD CONSTRAINT professional_workout_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);
ALTER TABLE public.professional_workout_templates ADD CONSTRAINT professional_workout_templates_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.professional_workout_templates ADD CONSTRAINT professional_workout_templates_pkey PRIMARY KEY (id);
ALTER TABLE public.professional_workout_templates ADD CONSTRAINT professional_workout_templates_plan_check CHECK (public.validate_workout_plan_payload_v41b(plan_data));
ALTER TABLE public.professional_workout_templates ADD CONSTRAINT professional_workout_templates_schema_version_check CHECK (schema_version = 1 AND schema_version = ((plan_data ->> 'schemaVersion'::text)::integer));
ALTER TABLE public.professional_workout_templates ADD CONSTRAINT professional_workout_templates_status_check CHECK (status = ANY (ARRAY['active'::text, 'archived'::text]));
ALTER TABLE public.professional_workout_templates ADD CONSTRAINT professional_workout_templates_title_check CHECK (char_length(btrim(title)) >= 2 AND char_length(btrim(title)) <= 120);
GRANT SELECT ON public.professional_workout_templates TO authenticated;
GRANT ALL ON public.professional_workout_templates TO service_role;
CREATE INDEX professional_workout_templates_owner_idx ON public.professional_workout_templates (owner_user_id, status, updated_at DESC);
CREATE POLICY professional_workout_templates_select_own_v41b ON public.professional_workout_templates FOR SELECT TO authenticated USING ((owner_user_id = auth.uid()));
CREATE TABLE public.profiles (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, name text, email text, gender text, birth_date date, height numeric(5,2), weight_goal numeric(5,2), goal text, theme text, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL, full_name text, display_name text, phone text, timezone text, locale text DEFAULT 'pt-BR'::text, onboarding_completed boolean DEFAULT false NOT NULL, onboarding_step integer DEFAULT 0 NOT NULL);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);
ALTER TABLE public.profiles ADD CONSTRAINT profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_user_id_key UNIQUE (user_id);
GRANT ALL ON public.profiles TO anon;
GRANT ALL ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
CREATE INDEX profiles_user_id_idx ON public.profiles (user_id);
CREATE TRIGGER set_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE POLICY profiles_delete_own ON public.profiles FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY profiles_insert_own_v40a2 ON public.profiles FOR INSERT TO authenticated WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));
CREATE POLICY profiles_select_own_v40a2 ON public.profiles FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));
CREATE POLICY profiles_update_own_v40a2 ON public.profiles FOR UPDATE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));
CREATE TABLE public.student_nutrition_assignments (id uuid DEFAULT gen_random_uuid() NOT NULL, relationship_id uuid NOT NULL, template_id uuid, assignment_version integer NOT NULL, title_snapshot text NOT NULL, description_snapshot text, plan_data_snapshot jsonb NOT NULL, schema_version integer DEFAULT 1 NOT NULL, status text DEFAULT 'active'::text NOT NULL, assigned_at timestamp with time zone DEFAULT now() NOT NULL, effective_from date, effective_until date, superseded_at timestamp with time zone, revoked_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.student_nutrition_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_description_check CHECK (description_snapshot IS NULL OR public.nutrition_text_is_safe_v41c(description_snapshot, 2000));
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_effective_dates_check CHECK (effective_until IS NULL OR effective_from IS NULL OR effective_until >= effective_from);
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_pkey PRIMARY KEY (id);
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_plan_check CHECK (public.validate_nutrition_plan_payload_v41c(plan_data_snapshot));
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_relationship_id_fkey FOREIGN KEY (relationship_id) REFERENCES public.professional_student_relationships(id);
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_relationship_version_key UNIQUE (relationship_id, assignment_version);
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_schema_version_check CHECK (schema_version = 1 AND schema_version = ((plan_data_snapshot ->> 'schemaVersion'::text)::integer));
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_status_check CHECK (status = ANY (ARRAY['active'::text, 'superseded'::text, 'revoked'::text]));
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_status_timestamps_check CHECK (status = 'active'::text AND superseded_at IS NULL AND revoked_at IS NULL OR status = 'superseded'::text AND superseded_at IS NOT NULL AND revoked_at IS NULL OR status = 'revoked'::text AND revoked_at IS NOT NULL AND superseded_at IS NULL);
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.professional_nutrition_templates(id) ON DELETE SET NULL;
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_title_check CHECK (char_length(btrim(title_snapshot)) >= 2 AND char_length(btrim(title_snapshot)) <= 120 AND public.nutrition_text_is_safe_v41c(title_snapshot, 120));
ALTER TABLE public.student_nutrition_assignments ADD CONSTRAINT student_nutrition_assignments_version_check CHECK (assignment_version >= 1);
GRANT SELECT ON public.student_nutrition_assignments TO authenticated;
GRANT ALL ON public.student_nutrition_assignments TO service_role;
CREATE INDEX student_nutrition_assignments_relationship_idx ON public.student_nutrition_assignments (relationship_id, assignment_version DESC);
CREATE UNIQUE INDEX student_nutrition_assignments_one_active_idx ON public.student_nutrition_assignments (relationship_id) WHERE status = 'active'::text;
CREATE TRIGGER notify_nutrition_assignment_insert_v41c AFTER INSERT ON public.student_nutrition_assignments FOR EACH ROW EXECUTE FUNCTION public.notify_nutrition_assignment_v41c();
CREATE TRIGGER notify_nutrition_assignment_status_v41c AFTER UPDATE OF status ON public.student_nutrition_assignments FOR EACH ROW EXECUTE FUNCTION public.notify_nutrition_assignment_v41c();
CREATE TRIGGER protect_nutrition_assignment_snapshot_v41c BEFORE UPDATE ON public.student_nutrition_assignments FOR EACH ROW EXECUTE FUNCTION public.protect_nutrition_assignment_snapshot_v41c();
CREATE POLICY student_nutrition_assignments_select_participant_v41c ON public.student_nutrition_assignments FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.professional_student_relationships relationship
  WHERE ((relationship.id = student_nutrition_assignments.relationship_id) AND ((relationship.student_user_id = auth.uid()) OR ((relationship.professional_user_id = auth.uid()) AND (relationship.professional_type = 'nutritionist'::text) AND (relationship.status = 'active'::text) AND (relationship.scopes @> '{"manage_nutrition_plan": true}'::jsonb)))))));
CREATE TABLE public.student_workout_assignments (id uuid DEFAULT gen_random_uuid() NOT NULL, relationship_id uuid NOT NULL, template_id uuid, assignment_version integer NOT NULL, title_snapshot text NOT NULL, description_snapshot text, plan_data_snapshot jsonb NOT NULL, schema_version integer DEFAULT 1 NOT NULL, status text DEFAULT 'active'::text NOT NULL, assigned_at timestamp with time zone DEFAULT now() NOT NULL, effective_from date, superseded_at timestamp with time zone, revoked_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.student_workout_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_description_check CHECK (description_snapshot IS NULL OR char_length(description_snapshot) <= 2000);
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_pkey PRIMARY KEY (id);
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_plan_check CHECK (public.validate_workout_plan_payload_v41b(plan_data_snapshot));
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_relationship_id_fkey FOREIGN KEY (relationship_id) REFERENCES public.professional_student_relationships(id);
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_relationship_version_key UNIQUE (relationship_id, assignment_version);
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_schema_version_check CHECK (schema_version = 1 AND schema_version = ((plan_data_snapshot ->> 'schemaVersion'::text)::integer));
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_status_check CHECK (status = ANY (ARRAY['active'::text, 'superseded'::text, 'revoked'::text]));
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_status_timestamps_check CHECK (status = 'active'::text AND superseded_at IS NULL AND revoked_at IS NULL OR status = 'superseded'::text AND superseded_at IS NOT NULL AND revoked_at IS NULL OR status = 'revoked'::text AND revoked_at IS NOT NULL AND superseded_at IS NULL);
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.professional_workout_templates(id) ON DELETE SET NULL;
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_title_check CHECK (char_length(btrim(title_snapshot)) >= 2 AND char_length(btrim(title_snapshot)) <= 120);
ALTER TABLE public.student_workout_assignments ADD CONSTRAINT student_workout_assignments_version_check CHECK (assignment_version >= 1);
GRANT SELECT ON public.student_workout_assignments TO authenticated;
GRANT ALL ON public.student_workout_assignments TO service_role;
CREATE INDEX student_workout_assignments_relationship_idx ON public.student_workout_assignments (relationship_id, assignment_version DESC);
CREATE UNIQUE INDEX student_workout_assignments_one_active_idx ON public.student_workout_assignments (relationship_id) WHERE status = 'active'::text;
CREATE TRIGGER notify_workout_assignment_insert_v41c AFTER INSERT ON public.student_workout_assignments FOR EACH ROW EXECUTE FUNCTION public.notify_workout_assignment_v41c();
CREATE TRIGGER notify_workout_assignment_status_v41c AFTER UPDATE OF status ON public.student_workout_assignments FOR EACH ROW EXECUTE FUNCTION public.notify_workout_assignment_v41c();
CREATE TRIGGER protect_workout_assignment_snapshot_v41b BEFORE UPDATE ON public.student_workout_assignments FOR EACH ROW EXECUTE FUNCTION public.protect_workout_assignment_snapshot_v41b();
CREATE POLICY student_workout_assignments_select_participant_v41b ON public.student_workout_assignments FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.professional_student_relationships relationship
  WHERE ((relationship.id = student_workout_assignments.relationship_id) AND ((relationship.professional_user_id = auth.uid()) OR (relationship.student_user_id = auth.uid()))))));
CREATE TABLE public.trainer_student_invitations (id uuid DEFAULT gen_random_uuid() NOT NULL, trainer_user_id uuid NOT NULL, invite_code_hash text NOT NULL, invite_code_prefix text NOT NULL, status text DEFAULT 'pending'::text NOT NULL, expires_at timestamp with time zone NOT NULL, accepted_by_user_id uuid, accepted_at timestamp with time zone, cancelled_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.trainer_student_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trainer_student_invitations ADD CONSTRAINT trainer_student_invitations_accepted_by_user_id_fkey FOREIGN KEY (accepted_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.trainer_student_invitations ADD CONSTRAINT trainer_student_invitations_hash_key UNIQUE (invite_code_hash);
ALTER TABLE public.trainer_student_invitations ADD CONSTRAINT trainer_student_invitations_pkey PRIMARY KEY (id);
ALTER TABLE public.trainer_student_invitations ADD CONSTRAINT trainer_student_invitations_status_check CHECK (status = ANY (ARRAY['pending'::text, 'accepted'::text, 'cancelled'::text, 'expired'::text]));
ALTER TABLE public.trainer_student_invitations ADD CONSTRAINT trainer_student_invitations_trainer_user_id_fkey FOREIGN KEY (trainer_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT ALL ON public.trainer_student_invitations TO service_role;
CREATE INDEX trainer_student_invitations_expires_idx ON public.trainer_student_invitations (expires_at);
CREATE INDEX trainer_student_invitations_accepted_by_idx ON public.trainer_student_invitations (accepted_by_user_id);
CREATE INDEX trainer_student_invitations_trainer_idx ON public.trainer_student_invitations (trainer_user_id);
CREATE INDEX trainer_student_invitations_trainer_status_idx ON public.trainer_student_invitations (trainer_user_id, status);
CREATE INDEX trainer_student_invitations_status_idx ON public.trainer_student_invitations (status);
CREATE POLICY trainer_student_invitations_select_related_v40b2 ON public.trainer_student_invitations FOR SELECT TO authenticated USING (((trainer_user_id = auth.uid()) OR ((status = 'accepted'::text) AND (accepted_by_user_id = auth.uid()))));
CREATE TABLE public.trainer_student_relationships (id uuid DEFAULT gen_random_uuid() NOT NULL, trainer_user_id uuid NOT NULL, student_user_id uuid NOT NULL, organization_id uuid, status text DEFAULT 'pending'::text NOT NULL, permissions jsonb DEFAULT jsonb_build_object('view_workouts', false, 'assign_workouts', false, 'view_executions', false, 'view_evolution', false, 'view_nutrition', false) NOT NULL, requested_by uuid, accepted_at timestamp with time zone, revoked_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.trainer_student_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trainer_student_relationships ADD CONSTRAINT trainer_student_relationships_distinct_users CHECK (trainer_user_id <> student_user_id);
ALTER TABLE public.trainer_student_relationships ADD CONSTRAINT trainer_student_relationships_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.trainer_student_relationships ADD CONSTRAINT trainer_student_relationships_permissions_check CHECK (jsonb_typeof(permissions) = 'object'::text AND permissions ?& ARRAY['view_workouts'::text, 'assign_workouts'::text, 'view_executions'::text, 'view_evolution'::text, 'view_nutrition'::text] AND jsonb_typeof(permissions -> 'view_workouts'::text) = 'boolean'::text AND jsonb_typeof(permissions -> 'assign_workouts'::text) = 'boolean'::text AND jsonb_typeof(permissions -> 'view_executions'::text) = 'boolean'::text AND jsonb_typeof(permissions -> 'view_evolution'::text) = 'boolean'::text AND jsonb_typeof(permissions -> 'view_nutrition'::text) = 'boolean'::text AND (permissions - 'view_workouts'::text - 'assign_workouts'::text - 'view_executions'::text - 'view_evolution'::text - 'view_nutrition'::text) = '{}'::jsonb);
ALTER TABLE public.trainer_student_relationships ADD CONSTRAINT trainer_student_relationships_pkey PRIMARY KEY (id);
ALTER TABLE public.trainer_student_relationships ADD CONSTRAINT trainer_student_relationships_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.trainer_student_relationships ADD CONSTRAINT trainer_student_relationships_status_check CHECK (status = ANY (ARRAY['pending'::text, 'active'::text, 'revoked'::text, 'rejected'::text]));
ALTER TABLE public.trainer_student_relationships ADD CONSTRAINT trainer_student_relationships_student_user_id_fkey FOREIGN KEY (student_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.trainer_student_relationships ADD CONSTRAINT trainer_student_relationships_trainer_user_id_fkey FOREIGN KEY (trainer_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT SELECT ON public.trainer_student_relationships TO authenticated;
GRANT ALL ON public.trainer_student_relationships TO service_role;
CREATE INDEX trainer_student_relationships_student_idx ON public.trainer_student_relationships (student_user_id);
CREATE INDEX trainer_student_relationships_trainer_idx ON public.trainer_student_relationships (trainer_user_id);
CREATE INDEX trainer_student_relationships_organization_idx ON public.trainer_student_relationships (organization_id);
CREATE INDEX trainer_student_relationships_status_idx ON public.trainer_student_relationships (status);
CREATE UNIQUE INDEX trainer_student_relationships_org_context_key ON public.trainer_student_relationships (trainer_user_id, student_user_id, organization_id) WHERE organization_id IS NOT NULL;
CREATE UNIQUE INDEX trainer_student_relationships_independent_context_key ON public.trainer_student_relationships (trainer_user_id, student_user_id) WHERE organization_id IS NULL;
CREATE TRIGGER sync_legacy_trainer_relationship_v41a AFTER INSERT OR DELETE OR UPDATE ON public.trainer_student_relationships FOR EACH ROW EXECUTE FUNCTION public.sync_legacy_trainer_relationship_v41a();
CREATE POLICY trainer_student_relationships_select_scoped_v40b1 ON public.trainer_student_relationships FOR SELECT TO authenticated USING (((trainer_user_id = auth.uid()) OR (student_user_id = auth.uid()) OR ((organization_id IS NOT NULL) AND public.has_organization_role(organization_id, ARRAY['owner'::text, 'admin'::text], auth.uid()))));
CREATE TABLE public.user_account_modes (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, mode text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.user_account_modes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_account_modes ADD CONSTRAINT user_account_modes_mode_check CHECK (mode = ANY (ARRAY['individual'::text, 'student'::text, 'trainer'::text, 'nutritionist'::text]));
ALTER TABLE public.user_account_modes ADD CONSTRAINT user_account_modes_pkey PRIMARY KEY (id);
ALTER TABLE public.user_account_modes ADD CONSTRAINT user_account_modes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.user_account_modes ADD CONSTRAINT user_account_modes_user_mode_key UNIQUE (user_id, mode);
GRANT SELECT ON public.user_account_modes TO authenticated;
GRANT ALL ON public.user_account_modes TO service_role;
CREATE INDEX user_account_modes_user_id_idx ON public.user_account_modes (user_id);
CREATE POLICY user_account_modes_select_own_v40b2 ON public.user_account_modes FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE TABLE public.user_commercial_accounts (user_id uuid NOT NULL, primary_account_type text, plan_code text, subscription_status text DEFAULT 'active'::text NOT NULL, personal_use_enabled boolean DEFAULT true NOT NULL, account_type_selected_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.user_commercial_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_commercial_accounts ADD CONSTRAINT user_commercial_accounts_pkey PRIMARY KEY (user_id);
ALTER TABLE public.user_commercial_accounts ADD CONSTRAINT user_commercial_accounts_plan_type_fk FOREIGN KEY (plan_code, primary_account_type) REFERENCES public.account_plan_catalog(code, account_type) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE public.user_commercial_accounts ADD CONSTRAINT user_commercial_accounts_primary_account_type_check CHECK (primary_account_type = ANY (ARRAY['individual'::text, 'trainer'::text, 'nutritionist'::text]));
ALTER TABLE public.user_commercial_accounts ADD CONSTRAINT user_commercial_accounts_subscription_status_check CHECK (subscription_status = ANY (ARRAY['active'::text, 'trialing'::text, 'inactive'::text, 'past_due'::text, 'canceled'::text]));
ALTER TABLE public.user_commercial_accounts ADD CONSTRAINT user_commercial_accounts_type_plan_pair_check CHECK ((primary_account_type IS NULL) = (plan_code IS NULL));
ALTER TABLE public.user_commercial_accounts ADD CONSTRAINT user_commercial_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT SELECT ON public.user_commercial_accounts TO authenticated;
GRANT ALL ON public.user_commercial_accounts TO service_role;
CREATE INDEX user_commercial_accounts_plan_idx ON public.user_commercial_accounts (plan_code);
CREATE POLICY user_commercial_accounts_select_own_v41a1 ON public.user_commercial_accounts FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE TABLE public.user_identity_details (user_id uuid NOT NULL, birth_date date NOT NULL, age_status text NOT NULL, age_verified_at timestamp with time zone, country_code text DEFAULT 'BR'::text NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.user_identity_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_identity_details ADD CONSTRAINT user_identity_details_age_status_check CHECK (age_status = ANY (ARRAY['adult'::text, 'minor'::text, 'unknown'::text]));
ALTER TABLE public.user_identity_details ADD CONSTRAINT user_identity_details_country_code_check CHECK (country_code ~ '^[A-Z]{2}$'::text);
ALTER TABLE public.user_identity_details ADD CONSTRAINT user_identity_details_pkey PRIMARY KEY (user_id);
ALTER TABLE public.user_identity_details ADD CONSTRAINT user_identity_details_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT SELECT ON public.user_identity_details TO authenticated;
GRANT ALL ON public.user_identity_details TO service_role;
CREATE TRIGGER validate_user_identity_birth_date_v41a1 BEFORE INSERT OR UPDATE OF birth_date ON public.user_identity_details FOR EACH ROW EXECUTE FUNCTION public.validate_user_identity_birth_date_v41a1();
CREATE POLICY user_identity_details_select_own_v41a1 ON public.user_identity_details FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE TABLE public.user_legal_acceptances (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, document_type text NOT NULL, document_version text NOT NULL, accepted_at timestamp with time zone DEFAULT now() NOT NULL, created_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.user_legal_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_legal_acceptances ADD CONSTRAINT user_legal_acceptances_document_type_check CHECK (document_type = ANY (ARRAY['terms'::text, 'privacy'::text]));
ALTER TABLE public.user_legal_acceptances ADD CONSTRAINT user_legal_acceptances_document_version_check CHECK (document_version ~ '^[a-z]+-[0-9]{4}-[0-9]{2}$'::text);
ALTER TABLE public.user_legal_acceptances ADD CONSTRAINT user_legal_acceptances_pkey PRIMARY KEY (id);
ALTER TABLE public.user_legal_acceptances ADD CONSTRAINT user_legal_acceptances_user_document_version_key UNIQUE (user_id, document_type, document_version);
ALTER TABLE public.user_legal_acceptances ADD CONSTRAINT user_legal_acceptances_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT SELECT ON public.user_legal_acceptances TO authenticated;
GRANT ALL ON public.user_legal_acceptances TO service_role;
CREATE INDEX user_legal_acceptances_user_idx ON public.user_legal_acceptances (user_id, document_type);
CREATE POLICY user_legal_acceptances_select_own_v41a1 ON public.user_legal_acceptances FOR SELECT TO authenticated USING ((user_id = auth.uid()));
CREATE TABLE public.user_notifications (id uuid DEFAULT gen_random_uuid() NOT NULL, recipient_user_id uuid NOT NULL, actor_user_id uuid, notification_type text NOT NULL, title text NOT NULL, message text NOT NULL, entity_type text, entity_id uuid, dedupe_key text, metadata jsonb DEFAULT '{}'::jsonb NOT NULL, read_at timestamp with time zone, created_at timestamp with time zone DEFAULT now() NOT NULL, expires_at timestamp with time zone);
ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_dedupe_key_check CHECK (dedupe_key IS NULL OR dedupe_key = btrim(dedupe_key) AND char_length(btrim(dedupe_key)) >= 1 AND char_length(btrim(dedupe_key)) <= 200);
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_entity_type_check CHECK (entity_type IS NULL OR (entity_type = ANY (ARRAY['relationship'::text, 'workout_assignment'::text, 'nutrition_assignment'::text, 'system'::text])));
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_expiry_check CHECK (expires_at IS NULL OR expires_at > created_at);
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_message_check CHECK (char_length(btrim(message)) >= 1 AND char_length(btrim(message)) <= 500);
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_metadata_object_check CHECK (jsonb_typeof(metadata) = 'object'::text);
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_metadata_safe_check CHECK (jsonb_typeof(metadata) = 'object'::text AND octet_length(metadata::text) <= 8192 AND public.notification_metadata_is_safe_v41c(metadata));
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_pkey PRIMARY KEY (id);
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_title_check CHECK (char_length(btrim(title)) >= 1 AND char_length(btrim(title)) <= 120);
ALTER TABLE public.user_notifications ADD CONSTRAINT user_notifications_type_check CHECK (notification_type = ANY (ARRAY['relationship_activated'::text, 'relationship_revoked'::text, 'workout_plan_assigned'::text, 'workout_plan_updated'::text, 'workout_plan_revoked'::text, 'nutrition_plan_assigned'::text, 'nutrition_plan_updated'::text, 'nutrition_plan_revoked'::text, 'system'::text]));
GRANT SELECT ON public.user_notifications TO authenticated;
GRANT ALL ON public.user_notifications TO service_role;
CREATE INDEX user_notifications_recipient_read_created_idx ON public.user_notifications (recipient_user_id, read_at, created_at DESC);
CREATE UNIQUE INDEX user_notifications_recipient_dedupe_idx ON public.user_notifications (recipient_user_id, dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE INDEX user_notifications_unread_idx ON public.user_notifications (recipient_user_id, created_at DESC) WHERE read_at IS NULL;
CREATE POLICY user_notifications_select_own_v41c ON public.user_notifications FOR SELECT TO authenticated USING (((recipient_user_id = auth.uid()) AND ((expires_at IS NULL) OR (expires_at > now()))));
CREATE TABLE public.workouts (id uuid DEFAULT gen_random_uuid() NOT NULL, user_id uuid NOT NULL, workout_date date NOT NULL, name text, exercises jsonb DEFAULT '[]'::jsonb NOT NULL, total_volume numeric(12,2) DEFAULT 0 NOT NULL, duration_minutes integer, created_at timestamp with time zone DEFAULT now() NOT NULL, updated_at timestamp with time zone DEFAULT now() NOT NULL);
ALTER TABLE public.workouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workouts ADD CONSTRAINT workouts_pkey PRIMARY KEY (id);
ALTER TABLE public.workouts ADD CONSTRAINT workouts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
GRANT ALL ON public.workouts TO anon;
GRANT ALL ON public.workouts TO authenticated;
GRANT ALL ON public.workouts TO service_role;
CREATE INDEX workouts_workout_date_idx ON public.workouts (workout_date);
CREATE INDEX workouts_user_date_id_v41d_idx ON public.workouts (user_id, workout_date DESC, id DESC);
CREATE INDEX workouts_user_id_idx ON public.workouts (user_id);
CREATE INDEX workouts_user_date_idx ON public.workouts (user_id, workout_date);
CREATE TRIGGER set_workouts_updated_at BEFORE UPDATE ON public.workouts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE POLICY workouts_delete_own ON public.workouts FOR DELETE USING ((auth.uid() = user_id));
CREATE POLICY workouts_insert_own ON public.workouts FOR INSERT WITH CHECK ((auth.uid() = user_id));
CREATE POLICY workouts_select_own ON public.workouts FOR SELECT USING ((auth.uid() = user_id));
CREATE POLICY workouts_update_own ON public.workouts FOR UPDATE USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));
COMMENT ON INDEX public.workouts_user_date_id_v41d_idx IS 'FORJA V4.1D professional monitoring';
