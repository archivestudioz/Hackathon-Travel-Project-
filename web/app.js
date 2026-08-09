// Roam — the whole client.
//
// There is no application server: this file calls Postgres functions directly
// through PostgREST and subscribes to Postgres' write-ahead log for live
// updates. RLS decides what comes back, so authorization is never this file's
// responsibility.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { CONFIG } from "./config.js";
import { buildStyle } from "./map-style.js";
import { LOCALES, setLocale, getLocale, t } from "./i18n.js";

const sb = createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true },
});

// ── state ───────────────────────────────────────────────────────────────────

const S = {
  city: null,
  mode: "walk",
  filter: "all",
  ride: null,
  itinerary: [],
  channel: null,
  markers: { places: [], stops: [], guide: null, me: null },
  playing: null,
  // Who the traveler is. Everything shown is filtered through this, which is
  // the difference between a generated route and a hand-authored tour that is
  // identical for everyone who buys it.
  prefs: { interests: [], pace: "balanced", crowd: "local", accessibility: [] },
};

const INTERESTS = ["eat", "culture", "hike", "beach", "market", "nightlife", "art", "history", "nature"];
const INTEREST_GLYPH = {
  eat: "🍽", culture: "🏛", hike: "🥾", beach: "🏖", market: "🧺",
  nightlife: "🌃", art: "🎨", history: "📜", nature: "🌿",
};
const CROWDS = ["local", "mixed", "iconic"];
const PACES = ["relaxed", "balanced", "packed"];

const CATEGORY_GLYPH = {
  eat: "🍽", beach: "🏖", attraction: "📸", hike: "🥾", culture: "🏛",
  market: "🧺", viewpoint: "🌅", essentials: "🚻", event: "🎟", wifi: "📶",
};

const MODE_GLYPH = { walk: "🚶", drive: "🚗", boat: "⛵" };

const $ = (id) => document.getElementById(id);

// ── map ─────────────────────────────────────────────────────────────────────

let map;

function initMap() {
  // Register the pmtiles protocol so a single static city file can stand in for
  // the hosted API. The map then works with no network at all — which matters
  // for an app whose utility layer helps you find internet.
  if (window.pmtiles) {
    const protocol = new pmtiles.Protocol();
    maplibregl.addProtocol("pmtiles", protocol.tile);
  }

  const useHosted = Boolean(CONFIG.PROTOMAPS_API_KEY);
  const style = buildStyle(
    useHosted
      ? { tiles: `https://api.protomaps.com/tiles/v4/{z}/{x}/{y}.mvt?key=${CONFIG.PROTOMAPS_API_KEY}` }
      : { pmtilesUrl: CONFIG.OFFLINE_PMTILES }
  );

  map = new maplibregl.Map({
    container: "map",
    style,
    center: [-73.9855, 40.758],
    zoom: 13,
    attributionControl: { compact: true },
  });

  // Rule 4: the user never has to pan or zoom, so leave room for the sheet.
  map.on("load", () => map.resize());
}

function padding() {
  return { top: 90, bottom: Math.round(window.innerHeight * 0.5), left: 40, right: 40 };
}

function frame(points) {
  const valid = points.filter((p) => Number.isFinite(p[0]) && Number.isFinite(p[1]));
  if (!valid.length) return;
  if (valid.length === 1) {
    map.easeTo({ center: valid[0], zoom: 15, padding: padding() });
    return;
  }
  const bounds = valid.reduce(
    (b, p) => b.extend(p),
    new maplibregl.LngLatBounds(valid[0], valid[0])
  );
  map.fitBounds(bounds, { padding: padding(), maxZoom: 16, duration: 600 });
}

function marker(lngLat, className, html) {
  const el = document.createElement("div");
  el.className = `mk ${className}`;
  el.innerHTML = html;
  return new maplibregl.Marker({ element: el }).setLngLat(lngLat).addTo(map);
}

function clearMarkers(kind) {
  S.markers[kind].forEach((m) => m.remove());
  S.markers[kind] = [];
}

// ── chrome ──────────────────────────────────────────────────────────────────

