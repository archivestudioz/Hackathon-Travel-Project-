drop schema if exists public cascade;
create schema public;
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on schema public to postgres, service_role;


create extension if not exists postgis;
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

create type travel_style   as enum ('solo', 'couple', 'family', 'group');
create type budget_level   as enum ('shoestring', 'moderate', 'comfortable', 'splurge');
create type trip_pace      as enum ('relaxed', 'balanced', 'packed');
create type trip_status    as enum ('planning', 'active', 'past');
create type media_kind     as enum ('tiktok', 'instagram', 'youtube', 'hosted_video', 'image', 'placeholder');
create type media_license  as enum ('oembed', 'owned', 'stock', 'placeholder');
create type host_kind      as enum ('local_business', 'community', 'individual', 'venue', 'institution');

create table countries (
  code       text primary key,              -- ISO 3166-1 alpha-2
  name_en    text not null,
  emoji      text,
  available  boolean not null default false,
  sort       integer not null default 0
);

create table interests (
  slug     text primary key,
  label_en text not null,
  emoji    text,
  sort     integer not null default 0
);

create table travel_reasons (
  slug     text primary key,
  label_en text not null,
  emoji    text,
  sort     integer not null default 0
);

create table cities (
  id           uuid primary key default gen_random_uuid(),
  country_code text not null references countries (code),
  slug         text unique not null,
  name_en      text not null,
  name_ja      text,
  center       geography(Point, 4326) not null,
  center_lat   double precision generated always as (st_y(center::geometry)) stored,
  center_lng   double precision generated always as (st_x(center::geometry)) stored,
  timezone     text not null default 'Asia/Tokyo'
);

create index cities_country_idx on cities (country_code);

create table neighborhoods (
  id      uuid primary key default gen_random_uuid(),
  city_id uuid not null references cities (id) on delete cascade,
  slug    text not null,
  name_en text not null,
  name_ja text,
  center  geography(Point, 4326) not null,
  lat     double precision generated always as (st_y(center::geometry)) stored,
  lng     double precision generated always as (st_x(center::geometry)) stored,
  blurb   text,
  unique (city_id, slug)
);

create index neighborhoods_center_idx on neighborhoods using gist (center);

create table hosts (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  kind        host_kind not null default 'local_business',
  bio         text,
  avatar_url  text,
  website_url text,
  verified    boolean not null default false,
  is_local    boolean not null default true
);

create table experiences (
  id                uuid primary key default gen_random_uuid(),
  city_id           uuid not null references cities (id) on delete cascade,
  neighborhood_id   uuid references neighborhoods (id) on delete set null,
  host_id           uuid references hosts (id) on delete set null,

  name              text not null,
  name_ja           text,
  short_description text not null,
  description       text,

  category          text not null,      -- primary interest slug
  tags              text[] not null default '{}',

  starts_at         timestamptz,        -- null = always-available attraction
  ends_at           timestamptz,
  duration_min      integer,
  recurrence_note   text,               -- "Every Sunday", "Daily 10:0018:00"

  is_free           boolean not null default false,
  price_yen         integer not null default 0,
  price_note        text,

  venue_name        text,
  address           text,
  point             geography(Point, 4326) not null,
  lat               double precision generated always as (st_y(point::geometry)) stored,
  lng               double precision generated always as (st_x(point::geometry)) stored,

  booking_url       text,
  external_url      text,
  stay22_url        text,               -- sponsor: stays near this venue

  locality          numeric(3,2) not null default 0.50,

  save_count        integer not null default 0,
  share_count       integer not null default 0,

  published         boolean not null default true,
  created_at        timestamptz not null default now(),

  constraint experiences_price_valid check (
    (is_free and price_yen = 0) or (not is_free and price_yen >= 0)
  )
);

create index experiences_point_idx    on experiences using gist (point);
create index experiences_city_idx     on experiences (city_id);
create index experiences_starts_idx   on experiences (starts_at);
create index experiences_category_idx on experiences (category);
create index experiences_tags_idx     on experiences using gin (tags);
create index experiences_name_trgm    on experiences using gin (name gin_trgm_ops);

create table experience_media (
  id                 uuid primary key default gen_random_uuid(),
  experience_id      uuid not null references experiences (id) on delete cascade,
  kind               media_kind not null,
  license            media_license not null default 'placeholder',
  source_url         text,
  thumbnail_url      text,
  alt_text           text,
  attribution_name   text,
  attribution_handle text,
  attribution_url    text,
  position           integer not null default 0,
  is_primary         boolean not null default false,
  created_at         timestamptz not null default now(),

  constraint media_needs_source check (
    kind = 'placeholder' or source_url is not null
  )
);

create index experience_media_exp_idx on experience_media (experience_id, position);
create unique index experience_media_primary_idx
  on experience_media (experience_id) where is_primary;

create table profiles (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete cascade,
  display_name text not null default 'Traveler',
  avatar_url   text,
  about        text,
  created_at   timestamptz not null default now()
);

create index profiles_auth_user_id_idx on profiles (auth_user_id);

create table traveler_profiles (
  profile_id  uuid primary key references profiles (id) on delete cascade,
  interests   text[] not null default '{}',   -- interests.slug
  countries   text[] not null default '{}',   -- countries.code
  reasons     text[] not null default '{}',   -- travel_reasons.slug
  onboarded   boolean not null default false,
  updated_at  timestamptz not null default now()
);

create table trips (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references profiles (id) on delete cascade,
  name            text,
  country_code    text references countries (code),
  city_id         uuid references cities (id) on delete set null,
  neighborhood_id uuid references neighborhoods (id) on delete set null,
  start_date      date,
  end_date        date,
  duration_days   integer generated always as (
                    case when start_date is not null and end_date is not null
                         then (end_date - start_date) + 1 end) stored,
  party           travel_style  not null default 'solo',
  budget          budget_level  not null default 'moderate',
  pace            trip_pace     not null default 'balanced',
  notes           text,
  status          trip_status   not null default 'planning',
  created_at      timestamptz   not null default now(),

  constraint trip_dates_ordered check (
    start_date is null or end_date is null or end_date >= start_date
  )
);

create index trips_profile_idx on trips (profile_id, start_date desc nulls last);

