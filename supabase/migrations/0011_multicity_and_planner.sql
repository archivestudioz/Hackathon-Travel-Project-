-- Multi-city trips, and the itinerary planner.
--
-- Two things, because the second depends on the first.
--
-- MULTI-CITY. A Japan trip is Tokyo then Kyoto then Osaka, not one city. The
-- old single city_id made "wrong city −3.5" actively suppress Kyoto cards on a
-- Tokyo trip, which is exactly backwards for a traveler doing all three.
--
-- THE PLANNER. "Turn 12 saves into a day-by-day plan" is the moment the product
-- stops being a feed and starts being useful. It has to do three things a
-- human would: keep each day in one neighbourhood so you are not crossing the
-- city twice, put things at the hour they actually happen, and never
-- double-book. All deterministic — the same saves always produce the same plan,
-- so a demo cannot embarrass you on the third run.

-- ---------------------------------------------------------- multi-city trips --

create table if not exists trip_cities (
  trip_id     uuid not null references trips (id) on delete cascade,
  city_id     uuid not null references cities (id) on delete cascade,
  seq         integer not null default 1,
  -- Optional. When null the planner splits the trip evenly between cities in
  -- seq order, which is what a traveler who has not booked trains yet expects.
  arrive_date date,
  depart_date date,
  primary key (trip_id, city_id)
);

create index if not exists trip_cities_trip_idx on trip_cities (trip_id, seq);

alter table trip_cities enable row level security;

drop policy if exists trip_cities_own on trip_cities;
create policy trip_cities_own on trip_cities for all
  using      (exists (select 1 from trips t
                       where t.id = trip_id and t.profile_id = current_profile_id()))
  with check (exists (select 1 from trips t
                       where t.id = trip_id and t.profile_id = current_profile_id()));

-- Every existing trip keeps working: its single city becomes leg 1.
insert into trip_cities (trip_id, city_id, seq)
select id, city_id, 1 from trips where city_id is not null
on conflict do nothing;

create or replace function trip_city_ids(p_trip_id uuid)
returns uuid[] language sql stable as $$
  select coalesce(
    nullif(array(select city_id from trip_cities where trip_id = p_trip_id order by seq), '{}'),
    array(select city_id from trips where id = p_trip_id and city_id is not null));
$$;

-- Which city is the traveler in on a given day? Explicit dates win; otherwise
-- the trip is split evenly across the legs in order.
create or replace function trip_city_for_day(p_trip_id uuid, p_day date)
returns uuid
language plpgsql stable as $$
declare
  v_trip   trips;
  v_exact  uuid;
  v_n      integer;
  v_len    integer;
  v_offset integer;
begin
  select * into v_trip from trips where id = p_trip_id;
  if not found then return null; end if;

  select city_id into v_exact from trip_cities
   where trip_id = p_trip_id
     and arrive_date is not null and depart_date is not null
     and p_day between arrive_date and depart_date
   order by seq limit 1;
  if v_exact is not null then return v_exact; end if;

  select count(*) into v_n from trip_cities where trip_id = p_trip_id;
  if v_n = 0 then return v_trip.city_id; end if;
  if v_n = 1 or v_trip.start_date is null or v_trip.end_date is null then
    return (select city_id from trip_cities where trip_id = p_trip_id order by seq limit 1);
  end if;

  v_len    := greatest(1, (v_trip.end_date - v_trip.start_date) + 1);
  v_offset := least(v_n - 1, ((p_day - v_trip.start_date) * v_n) / v_len);

  return (select city_id from trip_cities where trip_id = p_trip_id
           order by seq offset v_offset limit 1);
end;
$$;

-- ------------------------------------------------------------ time-of-day --

