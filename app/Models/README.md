# On-device Gemma models

Place a LiteRT-LM `.litertlm` file here (or in the app’s `Documents/VantageModels` on device). Used when Gemini is offline or fails — see `SceneAI` / `GemmaClient`.

Recommended: **Gemma 4 E2B** from the LiteRT community on Hugging Face.

```bash
# from repo root
./scripts/download_gemma.sh
```

Default filename (`Secrets.gemmaModelFileName`): `gemma-4-E2B-it.litertlm`

Large model files are gitignored — do not commit them. The app still runs without this file (Vision templates fill in).
