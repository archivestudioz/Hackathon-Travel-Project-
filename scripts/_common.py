"""Shared Supabase access for the build-time and demo scripts.

Everything here uses the service-role key and therefore bypasses RLS. None of
this ships to the browser — it runs on your laptop before and during the demo.
"""

from __future__ import annotations

import os
import sys
from typing import Any

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:  # dotenv is a convenience, not a requirement
    pass

SUPABASE_URL = (os.getenv("SUPABASE_URL") or "").rstrip("/")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or ""


def require_env() -> None:
    missing = [
        name
        for name, value in (
            ("SUPABASE_URL", SUPABASE_URL),
            ("SUPABASE_SERVICE_ROLE_KEY", SERVICE_KEY),
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
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers=_headers(),
        params=params or {},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()


def insert(table: str, rows: list[dict] | dict, upsert: bool = False) -> list[dict]:
    prefer = "return=representation"
    if upsert:
        prefer += ",resolution=merge-duplicates"
    response = requests.post(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers=_headers({"Prefer": prefer}),
        json=rows,
        timeout=60,
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


def delete(table: str, match: dict[str, Any]) -> None:
    params = {key: f"eq.{value}" for key, value in match.items()}
    response = requests.delete(
        f"{SUPABASE_URL}/rest/v1/{table}", headers=_headers(), params=params, timeout=30
    )
    response.raise_for_status()


def rpc(name: str, payload: dict | None = None) -> Any:
    response = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/{name}",
        headers=_headers(),
        json=payload or {},
        timeout=30,
    )
    response.raise_for_status()
    return response.json() if response.content else None
