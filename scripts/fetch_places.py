#!/usr/bin/env python3
"""Bulk-load places from OpenStreetMap via Overpass.

Run this BEFORE demo day. Overpass is a shared community resource and it is
occasionally slow — exactly the kind of third-party call that should never sit
between a judge and your demo. The results are written straight into Postgres
and then frozen; the app reads the database.

    python scripts/fetch_places.py --city nyc
    python scripts/fetch_places.py --city vce --category eat

OSM carries far more traveler-critical data than most apps use. Free wifi,
wheelchair access, and opening hours all come out of the same query, which is
why the wifi layer and the accessibility filter cost almost nothing extra.
"""

from __future__ import annotations

import argparse
import sys
import time

import requests

from _common import insert, require_env, rpc, select, wkt

OVERPASS = "https://overpass-api.de/api/interpreter"

# category -> the OSM tag filters that mean it
CATEGORY_FILTERS = {
    "eat":        ['["amenity"~"restaurant|cafe|fast_food|bar|ice_cream"]'],
    "market":     ['["amenity"="marketplace"]', '["shop"="mall"]'],
    "culture":    ['["tourism"="museum"]', '["tourism"="gallery"]', '["historic"~"monument|memorial|castle|ruins"]'],
    "attraction": ['["tourism"~"attraction|artwork|viewpoint"]', '["leisure"="park"]'],
    "viewpoint":  ['["tourism"="viewpoint"]'],
    "beach":      ['["natural"="beach"]', '["leisure"="beach_resort"]'],
    "hike":       ['["route"="hiking"]', '["leisure"="nature_reserve"]'],
    # The unglamorous things a traveler abroad actually needs.
    "essentials": ['["amenity"~"toilets|drinking_water|pharmacy|atm|bank"]'],
}


def build_query(bbox: tuple[float, float, float, float], filters: list[str]) -> str:
    """bbox is (min_lat, min_lng, max_lat, max_lng) — Overpass's ordering."""
    box = ",".join(str(coordinate) for coordinate in bbox)
    parts = "".join(f"node{f}({box});way{f}({box});" for f in filters)
    return f"[out:json][timeout:90];({parts});out center tags;"


def to_row(element: dict, city_id: str, category: str) -> dict | None:
    tags = element.get("tags") or {}
    name = tags.get("name")
    if not name:
        return None  # unnamed nodes are noise on a map built for legibility

    lat = element.get("lat") or (element.get("center") or {}).get("lat")
    lng = element.get("lon") or (element.get("center") or {}).get("lon")
    if lat is None or lng is None:
        return None

    internet = tags.get("internet_access", "")
    has_wifi = internet in {"wlan", "yes"} or tags.get("wifi") == "yes"

    return {
        "city_id": city_id,
        "name": name,
        "category": category,
        "themes": [category],
        "point": wkt(lng, lat),
        "has_wifi": has_wifi,
        "wifi_fee": tags.get("internet_access:fee"),
        "wifi_ssid": tags.get("internet_access:ssid"),
        "wheelchair": tags.get("wheelchair"),
        "opening_hours": tags.get("opening_hours"),
        # Localness signals. A wikidata entry means somebody wrote an
        # encyclopaedia article about it, which is a good proxy for "the
        # guidebook already sent everyone here". A brand means it is a chain,
        # which is the opposite of a local experience anywhere on earth.
        "has_wikidata": "wikidata" in tags or "wikipedia" in tags,
        "is_chain": bool(tags.get("brand") or tags.get("brand:wikidata")),
        "source": "overpass",
        "osm_id": element.get("id"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Overpass → Roam places.")
    parser.add_argument("--city", required=True, help="city slug: nyc · sju · vce")
    parser.add_argument("--category", default=None, help="one category, or all if omitted")
    args = parser.parse_args()

    require_env()

    cities = select(
        "cities",
        {
            "slug": f"eq.{args.city}",
            "select": "id,name,bbox_min_lat,bbox_min_lng,bbox_max_lat,bbox_max_lng",
        },
    )
    if not cities:
        sys.exit(f"unknown city '{args.city}' — seed it first")
    city = cities[0]
    bbox = (
        city["bbox_min_lat"],
        city["bbox_min_lng"],
        city["bbox_max_lat"],
        city["bbox_max_lng"],
    )

    categories = [args.category] if args.category else list(CATEGORY_FILTERS)
    grand_total = 0

    for category in categories:
        filters = CATEGORY_FILTERS.get(category)
        if not filters:
            print(f"skipping unknown category '{category}'")
            continue

        print(f"{city['name']} · {category} …", end=" ", flush=True)
        response = requests.post(
            OVERPASS, data={"data": build_query(bbox, filters)}, timeout=180
        )
        response.raise_for_status()
        elements = response.json().get("elements", [])

        rows = [row for row in (to_row(e, city["id"], category) for e in elements) if row]
        # Overpass returns a node and a way for the same feature often enough
        # that deduping by osm_id here saves a lot of duplicate pins.
        unique = list({row["osm_id"]: row for row in rows}.values())

        if unique:
            for start in range(0, len(unique), 500):
                insert("places", unique[start : start + 500], upsert=True)
        grand_total += len(unique)
        print(f"{len(unique)} places")

        time.sleep(2)  # be a good Overpass citizen

    # Tourist density depends on every place around it, so localness can only be
    # scored once the whole city is in.
    scored = rpc("recompute_localness", {"p_city_id": city["id"]})
    print(f"\n{grand_total} places loaded for {city['name']} · localness scored for {scored}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
