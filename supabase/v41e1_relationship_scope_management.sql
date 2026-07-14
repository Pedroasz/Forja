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
    ('public.professional_student_relationships.student_user_id', 'public.professional_student_relationships.student_user_id'),
    ('public.professional_student_relationships.professional_type', 'public.professional_student_relationships.professional_type'),
    ('public.professional_student_relationships.status', 'public.professional_student_relationships.status'),
    ('public.professional_student_relationships.scopes', 'public.professional_student_relationships.scopes')
  ) as required(object_name, object_key)
  where (required.object_key = 'public.professional_student_relationships' and pg_catalog.to_regclass(required.object_key) is null)
     or (required.object_key <> 'public.professional_student_relationships' and not exists (
       select 1
       from pg_catalog.pg_attribute attribute
       where attribute.attrelid = pg_catalog.to_regclass('public.professional_student_relationships')
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

create or replace function public.set_my_professional_relationship_scopes(
  target_relationship_id uuid,
  target_scopes jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  relationship_record public.professional_student_relationships%rowtype;
  normalized_scopes jsonb;
  requested_key text;
  requested_value jsonb;
  legacy_permissions jsonb;
  legacy_row_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'session_required' using errcode = '42501';
  end if;
  if target_relationship_id is null then
    raise exception 'relationship_required' using errcode = '22023';
  end if;
  if target_scopes is null or pg_catalog.jsonb_typeof(target_scopes) <> 'object' then
    raise exception 'relationship_scopes_must_be_object' using errcode = '22023';
  end if;

  select *
  into relationship_record
  from public.professional_student_relationships relationship
  where relationship.id = target_relationship_id
    and relationship.student_user_id = auth.uid()
  for update;

  if not found then
    raise exception 'relationship_student_only' using errcode = '42501';
  end if;
  if relationship_record.status <> 'active' then
    raise exception 'relationship_inactive' using errcode = '42501';
  end if;
  if relationship_record.professional_type not in ('trainer', 'nutritionist') then
    raise exception 'invalid_professional_type' using errcode = '22023';
  end if;

  for requested_key, requested_value in
    select key, value from pg_catalog.jsonb_each(target_scopes)
  loop
    if requested_key not in (
      'manage_workout_plan',
      'view_workout_executions',
      'manage_nutrition_plan',
      'view_nutrition_logs',
      'view_evolution'
    ) then
      raise exception 'relationship_scope_unknown_key' using errcode = '22023';
    end if;
    if pg_catalog.jsonb_typeof(requested_value) <> 'boolean' then
      raise exception 'relationship_scope_value_must_be_boolean' using errcode = '22023';
    end if;
    if relationship_record.professional_type = 'trainer'
       and requested_key in ('manage_nutrition_plan', 'view_nutrition_logs') then
      raise exception 'relationship_scope_not_allowed_for_trainer' using errcode = '22023';
    end if;
    if relationship_record.professional_type = 'nutritionist'
       and requested_key in ('manage_workout_plan', 'view_workout_executions') then
      raise exception 'relationship_scope_not_allowed_for_nutritionist' using errcode = '22023';
    end if;
  end loop;

  if relationship_record.professional_type = 'trainer' then
    normalized_scopes := pg_catalog.jsonb_build_object(
      'manage_workout_plan', coalesce((target_scopes ->> 'manage_workout_plan')::boolean, false),
      'view_workout_executions', coalesce((target_scopes ->> 'view_workout_executions')::boolean, false),
      'manage_nutrition_plan', false,
      'view_nutrition_logs', false,
      'view_evolution', coalesce((target_scopes ->> 'view_evolution')::boolean, false)
    );
  else
    normalized_scopes := pg_catalog.jsonb_build_object(
      'manage_workout_plan', false,
      'view_workout_executions', false,
      'manage_nutrition_plan', coalesce((target_scopes ->> 'manage_nutrition_plan')::boolean, false),
      'view_nutrition_logs', coalesce((target_scopes ->> 'view_nutrition_logs')::boolean, false),
      'view_evolution', coalesce((target_scopes ->> 'view_evolution')::boolean, false)
    );
  end if;

  if relationship_record.professional_type = 'trainer'
     and pg_catalog.to_regclass('public.trainer_student_relationships') is not null then
    execute 'select permissions from public.trainer_student_relationships where id = $1 for update'
      into legacy_permissions
      using relationship_record.id;
    get diagnostics legacy_row_count = row_count;
  end if;

  if legacy_row_count > 0 then
    legacy_permissions := pg_catalog.jsonb_build_object(
      'assign_workouts', normalized_scopes -> 'manage_workout_plan',
      'view_workouts', normalized_scopes -> 'manage_workout_plan',
      'view_executions', normalized_scopes -> 'view_workout_executions',
      'view_evolution', normalized_scopes -> 'view_evolution',
      'view_nutrition', false
    );
    execute 'update public.trainer_student_relationships set permissions = $1 where id = $2'
      using legacy_permissions, relationship_record.id;
  else
    update public.professional_student_relationships
    set scopes = normalized_scopes
    where id = relationship_record.id
      and student_user_id = auth.uid();
  end if;

  return pg_catalog.jsonb_build_object('scopes', normalized_scopes);
end;
$function$;

revoke execute on function public.set_my_professional_relationship_scopes(uuid, jsonb) from public;
revoke execute on function public.set_my_professional_relationship_scopes(uuid, jsonb) from anon;
grant execute on function public.set_my_professional_relationship_scopes(uuid, jsonb) to authenticated;

revoke update on table public.professional_student_relationships from public, anon, authenticated;

do $v41e1_legacy_grants$
begin
  if pg_catalog.to_regclass('public.trainer_student_relationships') is not null then
    execute 'revoke update on table public.trainer_student_relationships from public, anon, authenticated';
  end if;
end;
$v41e1_legacy_grants$;

commit;