-- Where a thing naturally sits in a day. A ramen crawl at 09:00 and a shrine at
-- 21:00 are both technically valid and both obviously wrong, and getting this
-- right is most of what makes a generated plan look human.
create or replace function preferred_slot(p_category text, p_tags text[] default '{}')
returns time language sql immutable as $$
  select case
    -- Tags win over category. 'cars' covers both a midnight expressway meet and
    -- a Ginza showroom that shuts at eight; only the tag distinguishes them.
    when 'late-night' = any (p_tags)                   then time '21:30'
    when p_category in ('nature', 'hiking')            then time '09:00'
    when p_category = 'market'                         then time '10:00'
    when p_category in ('culture', 'traditional', 'art', 'attraction') then time '11:00'
    when p_category = 'food'                           then time '12:30'
    when p_category in ('shopping', 'anime', 'cars')   then time '15:00'
    when p_category = 'wellness'                       then time '17:00'
    when p_category in ('music', 'festival')           then time '19:00'
    when p_category = 'nightlife'                      then time '21:00'
    else time '14:00'
  end;
$$;

create or replace function slot_duration(p_category text, p_duration integer)
returns integer language sql immutable as $$
  select coalesce(p_duration, case
    when p_category in ('hiking', 'nature')  then 180
    when p_category in ('nightlife', 'cars') then 150
    when p_category = 'food'                 then 90
    when p_category = 'shopping'             then 90
    else 120 end);
$$;

-- Rough travel time between two points. Straight-line distance with an urban
-- detour factor, then a mode guess by distance: walking under a kilometre,
-- train beyond. Not routing — but "~18 min by train" between stops is what
-- makes a plan feel real, and a routing API is a network dependency we refuse
-- to put in the request path.
create or replace function travel_estimate(
  p_from geography, p_to geography
)
returns jsonb language sql immutable as $$
  with d as (select st_distance(p_from, p_to) * 1.35 as m)
  select case
    when d.m < 120  then jsonb_build_object('minutes', 0,  'mode', 'none',    'metres', round(d.m))
    when d.m < 1100 then jsonb_build_object('minutes', greatest(1, round(d.m / 80.0)),
                                            'mode', 'walk',  'metres', round(d.m))
    else                 jsonb_build_object('minutes', greatest(6, round(d.m / 420.0) + 5),
                                            'mode', 'train', 'metres', round(d.m))
  end
  from d;
$$;

-- ------------------------------------------------------------- conflicts --

create or replace function itinerary_conflicts(p_trip_id uuid default null)
returns table (
  entry_id uuid, other_entry_id uuid, day date,
  name text, other_name text,
  starts time, other_starts time, overlap_min integer
)
language sql stable as $$
  with t as (select coalesce(p_trip_id, current_trip_id()) as tid),
  -- Minutes-from-midnight, not `time`. A 21:00 start plus a 180-minute
  -- duration is 24:00, which casts back to 00:00 and makes every late-evening
  -- overlap invisible — the detector reported zero conflicts on a day that
  -- plainly had one.
  slots as (
    select i.id, i.day, i.experience_id, e.name,
           coalesce(i.planned_start, preferred_slot(e.category, e.tags)) as s,
           (extract(hour from coalesce(i.planned_start, preferred_slot(e.category, e.tags))) * 60
            + extract(minute from coalesce(i.planned_start, preferred_slot(e.category, e.tags))))::integer
             as start_min,
           (extract(hour from coalesce(i.planned_start, preferred_slot(e.category, e.tags))) * 60
            + extract(minute from coalesce(i.planned_start, preferred_slot(e.category, e.tags)))
            + slot_duration(e.category, e.duration_min))::integer as end_min
      from itinerary_entries i
      join experiences e on e.id = i.experience_id, t
     where i.trip_id = t.tid and i.profile_id = current_profile_id()
  )
  select a.id, b.id, a.day, a.name, b.name, a.s, b.s,
         (least(a.end_min, b.end_min) - greatest(a.start_min, b.start_min))::integer
    from slots a join slots b
      on a.day = b.day and a.id < b.id
     and a.start_min < b.end_min and b.start_min < a.end_min
   order by a.day, a.start_min;
$$;

-- ------------------------------------------------------------ THE PLANNER --

