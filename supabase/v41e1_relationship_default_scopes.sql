begin;

do $v41e1_required_schema$
declare
  missing_object text;
begin
  select required.object_name
  into missing_object
  from (values
    ('public.professional_student_relationships', 'public.professional_student_relationships'),
    ('public.professional_student_relationships.id', 'public.professional_student_relationships.id'),
    ('public.professional_student_relationships.professional_type', 'public.professional_student_relationships.professional_type'),
    ('public.professional_student_relationships.status', 'public.professional_student_relationships.status'),
    ('public.professional_student_relationships.scopes', 'public.professional_student_relationships.scopes'),
    ('public.trainer_student_relationships', 'public.trainer_student_relationships'),
    ('public.trainer_student_relationships.permissions', 'public.trainer_student_relationships.permissions')
  ) as required(object_name, object_key)
  where (required.object_key in ('public.professional_student_relationships', 'public.trainer_student_relationships')
         and pg_catalog.to_regclass(required.object_key) is null)
     or (required.object_key not in ('public.professional_student_relationships', 'public.trainer_student_relationships') and not exists (
       select 1
       from pg_catalog.pg_attribute attribute
       where attribute.attrelid = pg_catalog.to_regclass(pg_catalog.split_part(required.object_key, '.', 1) || '.' || pg_catalog.split_part(required.object_key, '.', 2))
         and attribute.attname = pg_catalog.split_part(required.object_key, '.', 3)
         and attribute.attnum > 0
         and not attribute.attisdropped
     ))
  order by required.object_name
  limit 1;

  if missing_object is not null then
    raise exception 'v41e1_missing_required_object: %', missing_object using errcode = '42703';
  end if;
end;
$v41e1_required_schema$;

drop function if exists public.set_my_professional_relationship_scopes(uuid, jsonb);

create or replace function public.default_professional_relationship_scopes_v41e1(
  target_professional_type text
) returns jsonb
language plpgsql
set search_path = ''
as $function$
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

create or replace function public.apply_default_professional_relationship_scopes_v41e1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  new.scopes := public.default_professional_relationship_scopes_v41e1(new.professional_type);
  return new;
end;
$function$;

revoke execute on function public.default_professional_relationship_scopes_v41e1(text) from public, anon, authenticated;
revoke execute on function public.apply_default_professional_relationship_scopes_v41e1() from public, anon, authenticated;

drop trigger if exists apply_default_professional_relationship_scopes_v41e1 on public.professional_student_relationships;
create trigger apply_default_professional_relationship_scopes_v41e1
before insert or update on public.professional_student_relationships
for each row
execute function public.apply_default_professional_relationship_scopes_v41e1();

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

revoke update on table public.professional_student_relationships from public, anon, authenticated;
revoke update on table public.trainer_student_relationships from public, anon, authenticated;

update public.trainer_student_relationships
set permissions = pg_catalog.jsonb_build_object(
  'view_workouts', true,
  'assign_workouts', true,
  'view_executions', true,
  'view_evolution', true,
  'view_nutrition', false
)
where status = 'active';

update public.professional_student_relationships
set scopes = public.default_professional_relationship_scopes_v41e1(professional_type)
where status = 'active';

commit;
