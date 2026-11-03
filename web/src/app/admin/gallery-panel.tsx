"use client";

import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { ArrowDown, ArrowUp, ImagePlus, Loader2, Trash2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { api, jsonInit, pool, preparePhoto, type GalleryPhoto, type Summary } from "./lib";

const field = "w-full rounded-xl bg-surface px-3 py-2 text-sm outline-none ring-foreground/20 placeholder:text-tertiary focus:ring-2";

/** Favourite photos for the public /gallery page, each optionally linked to a recipe. */
export function GalleryPanel({ token, version }: { token: string; version: number }) {
  const [photos, setPhotos] = useState<GalleryPhoto[] | null>(null);
  const [recipes, setRecipes] = useState<Summary[]>([]);
  const [linkNew, setLinkNew] = useState("");
  const [uploading, setUploading] = useState<{ done: number; total: number } | null>(null);
  const [over, setOver] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let live = true;
    Promise.all([
      api<{ photos: GalleryPhoto[] }>("/api/gallery?all=1", token),
      api<{ recipes: Summary[] }>("/api/recipes?all=1", token),
    ]).then(([g, r]) => { if (live) { setPhotos(g.photos); setRecipes(r.recipes); } })
      .catch((e) => toast.error((e as Error).message));
    return () => { live = false; };
  }, [token, version]);

  async function upload(files: File[]) {
    const images = files.filter((f) => f.type.startsWith("image/"));
    if (!images.length) return;
    setUploading({ done: 0, total: images.length });
    const added: GalleryPhoto[] = [];
    let failed = 0;
    // Two at a time: each is re-encoded in the browser (EXIF and GPS dropped), then sent.
    await pool(images, 2, async (file) => {
      try {
        const p = await preparePhoto(file, 3200);
        const form = new FormData();
        form.append("file", p.blob, "photo.jpg");
        form.append("title", "");
        form.append("caption", "");
        form.append("recipe", linkNew);
        form.append("width", String(p.width));
        form.append("height", String(p.height));
        URL.revokeObjectURL(p.previewUrl);
        const res = await api<{ photos: GalleryPhoto[] }>("/api/gallery", token, { method: "POST", body: form });
        added.push(...res.photos);
        setPhotos((cur) => [...res.photos, ...(cur ?? [])]);
      } catch (e) {
        failed++;
        toast.error(`${file.name}: ${(e as Error).message}`);
      } finally {
        setUploading((u) => (u ? { ...u, done: u.done + 1 } : u));
      }
    });
    setUploading(null);
    if (added.length) toast.success(`Added ${added.length} ${added.length === 1 ? "photo" : "photos"} to the gallery${failed ? ` (${failed} failed)` : ""}`);
  }

  async function patch(id: string, body: { title?: string; caption?: string; recipe?: string | null }) {
    try {
      const res = await api<{ photo: GalleryPhoto }>(`/api/gallery/${id}`, token, jsonInit("PATCH", body));
      setPhotos((cur) => cur?.map((p) => (p.id === id ? res.photo : p)) ?? null);
    } catch (e) { toast.error((e as Error).message); }
  }

  async function move(index: number, delta: number) {
    if (!photos) return;
    const next = [...photos];
    const [item] = next.splice(index, 1);
    next.splice(Math.max(0, Math.min(next.length, index + delta)), 0, item);
    setPhotos(next);
    try {
      await api("/api/gallery", token, jsonInit("PUT", { order: next.map((p) => p.id) }));
    } catch (e) { toast.error((e as Error).message); setPhotos(photos); }
  }

  async function remove(p: GalleryPhoto) {
    if (!confirm(`Remove ${p.title ? `“${p.title}”` : "this photo"} from the gallery? The file is deleted.`)) return;
    try {
      await api(`/api/gallery/${p.id}`, token, { method: "DELETE" });
      setPhotos((cur) => cur?.filter((x) => x.id !== p.id) ?? null);
    } catch (e) { toast.error((e as Error).message); }
  }

  const recipeSelect = (value: string, onChange: (slug: string) => void, label: string) => (
    <select value={value} onChange={(e) => onChange(e.target.value)} aria-label={label} className={cn(field, "cursor-pointer")}>
      <option value="">No recipe</option>
      {recipes.map((r) => <option key={r.slug} value={r.slug}>{r.name}{r.status === "draft" ? " (draft)" : ""}</option>)}
    </select>
  );

  return (
    <div className="space-y-10">
      <section className="grid gap-4 lg:grid-cols-[1.4fr_1fr] lg:items-stretch">
        <button type="button" onClick={() => input.current?.click()} disabled={!!uploading}
          onDragOver={(e) => { e.preventDefault(); setOver(true); }} onDragLeave={() => setOver(false)}
          onDrop={(e) => { e.preventDefault(); setOver(false); void upload([...e.dataTransfer.files]); }}
          className={cn("flex min-h-44 flex-col items-center justify-center gap-2 rounded-[var(--fl-radius-card)] border-2 border-dashed text-muted-foreground transition-colors hover:border-foreground/40 hover:text-foreground",
            over ? "border-foreground bg-surface" : "border-hairline")}>
          {uploading ? <Loader2 className="size-6 animate-spin" /> : <ImagePlus className="size-6" />}
          <span className="font-medium">{uploading ? `Uploading ${uploading.done} of ${uploading.total}…` : "Add your favourite photos"}</span>
          <span className="text-xs text-tertiary">Drop or pick several · resized to 3200 px · location data removed</span>
        </button>
        <div className="space-y-3 rounded-[var(--fl-radius-card)] bg-surface p-5">
          <p className="text-sm font-medium">Link new uploads to</p>
          {recipeSelect(linkNew, setLinkNew, "Recipe for new uploads")}
          <p className="text-xs leading-relaxed text-tertiary">Visitors see a link to the recipe on each photo. Links to drafts stay hidden until the recipe is published. Only upload photos you own.</p>
        </div>
      </section>
      <input ref={input} type="file" multiple accept="image/jpeg,image/png,image/webp,image/heic,image/heif" className="sr-only"
        onChange={(e) => { void upload([...(e.target.files ?? [])]); e.target.value = ""; }} />

      {photos === null ? (
        <p className="text-muted-foreground">Loading…</p>
      ) : photos.length === 0 ? (
        <p className="py-16 text-center text-muted-foreground">No photos yet. The public gallery stays hidden from the sitemap until you add some.</p>
      ) : (
        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {photos.map((p, i) => (
            <figure key={p.id} className="space-y-3">
              <div className="group relative overflow-hidden rounded-2xl bg-surface">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={p.url} alt="" loading="lazy" className="aspect-[4/3] w-full object-cover" />
                <div className="absolute right-2 top-2 flex gap-1.5 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
                  <button type="button" onClick={() => void move(i, -1)} disabled={i === 0} aria-label="Move earlier" className="grid size-8 place-items-center rounded-full bg-white/90 text-black disabled:opacity-40"><ArrowUp className="size-4" /></button>
                  <button type="button" onClick={() => void move(i, 1)} disabled={i === photos.length - 1} aria-label="Move later" className="grid size-8 place-items-center rounded-full bg-white/90 text-black disabled:opacity-40"><ArrowDown className="size-4" /></button>
                  <button type="button" onClick={() => void remove(p)} aria-label="Remove photo" className="grid size-8 place-items-center rounded-full bg-white/90 text-black"><Trash2 className="size-4" /></button>
                </div>
              </div>
              <input defaultValue={p.title} placeholder="Title (optional)" aria-label="Title" maxLength={120} className={field}
                onBlur={(e) => { if (e.target.value !== p.title) void patch(p.id, { title: e.target.value }); }} />
              <textarea defaultValue={p.caption} placeholder="Caption (optional)" aria-label="Caption" maxLength={1000} rows={2} className={cn(field, "resize-y")}
                onBlur={(e) => { if (e.target.value !== p.caption) void patch(p.id, { caption: e.target.value }); }} />
              {recipeSelect(p.recipe?.slug ?? "", (slug) => void patch(p.id, { recipe: slug || null }), "Recipe")}
            </figure>
          ))}
        </div>
      )}
      <div className="flex justify-end">
        <a href="/gallery" target="_blank" rel="noreferrer" className="rounded-full px-4 py-2 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground">View public gallery ↗</a>
      </div>
    </div>
  );
}