function toast(message, ms = 2600) {
  const el = $("toast");
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => (el.hidden = true), ms);
}

function setState(state) {
  $("sheet").dataset.state = state;
  document.querySelectorAll(".sheet section").forEach((section) => {
    section.hidden = section.dataset.view !== state;
  });
}

function applyStrings() {
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    el.textContent = t(el.dataset.i18n);
  });
  renderChips();
  renderModes();
  renderOnboard();
}

// ── explore ─────────────────────────────────────────────────────────────────

const FILTERS = [
  ["all", "explore", "🧭"],
  ["events", "events", "🎟"],
  ["eat", "eat", "🍽"],
  ["attraction", "attraction", "📸"],
  ["culture", "culture", "🏛"],
  ["market", "market", "🧺"],
  ["beach", "beach", "🏖"],
  ["hike", "hike", "🥾"],
  ["wifi", "wifi", "📶"],
];

function renderChips() {
  $("chips").innerHTML = FILTERS.map(
    ([key, label, glyph]) => `
      <button class="chip" role="tab" data-filter="${key}"
              aria-selected="${S.filter === key}">${glyph} ${t(label)}</button>`
  ).join("");
}

function renderModes() {
  const modes = S.city?.modes?.length ? S.city.modes : ["walk"];
  $("mode-toggle").innerHTML = modes
    .map(
      (mode) => `<button data-mode="${mode}" aria-pressed="${S.mode === mode}"
                         aria-label="${t(mode)}" title="${t(mode)}">${MODE_GLYPH[mode]}</button>`
    )
    .join("");
}

function distanceLabel(metres) {
  return metres < 950 ? `${Math.round(metres)} m` : `${(metres / 1000).toFixed(1)} km`;
}

async function loadResults() {
  const list = $("result-list");
  list.innerHTML = `<p class="empty">${t("loading")}…</p>`;
  clearMarkers("places");

  const lat = S.city.center_lat;
  const lng = S.city.center_lng;

  if (S.filter === "events") return renderEvents(await fetchEvents(lat, lng));

  // The wifi layer is a plain proximity lookup — you want the nearest signal,
  // not the most characterful one. Everything else is ranked by who you are.
  const { data, error } =
    S.filter === "wifi"
      ? await sb.rpc("nearby_places", {
          p_lat: lat, p_lng: lng, p_category: null,
          p_radius_m: 6000, p_wifi_only: true, p_limit: 40,
        })
      : await sb.rpc("recommended_places", {
          p_lat: lat, p_lng: lng, p_radius_m: 6000, p_limit: 40,
          p_category: S.filter === "all" ? null : S.filter,
        });

  if (error) {
    list.innerHTML = `<p class="empty">${error.message}</p>`;
    return;
  }
  renderPlaces(data || []);
}

async function fetchEvents(lat, lng) {
  const { data } = await sb.rpc("nearby_events", {
    p_lat: lat,
    p_lng: lng,
    p_radius_m: 12000,
    p_limit: 30,
  });
  return data || [];
}

function badges(place) {
  const out = [];
  if (place.has_wifi) {
    const free = place.wifi_fee === "no" || place.wifi_fee === null;
    // Glyph differs as well as colour — never colour alone (rule 3).
    out.push(
      free
        ? `<span class="badge free">📶 ${t("free")}</span>`
        : `<span class="badge paid">🔒 ${t("paid")}</span>`
    );
  }
  if (place.hidden_gem) out.push(`<span class="badge gem">💎 ${t("hiddenGem")}</span>`);
  if (place.wheelchair === "yes") out.push(`<span class="badge a11y">♿ ${t("accessible")}</span>`);
  return out.join(" ");
}

