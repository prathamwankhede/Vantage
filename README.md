# Vantage

**Know what’s ahead. Move with confidence.**

A calm, chest-worn iPhone guide for blind and low-vision people. Freeroam watches the path with on-device depth and haptics. Navigate uses Gemini landmarks plus AirPods HRTF spatial audio to talk you through a building or block — no map.

Vantage is not a replacement for a white cane or a guide dog.

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![ARKit](https://img.shields.io/badge/ARKit-LiDAR-0A84FF)

## What it does

1. **Freeroam** — Haptics-only while walking (White Cane–style near/medium/far patterns, continuous buzz when very close). Optional LiDAR night-vision overlay. No beeps, no side bars. Ask with “Vantage…” when you want voice.
2. **Navigate** — Tell Vantage a destination (“the exit”, “pharmacy counter”). Gemini reads the camera and gives short landmark steps. Depth safety stays on underneath. Hazards and steps are placed with `AVAudioEnvironmentNode` HRTF so AirPods + head tracking let you pinpoint where they are. No MapKit, no GPS routing.
3. **Ask** — Say “Vantage…” then a question (“What’s ahead?”, “Name that”). Local toggles like “night vision on/off” never call Gemini.

## Built with

`Swift` `SwiftUI` `ARKit` `LiDAR` `Vision` `Core Motion` `Core Haptics` `Speech` `ElevenLabs` `Google Gemini` `Gemma` `LiteRT-LM` `XcodeGen`

## Run it

Needs a physical iPhone on iOS 17+ (LiDAR recommended). AirPods Pro/Max (or any headphones) unlock Navigate spatial audio; head tracking uses `CMHeadphoneMotionManager` when available.

```bash
brew install xcodegen
./scripts/download_gemma.sh              # on-device Gemma weights → app/Models/
cd app
cp Secrets.swift.example Secrets.swift   # add Gemini + ElevenLabs keys
xcodegen generate
open Vantage.xcodeproj
```

Offline Q&A order: **Gemini (online) → Gemma on-device → Vision templates**.

Offline phrase bank (bundled MP3s under `app/Phrases/`) plus a runtime ElevenLabs disk cache (`Documents/TTSCache` — first network speak is saved for offline reuse):

```bash
# uses app/Secrets.swift when env vars are empty
export ELEVENLABS_API_KEY=…   # optional override
python3 scripts/generate_phrases.py
```

Allow camera, microphone, speech, and motion permissions, then run on device.

## Repo map

| Path | What’s in it |
| --- | --- |
| [`PLAN.md`](PLAN.md) | Product and architecture plan |
| `app/` | SwiftUI app + `project.yml` for XcodeGen |
| `app/Core/` | Depth, haptics, speaker, listener, Gemini |
| `app/Spatial/` | AirPods head motion + spatial tone |
| `app/Engine/` | Freeroam safety loop + Navigate session |
| `app/UI/` | Brand shell and session screens |
| `app/Design/` | Visual identity tokens |
| `scripts/` | Phrase bank generator |

## Design principles

- Safety never waits on the network.
- Freeroam: haptics only while walking; voice on ask. Navigate: HRTF tone + haptics + sparse voice.
- Say when unsure. Never invent street names.
- Distinct ink-and-teal visual identity; calm UI without clutter.
