import { display, LABELS, type FieldKey, type RecipeSettings } from "@/lib/recipe/schema";
import { cn } from "@/lib/utils";

const SECONDARY: FieldKey[] = [
  "colorChrome", "colorChromeFXBlue", "dynamicRange", "highlight", "shadow",
  "color", "sharpness", "highISONR", "clarity", "dRangePriority",
  "grainSize", "monochromaticWarmCool", "monochromaticMagentaGreen", "suggestedExposureCompensation",
];

function Tile({ label, value, big }: { label: string; value: string; big?: boolean }) {
  const muted = value === "—" || value === "n/a";
  return (
    <div className={cn("rounded-2xl border border-border bg-card px-3 py-3 text-center", big && "py-5")}>
      <div className={cn("font-semibold tabular-nums", big ? "text-xl" : "text-lg", muted && "text-muted-foreground")}>{value}</div>
      <div className="mt-1 text-[11px] uppercase tracking-wider text-muted-foreground">{label}</div>
    </div>
  );
}

/** Recipe settings as tiles. Unset values show "—" (camera keeps its own value). */
export function SettingsGrid({ settings }: { settings: RecipeSettings }) {
  const wb = display(settings, "whiteBalance");
  const kelvin = display(settings, "kelvin");
  const red = display(settings, "wbShiftRed"), blue = display(settings, "wbShiftBlue");
  const visible = SECONDARY.filter((k) => display(settings, k) !== "n/a");
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Tile big label="Film simulation" value={display(settings, "filmSimulation")} />
        <Tile big label={`WB · R ${red} B ${blue}`} value={kelvin !== "n/a" && kelvin !== "—" ? kelvin : wb} />
        <Tile big label="Grain effect" value={display(settings, "grainRoughness")} />
      </div>
      <div className="grid grid-cols-3 gap-3 sm:grid-cols-5">
        {visible.map((k) => <Tile key={k} label={LABELS[k]} value={display(settings, k)} />)}
      </div>
    </div>
  );
}
