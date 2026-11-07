-- LOCAL PROTOTYPE: do not deploy independently of task 5 integration and tests.
begin;
-- Standard assignments remain unique. Refresher cycles use the same course and
-- user but have independent assignment IDs, reading marks and attempts.
alter table public.course_assignments add column refresher_of_certificate_id uuid references public.certificates(id) on delete restrict;
alter table public.course_assignments add column access_assignment_id uuid references public.course_assignments(id) on delete restrict;
alter table public.course_assignments add constraint refresher_access_pair check ((refresher_of_certificate_id is null and access_assignment_id is null) or (refresher_of_certificate_id is not null and access_assignment_id is not null));
alter table public.course_assignments drop constraint course_assignments_course_id_user_id_key;
create unique index course_assignments_regular_unique on public.course_assignments(course_id,user_id) where refresher_of_certificate_id is null;
create unique index course_assignments_refresher_unique on public.course_assignments(refresher_of_certificate_id) where refresher_of_certificate_id is not null;

alter table public.course_block_progress add column assignment_id uuid references public.course_assignments(id) on delete restrict;
update public.course_block_progress p set assignment_id=a.id from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.course_assignments a on a.course_id=m.course_id where b.id=p.block_id and a.user_id=p.user_id;
alter table public.course_block_progress alter column assignment_id set not null;
alter table public.course_block_progress drop constraint course_block_progress_pkey;
alter table public.course_block_progress add primary key(assignment_id,block_id);
alter table public.assessment_attempts add column assignment_id uuid references public.course_assignments(id) on delete restrict;
alter table public.assessment_attempts disable trigger completion_assessment_change;
update public.assessment_attempts t set assignment_id=a.id from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.course_assignments a on a.course_id=m.course_id where b.id=t.block_id and a.user_id=t.user_id;
alter table public.assessment_attempts enable trigger completion_assessment_change;
alter table public.assessment_attempts alter column assignment_id set not null;
alter table public.assessment_attempts drop constraint assessment_attempts_block_id_user_id_attempt_number_key;
alter table public.assessment_attempts add constraint assessment_attempts_cycle_number_unique unique(assignment_id,block_id,attempt_number);
create index assessment_attempts_assignment_block on public.assessment_attempts(assignment_id,block_id);

create or replace function private.assignment_is_active(target_assignment uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.course_assignments a
  left join public.course_assignments anchor on anchor.id=a.access_assignment_id and anchor.user_id=a.user_id and anchor.access_assignment_id is null
  left join public.certificates source on source.id=a.refresher_of_certificate_id
  where a.id=target_assignment and (
    (a.access_assignment_id is null and (a.individually_assigned or exists(select 1 from public.assignment_group_sources s join public.group_memberships m on m.group_id=s.group_id and m.user_id=a.user_id and m.status='active' where s.assignment_id=a.id)))
    or (anchor.id is not null and source.status in ('active','superseded') and (anchor.individually_assigned or exists(select 1 from public.assignment_group_sources s join public.group_memberships m on m.group_id=s.group_id and m.user_id=anchor.user_id and m.status='active' where s.assignment_id=anchor.id)))
  ));
$$;
-- Lock qualification before the cycle, matching scheduler and original-course
-- reopening. This prevents a concurrent renewal escaping revocation.
create function private.lock_cycle(target_assignment uuid) returns void language plpgsql security definer set search_path='' as $$
declare anchor uuid;
begin
 select coalesce(access_assignment_id,id) into anchor from public.course_assignments where id=target_assignment;
 if anchor is null then raise exception 'Assignment not found' using errcode='42501';end if;
 perform 1 from public.course_assignments where id=anchor for update;
 if anchor<>target_assignment then perform 1 from public.course_assignments where id=target_assignment for update;end if;
end; $$;
revoke all on function private.lock_cycle(uuid) from public,anon,authenticated;

