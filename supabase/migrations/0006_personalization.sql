-- Roam — the app as your guide.
--
-- Two ideas live here, and they are the product:
--
--   1. LOCAL-FIRST. Most travel apps rank by fame, which is why every traveler
--      ends up in the same five places. We score the opposite direction:
--      a place is more interesting when locals go there and guidebooks don't.
--      Tourist attractions still appear — they are just not the default.
--
--   2. PERSONALISED. A route is generated from who you are: what you like, how
--      fast you move, whether stairs are a problem. Not a hand-authored tour
--      that is the same for everyone who buys it.
--
-- Together these are what a hand-authored audio-tour app structurally cannot do:
-- authoring caps you at a few hundred cities, generation works everywhere OSM
-- does, and a generated route can be different for every traveler.

-- ------------------------------------------------------- traveler profiles --

create table traveler_profiles (
  profile_id       uuid primary key references profiles (id) on delete cascade,
  interests        text[] not null default '{}',        -- eat · culture · hike · beach · market · nightlife · art · history · nature
  pace             text   not null default 'balanced',  -- relaxed · balanced · packed
  crowd_preference text   not null default 'local',     -- local · mixed · iconic
  accessibility    text[] not null default '{}',        -- step_free · low_walking
  updated_at       timestamptz not null default now(),
  constraint traveler_pace_valid  check (pace in ('relaxed', 'balanced', 'packed')),
  constraint traveler_crowd_valid check (crowd_preference in ('local', 'mixed', 'iconic'))
);

alter table traveler_profiles enable row level security;

create policy traveler_profiles_own on traveler_profiles for all
  using      (profile_id = current_profile_id())
  with check (profile_id = current_profile_id());

-- --------------------------------------------------------------- localness --

alter table places add column if not exists localness       numeric(3,2) not null default 0.50;
alter table places add column if not exists tourist_density integer      not null default 0;
alter table places add column if not exists is_chain        boolean      not null default false;
alter table places add column if not exists has_wikidata    boolean      not null default false;

create index if not exists places_localness_idx on places (localness desc);

-- Tourist density is the honest signal, and it is a geospatial question rather
-- than a guess: how many famous things are within 250 m? A café beside the
-- Rialto Bridge is in a tourist zone no matter what its own tags say, and a
-- café in Cannaregio is not.
create or replace function recompute_localness(p_city_id uuid default null)
returns integer
language plpgsql
as $$
declare
  v_updated integer;
begin
  with density as (
    select p.id,
           (select count(*)
              from places n
             where n.id <> p.id
               and (n.has_wikidata or n.category = 'attraction')
               and st_dwithin(n.point, p.point, 250)
           )::integer as d
      from places p
     where p_city_id is null or p.city_id = p_city_id
  )
  update places p
     set tourist_density = density.d,
         localness = greatest(0, least(1,
             0.55
           - case when p.has_wikidata          then 0.30 else 0 end
           - case when p.category = 'attraction' then 0.20 else 0 end
           - case when p.is_chain              then 0.20 else 0 end
           - least(0.25, density.d * 0.03)
           + case when p.hidden_gem            then 0.30 else 0 end
         ))
    from density
   where density.id = p.id;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

select recompute_localness();

-- ------------------------------------------------------- personalised feed --

-- How hard to lean away from the postcard. 'local' actively rewards obscurity,
-- 'iconic' inverts it for the traveler who does want the Doge's Palace.
create or replace function crowd_weight(p_pref text)
returns double precision language sql immutable as $$
  select case p_pref when 'local' then 3.0 when 'iconic' then -1.5 else 1.0 end;
$$;

