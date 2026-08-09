-- PART 1 of 4 — Tables, enums, triggers. Run this FIRST.
-- Supabase dashboard -> SQL Editor -> New query -> paste -> Run.
-- Run parts IN ORDER. Wait for each to say Success before the next.

-- ═══ supabase/migrations/0001_schema.sql ═══
-- Japan travel discovery — core schema
--
-- Run order: 0001_schema -> 0002_scoring -> 0003_actions -> 0004_rls
--
-- Four decisions the rest of the engine depends on:
--
--   1. TASTE AND TRIPS ARE SEPARATE. traveler_profiles holds what a person is
--      into, forever. trips hold one journey: this city, these dates, this
--      budget. Conflating them would mean a traveler can only have one trip,
--      editing dates would clobber their interests, and the feed could not work
--      until they committed to travelling — wrong for a product people scroll
--      for inspiration long before they book.
--
--   2. Every geography column carries generated lat/lng companions. PostgREST
--      serialises geography as hex EWKB, which a browser cannot read.
--
--   3. experience_media stores REFERENCES ONLY — a canonical post URL plus
--      attribution. No video bytes are ever copied. Embeds resolve at render
--      time through the official oEmbed endpoints. Legal boundary, not a
--      performance choice.
--
--   4. profiles.id is not auth.users.id. An optional auth_user_id link keeps
--      seeded hosts from needing GoTrue accounts.

create extension if not exists postgis;
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

create type travel_style   as enum ('solo', 'couple', 'family', 'group');
create type budget_level   as enum ('shoestring', 'moderate', 'comfortable', 'splurge');
create type trip_pace      as enum ('relaxed', 'balanced', 'packed');
create type trip_status    as enum ('planning', 'active', 'past');
create type media_kind     as enum ('tiktok', 'instagram', 'youtube', 'hosted_video', 'image', 'placeholder');
create type media_license  as enum ('oembed', 'owned', 'stock', 'placeholder');
create type host_kind      as enum ('local_business', 'community', 'individual', 'venue', 'institution');

-- ---------------------------------------------------------- vocabularies --
-- Tables rather than enums so onboarding renders itself from the API. A
-- hardcoded list in the client drifts from what scoring actually understands.

create table countries (
  code       text primary key,              -- ISO 3166-1 alpha-2
  name_en    text not null,
  emoji      text,
  -- Whether we have real content here yet. Onboarding can offer aspiration
  -- ("where do you like to travel") honestly without pretending to have
  -- inventory everywhere.
  available  boolean not null default false,
  sort       integer not null default 0
);

create table interests (
  slug     text primary key,
  label_en text not null,
  emoji    text,
  sort     integer not null default 0
);

-- Why someone travels, which is a different axis from what they like. Two
-- people can both pick "food" and want completely different trips depending on
-- whether they answered "big night out" or "slow reset".
create table travel_reasons (
  slug     text primary key,
  label_en text not null,
  emoji    text,
  sort     integer not null default 0
);

-- ------------------------------------------------------ places & taxonomy --

create table cities (
  id           uuid primary key default gen_random_uuid(),
  country_code text not null references countries (code),
  slug         text unique not null,
  name_en      text not null,
  name_ja      text,
  center       geography(Point, 4326) not null,
  center_lat   double precision generated always as (st_y(center::geometry)) stored,
  center_lng   double precision generated always as (st_x(center::geometry)) stored,
  timezone     text not null default 'Asia/Tokyo'
);

create index cities_country_idx on cities (country_code);

create table neighborhoods (
  id      uuid primary key default gen_random_uuid(),
  city_id uuid not null references cities (id) on delete cascade,
  slug    text not null,
  name_en text not null,
  name_ja text,
  center  geography(Point, 4326) not null,
  lat     double precision generated always as (st_y(center::geometry)) stored,
  lng     double precision generated always as (st_x(center::geometry)) stored,
  blurb   text,
  unique (city_id, slug)
);

create index neighborhoods_center_idx on neighborhoods using gist (center);

-- ------------------------------------------------------------------ hosts --

create table hosts (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  kind        host_kind not null default 'local_business',
  bio         text,
  avatar_url  text,
  website_url text,
  verified    boolean not null default false,
  -- Locally organised supply is the differentiated inventory, so it is a
  -- first-class attribute rather than something inferred later.
  is_local    boolean not null default true
);

