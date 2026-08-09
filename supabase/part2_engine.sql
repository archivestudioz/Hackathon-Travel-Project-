-- PART 2 of 4 — Scoring, the action surface, RLS, age bands.
-- Supabase dashboard -> SQL Editor -> New query -> paste -> Run.
-- Run parts IN ORDER. Wait for each to say Success before the next.

-- ═══ supabase/migrations/0002_scoring.sql ═══
-- Personalisation engine.
--
-- Deterministic, not learned. Two reasons that is right and not merely fast: a
-- judge can be shown exactly why a card surfaced, and identical inputs always
-- produce an identical feed, so a demo cannot embarrass you by ranking
-- differently on the third run.
--
-- Scoring runs in TWO MODES, matching the two-stage profile:
--
--   INSPIRATION  (no trip)  — interests, countries, and reasons only. This is
--                             the scroll-for-ideas feed someone uses months
--                             before booking. Nothing is penalised for being in
--                             the wrong city or over budget, because there is
--                             no budget and no city yet.
--
--   PLANNING     (a trip)   — everything above, plus the trip's city,
--                             neighbourhood, dates, budget, party, and pace.
--                             Now a wrong city IS penalised, because the
--                             traveler has told us where they are going.
--
-- Every component emits its human sentence in the same pass that produces its
-- number, so `reasons` cannot drift from `score`. The explanation on the card
-- is literally the reason it ranked.

create or replace function current_profile_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from profiles where auth_user_id = auth.uid();
$$;

-- The trip the feed should assume when the client does not name one: whatever
-- the traveler is actively planning or currently on.
create or replace function current_trip_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from trips
   where profile_id = current_profile_id()
     and status in ('active', 'planning')
   order by (status = 'active') desc, start_date asc nulls last, created_at desc
   limit 1;
$$;

create or replace function budget_ceiling_yen(p_budget budget_level)
returns integer language sql immutable as $$
  select case p_budget
           when 'shoestring'  then 1500
           when 'moderate'    then 5000
           when 'comfortable' then 15000
           else                    1000000
         end;
$$;

create or replace function style_tag(p_style travel_style)
returns text language sql immutable as $$
  select case p_style
           when 'family' then 'family-friendly'
           when 'couple' then 'romantic'
           when 'group'  then 'group-friendly'
           else               'solo-friendly'
         end;
$$;

-- ------------------------------------------------------------------ scores --

create or replace function experience_scores(p_profile uuid, p_trip uuid default null)
returns table (experience_id uuid, score numeric, reasons text[])
language sql stable
as $$
  with me as (
    select coalesce(tp.interests, '{}')::text[] as interests,
           coalesce(tp.countries, '{}')::text[] as countries,
           coalesce(tp.reasons,   '{}')::text[] as reasons,
           lower(coalesce(pr.about, ''))        as about
      from (select 1) _
      left join profiles pr          on pr.id = p_profile
      left join traveler_profiles tp on tp.profile_id = p_profile
  ),
  trip as (
    select t.id, t.city_id, t.neighborhood_id, t.start_date, t.end_date,
           t.budget, t.party, t.pace,
           c.name_en as trip_city, n.name_en as trip_hood
      from trips t
      left join cities c        on c.id = t.city_id
      left join neighborhoods n on n.id = t.neighborhood_id
     where t.id = p_trip
  ),
  -- Behaviour so far, per category. Saves lift a category; dismissals push the
  -- whole category down, not just the one card.
  affinity as (
    select e.category as cat,
           count(s.profile_id) as saved_n,
           count(d.profile_id) as dismissed_n
      from experiences e
      left join saved_items     s on s.experience_id = e.id and s.profile_id = p_profile
      left join dismissed_items d on d.experience_id = e.id and d.profile_id = p_profile
     group by e.category
  ),
  base as (
    select e.*,
           c.name_en   as city_name,
           c.country_code,
           me.interests, me.countries, me.reasons, me.about,
           t.id        as trip_id,
           t.trip_city, t.trip_hood,
           t.budget    as trip_budget,
           t.party     as trip_party,
           coalesce(a.saved_n, 0)     as cat_saved,
           coalesce(a.dismissed_n, 0) as cat_dismissed,

           (e.category = any (me.interests) or e.tags && me.interests) as hits_interest,
           -- Checks tags as well as category: a food tour tagged 'traditional'
           -- should tell a culture traveler why, not just "matches interests".
           (select i.label_en from interests i
             where i.slug = any (me.interests)
               and (i.slug = e.category or i.slug = any (e.tags))
             order by (i.slug = e.category) desc limit 1)               as matched_interest,

           -- Reason for travel is a softer signal than interest, and separate:
           -- two people who both pick "food" want different trips depending on
           -- whether they travel for a big night out or a slow reset.
           (e.tags && me.reasons or e.category = any (me.reasons))      as hits_reason,
           (me.countries <> '{}' and c.country_code = any (me.countries)) as hits_country,

           (t.id is not null)                                           as planning,
           (t.city_id is not null and e.city_id = t.city_id)            as hits_city,
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
      left join affinity a on a.cat = e.category
     where e.published
       and not exists (select 1 from dismissed_items d
                        where d.experience_id = e.id and d.profile_id = p_profile)
  )
  select
    b.id,
    round((
        case when b.hits_interest then 3.0 else 0 end
      + case when b.hits_reason   then 1.2 else 0 end
      + case when b.hits_country  then 0.8 else 0 end

      -- City only matters once a trip exists. Before that the traveler has not
      -- told us where they are going, so penalising Tokyo would be inventing an
      -- opinion they never expressed.
      + case when not b.planning        then 0
             when b.city_id is not null and b.hits_city then 2.5
             when b.trip_city is null   then 0
             else                            -3.5 end
      + case when b.hits_hood then 1.0 else 0 end

      + case when b.in_trip_window then 2.5
             when b.always_on      then 0.8
             when b.outside_trip   then -2.0
             else 0 end

      -- Overshoot scales with how bad it is. A flat penalty let a 14,000 yen
      -- kaiseki outrank free things for a shoestring traveler.
      + case when not b.planning  then 0
             when b.fits_budget   then 1.5
             else -1.0 - least(3.5,
                    b.price_yen::numeric
                    / greatest(1, budget_ceiling_yen(b.trip_budget)) - 1) end

      + case when b.fits_style then 1.0 else 0 end
      + least(1.5, b.cat_saved * 0.5)
      - least(2.0, b.cat_dismissed * 0.75)
      + b.locality * 1.2
      + case when b.hits_about then 1.5 else 0 end
      + case when b.soon       then 0.8 else 0 end
      -- Popularity nudges ordering; it must never dominate it, or the feed
      -- collapses to the same handful of cards for every traveler.
      + least(1.0, ln(b.save_count + 1) * 0.25)
    )::numeric, 3) as score,

    array_remove(array[
      case when b.matched_interest is not null
             then 'Because you like ' || lower(b.matched_interest) end,
      case when b.hits_interest and b.matched_interest is null
             then 'Matches your interests' end,
      case when b.hits_hood then 'In ' || b.trip_hood || ', where you are staying' end,
      case when b.in_trip_window and b.hits_city
             then 'Happening during your ' || b.trip_city || ' dates' end,
      case when b.in_trip_window and not b.hits_city
             then 'Happening while you are there' end,
      case when b.hits_city and not b.hits_hood and not b.in_trip_window
             then 'In ' || b.city_name end,
      case when b.hits_reason and not b.hits_interest
             then 'Fits why you travel' end,
      case when b.hits_about     then 'Matches what you wrote on your profile' end,
      case when b.soon           then 'Happening this week' end,
      case when b.locality >= 0.7 then 'Locally hosted, not on the tourist trail' end,
      case when b.is_free        then 'Free' end,
      case when b.fits_style     then 'Good for ' || b.trip_party::text || ' travel' end,
      case when b.cat_saved > 0  then 'You have saved ' || b.category || ' before' end
    ], null) as reasons
  from base b;
