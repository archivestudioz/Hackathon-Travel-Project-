-- Demo seed — Tokyo · Kyoto · Osaka
--
-- Twenty real places and events, weighted toward locally-organised and
-- time-sensitive things rather than the top-ten list. A few well-known
-- attractions are included deliberately: without them the locality score has
-- nothing to score against, and the "hidden gems" rail means nothing if every
-- row is already a hidden gem.
--
-- Event times are relative to now() so the demo never goes stale. Real
-- festivals have real seasons (Tenjin Matsuri is late July) — swap in fixed
-- dates when this stops being a demo.
--
-- MEDIA: every row is seeded as a clearly-labelled placeholder. Nothing here
-- points at a copied video. To use a real post, set kind to 'tiktok' or
-- 'instagram', put the public post URL in source_url, and fill in attribution —
-- the client resolves it through the official oEmbed endpoint at render time.

begin;

-- ------------------------------------------------------------- vocabularies --

-- Countries a traveler can name at signup. `available` is honest about where we
-- actually have inventory, so onboarding can ask the broad question ("where do
-- you like to travel?") without pretending to have content everywhere.
insert into countries (code, name_en, emoji, available, sort) values
  ('JP','Japan',         '🇯🇵', true,  1),
  ('KR','South Korea',   '🇰🇷', false, 2),
  ('TW','Taiwan',        '🇹🇼', false, 3),
  ('TH','Thailand',      '🇹🇭', false, 4),
  ('VN','Vietnam',       '🇻🇳', false, 5),
  ('IT','Italy',         '🇮🇹', false, 6),
  ('ES','Spain',         '🇪🇸', false, 7),
  ('PT','Portugal',      '🇵🇹', false, 8),
  ('MX','Mexico',        '🇲🇽', false, 9),
  ('US','United States', '🇺🇸', false, 10);

-- Why someone travels — a different axis from what they like. Two people who
-- both pick "food" want very different trips depending on whether they answered
-- "big night out" or "slow reset".
insert into travel_reasons (slug, label_en, emoji, sort) values
  ('vacation',   'Just a holiday',        '🌴', 1),
  ('food',       'Eating my way around', '🍜', 2),
  ('culture',    'Culture and history',  '⛩', 3),
  ('adventure',  'Adventure and hiking', '🥾', 4),
  ('nightlife',  'Going out',            '🌃', 5),
  ('reset',      'Rest and reset',       '♨️', 6),
  ('photography','Photography',          '📷', 7),
  ('anime',      'Anime and gaming',     '🎮', 8),
  ('business',   'Work trip',            '💼', 9),
  ('friends',    'Visiting people',      '👋', 10);

-- ------------------------------------------------------------- interests --

insert into interests (slug, label_en, emoji, sort) values
  ('food',        'Restaurants & food',  '🍜', 1),
  ('nightlife',   'Bars & nightclubs',   '🌃', 2),
  ('nature',      'Nature & parks',      '🌿', 3),
  ('hiking',      'Hiking & trails',     '🥾', 4),
  ('beach',       'Beaches',             '🏖', 5),
  ('art',         'Art & design',        '🎨', 6),
  ('anime',       'Anime & gaming',      '🎮', 7),
  ('music',       'Live music',          '🎧', 8),
  ('shopping',    'Shopping & vintage',  '🛍', 9),
  ('festival',    'Festivals',           '🎏', 10),
  ('wellness',    'Wellness & onsen',    '♨️', 11),
  ('traditional', 'Traditional culture', '⛩', 12),
  ('market',      'Markets',             '🧺', 13);

-- ---------------------------------------------------------------- cities --

-- Bounding boxes are what scripts/ingest_places.py hands to Overpass, so they
-- live with the city rather than in a migration that would run before them.
insert into cities (country_code, slug, name_en, name_ja, center,
                    bbox_min_lng, bbox_min_lat, bbox_max_lng, bbox_max_lat) values
  ('JP','tokyo', 'Tokyo', '東京', st_makepoint(139.6503, 35.6762)::geography,
   139.6300, 35.6200, 139.8100, 35.7400),   -- core 23 wards
  ('JP','kyoto', 'Kyoto', '京都', st_makepoint(135.7681, 35.0116)::geography,
   135.6500, 34.9500, 135.8100, 35.0700),   -- Arashiyama through to Fushimi
  ('JP','osaka', 'Osaka', '大阪', st_makepoint(135.5023, 34.6937)::geography,
   135.4700, 34.6300, 135.5400, 34.7300);   -- Namba up to Tenma

insert into neighborhoods (city_id, slug, name_en, name_ja, center, blurb)
select c.id, v.slug, v.name_en, v.name_ja, st_makepoint(v.lng, v.lat)::geography, v.blurb
from cities c, (values
  ('tokyo','shibuya',        'Shibuya',        '渋谷',   139.7016, 35.6580, 'Crossing, record shops, and the city at its loudest.'),
  ('tokyo','shinjuku',       'Shinjuku',       '新宿',   139.7034, 35.6938, 'Golden Gai, department stores, and Omoide Yokocho smoke.'),
  ('tokyo','asakusa',        'Asakusa',        '浅草',   139.7967, 35.7148, 'Senso-ji, artisan streets, and the old low city.'),
  ('tokyo','shimokitazawa',  'Shimokitazawa',  '下北沢', 139.6683, 35.6613, 'Live houses, secondhand racks, tiny theatres.'),
  ('tokyo','koenji',         'Koenji',         '高円寺', 139.6497, 35.7053, 'Punk bars and the densest vintage in Tokyo.'),
  ('tokyo','akihabara',      'Akihabara',      '秋葉原', 139.7745, 35.7022, 'Arcades, parts shops, and six floors of everything.'),
  ('tokyo','nakameguro',     'Nakameguro',     '中目黒', 139.6990, 35.6440, 'Canal-side cafes under the cherry trees.'),
  ('tokyo','yanaka',         'Yanaka',         '谷中',   139.7660, 35.7280, 'Survived the war and the bubble. Cats and senbei.'),
  ('tokyo','toyosu',         'Toyosu',         '豊洲',   139.7967, 35.6550, 'Reclaimed waterfront, the new fish market, digital art.'),
  ('kyoto','gion',           'Gion',           '祇園',   135.7752, 35.0037, 'Wooden machiya, lantern light, and the Kamo river.'),
  ('kyoto','arashiyama',     'Arashiyama',     '嵐山',   135.6668, 35.0094, 'Bamboo, monkeys, and the Hozu river gorge.'),
  ('kyoto','nishiki',        'Nishiki',        '錦',     135.7648, 35.0050, 'Four hundred metres of covered market.'),
  ('kyoto','fushimi',        'Fushimi',        '伏見',   135.7727, 34.9671, 'Sake breweries and ten thousand torii.'),
  ('kyoto','nishijin',       'Nishijin',       '西陣',   135.7420, 35.0300, 'Weaving district, quiet workshops, no crowds.'),
  ('osaka','namba',          'Namba',          '難波',   135.5010, 34.6656, 'Dotonbori neon and the food everyone comes for.'),
  ('osaka','shinsekai',      'Shinsekai',      '新世界', 135.5062, 34.6524, 'Tsutenkaku tower and kushikatsu under it.'),
  ('osaka','tenma',          'Tenma',          '天満',   135.5120, 34.7055, 'The longest shopping arcade in Japan, and standing bars.'),
  ('osaka','amerikamura',    'Amerikamura',    'アメリカ村', 135.4980, 34.6720, 'Street art, skate shops, and Osaka youth culture.'),
  ('osaka','nakazakicho',    'Nakazakicho',    '中崎町', 135.5030, 34.7080, 'Prewar houses turned into cafes and zine shops.')
) as v(city, slug, name_en, name_ja, lng, lat, blurb)
where c.slug = v.city;

-- ----------------------------------------------------------------- hosts --

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
  ('a0000000-0000-4000-8000-000000000020','Amemura Art Walk','community','Street artists running free walking sessions.',                        false, true);

-- ----------------------------------------------------------- experiences --

insert into experiences (
  id, city_id, neighborhood_id, host_id, name, name_ja, short_description, description,
  category, tags, starts_at, duration_min, recurrence_note,
  is_free, price_yen, price_note, venue_name, address, point,
  booking_url, external_url, locality, save_count, share_count)
select
  v.id::uuid, c.id, n.id, v.host::uuid, v.name, v.name_ja, v.short_desc, v.long_desc,
  v.category, v.tags::text[],
  case when v.offset_h is null then null else now() + v.offset_h end,
  v.duration, v.recurrence,
  v.is_free, v.price, v.price_note, v.venue, v.address,
  st_makepoint(v.lng, v.lat)::geography,
  v.booking, v.external, v.locality, v.saves, v.shares
from (values
  -- ── Tokyo ──────────────────────────────────────────────────────────────
  ('b0000000-0000-4000-8000-000000000001','tokyo','asakusa','a0000000-0000-4000-8000-000000000001',
   'Tsukiji Outer Market Morning Walk','築地場外市場 朝さんぽ',
   'Eat breakfast standing up with the people who sell the fish.',
   'The inner market moved to Toyosu, but the outer market never left. Start at 7am with tamagoyaki straight off the griddle, then work through uni, tuna cheek, and a bowl of miso from a stall with no English menu. Your host''s family has sold fish here for three generations, which is the only reason some of these stops will serve you at all.',
   'food','{food,traditional,solo-friendly}', interval '18 hours', 150, 'Daily except Sunday',
   false, 3800, 'Includes six tastings', 'Tsukiji Outer Market','4-16-2 Tsukiji, Chuo City, Tokyo',
   139.7707, 35.6654, null, 'https://www.tsukiji.or.jp/english/', 0.72, 214, 38),

  ('b0000000-0000-4000-8000-000000000002','tokyo','koenji',null,
   'Koenji Vintage Crawl','高円寺 古着めぐり',
   'Forty secondhand shops in six streets. No map, no plan.',
   'Koenji has the densest concentration of vintage clothing in Tokyo and almost no tourists in it. The monthly crawl is run by the shop owners themselves — it costs nothing, it starts when enough people show up outside the north exit, and it ends in whichever bar is still open.',
   'shopping','{shopping,art,solo-friendly,group-friendly}', interval '3 days', 180, 'First Saturday monthly',
   true, 0, null, 'Koenji Station North Exit','Koenji-kita, Suginami City, Tokyo',
   139.6497, 35.7053, null, null, 0.88, 96, 21),

  ('b0000000-0000-4000-8000-000000000003','tokyo','shimokitazawa','a0000000-0000-4000-8000-000000000003',
   'Shelter Shimokitazawa: Friday Live','SHELTER 下北沢',
   'Basement live house, four bands, capacity 250.',
   'Shelter has been putting on shows since 1991 and it is where a lot of bands you have heard of played their tenth gig. Standing room, drink ticket included, doors at 18:30. The lineup rotates weekly and is almost entirely Japanese indie.',
   'music','{music,nightlife,solo-friendly}', interval '2 days', 210, 'Most Fridays',
   false, 3300, 'Plus one drink ticket, 600 yen', 'Shimokitazawa SHELTER','2-6-10 Kitazawa, Setagaya City, Tokyo',
   139.6670, 35.6620, null, 'https://www.loft-prj.co.jp/SHELTER/', 0.79, 142, 27),

  ('b0000000-0000-4000-8000-000000000004','tokyo','yanaka','a0000000-0000-4000-8000-000000000004',
   'Yanaka Evening Stroll & Senbei','谷中 夕方さんぽ',
   'The Tokyo that survived the firebombing, walked at dusk.',
   'Yanaka is one of the few districts to come through both the 1923 earthquake and the 1945 firebombing largely intact. A retired schoolteacher walks you through the cemetery at golden hour, past the cats, and ends at a senbei shop that has been grilling rice crackers by hand since 1913.',
   'traditional','{traditional,food,nature,solo-friendly,family-friendly}', interval '30 hours', 120, 'Tuesdays and Thursdays',
   false, 2000, null, 'Yanaka Ginza','3-13-1 Yanaka, Taito City, Tokyo',
   139.7660, 35.7280, null, null, 0.91, 73, 12),

  ('b0000000-0000-4000-8000-000000000005','tokyo','akihabara','a0000000-0000-4000-8000-000000000005',
   'Akihabara Retro Arcade Deep Dive','秋葉原 レトロゲーム探訪',
   'Four floors of cabinets from 1978 onward, with someone who can explain them.',
   'Not the tourist arcade on the main street. This runs through three buildings of working vintage cabinets, a parts shop where people still repair PCBs, and a doujin game floor. Coins included. Your host restores cabinets for a living.',
   'anime','{anime,shopping,solo-friendly,group-friendly}', interval '4 days', 150, 'Weekends',
   false, 4500, 'Includes 1000 yen in tokens', 'Super Potato Retro-kan','1-11-2 Sotokanda, Chiyoda City, Tokyo',
   139.7712, 35.7000, null, null, 0.68, 187, 44),

  ('b0000000-0000-4000-8000-000000000006','tokyo','nakameguro','a0000000-0000-4000-8000-000000000006',
   'Meguro River Sakura Night Walk','目黒川 夜桜',
   'Eight hundred cherry trees over a canal, lit by volunteers.',
   'For two weeks a year the Meguro river becomes the best walk in Tokyo. The lanterns are hung by a neighbourhood volunteer association, not the city. Come on a weekday — the weekend is genuinely impassable. Free, and the riverside stands sell sparkling wine in plastic cups.',
   'nature','{nature,festival,romantic,free}', interval '5 days', 90, 'Late March to early April',
   true, 0, null, 'Nakameguro Riverside','Nakameguro, Meguro City, Tokyo',
   139.6990, 35.6440, null, null, 0.62, 341, 86),

  ('b0000000-0000-4000-8000-000000000007','tokyo','shinjuku','a0000000-0000-4000-8000-000000000007',
   'Golden Gai Izakaya Hop','ゴールデン街 はしご酒',
   'Six seats a bar, six bars a night, in 200 wooden buildings.',
   'Golden Gai is 280 tiny bars in six alleys, most seating fewer than eight people, many with a cover charge and a regulars-only reputation that a local host dissolves instantly. Three bars, three drinks, and an explanation of which doors you can open alone next time.',
   'nightlife','{nightlife,food,group-friendly}', interval '1 day', 180, 'Nightly except Sunday',
   false, 7000, 'Includes three drinks and cover charges', 'Shinjuku Golden Gai','1-1-6 Kabukicho, Shinjuku City, Tokyo',
   139.7043, 35.6938, null, null, 0.74, 268, 71),

  ('b0000000-0000-4000-8000-000000000008','tokyo','asakusa','a0000000-0000-4000-8000-000000000008',
   'Morning Zazen at a Neighbourhood Temple','朝坐禅',
   'Forty minutes of seated meditation. No English, no ceremony, no photos.',
   'Not a tourist zazen experience. This is the regular twice-weekly sitting that the neighbourhood attends, at 6:30am, and visitors are welcome to join quietly at the back. Instruction is minimal and in Japanese, but the posture is demonstrated. Tea afterwards.',
   'wellness','{wellness,traditional,solo-friendly}', interval '20 hours', 60, 'Wednesdays and Saturdays, 06:30',
   false, 1000, 'Donation, tea included', 'Chokoku-ji','2-1-15 Nishiasakusa, Taito City, Tokyo',
   139.7920, 35.7160, null, null, 0.94, 41, 6),

  ('b0000000-0000-4000-8000-000000000009','tokyo','toyosu','a0000000-0000-4000-8000-000000000009',
   'teamLab Planets TOKYO','チームラボプラネッツ',
   'Barefoot through knee-deep water and a room of mirrors.',
   'Four large-scale installations you walk through barefoot, including one where you wade through water with projected koi. Book ahead; it sells out. Wear shorts or clothes you can roll up.',
   'art','{art,family-friendly,couple}', null, 90, 'Daily 09:00–22:00',
   false, 3800, 'Timed entry, book ahead', 'teamLab Planets TOKYO','6-1-16 Toyosu, Koto City, Tokyo',
   139.7900, 35.6490, 'https://www.teamlab.art/e/planets/', 'https://www.teamlab.art/e/planets/', 0.18, 892, 240),

  ('b0000000-0000-4000-8000-000000000010','tokyo','shibuya','a0000000-0000-4000-8000-000000000010',
   'Shibuya Record Store Crawl','渋谷 レコード店めぐり',
   'Seven shops, from 40-yen bins to sealed city pop.',
   'Shibuya still has one of the densest record scenes on earth. This is a self-paced route between seven shops with a hand-drawn map from Face Records — jazz kissa reissues, 1980s city pop, and a basement that only sells 7-inches. Free to walk; bring cash.',
   'music','{music,shopping,solo-friendly}', null, 180, 'Any day, shops open 12:00–20:00',
   true, 0, 'Free route; records are not', 'Face Records Shibuya','3-15-1 Jinnan, Shibuya City, Tokyo',
   139.6980, 35.6640, null, null, 0.77, 118, 19),

  -- ── Kyoto ──────────────────────────────────────────────────────────────
  ('b0000000-0000-4000-8000-000000000011','kyoto','nishiki','a0000000-0000-4000-8000-000000000011',
   'Nishiki Market Breakfast Tasting','錦市場 朝ごはん',
   'Eight stalls before the market fills up, starting at 9am.',
   'Nishiki is four hundred metres of covered market and by noon you cannot move. At nine it belongs to the stallholders. Tastings include tamago, pickled everything, fresh yuba, and a knife shop demonstration that is not a sales pitch.',
   'food','{food,traditional,market,solo-friendly,family-friendly}', interval '15 hours', 120, 'Daily except Wednesday',
   false, 3500, 'Eight tastings included', 'Nishiki Market','Nakagyo Ward, Kyoto',
   135.7648, 35.0050, null, 'https://www.kyoto-nishiki.or.jp/', 0.66, 203, 47),

  ('b0000000-0000-4000-8000-000000000012','kyoto','arashiyama','a0000000-0000-4000-8000-000000000012',
   'Arashiyama Bamboo Grove at Dawn','嵐山 竹林の朝',
   'The famous grove, at 6am, before the buses.',
   'The bamboo grove is genuinely extraordinary and genuinely ruined by 9am. A local photographer meets you at 5:45, walks you through while it is still empty, and continues to the Hozu riverbank and a temple garden most day-trippers never reach. Bring a jacket.',
   'nature','{nature,hiking,traditional,romantic,solo-friendly}', interval '26 hours', 150, 'Daily, weather permitting',
   false, 2500, null, 'Arashiyama Bamboo Grove','Ukyo Ward, Kyoto',
   135.6668, 35.0094, null, null, 0.45, 456, 132),

  ('b0000000-0000-4000-8000-000000000013','kyoto','nishijin','a0000000-0000-4000-8000-000000000013',
   'Kyo-Yuzen Silk Dyeing Workshop','京友禅 染め体験',
   'Hand-dye a silk panel in a fifth-generation workshop.',
   'Nishijin is the weaving district and most visitors never go. This family has dyed yuzen silk for five generations. You dye a small panel yourself with their brushes and pigments, take it home, and watch the master finish a commissioned kimono length in the next room.',
   'traditional','{traditional,art,family-friendly,couple}', interval '2 days', 120, 'Mon/Wed/Fri, book ahead',
   false, 5500, 'Materials included, take your panel home', 'Nishijin Yuzen Kobo','Kamigyo Ward, Kyoto',
   135.7420, 35.0300, null, null, 0.89, 64, 11),

  ('b0000000-0000-4000-8000-000000000014','kyoto','gion','a0000000-0000-4000-8000-000000000014',
   'Machiya Counter Kaiseki','町家 割烹',
   'Eight seats, one counter, whatever came in that morning.',
   'A restored wooden townhouse in Gion with a single eight-seat counter. No fixed menu — the chef buys at Nishiki that morning and tells you what you are eating as he plates it. Reservation only, and they do take walk-in cancellations if you ask in person.',
   'food','{food,traditional,romantic,couple}', interval '31 hours', 150, 'Tuesday to Saturday, 18:00 and 20:30',
   false, 14000, 'Sake pairing 4500 extra', 'Machiya Kappo Sen','Higashiyama Ward, Kyoto',
   135.7752, 35.0037, null, null, 0.83, 89, 16),

  ('b0000000-0000-4000-8000-000000000015','kyoto','fushimi','a0000000-0000-4000-8000-000000000015',
   'Fushimi Sake Brewery Tasting','伏見 酒蔵めぐり',
   'Soft water, eighteen breweries, and the ones that still open their doors.',
   'Fushimi''s water is softer than Nada''s, which is why the sake is rounder. Three working breweries, a tasting flight at each, and a walk along the Horikawa canal between them. Most tourists in Fushimi only see the torii gates two kilometres north.',
   -- 'alcohol' is load-bearing, not descriptive: is_adults_only() reads it, and
   -- without it a sake tasting reaches an under_18 feed because its category is
   -- 'food'. Any experience that serves drink needs this tag.
   'food','{food,traditional,alcohol,group-friendly}', interval '50 hours', 180, 'Daily except Monday',
   false, 2800, 'Nine tastings', 'Fushimi Sake District','Fushimi Ward, Kyoto',
   135.7620, 34.9330, null, null, 0.81, 127, 24),

  -- ── Osaka ──────────────────────────────────────────────────────────────
  ('b0000000-0000-4000-8000-000000000016','osaka','tenma','a0000000-0000-4000-8000-000000000016',
   'Tenma Standing Bar Crawl','天満 立ち飲みはしご',
   'Four tachinomi bars. Nobody sits down. Everything is under 500 yen.',
   'Tenma has the longest shopping arcade in Japan and underneath it the best standing-bar density in Osaka. Four bars, a dish and a drink at each, all of it cheap and none of it aimed at visitors. Your host is a former salaryman who drank here for twenty years before guiding.',
   'nightlife','{nightlife,food,solo-friendly,group-friendly}', interval '8 hours', 180, 'Thursday to Sunday',
   false, 5000, 'Four drinks and four dishes', 'Tenjinbashisuji Arcade','Kita Ward, Osaka',
   135.5120, 34.7055, null, null, 0.86, 176, 39),

  ('b0000000-0000-4000-8000-000000000017','osaka','shinsekai','a0000000-0000-4000-8000-000000000017',
   'Shinsekai Kushikatsu, No Double Dipping','新世界 串カツ',
   'Deep-fried everything under a 1912 tower, with one unbreakable rule.',
   'Shinsekai was built in 1912 to look like Paris and Coney Island at once, then forgotten for fifty years. Kushikatsu is skewered, battered, deep-fried, and dipped once in communal sauce — dip twice and you will be told off. Run by the shopkeepers'' association, so you eat at four different counters.',
   'food','{food,nightlife,group-friendly,family-friendly}', interval '11 hours', 120, 'Daily',
   false, 3200, 'Twelve skewers across four shops', 'Shinsekai','Naniwa Ward, Osaka',
   135.5062, 34.6524, null, null, 0.64, 231, 58),

  ('b0000000-0000-4000-8000-000000000018','osaka','nakazakicho','a0000000-0000-4000-8000-000000000018',
   'Nakazakicho Cafe & Zine Walk','中崎町 カフェとzine',
   'Prewar houses turned into cafes, one street from a skyscraper district.',
   'Nakazakicho survived the war and then got left alone. The wooden houses are now cafes, secondhand bookshops, and zine publishers, and it is a ten-minute walk from Umeda station where nobody goes. Self-guided route with a printed zine map made by the cafe owners.',
   'art','{art,shopping,food,solo-friendly}', null, 150, 'Any day; most cafes closed Tuesday',
   true, 0, 'Route free; zine map 300 yen at any participating cafe', 'Nakazakicho','Kita Ward, Osaka',
   135.5030, 34.7080, null, null, 0.93, 58, 9),

  ('b0000000-0000-4000-8000-000000000019','osaka','tenma','a0000000-0000-4000-8000-000000000019',
   'Tenjin Matsuri River Procession','天神祭 船渡御',
   'A thousand-year-old festival, a hundred boats, and fireworks over the Okawa.',
   'One of Japan''s three great festivals, held by Osaka Tenmangu since the tenth century. Portable shrines are carried to the river and loaded onto boats, which process upstream by torchlight while fireworks go up over the water. Free to watch from the banks; arrive by 17:00 for anywhere near the front.',
   'festival','{festival,traditional,nature,family-friendly,group-friendly}', interval '6 days', 300, 'July 24–25 annually',
   true, 0, 'Free from the riverbank; paid grandstand seats exist', 'Okawa River','Kita Ward, Osaka',
   135.5140, 34.6960, null, 'https://osakatemmangu.or.jp/', 0.55, 512, 168),

  ('b0000000-0000-4000-8000-000000000020','osaka','amerikamura','a0000000-0000-4000-8000-000000000020',
   'Amemura Street Art Walk','アメ村 ストリートアート',
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

-- ----------------------------------------------------------------- media --

-- Placeholders, deliberately. The app must look finished with zero API keys and
-- without a single copied file. alt_text describes the shot so the UI can
-- render something meaningful rather than a grey box.
insert into experience_media (experience_id, kind, license, alt_text, is_primary, position)
select id, 'placeholder', 'placeholder',
       short_description, true, 0
from experiences;

commit;
