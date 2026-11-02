import type { ExtractedRecipe } from "../src/lib/extract/mapping";

/** Fields scored for every fixture. A field missing from `expected` must come back null. */
export const SCORED_FIELDS = [
  "filmSimulation", "grainRoughness", "grainSize", "colorChrome", "colorChromeFXBlue", "whiteBalance", "kelvin",
  "wbShiftRed", "wbShiftBlue", "dynamicRange", "dRangePriority", "highlight", "shadow", "color", "sharpness",
  "highISONR", "clarity", "monochromaticWarmCool", "monochromaticMagentaGreen", "exposureCompensation",
] as const;

export type Expected = Partial<Record<(typeof SCORED_FIELDS)[number] | "name", string | number>> & { unsupportedLabels?: string[] };

const same = (a: unknown, b: unknown) =>
  typeof a === "number" && typeof b === "number" ? Math.abs(a - b) < 0.01 : (a ?? null) === (b ?? null);

export function score(expected: Expected, got: Partial<ExtractedRecipe> | null) {
  const misses: string[] = [];
  let correct = 0;
  for (const f of SCORED_FIELDS) {
    const e = expected[f] ?? null, g = got?.[f] ?? null;
    if (same(e, g)) correct++; else misses.push(`${f}: expected ${JSON.stringify(e)} got ${JSON.stringify(g)}`);
  }
  const unsupportedOK = (expected.unsupportedLabels ?? []).every((u) =>
    (got?.otherSettings ?? []).some((o) => o.label.toLowerCase().includes(u)));
  if (!unsupportedOK) misses.push(`otherSettings: expected ${expected.unsupportedLabels}`);
  return { correct, total: SCORED_FIELDS.length, exact: misses.length === 0, misses };
}
