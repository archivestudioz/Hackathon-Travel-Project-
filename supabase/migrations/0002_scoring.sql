-- Personalisation engine.
--
-- Deterministic, not learned. Two reasons that is the right call here and not
-- just the fast one: a judge can be shown exactly why a card surfaced, and the
-- same inputs always produce the same feed, so a demo cannot embarrass you by
-- ranking differently on the third run.
--
-- Every scoring component also emits a human sentence, so `reasons` is produced
-- by the same pass that produces `score`. They cannot drift apart — the card's
-- explanation is not a separate guess about why it ranked.

create or replace function current_profile_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from profiles where auth_user_id = auth.uid();
$$;

-- What a traveler can comfortably spend on one experience, in yen.
create or replace function budget_ceiling_yen(p_budget budget_level)
returns integer language sql immutable as $$
  select case p_budget
           when 'shoestring'  then 1500
           when 'moderate'    then 5000
           when 'comfortable' then 15000
           else                    1000000
         end;
$$;

-- Tags that signal an experience suits a given party shape.
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

-- Returns a score and its explanation for every published experience.
-- Dismissed experiences are excluded outright rather than down-weighted: a
-- swipe left is an instruction, not a hint.
create or replace function experience_scores(p_profile uuid)
returns table (experience_id uuid, score numeric, reasons text[])
language sql stable
as $$
  with me as (
    select coalesce(tp.interests,     '{}')::text[]   as interests,
           coalesce(tp.destinations,  '{}')::text[]   as destinations,
           coalesce(tp.neighborhoods, '{}')::text[]   as neighborhoods,
           tp.trip_start,
           tp.trip_end,
           coalesce(tp.budget, 'moderate')::budget_level as budget,
           coalesce(tp.style,  'solo')::travel_style     as style,
           lower(coalesce(pr.about, ''))              as about,
           coalesce(tp.onboarded, false)              as onboarded
      from (select 1) _
      left join profiles pr             on pr.id = p_profile
      left join traveler_preferences tp on tp.profile_id = p_profile
  ),
  -- How the traveler has behaved so far, per category. Saves pull a category
  -- up; dismissals push the whole category down, not just the card.
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
           c.slug  as city_slug,
           c.name_en as city_name,
           n.slug  as hood_slug,
           n.name_en as hood_name,
           me.*,
           coalesce(a.saved_n, 0)     as cat_saved,
           coalesce(a.dismissed_n, 0) as cat_dismissed,

           -- interest overlap
           (e.category = any (me.interests) or e.tags && me.interests) as hits_interest,
           -- The specific interest that matched, for the sentence. Checks tags
           -- as well as category, otherwise a food tour tagged 'traditional'
           -- tells a culture traveler only "matches your interests", which is
           -- the vaguest possible version of the truth.
           (select i.label_en
              from interests i
             where i.slug = any (me.interests)
               and (i.slug = e.category or i.slug = any (e.tags))
             order by (i.slug = e.category) desc
             limit 1)                                                  as matched_interest,

           (me.destinations <> '{}')                                   as has_destinations,
           (c.slug = any (me.destinations))                            as hits_city,
           (n.slug is not null and n.slug = any (me.neighborhoods))     as hits_hood,

           -- Date compatibility. An always-on attraction (no start time) is
           -- never "wrong" for a trip window, it just earns less than a thing
           -- happening while you are actually there.
           (e.starts_at is null)                                        as always_on,
           (e.starts_at is not null
             and me.trip_start is not null
             and e.starts_at::date between me.trip_start and coalesce(me.trip_end, me.trip_start))
                                                                        as in_trip_window,
           (e.starts_at is not null
             and me.trip_start is not null
             and e.starts_at::date not between me.trip_start and coalesce(me.trip_end, me.trip_start))
                                                                        as outside_trip,

           (e.is_free or e.price_yen <= budget_ceiling_yen(me.budget))  as fits_budget,
           (style_tag(me.style) = any (e.tags))                         as fits_style,

           -- Free-text from the profile screen, matched against tags. Cheap,
           -- and it makes the box do something real instead of decorating.
           (me.about <> '' and exists (
              select 1 from unnest(e.tags || array[e.category]) tg
               where me.about like '%' || lower(tg) || '%'))            as hits_about,

           (e.starts_at is not null
             and e.starts_at between now() and now() + interval '7 days') as soon
      from experiences e
      join cities c            on c.id = e.city_id
      left join neighborhoods n on n.id = e.neighborhood_id
     cross join me
      left join affinity a      on a.cat = e.category
     where e.published
       and not exists (
             select 1 from dismissed_items d
              where d.experience_id = e.id and d.profile_id = p_profile)
  )
  select
    b.id,
    round((
        case when b.hits_interest  then 3.0 else 0 end
      -- Someone who told us they are going to Kyoto should not be shown Tokyo
      -- at the top of their feed, however well it matches on taste. Naming a
      -- destination is close to a filter, so a wrong city is penalised, not
      -- merely unrewarded.
      + case when not b.has_destinations then 0
             when b.hits_city            then 2.5
             else                            -3.5 end
      + case when b.hits_hood      then 1.0 else 0 end
      + case when b.in_trip_window then 2.5
             when b.always_on      then 0.8
             when b.outside_trip   then -2.0
             else 0 end
      -- Overshooting the budget scales with how badly. A flat penalty let a
      -- 14,000 yen kaiseki outrank free things for a shoestring traveler.
      + case when b.fits_budget then 1.5
             else -1.0 - least(3.5,
                    b.price_yen::numeric / greatest(1, budget_ceiling_yen(b.budget)) - 1)
        end
      + case when b.fits_style     then 1.0 else 0 end
      + least(1.5, b.cat_saved * 0.5)
      - least(2.0, b.cat_dismissed * 0.75)
      + b.locality * 1.2
      + case when b.hits_about then 1.5 else 0 end
      + case when b.soon       then 0.8 else 0 end
      -- Social proof, dampened. Popularity should nudge ordering, never
      -- dominate it, or the feed collapses to the same few cards for everyone.
      + least(1.0, ln(b.save_count + 1) * 0.25)
    )::numeric, 3) as score,

    -- Ordered most-persuasive first; the UI can show just reasons[1].
    array_remove(array[
      case when b.matched_interest is not null
             then 'Because you like ' || lower(b.matched_interest) end,
      case when b.hits_interest and b.matched_interest is null
             then 'Matches your interests' end,
      case when b.hits_hood      then 'In ' || b.hood_name || ', where you are staying' end,
      case when b.in_trip_window and b.hits_city
             then 'Happening during your ' || b.city_name || ' dates' end,
      case when b.in_trip_window and not b.hits_city
             then 'Happening while you are in Japan' end,
      case when b.hits_city and not b.hits_hood and not b.in_trip_window
             then 'In ' || b.city_name end,
      case when b.is_free and not b.fits_budget then null
           when b.fits_budget and b.price_yen > 0 and b.has_destinations
             then 'Within your budget' end,
      case when b.hits_about     then 'Matches what you wrote on your profile' end,
      case when b.soon           then 'Happening this week' end,
      case when b.locality >= 0.7 then 'Locally hosted, not on the tourist trail' end,
      case when b.is_free        then 'Free' end,
      case when b.fits_style     then 'Good for ' || b.style::text || ' travel' end,
      case when b.cat_saved > 0  then 'You have saved ' || b.category || ' before' end
    ], null) as reasons
  from base b;
