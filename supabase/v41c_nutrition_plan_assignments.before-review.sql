-- Run after v41c_notifications.sql; notification creation is an internal dependency.
begin;

create or replace function public.nutrition_text_is_safe_v41c(target_value text,target_max_length integer)
returns boolean
language sql immutable
set search_path = ''
as $$
  select target_value is not null
    and char_length(target_value)<=target_max_length
    and target_value !~* '(<[^>]*>|javascript:|on[a-z]+[[:space:]]*=)'
$$;

create or replace function public.nutrition_unit_is_supported_v41c(target_unit text)
returns boolean
language sql immutable
set search_path = ''
as $$
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
$$;

create or replace function public.validate_nutrition_plan_payload_v41c(plan_data jsonb)
returns boolean
language plpgsql immutable
set search_path = ''
as $$
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
$$;

create table if not exists public.professional_nutrition_templates (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id),
  title text not null,
  description text,
  plan_data jsonb not null,
  schema_version integer not null default 1,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint professional_nutrition_templates_title_check check (char_length(btrim(title)) between 2 and 120 and public.nutrition_text_is_safe_v41c(title,120)),
  constraint professional_nutrition_templates_description_check check (description is null or public.nutrition_text_is_safe_v41c(description,2000)),
  constraint professional_nutrition_templates_schema_version_check check (schema_version=1 and schema_version=(plan_data->>'schemaVersion')::integer),
  constraint professional_nutrition_templates_status_check check (status in ('active','archived')),
  constraint professional_nutrition_templates_plan_check check (public.validate_nutrition_plan_payload_v41c(plan_data))
);

create table if not exists public.student_nutrition_assignments (
  id uuid primary key default gen_random_uuid(),
  relationship_id uuid not null references public.professional_student_relationships(id),
  template_id uuid references public.professional_nutrition_templates(id) on delete set null,
  assignment_version integer not null,
  title_snapshot text not null,
  description_snapshot text,
  plan_data_snapshot jsonb not null,
  schema_version integer not null default 1,
  status text not null default 'active',
  assigned_at timestamptz not null default now(),
  effective_from date,
  effective_until date,
  superseded_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_nutrition_assignments_version_check check (assignment_version>=1),
  constraint student_nutrition_assignments_title_check check (char_length(btrim(title_snapshot)) between 2 and 120 and public.nutrition_text_is_safe_v41c(title_snapshot,120)),
  constraint student_nutrition_assignments_description_check check (description_snapshot is null or public.nutrition_text_is_safe_v41c(description_snapshot,2000)),
  constraint student_nutrition_assignments_schema_version_check check (schema_version=1 and schema_version=(plan_data_snapshot->>'schemaVersion')::integer),
  constraint student_nutrition_assignments_status_check check (status in ('active','superseded','revoked')),
  constraint student_nutrition_assignments_status_timestamps_check check (
    (status='active' and superseded_at is null and revoked_at is null) or
    (status='superseded' and superseded_at is not null and revoked_at is null) or
    (status='revoked' and revoked_at is not null and superseded_at is null)
  ),
  constraint student_nutrition_assignments_effective_dates_check check (effective_until is null or effective_from is null or effective_until>=effective_from),
  constraint student_nutrition_assignments_plan_check check (public.validate_nutrition_plan_payload_v41c(plan_data_snapshot)),
  constraint student_nutrition_assignments_relationship_version_key unique (relationship_id,assignment_version)
);

