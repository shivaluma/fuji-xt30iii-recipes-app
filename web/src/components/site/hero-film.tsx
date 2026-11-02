"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { FILM_SIMULATION_NAMES, RecipeSettingsSchema, type FilmSimulation } from "@/lib/recipe/schema";
import { renderRecipe } from "@/lib/preview/render";
import { loadImageData } from "@/components/recipe/recipe-preview";

const SIMS: FilmSimulation[] = ["classicChrome", "velvia", "nostalgicNeg", "acrosR", "classicNeg", "realaAce", "eternaBleachBypass", "provia"];

/**
 * Hero background: FilmLab's own sample photo rendered live through each film simulation by the
 * in-browser preview engine, cross-fading every few seconds.
 */
export function HeroFilm() {
  const [frames, setFrames] = useState<{ sim: FilmSimulation; url: string }[]>([]);
  const [i, setI] = useState(0);
  const reduce = useReducedMotion();

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const src = await loadImageData("/samples/landscape.jpg", 1500);
      const canvas = document.createElement("canvas");
      canvas.width = src.width; canvas.height = src.height;
      const ctx = canvas.getContext("2d")!;
      for (const sim of SIMS) {
        if (cancelled) return;
        // Yield between frames so the first paint and scrolling stay smooth.
        await new Promise((r) => setTimeout(r, 30));
        const grain = sim === "acrosR" || sim === "classicNeg" ? { grainRoughness: { state: "value", value: "weak" } } : {};
        ctx.putImageData(renderRecipe(src, RecipeSettingsSchema.parse({ filmSimulation: sim, ...grain })), 0, 0);
        const url = canvas.toDataURL("image/jpeg", 0.85);
        if (!cancelled) setFrames((f) => [...f, { sim, url }]);
      }
    })();
    return () => { cancelled = true; };
  }, []);

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
      <img src="/samples/landscape.jpg" alt="" className="absolute inset-0 size-full scale-105 object-cover" />
      <AnimatePresence initial={false}>
        {current && (
           
          <motion.img
            key={current.sim}
            src={current.url}
            alt=""
            className="absolute inset-0 size-full object-cover"
            initial={{ opacity: 0, scale: 1.08 }}
            animate={{ opacity: 1, scale: 1.02 }}
            exit={{ opacity: 0 }}
            transition={{ opacity: { duration: 1.1 }, scale: { duration: 3.2, ease: "linear" } }}
          />
        )}
      </AnimatePresence>
      <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(0,0,0,.55)_0%,rgba(0,0,0,.15)_35%,rgba(0,0,0,.65)_75%,#000_100%)]" />
      <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(0,0,0,.72)_0%,rgba(0,0,0,.35)_45%,transparent_75%)]" />
      <div className="fl-grain absolute inset-0" />
      <AnimatePresence mode="wait">
        {current && (
          <motion.div
            key={current.sim}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.4 }}
            className="absolute bottom-28 right-5 flex items-center gap-2 rounded-full border border-hairline bg-black/55 px-3.5 py-2 text-xs font-semibold backdrop-blur sm:bottom-10 sm:right-8"
          >
            <span className="size-2 rounded-full bg-primary" />
            {FILM_SIMULATION_NAMES[current.sim]}
            <span className="text-tertiary">· live preview</span>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