function renderPlaces(places) {
  const list = $("result-list");
  if (!places.length) {
    list.innerHTML = `<p class="empty">${t("noResults")}</p>`;
    return;
  }

  list.innerHTML = places
    .map(
      (place) => `
      <button class="row" data-lng="${place.lng}" data-lat="${place.lat}">
        <span class="row-glyph">${CATEGORY_GLYPH[place.category] || "📍"}</span>
        <span class="row-body">
          <span class="row-title">${place.name}</span>
          <span class="row-meta">${badges(place) || place.category}</span>
          ${place.reason ? `<span class="row-reason">${place.reason}</span>` : ""}
        </span>
        <span class="row-dist">${distanceLabel(place.distance_m)}</span>
      </button>`
    )
    .join("");

  // Rule 5: one marker type at a time on the explore screen.
  places.slice(0, 24).forEach((place) => {
    S.markers.places.push(
      marker([place.lng, place.lat], "mk-place", CATEGORY_GLYPH[place.category] || "📍")
    );
  });

  frame(places.slice(0, 24).map((p) => [p.lng, p.lat]));
}

function renderEvents(events) {
  const list = $("result-list");
  if (!events.length) {
    list.innerHTML = `<p class="empty">${t("noResults")}</p>`;
    return;
  }

  const when = new Intl.DateTimeFormat(getLocale(), { weekday: "short", hour: "numeric" });

  list.innerHTML = events
    .map(
      (event) => `
      <button class="row" data-lng="${event.lng}" data-lat="${event.lat}">
        <span class="row-glyph">🎟</span>
        <span class="row-body">
          <span class="row-title">${event.name}</span>
          <span class="row-meta">${when.format(new Date(event.starts_at))} · ${event.venue_name ?? ""}</span>
        </span>
        <span class="row-dist">${event.price_min_cents ? "$" + (event.price_min_cents / 100).toFixed(0) : t("free")}</span>
      </button>`
    )
    .join("");

  events.forEach((event) => {
    S.markers.places.push(marker([event.lng, event.lat], "mk-place", "🎟"));
  });
  frame(events.map((e) => [e.lng, e.lat]));
}

// ── onboarding ──────────────────────────────────────────────────────────────

function renderOnboard() {
  $("interest-chips").innerHTML = INTERESTS.map(
    (key) => `<button class="chip" data-interest="${key}"
        aria-selected="${S.prefs.interests.includes(key)}">${INTEREST_GLYPH[key]} ${t(key)}</button>`
  ).join("");

  $("crowd-toggle").innerHTML = CROWDS.map(
    (key) => `<button data-crowd="${key}" aria-pressed="${S.prefs.crowd === key}">${t(key)}</button>`
  ).join("");

  $("pace-toggle").innerHTML = PACES.map(
    (key) => `<button data-pace="${key}" aria-pressed="${S.prefs.pace === key}">${t(key)}</button>`
  ).join("");

  $("a11y-toggle").setAttribute(
    "aria-pressed",
    String(S.prefs.accessibility.includes("step_free"))
  );
}

async function savePreferences() {
  const { error } = await sb.rpc("save_my_preferences", {
    p_interests: S.prefs.interests,
    p_pace: S.prefs.pace,
    p_crowd: S.prefs.crowd,
    p_accessibility: S.prefs.accessibility,
  });
  if (error) return toast(error.message);
  setState("explore");
  loadResults();
}

async function loadPreferences() {
  const { data } = await sb
    .from("traveler_profiles")
    .select("interests, pace, crowd_preference, accessibility")
    .maybeSingle();

  if (!data) return false;
  S.prefs = {
    interests: data.interests || [],
    pace: data.pace || "balanced",
    crowd: data.crowd_preference || "local",
    accessibility: data.accessibility || [],
  };
  return true;
}

// ── self-guided: the app is the guide ───────────────────────────────────────

async function startMyRoute() {
  const button = $("start-route");
  button.disabled = true;

  try {
    const minutes = { relaxed: 180, balanced: 120, packed: 90 }[S.prefs.pace] ?? 120;
    const { data: ride, error } = await sb.rpc("start_self_guided", {
      p_lat: S.city.center_lat,
      p_lng: S.city.center_lng,
      p_mode: S.mode,
      p_duration_min: minutes,
      p_label: S.city.name,
    });
    if (error) throw error;

    S.ride = ride;
    await loadItinerary();
    subscribeToRide(ride.id);
    startTour();
    toast(`🎧 ${t("yourRoute")} · ${S.itinerary.length} ${t("stops")}`);
  } catch (error) {
    toast(error.message || String(error));
  } finally {
    button.disabled = false;
  }
}

