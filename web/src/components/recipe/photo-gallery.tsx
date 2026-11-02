"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";

export type GalleryPhoto = { id: string; url: string; kind: string };

const CAPTION: Record<string, string> = {
  "camera-jpeg": "JPEG made by the camera with this recipe",
  "approximate-preview": "Approximate preview by FilmLab — not camera output",
  photo: "Sample photo",
};

/** A recipe's sample photos: one large, the rest as thumbnails to switch between. */
export function PhotoGallery({ photos, name }: { photos: GalleryPhoto[]; name: string }) {
  const [active, setActive] = useState(0);
  const current = photos[Math.min(active, photos.length - 1)];
  return (
    <figure>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img key={current.id} src={current.url} alt={`Sample photo for ${name}`}
        className="max-h-[78vh] w-full rounded-[var(--fl-radius-card)] bg-surface object-contain animate-in fade-in duration-300" />
      <figcaption className="mt-3 text-xs text-tertiary">{CAPTION[current.kind] ?? CAPTION.photo}</figcaption>
      {photos.length > 1 && (
        <div className="-mx-1 mt-4 flex gap-3 overflow-x-auto px-1 py-1 [scrollbar-width:none]">
          {photos.map((p, i) => (
            <button key={p.id} type="button" onClick={() => setActive(i)} aria-label={`Show photo ${i + 1}`} aria-pressed={i === active}
              className={cn("relative aspect-[4/3] w-24 shrink-0 overflow-hidden rounded-xl bg-surface transition-opacity",
                i === active ? "ring-2 ring-foreground ring-offset-2 ring-offset-background" : "opacity-60 hover:opacity-100")}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={p.url} alt="" className="size-full object-cover" />
            </button>
          ))}
        </div>
      )}
    </figure>
  );
}
