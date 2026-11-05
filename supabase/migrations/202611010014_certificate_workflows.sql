-- LOCAL PROTOTYPE: requires complete task 5 testing before deployment.
begin;
-- Keep upload and settings in one transaction: a failed settings validation
-- cannot leave a newly uploaded orphan template behind.
create function public.save_certificate_settings_bundle(target_course uuid,png_base64 text,page_width numeric,page_height numeric,target_template uuid,months integer,refresher_family uuid,days_before integer,positions jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare selected uuid;
begin
 if png_base64 is not null then selected:=public.add_certificate_template(target_course,png_base64,page_width,page_height); else selected:=target_template;end if;
 perform public.save_certificate_settings(target_course,selected,months,refresher_family,days_before,positions);
 return selected;
end; $$;
revoke all on function public.save_certificate_settings_bundle(uuid,text,numeric,numeric,uuid,integer,uuid,integer,jsonb) from public,anon;
grant execute on function public.save_certificate_settings_bundle(uuid,text,numeric,numeric,uuid,integer,uuid,integer,jsonb) to authenticated;

-- A verified historical date is an auditable date-only fact. Do not fabricate
-- a timestamp for it or continue labelling it as unverified.
drop function public.list_assignment_progress();
create function public.list_assignment_progress() returns table(
 assignment_id uuid,course_id uuid,user_id uuid,target_date date,active boolean,
 required_total bigint,required_done bigint,required_pending bigint,percent numeric,
 started_at timestamptz,completed_at timestamptz,status text,overdue boolean,completed_late boolean,completion_origin text,verified_completion_date date
) language sql stable security definer set search_path='' as $$
 select a.id,a.course_id,a.user_id,a.target_date,private.assignment_is_active(a.id),cnt.total,cnt.done,cnt.pending,
   case when cnt.total>0 then floor(cnt.done*100.0/cnt.total) else null end,
   s.started_at,s.completed_at,
   case when cnt.total=0 then 'needs_rule' when s.completed_at is not null then 'completed' when cnt.pending>0 then 'awaiting_review' when s.started_at is not null then 'in_progress' else 'not_started' end,
   (s.completed_at is null and now() >= ((a.target_date+1)::timestamp at time zone 'Pacific/Auckland')),
   case when s.completed_at is null then false when e.source='initial_recognition' and v.verified_completion_date is null then null when e.source='initial_recognition' then v.verified_completion_date>a.target_date else s.completed_at >= ((a.target_date+1)::timestamp at time zone 'Pacific/Auckland') end,
   case when s.completed_at is null then null when e.source='initial_recognition' and v.verified_completion_date is not null then 'verified_historical' else e.source end,
   case when s.completed_at is not null then v.verified_completion_date else null end
 from public.course_assignments a
 cross join lateral private.required_block_counts(a.id) cnt
 left join public.course_completion_state s on s.assignment_id=a.id
 left join lateral (select id,source from public.course_completion_events where assignment_id=a.id and event_type='completed' order by event_sequence desc limit 1) e on true
 left join public.certificate_date_verifications v on v.completion_event_id=e.id
 where auth.uid() is not null and (private.is_admin() or (a.user_id=auth.uid() and private.assignment_is_active(a.id)) or (a.user_id<>auth.uid() and private.can_view_profile(a.user_id)));
$$;
revoke all on function public.list_assignment_progress() from public,anon;
grant execute on function public.list_assignment_progress() to authenticated;
commit;