-- ------------------------------------------------------------ experiences --

-- One table for events and attractions. The difference is whether it has a
-- start time, not what kind of row it is — which keeps the feed, the scoring,
-- search, and the itinerary from each needing two code paths.
create table experiences (
  id                uuid primary key default gen_random_uuid(),
  city_id           uuid not null references cities (id) on delete cascade,
  neighborhood_id   uuid references neighborhoods (id) on delete set null,
  host_id           uuid references hosts (id) on delete set null,

  name              text not null,
  name_ja           text,
  short_description text not null,
  description       text,

  category          text not null,      -- primary interest slug
  tags              text[] not null default '{}',

  starts_at         timestamptz,        -- null = always-available attraction
  ends_at           timestamptz,
  duration_min      integer,
  recurrence_note   text,               -- "Every Sunday", "Daily 10:00–18:00"

  is_free           boolean not null default false,
  price_yen         integer not null default 0,
  price_note        text,

  venue_name        text,
  address           text,
  point             geography(Point, 4326) not null,
  lat               double precision generated always as (st_y(point::geometry)) stored,
  lng               double precision generated always as (st_x(point::geometry)) stored,

  booking_url       text,
  external_url      text,
  stay22_url        text,               -- sponsor: stays near this venue

  -- 0..1, higher means more locally-rooted and less guidebook. Drives the
  -- "Hidden local gems" rail and a scoring bonus.
  locality          numeric(3,2) not null default 0.50,

  -- Denormalised social proof, trigger-maintained so the feed never joins to
  -- count rows. Saves and shares only — the spec has no likes and no comments.
  save_count        integer not null default 0,
  share_count       integer not null default 0,

  published         boolean not null default true,
  created_at        timestamptz not null default now(),

  constraint experiences_price_valid check (
    (is_free and price_yen = 0) or (not is_free and price_yen >= 0)
  )
);

create index experiences_point_idx    on experiences using gist (point);
create index experiences_city_idx     on experiences (city_id);
create index experiences_starts_idx   on experiences (starts_at);
create index experiences_category_idx on experiences (category);
create index experiences_tags_idx     on experiences using gin (tags);
create index experiences_name_trgm    on experiences using gin (name gin_trgm_ops);

-- --------------------------------------------------------- media provider --

-- A row is a POINTER to media that lives somewhere else, plus the attribution
-- required to display it legally.
--
--   'tiktok' / 'instagram' -> source_url is the public post URL; the client
--                             resolves it through the official oEmbed endpoint
--                             at render time. Both keyless as of 2026.
--   'hosted_video'/'image' -> media we own or licensed.
--   'placeholder'          -> clearly-labelled demo asset, so the app looks
--                             finished with zero API keys.
--
-- There is deliberately no column for video bytes or a rehosted file path.
create table experience_media (
  id                 uuid primary key default gen_random_uuid(),
  experience_id      uuid not null references experiences (id) on delete cascade,
  kind               media_kind not null,
  license            media_license not null default 'placeholder',
  source_url         text,
  thumbnail_url      text,
  alt_text           text,
  attribution_name   text,
  attribution_handle text,
  attribution_url    text,
  position           integer not null default 0,
  is_primary         boolean not null default false,
  created_at         timestamptz not null default now(),

  constraint media_needs_source check (
    kind = 'placeholder' or source_url is not null
  )
);

create index experience_media_exp_idx on experience_media (experience_id, position);
create unique index experience_media_primary_idx
  on experience_media (experience_id) where is_primary;

-- --------------------------------------------------------------- identity --

create table profiles (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete cascade,
  display_name text not null default 'Traveler',
  avatar_url   text,
  -- Free-text box on the profile screen. Fed into scoring as a keyword signal,
  -- so the box does something real instead of decorating.
  about        text,
  created_at   timestamptz not null default now()
);

create index profiles_auth_user_id_idx on profiles (auth_user_id);

-- ─────────────────────── STAGE 1: who you are, always ───────────────────────
--
-- Broad and evergreen. Answered once, at signup, and rarely changed: which
-- countries you travel to or dream about, why you travel, and what you are
-- into. Deliberately contains no dates, no city, no budget — those belong to a
-- trip, and putting them here is what would limit a traveler to one journey.
create table traveler_profiles (
  profile_id  uuid primary key references profiles (id) on delete cascade,
  interests   text[] not null default '{}',   -- interests.slug
  countries   text[] not null default '{}',   -- countries.code
  reasons     text[] not null default '{}',   -- travel_reasons.slug
  onboarded   boolean not null default false,
  updated_at  timestamptz not null default now()
);

