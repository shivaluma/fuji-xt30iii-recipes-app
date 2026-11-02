import { Check, Minus, X } from "lucide-react";
import { GENERATIONS, GENERATION_LABEL, worksOn } from "@/lib/recipe/cameras";
import type { RecipeSettings } from "@/lib/recipe/schema";
import { cn } from "@/lib/utils";

/** Which Fujifilm bodies can take this recipe as written, which need small changes, and which can't. */
export function WorksOn({ settings }: { settings: RecipeSettings }) {
  const all = worksOn(settings);
  const usable = all.filter((c) => c.level !== "none").length;
  const partial = all.filter((c) => c.level === "partial");
  return (
    <section>
      <div className="mb-6 flex items-baseline justify-between">
        <h2 className="font-display text-2xl font-normal tracking-[-0.03em]">Works on</h2>
        <span className="text-sm text-muted-foreground">{usable} of {all.length} cameras</span>
      </div>
      <div className="space-y-5">
        {GENERATIONS.map((g) => (
          <div key={g}>
            <p className="mb-2.5 text-xs font-medium uppercase tracking-[.08em] text-tertiary">{GENERATION_LABEL[g]}</p>
            <div className="flex flex-wrap gap-2">
              {all.filter((c) => c.camera.generation === g).map(({ camera, level, issues }) => (
                <span key={camera.id} title={issues.map((i) => i.message).join("\n") || undefined}
                  className={cn("inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm",
                    level === "full" && "border-hairline",
                    level === "partial" && "border-amber-300 bg-amber-50 text-amber-900",
                    level === "none" && "border-transparent bg-surface text-tertiary line-through decoration-1")}>
                  {level === "full" ? <Check className="size-3.5" /> : level === "partial" ? <Minus className="size-3.5" /> : <X className="size-3.5" />}
                  {camera.name}
                </span>
              ))}
            </div>
          </div>
        ))}
      </div>
      {partial.length > 0 && (
        <details className="mt-5 text-sm text-muted-foreground">
          <summary className="cursor-pointer select-none">What changes on {partial.length} camera{partial.length === 1 ? "" : "s"}</summary>
          <ul className="mt-3 space-y-1.5">
            {partial.map(({ camera, issues }) => (
              <li key={camera.id}><span className="text-foreground">{camera.name}:</span> {issues.map((i) => i.message.replace(` on the ${camera.name}`, "")).join(" · ")}</li>
            ))}
          </ul>
        </details>
      )}
      <p className="mt-4 text-xs leading-relaxed text-tertiary">
        Feature lists come from the X‑T30 III manual and community reports for other bodies; check your camera&apos;s firmware.
      </p>
    </section>
  );
}
