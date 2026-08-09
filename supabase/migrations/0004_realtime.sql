-- Roam — Realtime.
--
-- The map does not poll. It subscribes to Postgres' write-ahead log through
-- Supabase Realtime, so a row written by the guide simulator reaches the
-- browser as a push. RLS is applied to the stream too: a traveler only receives
-- positions for rides they're actually on.

alter publication supabase_realtime add table ride_positions;
alter publication supabase_realtime add table rides;

-- Realtime needs the full row on UPDATE to evaluate RLS against it, otherwise
-- filtered subscriptions silently drop messages.
alter table rides          replica identity full;
alter table ride_positions replica identity full;
