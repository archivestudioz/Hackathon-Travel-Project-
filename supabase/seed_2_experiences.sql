insert into experiences (
  id, city_id, neighborhood_id, host_id, name, name_ja, short_description, description,
  category, tags, starts_at, duration_min, recurrence_note,
  is_free, price_yen, price_note, venue_name, address, point,
  booking_url, external_url, locality, save_count, share_count)
select
  v.id::uuid, c.id, n.id, v.host::uuid, v.name, v.name_ja, v.short_desc, v.long_desc,
  v.category, v.tags::text[],
  case when v.offset_h is null then null
       else date_trunc('day', now() + v.offset_h)
            + preferred_slot(v.category, v.tags::text[]) end,
  v.duration, v.recurrence,
  v.is_free, v.price, v.price_note, v.venue, v.address,
  st_makepoint(v.lng, v.lat)::geography,
  v.booking, v.external, v.locality, v.saves, v.shares
from (values
  ('b0000000-0000-4000-8000-000000000001','tokyo','asakusa','a0000000-0000-4000-8000-000000000001',
   'Tsukiji Outer Market Morning Walk',' ',
   'Eat breakfast standing up with the people who sell the fish.',
   'The inner market moved to Toyosu, but the outer market never left. Start at 7am with tamagoyaki straight off the griddle, then work through uni, tuna cheek, and a bowl of miso from a stall with no English menu. Your host''s family has sold fish here for three generations, which is the only reason some of these stops will serve you at all.',
   'food','{food,traditional,solo-friendly}', interval '18 hours', 150, 'Daily except Sunday',
   false, 3800, 'Includes six tastings', 'Tsukiji Outer Market','4-16-2 Tsukiji, Chuo City, Tokyo',
   139.7707, 35.6654, null, 'https://www.tsukiji.or.jp/english/', 0.72, 214, 38),

  ('b0000000-0000-4000-8000-000000000002','tokyo','koenji',null,
   'Koenji Vintage Crawl',' ',
   'Forty secondhand shops in six streets. No map, no plan.',
   'Koenji has the densest concentration of vintage clothing in Tokyo and almost no tourists in it. The monthly crawl is run by the shop owners themselves  it costs nothing, it starts when enough people show up outside the north exit, and it ends in whichever bar is still open.',
   'shopping','{shopping,art,solo-friendly,group-friendly}', interval '3 days', 180, 'First Saturday monthly',
   true, 0, null, 'Koenji Station North Exit','Koenji-kita, Suginami City, Tokyo',
   139.6497, 35.7053, null, null, 0.88, 96, 21),

  ('b0000000-0000-4000-8000-000000000003','tokyo','shimokitazawa','a0000000-0000-4000-8000-000000000003',
   'Shelter Shimokitazawa: Friday Live','SHELTER ',
   'Basement live house, four bands, capacity 250.',
   'Shelter has been putting on shows since 1991 and it is where a lot of bands you have heard of played their tenth gig. Standing room, drink ticket included, doors at 18:30. The lineup rotates weekly and is almost entirely Japanese indie.',
   'music','{music,nightlife,solo-friendly}', interval '2 days', 210, 'Most Fridays',
   false, 3300, 'Plus one drink ticket, 600 yen', 'Shimokitazawa SHELTER','2-6-10 Kitazawa, Setagaya City, Tokyo',
   139.6670, 35.6620, null, 'https://www.loft-prj.co.jp/SHELTER/', 0.79, 142, 27),

  ('b0000000-0000-4000-8000-000000000004','tokyo','yanaka','a0000000-0000-4000-8000-000000000004',
   'Yanaka Evening Stroll & Senbei',' ',
   'The Tokyo that survived the firebombing, walked at dusk.',
   'Yanaka is one of the few districts to come through both the 1923 earthquake and the 1945 firebombing largely intact. A retired schoolteacher walks you through the cemetery at golden hour, past the cats, and ends at a senbei shop that has been grilling rice crackers by hand since 1913.',
   'traditional','{traditional,food,nature,solo-friendly,family-friendly}', interval '30 hours', 120, 'Tuesdays and Thursdays',
   false, 2000, null, 'Yanaka Ginza','3-13-1 Yanaka, Taito City, Tokyo',
   139.7660, 35.7280, null, null, 0.91, 73, 12),

  ('b0000000-0000-4000-8000-000000000005','tokyo','akihabara','a0000000-0000-4000-8000-000000000005',
   'Akihabara Retro Arcade Deep Dive',' ',
   'Four floors of cabinets from 1978 onward, with someone who can explain them.',
   'Not the tourist arcade on the main street. This runs through three buildings of working vintage cabinets, a parts shop where people still repair PCBs, and a doujin game floor. Coins included. Your host restores cabinets for a living.',
   'anime','{anime,shopping,solo-friendly,group-friendly}', interval '4 days', 150, 'Weekends',
   false, 4500, 'Includes 1000 yen in tokens', 'Super Potato Retro-kan','1-11-2 Sotokanda, Chiyoda City, Tokyo',
   139.7712, 35.7000, null, null, 0.68, 187, 44),

  ('b0000000-0000-4000-8000-000000000006','tokyo','nakameguro','a0000000-0000-4000-8000-000000000006',
   'Meguro River Sakura Night Walk',' ',
   'Eight hundred cherry trees over a canal, lit by volunteers.',
   'For two weeks a year the Meguro river becomes the best walk in Tokyo. The lanterns are hung by a neighbourhood volunteer association, not the city. Come on a weekday  the weekend is genuinely impassable. Free, and the riverside stands sell sparkling wine in plastic cups.',
   'nature','{nature,festival,romantic,late-night,free}', interval '5 days', 90, 'Late March to early April',
   true, 0, null, 'Nakameguro Riverside','Nakameguro, Meguro City, Tokyo',
   139.6990, 35.6440, null, null, 0.62, 341, 86),

  ('b0000000-0000-4000-8000-000000000007','tokyo','shinjuku','a0000000-0000-4000-8000-000000000007',
   'Golden Gai Izakaya Hop',' ',
   'Six seats a bar, six bars a night, in 200 wooden buildings.',
   'Golden Gai is 280 tiny bars in six alleys, most seating fewer than eight people, many with a cover charge and a regulars-only reputation that a local host dissolves instantly. Three bars, three drinks, and an explanation of which doors you can open alone next time.',
   'nightlife','{nightlife,food,group-friendly}', interval '1 day', 180, 'Nightly except Sunday',
   false, 7000, 'Includes three drinks and cover charges', 'Shinjuku Golden Gai','1-1-6 Kabukicho, Shinjuku City, Tokyo',
   139.7043, 35.6938, null, null, 0.74, 268, 71),

  ('b0000000-0000-4000-8000-000000000008','tokyo','asakusa','a0000000-0000-4000-8000-000000000008',
   'Morning Zazen at a Neighbourhood Temple',null,
   'Forty minutes of seated meditation. No English, no ceremony, no photos.',
   'Not a tourist zazen experience. This is the regular twice-weekly sitting that the neighbourhood attends, at 6:30am, and visitors are welcome to join quietly at the back. Instruction is minimal and in Japanese, but the posture is demonstrated. Tea afterwards.',
   'wellness','{wellness,traditional,solo-friendly}', interval '20 hours', 60, 'Wednesdays and Saturdays, 06:30',
   false, 1000, 'Donation, tea included', 'Chokoku-ji','2-1-15 Nishiasakusa, Taito City, Tokyo',
   139.7920, 35.7160, null, null, 0.94, 41, 6),

  ('b0000000-0000-4000-8000-000000000009','tokyo','toyosu','a0000000-0000-4000-8000-000000000009',
   'teamLab Planets TOKYO',null,
   'Barefoot through knee-deep water and a room of mirrors.',
   'Four large-scale installations you walk through barefoot, including one where you wade through water with projected koi. Book ahead; it sells out. Wear shorts or clothes you can roll up.',
   'art','{art,family-friendly,couple}', null, 90, 'Daily 09:0022:00',
   false, 3800, 'Timed entry, book ahead', 'teamLab Planets TOKYO','6-1-16 Toyosu, Koto City, Tokyo',
   139.7900, 35.6490, 'https://www.teamlab.art/e/planets/', 'https://www.teamlab.art/e/planets/', 0.18, 892, 240),

  ('b0000000-0000-4000-8000-000000000010','tokyo','shibuya','a0000000-0000-4000-8000-000000000010',
   'Shibuya Record Store Crawl',' ',
   'Seven shops, from 40-yen bins to sealed city pop.',
   'Shibuya still has one of the densest record scenes on earth. This is a self-paced route between seven shops with a hand-drawn map from Face Records  jazz kissa reissues, 1980s city pop, and a basement that only sells 7-inches. Free to walk; bring cash.',
   'music','{music,shopping,solo-friendly}', null, 180, 'Any day, shops open 12:0020:00',
   true, 0, 'Free route; records are not', 'Face Records Shibuya','3-15-1 Jinnan, Shibuya City, Tokyo',
   139.6980, 35.6640, null, null, 0.77, 118, 19),

  ('b0000000-0000-4000-8000-000000000011','kyoto','nishiki','a0000000-0000-4000-8000-000000000011',
   'Nishiki Market Breakfast Tasting',' ',
   'Eight stalls before the market fills up, starting at 9am.',
   'Nishiki is four hundred metres of covered market and by noon you cannot move. At nine it belongs to the stallholders. Tastings include tamago, pickled everything, fresh yuba, and a knife shop demonstration that is not a sales pitch.',
   'food','{food,traditional,market,solo-friendly,family-friendly}', interval '15 hours', 120, 'Daily except Wednesday',
   false, 3500, 'Eight tastings included', 'Nishiki Market','Nakagyo Ward, Kyoto',
   135.7648, 35.0050, null, 'https://www.kyoto-nishiki.or.jp/', 0.66, 203, 47),

  ('b0000000-0000-4000-8000-000000000012','kyoto','arashiyama','a0000000-0000-4000-8000-000000000012',
   'Arashiyama Bamboo Grove at Dawn',' ',
   'The famous grove, at 6am, before the buses.',
   'The bamboo grove is genuinely extraordinary and genuinely ruined by 9am. A local photographer meets you at 5:45, walks you through while it is still empty, and continues to the Hozu riverbank and a temple garden most day-trippers never reach. Bring a jacket.',
   'nature','{nature,hiking,traditional,romantic,solo-friendly}', interval '26 hours', 150, 'Daily, weather permitting',
   false, 2500, null, 'Arashiyama Bamboo Grove','Ukyo Ward, Kyoto',
   135.6668, 35.0094, null, null, 0.45, 456, 132),

  ('b0000000-0000-4000-8000-000000000013','kyoto','nishijin','a0000000-0000-4000-8000-000000000013',
   'Kyo-Yuzen Silk Dyeing Workshop',' ',
   'Hand-dye a silk panel in a fifth-generation workshop.',
   'Nishijin is the weaving district and most visitors never go. This family has dyed yuzen silk for five generations. You dye a small panel yourself with their brushes and pigments, take it home, and watch the master finish a commissioned kimono length in the next room.',
   'traditional','{traditional,art,family-friendly,couple}', interval '2 days', 120, 'Mon/Wed/Fri, book ahead',
   false, 5500, 'Materials included, take your panel home', 'Nishijin Yuzen Kobo','Kamigyo Ward, Kyoto',
   135.7420, 35.0300, null, null, 0.89, 64, 11),

  ('b0000000-0000-4000-8000-000000000014','kyoto','gion','a0000000-0000-4000-8000-000000000014',
   'Machiya Counter Kaiseki',' ',
   'Eight seats, one counter, whatever came in that morning.',
   'A restored wooden townhouse in Gion with a single eight-seat counter. No fixed menu  the chef buys at Nishiki that morning and tells you what you are eating as he plates it. Reservation only, and they do take walk-in cancellations if you ask in person.',
   'food','{food,traditional,romantic,couple}', interval '31 hours', 150, 'Tuesday to Saturday, 18:00 and 20:30',
   false, 14000, 'Sake pairing 4500 extra', 'Machiya Kappo Sen','Higashiyama Ward, Kyoto',
   135.7752, 35.0037, null, null, 0.83, 89, 16),

  ('b0000000-0000-4000-8000-000000000015','kyoto','fushimi','a0000000-0000-4000-8000-000000000015',
   'Fushimi Sake Brewery Tasting',' ',
   'Soft water, eighteen breweries, and the ones that still open their doors.',
   'Fushimi''s water is softer than Nada''s, which is why the sake is rounder. Three working breweries, a tasting flight at each, and a walk along the Horikawa canal between them. Most tourists in Fushimi only see the torii gates two kilometres north.',
   'food','{food,traditional,alcohol,group-friendly}', interval '50 hours', 180, 'Daily except Monday',
   false, 2800, 'Nine tastings', 'Fushimi Sake District','Fushimi Ward, Kyoto',
   135.7620, 34.9330, null, null, 0.81, 127, 24),

  ('b0000000-0000-4000-8000-000000000016','osaka','tenma','a0000000-0000-4000-8000-000000000016',
   'Tenma Standing Bar Crawl',' ',
   'Four tachinomi bars. Nobody sits down. Everything is under 500 yen.',
   'Tenma has the longest shopping arcade in Japan and underneath it the best standing-bar density in Osaka. Four bars, a dish and a drink at each, all of it cheap and none of it aimed at visitors. Your host is a former salaryman who drank here for twenty years before guiding.',
   'nightlife','{nightlife,food,solo-friendly,group-friendly}', interval '8 hours', 180, 'Thursday to Sunday',
   false, 5000, 'Four drinks and four dishes', 'Tenjinbashisuji Arcade','Kita Ward, Osaka',
   135.5120, 34.7055, null, null, 0.86, 176, 39),

  ('b0000000-0000-4000-8000-000000000017','osaka','shinsekai','a0000000-0000-4000-8000-000000000017',
   'Shinsekai Kushikatsu, No Double Dipping',' ',
   'Deep-fried everything under a 1912 tower, with one unbreakable rule.',
   'Shinsekai was built in 1912 to look like Paris and Coney Island at once, then forgotten for fifty years. Kushikatsu is skewered, battered, deep-fried, and dipped once in communal sauce  dip twice and you will be told off. Run by the shopkeepers'' association, so you eat at four different counters.',
   'food','{food,nightlife,group-friendly,family-friendly}', interval '11 hours', 120, 'Daily',
   false, 3200, 'Twelve skewers across four shops', 'Shinsekai','Naniwa Ward, Osaka',
   135.5062, 34.6524, null, null, 0.64, 231, 58),

  ('b0000000-0000-4000-8000-000000000018','osaka','nakazakicho','a0000000-0000-4000-8000-000000000018',
   'Nakazakicho Coffee & Zine Walk',' zine',
   'Prewar houses turned into coffee shops, one street from a skyscraper district.',
   'Nakazakicho survived the war and then got left alone. The wooden houses are now coffee shops, secondhand bookshops, and zine publishers, and it is a ten-minute walk from Umeda station where nobody goes. Self-guided route with a printed zine map made by the coffee shop owners.',
   'art','{art,shopping,food,solo-friendly}', null, 150, 'Any day; most coffee shops closed Tuesday',
   true, 0, 'Route free; zine map 300 yen at any participating coffee shop', 'Nakazakicho','Kita Ward, Osaka',
   135.5030, 34.7080, null, null, 0.93, 58, 9),

  ('b0000000-0000-4000-8000-000000000019','osaka','tenma','a0000000-0000-4000-8000-000000000019',
   'Tenjin Matsuri River Procession',' ',
   'A thousand-year-old festival, a hundred boats, and fireworks over the Okawa.',
   'One of Japan''s three great festivals, held by Osaka Tenmangu since the tenth century. Portable shrines are carried to the river and loaded onto boats, which process upstream by torchlight while fireworks go up over the water. Free to watch from the banks; arrive by 17:00 for anywhere near the front.',
   'festival','{festival,traditional,nature,family-friendly,group-friendly}', interval '6 days', 300, 'July 2425 annually',
   true, 0, 'Free from the riverbank; paid grandstand seats exist', 'Okawa River','Kita Ward, Osaka',
   135.5140, 34.6960, null, 'https://osakatemmangu.or.jp/', 0.55, 512, 168),

  ('b0000000-0000-4000-8000-000000000020','osaka','amerikamura','a0000000-0000-4000-8000-000000000020',
   'Amemura Street Art Walk',' ',
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

insert into experiences (
  id, city_id, neighborhood_id, host_id, name, name_ja, short_description, description,
  category, tags, starts_at, duration_min, recurrence_note,
  is_free, price_yen, price_note, venue_name, address, point,
  booking_url, external_url, locality, save_count, share_count)
select
  v.id::uuid, c.id, n.id, v.host::uuid, v.name, v.name_ja, v.short_desc, v.long_desc,
  v.category, v.tags::text[],
  case when v.offset_h is null then null
       else date_trunc('day', now() + v.offset_h)
            + preferred_slot(v.category, v.tags::text[]) end,
  v.duration, v.recurrence,
  v.is_free, v.price, v.price_note, v.venue, v.address,
  st_makepoint(v.lng, v.lat)::geography,
  v.booking, v.external, v.locality, v.saves, v.shares
from (values
  ('b0000000-0000-4000-8000-000000000021','tokyo',null,'a0000000-0000-4000-8000-000000000021',
   'Daikoku Futo PA Night Meet','PA',
   'The most famous car park on earth, under an expressway loop.',
   'A motorway service area on reclaimed land in Yokohama Bay that became the centre of Japanese car culture by accident. Bosozoku bikes, kaido racers, immaculate kyusha, and someone''s twin-turbo Supra idling next to a hand-built VIP sedan. Nothing is organised and nothing is advertised  it happens on weekend nights when the police are not closing the ramp. Take the Wangan line, not a taxi that will not wait.',
   'cars','{cars,late-night,photography,group-friendly}', interval '22 hours', 180, 'Weekend nights, weather and police permitting',
   true, 0, 'Free. Parking is the whole point.', 'Daikoku Futo Parking Area','Daikoku Futo, Tsurumi Ward, Yokohama (45 min from central Tokyo)',
   139.6873, 35.4553, null, null, 0.94, 388, 121),

  ('b0000000-0000-4000-8000-000000000022','tokyo','toyosu','a0000000-0000-4000-8000-000000000021',
   'Tatsumi PA After Midnight','PA',
   'Smaller, closer, and the Tokyo skyline behind every car.',
   'Tatsumi sits on the Shuto expressway with the bay and the skyline as a backdrop, which is why it out-photographs Daikoku even though it is a fraction of the size. Quieter crowd, more regulars, more actual conversation. Peaks somewhere after 1am.',
   'cars','{cars,late-night,photography,viewpoint}', interval '26 hours', 120, 'Most nights after midnight',
   true, 0, null, 'Tatsumi Parking Area','Tatsumi, Koto City, Tokyo',
   139.8092, 35.6417, null, null, 0.91, 174, 46),

  ('b0000000-0000-4000-8000-000000000023','tokyo','nakameguro','a0000000-0000-4000-8000-000000000022',
   'Daikanyama Morning Cruise',null,
   'Cars and coffee at 7am, then everyone drives off by nine.',
   'A monthly meet in the T-Site bookshop car park that has run since 2011, with a different theme each time  air-cooled Porsches one month, 1980s Japanese saloons the next. Genuinely welcoming to people on foot, and the coffee is good. Over by 09:00 because Daikanyama has to open.',
   'cars','{cars,shopping,photography,family-friendly}', interval '54 hours', 120, 'First Sunday monthly, 07:0009:00',
   true, 0, 'Free to attend on foot', 'Daikanyama T-Site','17-5 Sarugakucho, Shibuya City, Tokyo',
   139.7030, 35.6490, null, null, 0.74, 142, 33),

  ('b0000000-0000-4000-8000-000000000024','tokyo','toyosu','a0000000-0000-4000-8000-000000000023',
   'Super Autobacs Tokyo Bay',null,
   'Four floors of parts, and demo cars nobody will stop you photographing.',
   'A car parts megastore the size of a supermarket, with a demo floor of fully built cars, a wheel wall that goes to the ceiling, and an aftermarket catalogue that explains more about Japanese car culture than any museum. Staff are used to visitors and several speak English.',
   'cars','{cars,shopping}', null, 90, 'Daily 10:0020:00',
   true, 0, 'Free entry', 'Super Autobacs Tokyo Bay Shinonome','1-2-8 Shinonome, Koto City, Tokyo',
   139.8000, 35.6470, null, null, 0.66, 88, 14),

  ('b0000000-0000-4000-8000-000000000025','tokyo','shinjuku','a0000000-0000-4000-8000-000000000025',
   'Honda Welcome Plaza Aoyama',null,
   'Free F1 cars in a lobby, ten minutes from Omotesando.',
   'The ground floor of Honda headquarters, open to the street, usually with a championship-winning F1 car and a rotating display of ASIMO-era engineering. Takes twenty minutes and costs nothing, which makes it the easiest car stop in central Tokyo.',
   'cars','{cars,culture,family-friendly}', null, 30, 'Daily 10:0018:00',
   true, 0, 'Free', 'Honda Welcome Plaza Aoyama','2-1-1 Minami-Aoyama, Minato City, Tokyo',
   139.7170, 35.6660, null, null, 0.34, 96, 12),

  ('b0000000-0000-4000-8000-000000000026','tokyo',null,'a0000000-0000-4000-8000-000000000024',
   'Nissan Crossing, Ginza',null,
   'Concept cars behind glass on the busiest corner in Ginza.',
   'A three-storey brand showroom on the Ginza 4-chome crossing with a rotating concept or heritage car and a caf upstairs. Squarely a tourist stop rather than a scene one  included here so you can see the difference from Daikoku in one scroll.',
   'cars','{cars,shopping}', null, 40, 'Daily 10:0020:00',
   true, 0, 'Free', 'Nissan Crossing','5-8-1 Ginza, Chuo City, Tokyo',
   139.7650, 35.6720, null, null, 0.22, 211, 28)
) as v(id, city, hood, host, name, name_ja, short_desc, long_desc, category, tags,
       offset_h, duration, recurrence, is_free, price, price_note, venue, address,
       lng, lat, booking, external, locality, saves, shares)
join cities c on c.slug = v.city
left join neighborhoods n on n.city_id = c.id and n.slug = v.hood;

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

  ('b0000000-0000-4000-8000-000000000101','tokyo','shibuya',
   'Shibuya Yokocho Lantern Alley',null,
   'Two hundred metres of red lanterns and regional izakaya, open past 3am.',
   'A covered alley under Miyashita Park where each stall cooks the food of a different Japanese prefecture  Hokkaido crab at one counter, Kyushu motsunabe at the next. Locals rate the atmosphere well above the cooking, which is the honest reason to come: it is loud, cheap to walk through, and one of the few places in Shibuya still serving at 4am.',
   'food','{food,nightlife,late-night,group-friendly,alcohol}', null, 60, 'Open daily until late',
   true, 0, 'Free to walk; stalls from 800', 'Shibuya Yokocho, RAYARD Miyashita Park','1-26-5 Jingumae, Shibuya City, Tokyo',
   139.7020, 35.6613, null, 0.35, 0, 0),

  ('b0000000-0000-4000-8000-000000000102','kyoto',null,
   'Do It Jazz at Club Metro',null,
   'Jazz dance night in a subway-station basement that has run since 1990.',
   'Club Metro occupies the basement of a Keihan station entrance and has been Kyoto''s underground music room for thirty-five years. Do It Jazz is its long-running swing and jazz-dance night: fedoras, partner footwork, and a floor that fills with people who clearly practise. Turn up alone and someone will dance with you.',
   'nightlife','{nightlife,music,dance,late-night,solo-friendly,alcohol}', interval '5 days', 240, 'Monthly  check Club Metro listings',
   false, 2500, 'Door price, one drink included', 'Club Metro','Ebisu Building B1F, Kawabata-Marutamachi, Sakyo Ward, Kyoto',
   135.7736, 35.0181, 'http://www.metro.ne.jp/', 0.91, 0, 0),

  ('b0000000-0000-4000-8000-000000000103','osaka',null,
   'Boat Race Suminoe',null,
   'Motorboat racing, 100 to get in, and nobody in the stands is a tourist.',
   'Kyotei is one of Japan''s four legal public gambling sports and Suminoe is Osaka''s course. Entry is a hundred yen. The crowd is retirees with pencils and marked-up form guides, the boats are terrifyingly fast around the first buoy, and a hundred-yen bet keeps you interested for the whole afternoon. Twenty minutes south of Namba on the Yotsubashi line.',
   'traditional','{gambling,sport,cheap,solo-friendly,local}', interval '2 days', 180, 'Race days  check the calendar',
   false, 100, 'Entry only; bets from 100', 'Boat Race Suminoe','1-1-71 Hokko, Suminoe Ward, Osaka',
   135.4755, 34.6130, 'https://www.boatrace-suminoye.jp/', 0.88, 0, 0),

  ('b0000000-0000-4000-8000-000000000104','tokyo','shinjuku',
   'Warp Shinjuku',null,
   'Four floors, four genres, and it does not card you at the door for being foreign.',
   'A Kabukicho megaclub with a different sound on every floor  hip-hop, EDM, K-pop, and a rotating fourth. The reason it keeps showing up in travellers'' feeds is that it is genuinely foreigner-friendly, which in Shinjuku is not a given. Busiest between 1am and 4am, when the trains have stopped and nobody is leaving.',
   'nightlife','{nightlife,music,late-night,group-friendly,club,alcohol}', interval '3 days', 300, 'Fridays and Saturdays',
   false, 3500, 'Door, includes one drink', 'Warp Shinjuku','1-20-1 Kabukicho, Shinjuku City, Tokyo',
   139.7025, 35.6952, null, 0.52, 0, 0),

  ('b0000000-0000-4000-8000-000000000105','tokyo',null,
   'Odaiba Summer Fireworks',' ',
   'Fireworks over Rainbow Bridge, with Tokyo Tower behind them.',
   'Tokyo Bay fireworks framed by the Rainbow Bridge, watched from the sand at Odaiba Seaside Park. Yakatabune pleasure boats fill the water underneath, which is the expensive way to see it; the free way is to arrive two hours early with a convenience-store dinner and sit on the beach like everyone else.',
   'festival','{festival,summer,free,group-friendly,photography}', interval '6 days', 90, 'Selected summer evenings',
   true, 0, null, 'Odaiba Seaside Park','1-4 Daiba, Minato City, Tokyo',
   139.7740, 35.6300, null, 0.30, 0, 0),

  ('b0000000-0000-4000-8000-000000000106','osaka',null,
   'Umeda Sky Building Heart Locks',null,
   'A rooftop ring 170m up, reached by an escalator through open air.',
   'Two towers joined at the fortieth floor by a doughnut-shaped open-air deck, which you reach on a glass escalator suspended in the gap between them. Couples engrave heart-shaped padlocks and clip them to the railings. It is unambiguously a tourist landmark and it is still one of the best hours in Osaka after dark.',
   'art','{views,architecture,couples,night,photography}', null, 90, 'Daily, 09:3022:30',
   false, 2000, 'Floating Garden Observatory admission', 'Umeda Sky Building, Floating Garden Observatory','1-1-88 Oyodonaka, Kita Ward, Osaka',
   135.4903, 34.7052, 'https://www.skybldg.co.jp/en/', 0.15, 0, 0),

  ('b0000000-0000-4000-8000-000000000107','tokyo',null,
   'Blue Note Tokyo',null,
   'Sit down, order dinner, and watch a band you would queue for anywhere else.',
   'The Aoyama room of the Blue Note, running two sets a night since 1988. You eat at the table while the band plays two metres away  Japanese acts like Soil & "Pimp" Sessions alongside touring international names. The alternative to a club night when you want the music loud and the room seated.',
   'music','{music,jazz,live,couples,dinner,alcohol}', interval '1 day', 120, 'Two sets nightly',
   false, 9500, 'Ticket only; food and drink extra', 'Blue Note Tokyo','6-3-16 Minami-Aoyama, Minato City, Tokyo',
   139.7135, 35.6608, 'https://www.bluenote.co.jp/jp/', 0.28, 0, 0),

  ('b0000000-0000-4000-8000-000000000108','tokyo','shibuya',
   'Shibuya Bon Odori',null,
   'A neighbourhood folk dance, held under the Shibuya billboards.',
   'A yagura tower goes up in Miyashita Park, taiko drummers climb it, and everybody circles below in happi coats doing steps their grandparents did. What makes the Shibuya one strange and good is the backdrop  Shibuya 109 and the neon crossing right behind a four-hundred-year-old dance. Visitors are pulled into the circle; there is no ticket and no audience.',
   'festival','{festival,traditional,summer,free,music,group-friendly}', interval '7 days', 180, 'Two evenings in late summer',
   true, 0, null, 'Miyashita Park','6-20-10 Jingumae, Shibuya City, Tokyo',
   139.7015, 35.6620, null, 0.58, 0, 0),

  ('b0000000-0000-4000-8000-000000000109','tokyo','shibuya',
   'Tokyo Night Market at Yoyogi Park',null,
   'Five nights of food stalls, carnival games and a live stage in Yoyogi Park.',
   'The Keyaki event plaza at the top of Yoyogi Park fills with food stalls, shooting galleries and a lantern-lit stage for five consecutive nights. It is a Tokyo crowd rather than a tourist one  office workers straight off the Yamanote, families, students  and it costs nothing to walk in.',
   'market','{market,food,music,free,group-friendly,summer}', interval '4 days', 120, 'Five consecutive nights',
   true, 0, 'Free entry; stalls from 500', 'Yoyogi Park Keyaki Namiki Plaza','2-1 Yoyogikamizonocho, Shibuya City, Tokyo',
   139.6950, 35.6698, null, 0.62, 0, 0),

  ('b0000000-0000-4000-8000-000000000110','tokyo',null,
   'Red Tokyo Tower',null,
   'Japan''s largest e-sports park, three floors inside the base of Tokyo Tower.',
   'Foot Town, the building under Tokyo Tower everyone walks past on the way to the lift, holds a three-floor digital amusement park: a robot-arm claw machine the size of a car, projection-mapped climbing walls, racing rigs and an e-sports arena. Almost nobody recommends it, which is why it is rarely queued.',
   'anime','{anime,gaming,indoor,group-friendly,rainy-day}', null, 150, 'Daily, 10:0022:00',
   false, 2900, 'Day pass', 'Red Tokyo Tower, Foot Town 35F','4-2-8 Shibakoen, Minato City, Tokyo',
   139.7454, 35.6586, 'https://tokyotower.red-brand.jp/', 0.25, 0, 0)

) as v(id, city, hood, name, name_ja, short_desc, long_desc, category, tags,
       offset_h, duration, recurrence, is_free, price, price_note, venue, address,
       lng, lat, external, locality, saves, shares)
join cities c on c.slug = v.city
left join neighborhoods n on n.city_id = c.id and n.slug = v.hood
on conflict (id) do nothing;
