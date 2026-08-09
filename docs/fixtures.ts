/**
 * Roam engine — fixtures.
 *
 * REAL payloads, dumped from the seeded database. Not hand-written, so the
 * shapes cannot drift from what the engine actually returns.
 *
 * Why this file exists: components generated from Figma tend to arrive with
 * invented prop shapes. Binding them to these fixtures from the first commit
 * means the swap to live data is a single import change rather than a
 * refactor of every card.
 *
 *   import { FEED } from '@/lib/fixtures'
 *   const cards = FEED                      // building screens, no backend
 *   const cards = await getFeed()           // same shape, live
 *
 * Regenerate after changing the seed or any function signature.
 */

import type {
  ExperienceCard, SessionState, PickerCard, Trip, ItineraryDay,
} from './roam-client'

/** getSessionState() */
export const SESSION: SessionState = {
    "is_guest": true,
    "onboarded": true,
    "signed_in": true,
    "confidence": 0.4,
    "profile_id": "baae18d6-758c-490e-853f-60c9a87ad874",
    "trip_count": 1,
    "next_screen": "feed",
    "saved_count": 4,
    "display_name": "Mika",
    "prompt_signup": true
  }

/** getFeed() */
export const FEED: ExperienceCard[] = [
    {
      "lat": 34.708,
      "lng": 135.503,
      "city": "Osaka",
      "name": "Nakazakicho Cafe & Zine Walk",
      "tags": [
        "art",
        "shopping",
        "food",
        "solo-friendly"
      ],
      "score": 12.236,
      "is_free": true,
      "reasons": [
        "More like the food you keep saving",
        "Because you like restaurants & food",
        "In Osaka",
        "Locally hosted, not on the tourist trail",
        "Free"
      ],
      "category": "art",
      "is_saved": false,
      "host_name": "Nakazaki Zine Club",
      "price_yen": 0,
      "starts_at": null,
      "media_kind": "placeholder",
      "price_note": "Route free; zine map 300 yen at any participating cafe",
      "save_count": 58,
      "venue_name": "Nakazakicho",
      "share_count": 9,
      "duration_min": 150,
      "in_itinerary": false,
      "neighborhood": "Nakazakicho",
      "experience_id": "b0000000-0000-4000-8000-000000000018",
      "host_is_local": true,
      "host_verified": false,
      "media_license": "placeholder",
      "recurrence_note": "Any day; most cafes closed Tuesday",
      "media_source_url": null,
      "short_description": "Prewar houses turned into cafes, one street from a skyscraper district.",
      "media_thumbnail_url": null,
      "media_attribution_url": null,
      "media_attribution_name": null
    },
    {
      "lat": 34.696,
      "lng": 135.514,
      "city": "Osaka",
      "name": "Tenjin Matsuri River Procession",
      "tags": [
        "festival",
        "traditional",
        "nature",
        "family-friendly",
        "group-friendly"
      ],
      "score": 10.02,
      "is_free": true,
      "reasons": [
        "Because you like traditional culture",
        "In Tenma, where you are staying",
        "Happening this week",
        "Free",
        "Good for group travel"
      ],
      "category": "festival",
      "is_saved": false,
      "host_name": "Osaka Tenmangu Shrine",
      "price_yen": 0,
      "starts_at": "2026-08-15T17:39:09.760599+00:00",
      "media_kind": "placeholder",
      "price_note": "Free from the riverbank; paid grandstand seats exist",
      "save_count": 512,
      "venue_name": "Okawa River",
      "share_count": 168,
      "duration_min": 300,
      "in_itinerary": false,
      "neighborhood": "Tenma",
      "experience_id": "b0000000-0000-4000-8000-000000000019",
      "host_is_local": true,
      "host_verified": true,
      "media_license": "placeholder",
      "recurrence_note": "July 24–25 annually",
      "media_source_url": null,
      "short_description": "A thousand-year-old festival, a hundred boats, and fireworks over the Okawa.",
      "media_thumbnail_url": null,
      "media_attribution_url": null,
      "media_attribution_name": null
    },
    {
      "lat": 34.672,
      "lng": 135.498,
      "city": "Osaka",
      "name": "Amemura Street Art Walk",
      "tags": [
        "art",
        "shopping",
        "music",
        "solo-friendly",
        "group-friendly"
      ],
      "score": 6.644,
      "is_free": true,
      "reasons": [
        "In Osaka",
        "Happening this week",
        "Locally hosted, not on the tourist trail",
        "Free",
        "Good for group travel"
      ],
      "category": "art",
      "is_saved": false,
      "host_name": "Amemura Art Walk",
      "price_yen": 0,
      "starts_at": "2026-08-13T17:39:09.760599+00:00",
      "media_kind": "placeholder",
      "price_note": null,
      "save_count": 84,
      "venue_name": "Triangle Park, Amerikamura",
      "share_count": 17,
      "duration_min": 90,
      "in_itinerary": false,
      "neighborhood": "Amerikamura",
      "experience_id": "b0000000-0000-4000-8000-000000000020",
      "host_is_local": true,
      "host_verified": false,
      "media_license": "placeholder",
      "recurrence_note": "Sundays, 15:00",
      "media_source_url": null,
      "short_description": "Murals, skate shops, and the artists who painted them.",
      "media_thumbnail_url": null,
      "media_attribution_url": null,
      "media_attribution_name": null
    },
    {
      "lat": 35.647,
      "lng": 139.8,
      "city": "Tokyo",
      "name": "Super Autobacs Tokyo Bay",
      "tags": [
        "cars",
        "shopping"
      ],
      "score": 4.152,
      "is_free": true,
      "reasons": [
        "Because you like car culture",
        "Free"
      ],
      "category": "cars",
      "is_saved": false,
      "host_name": "Super Autobacs",
      "price_yen": 0,
      "starts_at": null,
      "media_kind": "placeholder",
      "price_note": "Free entry",
      "save_count": 88,
      "venue_name": "Super Autobacs Tokyo Bay Shinonome",
      "share_count": 14,
      "duration_min": 90,
      "in_itinerary": false,
      "neighborhood": "Toyosu",
      "experience_id": "b0000000-0000-4000-8000-000000000024",
      "host_is_local": false,
      "host_verified": true,
      "media_license": "placeholder",
      "recurrence_note": "Daily 10:00–20:00",
      "media_source_url": null,
      "short_description": "Four floors of parts, and demo cars nobody will stop you photographing.",
      "media_thumbnail_url": null,
      "media_attribution_url": null,
      "media_attribution_name": null
    },
    {
      "lat": 34.933,
      "lng": 135.762,
      "city": "Kyoto",
      "name": "Fushimi Sake Brewery Tasting",
      "tags": [
        "food",
        "traditional",
        "alcohol",
        "group-friendly"
      ],
      "score": 3.892,
      "is_free": false,
      "reasons": [
        "More like the food you keep saving",
        "Because you like restaurants & food",
        "Happening this week",
        "Locally hosted, not on the tourist trail",
        "Good for group travel"
      ],
      "category": "food",
      "is_saved": false,
      "host_name": "Fushimi Sake Guild",
      "price_yen": 2800,
      "starts_at": "2026-08-11T19:39:09.760599+00:00",
      "media_kind": "placeholder",
      "price_note": "Nine tastings",
      "save_count": 127,
      "venue_name": "Fushimi Sake District",
      "share_count": 24,
      "duration_min": 180,
      "in_itinerary": false,
      "neighborhood": "Fushimi",
      "experience_id": "b0000000-0000-4000-8000-000000000015",
      "host_is_local": true,
      "host_verified": true,
      "media_license": "placeholder",
      "recurrence_note": "Daily except Monday",
      "media_source_url": null,
      "short_description": "Soft water, eighteen breweries, and the ones that still open their doors.",
      "media_thumbnail_url": null,
      "media_attribution_url": null,
      "media_attribution_name": null
    },
    {
      "lat": 35.662,
      "lng": 139.667,
      "city": "Tokyo",
      "name": "Shelter Shimokitazawa: Friday Live",
      "tags": [
        "music",
        "nightlife",
        "solo-friendly"
      ],
      "score": 3.828,
      "is_free": false,
      "reasons": [
        "More like the nightlife you keep saving",
        "Because you like bars & nightclubs",
        "Happening this week",
        "Locally hosted, not on the tourist trail"
      ],
      "category": "music",
      "is_saved": false,
      "host_name": "Shelter Shimokita",
      "price_yen": 3300,
      "starts_at": "2026-08-11T17:39:09.760599+00:00",
      "media_kind": "placeholder",
      "price_note": "Plus one drink ticket, 600 yen",
      "save_count": 142,
      "venue_name": "Shimokitazawa SHELTER",
      "share_count": 27,
      "duration_min": 210,
      "in_itinerary": false,
      "neighborhood": "Shimokitazawa",
      "experience_id": "b0000000-0000-4000-8000-000000000003",
      "host_is_local": true,
      "host_verified": true,
      "media_license": "placeholder",
      "recurrence_note": "Most Fridays",
      "media_source_url": null,
      "short_description": "Basement live house, four bands, capacity 250.",
      "media_thumbnail_url": null,
      "media_attribution_url": null,
      "media_attribution_name": null
    },
    {
      "lat": 35.666,
      "lng": 139.717,
      "city": "Tokyo",
      "name": "Honda Welcome Plaza Aoyama",
      "tags": [
        "cars",
        "culture",
        "family-friendly"
      ],
      "score": 3.768,
      "is_free": true,
      "reasons": [
        "Because you like car culture",
        "Free"
      ],
      "category": "cars",
      "is_saved": false,
      "host_name": "Honda Welcome Plaza",
      "price_yen": 0,
      "starts_at": null,
      "media_kind": "placeholder",
      "price_note": "Free",
      "save_count": 96,
      "venue_name": "Honda Welcome Plaza Aoyama",
      "share_count": 12,
      "duration_min": 30,
      "in_itinerary": false,
      "neighborhood": "Shinjuku",
      "experience_id": "b0000000-0000-4000-8000-000000000025",
      "host_is_local": false,
      "host_verified": true,
      "media_license": "placeholder",
      "recurrence_note": "Daily 10:00–18:00",
      "media_source_url": null,
      "short_description": "Free F1 cars in a lobby, ten minutes from Omotesando.",
      "media_thumbnail_url": null,
      "media_attribution_url": null,
      "media_attribution_name": null
    },
    {
      "lat": 35.672,
      "lng": 139.765,
      "city": "Tokyo",
      "name": "Nissan Crossing, Ginza",
      "tags": [
        "cars",
        "shopping"
      ],
      "score": 3.624,
      "is_free": true,
      "reasons": [
        "Because you like car culture",
        "Free"
      ],
      "category": "cars",
      "is_saved": false,
      "host_name": "Nissan Crossing",
      "price_yen": 0,
      "starts_at": null,
      "media_kind": "placeholder",
      "price_note": "Free",
      "save_count": 211,
      "venue_name": "Nissan Crossing",
      "share_count": 28,
      "duration_min": 40,
      "in_itinerary": false,
      "neighborhood": null,
      "experience_id": "b0000000-0000-4000-8000-000000000026",
      "host_is_local": false,
      "host_verified": true,
      "media_license": "placeholder",
      "recurrence_note": "Daily 10:00–20:00",
      "media_source_url": null,
      "short_description": "Concept cars behind glass on the busiest corner in Ginza.",
      "media_thumbnail_url": null,
      "media_attribution_url": null,
      "media_attribution_name": null
    }
  ]

