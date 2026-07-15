begin;

-- Future identity work must separate CPF digit validation, duplicate detection,
-- identity/status confirmation, CREF/CRN verification and payment billing purpose.
-- No CPF field is created until encryption, purpose and retention are defined.

create table if not exists public.account_plan_catalog (
  code text primary key,
  account_type text not null check (account_type in ('individual', 'trainer', 'nutritionist')),
  display_name text not null check (char_length(btrim(display_name)) between 3 and 80),
  active_client_limit integer check (active_client_limit is null or active_client_limit >= 0),
  is_free boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint account_plan_catalog_code_format_check check (code ~ '^[a-z][a-z0-9_]{2,49}$'),
  constraint account_plan_catalog_code_type_key unique (code, account_type)
);

create table if not exists public.user_commercial_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  primary_account_type text check (primary_account_type in ('individual', 'trainer', 'nutritionist')),
  plan_code text,
  subscription_status text not null default 'active' check (subscription_status in ('active', 'trialing', 'inactive', 'past_due', 'canceled')),
  personal_use_enabled boolean not null default true,
  account_type_selected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_commercial_accounts_type_plan_pair_check check ((primary_account_type is null) = (plan_code is null)),
  constraint user_commercial_accounts_plan_type_fk foreign key (plan_code, primary_account_type)
    references public.account_plan_catalog(code, account_type) on update restrict on delete restrict
);

