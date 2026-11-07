-- A migration-time recognition is not evidence of the original completion date.
-- Preserve the recognition timestamp, but never infer it was completed late.
begin;
drop function public.list_assignment_progress();
create function public.list_assignment_progress() returns table(
 assignment_id uuid,course_id uuid,user_id uuid,target_date date,active boolean,
 required_total bigint,required_done bigint,required_pending bigint,percent numeric,
 started_at timestamptz,completed_at timestamptz,status text,overdue boolean,completed_late boolean,completion_origin text
) language sql stable security definer set search_path='' as $$
 select a.id,a.course_id,a.user_id,a.target_date,private.assignment_is_active(a.id),cnt.total,cnt.done,cnt.pending,
   case when cnt.total>0 then floor(cnt.done*100.0/cnt.total) else null end,
   s.started_at,s.completed_at,
   case when cnt.total=0 then 'needs_rule' when s.completed_at is not null then 'completed' when cnt.pending>0 then 'awaiting_review' when s.started_at is not null then 'in_progress' else 'not_started' end,
   (s.completed_at is null and now() >= ((a.target_date+1)::timestamp at time zone 'Pacific/Auckland')),
   case when s.completed_at is null then false when e.source='initial_recognition' then null else s.completed_at >= ((a.target_date+1)::timestamp at time zone 'Pacific/Auckland') end,
   case when s.completed_at is not null then e.source else null end
 from public.course_assignments a
 cross join lateral private.required_block_counts(a.id) cnt
 left join public.course_completion_state s on s.assignment_id=a.id
 left join lateral (select source from public.course_completion_events where assignment_id=a.id and event_type='completed' order by event_sequence desc limit 1) e on true
 where auth.uid() is not null and (private.is_admin() or (a.user_id=auth.uid() and private.assignment_is_active(a.id)) or (a.user_id<>auth.uid() and private.can_view_profile(a.user_id)));
$$;
revoke all on function public.list_assignment_progress() from public,anon;
grant execute on function public.list_assignment_progress() to authenticated;
commit;
