begin;

-- V4.1D exposes bounded read-only RPCs. It neither changes source-table grants nor RLS.
do $v41d_required_schema$
declare
  missing_object text;
begin
  select required.table_name
  into missing_object
  from (values
    ('public.professional_student_relationships'),
    ('public.workouts'),
    ('public.meals'),
    ('public.evolution'),
    ('public.user_commercial_accounts'),
    ('public.account_plan_catalog'),
    ('public.user_account_modes'),
    ('public.organization_members')
  ) as required(table_name)
  where pg_catalog.to_regclass(required.table_name) is null
  order by required.table_name
  limit 1;

  if missing_object is not null then
    raise exception 'v41d_missing_required_object: %', missing_object using errcode = '42P01';
  end if;

  select required.object_name
  into missing_object
  from (values
    ('public.professional_student_relationships', 'id', 'public.professional_student_relationships.id'),
    ('public.professional_student_relationships', 'professional_user_id', 'public.professional_student_relationships.professional_user_id'),
    ('public.professional_student_relationships', 'student_user_id', 'public.professional_student_relationships.student_user_id'),
    ('public.professional_student_relationships', 'professional_type', 'public.professional_student_relationships.professional_type'),
    ('public.professional_student_relationships', 'organization_id', 'public.professional_student_relationships.organization_id'),
    ('public.professional_student_relationships', 'status', 'public.professional_student_relationships.status'),
    ('public.professional_student_relationships', 'scopes', 'public.professional_student_relationships.scopes'),
    ('public.user_commercial_accounts', 'user_id', 'public.user_commercial_accounts.user_id'),
    ('public.user_commercial_accounts', 'primary_account_type', 'public.user_commercial_accounts.primary_account_type'),
    ('public.user_commercial_accounts', 'plan_code', 'public.user_commercial_accounts.plan_code'),
    ('public.user_commercial_accounts', 'subscription_status', 'public.user_commercial_accounts.subscription_status'),
    ('public.account_plan_catalog', 'code', 'public.account_plan_catalog.code'),
    ('public.account_plan_catalog', 'account_type', 'public.account_plan_catalog.account_type'),
    ('public.account_plan_catalog', 'is_active', 'public.account_plan_catalog.is_active'),
    ('public.user_account_modes', 'user_id', 'public.user_account_modes.user_id'),
    ('public.user_account_modes', 'mode', 'public.user_account_modes.mode'),
    ('public.organization_members', 'organization_id', 'public.organization_members.organization_id'),
    ('public.organization_members', 'user_id', 'public.organization_members.user_id'),
    ('public.organization_members', 'role', 'public.organization_members.role'),
    ('public.organization_members', 'status', 'public.organization_members.status'),
    ('public.workouts', 'id', 'public.workouts.id'),
    ('public.workouts', 'user_id', 'public.workouts.user_id'),
    ('public.workouts', 'workout_date', 'public.workouts.workout_date'),
    ('public.workouts', 'name', 'public.workouts.name'),
    ('public.workouts', 'exercises', 'public.workouts.exercises'),
    ('public.workouts', 'total_volume', 'public.workouts.total_volume'),
    ('public.workouts', 'duration_minutes', 'public.workouts.duration_minutes'),
    ('public.meals', 'id', 'public.meals.id'),
    ('public.meals', 'user_id', 'public.meals.user_id'),
    ('public.meals', 'meal_date', 'public.meals.meal_date'),
    ('public.meals', 'items', 'public.meals.items'),
    ('public.meals', 'total_calories', 'public.meals.total_calories'),
    ('public.meals', 'total_protein', 'public.meals.total_protein'),
    ('public.meals', 'total_carbs', 'public.meals.total_carbs'),
    ('public.meals', 'total_fat', 'public.meals.total_fat'),
    ('public.evolution', 'id', 'public.evolution.id'),
    ('public.evolution', 'user_id', 'public.evolution.user_id'),
    ('public.evolution', 'record_date', 'public.evolution.record_date'),
    ('public.evolution', 'weight', 'public.evolution.weight'),
    ('public.evolution', 'body_fat', 'public.evolution.body_fat'),
    ('public.evolution', 'waist', 'public.evolution.waist'),
    ('public.evolution', 'hip', 'public.evolution.hip'),
    ('public.evolution', 'chest', 'public.evolution.chest'),
    ('public.evolution', 'left_arm', 'public.evolution.left_arm'),
    ('public.evolution', 'right_arm', 'public.evolution.right_arm'),
    ('public.evolution', 'left_thigh', 'public.evolution.left_thigh'),
    ('public.evolution', 'right_thigh', 'public.evolution.right_thigh'),
    ('public.evolution', 'notes', 'public.evolution.notes')
  ) as required(table_name, column_name, object_name)
  where not exists (
    select 1
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid = pg_catalog.to_regclass(required.table_name)
      and attribute.attname = required.column_name
      and attribute.attnum > 0
      and not attribute.attisdropped
  )
  order by required.object_name
  limit 1;

  if missing_object is not null then
    raise exception 'v41d_missing_required_object: %', missing_object using errcode = '42703';
  end if;