$$;

-- ------------------------------------------------------------- card shape --

-- Every surface that shows an experience renders the same card. Defining that
-- once means the UI team writes one component and one TypeScript type, and a
-- field added here appears everywhere instead of in four hand-synced queries.
create view experience_cards
with (security_invoker = true)
as
select e.id                         as experience_id,
       e.name, e.short_description, e.category, e.tags,
       c.country_code,
       c.name_en                    as city,
       c.slug                       as city_slug,
       n.name_en                    as neighborhood,
       n.slug                       as neighborhood_slug,
       e.venue_name, e.address,
       e.starts_at, e.ends_at, e.duration_min, e.recurrence_note,
       e.is_free, e.price_yen, e.price_note,
       e.lat, e.lng,
       e.booking_url, e.external_url, e.stay22_url,
       h.name                       as host_name,
       coalesce(h.verified, false)  as host_verified,
       coalesce(h.is_local, true)   as host_is_local,
       m.kind                       as media_kind,
       m.source_url                 as media_source_url,
       m.thumbnail_url              as media_thumbnail_url,
       m.attribution_name           as media_attribution_name,
       m.attribution_url            as media_attribution_url,
       m.license                    as media_license,
       e.save_count, e.share_count, e.locality,
       e.published, e.city_id, e.neighborhood_id
  from experiences e
  join cities c             on c.id = e.city_id
  left join neighborhoods n on n.id = e.neighborhood_id
  left join hosts h         on h.id = e.host_id
  left join experience_media m on m.experience_id = e.id and m.is_primary;

-- --------------------------------------------------------------- the feed --

-- The swipe deck. Pass p_trip_id to plan for a specific journey; omit it and
-- the engine uses whichever trip the traveler is actively planning, falling
-- back to pure inspiration mode when they have none.
create or replace function feed(
  p_trip_id uuid default null,
  p_limit   integer default 20,
  p_offset  integer default 0
)
returns table (
  experience_id uuid, name text, short_description text, category text, tags text[],
  city text, neighborhood text, venue_name text,
  starts_at timestamptz, duration_min integer, recurrence_note text,
  is_free boolean, price_yen integer, price_note text,
  lat double precision, lng double precision,
  host_name text, host_verified boolean, host_is_local boolean,
  media_kind media_kind, media_source_url text, media_thumbnail_url text,
  media_attribution_name text, media_attribution_url text, media_license media_license,
  save_count integer, share_count integer,
  is_saved boolean, in_itinerary boolean,
  score numeric, reasons text[]
)
language sql stable
as $$
  with me as (
    select current_profile_id() as pid,
           coalesce(p_trip_id, current_trip_id()) as tid
  )
  select k.experience_id, k.name, k.short_description, k.category, k.tags,
         k.city, k.neighborhood, k.venue_name,
         k.starts_at, k.duration_min, k.recurrence_note,
         k.is_free, k.price_yen, k.price_note,
         k.lat, k.lng,
         k.host_name, k.host_verified, k.host_is_local,
         k.media_kind, k.media_source_url, k.media_thumbnail_url,
         k.media_attribution_name, k.media_attribution_url, k.media_license,
         k.save_count, k.share_count,
         false, (i.id is not null),
         sc.score, sc.reasons
    from me
    join experience_scores((select pid from me), (select tid from me)) sc on true
    join experience_cards k on k.experience_id = sc.experience_id
    left join saved_items s on s.experience_id = k.experience_id
                           and s.profile_id = (select pid from me)
    left join itinerary_entries i on i.experience_id = k.experience_id
                                 and i.trip_id = (select tid from me)
   -- Already-saved cards leave the swipe deck; the traveler has decided.
   where s.profile_id is null
   order by sc.score desc, k.save_count desc, k.experience_id
   limit p_limit offset p_offset;
$$;

-- ═══ supabase/migrations/0003_actions.sql ═══
-- The action surface.
--
-- Every interactive element in the product maps to exactly one function here.
-- If a screen needs something this file does not expose, that is a gap in the
-- engine, not something the UI should route around with raw table access.
--
-- All writes resolve the caller through current_profile_id(); no function takes
-- a profile id, so a client cannot act as another traveler.
--
-- Functions are grouped by the two onboarding stages:
--   STAGE 1  profile — broad, evergreen taste
--   STAGE 2  trips   — one specific journey, asked for only when planning

-- ══════════════════════════════ STAGE 1: profile ══════════════════════════

-- Everything the signup screen needs, in one request. Broad questions only:
-- where do you travel, why, and what are you into. No dates, no city, no
-- budget — those are trip questions and asking them here would be premature.
create or replace function onboarding_options()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'countries', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', code, 'name', name_en, 'emoji', emoji,
               'available', available) order by sort, name_en), '[]'::jsonb)
        from countries),
    'interests', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'slug', slug, 'label', label_en, 'emoji', emoji) order by sort), '[]'::jsonb)
        from interests),
    'reasons', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'slug', slug, 'label', label_en, 'emoji', emoji) order by sort), '[]'::jsonb)
        from travel_reasons)
  );
