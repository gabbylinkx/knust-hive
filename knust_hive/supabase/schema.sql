-- ============================================================
-- KNUST Hive — Supabase schema
-- Run in the Supabase SQL editor, top to bottom, on a fresh project.
-- ============================================================

create extension if not exists "uuid-ossp";
create extension if not exists "btree_gist";

-- ---------- Profiles (extends auth.users) ----------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  faculty text,
  department text,
  year_group int,
  interests text[] default '{}',
  avatar_url text,
  is_admin boolean not null default false,
  created_at timestamptz default now()
);

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

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---------- Stops (shuttle) ----------
create table stops (
  id text primary key,
  name text not null,
  route text not null check (route in ('green', 'gold')),
  lat double precision,   -- nullable until GPS survey is done
  lng double precision,
  is_hub boolean default false
);

-- ---------- Shuttle sightings (crowdsourced) ----------
create table shuttle_reports (
  id uuid primary key default uuid_generate_v4(),
  stop_id text not null references stops(id),
  route text not null check (route in ('green', 'gold')),
  reported_by uuid not null references profiles(id),
  created_at timestamptz default now()
);
create index on shuttle_reports (created_at desc);

-- ---------- Approved shuttle operators and live vehicle GPS ----------
create table shuttle_operators (
  vehicle_id text primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  label text not null,
  route text not null check (route in ('green', 'gold')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table live_shuttle_locations (
  vehicle_id text primary key references shuttle_operators(vehicle_id) on delete cascade,
  label text not null,
  route text not null check (route in ('green', 'gold')),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  heading double precision check (heading is null or heading between 0 and 360),
  speed_meters_per_second double precision check (
    speed_meters_per_second is null or speed_meters_per_second >= 0
  ),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);
create index on live_shuttle_locations (updated_at desc) where is_active;

-- ---------- Ride board ----------
create table ride_posts (
  id uuid primary key default uuid_generate_v4(),
  type text not null check (type in ('need', 'offer')),
  from_stop_id text not null references stops(id),
  to_stop_id text not null references stops(id),
  time_label text not null,
  note text,
  posted_by uuid not null references profiles(id),
  created_at timestamptz default now()
);

-- ---------- Campus feed ----------
create table feed_posts (
  id uuid primary key default uuid_generate_v4(),
  category text not null check (category in ('event', 'lostFound', 'shoutout', 'studyGroup')),
  text text not null,
  posted_by uuid not null references profiles(id),
  rsvp_count int default 0,
  created_at timestamptz default now()
);

create table event_rsvps (
  post_id uuid references feed_posts(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  primary key (post_id, user_id)
);

-- ---------- Communities ----------
create table communities (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  description text
);

create table community_members (
  community_id uuid references communities(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  primary key (community_id, user_id)
);

-- ---------- Chat ----------
create table chats (
  id uuid primary key default uuid_generate_v4(),
  created_by uuid references profiles(id) on delete set null,
  is_group boolean default false,
  is_anonymous_wall boolean default false, -- confession wall
  name text,
  created_at timestamptz default now()
);

create table chat_members (
  chat_id uuid references chats(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  primary key (chat_id, user_id)
);

create table messages (
  id uuid primary key default uuid_generate_v4(),
  chat_id uuid references chats(id) on delete cascade,
  sender_id uuid references profiles(id),
  text text not null,
  message_type text not null default 'text'
    check (message_type in ('text', 'image', 'video', 'audio', 'file')),
  attachment_path text,
  file_name text,
  mime_type text,
  flagged boolean default false, -- set by moderation function before showing on wall
  created_at timestamptz default now(),
  unique (id, chat_id),
  check (
    (message_type = 'text' and attachment_path is null)
    or (message_type <> 'text' and attachment_path is not null)
  )
);
create index on messages (chat_id, created_at);

create table message_reactions (
  id uuid primary key default uuid_generate_v4(),
  message_id uuid not null,
  chat_id uuid not null,
  user_id uuid not null references profiles(id) on delete cascade,
  emoji text not null check (emoji in ('❤️', '😂', '😮', '😢', '🔥', '👍')),
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji),
  foreign key (message_id, chat_id)
    references messages(id, chat_id) on delete cascade
);
create index on message_reactions (chat_id, message_id);

-- ---------- Skills ----------
create table skill_paths (
  id uuid primary key default uuid_generate_v4(),
  title text not null,
  tag text,
  description text,
  resource_url text
);

insert into skill_paths (title, tag, description, resource_url)
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
  select 1 from skill_paths existing where existing.title = seed.title
);

create table user_skill_progress (
  user_id uuid references profiles(id) on delete cascade,
  skill_id uuid references skill_paths(id) on delete cascade,
  status text default 'started' check (status in ('started', 'completed')),
  updated_at timestamptz default now(),
  primary key (user_id, skill_id)
);

create table mentorships (
  mentor_id uuid references profiles(id),
  mentee_id uuid references profiles(id),
  status text default 'pending' check (status in ('pending', 'active', 'ended')),
  created_at timestamptz default now(),
  primary key (mentor_id, mentee_id)
);

-- ---------- Academics ----------
create table timetable_entries (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references profiles(id) on delete cascade,
  course_name text not null,
  day_of_week int not null check (day_of_week between 0 and 6),
  start_time time not null,
  end_time time not null,
  room text,
  check (end_time > start_time),
  -- prevents two entries for the same user overlapping in time
  exclude using gist (
    user_id with =,
    day_of_week with =,
    tsrange('2000-01-01'::date + start_time, '2000-01-01'::date + end_time) with &&
  )
);

create table cwa_records (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references profiles(id) on delete cascade,
  course_code text not null,
  credit_hours numeric not null check (credit_hours > 0),
  grade text check (grade in ('A', 'B+', 'B', 'C+', 'C', 'D+', 'D', 'F')),
  score numeric check (score is null or score between 0 and 100),
  semester text not null
);

-- ---------- Marketplace ----------
create table marketplace_listings (
  id uuid primary key default uuid_generate_v4(),
  seller_id uuid references profiles(id),
  title text not null,
  price numeric check (price is null or price >= 0),
  description text,
  image_url text,
  status text default 'available' check (status in ('available', 'sold')),
  created_at timestamptz default now()
);

-- ---------- Past questions repository ----------
create table past_questions (
  id uuid primary key default uuid_generate_v4(),
  course_code text not null,
  year int,
  file_url text not null, -- Supabase Storage path
  uploaded_by uuid references profiles(id)
);

create table moderation_reports (
  id uuid primary key default uuid_generate_v4(),
  reporter_id uuid not null references profiles(id) on delete cascade,
  content_type text not null check (content_type in ('feed_post', 'message', 'marketplace_listing')),
  content_id uuid not null,
  reason text not null check (char_length(reason) between 3 and 500),
  status text not null default 'open' check (status in ('open', 'resolved')),
  resolved_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
create index on moderation_reports (status, created_at desc);

-- ============================================================
-- Row Level Security
-- ============================================================
alter table profiles enable row level security;
alter table stops enable row level security;
alter table shuttle_reports enable row level security;
alter table shuttle_operators enable row level security;
alter table live_shuttle_locations enable row level security;
alter table ride_posts enable row level security;
alter table feed_posts enable row level security;
alter table messages enable row level security;
alter table message_reactions enable row level security;
alter table chat_members enable row level security;
alter table communities enable row level security;
alter table community_members enable row level security;
alter table chats enable row level security;
alter table timetable_entries enable row level security;
alter table cwa_records enable row level security;
alter table marketplace_listings enable row level security;
alter table past_questions enable row level security;
alter table mentorships enable row level security;
alter table user_skill_progress enable row level security;
alter table event_rsvps enable row level security;
alter table moderation_reports enable row level security;
alter table skill_paths enable row level security;

create policy "profiles are viewable by any signed-in student"
  on profiles for select using (auth.role() = 'authenticated');
create policy "users manage their own profile"
  on profiles for update using (auth.uid() = id);
create policy "users create their own profile"
  on profiles for insert with check (auth.uid() = id);
-- Do not allow a client to promote its own account to moderator.
revoke insert, update on profiles from anon, authenticated;
grant insert (id, display_name, faculty, department, year_group, interests, avatar_url)
  on profiles to authenticated;
grant update (display_name, faculty, department, year_group, interests, avatar_url)
  on profiles to authenticated;

create policy "signed-in students can view shuttle stops"
  on stops for select to authenticated using (true);
create policy "students can view skill resources"
  on skill_paths for select to authenticated using (true);

create policy "reports viewable by all, insertable by owner"
  on shuttle_reports for select using (true);
create policy "reports insertable by signed-in students"
  on shuttle_reports for insert with check (auth.uid() = reported_by);

create policy "operators can view their own assignment"
  on shuttle_operators for select to authenticated
  using (user_id = auth.uid());
create policy "signed-in students can view live shuttle locations"
  on live_shuttle_locations for select to authenticated using (true);
create policy "approved operators publish their assigned vehicle location"
  on live_shuttle_locations for insert to authenticated
  with check (
    exists (
      select 1 from public.shuttle_operators so
      where so.vehicle_id = live_shuttle_locations.vehicle_id
        and so.user_id = auth.uid()
        and so.route = live_shuttle_locations.route
        and so.label = live_shuttle_locations.label
        and so.is_active
    )
  );
create policy "approved operators update their assigned vehicle location"
  on live_shuttle_locations for update to authenticated
  using (
    exists (
      select 1 from public.shuttle_operators so
      where so.vehicle_id = live_shuttle_locations.vehicle_id
        and so.user_id = auth.uid()
        and so.is_active
    )
  )
  with check (
    exists (
      select 1 from public.shuttle_operators so
      where so.vehicle_id = live_shuttle_locations.vehicle_id
        and so.user_id = auth.uid()
        and so.route = live_shuttle_locations.route
        and so.label = live_shuttle_locations.label
        and so.is_active
    )
  );

revoke all on shuttle_operators from anon, authenticated;
grant select on shuttle_operators to authenticated;
revoke all on live_shuttle_locations from anon, authenticated;
grant select, insert, update on live_shuttle_locations to authenticated;

create policy "ride posts viewable by all"
  on ride_posts for select using (true);
create policy "ride posts insertable by owner"
  on ride_posts for insert with check (auth.uid() = posted_by);
create policy "ride posts deletable by owner"
  on ride_posts for delete using (auth.uid() = posted_by);

create policy "feed viewable by all"
  on feed_posts for select using (true);
create policy "feed insertable by owner"
  on feed_posts for insert with check (auth.uid() = posted_by);
create policy "feed deletable by owner"
  on feed_posts for delete using (auth.uid() = posted_by);

create policy "messages viewable only by chat members"
  on messages for select using (
    exists (select 1 from chat_members cm where cm.chat_id = messages.chat_id and cm.user_id = auth.uid())
  );
create policy "messages insertable only by chat members"
  on messages for insert with check (
    exists (select 1 from chat_members cm where cm.chat_id = messages.chat_id and cm.user_id = auth.uid())
  );

-- SECURITY DEFINER helpers avoid recursive RLS lookups while testing
-- membership and moderator roles. The function owner must be a trusted
-- database role; clients receive execute permission only.
create or replace function public.is_chat_member(target_chat uuid)
returns boolean
language sql stable security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = auth.uid()
  );
$$;

create or replace function public.is_moderator()
returns boolean
language sql stable security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and is_admin
  );
$$;

revoke all on function public.is_chat_member(uuid) from public;
revoke all on function public.is_moderator() from public;
grant execute on function public.is_chat_member(uuid) to authenticated;
grant execute on function public.is_moderator() to authenticated;

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
  if not exists (select 1 from public.profiles where id = target_user) then
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
    and (select count(*) from public.chat_members all_members
         where all_members.chat_id = c.id) = 2
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

create policy "communities are readable by signed-in students"
  on communities for select to authenticated using (true);
create policy "students create communities"
  on communities for insert to authenticated with check (true);

create policy "students view their own memberships"
  on community_members for select to authenticated
  using (user_id = auth.uid());
create policy "students join themselves"
  on community_members for insert to authenticated
  with check (user_id = auth.uid());
create policy "students leave themselves"
  on community_members for delete to authenticated
  using (user_id = auth.uid());

create policy "members view their chats"
  on chats for select to authenticated
  using (created_by = auth.uid() or public.is_chat_member(id));
create policy "students create chats"
  on chats for insert to authenticated
  with check (created_by = auth.uid());

create policy "members view chat memberships"
  on chat_members for select to authenticated
  using (user_id = auth.uid() or public.is_chat_member(chat_id));
create policy "chat creators add group members"
  on chat_members for insert to authenticated
  with check (
    exists (
      select 1 from public.chats c
      where c.id = chat_id
        and c.created_by = auth.uid()
        and c.is_group = true
    )
  );
create policy "chat creators remove members"
  on chat_members for delete to authenticated
  using (
    exists (
      select 1 from public.chats c
      where c.id = chat_id and c.created_by = auth.uid()
    )
  );

drop policy if exists "messages viewable only by chat members" on messages;
create policy "messages viewable only by chat members"
  on messages for select to authenticated
  using (public.is_chat_member(chat_id));
drop policy if exists "messages insertable only by chat members" on messages;
create policy "messages insertable only by chat members"
  on messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_chat_member(chat_id)
    and (
      attachment_path is null
      or (
        (storage.foldername(attachment_path))[1] = chat_id::text
        and (storage.foldername(attachment_path))[2] = auth.uid()::text
      )
    )
  );
create policy "senders delete their own chat messages"
  on messages for delete to authenticated
  using (sender_id = auth.uid() and public.is_chat_member(chat_id));

create policy "chat members read message reactions"
  on message_reactions for select to authenticated
  using (public.is_chat_member(chat_id));
create policy "chat members add their own message reactions"
  on message_reactions for insert to authenticated
  with check (user_id = auth.uid() and public.is_chat_member(chat_id));
create policy "students remove their own message reactions"
  on message_reactions for delete to authenticated
  using (user_id = auth.uid() and public.is_chat_member(chat_id));
grant delete on messages to authenticated;
grant select, insert, delete on message_reactions to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'chat-media',
  'chat-media',
  false,
  26214400,
  array[
    'image/jpeg', 'image/png', 'image/gif', 'image/webp',
    'video/mp4', 'video/webm', 'video/quicktime',
    'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/webm', 'audio/wav',
    'application/pdf', 'text/plain', 'text/csv',
    'application/rtf', 'application/zip',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "chat members upload their own media"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.is_chat_member((storage.foldername(name))[1]::uuid)
  );
create policy "chat members read chat media"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat-media'
    and public.is_chat_member((storage.foldername(name))[1]::uuid)
  );
