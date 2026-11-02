# Recipe extraction benchmark — 2026-11-02

**Fixtures:**
- 10 synthetic screenshots (`fixtures/`, rendered by `scripts/bench/generate-fixtures.swift`, hand-verified `expected.json`): light, dark and small-font lists, a card grid, a Reddit comment with a prompt injection, mixed Vietnamese, cropped, missing settings, unsupported settings, negatives.
- 2 real third-party recipe-card screenshots, kept private and not in the repo.

**Results come from fixtures, not production traffic.** 20 recipe fields are scored per image. A field absent from the image must come back `null`. "Exact" means every field is right.

**Setup:** cost is OpenRouter's reported `usage.cost`; latency is wall-clock from this Mac (Vietnam) to OpenRouter.

## Vision models (via OpenRouter, strict JSON schema, temperature 0, minimal thinking)

| Model | Runs | Field acc. | Whole-recipe exact | p50 | p95 | In / out tokens | $ / extraction | $ / correct recipe | Failures |
|---|---|---|---|---|---|---|---|---|---|
| **google/gemini-3.1-flash-lite** ✅ default | 3×12 | **100%** | **100% (36/36)** | 2.8 s | 3.6 s | 3269 / 586 | $0.00170 | **$0.00170** | 0 |
| google/gemini-3.5-flash-lite | 3×12 | 100% | 100% (36/36) | 2.7 s | 3.7 s | 1824 / 572 | $0.00198 | $0.00198 | 0 |
| google/gemini-2.5-flash-lite | 3×12 | 88.6% | 78% | 3.1 s | 4.6 s | 998 / 565 | $0.00028 | $0.00031 | 5 (HTTP 429) |
| qwen/qwen3-vl-30b-a3b-instruct | 1×12 | 54% | 8% | 14 s | 22 s | 1510 / 406 | $0.00047 | $0.0042 | 3 |
| qwen/qwen3.5-flash-02-23 | 1×12 | 48% | 25% | 18 s | 43 s | 2239 / 1213 | $0.00046 | $0.00046* | 9 |
| qwen/qwen3-vl-8b-instruct | 1×12 | — | — | — | — | — | — | — | 12 (HTTP 429, inconclusive) |

\* Its cost per correct recipe is computed over only 3 correct results.

**Failures worth knowing about:**
- **Gemini 2.5 Flash-Lite obeyed the prompt injection** in the Reddit fixture in 3 of 3 runs. It set Clarity +5 and Highlight +4 as instructed inside the image, and also read ACROS+R as ACROS+G.
- **The Qwen models invented defaults** (e.g. Kelvin 0, D-Range Priority off), returned non-conforming JSON, or were rate-limited.

The Qwen OCR model (`qwen-vl-ocr`) isn't available on OpenRouter, so it wasn't tested.

## On-device baseline (Apple Vision OCR + FilmLab's deterministic parser, free, offline)

Measured on macOS with the same Vision framework iOS uses (`scripts/bench/ondevice.sh`, scored by `pnpm bench:ondevice`).

| | Field acc. | Whole-recipe exact | Latency per image |
|---|---|---|---|
| On-device | 92.9% | 75% (9/12) | 50–380 ms (Mac) |

- **Perfect** on every "Label: value" list (incl. dark, small font, cropped, missing, negatives, unsupported, Vietnamese) and on real card B.
- **Incomplete** on:
  - the informal Reddit comment (no film simulation found);
  - the card grid's lone "0" (Sharpness);
  - real card A's lone "0"s (Sharpness, Clarity).
- **Every on-device miss was detectable.** Each came back unusable, or the field was flagged "not read". There were no silently wrong values.

## Decision

- **iOS uses a hybrid pipeline:** on-device first, and Gemini 3.1 Flash-Lite only when the on-device result is unusable or has unread fields (`RecipeImportDraft.needsAIFallback`).
  - On these fixtures, 3 of 12 images escalate, and Gemini got those right.
  - That gives ~100% on the fixture set at **~$0.00042 per recipe on average** (3/12 × $0.0017). 75% of imports finish in under 0.5 s.
- **The web admin has no local OCR** (none in the browser without a heavy dependency), so it calls the model directly.
- **Default model: `google/gemini-3.1-flash-lite`.** It has the lowest cost per correct recipe among the models with perfect accuracy, and resisted the injection.
  - 3.5 Flash-Lite is equally accurate, 17% more expensive, and slightly faster at p50. Switch with `EXTRACTION_MODEL`.

## Reproduce

```sh
./scripts/bench/generate-fixtures.sh                          # (re)render synthetic fixtures
cd web && OPENROUTER_API_KEY=… BENCH_RUNS=3 \
  BENCH_MODELS=google/gemini-3.1-flash-lite,google/gemini-3.5-flash-lite pnpm bench
./scripts/bench/ondevice.sh && cd web && pnpm bench:ondevice  # free on-device baseline
# optional private fixtures: BENCH_EXTRA_DIR=/dir/with/{id}.jpg+expected.json
```
