#!/usr/bin/env python3
"""Regenerate offline ElevenLabs clips for Vantage into app/Phrases/.

Reads ELEVENLABS_API_KEY / ELEVENLABS_VOICE_ID from the environment, or parses
app/Secrets.swift (gitignored) when those env vars are empty.

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

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "app" / "Phrases"
SECRETS = ROOT / "app" / "Secrets.swift"

PHRASES = [
    "Welcome to Vantage. Say Freeroam to walk with vibration warnings, or Navigate to be guided somewhere.",
    "Main menu. Say Freeroam, or Navigate.",
    "Say Freeroam, or Navigate.",
    "Sorry, I didn't catch that. Say Freeroam, or Navigate.",
    "Freeroam. Haptics watch the path. Say Vantage when you need me.",
    "Hello, this is Vantage. Know what's ahead. Move with confidence.",
    "Clear path",
    "Stop",
    "Stop, move left",
    "Stop, move right",
    "Stop, turn left",
    "Stop, turn right",
    "Quiet mode. Haptics only.",
    "Speaking on.",
    "Night vision on.",
    "Night vision off.",
    "Night vision on. Needs LiDAR for the depth view.",
    "Indoor alert mode.",
    "Outdoor alert mode.",
    "Universal alert mode.",
    "Great. You can go back when you're ready.",
    "Freeroam has no steps. Start Navigate from the menu, or ask what's ahead.",
    "I can't see a frame right now.",
    "Nothing close enough to name.",
    "I don't have a clear name for that.",
]


def slug(text: str) -> str:
    parts = re.split(r"[^a-z0-9]+", text.lower())
    return "_".join(p for p in parts if p)


def secrets_from_swift() -> tuple[str, str]:
    if not SECRETS.exists():
        return "", ""
    text = SECRETS.read_text(encoding="utf-8")
    key = re.search(r'static let elevenLabsKey\s*=\s*"([^"]*)"', text)
    voice = re.search(r'static let elevenLabsVoiceID\s*=\s*"([^"]*)"', text)
    return (key.group(1) if key else ""), (voice.group(1) if voice else "")


def synthesize(text: str, key: str, voice: str) -> bytes:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128"
    r = requests.post(
        url,
        headers={"xi-api-key": key, "Content-Type": "application/json"},
        json={"text": text, "model_id": "eleven_flash_v2_5"},
        timeout=45,
    )
    r.raise_for_status()
    return r.content


def main() -> None:
    env_key = os.environ.get("ELEVENLABS_API_KEY", "")
    env_voice = os.environ.get("ELEVENLABS_VOICE_ID", "")
    file_key, file_voice = secrets_from_swift()
    key = env_key or file_key
    voice = env_voice or file_voice or "cgSgspJ2msm6clMCkdW9"
    if not key or not key.startswith("sk_"):
        print("No ElevenLabs key. Set ELEVENLABS_API_KEY or fill app/Secrets.swift", file=sys.stderr)
        sys.exit(1)

    # Fail fast if the key is rejected (common when Secrets.swift has a stale key).
    try:
        probe = requests.get(
            "https://api.elevenlabs.io/v1/user",
            headers={"xi-api-key": key},
            timeout=20,
        )
        if probe.status_code == 401:
            print(
                "ElevenLabs rejected the API key (401). Update app/Secrets.swift or ELEVENLABS_API_KEY.",
                file=sys.stderr,
            )
            sys.exit(2)
        probe.raise_for_status()
    except requests.RequestException as exc:
        print("ElevenLabs probe failed:", type(exc).__name__, file=sys.stderr)
        sys.exit(2)

    OUT.mkdir(parents=True, exist_ok=True)
    ok = 0
    for phrase in PHRASES:
        path = OUT / f"{slug(phrase)}.mp3"
        if path.exists() and path.stat().st_size > 500:
            print("skip", path.name)
            ok += 1
            continue
        try:
            data = synthesize(phrase, key, voice)
            path.write_bytes(data)
            print("ok", path.name, len(data), "bytes")
            ok += 1
        except Exception as exc:
            print(
                "fail",
                path.name,
                type(exc).__name__,
                str(exc).encode("ascii", "replace").decode(),
                file=sys.stderr,
            )
    print(f"Done: {ok}/{len(PHRASES)} clips in {OUT}")



if __name__ == "__main__":
    main()
