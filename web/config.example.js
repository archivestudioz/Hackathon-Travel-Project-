// Copy to web/config.js and fill in. config.js is gitignored.
export const CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT.supabase.co",
  SUPABASE_ANON_KEY: "",

  // Protomaps hosted API — global vector tiles, free under 1M requests/month.
  PROTOMAPS_API_KEY: "",

  // Offline fallback. Fetch with scripts/fetch_tiles.sh; if the hosted API is
  // unreachable at load, the map falls back to this and the demo still runs.
  OFFLINE_PMTILES: "./tiles/nyc.pmtiles",

  DEFAULT_CITY: "nyc",
  DEFAULT_LOCALE: "en",
};
