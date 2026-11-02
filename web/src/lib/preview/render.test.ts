import { beforeAll, describe, expect, it } from "vitest";
import { RecipeSettingsSchema } from "@/lib/recipe/schema";
import { renderRecipe, whiteBalanceGains } from "./render";

beforeAll(() => {
  // Minimal ImageData for Node (the browser provides the real one).
  (globalThis as Record<string, unknown>).ImageData ??= class {
    data: Uint8ClampedArray;
    constructor(public width: number, public height: number) { this.data = new Uint8ClampedArray(width * height * 4); }
  };
});

function patch(r: number, g: number, b: number, w = 32, h = 32) {
  const img = new ImageData(w, h);
  for (let i = 0; i < w * h; i++) img.data.set([r, g, b, 255], i * 4);
  return img;
}
const s = (o: object) => RecipeSettingsSchema.parse({ filmSimulation: "provia", ...o });
const mean = (img: ImageData) => {
  const m = [0, 0, 0];
  for (let i = 0; i < img.data.length; i += 4) for (let c = 0; c < 3; c++) m[c] += img.data[i + c];
  return m.map((v) => v / (img.data.length / 4));
};

describe("browser preview renderer", () => {
  it("monochrome output is neutral", () => {
    const out = renderRecipe(patch(200, 80, 40), s({ filmSimulation: "acros" }));
    const [r, g, b] = mean(out);
    expect(Math.max(r, g, b) - Math.min(r, g, b)).toBeLessThan(2);
  });

  it("higher Kelvin renders warmer, lower cooler", () => {
    const warm = whiteBalanceGains(s({ whiteBalance: { state: "value", value: "colorTemperature" }, kelvin: { state: "value", value: 8000 } }));
    const cool = whiteBalanceGains(s({ whiteBalance: { state: "value", value: "colorTemperature" }, kelvin: { state: "value", value: 3200 } }));
    expect(warm[0] / warm[2]).toBeGreaterThan(1);
    expect(cool[0] / cool[2]).toBeLessThan(1);
  });

  it("grain is deterministic, mean-preserving-ish, and visible", () => {
    const grain = s({ grainRoughness: { state: "value", value: "strong" }, grainSize: { state: "value", value: "small" } });
    const a = renderRecipe(patch(128, 128, 128, 64, 64), grain), b = renderRecipe(patch(128, 128, 128, 64, 64), grain);
    expect(a.data).toEqual(b.data);
    const plain = renderRecipe(patch(128, 128, 128, 64, 64), s({}));
    expect(Math.abs(mean(a)[1] - mean(plain)[1])).toBeLessThan(3);
    const distinct = new Set(Array.from({ length: 64 * 64 }, (_, i) => a.data[i * 4 + 1]));
    expect(distinct.size).toBeGreaterThan(5);
  });

  it("different simulations differ", () => {
    const src = patch(90, 150, 210);
    expect(mean(renderRecipe(src, s({ filmSimulation: "velvia" })))).not.toEqual(mean(renderRecipe(src, s({ filmSimulation: "classicChrome" }))));
  });
});
