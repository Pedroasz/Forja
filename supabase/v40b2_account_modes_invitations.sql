begin;

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.user_account_modes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null check (mode in ('individual', 'student', 'trainer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_account_modes_user_mode_key unique (user_id, mode)
);

create table if not exists public.trainer_student_invitations (
  id uuid primary key default gen_random_uuid(),
  trainer_user_id uuid not null references auth.users(id) on delete cascade,
  invite_code_hash text not null,
  invite_code_prefix text not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'cancelled', 'expired')),
  expires_at timestamptz not null,
  accepted_by_user_id uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trainer_student_invitations_hash_key unique (invite_code_hash)
);

create index if not exists user_account_modes_user_id_idx on public.user_account_modes (user_id);
create index if not exists trainer_student_invitations_trainer_idx on public.trainer_student_invitations (trainer_user_id);
create index if not exists trainer_student_invitations_accepted_by_idx on public.trainer_student_invitations (accepted_by_user_id);
create index if not exists trainer_student_invitations_status_idx on public.trainer_student_invitations (status);
create index if not exists trainer_student_invitations_expires_idx on public.trainer_student_invitations (expires_at);
create index if not exists trainer_student_invitations_trainer_status_idx on public.trainer_student_invitations (trainer_user_id, status);

alter table public.user_account_modes enable row level security;
alter table public.trainer_student_invitations enable row level security;

