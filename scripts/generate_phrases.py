#!/usr/bin/env python3
"""Regenerate offline ElevenLabs clips for Vantage into app/Phrases/.

Requires ELEVENLABS_API_KEY and optionally ELEVENLABS_VOICE_ID.
Slug rules must match Speaker.slug in app/Core/Speaker.swift.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

try:
    import requests
except ImportError:
    print("pip install requests", file=sys.stderr)
    sys.exit(1)

VOICE = os.environ.get("ELEVENLABS_VOICE_ID", "cgSgspJ2msm6clMCkdW9")
KEY = os.environ.get("ELEVENLABS_API_KEY", "")
OUT = Path(__file__).resolve().parents[1] / "app" / "Phrases"

PHRASES = [
    "Clear path",
    "Stop",
    "Stop, move left",
    "Stop, move right",
    "Stop, turn left",
    "Stop, turn right",
    "Quiet mode. Haptics and tones only.",
    "Speaking on.",
    "Freeroam. I'll watch the path. Say Vantage when you need me.",
    "Hello, this is Vantage. Know what's ahead. Move with confidence.",
]


def slug(text: str) -> str:
    parts = re.split(r"[^a-z0-9]+", text.lower())
    return "_".join(p for p in parts if p)


def synthesize(text: str) -> bytes:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE}?output_format=mp3_44100_128"
    r = requests.post(
        url,
        headers={"xi-api-key": KEY, "Content-Type": "application/json"},
        json={"text": text, "model_id": "eleven_flash_v2_5"},
        timeout=30,
    )
    r.raise_for_status()
    return r.content


def main() -> None:
    if not KEY:
        print("Set ELEVENLABS_API_KEY", file=sys.stderr)
        sys.exit(1)
    OUT.mkdir(parents=True, exist_ok=True)
    for phrase in PHRASES:
        path = OUT / f"{slug(phrase)}.mp3"
        print("→", path.name)
        path.write_bytes(synthesize(phrase))
    print("Done:", OUT)


if __name__ == "__main__":
    main()
