begin;

create or replace function public.validate_workout_plan_payload_v41b(plan_data jsonb)
returns boolean
language plpgsql immutable
set search_path = ''
as $$
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
$$;

create table if not exists public.professional_workout_templates (
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
  constraint professional_workout_templates_title_check check (char_length(btrim(title)) between 2 and 120),
  constraint professional_workout_templates_description_check check (description is null or char_length(description) <= 2000),
  constraint professional_workout_templates_schema_version_check check (schema_version = 1 and schema_version = (plan_data ->> 'schemaVersion')::integer),
  constraint professional_workout_templates_status_check check (status in ('active','archived')),
  constraint professional_workout_templates_plan_check check (public.validate_workout_plan_payload_v41b(plan_data))
);

create table if not exists public.student_workout_assignments (
  id uuid primary key default gen_random_uuid(),
  relationship_id uuid not null references public.professional_student_relationships(id),
  template_id uuid references public.professional_workout_templates(id) on delete set null,
  assignment_version integer not null,
  title_snapshot text not null,
  description_snapshot text,
  plan_data_snapshot jsonb not null,
  schema_version integer not null default 1,
  status text not null default 'active',
  assigned_at timestamptz not null default now(),
  effective_from date,
  superseded_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_workout_assignments_version_check check (assignment_version >= 1),
  constraint student_workout_assignments_title_check check (char_length(btrim(title_snapshot)) between 2 and 120),
  constraint student_workout_assignments_description_check check (description_snapshot is null or char_length(description_snapshot) <= 2000),
  constraint student_workout_assignments_schema_version_check check (schema_version = 1 and schema_version = (plan_data_snapshot ->> 'schemaVersion')::integer),
  constraint student_workout_assignments_status_check check (status in ('active','superseded','revoked')),
  constraint student_workout_assignments_plan_check check (public.validate_workout_plan_payload_v41b(plan_data_snapshot)),
  constraint student_workout_assignments_relationship_version_key unique (relationship_id,assignment_version)
);

alter table public.professional_workout_templates
  drop constraint if exists professional_workout_templates_schema_version_check;
alter table public.professional_workout_templates
  add constraint professional_workout_templates_schema_version_check check (
    schema_version = 1
    and schema_version = (plan_data ->> 'schemaVersion')::integer
  );

alter table public.student_workout_assignments
  drop constraint if exists student_workout_assignments_schema_version_check;
alter table public.student_workout_assignments
  add constraint student_workout_assignments_schema_version_check check (
    schema_version = 1
    and schema_version = (plan_data_snapshot ->> 'schemaVersion')::integer
  );

alter table public.student_workout_assignments
  drop constraint if exists student_workout_assignments_status_timestamps_check;
alter table public.student_workout_assignments
  add constraint student_workout_assignments_status_timestamps_check check (
    (status='active' and superseded_at is null and revoked_at is null)
    or (status='superseded' and superseded_at is not null and revoked_at is null)
    or (status='revoked' and revoked_at is not null and superseded_at is null)
  );

create index if not exists professional_workout_templates_owner_idx on public.professional_workout_templates(owner_user_id,status,updated_at desc);
create index if not exists student_workout_assignments_relationship_idx on public.student_workout_assignments(relationship_id,assignment_version desc);
create unique index if not exists student_workout_assignments_one_active_idx on public.student_workout_assignments(relationship_id) where status='active';

alter table public.professional_workout_templates enable row level security;
alter table public.student_workout_assignments enable row level security;

revoke all on public.professional_workout_templates,public.student_workout_assignments from public,anon,authenticated;
grant select on public.professional_workout_templates,public.student_workout_assignments to authenticated;

drop policy if exists professional_workout_templates_select_own_v41b on public.professional_workout_templates;
create policy professional_workout_templates_select_own_v41b on public.professional_workout_templates for select to authenticated using (owner_user_id=auth.uid());

drop policy if exists student_workout_assignments_select_participant_v41b on public.student_workout_assignments;
create policy student_workout_assignments_select_participant_v41b on public.student_workout_assignments for select to authenticated using (
  exists(select 1 from public.professional_student_relationships relationship
    where relationship.id=relationship_id
      and (relationship.professional_user_id=auth.uid() or relationship.student_user_id=auth.uid()))
);

