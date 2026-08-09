-- Onboarding, cut to one screen.
--
-- Four question screens is a form, and a form is where casual users leave.
-- Spotify asks one thing — tap some artists — and it works because tapping
-- album art feels like play while a checklist feels like admin. The taps also
-- carry far more signal than a checkbox: choosing three cards reveals category,
-- price tolerance, and how touristy you like things, all at once.
--
-- So: ONE screen. "Tap three that look good." Everything else is learned from
-- behaviour, and the algorithm does the work instead of the traveler.
--
--   asked      3 taps  (+ an optional country, pre-filled)
--   derived    interests, category affinity, locality preference
--   learned    every swipe, save, dismissal, and itinerary add, forever
--
-- Declared interests survive as an OPTIONAL override on the profile screen for
-- the minority who want to curate. They are no longer the primary input.

-- ------------------------------------------------------------- the picker --

-- Twelve cards for the cold-start screen: visually distinct, one per category,
-- and deliberately spread across the locality range so the very first taps
-- tell us whether this person wants landmarks or back streets.
create or replace function cold_start_picks(
  p_country text default 'JP',
  p_limit   integer default 12
)
returns table (
  experience_id uuid, name text, short_description text, category text,
  city text, neighborhood text, is_free boolean, price_yen integer,
  locality numeric, thumbnail_url text
)
language sql stable as $$
  with ranked as (
    select k.*,
           row_number() over (
             partition by k.category
             order by k.save_count desc, k.experience_id
           ) as rn
      from experience_cards k
     where k.published
       and (p_country is null or k.country_code = p_country)
  )
  select r.experience_id, r.name, r.short_description, r.category,
         r.city, r.neighborhood, r.is_free, r.price_yen,
         r.locality, r.media_thumbnail_url
    from ranked r
   where r.rn = 1                       -- one per category keeps it diverse
   order by r.locality desc, r.save_count desc
   limit p_limit;
$$;

