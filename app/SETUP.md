# Vantage setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. `cd app && cp Secrets.swift.example Secrets.swift` and add Gemini + ElevenLabs keys
3. `xcodegen generate && open Vantage.xcodeproj`
4. Select a physical iPhone (iOS 17+), allow permissions, run
5. Optional: `python3 ../scripts/generate_phrases.py` with `ELEVENLABS_API_KEY` for offline clips

AirPods recommended. Spatial left/right cues need headphones; head tracking uses AirPods motion when available.
