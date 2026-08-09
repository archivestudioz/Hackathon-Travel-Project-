-- The action surface.
--
-- Every interactive element in the product spec maps to exactly one function
-- here. If a screen needs something this file does not expose, that is a gap in
-- the engine, not something the UI should work around with raw table access.
--
-- All writes resolve the caller through current_profile_id(); no function takes
-- a profile id as an argument, so a client cannot act as another traveler.

-- ------------------------------------------------------------- onboarding --

-- Everything the onboarding screen needs to render itself: the interest
-- vocabulary, the cities, and their neighborhoods. Returned as one document so
-- onboarding costs a single request.
create or replace function onboarding_options()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'interests', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'slug', slug, 'label', label_en, 'emoji', emoji) order by sort), '[]'::jsonb)
        from interests),
    'cities', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'slug', c.slug, 'name', c.name_en, 'name_ja', c.name_ja,
               'lat', c.center_lat, 'lng', c.center_lng,
               'neighborhoods', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'slug', n.slug, 'name', n.name_en, 'blurb', n.blurb)
                        order by n.name_en), '[]'::jsonb)
                   from neighborhoods n where n.city_id = c.id)
             ) order by c.name_en), '[]'::jsonb)
        from cities c),
    'budgets', jsonb_build_array(
      jsonb_build_object('slug','shoestring',  'label','Shoestring',  'ceiling_yen',1500),
      jsonb_build_object('slug','moderate',    'label','Moderate',    'ceiling_yen',5000),
      jsonb_build_object('slug','comfortable', 'label','Comfortable', 'ceiling_yen',15000),
      jsonb_build_object('slug','splurge',     'label','Splurge',     'ceiling_yen',null)),
    'styles', jsonb_build_array(
      jsonb_build_object('slug','solo','label','Solo'),
      jsonb_build_object('slug','couple','label','Couple'),
      jsonb_build_object('slug','family','label','Family'),
      jsonb_build_object('slug','group','label','Group'))
  );
$$;

create or replace function save_onboarding(
  p_interests     text[]       default '{}',
  p_destinations  text[]       default '{}',
  p_neighborhoods text[]       default '{}',
  p_trip_start    date         default null,
  p_trip_end      date         default null,
  p_budget        budget_level default 'moderate',
  p_style         travel_style default 'solo'
)
returns traveler_preferences
language plpgsql security definer set search_path = public as $$
declare
  v_pid uuid := current_profile_id();
  v_row traveler_preferences;
begin
  if v_pid is null then
    raise exception 'not signed in';
  end if;

  insert into traveler_preferences (
    profile_id, interests, destinations, neighborhoods,
    trip_start, trip_end, budget, style, onboarded)
  values (v_pid, p_interests, p_destinations, p_neighborhoods,
          p_trip_start, p_trip_end, p_budget, p_style, true)
  on conflict (profile_id) do update
     set interests     = excluded.interests,
         destinations  = excluded.destinations,
         neighborhoods = excluded.neighborhoods,
         trip_start    = excluded.trip_start,
         trip_end      = excluded.trip_end,
         budget        = excluded.budget,
         style         = excluded.style,
         onboarded     = true,
         updated_at    = now()
  returning * into v_row;

  return v_row;
end;
$$;

-- The profile screen: display name, avatar, and the free-text box whose
-- contents feed back into scoring.
create or replace function update_profile(
  p_display_name text default null,
  p_avatar_url   text default null,
  p_about        text default null
)
returns profiles
language plpgsql security definer set search_path = public as $$
declare
  v_row profiles;
begin
  update profiles
     set display_name = coalesce(p_display_name, display_name),
         avatar_url   = coalesce(p_avatar_url,   avatar_url),
         about        = coalesce(p_about,        about)
   where id = current_profile_id()
  returning * into v_row;

  if not found then
    raise exception 'not signed in';
  end if;
  return v_row;
end;
$$;