end;
$v41d_required_schema$;

-- Remove only the V4.1D review signatures that exposed relationship-derived values.
drop function if exists public.list_my_student_workout_executions(uuid, uuid, uuid, date, date, integer, date, uuid);
drop function if exists public.list_my_student_nutrition_logs(uuid, uuid, uuid, date, date, integer, date, uuid);
drop function if exists public.list_my_student_evolution(uuid, uuid, text, uuid, date, date, integer, date, uuid);
drop function if exists public.assert_professional_student_read_access_v41d(uuid, uuid, text, text, uuid);

create or replace function public.get_my_professional_monitoring_entitlement_v41d(
  target_relationship_id uuid,
  target_required_scope text,
  target_allowed_professional_types text[]
) returns uuid
language plpgsql stable security definer
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

create or replace function public.assert_professional_monitoring_page_v41d(
  target_start_date date,
  target_end_date date,
  target_limit integer,
  target_cursor_date date,
  target_cursor_id uuid
) returns void
language plpgsql immutable
set search_path = ''
as $function$
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

create or replace function public.list_my_student_workout_executions(
  target_relationship_id uuid,
  target_start_date date,
  target_end_date date,
  target_limit integer,
  target_cursor_date date default null,
  target_cursor_id uuid default null
) returns jsonb
language plpgsql stable security definer
set search_path = ''
as $function$
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

create or replace function public.list_my_student_nutrition_logs(
  target_relationship_id uuid,
  target_start_date date,
  target_end_date date,
  target_limit integer,
  target_cursor_date date default null,
  target_cursor_id uuid default null
) returns jsonb
language plpgsql stable security definer
set search_path = ''
as $function$
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

create or replace function public.list_my_student_evolution(
  target_relationship_id uuid,
  target_start_date date,
  target_end_date date,
  target_limit integer,
  target_cursor_date date default null,
  target_cursor_id uuid default null
) returns jsonb
language plpgsql stable security definer
set search_path = ''
as $function$
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

-- The base workout index omits id, so only this source needs a V4.1D cursor index.
do $v41d_workout_index$
declare
  equivalent_exists boolean;
begin
  select exists (
    select 1
    from pg_catalog.pg_index index_record
    where index_record.indrelid = 'public.workouts'::regclass
      and index_record.indisvalid
      and index_record.indpred is null
      and (
        select pg_catalog.array_agg(attribute.attname::text order by key_column.ordinality)
        from pg_catalog.unnest(index_record.indkey::smallint[]) with ordinality key_column(attnum, ordinality)
        join pg_catalog.pg_attribute attribute
          on attribute.attrelid = index_record.indrelid
         and attribute.attnum = key_column.attnum
        where key_column.ordinality <= index_record.indnkeyatts
          and key_column.ordinality <= 3
      ) = array['user_id', 'workout_date', 'id']::text[]
  ) into equivalent_exists;

  if not equivalent_exists then
    if pg_catalog.to_regclass('public.workouts_user_date_id_v41d_idx') is not null then
      raise exception 'v41d_index_name_conflict: public.workouts_user_date_id_v41d_idx';
    end if;
    execute 'create index workouts_user_date_id_v41d_idx on public.workouts (user_id, workout_date desc, id desc)';
    execute 'comment on index public.workouts_user_date_id_v41d_idx is ''FORJA V4.1D professional monitoring''';
  end if;
end;
$v41d_workout_index$;

revoke all on function public.get_my_professional_monitoring_entitlement_v41d(uuid, text, text[]) from public, anon, authenticated;
revoke all on function public.assert_professional_monitoring_page_v41d(date, date, integer, date, uuid) from public, anon, authenticated;
revoke all on function public.list_my_student_workout_executions(uuid, date, date, integer, date, uuid) from public, anon, authenticated;
revoke all on function public.list_my_student_nutrition_logs(uuid, date, date, integer, date, uuid) from public, anon, authenticated;
revoke all on function public.list_my_student_evolution(uuid, date, date, integer, date, uuid) from public, anon, authenticated;

grant execute on function public.list_my_student_workout_executions(uuid, date, date, integer, date, uuid) to authenticated;
grant execute on function public.list_my_student_nutrition_logs(uuid, date, date, integer, date, uuid) to authenticated;
grant execute on function public.list_my_student_evolution(uuid, date, date, integer, date, uuid) to authenticated;

commit;
