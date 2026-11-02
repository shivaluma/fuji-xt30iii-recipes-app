import type { ExtractedRecipe } from "./mapping";

/** An all-null model answer to build test cases from. */
export const blank: ExtractedRecipe = {
  isRecipe: true, name: null, cameraModel: null, credit: null, filmSimulation: null, filmSimulationText: null,
  grainRoughness: null, grainSize: null, colorChrome: null, colorChromeFXBlue: null, whiteBalance: null, kelvin: null,
  wbShiftRed: null, wbShiftBlue: null, dynamicRange: null, dRangePriority: null, highlight: null, shadow: null, color: null,
  sharpness: null, highISONR: null, clarity: null, monochromaticWarmCool: null, monochromaticMagentaGreen: null,
  exposureCompensation: null, iso: null, otherSettings: [], raw: [], uncertainFields: [],
};
