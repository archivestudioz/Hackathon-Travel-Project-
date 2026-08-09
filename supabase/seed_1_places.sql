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
  ('tokyo','nakameguro',     'Nakameguro',     null, 139.6990, 35.6440, 'Canal-side coffee shops under the cherry trees.'),
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
  ('osaka','nakazakicho',    'Nakazakicho',    null, 135.5030, 34.7080, 'Prewar houses turned into coffee shops and zine shops.')
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
  ('a0000000-0000-4000-8000-000000000018','Nakazaki Zine Club','community','Coffee owners and small publishers.',                                  false, true),
  ('a0000000-0000-4000-8000-000000000019','Osaka Tenmangu Shrine','institution','Host of Tenjin Matsuri since 951.',                             true,  true),
  ('a0000000-0000-4000-8000-000000000020','Amemura Art Walk','community','Street artists running free walking sessions.',                        false, true),
  ('a0000000-0000-4000-8000-000000000021','Daikoku Regulars','community','No organisers, no schedule. People just turn up.',                     false, true),
  ('a0000000-0000-4000-8000-000000000022','Morning Cruise Tokyo','community','Monthly Cars & Coffee at Daikanyama T-Site since 2011.',           true,  true),
  ('a0000000-0000-4000-8000-000000000023','Super Autobacs','local_business','Parts megastore and demo-car showroom.',                            true,  false),
  ('a0000000-0000-4000-8000-000000000024','Nissan Crossing','institution','Nissan brand showroom on the Ginza crossing.',                        true,  false),
  ('a0000000-0000-4000-8000-000000000025','Honda Welcome Plaza','institution','Honda showroom and F1 heritage display in Aoyama.',               true,  false);
