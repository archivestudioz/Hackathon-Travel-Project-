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