/** getPickerCards() */
export const PICKER_CARDS: PickerCard[] = [
    {
      "city": "Tokyo",
      "name": "Daikoku Futo PA Night Meet",
      "is_free": true,
      "category": "cars",
      "locality": 0.94,
      "price_yen": 0,
      "neighborhood": null,
      "experience_id": "b0000000-0000-4000-8000-000000000021",
      "thumbnail_url": null,
      "short_description": "The most famous car park on earth, under an expressway loop."
    },
    {
      "city": "Tokyo",
      "name": "Morning Zazen at a Neighbourhood Temple",
      "is_free": false,
      "category": "wellness",
      "locality": 0.94,
      "price_yen": 1000,
      "neighborhood": "Asakusa",
      "experience_id": "b0000000-0000-4000-8000-000000000008",
      "thumbnail_url": null,
      "short_description": "Forty minutes of seated meditation. No English, no ceremony, no photos."
    },
    {
      "city": "Tokyo",
      "name": "Yanaka Evening Stroll & Senbei",
      "is_free": false,
      "category": "traditional",
      "locality": 0.91,
      "price_yen": 2000,
      "neighborhood": "Yanaka",
      "experience_id": "b0000000-0000-4000-8000-000000000004",
      "thumbnail_url": null,
      "short_description": "The Tokyo that survived the firebombing, walked at dusk."
    },
    {
      "city": "Tokyo",
      "name": "Koenji Vintage Crawl",
      "is_free": true,
      "category": "shopping",
      "locality": 0.88,
      "price_yen": 0,
      "neighborhood": "Koenji",
      "experience_id": "b0000000-0000-4000-8000-000000000002",
      "thumbnail_url": null,
      "short_description": "Forty secondhand shops in six streets. No map, no plan."
    },
    {
      "city": "Tokyo",
      "name": "Shelter Shimokitazawa: Friday Live",
      "is_free": false,
      "category": "music",
      "locality": 0.79,
      "price_yen": 3300,
      "neighborhood": "Shimokitazawa",
      "experience_id": "b0000000-0000-4000-8000-000000000003",
      "thumbnail_url": null,
      "short_description": "Basement live house, four bands, capacity 250."
    },
    {
      "city": "Tokyo",
      "name": "Golden Gai Izakaya Hop",
      "is_free": false,
      "category": "nightlife",
      "locality": 0.74,
      "price_yen": 7000,
      "neighborhood": "Shinjuku",
      "experience_id": "b0000000-0000-4000-8000-000000000007",
      "thumbnail_url": null,
      "short_description": "Six seats a bar, six bars a night, in 200 wooden buildings."
    },
    {
      "city": "Tokyo",
      "name": "Akihabara Retro Arcade Deep Dive",
      "is_free": false,
      "category": "anime",
      "locality": 0.68,
      "price_yen": 4500,
      "neighborhood": "Akihabara",
      "experience_id": "b0000000-0000-4000-8000-000000000005",
      "thumbnail_url": null,
      "short_description": "Four floors of cabinets from 1978 onward, with someone who can explain them."
    },
    {
      "city": "Osaka",
      "name": "Shinsekai Kushikatsu, No Double Dipping",
      "is_free": false,
      "category": "food",
      "locality": 0.64,
      "price_yen": 3200,
      "neighborhood": "Shinsekai",
      "experience_id": "b0000000-0000-4000-8000-000000000017",
      "thumbnail_url": null,
      "short_description": "Deep-fried everything under a 1912 tower, with one unbreakable rule."
    },
    {
      "city": "Osaka",
      "name": "Tenjin Matsuri River Procession",
      "is_free": true,
      "category": "festival",
      "locality": 0.55,
      "price_yen": 0,
      "neighborhood": "Tenma",
      "experience_id": "b0000000-0000-4000-8000-000000000019",
      "thumbnail_url": null,
      "short_description": "A thousand-year-old festival, a hundred boats, and fireworks over the Okawa."
    },
    {
      "city": "Kyoto",
      "name": "Arashiyama Bamboo Grove at Dawn",
      "is_free": false,
      "category": "nature",
      "locality": 0.45,
      "price_yen": 2500,
      "neighborhood": "Arashiyama",
      "experience_id": "b0000000-0000-4000-8000-000000000012",
      "thumbnail_url": null,
      "short_description": "The famous grove, at 6am, before the buses."
    },
    {
      "city": "Tokyo",
      "name": "teamLab Planets TOKYO",
      "is_free": false,
      "category": "art",
      "locality": 0.18,
      "price_yen": 3800,
      "neighborhood": "Toyosu",
      "experience_id": "b0000000-0000-4000-8000-000000000009",
      "thumbnail_url": null,
      "short_description": "Barefoot through knee-deep water and a room of mirrors."
    }
  ]

