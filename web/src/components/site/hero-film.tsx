"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { FILM_SIMULATION_NAMES, RecipeSettingsSchema, type FilmSimulation } from "@/lib/recipe/schema";
import { renderRecipe } from "@/lib/preview/render";
import { loadImageData } from "@/components/recipe/recipe-preview";

const SIMS: FilmSimulation[] = ["classicChrome", "nostalgicNeg", "acrosR", "eterna", "classicNeg", "realaAce", "velvia", "provia"];

/**
 * Hero background: FilmLab's own sample photo rendered live through each film simulation by the
 * in-browser preview engine, cross-fading every few seconds.
 */
export function HeroFilm({ src, credit, position }: { src: string; credit: string | null; position: string }) {
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
        const url = canvas.toDataURL("image/jpeg", 0.85);
        if (!cancelled) setFrames((f) => [...f, { sim, url }]);
      }
    })();
    return () => { cancelled = true; };
  }, [src]);

  useEffect(() => {
    if (reduce || frames.length < 2) return;
    const t = setInterval(() => setI((x) => (x + 1) % frames.length), 2600);
    return () => clearInterval(t);
  }, [frames.length, reduce]);

  const current = frames[i % Math.max(frames.length, 1)];
  return (
    <div className="absolute inset-0 overflow-hidden" aria-hidden>
      {/* Plain sample until the first rendered frame is ready */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={src} alt="" className="absolute inset-0 size-full scale-105 object-cover" style={{ objectPosition: position }} />
      <AnimatePresence initial={false}>
        {current && (
           
          <motion.img
            key={current.sim}
            src={current.url}
            alt=""
            className="absolute inset-0 size-full object-cover"
            style={{ objectPosition: position }}
            initial={{ opacity: 0, scale: 1.08 }}
            animate={{ opacity: 1, scale: 1.02 }}
            exit={{ opacity: 0 }}
            transition={{ opacity: { duration: 1.1 }, scale: { duration: 3.2, ease: "linear" } }}
          />
        )}
      </AnimatePresence>
      <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(0,0,0,.35)_0%,rgba(0,0,0,.05)_30%,rgba(0,0,0,.55)_72%,#000_100%)]" />
      <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(0,0,0,.6)_0%,rgba(0,0,0,.25)_45%,transparent_75%)]" />
      <div className="fl-grain absolute inset-0" />
      <AnimatePresence mode="wait">
        {current && (
          <motion.div
            key={current.sim}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.4 }}
            className="absolute right-4 top-20 flex items-center gap-2 rounded-full border border-hairline bg-black/55 px-3.5 py-2 text-xs font-semibold backdrop-blur sm:bottom-10 sm:right-8 sm:top-auto"
          >
            <span className="size-2 rounded-full bg-primary" />
            {FILM_SIMULATION_NAMES[current.sim]}
            <span className="text-tertiary">· live preview</span>
          </motion.div>
        )}
      </AnimatePresence>
      {credit && (
        <span className="absolute right-5 top-[7.75rem] text-[11px] font-medium text-white/60 sm:bottom-4 sm:right-8 sm:top-auto">Photo: {credit}</span>
      )}
    </div>
  );
}
