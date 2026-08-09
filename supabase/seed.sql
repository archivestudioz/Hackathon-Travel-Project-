-- Roam — demo seed: New York · San Juan · Venice
--
-- Three cities chosen because each breaks a different assumption:
--   NYC        dense, drivable, huge event inventory, LinkNYC free wifi
--   San Juan   beaches + walkable colonial grid, Spanish, cruise-day windows
--   Venice     NO CARS — walking and boat only. Proves the mode system generalises.
--
-- Places here are a hand-checked core set. scripts/fetch_places.py bulk-loads the
-- rest from Overpass with exact coordinates, wifi tags, and wheelchair access.

begin;

-- ------------------------------------------------------------------ cities --

insert into cities (slug, name, country, center, default_mode, modes, locales,
                    bbox_min_lng, bbox_min_lat, bbox_max_lng, bbox_max_lat, tagline)
values
  ('nyc', 'New York', 'United States',
   st_makepoint(-73.9855, 40.7580)::geography, 'walk', '{walk,drive}', '{en,es,zh}',
   -74.0200, 40.7000, -73.9300, 40.8000,
   'Five boroughs, a thousand neighbourhoods, free wifi on half the corners.'),

  ('sju', 'San Juan', 'Puerto Rico',
   st_makepoint(-66.1057, 18.4655)::geography, 'walk', '{walk,drive}', '{es,en}',
   -66.1400, 18.4400, -66.0300, 18.4800,
   'Blue cobblestones, 500-year-old forts, and the beach twenty minutes away.'),

  ('vce', 'Venice', 'Italy',
   st_makepoint(12.3155, 45.4408)::geography, 'walk', '{walk,boat}', '{en,es}',
   12.3000, 45.4200, 12.3700, 45.4500,
   'No cars. No grid. Get lost on purpose — that is the entire point.');

-- ------------------------------------------------------------------ guides --

insert into profiles (id, role, display_name, avatar_url, bio, languages)
values
  ('11111111-1111-4111-8111-000000000001', 'guide', 'Mateo Ruiz',    null, 'Lower East Side born. I will feed you until you beg me to stop.', '{en,es}'),
  ('11111111-1111-4111-8111-000000000002', 'guide', 'Aisha Bello',   null, 'Brooklyn architecture and the stories behind the facades.',       '{en,fr}'),
  ('11111111-1111-4111-8111-000000000003', 'guide', 'Danny Chen',    null, 'Chinatown to Flushing. I drive, so we cover ground.',             '{en,zh}'),
  ('11111111-1111-4111-8111-000000000004', 'guide', 'Yamila Cortés', null, 'Old San Juan is my backyard. Forts, fritters, and no crowds.',    '{es,en}'),
  ('11111111-1111-4111-8111-000000000005', 'guide', 'Rafael Nieves', null, 'Beaches, bomba, and the best mofongo outside my mother''s house.', '{es,en}'),
  ('11111111-1111-4111-8111-000000000006', 'guide', 'Elena Bassi',   null, 'Venetian, fifth generation. I know which bridges the crowds skip.', '{en,es}'),
  ('11111111-1111-4111-8111-000000000007', 'guide', 'Marco Zanetti', null, 'Licensed boatman. The city looks completely different from water.', '{en}');

