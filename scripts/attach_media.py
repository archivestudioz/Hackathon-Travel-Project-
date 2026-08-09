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

from _common import insert, require_env, select, update

TIKTOK_OEMBED = "https://www.tiktok.com/oembed"
INSTAGRAM_OEMBED = "https://graph.facebook.com/v20.0/instagram_oembed"

# Most downloaders keep the post id in the filename. TikTok ids are 19 digits;
# Instagram shortcodes are 11 characters of base64-ish text.
TIKTOK_ID = re.compile(r"(?<!\d)(\d{18,20})(?!\d)")

# The separators are not optional, and that is the whole point. Written as
# `(?:reel|p)[_-]?(...)`, the bare `p` alternative matches the p in "snaptik"
# and the eleven characters after it become a shortcode — so every
# `snaptik_7404778374024957202_v3.mp4` silently resolved to the Instagram URL
# .../reel/tik_7404778/, which is not a post and never will be. Requiring a
# boundary before and a separator after kills it: TikTok downloads no longer
# look like Instagram reels.
INSTAGRAM_CODE = re.compile(
    r"(?:^|[/_\-\s])(?:reels?|p)[/_-]([A-Za-z0-9_-]{11})(?![A-Za-z0-9])"
)


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

    # TikTok first. A 19-digit run is far more specific than an 11-character
    # base64-ish blob, so testing it first means an ambiguous name resolves to
    # the more confident reading rather than the more permissive one.
    match = TIKTOK_ID.search(stem)
    if match:
        return f"https://www.tiktok.com/@placeholder/video/{match.group(1)}"

    match = INSTAGRAM_CODE.search(stem)
    if match:
        return f"https://www.instagram.com/reel/{match.group(1)}/"

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
    """Turn a downloads folder into a CSV skeleton to fill in.

    Runs with no credentials — the useful half is reading post ids out of
    filenames, and that needs nothing but the folder. If Supabase is
    configured it also lists the experiences to match against.
    """
    if not folder.exists():
        print(f"no such folder: {folder}")
        return 1

    videos = sorted(
        p for p in folder.rglob("*")
        if p.suffix.lower() in {".mp4", ".mov", ".webm", ".mkv"}
    )
    if not videos:
        print(f"no video files under {folder}")
        return 1

    try:
        experiences = select("experiences", {"select": "id,name,category", "order": "name"})
    except Exception:
        experiences = []

    print(f"# {len(videos)} files"
          + (f" · {len(experiences)} experiences" if experiences
             else " · (no Supabase credentials — filename recovery only)"))
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

    if experiences:
        print("#")
        print("# experiences to choose from:")
        for e in experiences:
            print(f"#   {e['id']}  {e['category']:<12} {e['name']}")

    if unresolved:
        print(f"#\n# {unresolved} file(s) had no recoverable id — find those posts by")
        print("# searching the creator or caption, and paste the URL by hand.")
    return 0


CATALOG_ENTRY = re.compile(
    r"^###\s+(\d+)\.\s+(.*?)$\n(?:.*?^-\s+\*\*Filename:\*\*\s+`(.+?)`)",
    re.MULTILINE | re.DOTALL,
)


def load_catalog(path: Path) -> dict[int, dict]:
    """Clip number → title and filename, straight out of the catalog markdown.

    The videos never have to be present. Everything this pipeline needs from a
    130MB folder is in the FILENAMES, and the catalog is a text file that
    already contains all 39 of them — so this runs identically whether the
    footage is on someone's laptop, in Drive, or deleted.
    """
    text = path.read_text(encoding="utf-8")
    clips: dict[int, dict] = {}
    for number, title, filename in CATALOG_ENTRY.findall(text):
        # findall with DOTALL is greedy across entries; re-scan each block for
        # the FIRST filename after the heading instead of trusting the span.
        clips[int(number)] = {"title": title.strip(), "filename": filename.strip()}
    return clips


