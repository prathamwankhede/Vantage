# Vantage

**Know what’s ahead. Move with confidence.**

A calm, chest-worn iPhone guide for blind and low-vision people. Freeroam watches the path with LiDAR (or monocular) depth and haptics. Navigate uses **Google Gemini** landmark steps plus **AirPods HRTF** spatial audio — no map, no GPS routing. Voice is **ElevenLabs**, with on-device **Gemma** when the network drops.

Vantage is not a replacement for a white cane or a guide dog.

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![ARKit](https://img.shields.io/badge/ARKit-LiDAR-0A84FF)

## Demo (90 seconds)

1. Strap or hold the phone at chest height. Put on AirPods.
2. **Freeroam** — walk toward a chair/person; feel near / medium / far haptics (continuous buzz when very close).
3. Say **“Vantage, what’s ahead?”** — Gemini (or on-device Gemma) answers from the camera.
4. **Navigate** → “the exit” (or any landmark) — hear short steps; the spatial tone points where to look.
5. Say **“night vision on”** — LiDAR depth overlay (local command, no Gemini).

## What it does

| Mode | Behavior |
| --- | --- |
| **Freeroam** | Haptics-only while walking. No beeps. Ask with “Vantage…” when you want voice. |
| **Navigate** | Destination in plain language. Gemini returns landmark steps. Depth safety stays on underneath. HRTF places the cue in space. |
| **Ask** | Wake word + question. Local toggles (`quiet mode`, `night vision on/off`) never call the cloud. |

## Built with

`Swift` `SwiftUI` `ARKit` `LiDAR` `Vision` `Core Motion` `Core Haptics` `Speech` `AVAudioEnvironmentNode` `ElevenLabs` `Google Gemini` `Gemma` `LiteRT-LM` `XcodeGen`

## Run it

Physical iPhone, iOS 17+ (LiDAR recommended). AirPods for spatial Navigate.

```bash
brew install xcodegen git-lfs && git lfs install
./scripts/download_gemma.sh              # optional on-device Gemma → app/Models/
cd app
cp Secrets.swift.example Secrets.swift   # Gemini + ElevenLabs keys
cp Local.xcconfig.example Local.xcconfig # DEVELOPMENT_TEAM + bundle id
xcodegen generate
open Vantage.xcodeproj
```

See [`app/SETUP.md`](app/SETUP.md) for signing, Developer Mode, and package quirks.

Offline Q&A: **Gemini → Gemma on-device → Vision templates**.  
TTS: bundled `app/Phrases/` → disk cache → ElevenLabs → system voice.

```bash
python3 scripts/generate_phrases.py   # needs a valid ElevenLabs key
```

## Repo map

| Path | What’s in it |
| --- | --- |
| [`PLAN.md`](PLAN.md) | Architecture and cue policy |
| [`DEVPOST.md`](DEVPOST.md) | HackRU submission copy + demo script |
| `app/` | SwiftUI app + `project.yml` |
| `app/Core/` | Depth, haptics, speaker, Gemini, Gemma |
| `app/Spatial/` | Head tracking + HRTF tone |
| `app/Engine/` | Freeroam + Navigate |
| `scripts/` | Phrase bank + Gemma download |

## Design principles

- Safety never waits on the network.
- Freeroam: haptics only. Navigate: one HRTF tone + haptics + sparse voice.
- Say when unsure. Never invent street names.
- Ink + teal + cream — calm UI, large targets, VoiceOver-friendly.
