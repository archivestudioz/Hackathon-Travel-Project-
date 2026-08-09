// Roam basemap — deliberately almost empty.
//
// The clunkiness of most maps comes from labels: every street name, shop, and
// one-way arrow, at every zoom, in the local language. We strip ALL of them.
// That fixes two problems at once — visual noise, and the fact that a traveler
// cannot read the local script. The basemap becomes pure shape, and every label
// and colour on screen afterwards is ours.
//
// Layer names follow the Protomaps basemap vector schema.

export const PALETTE = {
  land: "#F4F1EC",
  water: "#C9DCE8",
  green: "#DCE8D4",
  building: "#E8E4DD",
  roadMinor: "#FFFFFF",
  roadMajor: "#FFFFFF",
  roadCasing: "#E2DCD2",
};

export function buildStyle({ tiles, pmtilesUrl }) {
  const source = pmtilesUrl
    ? { type: "vector", url: `pmtiles://${pmtilesUrl}`, attribution: "© OpenStreetMap" }
    : { type: "vector", tiles: [tiles], maxzoom: 15, attribution: "© OpenStreetMap" };

  return {
    version: 8,
    glyphs: "https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf",
    sources: { protomaps: source },
    layers: [
      { id: "bg", type: "background", paint: { "background-color": PALETTE.land } },
      {
        id: "earth",
        type: "fill",
        source: "protomaps",
        "source-layer": "earth",
        paint: { "fill-color": PALETTE.land },
      },
      {
        id: "green",
        type: "fill",
        source: "protomaps",
        "source-layer": "landuse",
        filter: ["in", ["get", "pmap:kind"], ["literal", ["park", "forest", "wood", "grass", "scrub", "farmland", "cemetery"]]],
        paint: { "fill-color": PALETTE.green },
      },
      {
        id: "water",
        type: "fill",
        source: "protomaps",
        "source-layer": "water",
        paint: { "fill-color": PALETTE.water },
      },
      {
        id: "buildings",
        type: "fill",
        source: "protomaps",
        "source-layer": "buildings",
        minzoom: 14,
        paint: { "fill-color": PALETTE.building, "fill-opacity": 0.7 },
      },
      // Exactly three road weights. Eight is what makes a map look busy.
      {
        id: "roads-casing",
        type: "line",
        source: "protomaps",
        "source-layer": "roads",
        paint: {
          "line-color": PALETTE.roadCasing,
          "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 10, 1.5, 16, 12],
        },
      },
      {
        id: "roads-minor",
        type: "line",
        source: "protomaps",
        "source-layer": "roads",
        filter: ["in", ["get", "pmap:kind"], ["literal", ["minor_road", "other", "path"]]],
        paint: {
          "line-color": PALETTE.roadMinor,
          "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 12, 0.6, 16, 6],
        },
      },
      {
        id: "roads-major",
        type: "line",
        source: "protomaps",
        "source-layer": "roads",
        filter: ["in", ["get", "pmap:kind"], ["literal", ["highway", "major_road", "medium_road"]]],
        paint: {
          "line-color": PALETTE.roadMajor,
          "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 10, 1.2, 16, 10],
        },
      },
      // No label layers. That is the whole point.
    ],
  };
}