/** getExperience(id) */
export const EXPERIENCE_DETAIL: any = {
    "lat": 35.4553,
    "lng": 139.6873,
    "city": "Tokyo",
    "host": {
      "bio": "No organisers, no schedule. People just turn up.",
      "kind": "community",
      "name": "Daikoku Regulars",
      "is_local": true,
      "verified": false,
      "avatar_url": null,
      "website_url": null
    },
    "name": "Daikoku Futo PA Night Meet",
    "tags": [
      "cars",
      "late-night",
      "photography",
      "group-friendly"
    ],
    "media": [
      {
        "kind": "placeholder",
        "license": "placeholder",
        "alt_text": "The most famous car park on earth, under an expressway loop.",
        "is_primary": true,
        "source_url": null,
        "thumbnail_url": null,
        "attribution_url": null,
        "attribution_name": null,
        "attribution_handle": null
      }
    ],
    "address": "Daikoku Futo, Tsurumi Ward, Yokohama (45 min from central Tokyo)",
    "ends_at": null,
    "is_free": true,
    "name_ja": "大黒PA",
    "reasons": [
      "Because you like car culture",
      "Happening this week",
      "Locally hosted, not on the tourist trail",
      "Free",
      "Good for group travel"
    ],
    "related": [
      {
        "name": "Nissan Crossing, Ginza",
        "is_free": true,
        "category": "cars",
        "price_yen": 0,
        "neighborhood": null,
        "experience_id": "b0000000-0000-4000-8000-000000000026",
        "thumbnail_url": null
      },
      {
        "name": "Tenjin Matsuri River Procession",
        "is_free": true,
        "category": "festival",
        "price_yen": 0,
        "neighborhood": "Tenma",
        "experience_id": "b0000000-0000-4000-8000-000000000019",
        "thumbnail_url": null
      },
      {
        "name": "Golden Gai Izakaya Hop",
        "is_free": false,
        "category": "nightlife",
        "price_yen": 7000,
        "neighborhood": "Shinjuku",
        "experience_id": "b0000000-0000-4000-8000-000000000007",
        "thumbnail_url": null
      },
      {
        "name": "Shinsekai Kushikatsu, No Double Dipping",
        "is_free": false,
        "category": "food",
        "price_yen": 3200,
        "neighborhood": "Shinsekai",
        "experience_id": "b0000000-0000-4000-8000-000000000017",
        "thumbnail_url": null
      },
      {
        "name": "Akihabara Retro Arcade Deep Dive",
        "is_free": false,
        "category": "anime",
        "price_yen": 4500,
        "neighborhood": "Akihabara",
        "experience_id": "b0000000-0000-4000-8000-000000000005",
        "thumbnail_url": null
      },
      {
        "name": "Tenma Standing Bar Crawl",
        "is_free": false,
        "category": "nightlife",
        "price_yen": 5000,
        "neighborhood": "Tenma",
        "experience_id": "b0000000-0000-4000-8000-000000000016",
        "thumbnail_url": null
      }
    ],
    "category": "cars",
    "is_saved": true,
    "locality": 0.94,
    "price_yen": 0,
    "starts_at": "2026-08-10T15:39:09.760599+00:00",
    "price_note": "Free. Parking is the whole point.",
    "save_count": 389,
    "stay22_url": null,
    "venue_name": "Daikoku Futo Parking Area",
    "booking_url": null,
    "description": "A motorway service area on reclaimed land in Yokohama Bay that became the centre of Japanese car culture by accident. Bosozoku bikes, kaido racers, immaculate kyusha, and someone's twin-turbo Supra idling next to a hand-built VIP sedan. Nothing is organised and nothing is advertised — it happens on weekend nights when the police are not closing the ramp. Take the Wangan line, not a taxi that will not wait.",
    "share_count": 121,
    "duration_min": 180,
    "external_url": null,
    "in_itinerary": false,
    "neighborhood": null,
    "experience_id": "b0000000-0000-4000-8000-000000000021",
    "recurrence_note": "Weekend nights, weather and police permitting",
    "short_description": "The most famous car park on earth, under an expressway loop."
  }

