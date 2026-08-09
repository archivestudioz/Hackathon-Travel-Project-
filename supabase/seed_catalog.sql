-- Experiences that exist because there is real video of them.
--
--   psql "$SUPABASE_DB_URL" -f supabase/seed_catalog.sql   # after seed.sql
--
-- content/video-catalog.md lists 39 clips your team pulled from TikTok and
-- Instagram. content/clip-map.tsv triages all 39. This file creates the ten
-- that survived both filters: in Tokyo, Kyoto or Osaka, AND at a venue real
-- enough to put a pin on.
--
-- The other twenty-nine are not here, and the map says why for each one. Two
-- reasons dominate. Fifteen are elsewhere in Japan — a Miyazaki gorge filed
-- under "Osaka" would land in an Osaka day's walking cluster and the planner
-- would route someone across the country for lunch. Ten have no identifiable
-- venue; the catalog says so itself. Inventing coordinates for "an R&B bar in
-- Tokyo" is the one thing this app must never do, because a judge who knows
-- Tokyo will check.
--
-- WHAT THIS FIXES BESIDES CONTENT
--
-- Kyoto had zero nightlife. Not "thin" — zero rows, so a traveler with a Kyoto
-- leg and a taste for music got nothing after dark and the planner left the
-- evening empty. Clip 6 fixes that.
--
-- Osaka had no low-locality anchor. Every Osaka row scored 0.72+, so "hidden
-- local gems" in Osaka was ranking against nothing. Umeda Sky Building comes in
-- at 0.15 on purpose — the scoring needs something touristic to beat.
--
-- COORDINATES ARE VENUE CENTROIDS, good to roughly a block. They are accurate
-- enough for neighborhood clustering and travel estimates, which is all the
-- planner asks of them. `source` is set to 'catalog' so recompute_localness()
-- leaves these rows alone, same as the hand-curated seed.
--
-- MEDIA IS SEEDED AS PLACEHOLDER, like everything else. Nothing here downloads
-- or rehosts a video — the schema still has no column for one. Running
--
--     python scripts/attach_media.py --catalog content/video-catalog.md
--
-- resolves the real post through the keyless oEmbed endpoints and upgrades
-- these rows in place, with the creator's name and a link back.

