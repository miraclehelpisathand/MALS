-- Minimal own-group directory for signed-in users: active memberships and
-- current leaders' display names only. No trainee directory or email addresses.
begin;
create function public.list_my_groups_with_leaders()
returns table(group_id uuid, group_name text, leader_names text[])
language sql stable security definer set search_path = '' as $$
  select g.id, g.name,
    coalesce(array_agg(distinct p.display_name order by p.display_name)
      filter (where r.user_id is not null and p.display_name is not null), '{}'::text[])
  from public.group_memberships m
  join public.groups g on g.id=m.group_id
  left join public.group_leaders l on l.group_id=g.id
  left join public.user_roles r on r.user_id=l.user_id and r.role='leader'
  left join public.profiles p on p.id=r.user_id
  where m.user_id=auth.uid() and m.status='active'
  group by g.id,g.name;
$$;
revoke all on function public.list_my_groups_with_leaders() from public,anon;
grant execute on function public.list_my_groups_with_leaders() to authenticated;
commit;