/** getExploreSections('tokyo') */
export const EXPLORE_SECTIONS: any = {
    "popular_near_you": [
      {
        "city": "Tokyo",
        "name": "teamLab Planets TOKYO",
        "is_free": false,
        "category": "art",
        "price_yen": 3800,
        "starts_at": null,
        "save_count": 892,
        "neighborhood": "Toyosu",
        "experience_id": "b0000000-0000-4000-8000-000000000009",
        "thumbnail_url": null
      },
      {
        "city": "Tokyo",
        "name": "Daikoku Futo PA Night Meet",
        "is_free": true,
        "category": "cars",
        "price_yen": 0,
        "starts_at": "2026-08-10T15:39:09.760599+00:00",
        "save_count": 389,
        "neighborhood": null,
        "experience_id": "b0000000-0000-4000-8000-000000000021",
        "thumbnail_url": null
      },
      {
        "city": "Tokyo",
        "name": "Meguro River Sakura Night Walk",
        "is_free": true,
        "category": "nature",
        "price_yen": 0,
        "starts_at": "2026-08-14T17:39:09.760599+00:00",
        "save_count": 341,
        "neighborhood": "Nakameguro",
        "experience_id": "b0000000-0000-4000-8000-000000000006",
        "thumbnail_url": null
      },
      {
        "city": "Tokyo",
        "name": "Golden Gai Izakaya Hop",
        "is_free": false,
        "category": "nightlife",
        "price_yen": 7000,
        "starts_at": "2026-08-10T17:39:09.760599+00:00",
        "save_count": 268,
        "neighborhood": "Shinjuku",
        "experience_id": "b0000000-0000-4000-8000-000000000007",
        "thumbnail_url": null
      }
    ],
    "hidden_local_gems": [
      {
        "city": "Tokyo",
        "name": "Morning Zazen at a Neighbourhood Temple",
        "is_free": false,
        "category": "wellness",
        "locality": 0.94,
        "price_yen": 1000,
        "starts_at": "2026-08-10T13:39:09.760599+00:00",
        "neighborhood": "Asakusa",
        "experience_id": "b0000000-0000-4000-8000-000000000008",
        "thumbnail_url": null
      },
      {
        "city": "Tokyo",
        "name": "Daikoku Futo PA Night Meet",
        "is_free": true,
        "category": "cars",
        "locality": 0.94,
        "price_yen": 0,
        "starts_at": "2026-08-10T15:39:09.760599+00:00",
        "neighborhood": null,
        "experience_id": "b0000000-0000-4000-8000-000000000021",
        "thumbnail_url": null
      },
      {
        "city": "Tokyo",
        "name": "Yanaka Evening Stroll & Senbei",
        "is_free": false,
        "category": "traditional",
        "locality": 0.91,
        "price_yen": 2000,
        "starts_at": "2026-08-10T23:39:09.760599+00:00",
        "neighborhood": "Yanaka",
        "experience_id": "b0000000-0000-4000-8000-000000000004",
        "thumbnail_url": null
      },
      {
        "city": "Tokyo",
        "name": "Tatsumi PA After Midnight",
        "is_free": true,
        "category": "cars",
        "locality": 0.91,
        "price_yen": 0,
        "starts_at": "2026-08-10T19:39:09.760599+00:00",
        "neighborhood": "Toyosu",
        "experience_id": "b0000000-0000-4000-8000-000000000022",
        "thumbnail_url": null
      }
    ],
    "happening_this_week": [
      {
        "city": "Tokyo",
        "name": "Tsukiji Outer Market Morning Walk",
        "is_free": false,
        "category": "food",
        "price_yen": 3800,
        "starts_at": "2026-08-10T11:39:09.760599+00:00",
        "save_count": 215,
        "neighborhood": "Asakusa",
        "experience_id": "b0000000-0000-4000-8000-000000000001",
        "thumbnail_url": null
      },
      {
        "city": "Tokyo",
        "name": "Morning Zazen at a Neighbourhood Temple",
        "is_free": false,
        "category": "wellness",
        "price_yen": 1000,
        "starts_at": "2026-08-10T13:39:09.760599+00:00",
        "save_count": 41,
        "neighborhood": "Asakusa",
        "experience_id": "b0000000-0000-4000-8000-000000000008",
        "thumbnail_url": null
      },
      {
        "city": "Tokyo",
        "name": "Daikoku Futo PA Night Meet",
        "is_free": true,
        "category": "cars",
        "price_yen": 0,
        "starts_at": "2026-08-10T15:39:09.760599+00:00",
        "save_count": 389,
        "neighborhood": null,
        "experience_id": "b0000000-0000-4000-8000-000000000021",
        "thumbnail_url": null
      },
      {
        "city": "Tokyo",
        "name": "Golden Gai Izakaya Hop",
        "is_free": false,
        "category": "nightlife",
        "price_yen": 7000,
        "starts_at": "2026-08-10T17:39:09.760599+00:00",
        "save_count": 268,
        "neighborhood": "Shinjuku",
        "experience_id": "b0000000-0000-4000-8000-000000000007",
        "thumbnail_url": null
      }
    ]
  }

