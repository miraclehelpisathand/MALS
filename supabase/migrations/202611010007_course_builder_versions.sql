-- Draft editing and copy-on-write course versions. Existing assignments,
-- group requirements and progress keep their original course and block IDs.
begin;
alter table public.courses add column family_id uuid not null default gen_random_uuid();
alter table public.courses add column version_number integer not null default 1 check(version_number>0);
alter table public.courses add column previous_version_id uuid references public.courses(id) on delete restrict;
alter table public.course_blocks add column is_required boolean not null default true;
create unique index courses_family_version on public.courses(family_id,version_number);
create unique index courses_one_draft_per_family on public.courses(family_id) where status='draft';

create function private.lock_draft_course(target_course uuid) returns void language plpgsql security definer set search_path='' as $$
declare course_status text;
begin
  if not private.can_author() then raise exception 'Not authorised' using errcode='42501'; end if;
  select status into course_status from public.courses where id=target_course for update;
  if not found or course_status <> 'draft' then raise exception 'Course must be a draft' using errcode='22023'; end if;
end; $$;
revoke all on function private.lock_draft_course(uuid) from public,anon,authenticated;

create function public.update_draft_course(target_course uuid, new_title text, new_description text) returns void language plpgsql security definer set search_path='' as $$
begin
  perform private.lock_draft_course(target_course);
  update public.courses set title=new_title,description=coalesce(new_description,'') where id=target_course;
end; $$;
create function public.update_draft_module(target_module uuid, new_title text) returns void language plpgsql security definer set search_path='' as $$
declare course_id uuid;
begin
  select m.course_id into course_id from public.course_modules m where m.id=target_module;
  perform private.lock_draft_course(course_id);
  update public.course_modules set title=new_title where id=target_module;
  if not found then raise exception 'Module not found' using errcode='22023'; end if;