create or replace function build_itinerary(
  p_trip_id uuid default null,
  p_replace boolean default true
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_pid      uuid := current_profile_id();
  v_tid      uuid := coalesce(p_trip_id, current_trip_id());
  v_trip     trips;
  v_per_day  integer;
  v_day      date;
  v_city     uuid;
  v_anchor   record;
  v_item     record;
  v_placed   integer;
  v_slot     time;
  v_total    integer := 0;
  v_days     integer := 0;
  v_remaining  integer;
  v_mins       integer;
  v_base_mins  integer;
  v_days_left  integer;
  v_target     integer;
  v_hoods    text[];
begin
  if v_pid is null then raise exception 'not signed in'; end if;
  if v_tid is null then raise exception 'no trip yet'; end if;

  select * into v_trip from trips where id = v_tid and profile_id = v_pid;
  if not found then raise exception 'trip not found'; end if;
  if v_trip.start_date is null or v_trip.end_date is null then
    raise exception 'trip needs dates before it can be planned';
  end if;

  if p_replace then
    delete from itinerary_entries where trip_id = v_tid;
  end if;

  v_per_day := case v_trip.pace when 'relaxed' then 2 when 'packed' then 4 else 3 end;

  -- Everything saved, in one of this trip's cities, not already scheduled.
  create temp table _pool on commit drop as
  select e.id, e.category, e.tags, e.neighborhood_id, e.city_id, e.point,
         e.starts_at, e.duration_min, e.price_yen,
         coalesce(sc.score, 0) as score
    from saved_items s
    join experiences e on e.id = s.experience_id
    left join experience_scores(v_pid, v_tid) sc on sc.experience_id = e.id
   where s.profile_id = v_pid
     and e.city_id = any (trip_city_ids(v_tid))
     and not exists (select 1 from itinerary_entries i
                      where i.trip_id = v_tid and i.experience_id = e.id);

  -- PASS 1 — anything with a real start time is pinned to its own date. A
  -- festival on the 24th cannot be moved to balance a day out.
  for v_item in
    select * from _pool
     where starts_at is not null
       and starts_at::date between v_trip.start_date and v_trip.end_date
     order by starts_at
  loop
    insert into itinerary_entries (trip_id, profile_id, experience_id, day, position, planned_start)
    values (v_tid, v_pid, v_item.id, v_item.starts_at::date,
            (select coalesce(max(position), 0) + 1 from itinerary_entries
              where trip_id = v_tid and day = v_item.starts_at::date),
            v_item.starts_at::time)
    on conflict (trip_id, experience_id) do nothing;

    delete from _pool where id = v_item.id;
    v_total := v_total + 1;
  end loop;

  -- PASS 2 — fill the remaining days. Each day gets an anchor (the best
  -- unscheduled thing in that day's city) and is then filled from the SAME
  -- neighbourhood outward, so a day is a walkable cluster rather than four
  -- train rides.
  v_day := v_trip.start_date;
  while v_day <= v_trip.end_date loop
    v_city := trip_city_for_day(v_tid, v_day);

    select count(*) into v_placed
      from itinerary_entries where trip_id = v_tid and day = v_day;

    -- Spread, don't front-load. Divide what is left for this city by the days
    -- this city still has, so two Kyoto saves become one on each of two days
    -- rather than both on the first and an empty day after it.
    select count(*) into v_remaining
      from _pool where city_id = coalesce(v_city, city_id);
    select count(*) into v_days_left
      from generate_series(v_day, v_trip.end_date, interval '1 day') g
     where trip_city_for_day(v_tid, g::date) is not distinct from v_city;

    v_target := least(
      v_per_day,
      greatest(1, ceil(v_remaining::numeric / greatest(1, v_days_left))::integer));

    if v_placed < v_target then
      select * into v_anchor from _pool
       where city_id = coalesce(v_city, city_id)
       order by score desc, id limit 1;

      if v_anchor.id is not null then
        for v_item in
          select p.*,
                 st_distance(p.point, v_anchor.point) as dist_m
            from _pool p
           where p.city_id = coalesce(v_city, p.city_id)
           order by (p.neighborhood_id is not distinct from v_anchor.neighborhood_id) desc,
                    st_distance(p.point, v_anchor.point),
                    p.score desc
           limit (v_target - v_placed)
        loop
          -- A "Night Walk" seeded with a 19:00 start keeps 19:00 even when its
          -- date falls outside the trip. The clock time is real information;
          -- only the date was unusable.
          v_slot := coalesce(v_item.starts_at::time,
                             preferred_slot(v_item.category, v_item.tags));

          -- Two things at 12:30 in one day: push the second on by ninety
          -- minutes. Done in integer minutes because adding an interval to a
          -- `time` wraps silently past midnight — that is how a 21:00 izakaya
          -- crawl became 00:00 and looked like a scheduling bug to anyone
          -- reading the timeline.
          v_mins := extract(hour from v_slot) * 60 + extract(minute from v_slot);
          v_base_mins := v_mins;
          while v_mins <= 22 * 60 + 30 and exists (
            select 1 from itinerary_entries i
             where i.trip_id = v_tid and i.day = v_day
               and i.planned_start is not null
               and abs((extract(hour from i.planned_start) * 60
                        + extract(minute from i.planned_start)) - v_mins) < 90
          ) loop
            v_mins := v_mins + 90;
          end loop;

          -- Ran out of evening. Keep the honest hour and let the day carry a
          -- visible overlap — itinerary_conflicts() reports it and the UI has
          -- an amber strip for exactly this. Better than inventing midnight.
          if v_mins > 22 * 60 + 30 then
            v_mins := v_base_mins;
          end if;
          v_slot := make_time((v_mins / 60)::integer, (v_mins % 60)::integer, 0);

          insert into itinerary_entries
            (trip_id, profile_id, experience_id, day, position, planned_start)
          values (v_tid, v_pid, v_item.id, v_day,
                  (select coalesce(max(position), 0) + 1 from itinerary_entries
                    where trip_id = v_tid and day = v_day),
                  v_slot)
          on conflict (trip_id, experience_id) do nothing;

          delete from _pool where id = v_item.id;
          v_total := v_total + 1;
        end loop;
      end if;
    end if;

    v_day := v_day + 1;
  end loop;

  -- Renumber positions so they read in time order on the timeline.
  with ordered as (
    select id, row_number() over (partition by day order by planned_start, id) as rn
      from itinerary_entries where trip_id = v_tid
  )
  update itinerary_entries i set position = ordered.rn
    from ordered where ordered.id = i.id;

  select count(distinct day) into v_days from itinerary_entries where trip_id = v_tid;

  select array_agg(distinct n.name_en) into v_hoods
    from itinerary_entries i
    join experiences e on e.id = i.experience_id
    join neighborhoods n on n.id = e.neighborhood_id
   where i.trip_id = v_tid;

  return jsonb_build_object(
    'trip_id', v_tid,
    'scheduled', v_total,
    'days_used', v_days,
    'unplaced', (select count(*) from _pool),
    'neighborhoods', coalesce(to_jsonb(v_hoods), '[]'::jsonb),
    'conflicts', (select count(*) from itinerary_conflicts(v_tid)),
    'summary', v_total || ' experiences scheduled across ' || v_days || ' days');
end;
$$;

-- ----------------------------------------------------------- the day strip --

-- Every day of the trip, including empty ones, because the UI's day strip has
-- to render a chip for a day with nothing in it.
create or replace function trip_days(p_trip_id uuid default null)
returns table (
  day date, city text, stop_count integer, total_price_yen integer,
  neighborhoods text[], is_today boolean
)
language sql stable as $$
  with t as (select * from trips
              where id = coalesce(p_trip_id, current_trip_id())
                and profile_id = current_profile_id())
  select d::date,
         (select c.name_en from cities c where c.id = trip_city_for_day(t.id, d::date)),
         count(i.id)::integer,
         coalesce(sum(e.price_yen), 0)::integer,
         coalesce(array_agg(distinct n.name_en) filter (where n.name_en is not null), '{}'),
         d::date = current_date
    from t
   cross join generate_series(t.start_date, t.end_date, interval '1 day') d
    left join itinerary_entries i on i.trip_id = t.id and i.day = d::date
    left join experiences e on e.id = i.experience_id
    left join neighborhoods n on n.id = e.neighborhood_id
   group by t.id, d
   order by d;
$$;

-- ------------------------------------------------------- passed & reset --

create or replace function my_dismissed()
returns table (
  experience_id uuid, name text, category text, city text, neighborhood text,
  thumbnail_url text, price_yen integer, dismissed_at timestamptz
)
language sql stable as $$
  select k.experience_id, k.name, k.category, k.city, k.neighborhood,
         k.media_thumbnail_url, k.price_yen, d.created_at
    from dismissed_items d
    join experience_cards k on k.experience_id = d.experience_id
   where d.profile_id = current_profile_id()
   order by d.created_at desc;
$$;

-- Judges arrive in waves. This clears one traveler back to a fresh state
-- without touching the catalogue.
create or replace function reset_demo()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_pid uuid := current_profile_id();
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  delete from itinerary_entries where profile_id = v_pid;
  delete from trips           where profile_id = v_pid;
  delete from saved_items     where profile_id = v_pid;
  delete from dismissed_items where profile_id = v_pid;

  update traveler_profiles
     set interests = '{}', countries = '{}', reasons = '{}', onboarded = false
   where profile_id = v_pid;

  update profiles set about = null where id = v_pid;

  return jsonb_build_object('reset', true, 'next_screen', 'picker');
end;
$$;

-- ------------------------------------------- itinerary with travel legs --

create or replace function my_itinerary(p_trip_id uuid default null)
returns jsonb language sql stable as $$
  with t as (select coalesce(p_trip_id, current_trip_id()) as tid),
  stops as (
    select i.id, i.day, i.position, i.planned_start, i.planned_end, i.note,
           k.*, e.point,
           lag(e.point) over (partition by i.day order by i.position) as prev_point
      from itinerary_entries i
      join experience_cards k on k.experience_id = i.experience_id
      join experiences e on e.id = i.experience_id, t
     where i.trip_id = t.tid and i.profile_id = current_profile_id()
  )
  select jsonb_build_object(
    'trip', (select jsonb_build_object(
               'trip_id', tr.id, 'name', tr.name,
               'cities', (select coalesce(jsonb_agg(c.name_en order by tc.seq), '[]'::jsonb)
                            from trip_cities tc join cities c on c.id = tc.city_id
                           where tc.trip_id = tr.id),
               'start_date', tr.start_date, 'end_date', tr.end_date,
               'duration_days', tr.duration_days, 'party', tr.party,
               'budget', tr.budget, 'pace', tr.pace, 'status', tr.status)
              from trips tr where tr.id = (select tid from t)
                and tr.profile_id = current_profile_id()),
    'days', coalesce((
      select jsonb_agg(row order by row->>'day') from (
        select jsonb_build_object(
                 'day', s.day,
                 'stop_count', count(*),
                 'total_price_yen', sum(s.price_yen),
                 'neighborhoods', coalesce(array_agg(distinct s.neighborhood)
                                    filter (where s.neighborhood is not null), '{}'),
                 'stops', jsonb_agg(jsonb_build_object(
                   'entry_id', s.id, 'experience_id', s.experience_id,
                   'position', s.position,
                   'planned_start', s.planned_start, 'planned_end', s.planned_end,
                   'note', s.note,
                   'name', s.name, 'category', s.category,
                   'city', s.city, 'neighborhood', s.neighborhood,
                   'venue_name', s.venue_name, 'address', s.address,
                   'lat', s.lat, 'lng', s.lng,
                   'starts_at', s.starts_at, 'duration_min', s.duration_min,
                   'is_free', s.is_free, 'price_yen', s.price_yen,
                   'booking_url', s.booking_url, 'stay22_url', s.stay22_url,
                   'thumbnail_url', s.media_thumbnail_url, 'host_name', s.host_name,
                   -- The "~18 min by train" connector between consecutive stops.
                   'travel_from_previous',
                     case when s.prev_point is null then null
                          else travel_estimate(s.prev_point, s.point) end
                 ) order by s.position)) as row
          from stops s group by s.day) days), '[]'::jsonb),
    'conflicts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'day', c.day, 'name', c.name, 'other_name', c.other_name,
               'starts', c.starts, 'other_starts', c.other_starts,
               'overlap_min', c.overlap_min))
        from itinerary_conflicts((select tid from t)) c), '[]'::jsonb)
  );
