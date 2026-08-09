-- Roam — mint a traveler profile on first sign-in.
--
-- The app uses Supabase anonymous sign-in: no login screen, no seeded
-- passwords, but a real auth.uid() so RLS is genuinely enforced rather than
-- simulated. This trigger gives every new session a profile to own.

create or replace function handle_new_auth_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into profiles (auth_user_id, role, display_name, languages)
  values (
    new.id,
    'traveler',
    coalesce(new.raw_user_meta_data ->> 'display_name', 'Traveler'),
    case
      when new.raw_user_meta_data ->> 'locale' is not null
        then array[new.raw_user_meta_data ->> 'locale']
      else array['en']
    end
  )
  on conflict (auth_user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();