alter table public.professional_nutrition_templates drop constraint if exists professional_nutrition_templates_schema_version_check;
alter table public.professional_nutrition_templates add constraint professional_nutrition_templates_schema_version_check check (schema_version=1 and schema_version=(plan_data->>'schemaVersion')::integer);
alter table public.professional_nutrition_templates drop constraint if exists professional_nutrition_templates_title_check;
alter table public.professional_nutrition_templates add constraint professional_nutrition_templates_title_check check (char_length(btrim(title)) between 2 and 120 and public.nutrition_text_is_safe_v41c(title,120));
alter table public.professional_nutrition_templates drop constraint if exists professional_nutrition_templates_description_check;
alter table public.professional_nutrition_templates add constraint professional_nutrition_templates_description_check check (description is null or public.nutrition_text_is_safe_v41c(description,2000));
alter table public.student_nutrition_assignments drop constraint if exists student_nutrition_assignments_schema_version_check;
alter table public.student_nutrition_assignments add constraint student_nutrition_assignments_schema_version_check check (schema_version=1 and schema_version=(plan_data_snapshot->>'schemaVersion')::integer);
alter table public.student_nutrition_assignments drop constraint if exists student_nutrition_assignments_title_check;
alter table public.student_nutrition_assignments add constraint student_nutrition_assignments_title_check check (char_length(btrim(title_snapshot)) between 2 and 120 and public.nutrition_text_is_safe_v41c(title_snapshot,120));
alter table public.student_nutrition_assignments drop constraint if exists student_nutrition_assignments_description_check;
alter table public.student_nutrition_assignments add constraint student_nutrition_assignments_description_check check (description_snapshot is null or public.nutrition_text_is_safe_v41c(description_snapshot,2000));
alter table public.student_nutrition_assignments drop constraint if exists student_nutrition_assignments_status_timestamps_check;
alter table public.student_nutrition_assignments add constraint student_nutrition_assignments_status_timestamps_check check (
  (status='active' and superseded_at is null and revoked_at is null) or
  (status='superseded' and superseded_at is not null and revoked_at is null) or
  (status='revoked' and revoked_at is not null and superseded_at is null)
);

create index if not exists professional_nutrition_templates_owner_idx on public.professional_nutrition_templates(owner_user_id,status,updated_at desc);
create index if not exists student_nutrition_assignments_relationship_idx on public.student_nutrition_assignments(relationship_id,assignment_version desc);
create unique index if not exists student_nutrition_assignments_one_active_idx on public.student_nutrition_assignments(relationship_id) where status='active';

alter table public.professional_nutrition_templates enable row level security;
alter table public.student_nutrition_assignments enable row level security;
revoke all on table public.professional_nutrition_templates,public.student_nutrition_assignments from public,anon,authenticated;
grant select on table public.professional_nutrition_templates,public.student_nutrition_assignments to authenticated;

drop policy if exists professional_nutrition_templates_select_own_v41c on public.professional_nutrition_templates;
create policy professional_nutrition_templates_select_own_v41c on public.professional_nutrition_templates for select to authenticated using (owner_user_id=auth.uid());
drop policy if exists student_nutrition_assignments_select_participant_v41c on public.student_nutrition_assignments;
create policy student_nutrition_assignments_select_participant_v41c on public.student_nutrition_assignments for select to authenticated using (
  exists(select 1 from public.professional_student_relationships relationship where relationship.id=relationship_id and (
    relationship.student_user_id=auth.uid() or (
      relationship.professional_user_id=auth.uid() and relationship.professional_type='nutritionist' and relationship.status='active'
      and coalesce((relationship.scopes->>'manage_nutrition_plan')::boolean,false)
    )
  ))
);

create or replace function public.assert_my_nutritionist_identity_v41c()
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  if not exists(select 1 from public.user_commercial_accounts account where account.user_id=auth.uid() and account.primary_account_type='nutritionist')
    or not exists(select 1 from public.user_account_modes mode where mode.user_id=auth.uid() and mode.mode='nutritionist') then raise exception 'nutritionist_account_required' using errcode='42501'; end if;
  if not exists(select 1 from public.user_commercial_accounts account join public.account_plan_catalog plan on plan.code=account.plan_code and plan.account_type=account.primary_account_type where account.user_id=auth.uid() and account.primary_account_type='nutritionist') then raise exception 'nutritionist_plan_unavailable' using errcode='42501'; end if;
end;
$$;

