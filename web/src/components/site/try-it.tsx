"use client";

import { useMemo, useState } from "react";
import { FILM_SIMULATION_NAMES, RecipeSettingsSchema, type FilmSimulation } from "@/lib/recipe/schema";
import { RecipePreview, Chip } from "@/components/recipe/recipe-preview";

const PICKS: FilmSimulation[] = ["classicChrome", "nostalgicNeg", "velvia", "classicNeg", "realaAce", "eterna", "acrosR", "sepia"];

/** Pick a simulation, drag the divider, try your own photo. */
export function TryIt() {
  const [sim, setSim] = useState<FilmSimulation>("classicChrome");
  const settings = useMemo(() => RecipeSettingsSchema.parse({ filmSimulation: sim }), [sim]);
  return (
    <div className="space-y-6">
      <div className="flex gap-2.5 overflow-x-auto pb-1 [scrollbar-width:none]">
        {PICKS.map((s) => (
          <Chip key={s} active={sim === s} onClick={() => setSim(s)} className="shrink-0">{FILM_SIMULATION_NAMES[s]}</Chip>
        ))}
      </div>
      <RecipePreview settings={settings} />
    </div>
  );
}