$$;

create or replace function save_profile_onboarding(
  p_interests text[] default '{}',
  p_countries text[] default '{}',
  p_reasons   text[] default '{}'
)
returns traveler_profiles
language plpgsql security definer set search_path = public as $$
declare
  v_pid uuid := current_profile_id();
  v_row traveler_profiles;
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  insert into traveler_profiles (profile_id, interests, countries, reasons, onboarded)
  values (v_pid, p_interests, p_countries, p_reasons, true)
  on conflict (profile_id) do update
     set interests  = excluded.interests,
         countries  = excluded.countries,
         reasons    = excluded.reasons,
         onboarded  = true,
         updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function update_profile(
  p_display_name text default null,
  p_avatar_url   text default null,
  p_about        text default null
)
returns profiles
language plpgsql security definer set search_path = public as $$
declare v_row profiles;
begin
  update profiles
     set display_name = coalesce(p_display_name, display_name),
         avatar_url   = coalesce(p_avatar_url,   avatar_url),
         about        = coalesce(p_about,        about)
   where id = current_profile_id()
  returning * into v_row;

  if not found then raise exception 'not signed in'; end if;
  return v_row;
end;
$$;

-- The whole profile tab in one call.
create or replace function my_profile()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'profile_id',   p.id,
    'display_name', p.display_name,
    'avatar_url',   p.avatar_url,
    'about',        p.about,
    'onboarded',    coalesce(tp.onboarded, false),
    'interests',    coalesce(tp.interests, '{}'),
    'countries',    coalesce(tp.countries, '{}'),
    'reasons',      coalesce(tp.reasons,   '{}'),
    'saved_count',  (select count(*) from saved_items s where s.profile_id = p.id),
    'trip_count',   (select count(*) from trips t where t.profile_id = p.id),
    'active_trip',  current_trip_id()
  )
  from profiles p
  left join traveler_profiles tp on tp.profile_id = p.id
  where p.id = current_profile_id();
$$;

-- ══════════════════════════════ STAGE 2: trips ════════════════════════════

-- The deeper questions, asked only once someone decides to plan. Scoped to a
-- country so the city list is short and relevant rather than global.
create or replace function trip_options(p_country_code text default 'JP')
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'country', (select jsonb_build_object('code', code, 'name', name_en, 'emoji', emoji)
                  from countries where code = p_country_code),
    'cities', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'slug', c.slug, 'name', c.name_en, 'name_ja', c.name_ja,
               'lat', c.center_lat, 'lng', c.center_lng,
               'experience_count', (select count(*) from experiences e
                                     where e.city_id = c.id and e.published),
               'neighborhoods', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'id', n.id, 'slug', n.slug, 'name', n.name_en, 'blurb', n.blurb)
                        order by n.name_en), '[]'::jsonb)
                   from neighborhoods n where n.city_id = c.id)
             ) order by c.name_en), '[]'::jsonb)
        from cities c where c.country_code = p_country_code),
    'budgets', jsonb_build_array(
      jsonb_build_object('slug','shoestring',  'label','Shoestring',  'ceiling_yen',1500),
      jsonb_build_object('slug','moderate',    'label','Moderate',    'ceiling_yen',5000),
      jsonb_build_object('slug','comfortable', 'label','Comfortable', 'ceiling_yen',15000),
      jsonb_build_object('slug','splurge',     'label','Splurge',     'ceiling_yen',null)),
    'parties', jsonb_build_array(
      jsonb_build_object('slug','solo','label','Solo'),
      jsonb_build_object('slug','couple','label','Couple'),
      jsonb_build_object('slug','family','label','Family'),
      jsonb_build_object('slug','group','label','Group')),
    'paces', jsonb_build_array(
      jsonb_build_object('slug','relaxed','label','Relaxed'),
      jsonb_build_object('slug','balanced','label','Balanced'),
      jsonb_build_object('slug','packed','label','Packed'))
  );
$$;

-- Creating a trip is what turns the inspiration feed into a planning feed.
create or replace function create_trip(
  p_city_slug         text,
  p_start_date        date default null,
  p_duration_days     integer default null,
  p_end_date          date default null,
  p_neighborhood_slug text default null,
  p_party             travel_style default 'solo',
  p_budget            budget_level default 'moderate',
  p_pace              trip_pace default 'balanced',
  p_name              text default null,
  p_notes             text default null
)
returns trips
language plpgsql security definer set search_path = public as $$
declare
  v_pid  uuid := current_profile_id();
  v_city cities;
  v_hood uuid;
  v_end  date;
  v_row  trips;
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  select * into v_city from cities where slug = p_city_slug;
  if not found then raise exception 'unknown city %', p_city_slug; end if;

  if p_neighborhood_slug is not null then
    select id into v_hood from neighborhoods
     where city_id = v_city.id and slug = p_neighborhood_slug;
  end if;

  -- Travelers think in "how long", not "which day do I fly home". Accept
  -- either and derive the other.
  v_end := coalesce(
    p_end_date,
    case when p_start_date is not null and p_duration_days is not null
         then p_start_date + (p_duration_days - 1) end);

  insert into trips (profile_id, country_code, city_id, neighborhood_id,
                     start_date, end_date, party, budget, pace, name, notes, status)
  values (v_pid, v_city.country_code, v_city.id, v_hood,
          p_start_date, v_end, p_party, p_budget, p_pace,
          coalesce(p_name, v_city.name_en), p_notes, 'planning')
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function update_trip(
  p_trip_id           uuid,
  p_start_date        date default null,
  p_end_date          date default null,
  p_neighborhood_slug text default null,
  p_party             travel_style default null,
  p_budget            budget_level default null,
  p_pace              trip_pace default null,
  p_name              text default null,
  p_notes             text default null,
  p_status            trip_status default null
)
returns trips
language plpgsql security definer set search_path = public as $$
declare
  v_hood uuid;
  v_row  trips;
