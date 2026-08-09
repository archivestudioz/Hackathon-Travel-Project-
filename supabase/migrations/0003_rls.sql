-- Roam — Row Level Security.
--
-- This is the authorization layer. Not middleware, not a guard clause in an
-- endpoint someone can forget to add — the database itself refuses to return
-- rows the caller shouldn't see. A traveler cannot read another traveler's ride
-- even if the client is rewritten from scratch.

alter table cities         enable row level security;
alter table profiles       enable row level security;
alter table guide_profiles enable row level security;
alter table guide_status   enable row level security;
alter table places         enable row level security;
alter table events         enable row level security;
alter table narrations     enable row level security;
alter table rides          enable row level security;
alter table ride_stops     enable row level security;
alter table ride_positions enable row level security;
alter table wifi_reports   enable row level security;

-- ------------------------------------------------- public discovery surface --
-- Cities, places, events, guides, and narration are the catalogue. Anyone can
-- browse them, signed in or not — that's the point of a discovery app.

create policy cities_read         on cities         for select using (true);
create policy places_read         on places         for select using (true);
create policy events_read         on events         for select using (true);
create policy narrations_read     on narrations     for select using (true);
create policy profiles_read       on profiles       for select using (true);
create policy guide_profiles_read on guide_profiles for select using (true);
create policy guide_status_read   on guide_status   for select using (true);

-- A traveler may edit only their own profile.
create policy profiles_update_own on profiles for update
  using      (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- --------------------------------------------------------------- your rides --
-- Visible to the two people on the ride and nobody else.

create policy rides_read_participant on rides for select
  using (traveler_id = current_profile_id() or guide_id = current_profile_id());

create policy rides_insert_own on rides for insert
  with check (traveler_id = current_profile_id());

create policy rides_update_participant on rides for update
  using      (traveler_id = current_profile_id() or guide_id = current_profile_id())
  with check (traveler_id = current_profile_id() or guide_id = current_profile_id());

-- Stops and positions inherit the ride's participation check.
create policy ride_stops_participant on ride_stops for select
  using (exists (
    select 1 from rides r
     where r.id = ride_stops.ride_id
       and (r.traveler_id = current_profile_id() or r.guide_id = current_profile_id())
  ));

create policy ride_positions_participant on ride_positions for select
  using (exists (
    select 1 from rides r
     where r.id = ride_positions.ride_id
       and (r.traveler_id = current_profile_id() or r.guide_id = current_profile_id())
  ));

-- The traveler's own device may report position; the guide side is driven by
-- the simulator using the service-role key, which bypasses RLS entirely.
create policy ride_positions_insert_participant on ride_positions for insert
  with check (exists (
    select 1 from rides r
     where r.id = ride_positions.ride_id
       and (r.traveler_id = current_profile_id() or r.guide_id = current_profile_id())
  ));

-- ------------------------------------------------------------ wifi reports --
-- Counts are public (that's what makes the layer trustworthy); writing one
-- requires a session, so a single actor can't anonymously flood a venue.

create policy wifi_reports_read on wifi_reports for select using (true);

create policy wifi_reports_insert_authed on wifi_reports for insert
  with check (current_profile_id() is not null);
