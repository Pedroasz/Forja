begin;

drop function if exists public.list_my_student_workout_executions(uuid, uuid, uuid, date, date, integer, date, uuid);
drop function if exists public.list_my_student_nutrition_logs(uuid, uuid, uuid, date, date, integer, date, uuid);
drop function if exists public.list_my_student_evolution(uuid, uuid, text, uuid, date, date, integer, date, uuid);

drop function if exists public.assert_professional_monitoring_page_v41d(date, date, integer, date, uuid);
drop function if exists public.assert_professional_student_read_access_v41d(uuid, uuid, text, text, uuid);

-- Only indexes carrying the V4.1D ownership marker are eligible for removal.
do $v41d_rollback_indexes$
begin
  if pg_catalog.to_regclass('public.workouts_user_date_id_v41d_idx') is not null
     and pg_catalog.obj_description(
       pg_catalog.to_regclass('public.workouts_user_date_id_v41d_idx'),
       'pg_class'
     ) = 'FORJA V4.1D professional monitoring' then
    execute 'drop index public.workouts_user_date_id_v41d_idx';
  end if;

  if pg_catalog.to_regclass('public.meals_user_date_id_v41d_idx') is not null
     and pg_catalog.obj_description(
       pg_catalog.to_regclass('public.meals_user_date_id_v41d_idx'),
       'pg_class'
     ) = 'FORJA V4.1D professional monitoring' then
    execute 'drop index public.meals_user_date_id_v41d_idx';
  end if;

  if pg_catalog.to_regclass('public.evolution_user_date_id_v41d_idx') is not null
     and pg_catalog.obj_description(
       pg_catalog.to_regclass('public.evolution_user_date_id_v41d_idx'),
       'pg_class'
     ) = 'FORJA V4.1D professional monitoring' then
    execute 'drop index public.evolution_user_date_id_v41d_idx';
  end if;
end;
$v41d_rollback_indexes$;

commit;
