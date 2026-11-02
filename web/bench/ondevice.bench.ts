/** Scores the on-device baseline produced by scripts/bench/ondevice.sh (no network). */
import { it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { score, type Expected } from "./score";

it("on-device baseline", () => {
  const file = path.join(import.meta.dirname, "results", "ondevice.json");
  if (!fs.existsSync(file)) { console.log("run scripts/bench/ondevice.sh first"); return; }
  const results = JSON.parse(fs.readFileSync(file, "utf8")) as Record<string, { latencyMs: number; output: never }>;
  const expected: Record<string, Expected> = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, "expected.json"), "utf8"));
  const extra = process.env.BENCH_EXTRA_DIR;
  if (extra) Object.assign(expected, JSON.parse(fs.readFileSync(path.join(extra, "expected.json"), "utf8")));
  const rows = Object.entries(expected).filter(([id]) => !id.startsWith("_") && results[id])
    .map(([id, e]) => ({ id, latencyMs: results[id].latencyMs, ...score(e, results[id].output) }));
  const summary = {
    n: rows.length,
    fieldAccuracy: rows.reduce((a, r) => a + r.correct, 0) / rows.reduce((a, r) => a + r.total, 0),
    wholeRecipeExact: rows.filter((r) => r.exact).length / rows.length,
    rows,
  };
  fs.writeFileSync(path.join(import.meta.dirname, "results", "ondevice-scored.json"), JSON.stringify(summary, null, 2));
});
