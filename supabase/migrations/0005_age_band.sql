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