-- Whole profile screen in one call: identity, preferences, and counts.
create or replace function my_profile()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'profile_id',   p.id,
    'display_name', p.display_name,
    'avatar_url',   p.avatar_url,
    'about',        p.about,
    'onboarded',    coalesce(tp.onboarded, false),
    'interests',    coalesce(tp.interests, '{}'),
    'destinations', coalesce(tp.destinations, '{}'),
    'neighborhoods',coalesce(tp.neighborhoods, '{}'),
    'trip_start',   tp.trip_start,
    'trip_end',     tp.trip_end,
    'budget',       coalesce(tp.budget, 'moderate'),
    'style',        coalesce(tp.style,  'solo'),
    'saved_count',     (select count(*) from saved_items       s where s.profile_id = p.id),
    'itinerary_count', (select count(*) from itinerary_entries i where i.profile_id = p.id)
  )
  from profiles p
  left join traveler_preferences tp on tp.profile_id = p.id
  where p.id = current_profile_id();
$$;

-- ------------------------------------------------------- swipe & save ------

-- Swipe right. Idempotent, because a double-tap should not error.
create or replace function save_experience(p_experience_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_pid uuid := current_profile_id();
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  insert into saved_items (profile_id, experience_id)
  values (v_pid, p_experience_id)
  on conflict do nothing;

  -- Saving overrides an earlier dismissal; the traveler changed their mind.
  delete from dismissed_items
   where profile_id = v_pid and experience_id = p_experience_id;

  return jsonb_build_object(
    'experience_id', p_experience_id, 'is_saved', true,
    'save_count', (select save_count from experiences where id = p_experience_id));
end;
$$;

create or replace function unsave_experience(p_experience_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_pid uuid := current_profile_id();
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  delete from saved_items where profile_id = v_pid and experience_id = p_experience_id;

  return jsonb_build_object(
    'experience_id', p_experience_id, 'is_saved', false,
    'save_count', (select save_count from experiences where id = p_experience_id));
end;
$$;

-- Swipe left.
create or replace function dismiss_experience(p_experience_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_pid uuid := current_profile_id();
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  insert into dismissed_items (profile_id, experience_id)
  values (v_pid, p_experience_id)
  on conflict do nothing;

  delete from saved_items where profile_id = v_pid and experience_id = p_experience_id;

  return jsonb_build_object('experience_id', p_experience_id, 'dismissed', true);
end;
$$;

-- Undo, for the swipe-back affordance every card deck needs.
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

  return jsonb_build_object(
    'experience_id', p_experience_id,
    'share_count', (select share_count from experiences where id = p_experience_id));
end;
$$;

-- ---------------------------------------------------------------- detail --

-- The full experience page in one request: the card, every media item, the
-- host, why it matched, and related experiences.
create or replace function experience_detail(p_experience_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'experience_id',     k.experience_id,
    'name',              k.name,
    'name_ja',           e.name_ja,
    'short_description', k.short_description,
    'description',       e.description,
    'category',          k.category,
    'tags',              k.tags,
    'city',              k.city,
    'neighborhood',      k.neighborhood,
    'venue_name',        k.venue_name,
    'address',           k.address,
    'lat',               k.lat,
    'lng',               k.lng,
    'starts_at',         k.starts_at,
    'ends_at',           k.ends_at,
    'duration_min',      k.duration_min,
    'recurrence_note',   k.recurrence_note,
    'is_free',           k.is_free,
    'price_yen',         k.price_yen,
    'price_note',        k.price_note,
    'booking_url',       k.booking_url,
    'external_url',      k.external_url,
    'stay22_url',        k.stay22_url,
    'save_count',        k.save_count,
    'share_count',       k.share_count,
    'locality',          k.locality,
    'is_saved',      exists (select 1 from saved_items s
                              where s.experience_id = k.experience_id
                                and s.profile_id = current_profile_id()),
    'in_itinerary',  exists (select 1 from itinerary_entries i
                              where i.experience_id = k.experience_id
                                and i.profile_id = current_profile_id()),
    'reasons', coalesce((select sc.reasons from experience_scores(current_profile_id()) sc
                          where sc.experience_id = k.experience_id), '{}'),
    'host', case when e.host_id is null then null else (
      select jsonb_build_object('name', h.name, 'kind', h.kind, 'bio', h.bio,
                                'avatar_url', h.avatar_url, 'website_url', h.website_url,
                                'verified', h.verified, 'is_local', h.is_local)
        from hosts h where h.id = e.host_id) end,
    -- Media is a list of POINTERS with attribution. Embeds resolve client-side
    -- through the official oEmbed endpoints; nothing here is a copied file.
    'media', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'kind', m.kind, 'license', m.license,
               'source_url', m.source_url, 'thumbnail_url', m.thumbnail_url,
               'alt_text', m.alt_text,
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
        from (
          select rc.*
            from experience_cards rc
           where rc.experience_id <> k.experience_id
             and rc.published
             and (rc.category = k.category or rc.tags && k.tags)
           order by (rc.neighborhood_id is not distinct from k.neighborhood_id) desc,
                    rc.save_count desc
           limit 6) r)
  )
  from experience_cards k
  join experiences e on e.id = k.experience_id
  where k.experience_id = p_experience_id;
$$;

-- --------------------------------------------------------------- explore --

-- Search and filters. Every argument is optional so the client can build the
-- query up as the traveler touches controls, without branching on which
-- endpoint to call.
create or replace function explore(
  p_query       text default null,
  p_categories  text[] default null,
  p_city        text default null,      -- city slug
  p_neighborhood text default null,     -- neighborhood slug
  p_from        date default null,
  p_to          date default null,
  p_free_only   boolean default false,
  p_max_price   integer default null,
  p_sort        text default 'recommended',  -- recommended | soonest | price | popular
  p_limit       integer default 40,
  p_offset      integer default 0
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
         coalesce(sc.score, 0), coalesce(sc.reasons, '{}')
    from me
    join experience_cards k on k.published
    left join experience_scores((select pid from me)) sc on sc.experience_id = k.experience_id
    left join saved_items s       on s.experience_id = k.experience_id and s.profile_id = (select pid from me)
    left join itinerary_entries i on i.experience_id = k.experience_id and i.profile_id = (select pid from me)
   where (p_query is null or p_query = ''
          or k.name ilike '%' || p_query || '%'
          or k.short_description ilike '%' || p_query || '%'
          or k.venue_name ilike '%' || p_query || '%'
          or exists (select 1 from unnest(k.tags) tg where tg ilike '%' || p_query || '%'))
     and (p_categories is null or k.category = any (p_categories) or k.tags && p_categories)
     and (p_city is null or k.city_slug = p_city)
     and (p_neighborhood is null or k.neighborhood_slug = p_neighborhood)
     -- An always-on attraction has no date, so it should never be filtered out
     -- by a date range the traveler set to find things happening that week.
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

-- The three curated rails on the Explore screen. Returned as one document
-- because the screen renders them together.
create or replace function explore_sections(p_city text default null, p_limit integer default 8)
returns jsonb language sql stable as $$
  with me as (select current_profile_id() as pid),
  base as (
    select k.*, coalesce(sc.score, 0) as score
      from me
      join experience_cards k on k.published
      left join experience_scores((select pid from me)) sc on sc.experience_id = k.experience_id
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
         order by b.starts_at
         limit p_limit) s),
    -- Locally hosted and comparatively undiscovered. This is the rail that
    -- makes the product about local experience rather than the top-ten list.
    'hidden_local_gems', (
      select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('experience_id', b.experience_id, 'name', b.name,
                 'category', b.category, 'neighborhood', b.neighborhood, 'city', b.city,
                 'starts_at', b.starts_at, 'is_free', b.is_free, 'price_yen', b.price_yen,
                 'thumbnail_url', b.media_thumbnail_url, 'locality', b.locality) as x
          from base b
         where b.locality >= 0.65 and b.host_is_local
         order by b.locality desc, b.save_count asc
         limit p_limit) s),
    'popular_near_you', (
      select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('experience_id', b.experience_id, 'name', b.name,
                 'category', b.category, 'neighborhood', b.neighborhood, 'city', b.city,
                 'starts_at', b.starts_at, 'is_free', b.is_free, 'price_yen', b.price_yen,
                 'thumbnail_url', b.media_thumbnail_url, 'save_count', b.save_count) as x
          from base b
         order by b.save_count desc, b.score desc
         limit p_limit) s)
  );
