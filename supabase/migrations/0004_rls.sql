-- Row Level Security.
--
-- Authorization lives in the database, not in application code. There is no
-- endpoint a developer can forget to guard, and the UI team never has to reason
-- about permissions — they call as the signed-in user and get back exactly what
-- that user is allowed to see.
--
-- Shape of the rules:
--   * The catalogue (cities, experiences, media, hosts) is public read. It is a
--     discovery app; browsing must work before sign-in.
--   * Everything personal (preferences, saves, dismissals, itinerary) is
--     readable and writable only by its owner.

alter table cities               enable row level security;
alter table neighborhoods        enable row level security;
alter table interests            enable row level security;
alter table hosts                enable row level security;
alter table experiences          enable row level security;
alter table experience_media     enable row level security;
alter table profiles             enable row level security;
alter table traveler_preferences enable row level security;
alter table saved_items          enable row level security;
alter table dismissed_items      enable row level security;
alter table share_events         enable row level security;
alter table itinerary_entries    enable row level security;

-- ------------------------------------------------------ public catalogue --

create policy cities_read        on cities            for select using (true);
create policy neighborhoods_read on neighborhoods     for select using (true);
create policy interests_read     on interests         for select using (true);
create policy hosts_read         on hosts             for select using (true);
create policy experiences_read   on experiences       for select using (published);
create policy media_read         on experience_media  for select using (true);

-- --------------------------------------------------------------- identity --

-- Display names and avatars are shown on shared itineraries, so profiles are
-- readable; the free-text `about` field is personalisation input rather than
-- anything the product renders for other people.
create policy profiles_read       on profiles for select using (true);
create policy profiles_write_own  on profiles for update
  using      (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- ------------------------------------------------------------- owned data --

create policy prefs_own on traveler_preferences for all
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

-- Share counts are public social proof, but who shared what is not. Read is
-- deliberately closed: the aggregate lives on experiences.share_count.
create policy shares_insert_own on share_events for insert
  with check (profile_id = current_profile_id() or profile_id is null);

create policy shares_read_own on share_events for select
  using (profile_id = current_profile_id());
