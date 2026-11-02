/**
 * Extraction benchmark. Real API calls — costs money (typically well under $0.10 per full run).
 *   OPENROUTER_API_KEY=… pnpm bench
 *   BENCH_MODELS=google/gemini-3.1-flash-lite,qwen/qwen3-vl-8b-instruct  (comma list)
 *   BENCH_EXTRA_DIR=/path/with/*.jpg + expected.json   (extra private fixtures, e.g. real screenshots)
 *   BENCH_RUNS=1
 * Writes bench/results/<date>.json and prints a summary table.
 */
import { it, vi } from "vitest";
vi.mock("server-only", () => ({}));
import fs from "node:fs";
import path from "node:path";
import { OpenRouterProvider } from "../src/lib/extract/providers/openrouter";
import { runExtraction } from "../src/lib/extract/service";
import { score, type Expected } from "./score";

const DIR = path.join(__dirname, "fixtures");
const MODELS = (process.env.BENCH_MODELS ?? "google/gemini-3.1-flash-lite").split(",").map((s) => s.trim()).filter(Boolean);
const RUNS = Number(process.env.BENCH_RUNS ?? 1);

type Case = { id: string; file: string; expected: Expected; source: "synthetic" | "extra" };
function cases(): Case[] {
  const out: Case[] = [];
  const exp = JSON.parse(fs.readFileSync(path.join(__dirname, "expected.json"), "utf8")) as Record<string, Expected>;
  for (const [id, expected] of Object.entries(exp)) if (!id.startsWith("_")) out.push({ id, file: path.join(DIR, `${id}.png`), expected, source: "synthetic" });
  const extra = process.env.BENCH_EXTRA_DIR;
  if (extra) {
    const e = JSON.parse(fs.readFileSync(path.join(extra, "expected.json"), "utf8")) as Record<string, Expected>;
    for (const [id, expected] of Object.entries(e)) {
      const file = ["jpg", "png", "jpeg", "webp"].map((x) => path.join(extra, `${id}.${x}`)).find(fs.existsSync);
      if (file) out.push({ id, file, expected, source: "extra" });
    }
  }
  return out;
}
const mime = (f: string) => (f.endsWith(".png") ? "image/png" : f.endsWith(".webp") ? "image/webp" : "image/jpeg") as "image/png";
const pct = (xs: number[], p: number) => { const s = [...xs].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)] ?? 0; };

it("benchmark", { timeout: 30 * 60_000 }, async () => {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) { console.log("OPENROUTER_API_KEY not set — skipping"); return; }
  const all = cases();
  const report = await Promise.all(MODELS.map(async (model) => {
    const provider = new OpenRouterProvider(model, key);
    const rows = [];
    for (let run = 0; run < RUNS; run++) {
      for (const c of all) {
        const image = { data: fs.readFileSync(c.file).toString("base64"), mediaType: mime(c.file) };
        try {
          const r = await runExtraction({ image }, provider);
          rows.push({ id: c.id, source: c.source, ok: true, ...score(c.expected, r.draft.extracted), latencyMs: r.latencyMs, attempts: r.attempts, usage: r.usage });
        } catch (e) {
          rows.push({ id: c.id, source: c.source, ok: false, error: (e as Error).message, ...score(c.expected, null), latencyMs: null, attempts: 2, usage: null });
        }
      }
    }
    const ok = rows.filter((r) => r.ok);
    const lat = ok.map((r) => r.latencyMs!);
    const cost = ok.reduce((a, r) => a + (r.usage?.costUSD ?? 0), 0);
    const exact = rows.filter((r) => r.exact).length;
    return {
      model, n: rows.length,
      fieldAccuracy: rows.reduce((a, r) => a + r.correct, 0) / rows.reduce((a, r) => a + r.total, 0),
      wholeRecipeExact: exact / rows.length,
      failures: rows.length - ok.length,
      retries: ok.filter((r) => r.attempts > 1).length,
      p50ms: pct(lat, 50), p95ms: pct(lat, 95),
      avgInputTokens: Math.round(ok.reduce((a, r) => a + (r.usage?.inputTokens ?? 0), 0) / Math.max(ok.length, 1)),
      avgOutputTokens: Math.round(ok.reduce((a, r) => a + (r.usage?.outputTokens ?? 0), 0) / Math.max(ok.length, 1)),
      avgCostUSD: cost / Math.max(ok.length, 1),
      costPerCorrectRecipeUSD: exact ? cost / exact : null,
      rows,
    };
  }));
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  fs.mkdirSync(path.join(__dirname, "results"), { recursive: true });
  fs.writeFileSync(path.join(__dirname, "results", `${stamp}.json`), JSON.stringify({ date: new Date().toISOString(), runs: RUNS, cases: all.map((c) => `${c.id} (${c.source})`), report }, null, 2));
  console.log("\n| model | field acc | whole-recipe exact | p50 ms | p95 ms | in tok | out tok | $/extraction | $/correct recipe | failures | retries |\n|---|---|---|---|---|---|---|---|---|---|---|");
  for (const m of report) console.log(`| ${m.model} | ${(m.fieldAccuracy * 100).toFixed(1)}% | ${(m.wholeRecipeExact * 100).toFixed(0)}% (${Math.round(m.wholeRecipeExact * m.n)}/${m.n}) | ${m.p50ms} | ${m.p95ms} | ${m.avgInputTokens} | ${m.avgOutputTokens} | ${m.avgCostUSD.toFixed(6)} | ${m.costPerCorrectRecipeUSD?.toFixed(6) ?? "–"} | ${m.failures} | ${m.retries} |`);
  for (const m of report) for (const r of m.rows) if (!r.exact) console.log(`  [${m.model}] ${r.id}: ${"error" in r ? r.error : r.misses.join("; ")}`);
});
