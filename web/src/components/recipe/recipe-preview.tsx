"use client";

import { useEffect, useRef, useState } from "react";
import { ImagePlus } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";
import type { RecipeSettings } from "@/lib/recipe/schema";
import { renderRecipe } from "@/lib/preview/render";

const SAMPLES = [
  { id: "landscape", label: "Landscape", src: "/samples/landscape.jpg" },
  { id: "chart", label: "Colour chart", src: "/samples/chart.jpg" },
];
const MAX_EDGE = 1200;

async function loadImageData(src: string): Promise<ImageData> {
  const img = new Image();
  img.decoding = "async";
  img.src = src;
  await img.decode();
  const scale = Math.min(1, MAX_EDGE / Math.max(img.naturalWidth, img.naturalHeight));
  const w = Math.round(img.naturalWidth * scale), h = Math.round(img.naturalHeight * scale);
  const canvas = new OffscreenCanvas(w, h);
  const ctx = canvas.getContext("2d")!;
  ctx.drawImage(img, 0, 0, w, h);
  return ctx.getImageData(0, 0, w, h);
}

/**
 * Approximate, in-browser preview of a recipe on a sample image or the visitor's own photo.
 * The visitor's photo never leaves the browser.
 */
export function RecipePreview({ settings }: { settings: RecipeSettings }) {
  const [source, setSource] = useState(SAMPLES[0].src);
  const [ownName, setOwnName] = useState<string | null>(null);
  const [original, setOriginal] = useState<ImageData | null>(null);
  const [split, setSplit] = useState(50);
  // What the canvases currently show; "busy" while it lags behind the inputs.
  const [rendered, setRendered] = useState<{ original: ImageData; settings: RecipeSettings } | null>(null);
  const busy = !original || rendered?.original !== original || rendered?.settings !== settings;
  const recipeCanvas = useRef<HTMLCanvasElement>(null);
  const originalCanvas = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    let cancelled = false;
    loadImageData(source).then((data) => { if (!cancelled) setOriginal(data); });
    return () => { cancelled = true; };
  }, [source]);

  useEffect(() => {
    if (!original) return;
    const id = setTimeout(() => {
      const out = renderRecipe(original, settings);
      for (const [ref, data] of [[recipeCanvas, out], [originalCanvas, original]] as const) {
        const c = ref.current;
        if (!c) continue;
        c.width = data.width; c.height = data.height;
        c.getContext("2d")!.putImageData(data, 0, 0);
      }
      setRendered({ original, settings });
    }, 0);
    return () => clearTimeout(id);
  }, [original, settings]);

  function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setOwnName(file.name);
    setSource(URL.createObjectURL(file));
  }

  return (
    <div className="space-y-3">
      <div className="relative overflow-hidden rounded-3xl border border-border bg-card">
        <canvas ref={recipeCanvas} className="block h-auto w-full" aria-label="Recipe preview" />
        <canvas
          ref={originalCanvas}
          className="pointer-events-none absolute inset-0 block h-full w-full"
          style={{ clipPath: `inset(0 ${100 - split}% 0 0)` }}
          aria-label="Original"
        />
        <div className="pointer-events-none absolute inset-y-0 w-0.5 bg-white/90" style={{ left: `${split}%` }} />
        <div className="absolute left-3 top-3 flex gap-2">
          <Badge variant="secondary" className="bg-black/60 backdrop-blur">Approximate · In browser</Badge>
          {busy && <Badge variant="secondary" className="bg-black/60">Rendering…</Badge>}
        </div>
        <div className="pointer-events-none absolute bottom-3 left-3 rounded-full bg-black/55 px-2.5 py-1 text-xs">Original</div>
        <div className="pointer-events-none absolute bottom-3 right-3 rounded-full bg-black/55 px-2.5 py-1 text-xs">Recipe</div>
      </div>
      <Slider value={[split]} onValueChange={(v) => setSplit(Array.isArray(v) ? v[0] : v)} min={0} max={100} aria-label="Before and after divider" />
      <div className="flex flex-wrap items-center gap-2">
        {SAMPLES.map((s) => (
          <Button key={s.id} size="sm" variant={source === s.src ? "default" : "secondary"} onClick={() => { setSource(s.src); setOwnName(null); }}>
            {s.label}
          </Button>
        ))}
        <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-lg bg-secondary px-2.5 py-1.5 text-sm hover:bg-secondary/80">
          <ImagePlus className="size-4" /> {ownName ? ownName : "Try your photo"}
          <input type="file" accept="image/jpeg,image/png,image/webp,image/heic" className="sr-only" onChange={onFile} />
        </label>
      </div>
      <p className="text-xs text-muted-foreground">
        Your photo stays in your browser. This is FilmLab&apos;s approximation (no clarity/sharpening on the web), not camera output.
      </p>
    </div>
  );
}