def load_clip_map(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                continue
            rows.append({
                "clip": int(parts[0]),
                "verdict": parts[1].strip().upper(),
                "target": parts[2].strip(),
                "note": parts[3].strip() if len(parts) > 3 else "",
            })
    return rows


def cmd_catalog(catalog_path: Path, map_path: Path, dry_run: bool) -> int:
    """Attach the catalogued clips to the experiences they actually show.

    ATTACH and NEW rows resolve through the official oEmbed endpoints, which
    are keyless — so the creator's name and a link back come from the platform
    rather than from a guess, which is what makes the embed permitted.
    """
    if not catalog_path.exists():
        print(f"no catalog at {catalog_path}")
        return 1
    if not map_path.exists():
        print(f"no clip map at {map_path}")
        return 1

    clips = load_catalog(catalog_path)
    mapping = load_clip_map(map_path)
    if not clips or not mapping:
        print("catalog or map parsed empty — check the formats")
        return 1

    wanted = [r for r in mapping if r["verdict"] in {"ATTACH", "NEW"}]
    skipped = [r for r in mapping if r["verdict"] == "SKIP"]
    print(f"# {len(clips)} clips catalogued · {len(wanted)} in scope · {len(skipped)} skipped")

    try:
        experiences = select("experiences", {"select": "id,name"})
        by_name = {e["name"]: e["id"] for e in experiences}
    except Exception:
        by_name = {}
        if not dry_run:
            print("no Supabase credentials — run with --dry-run, or set them")
            return 1

    attached = failed = 0
    seen_primary: set[str] = set()

    for row in wanted:
        clip = clips.get(row["clip"])
        if not clip:
            print(f"  ✗ clip {row['clip']} is in the map but not in the catalog")
            failed += 1
            continue

        url = url_from_filename(Path(clip["filename"]))
        if not url:
            # Caption-derived filename with no recoverable id. Not a failure —
            # find the post by searching the creator, then add it via --map.
            print(f"  · clip {row['clip']:>2}  no post id in filename — {clip['title'][:44]}")
            continue

        experience_id = by_name.get(row["target"])
        if by_name and not experience_id:
            print(f"  ✗ clip {row['clip']:>2}  no experience named {row['target']!r}"
                  " — run seed_catalog.sql first")
            failed += 1
            continue

        # A clip listed twice against one experience is a second angle, not a
        # replacement: the first becomes primary, the rest are extra media.
        is_primary = row["target"] not in seen_primary
        seen_primary.add(row["target"])

        if dry_run:
            print(f"  · clip {row['clip']:>2}  {'primary' if is_primary else 'extra  '}"
                  f"  {url}  →  {row['target']}")
            attached += 1
            continue

        data = resolve(url)
        if not data:
            print(f"  ✗ clip {row['clip']:>2}  did not resolve — private, deleted, or region-locked")
            failed += 1
            continue

        if is_primary:
            existing = update(
                "experience_media",
                {"experience_id": experience_id, "is_primary": "true"},
                data,
            )
            if not existing:
                insert("experience_media", {
                    "experience_id": experience_id, **data,
                    "position": 0, "is_primary": True,
                })
        else:
            insert("experience_media", {
                "experience_id": experience_id, **data,
                "position": 1, "is_primary": False,
            })
        print(f"  ✓ clip {row['clip']:>2}  {data['attribution_name']:<20} → {row['target']}")
        attached += 1

    print(f"\n{attached} attached, {failed} failed"
          + (" (dry run — nothing written)" if dry_run else ""))

    # Say what was dropped. A report that only lists the hits reads as "we used
    # all 39", and we used about a quarter.
    reasons: dict[str, int] = {}
    for row in skipped:
        key = ("out of scope" if "out of scope" in row["note"]
               else "not Japan" if "not Japan" in row["note"]
               else "venue unidentifiable")
        reasons[key] = reasons.get(key, 0) + 1
    print(f"{len(skipped)} skipped: "
          + " · ".join(f"{n} {k}" for k, n in sorted(reasons.items())))
    return 0 if failed == 0 else 1


def cmd_check(url: str) -> int:
    """Diagnose one URL, and say WHICH failure it was.

    resolve() collapses every failure to None, which is right for a bulk run
    and useless when you are debugging one post: a corporate proxy or a
    sandbox that blocks tiktok.com produces exactly the same silence as a
    deleted video, and you go looking for the wrong problem.
    """
    kind = classify(url)
    if not kind:
        print(f"✗ not a TikTok or Instagram URL: {url}")
        return 1

    endpoint = TIKTOK_OEMBED if kind == "tiktok" else INSTAGRAM_OEMBED
    try:
        response = requests.get(f"{endpoint}?url={quote(url, safe='')}", timeout=20)
    except requests.RequestException as exc:
        print(f"✗ could not reach {endpoint}")
        print(f"  {type(exc).__name__}: {exc}")
        print("  NETWORK problem, not a bad post — check the proxy, then retry.")
        return 1

    if response.status_code != 200:
        print(f"✗ {endpoint} returned {response.status_code}")
        print("  the post is private, deleted, or region-locked")
        return 1

    try:
        payload = response.json()
    except ValueError:
        print(f"✗ {endpoint} returned {response.status_code} but not JSON")
        print("  usually a captcha or consent interstitial — retry from a normal network")
        return 1

    print(f"✓ {kind}")
    print(f"  creator   {payload.get('author_name')}")
    print(f"  thumbnail {payload.get('thumbnail_url')}")
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
            attached += 1
            continue

        # The seed already gives every experience one placeholder primary row,
        # and a partial unique index allows only one primary per experience —
        # so replace that row rather than inserting a second one.
        existing = update(
            "experience_media",
            {"experience_id": experience_id, "is_primary": "true"},
            data,
        )
        if not existing:
            insert("experience_media", {
                "experience_id": experience_id, **data,
                "position": 0, "is_primary": True,
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
    group.add_argument("--catalog", type=Path, help="content/video-catalog.md → attach by clip map")
    group.add_argument("--check", type=str, help="test one post URL")
    parser.add_argument("--clip-map", type=Path, default=Path("content/clip-map.tsv"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.check:
        return cmd_check(args.check)

    # --scan deliberately does not require credentials.
    if args.scan:
        return cmd_scan(args.scan)

    # Neither does --catalog with --dry-run: the filename→URL half needs nothing.
    if args.catalog:
        return cmd_catalog(args.catalog, args.clip_map, args.dry_run)

    require_env()
    return cmd_map(args.map, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
