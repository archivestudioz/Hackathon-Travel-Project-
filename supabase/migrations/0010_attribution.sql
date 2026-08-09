-- Creator attribution, enforced by the database.
--
-- Crediting every creator is product policy: they get real exposure through the
-- app, and that is a genuine part of the value we offer them. An embed links
-- back to their live profile and drives traffic to the actual post, which is
-- worth considerably more to a creator than a name caption under a copied file.
--
-- Because it is policy, it should not depend on a screen remembering to render
-- it. A row that cannot be displayed with credit should not be storable.

-- Every embedded post must carry the creator's name AND a link back. Name
-- alone is a caption; the link is what actually sends them traffic.
alter table experience_media
  drop constraint if exists media_oembed_needs_attribution;

alter table experience_media
  add constraint media_oembed_needs_attribution check (
    license <> 'oembed'
    or (attribution_name is not null and attribution_name <> ''
        and attribution_url is not null and attribution_url <> '')
  );

-- Convenience for the card: one string the UI can render without deciding how
-- to format credit per platform.
create or replace function media_credit(
  p_kind media_kind,
  p_name text,
  p_handle text
)
returns text language sql immutable as $$
  select case
           when p_name is null then null
           when p_handle is not null then p_handle || ' on ' ||
             case p_kind when 'tiktok' then 'TikTok'
                         when 'instagram' then 'Instagram'
                         else 'their channel' end
           else p_name
         end;
$$;

-- Surface credit on the card so it travels with the media rather than needing a
-- second lookup. A card that cannot show credit cannot show the video either.
drop view if exists experience_cards;

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
       m.attribution_handle         as media_attribution_handle,
       m.attribution_url            as media_attribution_url,
       media_credit(m.kind, m.attribution_name, m.attribution_handle)
                                    as media_credit,
       m.license                    as media_license,
       e.save_count, e.share_count, e.locality,
       e.published, e.city_id, e.neighborhood_id
  from experiences e
  join cities c             on c.id = e.city_id
  left join neighborhoods n on n.id = e.neighborhood_id
  left join hosts h         on h.id = e.host_id
  left join experience_media m on m.experience_id = e.id and m.is_primary;



-- Both functions declare an explicit RETURNS TABLE, so the new view columns do
-- NOT propagate on their own. Re-declared here with credit appended to the end,
-- which keeps every existing client field at the same name.
--
-- CREATE OR REPLACE cannot widen a RETURNS TABLE — Postgres rejects it with
-- "cannot change return type of existing function" — so both have to be dropped
-- first. Dropping is safe here: PostgREST resolves functions per request, so
-- there is no window where a client holds a stale reference.
drop function if exists feed(uuid, integer, integer);
drop function if exists explore(text, text[], text, text, date, date, boolean,
                                integer, text, integer, integer);

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
  media_attribution_name text, media_attribution_handle text,
  media_attribution_url text, media_credit text, media_license media_license,
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
         sc.media_attribution_name, sc.media_attribution_handle,
         sc.media_attribution_url, sc.media_credit, sc.media_license,
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
  media_attribution_name text, media_attribution_handle text,
  media_attribution_url text, media_credit text, media_license media_license,
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
         k.media_attribution_name, k.media_attribution_handle,
         k.media_attribution_url, k.media_credit, k.media_license,
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

