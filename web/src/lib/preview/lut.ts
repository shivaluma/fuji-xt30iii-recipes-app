// Port of FilmLab/Services/Preview/FilmLookProfiles.swift (FilmLookProfile + FilmLUTBuilder).
// FilmLab's ORIGINAL placeholder looks — approximations, not Fujifilm processing.
// Keep in sync with Swift; `lut.test.ts` checks parity against values exported from Swift.
import type { FilmSimulation, RecipeSettings } from "@/lib/recipe/schema";
import { valueOf } from "@/lib/recipe/schema";

type V3 = [number, number, number];
type HueBand = { center: number; width: number; saturation: number; hueShift: number; lightness?: number };
type Profile = {
  contrast: number; saturation: number; blackLift: number; highlightRolloff: number;
  shadowTint: V3; highlightTint: V3; hueBands: HueBand[]; monoMix?: V3; monoTone: V3;
};

const base = (p: Partial<Profile>): Profile => ({
  contrast: 0, saturation: 1, blackLift: 0, highlightRolloff: 0.05,
  shadowTint: [0, 0, 0], highlightTint: [0, 0, 0], hueBands: [], monoTone: [0, 0, 0], ...p,
});
const LUMA: V3 = [0.2126, 0.7152, 0.0722], YE: V3 = [0.32, 0.62, 0.06], R: V3 = [0.55, 0.4, 0.05], G: V3 = [0.18, 0.74, 0.08];

export function profile(sim: FilmSimulation): Profile {
  switch (sim) {
    case "provia": return base({ contrast: 0.12, saturation: 1.05 });
    case "velvia": return base({ contrast: 0.28, saturation: 1.38, highlightRolloff: 0.03, hueBands: [
      { center: 120, width: 50, saturation: 1.15, hueShift: -4 }, { center: 220, width: 40, saturation: 1.15, hueShift: 4, lightness: -0.03 }] });
    case "astia": return base({ contrast: 0.05, saturation: 1.1, highlightRolloff: 0.1, hueBands: [
      { center: 25, width: 30, saturation: 0.92, hueShift: 2, lightness: 0.02 }] });
    case "classicChrome": return base({ contrast: 0.2, saturation: 0.72, blackLift: 0.01, shadowTint: [0, 0.006, 0.01], highlightTint: [0.012, 0.006, -0.008], hueBands: [
      { center: 210, width: 45, saturation: 0.85, hueShift: -10, lightness: -0.04 }, { center: 0, width: 30, saturation: 0.8, hueShift: 4 },
      { center: 110, width: 45, saturation: 0.75, hueShift: -8 }] });
    case "realaAce": return base({ contrast: 0.16, saturation: 1.08, highlightRolloff: 0.06, hueBands: [
      { center: 30, width: 25, saturation: 1.0, hueShift: 0, lightness: 0.01 }] });
    case "proNegHi": return base({ contrast: 0.14, saturation: 0.96, highlightRolloff: 0.08, hueBands: [
      { center: 25, width: 30, saturation: 0.94, hueShift: 1, lightness: 0.015 }] });
    case "proNegStd": return base({ contrast: -0.05, saturation: 0.88, highlightRolloff: 0.12, hueBands: [
      { center: 25, width: 30, saturation: 0.92, hueShift: 1, lightness: 0.02 }] });
    case "classicNeg": return base({ contrast: 0.26, saturation: 0.9, blackLift: 0.02, highlightRolloff: 0.08, shadowTint: [-0.01, 0.012, 0.02], highlightTint: [0.025, 0.01, -0.02], hueBands: [
      { center: 110, width: 50, saturation: 0.85, hueShift: 18 }, { center: 0, width: 25, saturation: 1.05, hueShift: -6, lightness: -0.02 },
      { center: 200, width: 40, saturation: 0.9, hueShift: 8 }] });
    case "nostalgicNeg": return base({ contrast: 0.1, saturation: 0.98, blackLift: 0.015, highlightRolloff: 0.14, shadowTint: [0.005, 0, -0.005], highlightTint: [0.035, 0.018, -0.03], hueBands: [
      { center: 40, width: 35, saturation: 1.12, hueShift: -3 }] });
    case "eterna": return base({ contrast: -0.12, saturation: 0.7, blackLift: 0.025, highlightRolloff: 0.18, shadowTint: [-0.004, 0.006, 0.01], hueBands: [
      { center: 180, width: 60, saturation: 0.95, hueShift: -6 }] });
    case "eternaBleachBypass": return base({ contrast: 0.38, saturation: 0.32, blackLift: 0.01, highlightRolloff: 0.04, shadowTint: [0, 0.004, 0.006], highlightTint: [0.008, 0.008, 0.004] });
    case "acros": return base({ contrast: 0.24, saturation: 0, highlightRolloff: 0.08, monoMix: LUMA });
    case "acrosYe": return base({ contrast: 0.26, saturation: 0, highlightRolloff: 0.08, monoMix: YE });
    case "acrosR": return base({ contrast: 0.3, saturation: 0, highlightRolloff: 0.08, monoMix: R });
    case "acrosG": return base({ contrast: 0.24, saturation: 0, highlightRolloff: 0.08, monoMix: G });
    case "monochrome": return base({ contrast: 0.1, saturation: 0, monoMix: LUMA });
    case "monochromeYe": return base({ contrast: 0.12, saturation: 0, monoMix: YE });
    case "monochromeR": return base({ contrast: 0.16, saturation: 0, monoMix: R });
    case "monochromeG": return base({ contrast: 0.1, saturation: 0, monoMix: G });
    case "sepia": return base({ contrast: 0.06, saturation: 0, blackLift: 0.01, monoMix: LUMA, monoTone: [0.09, 0.03, -0.07] });
  }
}

