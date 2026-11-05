-- Development milestone: plain-text course building and dated assignments.
-- Published courses are immutable until proper versioning is introduced.
begin;
create table public.courses (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(btrim(title)) between 1 and 120),
  description text not null default '' check (length(description) <= 1000),
  status text not null default 'draft' check (status in ('draft','published')),
  created_at timestamptz not null default now(),
  published_at timestamptz
);
create table public.course_modules (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete restrict,
  title text not null check (length(btrim(title)) between 1 and 120),
  position integer not null check (position >= 0),
  unique (course_id, position)
);
create table public.course_blocks (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.course_modules(id) on delete restrict,
  title text not null check (length(btrim(title)) between 1 and 120),
  body text not null default '' check (length(body) <= 12000),
  position integer not null check (position >= 0),
  unique (module_id, position)
);
create table public.course_assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  target_date date not null,
  individually_assigned boolean not null default false,
  created_at timestamptz not null default now(),
  unique (course_id,user_id)
);
create table public.group_course_requirements (
  group_id uuid not null references public.groups(id) on delete restrict,
  course_id uuid not null references public.courses(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (group_id,course_id)
);
create table public.assignment_group_sources (
  assignment_id uuid not null references public.course_assignments(id) on delete restrict,
  group_id uuid not null references public.groups(id) on delete restrict,
  primary key (assignment_id,group_id)
);
create function private.can_author() returns boolean language sql stable security definer set search_path='' as $$
  select private.is_admin() or exists (select 1 from public.user_roles r where r.user_id=auth.uid() and r.role='author');
$$;
-- Group-only access is active only while at least one source membership is
-- active. Archiving/deleting membership preserves records but revokes access
-- unless another active group or individual assignment still grants it.
create function private.assignment_is_active(target_assignment uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists (select 1 from public.course_assignments a where a.id=target_assignment and
    (a.individually_assigned or exists (select 1 from public.assignment_group_sources s join public.group_memberships m on m.group_id=s.group_id and m.user_id=a.user_id and m.status='active' where s.assignment_id=a.id)));
$$;
create function private.can_read_course(target_course uuid) returns boolean language sql stable security definer set search_path='' as $$
  select private.can_author() or exists (select 1 from public.course_assignments a where a.course_id=target_course and ((a.user_id=auth.uid() and private.assignment_is_active(a.id)) or (a.user_id<>auth.uid() and private.can_view_profile(a.user_id)))) or exists (select 1 from public.group_course_requirements g where g.course_id=target_course and private.leads_group(g.group_id));
$$;
revoke all on function private.can_author(), private.can_read_course(uuid), private.assignment_is_active(uuid) from public;
grant execute on function private.can_author(), private.can_read_course(uuid), private.assignment_is_active(uuid) to authenticated;
alter table public.courses enable row level security;
alter table public.course_modules enable row level security;
alter table public.course_blocks enable row level security;
alter table public.course_assignments enable row level security;
alter table public.group_course_requirements enable row level security;
alter table public.assignment_group_sources enable row level security;
revoke all on public.courses,public.course_modules,public.course_blocks,public.course_assignments,public.group_course_requirements,public.assignment_group_sources from public,anon,authenticated;
grant select on public.courses,public.course_modules,public.course_blocks,public.course_assignments,public.group_course_requirements,public.assignment_group_sources to authenticated;
create policy courses_read on public.courses for select to authenticated using (private.can_read_course(id));
create policy modules_read on public.course_modules for select to authenticated using (private.can_read_course(course_id));
create policy blocks_read on public.course_blocks for select to authenticated using (exists (select 1 from public.course_modules m where m.id=module_id and private.can_read_course(m.course_id)));
create policy assignments_read on public.course_assignments for select to authenticated using (private.is_admin() or (user_id=auth.uid() and private.assignment_is_active(id)) or (user_id<>auth.uid() and private.can_view_profile(user_id)));
create policy group_courses_read on public.group_course_requirements for select to authenticated using (private.is_admin() or private.leads_group(group_id) or exists (select 1 from public.group_memberships m where m.group_id=group_course_requirements.group_id and m.user_id=auth.uid() and m.status='active'));
create policy sources_read on public.assignment_group_sources for select to authenticated using (private.is_admin() or private.leads_group(group_id) or exists (select 1 from public.course_assignments a where a.id=assignment_id and a.user_id=auth.uid()));

create function public.create_course(title text, description text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
  if not private.can_author() then raise exception 'Not authorised' using errcode='42501'; end if;
  insert into public.courses(title,description) values (title,coalesce(description,'')) returning id into result;
  return result;
end; $$;
create function public.add_course_module(target_course uuid, title text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; course_status text;
begin
  if not private.can_author() then raise exception 'Not authorised' using errcode='42501'; end if;
  select status into course_status from public.courses where id=target_course for update;
  if not found or course_status <> 'draft' then raise exception 'Course must be a draft' using errcode='22023'; end if;
  insert into public.course_modules(course_id,title,position) values(target_course,title,(select coalesce(max(position)+1,0) from public.course_modules where course_id=target_course)) returning id into result;
  return result;
end; $$;
create function public.add_course_block(target_module uuid, title text, body text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; course_status text;
begin
  if not private.can_author() then raise exception 'Not authorised' using errcode='42501'; end if;
  select c.status into course_status from public.courses c join public.course_modules m on m.course_id=c.id where m.id=target_module for update of c;
  if not found or course_status <> 'draft' then raise exception 'Course must be a draft' using errcode='22023'; end if;
  insert into public.course_blocks(module_id,title,body,position) values(target_module,title,coalesce(body,''),(select coalesce(max(position)+1,0) from public.course_blocks where module_id=target_module)) returning id into result;
  return result;
end; $$;
create function public.publish_course(target_course uuid) returns void language plpgsql security definer set search_path='' as $$
declare course_status text;
begin
  if not private.can_author() then raise exception 'Not authorised' using errcode='42501'; end if;
  select status into course_status from public.courses where id=target_course for update;
  if not found or course_status <> 'draft' then raise exception 'Course must be a draft' using errcode='22023'; end if;
  if not exists(select 1 from public.course_modules m join public.course_blocks b on b.module_id=m.id where m.course_id=target_course) then raise exception 'Add at least one content block before publishing' using errcode='22023'; end if;
  update public.courses set status='published',published_at=now() where id=target_course;
end; $$;

create function public.assign_course_individual(target_course uuid, target_user uuid, due_date date) returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not (private.is_admin() or exists(select 1 from public.group_memberships m where m.user_id=target_user and private.leads_group(m.group_id))) then raise exception 'Not authorised' using errcode='42501'; end if;
  if due_date is null or not exists(select 1 from public.courses where id=target_course and status='published') or not exists(select 1 from public.user_roles where user_id=target_user and role='trainee') then raise exception 'A published course, trainee and target date are required' using errcode='22023'; end if;
  insert into public.course_assignments(course_id,user_id,target_date,individually_assigned) values(target_course,target_user,due_date,true) on conflict(course_id,user_id) do update set individually_assigned=true;
end; $$;
create function public.assign_course_group(target_course uuid, target_group uuid, due_date date) returns void language plpgsql security definer set search_path='' as $$
declare member record; assignment uuid;
begin
  if auth.uid() is null or not (private.is_admin() or private.leads_group(target_group)) then raise exception 'Not authorised' using errcode='42501'; end if;
  if due_date is null or not exists(select 1 from public.courses where id=target_course and status='published') then raise exception 'A published course and target date are required' using errcode='22023'; end if;
  perform 1 from public.groups where id=target_group for update;
  if not found then raise exception 'Group not found' using errcode='22023'; end if;
  insert into public.group_course_requirements(group_id,course_id) values(target_group,target_course);
  for member in select user_id from public.group_memberships where group_id=target_group and status='active' loop
    insert into public.course_assignments(course_id,user_id,target_date) values(target_course,member.user_id,due_date) on conflict(course_id,user_id) do nothing;
    select id into assignment from public.course_assignments where course_id=target_course and user_id=member.user_id;
    insert into public.assignment_group_sources values(assignment,target_group) on conflict do nothing;
  end loop;
end; $$;

-- Replace the previous 3-argument entry point with a dated wrapper. The legacy
-- implementation remains private to the owner so callers cannot bypass dates.
alter function public.manage_group_membership(uuid,uuid,text) rename to manage_group_membership_legacy;
revoke all on function public.manage_group_membership_legacy(uuid,uuid,text) from public,anon,authenticated;
create function public.manage_group_membership(target_group uuid, target_user uuid, action text, course_dates jsonb default '{}'::jsonb) returns void language plpgsql security definer set search_path='' as $$
declare requirement record; selected_date date; assignment uuid; date_text text;
begin
  if auth.uid() is null or not (private.is_admin() or private.leads_group(target_group)) then raise exception 'Not authorised' using errcode='42501'; end if;
  perform 1 from public.groups where id=target_group for update;
  if not found then raise exception 'Group not found' using errcode='22023'; end if;
  if action in ('add','restore') then
    if course_dates is null or jsonb_typeof(course_dates) <> 'object' then raise exception 'Separate target dates are required' using errcode='22023'; end if;
    for requirement in select course_id from public.group_course_requirements where group_id=target_group loop
      date_text := course_dates ->> requirement.course_id::text;
      if date_text is null or date_text !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'A target date is required for each group course' using errcode='22023'; end if;
      selected_date := date_text::date;
      if to_char(selected_date,'YYYY-MM-DD') <> date_text then raise exception 'Invalid target date' using errcode='22023'; end if;
    end loop;
  end if;
  perform public.manage_group_membership_legacy(target_group,target_user,action);
  if action in ('add','restore') then
    for requirement in select course_id from public.group_course_requirements where group_id=target_group loop
      selected_date := (course_dates ->> requirement.course_id::text)::date;
      insert into public.course_assignments(course_id,user_id,target_date) values(requirement.course_id,target_user,selected_date) on conflict(course_id,user_id) do nothing;
      select id into assignment from public.course_assignments where course_id=requirement.course_id and user_id=target_user;
      insert into public.assignment_group_sources values(assignment,target_group) on conflict do nothing;
    end loop;
  end if;
end; $$;
revoke all on function public.create_course(text,text),public.add_course_module(uuid,text),public.add_course_block(uuid,text,text),public.publish_course(uuid),public.assign_course_individual(uuid,uuid,date),public.assign_course_group(uuid,uuid,date),public.manage_group_membership(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.create_course(text,text),public.add_course_module(uuid,text),public.add_course_block(uuid,text,text),public.publish_course(uuid),public.assign_course_individual(uuid,uuid,date),public.assign_course_group(uuid,uuid,date),public.manage_group_membership(uuid,uuid,text,jsonb) to authenticated;
commit;
