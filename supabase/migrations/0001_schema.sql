-- Roam — core schema
-- Run order: 0001_schema -> 0002_functions -> 0003_rls -> 0004_realtime -> 0005_auth_hook
--
-- Two design notes that everything else depends on:
--
--   1. Every geography column has generated lat/lng companions. PostgREST returns
--      geography as hex EWKB, which is useless to the browser and to Realtime
--      payloads. The generated columns mean the map gets plain numbers with zero
--      parsing on either side, so there is no decode step in the live path.
--
--   2. profiles.id is NOT auth.users.id. Guides are seeded rows with no auth user
--      (the guide side is simulated for the demo), so we keep an optional
--      auth_user_id link instead of forcing every profile through GoTrue.

create extension if not exists postgis;
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;   -- event dedupe across ticket sources

create type actor_role       as enum ('traveler', 'guide');
-- 'boat' is not a novelty: Venice has no cars, so the vaporetto IS the vehicle.
-- Three demo cities, three transport realities, one system.
create type travel_mode      as enum ('walk', 'drive', 'boat');
create type ride_status      as enum ('requested', 'matched', 'enroute', 'active', 'completed', 'cancelled');
create type narration_subject as enum ('place', 'event', 'ride_intro');

-- ------------------------------------------------------------------ cities --

-- Roam is global — the map renders anywhere on earth. Cities exist because
-- seeded guides and cached places have to live somewhere, not because the
-- product is scoped to them. Adding a city is a row plus an Overpass fetch.
create table cities (
  id           uuid primary key default gen_random_uuid(),
  slug         text unique not null,
  name         text not null,
  country      text not null,
  center       geography(Point, 4326) not null,
  center_lat   double precision generated always as (st_y(center::geometry)) stored,
  center_lng   double precision generated always as (st_x(center::geometry)) stored,
  default_mode travel_mode not null default 'walk',
  modes        travel_mode[] not null default '{walk}',
  locales      text[] not null default '{en}',
  bbox_min_lng double precision not null,
  bbox_min_lat double precision not null,
  bbox_max_lng double precision not null,
  bbox_max_lat double precision not null,
  tagline      text
);

create index cities_center_idx on cities using gist (center);

-- ---------------------------------------------------------------- profiles --

create table profiles (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete set null,
  role         actor_role  not null default 'traveler',
  display_name text        not null,
  avatar_url   text,
  bio          text,
  languages    text[]      not null default '{}',
  created_at   timestamptz not null default now()
);

create index profiles_auth_user_id_idx on profiles (auth_user_id);

create table guide_profiles (
  profile_id        uuid primary key references profiles (id) on delete cascade,
  headline          text          not null,
  modes             travel_mode[] not null default '{walk}',
  specialties       text[]        not null default '{}',
  hourly_rate_cents integer       not null default 0,
  rating            numeric(2, 1) not null default 5.0,
  rides_completed   integer       not null default 0,
  verified          boolean       not null default false,
  home_point        geography(Point, 4326) not null,
  home_lat          double precision generated always as (st_y(home_point::geometry)) stored,
  home_lng          double precision generated always as (st_x(home_point::geometry)) stored
);

create index guide_profiles_home_idx        on guide_profiles using gist (home_point);
create index guide_profiles_specialties_idx on guide_profiles using gin (specialties);

-- Live presence. One row per guide, updated in place (never appended to) so the
-- "who is available near me" query stays a single index scan.
create table guide_status (
  guide_id   uuid primary key references guide_profiles (profile_id) on delete cascade,
  is_online  boolean not null default false,
  last_point geography(Point, 4326),
  lat        double precision generated always as (st_y(last_point::geometry)) stored,
  lng        double precision generated always as (st_x(last_point::geometry)) stored,
  heading    double precision,
  updated_at timestamptz not null default now()
);

create index guide_status_last_point_idx on guide_status using gist (last_point);

-- ------------------------------------------------------------------ places --

-- Sourced from Overpass ahead of demo day via scripts/fetch_places.py and frozen
-- into seed SQL. Nothing calls Overpass while judges are watching.
create table places (
  id          uuid primary key default gen_random_uuid(),
  city_id     uuid references cities (id) on delete set null,
  name        text not null,
  category    text not null,          -- eat · beach · attraction · hike · culture · viewpoint · market · essentials
  themes      text[] not null default '{}',
  blurb       text,                   -- Tavily-enriched at build time
  known_for   text,
  hidden_gem  boolean not null default false,
  point       geography(Point, 4326) not null,
  lat         double precision generated always as (st_y(point::geometry)) stored,
  lng         double precision generated always as (st_x(point::geometry)) stored,
  -- wifi (OSM internet_access=*) — the utility layer
  has_wifi    boolean not null default false,
  wifi_fee    text,                   -- 'no' (free) · 'yes' · 'customers'
  wifi_ssid   text,
  -- accessibility (OSM wheelchair=*) — Track 4 claim, free from the same fetch
  wheelchair  text,                   -- 'yes' · 'limited' · 'no'
  opening_hours text,
  stay22_url  text,                   -- sponsor: monetized stays nearby
  source      text not null default 'overpass',
  osm_id      bigint,
  created_at  timestamptz not null default now()
);

create index places_point_idx    on places using gist (point);
create index places_category_idx on places (category);
create index places_themes_idx   on places using gin (themes);
create index places_wifi_idx     on places (has_wifi) where has_wifi;
create unique index places_osm_id_key on places (osm_id) where osm_id is not null;

