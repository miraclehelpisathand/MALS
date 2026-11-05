-- Development foundation only. Apply to a new, dedicated development project.
-- Roles are deliberately not assigned from user-supplied metadata.
begin;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (length(display_name) <= 100),
  created_at timestamptz not null default now()
);
create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('administrator', 'author', 'trainer', 'leader', 'trainee')),
  primary key (user_id, role)
);
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 100),
  parent_id uuid references public.groups(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (parent_id is null or parent_id <> id)
);
create table public.group_leaders (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (group_id, user_id)
);
create table public.group_memberships (
  group_id uuid not null references public.groups(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'active' check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
-- Deliberately no cascading foreign keys: a membership audit must survive deletion.
create table public.membership_audit (
  id bigint generated always as identity primary key,
  group_id uuid not null,
  user_id uuid not null,
  actor_id uuid not null,
  action text not null check (action in ('add', 'archive', 'restore', 'delete')),
  occurred_at timestamptz not null default now()
);

create function private.create_profile_for_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(split_part(new.email, '@', 1), ''), 100));
  return new;
end;
$$;
revoke all on function private.create_profile_for_user() from public;
create trigger create_profile_after_auth_user after insert on auth.users
for each row execute function private.create_profile_for_user();
-- If the development project already has users, create their profiles too.
insert into public.profiles (id, display_name)
select id, left(coalesce(split_part(email, '@', 1), ''), 100) from auth.users
on conflict (id) do nothing;

-- These helpers bypass table RLS to avoid recursive policies. They accept only
-- target IDs and always use the authenticated caller's uid, not caller claims
-- or user-supplied roles. No parent-group inheritance is assumed.
create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_roles r where r.user_id = auth.uid() and r.role = 'administrator');
$$;
create function private.leads_group(target_group uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_leaders l where l.group_id = target_group and l.user_id = auth.uid());
$$;
create function private.can_view_profile(target_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select target_user = auth.uid() or private.is_admin() or exists (
    select 1 from public.group_memberships m
    join public.group_leaders l on l.group_id = m.group_id
    where m.user_id = target_user and l.user_id = auth.uid()
  );
$$;
revoke all on function private.is_admin() from public;
revoke all on function private.leads_group(uuid) from public;
revoke all on function private.can_view_profile(uuid) from public;
grant execute on function private.is_admin(), private.leads_group(uuid), private.can_view_profile(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.groups enable row level security;
alter table public.group_leaders enable row level security;
alter table public.group_memberships enable row level security;
alter table public.membership_audit enable row level security;

-- Revoke default table grants to prevent anonymous access and unintended writes.
revoke all on public.profiles, public.user_roles, public.groups, public.group_leaders, public.group_memberships, public.membership_audit from public, anon, authenticated;
grant select on public.profiles, public.user_roles, public.groups, public.group_leaders, public.group_memberships, public.membership_audit to authenticated;
grant insert, update on public.groups to authenticated;
grant insert, delete on public.user_roles, public.group_leaders to authenticated;

create policy profiles_read on public.profiles for select to authenticated using (private.can_view_profile(id));
create policy roles_read on public.user_roles for select to authenticated using (user_id = auth.uid() or private.is_admin());
create policy roles_insert_admin on public.user_roles for insert to authenticated with check (private.is_admin());
create policy roles_delete_admin on public.user_roles for delete to authenticated using (private.is_admin());
create policy groups_read on public.groups for select to authenticated using (
  private.is_admin() or private.leads_group(id) or exists (
    select 1 from public.group_memberships m where m.group_id = id and m.user_id = auth.uid() and m.status = 'active'
  )
);
create policy groups_insert_admin on public.groups for insert to authenticated with check (private.is_admin());
create policy groups_update_admin on public.groups for update to authenticated using (private.is_admin()) with check (private.is_admin());
create policy leaders_read on public.group_leaders for select to authenticated using (private.is_admin() or user_id = auth.uid() or private.leads_group(group_id));
create policy leaders_insert_admin on public.group_leaders for insert to authenticated with check (private.is_admin());
create policy leaders_delete_admin on public.group_leaders for delete to authenticated using (private.is_admin());
create policy memberships_read on public.group_memberships for select to authenticated using (
  private.is_admin() or private.leads_group(group_id) or (user_id = auth.uid() and status = 'active')
);
create policy membership_audit_read on public.membership_audit for select to authenticated using (private.is_admin() or private.leads_group(group_id));

-- Controlled mutation ensures audit, prevents unauthorised scope escalation and
-- treats membership deletion separately from the user's profile/history.
create function public.manage_group_membership(target_group uuid, target_user uuid, action text)
returns void language plpgsql security definer set search_path = '' as $$
declare current_status text;
begin
  if auth.uid() is null or not (private.is_admin() or private.leads_group(target_group)) then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if action is null or action not in ('add', 'archive', 'restore', 'delete') then
    raise exception 'Invalid membership action' using errcode = '22023';
  end if;
  if action = 'add' then
    -- A leader may place an already-visible trainee in another group they lead,
    -- but cannot grant themselves visibility of a random unrelated account.
    if not private.is_admin() and not private.can_view_profile(target_user) then
      raise exception 'Trainee is not in your authorised scope' using errcode = '42501';
    end if;
    if not exists (select 1 from public.user_roles r where r.user_id = target_user and r.role = 'trainee') then
      raise exception 'Target must be a trainee' using errcode = '22023';
    end if;
    insert into public.group_memberships (group_id, user_id) values (target_group, target_user);
  else
    select status into current_status from public.group_memberships m
    where m.group_id = target_group and m.user_id = target_user for update;
    if not found then raise exception 'Membership not found' using errcode = '22023'; end if;
    if action = 'archive' and current_status = 'active' then
      update public.group_memberships set status = 'archived', updated_at = now() where group_id = target_group and user_id = target_user;
    elsif action = 'restore' and current_status = 'archived' then
      update public.group_memberships set status = 'active', updated_at = now() where group_id = target_group and user_id = target_user;
    elsif action = 'delete' then
      delete from public.group_memberships where group_id = target_group and user_id = target_user;
    else
      raise exception 'Invalid membership state' using errcode = '22023';
    end if;
  end if;
  insert into public.membership_audit (group_id, user_id, actor_id, action) values (target_group, target_user, auth.uid(), action);
end;
$$;
revoke all on function public.manage_group_membership(uuid, uuid, text) from public, anon;
grant execute on function public.manage_group_membership(uuid, uuid, text) to authenticated;
commit;
