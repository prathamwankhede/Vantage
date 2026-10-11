<div align="center">

<img src="vantage-thumbnail.jpg" alt="Vantage" width="220" />

# Vantage

### A chest-worn iPhone guide for blind and low-vision people

*Feel the path ahead, understand what's in front of you, and move with confidence — even when Wi‑Fi drops.*

<p>
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white" />
  <img alt="iOS" src="https://img.shields.io/badge/iOS-17%2B-000000?logo=apple&logoColor=white" />
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-UI-0D96F6?logo=swift&logoColor=white" />
  <img alt="ARKit" src="https://img.shields.io/badge/ARKit-LiDAR%20%2B%20Camera-000000?logo=apple&logoColor=white" />
  <img alt="Core Haptics" src="https://img.shields.io/badge/Core%20Haptics-Bands-555555?logo=apple&logoColor=white" />
  <img alt="Gemini" src="https://img.shields.io/badge/Gemini-when%20online-8E75B2?logo=googlegemini&logoColor=white" />
  <img alt="Gemma" src="https://img.shields.io/badge/Gemma-on%20device-4285F4?logo=google&logoColor=white" />
  <img alt="ElevenLabs" src="https://img.shields.io/badge/ElevenLabs-calm%20voice-000000" />
  <img alt="HackRU Fall 2026" src="https://img.shields.io/badge/HackRU-Fall%202026-cc0033" />
</p>

<sub>Built at <b>HackRU Fall 2026</b> · Busch Student Center · Oct 10–11, 2026 · Social Good</sub>

</div>

---

## Overview

Vantage is a voice-first guide worn on a chest lanyard. **Freeroam** watches the next few steps with LiDAR (or camera) depth and calm haptics. Say **"Vantage, …"** when you want the world named out loud.

> The phone handles danger locally. AI helps Vantage understand the view — it never owns the safety loop.

1. **Watches** left / ahead / right — LiDAR when available, camera distance when not.
2. **Feels** — near / medium / far haptic bands; continuous buzz when something is very close. No beeps.
3. **Callouts** — Freeroam speaks sparingly on approach (people, doors, stairs, elevators).
4. **Asks** — wake word *"Vantage…"* for what's ahead, around me, repeat, return to start, naming.
5. **Answers** with Gemini when online, on-device Gemma when offline, then Vision templates.
6. **Navigate** — say a destination; Gemini picks a landmark and LiDAR pins it in 3D. A spatial beacon stays on it, steers round walls and hallway bends, and Compass-style ticks + a Level-style click tell you when you're facing the right way. Destination signs are read on-device.
7. **Night vision** — LiDAR depth on the camera when there’s light; auto full-frame when the room is dark. Color or **3D Spatial** shading, in both modes (local, no cloud).

Vantage doesn't replace a cane or a guide dog. It adds another sense to a phone people already carry.

---

## Highlights

| | |
|---|---|
| **Offline safety** | Depth + haptics run on the phone. No network needed to feel *"too close."* |
| **Any modern iPhone** | LiDAR Pro preferred. Without it, Vision estimates distance from the camera. |
| **Gemini + Gemma** | Gemini when you're online; on-device Gemma when you're not. |
| **Calm ElevenLabs voice** | Speaks on ask; disk cache + system voice fallback. |
| **Always listening** | Wake word *"Vantage…"* — interrupt anytime. |
| **Quiet mode** | Haptics only (silences Freeroam callouts too). |
| **Navigate** | 3D landmark pin · on-device sign reading · room mesh that finds doors and routes round walls and bends · HRTF beacon with AirPods head tracking. |
| **Feel the heading** | Compass-style ticks as you turn, a Level-style click when you're on course — the cone adapts to distance. |
| **Return to start** | Clew-style ARKit breadcrumbs — no cloud. |
| **Smart night vision** | Overlay in lit rooms · full LiDAR when dark · Color or 3D Spatial · Freeroam and Navigate. |
| **Blind-first UI** | Voice from launch, huge targets, ink / teal / cream, VoiceOver-friendly. |

---

## Architecture

```mermaid
flowchart LR
    subgraph Wearer
        MIC["Voice"]
        BODY["Haptics"]
        EAR["Spoken answers"]
        SCREEN["Camera · captions · night vision"]
    end

    subgraph Device["On-device"]
        AR["ARKit"]
        DEPTH["LiDAR zones / camera distance"]
        NV["NightVisionRenderer"]
        ENG["FreeroamEngine"]
        NAV["NavigateSession<br/>3D pin · beacon · heading"]
        MESH["RoomMap<br/>scene mesh"]
        OCR["SignSpotter"]
        HRTF["SpatialTone (HRTF)"]
        SPK["Speaker"]
        LISTEN["AlwaysListener"]
        GEMMA["GemmaClient"]
        HAP["HapticPulser"]
    end

    subgraph Cloud["When online"]
        GEM["Gemini"]
        EL["ElevenLabs TTS"]
    end

    AR --> DEPTH --> ENG
    AR --> NV --> SCREEN
    MIC --> LISTEN --> ENG
    ENG --> HAP --> BODY
    ENG --> SPK --> EAR
    ENG --> SCREEN
    AR --> MESH --> NAV
    AR --> OCR --> NAV
    ENG <--> NAV
    NAV --> HRTF --> EAR
    NAV --> HAP
    NAV -->|"landmark + box"| GEM
    ENG -->|"online"| GEM
    ENG -->|"offline / fallback"| GEMMA
    SPK -.-> EL
```

