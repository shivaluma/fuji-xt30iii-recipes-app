"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { ArrowUpRight, ChevronLeft, ChevronRight, X } from "lucide-react";
import { FILM_SIMULATION_NAMES, type FilmSimulation } from "@/lib/recipe/schema";
import { cn } from "@/lib/utils";

export type GalleryTile = {
  id: string; url: string; title: string; caption: string; width: number | null; height: number | null;
  recipe: { slug: string; name: string; filmSimulation: FilmSimulation } | null;
};

function RecipeChip({ recipe, className }: { recipe: NonNullable<GalleryTile["recipe"]>; className?: string }) {
  return (
    <Link href={`/recipes/${recipe.slug}`} onClick={(e) => e.stopPropagation()}
      className={cn("inline-flex max-w-full items-center gap-1.5 rounded-full bg-white/90 px-3 py-1.5 text-xs font-medium text-black backdrop-blur transition-opacity hover:opacity-80", className)}>
      <span className="truncate">{recipe.name}</span>
      <span className="shrink-0 text-black/50">· {FILM_SIMULATION_NAMES[recipe.filmSimulation]}</span>
      <ArrowUpRight className="size-3 shrink-0" />
    </Link>
  );
}

/** Masonry of favourite photos; each opens full screen with its recipe one tap away. */
export function GalleryGrid({ photos }: { photos: GalleryTile[] }) {
  const [open, setOpen] = useState<number | null>(null);
  return (
    <>
      <div className="columns-1 gap-4 sm:columns-2 lg:columns-3 [&>*]:mb-4">
        {photos.map((p, i) => (
          <figure key={p.id} className="group relative break-inside-avoid overflow-hidden rounded-[var(--fl-radius-card)] bg-surface animate-in fade-in fill-mode-both duration-700 motion-reduce:animate-none"
            style={{ animationDelay: `${Math.min(i, 9) * 40}ms` }}>
            <button type="button" onClick={() => setOpen(i)} aria-label={`Open ${p.title || "photo"}`} className="block w-full cursor-zoom-in">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={p.url} alt={p.title || (p.recipe ? `Photo shot with ${p.recipe.name}` : "Gallery photo")}
                width={p.width ?? undefined} height={p.height ?? undefined} loading={i < 6 ? "eager" : "lazy"} decoding="async"
                className="h-auto w-full transition-transform duration-700 ease-out group-hover:scale-[1.02]" />
            </button>
            {(p.title || p.recipe) && (
              <figcaption className="pointer-events-none absolute inset-x-0 bottom-0 flex flex-col items-start gap-2 bg-gradient-to-t from-black/60 via-black/20 to-transparent p-4 pt-16 text-white">
                {p.title && <span className="font-display text-lg leading-tight tracking-[-0.02em]">{p.title}</span>}
                {p.recipe && <RecipeChip recipe={p.recipe} className="pointer-events-auto" />}
              </figcaption>
            )}
          </figure>
        ))}
      </div>
      {open !== null && <Lightbox photos={photos} index={open} onIndex={setOpen} onClose={() => setOpen(null)} />}
    </>
  );
}

function Lightbox({ photos, index, onIndex, onClose }: { photos: GalleryTile[]; index: number; onIndex: (i: number) => void; onClose: () => void }) {
  const p = photos[index];
  const close = useRef<HTMLButtonElement>(null);
  const step = useCallback((d: number) => onIndex((index + d + photos.length) % photos.length), [index, onIndex, photos.length]);
  useEffect(() => {
    close.current?.focus();
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowRight") step(1);
      if (e.key === "ArrowLeft") step(-1);
    };
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", key);
    return () => { window.removeEventListener("keydown", key); document.body.style.overflow = overflow; };
  }, [onClose, step]);
  // Warm the neighbours so arrowing through is instant.
  useEffect(() => {
    [photos[(index + 1) % photos.length], photos[(index - 1 + photos.length) % photos.length]].forEach((n) => { if (n) new Image().src = n.url; });
  }, [index, photos]);

  const nav = "grid size-11 place-items-center rounded-full bg-white/10 text-white backdrop-blur transition-colors hover:bg-white/20";
  return (
    <div role="dialog" aria-modal="true" aria-label={p.title || "Photo"} onClick={onClose}
      className="fixed inset-0 z-[70] flex flex-col bg-black/95 animate-in fade-in duration-200">
      <div className="flex items-center justify-between p-4 text-sm text-white/60">
        <span className="tabular-nums">{index + 1} / {photos.length}</span>
        <button ref={close} type="button" onClick={onClose} aria-label="Close" className={nav}><X className="size-5" /></button>
      </div>
      <div className="relative flex min-h-0 flex-1 items-center justify-center px-4">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img key={p.id} src={p.url} alt={p.title || "Gallery photo"} onClick={(e) => e.stopPropagation()}
          className="max-h-full max-w-full rounded-xl object-contain animate-in fade-in zoom-in-[.98] duration-300" />
        {photos.length > 1 && (
          <>
            <button type="button" onClick={(e) => { e.stopPropagation(); step(-1); }} aria-label="Previous photo" className={cn(nav, "absolute left-4 top-1/2 -translate-y-1/2 max-sm:hidden")}><ChevronLeft className="size-5" /></button>
            <button type="button" onClick={(e) => { e.stopPropagation(); step(1); }} aria-label="Next photo" className={cn(nav, "absolute right-4 top-1/2 -translate-y-1/2 max-sm:hidden")}><ChevronRight className="size-5" /></button>
          </>
        )}
      </div>
      <div onClick={(e) => e.stopPropagation()} className="mx-auto flex w-full max-w-3xl flex-col items-center gap-3 px-5 pb-8 pt-5 text-center text-white">
        {p.title && <p className="font-display text-2xl tracking-[-0.03em]">{p.title}</p>}
        {p.caption && <p className="max-w-xl whitespace-pre-line text-sm leading-relaxed text-white/70">{p.caption}</p>}
        {p.recipe && <RecipeChip recipe={p.recipe} />}
        {photos.length > 1 && (
          <div className="flex gap-3 sm:hidden">
            <button type="button" onClick={() => step(-1)} aria-label="Previous photo" className={nav}><ChevronLeft className="size-5" /></button>
            <button type="button" onClick={() => step(1)} aria-label="Next photo" className={nav}><ChevronRight className="size-5" /></button>
          </div>
        )}
      </div>
    </div>
  );
}
