-- LOCAL PROTOTYPE: do not deploy until full cycle integration and validation.
begin;
alter table public.certificates add column qualification_assignment_id uuid references public.course_assignments(id) on delete restrict;
update public.certificates set qualification_assignment_id=assignment_id;
alter table public.certificates alter column qualification_assignment_id set not null;
alter table public.certificates add column renewal_of_certificate_id uuid references public.certificates(id) on delete restrict;
create unique index certificates_one_active_qualification on public.certificates(qualification_assignment_id) where status='active';
create or replace function private.issue_certificate(target_event uuid, completion_day date, approver uuid default null, policy_course uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.course_completion_events%rowtype; a public.course_assignments%rowtype; cfg public.course_certificate_settings%rowtype; learner text; course public.courses%rowtype; result uuid;
begin
 select * into e from public.course_completion_events where id=target_event and event_type='completed';
 if not found then raise exception 'Completion event not found' using errcode='22023';end if;
 select * into a from public.course_assignments where id=e.assignment_id;
 select * into cfg from public.course_certificate_settings where course_id=coalesce(policy_course,a.course_id);
 if not found then return null;end if;
 if not exists(select 1 from public.courses original join public.courses policy on policy.family_id=original.family_id where original.id=a.course_id and policy.id=cfg.course_id and policy.status='published') then raise exception 'Certificate settings must be from a published version of the same course' using errcode='22023';end if;
 select display_name into learner from public.profiles where id=a.user_id;select * into course from public.courses where id=a.course_id;
 insert into public.certificates(qualification_assignment_id,assignment_id,completion_event_id,user_id,award_course_id,policy_course_id,template_id,trainee_name,course_title,course_version,completion_date,expiry_date,validity_months,refresher_family_id,lead_days,layout,issued_by)
 values(a.id,a.id,e.id,a.user_id,a.course_id,cfg.course_id,cfg.template_id,learner,course.title,course.version_number,completion_day,case when cfg.validity_months is null then null else (completion_day+make_interval(months=>cfg.validity_months))::date end,cfg.validity_months,cfg.refresher_family_id,cfg.lead_days,cfg.layout,approver)
 on conflict(completion_event_id) do nothing returning id into result;
 return result;
end; $$;

-- The source certificate captures the original qualification and its immutable
-- policy, even when the refresher is a completely different published course.
create function private.copy_qualification_certificate(source_certificate uuid,target_event uuid,completion_day date,approver uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare source public.certificates%rowtype; e public.course_completion_events%rowtype; a public.course_assignments%rowtype; learner text; result uuid;
begin
 select * into source from public.certificates where id=source_certificate;
 select * into e from public.course_completion_events where id=target_event and event_type='completed';
 if source.id is null or e.id is null then raise exception 'Certificate or completion event not found' using errcode='22023';end if;
 select * into a from public.course_assignments where id=e.assignment_id;
 if a.user_id<>source.user_id or coalesce(a.access_assignment_id,a.id)<>source.qualification_assignment_id then raise exception 'Completion does not match qualification' using errcode='22023';end if;
 select display_name into learner from public.profiles where id=a.user_id;
 insert into public.certificates(qualification_assignment_id,assignment_id,completion_event_id,user_id,award_course_id,policy_course_id,template_id,trainee_name,course_title,course_version,completion_date,expiry_date,validity_months,refresher_family_id,lead_days,layout,issued_by,renewal_of_certificate_id)
 values(source.qualification_assignment_id,a.id,e.id,a.user_id,source.award_course_id,source.policy_course_id,source.template_id,learner,source.course_title,source.course_version,completion_day,case when source.validity_months is null then null else (completion_day+make_interval(months=>source.validity_months))::date end,source.validity_months,source.refresher_family_id,source.lead_days,source.layout,approver,source.id)
 on conflict(completion_event_id) do nothing returning id into result;
 return result;
end; $$;
revoke all on function private.copy_qualification_certificate(uuid,uuid,date,uuid) from public,anon,authenticated;

-- A historical refresher must not reissue a later qualification, or bypass
-- an original course reopening. Events use one database-wide sequence.
create function private.refresher_reissue_is_current(target_assignment uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.course_assignments a
  join public.course_completion_state anchor on anchor.assignment_id=a.access_assignment_id and anchor.completed_at is not null
  join lateral (
   select c.assignment_id,c.status,ev.event_sequence
   from public.certificates c join public.course_completion_events ev on ev.id=c.completion_event_id
   where c.qualification_assignment_id=a.access_assignment_id
   order by ev.event_sequence desc limit 1
  ) latest on true
  where a.id=target_assignment and a.access_assignment_id is not null
    and latest.assignment_id=a.id and latest.status='revoked'
    and not exists(select 1 from public.course_completion_events reopen
     where reopen.assignment_id=a.access_assignment_id and reopen.event_type='reopened' and reopen.event_sequence>latest.event_sequence)
 );
$$;
revoke all on function private.refresher_reissue_is_current(uuid) from public,anon,authenticated;

create or replace function private.certificate_completion_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.course_assignments%rowtype; source public.certificates%rowtype;
begin
 select * into a from public.course_assignments where id=new.assignment_id;
 if new.event_type='reopened' then
  update public.certificates set status='revoked',revoked_at=new.occurred_at,revocation_reason='Course reopened' where status='active' and (assignment_id=a.id or (a.access_assignment_id is null and qualification_assignment_id=a.id));
  update public.certificate_reissue_requests set status='cancelled' where status='pending' and (assignment_id=a.id or (a.access_assignment_id is null and assignment_id in (select id from public.course_assignments where access_assignment_id=a.id)));
 elsif new.source='activity' then
  if exists(select 1 from public.certificates where status='revoked' and (assignment_id=a.id or (a.access_assignment_id is null and qualification_assignment_id=a.id))) then
   if a.access_assignment_id is null or private.refresher_reissue_is_current(a.id) then
    insert into public.certificate_reissue_requests(completion_event_id,assignment_id,user_id) values(new.id,a.id,a.user_id) on conflict do nothing;
   end if;
  elsif a.refresher_of_certificate_id is not null then
   select * into source from public.certificates where id=a.refresher_of_certificate_id for update;
   -- An old refresher cannot extend a qualification revoked while it was underway.
   if source.status='active' and source.qualification_assignment_id=a.access_assignment_id then
    update public.certificates set status='superseded' where id=source.id;
    perform private.copy_qualification_certificate(source.id,new.id,(new.occurred_at at time zone 'Pacific/Auckland')::date,null);
   end if;
  elsif exists(select 1 from public.course_certificate_settings where course_id=a.course_id) then
   perform private.issue_certificate(new.id,(new.occurred_at at time zone 'Pacific/Auckland')::date,null);
  end if;
 end if;
 return new;
end; $$;
create or replace function public.approve_certificate_reissue(target_event uuid) returns void language plpgsql security definer set search_path='' as $$
declare req public.certificate_reissue_requests%rowtype; e public.course_completion_events%rowtype; a public.course_assignments%rowtype; prior uuid;
begin
 select * into req from public.certificate_reissue_requests where completion_event_id=target_event;
 if not found or not private.can_review_assessment(req.user_id) then raise exception 'Not authorised' using errcode='42501';end if;
 perform private.lock_cycle(req.assignment_id);
 select * into a from public.course_assignments where id=req.assignment_id;
 select * into req from public.certificate_reissue_requests where completion_event_id=target_event for update;
 if req.status<>'pending' or not private.assignment_is_active(req.assignment_id) or not exists(select 1 from public.course_completion_state where assignment_id=req.assignment_id and completed_at is not null) or target_event<>(select id from public.course_completion_events where assignment_id=req.assignment_id and event_type='completed' order by event_sequence desc limit 1) then raise exception 'Reissue is no longer eligible' using errcode='22023';end if;
 select * into e from public.course_completion_events where id=target_event;
 select c.id into prior from public.certificates c join public.course_completion_events ev on ev.id=c.completion_event_id
 where c.status='revoked' and (c.assignment_id=a.id or (a.access_assignment_id is null and c.qualification_assignment_id=a.id)) order by ev.event_sequence desc limit 1 for update of c;
 if prior is null then raise exception 'Previous certificate not found' using errcode='22023';end if;
 if a.access_assignment_id is not null and not private.refresher_reissue_is_current(a.id) then raise exception 'Refresher reissue is no longer eligible' using errcode='22023';end if;
 if exists(select 1 from public.certificates c join public.certificates old on old.id=prior where c.qualification_assignment_id=old.qualification_assignment_id and c.status='active') then raise exception 'This qualification already has an active certificate' using errcode='22023';end if;
 perform private.copy_qualification_certificate(prior,target_event,(e.occurred_at at time zone 'Pacific/Auckland')::date,auth.uid());
 update public.certificate_reissue_requests set status='approved',reviewed_by=auth.uid(),reviewed_at=now() where completion_event_id=target_event;
end; $$;

-- Health records deliberately contain no trainee information. If no heartbeat
-- appears, the scheduler has failed to run and an operator must be alerted.
create table private.refresher_job_runs (
 id bigint generated always as identity primary key,
 started_at timestamptz not null,finished_at timestamptz not null,
 eligible_count integer not null,created_count integer not null,error_count integer not null,
 error_codes text[] not null default '{}'
);
revoke all on private.refresher_job_runs from public,anon,authenticated;
create function private.run_refresher_scheduler(as_of date default (now() at time zone 'Pacific/Auckland')::date) returns integer language plpgsql security definer set search_path='' as $$
declare candidate record; source public.certificates%rowtype; target uuid; created_count integer:=0;eligible_count integer:=0;error_count integer:=0;errors text[]:='{}';started timestamptz:=clock_timestamp();
begin
 if as_of is null then raise exception 'Date required' using errcode='22023';end if;
 for candidate in select c.id,c.qualification_assignment_id from public.certificates c where c.status='active' and c.expiry_date is not null and c.refresher_family_id is not null and as_of>=c.expiry_date-c.lead_days and not exists(select 1 from public.course_assignments a where a.refresher_of_certificate_id=c.id) order by c.qualification_assignment_id,c.id loop
  begin
   -- Same lock order as reopening: qualification first, then certificate.
   perform 1 from public.course_assignments where id=candidate.qualification_assignment_id for update skip locked;
   if not found then continue;end if;
   select * into source from public.certificates where id=candidate.id for update;
   if source.status<>'active' or source.expiry_date is null or as_of<source.expiry_date-source.lead_days or not private.assignment_is_active(source.qualification_assignment_id) or exists(select 1 from public.course_assignments where refresher_of_certificate_id=source.id) then continue;end if;
   eligible_count:=eligible_count+1;
   select id into target from public.courses where family_id=source.refresher_family_id and status='published' order by version_number desc limit 1;
   if target is null then raise exception 'No published refresher version' using errcode='22023';end if;
   insert into public.course_assignments(course_id,user_id,target_date,refresher_of_certificate_id,access_assignment_id) values(target,source.user_id,source.expiry_date,source.id,source.qualification_assignment_id) on conflict(refresher_of_certificate_id) where refresher_of_certificate_id is not null do nothing;
   if found then created_count:=created_count+1;end if;
  exception when others then
   error_count:=error_count+1;errors:=array_append(errors,sqlstate);
  end;
 end loop;
 insert into private.refresher_job_runs(started_at,finished_at,eligible_count,created_count,error_count,error_codes) values(started,clock_timestamp(),eligible_count,created_count,error_count,errors);
 return created_count;
end; $$;
revoke all on function private.run_refresher_scheduler(date) from public,anon,authenticated;
create function public.refresher_scheduler_health() returns table(started_at timestamptz,finished_at timestamptz,eligible_count integer,created_count integer,error_count integer,error_codes text[]) language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'Administrator required' using errcode='42501';end if;
 return query select r.started_at,r.finished_at,r.eligible_count,r.created_count,r.error_count,r.error_codes from private.refresher_job_runs r order by r.id desc limit 30;
end; $$;
revoke all on function public.refresher_scheduler_health() from public,anon;
grant execute on function public.refresher_scheduler_health() to authenticated;

-- A dedicated unprivileged Auth account may be allowlisted by a database
-- operator to check aggregate health. It cannot enroll itself, run the job,
-- see trainee information or read the underlying records. No account is
-- allowlisted automatically. The monitor is separate from administrator UI.
create table private.refresher_monitor_users (
 user_id uuid primary key references auth.users(id) on delete cascade
);
revoke all on private.refresher_monitor_users from public,anon,authenticated;
create function public.refresher_monitor_status() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare last_finished timestamptz; recent_errors bigint; cron_failures bigint:=0; job_active boolean:=false; logging_enabled boolean:=coalesce(pg_catalog.current_setting('cron.log_run',true)='on',false);
begin
 if not exists(select 1 from private.refresher_monitor_users where user_id=auth.uid())
    or exists(select 1 from public.user_roles where user_id=auth.uid())
    or exists(select 1 from public.group_memberships where user_id=auth.uid())
    or exists(select 1 from public.group_leaders where user_id=auth.uid())
    or exists(select 1 from public.course_assignments where user_id=auth.uid()) then
  raise exception 'Not authorised' using errcode='42501';
 end if;
 select max(finished_at), coalesce(sum(error_count) filter (where finished_at>=statement_timestamp()-interval '26 hours'),0)
 into last_finished,recent_errors from private.refresher_job_runs;
 -- Dynamic SQL allows installation before pg_cron; absent job/extension fails
 -- closed. Cron records are checked as well as the application heartbeat.
 if pg_catalog.to_regclass('cron.job') is not null and pg_catalog.to_regclass('cron.job_run_details') is not null then
  execute $sql$select exists(select 1 from cron.job where jobname='miracle-academy-refresher-hourly' and active and schedule='17 * * * *'
    and command='select private.run_refresher_scheduler();' and database=current_database())$sql$ into job_active;
  execute $sql$select count(*) from cron.job_run_details d join cron.job j on j.jobid=d.jobid
   where j.jobname='miracle-academy-refresher-hourly' and d.status='failed'
     and d.start_time>=statement_timestamp()-interval '26 hours'$sql$ into cron_failures;
 end if;
 return pg_catalog.jsonb_build_object(
  'healthy',job_active and logging_enabled and last_finished is not null and last_finished>=statement_timestamp()-interval '3 hours'
    and last_finished<=statement_timestamp()+interval '5 minutes' and recent_errors=0 and cron_failures=0,
  'job_active',job_active,'logging_enabled',logging_enabled,'last_finished',last_finished,'recent_errors',recent_errors,'cron_failures',cron_failures
 );
end; $$;
revoke all on function public.refresher_monitor_status() from public,anon;
grant execute on function public.refresher_monitor_status() to authenticated;
commit;
