import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { CAMERAS, compatibility, cameraById, generationFromText, inferGeneration, recognizeCamera } from "./cameras";
import { RecipeSettingsSchema } from "./schema";

const settings = (o: Record<string, unknown>) => RecipeSettingsSchema.parse(o);
const v = <T,>(value: T) => ({ state: "value", value });

describe("camera catalog", () => {
  it("matches shared/camera-catalog.json (the iOS app reads the same data)", () => {
    const shared = path.resolve(import.meta.dirname, "../../../../shared/camera-catalog.json");
    const local = path.resolve(import.meta.dirname, "camera-catalog.json");
    expect(JSON.parse(fs.readFileSync(local, "utf8"))).toEqual(JSON.parse(fs.readFileSync(shared, "utf8")));
  });

  it("has unique ids and names", () => {
    expect(new Set(CAMERAS.map((c) => c.id)).size).toBe(CAMERAS.length);
    expect(new Set(CAMERAS.map((c) => c.name)).size).toBe(CAMERAS.length);
  });

  it("puts X-Processor 5 bodies in X-Trans V, including X-Trans 4-sensor ones", () => {
    for (const c of CAMERAS) expect(c.generation).toBe(c.processor === "X-Processor 5" ? "V" : "IV");
    expect(cameraById("x-t30-iii")!.generation).toBe("V");
    expect(cameraById("x-s20")!.generation).toBe("V");
  });
});

describe("recognizeCamera", () => {
  const cases: [string, string | null][] = [
    ["X-T30 III", "x-t30-iii"], ["Fujifilm X-T30 Mark III", "x-t30-iii"], ["xt30iii", "x-t30-iii"],
    ["X-T30 II", "x-t30-ii"], ["X-T30", "x-t30"], ["my X-T30 for street", "x-t30"],
    ["X100VI", "x100vi"], ["X100V", "x100v"], ["X100 V recipe", "x100v"],
    ["X-T5", "x-t5"], ["X-T50", "x-t50"], ["XT5", "x-t5"],
    ["X-H2S", "x-h2s"], ["X-H2", "x-h2"], ["X-Pro3", "x-pro3"], ["X-E4", "x-e4"], ["X-S20", "x-s20"], ["X-M5", "x-m5"],
    ["Canon R6", null], ["", null],
  ];
  it.each(cases)("%s → %s", (text, id) => expect(recognizeCamera(text)?.id ?? null).toBe(id));
});

describe("generations", () => {
  it.each([["X-Trans IV", "IV"], ["x-trans 5", "V"], ["X-Trans CMOS 4", "IV"], ["XTrans V recipe", "V"], ["X-T5", null]] as const)(
    "%s → %s", (text, g) => expect(generationFromText(text)).toBe(g));

  it("prefers the explicit tag, then V-only simulations, then the camera", () => {
    const base = { settings: settings({ filmSimulation: "classicChrome" }), compatibleCameras: ["X-T4"] };
    expect(inferGeneration({ ...base, xTransGeneration: "V" })).toBe("V");
    expect(inferGeneration({ ...base, settings: settings({ filmSimulation: "nostalgicNeg" }) })).toBe("V");
    expect(inferGeneration(base)).toBe("IV");
    expect(inferGeneration({ ...base, compatibleCameras: [] })).toBeNull();
    // "X-T30 III" used to be added to every recipe by default; another camera takes precedence.
    expect(inferGeneration({ ...base, compatibleCameras: ["X-T30 III", "X100V"] })).toBe("IV");
    expect(inferGeneration({ ...base, compatibleCameras: ["X-T30 III"] })).toBe("V");
  });
});

describe("compatibility", () => {
  it("REALA ACE isn't on X-Trans IV bodies", () => {
    expect(compatibility(settings({ filmSimulation: "realaAce" }), cameraById("x-t4")!).level).toBe("none");
    expect(compatibility(settings({ filmSimulation: "realaAce" }), cameraById("x-t5")!).level).toBe("full");
  });

  it("CLASSIC Neg. isn't on the X-T3", () => {
    expect(compatibility(settings({ filmSimulation: "classicNeg" }), cameraById("x-t3")!).level).toBe("none");
  });

  it("flags settings an early body lacks, but not when they're off", () => {
    const s = settings({ filmSimulation: "classicChrome", clarity: v(-2), colorChromeFXBlue: v("off"), highlight: v(-1.5) });
    const c = compatibility(s, cameraById("x-t30")!);
    expect(c.level).toBe("partial");
    expect(c.issues.map((i) => i.field).sort()).toEqual(["clarity", "highlight"]);
    expect(compatibility(s, cameraById("x-t30-iii")!).level).toBe("full");
  });
});
