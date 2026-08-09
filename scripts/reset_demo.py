#!/usr/bin/env python3
"""Wipe rides back to a clean pre-demo state.

Judges arrive in waves and you will run this flow a dozen times. This clears
every ride, stop, and position, and parks each guide back at their home point
so the next run looks exactly like the first one. It does not touch cities,
places, events, or narration audio.

    python scripts/reset_demo.py
"""

from __future__ import annotations

import requests

from _common import SERVICE_KEY, SUPABASE_URL, require_env, select, update, wkt


def delete_all(table: str) -> None:
    """PostgREST refuses an unfiltered delete, so match every row explicitly."""
    response = requests.delete(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers={
            "apikey": SERVICE_KEY,
            "Authorization": f"Bearer {SERVICE_KEY}",
            "Prefer": "return=minimal",
        },
        params={"id": "not.is.null"},
        timeout=30,
    )
    response.raise_for_status()


def main() -> int:
    require_env()

    # ride_stops and ride_positions cascade from rides.
    delete_all("rides")
    print("cleared rides, stops, and positions")

    guides = select("guide_profiles", {"select": "profile_id,home_lat,home_lng"})
    for guide in guides:
        update(
            "guide_status",
            {"guide_id": guide["profile_id"]},
            {
                "last_point": wkt(guide["home_lng"], guide["home_lat"]),
                "is_online": True,
                "heading": None,
            },
        )
    print(f"parked {len(guides)} guides back at home")
    print("ready for the next run")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