begin
  if p_neighborhood_slug is not null then
    select n.id into v_hood
      from neighborhoods n
      join trips t on t.id = p_trip_id and t.city_id = n.city_id
     where n.slug = p_neighborhood_slug;
  end if;

  update trips
     set start_date      = coalesce(p_start_date, start_date),
         end_date        = coalesce(p_end_date, end_date),
         neighborhood_id = coalesce(v_hood, neighborhood_id),
         party           = coalesce(p_party, party),
         budget          = coalesce(p_budget, budget),
         pace            = coalesce(p_pace, pace),
         name            = coalesce(p_name, name),
         notes           = coalesce(p_notes, notes),
         status          = coalesce(p_status, status)
   where id = p_trip_id and profile_id = current_profile_id()
  returning * into v_row;

  if not found then raise exception 'trip not found'; end if;
  return v_row;
end;
$$;

create or replace function delete_trip(p_trip_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  delete from trips where id = p_trip_id and profile_id = current_profile_id();
  return jsonb_build_object('trip_id', p_trip_id, 'deleted', true);
end;
$$;

create or replace function my_trips()
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'trip_id',       t.id,
           'name',          t.name,
           'city',          c.name_en,
           'city_slug',     c.slug,
           'neighborhood',  n.name_en,
           'country',       t.country_code,
           'start_date',    t.start_date,
           'end_date',      t.end_date,
           'duration_days', t.duration_days,
           'party',         t.party,
           'budget',        t.budget,
           'pace',          t.pace,
           'status',        t.status,
           'stop_count',    (select count(*) from itinerary_entries i where i.trip_id = t.id),
           'is_current',    (t.id = current_trip_id())
         ) order by t.start_date asc nulls last, t.created_at desc), '[]'::jsonb)
    from trips t
    left join cities c        on c.id = t.city_id
    left join neighborhoods n on n.id = t.neighborhood_id
   where t.profile_id = current_profile_id();
$$;

-- The bridge the two-stage model makes possible: things this traveler saved
-- ages ago that happen to be in the city they are now planning, and are not
-- scheduled yet. Turning saves into an itinerary is the whole point.
create or replace function trip_suggestions(p_trip_id uuid default null)
returns table (
  experience_id uuid, name text, short_description text, category text,
  city text, neighborhood text, starts_at timestamptz,
  is_free boolean, price_yen integer, thumbnail_url text, saved_at timestamptz
)
language sql stable as $$
  with t as (select * from trips
              where id = coalesce(p_trip_id, current_trip_id())
                and profile_id = current_profile_id())
  select k.experience_id, k.name, k.short_description, k.category,
         k.city, k.neighborhood, k.starts_at,
         k.is_free, k.price_yen, k.media_thumbnail_url, s.created_at
    from t
    join saved_items s      on s.profile_id = current_profile_id()
    join experience_cards k on k.experience_id = s.experience_id
   where (t.city_id is null or k.city_id = t.city_id)
     and not exists (select 1 from itinerary_entries i
                      where i.trip_id = t.id and i.experience_id = k.experience_id)
   order by s.created_at desc;
$$;

-- ═════════════════════════════ swipe & save ═══════════════════════════════

create or replace function save_experience(p_experience_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pid uuid := current_profile_id();
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  insert into saved_items (profile_id, experience_id)
  values (v_pid, p_experience_id) on conflict do nothing;

  -- The last gesture wins: saving overrides an earlier pass.
  delete from dismissed_items where profile_id = v_pid and experience_id = p_experience_id;

  return jsonb_build_object('experience_id', p_experience_id, 'is_saved', true,
    'save_count', (select save_count from experiences where id = p_experience_id));
end;
$$;

create or replace function unsave_experience(p_experience_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  delete from saved_items
   where profile_id = current_profile_id() and experience_id = p_experience_id;
  return jsonb_build_object('experience_id', p_experience_id, 'is_saved', false,
    'save_count', (select save_count from experiences where id = p_experience_id));
end;
$$;

create or replace function dismiss_experience(p_experience_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pid uuid := current_profile_id();
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  insert into dismissed_items (profile_id, experience_id)
  values (v_pid, p_experience_id) on conflict do nothing;

  delete from saved_items where profile_id = v_pid and experience_id = p_experience_id;

  return jsonb_build_object('experience_id', p_experience_id, 'dismissed', true);
end;
$$;

create or replace function undo_dismiss(p_experience_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  delete from dismissed_items
   where profile_id = current_profile_id() and experience_id = p_experience_id;
  return jsonb_build_object('experience_id', p_experience_id, 'dismissed', false);
end;
$$;

create or replace function share_experience(p_experience_id uuid, p_channel text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  insert into share_events (profile_id, experience_id, channel)
  values (current_profile_id(), p_experience_id, p_channel);
  return jsonb_build_object('experience_id', p_experience_id,
    'share_count', (select share_count from experiences where id = p_experience_id));
end;
$$;

create or replace function my_saved()
returns table (
  experience_id uuid, name text, short_description text, category text,
  city text, neighborhood text, venue_name text,
  starts_at timestamptz, is_free boolean, price_yen integer,
  lat double precision, lng double precision,
  media_thumbnail_url text, save_count integer,
  in_itinerary boolean, saved_at timestamptz
)
language sql stable as $$
  select k.experience_id, k.name, k.short_description, k.category,
         k.city, k.neighborhood, k.venue_name,
         k.starts_at, k.is_free, k.price_yen, k.lat, k.lng,
         k.media_thumbnail_url, k.save_count,
         exists (select 1 from itinerary_entries i
                  where i.experience_id = k.experience_id
                    and i.profile_id = s.profile_id),
         s.created_at
    from saved_items s
    join experience_cards k on k.experience_id = s.experience_id
   where s.profile_id = current_profile_id()
   order by s.created_at desc;
$$;

-- ══════════════════════════════ detail page ═══════════════════════════════

create or replace function experience_detail(p_experience_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'experience_id', k.experience_id, 'name', k.name, 'name_ja', e.name_ja,
    'short_description', k.short_description, 'description', e.description,
    'category', k.category, 'tags', k.tags,
    'city', k.city, 'neighborhood', k.neighborhood,
    'venue_name', k.venue_name, 'address', k.address, 'lat', k.lat, 'lng', k.lng,
    'starts_at', k.starts_at, 'ends_at', k.ends_at,
    'duration_min', k.duration_min, 'recurrence_note', k.recurrence_note,
    'is_free', k.is_free, 'price_yen', k.price_yen, 'price_note', k.price_note,
    'booking_url', k.booking_url, 'external_url', k.external_url,
    'stay22_url', k.stay22_url,
    'save_count', k.save_count, 'share_count', k.share_count, 'locality', k.locality,
    'is_saved', exists (select 1 from saved_items s
                         where s.experience_id = k.experience_id
                           and s.profile_id = current_profile_id()),
    'in_itinerary', exists (select 1 from itinerary_entries i
                             where i.experience_id = k.experience_id
                               and i.profile_id = current_profile_id()),
    'reasons', coalesce((select sc.reasons
                           from experience_scores(current_profile_id(), current_trip_id()) sc
                          where sc.experience_id = k.experience_id), '{}'),
    'host', case when e.host_id is null then null else (
      select jsonb_build_object('name', h.name, 'kind', h.kind, 'bio', h.bio,
               'avatar_url', h.avatar_url, 'website_url', h.website_url,
               'verified', h.verified, 'is_local', h.is_local)
        from hosts h where h.id = e.host_id) end,
    -- Pointers with attribution. Embeds resolve client-side through official
    -- oEmbed endpoints; nothing here is a copied file.
    'media', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'kind', m.kind, 'license', m.license, 'source_url', m.source_url,
               'thumbnail_url', m.thumbnail_url, 'alt_text', m.alt_text,
               'attribution_name', m.attribution_name,
               'attribution_handle', m.attribution_handle,
               'attribution_url', m.attribution_url,
               'is_primary', m.is_primary) order by m.position), '[]'::jsonb)
        from experience_media m where m.experience_id = k.experience_id),
    'related', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'experience_id', r.experience_id, 'name', r.name,
               'category', r.category, 'neighborhood', r.neighborhood,
               'thumbnail_url', r.media_thumbnail_url,
               'is_free', r.is_free, 'price_yen', r.price_yen)), '[]'::jsonb)
        from (select rc.* from experience_cards rc
               where rc.experience_id <> k.experience_id and rc.published
                 and (rc.category = k.category or rc.tags && k.tags)
               order by (rc.neighborhood_id is not distinct from k.neighborhood_id) desc,
                        rc.save_count desc
               limit 6) r)
  )
  from experience_cards k
  join experiences e on e.id = k.experience_id
  where k.experience_id = p_experience_id;
