#!/usr/bin/env python3
"""Attach real TikTok / Instagram posts to experiences — by reference, not by file.

    # you already have a mapping
    python scripts/attach_media.py --map media.csv

    # you have a folder of downloads and want the URLs back out of the filenames
    python scripts/attach_media.py --scan ~/tokyo-clips --dry-run

    # confirm a URL resolves before committing it
    python scripts/attach_media.py --check https://www.tiktok.com/@user/video/7123456789

WHY THIS INSTEAD OF UPLOADING THE FILES
---------------------------------------
Downloaded TikTok and Instagram videos cannot be rehosted — it breaches both
platforms' terms and the creator's copyright, and "it's just a demo" stops being
true the moment there is money or an audience attached.

Embedding loses you nothing. The oEmbed endpoints return the real post, played
by the real platform player, at better quality than a re-encode, with the
creator credited. Both are keyless as of 2026. What you need out of your
downloads folder is therefore the POST URLS, not the bytes.

The files themselves should not be committed, deployed, or uploaded anywhere.
.gitignore already excludes the usual folder names.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path
from urllib.parse import quote

import requests

from _common import insert, require_env, select

TIKTOK_OEMBED = "https://www.tiktok.com/oembed"
INSTAGRAM_OEMBED = "https://graph.facebook.com/v20.0/instagram_oembed"

# Most downloaders keep the post id in the filename. TikTok ids are 19 digits;
# Instagram shortcodes are 11 characters of base64-ish text.
TIKTOK_ID = re.compile(r"(\d{18,20})")
INSTAGRAM_CODE = re.compile(r"(?:reel|p)[_-]?([A-Za-z0-9_-]{11})")


def classify(url: str) -> str | None:
    if "tiktok.com" in url:
        return "tiktok"
    if "instagram.com" in url:
        return "instagram"
    return None


def url_from_filename(path: Path) -> str | None:
    """Reconstruct a post URL from a downloaded file's name.

    A TikTok URL only needs the numeric id to resolve — the @handle in the path
    is ignored by the endpoint, so a placeholder works.
    """
    stem = path.stem

    match = INSTAGRAM_CODE.search(stem)
    if match:
        return f"https://www.instagram.com/reel/{match.group(1)}/"

    match = TIKTOK_ID.search(stem)
    if match:
        return f"https://www.tiktok.com/@placeholder/video/{match.group(1)}"

    return None


def resolve(url: str) -> dict | None:
    """Ask the official endpoint for the thumbnail and the creator's name.

    Attribution is not decoration: rendering the creator's name and linking back
    is the condition under which embedding is permitted.
    """
    kind = classify(url)
    if not kind:
        return None

    endpoint = TIKTOK_OEMBED if kind == "tiktok" else INSTAGRAM_OEMBED
    try:
        response = requests.get(f"{endpoint}?url={quote(url, safe='')}", timeout=20)
        if response.status_code != 200:
            return None
        payload = response.json()
    except (requests.RequestException, ValueError):
        return None

    return {
        "kind": kind,
        "license": "oembed",
        "source_url": url,
        "thumbnail_url": payload.get("thumbnail_url"),
        "alt_text": payload.get("title"),
        "attribution_name": payload.get("author_name"),
        "attribution_url": payload.get("author_url"),
    }


def load_map(path: Path) -> list[tuple[str, str]]:
    """CSV of experience_id,post_url — with or without a header row."""
    pairs: list[tuple[str, str]] = []
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle):
            if len(row) < 2:
                continue
            experience_id, url = row[0].strip(), row[1].strip()
            if experience_id.lower() in {"experience_id", "id"}:
                continue          # header
            pairs.append((experience_id, url))
    return pairs


def cmd_scan(folder: Path) -> int:
    """Turn a downloads folder into a CSV skeleton to fill in."""
    videos = sorted(
        p for p in folder.rglob("*")
        if p.suffix.lower() in {".mp4", ".mov", ".webm", ".mkv"}
    )
    if not videos:
        print(f"no video files under {folder}")
        return 1

    experiences = select("experiences", {"select": "id,name,category", "order": "name"})
    print(f"# {len(videos)} files · {len(experiences)} experiences")
    print("# Paste into media.csv, match each URL to an experience, then:")
    print("#   python scripts/attach_media.py --map media.csv")
    print("#")
    print("# experience_id,post_url,  # source file")

    unresolved = 0
    for video in videos:
        url = url_from_filename(video)
        if url:
            print(f",{url},  # {video.name}")
        else:
            unresolved += 1
            print(f",,  # {video.name}  ← no post id in filename")

    print("#")
    print("# experiences to choose from:")
    for e in experiences:
        print(f"#   {e['id']}  {e['category']:<12} {e['name']}")

    if unresolved:
        print(f"#\n# {unresolved} file(s) had no recoverable id — find those posts by")
        print("# searching the creator or caption, and paste the URL by hand.")
    return 0


def cmd_check(url: str) -> int:
    data = resolve(url)
    if not data:
        print(f"✗ did not resolve: {url}")
        print("  the post may be private, deleted, or region-locked")
        return 1
    print(f"✓ {data['kind']}")
    print(f"  creator   {data['attribution_name']}")
    print(f"  thumbnail {data['thumbnail_url']}")
    return 0


def cmd_map(path: Path, dry_run: bool) -> int:
    pairs = load_map(path)
    if not pairs:
        print(f"no usable rows in {path}")
        return 1

    attached = failed = 0
    for experience_id, url in pairs:
        data = resolve(url)
        if not data:
            print(f"  ✗ {url[:60]} — did not resolve")
            failed += 1
            continue

        if dry_run:
            print(f"  · {data['attribution_name']:<22} → {experience_id[:8]}")
        else:
            insert("experience_media", {
                "experience_id": experience_id,
                **data,
                "position": 0,
                "is_primary": True,
            })
            print(f"  ✓ {data['attribution_name']:<22} → {experience_id[:8]}")
        attached += 1

    print(f"\n{attached} attached, {failed} failed"
          + (" (dry run — nothing written)" if dry_run else ""))
    return 0 if failed == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Attach TikTok/Instagram posts by reference.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--map", type=Path, help="CSV: experience_id,post_url")
    group.add_argument("--scan", type=Path, help="folder of downloads → CSV skeleton")
    group.add_argument("--check", type=str, help="test one post URL")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.check:
        return cmd_check(args.check)

    require_env()
    if args.scan:
        return cmd_scan(args.scan)
    return cmd_map(args.map, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
