-- Completion reflects current required reading and any successful assessment
-- attempt on the assigned immutable course version. NZ local end-of-day dates.
begin;
create table public.course_completion_state (
 assignment_id uuid primary key references public.course_assignments(id) on delete restrict,
 started_at timestamptz,
 completed_at timestamptz
);
create table public.course_completion_events (
 id uuid primary key default gen_random_uuid(),
 event_sequence bigint generated always as identity unique,
 assignment_id uuid not null references public.course_assignments(id) on delete restrict,
 event_type text not null check(event_type in ('completed','reopened')),
 occurred_at timestamptz not null default now(),
 actor_id uuid references public.profiles(id) on delete restrict,
 source text not null default 'activity' check(source in ('activity','initial_recognition'))
);
create index completion_events_assignment on public.course_completion_events(assignment_id,occurred_at,event_sequence);
alter table public.course_completion_state enable row level security;
alter table public.course_completion_events enable row level security;
revoke all on public.course_completion_state,public.course_completion_events from public,anon,authenticated;
grant select on public.course_completion_events to authenticated;
create policy completion_events_read on public.course_completion_events for select to authenticated using (
 exists(select 1 from public.course_assignments a where a.id=assignment_id and (private.is_admin() or (a.user_id=auth.uid() and private.assignment_is_active(a.id)) or (a.user_id<>auth.uid() and private.can_view_profile(a.user_id))))
);

create function private.required_block_counts(target_assignment uuid) returns table(total bigint,done bigint,pending bigint) language sql stable security definer set search_path='' as $$
 select count(*) filter(where b.is_required),
 count(*) filter(where b.is_required and case b.block_type
   when 'text' then exists(select 1 from public.course_block_progress p where p.block_id=b.id and p.user_id=a.user_id)
   when 'quiz' then exists(select 1 from public.assessment_attempts t where t.block_id=b.id and t.user_id=a.user_id and t.status='passed')
   when 'practical' then exists(select 1 from public.assessment_attempts t where t.block_id=b.id and t.user_id=a.user_id and t.status='competent')
   else false end),
 count(*) filter(where b.is_required and b.block_type in ('quiz','practical') and exists(select 1 from public.assessment_attempts t where t.block_id=b.id and t.user_id=a.user_id and t.status='pending_review') and not exists(select 1 from public.assessment_attempts t where t.block_id=b.id and t.user_id=a.user_id and ((b.block_type='quiz' and t.status='passed') or (b.block_type='practical' and t.status='competent'))))
 from public.course_assignments a join public.course_modules m on m.course_id=a.course_id join public.course_blocks b on b.module_id=m.id where a.id=target_assignment;
$$;
revoke all on function private.required_block_counts(uuid) from public,anon,authenticated;

-- Called while holding the assignment row lock, serialising transitions.
create function private.recalculate_completion(target_assignment uuid, start_activity boolean, source text default 'activity') returns void language plpgsql security definer set search_path='' as $$
declare totals record; previous timestamptz; newly_completed boolean; now_time timestamptz:=now();
begin
 perform 1 from public.course_assignments where id=target_assignment for update;
 if not found then return; end if;
 insert into public.course_completion_state(assignment_id,started_at) values(target_assignment,case when start_activity then now_time else null end) on conflict(assignment_id) do nothing;
 if start_activity then update public.course_completion_state set started_at=coalesce(started_at,now_time) where assignment_id=target_assignment; end if;
 select completed_at into previous from public.course_completion_state where assignment_id=target_assignment;
 select * into totals from private.required_block_counts(target_assignment);
 newly_completed:=totals.total>0 and totals.total=totals.done;
 if newly_completed and previous is null then
   update public.course_completion_state set completed_at=now_time where assignment_id=target_assignment;
   insert into public.course_completion_events(assignment_id,event_type,occurred_at,actor_id,source) values(target_assignment,'completed',now_time,auth.uid(),source);
 elsif not newly_completed and previous is not null then
   update public.course_completion_state set completed_at=null where assignment_id=target_assignment;
   insert into public.course_completion_events(assignment_id,event_type,occurred_at,actor_id,source) values(target_assignment,'reopened',now_time,auth.uid(),source);
 end if;
end; $$;
revoke all on function private.recalculate_completion(uuid,boolean,text) from public,anon,authenticated;

create function private.completion_activity_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare target_user uuid; target_block uuid; assignment uuid;
begin
 if tg_op='DELETE' then target_user:=old.user_id;target_block:=old.block_id; else target_user:=new.user_id;target_block:=new.block_id;end if;
 select a.id into assignment from public.course_assignments a join public.course_modules m on m.course_id=a.course_id join public.course_blocks b on b.module_id=m.id where b.id=target_block and a.user_id=target_user;
 if assignment is not null then perform private.recalculate_completion(assignment,tg_op<>'DELETE','activity');end if;
 if tg_op='DELETE' then return old;else return new;end if;
