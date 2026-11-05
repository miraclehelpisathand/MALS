-- Direct group leadership must stop granting access when the leader role is
-- removed. Keep functions security-definer with a fixed, empty search_path.
begin;
create or replace function private.leads_group(target_group uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.group_leaders l
    join public.user_roles r on r.user_id = l.user_id and r.role = 'leader'
    where l.group_id = target_group and l.user_id = auth.uid()
  );
$$;
create or replace function private.can_view_profile(target_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select target_user = auth.uid() or private.is_admin() or exists (
    select 1 from public.group_memberships m
    where m.user_id = target_user and private.leads_group(m.group_id)
  );
$$;
commit;
