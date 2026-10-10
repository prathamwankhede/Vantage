# Vantage setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Git LFS (the LiteRT-LM package needs it): `brew install xcodegen git-lfs && git lfs install`
2. `cd app && cp Secrets.swift.example Secrets.swift` and add Gemini + ElevenLabs keys. If you copied it earlier, make sure it has every field in the example (`backendURL`, `backendKey`, `gemmaModelFileName`).
3. **Signing:** `cp Local.xcconfig.example Local.xcconfig` and set your `DEVELOPMENT_TEAM` and a unique `PRODUCT_BUNDLE_IDENTIFIER` (a free Personal Team can't reuse `com.vantage.app`).
4. **Gemma (on-device):** from repo root run `./scripts/download_gemma.sh` (needs `pip install huggingface_hub`). Puts `gemma-4-E2B-it.litertlm` (2.6 GB) in `app/Models/` (gitignored); it ships inside the app as `Models/`. The main screen shows "On-device Gemma: ready (GPU)" once it has loaded. Gemma only answers when Gemini can't — to try it, turn on Airplane Mode and say "Vantage, what's ahead?".
5. `xcodegen generate && open Vantage.xcodeproj` — the `.xcodeproj` is generated and gitignored, so rerun this after pulling changes to `project.yml` or adding files.
6. **iPhone:** connect it, tap Trust, then turn on Settings → Privacy & Security → Developer Mode (the phone restarts). Pick the phone in Xcode's run destination menu and press Run.
7. First launch with a Personal Team: Settings → General → VPN & Device Management → trust your developer certificate. Allow camera, mic, speech and motion.
8. Optional: `python3 ../scripts/generate_phrases.py` with `ELEVENLABS_API_KEY` for offline TTS clips

If Xcode says "Git LFS is not installed" while resolving packages even though it is, Xcode can't see Homebrew's PATH. Either resolve once from Terminal (`xcodebuild -resolvePackageDependencies -project Vantage.xcodeproj -scheme Vantage`) or link it: `sudo ln -s /opt/homebrew/bin/git-lfs "$(xcode-select -p)/usr/bin/git-lfs"`.

## Offline stack

| Layer | When |
| --- | --- |
| Gemini | Online scene Q&A + Navigate landmarks |
| **Gemma (LiteRT-LM)** | Offline / Gemini failure — on-device LLM |
| Vision templates | Gemma model missing or still loading |

AirPods recommended for spatial left/right cues.