end; $$;
revoke all on function private.completion_activity_trigger() from public,anon,authenticated;
create trigger completion_text_change after insert or delete on public.course_block_progress for each row execute function private.completion_activity_trigger();
create trigger completion_assessment_change after insert or update on public.assessment_attempts for each row execute function private.completion_activity_trigger();

-- Lock before mutating a reading mark so concurrent required-block updates
-- cannot lose the final completion transition.
create or replace function public.set_text_block_read(target_block uuid, is_read boolean) returns void language plpgsql security definer set search_path='' as $$
declare assignment uuid;
begin
 select a.id into assignment from public.course_blocks b join public.course_modules m on m.id=b.module_id join public.courses c on c.id=m.course_id and c.status='published' join public.course_assignments a on a.course_id=c.id and a.user_id=auth.uid() where b.id=target_block and b.block_type='text' and private.assignment_is_active(a.id) for update of a;
 if not found or is_read is null then raise exception 'An active assignment for a text block is required' using errcode='42501'; end if;
 if is_read then insert into public.course_block_progress(user_id,block_id) values(auth.uid(),target_block) on conflict(user_id,block_id) do nothing; else delete from public.course_block_progress where user_id=auth.uid() and block_id=target_block; end if;
end; $$;

-- The earlier review function locks the attempt. Lock the assignment first,
-- consistently with quiz submissions and text updates; retain all its checks.
alter function public.review_assessment(uuid,jsonb,text) rename to review_assessment_without_completion_lock;
revoke all on function public.review_assessment_without_completion_lock(uuid,jsonb,text) from public,anon,authenticated;
create function public.review_assessment(target_attempt uuid, decisions jsonb, comment text) returns void language plpgsql security definer set search_path='' as $$
declare learner uuid; assignment uuid;
begin
 select h.user_id,a.id into learner,assignment from public.assessment_attempts h join public.course_blocks b on b.id=h.block_id join public.course_modules m on m.id=b.module_id join public.course_assignments a on a.course_id=m.course_id and a.user_id=h.user_id where h.id=target_attempt;
 if not found or not private.can_review_assessment(learner) then raise exception 'Not authorised' using errcode='42501'; end if;
 perform 1 from public.course_assignments where id=assignment for update;
 perform public.review_assessment_without_completion_lock(target_attempt,decisions,comment);
end; $$;
revoke all on function public.review_assessment(uuid,jsonb,text) from public,anon;
grant execute on function public.review_assessment(uuid,jsonb,text) to authenticated;

-- Existing activity was not previously a formal completion. Recognise any
-- currently satisfied assignment at migration time, not a guessed past date.
do $$
declare a record; activity_time timestamptz;
begin
 for a in select id,course_id,user_id from public.course_assignments loop
   select min(t) into activity_time from (
     select p.marked_at t from public.course_block_progress p join public.course_blocks b on b.id=p.block_id join public.course_modules m on m.id=b.module_id where p.user_id=a.user_id and m.course_id=a.course_id
     union all select h.submitted_at from public.assessment_attempts h join public.course_blocks b on b.id=h.block_id join public.course_modules m on m.id=b.module_id where h.user_id=a.user_id and m.course_id=a.course_id
   ) activity;
   insert into public.course_completion_state(assignment_id,started_at) values(a.id,activity_time) on conflict do nothing;
   perform private.recalculate_completion(a.id,false,'initial_recognition');
 end loop;
end; $$;

-- Aggregate status only: no assessment answers or scores are exposed to
-- leaders who can view a trainee but are not permitted to review assessments.
create function public.list_assignment_progress() returns table(
 assignment_id uuid,course_id uuid,user_id uuid,target_date date,active boolean,
 required_total bigint,required_done bigint,required_pending bigint,percent numeric,
 started_at timestamptz,completed_at timestamptz,status text,overdue boolean,completed_late boolean
) language sql stable security definer set search_path='' as $$
 select a.id,a.course_id,a.user_id,a.target_date,private.assignment_is_active(a.id),cnt.total,cnt.done,cnt.pending,
   case when cnt.total>0 then floor(cnt.done*100.0/cnt.total) else null end,
   s.started_at,s.completed_at,
   case when cnt.total=0 then 'needs_rule' when s.completed_at is not null then 'completed' when cnt.pending>0 then 'awaiting_review' when s.started_at is not null then 'in_progress' else 'not_started' end,
   (s.completed_at is null and now() >= ((a.target_date+1)::timestamp at time zone 'Pacific/Auckland')),
   (s.completed_at is not null and s.completed_at >= ((a.target_date+1)::timestamp at time zone 'Pacific/Auckland'))
 from public.course_assignments a
 cross join lateral private.required_block_counts(a.id) cnt
 left join public.course_completion_state s on s.assignment_id=a.id
 where auth.uid() is not null and (private.is_admin() or (a.user_id=auth.uid() and private.assignment_is_active(a.id)) or (a.user_id<>auth.uid() and private.can_view_profile(a.user_id)));
$$;
revoke all on function public.list_assignment_progress() from public,anon;
grant execute on function public.list_assignment_progress() to authenticated;
commit;