create policy "senders delete their own chat media"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.is_chat_member((storage.foldername(name))[1]::uuid)
  );

create policy "students manage their timetable"
  on timetable_entries for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "students manage their cwa records"
  on cwa_records for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "students view marketplace listings"
  on marketplace_listings for select to authenticated using (true);
create policy "students create their listings"
  on marketplace_listings for insert to authenticated
  with check (seller_id = auth.uid());
create policy "sellers update their listings"
  on marketplace_listings for update to authenticated
  using (seller_id = auth.uid()) with check (seller_id = auth.uid());
create policy "sellers delete their listings"
  on marketplace_listings for delete to authenticated using (seller_id = auth.uid());

create policy "students read past questions"
  on past_questions for select to authenticated using (true);
create policy "students share past questions"
  on past_questions for insert to authenticated
  with check (uploaded_by = auth.uid());
create policy "students remove their past questions"
  on past_questions for delete to authenticated using (uploaded_by = auth.uid());

create policy "participants read mentorships"
  on mentorships for select to authenticated
  using (mentor_id = auth.uid() or mentee_id = auth.uid());
create policy "students request mentorship"
  on mentorships for insert to authenticated
  with check (mentee_id = auth.uid() and mentor_id <> auth.uid());
create policy "mentors respond to mentorship"
  on mentorships for update to authenticated
  using (mentor_id = auth.uid()) with check (mentor_id = auth.uid());

