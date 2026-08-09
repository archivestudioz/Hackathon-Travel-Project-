#!/usr/bin/env python3
"""Bulk-load experiences from OpenStreetMap via Overpass.

    python scripts/ingest_places.py --city tokyo
    python scripts/ingest_places.py --city kyoto --category food
    python scripts/ingest_places.py --city osaka --dry-run

RUN THIS BEFORE DEMO DAY. Overpass is a shared community resource and is
occasionally very slow — exactly the kind of third-party call that must never
sit between a judge and the product.

OSM carries far more than coordinates. Wheelchair access, opening hours, and
whether somewhere serves alcohol all arrive in the same query, which is why the
accessibility data and the under-18 filter cost nothing extra to support.
"""

from __future__ import annotations

import argparse
import sys
import time

import requests

from _common import get_city, insert, require_env, rpc, wkt

OVERPASS = "https://overpass-api.de/api/interpreter"

# Our category -> the OSM tag filters that mean it.
CATEGORY_FILTERS: dict[str, list[str]] = {
    "food":        ['["amenity"~"^(restaurant|cafe|fast_food|ice_cream)$"]'],
    "nightlife":   ['["amenity"~"^(bar|pub|nightclub|biergarten)$"]'],
    "market":      ['["amenity"="marketplace"]', '["shop"="department_store"]'],
    "culture":     ['["tourism"~"^(museum|gallery)$"]',
                    '["historic"~"^(monument|memorial|castle|ruins|temple|shrine)$"]',
                    '["amenity"~"^(place_of_worship|theatre)$"]'],
    "art":         ['["tourism"="artwork"]', '["amenity"="arts_centre"]'],
    "nature":      ['["leisure"~"^(park|garden|nature_reserve)$"]'],
    "hiking":      ['["route"="hiking"]', '["highway"="path"]["name"]'],
    "beach":       ['["natural"="beach"]'],
    "wellness":    ['["amenity"="public_bath"]', '["leisure"="sauna"]'],
    "shopping":    ['["shop"~"^(books|clothes|music|second_hand|vintage)$"]'],
    "anime":       ['["shop"~"^(anime|games|video_games)$"]', '["leisure"="amusement_arcade"]'],
    "attraction":  ['["tourism"~"^(attraction|viewpoint)$"]'],
}

# Tags that mean an experience is for adults. Mirrors is_adults_only() in the
# database — a sake tasting whose category is 'food' still has to carry this, or
# it reaches an under-18 feed.
ALCOHOL_TAGS = {"bar", "pub", "nightclub", "biergarten", "sake", "brewery", "winery", "alcohol"}


def build_query(bbox: tuple[float, float, float, float], filters: list[str]) -> str:
    """bbox is (min_lat, min_lng, max_lat, max_lng) — Overpass's ordering."""
    box = ",".join(str(c) for c in bbox)
    parts = "".join(f"node{f}({box});way{f}({box});" for f in filters)
    return f"[out:json][timeout:120];({parts});out center tags;"


def derive_tags(category: str, tags: dict) -> list[str]:
    out = {category}

    if tags.get("cuisine"):
        out.update(c.strip() for c in tags["cuisine"].split(";") if c.strip())

    amenity = tags.get("alcohol") or tags.get("amenity") or ""
    craft = tags.get("craft") or ""
    if amenity in ALCOHOL_TAGS or craft in ALCOHOL_TAGS or tags.get("alcohol") == "yes":
        out.add("alcohol")

    if tags.get("wheelchair") == "yes":
        out.add("step-free")

    return sorted(out)


def to_row(element: dict, city_id: str, category: str) -> dict | None:
    tags = element.get("tags") or {}
    # Unnamed nodes are noise in a feed built around named experiences.
    name = tags.get("name:en") or tags.get("name")
    if not name:
        return None

    lat = element.get("lat") or (element.get("center") or {}).get("lat")
    lng = element.get("lon") or (element.get("center") or {}).get("lon")
    if lat is None or lng is None:
        return None

    fee = (tags.get("fee") or "").lower()
    is_free = fee == "no" or category in {"nature", "hiking", "beach", "art"}

    return {
        "city_id": city_id,
        "name": name,
        "name_ja": tags.get("name:ja") or tags.get("name"),
        "short_description": tags.get("description") or f"{category.title()} in the neighbourhood.",
        "category": category,
        "tags": derive_tags(category, tags),
        "is_free": is_free,
        "price_yen": 0,
        "venue_name": name,
        "address": tags.get("addr:full") or tags.get("addr:street"),
        "point": wkt(lng, lat),
        "external_url": tags.get("website") or tags.get("contact:website"),
        # Localness signals, scored later by recompute_localness().
        "has_wikidata": "wikidata" in tags or "wikipedia" in tags,
        "is_chain": bool(tags.get("brand") or tags.get("brand:wikidata")),
        "source": "overpass",
        "osm_id": element.get("id"),
        "published": True,
    }


def attach_neighborhoods(city_id: str) -> int:
    """Snap each experience to its nearest neighbourhood centroid.

    Neighbourhood is the single strongest proximity signal the engine has — it
    produces "In Tenma, where you are staying" — so a row without one is
    effectively invisible to that part of scoring.
    """
    return rpc("attach_neighborhoods", {"p_city_id": city_id}) or 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Overpass → experiences.")
    parser.add_argument("--city", required=True, help="city slug: tokyo · kyoto · osaka")
    parser.add_argument("--category", default=None, help="one category, or all if omitted")
    parser.add_argument("--limit", type=int, default=None, help="cap rows per category")
    parser.add_argument("--dry-run", action="store_true", help="fetch and report, write nothing")
    args = parser.parse_args()

    require_env()
    city = get_city(args.city)
    bbox = (
        city["bbox_min_lat"], city["bbox_min_lng"],
        city["bbox_max_lat"], city["bbox_max_lng"],
    )

    categories = [args.category] if args.category else list(CATEGORY_FILTERS)
    total = 0

    for category in categories:
        filters = CATEGORY_FILTERS.get(category)
        if not filters:
            print(f"skipping unknown category '{category}'")
            continue

        print(f"{city['name_en']} · {category:11s} …", end=" ", flush=True)
        try:
            response = requests.post(
                OVERPASS, data={"data": build_query(bbox, filters)}, timeout=240
            )
            response.raise_for_status()
        except requests.RequestException as error:
            # One category failing must not lose the categories already loaded.
            print(f"FAILED ({error.__class__.__name__}) — skipping")
            continue

        elements = response.json().get("elements", [])
        rows = [r for r in (to_row(e, city["id"], category) for e in elements) if r]
        # Overpass frequently returns both a node and a way for one feature.
        unique = list({r["osm_id"]: r for r in rows}.values())
        if args.limit:
            unique = unique[: args.limit]

        if args.dry_run:
            print(f"{len(unique)} found (dry run)")
        else:
            for start in range(0, len(unique), 500):
                insert("experiences", unique[start : start + 500], on_conflict="osm_id")
            print(f"{len(unique)} loaded")

        total += len(unique)
        time.sleep(2)  # be a good Overpass citizen

    if args.dry_run:
        print(f"\n{total} rows would be loaded")
        return 0

    hooked = attach_neighborhoods(city["id"])
    # Tourist density depends on every other place nearby, so localness can only
    # be scored once the whole city is in.
    scored = rpc("recompute_localness", {"p_city_id": city["id"]})
    print(f"\n{total} experiences · {hooked} snapped to a neighbourhood · {scored} scored")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