$$;

-- ═══════════════════════════════ explore ══════════════════════════════════

create or replace function explore(
  p_query        text default null,
  p_categories   text[] default null,
  p_city         text default null,
  p_neighborhood text default null,
  p_from         date default null,
  p_to           date default null,
  p_free_only    boolean default false,
  p_max_price    integer default null,
  p_sort         text default 'recommended',
  p_limit        integer default 40,
  p_offset       integer default 0
)
returns table (
  experience_id uuid, name text, short_description text, category text, tags text[],
  city text, neighborhood text, venue_name text,
  starts_at timestamptz, duration_min integer, recurrence_note text,
  is_free boolean, price_yen integer, price_note text,
  lat double precision, lng double precision,
  host_name text, host_verified boolean, host_is_local boolean,
  media_kind media_kind, media_source_url text, media_thumbnail_url text,
  media_attribution_name text, media_attribution_url text, media_license media_license,
  save_count integer, share_count integer,
  is_saved boolean, in_itinerary boolean,
  score numeric, reasons text[]
)
language sql stable as $$
  with me as (select current_profile_id() as pid, current_trip_id() as tid)
  select k.experience_id, k.name, k.short_description, k.category, k.tags,
         k.city, k.neighborhood, k.venue_name,
         k.starts_at, k.duration_min, k.recurrence_note,
         k.is_free, k.price_yen, k.price_note, k.lat, k.lng,
         k.host_name, k.host_verified, k.host_is_local,
         k.media_kind, k.media_source_url, k.media_thumbnail_url,
         k.media_attribution_name, k.media_attribution_url, k.media_license,
         k.save_count, k.share_count,
         (s.profile_id is not null), (i.id is not null),
         coalesce(sc.score, 0), coalesce(sc.reasons, '{}')
    from me
    join experience_cards k on k.published
    left join experience_scores((select pid from me), (select tid from me)) sc
           on sc.experience_id = k.experience_id
    left join saved_items s on s.experience_id = k.experience_id
                           and s.profile_id = (select pid from me)
    left join itinerary_entries i on i.experience_id = k.experience_id
                                 and i.profile_id = (select pid from me)
   where (p_query is null or p_query = ''
          or k.name ilike '%' || p_query || '%'
          or k.short_description ilike '%' || p_query || '%'
          or k.venue_name ilike '%' || p_query || '%'
          or exists (select 1 from unnest(k.tags) tg where tg ilike '%' || p_query || '%'))
     and (p_categories is null or k.category = any (p_categories) or k.tags && p_categories)
     and (p_city is null or k.city_slug = p_city)
     and (p_neighborhood is null or k.neighborhood_slug = p_neighborhood)
     -- An always-on attraction has no date, so a "this week" filter must not
     -- remove it from the results.
     and (p_from is null or k.starts_at is null or k.starts_at::date >= p_from)
     and (p_to   is null or k.starts_at is null or k.starts_at::date <= p_to)
     and (not p_free_only or k.is_free)
     and (p_max_price is null or k.price_yen <= p_max_price)
   order by
     case when p_sort = 'soonest' then k.starts_at end asc nulls last,
     case when p_sort = 'price'   then k.price_yen end asc,
     case when p_sort = 'popular' then k.save_count end desc,
     case when p_sort = 'recommended' then coalesce(sc.score, 0) end desc,
     k.save_count desc, k.experience_id
   limit p_limit offset p_offset;
$$;

create or replace function explore_sections(p_city text default null, p_limit integer default 8)
returns jsonb language sql stable as $$
  with me as (select current_profile_id() as pid, current_trip_id() as tid),
  base as (
    select k.*, coalesce(sc.score, 0) as score
      from me
      join experience_cards k on k.published
      left join experience_scores((select pid from me), (select tid from me)) sc
             on sc.experience_id = k.experience_id
     where p_city is null or k.city_slug = p_city
  )
  select jsonb_build_object(
    'happening_this_week', (
      select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('experience_id', b.experience_id, 'name', b.name,
                 'category', b.category, 'neighborhood', b.neighborhood, 'city', b.city,
                 'starts_at', b.starts_at, 'is_free', b.is_free, 'price_yen', b.price_yen,
                 'thumbnail_url', b.media_thumbnail_url, 'save_count', b.save_count) as x
          from base b
         where b.starts_at between now() and now() + interval '7 days'
         order by b.starts_at limit p_limit) s),
    -- Locally hosted and comparatively undiscovered. This rail is what makes
    -- the product about local experience rather than the top-ten list.
    'hidden_local_gems', (
      select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('experience_id', b.experience_id, 'name', b.name,
                 'category', b.category, 'neighborhood', b.neighborhood, 'city', b.city,
                 'starts_at', b.starts_at, 'is_free', b.is_free, 'price_yen', b.price_yen,
                 'thumbnail_url', b.media_thumbnail_url, 'locality', b.locality) as x
          from base b
         where b.locality >= 0.65 and b.host_is_local
         order by b.locality desc, b.save_count asc limit p_limit) s),
    'popular_near_you', (
      select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('experience_id', b.experience_id, 'name', b.name,
                 'category', b.category, 'neighborhood', b.neighborhood, 'city', b.city,
                 'starts_at', b.starts_at, 'is_free', b.is_free, 'price_yen', b.price_yen,
                 'thumbnail_url', b.media_thumbnail_url, 'save_count', b.save_count) as x
          from base b
         order by b.save_count desc, b.score desc limit p_limit) s)
  );
