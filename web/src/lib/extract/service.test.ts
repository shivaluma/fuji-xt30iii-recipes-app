import { describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
import { runExtraction, configuredProvider, ExtractionError } from "./service";
import { ProviderError, type ExtractionProvider } from "./providers/types";
import { blank } from "./test-fixtures";

function mockProvider(...responses: (unknown | Error)[]): ExtractionProvider & { calls: number } {
  const p = {
    id: "mock", model: "mock-1", calls: 0,
    async extract() {
      const r = responses[Math.min(p.calls++, responses.length - 1)];
      if (r instanceof Error) throw r;
      return { output: r, model: "mock-1", usage: { inputTokens: 100, outputTokens: 50, costUSD: 0.0001 } };
    },
  };
  return p;
}

describe("extraction service (mocked model)", () => {
  it("validates and maps a good response", async () => {
    const p = mockProvider({ ...blank, filmSimulation: "velvia", highlight: -1 });
    const r = await runExtraction({ text: "x" }, p);
    expect(r.attempts).toBe(1);
    expect(r.draft.settings!.highlight).toEqual({ state: "value", value: -1 });
    expect(r.usage.costUSD).toBe(0.0001);
  });

  it("retries once when the output fails schema validation", async () => {
    const p = mockProvider({ nope: true }, { ...blank, filmSimulation: "provia" });
    const r = await runExtraction({ text: "x" }, p);
    expect(p.calls).toBe(2);
    expect(r.attempts).toBe(2);
  });

  it("gives up after the retry budget on repeated transient errors", async () => {
    const p = mockProvider(new ProviderError("busy", 503, true));
    await expect(runExtraction({ text: "x" }, p)).rejects.toBeInstanceOf(ExtractionError);
    expect(p.calls).toBe(2);
  });

  it("does not retry non-retryable errors", async () => {
    const p = mockProvider(new ProviderError("refused", 422, false));
    await expect(runExtraction({ text: "x" }, p)).rejects.toMatchObject({ status: 422 });
    expect(p.calls).toBe(1);
  });

  it("reports when no provider is configured", async () => {
    await expect(runExtraction({ text: "x" }, null)).rejects.toMatchObject({ status: 503 });
  });

  it("selects the provider from env", () => {
    expect(configuredProvider({})).toBeNull();
    expect(configuredProvider({ OPENROUTER_API_KEY: "k" })?.model).toBe("google/gemini-3.1-flash-lite");
    expect(configuredProvider({ OPENROUTER_API_KEY: "k", EXTRACTION_MODEL: "qwen/x" })?.model).toBe("qwen/x");
    expect(configuredProvider({ ANTHROPIC_API_KEY: "k" })?.id).toBe("anthropic");
  });
});
