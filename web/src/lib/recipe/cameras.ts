import catalog from "./camera-catalog.json";
import {
  FILM_SIMULATION_NAMES, LABELS, valueOf,
  type FieldKey, type FilmRecipe, type FilmSimulation, type RecipeSettings,
} from "./schema";

/**
 * Supported bodies and the X-Trans recipe families. The data is a copy of
 * shared/camera-catalog.json (the iOS app reads the same file; cameras.test.ts fails if they drift).
 *
 * "X-Trans IV" / "X-Trans V" is the recipe family the community uses. It follows the processor's
 * feature set, so X-Processor 5 bodies with an X-Trans CMOS 4 sensor (X-T30 III, X-S20, X-M5)
 * take X-Trans V recipes.
 */
export const GENERATIONS = ["V", "IV"] as const;
export type Generation = (typeof GENERATIONS)[number];
export const GENERATION_LABEL: Record<Generation, string> = { V: "X-Trans V", IV: "X-Trans IV" };

type Range = { min: number; max: number; step: number };
export type Camera = {
  id: string;
  name: string;
  aliases: string[];
  sensor: string;
  processor: string;
  generation: Generation;
  filmSimulations: FilmSimulation[];
  unsupported: FieldKey[];
  ranges: Partial<Record<FieldKey, Range>>;
  hasFilmSimulationDial: boolean;
  /** How the feature data is known: the owner's manual, or community reports. */
  status: "verifiedInDocs" | "reportedByThirdParty" | "notVerified";
  notes: string[];
};

type RawCamera = (typeof catalog.cameras)[number];
const sets = catalog.filmSimulationSets as Record<string, FilmSimulation[]>;
const baseRanges = catalog.baseRanges as Partial<Record<FieldKey, Range>>;

export const CAMERAS: Camera[] = catalog.cameras.map((c: RawCamera) => ({
  id: c.id, name: c.name, aliases: c.aliases, sensor: c.sensor, processor: c.processor,
  generation: c.xTransGeneration as Generation,
  filmSimulations: sets[c.filmSimulations],
  unsupported: c.unsupported as FieldKey[],
  ranges: { ...baseRanges, ...(c.ranges as Partial<Record<FieldKey, Range>>) },
  hasFilmSimulationDial: c.hasFilmSimulationDial,
  status: c.status as Camera["status"],
  notes: c.notes,
}));

export const REFERENCE_CAMERA = CAMERAS.find((c) => c.id === "x-t30-iii")!;
export const cameraById = (id: string) => CAMERAS.find((c) => c.id === id) ?? null;
export const camerasIn = (g: Generation) => CAMERAS.filter((c) => c.generation === g);

// ---------- Recognition ----------

const alnum = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, "");
const escape = (ch: string) => ch.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
/** Every key of every camera, longest first, so "X-T30 II" wins over "X-T30" and "X100VI" over "X100V". */
const KEYS = CAMERAS.flatMap((c) => [c.name, ...c.aliases].map((k) => ({ camera: c, key: alnum(k) })))
  .sort((a, b) => b.key.length - a.key.length)
  .map(({ camera, key }) => ({
    camera,
    // Characters in order, each optionally separated by one space or hyphen; not glued to other letters/digits.
    pattern: new RegExp(`(?<![A-Z0-9])${[...key].map(escape).join("[\\s-]?")}(?![A-Z0-9])`),
  }));

/** Finds the camera named in free text ("Fujifilm X-T30 Mark II", "xt5", "X100VI recipe"). */
export function recognizeCamera(text: string | null | undefined): Camera | null {
  if (!text) return null;
  const t = text.toUpperCase().replace(/FUJIFILM/g, " ").replace(/\bMARK\b/g, " ").replace(/\s+/g, " ");
  return KEYS.find((k) => k.pattern.test(t))?.camera ?? null;
}

/** "X-Trans IV", "X-Trans CMOS 5", "xtrans v" → generation. */
export function generationFromText(text: string | null | undefined): Generation | null {
  const m = text?.match(/X[\s-]?TRANS[\s-]?(?:CMOS[\s-]?)?(IV|V|4|5)\b/i);
  if (!m) return null;
  return m[1].toUpperCase() === "IV" || m[1] === "4" ? "IV" : "V";
}

/** Simulations that only exist on X-Processor 5 bodies. */
const V_ONLY: FilmSimulation[] = ["realaAce", "nostalgicNeg"];

/**
 * The recipe's family: an explicit tag wins; otherwise a simulation only X-Trans V has; otherwise
 * the camera the recipe was made for; otherwise unknown. "X-T30 III" was historically added to
 * every recipe by default, so it only counts when no other camera is listed.
 */
export function inferGeneration(r: Pick<FilmRecipe, "settings" | "compatibleCameras"> & { xTransGeneration?: Generation | null }): Generation | null {
  if (r.xTransGeneration) return r.xTransGeneration;
  if (V_ONLY.includes(r.settings.filmSimulation)) return "V";
  const others = r.compatibleCameras.filter((c) => recognizeCamera(c)?.id !== REFERENCE_CAMERA.id);
  for (const c of others.length ? others : r.compatibleCameras) {
    const g = recognizeCamera(c)?.generation ?? generationFromText(c);
    if (g) return g;
  }
  return null;
}

// ---------- Compatibility ----------

export type CameraIssue = { field: FieldKey | "filmSimulation"; message: string };
export type Compatibility = { camera: Camera; level: "full" | "partial" | "none"; issues: CameraIssue[] };

/** What happens if you dial this recipe into `camera`: everything works, some settings don't, or the simulation is missing. */
export function compatibility(s: RecipeSettings, camera: Camera): Compatibility {
  if (!camera.filmSimulations.includes(s.filmSimulation)) {
    return { camera, level: "none", issues: [{ field: "filmSimulation", message: `${FILM_SIMULATION_NAMES[s.filmSimulation]} isn't available on the ${camera.name}.` }] };
  }
  const issues: CameraIssue[] = [];
  for (const k of Object.keys(s) as (FieldKey | "filmSimulation")[]) {
    if (k === "filmSimulation") continue;
    const v = valueOf(s[k] as { state: string; value?: unknown });
    if (v === undefined) continue;
    if (camera.unsupported.includes(k)) {
      // "Off" is what a camera without the feature does anyway.
      if (v !== "off") issues.push({ field: k, message: `No ${LABELS[k]} on the ${camera.name}.` });
      continue;
    }
    const r = camera.ranges[k];
    if (r && typeof v === "number") {
      const steps = (v - r.min) / r.step;
      if (v < r.min || v > r.max || Math.abs(steps - Math.round(steps)) > 1e-6) {
        issues.push({ field: k, message: `${LABELS[k]} ${v > 0 ? "+" : ""}${v} isn't available on the ${camera.name} (${r.min}…+${r.max}, step ${r.step}).` });
      }
    }
  }
  return { camera, level: issues.length ? "partial" : "full", issues };
}

/** Compatibility with every catalog body, X-Trans V first. */
export const worksOn = (s: RecipeSettings) => GENERATIONS.flatMap((g) => camerasIn(g).map((c) => compatibility(s, c)));
