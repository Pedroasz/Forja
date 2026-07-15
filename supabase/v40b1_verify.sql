-- V4.0B1 verification only. Every statement below is read-only.

-- 1. Expected: four rows, one for each new table.
select table_schema, table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('organizations', 'organization_members', 'trainer_student_relationships', 'platform_user_roles')
order by table_name;

-- 2. Expected: primary keys, foreign keys, CHECKs and the declared UNIQUE constraints.
select conrelid::regclass as table_name, conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid in (
  'public.organizations'::regclass,
  'public.organization_members'::regclass,
  'public.trainer_student_relationships'::regclass,
  'public.platform_user_roles'::regclass
)
order by table_name::text, contype, conname;

-- 3. Expected: rowsecurity = true for all four tables.
select relname as table_name, relrowsecurity as rls_enabled, relforcerowsecurity as force_rls
from pg_class
where oid in (
  'public.organizations'::regclass,
  'public.organization_members'::regclass,
  'public.trainer_student_relationships'::regclass,
  'public.platform_user_roles'::regclass
)
order by relname;

-- 4. Expected: SELECT policies only, all restricted to authenticated.
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('organizations', 'organization_members', 'trainer_student_relationships', 'platform_user_roles')
order by tablename, policyname;

-- 5. Expected: zero rows. No policy may include anon or public.
select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename in ('organizations', 'organization_members', 'trainer_student_relationships', 'platform_user_roles')
  and (roles @> array['anon']::name[] or roles @> array['public']::name[]);

-- 6. Expected: zero rows. Direct INSERT/UPDATE/DELETE remains unavailable.
select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename in ('organizations', 'organization_members', 'trainer_student_relationships', 'platform_user_roles')
  and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL');

-- 7 and 8. Expected: the three boolean helpers and get_current_access_context.
select n.nspname as schema_name, p.proname, pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as result, p.prosecdef as security_definer, p.provolatile
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'is_organization_member',
    'has_organization_role',
    'has_active_trainer_student_relationship',
    'get_current_access_context'
  )
order by p.proname;

-- 9. Expected: ownership, lookup, context uniqueness and slug indexes.
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('organizations', 'organization_members', 'trainer_student_relationships', 'platform_user_roles')
order by tablename, indexname;

-- 10. Expected: zero rows. V4.0B1 adds no role/admin field to profiles.
select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'profiles'
  and column_name in ('role', 'admin', 'trainer', 'gym_admin', 'organization_id');

-- 11. Expected immediately after migration: all counts are zero (no fictitious data).
select
  (select count(*) from public.organizations) as organizations_count,
  (select count(*) from public.organization_members) as memberships_count,
  (select count(*) from public.trainer_student_relationships) as relationships_count;

-- 12. Expected immediately after migration: zero; no platform role is auto-created.
select count(*) as platform_roles_count,
       count(*) filter (where role = 'platform_admin') as platform_admin_count
from public.platform_user_roles;

-- 13. Expected: authenticated has exactly SELECT on each new table.
select table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee = 'authenticated'
  and table_name in ('organizations', 'organization_members', 'trainer_student_relationships', 'platform_user_roles')
order by table_name, privilege_type;

-- 14. Expected: zero rows. anon has no direct table privilege.
select table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee = 'anon'
  and table_name in ('organizations', 'organization_members', 'trainer_student_relationships', 'platform_user_roles');

-- 15. Expected: zero rows. Neither role has direct write privileges.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated')
  and table_name in ('organizations', 'organization_members', 'trainer_student_relationships', 'platform_user_roles')
  and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
order by grantee, table_name, privilege_type;

-- 16. Expected: false for every function. anon cannot execute foundation helpers.
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('is_organization_member', 'has_organization_role', 'has_active_trainer_student_relationship', 'get_current_access_context')
order by p.proname;

-- 17. Expected: true for exactly these four functions and no other foundation function.
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('is_organization_member', 'has_organization_role', 'has_active_trainer_student_relationship', 'get_current_access_context')
order by p.proname;

-- 18. Expected: security_definer = true and search_path_setting is empty (search_path="").
select p.proname,
       p.prosecdef as security_definer,
       coalesce((select setting from unnest(p.proconfig) as setting where setting like 'search_path=%' limit 1), '') as search_path_setting
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('is_organization_member', 'has_organization_role', 'has_active_trainer_student_relationship', 'get_current_access_context')
order by p.proname;

-- 19. Expected: permissions_constraint_has_required_keys = true.
select conname,
       position('?&' in pg_get_constraintdef(oid)) > 0
         and pg_get_constraintdef(oid) like '%view_workouts%'
         and pg_get_constraintdef(oid) like '%assign_workouts%'
         and pg_get_constraintdef(oid) like '%view_executions%'
         and pg_get_constraintdef(oid) like '%view_evolution%'
         and pg_get_constraintdef(oid) like '%view_nutrition%'
         as permissions_constraint_has_required_keys,
       pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.trainer_student_relationships'::regclass
  and conname = 'trainer_student_relationships_permissions_check';

-- 20. Expected: confdeltype = n and definition contains ON DELETE SET NULL.
select conname, confdeltype,
       pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.trainer_student_relationships'::regclass
  and conname like '%requested_by%';

-- 21. Expected: slug constraint includes char_length, bounds 3/60 and a regular expression.
select conname,
       pg_get_constraintdef(oid) as definition,
       pg_get_constraintdef(oid) like '%char_length%' as has_char_length,
       pg_get_constraintdef(oid) like '%3%' as has_minimum_3,
       pg_get_constraintdef(oid) like '%60%' as has_maximum_60,
       pg_get_constraintdef(oid) like '%~%' as has_regular_expression
from pg_constraint
where conrelid = 'public.organizations'::regclass
  and contype = 'c'
  and pg_get_constraintdef(oid) like '%slug%';