$$;

-- ------------------------------------------------------------- saved tab --

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
         (i.id is not null), s.created_at
    from saved_items s
    join experience_cards k on k.experience_id = s.experience_id
    left join itinerary_entries i
           on i.experience_id = s.experience_id and i.profile_id = s.profile_id
   where s.profile_id = current_profile_id()
   order by s.created_at desc;
$$;

-- ---------------------------------------------------------- itinerary tab --

-- Adding to the itinerary implies saving: the traveler has committed, so the
-- item should also appear in Saved without a second call.
create or replace function add_to_itinerary(
  p_experience_id uuid,
  p_day           date default null,
  p_planned_start time default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_pid  uuid := current_profile_id();
  v_day  date;
  v_pos  integer;
  v_id   uuid;
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  -- Default the day sensibly: when the experience has a date, use it; failing
  -- that the trip start; failing that today.
  select coalesce(
           p_day,
           (select e.starts_at::date from experiences e where e.id = p_experience_id),
           (select tp.trip_start from traveler_preferences tp where tp.profile_id = v_pid),
           current_date)
    into v_day;

  select coalesce(max(position), 0) + 1 into v_pos
    from itinerary_entries where profile_id = v_pid and day = v_day;

  insert into itinerary_entries (profile_id, experience_id, day, position, planned_start)
  values (v_pid, p_experience_id, v_day, v_pos,
          coalesce(p_planned_start,
                   (select e.starts_at::time from experiences e where e.id = p_experience_id)))
  on conflict (profile_id, experience_id) do update
     set day = excluded.day, planned_start = excluded.planned_start
  returning id into v_id;

  insert into saved_items (profile_id, experience_id)
  values (v_pid, p_experience_id) on conflict do nothing;

  -- Committing to something overrides an earlier swipe-left. Without this a row
  -- can be simultaneously dismissed and scheduled, which drops it out of
  -- scoring and leaves its detail page with no explanation of why it matched.
  delete from dismissed_items
   where profile_id = v_pid and experience_id = p_experience_id;

  return jsonb_build_object('entry_id', v_id, 'experience_id', p_experience_id,
                            'day', v_day, 'in_itinerary', true);
end;
$$;

create or replace function remove_from_itinerary(p_experience_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  delete from itinerary_entries
   where profile_id = current_profile_id() and experience_id = p_experience_id;
  return jsonb_build_object('experience_id', p_experience_id, 'in_itinerary', false);
end;
$$;

create or replace function update_itinerary_entry(
  p_experience_id uuid,
  p_day           date default null,
  p_planned_start time default null,
  p_planned_end   time default null,
  p_position      integer default null,
  p_note          text default null
)
returns itinerary_entries
language plpgsql security definer set search_path = public as $$
declare
  v_row itinerary_entries;
begin
  update itinerary_entries
     set day           = coalesce(p_day, day),
         planned_start = coalesce(p_planned_start, planned_start),
         planned_end   = coalesce(p_planned_end, planned_end),
         position      = coalesce(p_position, position),
         note          = coalesce(p_note, note)
   where profile_id = current_profile_id() and experience_id = p_experience_id
  returning * into v_row;

  if not found then raise exception 'itinerary entry not found'; end if;
  return v_row;
end;
$$;

-- The itinerary screen: days in order, each with its stops in order. Grouped
-- server-side so the client renders a timeline rather than assembling one.
create or replace function my_itinerary()
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(day_row order by day_row->>'day'), '[]'::jsonb)
  from (
    select jsonb_build_object(
             'day', i.day,
             'stop_count', count(*),
             'total_price_yen', sum(k.price_yen),
             'stops', jsonb_agg(jsonb_build_object(
               'entry_id',      i.id,
               'experience_id', k.experience_id,
               'position',      i.position,
               'planned_start', i.planned_start,
               'planned_end',   i.planned_end,
               'note',          i.note,
               'name',          k.name,
               'category',      k.category,
               'city',          k.city,
               'neighborhood',  k.neighborhood,
               'venue_name',    k.venue_name,
               'address',       k.address,
               'lat',           k.lat,
               'lng',           k.lng,
               'starts_at',     k.starts_at,
               'duration_min',  k.duration_min,
               'is_free',       k.is_free,
               'price_yen',     k.price_yen,
               'booking_url',   k.booking_url,
               'stay22_url',    k.stay22_url,
               'thumbnail_url', k.media_thumbnail_url,
               'host_name',     k.host_name
             ) order by i.position, i.planned_start)
           ) as day_row
      from itinerary_entries i
      join experience_cards k on k.experience_id = i.experience_id
     where i.profile_id = current_profile_id()
     group by i.day
  ) days;
$$;