create policy "students manage their skill progress"
  on user_skill_progress for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "students manage their own rsvps"
  on event_rsvps for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "students submit moderation reports"
  on moderation_reports for insert to authenticated
  with check (reporter_id = auth.uid());
create policy "moderators review moderation reports"
  on moderation_reports for select to authenticated
  using (public.is_moderator());
create policy "moderators resolve moderation reports"
  on moderation_reports for update to authenticated
  using (public.is_moderator())
  with check (public.is_moderator() and resolved_by = auth.uid());
revoke update on moderation_reports from authenticated;
grant update (status, resolved_by) on moderation_reports to authenticated;

-- ============================================================
-- Enable Realtime on the tables the app streams from
-- ============================================================
alter publication supabase_realtime add table shuttle_reports;
alter publication supabase_realtime add table live_shuttle_locations;
alter publication supabase_realtime add table ride_posts;
alter publication supabase_realtime add table feed_posts;
alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table message_reactions;
alter publication supabase_realtime add table chat_members;
alter publication supabase_realtime add table timetable_entries;
alter publication supabase_realtime add table cwa_records;
alter publication supabase_realtime add table communities;
alter publication supabase_realtime add table marketplace_listings;
alter publication supabase_realtime add table past_questions;
alter publication supabase_realtime add table moderation_reports;

-- ============================================================
-- Seed: campus stops
-- ============================================================
insert into stops (id, name, route, is_hub) values
  ('g0', 'Main Gate', 'green', false),
  ('g1', 'Republic Hall', 'green', false),
  ('g2', 'Katanga', 'green', false),
  ('hub', 'Commercial Area', 'green', true),
  ('g3', 'Engineering', 'green', false),
  ('g4', 'Business School', 'green', false),
  ('g5', 'Conti Campus', 'green', false),
  ('y0', 'Bomso Gate', 'gold', false),
  ('y1', 'Ayeduase Gate', 'gold', false),
  ('y2', 'Unity Hall', 'gold', false),
  ('y3', 'Africa Hall', 'gold', false),
  ('y4', 'Queens Hall', 'gold', false),
  ('y5', 'Univ. Hospital', 'gold', false)
on conflict (id) do nothing;