export type LUTKey = {
  simulation: FilmSimulation; highlight: number; shadow: number; color: number;
  colorChrome: string; colorChromeFXBlue: string; monoWarmCool: number; monoMagentaGreen: number;
  highlightProtection: number; shadowProtection: number;
};

export function lutKey(s: RecipeSettings): LUTKey {
  const drp = valueOf(s.dRangePriority) ?? "off";
  const manual = drp === "off";
  const dr = valueOf(s.dynamicRange) ?? "dr100";
  let hp = 0, sp = 0;
  if (!manual) { if (drp === "strong") { hp = 2; sp = 0.8 } else if (drp === "weak") { hp = 1; sp = 0.4 } else { hp = 1.5; sp = 0.6 } }
  else if (dr === "dr400") hp = 2; else if (dr === "dr200") hp = 1; else if (dr === "auto") hp = 0.5;
  return {
    simulation: s.filmSimulation,
    highlight: manual ? valueOf(s.highlight) ?? 0 : 0,
    shadow: manual ? valueOf(s.shadow) ?? 0 : 0,
    color: valueOf(s.color) ?? 0,
    colorChrome: valueOf(s.colorChrome) ?? "off",
    colorChromeFXBlue: valueOf(s.colorChromeFXBlue) ?? "off",
    monoWarmCool: valueOf(s.monochromaticWarmCool) ?? 0,
    monoMagentaGreen: valueOf(s.monochromaticMagentaGreen) ?? 0,
    highlightProtection: hp, shadowProtection: sp,
  };
}