create or replace function public.assert_my_nutritionist_write_access_v41c()
returns void
language plpgsql stable security definer
set search_path = ''
as $$
declare account_subscription_status text; account_plan_is_active boolean;
begin
  perform public.assert_my_nutritionist_identity_v41c();
  select account.subscription_status,plan.is_active into account_subscription_status,account_plan_is_active
  from public.user_commercial_accounts account join public.account_plan_catalog plan on plan.code=account.plan_code and plan.account_type=account.primary_account_type
  where account.user_id=auth.uid() and account.primary_account_type='nutritionist';
  if not found or account_plan_is_active is not true then raise exception 'nutritionist_plan_unavailable' using errcode='42501'; end if;
  if account_subscription_status is null or account_subscription_status not in ('active','trialing') then raise exception 'nutritionist_subscription_inactive' using errcode='42501'; end if;
end;
$$;

create or replace function public.protect_nutrition_assignment_snapshot_v41c()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
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
$$;

drop trigger if exists protect_nutrition_assignment_snapshot_v41c on public.student_nutrition_assignments;
create trigger protect_nutrition_assignment_snapshot_v41c before update on public.student_nutrition_assignments for each row execute function public.protect_nutrition_assignment_snapshot_v41c();

create or replace function public.create_my_nutrition_template(target_title text,target_description text,target_plan_data jsonb,target_organization_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
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
end; $$;

create or replace function public.update_my_nutrition_template(target_template_id uuid,target_title text,target_description text,target_plan_data jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
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
end; $$;

create or replace function public.archive_my_nutrition_template(target_template_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare template_record public.professional_nutrition_templates;
begin
  perform public.assert_my_nutritionist_identity_v41c();
  update public.professional_nutrition_templates set status='archived',updated_at=now() where id=target_template_id and owner_user_id=auth.uid() returning * into template_record;
  if not found then raise exception 'nutrition_template_not_found' using errcode='P0001'; end if;
  return jsonb_build_object('id',template_record.id,'status',template_record.status,'updatedAt',template_record.updated_at);
end; $$;

create or replace function public.list_my_nutrition_templates()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.assert_my_nutritionist_identity_v41c();
  return coalesce((select jsonb_agg(jsonb_build_object('id',template.id,'title',template.title,'description',template.description,'planData',template.plan_data,'schemaVersion',template.schema_version,'status',template.status,'organizationId',template.organization_id,'createdAt',template.created_at,'updatedAt',template.updated_at) order by template.updated_at desc) from public.professional_nutrition_templates template where template.owner_user_id=auth.uid()),'[]'::jsonb);
end; $$;

create or replace function public.list_my_manageable_nutrition_students()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
  where relationship.professional_user_id=auth.uid() and relationship.professional_type='nutritionist' and relationship.status='active' and coalesce((relationship.scopes->>'manage_nutrition_plan')::boolean,false)),'[]'::jsonb);
end; $$;

create or replace function public.assign_nutrition_template_to_student(target_template_id uuid,target_relationship_id uuid,target_effective_from date default null,target_effective_until date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare relationship_record public.professional_student_relationships; template_record public.professional_nutrition_templates; new_assignment public.student_nutrition_assignments; next_version integer;
begin
  perform public.assert_my_nutritionist_write_access_v41c();
  if target_effective_until is not null and target_effective_from is not null and target_effective_until<target_effective_from then raise exception 'invalid_nutrition_effective_dates' using errcode='22023'; end if;
  select * into relationship_record from public.professional_student_relationships where id=target_relationship_id and professional_user_id=auth.uid() and professional_type='nutritionist' for update;
  if not found then raise exception 'nutrition_relationship_not_found' using errcode='P0001'; end if;
  if relationship_record.status<>'active' then raise exception 'nutrition_relationship_inactive' using errcode='P0001'; end if;
  if coalesce((relationship_record.scopes->>'manage_nutrition_plan')::boolean,false) is not true then raise exception 'nutrition_scope_required' using errcode='42501'; end if;
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
end; $$;

create or replace function public.revoke_my_student_nutrition_assignment(target_assignment_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare assignment_record public.student_nutrition_assignments;
begin
  perform public.assert_my_nutritionist_identity_v41c();
  select assignment.* into assignment_record from public.student_nutrition_assignments assignment join public.professional_student_relationships relationship on relationship.id=assignment.relationship_id
  where assignment.id=target_assignment_id and relationship.professional_user_id=auth.uid() and relationship.professional_type='nutritionist' for update of assignment;
  if not found then raise exception 'nutrition_assignment_not_found' using errcode='P0001'; end if;
  if assignment_record.status<>'active' then raise exception 'nutrition_assignment_inactive' using errcode='P0001'; end if;
  update public.student_nutrition_assignments set status='revoked',revoked_at=now(),superseded_at=null,updated_at=now() where id=assignment_record.id returning * into assignment_record;
  return jsonb_build_object('assignmentId',assignment_record.id,'relationshipId',assignment_record.relationship_id,'assignmentVersion',assignment_record.assignment_version,'assignmentStatus',assignment_record.status,'revokedAt',assignment_record.revoked_at);
end; $$;

drop function if exists public.list_my_assigned_nutrition_plans();

create or replace function public.list_my_assigned_nutrition_plans(target_local_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
    'canManageNutritionPlan',coalesce((relationship.scopes->>'manage_nutrition_plan')::boolean,false),
    'isCurrent',(assignment.status='active' and relationship.status='active' and relationship.professional_type='nutritionist'
      and coalesce((relationship.scopes->>'manage_nutrition_plan')::boolean,false)
      and (assignment.effective_from is null or assignment.effective_from<=target_local_date)
      and (assignment.effective_until is null or assignment.effective_until>=target_local_date)),
    'assignedAt',assignment.assigned_at,'effectiveFrom',assignment.effective_from,'effectiveUntil',assignment.effective_until
  ) order by case assignment.status when 'active' then 0 else 1 end,assignment.assignment_version desc)
  from public.student_nutrition_assignments assignment
  join public.professional_student_relationships relationship on relationship.id=assignment.relationship_id
  left join public.profiles profile on profile.user_id=relationship.professional_user_id
  left join public.organizations organization on organization.id=relationship.organization_id
  where relationship.student_user_id=auth.uid()),'[]'::jsonb);