$$;

-- ══════════════════════════════ itinerary ═════════════════════════════════

-- Scheduling requires a trip. When there isn't one the error is explicit, so
-- the UI can prompt "let's set up your trip" — which is exactly the moment the
-- deeper questions are supposed to be asked.
create or replace function add_to_itinerary(
  p_experience_id uuid,
  p_trip_id       uuid default null,
  p_day           date default null,
  p_planned_start time default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_pid  uuid := current_profile_id();
  v_tid  uuid := coalesce(p_trip_id, current_trip_id());
  v_trip trips;
  v_day  date;
  v_pos  integer;
  v_id   uuid;
begin
  if v_pid is null then raise exception 'not signed in'; end if;
  if v_tid is null then raise exception 'no trip yet'; end if;

  select * into v_trip from trips where id = v_tid and profile_id = v_pid;
  if not found then raise exception 'trip not found'; end if;

  -- Default the day sensibly: the event's own date if it has one, else the
  -- first day of the trip, else today.
  select coalesce(
           p_day,
           (select e.starts_at::date from experiences e where e.id = p_experience_id),
           v_trip.start_date,
           current_date)
    into v_day;

  -- Keep the stop inside the trip window rather than silently creating a day
  -- that is not part of the journey.
  if v_trip.start_date is not null and v_day < v_trip.start_date then
    v_day := v_trip.start_date;
  end if;
  if v_trip.end_date is not null and v_day > v_trip.end_date then
    v_day := v_trip.end_date;
  end if;

  select coalesce(max(position), 0) + 1 into v_pos
    from itinerary_entries where trip_id = v_tid and day = v_day;

  insert into itinerary_entries (trip_id, profile_id, experience_id, day, position, planned_start)
  values (v_tid, v_pid, p_experience_id, v_day, v_pos,
          coalesce(p_planned_start,
                   (select e.starts_at::time from experiences e where e.id = p_experience_id)))
  on conflict (trip_id, experience_id) do update
     set day = excluded.day, planned_start = excluded.planned_start
  returning id into v_id;

  insert into saved_items (profile_id, experience_id)
  values (v_pid, p_experience_id) on conflict do nothing;

  -- Committing overrides an earlier swipe-left; without this a row could be
  -- both dismissed and scheduled, dropping out of scoring entirely.
  delete from dismissed_items where profile_id = v_pid and experience_id = p_experience_id;

  return jsonb_build_object('entry_id', v_id, 'trip_id', v_tid,
                            'experience_id', p_experience_id,
                            'day', v_day, 'in_itinerary', true);
end;
$$;

create or replace function remove_from_itinerary(
  p_experience_id uuid,
  p_trip_id       uuid default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_tid uuid := coalesce(p_trip_id, current_trip_id());
begin
  delete from itinerary_entries
   where profile_id = current_profile_id()
     and experience_id = p_experience_id
     and (v_tid is null or trip_id = v_tid);
  return jsonb_build_object('experience_id', p_experience_id, 'in_itinerary', false);
end;
$$;

create or replace function update_itinerary_entry(
  p_entry_id      uuid,
  p_day           date default null,
  p_planned_start time default null,
  p_planned_end   time default null,
  p_position      integer default null,
  p_note          text default null
)
returns itinerary_entries
language plpgsql security definer set search_path = public as $$
declare v_row itinerary_entries;
begin
  update itinerary_entries
     set day           = coalesce(p_day, day),
         planned_start = coalesce(p_planned_start, planned_start),
         planned_end   = coalesce(p_planned_end, planned_end),
         position      = coalesce(p_position, position),
         note          = coalesce(p_note, note)
   where id = p_entry_id and profile_id = current_profile_id()
  returning * into v_row;

  if not found then raise exception 'itinerary entry not found'; end if;
  return v_row;
end;
$$;

-- The itinerary tab: days in order, stops in order, ready to render as a
-- timeline without the client regrouping anything.
create or replace function my_itinerary(p_trip_id uuid default null)
returns jsonb language sql stable as $$
  with t as (select coalesce(p_trip_id, current_trip_id()) as tid)
  select jsonb_build_object(
    'trip', (select jsonb_build_object(
               'trip_id', tr.id, 'name', tr.name, 'city', c.name_en,
               'neighborhood', n.name_en,
               'start_date', tr.start_date, 'end_date', tr.end_date,
               'duration_days', tr.duration_days, 'party', tr.party,
               'budget', tr.budget, 'pace', tr.pace, 'status', tr.status)
              from trips tr
              left join cities c        on c.id = tr.city_id
              left join neighborhoods n on n.id = tr.neighborhood_id
             where tr.id = (select tid from t)
               and tr.profile_id = current_profile_id()),
    'days', coalesce((
      select jsonb_agg(day_row order by day_row->>'day')
        from (
          select jsonb_build_object(
                   'day', i.day,
                   'stop_count', count(*),
                   'total_price_yen', sum(k.price_yen),
                   'stops', jsonb_agg(jsonb_build_object(
                     'entry_id', i.id, 'experience_id', k.experience_id,
                     'position', i.position,
                     'planned_start', i.planned_start, 'planned_end', i.planned_end,
                     'note', i.note,
                     'name', k.name, 'category', k.category,
                     'city', k.city, 'neighborhood', k.neighborhood,
                     'venue_name', k.venue_name, 'address', k.address,
                     'lat', k.lat, 'lng', k.lng,
                     'starts_at', k.starts_at, 'duration_min', k.duration_min,
                     'is_free', k.is_free, 'price_yen', k.price_yen,
                     'booking_url', k.booking_url, 'stay22_url', k.stay22_url,
                     'thumbnail_url', k.media_thumbnail_url, 'host_name', k.host_name
                   ) order by i.position, i.planned_start)
                 ) as day_row
            from itinerary_entries i
            join experience_cards k on k.experience_id = i.experience_id
           where i.trip_id = (select tid from t)
             and i.profile_id = current_profile_id()
           group by i.day
        ) days), '[]'::jsonb)
  );
$$;

-- ═══ supabase/migrations/0004_rls.sql ═══
-- Row Level Security.
--
-- Authorization lives in the database, not in application code. There is no
-- endpoint a developer can forget to guard, and the UI team never reasons about
-- permissions — they call as the signed-in user and receive exactly what that
-- user is allowed to see.
--
--   * The catalogue and the vocabularies are public read. It is a discovery
--     app; browsing has to work before anyone signs up.
--   * Everything personal — taste, trips, saves, dismissals, itinerary — is
--     readable and writable only by its owner.

alter table countries          enable row level security;
alter table interests          enable row level security;
alter table travel_reasons     enable row level security;
alter table cities             enable row level security;
alter table neighborhoods      enable row level security;
alter table hosts              enable row level security;
alter table experiences        enable row level security;
alter table experience_media   enable row level security;
alter table profiles           enable row level security;
alter table traveler_profiles  enable row level security;
alter table trips              enable row level security;
alter table saved_items        enable row level security;
alter table dismissed_items    enable row level security;
alter table share_events       enable row level security;
alter table itinerary_entries  enable row level security;

-- ------------------------------------------ public catalogue & vocabulary --

create policy countries_read      on countries        for select using (true);
create policy interests_read      on interests        for select using (true);
create policy reasons_read        on travel_reasons   for select using (true);
create policy cities_read         on cities           for select using (true);
create policy neighborhoods_read  on neighborhoods    for select using (true);
create policy hosts_read          on hosts            for select using (true);
create policy experiences_read    on experiences      for select using (published);
create policy media_read          on experience_media for select using (true);

-- --------------------------------------------------------------- identity --

-- Display names appear on shared itineraries, so profiles are readable. The
-- free-text `about` is personalisation input rather than anything rendered for
-- other people.
create policy profiles_read      on profiles for select using (true);
create policy profiles_write_own on profiles for update
  using      (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- ------------------------------------------------------------- owned data --

create policy taste_own on traveler_profiles for all
  using      (profile_id = current_profile_id())
  with check (profile_id = current_profile_id());

create policy trips_own on trips for all
  using      (profile_id = current_profile_id())
  with check (profile_id = current_profile_id());

create policy saved_own on saved_items for all
  using      (profile_id = current_profile_id())
  with check (profile_id = current_profile_id());

create policy dismissed_own on dismissed_items for all
  using      (profile_id = current_profile_id())
  with check (profile_id = current_profile_id());

create policy itinerary_own on itinerary_entries for all
  using      (profile_id = current_profile_id())
  with check (profile_id = current_profile_id());

-- Aggregate share counts are public social proof (denormalised onto
-- experiences); who shared what is not.
create policy shares_insert_own on share_events for insert
  with check (profile_id = current_profile_id() or profile_id is null);

create policy shares_read_own on share_events for select
  using (profile_id = current_profile_id());

-- ═══ supabase/migrations/0005_age_band.sql ═══
-- Age, collected at signup.
--
-- A BAND, not a birthday. It is the least data that does the job, it never goes
-- stale the way a stored integer does, and it is materially less regulated
-- personal data than a date of birth.
--
-- It also does real work rather than sitting in a profile screen: `under_18`
-- filters bars and nightclubs out of the feed entirely. That is a hard filter,
-- not a scoring nudge — "ranked lower" is not an acceptable answer to "should a
-- minor be shown a nightclub".

create type age_band as enum
  ('under_18', '18_24', '25_34', '35_44', '45_54', '55_plus', 'undisclosed');

alter table profiles
  add column if not exists age_band age_band not null default 'undisclosed';

-- Tags and categories that require an adult. Kept as a function rather than
-- hardcoded into the scoring SQL so the policy is stated in one place and can
-- be audited.
create or replace function is_adults_only(p_category text, p_tags text[])
returns boolean language sql immutable as $$
  select p_category = 'nightlife'
      or p_tags && array['nightlife', 'bar', 'club', 'alcohol', 'sake', 'izakaya'];
$$;

-- update_profile gains age_band. Same COALESCE-per-field shape as before, so a
-- screen can save one field without clobbering the others.
--
-- The old three-argument version has to be dropped explicitly: adding a
-- parameter creates an OVERLOAD rather than replacing the function, and a
-- client calling update_profile with three arguments would silently reach the
-- version that cannot set age_band. Postgres will not warn about this.
drop function if exists update_profile(text, text, text);

create or replace function update_profile(
  p_display_name text default null,
  p_avatar_url   text default null,
  p_about        text default null,
  p_age_band     age_band default null
)
returns profiles
language plpgsql security definer set search_path = public as $$
declare v_row profiles;
begin
  update profiles
     set display_name = coalesce(p_display_name, display_name),
         avatar_url   = coalesce(p_avatar_url,   avatar_url),
         about        = coalesce(p_about,        about),
         age_band     = coalesce(p_age_band,     age_band)
   where id = current_profile_id()
  returning * into v_row;

  if not found then raise exception 'not signed in'; end if;
  return v_row;
end;
$$;

-- Surface it on the profile screen payload.
create or replace function my_profile()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'profile_id',   p.id,
    'display_name', p.display_name,
    'avatar_url',   p.avatar_url,
    'about',        p.about,
    'age_band',     p.age_band,
    'onboarded',    coalesce(tp.onboarded, false),
    'interests',    coalesce(tp.interests, '{}'),
    'countries',    coalesce(tp.countries, '{}'),
    'reasons',      coalesce(tp.reasons,   '{}'),
    'saved_count',  (select count(*) from saved_items s where s.profile_id = p.id),
    'trip_count',   (select count(*) from trips t where t.profile_id = p.id),
    'active_trip',  current_trip_id()
  )
  from profiles p
  left join traveler_profiles tp on tp.profile_id = p.id
  where p.id = current_profile_id();
$$;

-- Onboarding needs to render the band picker from the API like every other
-- vocabulary, so it does not drift from the enum.
create or replace function onboarding_options()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'countries', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'code', code, 'name', name_en, 'emoji', emoji,
               'available', available) order by sort, name_en), '[]'::jsonb)
        from countries),
    'interests', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'slug', slug, 'label', label_en, 'emoji', emoji) order by sort), '[]'::jsonb)
        from interests),
    'reasons', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'slug', slug, 'label', label_en, 'emoji', emoji) order by sort), '[]'::jsonb)
        from travel_reasons),
    'age_bands', jsonb_build_array(
      jsonb_build_object('slug','under_18',   'label','Under 18'),
      jsonb_build_object('slug','18_24',      'label','18–24'),
      jsonb_build_object('slug','25_34',      'label','25–34'),
      jsonb_build_object('slug','35_44',      'label','35–44'),
      jsonb_build_object('slug','45_54',      'label','45–54'),
      jsonb_build_object('slug','55_plus',    'label','55+'),
      jsonb_build_object('slug','undisclosed','label','Rather not say'))
  );
