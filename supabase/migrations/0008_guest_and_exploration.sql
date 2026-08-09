-- Guest mode, and making a zero-signal feed actually good.
--
-- Every account is already anonymous, so "guest" does not need new auth — it
-- needs a path that skips the three taps and still produces a feed worth
-- scrolling. Two things make that work:
--
--   1. continue_as_guest() marks the traveler onboarded with no declared taste,
--      so nothing downstream has to special-case "never answered".
--
--   2. The feed EXPLORES when it knows nothing. A cold feed ordered purely by
--      score returns five variations on the same category, which is both boring
--      and the slowest possible way to learn anything. Interleaving categories
--      fixes both at once: it reads as variety, and every swipe discriminates
--      between categories instead of within one.
--
-- Exploration decays as confidence rises. A new traveler gets breadth; a
-- returning one gets what they actually like.

alter table profiles
  add column if not exists is_guest boolean not null default false;

-- Skip the taps entirely. Still a real profile with real RLS — the traveler
-- simply has not told us anything yet.
create or replace function continue_as_guest()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_pid uuid := current_profile_id();
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  update profiles set is_guest = true where id = v_pid;

  insert into traveler_profiles (profile_id, interests, countries, reasons, onboarded)
  values (v_pid, '{}', '{}', '{}', true)
  on conflict (profile_id) do update
     set onboarded = true, updated_at = now();

  return jsonb_build_object('guest', true, 'onboarded', true);
end;
$$;

-- A guest who later taps three cards, or saves anything, stops being a guest.
-- Worth tracking separately from `onboarded` because it is the number that
-- tells you whether the skip button is eating your signal.
create or replace function claim_guest_profile(p_display_name text default null)
returns profiles
language plpgsql security definer set search_path = public as $$
declare v_row profiles;
begin
  update profiles
     set is_guest = false,
         display_name = coalesce(p_display_name, display_name)
   where id = current_profile_id()
  returning * into v_row;

  if not found then raise exception 'not signed in'; end if;
  return v_row;
end;
$$;

-- ------------------------------------------------------------ exploration --

-- How much breadth to force into the deck. 1.0 = pure round-robin across
-- categories, 0.0 = pure score order.
create or replace function exploration_weight(p_profile uuid)
returns numeric language sql stable as $$
  select greatest(0.0, 1.0 - learned_confidence(p_profile) / 0.4);
$$;

-- The feed, with exploration. Same columns as before — the UI does not change.
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
    select current_profile_id()                      as pid,
           coalesce(p_trip_id, current_trip_id())    as tid
  ),
  scored as (
    select k.*, sc.score, sc.reasons,
           (i.id is not null) as in_itin,
           -- Rank within each category, so "the best food card" and "the best
           -- art card" can be pulled out together.
           row_number() over (partition by k.category order by sc.score desc) as cat_rank
      from me
      join experience_scores((select pid from me), (select tid from me)) sc on true
      join experience_cards k on k.experience_id = sc.experience_id
      left join saved_items s on s.experience_id = k.experience_id
                             and s.profile_id = (select pid from me)
      left join itinerary_entries i on i.experience_id = k.experience_id
                                   and i.trip_id = (select tid from me)
     where s.profile_id is null      -- decided cards leave the swipe deck
  )
  select sc.experience_id, sc.name, sc.short_description, sc.category, sc.tags,
         sc.city, sc.neighborhood, sc.venue_name,
         sc.starts_at, sc.duration_min, sc.recurrence_note,
         sc.is_free, sc.price_yen, sc.price_note,
         sc.lat, sc.lng,
         sc.host_name, sc.host_verified, sc.host_is_local,
         sc.media_kind, sc.media_source_url, sc.media_thumbnail_url,
         sc.media_attribution_name, sc.media_attribution_url, sc.media_license,
         sc.save_count, sc.share_count,
         false, sc.in_itin,
         sc.score, sc.reasons
    from scored sc, me
   -- With no signal, take one card per category before any second card: the
   -- deck reads as variety and each swipe tells us something new. As confidence
   -- rises the term collapses and pure score ordering takes over.
   order by (sc.cat_rank * exploration_weight((select pid from me))),
            sc.score desc,
            sc.experience_id
   limit p_limit offset p_offset;
$$;
