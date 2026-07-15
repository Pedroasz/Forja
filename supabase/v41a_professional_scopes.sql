begin;

-- Extend existing account modes without touching profiles.
alter table public.user_account_modes
  drop constraint if exists user_account_modes_mode_check;

alter table public.user_account_modes
  add constraint user_account_modes_mode_check
  check (mode in ('individual', 'student', 'trainer', 'nutritionist'));

-- Nutritionist is a professional organization role, never an administrative one.
alter table public.organization_members
  drop constraint if exists organization_members_role_check;

alter table public.organization_members
  add constraint organization_members_role_check
  check (role in ('owner', 'admin', 'trainer', 'nutritionist', 'student'));

create table if not exists public.professional_student_relationships (
  id uuid primary key default gen_random_uuid(),
  professional_user_id uuid not null references auth.users(id) on delete cascade,
  student_user_id uuid not null references auth.users(id) on delete cascade,
  professional_type text not null,
  organization_id uuid references public.organizations(id) on delete cascade,
  status text not null default 'pending',
  scopes jsonb not null default jsonb_build_object(
    'manage_workout_plan', false,
    'view_workout_executions', false,
    'manage_nutrition_plan', false,
    'view_nutrition_logs', false,
    'view_evolution', false
  ),
  requested_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint professional_student_relationships_type_check check (professional_type in ('trainer', 'nutritionist')),
  constraint professional_student_relationships_status_check check (status in ('pending', 'active', 'rejected', 'revoked')),
  constraint professional_student_relationships_distinct_users check (professional_user_id <> student_user_id),
  constraint professional_student_relationships_scopes_check check (
    jsonb_typeof(scopes) = 'object'
    and scopes ?& array[
      'manage_workout_plan',
      'view_workout_executions',
      'manage_nutrition_plan',
      'view_nutrition_logs',
      'view_evolution'
    ]
    and jsonb_typeof(scopes -> 'manage_workout_plan') = 'boolean'
    and jsonb_typeof(scopes -> 'view_workout_executions') = 'boolean'
    and jsonb_typeof(scopes -> 'manage_nutrition_plan') = 'boolean'
    and jsonb_typeof(scopes -> 'view_nutrition_logs') = 'boolean'
    and jsonb_typeof(scopes -> 'view_evolution') = 'boolean'
    and (scopes
      - 'manage_workout_plan'
      - 'view_workout_executions'
      - 'manage_nutrition_plan'
      - 'view_nutrition_logs'
      - 'view_evolution') = '{}'::jsonb
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
  )
);

create unique index if not exists professional_student_relationships_org_context_key
  on public.professional_student_relationships
  (professional_user_id, student_user_id, professional_type, organization_id)
  where organization_id is not null;

create unique index if not exists professional_student_relationships_independent_context_key
  on public.professional_student_relationships
  (professional_user_id, student_user_id, professional_type)
  where organization_id is null;

create index if not exists professional_student_relationships_professional_idx
  on public.professional_student_relationships (professional_user_id, professional_type, status);
create index if not exists professional_student_relationships_student_idx
  on public.professional_student_relationships (student_user_id, status);
create index if not exists professional_student_relationships_organization_idx
  on public.professional_student_relationships (organization_id, status);

alter table public.professional_student_relationships enable row level security;

create or replace function public.default_professional_scopes(target_professional_type text)
returns jsonb
language sql immutable
set search_path = ''
as $$
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
$$;

drop function if exists public.has_active_professional_relationship(uuid, uuid, text, text);

create or replace function public.has_active_professional_relationship(
  professional_id uuid,
  student_id uuid,
  target_professional_type text,
  required_scope text default null,
  target_organization_id uuid default null
) returns boolean
language sql stable security definer
set search_path = ''
as $$
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
$$;

create or replace function public.has_organization_role(
  target_organization_id uuid,
  allowed_roles text[],
  target_user_id uuid default auth.uid()
) returns boolean
language sql stable security definer
set search_path = ''
as $$
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
$$;

-- Existing trainer links keep their identifiers, status and effective permissions.
insert into public.professional_student_relationships (
  id, professional_user_id, student_user_id, professional_type, organization_id,
  status, scopes, requested_by, accepted_at, revoked_at, created_at, updated_at
)
select
  relationship.id,
  relationship.trainer_user_id,
  relationship.student_user_id,
  'trainer',
  relationship.organization_id,
  relationship.status,
  jsonb_build_object(
    'manage_workout_plan', coalesce((relationship.permissions ->> 'assign_workouts')::boolean, false),
    'view_workout_executions', coalesce((relationship.permissions ->> 'view_executions')::boolean, false),
    'manage_nutrition_plan', false,
    'view_nutrition_logs', false,
    'view_evolution', coalesce((relationship.permissions ->> 'view_evolution')::boolean, false)
  ),
  relationship.requested_by,
  relationship.accepted_at,
  relationship.revoked_at,
  relationship.created_at,
  relationship.updated_at
from public.trainer_student_relationships relationship
on conflict do nothing;

create or replace function public.sync_legacy_trainer_relationship_v41a()
returns trigger
language plpgsql
set search_path = ''
as $$
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
$$;

drop trigger if exists sync_legacy_trainer_relationship_v41a on public.trainer_student_relationships;
create trigger sync_legacy_trainer_relationship_v41a
after insert or update or delete on public.trainer_student_relationships
for each row execute function public.sync_legacy_trainer_relationship_v41a();

create or replace function public.set_my_account_modes(requested_modes text[])
returns text[]
language plpgsql security definer
set search_path = ''
as $$
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
$$;

create or replace function public.get_current_access_context()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
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
$$;

revoke all on public.professional_student_relationships from public, anon, authenticated;
grant select on public.professional_student_relationships to authenticated;

drop policy if exists professional_student_relationships_select_scoped_v41a on public.professional_student_relationships;
create policy professional_student_relationships_select_scoped_v41a
on public.professional_student_relationships for select to authenticated
using (
  professional_user_id = auth.uid()
  or student_user_id = auth.uid()
  or (
    organization_id is not null
    and public.has_organization_role(organization_id, array['owner', 'admin']::text[], auth.uid())
  )
);

revoke all on function public.default_professional_scopes(text) from public, anon, authenticated;
revoke all on function public.has_active_professional_relationship(uuid, uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function public.sync_legacy_trainer_relationship_v41a() from public, anon, authenticated;
revoke all on function public.has_organization_role(uuid, text[], uuid) from public, anon, authenticated;
revoke all on function public.set_my_account_modes(text[]) from public, anon, authenticated;
revoke all on function public.get_current_access_context() from public, anon, authenticated;
grant execute on function public.has_active_professional_relationship(uuid, uuid, text, text, uuid) to authenticated;
grant execute on function public.has_organization_role(uuid, text[], uuid) to authenticated;
grant execute on function public.set_my_account_modes(text[]) to authenticated;
grant execute on function public.get_current_access_context() to authenticated;

commit;