-- ─────────────────────── STAGE 2: one specific journey ──────────────────────
--
-- Created when the traveler decides to plan. This is where the deeper questions
-- land: exactly which city, when, how long, who with, how much. A traveler can
-- have several, and none of it disturbs their taste profile.
create table trips (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references profiles (id) on delete cascade,
  name            text,
  country_code    text references countries (code),
  city_id         uuid references cities (id) on delete set null,
  -- Where they are staying. Powers "In Shibuya, where you're staying" and is
  -- the strongest proximity signal the engine gets.
  neighborhood_id uuid references neighborhoods (id) on delete set null,
  start_date      date,
  end_date        date,
  duration_days   integer generated always as (
                    case when start_date is not null and end_date is not null
                         then (end_date - start_date) + 1 end) stored,
  party           travel_style  not null default 'solo',
  budget          budget_level  not null default 'moderate',
  pace            trip_pace     not null default 'balanced',
  notes           text,
  status          trip_status   not null default 'planning',
  created_at      timestamptz   not null default now(),

  constraint trip_dates_ordered check (
    start_date is null or end_date is null or end_date >= start_date
  )
);

create index trips_profile_idx on trips (profile_id, start_date desc nulls last);

-- ------------------------------------------------------- saves & dismisses --

-- Saves and dismissals live on the PROFILE, not a trip. Someone can save a
-- Kyoto workshop eighteen months before booking anything; when they later plan
-- a Kyoto trip, those saves become the starting suggestions.
create table saved_items (
  profile_id    uuid not null references profiles (id) on delete cascade,
  experience_id uuid not null references experiences (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (profile_id, experience_id)
);

create index saved_items_profile_idx on saved_items (profile_id, created_at desc);

-- Swipe-left. Kept rather than discarded: "you passed on three nightlife cards"
-- is the strongest signal the traveler produces.
create table dismissed_items (
  profile_id    uuid not null references profiles (id) on delete cascade,
  experience_id uuid not null references experiences (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (profile_id, experience_id)
);

create table share_events (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid references profiles (id) on delete set null,
  experience_id uuid not null references experiences (id) on delete cascade,
  channel       text,
  created_at    timestamptz not null default now()
);

create index share_events_exp_idx on share_events (experience_id);

-- -------------------------------------------------------------- itinerary --

-- Entries belong to a trip and sit on a day within it.
create table itinerary_entries (
  id            uuid primary key default gen_random_uuid(),
  trip_id       uuid not null references trips (id) on delete cascade,
  profile_id    uuid not null references profiles (id) on delete cascade,
  experience_id uuid not null references experiences (id) on delete cascade,
  day           date not null,
  position      integer not null default 0,
  planned_start time,
  planned_end   time,
  note          text,
  created_at    timestamptz not null default now(),
  -- The same place can appear in two different trips, but not twice in one.
  unique (trip_id, experience_id)
);

create index itinerary_trip_day_idx on itinerary_entries (trip_id, day, position);
create index itinerary_profile_idx  on itinerary_entries (profile_id);

-- ---------------------------------------------------------------- triggers --

create or replace function bump_save_count()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update experiences set save_count = save_count + 1 where id = new.experience_id;
  elsif tg_op = 'DELETE' then
    update experiences set save_count = greatest(0, save_count - 1) where id = old.experience_id;
  end if;
  return null;
end;
$$;

create trigger saved_items_count
  after insert or delete on saved_items
  for each row execute function bump_save_count();

create or replace function bump_share_count()
returns trigger language plpgsql as $$
begin
  update experiences set share_count = share_count + 1 where id = new.experience_id;
  return null;
end;
$$;

create trigger share_events_count
  after insert on share_events
  for each row execute function bump_share_count();

-- Mint a profile and an empty taste row on first (anonymous) sign-in, so RLS
-- has something to own and onboarding has somewhere to write.
create or replace function handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_profile uuid;
begin
  insert into profiles (auth_user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', 'Traveler'))
  on conflict (auth_user_id) do nothing
  returning id into v_profile;

  if v_profile is not null then
    insert into traveler_profiles (profile_id) values (v_profile)
    on conflict do nothing;
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();
