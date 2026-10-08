-- Additive update for projects that already ran supabase/schema.sql.
-- Safe to run more than once; do not rerun schema.sql on an existing project.

insert into public.skill_paths (title, tag, description, resource_url)
select seed.title, seed.tag, seed.description, seed.resource_url
from (values
  ('Flutter learning pathway', 'App development',
   'Build cross-platform apps with Flutter. Start with the official learning pathway.',
   'https://docs.flutter.dev/get-started/learn-flutter'),
  ('Dart language tour', 'Programming',
   'Learn Dart syntax, collections, functions, and asynchronous programming.',
   'https://dart.dev/language'),
  ('GitHub Skills', 'Developer tools',
   'Practice GitHub workflows through short, interactive courses.',
   'https://skills.github.com/'),
  ('freeCodeCamp curriculum', 'Web development',
   'Explore free, self-paced programming and web development certifications.',
   'https://www.freecodecamp.org/learn/'),
  ('Microsoft Learn', 'Technology',
   'Browse free learning paths for cloud, software, data, and security.',
   'https://learn.microsoft.com/training/')
) as seed(title, tag, description, resource_url)
where not exists (
  select 1
  from public.skill_paths existing
  where existing.title = seed.title
);

create or replace function public.create_direct_chat(target_user uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  direct_chat_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in to start a direct chat';
  end if;
  if target_user is null or target_user = auth.uid() then
    raise exception 'Choose another student to start a direct chat';
  end if;
  if not exists (
    select 1 from public.profiles where id = target_user
  ) then
    raise exception 'The selected student profile does not exist';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      least(auth.uid()::text, target_user::text) || ':' ||
      greatest(auth.uid()::text, target_user::text),
      0
    )
  );

  select c.id into direct_chat_id
  from public.chats c
  join public.chat_members mine on mine.chat_id = c.id
  join public.chat_members theirs on theirs.chat_id = c.id
  where c.is_group = false
    and mine.user_id = auth.uid()
    and theirs.user_id = target_user
    and (
      select count(*)
      from public.chat_members all_members
      where all_members.chat_id = c.id
    ) = 2
  order by c.created_at, c.id
  limit 1;

  if direct_chat_id is null then
    insert into public.chats (created_by, is_group, name)
    values (auth.uid(), false, 'Direct message')
    returning id into direct_chat_id;

    insert into public.chat_members (chat_id, user_id)
    values (direct_chat_id, auth.uid()), (direct_chat_id, target_user);
  end if;

  return direct_chat_id;
end;
$$;

revoke all on function public.create_direct_chat(uuid) from public, anon;
grant execute on function public.create_direct_chat(uuid) to authenticated;
