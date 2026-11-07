-- Assessment definitions belong to an immutable course version. Answer keys
-- are never available through table reads; attempts are append-only to clients.
begin;
alter table public.course_blocks add column block_type text not null default 'text' check(block_type in ('text','quiz','practical'));
create table public.assessment_definitions (
  block_id uuid primary key references public.course_blocks(id) on delete cascade,
  definition jsonb not null
);
create table public.assessment_attempts (
  id uuid primary key default gen_random_uuid(),
  block_id uuid not null references public.course_blocks(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  attempt_number integer not null check(attempt_number>0),
  kind text not null check(kind in ('quiz','practical')),
  status text not null check(status in ('pending_review','passed','failed','competent','not_yet_competent')),
  answers jsonb not null default '{}'::jsonb,
  feedback jsonb not null default '{}'::jsonb,
  auto_points numeric not null default 0,
  score numeric,
  submitted_at timestamptz not null default now(),
  reviewer_id uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  review_details jsonb,
  review_comment text not null default '',
  unique(block_id,user_id,attempt_number)
);
create index assessment_attempts_user_block on public.assessment_attempts(user_id,block_id);
alter table public.assessment_definitions enable row level security;
alter table public.assessment_attempts enable row level security;
revoke all on public.assessment_definitions,public.assessment_attempts from public,anon,authenticated;
grant select on public.assessment_attempts to authenticated;
create function private.can_review_assessment(target_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and auth.uid()<>target_user and (
   private.is_admin() or (exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.role='trainer') and
     exists(select 1 from public.group_memberships m where m.user_id=target_user and m.status='active' and private.leads_group(m.group_id)))
 );
$$;
revoke all on function private.can_review_assessment(uuid) from public,anon;
grant execute on function private.can_review_assessment(uuid) to authenticated;
create policy attempts_read on public.assessment_attempts for select to authenticated using (
  private.can_review_assessment(user_id) or (user_id=auth.uid() and exists (
    select 1 from public.course_blocks b join public.course_modules m on m.id=b.module_id
    join public.course_assignments a on a.course_id=m.course_id and a.user_id=auth.uid()
    where b.id=block_id and private.assignment_is_active(a.id)
  ))
);

create function private.validate_assessment(kind text, doc jsonb) returns void language plpgsql security definer set search_path='' as $$
declare q jsonb; o jsonb; c jsonb; ids text[]:='{}'; option_ids text[]; correct_count int; n int;
begin
  if doc is null or jsonb_typeof(doc) is distinct from 'object' or length(doc::text)>100000 then raise exception 'Invalid assessment definition' using errcode='22023'; end if;
  if kind='quiz' then
    if jsonb_typeof(doc->'pass_mark') is distinct from 'number' or (doc->>'pass_mark') !~ '^\d+$' or (doc->>'pass_mark')::int not between 0 and 100 or jsonb_typeof(doc->'max_attempts') is distinct from 'number' or (doc->>'max_attempts') !~ '^\d+$' or (doc->>'max_attempts')::int not between 1 and 20 then raise exception 'Set a pass mark from 0 to 100 and attempt limit from 1 to 20' using errcode='22023'; end if;
    if jsonb_typeof(doc->'questions') is distinct from 'array' or jsonb_array_length(doc->'questions') not between 1 and 30 then raise exception 'Add 1 to 30 quiz questions' using errcode='22023'; end if;
    for q in select value from jsonb_array_elements(doc->'questions') loop
      if jsonb_typeof(q) is distinct from 'object' or coalesce(q->>'id','') !~ '^[A-Za-z0-9-]{1,80}$' or q->>'id'=any(ids) or jsonb_typeof(q->'prompt') is distinct from 'string' or coalesce(length(btrim(q->>'prompt')),0) not between 1 and 1000 or (q ? 'feedback' and jsonb_typeof(q->'feedback') is distinct from 'string') or coalesce(length(q->>'feedback'),0)>1000 or coalesce(q->>'type','') not in ('single','multiple','true_false','short') then raise exception 'Invalid or duplicate question' using errcode='22023'; end if;
      ids:=array_append(ids,q->>'id');
      if q->>'type'<>'short' then
        if jsonb_typeof(q->'options') is distinct from 'array' or jsonb_array_length(q->'options') not between 2 and 10 then raise exception 'Each choice question needs 2 to 10 options' using errcode='22023'; end if;
        option_ids:='{}';correct_count:=0;n:=0;
        for o in select value from jsonb_array_elements(q->'options') loop
          if jsonb_typeof(o) is distinct from 'object' or coalesce(o->>'id','') !~ '^[A-Za-z0-9-]{1,80}$' or o->>'id'=any(option_ids) or jsonb_typeof(o->'text') is distinct from 'string' or coalesce(length(btrim(o->>'text')),0) not between 1 and 500 or jsonb_typeof(o->'correct') is distinct from 'boolean' then raise exception 'Invalid or duplicate answer option' using errcode='22023'; end if;
          option_ids:=array_append(option_ids,o->>'id');n:=n+1;if (o->>'correct')::boolean then correct_count:=correct_count+1;end if;
        end loop;
        if correct_count<1 or (q->>'type' in ('single','true_false') and correct_count<>1) or (q->>'type'='true_false' and n<>2) then raise exception 'Choose valid correct answers' using errcode='22023'; end if;
      end if;
    end loop;
  elsif kind='practical' then
    if jsonb_typeof(doc->'criteria') is distinct from 'array' or jsonb_array_length(doc->'criteria') not between 1 and 30 then raise exception 'Add 1 to 30 checklist criteria' using errcode='22023'; end if;
    for c in select value from jsonb_array_elements(doc->'criteria') loop
      if jsonb_typeof(c) is distinct from 'object' or coalesce(c->>'id','') !~ '^[A-Za-z0-9-]{1,80}$' or c->>'id'=any(ids) or jsonb_typeof(c->'text') is distinct from 'string' or coalesce(length(btrim(c->>'text')),0) not between 1 and 1000 then raise exception 'Invalid or duplicate criterion' using errcode='22023'; end if;
      ids:=array_append(ids,c->>'id');
    end loop;
  else raise exception 'Invalid assessment type' using errcode='22023'; end if;
end; $$;
revoke all on function private.validate_assessment(text,jsonb) from public,anon,authenticated;

create function public.save_draft_assessment(target_module uuid, target_block uuid, new_title text, instructions text, required boolean, kind text, definition jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare parent_course uuid; result uuid;
begin
  select m.course_id into parent_course from public.course_modules m where m.id=target_module;
  perform private.lock_draft_course(parent_course);
  if required is null then raise exception 'Choose whether required' using errcode='22023'; end if;
  perform private.validate_assessment(kind,definition);
  if target_block is null then
    result:=public.add_course_block(target_module,new_title,instructions);
  else
    select b.id into result from public.course_blocks b where b.id=target_block and b.module_id=target_module and b.block_type=kind;
    if not found then raise exception 'Assessment not found' using errcode='22023'; end if;
  end if;
  update public.course_blocks set title=new_title,body=coalesce(instructions,''),is_required=required,block_type=kind where id=result;
  insert into public.assessment_definitions(block_id,definition) values(result,definition) on conflict(block_id) do update set definition=excluded.definition;
  return result;
end; $$;

-- Authors get their answer keys. Trainees/reviewers get only prompts/options,
-- not correctness flags or feedback until an attempt has been submitted.
create function public.get_assessment_definition(target_block uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare doc jsonb; k text; allowed boolean; safe_questions jsonb;
begin
 select d.definition,b.block_type into doc,k from public.assessment_definitions d join public.course_blocks b on b.id=d.block_id where b.id=target_block;
 if not found then raise exception 'Assessment not found' using errcode='22023'; end if;
 if private.can_author() then return doc; end if;
 select exists(select 1 from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.courses c on c.id=m.course_id and c.status='published' join public.course_assignments a on a.course_id=c.id where b.id=target_block and ((a.user_id=auth.uid() and private.assignment_is_active(a.id)) or (private.can_review_assessment(a.user_id) and (private.assignment_is_active(a.id) or exists(select 1 from public.assessment_attempts h where h.block_id=b.id and h.user_id=a.user_id))))) into allowed;
 if not allowed then raise exception 'Not authorised' using errcode='42501'; end if;
 if k='quiz' then
   select jsonb_agg((q.value - 'feedback' - 'options') || case when q.value->>'type'='short' then '{}'::jsonb else jsonb_build_object('options',(select jsonb_agg(o.value-'correct' order by o.ordinality) from jsonb_array_elements(q.value->'options') with ordinality o(value,ordinality))) end order by q.ordinality) into safe_questions from jsonb_array_elements(doc->'questions') with ordinality q(value,ordinality);
   return jsonb_set(doc,'{questions}',safe_questions);
 end if;
 return doc;
end; $$;

-- Names of reviewers of the caller's own currently accessible attempts only.
create function public.list_my_assessment_reviewers() returns table(reviewer_id uuid, display_name text) language sql stable security definer set search_path='' as $$
 select distinct p.id,p.display_name from public.assessment_attempts h
 join public.profiles p on p.id=h.reviewer_id
 join public.course_blocks b on b.id=h.block_id join public.course_modules m on m.id=b.module_id
 join public.course_assignments a on a.course_id=m.course_id and a.user_id=auth.uid()
 where h.user_id=auth.uid() and private.assignment_is_active(a.id);
$$;
revoke all on function public.list_my_assessment_reviewers() from public,anon;
grant execute on function public.list_my_assessment_reviewers() to authenticated;

create function public.submit_quiz(target_block uuid, submitted_answers jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare doc jsonb; aid uuid; q jsonb; o jsonb; answer jsonb; points numeric:=0; correct_total int; correct_selected int; wrong_selected int; selections int; attempt_count int; pending boolean:=false; result uuid; s numeric; st text; fb jsonb:='{}';
begin
  select a.id,d.definition into aid,doc from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.courses c on c.id=m.course_id and c.status='published' join public.course_assignments a on a.course_id=c.id and a.user_id=auth.uid() join public.assessment_definitions d on d.block_id=b.id where b.id=target_block and b.block_type='quiz' and private.assignment_is_active(a.id) for update of a;
  if not found then raise exception 'An active assignment is required' using errcode='42501'; end if;
  if jsonb_typeof(submitted_answers) is distinct from 'object' or (select count(*) from jsonb_object_keys(submitted_answers))<>jsonb_array_length(doc->'questions') then raise exception 'Answer every question' using errcode='22023'; end if;
  select count(*) into attempt_count from public.assessment_attempts where block_id=target_block and user_id=auth.uid();
  if attempt_count >= (doc->>'max_attempts')::int then raise exception 'Attempt limit reached' using errcode='22023'; end if;
  if exists(select 1 from public.assessment_attempts where block_id=target_block and user_id=auth.uid() and status='pending_review') then raise exception 'Wait for the previous attempt to be reviewed' using errcode='22023'; end if;
  for q in select value from jsonb_array_elements(doc->'questions') loop
    answer:=submitted_answers->(q->>'id');
    if q->>'type'='short' then
      if jsonb_typeof(answer) is distinct from 'string' or coalesce(length(btrim(answer#>>'{}')),0) not between 1 and 3000 then raise exception 'Answer every short-answer question' using errcode='22023'; end if;
      pending:=true;
    else
      if jsonb_typeof(answer) is distinct from 'array' then raise exception 'Select answers for every question' using errcode='22023'; end if;
      select count(*) into selections from jsonb_array_elements_text(answer);
      if selections<1 or selections<>(select count(distinct value) from jsonb_array_elements_text(answer)) or (q->>'type' in ('single','true_false') and selections<>1) or exists(select 1 from jsonb_array_elements_text(answer) x(value) where not exists(select 1 from jsonb_array_elements(q->'options') z(value) where z.value->>'id'=x.value)) then raise exception 'Invalid answer selection' using errcode='22023'; end if;
      select count(*) filter(where (o.value->>'correct')::boolean),count(*) filter(where (o.value->>'correct')::boolean and answer ? (o.value->>'id')),count(*) filter(where not (o.value->>'correct')::boolean and answer ? (o.value->>'id')) into correct_total,correct_selected,wrong_selected from jsonb_array_elements(q->'options') o(value);
      points:=points+greatest(0,(correct_selected-wrong_selected)::numeric/correct_total);
    end if;
    fb:=fb||jsonb_build_object(q->>'id',coalesce(q->>'feedback',''));
  end loop;
  if pending then st:='pending_review';s:=null; else s:=round(points*100/jsonb_array_length(doc->'questions'),2);st:=case when s >= (doc->>'pass_mark')::numeric then 'passed' else 'failed' end;end if;
  insert into public.assessment_attempts(block_id,user_id,attempt_number,kind,status,answers,feedback,auto_points,score) values(target_block,auth.uid(),attempt_count+1,'quiz',st,submitted_answers,fb,points,s) returning id into result;
  return result;
end; $$;

create function public.request_practical(target_block uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare aid uuid; n int; result uuid;
begin
 select a.id into aid from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.courses c on c.id=m.course_id and c.status='published' join public.course_assignments a on a.course_id=c.id and a.user_id=auth.uid() where b.id=target_block and b.block_type='practical' and private.assignment_is_active(a.id) for update of a;
 if not found then raise exception 'An active assignment is required' using errcode='42501'; end if;
 if exists(select 1 from public.assessment_attempts where block_id=target_block and user_id=auth.uid() and status='pending_review') then raise exception 'An assessment request is already awaiting review' using errcode='22023'; end if;
 select count(*)+1 into n from public.assessment_attempts where block_id=target_block and user_id=auth.uid();
 insert into public.assessment_attempts(block_id,user_id,attempt_number,kind,status) values(target_block,auth.uid(),n,'practical','pending_review') returning id into result;
 return result;
end; $$;

create function public.review_assessment(target_attempt uuid, decisions jsonb, comment text) returns void language plpgsql security definer set search_path='' as $$
declare a public.assessment_attempts%rowtype; doc jsonb; q jsonb; expected int:=0; correct int:=0; final_score numeric; final_status text; decision_value jsonb;
begin
 select * into a from public.assessment_attempts where id=target_attempt for update;
 if not found or not private.can_review_assessment(a.user_id) then raise exception 'Not authorised' using errcode='42501'; end if;
 if a.status<>'pending_review' then raise exception 'This attempt has already been reviewed' using errcode='22023'; end if;
 if not exists(select 1 from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.course_assignments ca on ca.course_id=m.course_id and ca.user_id=a.user_id where b.id=a.block_id and private.assignment_is_active(ca.id)) then raise exception 'The assignment is no longer active' using errcode='42501'; end if;
 if jsonb_typeof(decisions) is distinct from 'object' or coalesce(length(comment),0)>3000 then raise exception 'Invalid review' using errcode='22023'; end if;
 select definition into doc from public.assessment_definitions where block_id=a.block_id;
 if a.kind='quiz' then
   for q in select value from jsonb_array_elements(doc->'questions') where value->>'type'='short' loop
     expected:=expected+1;decision_value:=decisions->(q->>'id');
     if jsonb_typeof(decision_value) is distinct from 'boolean' then raise exception 'Mark each short answer correct or incorrect' using errcode='22023'; end if;
     if (decision_value#>>'{}')::boolean then correct:=correct+1;end if;
   end loop;
   if expected=0 then raise exception 'No trainer-marked answers' using errcode='22023'; end if;
   final_score:=round((a.auto_points+correct)*100/jsonb_array_length(doc->'questions'),2);
   final_status:=case when final_score >= (doc->>'pass_mark')::numeric then 'passed' else 'failed' end;
 else
   final_status:='competent';
   for q in select value from jsonb_array_elements(doc->'criteria') loop
     expected:=expected+1;decision_value:=decisions->(q->>'id');
     if jsonb_typeof(decision_value) is distinct from 'string' or (decision_value#>>'{}') not in ('competent','not_yet_competent','not_assessed') then raise exception 'Mark every checklist criterion' using errcode='22023'; end if;
     if (decision_value#>>'{}')<>'competent' then final_status:='not_yet_competent';end if;
   end loop;
 end if;
 if (select count(*) from jsonb_object_keys(decisions))<>expected then raise exception 'Invalid review decisions' using errcode='22023'; end if;
 update public.assessment_attempts set status=final_status,score=final_score,reviewer_id=auth.uid(),reviewed_at=now(),review_details=decisions,review_comment=coalesce(comment,'') where id=a.id;
end; $$;

-- Copy assessment definitions to new block IDs without copying attempts.
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
  return new_id;
end; $$;
create or replace function public.set_text_block_read(target_block uuid, is_read boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or is_read is null or not exists(select 1 from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.courses c on c.id=m.course_id and c.status='published' join public.course_assignments a on a.course_id=c.id and a.user_id=auth.uid() where b.id=target_block and b.block_type='text' and private.assignment_is_active(a.id)) then raise exception 'An active assignment for a text block is required' using errcode='42501'; end if;
 if is_read then insert into public.course_block_progress(user_id,block_id) values(auth.uid(),target_block) on conflict(user_id,block_id) do nothing; else delete from public.course_block_progress where user_id=auth.uid() and block_id=target_block; end if;
end; $$;
revoke all on function public.save_draft_assessment(uuid,uuid,text,text,boolean,text,jsonb), public.get_assessment_definition(uuid),public.submit_quiz(uuid,jsonb),public.request_practical(uuid),public.review_assessment(uuid,jsonb,text) from public,anon;
grant execute on function public.save_draft_assessment(uuid,uuid,text,text,boolean,text,jsonb), public.get_assessment_definition(uuid),public.submit_quiz(uuid,jsonb),public.request_practical(uuid),public.review_assessment(uuid,jsonb,text) to authenticated;
commit;