$$;

-- ------------------------------------------------- multi-city aware scoring --

-- Only the city test changes: membership in the trip's city list rather than
-- equality with one city. Without this a Kyoto card scores −3.5 on a trip that
-- literally includes Kyoto.
create or replace function experience_scores(p_profile uuid, p_trip uuid default null)
returns table (experience_id uuid, score numeric, reasons text[])
language sql stable
as $$
  with me as (
    select coalesce(tp.interests, '{}')::text[] as interests,
           coalesce(tp.countries, '{}')::text[] as countries,
           coalesce(tp.reasons,   '{}')::text[] as reasons,
           lower(coalesce(pr.about, ''))        as about,
           coalesce(pr.age_band, 'undisclosed') as age_band,
           learned_confidence(p_profile)        as conf
      from (select 1) _
      left join profiles pr          on pr.id = p_profile
      left join traveler_profiles tp on tp.profile_id = p_profile
  ),
  learned as (select slug, weight from interest_affinity(p_profile)),
  trip as (
    select t.id, t.neighborhood_id, t.start_date, t.end_date, t.budget, t.party,
           trip_city_ids(t.id) as city_ids,
           n.name_en as trip_hood,
           (select string_agg(c.name_en, ' & ' order by tc.seq)
              from trip_cities tc join cities c on c.id = tc.city_id
             where tc.trip_id = t.id) as trip_cities
      from trips t
      left join neighborhoods n on n.id = t.neighborhood_id
     where t.id = p_trip
  ),
  base as (
    select e.*, c.name_en as city_name, c.country_code,
           me.interests, me.countries, me.reasons, me.about, me.conf,
           t.id as trip_id, t.trip_cities, t.trip_hood,
           t.budget as trip_budget, t.party as trip_party,
           (e.category = any (me.interests) or e.tags && me.interests) as hits_interest,
           (select i.label_en from interests i
             where i.slug = any (me.interests)
               and (i.slug = e.category or i.slug = any (e.tags))
             order by (i.slug = e.category) desc limit 1)              as matched_interest,
           coalesce((select max(l.weight) from learned l
                      where l.slug = e.category or l.slug = any (e.tags)), 0) as learn_pos,
           coalesce((select min(l.weight) from learned l
                      where l.slug = e.category or l.slug = any (e.tags)), 0) as learn_neg,
           (select l.slug from learned l
             where (l.slug = e.category or l.slug = any (e.tags)) and l.weight > 0
             order by l.weight desc limit 1)                            as learned_slug,
           (e.tags && me.reasons or e.category = any (me.reasons))      as hits_reason,
           (me.countries <> '{}' and c.country_code = any (me.countries)) as hits_country,
           (t.id is not null)                                           as planning,
           (t.city_ids is not null and e.city_id = any (t.city_ids))    as hits_city,
           (t.neighborhood_id is not null
             and e.neighborhood_id = t.neighborhood_id)                 as hits_hood,
           (e.starts_at is null)                                        as always_on,
           (e.starts_at is not null and t.start_date is not null
             and e.starts_at::date
                 between t.start_date and coalesce(t.end_date, t.start_date)) as in_trip_window,
           (e.starts_at is not null and t.start_date is not null
             and e.starts_at::date
                 not between t.start_date and coalesce(t.end_date, t.start_date)) as outside_trip,
           (t.budget is null or e.is_free
             or e.price_yen <= budget_ceiling_yen(t.budget))            as fits_budget,
           (t.party is not null and style_tag(t.party) = any (e.tags))  as fits_style,
           (me.about <> '' and exists (
              select 1 from unnest(e.tags || array[e.category]) tg
               where me.about like '%' || lower(tg) || '%'))            as hits_about,
           (e.starts_at is not null
             and e.starts_at between now() and now() + interval '7 days') as soon
      from experiences e
      join cities c on c.id = e.city_id
     cross join me
      left join trip t on true
     where e.published
       and not exists (select 1 from dismissed_items d
                        where d.experience_id = e.id and d.profile_id = p_profile)
       and not (me.age_band = 'under_18' and is_adults_only(e.category, e.tags))
  )
  select b.id,
    round((
        case when b.hits_interest then 3.0 * (1 - b.conf * 0.6) else 0 end
      + b.conf * (least(2.0, b.learn_pos * 0.6) + greatest(-2.0, b.learn_neg * 0.6))
      + case when b.hits_reason  then 1.2 else 0 end
      + case when b.hits_country then 0.8 else 0 end
      + case when not b.planning  then 0
             when b.hits_city     then 2.5
             else                      -3.5 end
      + case when b.hits_hood then 1.0 else 0 end
      + case when b.in_trip_window then 2.5
             when b.always_on      then 0.8
             when b.outside_trip   then -2.0
             else 0 end
      + case when not b.planning then 0
             when b.fits_budget  then 1.5
             else -1.0 - least(3.5,
                    b.price_yen::numeric
                    / greatest(1, budget_ceiling_yen(b.trip_budget)) - 1) end
      + case when b.fits_style then 1.0 else 0 end
      + b.locality * 1.2
      + case when b.hits_about then 1.5 else 0 end
      + case when b.soon       then 0.8 else 0 end
      + least(1.0, ln(b.save_count + 1) * 0.25)
    )::numeric, 3) as score,
    array_remove(array[
      case when b.conf >= 0.3 and b.learn_pos >= 1.5 and b.learned_slug is not null
             then 'More like the ' || b.learned_slug || ' you keep saving' end,
      case when b.matched_interest is not null
             then 'Because you like ' || lower(b.matched_interest) end,
      case when b.hits_interest and b.matched_interest is null
             then 'Matches your interests' end,
      case when b.hits_hood then 'In ' || b.trip_hood || ', where you are staying' end,
      case when b.in_trip_window and b.hits_city
             then 'Happening during your ' || b.trip_cities || ' dates' end,
      case when b.in_trip_window and not b.hits_city
             then 'Happening while you are there' end,
      case when b.hits_city and not b.hits_hood and not b.in_trip_window
             then 'In ' || b.city_name end,
      case when b.hits_reason and not b.hits_interest then 'Fits why you travel' end,
      case when b.hits_about      then 'Matches what you wrote on your profile' end,
      case when b.soon            then 'Happening this week' end,
      case when b.locality >= 0.7 then 'Locally hosted, not on the tourist trail' end,
      case when b.is_free         then 'Free' end,
      case when b.fits_style      then 'Good for ' || b.trip_party::text || ' travel' end
    ], null)
  from base b;
