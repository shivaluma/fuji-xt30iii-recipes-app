import { display, LABELS, type FieldKey, type RecipeSettings } from "@/lib/recipe/schema";
import { cn } from "@/lib/utils";

const FIELDS: FieldKey[] = [
  "dynamicRange", "dRangePriority", "highlight", "shadow", "color", "clarity",
  "sharpness", "highISONR", "colorChrome", "colorChromeFXBlue", "grainRoughness", "grainSize",
  "monochromaticWarmCool", "monochromaticMagentaGreen", "suggestedExposureCompensation",
];

function Row({ label, value, wide }: { label: string; value: string; wide?: boolean }) {
  const unset = value === "—";
  return (
    <div className={cn("flex items-baseline justify-between gap-4 border-b border-hairline py-4", wide && "sm:col-span-2")}>
      <dt className="shrink-0 text-sm text-muted-foreground">{label}</dt>
      <dd className={cn("text-right font-medium tabular-nums", unset && "text-tertiary")}>{value}</dd>
    </div>
  );
}

/** Recipe settings as a two-column spec list. Unset values show "—" (camera keeps its own value). */
export function SettingsGrid({ settings }: { settings: RecipeSettings }) {
  const kelvin = display(settings, "kelvin");
  const wb = kelvin !== "n/a" && kelvin !== "—" ? kelvin : display(settings, "whiteBalance");
  const red = display(settings, "wbShiftRed"), blue = display(settings, "wbShiftBlue");
  const shift = red === "—" && blue === "—" ? "—" : `R ${red} · B ${blue}`;
  const rows: [string, string][] = [
    ["White balance", wb],
    ["WB shift", shift],
    ...FIELDS.filter((k) => display(settings, k) !== "n/a").map((k) => [LABELS[k], display(settings, k)] as [string, string]),
  ];
  return (
    <dl className="grid border-t border-hairline sm:grid-cols-2 sm:gap-x-12">
      <Row wide label="Film simulation" value={display(settings, "filmSimulation")} />
      {rows.map(([label, value]) => <Row key={label} label={label} value={value} />)}
    </dl>
  );
}