create or replace function recommended_places(
  p_lat      double precision,
  p_lng      double precision,
  p_radius_m integer default 4000,
  p_limit    integer default 30,
  p_category text default null
)
returns table (
  id uuid, name text, category text, themes text[], blurb text,
  lat double precision, lng double precision, localness numeric,
  hidden_gem boolean, has_wifi boolean, wifi_fee text, wheelchair text,
  distance_m double precision, score double precision, reason text
)
language sql stable as $$
  with me as (
    select coalesce(tp.interests, '{}')::text[]     as interests,
           coalesce(tp.crowd_preference, 'local')   as crowd,
           coalesce(tp.accessibility, '{}')::text[] as access
      from (select 1) _
      left join traveler_profiles tp on tp.profile_id = current_profile_id()
  ),
  scored as (
    select p.*,
           st_distance(p.point, st_makepoint(p_lng, p_lat)::geography) as dist,
           (p.category = any (me.interests) or p.themes && me.interests) as matches,
           me.crowd, me.access
      from places p, me
     where st_dwithin(p.point, st_makepoint(p_lng, p_lat)::geography, p_radius_m)
       and (p_category is null or p.category = p_category)
       -- A step-free requirement is a hard filter, not a scoring nudge.
       and (not ('step_free' = any (me.access)) or p.wheelchair = 'yes')
  )
  select s.id, s.name, s.category, s.themes, s.blurb, s.lat, s.lng, s.localness,
         s.hidden_gem, s.has_wifi, s.wifi_fee, s.wheelchair, s.dist,
         (case when s.matches then 3.0 else 0.0 end)
         + s.localness * crowd_weight(s.crowd)
         + (case when s.hidden_gem then 0.5 else 0.0 end)
         - (s.dist / nullif(p_radius_m, 0)) as score,
         case
           when s.hidden_gem and s.matches then 'Matches your interests, and most visitors miss it'
           when s.hidden_gem               then 'Most visitors walk straight past this'
           when s.matches                  then 'Matches your interests'
           when s.localness >= 0.6         then 'Where locals actually go'
           else                                 'Worth the detour'
         end as reason
    from scored s
   order by score desc
   limit p_limit;
$$;

-- ------------------------------------------------------------- self-guided --

-- The app is the guide. This reuses every piece of machinery the human-guide
-- flow already uses — rides, stops, positions, narration — with guide_id left
-- null. Nothing downstream needed a special case.
create or replace function start_self_guided(
  p_lat          double precision,
  p_lng          double precision,
  p_mode         travel_mode default 'walk',
  p_duration_min integer default 120,
  p_label        text default null
)
returns rides
language plpgsql security definer set search_path = public as $$
declare
  v_traveler uuid := current_profile_id();
  v_pace     text;
  v_stops    integer;
  v_radius   integer;
  v_ride     rides;
  v_place    record;
  v_seq      integer := 1;
begin
  if v_traveler is null then
    raise exception 'no traveler profile for the current session';
  end if;

  select coalesce(pace, 'balanced') into v_pace
    from traveler_profiles where profile_id = v_traveler;
  v_pace := coalesce(v_pace, 'balanced');

  -- Pace decides density, not distance: a packed day is more stops in the same
  -- area, not the same stops further apart.
  v_stops := greatest(3, least(8, ceil(
    p_duration_min / case v_pace when 'relaxed' then 40.0 when 'packed' then 18.0 else 25.0 end
  )::integer));

  -- Roughly how far you can actually get in the time, at this mode's speed,
  -- assuming a bit over half the time is spent moving.
  v_radius := greatest(800, least(12000,
    (mode_speed_mps(p_mode) * p_duration_min * 60 * 0.55 / 2)::integer
  ));

  insert into rides (traveler_id, guide_id, status, mode, pickup_point, pickup_label, started_at)
  values (v_traveler, null, 'active', p_mode,
          st_makepoint(p_lng, p_lat)::geography, p_label, now())
  returning * into v_ride;

  for v_place in
    select id from recommended_places(p_lat, p_lng, v_radius, v_stops)
  loop
    insert into ride_stops (ride_id, seq, place_id) values (v_ride.id, v_seq, v_place.id);
    v_seq := v_seq + 1;
  end loop;

  return v_ride;
end;
$$;

-- Three taps of onboarding, one round trip.
create or replace function save_my_preferences(
  p_interests     text[] default '{}',
  p_pace          text   default 'balanced',
  p_crowd         text   default 'local',
  p_accessibility text[] default '{}'
)
returns traveler_profiles
language plpgsql security definer set search_path = public as $$
declare
  v_row traveler_profiles;
begin
  insert into traveler_profiles (profile_id, interests, pace, crowd_preference, accessibility)
  values (current_profile_id(), p_interests, p_pace, p_crowd, p_accessibility)
  on conflict (profile_id) do update
     set interests        = excluded.interests,
         pace             = excluded.pace,
         crowd_preference = excluded.crowd_preference,
         accessibility    = excluded.accessibility,
         updated_at       = now()
  returning * into v_row;

  return v_row;
end;
$$;
