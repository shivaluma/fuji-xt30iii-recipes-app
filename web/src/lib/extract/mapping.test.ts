import { describe, expect, it } from "vitest";
import { toDraft } from "./mapping";
import { blank } from "./test-fixtures";
import { extractionJSONSchema } from "./providers/types";


describe("extraction → draft", () => {
  it("maps values exactly, keeps nulls unset (0 ≠ missing), infers Kelvin WB", () => {
    const d = toDraft({ ...blank, name: "Overcast", filmSimulation: "classicChrome", kelvin: 5200, wbShiftRed: 0, wbShiftBlue: -3,
      highlight: -0.5, clarity: 0, colorChrome: "strong", exposureCompensation: 0.333, iso: "Auto up to 6400" });
    const s = d.settings!;
    expect(s.whiteBalance).toEqual({ state: "value", value: "colorTemperature" });
    expect(s.wbShiftRed).toEqual({ state: "value", value: 0 });
    expect(s.wbShiftBlue).toEqual({ state: "value", value: -3 });
    expect(s.clarity).toEqual({ state: "value", value: 0 });
    expect(s.sharpness).toEqual({ state: "unset" });
    expect(s.suggestedExposureCompensation).toEqual({ state: "value", value: 0.333 }); // not rounded
    expect(d.notes).toEqual(["ISO: Auto up to 6400"]);
    expect(d.issues).toEqual([]);
  });

  it("never changes invalid values; reports them instead", () => {
    const d = toDraft({ ...blank, filmSimulation: "provia", color: 6, highlight: 4.5, clarity: 1.5, kelvin: 12000 });
    expect(d.settings!.color).toEqual({ state: "value", value: 6 });
    expect(d.settings!.highlight).toEqual({ state: "value", value: 4.5 });
    const byField = Object.fromEntries(d.issues.map((i) => [i.field, i]));
    expect(byField.color.kind).toBe("invalid");
    expect(byField.highlight.kind).toBe("invalid");
    expect(byField.clarity.kind).toBe("invalid");
    expect(byField.kelvin.kind).toBe("unsupported");
    expect(d.settings!.clarity).toEqual({ state: "unset" }); // 1.5 can't be stored; extracted keeps it
    expect(d.extracted.clarity).toBe(1.5);
  });

  it("flags settings the X-T30 III doesn't have, and keeps them as notes", () => {
    const d = toDraft({ ...blank, filmSimulation: "classicChrome", otherSettings: [{ label: "Smooth Skin Effect", value: "Strong" }] });
    expect(d.issues[0]).toMatchObject({ kind: "unsupported", severity: "warning" });
    expect(d.issues[0].message).toMatch(/Portrait Enhancer/);
    expect(d.notes).toContain("Smooth Skin Effect: Strong");
  });

  it("warns (without discarding) when a value has no effect", () => {
    const d = toDraft({ ...blank, filmSimulation: "acros", color: 2 });
    expect(d.issues).toEqual([expect.objectContaining({ field: "color", kind: "notApplicable" })]);
    expect(d.extracted.color).toBe(2);
  });

  it("reports non-Fujifilm simulations and non-recipes", () => {
    expect(toDraft({ ...blank, filmSimulationText: "Kodachrome 64" }).issues[0]).toMatchObject({ kind: "unsupported" });
    const none = toDraft({ ...blank, isRecipe: false });
    expect(none.settings).toBeNull();
  });

  it("surfaces uncertain fields", () => {
    const d = toDraft({ ...blank, filmSimulation: "eterna", shadow: -1.5, uncertainFields: ["shadow"] });
    expect(d.issues).toEqual([expect.objectContaining({ field: "shadow", kind: "uncertain" })]);
  });

  it("produces a strict JSON schema (all properties required, no extras)", () => {
    const s = extractionJSONSchema() as { required: string[]; additionalProperties: boolean; properties: Record<string, unknown> };
    expect(s.additionalProperties).toBe(false);
    expect(s.required.sort()).toEqual(Object.keys(s.properties).sort());
    expect(JSON.stringify(s)).not.toContain('"$schema"');
  });
});
