-- Remove the student-ID signup gate and create a profile automatically when
-- Supabase Auth creates an account, including email-confirmed registrations.

drop trigger if exists trg_check_student_id on public.profiles;
drop function if exists public.check_student_id();

update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) - 'student_id'
where coalesce(raw_user_meta_data, '{}'::jsonb) ? 'student_id';

alter table public.profiles drop column if exists student_id;
drop table if exists public.verified_student_ids;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(split_part(new.email, '@', 1), ''),
      'KNUST Student'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_auth_user()
  from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

insert into public.profiles (id, display_name)
select
  u.id,
  coalesce(
    nullif(btrim(u.raw_user_meta_data ->> 'display_name'), ''),
    nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
    nullif(split_part(u.email, '@', 1), ''),
    'KNUST Student'
  )
from auth.users u
on conflict (id) do nothing;

revoke insert, update on public.profiles from anon, authenticated;
grant insert (
  id, display_name, faculty, department, year_group, interests, avatar_url
) on public.profiles to authenticated;
grant update (
  display_name, faculty, department, year_group, interests, avatar_url
) on public.profiles to authenticated;

notify pgrst, 'reload schema';