-- One call finishes onboarding. The taps become real saves, so the traveler
-- lands on a Saved tab that already has something in it — the first screen
-- after signup is never empty.
create or replace function complete_cold_start(
  p_experience_ids uuid[],
  p_countries      text[] default '{}'
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_pid       uuid := current_profile_id();
  v_derived   text[];
  v_countries text[];
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  insert into saved_items (profile_id, experience_id)
  select v_pid, unnest(p_experience_ids)
  on conflict do nothing;

  -- Interests are inferred from what they tapped, not asked for. Categories and
  -- tags of the chosen cards, intersected with the real interest vocabulary so
  -- incidental tags like 'romantic' never leak in as an interest.
  select coalesce(array_agg(distinct i.slug), '{}')
    into v_derived
    from experiences e
    join interests i
      on i.slug = e.category or i.slug = any (e.tags)
   where e.id = any (p_experience_ids);

  -- If they never named a country, infer it from the taps.
  v_countries := case
    when p_countries <> '{}' then p_countries
    else coalesce((select array_agg(distinct c.country_code)
                     from experiences e join cities c on c.id = e.city_id
                    where e.id = any (p_experience_ids)), '{}')
  end;

  insert into traveler_profiles (profile_id, interests, countries, reasons, onboarded)
  values (v_pid, v_derived, v_countries, '{}', true)
  on conflict (profile_id) do update
     set interests  = excluded.interests,
         countries  = excluded.countries,
         onboarded  = true,
         updated_at = now();

  return jsonb_build_object(
    'onboarded', true,
    'saved', coalesce(array_length(p_experience_ids, 1), 0),
    'derived_interests', v_derived,
    'countries', v_countries);
end;
$$;

-- ---------------------------------------------------------- learned taste --

-- What behaviour says, as opposed to what the traveler declared. Weighted by
-- how much each action costs: putting something in an itinerary is a much
-- stronger statement than tapping a card during onboarding.
create or replace function interest_affinity(p_profile uuid)
returns table (slug text, weight numeric)
language sql stable as $$
  with signals as (
    select e.category as cat, e.tags, 1.0::numeric as w
      from saved_items s join experiences e on e.id = s.experience_id
     where s.profile_id = p_profile
    union all
    select e.category, e.tags, 1.5
      from itinerary_entries i join experiences e on e.id = i.experience_id
     where i.profile_id = p_profile
    union all
    select e.category, e.tags, -0.75
      from dismissed_items d join experiences e on e.id = d.experience_id
     where d.profile_id = p_profile
  ),
  spread as (
    select i.slug, s.w
      from signals s
      join interests i on i.slug = s.cat or i.slug = any (s.tags)
  )
  select spread.slug, round(sum(spread.w), 2) as weight
    from spread
   group by spread.slug
  having sum(spread.w) <> 0
   order by weight desc;
$$;

-- How much to trust behaviour over the initial taps. Ramps from 0 to 1 across
-- roughly twenty interactions, so a brand-new account leans on its cold start
-- and a returning one is driven almost entirely by what it has actually done.
create or replace function learned_confidence(p_profile uuid)
returns numeric language sql stable as $$
  select least(1.0, round((
    (select count(*) from saved_items      where profile_id = p_profile)
  + (select count(*) from dismissed_items  where profile_id = p_profile)
  + (select count(*) from itinerary_entries where profile_id = p_profile) * 2
  )::numeric / 20.0, 3));
$$;

-- ------------------------------------------------------------- scoring v2 --

-- Same shape as before; the interest term is now a blend. Declared interests
-- carry a new account, learned affinity takes over as evidence accumulates.
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
    select t.id, t.city_id, t.neighborhood_id, t.start_date, t.end_date,
           t.budget, t.party, c.name_en as trip_city, n.name_en as trip_hood
      from trips t
      left join cities c        on c.id = t.city_id
      left join neighborhoods n on n.id = t.neighborhood_id
     where t.id = p_trip
  ),
  base as (
    select e.*,
           c.name_en as city_name, c.country_code,
           me.interests, me.countries, me.reasons, me.about, me.conf,
           t.id as trip_id, t.trip_city, t.trip_hood,
           t.budget as trip_budget, t.party as trip_party,

           (e.category = any (me.interests) or e.tags && me.interests) as hits_interest,
           (select i.label_en from interests i
             where i.slug = any (me.interests)
               and (i.slug = e.category or i.slug = any (e.tags))
             order by (i.slug = e.category) desc limit 1)              as matched_interest,

           -- Behavioural score for this row: the strongest affinity among its
           -- own category and tags, positive or negative.
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
     where e.published
       and not exists (select 1 from dismissed_items d
                        where d.experience_id = e.id and d.profile_id = p_profile)
       and not (me.age_band = 'under_18' and is_adults_only(e.category, e.tags))
  )
  select
    b.id,
    round((
      -- Declared taste fades as behaviour accumulates; learned taste rises to
      -- meet it. At conf = 0 this is exactly the old scoring.
        case when b.hits_interest then 3.0 * (1 - b.conf * 0.6) else 0 end
      + b.conf * (least(2.0, b.learn_pos * 0.6) + greatest(-2.0, b.learn_neg * 0.6))

      + case when b.hits_reason  then 1.2 else 0 end
      + case when b.hits_country then 0.8 else 0 end
      + case when not b.planning        then 0
             when b.city_id is not null and b.hits_city then 2.5
             when b.trip_city is null   then 0
             else                            -3.5 end
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
      -- Behaviour explains itself first once we have enough of it. "More like
      -- what you have been saving" is both truer and more persuasive than
      -- repeating a preference the traveler set weeks ago.
      case when b.conf >= 0.3 and b.learn_pos >= 1.5 and b.learned_slug is not null
             then 'More like the ' || b.learned_slug || ' you keep saving' end,
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
      case when b.hits_about      then 'Matches what you wrote on your profile' end,
      case when b.soon            then 'Happening this week' end,
      case when b.locality >= 0.7 then 'Locally hosted, not on the tourist trail' end,
      case when b.is_free         then 'Free' end,
      case when b.fits_style      then 'Good for ' || b.trip_party::text || ' travel' end
    ], null) as reasons
  from base b;
$$;

-- Expose the learning state so the profile screen can show it honestly —
-- "we have learned this much about you" is itself a retention mechanic.
create or replace function my_taste()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'confidence', learned_confidence(current_profile_id()),
    'declared',   coalesce((select interests from traveler_profiles
                             where profile_id = current_profile_id()), '{}'),
    'learned',    coalesce((select jsonb_agg(jsonb_build_object('slug', slug, 'weight', weight))
                              from interest_affinity(current_profile_id())), '[]'::jsonb));
$$;
