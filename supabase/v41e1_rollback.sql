begin;

drop trigger if exists apply_default_professional_relationship_scopes_v41e1 on public.professional_student_relationships;
drop function if exists public.apply_default_professional_relationship_scopes_v41e1();
drop function if exists public.default_professional_relationship_scopes_v41e1(text);
drop function if exists public.set_my_professional_relationship_scopes(uuid, jsonb);

create or replace function public.accept_trainer_student_invitation(invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := auth.uid();
  normalized_code text;
  code_hash text;
  invitation record;
  relationship_id uuid;
  relationship_permissions jsonb;
  safe_permissions jsonb := pg_catalog.jsonb_build_object(
    'view_workouts', false,
    'assign_workouts', false,
    'view_executions', false,
    'view_evolution', false,
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
  select * into invitation from public.trainer_student_invitations where invite_code_hash = code_hash for update;
  if not found or invitation.status <> 'pending' then
    return pg_catalog.jsonb_build_object('accepted', false, 'message', 'Este código não é válido ou não está mais disponível.');
  end if;
  if invitation.expires_at <= now() then
    update public.trainer_student_invitations set status = 'expired', updated_at = now() where id = invitation.id;
    return pg_catalog.jsonb_build_object('accepted', false, 'message', 'Este convite não está mais disponível.');
  end if;
  if invitation.trainer_user_id = current_user_id then
    return pg_catalog.jsonb_build_object('accepted', false, 'message', 'Você não pode aceitar um convite criado pela sua própria conta.');
  end if;
  insert into public.trainer_student_relationships (trainer_user_id, student_user_id, organization_id, status, permissions, requested_by, accepted_at)
  values (invitation.trainer_user_id, current_user_id, null, 'active', safe_permissions, invitation.trainer_user_id, now())
  on conflict (trainer_user_id, student_user_id) where organization_id is null
  do update set
    status = 'active',
    permissions = case when public.trainer_student_relationships.status = 'active' then public.trainer_student_relationships.permissions else excluded.permissions end,
    accepted_at = case when public.trainer_student_relationships.status = 'active' then public.trainer_student_relationships.accepted_at else excluded.accepted_at end,
    revoked_at = null,
    updated_at = now()
  returning id, permissions into relationship_id, relationship_permissions;
  insert into public.user_account_modes(user_id, mode) values (current_user_id, 'student') on conflict (user_id, mode) do update set updated_at = now();
  update public.trainer_student_invitations set status = 'accepted', accepted_by_user_id = current_user_id, accepted_at = now(), updated_at = now() where id = invitation.id;
  return pg_catalog.jsonb_build_object('accepted', true, 'relationship_id', relationship_id, 'status', 'active', 'permissions', relationship_permissions);
end;
$function$;

commit;