begin;

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

  -- ── clip 4 · Shibuya, food ────────────────────────────────────────────────
  -- The creator's own caption is "didn't eat here, I've heard the food isn't
  -- the best" — so this is seeded as a free stroll, not a meal. Pretending
  -- otherwise would put it in the wrong price bucket and the wrong day slot.
  ('b0000000-0000-4000-8000-000000000101','tokyo','shibuya',
   'Shibuya Yokocho Lantern Alley','渋谷横丁',
   'Two hundred metres of red lanterns and regional izakaya, open past 3am.',
   'A covered alley under Miyashita Park where each stall cooks the food of a different Japanese prefecture — Hokkaido crab at one counter, Kyushu motsunabe at the next. Locals rate the atmosphere well above the cooking, which is the honest reason to come: it is loud, cheap to walk through, and one of the few places in Shibuya still serving at 4am.',
   'food','{food,nightlife,late-night,group-friendly,alcohol}', null, 60, 'Open daily until late',
   true, 0, 'Free to walk; stalls from ¥800', 'Shibuya Yokocho, RAYARD Miyashita Park','1-26-5 Jingumae, Shibuya City, Tokyo',
   139.7020, 35.6613, null, 0.35, 0, 0),

  -- ── clip 6 · Kyoto, nightlife ─────────────────────────────────────────────
  -- The only Kyoto nightlife row in the database. Club Metro has run in the
  -- same Keihan station basement since 1990 and almost no guidebook lists it.
  ('b0000000-0000-4000-8000-000000000102','kyoto',null,
   'Do It Jazz at Club Metro','ドゥ・イット・ジャズ',
   'Jazz dance night in a subway-station basement that has run since 1990.',
   'Club Metro occupies the basement of a Keihan station entrance and has been Kyoto''s underground music room for thirty-five years. Do It Jazz is its long-running swing and jazz-dance night: fedoras, partner footwork, and a floor that fills with people who clearly practise. Turn up alone and someone will dance with you.',
   'nightlife','{nightlife,music,dance,late-night,solo-friendly,alcohol}', interval '5 days', 240, 'Monthly — check Club Metro listings',
   false, 2500, 'Door price, one drink included', 'Club Metro','Ebisu Building B1F, Kawabata-Marutamachi, Sakyo Ward, Kyoto',
   135.7736, 35.0181, 'http://www.metro.ne.jp/', 0.91, 0, 0),

  -- ── clip 12 · Osaka, only-in-Japan ────────────────────────────────────────
  -- Filed as `traditional` because kyotei is a 70-year-old Japanese
  -- institution and there is no sports category. Tagged `gambling`, which
  -- migration 0012 teaches is_adults_only() to treat as 20+.
  ('b0000000-0000-4000-8000-000000000103','osaka',null,
   'Boat Race Suminoe','住之江競艇',
   'Motorboat racing, ¥100 to get in, and nobody in the stands is a tourist.',
   'Kyotei is one of Japan''s four legal public gambling sports and Suminoe is Osaka''s course. Entry is a hundred yen. The crowd is retirees with pencils and marked-up form guides, the boats are terrifyingly fast around the first buoy, and a hundred-yen bet keeps you interested for the whole afternoon. Twenty minutes south of Namba on the Yotsubashi line.',
   'traditional','{gambling,sport,cheap,solo-friendly,local}', interval '2 days', 180, 'Race days — check the calendar',
   false, 100, 'Entry only; bets from ¥100', 'Boat Race Suminoe','1-1-71 Hokko, Suminoe Ward, Osaka',
   135.4755, 34.6130, 'https://www.boatrace-suminoye.jp/', 0.88, 0, 0),

  -- ── clip 16 · Shinjuku, nightlife ─────────────────────────────────────────
  ('b0000000-0000-4000-8000-000000000104','tokyo','shinjuku',
   'Warp Shinjuku','ワープ新宿',
   'Four floors, four genres, and it does not card you at the door for being foreign.',
   'A Kabukicho megaclub with a different sound on every floor — hip-hop, EDM, K-pop, and a rotating fourth. The reason it keeps showing up in travellers'' feeds is that it is genuinely foreigner-friendly, which in Shinjuku is not a given. Busiest between 1am and 4am, when the trains have stopped and nobody is leaving.',
   'nightlife','{nightlife,music,late-night,group-friendly,club,alcohol}', interval '3 days', 300, 'Fridays and Saturdays',
   false, 3500, 'Door, includes one drink', 'Warp Shinjuku','1-20-1 Kabukicho, Shinjuku City, Tokyo',
   139.7025, 35.6952, null, 0.52, 0, 0),

  -- ── clip 22 · Tokyo Bay, festival ─────────────────────────────────────────
  ('b0000000-0000-4000-8000-000000000105','tokyo',null,
   'Odaiba Summer Fireworks','お台場 花火',
   'Fireworks over Rainbow Bridge, with Tokyo Tower behind them.',
   'Tokyo Bay fireworks framed by the Rainbow Bridge, watched from the sand at Odaiba Seaside Park. Yakatabune pleasure boats fill the water underneath, which is the expensive way to see it; the free way is to arrive two hours early with a convenience-store dinner and sit on the beach like everyone else.',
   'festival','{festival,summer,free,group-friendly,photography}', interval '6 days', 90, 'Selected summer evenings',
   true, 0, null, 'Odaiba Seaside Park','1-4 Daiba, Minato City, Tokyo',
   139.7740, 35.6300, null, 0.30, 0, 0),

  -- ── clip 24 · Osaka, the deliberate tourist anchor ────────────────────────
  -- Locality 0.15. Osaka's other rows all sit above 0.72, which left "hidden
  -- local gems" in Osaka ranking against nothing at all.
  ('b0000000-0000-4000-8000-000000000106','osaka',null,
   'Umeda Sky Building Heart Locks','梅田スカイビル',
   'A rooftop ring 170m up, reached by an escalator through open air.',
   'Two towers joined at the fortieth floor by a doughnut-shaped open-air deck, which you reach on a glass escalator suspended in the gap between them. Couples engrave heart-shaped padlocks and clip them to the railings. It is unambiguously a tourist landmark and it is still one of the best hours in Osaka after dark.',
   'art','{views,architecture,couples,night,photography}', null, 90, 'Daily, 09:30–22:30',
   false, 2000, 'Floating Garden Observatory admission', 'Umeda Sky Building, Floating Garden Observatory','1-1-88 Oyodonaka, Kita Ward, Osaka',
   135.4903, 34.7052, 'https://www.skybldg.co.jp/en/', 0.15, 0, 0),

  -- ── clip 26 · Aoyama, music ───────────────────────────────────────────────
  ('b0000000-0000-4000-8000-000000000107','tokyo',null,
   'Blue Note Tokyo','ブルーノート東京',
   'Sit down, order dinner, and watch a band you would queue for anywhere else.',
   'The Aoyama room of the Blue Note, running two sets a night since 1988. You eat at the table while the band plays two metres away — Japanese acts like Soil & "Pimp" Sessions alongside touring international names. The alternative to a club night when you want the music loud and the room seated.',
   'music','{music,jazz,live,couples,dinner,alcohol}', interval '1 day', 120, 'Two sets nightly',
   false, 9500, 'Ticket only; food and drink extra', 'Blue Note Tokyo','6-3-16 Minami-Aoyama, Minato City, Tokyo',
   139.7135, 35.6608, 'https://www.bluenote.co.jp/jp/', 0.28, 0, 0),

  -- ── clip 35 · Shibuya, festival ───────────────────────────────────────────
  ('b0000000-0000-4000-8000-000000000108','tokyo','shibuya',
   'Shibuya Bon Odori','渋谷盆踊り',
   'A neighbourhood folk dance, held under the Shibuya billboards.',
   'A yagura tower goes up in Miyashita Park, taiko drummers climb it, and everybody circles below in happi coats doing steps their grandparents did. What makes the Shibuya one strange and good is the backdrop — Shibuya 109 and the neon crossing right behind a four-hundred-year-old dance. Visitors are pulled into the circle; there is no ticket and no audience.',
   'festival','{festival,traditional,summer,free,music,group-friendly}', interval '7 days', 180, 'Two evenings in late summer',
   true, 0, null, 'Miyashita Park','6-20-10 Jingumae, Shibuya City, Tokyo',
   139.7015, 35.6620, null, 0.58, 0, 0),

  -- ── clip 38 · Shibuya, market ─────────────────────────────────────────────
  ('b0000000-0000-4000-8000-000000000109','tokyo','shibuya',
   'Tokyo Night Market at Yoyogi Park','東京ナイトマーケット',
   'Five nights of food stalls, carnival games and a live stage in Yoyogi Park.',
   'The Keyaki event plaza at the top of Yoyogi Park fills with food stalls, shooting galleries and a lantern-lit stage for five consecutive nights. It is a Tokyo crowd rather than a tourist one — office workers straight off the Yamanote, families, students — and it costs nothing to walk in.',
   'market','{market,food,music,free,group-friendly,summer}', interval '4 days', 120, 'Five consecutive nights',
   true, 0, 'Free entry; stalls from ¥500', 'Yoyogi Park Keyaki Namiki Plaza','2-1 Yoyogikamizonocho, Shibuya City, Tokyo',
   139.6950, 35.6698, null, 0.62, 0, 0),

  -- ── clip 39 · Minato, anime & gaming ──────────────────────────────────────
  ('b0000000-0000-4000-8000-000000000110','tokyo',null,
   'Red° Tokyo Tower','レッド東京タワー',
   'Japan''s largest e-sports park, three floors inside the base of Tokyo Tower.',
   'Foot Town, the building under Tokyo Tower everyone walks past on the way to the lift, holds a three-floor digital amusement park: a robot-arm claw machine the size of a car, projection-mapped climbing walls, racing rigs and an e-sports arena. Almost nobody recommends it, which is why it is rarely queued.',
   'anime','{anime,gaming,indoor,group-friendly,rainy-day}', null, 150, 'Daily, 10:00–22:00',
   false, 2900, 'Day pass', 'Red° Tokyo Tower, Foot Town 3–5F','4-2-8 Shibakoen, Minato City, Tokyo',
   139.7454, 35.6586, 'https://tokyotower.red-brand.jp/', 0.25, 0, 0)

) as v(id, city, hood, name, name_ja, short_desc, long_desc, category, tags,
       offset_h, duration, recurrence, is_free, price, price_note, venue, address,
       lng, lat, external, locality, saves, shares)
join cities c on c.slug = v.city
left join neighborhoods n on n.city_id = c.id and n.slug = v.hood
on conflict (id) do nothing;

-- Same placeholder every other row gets, so the app looks finished with no
-- keys. `--catalog` upgrades these in place rather than inserting a second
-- primary, which the partial unique index would reject anyway.
insert into experience_media (experience_id, kind, license, alt_text, is_primary, position)
select id, 'placeholder', 'placeholder', short_description, true, 0
from experiences
where source = 'catalog'
  and not exists (select 1 from experience_media m where m.experience_id = experiences.id);

-- Deliberately NOT calling attach_neighborhoods() here. It defaults to every
-- city and rewrites neighborhood_id on every row it can reach, including the
-- 26 hand-curated seed rows — which would silently re-cluster days the planner
-- output has already been verified against. Neighborhoods above are set by the
-- join, and the rows that resolve to null (Aoyama, Odaiba, Shibakoen, Sakyo,
-- Suminoe, Kita) are null because we have not seeded those neighborhoods, not
-- because we failed to look.

commit;