$$;

-- ------------------------------------------------------------- card shape --

-- Every surface that shows an experience — feed, explore, sections, saved,
-- itinerary — renders the same card. Defining that shape once means the UI
-- team writes one component and one TypeScript type, and a field added here
-- appears everywhere at once instead of in four hand-synced queries.
create view experience_cards
with (security_invoker = true)
as
select e.id                            as experience_id,
       e.name, e.short_description, e.category, e.tags,
       c.name_en                       as city,
       c.slug                          as city_slug,
       n.name_en                       as neighborhood,
       n.slug                          as neighborhood_slug,
       e.venue_name, e.address,
       e.starts_at, e.ends_at, e.duration_min, e.recurrence_note,
       e.is_free, e.price_yen, e.price_note,
       e.lat, e.lng,
       e.booking_url, e.external_url, e.stay22_url,
       h.name                          as host_name,
       coalesce(h.verified,  false)    as host_verified,
       coalesce(h.is_local,  true)     as host_is_local,
       m.kind                          as media_kind,
       m.source_url                    as media_source_url,
       m.thumbnail_url                 as media_thumbnail_url,
       m.attribution_name              as media_attribution_name,
       m.attribution_url               as media_attribution_url,
       m.license                       as media_license,
       e.save_count, e.share_count, e.locality,
       e.published, e.city_id, e.neighborhood_id
  from experiences e
  join cities c             on c.id = e.city_id
  left join neighborhoods n on n.id = e.neighborhood_id
  left join hosts h         on h.id = e.host_id
  left join experience_media m on m.experience_id = e.id and m.is_primary;

-- --------------------------------------------------------------- the feed --

-- One row per card in the swipe feed, already carrying its media, its social
-- proof, whether you have already saved it, and why it surfaced. Rendering a
-- card must never require a second round trip.
create or replace function feed(p_limit integer default 20, p_offset integer default 0)
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
  with me as (select current_profile_id() as pid)
  select k.experience_id, k.name, k.short_description, k.category, k.tags,
         k.city, k.neighborhood, k.venue_name,
         k.starts_at, k.duration_min, k.recurrence_note,
         k.is_free, k.price_yen, k.price_note,
         k.lat, k.lng,
         k.host_name, k.host_verified, k.host_is_local,
         k.media_kind, k.media_source_url, k.media_thumbnail_url,
         k.media_attribution_name, k.media_attribution_url, k.media_license,
         k.save_count, k.share_count,
         (s.profile_id is not null), (i.id is not null),
         sc.score, sc.reasons
    from me
    join experience_scores((select pid from me)) sc on true
    join experience_cards k on k.experience_id = sc.experience_id
    left join saved_items s       on s.experience_id = k.experience_id and s.profile_id = (select pid from me)
    left join itinerary_entries i on i.experience_id = k.experience_id and i.profile_id = (select pid from me)
   -- Already-saved cards drop out of the swipe deck; you have decided on them.
   where s.profile_id is null
   order by sc.score desc, k.save_count desc, k.experience_id
   limit p_limit offset p_offset;
$$;