-- ------------------------------------------------------------------ events --

-- Source-agnostic on purpose: ticketmaster · seatgeek · city open data ·
-- guide-posted. Adding a source is an ingestion adapter, not a schema change.
create table events (
  id              uuid primary key default gen_random_uuid(),
  city_id         uuid references cities (id) on delete set null,
  source          text not null,      -- 'ticketmaster' · 'seatgeek' · 'guide' · 'manual'
  source_event_id text,
  name            text not null,
  category        text not null,      -- music · sports · theater · festival · market · community
  starts_at       timestamptz not null,
  ends_at         timestamptz,
  venue_name      text,
  point           geography(Point, 4326) not null,
  lat             double precision generated always as (st_y(point::geometry)) stored,
  lng             double precision generated always as (st_x(point::geometry)) stored,
  ticket_url      text,
  stay22_url      text,
  image_url       text,
  price_min_cents integer,
  price_max_cents integer,
  currency        text not null default 'USD',
  blurb           text,
  created_at      timestamptz not null default now()
);

create index events_point_idx  on events using gist (point);
create index events_starts_idx on events (starts_at);
create index events_name_trgm  on events using gin (name gin_trgm_ops);   -- cross-source dedupe
create unique index events_source_key on events (source, source_event_id)
  where source_event_id is not null;

-- ------------------------------------------------------------------- rides --

create table rides (
  id           uuid primary key default gen_random_uuid(),
  traveler_id  uuid not null references profiles (id) on delete cascade,
  guide_id     uuid          references profiles (id) on delete set null,
  status       ride_status not null default 'requested',
  mode         travel_mode not null default 'walk',
  theme        text,
  pickup_point geography(Point, 4326) not null,
  pickup_lat   double precision generated always as (st_y(pickup_point::geometry)) stored,
  pickup_lng   double precision generated always as (st_x(pickup_point::geometry)) stored,
  pickup_label text,
  eta_min      integer,
  price_cents  integer not null default 0,
  requested_at timestamptz not null default now(),
  matched_at   timestamptz,
  started_at   timestamptz,
  ended_at     timestamptz
);

create index rides_traveler_idx on rides (traveler_id, requested_at desc);
create index rides_guide_idx    on rides (guide_id, requested_at desc);

-- A stop is either a place or an event. An event stop is simply a stop with a
-- fixed start time — which is the whole "intertwine events with guides" feature.
create table ride_stops (
  ride_id    uuid    not null references rides (id) on delete cascade,
  seq        integer not null,
  place_id   uuid references places (id) on delete restrict,
  event_id   uuid references events (id) on delete restrict,
  arrived_at timestamptz,
  primary key (ride_id, seq),
  constraint ride_stops_one_subject check (
    (place_id is not null and event_id is null) or
    (place_id is null and event_id is not null)
  )
);

-- Append-only position feed. This is what Realtime broadcasts, so it stays
-- narrow: no joins needed to render a moving dot.
create table ride_positions (
  id          bigserial primary key,
  ride_id     uuid not null references rides (id) on delete cascade,
  actor       actor_role not null,
  point       geography(Point, 4326) not null,
  lat         double precision generated always as (st_y(point::geometry)) stored,
  lng         double precision generated always as (st_x(point::geometry)) stored,
  heading     double precision,
  speed_mps   double precision,
  recorded_at timestamptz not null default now()
);

create index ride_positions_ride_idx on ride_positions (ride_id, recorded_at desc);

-- -------------------------------------------------------------- narrations --

-- ElevenLabs audio, generated at build time and stored in Supabase Storage.
-- The demo plays cached files: no API call while judges are watching.
create table narrations (
  id           uuid primary key default gen_random_uuid(),
  subject_type narration_subject not null,
  subject_id   uuid not null,
  locale       text not null,        -- en · es · zh · hi · ar
  script       text not null,
  audio_url    text not null,
  voice_id     text,
  duration_ms  integer,
  created_at   timestamptz not null default now(),
  unique (subject_type, subject_id, locale)
);

create index narrations_subject_idx on narrations (subject_type, subject_id);

-- ------------------------------------------------------------ wifi reports --

-- Community verification: "does this still work?" Keeps the wifi layer fresh
-- and gives the map a live, user-driven write path.
create table wifi_reports (
  id          uuid primary key default gen_random_uuid(),
  place_id    uuid not null references places (id) on delete cascade,
  profile_id  uuid references profiles (id) on delete set null,
  works       boolean not null,
  note        text,
  created_at  timestamptz not null default now()
);

create index wifi_reports_place_idx on wifi_reports (place_id, created_at desc);

-- ---------------------------------------------------------------- triggers --

-- Keep guide_status in sync with the latest guide ping so the discover screen
-- and the tracking screen never disagree about where a guide is.
create or replace function sync_guide_status_from_position()
returns trigger
language plpgsql
as $$
declare
  v_guide_id uuid;
begin
  if new.actor <> 'guide' then
    return new;
  end if;

  select guide_id into v_guide_id from rides where id = new.ride_id;
  if v_guide_id is null then
    return new;
  end if;

  update guide_status
     set last_point = new.point,
         heading    = new.heading,
         is_online  = true,
         updated_at = now()
   where guide_id = v_guide_id;

  return new;
end;
$$;

create trigger ride_positions_sync_guide_status
  after insert on ride_positions
  for each row execute function sync_guide_status_from_position();
