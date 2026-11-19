-- Tensor Sports League: database schema for Supabase (Postgres)
-- Run this in Supabase Dashboard -> SQL Editor -> New query.

-- ---------- Tables ----------

create table sports (
  id   bigint generated always as identity primary key,
  name text not null unique              -- e.g. 'Football', 'Cricket'
);

create table teams (
  id       bigint generated always as identity primary key,
  name     text not null,
  sport_id bigint not null references sports(id) on delete cascade,
  unique (name, sport_id)
);

-- An "event" is a tournament or fixture day that groups matches and photos.
create table events (
  id          bigint generated always as identity primary key,
  title       text not null,
  description text,
  event_date  date not null,
  created_at  timestamptz not null default now()
);

create table matches (
  id           bigint generated always as identity primary key,
  event_id     bigint references events(id) on delete set null,
  sport_id     bigint not null references sports(id),
  home_team_id bigint not null references teams(id),
  away_team_id bigint not null references teams(id),
  home_score   int not null default 0,
  away_score   int not null default 0,
  status       text not null default 'scheduled'
               check (status in ('scheduled', 'live', 'finished')),
  venue        text,
  starts_at    timestamptz not null,
  updated_at   timestamptz not null default now(),
  check (home_team_id <> away_team_id)
);

create table event_photos (
  id           bigint generated always as identity primary key,
  event_id     bigint not null references events(id) on delete cascade,
  storage_path text not null,            -- file path inside the 'event-photos' bucket
  caption      text,
  uploaded_by  uuid references auth.users(id),
  created_at   timestamptz not null default now()
);

-- Users listed here are admins (the people who can post scores and photos).
create table admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- ---------- Admin check ----------

create function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------- Row Level Security: everyone reads, only admins write ----------

alter table sports       enable row level security;
alter table teams        enable row level security;
alter table events       enable row level security;
alter table matches      enable row level security;
alter table event_photos enable row level security;
alter table admins       enable row level security;  -- no policies = nobody can read it via the API

create policy "public read sports"  on sports       for select using (true);
create policy "public read teams"   on teams        for select using (true);
create policy "public read events"  on events       for select using (true);
create policy "public read matches" on matches      for select using (true);
create policy "public read photos"  on event_photos for select using (true);

create policy "admin write sports"  on sports       for all using (is_admin()) with check (is_admin());
create policy "admin write teams"   on teams        for all using (is_admin()) with check (is_admin());
create policy "admin write events"  on events       for all using (is_admin()) with check (is_admin());
create policy "admin write matches" on matches      for all using (is_admin()) with check (is_admin());
create policy "admin write photos"  on event_photos for all using (is_admin()) with check (is_admin());

-- ---------- Live updates ----------
-- Lets the website receive score changes instantly.
alter publication supabase_realtime add table matches;

-- ---------- Photo storage bucket ----------

insert into storage.buckets (id, name, public)
values ('event-photos', 'event-photos', true)
on conflict (id) do nothing;

create policy "admin upload event photos" on storage.objects
  for insert with check (bucket_id = 'event-photos' and public.is_admin());

create policy "admin delete event photos" on storage.objects
  for delete using (bucket_id = 'event-photos' and public.is_admin());

-- ---------- After running this ----------
-- 1. Sign up once in your app (or Supabase Dashboard -> Authentication -> Users).
-- 2. Copy your user's UUID and make yourself admin:
--      insert into admins (user_id) values ('PASTE-YOUR-USER-UUID-HERE');