insert into guide_profiles (profile_id, headline, modes, specialties, hourly_rate_cents, rating, rides_completed, verified, home_point)
values
  ('11111111-1111-4111-8111-000000000001', 'Food-first walks on the Lower East Side',
   '{walk}',       '{eat,market,culture}',        4500, 4.9, 214, true,  st_makepoint(-73.9884, 40.7226)::geography),
  ('11111111-1111-4111-8111-000000000002', 'Brooklyn on foot, facades and back stories',
   '{walk}',       '{culture,attraction}',        4000, 4.8, 132, true,  st_makepoint(-73.9690, 40.6602)::geography),
  ('11111111-1111-4111-8111-000000000003', 'Chinatown to Flushing, by car',
   '{walk,drive}', '{eat,market}',                6000, 4.7,  88, true,  st_makepoint(-73.9970, 40.7150)::geography),
  ('11111111-1111-4111-8111-000000000004', 'Old San Juan without the cruise crowds',
   '{walk}',       '{attraction,culture,eat}',    3500, 5.0, 176, true,  st_makepoint(-66.1157, 18.4655)::geography),
  ('11111111-1111-4111-8111-000000000005', 'Beaches and bomba, east of the city',
   '{walk,drive}', '{beach,culture,eat}',         4000, 4.8, 121, true,  st_makepoint(-66.0770, 18.4601)::geography),
  ('11111111-1111-4111-8111-000000000006', 'The Venice locals actually walk through',
   '{walk}',       '{culture,attraction,market}', 5000, 4.9, 203, true,  st_makepoint(12.3266, 45.4450)::geography),
  ('11111111-1111-4111-8111-000000000007', 'Venice from the water, by licensed boat',
   '{boat}',       '{attraction,viewpoint}',      9000, 4.9,  67, true,  st_makepoint(12.3358, 45.4380)::geography);

insert into guide_status (guide_id, is_online, last_point)
select profile_id, true, home_point from guide_profiles;

-- ------------------------------------------------------------------ places --

-- New York
insert into places (city_id, name, category, themes, blurb, hidden_gem, point, has_wifi, wifi_fee, wheelchair)
-- themes needs an explicit cast: inside a VALUES list an array literal infers as text.
select c.id, v.name, v.category, v.themes::text[], v.blurb, v.gem,
       st_makepoint(v.lng, v.lat)::geography, v.wifi, v.fee, v.wc
from cities c, (values
  ('Katz''s Delicatessen',   'eat',        '{eat,culture}',        'Cutting pastrami by hand since 1888. Do not lose the ticket they hand you at the door.', false, -73.9874, 40.7223, false, null,  'yes'),
  ('Russ & Daughters',       'eat',        '{eat,culture}',        'Appetizing, not a deli — a distinction locals will explain at length.',                  false, -73.9884, 40.7226, false, null,  'limited'),
  ('Tenement Museum',        'culture',    '{culture,history}',    'Actual apartments, actual families, restored room by room.',                             false, -73.9901, 40.7188, true,  'customers', 'limited'),
  ('Washington Square Park', 'attraction', '{attraction,culture}', 'Chess hustlers, a piano someone dragged in, and the arch.',                              false, -73.9973, 40.7308, true,  'no',  'yes'),
  ('The High Line',          'attraction', '{attraction,hike}',    'A freight rail line the neighbourhood refused to let them demolish.',                    false, -74.0048, 40.7480, false, null,  'yes'),
  ('Chelsea Market',         'market',     '{eat,market}',         'A former Nabisco factory. The Oreo was invented in this building.',                      false, -74.0061, 40.7424, true,  'no',  'yes'),
  ('Brooklyn Bridge',        'attraction', '{attraction,viewpoint}','Walk it toward Manhattan at dusk, never the other way.',                                false, -73.9969, 40.7061, false, null,  'yes'),
  ('Bryant Park',            'attraction', '{attraction,wifi}',    'Free wifi, free chairs, and the back of the public library.',                            false, -73.9832, 40.7536, true,  'no',  'yes'),
  ('Top of the Rock',        'viewpoint',  '{viewpoint}',          'The view Empire State visitors are actually trying to photograph.',                      false, -73.9794, 40.7593, false, null,  'yes'),
  ('The Met',                'culture',    '{culture}',            'Two million square feet. Pick three wings and accept defeat.',                           false, -73.9632, 40.7794, true,  'no',  'yes'),
  ('Bethesda Terrace',       'attraction', '{attraction,culture}', 'The only formal architecture in Central Park, and the best acoustics.',                  false, -73.9709, 40.7740, false, null,  'yes'),
  ('Coney Island Beach',     'beach',      '{beach,attraction}',   'A boardwalk, the Cyclone, and hot dogs older than your grandparents.',                   false, -73.9791, 40.5730, true,  'no',  'yes'),
  ('Prospect Park Ravine',   'hike',       '{hike,attraction}',    'Brooklyn''s only forest. The designers liked it better than Central Park.',              true,  -73.9690, 40.6602, false, null,  'limited')
) as v(name, category, themes, blurb, gem, lng, lat, wifi, fee, wc)
where c.slug = 'nyc';

