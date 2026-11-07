-- Published titles/descriptions are a catalogue for active leaders. Course
-- content remains protected until a course is assigned within their scope.
begin;
create function public.list_published_course_catalog() returns table(id uuid, title text, description text)
language sql stable security definer set search_path='' as $$
  select c.id,c.title,c.description from public.courses c
  where c.status='published' and (private.is_admin() or exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.role='leader'));
$$;
revoke all on function public.list_published_course_catalog() from public,anon;
grant execute on function public.list_published_course_catalog() to authenticated;
commit;
