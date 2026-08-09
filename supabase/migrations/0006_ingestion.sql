-- Support for the ingestion lane.
--
-- Everything here is written by service-role scripts running BEFORE a demo, and
-- read by the app afterwards. Nothing in this file is on the request path.

-- Bounding boxes so an Overpass query knows what to ask for.
alter table cities
  add column if not exists bbox_min_lng double precision,
  add column if not exists bbox_min_lat double precision,
  add column if not exists bbox_max_lng double precision,
  add column if not exists bbox_max_lat double precision;

-- Provenance and localness inputs, captured at ingest.
--
-- `source` matters beyond bookkeeping: hand-curated rows carry deliberately
-- tuned locality values, and the bulk scorer must not overwrite them.
alter table experiences
  add column if not exists source          text not null default 'manual',
  add column if not exists osm_id          bigint,
  add column if not exists has_wikidata    boolean not null default false,
  add column if not exists is_chain        boolean not null default false,
  add column if not exists tourist_density integer not null default 0;

create index if not exists experiences_locality_idx on experiences (locality desc);
create index if not exists experiences_source_idx   on experiences (source);

-- Lets ingestion upsert on re-run instead of duplicating the city every time.
create unique index if not exists experiences_osm_id_key
  on experiences (osm_id) where osm_id is not null;

-- ------------------------------------------------------ neighbourhood snap --

-- Overpass returns coordinates, not neighbourhoods. Snapping each experience to
-- its nearest neighbourhood centroid is what makes "In Tenma, where you are
-- staying" possible — the single strongest proximity signal in scoring.
--
-- 2 km cap so a place on the edge of the city is left unassigned rather than
-- being claimed by a neighbourhood it is nowhere near.
create or replace function attach_neighborhoods(p_city_id uuid default null)
returns integer
language plpgsql
as $$
declare v_updated integer;
begin
  -- A correlated scalar subquery, not UPDATE … FROM LATERAL: Postgres does not
  -- let a LATERAL in the FROM clause reference the UPDATE's target row.
  update experiences e
     set neighborhood_id = (
       select n.id
         from neighborhoods n
        where n.city_id = e.city_id
          and st_dwithin(n.center, e.point, 2000)
        order by st_distance(n.center, e.point)
        limit 1)
   where p_city_id is null or e.city_id = p_city_id;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

-- ---------------------------------------------------------------- localness --

-- The product promises local experiences over guidebook ones, so "local" has to
-- be a number the ranking can use rather than a vibe.
--
-- The honest signal turns out to be geospatial rather than tag-based: count the
-- famous things within 250 m. A cafe beside a major shrine sits in a tourist
-- zone whatever its own tags claim, and an identical cafe two neighbourhoods
-- away does not.
-- p_force exists because the first run of this taught us something: scoring
-- every row flattened the hand-curated seed to a single value, because seeded
-- rows have no wikidata tag, no chain marker, and no dense neighbours. Bulk
-- ingested rows get scored; curated rows keep the locality a human chose,
-- unless you explicitly ask otherwise.
create or replace function recompute_localness(
  p_city_id uuid default null,
  p_force   boolean default false
)
returns integer
language plpgsql
as $$
declare v_updated integer;
begin
  -- The host join lives inside the CTE. An UPDATE's FROM clause cannot join
  -- against the target row, so pulling is_local through the CTE is the only
  -- legal way to use it in the SET expression.
  with density as (
    select e.id,
           (select count(*)
              from experiences n
             where n.id <> e.id
               and n.city_id = e.city_id
               and (n.has_wikidata or n.category = 'attraction')
               and st_dwithin(n.point, e.point, 250)
           )::integer            as d,
           coalesce(h.is_local, true) as host_local
      from experiences e
      left join hosts h on h.id = e.host_id
     where (p_city_id is null or e.city_id = p_city_id)
       and (p_force or e.source = 'overpass')
  )
  update experiences e
     set tourist_density = density.d,
         locality = greatest(0, least(1,
             0.55
           - case when e.has_wikidata            then 0.30 else 0 end
           - case when e.category = 'attraction' then 0.20 else 0 end
           - case when e.is_chain                then 0.20 else 0 end
           - least(0.25, density.d * 0.03)
           + case when density.host_local        then 0.20 else 0 end
         ))
    from density
   where density.id = e.id;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

-- Bounding box values live in seed.sql, alongside the cities they belong to.
-- Setting them here would be a no-op: migrations run before the seed, so there
-- would be no rows to update.
