#!/usr/bin/env python3
"""Generate stop narration with ElevenLabs and upload it to Supabase Storage.

Audio is the interface, not a feature. A traveler is walking with their hands
full and their eyes on the street — a screen is the wrong surface. It is also
the honest accessibility story: low literacy, low vision, or simply an
unfamiliar script all stop mattering when the guide talks to you.

This runs at BUILD time. The demo plays cached MP3s out of Storage, so nothing
reaches ElevenLabs while judges are watching.

    python scripts/narrate.py --city nyc
    python scripts/narrate.py --city vce --locales en,es
    python scripts/narrate.py --city sju --dry-run     # print scripts, spend nothing
"""

from __future__ import annotations

import argparse
import os
import sys

import requests

from _common import SERVICE_KEY, SUPABASE_URL, insert, require_env, select

ELEVEN_KEY = os.getenv("ELEVENLABS_API_KEY") or ""
VOICE_ID = os.getenv("ELEVENLABS_VOICE_ID") or "21m00Tcm4TlvDq8ikWAM"  # Rachel, a premade voice
MODEL_ID = "eleven_multilingual_v2"  # 29 languages, one voice
BUCKET = "narration"

# Kept short on purpose: roughly 20 seconds spoken. Long enough to be worth
# hearing, short enough that a traveler doesn't stand still on a pavement.
INTROS = {
    "en": "You're standing at {name}.",
    "es": "Estás frente a {name}.",
    "zh": "你现在来到了{name}。",
    "hi": "आप {name} पर हैं।",
    "ar": "أنت الآن عند {name}.",
}


def build_script(place: dict, locale: str) -> str:
    """One paragraph: where you are, why it matters, what to notice."""
    intro = INTROS.get(locale, INTROS["en"]).format(name=place["name"])
    body = place.get("blurb") or place.get("known_for") or ""
    if place.get("hidden_gem"):
        tail = {
            "en": "Most visitors walk straight past this one.",
            "es": "La mayoría de los visitantes pasa de largo.",
            "zh": "大多数游客都会错过这里。",
            "hi": "ज़्यादातर पर्यटक इसे देखे बिना निकल जाते हैं।",
            "ar": "معظم الزوار يمرون من هنا دون أن يلاحظوها.",
        }.get(locale, "")
        body = f"{body} {tail}".strip()
    return f"{intro} {body}".strip()


def synthesize(text: str, locale: str) -> bytes:
    response = requests.post(
        f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}",
        headers={"xi-api-key": ELEVEN_KEY, "Content-Type": "application/json"},
        json={
            "text": text,
            "model_id": MODEL_ID,
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
        },
        timeout=120,
    )
    response.raise_for_status()
    return response.content


def upload(path: str, audio: bytes) -> str:
    """Store the MP3 and return its public URL."""
    response = requests.post(
        f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{path}",
        headers={
            "apikey": SERVICE_KEY,
            "Authorization": f"Bearer {SERVICE_KEY}",
            "Content-Type": "audio/mpeg",
            "x-upsert": "true",
        },
        data=audio,
        timeout=120,
    )
    response.raise_for_status()
    return f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{path}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Pre-generate Roam narration.")
    parser.add_argument("--city", required=True, help="city slug: nyc · sju · vce")
    parser.add_argument("--locales", default="en,es,zh,hi,ar")
    parser.add_argument("--limit", type=int, default=None, help="cap places, to watch credits")
    parser.add_argument("--dry-run", action="store_true", help="print scripts, call nothing")
    args = parser.parse_args()

    require_env()
    locales = [code.strip() for code in args.locales.split(",") if code.strip()]

    cities = select("cities", {"slug": f"eq.{args.city}", "select": "id,name"})
    if not cities:
        sys.exit(f"unknown city '{args.city}'")
    city = cities[0]

    params = {
        "city_id": f"eq.{city['id']}",
        "select": "id,name,blurb,known_for,hidden_gem",
        "order": "hidden_gem.desc,name",
    }
    if args.limit:
        params["limit"] = str(args.limit)
    places = select("places", params)

    total_chars = 0
    print(f"{city['name']}: {len(places)} places × {len(locales)} locales")

    if not args.dry_run and not ELEVEN_KEY:
        sys.exit("ELEVENLABS_API_KEY is not set")

    for place in places:
        for locale in locales:
            script = build_script(place, locale)
            total_chars += len(script)

            if args.dry_run:
                print(f"  [{locale}] {place['name']}: {script}")
                continue

            audio = synthesize(script, locale)
            url = upload(f"{args.city}/{place['id']}/{locale}.mp3", audio)
            insert(
                "narrations",
                {
                    "subject_type": "place",
                    "subject_id": place["id"],
                    "locale": locale,
                    "script": script,
                    "audio_url": url,
                    "voice_id": VOICE_ID,
                },
                upsert=True,
            )
            print(f"  ✓ [{locale}] {place['name']}")

    print(f"\n{total_chars:,} characters" + (" (dry run — nothing spent)" if args.dry_run else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