// ── matching + live tracking ────────────────────────────────────────────────

async function findGuide() {
  const button = $("find-guide");
  button.disabled = true;

  try {
    const { data: ride, error } = await sb.rpc("match_guide", {
      p_lat: S.city.center_lat,
      p_lng: S.city.center_lng,
      p_mode: S.mode,
      p_theme: ["all", "wifi", "events"].includes(S.filter) ? null : S.filter,
      p_label: S.city.name,
    });
    if (error) throw error;

    S.ride = ride;
    await sb.rpc("plan_route", { p_ride_id: ride.id });
    await loadItinerary();
    await showGuideCard();
    subscribeToRide(ride.id);
    setState("matched");
  } catch (error) {
    toast(error.message || String(error));
  } finally {
    button.disabled = false;
  }
}

async function showGuideCard() {
  const { data } = await sb
    .from("profiles")
    .select("display_name, languages, guide_profiles(headline, rating, rides_completed, verified)")
    .eq("id", S.ride.guide_id)
    .single();

  const guide = data?.guide_profiles?.[0] || data?.guide_profiles || {};

  $("guide-card").innerHTML = `
    <div class="guide-avatar">${MODE_GLYPH[S.ride.mode]}</div>
    <div>
      <div class="guide-name">${data?.display_name ?? "Guide"} ${guide.verified ? "✓" : ""}</div>
      <div class="guide-line">${guide.headline ?? ""}</div>
      <div class="guide-line">⭐ ${guide.rating ?? "—"} · ${guide.rides_completed ?? 0} · ${(data?.languages || []).join(" · ")}</div>
    </div>
    <div class="eta"><b id="eta-value">${S.ride.eta_min ?? "—"}</b><span>${t("min")}</span></div>`;

  frame([
    [S.ride.pickup_lng, S.ride.pickup_lat],
    ...S.itinerary.map((stop) => [stop.lng, stop.lat]),
  ]);
}

function subscribeToRide(rideId) {
  S.channel?.unsubscribe();

  // Not polling. Postgres replicates each insert through Supabase Realtime, and
  // RLS is applied to the stream too — you only receive positions for a ride
  // you are actually on.
  S.channel = sb
    .channel(`ride:${rideId}`)
    .on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "ride_positions", filter: `ride_id=eq.${rideId}` },
      ({ new: position }) => onGuideMoved(position)
    )
    .on(
      "postgres_changes",
      { event: "UPDATE", schema: "public", table: "rides", filter: `id=eq.${rideId}` },
      ({ new: ride }) => onRideChanged(ride)
    )
    .subscribe();
}

function onGuideMoved(position) {
  const at = [position.lng, position.lat];

  if (!S.markers.guide) {
    // On a self-guided route the moving dot is the traveler, not a guide, so it
    // gets the universally-understood blue dot instead of an avatar.
    const selfGuided = !S.ride?.guide_id;
    S.markers.guide = selfGuided
      ? marker(at, "mk-me", "")
      : marker(at, "mk-guide", MODE_GLYPH[S.ride?.mode] || "🚶");
  } else {
    S.markers.guide.setLngLat(at);
  }

  // Recompute the ETA from the live position rather than trusting the estimate
  // we stored at match time.
  const target = nextTarget();
  if (target) {
    const speed = { walk: 1.4, boat: 5.0, drive: 8.3 }[S.ride.mode] ?? 1.4;
    const minutes = Math.max(1, Math.ceil(haversine(at, target) / speed / 60));
    const el = $("eta-value");
    if (el) el.textContent = minutes;
  }

  map.easeTo({ center: at, duration: 900, padding: padding() });
}

async function onRideChanged(ride) {
  S.ride = { ...S.ride, ...ride };
  if (ride.status === "active" && $("sheet").dataset.state !== "tour") startTour();
  if (ride.status === "active" || ride.status === "completed") await loadItinerary();
  if (ride.status === "completed") {
    toast(`✓ ${t("tourComplete")}`);
    setState("explore");
  }
}

