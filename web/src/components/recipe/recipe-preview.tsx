"use client";

import { useEffect, useState } from "react";
import { ImagePlus } from "lucide-react";
import type { RecipeSettings } from "@/lib/recipe/schema";
import { renderRecipe } from "@/lib/preview/render";
import { CompareView } from "./compare-view";
import { cn } from "@/lib/utils";
import { DEFAULT_PHOTO } from "@/lib/site-config";

export const SAMPLES = [
  { id: "fuji", label: "Mt Fuji", src: DEFAULT_PHOTO },
  { id: "chart", label: "Colour chart", src: "/samples/chart.jpg" },
];
const MAX_EDGE = 1400;

export async function loadImageData(src: string, maxEdge = MAX_EDGE): Promise<ImageData> {
  const img = new Image();
  img.decoding = "async";
  img.src = src;
  await img.decode();
  const scale = Math.min(1, maxEdge / Math.max(img.naturalWidth, img.naturalHeight));
  const w = Math.round(img.naturalWidth * scale), h = Math.round(img.naturalHeight * scale);
  const ctx = new OffscreenCanvas(w, h).getContext("2d")!;
  ctx.drawImage(img, 0, 0, w, h);
  return ctx.getImageData(0, 0, w, h);
}

export function Chip({ active, children, onClick, className }: { active?: boolean; children: React.ReactNode; onClick?: () => void; className?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm transition-colors duration-200 active:scale-[.98]",
        active ? "border-foreground bg-foreground text-background" : "border-hairline text-foreground hover:border-foreground/30",
        className,
      )}
    >
      {children}
    </button>
  );
}

/**
 * Approximate, in-browser preview of a recipe on a sample image or the visitor's own photo.
 * The visitor's photo never leaves the browser.
 */
export function RecipePreview({ settings, compact }: { settings: RecipeSettings; compact?: boolean }) {
  const [source, setSource] = useState(SAMPLES[0].src);
  const [ownName, setOwnName] = useState<string | null>(null);
  const [original, setOriginal] = useState<ImageData | null>(null);
  const [rendered, setRendered] = useState<{ for: ImageData; settings: RecipeSettings; out: ImageData } | null>(null);
  const busy = !original || rendered?.for !== original || rendered?.settings !== settings;

  useEffect(() => {
    let cancelled = false;
    loadImageData(source).then((data) => { if (!cancelled) setOriginal(data); });
    return () => { cancelled = true; };
  }, [source]);

  useEffect(() => {
    if (!original) return;
    const id = setTimeout(() => setRendered({ for: original, settings, out: renderRecipe(original, settings) }), 0);
    return () => clearTimeout(id);
  }, [original, settings]);

  function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setOwnName(file.name);
    setSource(URL.createObjectURL(file));
  }

  return (
    <div className="space-y-5">
      <CompareView
        original={original}
        processed={rendered?.out ?? null}
        badge={
          <span className="flex items-center gap-2 rounded-full bg-white/90 px-2.5 py-1 text-[11px] font-medium text-black backdrop-blur">
            <span className={cn("size-2 rounded-full", busy ? "animate-pulse bg-warning" : "bg-black")} />
            {busy ? "Rendering…" : "Approximate · In browser"}
          </span>
        }
      />
      {!compact && (
        <div className="flex flex-wrap items-center gap-2.5">
          {SAMPLES.map((s) => (
            <Chip key={s.id} active={source === s.src} onClick={() => { setSource(s.src); setOwnName(null); }}>{s.label}</Chip>
          ))}
          <label className={cn(
            "inline-flex cursor-pointer items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm transition-colors active:scale-[.98]",
            ownName ? "border-foreground bg-foreground text-background" : "border-dashed border-foreground/30 hover:border-foreground/60",
          )}>
            <ImagePlus className="size-4" /> <span className="max-w-40 truncate">{ownName ?? "Try your photo"}</span>
            <input type="file" accept="image/jpeg,image/png,image/webp,image/heic" className="sr-only" onChange={onFile} />
          </label>
        </div>
      )}
      <p className="text-xs text-tertiary">
        Drag the handle to compare. Your photo stays in your browser. This is FilmLab&apos;s approximation, not camera output.
      </p>
    </div>
  );
}