/** getItinerary() */
export const ITINERARY: { trip: any; days: ItineraryDay[] } = {
    "days": [
      {
        "day": "2026-08-29",
        "stops": [
          {
            "lat": 34.7055,
            "lng": 135.512,
            "city": "Osaka",
            "name": "Tenma Standing Bar Crawl",
            "note": null,
            "address": "Kita Ward, Osaka",
            "is_free": false,
            "category": "nightlife",
            "entry_id": "a6243a97-ac6a-449f-bfef-ec0c80a1a99b",
            "position": 1,
            "host_name": "Tenma Tachinomi Tour",
            "price_yen": 5000,
            "starts_at": "2026-08-10T01:39:09.760599+00:00",
            "stay22_url": null,
            "venue_name": "Tenjinbashisuji Arcade",
            "booking_url": null,
            "planned_end": null,
            "duration_min": 180,
            "neighborhood": "Tenma",
            "experience_id": "b0000000-0000-4000-8000-000000000016",
            "planned_start": "19:00:00",
            "thumbnail_url": null
          }
        ],
        "stop_count": 1,
        "total_price_yen": 5000
      },
      {
        "day": "2026-08-31",
        "stops": [
          {
            "lat": 34.6524,
            "lng": 135.5062,
            "city": "Osaka",
            "name": "Shinsekai Kushikatsu, No Double Dipping",
            "note": null,
            "address": "Naniwa Ward, Osaka",
            "is_free": false,
            "category": "food",
            "entry_id": "81ca7684-5b52-4217-afa2-da22c1165249",
            "position": 1,
            "host_name": "Shinsekai Kushikatsu Kumiai",
            "price_yen": 3200,
            "starts_at": "2026-08-10T04:39:09.760599+00:00",
            "stay22_url": null,
            "venue_name": "Shinsekai",
            "booking_url": null,
            "planned_end": null,
            "duration_min": 120,
            "neighborhood": "Shinsekai",
            "experience_id": "b0000000-0000-4000-8000-000000000017",
            "planned_start": "12:30:00",
            "thumbnail_url": null
          }
        ],
        "stop_count": 1,
        "total_price_yen": 3200
      }
    ],
    "trip": {
      "city": "Osaka",
      "name": "Osaka",
      "pace": "packed",
      "party": "group",
      "budget": "moderate",
      "status": "planning",
      "trip_id": "fc87a2bb-810d-4f47-b0a5-393b24f9175e",
      "end_date": "2026-09-01",
      "start_date": "2026-08-29",
      "neighborhood": "Tenma",
      "duration_days": 4
    }
  }

