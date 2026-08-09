-- Real accounts, with guest as the escape hatch.
--
-- Signup is the primary action; "Continue as guest" sits at the bottom of the
-- same screen. Both land in the same place, which is the important part: a
-- guest is not a lesser object with its own code path, it is a profile whose
-- auth user happens to be anonymous.
--
-- The payoff is the upgrade. Supabase can convert an anonymous user into a real
-- one IN PLACE — same `auth.users.id`, so the same `profiles` row, so every
-- save, dismissal, trip and itinerary survives. A guest who scrolls for ten
-- minutes and then signs up loses nothing, which is the entire reason to offer
-- guest mode at all rather than a hard wall.

-- Guest status is derived from the auth user, not set by hand. A manually
-- maintained flag drifts the moment someone upgrades through a path we did not
-- anticipate.
create or replace function handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_profile uuid;
  v_anon    boolean := coalesce((to_jsonb(new) ->> 'is_anonymous')::boolean, false);
begin
  -- nullif guards the empty string: split_part on a null email yields '',
  -- which coalesce happily accepts, leaving the traveler nameless.
  insert into profiles (auth_user_id, display_name, is_guest)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''),
             nullif(split_part(coalesce(to_jsonb(new) ->> 'email', ''), '@', 1), ''),
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

-- The upgrade. When GoTrue converts an anonymous user (the client calls
-- updateUser with an email, or links an OAuth identity), is_anonymous flips to
-- false and this clears the guest flag automatically. No client call, no
-- opportunity to forget.
create or replace function handle_auth_user_upgraded()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_was boolean := coalesce((to_jsonb(old) ->> 'is_anonymous')::boolean, false);
  v_now boolean := coalesce((to_jsonb(new) ->> 'is_anonymous')::boolean, false);
begin
  if v_was and not v_now then
    update profiles
       set is_guest = false,
           -- Only adopt the account's name if the traveler never chose one.
           display_name = case
             when coalesce(nullif(display_name, ''), 'Traveler') = 'Traveler'
               then coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''),
                             nullif(split_part(coalesce(to_jsonb(new) ->> 'email', ''), '@', 1), ''),
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

-- ---------------------------------------------------------- session state --

-- One call that tells the client which screen to render. Without it the UI ends
-- up inferring account state from three separate fields and getting it subtly
-- wrong on the edges — a guest mid-onboarding, or an upgraded account whose
-- taps predate the account.
create or replace function session_state()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'signed_in',   p.id is not null,
    'profile_id',  p.id,
    'display_name',p.display_name,
    'is_guest',    coalesce(p.is_guest, true),
    'onboarded',   coalesce(tp.onboarded, false),
    -- What the client should show next.
    --   'welcome'  sign-up screen, guest link at the bottom
    --   'picker'   the three-tap cold start
    --   'feed'     everything is ready
    'next_screen', case
                     when p.id is null                      then 'welcome'
                     when not coalesce(tp.onboarded, false) then 'picker'
                     else 'feed'
                   end,
    'saved_count', (select count(*) from saved_items s where s.profile_id = p.id),
    'trip_count',  (select count(*) from trips t where t.profile_id = p.id),
    'confidence',  learned_confidence(p.id),
    -- Nudge the upgrade once a guest has something worth losing, not before.
    -- Prompting an empty guest to sign up is how you lose them.
    'prompt_signup', coalesce(p.is_guest, false)
                     and (select count(*) from saved_items s where s.profile_id = p.id) >= 3
  )
  from profiles p
  left join traveler_profiles tp on tp.profile_id = p.id
  where p.id = current_profile_id();
$$;

-- Backfill anything created before this migration.
update profiles p
   set is_guest = coalesce((to_jsonb(u) ->> 'is_anonymous')::boolean, false)
  from auth.users u
 where u.id = p.auth_user_id;
