-- Live GPS is limited to manually assigned, approved shuttle operators.
-- Add a row to shuttle_operators using the Supabase SQL editor to authorize a driver.
create table if not exists public.shuttle_operators (
  vehicle_id text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  label text not null,
  route text not null check (route in ('green', 'gold')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.live_shuttle_locations (
  vehicle_id text primary key
    references public.shuttle_operators(vehicle_id) on delete cascade,
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

alter table public.live_shuttle_locations
  add column if not exists label text;
update public.live_shuttle_locations location
set label = operator.label
from public.shuttle_operators operator
where operator.vehicle_id = location.vehicle_id
  and location.label is null;
alter table public.live_shuttle_locations alter column label set not null;

create index if not exists live_shuttle_locations_updated_at_idx
  on public.live_shuttle_locations (updated_at desc) where is_active;

alter table public.shuttle_operators enable row level security;
alter table public.live_shuttle_locations enable row level security;

drop policy if exists "operators can view their own assignment"
  on public.shuttle_operators;
create policy "operators can view their own assignment"
  on public.shuttle_operators for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "signed-in students can view live shuttle locations"
  on public.live_shuttle_locations;
create policy "signed-in students can view live shuttle locations"
  on public.live_shuttle_locations for select to authenticated using (true);

drop policy if exists "approved operators publish their assigned vehicle location"
  on public.live_shuttle_locations;
create policy "approved operators publish their assigned vehicle location"
  on public.live_shuttle_locations for insert to authenticated
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

drop policy if exists "approved operators update their assigned vehicle location"
  on public.live_shuttle_locations;
create policy "approved operators update their assigned vehicle location"
  on public.live_shuttle_locations for update to authenticated
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

revoke all on public.shuttle_operators from anon, authenticated;
grant select on public.shuttle_operators to authenticated;
revoke all on public.live_shuttle_locations from anon, authenticated;
grant select, insert, update on public.live_shuttle_locations to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'live_shuttle_locations'
  ) then
    alter publication supabase_realtime
      add table public.live_shuttle_locations;
  end if;
end;
$$;

-- CWA uses credit-weighted percentage marks. Preserve old letter-grade rows
-- but leave them unscored until the student enters the actual course mark.
do $$
begin
  if to_regclass('public.gpa_records') is not null
     and to_regclass('public.cwa_records') is null then
    alter table public.gpa_records rename to cwa_records;
  end if;
end;
$$;

alter table public.cwa_records
  add column if not exists score numeric
  check (score is null or score between 0 and 100);

alter table public.cwa_records alter column grade drop not null;
drop policy if exists "students manage their gpa records"
  on public.cwa_records;
drop policy if exists "students manage their cwa records"
  on public.cwa_records;
create policy "students manage their cwa records"
  on public.cwa_records for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'cwa_records'
  ) then
    alter publication supabase_realtime add table public.cwa_records;
  end if;
end;
$$;

notify pgrst, 'reload schema';
