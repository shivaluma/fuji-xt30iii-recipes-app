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
    <div className={cn("rounded-small border border-hairline bg-surface-raised/70 px-3 py-3 text-center", big && "py-4")}>
      <div className={cn("font-display font-semibold tabular-nums", big ? "text-lg" : "text-base", muted && "text-tertiary")}>{value}</div>
      <div className="mt-1 text-[10px] font-semibold uppercase tracking-[.14em] text-muted-foreground">{label}</div>
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
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <Tile big label="Film simulation" value={display(settings, "filmSimulation")} />
        <Tile big label={`WB · R ${red} B ${blue}`} value={kelvin !== "n/a" && kelvin !== "—" ? kelvin : wb} />
        <Tile big label="Grain effect" value={display(settings, "grainRoughness")} />
      </div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {visible.map((k) => <Tile key={k} label={LABELS[k]} value={display(settings, k)} />)}
      </div>
    </div>
  );
}