/** getTrips() */
export const TRIPS: Trip[] = [
    {
      "city": "Osaka",
      "name": "Osaka",
      "pace": "packed",
      "party": "group",
      "budget": "moderate",
      "status": "planning",
      "country": "JP",
      "trip_id": "fc87a2bb-810d-4f47-b0a5-393b24f9175e",
      "end_date": "2026-09-01",
      "city_slug": "osaka",
      "is_current": true,
      "start_date": "2026-08-29",
      "stop_count": 2,
      "neighborhood": "Tenma",
      "duration_days": 4
    }
  ]

/** getSaved() */
export const SAVED: any[] = [
    {
      "lat": 34.6524,
      "lng": 135.5062,
      "city": "Osaka",
      "name": "Shinsekai Kushikatsu, No Double Dipping",
      "is_free": false,
      "category": "food",
      "saved_at": "2026-08-09T17:47:35.331258+00:00",
      "price_yen": 3200,
      "starts_at": "2026-08-10T04:39:09.760599+00:00",
      "save_count": 232,
      "venue_name": "Shinsekai",
      "in_itinerary": true,
      "neighborhood": "Shinsekai",
      "experience_id": "b0000000-0000-4000-8000-000000000017",
      "short_description": "Deep-fried everything under a 1912 tower, with one unbreakable rule.",
      "media_thumbnail_url": null
    },
    {
      "lat": 35.4553,
      "lng": 139.6873,
      "city": "Tokyo",
      "name": "Daikoku Futo PA Night Meet",
      "is_free": true,
      "category": "cars",
      "saved_at": "2026-08-09T17:47:35.315277+00:00",
      "price_yen": 0,
      "starts_at": "2026-08-10T15:39:09.760599+00:00",
      "save_count": 389,
      "venue_name": "Daikoku Futo Parking Area",
      "in_itinerary": false,
      "neighborhood": null,
      "experience_id": "b0000000-0000-4000-8000-000000000021",
      "short_description": "The most famous car park on earth, under an expressway loop.",
      "media_thumbnail_url": null
    },
    {
      "lat": 35.6654,
      "lng": 139.7707,
      "city": "Tokyo",
      "name": "Tsukiji Outer Market Morning Walk",
      "is_free": false,
      "category": "food",
      "saved_at": "2026-08-09T17:47:35.315277+00:00",
      "price_yen": 3800,
      "starts_at": "2026-08-10T11:39:09.760599+00:00",
      "save_count": 215,
      "venue_name": "Tsukiji Outer Market",
      "in_itinerary": false,
      "neighborhood": "Asakusa",
      "experience_id": "b0000000-0000-4000-8000-000000000001",
      "short_description": "Eat breakfast standing up with the people who sell the fish.",
      "media_thumbnail_url": null
    },
    {
      "lat": 34.7055,
      "lng": 135.512,
      "city": "Osaka",
      "name": "Tenma Standing Bar Crawl",
      "is_free": false,
      "category": "nightlife",
      "saved_at": "2026-08-09T17:47:35.315277+00:00",
      "price_yen": 5000,
      "starts_at": "2026-08-10T01:39:09.760599+00:00",
      "save_count": 177,
      "venue_name": "Tenjinbashisuji Arcade",
      "in_itinerary": true,
      "neighborhood": "Tenma",
      "experience_id": "b0000000-0000-4000-8000-000000000016",
      "short_description": "Four tachinomi bars. Nobody sits down. Everything is under 500 yen.",
      "media_thumbnail_url": null
    }
  ]

