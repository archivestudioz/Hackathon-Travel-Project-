#!/usr/bin/env python3
"""Enrich experiences with Tavily, at build time.

    python scripts/enrich_tavily.py --city tokyo --limit 40
    python scripts/enrich_tavily.py --city kyoto --dry-run

Overpass gives coordinates and tags. It does not tell a traveler why somewhere
is worth an afternoon. Tavily searches the open web for that, and the result is
written into the database — so the app reads a column, never an API.

Two things it produces:

  short_description  the one line on a card
  local_signal       whether write-ups describe somewhere as a local haunt or
                     as a must-see landmark, nudging `locality` up or down

The locality nudge is capped deliberately. Web sentiment is a weak signal
compared to the geospatial tourist-density measure in recompute_localness(), so
it adjusts rather than overrides.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

import requests

from _common import get_city, require_env, select, update

TAVILY_URL = "https://api.tavily.com/search"
TAVILY_KEY = os.getenv("TAVILY_API_KEY") or ""

# Words that suggest a place belongs to the people who live there …
LOCAL_MARKERS = (
    "locals", "local favourite", "local favorite", "neighbourhood", "neighborhood",
    "hidden gem", "off the beaten", "under the radar", "hole in the wall",
    "no tourists", "where locals",
)
# … and words that suggest the guidebook already sent everyone.
TOURIST_MARKERS = (
    "must-see", "must see", "top 10", "top ten", "bucket list", "iconic",
    "world famous", "most popular", "tourist attraction", "crowded",
)


def search(query: str) -> dict:
    response = requests.post(
        TAVILY_URL,
        json={
            "api_key": TAVILY_KEY,
            "query": query,
            "search_depth": "basic",
            "max_results": 4,
            "include_answer": True,
        },
        timeout=45,
    )
    response.raise_for_status()
    return response.json()


def local_signal(results: dict) -> float:
    """-1.0 (very touristy) … +1.0 (very local), from marker counts."""
    corpus = " ".join(
        [(results.get("answer") or "")]
        + [r.get("content", "") for r in results.get("results", [])]
    ).lower()

    local = sum(corpus.count(m) for m in LOCAL_MARKERS)
    tourist = sum(corpus.count(m) for m in TOURIST_MARKERS)
    if local + tourist == 0:
        return 0.0
    return (local - tourist) / (local + tourist)


def first_sentence(text: str, limit: int = 150) -> str | None:
    text = " ".join((text or "").split())
    if not text:
        return None
    for stop in (". ", "! ", "? "):
        if stop in text[:limit + 40]:
            return text[: text.index(stop) + 1].strip()
    return (text[:limit].rstrip() + "…") if len(text) > limit else text


def main() -> int:
    parser = argparse.ArgumentParser(description="Tavily → experience descriptions.")
    parser.add_argument("--city", required=True)
    parser.add_argument("--limit", type=int, default=40, help="cap API calls")
    parser.add_argument("--only-empty", action="store_true",
                        help="skip rows that already have a description")
    parser.add_argument("--dry-run", action="store_true", help="print, call nothing, spend nothing")
    args = parser.parse_args()

    require_env() if args.dry_run else require_env("TAVILY_API_KEY")
    city = get_city(args.city)

    params = {
        "city_id": f"eq.{city['id']}",
        "select": "id,name,category,locality,description,venue_name",
        "order": "save_count.desc,name",
        "limit": str(args.limit),
    }
    if args.only_empty:
        params["description"] = "is.null"
    rows = select("experiences", params)

    print(f"{city['name_en']}: enriching {len(rows)} experiences")
    touched = 0

    for row in rows:
        query = f"{row['name']} {city['name_en']} Japan — what is it, is it worth visiting"

        if args.dry_run:
            print(f"  · would search: {query}")
            continue

        try:
            results = search(query)
        except requests.RequestException as error:
            # One failure must not lose the rows already enriched.
            print(f"  ✗ {row['name']}: {error.__class__.__name__}")
            continue

        signal = local_signal(results)
        blurb = first_sentence(results.get("answer") or "")

        patch: dict = {}
        if blurb:
            patch["description"] = results.get("answer")
            patch["short_description"] = blurb
        if signal:
            # Capped nudge: geospatial density is the stronger signal.
            adjusted = max(0.0, min(1.0, float(row["locality"]) + signal * 0.15))
            patch["locality"] = round(adjusted, 2)

        if patch:
            update("experiences", {"id": row["id"]}, patch)
            touched += 1
            arrow = "↑local" if signal > 0 else ("↓touristy" if signal < 0 else "·")
            print(f"  ✓ {row['name'][:44]:44s} {arrow}")

        time.sleep(0.4)  # stay well inside the rate limit

    print(f"\n{touched} enriched" + (" (dry run — nothing spent)" if args.dry_run else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