create table if not exists public.user_identity_details (
  user_id uuid primary key references auth.users(id) on delete cascade,
  birth_date date not null,
  age_status text not null check (age_status in ('adult', 'minor', 'unknown')),
  age_verified_at timestamptz,
  country_code text not null default 'BR' check (country_code ~ '^[A-Z]{2}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_identity_details
  drop constraint if exists user_identity_details_birth_not_future,
  drop constraint if exists user_identity_details_age_plausible;

create or replace function public.validate_user_identity_birth_date_v41a1()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.birth_date is null or new.birth_date > current_date then
    raise exception 'Data de nascimento invalida.' using errcode = '22023';
  end if;
  if new.birth_date < (current_date - interval '120 years')::date then
    raise exception 'Data de nascimento invalida.' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_user_identity_birth_date_v41a1() from public, anon, authenticated;

drop trigger if exists validate_user_identity_birth_date_v41a1 on public.user_identity_details;
create trigger validate_user_identity_birth_date_v41a1
before insert or update of birth_date on public.user_identity_details
for each row execute function public.validate_user_identity_birth_date_v41a1();

create table if not exists public.user_legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_type text not null check (document_type in ('terms', 'privacy')),
  document_version text not null check (document_version ~ '^[a-z]+-[0-9]{4}-[0-9]{2}$'),
  accepted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint user_legal_acceptances_user_document_version_key unique (user_id, document_type, document_version)
);

create index if not exists user_commercial_accounts_plan_idx on public.user_commercial_accounts(plan_code);
create index if not exists user_legal_acceptances_user_idx on public.user_legal_acceptances(user_id, document_type);

alter table public.account_plan_catalog enable row level security;
alter table public.user_commercial_accounts enable row level security;
alter table public.user_identity_details enable row level security;
alter table public.user_legal_acceptances enable row level security;

insert into public.account_plan_catalog(code, account_type, display_name, active_client_limit, is_free, is_active)
values
  ('individual_free', 'individual', 'Individual Gratuito', null, true, true),
  ('trainer_free', 'trainer', 'Treinador Gratuito', 5, true, true),
  ('nutritionist_free', 'nutritionist', 'Nutricionista Gratuito', 5, true, true)
on conflict (code) do nothing;

revoke all on public.account_plan_catalog, public.user_commercial_accounts, public.user_identity_details, public.user_legal_acceptances from public, anon, authenticated;
grant select on public.account_plan_catalog, public.user_commercial_accounts, public.user_identity_details, public.user_legal_acceptances to authenticated;

drop policy if exists account_plan_catalog_select_active_v41a1 on public.account_plan_catalog;
create policy account_plan_catalog_select_active_v41a1 on public.account_plan_catalog for select to authenticated using (is_active = true);
drop policy if exists user_commercial_accounts_select_own_v41a1 on public.user_commercial_accounts;
create policy user_commercial_accounts_select_own_v41a1 on public.user_commercial_accounts for select to authenticated using (user_id = auth.uid());
drop policy if exists user_identity_details_select_own_v41a1 on public.user_identity_details;
create policy user_identity_details_select_own_v41a1 on public.user_identity_details for select to authenticated using (user_id = auth.uid());
drop policy if exists user_legal_acceptances_select_own_v41a1 on public.user_legal_acceptances;
create policy user_legal_acceptances_select_own_v41a1 on public.user_legal_acceptances for select to authenticated using (user_id = auth.uid());

create or replace function public.get_my_commercial_account_context()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select case when auth.uid() is null then jsonb_build_object(
    'primaryAccountType', null, 'planCode', null, 'planName', null,
    'subscriptionStatus', null, 'personalUseEnabled', true,
    'activeClientLimit', null, 'accountTypeSelectedAt', null,
    'requiresAccountTypeSelection', true, 'availableAccountTypes', '[]'::jsonb
  ) else jsonb_build_object(
    'primaryAccountType', account.primary_account_type,
    'planCode', account.plan_code,
    'planName', plan.display_name,
    'subscriptionStatus', account.subscription_status,
    'personalUseEnabled', coalesce(account.personal_use_enabled, true),
    'activeClientLimit', plan.active_client_limit,
    'accountTypeSelectedAt', account.account_type_selected_at,
    'requiresAccountTypeSelection', account.primary_account_type is null,
    'availableAccountTypes', coalesce((select jsonb_agg(jsonb_build_object(
      'accountType', catalog.account_type,
      'planCode', catalog.code,
      'planName', catalog.display_name,
      'activeClientLimit', catalog.active_client_limit
    ) order by catalog.code) from public.account_plan_catalog catalog where catalog.is_active and catalog.is_free), '[]'::jsonb)
  )
  from (select auth.uid() user_id) current_user
  left join public.user_commercial_accounts account on account.user_id = current_user.user_id
  left join public.account_plan_catalog plan on plan.code = account.plan_code and plan.account_type = account.primary_account_type;
$$;

create or replace function public.get_my_account_registration_context()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select case when auth.uid() is null then jsonb_build_object(
    'profileCompleted', false, 'fullName', null, 'displayName', null,
    'ageStatus', 'unknown', 'identityCompleted', false,
    'termsAccepted', false, 'privacyAccepted', false,
    'currentTermsVersion', 'terms-2026-01', 'currentPrivacyVersion', 'privacy-2026-01',
    'primaryAccountType', null, 'planCode', null, 'planName', null,
    'subscriptionStatus', null, 'personalUseEnabled', true,
    'activeClientLimit', null, 'accountTypeSelectedAt', null,
    'requiresAccountTypeSelection', true, 'requiresIdentityCompletion', true,
    'requiresLegalAcceptance', true, 'availableAccountTypes', '[]'::jsonb
  ) else (
    select commercial || jsonb_build_object(
      'profileCompleted', nullif(btrim(profile.full_name), '') is not null,
      'fullName', nullif(btrim(profile.full_name), ''),
      'displayName', nullif(btrim(profile.display_name), ''),
      'ageStatus', coalesce(identity.age_status, 'unknown'),
      'identityCompleted', identity.age_status = 'adult',
      'termsAccepted', exists(select 1 from public.user_legal_acceptances acceptance where acceptance.user_id=auth.uid() and acceptance.document_type='terms' and acceptance.document_version='terms-2026-01'),
      'privacyAccepted', exists(select 1 from public.user_legal_acceptances acceptance where acceptance.user_id=auth.uid() and acceptance.document_type='privacy' and acceptance.document_version='privacy-2026-01'),
      'currentTermsVersion', 'terms-2026-01',
      'currentPrivacyVersion', 'privacy-2026-01',
      'requiresIdentityCompletion', coalesce(identity.age_status, 'unknown') <> 'adult',
      'requiresLegalAcceptance', not (
        exists(select 1 from public.user_legal_acceptances acceptance where acceptance.user_id=auth.uid() and acceptance.document_type='terms' and acceptance.document_version='terms-2026-01')
        and exists(select 1 from public.user_legal_acceptances acceptance where acceptance.user_id=auth.uid() and acceptance.document_type='privacy' and acceptance.document_version='privacy-2026-01')
      )
    )
    from (select public.get_my_commercial_account_context() commercial) context
    left join public.profiles profile on profile.user_id=auth.uid()
    left join public.user_identity_details identity on identity.user_id=auth.uid()
  ) end;
$$;

create or replace function public.complete_my_initial_account_setup(
  target_account_type text,
  target_full_name text,
  target_display_name text,
  target_birth_date date,
  accepted_terms_version text,
  accepted_privacy_version text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_type text := pg_catalog.lower(pg_catalog.btrim(coalesce(target_account_type, '')));
  normalized_full_name text := pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(target_full_name, '')), '[[:space:]]+', ' ', 'g');
  normalized_display_name text := pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(target_display_name, '')), '[[:space:]]+', ' ', 'g');
  calculated_age integer;
  selected_plan_code text;
  existing_type text;
  existing_birth_date date;
  existing_profile_birth_date date;
