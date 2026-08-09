-- Japan travel discovery — core schema
--
-- Run order: 0001_schema -> 0002_scoring -> 0003_actions -> 0004_rls
--
-- Design notes that the rest of the engine depends on:
--
--   1. Every geography column carries generated lat/lng companions. PostgREST
--      serialises geography as hex EWKB, which a browser cannot read, so this
--      keeps a decode step out of the client entirely.
--
--   2. experience_media stores REFERENCES ONLY — a canonical post URL plus
--      attribution. No video bytes are ever copied or rehosted. Embeds are
--      resolved at render time through the official oEmbed endpoints. This is a
--      legal boundary, not a performance choice; see docs/api-contract.md.
--
--   3. profiles.id is not auth.users.id. An optional auth_user_id link keeps
--      seeded demo hosts from needing GoTrue accounts.

create extension if not exists postgis;
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;      -- search over experience names

create type travel_style   as enum ('solo', 'couple', 'family', 'group');
create type budget_level   as enum ('shoestring', 'moderate', 'comfortable', 'splurge');
create type media_kind     as enum ('tiktok', 'instagram', 'youtube', 'hosted_video', 'image', 'placeholder');
create type media_license  as enum ('oembed', 'owned', 'stock', 'placeholder');
create type host_kind      as enum ('local_business', 'community', 'individual', 'venue', 'institution');

-- ------------------------------------------------------ places & taxonomy --

create table cities (
  id         uuid primary key default gen_random_uuid(),
  slug       text unique not null,
  name_en    text not null,
  name_ja    text,
  center     geography(Point, 4326) not null,
  center_lat double precision generated always as (st_y(center::geometry)) stored,
  center_lng double precision generated always as (st_x(center::geometry)) stored,
  timezone   text not null default 'Asia/Tokyo'
);

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

-- The interest vocabulary is a table rather than an enum so the onboarding
-- screen can render it from the API instead of hardcoding a list that drifts.
create table interests (
  slug     text primary key,
  label_en text not null,
  emoji    text,
  sort     integer not null default 0
);

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
-- and the itinerary from needing two code paths for everything.
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

  -- Time. starts_at null means an always-available attraction.
  starts_at         timestamptz,
  ends_at           timestamptz,
  duration_min      integer,
  recurrence_note   text,               -- "Every Sunday", "Daily 10:00–18:00"

  -- Money, in yen. price_yen 0 with is_free true reads unambiguously.
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
  -- "Hidden local gems" section and a scoring bonus.
  locality          numeric(3,2) not null default 0.50,

  -- Denormalised social proof. Maintained by trigger so the feed never joins
  -- to count rows. The spec calls for saves and shares only — no likes,
  -- no comments.
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

-- The abstraction the spec asks for. A row is a POINTER to media that lives
-- somewhere else, plus the attribution required to display it legally.
--
--   kind 'tiktok' / 'instagram'  -> source_url is the public post URL. The
--                                   client resolves it through the official
--                                   oEmbed endpoint at render time. Both are
--                                   keyless as of 2026.
--   kind 'hosted_video'/'image'  -> media we actually own or licensed.
--   kind 'placeholder'           -> clearly-labelled demo asset, so the app
--                                   stays polished with zero API keys.
--
-- There is deliberately no column for video bytes or a rehosted file path.
create table experience_media (
  id                 uuid primary key default gen_random_uuid(),
  experience_id      uuid not null references experiences (id) on delete cascade,
  kind               media_kind not null,
  license            media_license not null default 'placeholder',
  source_url         text,              -- canonical post/page URL for oEmbed
  thumbnail_url      text,
  alt_text           text,
  attribution_name   text,
  attribution_handle text,
  attribution_url    text,
  position           integer not null default 0,
  is_primary         boolean not null default false,
  created_at         timestamptz not null default now(),

  -- An embeddable post is useless without the URL to embed.
  constraint media_needs_source check (
    kind = 'placeholder' or source_url is not null
  )
);

create index experience_media_exp_idx on experience_media (experience_id, position);
create unique index experience_media_primary_idx
  on experience_media (experience_id) where is_primary;

-- --------------------------------------------------------------- profiles --

create table profiles (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete cascade,
  display_name text not null default 'Traveler',
  avatar_url   text,
  -- Free-text box from the profile screen. Fed into scoring as keyword signal,
  -- which is why it is on the profile rather than buried in preferences.
  about        text,
  created_at   timestamptz not null default now()
);

create index profiles_auth_user_id_idx on profiles (auth_user_id);

-- Everything onboarding collects. One row per traveler.
create table traveler_preferences (
  profile_id     uuid primary key references profiles (id) on delete cascade,
  interests      text[] not null default '{}',
  destinations   text[] not null default '{}',   -- city slugs
  neighborhoods  text[] not null default '{}',   -- neighborhood slugs, optional
  trip_start     date,
  trip_end       date,
  budget         budget_level not null default 'moderate',
  style          travel_style not null default 'solo',
  onboarded      boolean not null default false,
  updated_at     timestamptz not null default now(),

  constraint trip_dates_ordered check (
    trip_start is null or trip_end is null or trip_end >= trip_start
  )
);

-- ------------------------------------------------------- saves & dismisses --

create table saved_items (
  profile_id    uuid not null references profiles (id) on delete cascade,
  experience_id uuid not null references experiences (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (profile_id, experience_id)
);

create index saved_items_profile_idx on saved_items (profile_id, created_at desc);

-- Swipe-left. Kept rather than discarded because "you dismissed three nightlife
-- cards" is one of the strongest personalisation signals available.
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

-- ------------------------------------------------------------- itinerary --

-- Entries hang off a date rather than a trip object: the spec's itinerary is
-- "group my saved things by day", and a trip entity would be ceremony the demo
-- never uses.
create table itinerary_entries (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references profiles (id) on delete cascade,
  experience_id uuid not null references experiences (id) on delete cascade,
  day           date not null,
  position      integer not null default 0,
  planned_start time,
  planned_end   time,
  note          text,
  created_at    timestamptz not null default now(),
  unique (profile_id, experience_id)
);

create index itinerary_profile_day_idx on itinerary_entries (profile_id, day, position);

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

-- Mint a profile on first (anonymous) sign-in so RLS has something to own.
create or replace function handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (auth_user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', 'Traveler'))
  on conflict (auth_user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();