create or replace function public.assign_course_individual(target_course uuid, target_user uuid, due_date date) returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not (private.is_admin() or exists(select 1 from public.group_memberships m where m.user_id=target_user and private.leads_group(m.group_id))) then raise exception 'Not authorised' using errcode='42501'; end if;
  if due_date is null or not exists(select 1 from public.courses where id=target_course and status='published') or not exists(select 1 from public.user_roles where user_id=target_user and role='trainee') then raise exception 'A published course, trainee and target date are required' using errcode='22023'; end if;
  insert into public.course_assignments(course_id,user_id,target_date,individually_assigned) values(target_course,target_user,due_date,true) on conflict(course_id,user_id) where refresher_of_certificate_id is null do update set individually_assigned=true;
end; $$;

create or replace function public.assign_course_group(target_course uuid, target_group uuid, due_date date) returns void language plpgsql security definer set search_path='' as $$
declare member record; assignment uuid;
begin
  if auth.uid() is null or not (private.is_admin() or private.leads_group(target_group)) then raise exception 'Not authorised' using errcode='42501'; end if;
  if due_date is null or not exists(select 1 from public.courses where id=target_course and status='published') then raise exception 'A published course and target date are required' using errcode='22023'; end if;
  perform 1 from public.groups where id=target_group for update;
  if not found then raise exception 'Group not found' using errcode='22023'; end if;
  insert into public.group_course_requirements(group_id,course_id) values(target_group,target_course);
  for member in select user_id from public.group_memberships where group_id=target_group and status='active' loop
    insert into public.course_assignments(course_id,user_id,target_date) values(target_course,member.user_id,due_date) on conflict(course_id,user_id) where refresher_of_certificate_id is null do nothing;
    select id into assignment from public.course_assignments where course_id=target_course and user_id=member.user_id and refresher_of_certificate_id is null;
    insert into public.assignment_group_sources values(assignment,target_group) on conflict do nothing;
  end loop;
end; $$;


create or replace function public.manage_group_membership(target_group uuid, target_user uuid, action text, course_dates jsonb default '{}'::jsonb) returns void language plpgsql security definer set search_path='' as $$
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
      insert into public.course_assignments(course_id,user_id,target_date) values(requirement.course_id,target_user,selected_date) on conflict(course_id,user_id) where refresher_of_certificate_id is null do nothing;
      select id into assignment from public.course_assignments where course_id=requirement.course_id and user_id=target_user and refresher_of_certificate_id is null;
      insert into public.assignment_group_sources values(assignment,target_group) on conflict do nothing;
    end loop;
  end if;
end; $$;

create or replace function private.required_block_counts(target_assignment uuid) returns table(total bigint,done bigint,pending bigint) language sql stable security definer set search_path='' as $$
 select count(*) filter(where b.is_required),
 count(*) filter(where b.is_required and case b.block_type
   when 'text' then exists(select 1 from public.course_block_progress p where p.block_id=b.id and p.assignment_id=a.id)
   when 'quiz' then exists(select 1 from public.assessment_attempts t where t.block_id=b.id and t.assignment_id=a.id and t.status='passed')
   when 'practical' then exists(select 1 from public.assessment_attempts t where t.block_id=b.id and t.assignment_id=a.id and t.status='competent')
   else false end),
 count(*) filter(where b.is_required and b.block_type in ('quiz','practical') and exists(select 1 from public.assessment_attempts t where t.block_id=b.id and t.assignment_id=a.id and t.status='pending_review') and not exists(select 1 from public.assessment_attempts t where t.block_id=b.id and t.assignment_id=a.id and ((b.block_type='quiz' and t.status='passed') or (b.block_type='practical' and t.status='competent'))))
 from public.course_assignments a join public.course_modules m on m.course_id=a.course_id join public.course_blocks b on b.module_id=m.id where a.id=target_assignment;
$$;

create or replace function private.completion_activity_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then perform private.recalculate_completion(old.assignment_id,false,'activity');return old;
 else perform private.recalculate_completion(new.assignment_id,true,'activity');return new;end if;
end; $$;

