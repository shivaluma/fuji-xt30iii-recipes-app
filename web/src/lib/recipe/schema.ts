import { z } from "zod";

// TypeScript mirror of the iOS app's recipe model (FilmLab/Domain/Recipe/*.swift).
// The JSON shape is identical so recipes move between app and web unchanged:
//   RecipeField<T> = {"state":"unset"} | {"state":"notApplicable"} | {"state":"value","value":T}

export const FILM_SIMULATIONS = [
  "provia", "velvia", "astia", "classicChrome", "realaAce", "proNegHi", "proNegStd", "classicNeg",
  "nostalgicNeg", "eterna", "eternaBleachBypass", "acros", "acrosYe", "acrosR", "acrosG",
  "monochrome", "monochromeYe", "monochromeR", "monochromeG", "sepia",
] as const;
export type FilmSimulation = (typeof FILM_SIMULATIONS)[number];

export const FILM_SIMULATION_NAMES: Record<FilmSimulation, string> = {
  provia: "PROVIA/STANDARD", velvia: "Velvia/VIVID", astia: "ASTIA/SOFT", classicChrome: "CLASSIC CHROME",
  realaAce: "REALA ACE", proNegHi: "PRO Neg. Hi", proNegStd: "PRO Neg. Std", classicNeg: "CLASSIC Neg.",
  nostalgicNeg: "NOSTALGIC Neg.", eterna: "ETERNA/CINEMA", eternaBleachBypass: "ETERNA BLEACH BYPASS",
  acros: "ACROS", acrosYe: "ACROS+Ye FILTER", acrosR: "ACROS+R FILTER", acrosG: "ACROS+G FILTER",
  monochrome: "MONOCHROME", monochromeYe: "MONOCHROME+Ye FILTER", monochromeR: "MONOCHROME+R FILTER",
  monochromeG: "MONOCHROME+G FILTER", sepia: "SEPIA",
};

export const isMonochrome = (s: FilmSimulation) =>
  ["acros", "acrosYe", "acrosR", "acrosG", "monochrome", "monochromeYe", "monochromeR", "monochromeG", "sepia"].includes(s);
export const supportsMonochromaticColor = (s: FilmSimulation) => isMonochrome(s) && s !== "sepia";

export const EFFECT_LEVELS = ["off", "weak", "strong"] as const;
export const GRAIN_SIZES = ["small", "large"] as const;
export const WHITE_BALANCES = [
  "autoWhitePriority", "auto", "autoAmbiencePriority", "custom1", "custom2", "custom3", "colorTemperature",
  "daylight", "shade", "fluorescent1", "fluorescent2", "fluorescent3", "incandescent", "underwater",
] as const;
export const WHITE_BALANCE_NAMES: Record<(typeof WHITE_BALANCES)[number], string> = {
  autoWhitePriority: "White Priority", auto: "Auto", autoAmbiencePriority: "Ambience Priority",
  custom1: "Custom 1", custom2: "Custom 2", custom3: "Custom 3", colorTemperature: "Color Temperature",
  daylight: "Daylight", shade: "Shade", fluorescent1: "Fluorescent 1", fluorescent2: "Fluorescent 2",
  fluorescent3: "Fluorescent 3", incandescent: "Incandescent", underwater: "Underwater",
};
export const DYNAMIC_RANGES = ["auto", "dr100", "dr200", "dr400"] as const;
export const DR_PRIORITIES = ["off", "weak", "strong", "auto"] as const;
export const MOODS = ["warm", "cool", "neutral", "highContrast", "lowContrast", "muted", "vivid", "vintage", "cinematic", "blackAndWhite"] as const;

function field<T extends z.ZodType>(value: T) {
  return z.discriminatedUnion("state", [
    z.object({ state: z.literal("unset") }),
    z.object({ state: z.literal("notApplicable") }),
    z.object({ state: z.literal("value"), value }),
  ]);
}
const opt = <T extends z.ZodType>(v: T) => field(v).default({ state: "unset" });

