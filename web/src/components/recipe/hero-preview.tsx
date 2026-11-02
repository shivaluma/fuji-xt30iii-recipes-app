"use client";

import { useEffect, useState } from "react";
import type { RecipeSettings } from "@/lib/recipe/schema";
import { renderRecipe } from "@/lib/preview/render";
import { CompareView } from "./compare-view";
import { loadImageData } from "./recipe-preview";
import { DEFAULT_PHOTO } from "@/lib/site-config";

/** Large before/after preview on the site's default photo (used when a recipe has no cover). */
export function HeroPreview({ settings }: { settings: RecipeSettings }) {
  const [pair, setPair] = useState<{ o: ImageData; r: ImageData } | null>(null);
  useEffect(() => {
    let cancelled = false;
    loadImageData(DEFAULT_PHOTO, 1400).then((o) => {
      if (!cancelled) setPair({ o, r: renderRecipe(o, settings) });
    });
    return () => { cancelled = true; };
  }, [settings]);
  return (
    <CompareView
      original={pair?.o ?? null}
      processed={pair?.r ?? null}
      className="w-full"
      badge={<span className="rounded-full bg-white/90 px-2.5 py-1 text-[11px] font-medium text-black backdrop-blur">Approximate preview · drag to compare</span>}
    />
  );
}
