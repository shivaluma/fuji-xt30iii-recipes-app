import { useRef, useState } from "react";
import { toast } from "sonner";
import { ImagePlus, Loader2, Star, X, ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";
import { MAX_PHOTOS, PHOTO_KIND_LABELS, preparePhoto, type Draft, type PhotoKind } from "./lib";

export type PhotoTile = { id: string; url: string; kind: PhotoKind; isCover: boolean };

/** Grid of a recipe's sample photos: add several at once, pick the cover, label each, remove. */
export function PhotoManager({
  photos, busy, onAdd, onRemove, onCover, onKind,
}: {
  photos: PhotoTile[];
  busy?: boolean;
  onAdd: (files: File[]) => void;
  onRemove: (id: string) => void;
  onCover: (id: string) => void;
  onKind: (id: string, kind: PhotoKind) => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [over, setOver] = useState(false);
  const room = MAX_PHOTOS - photos.length;
  const take = (files: File[]) => onAdd(files.filter((f) => f.type.startsWith("image/")).slice(0, room));

  return (
    <section className="space-y-4">
      <div className="flex items-baseline justify-between gap-4">
        <p className="text-sm font-medium">Sample photos <span className="font-normal text-tertiary">{photos.length}/{MAX_PHOTOS}</span></p>
        <p className="text-xs text-tertiary">Only photos you own · location data is removed</p>
      </div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {photos.map((p) => (
          <figure key={p.id} className={cn("group relative overflow-hidden rounded-2xl bg-surface", p.isCover && "ring-2 ring-foreground ring-offset-2 ring-offset-background")}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={p.url} alt="" className="aspect-[4/3] w-full object-cover" />
            <button type="button" onClick={() => onCover(p.id)} disabled={p.isCover || busy} aria-label={p.isCover ? "Cover photo" : "Make cover"} title={p.isCover ? "Cover" : "Make cover"}
              className={cn("absolute left-2 top-2 inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-medium backdrop-blur transition-opacity",
                p.isCover ? "bg-foreground text-background" : "bg-white/90 text-black opacity-0 group-hover:opacity-100 focus-visible:opacity-100")}>
              <Star className={cn("size-3", p.isCover && "fill-current")} /> {p.isCover ? "Cover" : "Make cover"}
            </button>
            <button type="button" onClick={() => onRemove(p.id)} disabled={busy} aria-label="Remove photo"
              className="absolute right-2 top-2 grid size-7 place-items-center rounded-full bg-white/90 text-black opacity-0 shadow-sm transition-opacity group-hover:opacity-100 focus-visible:opacity-100">
              <X className="size-3.5" />
            </button>
            <div className="absolute inset-x-2 bottom-2">
              <select value={p.kind} disabled={busy} onChange={(e) => onKind(p.id, e.target.value as PhotoKind)} aria-label="What this photo is"
                className="h-8 w-full cursor-pointer appearance-none rounded-full border-0 bg-white/90 pl-3 pr-8 text-xs text-black backdrop-blur">
                {Object.entries(PHOTO_KIND_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
              <ChevronDown aria-hidden className="pointer-events-none absolute right-2.5 top-1/2 size-3.5 -translate-y-1/2 text-black/60" />
            </div>
          </figure>
        ))}
        {room > 0 && (
          <button type="button" onClick={() => input.current?.click()} disabled={busy}
            onDragOver={(e) => { e.preventDefault(); setOver(true); }} onDragLeave={() => setOver(false)}
            onDrop={(e) => { e.preventDefault(); setOver(false); take([...e.dataTransfer.files]); }}
            className={cn("flex aspect-[4/3] flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed text-sm text-muted-foreground transition-colors hover:border-foreground/40 hover:text-foreground",
              over ? "border-foreground bg-surface" : "border-hairline")}>
            {busy ? <Loader2 className="size-5 animate-spin" /> : <ImagePlus className="size-5" />}
            {busy ? "Uploading…" : "Add photos"}
          </button>
        )}
      </div>
      <input ref={input} type="file" multiple accept="image/jpeg,image/png,image/webp,image/heic,image/heif" className="sr-only"
        onChange={(e) => { take([...(e.target.files ?? [])]); e.target.value = ""; }} />
    </section>
  );
}

/** Photos held in a draft until it is saved, then uploaded with it. */
export function PendingPhotos({ draft, onUpdate }: { draft: Draft; onUpdate: (fn: (d: Draft) => Draft) => void }) {
  const [busy, setBusy] = useState(false);
  const cover = draft.coverPhotoId ?? draft.photos[0]?.id ?? null;
  async function add(files: File[]) {
    setBusy(true);
    try {
      const added = await Promise.all(files.map(async (f) => {
        const p = await preparePhoto(f);
        return { id: crypto.randomUUID(), blob: p.blob, previewUrl: p.previewUrl, kind: "photo" as PhotoKind };
      }));
      onUpdate((d) => ({ ...d, photos: [...d.photos, ...added] }));
    } catch {
      toast.error("Couldn't open one of those images in this browser.");
    } finally { setBusy(false); }
  }
  return (
    <PhotoManager
      busy={busy}
      photos={draft.photos.map((p) => ({ id: p.id, url: p.previewUrl, kind: p.kind, isCover: p.id === cover }))}
      onAdd={add}
      onRemove={(id) => onUpdate((d) => ({ ...d, photos: d.photos.filter((p) => p.id !== id), coverPhotoId: d.coverPhotoId === id ? null : d.coverPhotoId }))}
      onCover={(id) => onUpdate((d) => ({ ...d, coverPhotoId: id }))}
      onKind={(id, kind) => onUpdate((d) => ({ ...d, photos: d.photos.map((p) => (p.id === id ? { ...p, kind } : p)) }))}
    />
  );
}