end; $$;

create or replace function public.notify_nutrition_assignment_v41c()
returns trigger language plpgsql security definer set search_path = '' as $$
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
end; $$;

drop trigger if exists notify_nutrition_assignment_insert_v41c on public.student_nutrition_assignments;
create trigger notify_nutrition_assignment_insert_v41c after insert on public.student_nutrition_assignments for each row execute function public.notify_nutrition_assignment_v41c();
drop trigger if exists notify_nutrition_assignment_status_v41c on public.student_nutrition_assignments;
create trigger notify_nutrition_assignment_status_v41c after update of status on public.student_nutrition_assignments for each row execute function public.notify_nutrition_assignment_v41c();

revoke all on function public.nutrition_text_is_safe_v41c(text,integer),public.nutrition_unit_is_supported_v41c(text),public.validate_nutrition_plan_payload_v41c(jsonb),public.assert_my_nutritionist_identity_v41c(),public.assert_my_nutritionist_write_access_v41c(),public.protect_nutrition_assignment_snapshot_v41c(),public.notify_nutrition_assignment_v41c() from public,anon,authenticated;
revoke all on function public.create_my_nutrition_template(text,text,jsonb,uuid),public.update_my_nutrition_template(uuid,text,text,jsonb),public.archive_my_nutrition_template(uuid),public.list_my_nutrition_templates(),public.list_my_manageable_nutrition_students(),public.assign_nutrition_template_to_student(uuid,uuid,date,date),public.revoke_my_student_nutrition_assignment(uuid),public.list_my_assigned_nutrition_plans(date) from public,anon,authenticated;
grant execute on function public.create_my_nutrition_template(text,text,jsonb,uuid),public.update_my_nutrition_template(uuid,text,text,jsonb),public.archive_my_nutrition_template(uuid),public.list_my_nutrition_templates(),public.list_my_manageable_nutrition_students(),public.assign_nutrition_template_to_student(uuid,uuid,date,date),public.revoke_my_student_nutrition_assignment(uuid),public.list_my_assigned_nutrition_plans(date) to authenticated;

commit;
