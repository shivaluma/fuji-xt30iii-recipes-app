import { describe, expect, it } from "vitest";
import fixture from "./__fixtures__/lut-parity.json";
import { RecipeSettingsSchema } from "@/lib/recipe/schema";
import { lutKey, transform } from "./lut";

// Values exported from the Swift engine (FilmLUTBuilder.transform). Float32 vs float64 → small tolerance.
describe("LUT parity with the iOS engine", () => {
  it.each(fixture.cases.map((c) => [c.name, c] as const))("%s", (_name, c) => {
    const key = lutKey(RecipeSettingsSchema.parse(c.settings));
    for (const p of c.points) {
      const out = transform(p.in as [number, number, number], key);
      out.forEach((v, i) => expect(Math.abs(v - p.out[i])).toBeLessThan(2e-3));
    }
  });
});