create or replace function public.assert_my_trainer_identity_v41b()
returns void
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  if not exists(select 1 from public.user_commercial_accounts account where account.user_id=auth.uid() and account.primary_account_type='trainer')
    or not exists(select 1 from public.user_account_modes mode where mode.user_id=auth.uid() and mode.mode='trainer') then
    raise exception 'trainer_account_required' using errcode='42501';
  end if;
  if not exists(select 1 from public.user_commercial_accounts account join public.account_plan_catalog plan on plan.code=account.plan_code and plan.account_type=account.primary_account_type where account.user_id=auth.uid() and account.primary_account_type='trainer') then raise exception 'trainer_plan_unavailable' using errcode='42501'; end if;
end;
$$;

create or replace function public.assert_my_trainer_write_access_v41b()
returns void
language plpgsql stable security definer
set search_path = ''
as $$
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
$$;

create or replace function public.protect_workout_assignment_snapshot_v41b()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
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
$$;

drop trigger if exists protect_workout_assignment_snapshot_v41b on public.student_workout_assignments;
create trigger protect_workout_assignment_snapshot_v41b before update on public.student_workout_assignments
for each row execute function public.protect_workout_assignment_snapshot_v41b();

create or replace function public.create_my_workout_template(target_title text,target_description text,target_plan_data jsonb,target_organization_id uuid default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
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
$$;

create or replace function public.update_my_workout_template(target_template_id uuid,target_title text,target_description text,target_plan_data jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
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
$$;

create or replace function public.archive_my_workout_template(target_template_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare template_record public.professional_workout_templates;
begin
  perform public.assert_my_trainer_identity_v41b();
  update public.professional_workout_templates set status='archived',updated_at=now() where id=target_template_id and owner_user_id=auth.uid() returning * into template_record;
  if not found then raise exception 'workout_template_not_found' using errcode='P0001'; end if;
  return jsonb_build_object('id',template_record.id,'status',template_record.status,'updatedAt',template_record.updated_at);
end;
$$;

create or replace function public.list_my_workout_templates()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform public.assert_my_trainer_identity_v41b();
  return coalesce((select jsonb_agg(jsonb_build_object('id',template.id,'title',template.title,'description',template.description,'planData',template.plan_data,'schemaVersion',template.schema_version,'status',template.status,'organizationId',template.organization_id,'createdAt',template.created_at,'updatedAt',template.updated_at) order by template.updated_at desc) from public.professional_workout_templates template where template.owner_user_id=auth.uid()),'[]'::jsonb);
end;
$$;

create or replace function public.list_my_manageable_workout_students()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
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
$$;

create or replace function public.assign_workout_template_to_student(target_template_id uuid,target_relationship_id uuid,target_effective_from date default null)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
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
$$;

create or replace function public.revoke_my_student_workout_assignment(target_assignment_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
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
$$;

create or replace function public.list_my_assigned_workout_plans()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
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
$$;

drop function if exists public.assert_my_trainer_account_v41b();
revoke all on function public.validate_workout_plan_payload_v41b(jsonb),public.assert_my_trainer_identity_v41b(),public.assert_my_trainer_write_access_v41b(),public.protect_workout_assignment_snapshot_v41b() from public,anon,authenticated;
revoke all on function public.create_my_workout_template(text,text,jsonb,uuid),public.update_my_workout_template(uuid,text,text,jsonb),public.archive_my_workout_template(uuid),public.list_my_workout_templates(),public.list_my_manageable_workout_students(),public.assign_workout_template_to_student(uuid,uuid,date),public.revoke_my_student_workout_assignment(uuid),public.list_my_assigned_workout_plans() from public,anon,authenticated;
grant execute on function public.create_my_workout_template(text,text,jsonb,uuid),public.update_my_workout_template(uuid,text,text,jsonb),public.archive_my_workout_template(uuid),public.list_my_workout_templates(),public.list_my_manageable_workout_students(),public.assign_workout_template_to_student(uuid,uuid,date),public.revoke_my_student_workout_assignment(uuid),public.list_my_assigned_workout_plans() to authenticated;

commit;
