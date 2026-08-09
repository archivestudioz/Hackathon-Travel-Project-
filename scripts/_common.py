"""Shared Supabase access for the ingestion scripts.

Everything here uses the SERVICE-ROLE key and therefore bypasses RLS. None of it
ships to the browser — these run on a laptop or in CI, before a demo, and write
their results into Postgres. The app then reads the database.

That separation is deliberate: no third party sits between a judge and the
product. Overpass being slow, Tavily rate-limiting, or Stay22 being down can
only ever break a build, never a demo.
"""

from __future__ import annotations

import os
import sys
from typing import Any

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:  # convenience, not a requirement
    pass

SUPABASE_URL = (os.getenv("SUPABASE_URL") or "").rstrip("/")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or ""


def require_env(*extra: str) -> None:
    missing = [
        name
        for name, value in (
            ("SUPABASE_URL", SUPABASE_URL),
            ("SUPABASE_SERVICE_ROLE_KEY", SERVICE_KEY),
            *((name, os.getenv(name) or "") for name in extra),
        )
        if not value
    ]
    if missing:
        sys.exit(f"Missing {', '.join(missing)} — copy .env.example to .env and fill it in.")


def _headers(extra: dict[str, str] | None = None) -> dict[str, str]:
    headers = {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
    }
    if extra:
        headers.update(extra)
    return headers


def wkt(lng: float, lat: float) -> str:
    """PostgREST accepts EWKT for geography columns."""
    return f"SRID=4326;POINT({lng} {lat})"


def select(table: str, params: dict[str, Any] | None = None) -> list[dict]:
    response = requests.get(
        f"{SUPABASE_URL}/rest/v1/{table}", headers=_headers(), params=params or {}, timeout=30
    )
    response.raise_for_status()
    return response.json()


def insert(table: str, rows: list[dict] | dict, on_conflict: str | None = None) -> list[dict]:
    """Upsert by default — every ingestion script must be safe to re-run."""
    prefer = "return=representation"
    params: dict[str, str] = {}
    if on_conflict:
        prefer += ",resolution=merge-duplicates"
        params["on_conflict"] = on_conflict

    response = requests.post(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers=_headers({"Prefer": prefer}),
        params=params,
        json=rows,
        timeout=90,
    )
    response.raise_for_status()
    return response.json() if response.content else []


def update(table: str, match: dict[str, Any], patch: dict) -> list[dict]:
    params = {key: f"eq.{value}" for key, value in match.items()}
    response = requests.patch(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers=_headers({"Prefer": "return=representation"}),
        params=params,
        json=patch,
        timeout=30,
    )
    response.raise_for_status()
    return response.json() if response.content else []


def rpc(name: str, payload: dict | None = None) -> Any:
    response = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/{name}", headers=_headers(), json=payload or {}, timeout=60
    )
    response.raise_for_status()
    return response.json() if response.content else None


def get_city(slug: str) -> dict:
    rows = select("cities", {"slug": f"eq.{slug}", "select": "*"})
    if not rows:
        sys.exit(f"unknown city '{slug}' — seed it first")
    return rows[0]
