import { describe, expect, it } from "vitest";
import seed from "../../../data/seed-recipes.json";
import { TransferDocumentSchema, normalize, validate, display, RecipeSettingsSchema } from "./schema";

describe("FilmLab JSON compatibility", () => {
  it("parses the app's export format and round-trips settings", () => {
    const doc = TransferDocumentSchema.parse(seed);
    expect(doc.recipes).toHaveLength(12);
    for (const r of doc.recipes) {
      expect(normalize(r.settings)).toEqual(r.settings); // app already normalized
      expect(validate(r.settings).filter((i) => i.severity === "error")).toEqual([]);
      expect(RecipeSettingsSchema.parse(JSON.parse(JSON.stringify(r.settings)))).toEqual(r.settings);
    }
  });

  it("applies the same dependency rules as the app", () => {
    const s = normalize(RecipeSettingsSchema.parse({
      filmSimulation: "acros",
      color: { state: "value", value: 2 },
      kelvin: { state: "value", value: 5000 },
      whiteBalance: { state: "value", value: "auto" },
      dRangePriority: { state: "value", value: "strong" },
      highlight: { state: "value", value: 1 },
    }));
    expect(s.color.state).toBe("notApplicable");
    expect(s.kelvin.state).toBe("notApplicable");
    expect(s.highlight.state).toBe("notApplicable");
    expect(s.monochromaticWarmCool.state).toBe("unset");
    expect(display(s, "filmSimulation")).toBe("ACROS");
  });

  it("flags out-of-range values", () => {
    const s = RecipeSettingsSchema.parse({ filmSimulation: "provia", clarity: { state: "value", value: 9 }, highlight: { state: "value", value: 0.25 } });
    expect(validate(s).map((i) => i.field).sort()).toEqual(["clarity", "highlight"]);
  });
});