const clamp01 = (x: number) => Math.min(Math.max(x, 0), 1);
const dot = (a: V3, b: V3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
// Swift uses fmodf (sign of dividend), not a positive modulo.
const fmod = (a: number, b: number) => a % b;

export function sCurve(x: number, k: number) {
  const s = x * x * (3 - 2 * x);
  return k >= 0 ? x + (s - x) * Math.min(k * 2.2, 1) : x + (0.5 + (x - 0.5) * 0.7 - x) * Math.min(-k * 2.2, 1);
}
export function rolloff(x: number, amount: number) {
  if (amount <= 0) return x;
  const knee = 1 - amount;
  if (x <= knee) return x;
  const t = (x - knee) / amount;
  return knee + amount * (t - 0.35 * t * t);
}
const chroma = (c: V3) => Math.max(...c) - Math.min(...c);
function bandWeight(hue: number, center: number, width: number) {
  let d = Math.abs(hue - center) % 360;
  if (d > 180) d = 360 - d;
  if (d >= width) return 0;
  const t = 1 - d / width;
  return t * t * (3 - 2 * t);
}
function rgbToHSV(c: V3): V3 {
  const mx = Math.max(...c), mn = Math.min(...c), d = mx - mn;
  let h = 0;
  if (d > 1e-6) {
    if (mx === c[0]) h = 60 * fmod((c[1] - c[2]) / d, 6);
    else if (mx === c[1]) h = 60 * ((c[2] - c[0]) / d + 2);
    else h = 60 * ((c[0] - c[1]) / d + 4);
  }
  if (h < 0) h += 360;
  return [h, mx > 0 ? d / mx : 0, mx];
}
function hsvToRGB([hh, s, v]: V3): V3 {
  const h = fmod(hh, 360) / 60, c = v * s, x = c * (1 - Math.abs(fmod(h, 2) - 1)), m = v - c;
  const i = Math.trunc(h);
  const rgb: V3 = i === 0 ? [c, x, 0] : i === 1 ? [x, c, 0] : i === 2 ? [0, c, x] : i === 3 ? [0, x, c] : i === 4 ? [x, 0, c] : [c, 0, x];
  return [rgb[0] + m, rgb[1] + m, rgb[2] + m];
}

function applyTone(c: V3, key: LUTKey): V3 {
  const curve = (x: number) => {
    let v = x;
    const sw = Math.max(0, 1 - v * 2);
    v -= key.shadow * 0.035 * sw * sw * 4 * v;
    v += key.shadowProtection * 0.06 * sw;
    const hw = Math.max(0, v * 2 - 1);
    v += key.highlight * 0.03 * hw * hw * 4 * (1 - v);
    if (key.highlightProtection > 0) v = rolloff(v, 0.12 * key.highlightProtection);
    return clamp01(v);
  };
  return [curve(c[0]), curve(c[1]), curve(c[2])];
}

/** One sRGB-encoded colour (0…1) through the look. Mirrors FilmLUTBuilder.transform. */
export function transform(input: V3, key: LUTKey): V3 {
  const p = profile(key.simulation);
  let c: V3 = [clamp01(input[0]), clamp01(input[1]), clamp01(input[2])];
  c = applyTone(c, key);

  if (p.monoMix) {
    let y = dot(c, p.monoMix);
    y = sCurve(y, p.contrast);
    y = rolloff(y, p.highlightRolloff);
    if (key.colorChrome !== "off") y -= chroma(input) * (key.colorChrome === "strong" ? 0.08 : 0.04) * y;
    const mid = 4 * y * (1 - y);
    const wc = key.monoWarmCool / 18, mg = key.monoMagentaGreen / 18;
    let out: V3 = [y, y, y];
    out = out.map((v, i) => v + p.monoTone[i] * mid) as V3;
    out = [out[0] + wc * 0.06 * mid, out[1], out[2] - wc * 0.06 * mid];
    out = [out[0] + mg * 0.03 * mid, out[1] - mg * 0.05 * mid, out[2] + mg * 0.03 * mid];
    return out.map((v) => clamp01(p.blackLift + v * (1 - p.blackLift))) as V3;
  }

  const hsv = rgbToHSV(c);
  let bandSat = 1, bandLight = 0;
  for (const b of p.hueBands) {
    const w = bandWeight(hsv[0], b.center, b.width);
    if (w <= 0) continue;
    hsv[0] += b.hueShift * w;
    bandSat *= 1 + (b.saturation - 1) * w;
    bandLight += (b.lightness ?? 0) * w * hsv[1];
  }
  hsv[1] = Math.min(hsv[1] * p.saturation * bandSat * (1 + key.color * 0.09), 1);
  hsv[0] = fmod(hsv[0] + 360, 360);
  c = hsvToRGB(hsv).map((v) => v + bandLight) as V3;

  if (key.colorChrome !== "off") {
    const ch = chroma(c), a = key.colorChrome === "strong" ? 0.16 : 0.08;
    c = c.map((v) => v * (1 - a * ch * ch)) as V3;
  }
  if (key.colorChromeFXBlue !== "off") {
    const w = bandWeight(hsv[0], 220, 40) * hsv[1], a = key.colorChromeFXBlue === "strong" ? 0.2 : 0.1;
    c = c.map((v) => v * (1 - a * w)) as V3;
    c[2] += a * 0.25 * w;
  }
  c = c.map((v) => rolloff(sCurve(v, p.contrast), p.highlightRolloff)) as V3;
  const y = dot(c, LUMA);
  c = c.map((v, i) => v + p.shadowTint[i] * (1 - y) * (1 - y) + p.highlightTint[i] * y * y) as V3;
  return c.map((v) => clamp01(p.blackLift + v * (1 - p.blackLift))) as V3;
}

export const LUT_DIMENSION = 25;

/** RGB float cube, red fastest (same layout as the Swift CIColorCube data minus alpha). */
export function buildCube(key: LUTKey, n = LUT_DIMENSION): Float32Array {
  const out = new Float32Array(n * n * n * 3);
  const s = 1 / (n - 1);
  let i = 0;
  for (let b = 0; b < n; b++) for (let g = 0; g < n; g++) for (let r = 0; r < n; r++) {
    const o = transform([r * s, g * s, b * s], key);
    out[i++] = o[0]; out[i++] = o[1]; out[i++] = o[2];
  }
  return out;
}