drop policy block_progress_read on public.course_block_progress;
-- Preserve the existing policy: learners can see their own retained reading
-- history even when group-only course access has ended. This does not grant
-- access to the course or the ability to change that history.
create policy block_progress_read on public.course_block_progress for select to authenticated using (private.can_view_profile(user_id));
drop policy attempts_read on public.assessment_attempts;
create policy attempts_read on public.assessment_attempts for select to authenticated using (
 private.can_review_assessment(user_id) or (user_id=auth.uid() and private.assignment_is_active(assignment_id))
);
create or replace function public.list_my_assessment_reviewers() returns table(reviewer_id uuid,display_name text) language sql stable security definer set search_path='' as $$
 select distinct p.id,p.display_name from public.assessment_attempts h join public.profiles p on p.id=h.reviewer_id
 where h.user_id=auth.uid() and private.assignment_is_active(h.assignment_id);
$$;

create function public.set_assignment_text_block_read(target_assignment uuid,target_block uuid,is_read boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.course_assignments where id=target_assignment and user_id=auth.uid() and private.assignment_is_active(id);
 if not found then raise exception 'An active assignment is required' using errcode='42501';end if;
 perform private.lock_cycle(target_assignment);
 perform 1 from public.course_assignments a join public.courses c on c.id=a.course_id and c.status='published' join public.course_modules m on m.course_id=c.id join public.course_blocks b on b.module_id=m.id
 where a.id=target_assignment and a.user_id=auth.uid() and b.id=target_block and b.block_type='text' and private.assignment_is_active(a.id) for update of a;
 if not found or is_read is null then raise exception 'An active assignment for a text block is required' using errcode='42501';end if;
 if is_read then insert into public.course_block_progress(user_id,block_id,assignment_id) values(auth.uid(),target_block,target_assignment) on conflict(assignment_id,block_id) do nothing;
 else delete from public.course_block_progress where assignment_id=target_assignment and block_id=target_block and user_id=auth.uid();end if;
end; $$;
create or replace function public.set_text_block_read(target_block uuid,is_read boolean) returns void language plpgsql security definer set search_path='' as $$
declare aid uuid;
begin
 select a.id into aid from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.course_assignments a on a.course_id=m.course_id and a.user_id=auth.uid() and a.refresher_of_certificate_id is null where b.id=target_block;
 perform public.set_assignment_text_block_read(aid,target_block,is_read);
end; $$;
create function public.submit_assignment_quiz(target_assignment uuid,target_block uuid, submitted_answers jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare doc jsonb; aid uuid; q jsonb; o jsonb; answer jsonb; points numeric:=0; correct_total int; correct_selected int; wrong_selected int; selections int; attempt_count int; pending boolean:=false; result uuid; s numeric; st text; fb jsonb:='{}';
begin
 perform 1 from public.course_assignments where id=target_assignment and user_id=auth.uid() and private.assignment_is_active(id);
 if not found then raise exception 'An active assignment is required' using errcode='42501';end if;
 perform private.lock_cycle(target_assignment);
  select a.id,d.definition into aid,doc from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.courses c on c.id=m.course_id and c.status='published' join public.course_assignments a on a.course_id=c.id and a.user_id=auth.uid() join public.assessment_definitions d on d.block_id=b.id where a.id=target_assignment and b.id=target_block and b.block_type='quiz' and private.assignment_is_active(a.id) for update of a;
  if not found then raise exception 'An active assignment is required' using errcode='42501'; end if;
  if jsonb_typeof(submitted_answers) is distinct from 'object' or (select count(*) from jsonb_object_keys(submitted_answers))<>jsonb_array_length(doc->'questions') then raise exception 'Answer every question' using errcode='22023'; end if;
  select count(*) into attempt_count from public.assessment_attempts where assignment_id=aid and block_id=target_block and user_id=auth.uid();
  if attempt_count >= (doc->>'max_attempts')::int then raise exception 'Attempt limit reached' using errcode='22023'; end if;
  if exists(select 1 from public.assessment_attempts where assignment_id=aid and block_id=target_block and user_id=auth.uid() and status='pending_review') then raise exception 'Wait for the previous attempt to be reviewed' using errcode='22023'; end if;
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
  insert into public.assessment_attempts(assignment_id,block_id,user_id,attempt_number,kind,status,answers,feedback,auto_points,score) values(aid,target_block,auth.uid(),attempt_count+1,'quiz',st,submitted_answers,fb,points,s) returning id into result;
  return result;
end; $$;

create function public.request_assignment_practical(target_assignment uuid,target_block uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare aid uuid; n int; result uuid;
begin
 perform 1 from public.course_assignments where id=target_assignment and user_id=auth.uid() and private.assignment_is_active(id);
 if not found then raise exception 'An active assignment is required' using errcode='42501';end if;
 perform private.lock_cycle(target_assignment);
 select a.id into aid from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.courses c on c.id=m.course_id and c.status='published' join public.course_assignments a on a.course_id=c.id and a.user_id=auth.uid() where a.id=target_assignment and b.id=target_block and b.block_type='practical' and private.assignment_is_active(a.id) for update of a;
 if not found then raise exception 'An active assignment is required' using errcode='42501'; end if;
 if exists(select 1 from public.assessment_attempts where assignment_id=aid and block_id=target_block and user_id=auth.uid() and status='pending_review') then raise exception 'An assessment request is already awaiting review' using errcode='22023'; end if;
 select count(*)+1 into n from public.assessment_attempts where assignment_id=aid and block_id=target_block and user_id=auth.uid();
 insert into public.assessment_attempts(assignment_id,block_id,user_id,attempt_number,kind,status) values(aid,target_block,auth.uid(),n,'practical','pending_review') returning id into result;
 return result;
end; $$;


create or replace function public.submit_quiz(target_block uuid,submitted_answers jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare aid uuid;
begin
 select a.id into aid from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.course_assignments a on a.course_id=m.course_id and a.user_id=auth.uid() and a.refresher_of_certificate_id is null where b.id=target_block;
 return public.submit_assignment_quiz(aid,target_block,submitted_answers);
end; $$;
create or replace function public.request_practical(target_block uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare aid uuid;
begin
 select a.id into aid from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.course_assignments a on a.course_id=m.course_id and a.user_id=auth.uid() and a.refresher_of_certificate_id is null where b.id=target_block;
 return public.request_assignment_practical(aid,target_block);
end; $$;
create or replace function public.review_assessment_without_completion_lock(target_attempt uuid, decisions jsonb, comment text) returns void language plpgsql security definer set search_path='' as $$
declare a public.assessment_attempts%rowtype; doc jsonb; q jsonb; expected int:=0; correct int:=0; final_score numeric; final_status text; decision_value jsonb;
begin
 select * into a from public.assessment_attempts where id=target_attempt for update;
 if not found or not private.can_review_assessment(a.user_id) then raise exception 'Not authorised' using errcode='42501'; end if;
 if a.status<>'pending_review' then raise exception 'This attempt has already been reviewed' using errcode='22023'; end if;
 if not private.assignment_is_active(a.assignment_id) then raise exception 'The assignment is no longer active' using errcode='42501'; end if;
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


create or replace function public.review_assessment(target_attempt uuid,decisions jsonb,comment text) returns void language plpgsql security definer set search_path='' as $$
declare learner uuid; assignment uuid;
begin
 select h.user_id,h.assignment_id into learner,assignment from public.assessment_attempts h where h.id=target_attempt;
 if not found or not private.can_review_assessment(learner) then raise exception 'Not authorised' using errcode='42501';end if;
 perform private.lock_cycle(assignment);
 perform public.review_assessment_without_completion_lock(target_attempt,decisions,comment);
end; $$;
revoke all on function public.set_assignment_text_block_read(uuid,uuid,boolean),public.submit_assignment_quiz(uuid,uuid,jsonb),public.request_assignment_practical(uuid,uuid) from public,anon;
grant execute on function public.set_assignment_text_block_read(uuid,uuid,boolean),public.submit_assignment_quiz(uuid,uuid,jsonb),public.request_assignment_practical(uuid,uuid) to authenticated;
commit;
