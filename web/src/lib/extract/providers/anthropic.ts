import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod";
import { EXTRACTION_SYSTEM_PROMPT, ExtractedRecipeSchema } from "../mapping";
import { ProviderError, userText, type ExtractionInput, type ExtractionProvider, type ProviderResult } from "./types";

/** Claude via the official Anthropic SDK (optional alternative provider). */
export class AnthropicProvider implements ExtractionProvider {
  readonly id = "anthropic";
  private readonly client: Anthropic;
  constructor(readonly model: string, apiKey: string) {
    this.client = new Anthropic({ apiKey, maxRetries: 0 }); // retries are handled by the service
  }

  async extract(input: ExtractionInput, signal: AbortSignal): Promise<ProviderResult> {
    const content: Anthropic.Beta.BetaContentBlockParam[] = [];
    if (input.image) content.push({ type: "image", source: { type: "base64", media_type: input.image.mediaType, data: input.image.data } });
    content.push({ type: "text", text: userText(input) });
    try {
      const response = await this.client.beta.messages.parse({
        model: this.model,
        max_tokens: 4000,
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: { effort: "low", format: betaZodOutputFormat(ExtractedRecipeSchema) },
        system: EXTRACTION_SYSTEM_PROMPT,
        messages: [{ role: "user", content }],
      }, { signal });
      if (response.stop_reason === "refusal") throw new ProviderError("The model declined to read this input.", 422, false);
      if (response.stop_reason === "max_tokens") throw new ProviderError("The model's answer was cut off.", 502, true);
      return {
        output: response.parsed_output,
        model: response.model,
        usage: { inputTokens: response.usage.input_tokens, outputTokens: response.usage.output_tokens, costUSD: null },
      };
    } catch (error) {
      if (error instanceof ProviderError) throw error;
      if (error instanceof Anthropic.RateLimitError) throw new ProviderError("Too many requests right now.", 429, true);
      if (error instanceof Anthropic.AuthenticationError) throw new ProviderError("The server's Anthropic API key is invalid.", 500, false);
      if (error instanceof Anthropic.APIConnectionError) throw new ProviderError("Couldn't reach the AI provider.", 503, true);
      if (error instanceof Anthropic.APIError) throw new ProviderError(`AI provider error (${error.status}).`, 502, (error.status ?? 500) >= 500);
      throw error;
    }
  }
}