-- San Juan
insert into places (city_id, name, category, themes, blurb, hidden_gem, point, has_wifi, wifi_fee, wheelchair)
-- themes needs an explicit cast: inside a VALUES list an array literal infers as text.
select c.id, v.name, v.category, v.themes::text[], v.blurb, v.gem,
       st_makepoint(v.lng, v.lat)::geography, v.wifi, v.fee, v.wc
from cities c, (values
  ('Castillo San Felipe del Morro', 'attraction', '{attraction,history}', 'Six levels of fortress aimed at an ocean that kept sending ships.',        false, -66.1241, 18.4709, false, null, 'limited'),
  ('Castillo San Cristóbal',        'attraction', '{attraction,history}', 'The larger fort, and the one most visitors skip. Go here instead.',        true,  -66.1046, 18.4700, false, null, 'limited'),
  ('Calle Fortaleza',               'attraction', '{attraction,culture}', 'The umbrella street. Yes it is for the photo. Take the photo.',            false, -66.1157, 18.4655, true,  'customers', 'yes'),
  ('Catedral de San Juan Bautista', 'culture',    '{culture,history}',    'Ponce de León is buried in the wall on your right.',                        false, -66.1183, 18.4655, false, null, 'yes'),
  ('Paseo de la Princesa',          'attraction', '{attraction,viewpoint}','A promenade along the old city wall, best an hour before sunset.',         false, -66.1180, 18.4645, false, null, 'yes'),
  ('La Placita de Santurce',        'market',     '{market,eat,nightlife}','A produce market by day that becomes the whole city''s bar after dark.',   true,  -66.0731, 18.4487, true,  'no', 'yes'),
  ('Barrachina',                    'eat',        '{eat}',                'Claims to have invented the piña colada. Caribe Hilton disputes it loudly.', false, -66.1173, 18.4661, true,  'customers', 'yes'),
  ('Condado Beach',                 'beach',      '{beach}',              'City beach, real waves, hotels behind you and nothing in front.',          false, -66.0770, 18.4601, true,  'customers', 'limited'),
  ('Ocean Park Beach',              'beach',      '{beach}',              'Where San Juan actually swims. Fewer towels, better water.',               true,  -66.0530, 18.4550, false, null, 'no'),
  ('Museo de Arte de Puerto Rico',  'culture',    '{culture}',            'Five centuries of Puerto Rican art and a garden worth the ticket alone.',   false, -66.0680, 18.4497, true,  'no', 'yes')
) as v(name, category, themes, blurb, gem, lng, lat, wifi, fee, wc)
where c.slug = 'sju';

-- Venice
insert into places (city_id, name, category, themes, blurb, hidden_gem, point, has_wifi, wifi_fee, wheelchair)
-- themes needs an explicit cast: inside a VALUES list an array literal infers as text.
select c.id, v.name, v.category, v.themes::text[], v.blurb, v.gem,
       st_makepoint(v.lng, v.lat)::geography, v.wifi, v.fee, v.wc
