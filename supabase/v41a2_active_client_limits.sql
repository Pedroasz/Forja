begin;

-- Internal counter. The optional exclusion keeps active-row identity changes neutral.
create or replace function public.get_professional_active_client_count_v41a2(
  target_professional_id uuid,
  target_professional_type text,
  relationship_id_to_exclude uuid default null
) returns bigint
language plpgsql volatile security definer
set search_path = ''
as $$
declare active_count bigint;
begin
  if target_professional_id is null or target_professional_type not in ('trainer','nutritionist') then
    raise exception 'invalid_professional_capacity_parameters' using errcode='22023';
  end if;
  select count(distinct relationship.student_user_id)
    into active_count
  from public.professional_student_relationships relationship
  where relationship.professional_user_id=target_professional_id
    and relationship.professional_type=target_professional_type
    and relationship.status='active'
    and (relationship_id_to_exclude is null or relationship.id<>relationship_id_to_exclude);
  return coalesce(active_count,0);
end;
$$;

create or replace function public.assert_professional_client_capacity_v41a2(
  target_professional_id uuid,
  target_professional_type text,
  target_student_id uuid,
  relationship_id_to_exclude uuid default null
) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  account_record record;
  plan_record record;
  active_count bigint;
begin
  if target_professional_id is null or target_student_id is null
     or target_professional_id=target_student_id
     or target_professional_type not in ('trainer','nutritionist') then
    raise exception 'invalid_professional_capacity_parameters' using errcode='22023';
  end if;

  select account.primary_account_type,account.plan_code,account.subscription_status
    into account_record
  from public.user_commercial_accounts account
  where account.user_id=target_professional_id
  for update;
  if not found or account_record.primary_account_type is null or account_record.plan_code is null then
    raise exception 'professional_account_required' using errcode='P0001';
  end if;
  if account_record.primary_account_type<>target_professional_type then
    raise exception 'professional_account_type_mismatch' using errcode='P0001';
  end if;
  if account_record.subscription_status not in ('active','trialing') then
    raise exception 'professional_subscription_inactive' using errcode='P0001';
  end if;

  select plan.active_client_limit,plan.is_active
    into plan_record
  from public.account_plan_catalog plan
  where plan.code=account_record.plan_code
    and plan.account_type=target_professional_type
    and plan.is_active=true;
  if not found then
    raise exception 'professional_plan_unavailable' using errcode='P0001';
  end if;

  -- Another active organization relationship for this student already occupies the slot.
  if exists(
    select 1 from public.professional_student_relationships relationship
    where relationship.professional_user_id=target_professional_id
      and relationship.professional_type=target_professional_type
      and relationship.student_user_id=target_student_id
      and relationship.status='active'
      and (relationship_id_to_exclude is null or relationship.id<>relationship_id_to_exclude)
  ) then return; end if;

  if plan_record.active_client_limit is null then return; end if;
  active_count:=public.get_professional_active_client_count_v41a2(
    target_professional_id,target_professional_type,relationship_id_to_exclude
  );
  if active_count>=plan_record.active_client_limit then
    raise exception 'professional_client_limit_reached' using errcode='P0001';
  end if;
end;
$$;

create or replace function public.enforce_professional_client_limit_v41a2()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.status='active' and (
    tg_op='INSERT'
    or old.status is distinct from 'active'
    or old.professional_user_id is distinct from new.professional_user_id
    or old.professional_type is distinct from new.professional_type
    or old.student_user_id is distinct from new.student_user_id
  ) then
    perform public.assert_professional_client_capacity_v41a2(
      new.professional_user_id,
      new.professional_type,
      new.student_user_id,
      case when tg_op='UPDATE' then old.id else null end
    );
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_professional_client_limit_v41a2 on public.professional_student_relationships;
create trigger enforce_professional_client_limit_v41a2
before insert or update of status,professional_user_id,professional_type,student_user_id
on public.professional_student_relationships
for each row execute function public.enforce_professional_client_limit_v41a2();

create or replace function public.get_my_professional_client_capacity()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  current_user_id uuid:=auth.uid();
  account_record record;
  plan_record record;
  professional_type text;
  active_count bigint:=0;
  remaining_slots integer;
  limit_reached boolean:=false;
  requires_professional_account boolean:=true;
  can_activate boolean:=false;
