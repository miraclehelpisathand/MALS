-- Administrators may label test profiles without changing IDs or timestamps.
begin;
grant update (display_name) on public.profiles to authenticated;
create policy profiles_update_admin on public.profiles for update to authenticated
  using (private.is_admin()) with check (private.is_admin());
commit;