create table saved_items (
  profile_id    uuid not null references profiles (id) on delete cascade,
  experience_id uuid not null references experiences (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (profile_id, experience_id)
);

create index saved_items_profile_idx on saved_items (profile_id, created_at desc);

create table dismissed_items (
  profile_id    uuid not null references profiles (id) on delete cascade,
  experience_id uuid not null references experiences (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (profile_id, experience_id)
);

create table share_events (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid references profiles (id) on delete set null,
  experience_id uuid not null references experiences (id) on delete cascade,
  channel       text,
  created_at    timestamptz not null default now()
);

create index share_events_exp_idx on share_events (experience_id);

create table itinerary_entries (
  id            uuid primary key default gen_random_uuid(),
  trip_id       uuid not null references trips (id) on delete cascade,
  profile_id    uuid not null references profiles (id) on delete cascade,
  experience_id uuid not null references experiences (id) on delete cascade,
  day           date not null,
  position      integer not null default 0,
  planned_start time,
  planned_end   time,
  note          text,
  created_at    timestamptz not null default now(),
  unique (trip_id, experience_id)
);

create index itinerary_trip_day_idx on itinerary_entries (trip_id, day, position);
create index itinerary_profile_idx  on itinerary_entries (profile_id);

create or replace function bump_save_count()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update experiences set save_count = save_count + 1 where id = new.experience_id;
  elsif tg_op = 'DELETE' then
    update experiences set save_count = greatest(0, save_count - 1) where id = old.experience_id;
  end if;
  return null;
end;
$$;

create trigger saved_items_count
  after insert or delete on saved_items
  for each row execute function bump_save_count();

create or replace function bump_share_count()
returns trigger language plpgsql as $$
begin
  update experiences set share_count = share_count + 1 where id = new.experience_id;
  return null;
end;
$$;

create trigger share_events_count
  after insert on share_events
  for each row execute function bump_share_count();

create or replace function handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_profile uuid;
begin
  insert into profiles (auth_user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', 'Traveler'))
  on conflict (auth_user_id) do nothing
  returning id into v_profile;

  if v_profile is not null then
    insert into traveler_profiles (profile_id) values (v_profile)
    on conflict do nothing;
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();

create or replace function current_profile_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from profiles where auth_user_id = auth.uid();
$$;

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

create or replace function experience_scores(p_profile uuid, p_trip uuid default null)
returns table (experience_id uuid, score numeric, reasons text[])
language sql stable
as $$
  with me as (
    select coalesce(tp.interests, '{}')::text[] as interests,
           coalesce(tp.countries, '{}')::text[] as countries,
           coalesce(tp.reasons,   '{}')::text[] as reasons,
           lower(coalesce(pr.about, null))        as about
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
   where s.profile_id is null
   order by sc.score desc, k.save_count desc, k.experience_id
   limit p_limit offset p_offset;
$$;

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

create or replace function save_experience(p_experience_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pid uuid := current_profile_id();
begin
  if v_pid is null then raise exception 'not signed in'; end if;

  insert into saved_items (profile_id, experience_id)
  values (v_pid, p_experience_id) on conflict do nothing;

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

  select coalesce(
           p_day,
           (select e.starts_at::date from experiences e where e.id = p_experience_id),
           v_trip.start_date,
           current_date)
    into v_day;

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

create policy countries_read      on countries        for select using (true);
create policy interests_read      on interests        for select using (true);
create policy reasons_read        on travel_reasons   for select using (true);
create policy cities_read         on cities           for select using (true);
create policy neighborhoods_read  on neighborhoods    for select using (true);
create policy hosts_read          on hosts            for select using (true);
create policy experiences_read    on experiences      for select using (published);
create policy media_read          on experience_media for select using (true);

create policy profiles_read      on profiles for select using (true);
create policy profiles_write_own on profiles for update
  using      (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

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

create policy shares_insert_own on share_events for insert
  with check (profile_id = current_profile_id() or profile_id is null);

create policy shares_read_own on share_events for select
  using (profile_id = current_profile_id());

create type age_band as enum
  ('under_18', '18_24', '25_34', '35_44', '45_54', '55_plus', 'undisclosed');

alter table profiles
  add column if not exists age_band age_band not null default 'undisclosed';

create or replace function is_adults_only(p_category text, p_tags text[])
returns boolean language sql immutable as $$
  select p_category = 'nightlife'
      or p_tags && array['nightlife', 'bar', 'club', 'alcohol', 'sake', 'izakaya'];
$$;

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
      jsonb_build_object('slug','18_24',      'label','1824'),
      jsonb_build_object('slug','25_34',      'label','2534'),
      jsonb_build_object('slug','35_44',      'label','3544'),
      jsonb_build_object('slug','45_54',      'label','4554'),
      jsonb_build_object('slug','55_plus',    'label','55+'),
      jsonb_build_object('slug','undisclosed','label','Rather not say'))
  );
$$;

create or replace function experience_scores(p_profile uuid, p_trip uuid default null)
returns table (experience_id uuid, score numeric, reasons text[])
language sql stable
as $$
  with me as (
    select coalesce(tp.interests, '{}')::text[] as interests,
           coalesce(tp.countries, '{}')::text[] as countries,
           coalesce(tp.reasons,   '{}')::text[] as reasons,
           lower(coalesce(pr.about, null))        as about,
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

alter table cities
  add column if not exists bbox_min_lng double precision,
  add column if not exists bbox_min_lat double precision,
  add column if not exists bbox_max_lng double precision,
  add column if not exists bbox_max_lat double precision;

alter table experiences
  add column if not exists source          text not null default 'manual',
  add column if not exists osm_id          bigint,
  add column if not exists has_wikidata    boolean not null default false,
  add column if not exists is_chain        boolean not null default false,
  add column if not exists tourist_density integer not null default 0;

create index if not exists experiences_locality_idx on experiences (locality desc);
create index if not exists experiences_source_idx   on experiences (source);

create unique index if not exists experiences_osm_id_key
  on experiences (osm_id) where osm_id is not null;

create or replace function attach_neighborhoods(p_city_id uuid default null)
returns integer
language plpgsql
as $$
declare v_updated integer;
begin
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

create or replace function recompute_localness(
  p_city_id uuid default null,
  p_force   boolean default false
)
returns integer
language plpgsql
as $$
declare v_updated integer;
begin
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

  select coalesce(array_agg(distinct i.slug), '{}')
    into v_derived
    from experiences e
    join interests i
      on i.slug = e.category or i.slug = any (e.tags)
   where e.id = any (p_experience_ids);

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

create or replace function learned_confidence(p_profile uuid)
returns numeric language sql stable as $$
  select least(1.0, round((
    (select count(*) from saved_items      where profile_id = p_profile)
  + (select count(*) from dismissed_items  where profile_id = p_profile)
  + (select count(*) from itinerary_entries where profile_id = p_profile) * 2
  )::numeric / 20.0, 3));
$$;

create or replace function experience_scores(p_profile uuid, p_trip uuid default null)
returns table (experience_id uuid, score numeric, reasons text[])
language sql stable
as $$
  with me as (
    select coalesce(tp.interests, '{}')::text[] as interests,
           coalesce(tp.countries, '{}')::text[] as countries,
           coalesce(tp.reasons,   '{}')::text[] as reasons,
           lower(coalesce(pr.about, null))        as about,
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

create or replace function my_taste()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'confidence', learned_confidence(current_profile_id()),
    'declared',   coalesce((select interests from traveler_profiles
                             where profile_id = current_profile_id()), '{}'),
    'learned',    coalesce((select jsonb_agg(jsonb_build_object('slug', slug, 'weight', weight))
                              from interest_affinity(current_profile_id())), '[]'::jsonb));
$$;

alter table profiles
  add column if not exists is_guest boolean not null default false;

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

create or replace function exploration_weight(p_profile uuid)
returns numeric language sql stable as $$
  select greatest(0.0, 1.0 - learned_confidence(p_profile) / 0.4);
$$;

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
   order by (sc.cat_rank * exploration_weight((select pid from me))),
            sc.score desc,
            sc.experience_id
   limit p_limit offset p_offset;
$$;

create or replace function handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_profile uuid;
  v_anon    boolean := coalesce((to_jsonb(new) ->> 'is_anonymous')::boolean, false);
begin
  insert into profiles (auth_user_id, display_name, is_guest)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', null),
             nullif(split_part(coalesce(to_jsonb(new) ->> 'email', null), '@', 1), null),
             'Traveler'),
    v_anon)
  on conflict (auth_user_id) do nothing
  returning id into v_profile;

  if v_profile is not null then
    insert into traveler_profiles (profile_id) values (v_profile)
    on conflict do nothing;
  end if;

  return new;
end;
$$;

create or replace function handle_auth_user_upgraded()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_was boolean := coalesce((to_jsonb(old) ->> 'is_anonymous')::boolean, false);
  v_now boolean := coalesce((to_jsonb(new) ->> 'is_anonymous')::boolean, false);
begin
  if v_was and not v_now then
    update profiles
       set is_guest = false,
           display_name = case
             when coalesce(nullif(display_name, null), 'Traveler') = 'Traveler'
               then coalesce(nullif(new.raw_user_meta_data ->> 'display_name', null),
                             nullif(split_part(coalesce(to_jsonb(new) ->> 'email', null), '@', 1), null),
                             display_name)
             else display_name end
     where auth_user_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_upgraded on auth.users;
create trigger on_auth_user_upgraded
  after update on auth.users
  for each row execute function handle_auth_user_upgraded();

create or replace function session_state()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'signed_in',   p.id is not null,
    'profile_id',  p.id,
    'display_name',p.display_name,
    'is_guest',    coalesce(p.is_guest, true),
    'onboarded',   coalesce(tp.onboarded, false),
    'next_screen', case
                     when p.id is null                      then 'welcome'
                     when not coalesce(tp.onboarded, false) then 'picker'
                     else 'feed'
                   end,
    'saved_count', (select count(*) from saved_items s where s.profile_id = p.id),
    'trip_count',  (select count(*) from trips t where t.profile_id = p.id),
    'confidence',  learned_confidence(p.id),
    'prompt_signup', coalesce(p.is_guest, false)
                     and (select count(*) from saved_items s where s.profile_id = p.id) >= 3
  )
  from profiles p
  left join traveler_profiles tp on tp.profile_id = p.id
  where p.id = current_profile_id();
$$;

update profiles p
   set is_guest = coalesce((to_jsonb(u) ->> 'is_anonymous')::boolean, false)
  from auth.users u
 where u.id = p.auth_user_id;

alter table experience_media
  drop constraint if exists media_oembed_needs_attribution;

alter table experience_media
  add constraint media_oembed_needs_attribution check (
    license <> 'oembed'
    or (attribution_name is not null and attribution_name <> ''
        and attribution_url is not null and attribution_url <> null)
  );

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


create table if not exists trip_cities (
  trip_id     uuid not null references trips (id) on delete cascade,
  city_id     uuid not null references cities (id) on delete cascade,
  seq         integer not null default 1,
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

insert into trip_cities (trip_id, city_id, seq)
select id, city_id, 1 from trips where city_id is not null
on conflict do nothing;

create or replace function trip_city_ids(p_trip_id uuid)
returns uuid[] language sql stable as $$
  select coalesce(
    nullif(array(select city_id from trip_cities where trip_id = p_trip_id order by seq), '{}'),
    array(select city_id from trips where id = p_trip_id and city_id is not null));
$$;

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

create or replace function preferred_slot(p_category text, p_tags text[] default '{}')
returns time language sql immutable as $$
  select case
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

create or replace function itinerary_conflicts(p_trip_id uuid default null)
returns table (
  entry_id uuid, other_entry_id uuid, day date,
  name text, other_name text,
  starts time, other_starts time, overlap_min integer
)
language sql stable as $$
  with t as (select coalesce(p_trip_id, current_trip_id()) as tid),
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

  v_day := v_trip.start_date;
  while v_day <= v_trip.end_date loop
    v_city := trip_city_for_day(v_tid, v_day);

    select count(*) into v_placed
      from itinerary_entries where trip_id = v_tid and day = v_day;

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
          v_slot := coalesce(v_item.starts_at::time,
                             preferred_slot(v_item.category, v_item.tags));

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

create or replace function experience_scores(p_profile uuid, p_trip uuid default null)
returns table (experience_id uuid, score numeric, reasons text[])
language sql stable
as $$
  with me as (
    select coalesce(tp.interests, '{}')::text[] as interests,
           coalesce(tp.countries, '{}')::text[] as countries,
           coalesce(tp.reasons,   '{}')::text[] as reasons,
           lower(coalesce(pr.about, null))        as about,
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
          coalesce(p_name, array_to_string(p_city_slugs, '  ')), 'planning')
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

create or replace function is_adults_only(p_category text, p_tags text[])
returns boolean language sql immutable as $$
  select p_category = 'nightlife'
      or p_tags && array['nightlife', 'bar', 'club', 'alcohol', 'sake',
                         'izakaya', 'gambling'];
$$;

insert into countries (code, name_en, emoji, available, sort) values
  ('JP','Japan',         null, true,  1),
  ('KR','South Korea',   null, false, 2),
  ('TW','Taiwan',        null, false, 3),
  ('TH','Thailand',      null, false, 4),
  ('VN','Vietnam',       null, false, 5),
  ('IT','Italy',         null, false, 6),
  ('ES','Spain',         null, false, 7),
  ('PT','Portugal',      null, false, 8),
  ('MX','Mexico',        null, false, 9),
  ('US','United States', null, false, 10);

insert into travel_reasons (slug, label_en, emoji, sort) values
  ('vacation',   'Just a holiday',        null, 1),
  ('food',       'Eating my way around', null, 2),
  ('culture',    'Culture and history',  null, 3),
  ('adventure',  'Adventure and hiking', null, 4),
  ('nightlife',  'Going out',            null, 5),
  ('reset',      'Rest and reset',       null, 6),
  ('photography','Photography',          null, 7),
  ('anime',      'Anime and gaming',     null, 8),
  ('business',   'Work trip',            null, 9),
  ('friends',    'Visiting people',      null, 10);

insert into interests (slug, label_en, emoji, sort) values
  ('food',        'Restaurants & food',  null, 1),
  ('nightlife',   'Bars & nightclubs',   null, 2),
  ('nature',      'Nature & parks',      null, 3),
  ('hiking',      'Hiking & trails',     null, 4),
  ('beach',       'Beaches',             null, 5),
  ('art',         'Art & design',        null, 6),
  ('anime',       'Anime & gaming',      null, 7),
  ('music',       'Live music',          null, 8),
  ('shopping',    'Shopping & vintage',  null, 9),
  ('festival',    'Festivals',           null, 10),
  ('wellness',    'Wellness & onsen',    null, 11),
  ('traditional', 'Traditional culture', null, 12),
  ('market',      'Markets',             null, 13),
  ('cars',        'Car culture',         null, 14);

insert into cities (country_code, slug, name_en, name_ja, center,
                    bbox_min_lng, bbox_min_lat, bbox_max_lng, bbox_max_lat) values
  ('JP','tokyo', 'Tokyo', null, st_makepoint(139.6503, 35.6762)::geography,
   139.6300, 35.6200, 139.8100, 35.7400),   -- core 23 wards
  ('JP','kyoto', 'Kyoto', null, st_makepoint(135.7681, 35.0116)::geography,
   135.6500, 34.9500, 135.8100, 35.0700),   -- Arashiyama through to Fushimi
  ('JP','osaka', 'Osaka', null, st_makepoint(135.5023, 34.6937)::geography,
   135.4700, 34.6300, 135.5400, 34.7300);   -- Namba up to Tenma

insert into neighborhoods (city_id, slug, name_en, name_ja, center, blurb)
select c.id, v.slug, v.name_en, v.name_ja, st_makepoint(v.lng, v.lat)::geography, v.blurb
from cities c, (values
  ('tokyo','shibuya',        'Shibuya',        null,   139.7016, 35.6580, 'Crossing, record shops, and the city at its loudest.'),
  ('tokyo','shinjuku',       'Shinjuku',       null,   139.7034, 35.6938, 'Golden Gai, department stores, and Omoide Yokocho smoke.'),
  ('tokyo','asakusa',        'Asakusa',        null,   139.7967, 35.7148, 'Senso-ji, artisan streets, and the old low city.'),
  ('tokyo','shimokitazawa',  'Shimokitazawa',  null, 139.6683, 35.6613, 'Live houses, secondhand racks, tiny theatres.'),
  ('tokyo','koenji',         'Koenji',         null, 139.6497, 35.7053, 'Punk bars and the densest vintage in Tokyo.'),
  ('tokyo','akihabara',      'Akihabara',      null, 139.7745, 35.7022, 'Arcades, parts shops, and six floors of everything.'),
  ('tokyo','nakameguro',     'Nakameguro',     null, 139.6990, 35.6440, 'Canal-side cafes under the cherry trees.'),
  ('tokyo','yanaka',         'Yanaka',         null,   139.7660, 35.7280, 'Survived the war and the bubble. Cats and senbei.'),
  ('tokyo','toyosu',         'Toyosu',         null,   139.7967, 35.6550, 'Reclaimed waterfront, the new fish market, digital art.'),
  ('kyoto','gion',           'Gion',           null,   135.7752, 35.0037, 'Wooden machiya, lantern light, and the Kamo river.'),
  ('kyoto','arashiyama',     'Arashiyama',     null,   135.6668, 35.0094, 'Bamboo, monkeys, and the Hozu river gorge.'),
  ('kyoto','nishiki',        'Nishiki',        null,     135.7648, 35.0050, 'Four hundred metres of covered market.'),
  ('kyoto','fushimi',        'Fushimi',        null,   135.7727, 34.9671, 'Sake breweries and ten thousand torii.'),
  ('kyoto','nishijin',       'Nishijin',       null,   135.7420, 35.0300, 'Weaving district, quiet workshops, no crowds.'),
  ('osaka','namba',          'Namba',          null,   135.5010, 34.6656, 'Dotonbori neon and the food everyone comes for.'),
  ('osaka','shinsekai',      'Shinsekai',      null, 135.5062, 34.6524, 'Tsutenkaku tower and kushikatsu under it.'),
  ('osaka','tenma',          'Tenma',          null,   135.5120, 34.7055, 'The longest shopping arcade in Japan, and standing bars.'),
  ('osaka','amerikamura',    'Amerikamura',    null, 135.4980, 34.6720, 'Street art, skate shops, and Osaka youth culture.'),
  ('osaka','nakazakicho',    'Nakazakicho',    null, 135.5030, 34.7080, 'Prewar houses turned into cafes and zine shops.')
) as v(city, slug, name_en, name_ja, lng, lat, blurb)
where c.slug = v.city;

insert into hosts (id, name, kind, bio, verified, is_local) values
  ('a0000000-0000-4000-8000-000000000001','Tsukiji Ganso Guides','local_business','Third-generation fishmonger family running small morning walks.', true,  true),
  ('a0000000-0000-4000-8000-000000000002','Koenji Kaiten Collective','community','Neighbourhood shop owners who run a free monthly crawl.',        false, true),
  ('a0000000-0000-4000-8000-000000000003','Shelter Shimokita','venue','Live house running since 1991.',                                          true,  true),
  ('a0000000-0000-4000-8000-000000000004','Yanaka Machi-aruki','individual','Retired schoolteacher, walks his own neighbourhood.',               false, true),
  ('a0000000-0000-4000-8000-000000000005','Retro Game Camp','local_business','Arcade preservation shop in Akiba.',                               true,  true),
  ('a0000000-0000-4000-8000-000000000006','Meguro River Sakura Association','community','Volunteer group who light the canal each spring.',      false, true),
  ('a0000000-0000-4000-8000-000000000007','Golden Gai Nomikai','individual','Bar-hopping host, six seats a night, books out fast.',              true,  true),
  ('a0000000-0000-4000-8000-000000000008','Chokoku-ji Temple','institution','Neighbourhood temple, open zazen twice weekly.',                    true,  true),
  ('a0000000-0000-4000-8000-000000000009','teamLab','institution','Digital art collective.',                                                     true,  false),
  ('a0000000-0000-4000-8000-000000000010','Face Records Shibuya','local_business','Vinyl shop and crawl organiser.',                             false, true),
  ('a0000000-0000-4000-8000-000000000011','Nishiki Asagohan','local_business','Market stallholders running a breakfast tasting.',                true,  true),
  ('a0000000-0000-4000-8000-000000000012','Arashiyama Dawn Walks','individual','Local photographer, 6am starts to beat the buses.',              false, true),
  ('a0000000-0000-4000-8000-000000000013','Nishijin Yuzen Kobo','local_business','Family dyeing workshop, five generations.',                    true,  true),
  ('a0000000-0000-4000-8000-000000000014','Machiya Kappo Sen','local_business','Eight-seat counter in a restored townhouse.',                    true,  true),
  ('a0000000-0000-4000-8000-000000000015','Fushimi Sake Guild','community','Association of eighteen Fushimi breweries.',                         true,  true),
  ('a0000000-0000-4000-8000-000000000016','Tenma Tachinomi Tour','individual','Osaka salaryman turned guide. Standing bars only.',               false, true),
  ('a0000000-0000-4000-8000-000000000017','Shinsekai Kushikatsu Kumiai','community','Shopkeepers association of Shinsekai.',                     false, true),
  ('a0000000-0000-4000-8000-000000000018','Nakazaki Zine Club','community','Cafe owners and small publishers.',                                  false, true),
  ('a0000000-0000-4000-8000-000000000019','Osaka Tenmangu Shrine','institution','Host of Tenjin Matsuri since 951.',                             true,  true),
  ('a0000000-0000-4000-8000-000000000020','Amemura Art Walk','community','Street artists running free walking sessions.',                        false, true),
  ('a0000000-0000-4000-8000-000000000021','Daikoku Regulars','community','No organisers, no schedule. People just turn up.',                     false, true),
  ('a0000000-0000-4000-8000-000000000022','Morning Cruise Tokyo','community','Monthly Cars & Coffee at Daikanyama T-Site since 2011.',           true,  true),
  ('a0000000-0000-4000-8000-000000000023','Super Autobacs','local_business','Parts megastore and demo-car showroom.',                            true,  false),
  ('a0000000-0000-4000-8000-000000000024','Nissan Crossing','institution','Nissan brand showroom on the Ginza crossing.',                        true,  false),
  ('a0000000-0000-4000-8000-000000000025','Honda Welcome Plaza','institution','Honda showroom and F1 heritage display in Aoyama.',               true,  false);

insert into experiences (
  id, city_id, neighborhood_id, host_id, name, name_ja, short_description, description,
  category, tags, starts_at, duration_min, recurrence_note,
  is_free, price_yen, price_note, venue_name, address, point,
  booking_url, external_url, locality, save_count, share_count)
select
  v.id::uuid, c.id, n.id, v.host::uuid, v.name, v.name_ja, v.short_desc, v.long_desc,
  v.category, v.tags::text[],
  case when v.offset_h is null then null
       else date_trunc('day', now() + v.offset_h)
            + preferred_slot(v.category, v.tags::text[]) end,
  v.duration, v.recurrence,
  v.is_free, v.price, v.price_note, v.venue, v.address,
  st_makepoint(v.lng, v.lat)::geography,
  v.booking, v.external, v.locality, v.saves, v.shares
from (values
  ('b0000000-0000-4000-8000-000000000001','tokyo','asakusa','a0000000-0000-4000-8000-000000000001',
   'Tsukiji Outer Market Morning Walk',' ',
   'Eat breakfast standing up with the people who sell the fish.',
   'The inner market moved to Toyosu, but the outer market never left. Start at 7am with tamagoyaki straight off the griddle, then work through uni, tuna cheek, and a bowl of miso from a stall with no English menu. Your host''s family has sold fish here for three generations, which is the only reason some of these stops will serve you at all.',
   'food','{food,traditional,solo-friendly}', interval '18 hours', 150, 'Daily except Sunday',
   false, 3800, 'Includes six tastings', 'Tsukiji Outer Market','4-16-2 Tsukiji, Chuo City, Tokyo',
   139.7707, 35.6654, null, 'https://www.tsukiji.or.jp/english/', 0.72, 214, 38),

  ('b0000000-0000-4000-8000-000000000002','tokyo','koenji',null,
   'Koenji Vintage Crawl',' ',
   'Forty secondhand shops in six streets. No map, no plan.',
   'Koenji has the densest concentration of vintage clothing in Tokyo and almost no tourists in it. The monthly crawl is run by the shop owners themselves  it costs nothing, it starts when enough people show up outside the north exit, and it ends in whichever bar is still open.',
   'shopping','{shopping,art,solo-friendly,group-friendly}', interval '3 days', 180, 'First Saturday monthly',
   true, 0, null, 'Koenji Station North Exit','Koenji-kita, Suginami City, Tokyo',
   139.6497, 35.7053, null, null, 0.88, 96, 21),

  ('b0000000-0000-4000-8000-000000000003','tokyo','shimokitazawa','a0000000-0000-4000-8000-000000000003',
   'Shelter Shimokitazawa: Friday Live','SHELTER ',
   'Basement live house, four bands, capacity 250.',
   'Shelter has been putting on shows since 1991 and it is where a lot of bands you have heard of played their tenth gig. Standing room, drink ticket included, doors at 18:30. The lineup rotates weekly and is almost entirely Japanese indie.',
   'music','{music,nightlife,solo-friendly}', interval '2 days', 210, 'Most Fridays',
   false, 3300, 'Plus one drink ticket, 600 yen', 'Shimokitazawa SHELTER','2-6-10 Kitazawa, Setagaya City, Tokyo',
   139.6670, 35.6620, null, 'https://www.loft-prj.co.jp/SHELTER/', 0.79, 142, 27),

  ('b0000000-0000-4000-8000-000000000004','tokyo','yanaka','a0000000-0000-4000-8000-000000000004',
   'Yanaka Evening Stroll & Senbei',' ',
   'The Tokyo that survived the firebombing, walked at dusk.',
   'Yanaka is one of the few districts to come through both the 1923 earthquake and the 1945 firebombing largely intact. A retired schoolteacher walks you through the cemetery at golden hour, past the cats, and ends at a senbei shop that has been grilling rice crackers by hand since 1913.',
   'traditional','{traditional,food,nature,solo-friendly,family-friendly}', interval '30 hours', 120, 'Tuesdays and Thursdays',
   false, 2000, null, 'Yanaka Ginza','3-13-1 Yanaka, Taito City, Tokyo',
   139.7660, 35.7280, null, null, 0.91, 73, 12),

  ('b0000000-0000-4000-8000-000000000005','tokyo','akihabara','a0000000-0000-4000-8000-000000000005',
   'Akihabara Retro Arcade Deep Dive',' ',
   'Four floors of cabinets from 1978 onward, with someone who can explain them.',
   'Not the tourist arcade on the main street. This runs through three buildings of working vintage cabinets, a parts shop where people still repair PCBs, and a doujin game floor. Coins included. Your host restores cabinets for a living.',
   'anime','{anime,shopping,solo-friendly,group-friendly}', interval '4 days', 150, 'Weekends',
   false, 4500, 'Includes 1000 yen in tokens', 'Super Potato Retro-kan','1-11-2 Sotokanda, Chiyoda City, Tokyo',
   139.7712, 35.7000, null, null, 0.68, 187, 44),

  ('b0000000-0000-4000-8000-000000000006','tokyo','nakameguro','a0000000-0000-4000-8000-000000000006',
   'Meguro River Sakura Night Walk',' ',
   'Eight hundred cherry trees over a canal, lit by volunteers.',
   'For two weeks a year the Meguro river becomes the best walk in Tokyo. The lanterns are hung by a neighbourhood volunteer association, not the city. Come on a weekday  the weekend is genuinely impassable. Free, and the riverside stands sell sparkling wine in plastic cups.',
   'nature','{nature,festival,romantic,late-night,free}', interval '5 days', 90, 'Late March to early April',
   true, 0, null, 'Nakameguro Riverside','Nakameguro, Meguro City, Tokyo',
   139.6990, 35.6440, null, null, 0.62, 341, 86),

  ('b0000000-0000-4000-8000-000000000007','tokyo','shinjuku','a0000000-0000-4000-8000-000000000007',
   'Golden Gai Izakaya Hop',' ',
   'Six seats a bar, six bars a night, in 200 wooden buildings.',
   'Golden Gai is 280 tiny bars in six alleys, most seating fewer than eight people, many with a cover charge and a regulars-only reputation that a local host dissolves instantly. Three bars, three drinks, and an explanation of which doors you can open alone next time.',
   'nightlife','{nightlife,food,group-friendly}', interval '1 day', 180, 'Nightly except Sunday',
   false, 7000, 'Includes three drinks and cover charges', 'Shinjuku Golden Gai','1-1-6 Kabukicho, Shinjuku City, Tokyo',
   139.7043, 35.6938, null, null, 0.74, 268, 71),

  ('b0000000-0000-4000-8000-000000000008','tokyo','asakusa','a0000000-0000-4000-8000-000000000008',
   'Morning Zazen at a Neighbourhood Temple',null,
   'Forty minutes of seated meditation. No English, no ceremony, no photos.',
   'Not a tourist zazen experience. This is the regular twice-weekly sitting that the neighbourhood attends, at 6:30am, and visitors are welcome to join quietly at the back. Instruction is minimal and in Japanese, but the posture is demonstrated. Tea afterwards.',
   'wellness','{wellness,traditional,solo-friendly}', interval '20 hours', 60, 'Wednesdays and Saturdays, 06:30',
   false, 1000, 'Donation, tea included', 'Chokoku-ji','2-1-15 Nishiasakusa, Taito City, Tokyo',
   139.7920, 35.7160, null, null, 0.94, 41, 6),

  ('b0000000-0000-4000-8000-000000000009','tokyo','toyosu','a0000000-0000-4000-8000-000000000009',
   'teamLab Planets TOKYO',null,
   'Barefoot through knee-deep water and a room of mirrors.',
   'Four large-scale installations you walk through barefoot, including one where you wade through water with projected koi. Book ahead; it sells out. Wear shorts or clothes you can roll up.',
   'art','{art,family-friendly,couple}', null, 90, 'Daily 09:0022:00',
   false, 3800, 'Timed entry, book ahead', 'teamLab Planets TOKYO','6-1-16 Toyosu, Koto City, Tokyo',
   139.7900, 35.6490, 'https://www.teamlab.art/e/planets/', 'https://www.teamlab.art/e/planets/', 0.18, 892, 240),

  ('b0000000-0000-4000-8000-000000000010','tokyo','shibuya','a0000000-0000-4000-8000-000000000010',
   'Shibuya Record Store Crawl',' ',
   'Seven shops, from 40-yen bins to sealed city pop.',
   'Shibuya still has one of the densest record scenes on earth. This is a self-paced route between seven shops with a hand-drawn map from Face Records  jazz kissa reissues, 1980s city pop, and a basement that only sells 7-inches. Free to walk; bring cash.',
   'music','{music,shopping,solo-friendly}', null, 180, 'Any day, shops open 12:0020:00',
   true, 0, 'Free route; records are not', 'Face Records Shibuya','3-15-1 Jinnan, Shibuya City, Tokyo',
   139.6980, 35.6640, null, null, 0.77, 118, 19),

  ('b0000000-0000-4000-8000-000000000011','kyoto','nishiki','a0000000-0000-4000-8000-000000000011',
   'Nishiki Market Breakfast Tasting',' ',
   'Eight stalls before the market fills up, starting at 9am.',
   'Nishiki is four hundred metres of covered market and by noon you cannot move. At nine it belongs to the stallholders. Tastings include tamago, pickled everything, fresh yuba, and a knife shop demonstration that is not a sales pitch.',
   'food','{food,traditional,market,solo-friendly,family-friendly}', interval '15 hours', 120, 'Daily except Wednesday',
   false, 3500, 'Eight tastings included', 'Nishiki Market','Nakagyo Ward, Kyoto',
   135.7648, 35.0050, null, 'https://www.kyoto-nishiki.or.jp/', 0.66, 203, 47),

  ('b0000000-0000-4000-8000-000000000012','kyoto','arashiyama','a0000000-0000-4000-8000-000000000012',
   'Arashiyama Bamboo Grove at Dawn',' ',
   'The famous grove, at 6am, before the buses.',
   'The bamboo grove is genuinely extraordinary and genuinely ruined by 9am. A local photographer meets you at 5:45, walks you through while it is still empty, and continues to the Hozu riverbank and a temple garden most day-trippers never reach. Bring a jacket.',
   'nature','{nature,hiking,traditional,romantic,solo-friendly}', interval '26 hours', 150, 'Daily, weather permitting',
   false, 2500, null, 'Arashiyama Bamboo Grove','Ukyo Ward, Kyoto',
   135.6668, 35.0094, null, null, 0.45, 456, 132),

  ('b0000000-0000-4000-8000-000000000013','kyoto','nishijin','a0000000-0000-4000-8000-000000000013',
   'Kyo-Yuzen Silk Dyeing Workshop',' ',
   'Hand-dye a silk panel in a fifth-generation workshop.',
   'Nishijin is the weaving district and most visitors never go. This family has dyed yuzen silk for five generations. You dye a small panel yourself with their brushes and pigments, take it home, and watch the master finish a commissioned kimono length in the next room.',
   'traditional','{traditional,art,family-friendly,couple}', interval '2 days', 120, 'Mon/Wed/Fri, book ahead',
   false, 5500, 'Materials included, take your panel home', 'Nishijin Yuzen Kobo','Kamigyo Ward, Kyoto',
   135.7420, 35.0300, null, null, 0.89, 64, 11),

  ('b0000000-0000-4000-8000-000000000014','kyoto','gion','a0000000-0000-4000-8000-000000000014',
   'Machiya Counter Kaiseki',' ',
   'Eight seats, one counter, whatever came in that morning.',
   'A restored wooden townhouse in Gion with a single eight-seat counter. No fixed menu  the chef buys at Nishiki that morning and tells you what you are eating as he plates it. Reservation only, and they do take walk-in cancellations if you ask in person.',
   'food','{food,traditional,romantic,couple}', interval '31 hours', 150, 'Tuesday to Saturday, 18:00 and 20:30',
   false, 14000, 'Sake pairing 4500 extra', 'Machiya Kappo Sen','Higashiyama Ward, Kyoto',
   135.7752, 35.0037, null, null, 0.83, 89, 16),

  ('b0000000-0000-4000-8000-000000000015','kyoto','fushimi','a0000000-0000-4000-8000-000000000015',
   'Fushimi Sake Brewery Tasting',' ',
   'Soft water, eighteen breweries, and the ones that still open their doors.',
   'Fushimi''s water is softer than Nada''s, which is why the sake is rounder. Three working breweries, a tasting flight at each, and a walk along the Horikawa canal between them. Most tourists in Fushimi only see the torii gates two kilometres north.',
   'food','{food,traditional,alcohol,group-friendly}', interval '50 hours', 180, 'Daily except Monday',
   false, 2800, 'Nine tastings', 'Fushimi Sake District','Fushimi Ward, Kyoto',
   135.7620, 34.9330, null, null, 0.81, 127, 24),

  ('b0000000-0000-4000-8000-000000000016','osaka','tenma','a0000000-0000-4000-8000-000000000016',
   'Tenma Standing Bar Crawl',' ',
   'Four tachinomi bars. Nobody sits down. Everything is under 500 yen.',
   'Tenma has the longest shopping arcade in Japan and underneath it the best standing-bar density in Osaka. Four bars, a dish and a drink at each, all of it cheap and none of it aimed at visitors. Your host is a former salaryman who drank here for twenty years before guiding.',
   'nightlife','{nightlife,food,solo-friendly,group-friendly}', interval '8 hours', 180, 'Thursday to Sunday',
   false, 5000, 'Four drinks and four dishes', 'Tenjinbashisuji Arcade','Kita Ward, Osaka',
   135.5120, 34.7055, null, null, 0.86, 176, 39),

  ('b0000000-0000-4000-8000-000000000017','osaka','shinsekai','a0000000-0000-4000-8000-000000000017',
   'Shinsekai Kushikatsu, No Double Dipping',' ',
   'Deep-fried everything under a 1912 tower, with one unbreakable rule.',
   'Shinsekai was built in 1912 to look like Paris and Coney Island at once, then forgotten for fifty years. Kushikatsu is skewered, battered, deep-fried, and dipped once in communal sauce  dip twice and you will be told off. Run by the shopkeepers'' association, so you eat at four different counters.',
   'food','{food,nightlife,group-friendly,family-friendly}', interval '11 hours', 120, 'Daily',
   false, 3200, 'Twelve skewers across four shops', 'Shinsekai','Naniwa Ward, Osaka',
   135.5062, 34.6524, null, null, 0.64, 231, 58),

  ('b0000000-0000-4000-8000-000000000018','osaka','nakazakicho','a0000000-0000-4000-8000-000000000018',
   'Nakazakicho Cafe & Zine Walk',' zine',
   'Prewar houses turned into cafes, one street from a skyscraper district.',
   'Nakazakicho survived the war and then got left alone. The wooden houses are now cafes, secondhand bookshops, and zine publishers, and it is a ten-minute walk from Umeda station where nobody goes. Self-guided route with a printed zine map made by the cafe owners.',
   'art','{art,shopping,food,solo-friendly}', null, 150, 'Any day; most cafes closed Tuesday',
   true, 0, 'Route free; zine map 300 yen at any participating cafe', 'Nakazakicho','Kita Ward, Osaka',
   135.5030, 34.7080, null, null, 0.93, 58, 9),

  ('b0000000-0000-4000-8000-000000000019','osaka','tenma','a0000000-0000-4000-8000-000000000019',
   'Tenjin Matsuri River Procession',' ',
   'A thousand-year-old festival, a hundred boats, and fireworks over the Okawa.',
   'One of Japan''s three great festivals, held by Osaka Tenmangu since the tenth century. Portable shrines are carried to the river and loaded onto boats, which process upstream by torchlight while fireworks go up over the water. Free to watch from the banks; arrive by 17:00 for anywhere near the front.',
   'festival','{festival,traditional,nature,family-friendly,group-friendly}', interval '6 days', 300, 'July 2425 annually',
   true, 0, 'Free from the riverbank; paid grandstand seats exist', 'Okawa River','Kita Ward, Osaka',
   135.5140, 34.6960, null, 'https://osakatemmangu.or.jp/', 0.55, 512, 168),

  ('b0000000-0000-4000-8000-000000000020','osaka','amerikamura','a0000000-0000-4000-8000-000000000020',
   'Amemura Street Art Walk',' ',
   'Murals, skate shops, and the artists who painted them.',
   'Amerikamura is where Osaka teenagers have gone since the 1970s. A rotating group of the artists who actually paint the walls run a free Sunday walk explaining what is up, what got painted over, and why. Ends at Triangle Park where everyone sits on the ground.',
   'art','{art,shopping,music,solo-friendly,group-friendly}', interval '4 days', 90, 'Sundays, 15:00',
   true, 0, null, 'Triangle Park, Amerikamura','Chuo Ward, Osaka',
   135.4980, 34.6720, null, null, 0.87, 84, 17)
) as v(id, city, hood, host, name, name_ja, short_desc, long_desc, category, tags,
       offset_h, duration, recurrence, is_free, price, price_note, venue, address,
       lng, lat, booking, external, locality, saves, shares)
join cities c on c.slug = v.city
left join neighborhoods n on n.city_id = c.id and n.slug = v.hood;

insert into experiences (
  id, city_id, neighborhood_id, host_id, name, name_ja, short_description, description,
  category, tags, starts_at, duration_min, recurrence_note,
  is_free, price_yen, price_note, venue_name, address, point,
  booking_url, external_url, locality, save_count, share_count)
select
  v.id::uuid, c.id, n.id, v.host::uuid, v.name, v.name_ja, v.short_desc, v.long_desc,
  v.category, v.tags::text[],
  case when v.offset_h is null then null
       else date_trunc('day', now() + v.offset_h)
            + preferred_slot(v.category, v.tags::text[]) end,
  v.duration, v.recurrence,
  v.is_free, v.price, v.price_note, v.venue, v.address,
  st_makepoint(v.lng, v.lat)::geography,
  v.booking, v.external, v.locality, v.saves, v.shares
from (values
  ('b0000000-0000-4000-8000-000000000021','tokyo',null,'a0000000-0000-4000-8000-000000000021',
   'Daikoku Futo PA Night Meet','PA',
   'The most famous car park on earth, under an expressway loop.',
   'A motorway service area on reclaimed land in Yokohama Bay that became the centre of Japanese car culture by accident. Bosozoku bikes, kaido racers, immaculate kyusha, and someone''s twin-turbo Supra idling next to a hand-built VIP sedan. Nothing is organised and nothing is advertised  it happens on weekend nights when the police are not closing the ramp. Take the Wangan line, not a taxi that will not wait.',
   'cars','{cars,late-night,photography,group-friendly}', interval '22 hours', 180, 'Weekend nights, weather and police permitting',
   true, 0, 'Free. Parking is the whole point.', 'Daikoku Futo Parking Area','Daikoku Futo, Tsurumi Ward, Yokohama (45 min from central Tokyo)',
   139.6873, 35.4553, null, null, 0.94, 388, 121),

  ('b0000000-0000-4000-8000-000000000022','tokyo','toyosu','a0000000-0000-4000-8000-000000000021',
   'Tatsumi PA After Midnight','PA',
   'Smaller, closer, and the Tokyo skyline behind every car.',
   'Tatsumi sits on the Shuto expressway with the bay and the skyline as a backdrop, which is why it out-photographs Daikoku even though it is a fraction of the size. Quieter crowd, more regulars, more actual conversation. Peaks somewhere after 1am.',
   'cars','{cars,late-night,photography,viewpoint}', interval '26 hours', 120, 'Most nights after midnight',
   true, 0, null, 'Tatsumi Parking Area','Tatsumi, Koto City, Tokyo',
   139.8092, 35.6417, null, null, 0.91, 174, 46),

  ('b0000000-0000-4000-8000-000000000023','tokyo','nakameguro','a0000000-0000-4000-8000-000000000022',
   'Daikanyama Morning Cruise',null,
   'Cars and coffee at 7am, then everyone drives off by nine.',
   'A monthly meet in the T-Site bookshop car park that has run since 2011, with a different theme each time  air-cooled Porsches one month, 1980s Japanese saloons the next. Genuinely welcoming to people on foot, and the coffee is good. Over by 09:00 because Daikanyama has to open.',
   'cars','{cars,shopping,photography,family-friendly}', interval '54 hours', 120, 'First Sunday monthly, 07:0009:00',
   true, 0, 'Free to attend on foot', 'Daikanyama T-Site','17-5 Sarugakucho, Shibuya City, Tokyo',
   139.7030, 35.6490, null, null, 0.74, 142, 33),

  ('b0000000-0000-4000-8000-000000000024','tokyo','toyosu','a0000000-0000-4000-8000-000000000023',
   'Super Autobacs Tokyo Bay',null,
   'Four floors of parts, and demo cars nobody will stop you photographing.',
   'A car parts megastore the size of a supermarket, with a demo floor of fully built cars, a wheel wall that goes to the ceiling, and an aftermarket catalogue that explains more about Japanese car culture than any museum. Staff are used to visitors and several speak English.',
   'cars','{cars,shopping}', null, 90, 'Daily 10:0020:00',
   true, 0, 'Free entry', 'Super Autobacs Tokyo Bay Shinonome','1-2-8 Shinonome, Koto City, Tokyo',
   139.8000, 35.6470, null, null, 0.66, 88, 14),

  ('b0000000-0000-4000-8000-000000000025','tokyo','shinjuku','a0000000-0000-4000-8000-000000000025',
   'Honda Welcome Plaza Aoyama',null,
   'Free F1 cars in a lobby, ten minutes from Omotesando.',
   'The ground floor of Honda headquarters, open to the street, usually with a championship-winning F1 car and a rotating display of ASIMO-era engineering. Takes twenty minutes and costs nothing, which makes it the easiest car stop in central Tokyo.',
   'cars','{cars,culture,family-friendly}', null, 30, 'Daily 10:0018:00',
   true, 0, 'Free', 'Honda Welcome Plaza Aoyama','2-1-1 Minami-Aoyama, Minato City, Tokyo',
   139.7170, 35.6660, null, null, 0.34, 96, 12),

  ('b0000000-0000-4000-8000-000000000026','tokyo',null,'a0000000-0000-4000-8000-000000000024',
   'Nissan Crossing, Ginza',null,
   'Concept cars behind glass on the busiest corner in Ginza.',
   'A three-storey brand showroom on the Ginza 4-chome crossing with a rotating concept or heritage car and a caf upstairs. Squarely a tourist stop rather than a scene one  included here so you can see the difference from Daikoku in one scroll.',
   'cars','{cars,shopping}', null, 40, 'Daily 10:0020:00',
   true, 0, 'Free', 'Nissan Crossing','5-8-1 Ginza, Chuo City, Tokyo',
   139.7650, 35.6720, null, null, 0.22, 211, 28)
) as v(id, city, hood, host, name, name_ja, short_desc, long_desc, category, tags,
       offset_h, duration, recurrence, is_free, price, price_note, venue, address,
       lng, lat, booking, external, locality, saves, shares)
join cities c on c.slug = v.city
left join neighborhoods n on n.city_id = c.id and n.slug = v.hood;

insert into experience_media (experience_id, kind, license, alt_text, is_primary, position)
select id, 'placeholder', 'placeholder',
       short_description, true, 0
from experiences;


insert into experiences (
  id, city_id, neighborhood_id, host_id, name, name_ja, short_description, description,
  category, tags, starts_at, duration_min, recurrence_note,
  is_free, price_yen, price_note, venue_name, address, point,
  booking_url, external_url, locality, save_count, share_count, source)
select
  v.id::uuid, c.id, n.id, null, v.name, v.name_ja, v.short_desc, v.long_desc,
  v.category, v.tags::text[],
  case when v.offset_h is null then null
       else date_trunc('day', now() + v.offset_h)
            + preferred_slot(v.category, v.tags::text[]) end,
  v.duration, v.recurrence,
  v.is_free, v.price, v.price_note, v.venue, v.address,
  st_makepoint(v.lng, v.lat)::geography,
  null, v.external, v.locality, v.saves, v.shares, 'catalog'
from (values

  ('b0000000-0000-4000-8000-000000000101','tokyo','shibuya',
   'Shibuya Yokocho Lantern Alley',null,
   'Two hundred metres of red lanterns and regional izakaya, open past 3am.',
   'A covered alley under Miyashita Park where each stall cooks the food of a different Japanese prefecture  Hokkaido crab at one counter, Kyushu motsunabe at the next. Locals rate the atmosphere well above the cooking, which is the honest reason to come: it is loud, cheap to walk through, and one of the few places in Shibuya still serving at 4am.',
   'food','{food,nightlife,late-night,group-friendly,alcohol}', null, 60, 'Open daily until late',
   true, 0, 'Free to walk; stalls from 800', 'Shibuya Yokocho, RAYARD Miyashita Park','1-26-5 Jingumae, Shibuya City, Tokyo',
   139.7020, 35.6613, null, 0.35, 0, 0),

  ('b0000000-0000-4000-8000-000000000102','kyoto',null,
   'Do It Jazz at Club Metro',null,
   'Jazz dance night in a subway-station basement that has run since 1990.',
   'Club Metro occupies the basement of a Keihan station entrance and has been Kyoto''s underground music room for thirty-five years. Do It Jazz is its long-running swing and jazz-dance night: fedoras, partner footwork, and a floor that fills with people who clearly practise. Turn up alone and someone will dance with you.',
   'nightlife','{nightlife,music,dance,late-night,solo-friendly,alcohol}', interval '5 days', 240, 'Monthly  check Club Metro listings',
   false, 2500, 'Door price, one drink included', 'Club Metro','Ebisu Building B1F, Kawabata-Marutamachi, Sakyo Ward, Kyoto',
   135.7736, 35.0181, 'http://www.metro.ne.jp/', 0.91, 0, 0),

  ('b0000000-0000-4000-8000-000000000103','osaka',null,
   'Boat Race Suminoe',null,
   'Motorboat racing, 100 to get in, and nobody in the stands is a tourist.',
   'Kyotei is one of Japan''s four legal public gambling sports and Suminoe is Osaka''s course. Entry is a hundred yen. The crowd is retirees with pencils and marked-up form guides, the boats are terrifyingly fast around the first buoy, and a hundred-yen bet keeps you interested for the whole afternoon. Twenty minutes south of Namba on the Yotsubashi line.',
   'traditional','{gambling,sport,cheap,solo-friendly,local}', interval '2 days', 180, 'Race days  check the calendar',
   false, 100, 'Entry only; bets from 100', 'Boat Race Suminoe','1-1-71 Hokko, Suminoe Ward, Osaka',
   135.4755, 34.6130, 'https://www.boatrace-suminoye.jp/', 0.88, 0, 0),

  ('b0000000-0000-4000-8000-000000000104','tokyo','shinjuku',
   'Warp Shinjuku',null,
   'Four floors, four genres, and it does not card you at the door for being foreign.',
   'A Kabukicho megaclub with a different sound on every floor  hip-hop, EDM, K-pop, and a rotating fourth. The reason it keeps showing up in travellers'' feeds is that it is genuinely foreigner-friendly, which in Shinjuku is not a given. Busiest between 1am and 4am, when the trains have stopped and nobody is leaving.',
   'nightlife','{nightlife,music,late-night,group-friendly,club,alcohol}', interval '3 days', 300, 'Fridays and Saturdays',
   false, 3500, 'Door, includes one drink', 'Warp Shinjuku','1-20-1 Kabukicho, Shinjuku City, Tokyo',
   139.7025, 35.6952, null, 0.52, 0, 0),

  ('b0000000-0000-4000-8000-000000000105','tokyo',null,
   'Odaiba Summer Fireworks',' ',
   'Fireworks over Rainbow Bridge, with Tokyo Tower behind them.',
   'Tokyo Bay fireworks framed by the Rainbow Bridge, watched from the sand at Odaiba Seaside Park. Yakatabune pleasure boats fill the water underneath, which is the expensive way to see it; the free way is to arrive two hours early with a convenience-store dinner and sit on the beach like everyone else.',
   'festival','{festival,summer,free,group-friendly,photography}', interval '6 days', 90, 'Selected summer evenings',
   true, 0, null, 'Odaiba Seaside Park','1-4 Daiba, Minato City, Tokyo',
   139.7740, 35.6300, null, 0.30, 0, 0),

  ('b0000000-0000-4000-8000-000000000106','osaka',null,
   'Umeda Sky Building Heart Locks',null,
   'A rooftop ring 170m up, reached by an escalator through open air.',
   'Two towers joined at the fortieth floor by a doughnut-shaped open-air deck, which you reach on a glass escalator suspended in the gap between them. Couples engrave heart-shaped padlocks and clip them to the railings. It is unambiguously a tourist landmark and it is still one of the best hours in Osaka after dark.',
   'art','{views,architecture,couples,night,photography}', null, 90, 'Daily, 09:3022:30',
   false, 2000, 'Floating Garden Observatory admission', 'Umeda Sky Building, Floating Garden Observatory','1-1-88 Oyodonaka, Kita Ward, Osaka',
   135.4903, 34.7052, 'https://www.skybldg.co.jp/en/', 0.15, 0, 0),

  ('b0000000-0000-4000-8000-000000000107','tokyo',null,
   'Blue Note Tokyo',null,
   'Sit down, order dinner, and watch a band you would queue for anywhere else.',
   'The Aoyama room of the Blue Note, running two sets a night since 1988. You eat at the table while the band plays two metres away  Japanese acts like Soil & "Pimp" Sessions alongside touring international names. The alternative to a club night when you want the music loud and the room seated.',
   'music','{music,jazz,live,couples,dinner,alcohol}', interval '1 day', 120, 'Two sets nightly',
   false, 9500, 'Ticket only; food and drink extra', 'Blue Note Tokyo','6-3-16 Minami-Aoyama, Minato City, Tokyo',
   139.7135, 35.6608, 'https://www.bluenote.co.jp/jp/', 0.28, 0, 0),

  ('b0000000-0000-4000-8000-000000000108','tokyo','shibuya',
   'Shibuya Bon Odori',null,
   'A neighbourhood folk dance, held under the Shibuya billboards.',
   'A yagura tower goes up in Miyashita Park, taiko drummers climb it, and everybody circles below in happi coats doing steps their grandparents did. What makes the Shibuya one strange and good is the backdrop  Shibuya 109 and the neon crossing right behind a four-hundred-year-old dance. Visitors are pulled into the circle; there is no ticket and no audience.',
   'festival','{festival,traditional,summer,free,music,group-friendly}', interval '7 days', 180, 'Two evenings in late summer',
   true, 0, null, 'Miyashita Park','6-20-10 Jingumae, Shibuya City, Tokyo',
   139.7015, 35.6620, null, 0.58, 0, 0),

  ('b0000000-0000-4000-8000-000000000109','tokyo','shibuya',
   'Tokyo Night Market at Yoyogi Park',null,
   'Five nights of food stalls, carnival games and a live stage in Yoyogi Park.',
   'The Keyaki event plaza at the top of Yoyogi Park fills with food stalls, shooting galleries and a lantern-lit stage for five consecutive nights. It is a Tokyo crowd rather than a tourist one  office workers straight off the Yamanote, families, students  and it costs nothing to walk in.',
   'market','{market,food,music,free,group-friendly,summer}', interval '4 days', 120, 'Five consecutive nights',
   true, 0, 'Free entry; stalls from 500', 'Yoyogi Park Keyaki Namiki Plaza','2-1 Yoyogikamizonocho, Shibuya City, Tokyo',
   139.6950, 35.6698, null, 0.62, 0, 0),

  ('b0000000-0000-4000-8000-000000000110','tokyo',null,
   'Red Tokyo Tower',null,
   'Japan''s largest e-sports park, three floors inside the base of Tokyo Tower.',
   'Foot Town, the building under Tokyo Tower everyone walks past on the way to the lift, holds a three-floor digital amusement park: a robot-arm claw machine the size of a car, projection-mapped climbing walls, racing rigs and an e-sports arena. Almost nobody recommends it, which is why it is rarely queued.',
   'anime','{anime,gaming,indoor,group-friendly,rainy-day}', null, 150, 'Daily, 10:0022:00',
   false, 2900, 'Day pass', 'Red Tokyo Tower, Foot Town 35F','4-2-8 Shibakoen, Minato City, Tokyo',
   139.7454, 35.6586, 'https://tokyotower.red-brand.jp/', 0.25, 0, 0)

) as v(id, city, hood, name, name_ja, short_desc, long_desc, category, tags,
       offset_h, duration, recurrence, is_free, price, price_note, venue, address,
       lng, lat, external, locality, saves, shares)
join cities c on c.slug = v.city
left join neighborhoods n on n.city_id = c.id and n.slug = v.hood
on conflict (id) do nothing;

insert into experience_media (experience_id, kind, license, alt_text, is_primary, position)
select id, 'placeholder', 'placeholder', short_description, true, 0
from experiences
where source = 'catalog'
  and not exists (select 1 from experience_media m where m.experience_id = experiences.id);