$$;

-- ---------------------------------------------------------- scoring update --

-- Rebuilt only to add the adults-only exclusion. Everything else is unchanged
-- from 0002; the filter sits in the same WHERE clause as the dismissal
-- exclusion, so a minor never sees the row at all rather than seeing it ranked
-- low. 'undisclosed' is treated as an adult — the band is optional, and
-- refusing to answer must not silently degrade the product.
create or replace function experience_scores(p_profile uuid, p_trip uuid default null)
returns table (experience_id uuid, score numeric, reasons text[])
language sql stable
as $$
  with me as (
    select coalesce(tp.interests, '{}')::text[] as interests,
           coalesce(tp.countries, '{}')::text[] as countries,
           coalesce(tp.reasons,   '{}')::text[] as reasons,
           lower(coalesce(pr.about, ''))        as about,
           coalesce(pr.age_band, 'undisclosed') as age_band
      from (select 1) _
      left join profiles pr          on pr.id = p_profile
      left join traveler_profiles tp on tp.profile_id = p_profile
  ),
  trip as (
    select t.id, t.city_id, t.neighborhood_id, t.start_date, t.end_date,
           t.budget, t.party, t.pace,
           c.name_en as trip_city, n.name_en as trip_hood
      from trips t
      left join cities c        on c.id = t.city_id
      left join neighborhoods n on n.id = t.neighborhood_id
     where t.id = p_trip
  ),
  affinity as (
    select e.category as cat,
           count(s.profile_id) as saved_n,
           count(d.profile_id) as dismissed_n
      from experiences e
      left join saved_items     s on s.experience_id = e.id and s.profile_id = p_profile
      left join dismissed_items d on d.experience_id = e.id and d.profile_id = p_profile
     group by e.category
  ),
  base as (
    select e.*,
           c.name_en as city_name, c.country_code,
           me.interests, me.countries, me.reasons, me.about,
           t.id as trip_id, t.trip_city, t.trip_hood,
           t.budget as trip_budget, t.party as trip_party,
           coalesce(a.saved_n, 0)     as cat_saved,
           coalesce(a.dismissed_n, 0) as cat_dismissed,

           (e.category = any (me.interests) or e.tags && me.interests) as hits_interest,
           (select i.label_en from interests i
             where i.slug = any (me.interests)
               and (i.slug = e.category or i.slug = any (e.tags))
             order by (i.slug = e.category) desc limit 1)               as matched_interest,
           (e.tags && me.reasons or e.category = any (me.reasons))      as hits_reason,
           (me.countries <> '{}' and c.country_code = any (me.countries)) as hits_country,

           (t.id is not null)                                           as planning,
           (t.city_id is not null and e.city_id = t.city_id)            as hits_city,
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
      left join affinity a on a.cat = e.category
     where e.published
       and not exists (select 1 from dismissed_items d
                        where d.experience_id = e.id and d.profile_id = p_profile)
       -- Hard exclusion, not a penalty.
       and not (me.age_band = 'under_18' and is_adults_only(e.category, e.tags))
  )
  select
    b.id,
    round((
        case when b.hits_interest then 3.0 else 0 end
      + case when b.hits_reason   then 1.2 else 0 end
      + case when b.hits_country  then 0.8 else 0 end
      + case when not b.planning        then 0
             when b.city_id is not null and b.hits_city then 2.5
             when b.trip_city is null   then 0
             else                            -3.5 end
      + case when b.hits_hood then 1.0 else 0 end
      + case when b.in_trip_window then 2.5
             when b.always_on      then 0.8
             when b.outside_trip   then -2.0
             else 0 end
      + case when not b.planning  then 0
             when b.fits_budget   then 1.5
             else -1.0 - least(3.5,
                    b.price_yen::numeric
                    / greatest(1, budget_ceiling_yen(b.trip_budget)) - 1) end
      + case when b.fits_style then 1.0 else 0 end
      + least(1.5, b.cat_saved * 0.5)
      - least(2.0, b.cat_dismissed * 0.75)
      + b.locality * 1.2
      + case when b.hits_about then 1.5 else 0 end
      + case when b.soon       then 0.8 else 0 end
      + least(1.0, ln(b.save_count + 1) * 0.25)
    )::numeric, 3) as score,

    array_remove(array[
      case when b.matched_interest is not null
             then 'Because you like ' || lower(b.matched_interest) end,
      case when b.hits_interest and b.matched_interest is null
             then 'Matches your interests' end,
      case when b.hits_hood then 'In ' || b.trip_hood || ', where you are staying' end,
      case when b.in_trip_window and b.hits_city
             then 'Happening during your ' || b.trip_city || ' dates' end,
      case when b.in_trip_window and not b.hits_city
             then 'Happening while you are there' end,
      case when b.hits_city and not b.hits_hood and not b.in_trip_window
             then 'In ' || b.city_name end,
      case when b.hits_reason and not b.hits_interest then 'Fits why you travel' end,
      case when b.hits_about     then 'Matches what you wrote on your profile' end,
      case when b.soon           then 'Happening this week' end,
      case when b.locality >= 0.7 then 'Locally hosted, not on the tourist trail' end,
      case when b.is_free        then 'Free' end,
      case when b.fits_style     then 'Good for ' || b.trip_party::text || ' travel' end,
      case when b.cat_saved > 0  then 'You have saved ' || b.category || ' before' end
    ], null) as reasons
  from base b;
$$;
