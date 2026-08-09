-- Roam — the entire API surface.
--
-- There is no application server. These functions ARE the backend: the browser
-- calls them through PostgREST as RPC, and RLS (0003) decides what each caller
-- can see. Every function is `security invoker` (the default) so policies apply.

-- Transport mode is first-class, not a toggle. Radius, speed, and stop count all
-- differ — which is why a walking guide 6 km away is correctly not a match, and
-- why Venice (no cars, vaporetto only) works without a special case anywhere.
create or replace function mode_radius_m(p_mode travel_mode)
returns integer language sql immutable as $$
  select case p_mode
           when 'walk'  then 1500
           when 'boat'  then 4000
           else 8000
         end;
$$;

create or replace function mode_speed_mps(p_mode travel_mode)
returns double precision language sql immutable as $$
  select case p_mode
           when 'walk'  then 1.4    --  5 km/h  on foot
           when 'boat'  then 5.0    -- 18 km/h  vaporetto / water taxi
           else 8.3                 -- 30 km/h  city driving
         end;
$$;

create or replace function mode_stop_count(p_mode travel_mode)
returns integer language sql immutable as $$
  select case p_mode when 'walk' then 5 when 'boat' then 4 else 3 end;
$$;

-- Resolve the calling auth user to a Roam profile. Used by every RLS policy.
create or replace function current_profile_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from profiles where auth_user_id = auth.uid();
$$;

-- ----------------------------------------------------------- discover places --

create or replace function nearby_places(
  p_lat      double precision,
  p_lng      double precision,
  p_category text default null,
  p_radius_m integer default 2000,
  p_wifi_only boolean default false,
  p_limit    integer default 60
)
returns table (
  id uuid, name text, category text, themes text[], blurb text, known_for text,
  hidden_gem boolean, lat double precision, lng double precision,
  has_wifi boolean, wifi_fee text, wifi_ssid text, wheelchair text,
  opening_hours text, stay22_url text, distance_m double precision
)
language sql stable as $$
  select p.id, p.name, p.category, p.themes, p.blurb, p.known_for,
         p.hidden_gem, p.lat, p.lng,
         p.has_wifi, p.wifi_fee, p.wifi_ssid, p.wheelchair,
         p.opening_hours, p.stay22_url,
         st_distance(p.point, st_makepoint(p_lng, p_lat)::geography) as distance_m
    from places p
   where st_dwithin(p.point, st_makepoint(p_lng, p_lat)::geography, p_radius_m)
     and (p_category is null or p.category = p_category)
     and (not p_wifi_only or p.has_wifi)
   order by distance_m
   limit p_limit;
$$;

-- ----------------------------------------------------------- discover events --

create or replace function nearby_events(
  p_lat      double precision,
  p_lng      double precision,
  p_radius_m integer default 5000,
  p_from     timestamptz default now(),
  p_limit    integer default 40
)
returns table (
  id uuid, name text, category text, starts_at timestamptz, venue_name text,
  lat double precision, lng double precision, ticket_url text, stay22_url text,
  image_url text, price_min_cents integer, blurb text, source text,
  distance_m double precision
)
language sql stable as $$
  select e.id, e.name, e.category, e.starts_at, e.venue_name,
         e.lat, e.lng, e.ticket_url, e.stay22_url, e.image_url,
         e.price_min_cents, e.blurb, e.source,
         st_distance(e.point, st_makepoint(p_lng, p_lat)::geography) as distance_m
    from events e
   where st_dwithin(e.point, st_makepoint(p_lng, p_lat)::geography, p_radius_m)
     and e.starts_at >= p_from
   order by e.starts_at, distance_m
   limit p_limit;
$$;

-- ----------------------------------------------------------- discover guides --

