-- V4.1C execution order: 1) v41c_notifications.sql, 2) v41c_nutrition_plan_assignments.sql, 3) v41c_verify.sql.
begin;

create or replace function public.notification_iso_date_is_valid_v41c(target_value text)
returns boolean
language plpgsql immutable security invoker
set search_path = ''
as $$
declare parsed_value date;
begin
  if target_value is null or target_value!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return false; end if;
  parsed_value:=target_value::date;
  return pg_catalog.to_char(parsed_value,'YYYY-MM-DD')=target_value;
exception when invalid_datetime_format or datetime_field_overflow then
  return false;
end;
$$;

create or replace function public.notification_metadata_is_safe_v41c(target_value jsonb)
returns boolean
language sql immutable security definer
set search_path = ''
as $$
  select target_value is not null
    and jsonb_typeof(target_value)='object'
    and octet_length(target_value::text)<=8192
    and not exists (
      select 1
      from jsonb_each(case when jsonb_typeof(target_value)='object' then target_value else '{}'::jsonb end) metadata_item
      where metadata_item.key not in ('professionalType','version','effectiveFrom','severity','action','route','code')
        or case metadata_item.key
          when 'professionalType' then
            jsonb_typeof(metadata_item.value)<>'string'
            or metadata_item.value#>>'{}' not in ('trainer','nutritionist')
          when 'version' then
            jsonb_typeof(metadata_item.value)<>'number'
            or metadata_item.value#>>'{}'!~'^[1-9][0-9]{0,9}$'
            or case
              when jsonb_typeof(metadata_item.value)='number' and metadata_item.value#>>'{}'~'^[1-9][0-9]{0,9}$'
                then (metadata_item.value#>>'{}')::numeric>2147483647
              else false
            end
          when 'effectiveFrom' then
            jsonb_typeof(metadata_item.value) not in ('string','null')
            or (jsonb_typeof(metadata_item.value)='string' and not public.notification_iso_date_is_valid_v41c(metadata_item.value#>>'{}'))
          when 'severity' then
            jsonb_typeof(metadata_item.value)<>'string'
            or metadata_item.value#>>'{}' not in ('info','success','warning','error')
          when 'action' then
            jsonb_typeof(metadata_item.value)<>'string'
            or char_length(metadata_item.value#>>'{}') not between 1 and 80
            or metadata_item.value#>>'{}'~*'[<>]|[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}'
            or regexp_replace(metadata_item.value#>>'{}','[^0-9]','','g')~'^[0-9]{10,14}$'
          when 'route' then
            jsonb_typeof(metadata_item.value)<>'string'
            or metadata_item.value#>>'{}' not in ('home','dieta','treino','evolucao','exportar','profile','connections')
          when 'code' then
            jsonb_typeof(metadata_item.value)<>'string'
            or char_length(metadata_item.value#>>'{}') not between 1 and 80
            or metadata_item.value#>>'{}'!~'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$'
            or metadata_item.value#>>'{}'~*'[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}'
            or regexp_replace(metadata_item.value#>>'{}','[^0-9]','','g')~'^[0-9]{10,14}$'
          else true
        end
    )
$$;

create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  notification_type text not null,
  title text not null,
  message text not null,
  entity_type text,
  entity_id uuid,
  dedupe_key text,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  constraint user_notifications_type_check check (notification_type in (
    'relationship_activated','relationship_revoked','workout_plan_assigned','workout_plan_updated','workout_plan_revoked',
    'nutrition_plan_assigned','nutrition_plan_updated','nutrition_plan_revoked','system'
  )),
  constraint user_notifications_entity_type_check check (entity_type is null or entity_type in ('relationship','workout_assignment','nutrition_assignment','system')),
  constraint user_notifications_title_check check (char_length(btrim(title)) between 1 and 120),
  constraint user_notifications_message_check check (char_length(btrim(message)) between 1 and 500),
  constraint user_notifications_dedupe_key_check check (
    dedupe_key is null or (dedupe_key=btrim(dedupe_key) and char_length(btrim(dedupe_key)) between 1 and 200)
  ),
  constraint user_notifications_metadata_object_check check (jsonb_typeof(metadata)='object'),
  constraint user_notifications_expiry_check check (expires_at is null or expires_at>created_at)
);

do $v41c$
declare invalid_count bigint;
begin
  select count(*) into invalid_count
  from public.user_notifications notification
  where notification.dedupe_key is not null
    and (notification.dedupe_key<>btrim(notification.dedupe_key) or char_length(btrim(notification.dedupe_key)) not between 1 and 200);
  if invalid_count>0 then
    raise exception 'V4.1C: public.user_notifications contains % invalid dedupe_key value(s)',invalid_count
      using detail='dedupe_key must already be trimmed and contain between 1 and 200 characters.',
            hint='Correct the reported legacy rows before rerunning this migration; no data was changed automatically.';
  end if;
end;
$v41c$;

alter table public.user_notifications drop constraint if exists user_notifications_dedupe_key_check;
alter table public.user_notifications add constraint user_notifications_dedupe_key_check check (
  dedupe_key is null or (dedupe_key=btrim(dedupe_key) and char_length(btrim(dedupe_key)) between 1 and 200)
);

alter table public.user_notifications drop constraint if exists user_notifications_metadata_safe_check;
alter table public.user_notifications add constraint user_notifications_metadata_safe_check check (
  jsonb_typeof(metadata)='object'
  and octet_length(metadata::text)<=8192
  and public.notification_metadata_is_safe_v41c(metadata)
);

create unique index if not exists user_notifications_recipient_dedupe_idx
  on public.user_notifications(recipient_user_id,dedupe_key) where dedupe_key is not null;
create index if not exists user_notifications_recipient_read_created_idx
  on public.user_notifications(recipient_user_id,read_at,created_at desc);
create index if not exists user_notifications_unread_idx
  on public.user_notifications(recipient_user_id,created_at desc) where read_at is null;

alter table public.user_notifications enable row level security;
revoke all on table public.user_notifications from public,anon,authenticated;
grant select on table public.user_notifications to authenticated;

do $v41c$
declare policy_record record;
begin
  for policy_record in select policyname from pg_policies where schemaname='public' and tablename='user_notifications' loop
    execute format('drop policy %I on public.user_notifications',policy_record.policyname);
  end loop;
end;
$v41c$;

create policy user_notifications_select_own_v41c on public.user_notifications
  for select to authenticated using (recipient_user_id=auth.uid() and (expires_at is null or expires_at>now()));

create or replace function public.create_user_notification_v41c(
  target_recipient_user_id uuid,
  target_actor_user_id uuid,
  target_notification_type text,
  target_title text,
  target_message text,
  target_entity_type text,
  target_entity_id uuid,
  target_dedupe_key text,
  target_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  notification_id uuid;
  safe_metadata jsonb:=coalesce(target_metadata,'{}'::jsonb);
  normalized_dedupe_key text;
begin
  if target_recipient_user_id is null then raise exception 'notification_recipient_required' using errcode='22023'; end if;
  if target_actor_user_id is not null and not exists(select 1 from auth.users actor where actor.id=target_actor_user_id) then raise exception 'notification_actor_not_found' using errcode='22023'; end if;
  if target_notification_type not in (
    'relationship_activated','relationship_revoked','workout_plan_assigned','workout_plan_updated','workout_plan_revoked',
    'nutrition_plan_assigned','nutrition_plan_updated','nutrition_plan_revoked','system'
  ) then raise exception 'invalid_notification_type' using errcode='22023'; end if;
  if target_entity_type is not null and target_entity_type not in ('relationship','workout_assignment','nutrition_assignment','system') then raise exception 'invalid_notification_entity' using errcode='22023'; end if;
  if char_length(btrim(coalesce(target_title,''))) not between 1 and 120 or char_length(btrim(coalesce(target_message,''))) not between 1 and 500 then raise exception 'invalid_notification_text' using errcode='22023'; end if;
  if target_dedupe_key is not null and char_length(btrim(target_dedupe_key)) not between 1 and 200 then raise exception 'invalid_notification_dedupe_key' using errcode='22023'; end if;
  normalized_dedupe_key:=case when target_dedupe_key is null then null else btrim(target_dedupe_key) end;
  if jsonb_typeof(safe_metadata)<>'object' or octet_length(safe_metadata::text)>8192 or not public.notification_metadata_is_safe_v41c(safe_metadata) then raise exception 'unsafe_notification_metadata' using errcode='22023'; end if;

  insert into public.user_notifications(recipient_user_id,actor_user_id,notification_type,title,message,entity_type,entity_id,dedupe_key,metadata)
  values(target_recipient_user_id,target_actor_user_id,target_notification_type,btrim(target_title),btrim(target_message),target_entity_type,target_entity_id,normalized_dedupe_key,safe_metadata)
  on conflict (recipient_user_id,dedupe_key) where dedupe_key is not null do nothing
  returning id into notification_id;

  if notification_id is null and normalized_dedupe_key is not null then
    select notification.id into notification_id from public.user_notifications notification
    where notification.recipient_user_id=target_recipient_user_id and notification.dedupe_key=normalized_dedupe_key;
  end if;
  return notification_id;
end;
$$;

create or replace function public.notify_relationship_status_v41c()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare actor_id uuid; professional_label text; student_label text; event_kind text;
begin
  if tg_op='INSERT' then
    if new.status<>'active' then return new; end if;
    event_kind:='activation';
  elsif tg_op='UPDATE' then
    if old.status is distinct from new.status and new.status='active' then
      event_kind:='activation';
    elsif old.status='active' and new.status='revoked' then
      event_kind:='revocation';
    else
      return new;
    end if;
  else
    return coalesce(new,old);
  end if;
  actor_id:=case when auth.uid() in (new.professional_user_id,new.student_user_id) then auth.uid() else null end;
  professional_label:=case new.professional_type when 'nutritionist' then 'nutricionista' else 'treinador' end;
  student_label:=case new.professional_type when 'nutritionist' then 'paciente' else 'aluno' end;

  if event_kind='activation' then
    perform public.create_user_notification_v41c(new.professional_user_id,actor_id,'relationship_activated','Nova conexão profissional','Um '||student_label||' aceitou sua conexão.','relationship',new.id,'relationship:active:'||new.id||':'||new.updated_at||':'||new.professional_user_id,jsonb_build_object('professionalType',new.professional_type));
    perform public.create_user_notification_v41c(new.student_user_id,actor_id,'relationship_activated','Conexão profissional ativa','Sua conexão com o '||professional_label||' está ativa.','relationship',new.id,'relationship:active:'||new.id||':'||new.updated_at||':'||new.student_user_id,jsonb_build_object('professionalType',new.professional_type));
  elsif event_kind='revocation' then
    perform public.create_user_notification_v41c(new.professional_user_id,actor_id,'relationship_revoked','Conexão profissional encerrada','Uma conexão profissional não está mais ativa.','relationship',new.id,'relationship:revoked:'||new.id||':'||new.updated_at||':'||new.professional_user_id,jsonb_build_object('professionalType',new.professional_type));
    perform public.create_user_notification_v41c(new.student_user_id,actor_id,'relationship_revoked','Conexão profissional encerrada','Uma conexão profissional não está mais ativa.','relationship',new.id,'relationship:revoked:'||new.id||':'||new.updated_at||':'||new.student_user_id,jsonb_build_object('professionalType',new.professional_type));
  end if;
  return new;
end;
$$;

drop trigger if exists notify_relationship_insert_v41c on public.professional_student_relationships;
create trigger notify_relationship_insert_v41c after insert on public.professional_student_relationships
for each row execute function public.notify_relationship_status_v41c();
drop trigger if exists notify_relationship_status_v41c on public.professional_student_relationships;
create trigger notify_relationship_status_v41c after update of status on public.professional_student_relationships
for each row execute function public.notify_relationship_status_v41c();

create or replace function public.notify_workout_assignment_v41c()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare relationship_record public.professional_student_relationships; event_type text;
begin
  if tg_op='INSERT' then
    if new.status<>'active' then return new; end if;
  elsif tg_op='UPDATE' then
    if not (old.status='active' and new.status='revoked') then return new; end if;
  else
    return coalesce(new,old);
  end if;
  select * into relationship_record from public.professional_student_relationships relationship where relationship.id=new.relationship_id;
  if not found then return new; end if;
  if tg_op='INSERT' then
    event_type:=case when new.assignment_version=1 then 'workout_plan_assigned' else 'workout_plan_updated' end;
    perform public.create_user_notification_v41c(
      relationship_record.student_user_id,relationship_record.professional_user_id,event_type,
      case event_type when 'workout_plan_assigned' then 'Novo plano de treino' else 'Plano de treino atualizado' end,
      'Versão '||new.assignment_version||' disponível.',
      'workout_assignment',new.id,'workout:'||event_type||':'||new.id,
      jsonb_build_object('version',new.assignment_version)
    );
  elsif tg_op='UPDATE' then
    perform public.create_user_notification_v41c(relationship_record.student_user_id,relationship_record.professional_user_id,'workout_plan_revoked','Plano de treino revogado','O plano de treino não está mais ativo.','workout_assignment',new.id,'workout:revoked:'||new.id,jsonb_build_object('version',new.assignment_version));
  end if;
  return new;
end;
$$;

drop trigger if exists notify_workout_assignment_insert_v41c on public.student_workout_assignments;
create trigger notify_workout_assignment_insert_v41c after insert on public.student_workout_assignments
for each row execute function public.notify_workout_assignment_v41c();
drop trigger if exists notify_workout_assignment_status_v41c on public.student_workout_assignments;
create trigger notify_workout_assignment_status_v41c after update of status on public.student_workout_assignments
for each row execute function public.notify_workout_assignment_v41c();

create or replace function public.list_my_notifications(target_limit integer default 30,target_before timestamptz default null)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  if target_limit is null or target_limit not between 1 and 100 then raise exception 'invalid_notification_limit' using errcode='22023'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',item.id,'notificationType',item.notification_type,'title',item.title,'message',item.message,
    'entityType',item.entity_type,'entityId',item.entity_id,'metadata',item.metadata,
    'readAt',item.read_at,'createdAt',item.created_at,'expiresAt',item.expires_at
  ) order by item.created_at desc) from (
    select notification.* from public.user_notifications notification
    where notification.recipient_user_id=auth.uid()
      and (notification.expires_at is null or notification.expires_at>now())
      and (target_before is null or notification.created_at<target_before)
    order by notification.created_at desc limit target_limit
  ) item),'[]'::jsonb);
end;
$$;

create or replace function public.get_my_unread_notification_count()
returns integer
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  return (select count(*)::integer from public.user_notifications notification where notification.recipient_user_id=auth.uid() and notification.read_at is null and (notification.expires_at is null or notification.expires_at>now()));
end;
$$;

create or replace function public.mark_my_notification_read(target_notification_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare notification_record public.user_notifications;
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  update public.user_notifications notification set read_at=coalesce(notification.read_at,now())
  where notification.id=target_notification_id and notification.recipient_user_id=auth.uid()
    and (notification.expires_at is null or notification.expires_at>now())
  returning notification.* into notification_record;
  if not found then raise exception 'notification_not_found' using errcode='P0001'; end if;
  return jsonb_build_object('id',notification_record.id,'readAt',notification_record.read_at);
end;
$$;

create or replace function public.mark_all_my_notifications_read()
returns integer
language plpgsql security definer
set search_path = ''
as $$
declare affected integer;
begin
  if auth.uid() is null then raise exception 'session_required' using errcode='42501'; end if;
  update public.user_notifications notification set read_at=now()
  where notification.recipient_user_id=auth.uid() and notification.read_at is null and (notification.expires_at is null or notification.expires_at>now());
  get diagnostics affected=row_count;
  return affected;
end;
$$;

revoke all on function public.notification_iso_date_is_valid_v41c(text),public.notification_metadata_is_safe_v41c(jsonb),public.create_user_notification_v41c(uuid,uuid,text,text,text,text,uuid,text,jsonb),public.notify_relationship_status_v41c(),public.notify_workout_assignment_v41c() from public,anon,authenticated;
revoke all on function public.list_my_notifications(integer,timestamptz),public.get_my_unread_notification_count(),public.mark_my_notification_read(uuid),public.mark_all_my_notifications_read() from public,anon,authenticated;
grant execute on function public.list_my_notifications(integer,timestamptz),public.get_my_unread_notification_count(),public.mark_my_notification_read(uuid),public.mark_all_my_notifications_read() to authenticated;

commit;