export const RecipeSettingsSchema = z.object({
  filmSimulation: z.enum(FILM_SIMULATIONS),
  grainRoughness: opt(z.enum(EFFECT_LEVELS)),
  grainSize: opt(z.enum(GRAIN_SIZES)),
  colorChrome: opt(z.enum(EFFECT_LEVELS)),
  colorChromeFXBlue: opt(z.enum(EFFECT_LEVELS)),
  whiteBalance: opt(z.enum(WHITE_BALANCES)),
  kelvin: opt(z.number().int()),
  wbShiftRed: opt(z.number().int()),
  wbShiftBlue: opt(z.number().int()),
  dynamicRange: opt(z.enum(DYNAMIC_RANGES)),
  dRangePriority: opt(z.enum(DR_PRIORITIES)),
  highlight: opt(z.number()),
  shadow: opt(z.number()),
  color: opt(z.number().int()),
  sharpness: opt(z.number().int()),
  highISONR: opt(z.number().int()),
  clarity: opt(z.number().int()),
  monochromaticWarmCool: opt(z.number().int()),
  monochromaticMagentaGreen: opt(z.number().int()),
  suggestedExposureCompensation: opt(z.number()),
});
export type RecipeSettings = z.infer<typeof RecipeSettingsSchema>;
export type FieldKey = Exclude<keyof RecipeSettings, "filmSimulation">;

export const ProvenanceSchema = z.object({
  kind: z.enum(["filmLabOriginal", "userCreated", "duplicated", "imported", "cameraSlot"]),
  author: z.string().nullish(),
  sourceURL: z.string().nullish(),
  license: z.string().nullish(),
  derivedFrom: z.string().nullish(),
  note: z.string().nullish(),
});