$$;

-- create_trip gains multi-city. The first slug stays trips.city_id so nothing
-- that reads a single city breaks.
create or replace function create_trip_multi(
  p_city_slugs        text[],
  p_start_date        date default null,
  p_duration_days     integer default null,
  p_end_date          date default null,
  p_neighborhood_slug text default null,
  p_party             travel_style default 'solo',
  p_budget            budget_level default 'moderate',
  p_pace              trip_pace default 'balanced',
  p_name              text default null
)
returns trips
language plpgsql security definer set search_path = public as $$
declare
  v_pid   uuid := current_profile_id();
  v_first cities;
  v_hood  uuid;
  v_end   date;
  v_row   trips;
  v_slug  text;
  v_seq   integer := 1;
begin
  if v_pid is null then raise exception 'not signed in'; end if;
  if coalesce(array_length(p_city_slugs, 1), 0) = 0 then
    raise exception 'pick at least one city';
  end if;

  select * into v_first from cities where slug = p_city_slugs[1];
  if not found then raise exception 'unknown city %', p_city_slugs[1]; end if;

  if p_neighborhood_slug is not null then
    select id into v_hood from neighborhoods
     where city_id = v_first.id and slug = p_neighborhood_slug;
  end if;

  v_end := coalesce(p_end_date,
    case when p_start_date is not null and p_duration_days is not null
         then p_start_date + (p_duration_days - 1) end);

  insert into trips (profile_id, country_code, city_id, neighborhood_id,
                     start_date, end_date, party, budget, pace, name, status)
  values (v_pid, v_first.country_code, v_first.id, v_hood,
          p_start_date, v_end, p_party, p_budget, p_pace,
          coalesce(p_name, array_to_string(p_city_slugs, ' · ')), 'planning')
  returning * into v_row;

  foreach v_slug in array p_city_slugs loop
    insert into trip_cities (trip_id, city_id, seq)
    select v_row.id, c.id, v_seq from cities c where c.slug = v_slug
    on conflict do nothing;
    v_seq := v_seq + 1;
  end loop;

  return v_row;
end;
$$;