begin
  if current_user_id is null then raise exception 'Sessão indisponível.' using errcode='42501'; end if;
  if normalized_type not in ('individual','trainer','nutritionist') then raise exception 'Tipo principal inválido.' using errcode='22023'; end if;
  if char_length(normalized_full_name) not between 2 and 80 or normalized_full_name !~ '[[:alpha:]]' then raise exception 'Nome completo inválido.' using errcode='22023'; end if;
  if char_length(normalized_display_name) > 40 then raise exception 'Nome de exibição inválido.' using errcode='22023'; end if;
  if normalized_display_name = '' then normalized_display_name := split_part(normalized_full_name, ' ', 1); end if;
  if target_birth_date is null or target_birth_date > current_date then raise exception 'Data de nascimento inválida.' using errcode='22023'; end if;
  if target_birth_date < (current_date - interval '120 years')::date then raise exception 'Data de nascimento inválida.' using errcode='22023'; end if;
  calculated_age := extract(year from age(current_date, target_birth_date));
  if calculated_age < 18 then raise exception 'O cadastro de menores ainda não está disponível nesta versão do Forja.' using errcode='22023'; end if;
  if accepted_terms_version <> 'terms-2026-01' or accepted_privacy_version <> 'privacy-2026-01' then raise exception 'Aceites legais desatualizados.' using errcode='22023'; end if;
  selected_plan_code := case normalized_type when 'individual' then 'individual_free' when 'trainer' then 'trainer_free' when 'nutritionist' then 'nutritionist_free' end;

  insert into public.user_commercial_accounts(user_id) values(current_user_id) on conflict(user_id) do nothing;
  select primary_account_type into existing_type from public.user_commercial_accounts where user_id=current_user_id for update;
  select birth_date into existing_profile_birth_date from public.profiles where user_id=current_user_id for update;
  if existing_profile_birth_date is not null and existing_profile_birth_date <> target_birth_date then raise exception 'A data de nascimento ja foi confirmada.' using errcode='42501'; end if;
  if existing_type is not null and existing_type <> normalized_type then raise exception 'O tipo principal já foi definido e não pode ser trocado diretamente.' using errcode='42501'; end if;
  select birth_date into existing_birth_date from public.user_identity_details where user_id=current_user_id for update;
  if existing_birth_date is not null and existing_birth_date <> target_birth_date then raise exception 'A data de nascimento já foi confirmada.' using errcode='42501'; end if;

  insert into public.user_identity_details(user_id,birth_date,age_status,age_verified_at,country_code)
  values(current_user_id,target_birth_date,'adult',now(),'BR')
  on conflict(user_id) do update set birth_date=excluded.birth_date,age_status='adult',age_verified_at=coalesce(public.user_identity_details.age_verified_at,now()),updated_at=now();

  insert into public.profiles(user_id,full_name,display_name,birth_date,locale,updated_at)
  values(current_user_id,normalized_full_name,normalized_display_name,target_birth_date,'pt-BR',now())
  on conflict(user_id) do update set full_name=excluded.full_name,display_name=excluded.display_name,birth_date=coalesce(public.profiles.birth_date,excluded.birth_date),locale=coalesce(public.profiles.locale,'pt-BR'),updated_at=now();

  update public.user_commercial_accounts set primary_account_type=normalized_type,plan_code=selected_plan_code,account_type_selected_at=coalesce(account_type_selected_at,now()),updated_at=now() where user_id=current_user_id;

  insert into public.user_legal_acceptances(user_id,document_type,document_version)
  values(current_user_id,'terms',accepted_terms_version),(current_user_id,'privacy',accepted_privacy_version)
  on conflict(user_id,document_type,document_version) do nothing;

  insert into public.user_account_modes(user_id,mode) values(current_user_id,normalized_type)
  on conflict(user_id,mode) do update set updated_at=now();
  if normalized_type in ('trainer','nutritionist') then
    insert into public.user_account_modes(user_id,mode) values(current_user_id,'individual')
    on conflict(user_id,mode) do update set updated_at=now();
  end if;

  return public.get_my_account_registration_context();
