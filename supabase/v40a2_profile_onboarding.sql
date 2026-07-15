begin;

alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists timezone text;
alter table public.profiles add column if not exists locale text;
alter table public.profiles add column if not exists onboarding_completed boolean;
alter table public.profiles add column if not exists onboarding_step integer;
alter table public.profiles add column if not exists updated_at timestamptz;

-- Rows that existed before V4.0A2 remain immediately usable.
update public.profiles
set onboarding_completed = true,
    onboarding_step = coalesce(onboarding_step, 4),
    updated_at = coalesce(updated_at, now())
where onboarding_completed is null;

alter table public.profiles alter column onboarding_completed set default false;
alter table public.profiles alter column onboarding_completed set not null;
alter table public.profiles alter column onboarding_step set default 0;
alter table public.profiles alter column onboarding_step set not null;
alter table public.profiles alter column locale set default 'pt-BR';
alter table public.profiles alter column updated_at set default now();

alter table public.profiles enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and cmd='SELECT' and coalesce(qual,'') like '%auth.uid()%user_id%') then
    create policy profiles_select_own_v40a2 on public.profiles for select to authenticated using (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and cmd='INSERT' and coalesce(with_check,'') like '%auth.uid()%user_id%') then
    create policy profiles_insert_own_v40a2 on public.profiles for insert to authenticated with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and cmd='UPDATE' and coalesce(qual,'') like '%auth.uid()%user_id%' and coalesce(with_check,'') like '%auth.uid()%user_id%') then
    create policy profiles_update_own_v40a2 on public.profiles for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

commit;