/** getOnboardingOptions() */
export const ONBOARDING_OPTIONS: any = {
    "reasons": [
      {
        "slug": "vacation",
        "emoji": "🌴",
        "label": "Just a holiday"
      },
      {
        "slug": "food",
        "emoji": "🍜",
        "label": "Eating my way around"
      },
      {
        "slug": "culture",
        "emoji": "⛩",
        "label": "Culture and history"
      },
      {
        "slug": "adventure",
        "emoji": "🥾",
        "label": "Adventure and hiking"
      },
      {
        "slug": "nightlife",
        "emoji": "🌃",
        "label": "Going out"
      },
      {
        "slug": "reset",
        "emoji": "♨️",
        "label": "Rest and reset"
      },
      {
        "slug": "photography",
        "emoji": "📷",
        "label": "Photography"
      },
      {
        "slug": "anime",
        "emoji": "🎮",
        "label": "Anime and gaming"
      },
      {
        "slug": "business",
        "emoji": "💼",
        "label": "Work trip"
      },
      {
        "slug": "friends",
        "emoji": "👋",
        "label": "Visiting people"
      }
    ],
    "age_bands": [
      {
        "slug": "under_18",
        "label": "Under 18"
      },
      {
        "slug": "18_24",
        "label": "18–24"
      },
      {
        "slug": "25_34",
        "label": "25–34"
      },
      {
        "slug": "35_44",
        "label": "35–44"
      },
      {
        "slug": "45_54",
        "label": "45–54"
      },
      {
        "slug": "55_plus",
        "label": "55+"
      },
      {
        "slug": "undisclosed",
        "label": "Rather not say"
      }
    ],
    "countries": [
      {
        "code": "JP",
        "name": "Japan",
        "emoji": "🇯🇵",
        "available": true
      },
      {
        "code": "KR",
        "name": "South Korea",
        "emoji": "🇰🇷",
        "available": false
      },
      {
        "code": "TW",
        "name": "Taiwan",
        "emoji": "🇹🇼",
        "available": false
      },
      {
        "code": "TH",
        "name": "Thailand",
        "emoji": "🇹🇭",
        "available": false
      },
      {
        "code": "VN",
        "name": "Vietnam",
        "emoji": "🇻🇳",
        "available": false
      },
      {
        "code": "IT",
        "name": "Italy",
        "emoji": "🇮🇹",
        "available": false
      },
      {
        "code": "ES",
        "name": "Spain",
        "emoji": "🇪🇸",
        "available": false
      },
      {
        "code": "PT",
        "name": "Portugal",
        "emoji": "🇵🇹",
        "available": false
      },
      {
        "code": "MX",
        "name": "Mexico",
        "emoji": "🇲🇽",
        "available": false
      },
      {
        "code": "US",
        "name": "United States",
        "emoji": "🇺🇸",
        "available": false
      }
    ],
    "interests": [
      {
        "slug": "food",
        "emoji": "🍜",
        "label": "Restaurants & food"
      },
      {
        "slug": "nightlife",
        "emoji": "🌃",
        "label": "Bars & nightclubs"
      },
      {
        "slug": "nature",
        "emoji": "🌿",
        "label": "Nature & parks"
      },
      {
        "slug": "hiking",
        "emoji": "🥾",
        "label": "Hiking & trails"
      },
      {
        "slug": "beach",
        "emoji": "🏖",
        "label": "Beaches"
      },
      {
        "slug": "art",
        "emoji": "🎨",
        "label": "Art & design"
      },
      {
        "slug": "anime",
        "emoji": "🎮",
        "label": "Anime & gaming"
      },
      {
        "slug": "music",
        "emoji": "🎧",
        "label": "Live music"
      },
      {
        "slug": "shopping",
        "emoji": "🛍",
        "label": "Shopping & vintage"
      },
      {
        "slug": "festival",
        "emoji": "🎏",
        "label": "Festivals"
      },
      {
        "slug": "wellness",
        "emoji": "♨️",
        "label": "Wellness & onsen"
      },
      {
        "slug": "traditional",
        "emoji": "⛩",
        "label": "Traditional culture"
      },
      {
        "slug": "market",
        "emoji": "🧺",
        "label": "Markets"
      },
      {
        "slug": "cars",
        "emoji": "🚗",
        "label": "Car culture"
      }
    ]
  }