from cities c, (values
  ('Piazza San Marco',            'attraction', '{attraction,culture}',  'Napoleon called it the drawing room of Europe. It floods most winters.',   false, 12.3388, 45.4341, true,  'no', 'yes'),
  ('Basilica di San Marco',       'culture',    '{culture,history}',     'Eight thousand square metres of gold mosaic, most of it looted.',          false, 12.3397, 45.4345, false, null, 'limited'),
  ('Palazzo Ducale',              'culture',    '{culture,history}',     'Government, courtroom and prison in one building. Cross the Bridge of Sighs.', false, 12.3400, 45.4337, false, null, 'limited'),
  ('Ponte di Rialto',             'attraction', '{attraction,viewpoint}','Four hundred years of people agreeing to stand in the same spot.',         false, 12.3358, 45.4380, false, null, 'yes'),
  ('Mercato di Rialto',           'market',     '{market,eat}',          'Fish market since 1097. Gone by lunchtime, so come early.',                false, 12.3340, 45.4400, false, null, 'limited'),
  ('Libreria Acqua Alta',         'attraction', '{attraction,culture}',  'Books stored in bathtubs and a gondola, because the floor floods.',        true,  12.3417, 45.4374, false, null, 'no'),
  ('Squero di San Trovaso',       'culture',    '{culture}',             'One of the last gondola workshops. Watch from across the canal.',          true,  12.3258, 45.4306, false, null, 'no'),
  ('Gallerie dell''Accademia',    'culture',    '{culture}',             'Venetian painting before Venice became a postcard of itself.',             false, 12.3280, 45.4314, false, null, 'yes'),
  ('Peggy Guggenheim Collection', 'culture',    '{culture}',             'Her unfinished palazzo on the Grand Canal, full of modernists.',           false, 12.3311, 45.4308, true,  'no', 'yes'),
  ('Cannaregio & the Ghetto',     'culture',    '{culture,history}',     'The original ghetto, and the quarter Venetians still live in.',            true,  12.3266, 45.4450, false, null, 'limited'),
  ('Burano',                      'attraction', '{attraction,viewpoint}','Painted fishermen''s houses, forty minutes out by vaporetto.',             false, 12.4167, 45.4853, false, null, 'limited'),
  ('Lido di Venezia',             'beach',      '{beach}',               'The sandbar that keeps the Adriatic out of the lagoon. Actual beach.',     false, 12.3670, 45.4088, false, null, 'yes')
) as v(name, category, themes, blurb, gem, lng, lat, wifi, fee, wc)
where c.slug = 'vce';

-- ------------------------------------------------------------------ events --

-- Hand-seeded from real listings. Timestamps are relative to now() so the demo
-- never goes stale. Ticketmaster / SeatGeek adapters replace this in V1 — the
-- schema is source-agnostic on purpose.
insert into events (city_id, source, name, category, starts_at, venue_name, point, ticket_url, price_min_cents, blurb)
select c.id, 'manual', v.name, v.category, now() + v.offset_h, v.venue,
       st_makepoint(v.lng, v.lat)::geography, null, v.price, v.blurb
from cities c, (values
  ('nyc', 'Jazz at Smalls',              'music',     interval '6 hours',  'Smalls Jazz Club',      -74.0021, 40.7333, 3500, 'Basement room, no amplification, sets until 4am.'),
  ('nyc', 'Brooklyn Night Market',       'market',    interval '30 hours', 'Grand Army Plaza',      -73.9700, 40.6740, 0,    'Forty vendors, most of them somebody''s family recipe.'),
  ('nyc', 'Shakespeare in the Park',     'theater',   interval '54 hours', 'Delacorte Theater',     -73.9694, 40.7800, 0,    'Free, outdoors, and you will queue. Bring a guide who knows when.'),
  ('sju', 'Bomba y Plena en la Placita', 'music',     interval '8 hours',  'La Placita de Santurce',-66.0731, 18.4487, 0,    'Drums, call and response, and no stage worth speaking of.'),
  ('sju', 'Noches de Galería',           'festival',  interval '32 hours', 'Old San Juan',          -66.1157, 18.4655, 0,    'Galleries open late, streets close, the whole quarter walks.'),
  ('vce', 'Vivaldi at the Frari',        'music',     interval '10 hours', 'Basilica dei Frari',     12.3266, 45.4368, 4000, 'Four Seasons, in the church where the composer was baptised.'),
  ('vce', 'Regata Storica rowing heats', 'festival',  interval '28 hours', 'Grand Canal',            12.3300, 45.4350, 0,    'Sixteenth-century costume, extremely competitive rowing.')
) as v(city, name, category, offset_h, venue, lng, lat, price, blurb)
where c.slug = v.city;

commit;
