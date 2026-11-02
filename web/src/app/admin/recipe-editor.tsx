import { useState } from "react";
import { AlertTriangle, Check, X } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { RecipePreview } from "@/components/recipe/recipe-preview";
import {
  DR_PRIORITIES, DYNAMIC_RANGES, EFFECT_LEVELS, FILM_SIMULATION_NAMES, FILM_SIMULATIONS, GRAIN_SIZES, LABELS, RANGES,
  WHITE_BALANCES, WHITE_BALANCE_NAMES, normalize, validate, type FieldKey, type RecipeSettings,
} from "@/lib/recipe/schema";
import { cn } from "@/lib/utils";
import { TAGS, type Draft } from "./lib";

const ENUMS: Partial<Record<FieldKey, readonly string[]>> = {
  grainRoughness: EFFECT_LEVELS, grainSize: GRAIN_SIZES, colorChrome: EFFECT_LEVELS, colorChromeFXBlue: EFFECT_LEVELS,
  whiteBalance: WHITE_BALANCES, dynamicRange: DYNAMIC_RANGES, dRangePriority: DR_PRIORITIES,
};
const GROUPS: { title: string; fields: FieldKey[] }[] = [
  { title: "White balance", fields: ["whiteBalance", "kelvin", "wbShiftRed", "wbShiftBlue"] },
  { title: "Tone", fields: ["dynamicRange", "dRangePriority", "highlight", "shadow", "color", "clarity"] },
  { title: "Effects", fields: ["grainRoughness", "grainSize", "colorChrome", "colorChromeFXBlue"] },
  { title: "Detail & more", fields: ["sharpness", "highISONR", "monochromaticWarmCool", "monochromaticMagentaGreen", "suggestedExposureCompensation"] },
];
export const fieldClass = "h-10 w-full rounded-xl border border-input bg-background px-3 text-sm outline-none transition-shadow focus-visible:ring-2 focus-visible:ring-ring disabled:bg-surface disabled:text-tertiary";

/** Validation errors + anything the extractor wasn't sure about. */
export function draftProblems(d: Draft) {
  const errors = validate(d.settings).filter((i) => i.severity === "error");
  return { errors, needsReview: d.uncertain.length > 0 || d.issues.length > 0 };
}

