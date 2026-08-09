#!/usr/bin/env python3
"""Drive a guide along their route — the second device, without a second device.

The guide side of Roam is simulated for the demo. This walks (or drives, or
boats) a guide from where they are to the traveler, then along the tour stops,
writing a position roughly once a second. Postgres replicates each insert to
Supabase Realtime, which pushes it to the browser, which moves the dot.

    python scripts/simulate_guide.py --ride <uuid>
    python scripts/simulate_guide.py --ride <uuid> --speed 6   # 6x for rehearsal

Nothing here is demo-only plumbing: this is exactly the shape of the writes a
real guide's phone would make.
"""

from __future__ import annotations

import argparse
import math
import sys
import time
from datetime import datetime, timezone

from _common import insert, require_env, rpc, select, update, wkt


def now_iso() -> str:
    """PostgREST sends JSON, so a timestamp has to be a real ISO string —
    the literal text "now()" is not a value Postgres can cast."""
    return datetime.now(timezone.utc).isoformat()

# Metres per second per mode — matches mode_speed_mps() in 0002_functions.sql.
SPEED_MPS = {"walk": 1.4, "boat": 5.0, "drive": 8.3}
TICK_SECONDS = 1.0
ARRIVAL_RADIUS_M = 25.0


def haversine_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Distance in metres between two (lng, lat) points."""
    lng1, lat1 = a
    lng2, lat2 = b
    radius = 6_371_000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    h = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(h))


def bearing_deg(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Initial compass bearing from a to b, for the heading cone on the map."""
    lng1, lat1 = a
    lng2, lat2 = b
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dlambda = math.radians(lng2 - lng1)
    y = math.sin(dlambda) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlambda)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def lerp(a: tuple[float, float], b: tuple[float, float], t: float) -> tuple[float, float]:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def leg(
    ride_id: str,
    start: tuple[float, float],
    end: tuple[float, float],
    speed_mps: float,
    multiplier: float,
    label: str,
) -> tuple[float, float]:
    """Walk one straight leg, emitting a position per tick.

    Straight-line interpolation is deliberate. A routing API would add a network
    dependency and a failure mode, and at demo zoom the difference is invisible.
    """
    distance = haversine_m(start, end)
    if distance < 1:
        return end

    heading = bearing_deg(start, end)
    step_m = speed_mps * multiplier * TICK_SECONDS
    steps = max(1, int(distance / step_m))
    print(f"  → {label}: {distance:,.0f} m, ~{steps} ticks")

    for i in range(1, steps + 1):
        lng, lat = lerp(start, end, i / steps)
        insert(
            "ride_positions",
            {
                "ride_id": ride_id,
                "actor": "guide",
                "point": wkt(lng, lat),
                "heading": heading,
                "speed_mps": speed_mps,
            },
        )
        time.sleep(TICK_SECONDS)

    return end


def main() -> int:
    parser = argparse.ArgumentParser(description="Simulate a Roam guide.")
    parser.add_argument("--ride", required=True, help="ride uuid")
    parser.add_argument("--speed", type=float, default=1.0, help="playback multiplier")
    parser.add_argument(
        "--from-stop", type=int, default=0, help="resume the tour at this stop number"
    )
    args = parser.parse_args()

    require_env()

    rides = select("rides", {"id": f"eq.{args.ride}", "select": "*"})
    if not rides:
        sys.exit(f"ride {args.ride} not found")
    ride = rides[0]

    mode = ride["mode"]
    speed = SPEED_MPS.get(mode, 1.4)
    pickup = (ride["pickup_lng"], ride["pickup_lat"])
    self_guided = ride.get("guide_id") is None

    if self_guided:
        # The app is the guide: there is nobody to come and collect you, so the
        # walk starts where you are.
        here = pickup
    else:
        guides = select(
            "guide_status", {"guide_id": f"eq.{ride['guide_id']}", "select": "lat,lng"}
        )
        if not guides or guides[0]["lat"] is None:
            sys.exit("guide has no last known position — is guide_status seeded?")
        here = (guides[0]["lng"], guides[0]["lat"])

    itinerary = rpc("ride_itinerary", {"p_ride_id": args.ride}) or []
    kind = "self-guided" if self_guided else "with guide"
    print(f"ride {args.ride[:8]} · {kind} · mode={mode} · {len(itinerary)} stops · {args.speed}x")

    # 1. the guide travels to the traveler — skipped when there isn't one
    if not self_guided:
        update("rides", {"id": args.ride}, {"status": "enroute"})
        here = leg(args.ride, here, pickup, speed, args.speed, "to pickup")

    # 2. the tour itself
    update("rides", {"id": args.ride}, {"status": "active", "started_at": now_iso()})
    for stop in itinerary[args.from_stop :]:
        target = (stop["lng"], stop["lat"])
        here = leg(args.ride, here, target, speed, args.speed, f"stop {stop['seq']} · {stop['name']}")
        update(
            "ride_stops",
            {"ride_id": args.ride, "seq": stop["seq"]},
            {"arrived_at": now_iso()},
        )
        print(f"  ✓ arrived at {stop['name']}")

    update("rides", {"id": args.ride}, {"status": "completed", "ended_at": now_iso()})
    print("tour complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
