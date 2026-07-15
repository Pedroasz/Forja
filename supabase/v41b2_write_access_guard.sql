begin;

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

revoke all on function public.assert_my_trainer_write_access_v41b() from public,anon,authenticated;

commit;