end; $$;
create function public.add_draft_block(target_module uuid, new_title text, new_body text, required boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
  if required is null then raise exception 'Choose whether the block is required' using errcode='22023'; end if;
  result:=public.add_course_block(target_module,new_title,new_body);
  update public.course_blocks set is_required=required where id=result;
  return result;
end; $$;
create function public.update_draft_block(target_block uuid, new_title text, new_body text, required boolean) returns void language plpgsql security definer set search_path='' as $$
declare course_id uuid;
begin
  select m.course_id into course_id from public.course_blocks b join public.course_modules m on m.id=b.module_id where b.id=target_block;
  perform private.lock_draft_course(course_id);
  if required is null then raise exception 'Choose whether the block is required' using errcode='22023'; end if;
  update public.course_blocks set title=new_title,body=coalesce(new_body,''),is_required=required where id=target_block;
  if not found then raise exception 'Block not found' using errcode='22023'; end if;
end; $$;
create function public.delete_draft_block(target_block uuid) returns void language plpgsql security definer set search_path='' as $$
declare course_id uuid;
begin
  select m.course_id into course_id from public.course_blocks b join public.course_modules m on m.id=b.module_id where b.id=target_block;
  perform private.lock_draft_course(course_id);
  delete from public.course_blocks where id=target_block;
  if not found then raise exception 'Block not found' using errcode='22023'; end if;
end; $$;
create function public.delete_draft_module(target_module uuid) returns void language plpgsql security definer set search_path='' as $$
declare course_id uuid;
begin
  select m.course_id into course_id from public.course_modules m where m.id=target_module;
  perform private.lock_draft_course(course_id);
  delete from public.course_blocks where module_id=target_module;
  delete from public.course_modules where id=target_module;
  if not found then raise exception 'Module not found' using errcode='22023'; end if;
end; $$;
create function public.delete_draft_course(target_course uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  perform private.lock_draft_course(target_course);
  delete from public.course_blocks where module_id in(select id from public.course_modules where course_id=target_course);
  delete from public.course_modules where course_id=target_course;
  delete from public.courses where id=target_course;
end; $$;

-- Serialise moves on the parent course. Use a spare positive position so the
-- existing immediate unique constraints remain valid during the swap.
create function public.move_draft_module(target_module uuid, direction integer) returns void language plpgsql security definer set search_path='' as $$
declare parent_course uuid; current_pos integer; other_id uuid; other_pos integer; spare integer;
begin
  select m.course_id into parent_course from public.course_modules m where m.id=target_module;
  perform private.lock_draft_course(parent_course);
  if direction is null or direction not in (-1,1) then raise exception 'Invalid direction' using errcode='22023'; end if;
  select position into current_pos from public.course_modules where id=target_module and course_modules.course_id=parent_course;
  if not found then raise exception 'Module not found' using errcode='22023'; end if;
  if direction=-1 then select id,position into other_id,other_pos from public.course_modules where course_modules.course_id=parent_course and position<current_pos order by position desc limit 1;
  else select id,position into other_id,other_pos from public.course_modules where course_modules.course_id=parent_course and position>current_pos order by position limit 1; end if;
  if other_id is null then return; end if;
  select max(position)+1 into spare from public.course_modules where course_modules.course_id=parent_course;
  update public.course_modules set position=spare where id=target_module;
  update public.course_modules set position=current_pos where id=other_id;
  update public.course_modules set position=other_pos where id=target_module;
end; $$;
create function public.move_draft_block(target_block uuid, direction integer) returns void language plpgsql security definer set search_path='' as $$
declare parent_course uuid; parent_module uuid; current_pos integer; other_id uuid; other_pos integer; spare integer;
begin
  select m.course_id,b.module_id into parent_course,parent_module from public.course_blocks b join public.course_modules m on m.id=b.module_id where b.id=target_block;
  perform private.lock_draft_course(parent_course);
  if direction is null or direction not in (-1,1) then raise exception 'Invalid direction' using errcode='22023'; end if;
  select position into current_pos from public.course_blocks where id=target_block and module_id=parent_module;
  if not found then raise exception 'Block not found' using errcode='22023'; end if;
  if direction=-1 then select id,position into other_id,other_pos from public.course_blocks where module_id=parent_module and position<current_pos order by position desc limit 1;
  else select id,position into other_id,other_pos from public.course_blocks where module_id=parent_module and position>current_pos order by position limit 1; end if;
  if other_id is null then return; end if;
  select max(position)+1 into spare from public.course_blocks where module_id=parent_module;
  update public.course_blocks set position=spare where id=target_block;
  update public.course_blocks set position=current_pos where id=other_id;
  update public.course_blocks set position=other_pos where id=target_block;
end; $$;

create or replace function public.publish_course(target_course uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  perform private.lock_draft_course(target_course);
  if not exists(select 1 from public.course_modules m join public.course_blocks b on b.module_id=m.id where m.course_id=target_course and b.is_required) then raise exception 'Add at least one required content block before publishing' using errcode='22023'; end if;
  update public.courses set status='published',published_at=now() where id=target_course;
end; $$;
create function public.create_course_version(target_course uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare source public.courses%rowtype; new_id uuid; new_module uuid; item record;
begin
  if not private.can_author() then raise exception 'Not authorised' using errcode='42501'; end if;
  select * into source from public.courses where id=target_course for update;
  if not found or source.status <> 'published' then raise exception 'Select a published course version' using errcode='22023'; end if;
  if exists(select 1 from public.courses where family_id=source.family_id and version_number>source.version_number) then raise exception 'Create a draft from the latest version; a newer version already exists' using errcode='22023'; end if;
  insert into public.courses(title,description,family_id,version_number,previous_version_id) values(source.title,source.description,source.family_id,source.version_number+1,source.id) returning id into new_id;
  for item in select * from public.course_modules where course_id=source.id order by position loop
    insert into public.course_modules(course_id,title,position) values(new_id,item.title,item.position) returning id into new_module;
    insert into public.course_blocks(module_id,title,body,position,is_required) select new_module,title,body,position,is_required from public.course_blocks where module_id=item.id order by position;
  end loop;
  return new_id;
end; $$;

-- The catalogue exposes version and family metadata, never draft content.
drop function public.list_published_course_catalog();
create function public.list_published_course_catalog() returns table(id uuid,title text,description text,family_id uuid,version_number integer)
language sql stable security definer set search_path='' as $$
  select c.id,c.title,c.description,c.family_id,c.version_number from public.courses c
  where c.status='published' and (private.is_admin() or exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.role='leader'));
$$;
revoke all on function public.list_published_course_catalog() from public,anon;
grant execute on function public.list_published_course_catalog() to authenticated;
revoke all on function public.update_draft_course(uuid,text,text),public.update_draft_module(uuid,text),public.add_draft_block(uuid,text,text,boolean),public.update_draft_block(uuid,text,text,boolean),public.delete_draft_block(uuid),public.delete_draft_module(uuid),public.delete_draft_course(uuid),public.move_draft_module(uuid,integer),public.move_draft_block(uuid,integer),public.create_course_version(uuid) from public,anon;
grant execute on function public.update_draft_course(uuid,text,text),public.update_draft_module(uuid,text),public.add_draft_block(uuid,text,text,boolean),public.update_draft_block(uuid,text,text,boolean),public.delete_draft_block(uuid),public.delete_draft_module(uuid),public.delete_draft_course(uuid),public.move_draft_module(uuid,integer),public.move_draft_block(uuid,integer),public.create_course_version(uuid) to authenticated;
commit;
