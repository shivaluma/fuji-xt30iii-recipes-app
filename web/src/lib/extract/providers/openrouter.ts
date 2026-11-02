import "server-only";
import { EXTRACTION_SYSTEM_PROMPT } from "../mapping";
import { extractionJSONSchema, ProviderError, userText, type ExtractionInput, type ExtractionProvider, type ProviderResult } from "./types";

const ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";

/**
 * OpenRouter (OpenAI-compatible REST; no SDK dependency). Default model is the benchmark winner
 * (see web/bench/RESULTS.md); override with EXTRACTION_MODEL.
 */
export class OpenRouterProvider implements ExtractionProvider {
  readonly id = "openrouter";
  constructor(readonly model: string, private readonly apiKey: string, private readonly opts: { maxTokens?: number; referer?: string } = {}) {}

  async extract(input: ExtractionInput, signal: AbortSignal): Promise<ProviderResult> {
    const content: unknown[] = [{ type: "text", text: userText(input) }];
    if (input.image) content.push({ type: "image_url", image_url: { url: `data:${input.image.mediaType};base64,${input.image.data}` } });
    const res = await fetch(ENDPOINT, {
      method: "POST",
      signal,
      headers: {
        authorization: `Bearer ${this.apiKey}`,
        "content-type": "application/json",
        "x-title": "FilmLab Recipes",
        ...(this.opts.referer ? { "http-referer": this.opts.referer } : {}),
      },
      body: JSON.stringify({
        model: this.model,
        messages: [{ role: "system", content: EXTRACTION_SYSTEM_PROMPT }, { role: "user", content }],
        response_format: { type: "json_schema", json_schema: { name: "fujifilm_recipe", strict: true, schema: extractionJSONSchema() } },
        // Only route to providers that honour structured outputs.
        provider: { require_parameters: true },
        // Simple extraction: keep thinking minimal (Gemini 3.x supports it; other models skip it).
        ...(this.model.startsWith("google/gemini-3") ? { reasoning: { effort: "minimal", exclude: true } } : {}),
        temperature: 0,
        max_tokens: this.opts.maxTokens ?? 1500,
        usage: { include: true },
      }),
    }).catch((e: unknown) => {
      if ((e as Error).name === "TimeoutError" || (e as Error).name === "AbortError") throw new ProviderError("The AI provider timed out.", 504, true);
      throw new ProviderError("Couldn't reach the AI provider.", 503, true);
    });

    const body = (await res.json().catch(() => null)) as null | {
      error?: { message?: string };
      model?: string;
      choices?: { message?: { content?: string | null }; finish_reason?: string }[];
      usage?: { prompt_tokens?: number; completion_tokens?: number; cost?: number };
    };
    if (!res.ok || !body || body.error) {
      const retryable = res.status === 429 || res.status >= 500;
      const msg = res.status === 401 || res.status === 403 ? "The server's OpenRouter API key is missing or invalid."
        : res.status === 402 ? "The OpenRouter account is out of credits. Top it up, then try again."
        : res.status === 429 ? "The AI provider is rate-limiting requests. Try again shortly."
        : `AI provider error (${res.status}).`;
      throw new ProviderError(msg, res.status === 401 || res.status === 403 ? 500 : retryable ? 503 : 502, retryable);
    }
    const choice = body.choices?.[0];
    if (choice?.finish_reason === "length") throw new ProviderError("The model's answer was cut off.", 502, true);
    let output: unknown;
    try { output = JSON.parse(choice?.message?.content ?? ""); } catch { throw new ProviderError("The model returned malformed JSON.", 502, true); }
    return {
      output,
      model: body.model ?? this.model,
      usage: { inputTokens: body.usage?.prompt_tokens ?? null, outputTokens: body.usage?.completion_tokens ?? null, costUSD: body.usage?.cost ?? null },
    };
  }
}