create or replace function public.normalize_invitation_code(input_code text)
returns text
language sql immutable
set search_path = ''
as $$
  select pg_catalog.upper(pg_catalog.regexp_replace(pg_catalog.coalesce(input_code, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create or replace function public.get_my_account_modes()
returns text[]
language sql stable security definer
set search_path = ''
as $$
  select case when auth.uid() is null then array[]::text[] else coalesce(
    (select array_agg(account_mode.mode order by account_mode.mode)
     from public.user_account_modes account_mode
     where account_mode.user_id = auth.uid()),
    array[]::text[]
  ) end;
$$;

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
  if exists (select 1 from unnest(normalized_modes) mode where mode not in ('individual', 'student', 'trainer')) then
    raise exception 'Modo de uso inválido.' using errcode = '22023';
  end if;
  delete from public.user_account_modes where user_id = current_user_id and mode <> all(normalized_modes);
  insert into public.user_account_modes (user_id, mode)
  select current_user_id, mode from unnest(normalized_modes) mode
  on conflict (user_id, mode) do update set updated_at = now();
  return normalized_modes;
end;
$$;

create or replace function public.create_trainer_student_invitation()
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid(); raw_token text; full_code text; normalized_code text;
  code_hash text; code_prefix text; invitation_id uuid; invitation_expires_at timestamptz;
begin
  if current_user_id is null then raise exception 'Sessão indisponível.' using errcode = '42501'; end if;
  perform 1 from public.user_account_modes
  where user_id=current_user_id and mode='trainer'
  for update;
  if not found then
    raise exception 'Ative o modo Treinador no seu perfil para gerar convites.' using errcode = '42501';
  end if;
  update public.trainer_student_invitations set status='expired', updated_at=now()
  where trainer_user_id=current_user_id and status='pending' and expires_at <= now();
  if (select count(*) from public.trainer_student_invitations where trainer_user_id=current_user_id and status='pending' and expires_at>now()) >= 20 then
    raise exception 'Você atingiu o limite de convites ativos.' using errcode = '54000';
  end if;
  loop
    raw_token := pg_catalog.upper(pg_catalog.encode(extensions.gen_random_bytes(10), 'hex'));
    full_code := 'FORJA-' || substring(raw_token,1,4) || '-' || substring(raw_token,5,4) || '-' || substring(raw_token,9,4) || '-' || substring(raw_token,13,4) || '-' || substring(raw_token,17,4);
    normalized_code := public.normalize_invitation_code(full_code);
    code_hash := pg_catalog.encode(extensions.digest(normalized_code, 'sha256'), 'hex');
    exit when not exists (select 1 from public.trainer_student_invitations where invite_code_hash=code_hash);
  end loop;
  code_prefix := 'FORJA-' || substring(raw_token,1,4);
  invitation_expires_at := now() + interval '7 days';
  insert into public.trainer_student_invitations (trainer_user_id,invite_code_hash,invite_code_prefix,expires_at)
  values (current_user_id,code_hash,code_prefix,invitation_expires_at) returning id into invitation_id;
  return jsonb_build_object('id',invitation_id,'invite_code',full_code,'invite_code_prefix',code_prefix,'expires_at',invitation_expires_at);
end;
$$;

create or replace function public.preview_trainer_invitation(invite_code text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare current_user_id uuid:=auth.uid(); normalized_code text; code_hash text; invitation record; trainer_name text;
begin
  if current_user_id is null then raise exception 'Sessão indisponível.' using errcode='42501'; end if;
  normalized_code:=public.normalize_invitation_code(invite_code);
  if char_length(normalized_code)<>25 then return jsonb_build_object('valid',false,'message','Este código não é válido ou não está mais disponível.'); end if;
  code_hash:=pg_catalog.encode(extensions.digest(normalized_code,'sha256'),'hex');
  select * into invitation from public.trainer_student_invitations where invite_code_hash=code_hash;
  if not found or invitation.status<>'pending' then return jsonb_build_object('valid',false,'message','Este código não é válido ou não está mais disponível.'); end if;
  if invitation.expires_at<=now() then
    update public.trainer_student_invitations set status='expired',updated_at=now() where id=invitation.id;
    return jsonb_build_object('valid',false,'message','Este convite não está mais disponível.');
  end if;
  if invitation.trainer_user_id=current_user_id then return jsonb_build_object('valid',false,'message','Você não pode aceitar um convite criado pela sua própria conta.'); end if;
  select coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Treinador do Forja') into trainer_name
  from public.profiles profile where profile.user_id=invitation.trainer_user_id;
  return jsonb_build_object('valid',true,'trainer_display_name',coalesce(trainer_name,'Treinador do Forja'),'expires_at',invitation.expires_at,'invite_prefix',invitation.invite_code_prefix);
end;
$$;

create or replace function public.accept_trainer_student_invitation(invite_code text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare current_user_id uuid:=auth.uid(); normalized_code text; code_hash text; invitation record; relationship_id uuid; relationship_permissions jsonb;
  safe_permissions jsonb:=jsonb_build_object('view_workouts',false,'assign_workouts',false,'view_executions',false,'view_evolution',false,'view_nutrition',false);
begin
  if current_user_id is null then raise exception 'Sessão indisponível.' using errcode='42501'; end if;
  normalized_code:=public.normalize_invitation_code(invite_code);
  if char_length(normalized_code)<>25 then return jsonb_build_object('accepted',false,'message','Este código não é válido ou não está mais disponível.'); end if;
  code_hash:=pg_catalog.encode(extensions.digest(normalized_code,'sha256'),'hex');
  select * into invitation from public.trainer_student_invitations where invite_code_hash=code_hash for update;
  if not found or invitation.status<>'pending' then return jsonb_build_object('accepted',false,'message','Este código não é válido ou não está mais disponível.'); end if;
  if invitation.expires_at<=now() then update public.trainer_student_invitations set status='expired',updated_at=now() where id=invitation.id; return jsonb_build_object('accepted',false,'message','Este convite não está mais disponível.'); end if;
  if invitation.trainer_user_id=current_user_id then return jsonb_build_object('accepted',false,'message','Você não pode aceitar um convite criado pela sua própria conta.'); end if;
  insert into public.trainer_student_relationships (trainer_user_id,student_user_id,organization_id,status,permissions,requested_by,accepted_at)
  values (invitation.trainer_user_id,current_user_id,null,'active',safe_permissions,invitation.trainer_user_id,now())
  on conflict (trainer_user_id,student_user_id) where organization_id is null
  do update set
    status='active',
    permissions=case
      when public.trainer_student_relationships.status='active' then public.trainer_student_relationships.permissions
      else excluded.permissions
    end,
    accepted_at=case
      when public.trainer_student_relationships.status='active' then public.trainer_student_relationships.accepted_at
      else excluded.accepted_at
    end,
    revoked_at=null,
    updated_at=now()
  returning id, permissions
  into relationship_id, relationship_permissions;
  insert into public.user_account_modes(user_id,mode) values(current_user_id,'student') on conflict(user_id,mode) do update set updated_at=now();
  update public.trainer_student_invitations set status='accepted',accepted_by_user_id=current_user_id,accepted_at=now(),updated_at=now() where id=invitation.id;
  return jsonb_build_object('accepted',true,'relationship_id',relationship_id,'status','active','permissions',relationship_permissions);
end;
$$;

create or replace function public.cancel_trainer_invitation(invitation_id uuid)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Sessão indisponível.' using errcode='42501'; end if;
  update public.trainer_student_invitations set status='cancelled',cancelled_at=now(),updated_at=now()
  where id=invitation_id and trainer_user_id=auth.uid() and status='pending' and expires_at>now();
  return found;
end;
$$;

create or replace function public.list_my_trainer_invitations()
returns table(id uuid,invite_code_prefix text,status text,expires_at timestamptz,created_at timestamptz,accepted_at timestamptz,cancelled_at timestamptz)
language sql stable security definer
set search_path = ''
as $$
  select invitation.id,invitation.invite_code_prefix,
         case when invitation.status='pending' and invitation.expires_at<=now() then 'expired' else invitation.status end as status,
         invitation.expires_at,invitation.created_at,invitation.accepted_at,invitation.cancelled_at
  from public.trainer_student_invitations invitation where auth.uid() is not null and invitation.trainer_user_id=auth.uid() order by invitation.created_at desc;
$$;

create or replace function public.list_my_trainer_student_connections()
returns table(relationship_id uuid,role_in_relationship text,display_name text,status text,permissions jsonb)
language sql stable security definer
set search_path = ''
as $$
  select relationship.id,'trainer'::text,coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Usuário do Forja'),relationship.status,relationship.permissions
  from public.trainer_student_relationships relationship join public.profiles profile on profile.user_id=relationship.student_user_id
  where relationship.trainer_user_id=auth.uid()
  union all
  select relationship.id,'student'::text,coalesce(nullif(profile.display_name,''),nullif(profile.full_name,''),'Treinador do Forja'),relationship.status,relationship.permissions
  from public.trainer_student_relationships relationship join public.profiles profile on profile.user_id=relationship.trainer_user_id
  where relationship.student_user_id=auth.uid();
$$;

revoke all on public.user_account_modes,public.trainer_student_invitations from public,anon,authenticated;
grant select on public.user_account_modes to authenticated;

drop policy if exists user_account_modes_select_own_v40b2 on public.user_account_modes;
create policy user_account_modes_select_own_v40b2 on public.user_account_modes for select to authenticated using(user_id=auth.uid());
drop policy if exists trainer_student_invitations_select_related_v40b2 on public.trainer_student_invitations;
create policy trainer_student_invitations_select_related_v40b2 on public.trainer_student_invitations for select to authenticated
using(trainer_user_id=auth.uid() or (status='accepted' and accepted_by_user_id=auth.uid()));

revoke all on function public.normalize_invitation_code(text),public.get_my_account_modes(),public.set_my_account_modes(text[]),public.create_trainer_student_invitation(),public.preview_trainer_invitation(text),public.accept_trainer_student_invitation(text),public.cancel_trainer_invitation(uuid),public.list_my_trainer_invitations(),public.list_my_trainer_student_connections() from public,anon,authenticated;
grant execute on function public.get_my_account_modes(),public.set_my_account_modes(text[]),public.create_trainer_student_invitation(),public.preview_trainer_invitation(text),public.accept_trainer_student_invitation(text),public.cancel_trainer_invitation(uuid),public.list_my_trainer_invitations(),public.list_my_trainer_student_connections() to authenticated;

commit;
