-- Self-reported text reading progress, not course completion or certification.
begin;
create table public.course_block_progress (
  user_id uuid not null references public.profiles(id) on delete restrict,
  block_id uuid not null references public.course_blocks(id) on delete restrict,
  marked_at timestamptz not null default now(),
  primary key (user_id, block_id)
);
create index course_block_progress_block_id_idx on public.course_block_progress (block_id);
alter table public.course_block_progress enable row level security;
revoke all on public.course_block_progress from public, anon, authenticated;
grant select on public.course_block_progress to authenticated;
create policy block_progress_read on public.course_block_progress for select to authenticated
  using (private.can_view_profile(user_id));

-- Only the assigned person can mark/unmark their own published text block.
-- Existing timestamps survive repeated mark calls; removing a mark deletes only
-- that self-reported indicator, not the user's assignment or other history.
create function public.set_text_block_read(target_block uuid, is_read boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or is_read is null or not exists (
    select 1 from public.course_blocks b
    join public.course_modules m on m.id = b.module_id
    join public.courses c on c.id = m.course_id and c.status = 'published'
    join public.course_assignments a on a.course_id = c.id and a.user_id = auth.uid()
    where b.id = target_block and private.assignment_is_active(a.id)
  ) then
    raise exception 'An active assignment is required to update your reading progress' using errcode = '42501';
  end if;
  if is_read then
    insert into public.course_block_progress (user_id, block_id)
    values (auth.uid(), target_block) on conflict (user_id, block_id) do nothing;
  else
    delete from public.course_block_progress where user_id = auth.uid() and block_id = target_block;
  end if;
end; $$;
revoke all on function public.set_text_block_read(uuid, boolean) from public, anon;
grant execute on function public.set_text_block_read(uuid, boolean) to authenticated;
commit;