end;
$$;

create or replace function public.set_my_personal_use_enabled(target_enabled boolean)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Sessão indisponível.' using errcode='42501'; end if;
  if target_enabled is null then raise exception 'Valor inválido.' using errcode='22023'; end if;
  insert into public.user_commercial_accounts(user_id,personal_use_enabled) values(auth.uid(),target_enabled)
  on conflict(user_id) do update set personal_use_enabled=excluded.personal_use_enabled,updated_at=now();
  if target_enabled then insert into public.user_account_modes(user_id,mode) values(auth.uid(),'individual') on conflict(user_id,mode) do update set updated_at=now(); end if;
  return public.get_my_commercial_account_context();
end;
$$;

-- Preserve the V4.1A context as the base and append only minimal registration data.
do $$
begin
  if to_regprocedure('public.get_current_access_context_v41a()') is null then
    alter function public.get_current_access_context() rename to get_current_access_context_v41a;
  end if;
end $$;

create or replace function public.get_current_access_context()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select public.get_current_access_context_v41a() || jsonb_build_object(
    'commercialAccount', jsonb_build_object(
      'primaryAccountType', commercial->'primaryAccountType',
      'planCode', commercial->'planCode',
      'subscriptionStatus', commercial->'subscriptionStatus',
      'activeClientLimit', commercial->'activeClientLimit',
      'personalUseEnabled', commercial->'personalUseEnabled',
      'requiresAccountTypeSelection', commercial->'requiresAccountTypeSelection'
    ),
    'registration', jsonb_build_object(
      'profileCompleted', registration->'profileCompleted',
      'ageVerified', to_jsonb((registration->>'ageStatus') = 'adult'),
      'legalAcceptancesCurrent', to_jsonb((registration->>'termsAccepted')::boolean and (registration->>'privacyAccepted')::boolean)
    )
  )
  from (select public.get_my_commercial_account_context() commercial, public.get_my_account_registration_context() registration) context;
$$;

revoke all on function public.get_my_commercial_account_context(), public.get_my_account_registration_context(), public.complete_my_initial_account_setup(text,text,text,date,text,text), public.set_my_personal_use_enabled(boolean), public.get_current_access_context(), public.get_current_access_context_v41a() from public, anon, authenticated;
grant execute on function public.get_my_commercial_account_context(), public.get_my_account_registration_context(), public.complete_my_initial_account_setup(text,text,text,date,text,text), public.set_my_personal_use_enabled(boolean), public.get_current_access_context() to authenticated;

commit;