function nextTarget() {
  const next = S.itinerary.find((stop) => !stop.arrived_at);
  if (next) return [next.lng, next.lat];
  return S.ride ? [S.ride.pickup_lng, S.ride.pickup_lat] : null;
}

function haversine([lng1, lat1], [lng2, lat2]) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dPhi = toRad(lat2 - lat1);
  const dLam = toRad(lng2 - lng1);
  const a =
    Math.sin(dPhi / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLam / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// ── tour ────────────────────────────────────────────────────────────────────

async function loadItinerary() {
  if (!S.ride) return;
  const { data } = await sb.rpc("ride_itinerary", {
    p_ride_id: S.ride.id,
    p_locale: getLocale(),
  });
  S.itinerary = data || [];
  if ($("sheet").dataset.state === "tour") renderTour();
}

function startTour() {
  setState("tour");
  renderTour();
}

function renderTour() {
  const done = S.itinerary.filter((stop) => stop.arrived_at).length;
  $("tour-head").textContent = `${done}/${S.itinerary.length} ${t("stops")}`;

  const nextSeq = S.itinerary.find((stop) => !stop.arrived_at)?.seq;

  $("stop-list").innerHTML = S.itinerary
    .map((stop) => {
      const cls = stop.arrived_at ? "done" : stop.seq === nextSeq ? "next" : "";
      return `
      <div class="row">
        <span class="stop-num ${cls}">${stop.arrived_at ? "✓" : stop.seq}</span>
        <span class="row-body">
          <span class="row-title">${stop.name}</span>
          <span class="row-meta">${CATEGORY_GLYPH[stop.category] || "📍"} ${stop.category}${
            stop.has_wifi ? ` · <span class="badge free">📶 ${t("free")}</span>` : ""
          }</span>
        </span>
        ${
          stop.audio_url
            ? `<button class="listen" data-audio="${stop.audio_url}"
                       aria-pressed="${S.playing === stop.audio_url}"
                       aria-label="${t("listen")}">▶</button>`
            : ""
        }
      </div>`;
    })
    .join("");

  clearMarkers("stops");
  S.itinerary.forEach((stop) => {
    const cls = stop.seq === nextSeq ? "mk-stop next" : "mk-stop";
    S.markers.stops.push(marker([stop.lng, stop.lat], cls, stop.arrived_at ? "✓" : stop.seq));
  });
}

function playNarration(url) {
  const audio = $("narration");
  if (S.playing === url) {
    audio.pause();
    S.playing = null;
  } else {
    audio.src = url;
    audio.play().catch(() => toast("Audio blocked — tap once more"));
    S.playing = url;
  }
  renderTour();
}

// ── cities & locale ─────────────────────────────────────────────────────────

let cities = [];

async function loadCities() {
  const { data } = await sb.from("cities").select("*").order("name");
  cities = data || [];
  S.city = cities.find((c) => c.slug === CONFIG.DEFAULT_CITY) || cities[0];
  applyCity();
}

function applyCity() {
  if (!S.city) return;
  $("city-name").textContent = S.city.name;
  $("city-flag").textContent = { nyc: "🗽", sju: "🌴", vce: "🛶" }[S.city.slug] ?? "📍";
  S.mode = S.city.default_mode;
  renderModes();
  map.jumpTo({ center: [S.city.center_lng, S.city.center_lat], zoom: 13 });
  // Don't fetch a feed behind the onboarding sheet — it would be unpersonalised
  // and immediately thrown away.
  if ($("sheet").dataset.state !== "onboard") loadResults();
}

function cycleCity() {
  const index = cities.findIndex((c) => c.slug === S.city.slug);
  S.city = cities[(index + 1) % cities.length];
  applyCity();
  toast(S.city.tagline || S.city.name, 3400);
}

function cycleLocale() {
  const codes = Object.keys(LOCALES);
  const next = codes[(codes.indexOf(getLocale()) + 1) % codes.length];
  setLocale(next);
  $("lang-btn").textContent = LOCALES[next].flag;
  applyStrings();
  loadResults();
  loadItinerary();
}

// ── wiring ──────────────────────────────────────────────────────────────────

function wire() {
  $("chips").addEventListener("click", (event) => {
    const chip = event.target.closest("[data-filter]");
    if (!chip) return;
    S.filter = chip.dataset.filter;
    renderChips();
    loadResults();
  });

  $("mode-toggle").addEventListener("click", (event) => {
    const button = event.target.closest("[data-mode]");
    if (!button) return;
    S.mode = button.dataset.mode;
    renderModes();
  });

  $("result-list").addEventListener("click", (event) => {
    const row = event.target.closest(".row");
    if (!row) return;
    frame([[Number(row.dataset.lng), Number(row.dataset.lat)]]);
  });

  $("stop-list").addEventListener("click", (event) => {
    const button = event.target.closest("[data-audio]");
    if (button) playNarration(button.dataset.audio);
  });

  $("interest-chips").addEventListener("click", (event) => {
    const chip = event.target.closest("[data-interest]");
    if (!chip) return;
    const key = chip.dataset.interest;
    const at = S.prefs.interests.indexOf(key);
    if (at >= 0) S.prefs.interests.splice(at, 1);
    else S.prefs.interests.push(key);
    renderOnboard();
  });

  $("crowd-toggle").addEventListener("click", (event) => {
    const button = event.target.closest("[data-crowd]");
    if (!button) return;
    S.prefs.crowd = button.dataset.crowd;
    renderOnboard();
  });

  $("pace-toggle").addEventListener("click", (event) => {
    const button = event.target.closest("[data-pace]");
    if (!button) return;
    S.prefs.pace = button.dataset.pace;
    renderOnboard();
  });

  $("a11y-toggle").addEventListener("click", () => {
    S.prefs.accessibility = S.prefs.accessibility.includes("step_free") ? [] : ["step_free"];
    renderOnboard();
  });

  $("save-prefs").addEventListener("click", savePreferences);
  $("start-route").addEventListener("click", startMyRoute);
  $("find-guide").addEventListener("click", findGuide);
  $("start-tour").addEventListener("click", startTour);
  $("city-btn").addEventListener("click", cycleCity);
  $("lang-btn").addEventListener("click", cycleLocale);
  $("recenter-btn").addEventListener("click", () =>
    frame(
      S.markers.guide
        ? [S.markers.guide.getLngLat().toArray()]
        : [[S.city.center_lng, S.city.center_lat]]
    )
  );

  $("cancel-ride").addEventListener("click", async () => {
    if (S.ride) await sb.from("rides").update({ status: "cancelled" }).eq("id", S.ride.id);
    resetRide();
  });

  $("end-tour").addEventListener("click", async () => {
    if (S.ride) await sb.from("rides").update({ status: "completed" }).eq("id", S.ride.id);
    resetRide();
  });

  $("narration").addEventListener("ended", () => {
    S.playing = null;
    renderTour();
  });
}

function resetRide() {
  S.channel?.unsubscribe();
  S.channel = null;
  S.ride = null;
  S.itinerary = [];
  clearMarkers("stops");
  S.markers.guide?.remove();
  S.markers.guide = null;
  setState("explore");
  loadResults();
}

// ── boot ────────────────────────────────────────────────────────────────────

async function boot() {
  setLocale(CONFIG.DEFAULT_LOCALE);
  $("lang-btn").textContent = LOCALES[getLocale()].flag;

  initMap();
  wire();
  applyStrings();

  // Anonymous sign-in: no login screen, but a real auth.uid(), so RLS is
  // genuinely enforced rather than simulated.
  const { data: session } = await sb.auth.getSession();
  if (!session?.session) {
    const { error } = await sb.auth.signInAnonymously();
    if (error) toast("Enable Anonymous sign-in in Supabase → Auth → Providers", 6000);
  }

  await loadCities();

  // A returning traveler skips straight to their feed; a new one answers three
  // questions first, because an unpersonalised recommendation is just a list.
  const known = await loadPreferences();
  renderOnboard();
  setState(known ? "explore" : "onboard");
  if (known) loadResults();
}

boot();