/** getTripOptions('JP') */
export const TRIP_OPTIONS: any = {
    "paces": [
      {
        "slug": "relaxed",
        "label": "Relaxed"
      },
      {
        "slug": "balanced",
        "label": "Balanced"
      },
      {
        "slug": "packed",
        "label": "Packed"
      }
    ],
    "cities": [
      {
        "id": "e765a682-b62a-43b8-88e1-fc50ad6c32ec",
        "lat": 35.0116,
        "lng": 135.7681,
        "name": "Kyoto",
        "slug": "kyoto",
        "name_ja": "京都",
        "neighborhoods": [
          {
            "id": "c197371f-58ee-41a9-8b8f-0f957981011f",
            "name": "Arashiyama",
            "slug": "arashiyama",
            "blurb": "Bamboo, monkeys, and the Hozu river gorge."
          },
          {
            "id": "6e312d94-a73c-4f9f-8f46-c81eda0fd039",
            "name": "Fushimi",
            "slug": "fushimi",
            "blurb": "Sake breweries and ten thousand torii."
          },
          {
            "id": "c914eca5-b346-448d-9ed7-e351c86dfdad",
            "name": "Gion",
            "slug": "gion",
            "blurb": "Wooden machiya, lantern light, and the Kamo river."
          },
          {
            "id": "ba5320f0-a435-4a8f-911f-25b058fcf3f6",
            "name": "Nishijin",
            "slug": "nishijin",
            "blurb": "Weaving district, quiet workshops, no crowds."
          },
          {
            "id": "010c4de4-4f1b-4021-90e9-7e2a273123f9",
            "name": "Nishiki",
            "slug": "nishiki",
            "blurb": "Four hundred metres of covered market."
          }
        ],
        "experience_count": 5
      },
      {
        "id": "9baed695-a5f5-425a-bae0-2a0029ba40d8",
        "lat": 34.6937,
        "lng": 135.5023,
        "name": "Osaka",
        "slug": "osaka",
        "name_ja": "大阪",
        "neighborhoods": [
          {
            "id": "920b8781-5676-425f-bf13-f645f470270d",
            "name": "Amerikamura",
            "slug": "amerikamura",
            "blurb": "Street art, skate shops, and Osaka youth culture."
          },
          {
            "id": "ce76524c-7e90-4a12-ae27-938255129b7b",
            "name": "Nakazakicho",
            "slug": "nakazakicho",
            "blurb": "Prewar houses turned into cafes and zine shops."
          },
          {
            "id": "f444ab8c-ce6c-4137-adf6-a52e799bb6ea",
            "name": "Namba",
            "slug": "namba",
            "blurb": "Dotonbori neon and the food everyone comes for."
          },
          {
            "id": "d7da49bb-7775-4ad5-8c04-1b423afa9b21",
            "name": "Shinsekai",
            "slug": "shinsekai",
            "blurb": "Tsutenkaku tower and kushikatsu under it."
          },
          {
            "id": "849a6422-f4d1-4418-ab34-ad527e32564b",
            "name": "Tenma",
            "slug": "tenma",
            "blurb": "The longest shopping arcade in Japan, and standing bars."
          }
        ],
        "experience_count": 5
      },
      {
        "id": "e8ace328-d96b-4b3c-95f6-26316ce8d3de",
        "lat": 35.6762,
        "lng": 139.6503,
        "name": "Tokyo",
        "slug": "tokyo",
        "name_ja": "東京",
        "neighborhoods": [
          {
            "id": "13aba2e2-11a4-4d7b-a11d-9224890666c6",
            "name": "Akihabara",
            "slug": "akihabara",
            "blurb": "Arcades, parts shops, and six floors of everything."
          },
          {
            "id": "a3d4c95f-b718-470a-a4a6-1e7ea4df5ef6",
            "name": "Asakusa",
            "slug": "asakusa",
            "blurb": "Senso-ji, artisan streets, and the old low city."
          },
          {
            "id": "e69e8272-b6b5-4066-87a0-c4b5935e85a3",
            "name": "Koenji",
            "slug": "koenji",
            "blurb": "Punk bars and the densest vintage in Tokyo."
          },
          {
            "id": "796beb19-cf6c-41be-914b-23f87a051aac",
            "name": "Nakameguro",
            "slug": "nakameguro",
            "blurb": "Canal-side cafes under the cherry trees."
          },
          {
            "id": "6bc99ed8-2afd-4a1b-9cc5-24af00f6e1fe",
            "name": "Shibuya",
            "slug": "shibuya",
            "blurb": "Crossing, record shops, and the city at its loudest."
          },
          {
            "id": "bc3ba074-2198-4983-8dbc-f4962b1fc85a",
            "name": "Shimokitazawa",
            "slug": "shimokitazawa",
            "blurb": "Live houses, secondhand racks, tiny theatres."
          },
          {
            "id": "e27d1b04-51d4-4f0d-80a6-c16189f6af91",
            "name": "Shinjuku",
            "slug": "shinjuku",
            "blurb": "Golden Gai, department stores, and Omoide Yokocho smoke."
          },
          {
            "id": "2f9673d8-a362-4a55-b8f7-3d2447efc752",
            "name": "Toyosu",
            "slug": "toyosu",
            "blurb": "Reclaimed waterfront, the new fish market, digital art."
          },
          {
            "id": "ad39e952-48f9-478c-8e73-921ef6d2822c",
            "name": "Yanaka",
            "slug": "yanaka",
            "blurb": "Survived the war and the bubble. Cats and senbei."
          }
        ],
        "experience_count": 16
      }
    ],
    "budgets": [
      {
        "slug": "shoestring",
        "label": "Shoestring",
        "ceiling_yen": 1500
      },
      {
        "slug": "moderate",
        "label": "Moderate",
        "ceiling_yen": 5000
      },
      {
        "slug": "comfortable",
        "label": "Comfortable",
        "ceiling_yen": 15000
      },
      {
        "slug": "splurge",
        "label": "Splurge",
        "ceiling_yen": null
      }
    ],
    "country": {
      "code": "JP",
      "name": "Japan",
      "emoji": "🇯🇵"
    },
    "parties": [
      {
        "slug": "solo",
        "label": "Solo"
      },
      {
        "slug": "couple",
        "label": "Couple"
      },
      {
        "slug": "family",
        "label": "Family"
      },
      {
        "slug": "group",
        "label": "Group"
      }
    ]
  }