**Safety never waits on the network.** Depth decides *where*; Vision / Gemini / Gemma decide *what*.

---

## Voice commands

Always start with **"Vantage, …"** (from launch, say **Freeroam** or **Navigate**.)

| Say | Vantage does |
|---|---|
| `Freeroam` / `Start` | Begins Freeroam |
| `Navigate` + destination | Landmark guide with spatial beacon |
| `… next` | Navigate: ask for the next landmark now |
| `… where's the door?` | Navigate: nearest door from the room mesh (on-device) |
| `Vantage` | Ready — ask what's ahead |
| `… what's ahead?` / `what's in front of me?` | Describes the camera view |
| `… around me` | Closest labeled things (on-device) |
| `… repeat` | Repeats the last spoken line |
| `… I'm lost` / `return to start` | Breadcrumb walk back |
| `… name that` / `what is that?` | Names the nearest obstacle |
| `… quiet` / `speaking on` | Haptics-only or speak again |
| `… night vision on` / `off` | LiDAR depth view (settings pick Color vs 3D Spatial) |
| `… go back` / `main menu` | Leaves the session |

---

## Quick start

```bash
git clone https://github.com/prathamwankhede/Vantage.git
cd Vantage
brew install xcodegen git-lfs && git lfs install
./scripts/download_gemma.sh   # optional on-device Gemma
cd app
cp Secrets.swift.example Secrets.swift
cp Local.xcconfig.example Local.xcconfig
xcodegen generate
open Vantage.xcodeproj
```

1. Add Gemini + ElevenLabs keys in `Secrets.swift`.
2. Set your `DEVELOPMENT_TEAM` in `Local.xcconfig`.
3. Run on a **physical iPhone** (LiDAR recommended). Allow Camera, Mic, Speech, Motion.
4. Say **"Start"** or tap Freeroam, then **"Vantage, what's ahead?"**
5. Optional: **"night vision on"** — Color / 3D Spatial in Detection settings.

Optional phrase bank (needs a valid ElevenLabs key):

```bash
python3 scripts/generate_phrases.py
```

More detail: [`app/SETUP.md`](app/SETUP.md) · architecture notes: [`PLAN.md`](PLAN.md)

---

## Repo map

| Piece | Role |
|---|---|
| `app/Engine/FreeroamEngine.swift` | Safety loop, wake word, callouts, crumbs |
| `app/Engine/NavigateSession.swift` | Landmark pin + beacon + Gemini steps |
| `app/Engine/NavTarget.swift` | Pinned target, bearing / distance / direction words |
| `app/Core/DepthSnapshot.swift` | Photo-instant depth → world point for a pin |
| `app/Core/SignSpotter.swift` | On-device sign reading for the destination |
| `app/Core/RoomMap.swift` | Scene-mesh doors + A* routing round walls and bends |
| `app/Core/HeadingLock.swift` / `HeadingHaptics.swift` | On-course gate (distance-adaptive) + Compass ticks / Level click |
| `app/Core/SceneTracker.swift` / `CalloutPolicy.swift` | Freeroam approach callouts |
| `app/Core/BreadcrumbTrail.swift` | Return-to-start keypoints |
| `app/Core/DepthZoneAnalyzer.swift` | LiDAR left / center / right |
| `app/Core/MonocularDistanceEstimator.swift` | Camera-only distance (no LiDAR) |
| `app/Core/HapticPulser.swift` | Near / medium / far bands |
| `app/Core/NightVisionRenderer.swift` | Color + 3D Spatial; overlay ↔ full-frame by luma |
| `app/Core/DetectionSettings.swift` | Alert modes, haptics, night-vision mode |
| `app/Core/SceneAI.swift` | Gemini → Gemma → templates |
| `app/Core/GemmaClient.swift` | On-device scene answers |
| `app/Core/GeminiClient.swift` | Cloud vision Q&A + Navigate landmark boxes |
| `app/Core/Speaker.swift` | ElevenLabs + cache + system voice |
| `app/Core/AlwaysListener.swift` | Wake-word listening |
| `app/Spatial/` | HRTF / head tracking for Navigate beacon |
| `app/UI/` | Loading, main menu, session, settings |
| `docs/branding/` | Logo + gallery thumbnail |
| `scripts/` | Gemma download + phrase generator |

---

## Built with

ARKit · Core Haptics · Apple Vision · Apple Speech · ElevenLabs · Google Gemini · Gemma (LiteRT-LM) · SwiftUI · XcodeGen

---

## Team · HackRU Fall 2026

| Name | Links |
|---|---|
| **Farhan Mir** | [GitHub](https://github.com/farhanmir) · [LinkedIn](https://www.linkedin.com/in/farhan-mir) |
| **Pratham Wankhede** | [GitHub](https://github.com/prathamwankhede) · [LinkedIn](https://www.linkedin.com/in/pratham-wankhede/) |

---

<div align="center">

**Know what's ahead. Move with confidence.**

<sub>Not a replacement for a cane or guide dog — a 24-hour prototype that adds another sense.</sub>

</div>
