# Vantage

**Know what’s ahead. Move with confidence.**

A calm, chest-worn iPhone guide for blind and low-vision people. **Freeroam** watches the path with LiDAR (or monocular) depth and haptics. Ask with “Vantage…” when you want voice. On-device **Gemma** covers offline Q&A; **Gemini** when you’re online.

Vantage is not a replacement for a white cane or a guide dog.

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![ARKit](https://img.shields.io/badge/ARKit-LiDAR-0A84FF)

## Demo (90 seconds)

1. Hold or strap the phone at chest height.
2. Say **Start** (or tap Freeroam) — walk toward a chair; feel near / medium / far haptics.
3. Say **“Vantage, what’s ahead?”**
4. Say **“night vision on”** (LiDAR phone).

## What it does

| Mode | Behavior |
| --- | --- |
| **Freeroam** | Haptics-only while walking. No beeps. Ask with “Vantage…” for voice. |
| **Ask** | Wake word + question. Local toggles (`quiet mode`, `night vision`) never call the cloud. |
| **Navigate** | Landmark guidance — code present, **hidden in the UI** until redone (`Features.navigate`). |

## Built with

`Swift` `SwiftUI` `ARKit` `LiDAR` `Vision` `Core Haptics` `Speech` `ElevenLabs` `Google Gemini` `Gemma` `LiteRT-LM` `XcodeGen`

## Run it

Physical iPhone, iOS 17+ (LiDAR recommended).

```bash
brew install xcodegen git-lfs && git lfs install
./scripts/download_gemma.sh              # optional on-device Gemma → app/Models/
cd app
cp Secrets.swift.example Secrets.swift   # Gemini + ElevenLabs keys
cp Local.xcconfig.example Local.xcconfig # DEVELOPMENT_TEAM + bundle id
xcodegen generate
open Vantage.xcodeproj
```

See [`app/SETUP.md`](app/SETUP.md) for signing and Developer Mode.

Offline Q&A: **Gemini → Gemma on-device → Vision templates**.

## Repo map

| Path | What’s in it |
| --- | --- |
| [`DEVPOST.md`](DEVPOST.md) | HackRU paste-ready submission |
| [`PLAN.md`](PLAN.md) | Architecture |
| [`docs/branding/`](docs/branding/) | Logo + Devpost thumbnail |
| `app/` | SwiftUI app + `project.yml` |
| `scripts/` | Phrase bank + Gemma download |

## Design principles

- Safety never waits on the network.
- Freeroam: haptics only while walking; voice on ask.
- Say when unsure. Never invent street names.
- Ink + teal + cream — large targets, VoiceOver-friendly.
