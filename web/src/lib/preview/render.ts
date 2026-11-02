// Browser-side approximate preview, following the same stage order as the iOS FilmLookEngine:
// exposure/WB (linear) → film LUT (sRGB-encoded, trilinear) → grain. Clarity/sharpness/NR are
// not simulated on the web. Output is an APPROXIMATION of FilmLab's on-device look, which is
// itself an approximation — never Fujifilm's processing.
import type { RecipeSettings } from "@/lib/recipe/schema";
import { valueOf } from "@/lib/recipe/schema";
import { buildCube, lutKey, LUT_DIMENSION } from "./lut";

export const WEB_ENGINE_VERSION = "filmlab-approx-1-web";

const PRESET_KELVIN: Record<string, number> = {
  daylight: 5500, shade: 7500, fluorescent1: 6500, fluorescent2: 5000, fluorescent3: 4000, incandescent: 3000, underwater: 6000,
};

const toLinear = (c: number) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
const toSRGB = (c: number) => (c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);

/** Approximate RGB of a blackbody (Tanner Helland fit), linearised. */
function kelvinRGB(k: number): [number, number, number] {
  const t = k / 100;
  const r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
  const g = t <= 66 ? 99.4708025861 * Math.log(t) - 161.1195681661 : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
  const b = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
  const c = (v: number) => toLinear(Math.min(Math.max(v, 1), 255) / 255);
  return [c(r), c(g), c(b)];
}

/** Per-channel linear gains: shooting with WB set to `k` under ~5500 K light. */
export function whiteBalanceGains(s: RecipeSettings): [number, number, number] {
  const wb = valueOf(s.whiteBalance);
  let k: number | undefined = wb === "colorTemperature" ? valueOf(s.kelvin) : wb ? PRESET_KELVIN[wb] : undefined;
  const gains: [number, number, number] = [1, 1, 1];
  if (k) {
    k = Math.min(Math.max(k, 2000), 12000);
    const src = kelvinRGB(5500), set = kelvinRGB(k);
    // Camera divides by the assumed illuminant; normalise on green.
    for (let i = 0; i < 3; i++) gains[i] = (src[i] / src[1]) / (set[i] / set[1]);
  }
  const red = valueOf(s.wbShiftRed) ?? 0, blue = valueOf(s.wbShiftBlue) ?? 0;
  gains[0] *= 1 + red * 0.025;
  gains[1] *= 1 - (red + blue) * 0.004;
  gains[2] *= 1 + blue * 0.025;
  return gains;
}

/** Deterministic hash noise in [0,1). */
function noise(x: number, y: number) {
  let h = (x * 374761393 + y * 668265263) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

export function renderRecipe(src: ImageData, s: RecipeSettings): ImageData {
  const { width: w, height: h, data } = src;
  const out = new ImageData(w, h);
  const o = out.data;
  const n = LUT_DIMENSION, cube = buildCube(lutKey(s), n);
  const ev = Math.pow(2, valueOf(s.suggestedExposureCompensation) ?? 0);
  const [gr, gg, gb] = whiteBalanceGains(s);
  const rough = valueOf(s.grainRoughness);
  const grainAmp = rough === "strong" ? 0.34 : rough === "weak" ? 0.2 : 0;
  const grainPx = Math.max(1, Math.min(w, h) / 1400) * (valueOf(s.grainSize) === "large" ? 2.2 : 1.1);

  // Linearisation table for 8-bit input.
  const lin = new Float32Array(256);
  for (let i = 0; i < 256; i++) lin[i] = toLinear(i / 255);
  const m = n - 1;
  const at = (r: number, g: number, b: number, c: number) => cube[((b * n + g) * n + r) * 3 + c];

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      // Linear exposure + WB, then back to sRGB encoding for the LUT.
      const r = toSRGB(Math.min(lin[data[i]] * ev * gr, 1));
      const g = toSRGB(Math.min(lin[data[i + 1]] * ev * gg, 1));
      const b = toSRGB(Math.min(lin[data[i + 2]] * ev * gb, 1));
      // Trilinear LUT lookup.
      const fr = r * m, fg = g * m, fb = b * m;
      const r0 = Math.min(Math.floor(fr), m - 1), g0 = Math.min(Math.floor(fg), m - 1), b0 = Math.min(Math.floor(fb), m - 1);
      const dr = fr - r0, dg = fg - g0, db = fb - b0;
      let gainN = 1;
      if (grainAmp > 0) gainN = 1 + (noise(Math.floor(x / grainPx), Math.floor(y / grainPx)) - 0.5) * grainAmp;
      for (let c = 0; c < 3; c++) {
        const c00 = at(r0, g0, b0, c) * (1 - dr) + at(r0 + 1, g0, b0, c) * dr;
        const c10 = at(r0, g0 + 1, b0, c) * (1 - dr) + at(r0 + 1, g0 + 1, b0, c) * dr;
        const c01 = at(r0, g0, b0 + 1, c) * (1 - dr) + at(r0 + 1, g0, b0 + 1, c) * dr;
        const c11 = at(r0, g0 + 1, b0 + 1, c) * (1 - dr) + at(r0 + 1, g0 + 1, b0 + 1, c) * dr;
        let v = (c00 * (1 - dg) + c10 * dg) * (1 - db) + (c01 * (1 - dg) + c11 * dg) * db;
        // Multiplicative grain in linear light (luminance-only, mean-preserving).
        if (gainN !== 1) v = toSRGB(Math.min(toLinear(v) * gainN, 1));
        o[i + c] = Math.round(v * 255);
      }
      o[i + 3] = 255;
    }
  }
  return out;
}
