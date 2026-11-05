-- Local development work: certificate records and revocation/reissue controls.
-- Do not deploy until the complete certificate and recurring-cycle workflow is tested.
begin;
create table public.certificate_templates (
 id uuid primary key default gen_random_uuid(),
 family_id uuid not null,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 artwork_png bytea not null check(octet_length(artwork_png) between 45 and 3145728),
 page_width numeric not null check(page_width between 100 and 3000),
 page_height numeric not null check(page_height between 100 and 3000),
 sha256 text not null
);
create table public.course_certificate_settings (
 course_id uuid primary key references public.courses(id) on delete cascade,
 template_id uuid not null references public.certificate_templates(id) on delete restrict,
 validity_months integer check(validity_months between 1 and 600),
 refresher_family_id uuid,
 lead_days integer check(lead_days between 0 and 3650),
 layout jsonb not null,
 check((validity_months is null and refresher_family_id is null and lead_days is null) or (validity_months is not null and refresher_family_id is not null and lead_days is not null))
);
create table public.certificate_date_verifications (
 completion_event_id uuid primary key references public.course_completion_events(id) on delete restrict,
 verified_completion_date date not null,
 reason text not null check(length(btrim(reason)) between 10 and 1000),
 verified_by uuid not null references public.profiles(id) on delete restrict,
 verified_at timestamptz not null default now()
);
create table public.certificates (
 id uuid primary key default gen_random_uuid(),
 assignment_id uuid not null references public.course_assignments(id) on delete restrict,
 completion_event_id uuid not null unique references public.course_completion_events(id) on delete restrict,
 user_id uuid not null references public.profiles(id) on delete restrict,
 award_course_id uuid not null references public.courses(id) on delete restrict,
 policy_course_id uuid not null references public.courses(id) on delete restrict,
 template_id uuid not null references public.certificate_templates(id) on delete restrict,
 trainee_name text not null,
 course_title text not null,
 course_version integer not null,
 completion_date date not null,
 expiry_date date,
 validity_months integer,
 refresher_family_id uuid,
 lead_days integer,
 layout jsonb not null,
 issued_at timestamptz not null default now(),
 issued_by uuid references public.profiles(id) on delete restrict,
 status text not null default 'active' check(status in ('active','revoked','superseded')),
 revoked_at timestamptz,
 revocation_reason text
);
create index certificates_user on public.certificates(user_id,issued_at,id);
create table public.certificate_reissue_requests (
 completion_event_id uuid primary key references public.course_completion_events(id) on delete restrict,
 assignment_id uuid not null references public.course_assignments(id) on delete restrict,
 user_id uuid not null references public.profiles(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','approved','cancelled')),
 requested_at timestamptz not null default now(),
 reviewed_by uuid references public.profiles(id) on delete restrict,
 reviewed_at timestamptz
);
alter table public.certificate_templates enable row level security;
alter table public.course_certificate_settings enable row level security;
alter table public.certificate_date_verifications enable row level security;
alter table public.certificates enable row level security;
alter table public.certificate_reissue_requests enable row level security;
revoke all on public.certificate_templates,public.course_certificate_settings,public.certificate_date_verifications,public.certificates,public.certificate_reissue_requests from public,anon,authenticated;
grant select on public.course_certificate_settings,public.certificates,public.certificate_reissue_requests,public.certificate_date_verifications to authenticated;
create policy certificate_verification_read on public.certificate_date_verifications for select to authenticated using (private.is_admin());
create policy certificate_settings_read on public.course_certificate_settings for select to authenticated using (private.can_author());
create policy certificate_read on public.certificates for select to authenticated using (user_id=auth.uid() or private.is_admin() or private.can_view_profile(user_id));
create policy certificate_requests_read on public.certificate_reissue_requests for select to authenticated using (user_id=auth.uid() or private.can_review_assessment(user_id));

create function private.validate_certificate_layout(doc jsonb) returns void language plpgsql security definer set search_path='' as $$
declare k text; item jsonb;
begin
 if jsonb_typeof(doc) is distinct from 'object' or length(doc::text)>2000 or (select count(*) from jsonb_object_keys(doc))<>5 then raise exception 'Position all five certificate fields' using errcode='22023';end if;
 foreach k in array array['name','course','completion_date','expiry_date','certificate_id'] loop
  item:=doc->k;
  if jsonb_typeof(item) is distinct from 'object' or (select count(*) from jsonb_object_keys(item))<>3 or jsonb_typeof(item->'x') is distinct from 'number' or jsonb_typeof(item->'y') is distinct from 'number' or jsonb_typeof(item->'size') is distinct from 'number' or (item->>'x')::numeric not between 0 and 100 or (item->>'y')::numeric not between 0 and 100 or (item->>'size')::numeric not between 6 and 72 then raise exception 'Invalid certificate field position or size' using errcode='22023';end if;
 end loop;
end; $$;
revoke all on function private.validate_certificate_layout(jsonb) from public,anon,authenticated;
-- Store only non-interactive PNG artwork, never the uploaded PDF. PNG chunk
-- structure and dimensions are bounded server-side. Browser image decoding
-- can still fail and must not be treated as a guarantee against decoder bugs.
create function private.png_u32(data bytea,off integer) returns bigint language sql immutable strict set search_path='' as $$
 select (get_byte(data,off)::bigint<<24)+(get_byte(data,off+1)::bigint<<16)+(get_byte(data,off+2)::bigint<<8)+get_byte(data,off+3)::bigint;
$$;
create function private.validate_certificate_png(data bytea, page_width numeric,page_height numeric) returns void language plpgsql security definer set search_path='' as $$
declare size integer:=octet_length(data); pos integer:=8; n bigint; kind bytea; width_px bigint; height_px bigint; seen_header boolean:=false;seen_data boolean:=false;seen_end boolean:=false; chunks integer:=0;
begin
 if data is null or size not between 45 and 3145728 or substring(data from 1 for 8)<>decode('89504e470d0a1a0a','hex') or page_width is null or page_height is null or page_width not between 100 and 3000 or page_height not between 100 and 3000 then raise exception 'Invalid certificate image' using errcode='22023';end if;
 while pos+12<=size loop
  chunks:=chunks+1;if chunks>1024 then raise exception 'Invalid certificate image chunks' using errcode='22023';end if;
  n:=private.png_u32(data,pos);kind:=substring(data from pos+5 for 4);
  if n>3145728 or pos+12+n>size then raise exception 'Invalid certificate image chunk length' using errcode='22023';end if;
  if kind=decode('49484452','hex') then
   if seen_header or pos<>8 or n<>13 then raise exception 'Invalid certificate image header' using errcode='22023';end if;
   width_px:=private.png_u32(data,pos+8);height_px:=private.png_u32(data,pos+12);
   if width_px not between 1 and 3600 or height_px not between 1 and 3600 or width_px*height_px>12000000 or get_byte(data,pos+16)<>8 or get_byte(data,pos+17) not in (2,6) or get_byte(data,pos+18)<>0 or get_byte(data,pos+19)<>0 or get_byte(data,pos+20)<>0 or abs(width_px::numeric/height_px-page_width/page_height)>0.02 then raise exception 'Unsupported certificate image dimensions or format' using errcode='22023';end if;
   seen_header:=true;
  elsif kind=decode('49444154','hex') then
   if not seen_header or seen_end or n=0 then raise exception 'Invalid certificate image data' using errcode='22023';end if;seen_data:=true;
  elsif kind=decode('49454e44','hex') then
   if not seen_header or not seen_data or n<>0 or pos+12<>size then raise exception 'Invalid certificate image ending' using errcode='22023';end if;seen_end:=true;
  else raise exception 'Unsupported certificate image chunk' using errcode='22023';end if;
  pos:=pos+12+n::integer;
  exit when seen_end;
 end loop;
 if not seen_end or pos<>size then raise exception 'Incomplete certificate image' using errcode='22023';end if;
end; $$;
revoke all on function private.png_u32(bytea,integer),private.validate_certificate_png(bytea,numeric,numeric) from public,anon,authenticated;
create function public.add_certificate_template(target_course uuid, png_base64 text,page_width numeric,page_height numeric) returns uuid language plpgsql security definer set search_path='' as $$
declare family uuid; raw bytea; result uuid;
begin
 perform private.lock_draft_course(target_course);
 if png_base64 is null or length(png_base64)>4194304 then raise exception 'Certificate image exceeds 3 MB' using errcode='22023';end if;
 begin raw:=decode(png_base64,'base64');exception when others then raise exception 'Invalid certificate image data' using errcode='22023';end;
 perform private.validate_certificate_png(raw,page_width,page_height);
 select family_id into family from public.courses where id=target_course;
 insert into public.certificate_templates(family_id,created_by,artwork_png,page_width,page_height,sha256) values(family,auth.uid(),raw,page_width,page_height,encode(sha256(raw),'hex')) returning id into result;
 return result;
end; $$;
create function public.save_certificate_settings(target_course uuid, target_template uuid, months integer, refresher_family uuid, days_before integer, positions jsonb) returns void language plpgsql security definer set search_path='' as $$
declare family uuid;
begin
 perform private.lock_draft_course(target_course);
 select family_id into family from public.courses where id=target_course;
 if not exists(select 1 from public.certificate_templates where id=target_template and family_id=family) then raise exception 'Choose a template from this course family' using errcode='22023';end if;
 if months is null then
  if refresher_family is not null or days_before is not null then raise exception 'Non-expiring certificates cannot schedule refreshers' using errcode='22023';end if;
 elsif months not between 1 and 600 or days_before is null or days_before not between 0 and 3650 or refresher_family is null or (refresher_family<>family and not exists(select 1 from public.courses where family_id=refresher_family and status='published')) then raise exception 'Choose validity and a published refresher course' using errcode='22023';end if;
 perform private.validate_certificate_layout(positions);
 insert into public.course_certificate_settings(course_id,template_id,validity_months,refresher_family_id,lead_days,layout) values(target_course,target_template,months,refresher_family,days_before,positions)
 on conflict(course_id) do update set template_id=excluded.template_id,validity_months=excluded.validity_months,refresher_family_id=excluded.refresher_family_id,lead_days=excluded.lead_days,layout=excluded.layout;
end; $$;
create function public.remove_certificate_settings(target_course uuid) returns void language plpgsql security definer set search_path='' as $$
begin perform private.lock_draft_course(target_course);delete from public.course_certificate_settings where course_id=target_course;end; $$;
create function public.get_certificate_template(target_template uuid, certificate_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Not authorised' using errcode='42501';end if;
 if not (private.can_author() and exists(select 1 from public.certificate_templates where id=target_template)) and not exists(select 1 from public.certificates c where c.id=certificate_id and c.template_id=target_template and (c.user_id=auth.uid() or private.is_admin() or private.can_view_profile(c.user_id))) then raise exception 'Not authorised' using errcode='42501';end if;
 select jsonb_build_object('png_base64',encode(artwork_png,'base64'),'width',page_width,'height',page_height) into result from public.certificate_templates where id=target_template;
 return result;
end; $$;

create function private.issue_certificate(target_event uuid, completion_day date, approver uuid default null, policy_course uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.course_completion_events%rowtype; a public.course_assignments%rowtype; cfg public.course_certificate_settings%rowtype; learner text; course public.courses%rowtype; result uuid;
begin
 select * into e from public.course_completion_events where id=target_event and event_type='completed';
 if not found then raise exception 'Completion event not found' using errcode='22023';end if;
 select * into a from public.course_assignments where id=e.assignment_id;
 select * into cfg from public.course_certificate_settings where course_id=coalesce(policy_course,a.course_id);
 if not found then return null;end if;
 if not exists(select 1 from public.courses original join public.courses policy on policy.family_id=original.family_id where original.id=a.course_id and policy.id=cfg.course_id and policy.status='published') then raise exception 'Certificate settings must be from a published version of the same course' using errcode='22023';end if;
 select display_name into learner from public.profiles where id=a.user_id;select * into course from public.courses where id=a.course_id;
 insert into public.certificates(assignment_id,completion_event_id,user_id,award_course_id,policy_course_id,template_id,trainee_name,course_title,course_version,completion_date,expiry_date,validity_months,refresher_family_id,lead_days,layout,issued_by)
 values(a.id,e.id,a.user_id,a.course_id,cfg.course_id,cfg.template_id,learner,course.title,course.version_number,completion_day,case when cfg.validity_months is null then null else (completion_day+make_interval(months=>cfg.validity_months))::date end,cfg.validity_months,cfg.refresher_family_id,cfg.lead_days,cfg.layout,approver)
 on conflict(completion_event_id) do nothing returning id into result;
 return result;
end; $$;
revoke all on function private.issue_certificate(uuid,date,uuid,uuid) from public,anon,authenticated;
create function private.certificate_completion_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.course_assignments%rowtype;
begin
 select * into a from public.course_assignments where id=new.assignment_id;
 if new.event_type='reopened' then
  update public.certificates set status='revoked',revoked_at=new.occurred_at,revocation_reason='Course reopened' where assignment_id=a.id and status='active';
  update public.certificate_reissue_requests set status='cancelled' where assignment_id=a.id and status='pending';
 elsif new.source='activity' then
  if exists(select 1 from public.certificates where assignment_id=a.id and status='revoked') then
    insert into public.certificate_reissue_requests(completion_event_id,assignment_id,user_id) values(new.id,a.id,a.user_id) on conflict do nothing;
  elsif exists(select 1 from public.course_certificate_settings where course_id=a.course_id) then
    perform private.issue_certificate(new.id,(new.occurred_at at time zone 'Pacific/Auckland')::date,null);
  end if;
 end if;
 return new;
end; $$;
revoke all on function private.certificate_completion_trigger() from public,anon,authenticated;
create trigger completion_certificate after insert on public.course_completion_events for each row execute function private.certificate_completion_trigger();
create function public.approve_certificate_reissue(target_event uuid) returns void language plpgsql security definer set search_path='' as $$
declare req public.certificate_reissue_requests%rowtype; e public.course_completion_events%rowtype; old_policy uuid;
begin
 select * into req from public.certificate_reissue_requests where completion_event_id=target_event;
 if not found or not private.can_review_assessment(req.user_id) then raise exception 'Not authorised' using errcode='42501';end if;
 perform 1 from public.course_assignments where id=req.assignment_id for update;
 select * into req from public.certificate_reissue_requests where completion_event_id=target_event for update;
 if req.status<>'pending' or not exists(select 1 from public.course_completion_state where assignment_id=req.assignment_id and completed_at is not null) or target_event<>(select id from public.course_completion_events where assignment_id=req.assignment_id and event_type='completed' order by event_sequence desc limit 1) then raise exception 'Reissue is no longer eligible' using errcode='22023';end if;
 select * into e from public.course_completion_events where id=target_event;
 select c.policy_course_id into old_policy from public.certificates c join public.course_completion_events ev on ev.id=c.completion_event_id where c.assignment_id=req.assignment_id and c.status='revoked' order by ev.event_sequence desc limit 1;
 if old_policy is null then raise exception 'Previous certificate not found' using errcode='22023';end if;
 perform private.issue_certificate(target_event,(e.occurred_at at time zone 'Pacific/Auckland')::date,auth.uid(),old_policy);
 update public.certificate_reissue_requests set status='approved',reviewed_by=auth.uid(),reviewed_at=now() where completion_event_id=target_event;
end; $$;
create function public.verify_historical_completion(target_event uuid, verified_date date, reason text, policy_course uuid) returns void language plpgsql security definer set search_path='' as $$
declare e public.course_completion_events%rowtype;
begin
 if not private.is_admin() then raise exception 'Administrator required' using errcode='42501';end if;
 select * into e from public.course_completion_events where id=target_event and event_type='completed' and source='initial_recognition';
 if not found or verified_date is null or verified_date>(now() at time zone 'Pacific/Auckland')::date or length(btrim(coalesce(reason,''))) not between 10 and 1000 then raise exception 'Enter a verified date and reason' using errcode='22023';end if;
 perform 1 from public.course_assignments where id=e.assignment_id for update;
 if not exists(select 1 from public.course_completion_state where assignment_id=e.assignment_id and completed_at is not null) or target_event<>(select id from public.course_completion_events where assignment_id=e.assignment_id and event_type='completed' order by event_sequence desc limit 1) then raise exception 'Completion is no longer current' using errcode='22023';end if;
 insert into public.certificate_date_verifications(completion_event_id,verified_completion_date,reason,verified_by) values(target_event,verified_date,reason,auth.uid());
 if not exists(select 1 from public.course_certificate_settings s join public.courses policy on policy.id=s.course_id join public.course_assignments a on a.id=e.assignment_id join public.courses original on original.id=a.course_id where s.course_id=policy_course and policy.status='published' and policy.family_id=original.family_id) then raise exception 'Select published certificate settings from the same course family' using errcode='22023';end if;
 perform private.issue_certificate(target_event,verified_date,auth.uid(),policy_course);
end; $$;
-- A new draft shares the immutable template but gets independently editable settings.
create or replace function public.create_course_version(target_course uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare source public.courses%rowtype; new_id uuid; new_module uuid; new_block uuid; item record; block record;
begin
  if not private.can_author() then raise exception 'Not authorised' using errcode='42501'; end if;
  select * into source from public.courses where id=target_course for update;
  if not found or source.status <> 'published' then raise exception 'Select a published course version' using errcode='22023'; end if;
  if exists(select 1 from public.courses where family_id=source.family_id and version_number>source.version_number) then raise exception 'Create a draft from the latest version; a newer version already exists' using errcode='22023'; end if;
  insert into public.courses(title,description,family_id,version_number,previous_version_id) values(source.title,source.description,source.family_id,source.version_number+1,source.id) returning id into new_id;
  for item in select * from public.course_modules where course_id=source.id order by position loop
    insert into public.course_modules(course_id,title,position) values(new_id,item.title,item.position) returning id into new_module;
    for block in select * from public.course_blocks where module_id=item.id order by position loop
      insert into public.course_blocks(module_id,title,body,position,is_required,block_type) values(new_module,block.title,block.body,block.position,block.is_required,block.block_type) returning id into new_block;
      insert into public.assessment_definitions(block_id,definition) select new_block,definition from public.assessment_definitions where block_id=block.id;
    end loop;
  end loop;
  insert into public.course_certificate_settings(course_id,template_id,validity_months,refresher_family_id,lead_days,layout) select new_id,template_id,validity_months,refresher_family_id,lead_days,layout from public.course_certificate_settings where course_id=source.id;
  return new_id;
end; $$;
revoke all on function public.add_certificate_template(uuid,text,numeric,numeric),public.save_certificate_settings(uuid,uuid,integer,uuid,integer,jsonb),public.remove_certificate_settings(uuid),public.get_certificate_template(uuid,uuid),public.approve_certificate_reissue(uuid),public.verify_historical_completion(uuid,date,text,uuid) from public,anon;
grant execute on function public.add_certificate_template(uuid,text,numeric,numeric),public.save_certificate_settings(uuid,uuid,integer,uuid,integer,jsonb),public.remove_certificate_settings(uuid),public.get_certificate_template(uuid,uuid),public.approve_certificate_reissue(uuid),public.verify_historical_completion(uuid,date,text,uuid) to authenticated;
commit;
