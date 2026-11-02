"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { FILM_SIMULATION_NAMES, RecipeSettingsSchema, type FilmSimulation } from "@/lib/recipe/schema";
import { renderRecipe } from "@/lib/preview/render";
import { loadImageData } from "@/components/recipe/recipe-preview";
import { cn } from "@/lib/utils";

const SIMS: FilmSimulation[] = ["classicChrome", "nostalgicNeg", "acrosR", "eterna", "classicNeg", "realaAce", "velvia", "provia"];

/**
 * The hero photo rendered live through each film simulation by the in-browser preview engine,
 * cross-fading every few seconds. Fills its (positioned) parent.
 */
export function HeroFilm({ src, credit, position, className }: { src: string; credit: string | null; position: string; className?: string }) {
  const [frames, setFrames] = useState<{ sim: FilmSimulation; url: string }[]>([]);
  const [i, setI] = useState(0);
  const reduce = useReducedMotion();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const base = await loadImageData(src, 2000);
      const canvas = document.createElement("canvas");
      canvas.width = base.width; canvas.height = base.height;
      const ctx = canvas.getContext("2d")!;
      for (const sim of SIMS) {
        if (cancelled) return;
        // Yield between frames so the first paint and scrolling stay smooth.
        await new Promise((r) => setTimeout(r, 30));
        const grain = sim === "acrosR" || sim === "classicNeg" ? { grainRoughness: { state: "value", value: "weak" } } : {};
        ctx.putImageData(renderRecipe(base, RecipeSettingsSchema.parse({ filmSimulation: sim, ...grain })), 0, 0);
        const url = canvas.toDataURL("image/jpeg", 0.88);
        if (!cancelled) setFrames((f) => [...f, { sim, url }]);
      }
    })();
    return () => { cancelled = true; };
  }, [src]);

  useEffect(() => {
    if (reduce || frames.length < 2) return;
    const t = setInterval(() => setI((x) => (x + 1) % frames.length), 2800);
    return () => clearInterval(t);
  }, [frames.length, reduce]);

  const current = frames[i % Math.max(frames.length, 1)];
  return (
    <div className={cn("absolute inset-0 overflow-hidden bg-surface", className)}>
      {/* Plain photo until the first rendered frame is ready */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt="" aria-hidden className="absolute inset-0 size-full object-cover" style={{ objectPosition: position }} />
      <AnimatePresence initial={false}>
        {current && (
          <motion.img
            key={current.sim}
            src={current.url}
            alt=""
            aria-hidden
            className="absolute inset-0 size-full object-cover"
            style={{ objectPosition: position }}
            initial={{ opacity: 0, scale: 1.06 }}
            animate={{ opacity: 1, scale: 1.0 }}
            exit={{ opacity: 0 }}
            transition={{ opacity: { duration: 1.1 }, scale: { duration: 3.4, ease: "linear" } }}
          />
        )}
      </AnimatePresence>
      <div className="absolute bottom-4 right-4 flex flex-col items-end gap-1.5">
        <AnimatePresence mode="wait">
          {current && (
            <motion.div
              key={current.sim}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ duration: 0.35 }}
              className="flex items-center gap-2 rounded-full bg-white/90 px-3 py-1.5 text-xs font-medium text-black backdrop-blur"
              aria-live="polite"
            >
              <span className="size-1.5 rounded-full bg-black" />
              {FILM_SIMULATION_NAMES[current.sim]}
              <span className="text-black/45">live preview</span>
            </motion.div>
          )}
        </AnimatePresence>
        {credit && <span className="text-[11px] font-medium text-white/80 drop-shadow">Photo: {credit}</span>}
      </div>
    </div>
  );
}