create or replace function nearby_guides(
  p_lat        double precision,
  p_lng        double precision,
  p_mode       travel_mode default 'walk',
  p_specialty  text default null,
  p_language   text default null,
  p_limit      integer default 10
)
returns table (
  guide_id uuid, display_name text, avatar_url text, headline text,
  specialties text[], languages text[], rating numeric, rides_completed integer,
  hourly_rate_cents integer, verified boolean,
  lat double precision, lng double precision,
  distance_m double precision, eta_min integer
)
language sql stable as $$
  with origin as (select st_makepoint(p_lng, p_lat)::geography as g)
  select pr.id, pr.display_name, pr.avatar_url, gp.headline,
         gp.specialties, pr.languages, gp.rating, gp.rides_completed,
         gp.hourly_rate_cents, gp.verified,
         coalesce(gs.lat, gp.home_lat) as lat,
         coalesce(gs.lng, gp.home_lng) as lng,
         st_distance(coalesce(gs.last_point, gp.home_point), o.g) as distance_m,
         ceil(st_distance(coalesce(gs.last_point, gp.home_point), o.g)
              / mode_speed_mps(p_mode) / 60.0)::integer as eta_min
    from guide_profiles gp
    join profiles pr on pr.id = gp.profile_id
    left join guide_status gs on gs.guide_id = gp.profile_id
   cross join origin o
   where p_mode = any (gp.modes)
     and st_dwithin(coalesce(gs.last_point, gp.home_point), o.g, mode_radius_m(p_mode))
     and (p_specialty is null or p_specialty = any (gp.specialties))
     and (p_language  is null or p_language  = any (pr.languages))
   order by gp.rating desc, distance_m
   limit p_limit;
$$;

-- ------------------------------------------------------------------- match --

-- Pick the best available guide and open a ride. Returns the ride row so the
-- client has everything it needs in one round trip.
create or replace function match_guide(
  p_lat       double precision,
  p_lng       double precision,
  p_mode      travel_mode default 'walk',
  p_theme     text default null,
  p_label     text default null,
  p_language  text default null
)
returns rides
language plpgsql security definer set search_path = public as $$
declare
  v_traveler uuid := current_profile_id();
  v_guide    record;
  v_ride     rides;
begin
  if v_traveler is null then
    raise exception 'no traveler profile for the current session';
  end if;

  select * into v_guide
    from nearby_guides(p_lat, p_lng, p_mode, p_theme, p_language, 1);

  -- NOT FOUND rather than `v_guide is null`: a record only tests as null when
  -- every one of its fields is null, which is a different question.
  if not found then
    raise exception 'no % guide available within % m', p_mode, mode_radius_m(p_mode);
  end if;

  insert into rides (traveler_id, guide_id, status, mode, theme,
                     pickup_point, pickup_label, eta_min, price_cents, matched_at)
  values (v_traveler, v_guide.guide_id, 'matched', p_mode, p_theme,
          st_makepoint(p_lng, p_lat)::geography, p_label, v_guide.eta_min,
          v_guide.hourly_rate_cents, now())
  returning * into v_ride;

  return v_ride;
end;
$$;

-- ------------------------------------------------------------------- route --

-- Build the stop list. Walking tours get more, tighter stops; driving tours get
-- fewer, spread wider. Straight-line ordering by distance is deliberate — a
-- routing API is invisible at demo zoom and adds a network dependency.
create or replace function plan_route(p_ride_id uuid, p_stops integer default null)
returns setof ride_stops
language plpgsql security definer set search_path = public as $$
declare
  v_ride  rides;
  v_n     integer;
  v_place record;
  v_seq   integer := 1;
begin
  select * into v_ride from rides where id = p_ride_id;
  if v_ride is null then
    raise exception 'ride % not found', p_ride_id;
  end if;

  v_n := coalesce(p_stops, mode_stop_count(v_ride.mode));

  delete from ride_stops where ride_id = p_ride_id;

  for v_place in
    select p.id
      from places p
     where st_dwithin(p.point, v_ride.pickup_point, mode_radius_m(v_ride.mode))
       and (v_ride.theme is null or v_ride.theme = any (p.themes) or p.category = v_ride.theme)
     order by p.hidden_gem desc,
              st_distance(p.point, v_ride.pickup_point)
     limit v_n
  loop
    insert into ride_stops (ride_id, seq, place_id) values (p_ride_id, v_seq, v_place.id);
    v_seq := v_seq + 1;
  end loop;

  return query select * from ride_stops where ride_id = p_ride_id order by seq;