begin
  if current_user_id is null then
    raise exception 'session_required' using errcode='42501';
  end if;
  select account.primary_account_type,account.plan_code,account.subscription_status
    into account_record
  from public.user_commercial_accounts account
  where account.user_id=current_user_id;
  if not found then
    return jsonb_build_object(
      'professionalType',null,'planCode',null,'planName',null,'subscriptionStatus',null,
      'activeClientLimit',null,'activeClientCount',0,'remainingSlots',null,
      'limitReached',false,'canActivateNewClient',false,'requiresProfessionalAccount',true
    );
  end if;

  if account_record.primary_account_type in ('trainer','nutritionist') then
    professional_type:=account_record.primary_account_type;
    requires_professional_account:=false;
    active_count:=public.get_professional_active_client_count_v41a2(current_user_id,professional_type);
  end if;
  select plan.display_name,plan.active_client_limit,plan.is_active
    into plan_record
  from public.account_plan_catalog plan
  where plan.code=account_record.plan_code
    and plan.account_type=account_record.primary_account_type;

  if plan_record.active_client_limit is not null then
    remaining_slots:=greatest(plan_record.active_client_limit-active_count::integer,0);
    limit_reached:=active_count>=plan_record.active_client_limit;
  end if;
  can_activate:=not requires_professional_account
    and coalesce(plan_record.is_active,false)
    and account_record.subscription_status in ('active','trialing')
    and not limit_reached;

  return jsonb_build_object(
    'professionalType',professional_type,
    'planCode',account_record.plan_code,
    'planName',plan_record.display_name,
    'subscriptionStatus',account_record.subscription_status,
    'activeClientLimit',plan_record.active_client_limit,
    'activeClientCount',active_count,
    'remainingSlots',remaining_slots,
    'limitReached',limit_reached,
    'canActivateNewClient',can_activate,
    'requiresProfessionalAccount',requires_professional_account
  );
end;
$$;

-- Keep every existing commercial-context field and append derived capacity only.
create or replace function public.get_my_commercial_account_context()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select case when auth.uid() is null then jsonb_build_object(
    'primaryAccountType',null,'planCode',null,'planName',null,
    'subscriptionStatus',null,'personalUseEnabled',true,
    'activeClientLimit',null,'activeClientCount',0,'remainingSlots',null,
    'limitReached',false,'canActivateNewClient',false,
    'accountTypeSelectedAt',null,'requiresAccountTypeSelection',true,
    'availableAccountTypes','[]'::jsonb
  ) else jsonb_build_object(
    'primaryAccountType',account.primary_account_type,
    'planCode',account.plan_code,
    'planName',plan.display_name,
    'subscriptionStatus',account.subscription_status,
    'personalUseEnabled',coalesce(account.personal_use_enabled,true),
    'activeClientLimit',capacity->'activeClientLimit',
    'activeClientCount',capacity->'activeClientCount',
    'remainingSlots',capacity->'remainingSlots',
    'limitReached',capacity->'limitReached',
    'canActivateNewClient',capacity->'canActivateNewClient',
    'accountTypeSelectedAt',account.account_type_selected_at,
    'requiresAccountTypeSelection',account.primary_account_type is null,
    'availableAccountTypes',coalesce((select jsonb_agg(jsonb_build_object(
      'accountType',catalog.account_type,'planCode',catalog.code,
      'planName',catalog.display_name,'activeClientLimit',catalog.active_client_limit
    ) order by catalog.code) from public.account_plan_catalog catalog
      where catalog.is_active and catalog.is_free),'[]'::jsonb)
  )
  from (select auth.uid() user_id) current_user
  left join public.user_commercial_accounts account on account.user_id=current_user.user_id
  left join public.account_plan_catalog plan on plan.code=account.plan_code and plan.account_type=account.primary_account_type
  cross join lateral (
    select case
      when auth.uid() is null then '{}'::jsonb
      else public.get_my_professional_client_capacity()
    end capacity
  ) capacity_context;
$$;

revoke all on function public.get_professional_active_client_count_v41a2(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.assert_professional_client_capacity_v41a2(uuid,text,uuid,uuid) from public,anon,authenticated;
revoke all on function public.enforce_professional_client_limit_v41a2() from public,anon,authenticated;
revoke all on function public.get_my_professional_client_capacity() from public,anon,authenticated;
revoke all on function public.get_my_commercial_account_context() from public,anon,authenticated;
grant execute on function public.get_my_professional_client_capacity() to authenticated;
grant execute on function public.get_my_commercial_account_context() to authenticated;

commit;