export function RecipeEditor({
  draft, onChange, sourceImage, footer,
}: {
  draft: Draft;
  onChange: (d: Draft) => void;
  sourceImage?: string | null;
  footer: React.ReactNode;
}) {
  const [view, setView] = useState<"preview" | "source">(sourceImage ? "source" : "preview");
  const set = (patch: Partial<Draft>) => onChange({ ...draft, ...patch });
  function setField(k: FieldKey, raw: string) {
    const value = raw === "" ? { state: "unset" } : { state: "value", value: ENUMS[k] ? raw : Number(raw) };
    set({ settings: normalize({ ...draft.settings, [k]: value } as RecipeSettings), uncertain: draft.uncertain.filter((u) => u !== k) });
  }
  const validation = validate(draft.settings);

  return (
    <div className="grid gap-10 xl:grid-cols-[1fr_1.1fr]">
      {/* Left: what we read from, and what it looks like */}
      <div className="space-y-4 xl:sticky xl:top-28 xl:self-start">
        {sourceImage && (
          <div className="inline-flex rounded-full bg-surface p-1 text-sm">
            {(["source", "preview"] as const).map((v) => (
              <button key={v} type="button" onClick={() => setView(v)}
                className={cn("rounded-full px-4 py-1.5 transition-colors", view === v ? "bg-background shadow-sm" : "text-muted-foreground hover:text-foreground")}>
                {v === "source" ? "Source image" : "Preview"}
              </button>
            ))}
          </div>
        )}
        {sourceImage && view === "source" ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={sourceImage} alt="Source the recipe was read from" className="max-h-[70vh] w-full rounded-[20px] bg-surface object-contain" />
        ) : (
          <RecipePreview settings={draft.settings} compact />
        )}
        {draft.meta && (
          <p className="text-xs text-tertiary">
            {draft.meta.model} · {(draft.meta.latencyMs / 1000).toFixed(1)} s
            {draft.meta.usage.costUSD !== null && ` · $${draft.meta.usage.costUSD.toFixed(4)}`}{draft.meta.attempts > 1 && ` · ${draft.meta.attempts} attempts`}
          </p>
        )}
      </div>

      {/* Right: fields */}
      <div className="space-y-10">
        {(draft.issues.length > 0 || draft.uncertain.length > 0) && (
          <div className="space-y-2 rounded-[20px] bg-amber-50 p-5 text-sm text-amber-900">
            <p className="flex items-center gap-2 font-medium"><AlertTriangle className="size-4" /> Check before saving</p>
            {draft.uncertain.length > 0 && <p>Not sure about: {draft.uncertain.map((u) => LABELS[u as FieldKey] ?? u).join(", ")}. Editing a field clears its flag.</p>}
            <ul className="space-y-1">
              {draft.issues.map((i, n) => (
                <li key={n}><span className="mr-1.5 rounded bg-amber-100 px-1.5 py-0.5 text-[10px] uppercase tracking-wide">{i.kind}</span>{i.message}</li>
              ))}
            </ul>
            {draft.issues.length > 0 && (
              <button type="button" onClick={() => set({ issues: [] })} className="mt-1 inline-flex items-center gap-1 text-xs font-medium underline underline-offset-2">
                <Check className="size-3.5" /> I&apos;ve checked these
              </button>
            )}
          </div>
        )}

        <section className="space-y-5">
          <div className="space-y-2">
            <Label htmlFor="ed-name">Name</Label>
            <Input id="ed-name" value={draft.name} onChange={(e) => set({ name: e.target.value })} placeholder="Untitled recipe" className="h-12 rounded-xl px-4 font-display text-xl tracking-[-0.02em] md:text-xl" />
          </div>
          <div className="grid gap-5 sm:grid-cols-2">
            <div className="space-y-2"><Label htmlFor="ed-credit">Credit</Label><Input id="ed-credit" value={draft.credit} onChange={(e) => set({ credit: e.target.value })} placeholder="@handle or name" className="h-10 rounded-xl" /></div>
            <div className="space-y-2"><Label htmlFor="ed-camera">Made for camera</Label><Input id="ed-camera" value={draft.cameraModel} onChange={(e) => set({ cameraModel: e.target.value })} placeholder="X-T30 III" className="h-10 rounded-xl" /></div>
          </div>
          <div className="space-y-2"><Label htmlFor="ed-summary">Summary</Label><Input id="ed-summary" value={draft.summary} onChange={(e) => set({ summary: e.target.value })} placeholder="One line about the look" className="h-10 rounded-xl" /></div>
          <div className="space-y-2.5">
            <Label>Works best for</Label>
            <div className="flex flex-wrap gap-2">
              {Object.entries(TAGS).map(([k, label]) => {
                const on = draft.tags.includes(k);
                return (
                  <button key={k} type="button" aria-pressed={on} onClick={() => set({ tags: on ? draft.tags.filter((t) => t !== k) : [...draft.tags, k] })}
                    className={cn("rounded-full border px-3 py-1.5 text-sm transition-colors", on ? "border-foreground bg-foreground text-background" : "border-hairline hover:border-foreground/30")}>
                    {label}
                  </button>
                );
              })}
            </div>
          </div>
        </section>

        <section className="space-y-6">
          <div className="space-y-2">
            <Label htmlFor="ed-sim">Film simulation</Label>
            <select id="ed-sim" className={fieldClass} value={draft.settings.filmSimulation}
              onChange={(e) => set({ settings: normalize({ ...draft.settings, filmSimulation: e.target.value as RecipeSettings["filmSimulation"] }), uncertain: draft.uncertain.filter((u) => u !== "filmSimulation") })}>
              {FILM_SIMULATIONS.map((s) => <option key={s} value={s}>{FILM_SIMULATION_NAMES[s]}</option>)}
            </select>
          </div>
          {GROUPS.map((g) => (
            <fieldset key={g.title} className="space-y-3">
              <legend className="mb-3 text-xs font-medium uppercase tracking-[.08em] text-tertiary">{g.title}</legend>
              <div className="grid grid-cols-2 gap-x-4 gap-y-4 sm:grid-cols-3">
                {g.fields.map((k) => {
                  const f = draft.settings[k] as { state: string; value?: string | number };
                  const na = f.state === "notApplicable";
                  const unsure = draft.uncertain.includes(k);
                  const options = ENUMS[k];
                  const r = RANGES[k];
                  const invalid = validation.some((i) => i.field === k && i.severity === "error");
                  return (
                    <div key={k} className="space-y-1.5">
                      <Label htmlFor={`ed-${k}`} className={cn("text-xs font-normal text-muted-foreground", unsure && "text-amber-700")}>
                        {LABELS[k]}{unsure ? " · check" : ""}
                      </Label>
                      {options ? (
                        <select id={`ed-${k}`} className={cn(fieldClass, unsure && "border-amber-400", invalid && "border-destructive")} disabled={na}
                          value={f.state === "value" ? String(f.value) : ""} onChange={(e) => setField(k, e.target.value)}>
                          <option value="">{na ? "n/a" : "Not set"}</option>
                          {options.map((o) => <option key={o} value={o}>{k === "whiteBalance" ? WHITE_BALANCE_NAMES[o as keyof typeof WHITE_BALANCE_NAMES] : o}</option>)}
                        </select>
                      ) : (
                        <input id={`ed-${k}`} type="number" className={cn(fieldClass, unsure && "border-amber-400", invalid && "border-destructive")} disabled={na}
                          placeholder={na ? "n/a" : "Not set"} step={r?.step ?? 0.01} min={r?.min} max={r?.max}
                          value={f.state === "value" ? String(f.value) : ""} onChange={(e) => setField(k, e.target.value)} />
                      )}
                    </div>
                  );
                })}
              </div>
            </fieldset>
          ))}
          {validation.length > 0 && (
            <ul className="space-y-1 text-sm text-destructive">{validation.map((i) => <li key={i.field} className="flex items-center gap-1.5"><X className="size-3.5" />{i.message}</li>)}</ul>
          )}
        </section>

        <section className="space-y-2">
          <Label htmlFor="ed-body">Story / notes <span className="font-normal text-tertiary">(shown on the recipe page)</span></Label>
          <Textarea id="ed-body" rows={5} value={draft.body} onChange={(e) => set({ body: e.target.value })} className="rounded-xl" />
        </section>

        {draft.raw.length > 0 && (
          <details className="text-sm text-muted-foreground">
            <summary className="cursor-pointer select-none">Text read from the source ({draft.raw.length})</summary>
            <ul className="mt-3 space-y-1">{draft.raw.map((r, n) => <li key={n}><span className="text-foreground">{LABELS[r.field as FieldKey] ?? r.field}</span>: {r.text}</li>)}</ul>
          </details>
        )}

        <div className="sticky bottom-4 z-10 flex flex-wrap items-center gap-2 rounded-full border border-hairline bg-background/95 p-2 shadow-[0_8px_30px_rgba(0,0,0,.08)] backdrop-blur">
          {footer}
        </div>
      </div>
    </div>
  );
}
