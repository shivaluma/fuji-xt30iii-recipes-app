import "server-only";
import { ExtractedRecipeSchema, toDraft, type ExtractionDraft } from "./mapping";
import { AnthropicProvider } from "./providers/anthropic";
import { OpenRouterProvider } from "./providers/openrouter";
import { ProviderError, type ExtractionInput, type ExtractionProvider } from "./providers/types";

/** Chosen by benchmark (web/bench/RESULTS.md). Override with EXTRACTION_MODEL. */
export const DEFAULT_OPENROUTER_MODEL = "google/gemini-3.1-flash-lite";
export const DEFAULT_ANTHROPIC_MODEL = "claude-opus-5-5";

export class ExtractionError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

/**
 * EXTRACTION_PROVIDER=openrouter|anthropic (default: whichever key is set, OpenRouter first),
 * EXTRACTION_MODEL=<model id>, OPENROUTER_BASE_URL=<OpenAI-compatible base URL> (proxies, local testing).
 */
export function configuredProvider(env: Record<string, string | undefined> = process.env): ExtractionProvider | null {
  const choice = env.EXTRACTION_PROVIDER ?? (env.OPENROUTER_API_KEY ? "openrouter" : env.ANTHROPIC_API_KEY ? "anthropic" : "");
  if (choice === "openrouter" && env.OPENROUTER_API_KEY) {
    return new OpenRouterProvider(env.EXTRACTION_MODEL || DEFAULT_OPENROUTER_MODEL, env.OPENROUTER_API_KEY, { referer: env.PUBLIC_SITE_URL, baseURL: env.OPENROUTER_BASE_URL });
  }
  if (choice === "anthropic" && env.ANTHROPIC_API_KEY) {
    return new AnthropicProvider(env.EXTRACTION_MODEL || DEFAULT_ANTHROPIC_MODEL, env.ANTHROPIC_API_KEY);
  }
  return null;
}

export type ExtractionResult = {
  draft: ExtractionDraft;
  provider: string;
  model: string;
  attempts: number;
  latencyMs: number;
  usage: { inputTokens: number | null; outputTokens: number | null; costUSD: number | null };
};

/**
 * Runs one extraction with a timeout and at most one retry for transient failures or output
 * that fails schema validation. Every response is validated before use.
 */
export async function runExtraction(
  input: ExtractionInput,
  provider: ExtractionProvider | null = configuredProvider(),
  opts: { timeoutMs?: number; maxAttempts?: number } = {},
): Promise<ExtractionResult> {
  if (!provider) throw new ExtractionError("AI extraction isn't configured on this server: set OPENROUTER_API_KEY (or ANTHROPIC_API_KEY).", 503);
  const maxAttempts = opts.maxAttempts ?? 2;
  const started = performance.now();
  let lastError: ProviderError | null = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const result = await provider.extract(input, AbortSignal.timeout(opts.timeoutMs ?? 25_000));
      const parsed = ExtractedRecipeSchema.safeParse(result.output);
      if (!parsed.success) throw new ProviderError("The model's answer didn't match the recipe schema.", 502, true);
      return {
        draft: toDraft(parsed.data), provider: provider.id, model: result.model, attempts: attempt,
        latencyMs: Math.round(performance.now() - started), usage: result.usage,
      };
    } catch (error) {
      if (!(error instanceof ProviderError)) throw error;
      lastError = error;
      if (!error.retryable || attempt === maxAttempts) break;
      await new Promise((r) => setTimeout(r, 400 * attempt));
    }
  }
  throw new ExtractionError(lastError?.message ?? "Extraction failed", lastError?.status ?? 502);
}
