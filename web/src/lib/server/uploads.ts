import "server-only";
import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { UPLOAD_DIR, type CoverKind } from "./db";

const TYPES: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };
export const PHOTO_KINDS: CoverKind[] = ["approximate-preview", "camera-jpeg", "photo"];
const MAX_BYTES = 10 * 1024 * 1024;

/** Validates and stores an uploaded image under a server-generated name. Returns the name or an error Response. */
export async function storeUpload(file: unknown, maxBytes = MAX_BYTES): Promise<string | Response> {
  if (!(file instanceof File)) return Response.json({ error: "Missing file" }, { status: 400 });
  if (!TYPES[file.type]) return Response.json({ error: "Use JPEG, PNG or WebP" }, { status: 415 });
  if (file.size > maxBytes) return Response.json({ error: `Image is larger than ${Math.round(maxBytes / 1048576)} MB` }, { status: 413 });
  const name = `${randomUUID()}.${TYPES[file.type]}`;
  fs.mkdirSync(/*turbopackIgnore: true*/ UPLOAD_DIR, { recursive: true });
  fs.writeFileSync(/*turbopackIgnore: true*/ path.join(/*turbopackIgnore: true*/ UPLOAD_DIR, name), Buffer.from(await file.arrayBuffer()));
  return name;
}

export const photoJSON = (p: { id: string; file: string; kind: string }, coverFile: string | null) =>
  ({ id: p.id, url: `/api/media/${p.file}`, kind: p.kind, isCover: p.file === coverFile });

export const galleryJSON = (g: import("./db").GalleryItem) => ({
  id: g.id, url: `/api/media/${g.file}`, title: g.title, caption: g.caption, width: g.width, height: g.height,
  recipe: g.recipe,
});