end;
$$;

-- Compose a night around an event: dinner before, the event as a fixed-time
-- anchor, a drink after. This is the "intertwine events with guides" feature,
-- and it works because an event stop is just a stop.
create or replace function plan_event_night(p_ride_id uuid, p_event_id uuid)
returns setof ride_stops
language plpgsql security definer set search_path = public as $$
declare
  v_ride  rides;
  v_event events;
  v_id    uuid;
  v_seq   integer := 1;
begin
  select * into v_ride  from rides  where id = p_ride_id;
  select * into v_event from events where id = p_event_id;
  if v_ride is null or v_event is null then
    raise exception 'ride or event not found';
  end if;

  delete from ride_stops where ride_id = p_ride_id;

  -- 1. somewhere to eat near the venue
  select p.id into v_id from places p
   where p.category = 'eat'
     and st_dwithin(p.point, v_event.point, 1200)
   order by p.hidden_gem desc, st_distance(p.point, v_event.point)
   limit 1;
  if v_id is not null then
    insert into ride_stops (ride_id, seq, place_id) values (p_ride_id, v_seq, v_id);
    v_seq := v_seq + 1;
  end if;

  -- 2. the event itself — the fixed time anchor
  insert into ride_stops (ride_id, seq, event_id) values (p_ride_id, v_seq, p_event_id);
  v_seq := v_seq + 1;

  -- 3. a drink afterwards
  select p.id into v_id from places p
   where 'nightlife' = any (p.themes)
     and st_dwithin(p.point, v_event.point, 1200)
   order by st_distance(p.point, v_event.point)
   limit 1;
  if v_id is not null then
    insert into ride_stops (ride_id, seq, place_id) values (p_ride_id, v_seq, v_id);
  end if;

  return query select * from ride_stops where ride_id = p_ride_id order by seq;
end;
$$;

-- Everything the tour screen needs, already joined and ordered, including the
-- narration URL for the caller's language.
create or replace function ride_itinerary(p_ride_id uuid, p_locale text default 'en')
returns table (
  seq integer, kind text, subject_id uuid, name text, category text,
  lat double precision, lng double precision, blurb text,
  starts_at timestamptz, ticket_url text, stay22_url text,
  has_wifi boolean, wheelchair text, audio_url text, arrived_at timestamptz
)
language sql stable as $$
  select s.seq,
         case when s.place_id is not null then 'place' else 'event' end as kind,
         coalesce(s.place_id, s.event_id) as subject_id,
         coalesce(p.name, e.name)         as name,
         coalesce(p.category, e.category) as category,
         coalesce(p.lat, e.lat), coalesce(p.lng, e.lng),
         coalesce(p.blurb, e.blurb),
         e.starts_at, e.ticket_url, coalesce(p.stay22_url, e.stay22_url),
         p.has_wifi, p.wheelchair,
         n.audio_url, s.arrived_at
    from ride_stops s
    left join places p on p.id = s.place_id
    left join events e on e.id = s.event_id
    left join narrations n
           on n.subject_id = coalesce(s.place_id, s.event_id)
          and n.locale = p_locale
   where s.ride_id = p_ride_id
   order by s.seq;
$$;

-- ------------------------------------------------------------------- wifi --

-- Community verification. Returns the refreshed confidence so the pin can
-- update immediately without a second round trip.
create or replace function confirm_wifi(p_place_id uuid, p_works boolean, p_note text default null)
returns table (works_count integer, fails_count integer, last_confirmed timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  insert into wifi_reports (place_id, profile_id, works, note)
  values (p_place_id, current_profile_id(), p_works, p_note);

  return query
    select count(*) filter (where works)::integer,
           count(*) filter (where not works)::integer,
           max(created_at) filter (where works)
      from wifi_reports where place_id = p_place_id;
end;
$$;
