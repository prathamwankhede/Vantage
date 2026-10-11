# Vantage setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Git LFS (LiteRT-LM needs it):

   ```bash
   brew install xcodegen git-lfs && git lfs install
   ```

2. `cd app && cp Secrets.swift.example Secrets.swift` and add Gemini + ElevenLabs keys. Keep every field from the example (`backendURL`, `backendKey`, `gemmaModelFileName`). **Never commit `Secrets.swift`.**

3. **Signing:** `cp Local.xcconfig.example Local.xcconfig` and set `DEVELOPMENT_TEAM` plus a unique `PRODUCT_BUNDLE_IDENTIFIER` (a free Personal Team can’t reuse `com.vantage.app`).

4. **Gemma (optional, on-device):** from repo root run `./scripts/download_gemma.sh` (`pip install huggingface_hub`). Puts `gemma-4-E2B-it.litertlm` (~2.6 GB) in `app/Models/` (gitignored); it ships in the app as `Models/`. Main screen shows “On-device Gemma: ready …” when loaded. Gemma answers only when Gemini can’t — Airplane Mode + “Vantage, what’s ahead?” to try it.

5. Generate and open the project:

   ```bash
   xcodegen generate && open Vantage.xcodeproj
   ```

   The `.xcodeproj` is gitignored — rerun after `project.yml` or new source files change.

6. **iPhone:** Trust the Mac → Settings → Privacy & Security → Developer Mode (restarts). Pick the phone in Xcode and Run. **LiDAR Pro** recommended for Navigate pins, signs, mesh, and night vision.

7. First Personal Team launch: Settings → General → VPN & Device Management → trust your cert. Allow Camera, Mic, Speech, Motion.

8. Optional offline TTS clips (valid ElevenLabs key required):

   ```bash
   python3 ../scripts/generate_phrases.py
   ```

   Reads `Secrets.swift` when env vars are empty. Runtime speaks also cache under `Documents/TTSCache`.

If Xcode says “Git LFS is not installed” while resolving packages, it can’t see Homebrew’s PATH. Resolve once from Terminal:

```bash
xcodebuild -resolvePackageDependencies -project Vantage.xcodeproj -scheme Vantage
```

or link: `sudo ln -s /opt/homebrew/bin/git-lfs "$(xcode-select -p)/usr/bin/git-lfs"`.

## Offline stack

| Layer | When |
| --- | --- |
| Gemini | Online scene Q&A + Navigate landmarks |
| **Gemma (LiteRT-LM)** | Offline / Gemini failure |
| Vision templates | Gemma missing or still loading |

## Demo checklist (HackRU)

- [ ] Physical **LiDAR** iPhone, charged; AirPods paired for Navigate HRTF
- [ ] `Secrets.swift` keys work; try “Vantage, what’s ahead?” once before judging
- [ ] Gemma downloaded if you want offline answers
- [ ] Phrase bank generated (optional but faster TTS)
- [ ] Freeroam first: walk → feel haptics → ask what’s ahead → night vision on
- [ ] Navigate encore: numbered room / long sign text; headphones on
- [ ] Quiet mode off unless showing haptics-only

## Demo tips

- Freeroam is the reliable surface; Navigate shows the harder stack (3D pin, OCR, mesh detours, heading haptics).
- Night vision: overlay when lit, full-frame when dark; Color vs 3D Spatial in Detection settings.
- Freeroam is haptics-first with sparse approach callouts; Quiet mode silences speech.
