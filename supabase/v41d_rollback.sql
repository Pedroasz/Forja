begin;

drop function if exists public.list_my_student_workout_executions(uuid, date, date, integer, date, uuid);
drop function if exists public.list_my_student_nutrition_logs(uuid, date, date, integer, date, uuid);
drop function if exists public.list_my_student_evolution(uuid, date, date, integer, date, uuid);

drop function if exists public.get_my_professional_monitoring_entitlement_v41d(uuid, text, text[]);
drop function if exists public.assert_professional_monitoring_page_v41d(date, date, integer, date, uuid);

-- Only the V4.1D-owned workout index may be removed; base meal/evolution indexes are untouched.
do $v41d_rollback_indexes$
begin
  if pg_catalog.to_regclass('public.workouts_user_date_id_v41d_idx') is not null
     and pg_catalog.obj_description(
       pg_catalog.to_regclass('public.workouts_user_date_id_v41d_idx'),
       'pg_class'
     ) = 'FORJA V4.1D professional monitoring' then
    execute 'drop index public.workouts_user_date_id_v41d_idx';
  end if;
end;
$v41d_rollback_indexes$;

commit;
