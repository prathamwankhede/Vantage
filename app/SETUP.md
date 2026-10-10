# Vantage setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. `cd app && cp Secrets.swift.example Secrets.swift` and add Gemini + ElevenLabs keys
3. **Gemma (on-device):** from repo root run `./scripts/download_gemma.sh` (needs `pip install huggingface_hub`). Puts `gemma-4-E2B-it.litertlm` in `app/Models/` (gitignored).
4. `xcodegen generate && open Vantage.xcodeproj`
5. Select a physical iPhone (iOS 17+), allow permissions, run
6. Optional: `python3 ../scripts/generate_phrases.py` with `ELEVENLABS_API_KEY` for offline TTS clips

## Offline stack

| Layer | When |
| --- | --- |
| Gemini | Online scene Q&A + Navigate landmarks |
| **Gemma (LiteRT-LM)** | Offline / Gemini failure — on-device LLM |
| Vision templates | Gemma model missing or still loading |

AirPods recommended for spatial left/right cues.
