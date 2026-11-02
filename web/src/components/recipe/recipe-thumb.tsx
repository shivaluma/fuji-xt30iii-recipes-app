"use client";

import { useEffect, useRef } from "react";
import type { RecipeSettings } from "@/lib/recipe/schema";
import { renderRecipe } from "@/lib/preview/render";

let samplePromise: Promise<ImageData> | null = null;
function sample(): Promise<ImageData> {
  samplePromise ??= (async () => {
    const img = new Image();
    img.src = "/samples/landscape.jpg";
    await img.decode();
    const w = 420, h = Math.round((img.naturalHeight / img.naturalWidth) * w);
    const c = new OffscreenCanvas(w, h);
    const ctx = c.getContext("2d")!;
    ctx.drawImage(img, 0, 0, w, h);
    return ctx.getImageData(0, 0, w, h);
  })();
  return samplePromise;
}

/** Lazily renders the recipe on FilmLab's synthetic sample photo when scrolled into view. */
export function RecipeThumb({ settings, className }: { settings: RecipeSettings; className?: string }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(async ([entry]) => {
      if (!entry.isIntersecting) return;
      io.disconnect();
      const out = renderRecipe(await sample(), settings);
      el.width = out.width; el.height = out.height;
      el.getContext("2d")!.putImageData(out, 0, 0);
    }, { rootMargin: "200px" });
    io.observe(el);
    return () => io.disconnect();
  }, [settings]);
  return <canvas ref={ref} className={className} aria-hidden />;
}
