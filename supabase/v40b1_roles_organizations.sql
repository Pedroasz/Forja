begin;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 120),
  slug text not null check (
    char_length(slug) between 3 and 60
    and slug ~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])$'
  ),
  organization_type text not null check (organization_type in ('academy', 'team')),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'active' check (status in ('active', 'suspended', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'trainer', 'student')),
  status text not null default 'pending' check (status in ('pending', 'active', 'suspended', 'revoked')),
  created_by uuid references auth.users(id) on delete set null,
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_members_organization_user_key unique (organization_id, user_id)
);

create table if not exists public.trainer_student_relationships (
  id uuid primary key default gen_random_uuid(),
  trainer_user_id uuid not null references auth.users(id) on delete cascade,
  student_user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'active', 'revoked', 'rejected')),
  permissions jsonb not null default jsonb_build_object(
    'view_workouts', false,
    'assign_workouts', false,
    'view_executions', false,
    'view_evolution', false,
    'view_nutrition', false
  ),
  requested_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trainer_student_relationships_distinct_users check (trainer_user_id <> student_user_id),
  constraint trainer_student_relationships_permissions_check check (
    jsonb_typeof(permissions) = 'object'
    and permissions ?& array[
      'view_workouts',
      'assign_workouts',
      'view_executions',
      'view_evolution',
      'view_nutrition'
    ]
    and jsonb_typeof(permissions -> 'view_workouts') = 'boolean'
    and jsonb_typeof(permissions -> 'assign_workouts') = 'boolean'
    and jsonb_typeof(permissions -> 'view_executions') = 'boolean'
    and jsonb_typeof(permissions -> 'view_evolution') = 'boolean'
    and jsonb_typeof(permissions -> 'view_nutrition') = 'boolean'
    and (permissions - 'view_workouts' - 'assign_workouts' - 'view_executions' - 'view_evolution' - 'view_nutrition') = '{}'::jsonb
  )
);

create table if not exists public.platform_user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('platform_admin', 'support')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  constraint platform_user_roles_user_role_key unique (user_id, role)
);

create unique index if not exists organizations_slug_lower_key on public.organizations (lower(slug));
create index if not exists organizations_owner_user_id_idx on public.organizations (owner_user_id);
create index if not exists organization_members_organization_id_idx on public.organization_members (organization_id);
create index if not exists organization_members_user_id_idx on public.organization_members (user_id);
create index if not exists organization_members_org_role_status_idx on public.organization_members (organization_id, role, status);
create index if not exists trainer_student_relationships_trainer_idx on public.trainer_student_relationships (trainer_user_id);
create index if not exists trainer_student_relationships_student_idx on public.trainer_student_relationships (student_user_id);
create index if not exists trainer_student_relationships_organization_idx on public.trainer_student_relationships (organization_id);
create index if not exists trainer_student_relationships_status_idx on public.trainer_student_relationships (status);
create unique index if not exists trainer_student_relationships_org_context_key on public.trainer_student_relationships (trainer_user_id, student_user_id, organization_id) where organization_id is not null;
create unique index if not exists trainer_student_relationships_independent_context_key on public.trainer_student_relationships (trainer_user_id, student_user_id) where organization_id is null;
create index if not exists platform_user_roles_user_id_idx on public.platform_user_roles (user_id);

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.trainer_student_relationships enable row level security;
alter table public.platform_user_roles enable row level security;

create or replace function public.is_organization_member(
  target_organization_id uuid,
  target_user_id uuid default auth.uid()
) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and target_user_id = auth.uid()
    and exists (
      select 1 from public.organization_members membership
      where membership.organization_id = target_organization_id
        and membership.user_id = target_user_id
        and membership.status in ('active', 'pending')
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
    and allowed_roles <@ array['owner', 'admin', 'trainer', 'student']::text[]
    and exists (
      select 1 from public.organization_members membership
      where membership.organization_id = target_organization_id
        and membership.user_id = target_user_id
        and membership.status = 'active'
        and membership.role = any(allowed_roles)
    );
$$;

create or replace function public.has_active_trainer_student_relationship(
  target_trainer_id uuid,
  target_student_id uuid,
  required_permission text default null
) returns boolean
language sql stable security definer
set search_path = ''
as $$
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
    'student_relationships', '[]'::jsonb
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
    ), '[]'::jsonb)
  ) end;
$$;

revoke all on public.organizations, public.organization_members, public.trainer_student_relationships, public.platform_user_roles from public, anon, authenticated;
grant select on public.organizations, public.organization_members, public.trainer_student_relationships, public.platform_user_roles to authenticated;

revoke all on function public.is_organization_member(uuid, uuid) from public, anon;
revoke all on function public.has_organization_role(uuid, text[], uuid) from public, anon;
revoke all on function public.has_active_trainer_student_relationship(uuid, uuid, text) from public, anon;
revoke all on function public.get_current_access_context() from public, anon;
grant execute on function public.is_organization_member(uuid, uuid) to authenticated;
grant execute on function public.has_organization_role(uuid, text[], uuid) to authenticated;
grant execute on function public.has_active_trainer_student_relationship(uuid, uuid, text) to authenticated;
grant execute on function public.get_current_access_context() to authenticated;

drop policy if exists organizations_select_related_v40b1 on public.organizations;
create policy organizations_select_related_v40b1 on public.organizations for select to authenticated
using (owner_user_id = auth.uid() or public.is_organization_member(id, auth.uid()));

drop policy if exists organization_members_select_scoped_v40b1 on public.organization_members;
create policy organization_members_select_scoped_v40b1 on public.organization_members for select to authenticated
using (
  user_id = auth.uid()
  or public.has_organization_role(organization_id, array['owner', 'admin']::text[], auth.uid())
);

drop policy if exists trainer_student_relationships_select_scoped_v40b1 on public.trainer_student_relationships;
create policy trainer_student_relationships_select_scoped_v40b1 on public.trainer_student_relationships for select to authenticated
using (
  trainer_user_id = auth.uid()
  or student_user_id = auth.uid()
  or (organization_id is not null and public.has_organization_role(organization_id, array['owner', 'admin']::text[], auth.uid()))
);

drop policy if exists platform_user_roles_select_own_v40b1 on public.platform_user_roles;
create policy platform_user_roles_select_own_v40b1 on public.platform_user_roles for select to authenticated
using (user_id = auth.uid());

commit;
