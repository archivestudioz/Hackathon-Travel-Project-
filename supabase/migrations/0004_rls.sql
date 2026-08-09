-- Row Level Security.
--
-- Authorization lives in the database, not in application code. There is no
-- endpoint a developer can forget to guard, and the UI team never reasons about
-- permissions — they call as the signed-in user and receive exactly what that
-- user is allowed to see.
--
--   * The catalogue and the vocabularies are public read. It is a discovery
--     app; browsing has to work before anyone signs up.
--   * Everything personal — taste, trips, saves, dismissals, itinerary — is
--     readable and writable only by its owner.

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

-- ------------------------------------------ public catalogue & vocabulary --

create policy countries_read      on countries        for select using (true);
create policy interests_read      on interests        for select using (true);
create policy reasons_read        on travel_reasons   for select using (true);
create policy cities_read         on cities           for select using (true);
create policy neighborhoods_read  on neighborhoods    for select using (true);
create policy hosts_read          on hosts            for select using (true);
create policy experiences_read    on experiences      for select using (published);
create policy media_read          on experience_media for select using (true);

-- --------------------------------------------------------------- identity --

-- Display names appear on shared itineraries, so profiles are readable. The
-- free-text `about` is personalisation input rather than anything rendered for
-- other people.
create policy profiles_read      on profiles for select using (true);
create policy profiles_write_own on profiles for update
  using      (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- ------------------------------------------------------------- owned data --

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

-- Aggregate share counts are public social proof (denormalised onto
-- experiences); who shared what is not.
create policy shares_insert_own on share_events for insert
  with check (profile_id = current_profile_id() or profile_id is null);

create policy shares_read_own on share_events for select
  using (profile_id = current_profile_id());