/// FilmRecipe as exported by the app (dates are ISO-8601 strings).
export const FilmRecipeSchema = z.object({
  id: z.string().regex(/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/),
  name: z.string().min(1).max(120),
  summary: z.string().default(""),
  settings: RecipeSettingsSchema,
  tags: z.array(z.string()).default([]),
  moods: z.array(z.enum(MOODS)).default([]),
  isFavorite: z.boolean().default(false),
  compatibleCameras: z.array(z.string()).default(["X-T30 III"]),
  provenance: ProvenanceSchema,
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FilmRecipe = z.infer<typeof FilmRecipeSchema>;

export const TransferDocumentSchema = z.object({
  format: z.literal("filmlab.recipes"),
  schemaVersion: z.number().int().max(1),
  exportedAt: z.string(),
  appVersion: z.string().nullish(),
  recipes: z.array(FilmRecipeSchema).min(1),
});

// MARK: helpers

type AnyField = RecipeSettings[FieldKey];
export const valueOf = <T>(f: { state: string; value?: T }): T | undefined => (f.state === "value" ? f.value : undefined);
const set = <T>(value: T) => ({ state: "value" as const, value });
const unset = { state: "unset" as const };
const na = { state: "notApplicable" as const };

/** Same dependency rules as `RecipeSettings.normalized()` in Swift. */
export function normalize(s: RecipeSettings): RecipeSettings {
  const out = structuredClone(s) as RecipeSettings;
  const apply = (k: FieldKey, applicable: boolean) => {
    const f = out[k] as AnyField;
    if (applicable) {
      if (f.state === "notApplicable") (out as Record<string, unknown>)[k] = unset;
    } else (out as Record<string, unknown>)[k] = na;
  };
  const wb = valueOf(out.whiteBalance);
  const grain = valueOf(out.grainRoughness);
  const drp = valueOf(out.dRangePriority);
  const manual = drp === undefined || drp === "off";
  apply("kelvin", wb === "colorTemperature");
  apply("grainSize", grain !== "off");
  apply("color", !isMonochrome(out.filmSimulation));
  apply("monochromaticWarmCool", supportsMonochromaticColor(out.filmSimulation));
  apply("monochromaticMagentaGreen", supportsMonochromaticColor(out.filmSimulation));
  apply("dynamicRange", manual);
  apply("highlight", manual);
  apply("shadow", manual);
  return out;
}

/** X-T30 III ranges (manual where stated; see the iOS CameraProfile for provenance). */
export const RANGES: Partial<Record<FieldKey, { min: number; max: number; step: number }>> = {
  kelvin: { min: 2500, max: 10000, step: 10 },
  wbShiftRed: { min: -9, max: 9, step: 1 },
  wbShiftBlue: { min: -9, max: 9, step: 1 },
  highlight: { min: -2, max: 4, step: 0.5 },
  shadow: { min: -2, max: 4, step: 0.5 },
  color: { min: -4, max: 4, step: 1 },
  sharpness: { min: -4, max: 4, step: 1 },
  highISONR: { min: -4, max: 4, step: 1 },
  clarity: { min: -5, max: 5, step: 1 },
  monochromaticWarmCool: { min: -18, max: 18, step: 1 },
  monochromaticMagentaGreen: { min: -18, max: 18, step: 1 },
};

export type Issue = { field: string; severity: "error" | "warning"; message: string };

export function validate(s: RecipeSettings): Issue[] {
  const issues: Issue[] = [];
  for (const [k, r] of Object.entries(RANGES) as [FieldKey, { min: number; max: number; step: number }][]) {
    const v = valueOf(s[k] as { state: string; value?: number });
    if (v === undefined) continue;
    const steps = (v - r.min) / r.step;
    if (v < r.min || v > r.max || Math.abs(steps - Math.round(steps)) > 1e-6) {
      issues.push({ field: k, severity: "error", message: `${LABELS[k]} ${v} is outside ${r.min}…${r.max} (step ${r.step}).` });
    }
  }
  if (valueOf(s.whiteBalance) === "colorTemperature" && valueOf(s.kelvin) === undefined) {
    issues.push({ field: "kelvin", severity: "error", message: "Color Temperature white balance needs a Kelvin value." });
  }
  return issues;
}

export const LABELS: Record<FieldKey | "filmSimulation", string> = {
  filmSimulation: "Film Simulation", grainRoughness: "Grain Effect", grainSize: "Grain Size",
  colorChrome: "Color Chrome Effect", colorChromeFXBlue: "Color Chrome FX Blue", whiteBalance: "White Balance",
  kelvin: "Color Temperature", wbShiftRed: "WB Shift R", wbShiftBlue: "WB Shift B", dynamicRange: "Dynamic Range",
  dRangePriority: "D Range Priority", highlight: "Highlight", shadow: "Shadow", color: "Color",
  sharpness: "Sharpness", highISONR: "High ISO NR", clarity: "Clarity",
  monochromaticWarmCool: "Monochromatic WC", monochromaticMagentaGreen: "Monochromatic MG",
  suggestedExposureCompensation: "Exposure (suggested)",
};

const signed = (v: number) => (v > 0 ? `+${v}` : `${v}`);
const title = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export function display(s: RecipeSettings, k: FieldKey | "filmSimulation"): string {
  if (k === "filmSimulation") return FILM_SIMULATION_NAMES[s.filmSimulation];
  const f = s[k] as { state: string; value?: unknown };
  if (f.state === "unset") return "—";
  if (f.state === "notApplicable") return "n/a";
  const v = f.value;
  switch (k) {
    case "whiteBalance": return WHITE_BALANCE_NAMES[v as keyof typeof WHITE_BALANCE_NAMES];
    case "kelvin": return `${v}K`;
    case "dynamicRange": return v === "auto" ? "DR Auto" : `DR${String(v).slice(2)}`;
    case "grainRoughness": case "grainSize": case "colorChrome": case "colorChromeFXBlue": case "dRangePriority":
      return title(String(v));
    case "suggestedExposureCompensation": return `${signed(Math.round((v as number) * 100) / 100)} EV`;
    default: return signed(v as number);
  }
}

export const set_ = set; // re-exported for builders/tests
